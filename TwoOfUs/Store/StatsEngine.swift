import Foundation

// MARK: - Result types

/// One calendar day's rolled-up totals.
struct DaySummary: Identifiable {
    var id: Date { day }
    let day: Date              // start of day
    let feedOz: Double
    let feedCount: Int
    let sleepSeconds: TimeInterval
    let diaperCount: Int
    /// Longest single completed sleep that started this day (the "stretch").
    let longestStretch: TimeInterval
}

/// A day's worth of ribbon marks, for the History swimlane.
struct DayMarks: Identifiable {
    var id: Date { day }
    let day: Date
    let marks: [RibbonMark]
}

/// One day's diaper counts split by type, for the diaper-trend chart.
struct DiaperDay: Identifiable {
    var id: Date { day }
    let day: Date
    let wet: Int
    let dirty: Int
    let both: Int
    var total: Int { wet + dirty + both }
}

/// One cell of the feed-time heatmap: how many feeds fell in `hour` (0–23) on `day`.
/// `dayIndex` is 0 for the oldest day in the window, so the chart can lay out rows
/// by number instead of relying on categorical-axis ordering.
struct FeedHeatCell: Identifiable {
    var id: Int { dayIndex * 24 + hour }
    let day: Date
    let dayIndex: Int
    let hour: Int
    let count: Int
}

/// Lifetime running totals.
struct LifetimeTotals {
    let totalOz: Double
    let totalSleepSeconds: TimeInterval
    let diaperCount: Int
    let feedCount: Int
}

/// A single caregiver's share of night feeds.
struct CaregiverShare: Identifiable {
    var id: String { name }   // grouped by name, so unique per result set
    let name: String
    let colorHex: String
    let count: Int
}

/// Records & milestones.
struct SleepRecord {
    let duration: TimeInterval
    let date: Date
}

/// A reached milestone (first N-hour sleep, Nth bottle, …) and when it happened.
struct Milestone: Identifiable {
    var id: String { title }  // each milestone title is generated at most once
    let emoji: String
    let title: String
    let date: Date
}

/// All-time share of logged events for one caregiver.
struct CaregiverContribution: Identifiable {
    var id: String { name }   // grouped by name, so unique per result set
    let name: String
    let colorHex: String
    let count: Int
}

/// A week's worth of shareable totals + highlights, for the "Wrapped" recap card.
struct WeekRecap {
    let start: Date
    let end: Date
    let feedCount: Int
    let totalOz: Double
    let totalSleep: TimeInterval
    let diaperCount: Int
    let longestStretch: TimeInterval
    let hungriestHour: Int?
    let nightMVP: String?
    /// A milestone reached during this window, if any, for the celebratory callout.
    let milestone: Milestone?
    /// Whether anything at all was logged in the window (drives the empty case).
    var hasData: Bool { feedCount > 0 || totalSleep > 0 || diaperCount > 0 }
}

/// Today's totals alongside the trailing-average "typical" day.
struct TodayComparison {
    let feedsToday: Int
    let ozToday: Double
    let ozAvg: Double
    let sleepToday: TimeInterval
    let sleepAvg: TimeInterval
    let diapersToday: Int
    let diapersAvg: Double
    /// False when there aren't enough prior days to show a meaningful "vs avg".
    let hasHistory: Bool
}

// MARK: - Engine

/// Pure aggregations over live events. Views pass their `@Query` results in.
/// Sleeps passed here should already be filtered to `deletedAt == nil`.
struct StatsEngine {
    let feeds: [FeedEvent]
    let sleeps: [SleepEvent]
    let diapers: [DiaperEvent]
    var calendar = Calendar.current
    var now = Date()

    private func startOfDay(_ date: Date) -> Date { calendar.startOfDay(for: date) }

