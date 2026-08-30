import Foundation

/// Deterministic natural-language → `ParsedQuery` parser: lowercased keyword
/// matching, no ML. This is the front door for every question — it answers
/// the common shapes instantly, on any device, with no Apple Intelligence
/// requirement, and it's fully unit-testable in CI (where Foundation Models
/// doesn't exist). Only questions this can't shape fall through to the
/// on-device model.
enum QueryParser {

    /// Returns nil when the question doesn't match any known shape — the
    /// caller then tries the Foundation Models fallback (or, without it,
    /// a notes search / "here's what I can answer" reply).
    static func parse(_ question: String) -> ParsedQuery? {
        let q = normalize(question)
        guard !q.isEmpty else { return nil }

        let period = detectPeriod(q)
        let compare = detectComparison(q)

        guard let metric = detectMetric(q) else { return nil }

        // Each metric has a sensible default window when none was spoken.
        let resolved = period ?? defaultPeriod(for: metric, comparing: compare != nil)
        return ParsedQuery(
            metric: metric,
            period: resolved,
            compareTo: metric.isAggregate ? compare : nil
        )
    }

    // MARK: Normalization

    private static func normalize(_ s: String) -> String {
        let lowered = s.lowercased()
        let stripped = lowered.unicodeScalars.map { scalar -> Character in
            CharacterSet.punctuationCharacters.contains(scalar) ? " " : Character(scalar)
        }
        return String(stripped).replacingOccurrences(
            of: " +", with: " ", options: .regularExpression
        ).trimmingCharacters(in: .whitespaces)
    }

    private static func contains(_ q: String, _ phrases: [String]) -> Bool {
        phrases.contains { q.contains($0) }
    }

    // MARK: Period

    private static func detectPeriod(_ q: String) -> AskPeriod? {
        if contains(q, ["last night", "overnight", "tonight"]) { return .lastNight }
        if q.contains("yesterday") { return .yesterday }
        if q.contains("this week") { return .thisWeek }
        if q.contains("last week") { return .lastWeek }
        if contains(q, ["ever", "all time", "of all time", "so far", "total overall"]) { return .allTime }
        if q.contains("today") { return .today }
        return nil
    }

    /// "…than last week", "…vs yesterday", "…compared to usual".
    private static func detectComparison(_ q: String) -> AskPeriod? {
        guard let range = q.range(of: " than ") ?? q.range(of: " vs ")
            ?? q.range(of: " versus ") ?? q.range(of: "compared to ")
            ?? q.range(of: "compared with ") else {
            // "more than usual" won't hit above (no trailing clause), so
            // check the usual-suspects directly.
            if contains(q, ["than usual", "than normal", "than average", "than typical"]) {
                return .lastWeek
            }
            return nil
        }
        let tail = String(q[range.upperBound...])
        if contains(tail, ["usual", "normal", "average", "typical"]) { return .lastWeek }
        return detectPeriod(tail) ?? .lastWeek
    }

    private static func defaultPeriod(for metric: AskMetric, comparing: Bool) -> AskPeriod {
        switch metric {
        case .totalSleep, .nightWakes:
            // "how much did he sleep?" with no window usually means the
            // night just past; comparisons default to the week.
            return comparing ? .thisWeek : .lastNight
        case .feedOz, .feedCount, .diaperCount:
            return comparing ? .thisWeek : .today
        case .averageBottle, .averageFeedInterval:
            return .thisWeek
        case .longestStretch:
            return .allTime
        case .bedtime:
            return .lastNight
        default:
            return .today
        }
    }

    // MARK: Metric

