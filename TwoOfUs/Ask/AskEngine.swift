import Foundation

/// Pure computation of answers to `ParsedQuery`s. Same shape as `StatsEngine`:
/// callers pass in live (deletedAt == nil untrusted — filtered here) events
/// plus an injectable clock and calendar, so every answer is reproducible in
/// tests. No SwiftData, no stores, no model calls — the numbers in every
/// sentence come from the arithmetic below and nowhere else.
struct AskEngine {
    var feeds: [FeedEvent] = []
    var sleeps: [SleepEvent] = []
    var diapers: [DiaperEvent] = []
    var notes: [NoteEvent] = []
    var babyName: String = "Baby"
    /// Family night window, minutes-of-day (SharedSettings defaults: 8pm–8am).
    var nightStartMinute: Int = 1200
    var nightEndMinute: Int = 480
    /// Predicted gap to the next feed after a given one — callers hand in
    /// `SharedSettings.feedInterval(after:)`; the default mirrors its 3h
    /// fallback for contexts with no settings row yet.
    var feedIntervalAfter: (Date) -> TimeInterval = { _ in 180 * 60 }
    /// Projected comfortable awake stretch (see `QuickLogger.sleepTarget`).
    /// nil = caller can't provide one; the next-nap answer degrades honestly.
    var sleepTarget: TimeInterval?
    var calendar = Calendar.current
    var now = Date()

    // MARK: Entry point

    func answer(_ query: ParsedQuery) -> AskAnswer {
        switch query.metric {
        case .lastFeed: return lastFeedAnswer()
        case .lastDiaper(let type): return lastDiaperAnswer(type)
        case .sleepStatus: return sleepStatusAnswer()
        case .bedtime: return bedtimeAnswer(query.period)
        case .nextFeed: return nextFeedAnswer()
        case .nextNap: return nextNapAnswer()
        case .wakeUp: return wakeUpAnswer()
        case .noteSearch(let needle): return noteAnswer(needle)
        default: return aggregateAnswer(query)
        }
    }

    // MARK: Periods → date intervals

    func interval(for period: AskPeriod) -> DateInterval {
        let dayStart = calendar.startOfDay(for: now)
        switch period {
        case .today:
            return DateInterval(start: dayStart, end: now)
        case .yesterday:
            let start = calendar.date(byAdding: .day, value: -1, to: dayStart) ?? dayStart
            return DateInterval(start: start, end: dayStart)
        case .lastNight:
            return lastNightWindow()
        case .thisWeek:
            let start = calendar.date(byAdding: .day, value: -6, to: dayStart) ?? dayStart
            return DateInterval(start: start, end: now)
        case .lastWeek:
            let end = calendar.date(byAdding: .day, value: -6, to: dayStart) ?? dayStart
            let start = calendar.date(byAdding: .day, value: -7, to: end) ?? end
            return DateInterval(start: start, end: end)
        case .allTime:
            return DateInterval(start: .distantPast, end: now)
        }
    }

    /// The most recent night window. Uses the family's configured wall-clock
    /// night (SharedSettings), not a hardcoded 19–07. During the night (3am)
    /// this is the night in progress; during the day it's the one just past.
    private func lastNightWindow() -> DateInterval {
        let dayStart = calendar.startOfDay(for: now)
        let tonightStart = dayStart.addingTimeInterval(TimeInterval(nightStartMinute * 60))
        if now >= tonightStart {
            // Already past tonight's nightStart (e.g. 11pm): "last night" is
            // the night in progress, which started this evening.
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            let end = tomorrow.addingTimeInterval(TimeInterval(nightEndMinute * 60))
            return DateInterval(start: tonightStart, end: min(end, now))
        }
        // Otherwise the night that started yesterday evening — still in
        // progress at 3am (window ends at `now`), just past at noon.
        let yesterday = calendar.date(byAdding: .day, value: -1, to: dayStart) ?? dayStart
        let start = yesterday.addingTimeInterval(TimeInterval(nightStartMinute * 60))
        let end = dayStart.addingTimeInterval(TimeInterval(nightEndMinute * 60))
        return DateInterval(start: start, end: min(max(end, start), now))
    }

    private func periodLabel(_ period: AskPeriod) -> String {
        switch period {
        case .today: return "today"
        case .yesterday: return "yesterday"
        case .lastNight: return "last night"
        case .thisWeek: return "this week"
        case .lastWeek: return "last week"
        case .allTime: return "so far"
        }
    }