    /// Last `days` calendar days, oldest → newest (includes today).
    private func recentDays(_ days: Int) -> [Date] {
        let today = startOfDay(now)
        return (0..<days).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
        }
    }

    // MARK: Daily summaries

    func dailySummaries(days: Int = 7) -> [DaySummary] {
        recentDays(days).map { dayStart in
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

            var oz = 0.0
            var feedCount = 0
            for feed in feeds where feed.deletedAt == nil {
                if feed.timestamp >= dayStart && feed.timestamp < dayEnd {
                    oz += feed.amountOz
                    feedCount += 1
                }
            }

            var diaperCount = 0
            for diaper in diapers where diaper.deletedAt == nil {
                if diaper.timestamp >= dayStart && diaper.timestamp < dayEnd { diaperCount += 1 }
            }

            var sleepSeconds: TimeInterval = 0
            var longest: TimeInterval = 0
            for sleep in sleeps where sleep.deletedAt == nil {
                guard let end = sleep.endedAt else { continue }
                // Overlap of [startedAt, end] with the day.
                let lo = max(sleep.startedAt, dayStart)
                let hi = min(end, dayEnd)
                if hi > lo { sleepSeconds += hi.timeIntervalSince(lo) }
                // Stretch credited to the day the sleep started.
                if sleep.startedAt >= dayStart && sleep.startedAt < dayEnd {
                    longest = max(longest, end.timeIntervalSince(sleep.startedAt))
                }
            }

            return DaySummary(
                day: dayStart, feedOz: oz, feedCount: feedCount,
                sleepSeconds: sleepSeconds, diaperCount: diaperCount,
                longestStretch: longest
            )
        }
    }

    // MARK: Swimlane

    func swimlane(days: Int = 7) -> [DayMarks] {
        recentDays(days).map { day in
            DayMarks(day: day, marks: RibbonMark.forDay(
                day, feeds: feeds, sleeps: sleeps, diapers: diapers, calendar: calendar
            ))
        }
    }

    // MARK: Diaper trend

    /// Per-day wet / dirty / both counts over the last `days` (oldest → newest).
    func diaperDays(days: Int = 7) -> [DiaperDay] {
        recentDays(days).map { dayStart in
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            var wet = 0, dirty = 0, both = 0
            for d in diapers where d.deletedAt == nil {
                guard d.timestamp >= dayStart && d.timestamp < dayEnd else { continue }
                switch d.type {
                case .wet:   wet += 1
                case .dirty: dirty += 1
                case .both:  both += 1
                }
            }
            return DiaperDay(day: dayStart, wet: wet, dirty: dirty, both: both)
        }
    }

    // MARK: Feed-time heatmap

    /// Feed counts bucketed by (day, hour-of-day) over the last `days`. Returns a
    /// full grid — every day × 24 hours, zeros included — so the chart renders a
    /// complete heatmap rather than only the cells that happen to have feeds.
    func feedHeatmap(days: Int = 7) -> [FeedHeatCell] {
        let dayStarts = recentDays(days)
        var counts: [Date: [Int]] = [:]
        for d in dayStarts { counts[d] = [Int](repeating: 0, count: 24) }
        for f in feeds where f.deletedAt == nil {
            let dayStart = startOfDay(f.timestamp)
            guard counts[dayStart] != nil else { continue }
            counts[dayStart]?[calendar.component(.hour, from: f.timestamp)] += 1
        }
        return dayStarts.enumerated().flatMap { index, day in
            (0..<24).map { hour in
                FeedHeatCell(day: day, dayIndex: index, hour: hour, count: counts[day]?[hour] ?? 0)
            }
        }
    }

    // MARK: Lifetime

    func lifetime() -> LifetimeTotals {
        var oz = 0.0
        for feed in feeds where feed.deletedAt == nil { oz += feed.amountOz }

        var sleepSeconds: TimeInterval = 0
        for sleep in sleeps where sleep.deletedAt == nil {
            if let end = sleep.endedAt { sleepSeconds += end.timeIntervalSince(sleep.startedAt) }
        }

        let feedCount = feeds.reduce(into: 0) { acc, f in if f.deletedAt == nil { acc += 1 } }
        let diaperCount = diapers.reduce(into: 0) { acc, d in if d.deletedAt == nil { acc += 1 } }

        return LifetimeTotals(
            totalOz: oz, totalSleepSeconds: sleepSeconds,
            diaperCount: diaperCount, feedCount: feedCount
        )
    }

    // MARK: Records

    /// Longest completed sleep ever.
    func longestSleep() -> SleepRecord? {
        var best: SleepRecord?
        for sleep in sleeps where sleep.deletedAt == nil {
            guard let end = sleep.endedAt else { continue }
            let dur = end.timeIntervalSince(sleep.startedAt)
            if dur > (best?.duration ?? 0) {
                best = SleepRecord(duration: dur, date: sleep.startedAt)
            }
        }
        return best
    }

    // MARK: Night-shift split

    /// Feeds in the night window (default 19:00–07:00) over the last `days`, by caregiver.
    func nightShift(days: Int = 7, nightStart: Int = 19, nightEnd: Int = 7) -> [CaregiverShare] {
        let cutoff = calendar.date(byAdding: .day, value: -days, to: now) ?? now
        var counts: [String: (color: String, count: Int)] = [:]

        for feed in feeds where feed.deletedAt == nil {
            guard feed.timestamp >= cutoff else { continue }
            let hour = calendar.component(.hour, from: feed.timestamp)
            let isNight = hour >= nightStart || hour < nightEnd
            guard isNight else { continue }
            let name = feed.loggedByName.isEmpty ? "Unknown" : feed.loggedByName
            let existing = counts[name]
            counts[name] = (existing?.color ?? feed.loggedByColorHex, (existing?.count ?? 0) + 1)
        }

        return counts
            .map { CaregiverShare(name: $0.key, colorHex: $0.value.color, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    // MARK: Hungriest hour

    /// Hour-of-day (0–23) with the most feeds over the last `days`; nil if no feeds.
    func hungriestHour(days: Int = 14) -> Int? {
        let cutoff = calendar.date(byAdding: .day, value: -days, to: now) ?? now
        var histogram = [Int](repeating: 0, count: 24)
        var any = false
        for feed in feeds where feed.deletedAt == nil {
            guard feed.timestamp >= cutoff else { continue }
            histogram[calendar.component(.hour, from: feed.timestamp)] += 1
            any = true
        }
        guard any else { return nil }
        var bestHour = 0
        for hour in 1..<24 where histogram[hour] > histogram[bestHour] { bestHour = hour }
        return bestHour
    }

    // MARK: Feed cadence ("on this day")

    /// Average gap between consecutive feeds over `[fromDaysAgo, toDaysAgo)`, in seconds.
    func averageFeedInterval(fromDaysAgo: Int, toDaysAgo: Int) -> TimeInterval? {
        let upper = calendar.date(byAdding: .day, value: -toDaysAgo, to: now) ?? now
        let lower = calendar.date(byAdding: .day, value: -fromDaysAgo, to: now) ?? now

        var times: [Date] = []
        for feed in feeds where feed.deletedAt == nil {
            if feed.timestamp >= lower && feed.timestamp < upper { times.append(feed.timestamp) }
        }
        guard times.count >= 2 else { return nil }
        times.sort()
        var total: TimeInterval = 0
        for i in 1..<times.count { total += times[i].timeIntervalSince(times[i - 1]) }
        return total / Double(times.count - 1)
    }

    // MARK: Milestones & streaks

    /// Reached milestones (first 4/5/6/8-hour sleep, 50/100/250/500th bottle,
    /// 100/250/500th diaper), newest first. All derived from existing events.
    func milestones() -> [Milestone] {
        var result: [Milestone] = []

        let completed = sleeps.filter { $0.deletedAt == nil }
            .compactMap { s -> (start: Date, dur: TimeInterval)? in
                guard let end = s.endedAt else { return nil }
                return (s.startedAt, end.timeIntervalSince(s.startedAt))
            }
            .sorted { $0.start < $1.start }
        for hours in [4, 5, 6, 8] {
            let target = TimeInterval(hours) * 3600
            if let first = completed.first(where: { $0.dur >= target }) {
                result.append(Milestone(emoji: "🌙", title: "First \(hours)-hour sleep", date: first.start))
            }
        }

        let feedTimes = feeds.filter { $0.deletedAt == nil }.map(\.timestamp).sorted()
        for n in [50, 100, 250, 500] where feedTimes.count >= n {
            result.append(Milestone(emoji: "🍼", title: "\(n)th bottle", date: feedTimes[n - 1]))
        }

        let diaperTimes = diapers.filter { $0.deletedAt == nil }.map(\.timestamp).sorted()
        for n in [100, 250, 500] where diaperTimes.count >= n {
            result.append(Milestone(emoji: "💩", title: "\(n)th diaper", date: diaperTimes[n - 1]))
        }

        return result.sorted { $0.date > $1.date }
    }

    /// The next bottle-count milestone and how many feeds remain, or nil once the
    /// biggest tracked target is passed.
    func nextMilestone() -> (title: String, remaining: Int)? {
        let feedCount = feeds.reduce(into: 0) { acc, f in if f.deletedAt == nil { acc += 1 } }
        for n in [50, 100, 250, 500, 1000] where feedCount < n {
            return ("\(n)th bottle", n - feedCount)
        }
        return nil
    }

    /// Consecutive days (ending today, or yesterday if today's still blank) with
    /// at least one logged event.
    func loggingStreak() -> Int {
        var days = Set<Date>()
        for f in feeds where f.deletedAt == nil { days.insert(startOfDay(f.timestamp)) }
        for s in sleeps where s.deletedAt == nil { days.insert(startOfDay(s.startedAt)) }
        for d in diapers where d.deletedAt == nil { days.insert(startOfDay(d.timestamp)) }
        guard !days.isEmpty else { return 0 }

        var day = startOfDay(now)
        if !days.contains(day) {
            // A not-yet-logged morning shouldn't read as a broken streak.
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day),
                  days.contains(yesterday) else { return 0 }
            day = yesterday
        }
        var streak = 0
        while days.contains(day) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }

    // MARK: Today vs typical

    func todayVsTypical(priorDays: Int = 7) -> TodayComparison {
        let summaries = dailySummaries(days: priorDays + 1)   // prior days + today
        guard let today = summaries.last else {
            return TodayComparison(feedsToday: 0, ozToday: 0, ozAvg: 0, sleepToday: 0,
                                   sleepAvg: 0, diapersToday: 0, diapersAvg: 0, hasHistory: false)
        }
        let prior = summaries.dropLast()
        // Average each metric over the prior days that actually have that metric —
        // NOT a fixed 7. For a newborn only a few days old the pre-birth (and
        // untracked) days are all zeros; dividing by 7 understated the "typical"
        // and inflated every "vs avg" delta.
        func avg(_ value: (DaySummary) -> Double) -> Double {
            let tracked = prior.filter { value($0) > 0 }
            guard !tracked.isEmpty else { return 0 }
            return tracked.reduce(0) { $0 + value($1) } / Double(tracked.count)
        }
        let hasHistory = prior.contains {
            $0.feedCount > 0 || $0.sleepSeconds > 0 || $0.diaperCount > 0
        }
        return TodayComparison(
            feedsToday: today.feedCount,
            ozToday: today.feedOz, ozAvg: avg { $0.feedOz },
            sleepToday: today.sleepSeconds, sleepAvg: avg { $0.sleepSeconds },
            diapersToday: today.diaperCount, diapersAvg: avg { Double($0.diaperCount) },
            hasHistory: hasHistory
        )
    }

    // MARK: Weekly recap ("Wrapped")

    /// Rolls up the last `days` into the shareable recap: totals, the week's
    /// longest sleep, busiest feeding hour, and the night MVP. Reuses the same
    /// aggregations the Stats/History cards do, so the numbers always agree.
    func weekRecap(days: Int = 7) -> WeekRecap {
        let summaries = dailySummaries(days: days)
        let longest = summaries.map(\.longestStretch).max() ?? 0
        let windowStart = summaries.first?.day ?? startOfDay(now)
        let windowEnd = calendar.date(byAdding: .day, value: 1,
                                      to: summaries.last?.day ?? startOfDay(now)) ?? now
        // milestones() is newest-first, so `.first` in-window is the latest one.
        let milestone = milestones().first { $0.date >= windowStart && $0.date < windowEnd }
        return WeekRecap(
            start: windowStart,
            end: summaries.last?.day ?? startOfDay(now),
            feedCount: summaries.reduce(0) { $0 + $1.feedCount },
            totalOz: summaries.reduce(0) { $0 + $1.feedOz },
            totalSleep: summaries.reduce(0) { $0 + $1.sleepSeconds },
            diaperCount: summaries.reduce(0) { $0 + $1.diaperCount },
            longestStretch: longest,
            hungriestHour: hungriestHour(days: days),
            nightMVP: nightShift(days: days).first?.name,
            milestone: milestone
        )
    }

    // MARK: Contributions (all-time, both parents)

    /// Every caregiver's all-time count of logged events, most first. Light and
    /// non-competitive — shows the shared load.
    func contributions() -> [CaregiverContribution] {
        var map: [String: (color: String, count: Int)] = [:]
        func tally(_ name: String, _ color: String) {
            let key = name.isEmpty ? "Unknown" : name
            let existing = map[key]
            map[key] = (existing?.color ?? color, (existing?.count ?? 0) + 1)
        }
        for f in feeds where f.deletedAt == nil { tally(f.loggedByName, f.loggedByColorHex) }
        for s in sleeps where s.deletedAt == nil { tally(s.loggedByName, s.loggedByColorHex) }
        for d in diapers where d.deletedAt == nil { tally(d.loggedByName, d.loggedByColorHex) }
        return map
            .map { CaregiverContribution(name: $0.key, colorHex: $0.value.color, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }
}
