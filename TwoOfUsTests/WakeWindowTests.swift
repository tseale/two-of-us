import XCTest
@testable import TwoOfUs

/// `WakeWindow` replaced a flat 2.5-hour constant that was blind to both age
/// and history. These pin the two properties that make it trustworthy: the
/// age band always bounds the answer, and his own data positions him inside it.
final class WakeWindowTests: XCTestCase {

    private let minute: TimeInterval = 60

    // MARK: Age bands

    func testNewbornWindowIsUnderAnHourAndOldBabiesAreHours() {
        // The old flat 2.5h was wrong at both ends — that's the whole point.
        XCTAssertEqual(WakeWindow.baseline(ageInDays: 3), 52.5 * minute, accuracy: 1)
        XCTAssertLessThan(WakeWindow.baseline(ageInDays: 3), 60 * minute,
                          "a newborn cannot stay awake for the old 2.5h default")
        XCTAssertGreaterThan(WakeWindow.baseline(ageInDays: 400), 4 * 3600,
                             "a toddler's window is far longer than the old default")
    }

    func testBandBoundariesAreExclusiveOnTheUpperDay() {
        // 28 days is the first day of the 1–2 month band, not the last newborn day.
        XCTAssertEqual(WakeWindow.ageBand(ageInDays: 27).upperBoundDays, 28)
        XCTAssertEqual(WakeWindow.ageBand(ageInDays: 28).upperBoundDays, 56)
    }

    func testUnbornAndNegativeAgesTakeTheNewbornBand() {
        // Setup-before-birth is supported (Baby.isBorn); a due date in the
        // future must not index off the front of the table.
        XCTAssertEqual(WakeWindow.ageBand(ageInDays: -20), WakeWindow.ageBand(ageInDays: 0))
    }

    // MARK: Personalization

    func testThinHistoryLeavesTheAgeBaselineAlone() {
        let baseline = WakeWindow.baseline(ageInDays: 60)
        // Two samples is below `minimumSamples` — one odd day must not redefine him.
        XCTAssertEqual(WakeWindow.predicted(ageInDays: 60, observedGaps: [80 * minute, 85 * minute]),
                       baseline)
        XCTAssertEqual(WakeWindow.predicted(ageInDays: 60, observedGaps: []), baseline)
    }

    func testConsistentlyShortWindowsPullThePredictionDown() {
        let baseline = WakeWindow.baseline(ageInDays: 60)   // 2–3 months → 90m midpoint
        let short = Array(repeating: 78 * minute, count: 8)
        let predicted = WakeWindow.predicted(ageInDays: 60, observedGaps: short)
        XCTAssertLessThan(predicted, baseline, "his own shorter windows should win")
        XCTAssertEqual(predicted, 78 * minute, accuracy: 1,
                       "at full confidence the prediction lands on his median")
    }

    func testMoreEvidenceMovesThePredictionFurther() {
        let baseline = WakeWindow.baseline(ageInDays: 60)
        let three = WakeWindow.predicted(ageInDays: 60,
                                         observedGaps: Array(repeating: 78 * minute, count: 3))
        let eight = WakeWindow.predicted(ageInDays: 60,
                                         observedGaps: Array(repeating: 78 * minute, count: 8))
        XCTAssertLessThan(three, baseline)
        XCTAssertLessThan(eight, three, "confidence grows with sample count")
    }

    // MARK: The clamp — the safety property

    func testPredictionNeverLeavesTheAgeBand() {
        let band = WakeWindow.ageBand(ageInDays: 60).range
        // A run of implausibly long (but individually plausible) windows.
        let long = Array(repeating: 5 * 3600 as TimeInterval, count: 20)
        let predicted = WakeWindow.predicted(ageInDays: 60, observedGaps: long)
        XCTAssertLessThanOrEqual(predicted, band.upperBound,
                                 "a chaotic week must not project a newborn into toddler territory")
        XCTAssertGreaterThanOrEqual(predicted, band.lowerBound)
    }

    func testImplausibleGapsAreDiscardedNotClamped() {
        // A 9-hour "wake gap" is a forgotten timer; it must not even count as a
        // sample, or three of them would look like enough evidence.
        let predicted = WakeWindow.predicted(ageInDays: 60,
                                             observedGaps: [9 * 3600, 10 * 3600, 11 * 3600])
        XCTAssertEqual(predicted, WakeWindow.baseline(ageInDays: 60),
                       "junk samples fall back to the age table, not to the band ceiling")
    }