    private static func detectMetric(_ q: String) -> AskMetric? {
        let asksSleep = contains(q, ["sleep", "slept", "asleep", "nap", "woke", "wake", "went down", "go down", "bed"])
        let asksFeed = contains(q, ["feed", "fed", "eat", "ate", "eating", "bottle", "ounce", " oz", "drink", "drank", "hungry"])
        let asksDiaper = contains(q, ["diaper", "poop", "pee", "wet", "dirty", "change", "changed"])

        // Predictions first — "when will/when's his next…" reads differently
        // from history questions that share the same nouns.
        let predictive = contains(q, ["when will", "when s the next", "when is the next", "next feed", "next bottle", "next nap", "how long until", "how much longer", "when s his next", "when is his next"])
        if predictive {
            if contains(q, ["wake", "woke", "get up", "be up"]) { return .wakeUp }
            if asksFeed || q.contains("hungry") { return .nextFeed }
            if asksSleep { return .nextNap }
        }

        // Bedtime ("what time did he go to sleep last night?") before generic
        // sleep — the phrasing overlaps.
        if asksSleep && contains(q, ["go to sleep", "went to sleep", "go down", "went down", "fall asleep", "fell asleep", "bedtime", "to bed", "down for the night"]) {
            return .bedtime
        }

        // Wakes during the night.
        if contains(q, ["wake up", "woke up", "wake ups", "wakeups", "wakings", "times did he wake", "times he woke", "night wakes", "how many wakes"]) {
            return .nightWakes
        }

        // Comparatives ("is he sleeping MORE…?") — before the current-state
        // rule, or "is he sleeping more this week" would read as a status
        // check on the word "is he".
        if contains(q, [" more ", " less ", " fewer ", "more than", "less than"]) {
            if asksSleep { return .totalSleep }
            if asksFeed { return .feedOz }
            if asksDiaper { return .diaperCount(diaperType(q)) }
        }

        // Records.
        if contains(q, ["longest", "biggest stretch", "best stretch", "record"]) && asksSleep {
            return .longestStretch
        }

        // Averages.
        if contains(q, ["average", "typical", "usually", "normally", "on average", "avg"]) {
            if asksFeed && contains(q, ["often", "interval", "between", "gap", "apart", "how frequently"]) {
                return .averageFeedInterval
            }
            if asksFeed { return .averageBottle }
            if asksSleep { return .totalSleep }   // "how much does he typically sleep" → compare window handles "typical"
        }
        if asksFeed && contains(q, ["how often", "interval", "between feeds", "far apart"]) {
            return .averageFeedInterval
        }

        // Current state — before the how-much/how-long aggregates so "how
        // long HAS he been sleeping" reads as status, not a total.
        if asksSleep && contains(q, ["is he ", "is she ", "still", "right now", "currently", "how long has"]) {
            return .sleepStatus
        }

        // "how much / how many / how long" aggregates.
        let asksAmount = contains(q, ["how much", "how many", "how long", "total", "count"])
        if asksAmount {
            if asksSleep { return .totalSleep }
            if asksFeed {
                return contains(q, ["time", "many feeds", "many bottles", "many times"]) ? .feedCount : .feedOz
            }
            if asksDiaper { return .diaperCount(diaperType(q)) }
        }

        // "did he poop today?" — a yes/no phrasing of the same count.
        if asksDiaper && contains(q, ["did he", "did she", "has he", "has she", "any "]) {
            return .diaperCount(diaperType(q))
        }

        // Last-event lookups.
        let asksLast = contains(q, ["last", "latest", "most recent", "when did", "when was", "what time"])
        if asksLast {
            if asksFeed { return .lastFeed }
            if asksDiaper { return .lastDiaper(diaperType(q)) }
            if asksSleep { return .sleepStatus }
        }

        // Notes recall: "when did we start …", or any question mentioning a
        // note-ish verb — fall through with the content words as the search.
        if contains(q, ["when did we", "when did you", "note", "notes", "what did the"]) {
            let needle = noteNeedle(q)
            if !needle.isEmpty { return .noteSearch(needle) }
        }

        return nil
    }

    private static func diaperType(_ q: String) -> DiaperType? {
        let dirty = contains(q, ["dirty", "poop", "poo "]) || q.hasSuffix("poo")
        let wet = contains(q, ["wet", "pee"])
        if dirty && wet { return .both }
        if dirty { return .dirty }
        if wet { return .wet }
        return nil
    }

    /// Content words for a notes search: everything left after stripping
    /// question scaffolding ("when did we start …" → "vitamin d drops").
    private static func noteNeedle(_ q: String) -> String {
        let stopWords: Set<String> = [
            "when", "did", "we", "you", "the", "a", "an", "he", "she", "his", "her",
            "start", "started", "stop", "stopped", "first", "last", "what", "time",
            "was", "were", "is", "are", "do", "does", "in", "on", "at", "to", "of",
            "say", "said", "about", "note", "notes", "get", "give", "gave", "him",
            "how", "why", "with", "and", "today", "yesterday", "week", "night",
        ]
        return q.split(separator: " ")
            .map(String.init)
            .filter { !stopWords.contains($0) }
            .joined(separator: " ")
    }
}
