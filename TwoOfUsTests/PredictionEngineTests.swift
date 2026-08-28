import XCTest
@testable import TwoOfUs

/// Pure-function tests for the statistical prediction engine. Times are built
/// on a fixed calendar day so the day/night routing is deterministic; the
/// night window is the default 8:00 PM – 8:00 AM throughout.
final class PredictionEngineTests: XCTestCase {

    private let calendar = Calendar.current
    private let nightStart = 1200   // 8:00 PM
    private let nightEnd = 480      // 8:00 AM

    /// A fixed "now": noon today.
    private var noon: Date {
        calendar.date(bySettingHour: 12, minute: 0, second: 0, of: .now)!
    }

    private func at(daysAgo: Int = 0, hour: Int, minute: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: noon)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private let threeHours: TimeInterval = 3 * 3600

    // MARK: Feed gaps

    func testFeedGapsExcludeClusterTopOffs() {
        // 9:00, 9:20 (top-off), 12:20 → one usable gap, measured from the
        // top-off (the anchor a prediction would start from), not from 9:00.
        let feeds = [at(daysAgo: 1, hour: 9), at(daysAgo: 1, hour: 9, minute: 20),
                     at(daysAgo: 1, hour: 12, minute: 20)]
        let gaps = PredictionEngine.feedGaps(feeds: feeds, night: false,
                                             nightStartMinute: nightStart, nightEndMinute: nightEnd,
                                             now: noon)
        XCTAssertEqual(gaps.map(\.gap), [3 * 3600])
        XCTAssertEqual(gaps.map(\.end), [at(daysAgo: 1, hour: 12, minute: 20)])
    }

    func testFeedGapsSeparateDayFromNight() {
        // A 10:00 PM → 1:00 AM gap is night evidence; it must not appear in
        // the daytime gap list.
        let feeds = [at(daysAgo: 1, hour: 22), at(daysAgo: 0, hour: 1)]
        let dayGaps = PredictionEngine.feedGaps(feeds: feeds, night: false,
                                                nightStartMinute: nightStart, nightEndMinute: nightEnd,
                                                now: noon)
        let nightGaps = PredictionEngine.feedGaps(feeds: feeds, night: true,
                                                  nightStartMinute: nightStart, nightEndMinute: nightEnd,
                                                  now: noon)
        XCTAssertTrue(dayGaps.isEmpty)
        XCTAssertEqual(nightGaps.map(\.gap), [3 * 3600])
    }

    func testFeedGapsDropImplausibleGaps() {
        // A 45m gap (past the 30m cluster threshold, under the 1h plausibility
        // floor) and a 7h hole (missed logs) both stay out of evidence.
        let feeds = [at(daysAgo: 1, hour: 9), at(daysAgo: 1, hour: 9, minute: 45),
                     at(daysAgo: 1, hour: 16, minute: 45)]
        let gaps = PredictionEngine.feedGaps(feeds: feeds, night: false,
                                             nightStartMinute: nightStart, nightEndMinute: nightEnd,
                                             now: noon)
        XCTAssertTrue(gaps.isEmpty)
    }

    // MARK: Next feed

    func testNextFeedColdStartFallsBackToTarget() {
        let last = at(hour: 10)
        let prediction = PredictionEngine.nextFeed(
            lastFeed: last, feeds: [last],
            targetInterval: threeHours,
            nightStartMinute: nightStart, nightEndMinute: nightEnd, now: noon)
        XCTAssertEqual(prediction.confidence, .low)
        XCTAssertEqual(prediction.date, last.addingTimeInterval(threeHours))
    }

    func testNextFeedBlendsTowardObservedCadence() {
        // Six consistent 2h daytime gaps against a 3h target: the projection
        // must move toward 2h but stay short of it (evidence not yet full).
        var feeds: [Date] = []
        for hour in stride(from: 8, through: 18, by: 2) {
            feeds.append(at(daysAgo: 1, hour: hour))
        }
        let last = at(hour: 10)
        let prediction = PredictionEngine.nextFeed(
            lastFeed: last, feeds: feeds + [last],
            targetInterval: threeHours,
            nightStartMinute: nightStart, nightEndMinute: nightEnd, now: noon)
        XCTAssertEqual(prediction.confidence, .medium)
        let projected = prediction.date.timeIntervalSince(last)
        XCTAssertLessThan(projected, threeHours)
        XCTAssertGreaterThan(projected, 2 * 3600)
    }