    func testMedianIgnoresASingleOutlier() {
        // Mean would be dragged; median holds.
        let gaps = [80 * minute, 82 * minute, 84 * minute, 86 * minute, 5.5 * 3600]
        XCTAssertEqual(WakeWindow.median(gaps)!, 84 * minute, accuracy: 1)
    }

    // MARK: Deriving gaps from history

    private func sleep(_ start: String, _ end: String?) -> (startedAt: Date, endedAt: Date?) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = .current
        return (f.date(from: "2026-08-06 \(start)")!, end.map { f.date(from: "2026-08-06 \($0)")! })
    }

    func testWakeGapsAreTheTimeBetweenSleeps() {
        let sleeps = [sleep("09:00", "10:00"), sleep("11:30", "12:30"), sleep("14:00", "15:00")]
        let gaps = WakeWindow.wakeGaps(sleeps: sleeps, nightStartMinute: 1200, nightEndMinute: 480)
        XCTAssertEqual(gaps, [90 * minute, 90 * minute])
    }

    func testNightWakesAreExcluded() {
        // Overnight he surfaces for a bottle and goes back down in 25 minutes.
        // Counting that as a wake window would wreck the daytime projection.
        let sleeps = [sleep("02:00", "02:30"), sleep("02:55", "06:00"), sleep("09:00", "10:00")]
        let gaps = WakeWindow.wakeGaps(sleeps: sleeps, nightStartMinute: 1200, nightEndMinute: 480)
        XCTAssertTrue(gaps.isEmpty,
                      "waking at 2:30 AM and 6:00 AM is night — neither is a wake window")
    }

    func testAnOpenSleepContributesNoGap() {
        let sleeps = [sleep("09:00", "10:00"), sleep("11:30", nil)]
        XCTAssertEqual(WakeWindow.wakeGaps(sleeps: sleeps, nightStartMinute: 1200, nightEndMinute: 480),
                       [90 * minute])
    }

    func testGapsAreDerivedInChronologicalOrderRegardlessOfInputOrder() {
        // The app's @Query sorts newest-first; the math must not depend on that.
        let ordered = [sleep("09:00", "10:00"), sleep("11:30", "12:30")]
        let reversed = Array(ordered.reversed())
        XCTAssertEqual(WakeWindow.wakeGaps(sleeps: reversed, nightStartMinute: 1200, nightEndMinute: 480),
                       WakeWindow.wakeGaps(sleeps: ordered, nightStartMinute: 1200, nightEndMinute: 480))
    }

    func testNightWindowWrapsMidnight() {
        let evening = sleep("21:00", "21:30").startedAt
        let morning = sleep("07:00", "07:30").startedAt
        let midday = sleep("13:00", "13:30").startedAt
        XCTAssertTrue(WakeWindow.isNight(evening, startMinute: 1200, endMinute: 480))
        XCTAssertTrue(WakeWindow.isNight(morning, startMinute: 1200, endMinute: 480))
        XCTAssertFalse(WakeWindow.isNight(midday, startMinute: 1200, endMinute: 480))
    }

    // MARK: Display

    func testShortLabelIsCompactEnoughForAWatchLine() {
        XCTAssertEqual(WakeWindow.shortLabel(45 * minute), "45m")
        XCTAssertEqual(WakeWindow.shortLabel(90 * minute), "1h30m")
        XCTAssertEqual(WakeWindow.shortLabel(2 * 3600), "2h")
    }

    func testNapHintShowsTheWindowItAssumed() {
        let woke = Date(timeIntervalSince1970: 1_770_000_000)
        let hint = WakeWindow.napHint(lastWake: woke, target: 90 * minute,
                                      now: woke.addingTimeInterval(10 * minute))
        XCTAssertTrue(hint.hasPrefix("next nap ~"), hint)
        XCTAssertTrue(hint.hasSuffix("· 1h30m awake"), hint)
    }

    func testNapHintFlipsToOverdue() {
        let woke = Date(timeIntervalSince1970: 1_770_000_000)
        let hint = WakeWindow.napHint(lastWake: woke, target: 90 * minute,
                                      now: woke.addingTimeInterval(2 * 3600))
        XCTAssertTrue(hint.hasPrefix("nap was due ~"), hint)
    }

    func testNapHintWithNoHistory() {
        XCTAssertEqual(WakeWindow.napHint(lastWake: nil, target: 90 * minute), "start timer")
    }
}