    // MARK: Live-event filters

    private var liveFeeds: [FeedEvent] { feeds.filter { $0.deletedAt == nil } }
    private var liveSleeps: [SleepEvent] { sleeps.filter { $0.deletedAt == nil } }
    private var liveDiapers: [DiaperEvent] { diapers.filter { $0.deletedAt == nil } }
    private var liveNotes: [NoteEvent] { notes.filter { $0.deletedAt == nil } }

    private func feeds(in window: DateInterval) -> [FeedEvent] {
        liveFeeds.filter { $0.timestamp >= window.start && $0.timestamp < window.end }
    }

    private func diapers(in window: DateInterval, type: DiaperType?) -> [DiaperEvent] {
        liveDiapers.filter {
            $0.timestamp >= window.start && $0.timestamp < window.end
                && (type == nil || $0.type == type)
        }
    }

    /// Sleep seconds overlapping the window; running sleeps count up to `now`.
    private func sleepSeconds(in window: DateInterval) -> TimeInterval {
        var total: TimeInterval = 0
        for s in liveSleeps {
            let end = s.endedAt ?? now
            let lo = max(s.startedAt, window.start)
            let hi = min(end, window.end)
            if hi > lo { total += hi.timeIntervalSince(lo) }
        }
        return total
    }

    /// Completed sleep sessions that overlap the window, ordered by start.
    private func sessions(overlapping window: DateInterval) -> [SleepEvent] {
        liveSleeps
            .filter { ($0.endedAt ?? now) > window.start && $0.startedAt < window.end }
            .sorted { $0.startedAt < $1.startedAt }
    }

    // MARK: Lookups

    private func lastFeedAnswer() -> AskAnswer {
        guard let feed = liveFeeds.max(by: { $0.timestamp < $1.timestamp }) else {
            return AskAnswer("No feeds logged for \(babyName) yet.")
        }
        let oz = OzFormat.string(feed.amountOz)
        let ago = TimeFormatting.since(feed.timestamp, now: now)
        var facts: [AskAnswer.Fact] = [
            .init(label: "Amount", value: "\(oz) oz"),
            .init(label: "Time", value: TimeFormatting.clock(feed.timestamp)),
        ]
        var by = ""
        if !feed.loggedByName.isEmpty {
            by = ", logged by \(feed.loggedByName)"
            facts.append(.init(label: "Logged by", value: feed.loggedByName))
        }
        return AskAnswer(
            "\(babyName) last ate \(oz) oz \(ago) ago, at \(TimeFormatting.clock(feed.timestamp))\(by).",
            facts: facts
        )
    }

    private func lastDiaperAnswer(_ type: DiaperType?) -> AskAnswer {
        let candidates = liveDiapers.filter { type == nil || $0.type == type }
        guard let diaper = candidates.max(by: { $0.timestamp < $1.timestamp }) else {
            let what = type.map { "\($0.label.lowercased()) diapers" } ?? "diapers"
            return AskAnswer("No \(what) logged for \(babyName) yet.")
        }
        let ago = TimeFormatting.since(diaper.timestamp, now: now)
        return AskAnswer(
            "\(babyName)'s last \(type == nil ? "" : "\(diaper.type.label.lowercased()) ")diaper was \(ago) ago, at \(TimeFormatting.clock(diaper.timestamp)).",
            facts: [
                .init(label: "Type", value: diaper.type.label),
                .init(label: "Time", value: TimeFormatting.clock(diaper.timestamp)),
            ]
        )
    }

    private func sleepStatusAnswer() -> AskAnswer {
        if let active = liveSleeps.first(where: { $0.endedAt == nil }) {
            let dur = TimeFormatting.duration(from: active.startedAt, to: now)
            return AskAnswer(
                "\(babyName) has been asleep for \(dur), since \(TimeFormatting.clock(active.startedAt)).",
                facts: [.init(label: "Asleep since", value: TimeFormatting.clock(active.startedAt))]
            )
        }
        let ended = liveSleeps.compactMap { s in s.endedAt.map { (s, $0) } }
            .max { $0.1 < $1.1 }
        guard let (last, end) = ended else {
            return AskAnswer("\(babyName) is awake — no sleeps logged yet.")
        }
        let dur = TimeFormatting.duration(from: last.startedAt, to: end)
        return AskAnswer(
            "\(babyName) is awake. The last sleep ended \(TimeFormatting.since(end, now: now)) ago and lasted \(dur).",
            facts: [
                .init(label: "Woke", value: TimeFormatting.clock(end)),
                .init(label: "Duration", value: dur),
            ]
        )
    }

