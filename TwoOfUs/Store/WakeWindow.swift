import Foundation

/// How long the baby can comfortably stay awake between sleeps — the basis for
/// every "next nap ~2:15 PM" projection in the app.
///
/// This replaces a flat 2.5-hour constant (`UrgencyDefaults.sleep`) that was
/// blind to both the baby's age and his actual history. A newborn's wake window
/// is well under an hour; a one-year-old's is four-plus. One number could never
/// be right for both, and it was never right for either.
///
/// **The model is: age sets the range, his own data positions him inside it.**
/// `ageBand` is a published age-appropriate range (see `bands`). The prediction
/// starts at that range's midpoint and slides toward the median of his recently
/// observed wake gaps as evidence accumulates, then clamps back into the range.
/// So a baby who reliably runs short gets a shorter projection than the table
/// suggests — but a chaotic week, a missed log, or a 6-hour car nap can never
/// drag the number somewhere implausible for his age.
///
/// **This is a planning aid, not clinical guidance.** The bands are the common
/// ranges that infant-sleep references broadly agree on; real babies vary, and
/// nothing here should be read as medical advice (same line the app already
/// holds in `BabyIntelligence`).
enum WakeWindow {

    // MARK: Age bands

    /// A published wake-window range for an age, and the label for that age
    /// bracket. `upperBoundDays` is exclusive.
    struct Band: Equatable {
        let upperBoundDays: Int
        let range: ClosedRange<TimeInterval>

        var midpoint: TimeInterval { (range.lowerBound + range.upperBound) / 2 }
    }

    private static let minute: TimeInterval = 60

    /// Common ranges by age. Newborn windows are startlingly short — the whole
    /// reason the old flat 2.5h read as nonsense for a two-month-old.
    static let bands: [Band] = [
        Band(upperBoundDays: 28,  range: 45 * minute...60 * minute),    // 0–4 weeks
        Band(upperBoundDays: 56,  range: 60 * minute...90 * minute),    // 1–2 months
        Band(upperBoundDays: 84,  range: 75 * minute...105 * minute),   // 2–3 months
        Band(upperBoundDays: 112, range: 90 * minute...120 * minute),   // 3–4 months
        Band(upperBoundDays: 168, range: 120 * minute...150 * minute),  // 4–6 months
        Band(upperBoundDays: 252, range: 150 * minute...180 * minute),  // 6–9 months
        Band(upperBoundDays: 365, range: 180 * minute...240 * minute),  // 9–12 months
        Band(upperBoundDays: .max, range: 240 * minute...360 * minute), // 12 months+
    ]

    /// The band for an age in days. Negative ages (a due date that hasn't
    /// arrived — `Baby.isBorn` is false) take the newborn band.
    static func ageBand(ageInDays: Int) -> Band {
        let days = max(0, ageInDays)
        return bands.first { days < $0.upperBoundDays } ?? bands[bands.count - 1]
    }

    /// The age-table answer alone, with no personalization.
    static func baseline(ageInDays: Int) -> TimeInterval {
        ageBand(ageInDays: ageInDays).midpoint
    }

    // MARK: Observed gaps

    /// A gap shorter than this is a nappy-change blip or a mis-log, not a wake
    /// window; longer than this is a forgotten timer or a day out. Both would
    /// poison the median, so neither counts as evidence.
    static let plausibleGap: ClosedRange<TimeInterval> = 15 * minute...6 * 3600

    /// Evidence needed before his own data moves the number at all, and the
    /// count at which it's trusted as much as it ever will be.
    static let minimumSamples = 3
    static let fullConfidenceSamples = 8

