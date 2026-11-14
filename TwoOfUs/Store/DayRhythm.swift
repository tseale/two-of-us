import Foundation

/// Today against his usual, "by this time of day", for the leading page of
/// iPhone Duo's spread between the morning and the evening.
///
/// The phone page beside it carries today's totals; this carries what the
/// totals can't say on their own — whether the day is running ahead or
/// behind, and how his rhythm compares with his week. Every comparison stops
/// the earlier days at the same clock time as now, so 2 PM is never measured
/// against a whole day. Pure and store-free (`DayRhythmTests`).
enum DayRhythm {
    struct Feed: Equatable {
        let time: Date
        let oz: Double
    }

    struct Sleep: Equatable {
        let start: Date
        let end: Date
    }

    enum Series: String {
        case today, usual
    }

    /// One point on a cumulative-ounces curve: `hour` since midnight.
    struct Point: Equatable, Identifiable {
        var id: String { "\(series.rawValue)-\(hour)" }
        let series: Series
        let hour: Double
        let oz: Double
    }

    struct Pace: Equatable {
        /// Today, from midnight to now.
        let today: [Point]
        /// His usual day, midnight to midnight — the average of the tracked
        /// prior days. Empty without history.
        let usual: [Point]
        let ozSoFar: Double
        /// What he has usually had by now; nil without history.
        let usualSoFar: Double?
        /// What a usual day adds up to; nil without history.
        let usualTotal: Double?
    }

    /// A number today, and the same number on his usual day by this time.
    struct Comparison<Value: Equatable>: Equatable {
        let today: Value?
        let usual: Value?
    }

    struct Rhythm: Equatable {
        /// Average time between bottles.
        let feedGap: Comparison<TimeInterval>
        /// Average bottle size.
        let bottle: Comparison<Double>
        /// Daytime sleep (sleeps that began after the night window ended).
        let naps: Comparison<TimeInterval>
        let napCount: Int
    }

    /// Cumulative ounces through the day, today against the average of the
    /// `priorDays` before it that have any bottle logged.
    static func pace(feeds: [Feed], dayStart: Date, now: Date, priorDays: Int = 7,
                     calendar: Calendar = .current) -> Pace {
        let nowHour = max(0, min(24, now.timeIntervalSince(dayStart) / 3600))

        let todays = feeds.filter { $0.time >= dayStart && $0.time <= now }
        var today: [Point] = []
        var hour = 0.0
        while hour < nowHour {
            today.append(Point(series: .today, hour: hour,
                               oz: cumulative(todays, from: dayStart, toHour: hour)))
            hour += 1
        }
        let ozSoFar = todays.reduce(0) { $0 + $1.oz }
        today.append(Point(series: .today, hour: nowHour, oz: ozSoFar))

        let days = trackedPriorDays(feeds: feeds, dayStart: dayStart, count: priorDays,
                                    calendar: calendar)
        guard !days.isEmpty else {
            return Pace(today: today, usual: [], ozSoFar: ozSoFar, usualSoFar: nil, usualTotal: nil)
        }
        let usual = stride(from: 0.0, through: 24, by: 1).map { h in
            Point(series: .usual, hour: h,
                  oz: days.reduce(0) { $0 + cumulative($1.feeds, from: $1.start, toHour: h) }
                      / Double(days.count))
        }
        let usualSoFar = days.reduce(0) { $0 + cumulative($1.feeds, from: $1.start, toHour: nowHour) }
            / Double(days.count)
        return Pace(today: today, usual: usual, ozSoFar: ozSoFar, usualSoFar: usualSoFar,
                    usualTotal: usual.last?.oz)
    }

    /// Bottle spacing, bottle size and daytime sleep, today against the
    /// usual by the same clock time. `dayBeginsMinute` is when the night
    /// window ends — a sleep that began after it is a nap.
    static func rhythm(feeds: [Feed], sleeps: [Sleep], dayStart: Date, now: Date,
                       dayBeginsMinute: Int, priorDays: Int = 7,
                       calendar: Calendar = .current) -> Rhythm {
        let elapsed = now.timeIntervalSince(dayStart)
        func day(_ start: Date) -> (feeds: [Feed], naps: [Sleep]) {
            let cutoff = start.addingTimeInterval(elapsed)
            let napsFrom = start.addingTimeInterval(TimeInterval(dayBeginsMinute * 60))
            let dayFeeds = feeds.filter { $0.time >= start && $0.time <= cutoff }
            let naps = sleeps.compactMap { sleep -> Sleep? in
                guard sleep.start >= napsFrom, sleep.start < cutoff else { return nil }
                return Sleep(start: sleep.start, end: min(sleep.end, cutoff))
            }
            return (dayFeeds, naps)
        }

        let today = day(dayStart)
        let priors = (1...max(priorDays, 1)).compactMap { k in
            calendar.date(byAdding: .day, value: -k, to: dayStart).map(day)
        }

        let gapToday = averageGap(today.feeds)
        let gapUsual = average(priors.compactMap { averageGap($0.feeds) })
        let bottleToday = averageOz(today.feeds)
        let bottleUsual = average(priors.compactMap { averageOz($0.feeds) })
        let napToday = today.naps.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        // Only days with any sleep logged count toward the usual naps.
        let napUsual = average(priors.filter { !$0.naps.isEmpty }.map { day in
            day.naps.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        })
        return Rhythm(feedGap: Comparison(today: gapToday, usual: gapUsual),
                      bottle: Comparison(today: bottleToday, usual: bottleUsual),
                      naps: Comparison(today: today.naps.isEmpty ? nil : napToday, usual: napUsual),
                      napCount: today.naps.count)
    }

    // MARK: Helpers

    private static func cumulative(_ feeds: [Feed], from start: Date, toHour hour: Double) -> Double {
        let cutoff = start.addingTimeInterval(hour * 3600)
        return feeds.filter { $0.time <= cutoff }.reduce(0) { $0 + $1.oz }
    }

    private static func trackedPriorDays(feeds: [Feed], dayStart: Date, count: Int,
                                         calendar: Calendar) -> [(start: Date, feeds: [Feed])] {
        guard count > 0 else { return [] }
        return (1...count).compactMap { k in
            guard let start = calendar.date(byAdding: .day, value: -k, to: dayStart),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
            let dayFeeds = feeds.filter { $0.time >= start && $0.time < end }
            return dayFeeds.isEmpty ? nil : (start, dayFeeds)
        }
    }

    private static func averageGap(_ feeds: [Feed]) -> TimeInterval? {
        let times = feeds.map(\.time).sorted()
        guard times.count >= 2, let first = times.first, let last = times.last else { return nil }
        return last.timeIntervalSince(first) / Double(times.count - 1)
    }

    private static func averageOz(_ feeds: [Feed]) -> Double? {
        guard !feeds.isEmpty else { return nil }
        return feeds.reduce(0) { $0 + $1.oz } / Double(feeds.count)
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