    private func bedtimeAnswer(_ period: AskPeriod) -> AskAnswer {
        // "Went down for the night" = the first sleep that STARTS inside the
        // night window (not a nap that ran into it).
        let window = interval(for: period == .lastNight ? .lastNight : period)
        guard let first = liveSleeps
            .filter({ $0.startedAt >= window.start && $0.startedAt < window.end })
            .min(by: { $0.startedAt < $1.startedAt }) else {
            return AskAnswer("I don't see a sleep starting \(periodLabel(period)) for \(babyName).")
        }
        var facts: [AskAnswer.Fact] = [
            .init(label: "Down at", value: TimeFormatting.clock(first.startedAt))
        ]
        var tail = "."
        if let end = first.endedAt {
            let dur = TimeFormatting.duration(from: first.startedAt, to: end)
            tail = " and slept \(dur) before the first wake."
            facts.append(.init(label: "First stretch", value: dur))
        }
        return AskAnswer(
            "\(babyName) went down at \(TimeFormatting.clock(first.startedAt)) \(periodLabel(period))\(tail)",
            facts: facts
        )
    }

    // MARK: Aggregates

    private func aggregateAnswer(_ query: ParsedQuery) -> AskAnswer {
        let window = interval(for: query.period)
        let label = periodLabel(query.period)
        var answer = aggregate(query.metric, in: window, label: label)
        if let baseline = query.compareTo {
            let baseWindow = interval(for: baseline)
            if let comparison = comparisonSentence(
                query.metric, window: window, baseWindow: baseWindow,
                label: label, baseLabel: periodLabel(baseline)
            ) {
                answer.sentence += " " + comparison.sentence
                answer.facts += comparison.facts
            }
        }
        return answer
    }

    private func aggregate(_ metric: AskMetric, in window: DateInterval, label: String) -> AskAnswer {
        switch metric {
        case .totalSleep:
            let secs = sleepSeconds(in: window)
            guard secs > 0 else { return AskAnswer("No sleep logged \(label) for \(babyName).") }
            let dur = TimeFormatting.duration(minutes: Int(secs / 60))
            return AskAnswer("\(babyName) slept \(dur) \(label).",
                             facts: [.init(label: "Sleep", value: dur)])

        case .nightWakes:
            let sessions = sessions(overlapping: window)
            // Wakes = times he was up BETWEEN sleeps inside the window: one
            // per completed session that another session follows.
            let wakes = max(0, sessions.count - 1)
            let sleepDur = TimeFormatting.duration(minutes: Int(sleepSeconds(in: window) / 60))
            if sessions.isEmpty {
                return AskAnswer("No sleep logged \(label) for \(babyName).")
            }
            return AskAnswer(
                "\(babyName) woke \(wakes == 0 ? "zero times" : Plural.count(wakes, "time")) \(label), sleeping \(sleepDur) in total.",
                facts: [
                    .init(label: "Wakes", value: "\(wakes)"),
                    .init(label: "Sleep", value: sleepDur),
                ]
            )

        case .feedOz:
            let fs = feeds(in: window)
            guard !fs.isEmpty else { return AskAnswer("No feeds logged \(label) for \(babyName).") }
            let oz = fs.reduce(0) { $0 + $1.amountOz }
            return AskAnswer(
                "\(babyName) had \(OzFormat.string(oz)) oz across \(Plural.count(fs.count, "feed")) \(label).",
                facts: [
                    .init(label: "Total", value: "\(OzFormat.string(oz)) oz"),
                    .init(label: "Feeds", value: "\(fs.count)"),
                ]
            )

        case .feedCount:
            let fs = feeds(in: window)
            let oz = fs.reduce(0) { $0 + $1.amountOz }
            return AskAnswer(
                fs.isEmpty
                    ? "No feeds logged \(label) for \(babyName)."
                    : "\(babyName) had \(Plural.count(fs.count, "feed")) \(label), totaling \(OzFormat.string(oz)) oz.",
                facts: fs.isEmpty ? [] : [
                    .init(label: "Feeds", value: "\(fs.count)"),
                    .init(label: "Total", value: "\(OzFormat.string(oz)) oz"),
                ]
            )

        case .diaperCount(let type):
            let ds = diapers(in: window, type: type)
            let what = type.map { "\($0.label.lowercased()) \(Plural.unit(ds.count, "diaper"))" }
                ?? Plural.unit(ds.count, "diaper")
            if ds.isEmpty {
                let none = type.map { "no \($0.label.lowercased()) diapers" } ?? "no diapers"
                return AskAnswer("\(babyName) has had \(none) \(label).")
            }
            return AskAnswer("\(babyName) had \(ds.count) \(what) \(label).",
                             facts: [.init(label: "Diapers", value: "\(ds.count)")])

        case .averageBottle:
            let fs = feeds(in: window)
            guard !fs.isEmpty else { return AskAnswer("No feeds logged \(label) for \(babyName).") }
            let avg = fs.reduce(0) { $0 + $1.amountOz } / Double(fs.count)
            return AskAnswer(
                "\(babyName)'s bottles have averaged \(OzFormat.string(avg)) oz \(label), over \(Plural.count(fs.count, "feed")).",
                facts: [.init(label: "Average", value: "\(OzFormat.string(avg)) oz")]
            )

        case .averageFeedInterval:
            let times = feeds(in: window).map(\.timestamp).sorted()
            guard times.count >= 2 else {
                return AskAnswer("Not enough feeds \(label) to measure \(babyName)'s feeding rhythm.")
            }
            var total: TimeInterval = 0
            for i in 1..<times.count { total += times[i].timeIntervalSince(times[i - 1]) }
            let avg = total / Double(times.count - 1)
            let dur = TimeFormatting.duration(minutes: Int(avg / 60))
            return AskAnswer("\(babyName) has been eating about every \(dur) \(label).",
                             facts: [.init(label: "Interval", value: dur)])

        case .longestStretch:
            let completed = liveSleeps.compactMap { s -> (SleepEvent, TimeInterval)? in
                guard let end = s.endedAt,
                      s.startedAt >= window.start, s.startedAt < window.end else { return nil }
                return (s, end.timeIntervalSince(s.startedAt))
            }
            guard let best = completed.max(by: { $0.1 < $1.1 }) else {
                return AskAnswer("No completed sleeps \(label) for \(babyName).")
            }
            let dur = TimeFormatting.duration(minutes: Int(best.1 / 60))
            let day = best.0.startedAt.formatted(date: .abbreviated, time: .omitted)
            return AskAnswer(
                "\(babyName)'s longest stretch \(label) is \(dur), on \(day).",
                facts: [
                    .init(label: "Longest", value: dur),
                    .init(label: "When", value: day),
                ]
            )

        default:
            return AskAnswer("I can't compute that one yet.")
        }
    }

