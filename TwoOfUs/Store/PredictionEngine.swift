import Foundation

/// On-device statistical predictions from the baby's own logged history —
/// when the next bottle lands, how big it runs, how long the current sleep
/// goes. Pure functions over plain values (no SwiftData, no stores), the
/// `WakeWindow` recipe generalized: **a prior sets the range, his own data
/// positions him inside it.** For feed timing the prior is the parent's
/// configured interval; for amounts and sleep durations it's the published
/// age band (`AgeBaselines`).
///
/// Everything is computed at read time from live events and never stored or
/// synced — both phones converge on the same numbers because they hold the
/// same history. Gated by `SharedSettings.aiPredictionsEnabled` at the call
/// sites, not here.
///
/// These are planning aids, never medical guidance (`WakeWindow` holds the
/// same line). A `.low` confidence result means "not enough of his data yet" —
/// callers fall back to today's non-AI hints rather than dressing the prior
/// up as personalization.
enum PredictionEngine {

    /// Evidence tiers, mapped from usable sample counts. `.low` = below the
    /// minimum (the prior stands alone; don't present it as his pattern),
    /// `.medium` = the blend has started moving, `.high` = trusted as much as
    /// it ever will be. UI renders these as wording, not badges.
    enum Confidence {
        case low, medium, high
    }

    struct FeedTime: Equatable {
        let date: Date
        let confidence: Confidence
    }

    struct FeedAmount: Equatable {
        let oz: Double
        let confidence: Confidence
    }

    struct SleepDuration: Equatable {
        let duration: TimeInterval
        let confidence: Confidence
        let isNight: Bool
    }

    private static let minute = 60.0
    private static let hour = 3600.0

    // MARK: Feed timing

    /// Feeds closer together than this are one feeding — a top-off, a burp
    /// break — not a new hunger cycle, and the gap between them is noise.
    static let feedClusterGap: TimeInterval = 30 * minute
    /// A gap outside this range is a mis-log or a skipped log, not evidence.
    static let plausibleFeedGap: ClosedRange<TimeInterval> = 1 * hour...6 * hour
    /// Trailing window: a growth spurt should move the numbers within days.
    static let feedHistoryWindow: TimeInterval = 14 * 24 * hour
    static let feedMinimumSamples = 5
    static let feedFullConfidenceSamples = 15