    /// Wake gaps derived from sleep history: the time from one sleep ending to
    /// the next beginning.
    ///
    /// **Night wakes are excluded.** Overnight the baby surfaces for a feed and
    /// goes back down inside half an hour; those 20-minute gaps are not wake
    /// windows, and including them would drag the daytime projection far too
    /// short. A gap counts only if the baby WOKE during the day.
    static func wakeGaps(
        sleeps: [(startedAt: Date, endedAt: Date?)],
        nightStartMinute: Int,
        nightEndMinute: Int,
        calendar: Calendar = .current
    ) -> [TimeInterval] {
        let ordered = sleeps.sorted { $0.startedAt < $1.startedAt }
        var gaps: [TimeInterval] = []
        for (index, sleep) in ordered.enumerated() {
            guard let wokeAt = sleep.endedAt, index + 1 < ordered.count else { continue }
            let nextStart = ordered[index + 1].startedAt
            let gap = nextStart.timeIntervalSince(wokeAt)
            guard plausibleGap.contains(gap) else { continue }
            guard !isNight(wokeAt, startMinute: nightStartMinute,
                           endMinute: nightEndMinute, calendar: calendar) else { continue }
            gaps.append(gap)
        }
        return gaps
    }

    /// Night as the app models it everywhere else: wall-clock minutes from
    /// midnight, wrapping across midnight (8:00 PM → 8:00 AM by default).
    static func isNight(_ date: Date, startMinute: Int, endMinute: Int,
                        calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return startMinute <= endMinute
            ? (minute >= startMinute && minute < endMinute)
            : (minute >= startMinute || minute < endMinute)
    }

    // MARK: The prediction

    /// The projected wake window: the age midpoint, slid toward the median of
    /// `observedGaps` in proportion to how much evidence there is, then clamped
    /// into the age band.
    ///
    /// Below `minimumSamples` the age table stands alone — three wake gaps is
    /// the least that can carry a meaningful median, and one unusual day should
    /// not redefine a baby.
    static func predicted(ageInDays: Int, observedGaps: [TimeInterval]) -> TimeInterval {
        let band = ageBand(ageInDays: ageInDays)
        let usable = observedGaps.filter { plausibleGap.contains($0) }
        guard usable.count >= minimumSamples, let observed = median(usable) else {
            return band.midpoint
        }
        let confidence = min(Double(usable.count), Double(fullConfidenceSamples))
            / Double(fullConfidenceSamples)
        let blended = band.midpoint + confidence * (observed - band.midpoint)
        return min(max(blended, band.range.lowerBound), band.range.upperBound)
    }

    /// Median, not mean: one 5-hour outing that slipped past `plausibleGap`
    /// shouldn't move the answer the way an average would.
    static func median(_ values: [TimeInterval]) -> TimeInterval? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[mid - 1] + sorted[mid]) / 2
            : sorted[mid]
    }

    // MARK: Display

    /// Compact window label for the tile hints — "1h50m", "45m". Deliberately
    /// tighter than `TimeFormatting.since`'s "1h 50m": it shares a single line
    /// with a clock time on a watch face.
    static func shortLabel(_ interval: TimeInterval) -> String {
        let totalMinutes = max(0, Int((interval / 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes)m" }
        return minutes == 0 ? "\(hours)h" : "\(hours)h\(minutes)m"
    }

    /// The "next nap" hint shown under the Sleep tile on every surface (Home,
    /// watch, widgets). Centralized so the four call sites can't drift apart,
    /// and so the projected window is always shown alongside the time — the
    /// number is a prediction, and a parent should be able to see what it
    /// assumed rather than wonder where 2:15 PM came from.
    /// The watch's hint line is far narrower than the phone tile's and truncates
    /// rather than wrapping, so it drops the trailing word. Same information,
    /// same order — "· 1h30m" after a clock time reads as the window either way.
    enum HintStyle { case full, compact }

    static func napHint(lastWake: Date?, target: TimeInterval, now: Date = .now,
                        style: HintStyle = .full) -> String {
        guard let lastWake else { return "start timer" }
        let next = lastWake.addingTimeInterval(target)
        let window = style == .full ? "\(shortLabel(target)) awake" : shortLabel(target)
        return next < now
            ? "nap was due ~\(TimeFormatting.clock(next)) · \(window)"
            : "next nap ~\(TimeFormatting.clock(next)) · \(window)"
    }

    /// Age in whole days from a date of birth, for `ageBand`.
    static func ageInDays(dateOfBirth: Date, now: Date = .now,
                          calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: dateOfBirth, to: now).day ?? 0
    }
}