    func testNextFeedClampsToBandAroundTarget() {
        // Eight 6h gaps (plausible individually) would blend to ~4.6h against
        // a 3h target — the clamp holds the projection at 1.5× the target.
        var feeds: [Date] = []
        for day in 1...4 {
            feeds.append(at(daysAgo: day, hour: 8))
            feeds.append(at(daysAgo: day, hour: 14))
            feeds.append(at(daysAgo: day, hour: 20))
        }
        let last = at(hour: 9)
        let prediction = PredictionEngine.nextFeed(
            lastFeed: last, feeds: feeds + [last],
            targetInterval: threeHours,
            nightStartMinute: nightStart, nightEndMinute: nightEnd, now: noon)
        XCTAssertNotEqual(prediction.confidence, .low)
        XCTAssertEqual(prediction.date.timeIntervalSince(last), threeHours * 1.5, accuracy: 1)
    }

    // MARK: Feed amount

    func testFeedAmountColdStartIsAgeBaseline() {
        let prediction = PredictionEngine.feedAmount(
            feeds: [], ageInDays: 90, at: noon,
            nightStartMinute: nightStart, nightEndMinute: nightEnd, now: noon)
        XCTAssertEqual(prediction.confidence, .low)
        let band = AgeBaselines.band(AgeBaselines.ozPerFeed, ageInDays: 90)
        XCTAssertEqual(prediction.oz, band.midpoint, accuracy: 0.26)
    }

    func testFeedAmountFollowsObservedBottlesAndRoundsToQuarterOz() {
        // A full week of 3.6 oz daytime bottles = full confidence even after
        // recency decay; the age midpoint (5.0 at 90 days) gives way to his
        // number, rounded to 0.25 steps.
        var feeds: [(Date, Double)] = []
        for day in 1...7 {
            for hour in [9, 12, 15] {
                feeds.append((at(daysAgo: day, hour: hour), 3.6))
            }
        }
        let prediction = PredictionEngine.feedAmount(
            feeds: feeds, ageInDays: 90, at: noon,
            nightStartMinute: nightStart, nightEndMinute: nightEnd, now: noon)
        XCTAssertEqual(prediction.confidence, .high)
        XCTAssertEqual(prediction.oz, 3.5)
        XCTAssertEqual(prediction.oz.truncatingRemainder(dividingBy: 0.25), 0)
    }

    func testFeedAmountUsesNightBottlesForNightReference() {
        // Days run 4 oz, nights run 2.5 — a 3:00 AM reference must read the
        // night pattern.
        var feeds: [(Date, Double)] = []
        for day in 1...5 {
            for hour in [9, 12, 15] { feeds.append((at(daysAgo: day, hour: hour), 4.0)) }
            feeds.append((at(daysAgo: day, hour: 23), 2.5))
            feeds.append((at(daysAgo: day, hour: 3), 2.5))
        }
        let prediction = PredictionEngine.feedAmount(
            feeds: feeds, ageInDays: 90, at: at(hour: 3),
            nightStartMinute: nightStart, nightEndMinute: nightEnd, now: noon)
        XCTAssertNotEqual(prediction.confidence, .low)
        // Ten night samples (decayed to ~8 effective): blended most of the
        // way from the 5 oz age midpoint toward his 2.5 — and clearly under
        // the 4 oz daytime pattern.
        XCTAssertLessThan(prediction.oz, 4)
        XCTAssertGreaterThanOrEqual(prediction.oz, 2.5)
    }

    // MARK: Sleep duration

    func testSleepDurationColdStartIsAgeBandMidpoint() {
        let start = at(hour: 13)
        let prediction = PredictionEngine.sleepDuration(
            startingAt: start, sleeps: [], ageInDays: 90,
            nightStartMinute: nightStart, nightEndMinute: nightEnd, now: noon)
        XCTAssertEqual(prediction.confidence, .low)
        XCTAssertFalse(prediction.isNight)
        let band = AgeBaselines.band(AgeBaselines.napDuration, ageInDays: 90)
        XCTAssertEqual(prediction.duration, band.midpoint, accuracy: 1)
    }