    /// Second sentence for comparisons: same metric over the baseline window,
    /// with a plain-language delta. Returns nil when either side has no data
    /// (a percentage against zero is noise, not an answer).
    private func comparisonSentence(
        _ metric: AskMetric, window: DateInterval, baseWindow: DateInterval,
        label: String, baseLabel: String
    ) -> AskAnswer? {
        func value(_ w: DateInterval) -> Double? {
            switch metric {
            case .totalSleep:
                let s = sleepSeconds(in: w); return s > 0 ? s : nil
            case .feedOz:
                let fs = feeds(in: w); return fs.isEmpty ? nil : fs.reduce(0) { $0 + $1.amountOz }
            case .feedCount:
                let c = feeds(in: w).count; return c > 0 ? Double(c) : nil
            case .diaperCount(let t):
                let c = diapers(in: w, type: t).count; return c > 0 ? Double(c) : nil
            case .averageBottle:
                let fs = feeds(in: w)
                return fs.isEmpty ? nil : fs.reduce(0) { $0 + $1.amountOz } / Double(fs.count)
            case .nightWakes:
                let s = sessions(overlapping: w)
                return s.isEmpty ? nil : Double(max(0, s.count - 1))
            default:
                return nil
            }
        }
        guard let current = value(window), let base = value(baseWindow), base > 0 else { return nil }
        let ratio = current / base
        let pct = Int((abs(ratio - 1) * 100).rounded())
        let direction: String
        if pct < 5 { direction = "about the same as" }
        else if ratio > 1 { direction = "\(pct)% more than" }
        else { direction = "\(pct)% less than" }
        return AskAnswer("That's \(direction) \(baseLabel).",
                         facts: [.init(label: "Vs \(baseLabel)", value: direction)])
    }

    // MARK: Predictions

