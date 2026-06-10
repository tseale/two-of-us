import Foundation

// MARK: - Result types

/// One calendar day's rolled-up totals.
struct DaySummary: Identifiable {
    let id = UUID()
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
    let id = UUID()
    let day: Date
    let marks: [RibbonMark]
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
    let id = UUID()
    let name: String
    let colorHex: String
    let count: Int
}

/// Records & milestones.
struct SleepRecord {
    let duration: TimeInterval
    let date: Date
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
}