    func testSleepDurationLearnsFromComparableNaps() {
        // Nine ~50m naps over five days: full confidence even after recency
        // decay, and the projection lands on his median, inside the age band.
        var sleeps: [(Date, Date?)] = []
        let today = at(hour: 9)
        sleeps.append((today, today.addingTimeInterval(50 * 60)))
        for day in 1...4 {
            for hour in [9, 14] {
                let start = at(daysAgo: day, hour: hour)
                sleeps.append((start, start.addingTimeInterval(50 * 60)))
            }
        }
        let prediction = PredictionEngine.sleepDuration(
            startingAt: at(hour: 13), sleeps: sleeps, ageInDays: 90,
            nightStartMinute: nightStart, nightEndMinute: nightEnd, now: noon)
        XCTAssertEqual(prediction.confidence, .high)
        XCTAssertEqual(prediction.duration, 50 * 60, accuracy: 60)
    }

    func testSleepDurationClassifiesNightAndIgnoresNaps() {
        // Overnight stretches (~5h) must not be dragged down by daytime naps.
        var sleeps: [(Date, Date?)] = []
        for day in 1...4 {
            let night = at(daysAgo: day, hour: 21)
            sleeps.append((night, night.addingTimeInterval(5 * 3600)))
            let nap = at(daysAgo: day, hour: 10)
            sleeps.append((nap, nap.addingTimeInterval(45 * 60)))
        }
        let prediction = PredictionEngine.sleepDuration(
            startingAt: at(hour: 21), sleeps: sleeps, ageInDays: 90,
            nightStartMinute: nightStart, nightEndMinute: nightEnd, now: noon)
        XCTAssertTrue(prediction.isNight)
        XCTAssertNotEqual(prediction.confidence, .low)
        XCTAssertGreaterThan(prediction.duration, 3 * 3600)
    }

    func testSleepDurationIgnoresRunningAndImplausibleSleeps() {
        // A running sleep (nil end) and a 9h "nap" (forgotten timer) are not
        // evidence — two usable naps stay under the minimum, so baseline.
        let running = at(daysAgo: 1, hour: 9)
        let forgotten = at(daysAgo: 2, hour: 9)
        var sleeps: [(Date, Date?)] = [
            (running, nil),
            (forgotten, forgotten.addingTimeInterval(9 * 3600)),
        ]
        for day in 3...4 {
            let start = at(daysAgo: day, hour: 10)
            sleeps.append((start, start.addingTimeInterval(40 * 60)))
        }
        let prediction = PredictionEngine.sleepDuration(
            startingAt: at(hour: 13), sleeps: sleeps, ageInDays: 90,
            nightStartMinute: nightStart, nightEndMinute: nightEnd, now: noon)
        XCTAssertEqual(prediction.confidence, .low)
    }

    // MARK: Next feed — recency

    func testNextFeedAdaptsToRecentCadenceShift() {
        // Growth spurt: days 4–8 ran 3.5h daytime gaps, the last two days run
        // 2.5h. Raw counts favor the stale rhythm (10 old gaps vs 8 recent),
        // so an unweighted median — or even an unweighted 40th percentile —
        // would still say 3.5h; recency decay must side with this week.
        var feeds: [Date] = []
        for day in 4...8 {                                   // 3.5h era
            for (hour, minute) in [(8, 0), (11, 30), (15, 0)] {
                feeds.append(at(daysAgo: day, hour: hour, minute: minute))
            }
        }
        for day in 1...2 {                                   // 2.5h era
            for (hour, minute) in [(8, 0), (10, 30), (13, 0), (15, 30), (18, 0)] {
                feeds.append(at(daysAgo: day, hour: hour, minute: minute))
            }
        }
        let last = at(hour: 9)
        let prediction = PredictionEngine.nextFeed(
            lastFeed: last, feeds: feeds + [last],
            targetInterval: threeHours,
            nightStartMinute: nightStart, nightEndMinute: nightEnd, now: noon)
        XCTAssertEqual(prediction.confidence, .high)
        XCTAssertEqual(prediction.date.timeIntervalSince(last), 2.5 * 3600, accuracy: 60)
    }

    // MARK: Weighted statistics

