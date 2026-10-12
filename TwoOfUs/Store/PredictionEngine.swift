import Foundation

/// On-device statistical predictions from the baby's own logged history —
/// when the next bottle lands, how big it runs, how long the current sleep
/// goes. Pure functions over plain values (no SwiftData, no stores), the
/// `WakeWindow` recipe generalized: **a prior sets the range, his own data
/// positions him inside it.** For feed timing the prior is the parent's
/// configured interval; for amounts and sleep durations it's the published
/// age band (`AgeBaselines`). His data is recency-weighted (see
/// `decayWeight`): a newborn's rhythm shifts week to week, and last night
/// should count for more than last Tuesday. Full analysis and worked
/// examples in docs/PREDICTION-MATH.md.
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

    struct Bedtime: Equatable {
        /// Tonight's projected bed-down moment.
        let date: Date
        /// The middle half of his observed bedtimes (weighted 25th–75th
        /// percentile), projected onto tonight — the honest "somewhere in
        /// here" a parent actually plans around.
        let range: ClosedRange<Date>
        let confidence: Confidence
    }

    private static let minute = 60.0
    private static let hour = 3600.0

    // MARK: Recency weighting

    /// Evidence decays with age: an event `halfLife` old carries half the
    /// weight of one logged now, two half-lives a quarter, and so on. A
    /// newborn's rhythm genuinely shifts on a 2–4 day timescale, and an
    /// unweighted median over a window lags a real change by half the
    /// window's span — the decay cuts that lag to roughly one half-life
    /// while the windows stay as the hard mis-log horizon. Per-prediction
    /// half-lives live beside their windows below; the walk-forward
    /// evaluation (`PredictionAccuracy`) is the arbiter if these ever need
    /// retuning.
    static func decayWeight(age: TimeInterval, halfLife: TimeInterval) -> Double {
        pow(2, -max(0, age) / halfLife)
    }

    /// Kish effective sample size: (Σw)²/Σw². Equal weights give back the
    /// raw count; mostly-stale evidence counts as fewer samples, so the
    /// confidence tiers stay honest under decay — thin recent data degrades
    /// toward the prior instead of masquerading as a full sample.
    static func effectiveCount(_ weights: [Double]) -> Double {
        let sum = weights.reduce(0, +)
        let sumOfSquares = weights.reduce(0) { $0 + $1 * $1 }
        guard sumOfSquares > 0 else { return 0 }
        return sum * sum / sumOfSquares
    }

    /// Weighted quantile: the smallest value whose cumulative weight reaches
    /// `q` of the total. Still an order statistic — an outlier that slips
    /// the plausibility filter contributes its weight, never its magnitude,
    /// which is the whole reason the engine medians instead of averaging.
    static func weightedQuantile(_ observed: [(value: Double, weight: Double)],
                                 q: Double) -> Double? {
        let usable = observed.filter { $0.weight > 0 }
        guard !usable.isEmpty else { return nil }
        let sorted = usable.sorted { $0.value < $1.value }
        let threshold = sorted.reduce(0) { $0 + $1.weight } * min(max(q, 0), 1)
        var cumulative = 0.0
        for pair in sorted {
            cumulative += pair.weight
            if cumulative >= threshold { return pair.value }
        }
        return sorted[sorted.count - 1].value
    }

    // MARK: Feed timing

    /// Feeds closer together than this are one feeding — a top-off, a burp
    /// break — not a new hunger cycle, and the gap between them is noise.
    static let feedClusterGap: TimeInterval = 30 * minute
    /// A gap outside this range is a mis-log or a skipped log, not evidence.
    static let plausibleFeedGap: ClosedRange<TimeInterval> = 1 * hour...6 * hour
    /// Trailing window: the hard horizon for mis-logs; the decay half-life
    /// below does the recency work inside it.
    static let feedHistoryWindow: TimeInterval = 14 * 24 * hour
    static let feedGapHalfLife: TimeInterval = 3 * 24 * hour
    /// Evidence thresholds, in Kish-effective samples (see `effectiveCount`) —
    /// lower than the raw-count 5/15 they replace because decayed evidence
    /// counts under its raw size.
    static let feedMinimumEvidence = 4.0
    static let feedFullEvidence = 12.0
    /// Feed timing reads the 40th percentile of his gaps, not the median —
    /// a deliberately slightly-early forecast, because the cost of the miss
    /// is asymmetric: a bottle warm a few minutes early beats a crying baby
    /// while it warms. Product decision, not a math accident. (The
    /// walk-forward MAE score pays a small penalty for this bias — if the
    /// ridge challenger starts winning on that margin alone, revisit.)
    static let feedGapQuantile = 0.4

    /// Observed gaps between distinct feedings (clusters collapsed), measured
    /// the way the prediction is anchored: from the LAST bottle of one feeding
    /// to the first of the next. Only gaps starting in the same day-part as
    /// `night` count — daytime cadence and overnight spacing are different
    /// rhythms, and mixing them drags both.
    /// Distinct feedings: bottles closer than `feedClusterGap` collapse into
    /// one, running from the first bottle to the last. Shared by the gap
    /// statistics, the Phase 2 model features, and the walk-forward accuracy
    /// evaluation, so all three agree on what "a feeding" is.
    static func feedings(feeds: [Date], within window: TimeInterval,
                         now: Date = .now) -> [(first: Date, last: Date)] {
        let recent = feeds
            .filter { $0 > now.addingTimeInterval(-window) && $0 <= now }
            .sorted()
        var feedings: [(first: Date, last: Date)] = []
        for t in recent {
            if let current = feedings.last, t.timeIntervalSince(current.last) < feedClusterGap {
                feedings[feedings.count - 1].last = t
            } else {
                feedings.append((first: t, last: t))
            }
        }
        return feedings
    }

    /// Each gap is returned with the moment it ended (the next feeding's
    /// first bottle) so callers can weight it by how long ago it happened.
    static func feedGaps(
        feeds: [Date],
        night: Bool,
        nightStartMinute: Int,
        nightEndMinute: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [(gap: TimeInterval, end: Date)] {
        let feedings = feedings(feeds: feeds, within: feedHistoryWindow, now: now)
        guard feedings.count >= 2 else { return [] }

        var gaps: [(gap: TimeInterval, end: Date)] = []
        for (a, b) in zip(feedings, feedings.dropFirst()) {
            let gap = b.first.timeIntervalSince(a.last)
            guard plausibleFeedGap.contains(gap) else { continue }
            guard WakeWindow.isNight(a.last, startMinute: nightStartMinute,
                                     endMinute: nightEndMinute, calendar: calendar) == night else { continue }
            gaps.append((gap: gap, end: b.first))
        }
        return gaps
    }

    /// The next expected feed: the configured target interval slid toward the
    /// recency-weighted 40th percentile of his observed gaps in proportion to
    /// evidence, clamped to a band around the target so a chaotic week can't
    /// push the projection somewhere implausible. Below the evidence minimum
    /// the target stands alone and confidence is `.low` — callers keep
    /// today's plain hint.
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
        let observed = gaps.map { (value: $0.gap,
                                   weight: decayWeight(age: now.timeIntervalSince($0.end),
                                                       halfLife: feedGapHalfLife)) }
        let blended = blend(prior: targetInterval, observed: observed,
                            quantile: feedGapQuantile,
                            minimum: feedMinimumEvidence, full: feedFullEvidence,
                            clampTo: targetInterval * 0.6...targetInterval * 1.5)
        return FeedTime(date: lastFeed.addingTimeInterval(blended.value),
                        confidence: blended.confidence)
    }

    // MARK: Day parts

    /// Finer buckets than day/night for bottle sizes: a first-thing-in-the-
    /// morning bottle and an evening cluster feed are genuinely different
    /// sizes once there's enough history to tell them apart. The night check
    /// defers to the household night window; the day splits at fixed clock
    /// boundaries (noon, 5 PM) rather than window-relative ones so the
    /// buckets stay meaningful whatever hours the parents configured.
    enum DayPart: Equatable {
        case night, morning, midday, evening

        static func classify(_ date: Date, nightStartMinute: Int, nightEndMinute: Int,
                             calendar: Calendar = .current) -> DayPart {
            if WakeWindow.isNight(date, startMinute: nightStartMinute,
                                  endMinute: nightEndMinute, calendar: calendar) { return .night }
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            let minuteOfDay = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            if minuteOfDay < 12 * 60 { return .morning }
            if minuteOfDay < 17 * 60 { return .midday }
            return .evening
        }
    }

    // MARK: Feed amount

    static let plausibleOz: ClosedRange<Double> = 0.5...12
    static let amountHistoryWindow: TimeInterval = 7 * 24 * hour
    /// Shortest half-life in the engine: growth spurts move bottle sizes
    /// within a day or two.
    static let amountHalfLife: TimeInterval = 2 * 24 * hour
    static let amountMinimumEvidence = 4.0
    static let amountFullEvidence = 12.0
    /// A clock bucket holds a third of the day's bottles, so demanding the
    /// whole-day evidence bar inside one would leave bucketed suggestions
    /// hedged forever. A same-hour sample is also worth more — the
    /// distribution it's drawn from is tighter — so full trust comes sooner.
    static let amountBucketFullEvidence = 8.0

    /// Expected bottle size for a feed at `reference`: the age-band midpoint
    /// slid toward the recency-weighted median of his comparable bottles
    /// over the trailing week. Comparable means the same clock bucket
    /// (`DayPart`) when that bucket carries enough evidence on its own —
    /// morning and evening bottles genuinely differ once history can show it
    /// — and otherwise the same side of the day/night split, so thin buckets
    /// degrade to the broader pattern instead of to the age table.
    /// Clamped to the age band stretched by 1.5 oz each side — the
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
        let part = DayPart.classify(reference, nightStartMinute: nightStartMinute,
                                    nightEndMinute: nightEndMinute, calendar: calendar)
        let usable = feeds.filter {
            $0.timestamp > now.addingTimeInterval(-amountHistoryWindow) && $0.timestamp <= now
                && plausibleOz.contains($0.oz)
        }
        func weighted(_ samples: [(timestamp: Date, oz: Double)]) -> [(value: Double, weight: Double)] {
            samples.map { (value: $0.oz,
                           weight: decayWeight(age: now.timeIntervalSince($0.timestamp),
                                               halfLife: amountHalfLife)) }
        }
        let bucketed = weighted(usable.filter {
            DayPart.classify($0.timestamp, nightStartMinute: nightStartMinute,
                             nightEndMinute: nightEndMinute, calendar: calendar) == part
        })
        let bucketStands = effectiveCount(bucketed.map(\.weight)) >= amountMinimumEvidence
        let observed = bucketStands
            ? bucketed
            : weighted(usable.filter {
                WakeWindow.isNight($0.timestamp, startMinute: nightStartMinute,
                                   endMinute: nightEndMinute, calendar: calendar) == night
            })
        let fullEvidence = bucketStands ? amountBucketFullEvidence : amountFullEvidence
        let band = AgeBaselines.band(AgeBaselines.ozPerFeed, ageInDays: ageInDays)
        let clamp = max(0.5, band.range.lowerBound - 1.5)...(band.range.upperBound + 1.5)
        let blended = blend(prior: band.midpoint, observed: observed,
                            minimum: amountMinimumEvidence, full: fullEvidence,
                            clampTo: clamp)
        return FeedAmount(oz: (blended.value * 4).rounded() / 4, confidence: blended.confidence)
    }

    // MARK: Sleep duration

    /// Duration sanity bounds per class — outside these it's a forgotten
    /// timer or a blip, not evidence.
    static let plausibleNap: ClosedRange<TimeInterval> = 15 * minute...4 * hour
    static let plausibleNightStretch: ClosedRange<TimeInterval> = 30 * minute...13 * hour
    static let sleepHistoryWindow: TimeInterval = 14 * 24 * hour
    /// Longest half-life in the engine: sleep samples are sparse (a handful
    /// of naps a day, two or three night stretches), so the decay leans
    /// gentler to keep the effective count above the minimum.
    static let sleepHalfLife: TimeInterval = 4 * 24 * hour
    static let sleepMinimumEvidence = 3.0
    static let sleepFullEvidence = 8.0

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
        let observed: [(value: Double, weight: Double)] = sleeps.compactMap { sleep in
            guard let end = sleep.endedAt,
                  sleep.startedAt > now.addingTimeInterval(-sleepHistoryWindow) else { return nil }
            let duration = end.timeIntervalSince(sleep.startedAt)
            guard plausible.contains(duration) else { return nil }
            guard WakeWindow.isNight(sleep.startedAt, startMinute: nightStartMinute,
                                     endMinute: nightEndMinute, calendar: calendar) == night else { return nil }
            return (value: duration,
                    weight: decayWeight(age: now.timeIntervalSince(sleep.startedAt),
                                        halfLife: sleepHalfLife))
        }
        let band = AgeBaselines.band(night ? AgeBaselines.nightStretch : AgeBaselines.napDuration,
                                     ageInDays: ageInDays)
        let blended = blend(prior: band.midpoint, observed: observed,
                            minimum: sleepMinimumEvidence, full: sleepFullEvidence,
                            clampTo: band.range)
        return SleepDuration(duration: blended.value, confidence: blended.confidence, isNight: night)
    }

    // MARK: Bedtime

    /// Bedtimes shift on a slower clock than bottles, and there's only one
    /// observation per night, so the window and half-life run longer and the
    /// evidence gates lower (one per night ≈ a week to full confidence).
    static let bedtimeHistoryWindow: TimeInterval = 10 * 24 * hour
    static let bedtimeHalfLife: TimeInterval = 4 * 24 * hour
    static let bedtimeMinimumEvidence = 3.0
    static let bedtimeFullEvidence = 7.0
    /// The hunting ground for "went down for the night" around the configured
    /// night start: a bed-down up to 90 minutes before the window still
    /// counts as bedtime, and the first down up to 4 hours after it still
    /// does (a rough evening, not a different routine). Anything later is a
    /// night wake re-settle, which must never read as bedtime evidence.
    static let bedtimeEarlyMargin: TimeInterval = 90 * minute
    static let bedtimeLateCutoff: TimeInterval = 4 * hour

    /// When he goes down for the night: the earliest qualifying sleep start
    /// of each trailing night, recency-weighted, blended toward the
    /// configured night start as the prior. The range is the weighted middle
    /// half of those observed bedtimes — shown to the parents instead of
    /// false single-minute precision.
    static func bedtime(
        sleeps: [(startedAt: Date, endedAt: Date?)],
        nightStartMinute: Int,
        nightEndMinute: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bedtime {
        let day: TimeInterval = 24 * hour
        // Offsets are measured from the start of the hunting ground, so the
        // prior (bedtime = the configured night start) sits `earlyMargin` in.
        let anchorFromMidnight = Double(nightStartMinute) * minute - bedtimeEarlyMargin
        let span = bedtimeEarlyMargin + bedtimeLateCutoff

        func secondsOfDay(_ date: Date) -> Double {
            let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
            return Double((parts.hour ?? 0) * 3600 + (parts.minute ?? 0) * 60 + (parts.second ?? 0))
        }

        // Earliest qualifying bed-down per night. Later night starts (the
        // 2 AM re-settle after a feed) lose to the real bedtime on min-offset.
        var byNight: [Date: (offset: Double, at: Date)] = [:]
        for sleep in sleeps {
            let start = sleep.startedAt
            guard start > now.addingTimeInterval(-bedtimeHistoryWindow), start <= now else { continue }
            var offset = (secondsOfDay(start) - anchorFromMidnight).truncatingRemainder(dividingBy: day)
            if offset < 0 { offset += day }
            guard offset <= span else { continue }
            let nightKey = calendar.startOfDay(for: start.addingTimeInterval(-offset))
            if let existing = byNight[nightKey], existing.offset <= offset { continue }
            byNight[nightKey] = (offset: offset, at: start)
        }

        let observed = byNight.values.map {
            (value: $0.offset,
             weight: decayWeight(age: now.timeIntervalSince($0.at), halfLife: bedtimeHalfLife))
        }
        let blended = blend(prior: bedtimeEarlyMargin, observed: observed,
                            minimum: bedtimeMinimumEvidence, full: bedtimeFullEvidence,
                            clampTo: 0...span)

        // Project onto the upcoming night: today's hunting ground, or
        // tomorrow's once tonight's has fully passed.
        var anchor = calendar.startOfDay(for: now).addingTimeInterval(anchorFromMidnight)
        if anchor.addingTimeInterval(span) < now { anchor = anchor.addingTimeInterval(day) }

        let lower = weightedQuantile(observed, q: 0.25) ?? blended.value
        let upper = weightedQuantile(observed, q: 0.75) ?? blended.value
        let range = anchor.addingTimeInterval(min(lower, upper))...anchor.addingTimeInterval(max(lower, upper))
        return Bedtime(
            date: anchor.addingTimeInterval(blended.value),
            range: range,
            confidence: blended.confidence)
    }

    // MARK: The blend

    /// The shared maths: the prior slid toward the recency-weighted observed
    /// quantile in proportion to evidence, clamped into `clampTo`. A
    /// quantile, not a mean — same reasoning as `WakeWindow.median`: one
    /// outlier that slipped the plausibility filter shouldn't move the
    /// answer the way an average would. Evidence is measured in Kish
    /// effective samples, so a window full of stale events reads as thin
    /// and leans on the prior rather than presenting old data at full
    /// confidence.
    static func blend(
        prior: Double,
        observed: [(value: Double, weight: Double)],
        quantile: Double = 0.5,
        minimum: Double,
        full: Double,
        clampTo bounds: ClosedRange<Double>
    ) -> (value: Double, confidence: Confidence) {
        let evidence = effectiveCount(observed.map(\.weight))
        guard evidence >= minimum,
              let statistic = weightedQuantile(observed, q: quantile) else {
            return (prior, .low)
        }
        let weight = min(evidence, full) / full
        let blended = prior + weight * (statistic - prior)
        let clamped = min(max(blended, bounds.lowerBound), bounds.upperBound)
        return (clamped, evidence >= full ? .high : .medium)
    }
}