    /// Observed gaps between distinct feedings (clusters collapsed), measured
    /// the way the prediction is anchored: from the LAST bottle of one feeding
    /// to the first of the next. Only gaps starting in the same day-part as
    /// `night` count — daytime cadence and overnight spacing are different
    /// rhythms, and mixing them drags both.
    static func feedGaps(
        feeds: [Date],
        night: Bool,
        nightStartMinute: Int,
        nightEndMinute: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [TimeInterval] {
        let recent = feeds
            .filter { $0 > now.addingTimeInterval(-feedHistoryWindow) && $0 <= now }
            .sorted()
        guard recent.count >= 2 else { return [] }

        // Collapse clusters: a feeding runs from its first bottle to the last
        // bottle within `feedClusterGap` of its predecessor.
        var feedings: [(first: Date, last: Date)] = []
        for t in recent {
            if let current = feedings.last, t.timeIntervalSince(current.last) < feedClusterGap {
                feedings[feedings.count - 1].last = t
            } else {
                feedings.append((first: t, last: t))
            }
        }

        var gaps: [TimeInterval] = []
        for (a, b) in zip(feedings, feedings.dropFirst()) {
            let gap = b.first.timeIntervalSince(a.last)
            guard plausibleFeedGap.contains(gap) else { continue }
            guard WakeWindow.isNight(a.last, startMinute: nightStartMinute,
                                     endMinute: nightEndMinute, calendar: calendar) == night else { continue }
            gaps.append(gap)
        }
        return gaps
    }

    /// The next expected feed: the configured target interval slid toward the
    /// median of his observed gaps in proportion to evidence, clamped to a
    /// band around the target so a chaotic week can't push the projection
    /// somewhere implausible. Below the sample minimum the target stands
    /// alone and confidence is `.low` — callers keep today's plain hint.
    ///
    /// This deliberately does NOT feed the alarm or the schedule: the bell is
    /// a contract the parents configured, the hint is a forecast. Alarms stay
    /// on `SharedSettings.feedInterval`.
    static func nextFeed(
        lastFeed: Date,
        feeds: [Date],
        targetInterval: TimeInterval,
        nightStartMinute: Int,
        nightEndMinute: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> FeedTime {
        let night = WakeWindow.isNight(lastFeed, startMinute: nightStartMinute,
                                       endMinute: nightEndMinute, calendar: calendar)
        let gaps = feedGaps(feeds: feeds, night: night,
                            nightStartMinute: nightStartMinute, nightEndMinute: nightEndMinute,
                            now: now, calendar: calendar)
        let blended = blend(prior: targetInterval, observed: gaps,
                            minimum: feedMinimumSamples, full: feedFullConfidenceSamples,
                            clampTo: targetInterval * 0.6...targetInterval * 1.5)
        return FeedTime(date: lastFeed.addingTimeInterval(blended.value),
                        confidence: blended.confidence)
    }

    // MARK: Feed amount

    static let plausibleOz: ClosedRange<Double> = 0.5...12
    static let amountHistoryWindow: TimeInterval = 7 * 24 * hour
    static let amountMinimumSamples = 5
    static let amountFullConfidenceSamples = 15

    /// Expected bottle size for a feed at `reference`: the age-band midpoint
    /// slid toward the median of his same-day-part bottles over the trailing
    /// week. Clamped to the age band stretched by 1.5 oz each side — the
    /// published bands are softer truth than wake windows (a big eater
    /// genuinely outruns his band, and under-suggesting every bottle would
    /// make the feature read broken), but a fat-fingered 10 oz log still
    /// can't drag the suggestion somewhere absurd. Rounded to quarter ounces,
    /// the app's finest logging step.
    static func feedAmount(
        feeds: [(timestamp: Date, oz: Double)],
        ageInDays: Int,
        at reference: Date,
        nightStartMinute: Int,
        nightEndMinute: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> FeedAmount {
        let night = WakeWindow.isNight(reference, startMinute: nightStartMinute,
                                       endMinute: nightEndMinute, calendar: calendar)
        let observed = feeds
            .filter {
                $0.timestamp > now.addingTimeInterval(-amountHistoryWindow) && $0.timestamp <= now
                    && plausibleOz.contains($0.oz)
                    && WakeWindow.isNight($0.timestamp, startMinute: nightStartMinute,
                                          endMinute: nightEndMinute, calendar: calendar) == night
            }
            .map(\.oz)
        let band = AgeBaselines.band(AgeBaselines.ozPerFeed, ageInDays: ageInDays)
        let clamp = max(0.5, band.range.lowerBound - 1.5)...(band.range.upperBound + 1.5)
        let blended = blend(prior: band.midpoint, observed: observed,
                            minimum: amountMinimumSamples, full: amountFullConfidenceSamples,
                            clampTo: clamp)
        return FeedAmount(oz: (blended.value * 4).rounded() / 4, confidence: blended.confidence)
    }

    // MARK: Sleep duration

    /// Duration sanity bounds per class — outside these it's a forgotten
    /// timer or a blip, not evidence.
    static let plausibleNap: ClosedRange<TimeInterval> = 15 * minute...4 * hour
    static let plausibleNightStretch: ClosedRange<TimeInterval> = 30 * minute...13 * hour
    static let sleepHistoryWindow: TimeInterval = 14 * 24 * hour
    static let sleepMinimumSamples = 3
    static let sleepFullConfidenceSamples = 8

    /// Expected length of a sleep starting at `start` — the current nap's
    /// remaining question ("when will he wake?") or the next nap's ("how long
    /// will I get?"). Classified nap vs night by the start time against the
    /// household night window; compared only against completed sleeps of the
    /// same class in the trailing two weeks; blended with the age band and
    /// clamped into it, `WakeWindow`-style.
    static func sleepDuration(
        startingAt start: Date,
        sleeps: [(startedAt: Date, endedAt: Date?)],
        ageInDays: Int,
        nightStartMinute: Int,
        nightEndMinute: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> SleepDuration {
        let night = WakeWindow.isNight(start, startMinute: nightStartMinute,
                                       endMinute: nightEndMinute, calendar: calendar)
        let plausible = night ? plausibleNightStretch : plausibleNap
        let observed: [TimeInterval] = sleeps.compactMap { sleep in
            guard let end = sleep.endedAt,
                  sleep.startedAt > now.addingTimeInterval(-sleepHistoryWindow) else { return nil }
            let duration = end.timeIntervalSince(sleep.startedAt)
            guard plausible.contains(duration) else { return nil }
            guard WakeWindow.isNight(sleep.startedAt, startMinute: nightStartMinute,
                                     endMinute: nightEndMinute, calendar: calendar) == night else { return nil }
            return duration
        }
        let band = AgeBaselines.band(night ? AgeBaselines.nightStretch : AgeBaselines.napDuration,
                                     ageInDays: ageInDays)
        let blended = blend(prior: band.midpoint, observed: observed,
                            minimum: sleepMinimumSamples, full: sleepFullConfidenceSamples,
                            clampTo: band.range)
        return SleepDuration(duration: blended.value, confidence: blended.confidence, isNight: night)
    }

    // MARK: The blend

    /// The shared maths: the prior slid toward the observed median in
    /// proportion to evidence, clamped into `clampTo`. Median, not mean —
    /// same reasoning as `WakeWindow.median`: one outlier that slipped the
    /// plausibility filter shouldn't move the answer the way an average would.
    static func blend(
        prior: Double,
        observed: [Double],
        minimum: Int,
        full: Int,
        clampTo bounds: ClosedRange<Double>
    ) -> (value: Double, confidence: Confidence) {
        guard observed.count >= minimum, let median = WakeWindow.median(observed) else {
            return (prior, .low)
        }
        let weight = min(Double(observed.count), Double(full)) / Double(full)
        let blended = prior + weight * (median - prior)
        let clamped = min(max(blended, bounds.lowerBound), bounds.upperBound)
        return (clamped, observed.count >= full ? .high : .medium)
    }
}