    private func nextFeedAnswer() -> AskAnswer {
        guard let last = liveFeeds.max(by: { $0.timestamp < $1.timestamp }) else {
            return AskAnswer("No feeds logged yet, so there's nothing to predict from.")
        }
        let due = last.timestamp.addingTimeInterval(feedIntervalAfter(last.timestamp))
        if due <= now {
            return AskAnswer(
                "\(babyName)'s next feed is due now — the last one was \(TimeFormatting.since(last.timestamp, now: now)) ago.",
                facts: [.init(label: "Last feed", value: TimeFormatting.clock(last.timestamp))]
            )
        }
        let inWords = TimeFormatting.duration(from: now, to: due)
        return AskAnswer(
            "\(babyName)'s next feed is expected around \(TimeFormatting.clock(due)) — about \(inWords) from now.",
            facts: [
                .init(label: "Expected", value: TimeFormatting.clock(due)),
                .init(label: "Last feed", value: TimeFormatting.clock(last.timestamp)),
            ]
        )
    }

    private func nextNapAnswer() -> AskAnswer {
        if liveSleeps.contains(where: { $0.endedAt == nil }) {
            return AskAnswer("\(babyName) is asleep right now.")
        }
        guard let target = sleepTarget,
              let lastEnd = liveSleeps.compactMap(\.endedAt).max() else {
            return AskAnswer("I need at least one completed sleep to project the next nap.")
        }
        let due = lastEnd.addingTimeInterval(target)
        if due <= now {
            return AskAnswer(
                "\(babyName)'s next nap is due about now — he's been up \(TimeFormatting.since(lastEnd, now: now)).",
                facts: [.init(label: "Awake since", value: TimeFormatting.clock(lastEnd))]
            )
        }
        return AskAnswer(
            "\(babyName)'s next nap is projected around \(TimeFormatting.clock(due)).",
            facts: [.init(label: "Projected", value: TimeFormatting.clock(due))]
        )
    }

    /// "When will he wake up?" — honest heuristic, not a promise: the median
    /// completed-sleep duration from the trailing week, applied to the
    /// running sleep. (The full prediction stack can replace this later.)
    private func wakeUpAnswer() -> AskAnswer {
        guard let active = liveSleeps.first(where: { $0.endedAt == nil }) else {
            return AskAnswer("\(babyName) is already awake.")
        }
        let weekAgo = now.addingTimeInterval(-7 * 24 * 3600)
        let durations = liveSleeps.compactMap { s -> TimeInterval? in
            guard let end = s.endedAt, s.startedAt >= weekAgo else { return nil }
            return end.timeIntervalSince(s.startedAt)
        }.sorted()
        let soFar = TimeFormatting.duration(from: active.startedAt, to: now)
        guard !durations.isEmpty else {
            return AskAnswer("\(babyName) has been asleep \(soFar); not enough history yet to guess the wake-up.")
        }
        let median = durations[durations.count / 2]
        let projected = active.startedAt.addingTimeInterval(median)
        if projected <= now {
            return AskAnswer(
                "\(babyName) has been asleep \(soFar) — already past his recent typical stretch, so it could be any time.",
                facts: [.init(label: "Asleep since", value: TimeFormatting.clock(active.startedAt))]
            )
        }
        return AskAnswer(
            "\(babyName) has been asleep \(soFar). Going by his recent sleeps, he'll likely wake around \(TimeFormatting.clock(projected)).",
            facts: [
                .init(label: "Asleep since", value: TimeFormatting.clock(active.startedAt)),
                .init(label: "Typical stretch", value: TimeFormatting.duration(minutes: Int(median / 60))),
            ]
        )
    }

    // MARK: Notes

    private func noteAnswer(_ needle: String) -> AskAnswer {
        let words = needle.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return AskAnswer("I didn't catch what to look for in the notes.") }
        // Best match = the live note containing the most needle words
        // (ties → earliest, since "when did we start X" wants the first time).
        let scored = liveNotes.compactMap { note -> (NoteEvent, Int)? in
            let text = note.text.lowercased()
            let hits = words.filter { text.contains($0) }.count
            return hits > 0 ? (note, hits) : nil
        }
        guard let best = scored.max(by: { a, b in
            a.1 != b.1 ? a.1 < b.1 : a.0.timestamp > b.0.timestamp
        }) else {
            return AskAnswer("No notes mention \(needle).")
        }
        let when = best.0.timestamp.formatted(date: .abbreviated, time: .shortened)
        return AskAnswer(
            "From your notes on \(when): \(best.0.text)",
            facts: [.init(label: "Noted", value: when)]
        )
    }
}
