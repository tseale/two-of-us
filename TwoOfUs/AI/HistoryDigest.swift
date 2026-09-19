import Foundation

/// The raw-history digest behind the weekly patterns card
/// (`BabyIntelligence.weeklyPatterns`).
///
/// `StatsView.buildDigest` hands the on-device model seven daily totals —
/// all its 8K context can comfortably take. This one spells out every event
/// of the trailing two weeks, day by day, with times, ounces, sleep spans, and
/// diaper types, because the point of the Private Cloud Compute model's 32K
/// context is that it can read actual patterns (evening cluster feeds, a night
/// stretch lengthening week over week) instead of totals. Pure and
/// store-free so it unit-tests without a model or a device.
enum HistoryDigest {
    struct Feed { let at: Date; let oz: Double }
    struct Sleep { let start: Date; let end: Date? }
    struct Diaper { let at: Date; let type: DiaperType }

    /// This week and the one before it.
    static let days = 14
    /// Fewer distinct days with anything logged than this and there is no
    /// week-over-week story to tell — the caller shows nothing.
    static let minimumDaysWithData = 7

    static func render(babyName: String, dateOfBirth: Date,
                       feeds: [Feed], sleeps: [Sleep], diapers: [Diaper],
                       now: Date = .now, calendar: Calendar = .current) -> String? {
        let today = calendar.startOfDay(for: now)
        let dayStarts = (0..<days).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
        }

        var dayBlocks: [String] = []
        var daysWithData = 0
        for dayStart in dayStarts {
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { continue }
            let inDay: (Date) -> Bool = { $0 >= dayStart && $0 < dayEnd }

            let dayFeeds = feeds.filter { inDay($0.at) }.sorted { $0.at < $1.at }
            let daySleeps = sleeps.filter { inDay($0.start) }.sorted { $0.start < $1.start }
            let dayDiapers = diapers.filter { inDay($0.at) }.sorted { $0.at < $1.at }
            guard !dayFeeds.isEmpty || !daySleeps.isEmpty || !dayDiapers.isEmpty else { continue }
            daysWithData += 1

            let age = calendar.dateComponents([.day], from: calendar.startOfDay(for: dateOfBirth), to: dayStart).day ?? 0
            var lines = ["\(Self.dayLabel(dayStart)) (day \(age)):"]

            if dayFeeds.isEmpty {
                lines.append("  feeds: none logged")
            } else {
                let list = dayFeeds.map { "\(TimeFormatting.clock($0.at)) \(OzFormat.string($0.oz))oz" }
                let total = dayFeeds.reduce(0) { $0 + $1.oz }
                lines.append("  feeds (\(dayFeeds.count), \(OzFormat.string(total))oz): " + list.joined(separator: ", "))
            }

            if daySleeps.isEmpty {
                lines.append("  sleeps: none logged")
            } else {
                var total: TimeInterval = 0
                let list = daySleeps.map { sleep -> String in
                    guard let end = sleep.end else {
                        return "\(TimeFormatting.clock(sleep.start)) ongoing"
                    }
                    total += end.timeIntervalSince(sleep.start)
                    return "\(TimeFormatting.clock(sleep.start))–\(TimeFormatting.clock(end)) (\(TimeFormatting.duration(from: sleep.start, to: end)))"
                }
                lines.append("  sleeps (\(daySleeps.count), \(TimeFormatting.duration(minutes: Int(total / 60)))): " + list.joined(separator: ", "))
            }

            if dayDiapers.isEmpty {
                lines.append("  diapers: none logged")
            } else {
                let dirty = dayDiapers.filter { $0.type != .wet }.count
                lines.append("  diapers: \(dayDiapers.count) (\(dirty) dirty)")
            }
            dayBlocks.append(lines.joined(separator: "\n"))
        }

        guard daysWithData >= minimumDaysWithData else { return nil }

        let header = "\(babyName) is \(TimeFormatting.age(from: dateOfBirth, now: now)) old. " +
            "Every logged event of the last \(days) days, local times, oldest day first. " +
            "\(Self.dayLabel(today)) is today and is still in progress. " +
            "Sleeps are listed under the day they started; overnight sleeps cross midnight."
        return ([header] + dayBlocks).joined(separator: "\n\n")
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return f
    }()

    private static func dayLabel(_ day: Date) -> String { dayFormatter.string(from: day) }
}