    func testWeightedQuantileWithEqualWeightsMatchesOrderStatistics() {
        let values = [Double](stride(from: 1.0, through: 10.0, by: 1.0))
        let pairs = values.map { (value: $0, weight: 1.0) }
        XCTAssertEqual(PredictionEngine.weightedQuantile(pairs, q: 0.5), 5)
        // The feed-timing quantile reads deliberately early.
        XCTAssertEqual(PredictionEngine.weightedQuantile(pairs, q: PredictionEngine.feedGapQuantile), 4)
    }

    func testWeightedQuantileFollowsWeight() {
        // Same two values; whichever carries the mass wins the median.
        XCTAssertEqual(PredictionEngine.weightedQuantile([(2, 1), (4, 3)], q: 0.5), 4)
        XCTAssertEqual(PredictionEngine.weightedQuantile([(2, 3), (4, 1)], q: 0.5), 2)
        XCTAssertNil(PredictionEngine.weightedQuantile([], q: 0.5))
        XCTAssertNil(PredictionEngine.weightedQuantile([(5, 0)], q: 0.5))
    }

    func testEffectiveCountDiscountsStaleEvidence() {
        // Equal weights: the raw count. Mostly-faded weights: far fewer.
        XCTAssertEqual(PredictionEngine.effectiveCount([1, 1, 1, 1]), 4, accuracy: 0.001)
        XCTAssertEqual(PredictionEngine.effectiveCount([0.5, 0.5]), 2, accuracy: 0.001)
        XCTAssertLessThan(PredictionEngine.effectiveCount([1, 0.1, 0.1, 0.1]), 1.7)
        XCTAssertEqual(PredictionEngine.effectiveCount([]), 0)
    }

    func testDecayWeightHalvesPerHalfLife() {
        let day: TimeInterval = 24 * 3600
        XCTAssertEqual(PredictionEngine.decayWeight(age: 0, halfLife: 3 * day), 1)
        XCTAssertEqual(PredictionEngine.decayWeight(age: 3 * day, halfLife: 3 * day), 0.5, accuracy: 0.001)
        XCTAssertEqual(PredictionEngine.decayWeight(age: 6 * day, halfLife: 3 * day), 0.25, accuracy: 0.001)
        // A clock-skewed future event can't out-weigh the present.
        XCTAssertEqual(PredictionEngine.decayWeight(age: -day, halfLife: 3 * day), 1)
    }

    // MARK: Blend

    func testBlendConfidenceTiers() {
        func flat(_ value: Double, _ count: Int) -> [(value: Double, weight: Double)] {
            Array(repeating: (value: value, weight: 1.0), count: count)
        }
        let low = PredictionEngine.blend(prior: 10, observed: flat(8, 2),
                                         minimum: 3, full: 8, clampTo: 0...20)
        XCTAssertEqual(low.confidence, .low)
        XCTAssertEqual(low.value, 10)

        let medium = PredictionEngine.blend(prior: 10, observed: flat(8, 4),
                                            minimum: 3, full: 8, clampTo: 0...20)
        XCTAssertEqual(medium.confidence, .medium)
        XCTAssertEqual(medium.value, 9, accuracy: 0.01)   // half evidence → halfway

        let high = PredictionEngine.blend(prior: 10, observed: flat(8, 8),
                                          minimum: 3, full: 8, clampTo: 0...20)
        XCTAssertEqual(high.confidence, .high)
        XCTAssertEqual(high.value, 8, accuracy: 0.01)     // full evidence → the median
    }

    func testBlendTreatsStaleEvidenceAsThin() {
        // Four samples would clear a minimum of 3 at full weight — but three
        // of them faded to 0.1, so the effective count falls below it and the
        // prior stands alone.
        let stale: [(value: Double, weight: Double)] = [(8, 1), (8, 0.1), (8, 0.1), (8, 0.1)]
        let result = PredictionEngine.blend(prior: 10, observed: stale,
                                            minimum: 3, full: 8, clampTo: 0...20)
        XCTAssertEqual(result.confidence, .low)
        XCTAssertEqual(result.value, 10)
    }

    func testBlendClampHolds() {
        let result = PredictionEngine.blend(
            prior: 10, observed: Array(repeating: (value: 30.0, weight: 1.0), count: 8),
            minimum: 3, full: 8, clampTo: 5...15)
        XCTAssertEqual(result.value, 15)
    }
}
