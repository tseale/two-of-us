import Foundation

/// How a night went, for the leading page of iPhone Duo's spread: "Last
/// night" in the morning and "Tonight so far" while the window is open.
///
/// The phone page beside it already says what happened last and what comes
/// next; this is the part nobody can see from there — the night as a whole,
/// how it compares with his week, and who was up with him. Pure and
/// store-free: plain values in, plain values out (`NightReportTests`).
enum NightReport {
    struct Sleep: Equatable {
        let start: Date
        /// Nil while he is still asleep.
        let end: Date?
    }

    struct Feed: Equatable {
        let time: Date
        let oz: Double
        let loggedByID: UUID
    }

    struct Diaper: Equatable {
        let time: Date
        let loggedByID: UUID
    }

    /// One parent's part of the night.
    struct Share: Equatable {
        var feeds = 0
        var oz: Double = 0
        var diapers = 0
        var total: Int { feeds + diapers }
    }

    struct Summary: Equatable {
        /// The night, clipped to `now` while it is still going.
        let window: DateInterval
        /// The whole night window (unclipped) — what a chart scales to.
        let night: DateInterval
        /// Total time asleep inside the window.
        let asleep: TimeInterval
        /// The longest unbroken sleep that touched the window, counted in
        /// full (a sleep that began at 7:40 PM still counts from 7:40).
        let longestStretch: TimeInterval
        /// Times he woke and went back down (gaps of `minimumWake` or more
        /// between two sleeps). Waking for the day is not one.
        let wakeUps: Int
        let feeds: Int
        let oz: Double
        let diapers: Int
        let shares: [UUID: Share]
        /// The night's sleeps clipped to the window, merged, in order.
        let segments: [DateInterval]
        let feedTimes: [Date]

        var isComplete: Bool { window.end >= night.end }
        var hasData: Bool { asleep > 0 || feeds > 0 || diapers > 0 }
    }

    /// A gap shorter than this between two sleeps is a resettle, not a
    /// wake-up (a SNOO soothe, a dream feed he slept through).
    static let minimumWake: TimeInterval = 5 * 60

    /// The night window that contains `now`, or else the most recent one
    /// that has started — at 9 AM, last night; at 2 AM, tonight.
    static func night(containing now: Date, startMinute: Int, endMinute: Int,
                      calendar: Calendar = .current) -> DateInterval {
        let length = ((endMinute - startMinute) % 1440 + 1440) % 1440
        let minutes = length == 0 ? 1440 : length
        var start = calendar.date(bySettingHour: (startMinute / 60) % 24, minute: startMinute % 60,
                                  second: 0, of: now) ?? now
        if start > now {
            start = calendar.date(byAdding: .day, value: -1, to: start) ?? start
        }
        let end = calendar.date(byAdding: .minute, value: minutes, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    /// The `count` nights before `night`, newest first — each with the
    /// moment that matches `now`, so a night still going is compared with
    /// the same stretch of the nights before it, never with their whole.
    static func priorNights(before night: DateInterval, now: Date, count: Int,
                            calendar: Calendar = .current) -> [(night: DateInterval, now: Date)] {
        guard count > 0 else { return [] }
        return (1...count).compactMap { k in
            guard let start = calendar.date(byAdding: .day, value: -k, to: night.start),
                  let end = calendar.date(byAdding: .day, value: -k, to: night.end),
                  let then = calendar.date(byAdding: .day, value: -k, to: now),
                  end > start
            else { return nil }
            return (DateInterval(start: start, end: end), then)
        }
    }

    static func summarize(night: DateInterval, now: Date,
                          sleeps: [Sleep], feeds: [Feed], diapers: [Diaper]) -> Summary {
        let end = min(night.end, max(now, night.start))
        let window = DateInterval(start: night.start, end: end)

        // Every sleep that touched the window, whole and clipped.
        var whole: [DateInterval] = []
        var clipped: [DateInterval] = []
        for sleep in sleeps {
            let sleepEnd = min(sleep.end ?? now, now)
            guard sleepEnd > sleep.start, sleepEnd > window.start, sleep.start < window.end
            else { continue }
            whole.append(DateInterval(start: sleep.start, end: sleepEnd))
            let lo = max(sleep.start, window.start)
            let hi = min(sleepEnd, window.end)
            if hi > lo { clipped.append(DateInterval(start: lo, end: hi)) }
        }

        let segments = merge(clipped, tolerance: 0)
        let asleep = segments.reduce(0) { $0 + $1.duration }
        // Stretches: a resettle shorter than `minimumWake` doesn't break one.
        let stretches = merge(whole, tolerance: minimumWake)
        let longest = stretches.map(\.duration).max() ?? 0

        var shares: [UUID: Share] = [:]
        var feedCount = 0
        var oz = 0.0
        var feedTimes: [Date] = []
        for feed in feeds where window.start <= feed.time && feed.time < window.end {
            feedCount += 1
            oz += feed.oz
            feedTimes.append(feed.time)
            shares[feed.loggedByID, default: Share()].feeds += 1
            shares[feed.loggedByID, default: Share()].oz += feed.oz
        }
        var diaperCount = 0
        for diaper in diapers where window.start <= diaper.time && diaper.time < window.end {
            diaperCount += 1
            shares[diaper.loggedByID, default: Share()].diapers += 1
        }

        return Summary(window: window, night: night, asleep: asleep, longestStretch: longest,
                       wakeUps: max(stretches.count - 1, 0),
                       feeds: feedCount, oz: oz, diapers: diaperCount, shares: shares,
                       segments: segments, feedTimes: feedTimes.sorted())
    }

    /// The usual time asleep across `nights`, over the nights that have any
    /// sleep logged (an untracked night is missing data, not a sleepless one).
    static func usualAsleep(_ nights: [Summary]) -> TimeInterval? {
        let tracked = nights.filter { $0.asleep > 0 }
        guard !tracked.isEmpty else { return nil }
        return tracked.reduce(0) { $0 + $1.asleep } / Double(tracked.count)
    }

    /// Overlapping (or nearly touching, within `tolerance`) intervals joined,
    /// in time order.
    static func merge(_ intervals: [DateInterval], tolerance: TimeInterval) -> [DateInterval] {
        var merged: [DateInterval] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, interval.start.timeIntervalSince(last.end) < tolerance
                || interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start,
                                                        end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        return merged
    }
}
