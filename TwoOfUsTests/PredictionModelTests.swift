import XCTest
@testable import TwoOfUs

/// Phase 2 (ridge model) + Phase 4 (walk-forward accuracy) tests. All pure
/// and deterministic — training is closed-form, so the same history always
/// fits the same model.
final class PredictionModelTests: XCTestCase {

    private let calendar = Calendar.current
    private let nightStart = 1200
    private let nightEnd = 480

    private var noon: Date {
        calendar.date(bySettingHour: 12, minute: 0, second: 0, of: .now)!
    }

    private func at(daysAgo: Int, hour: Int, minute: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: noon)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    /// A metronome baby: bottles at fixed hours every day for `days` days.
    private func metronomeFeeds(days: Int, hours: [Int]) -> [Date] {
        var feeds: [Date] = []
        for day in 1...days {
            for hour in hours { feeds.append(at(daysAgo: day, hour: hour)) }
        }
        return feeds
    }

    private var dob: Date { calendar.date(byAdding: .day, value: -120, to: noon)! }

    // MARK: Ridge regression

    func testRidgeRecoversALinearFunction() {
        // y = 3 + 2a − b, tiny lambda so the fit is essentially exact.
        var rows: [[Double]] = []
        var targets: [Double] = []
        for a in 0...5 {
            for b in 0...5 {
                rows.append([1, Double(a), Double(b)])
                targets.append(3 + 2 * Double(a) - Double(b))
            }
        }
        let w = RidgeRegression.fit(rows: rows, targets: targets, lambda: 1e-6)
        XCTAssertNotNil(w)
        XCTAssertEqual(w![0], 3, accuracy: 0.01)
        XCTAssertEqual(w![1], 2, accuracy: 0.01)
        XCTAssertEqual(w![2], -1, accuracy: 0.01)
        XCTAssertEqual(RidgeRegression.predict(coefficients: w!, features: [1, 4, 2]), 9, accuracy: 0.05)
    }

    func testRidgeRefusesUnderdeterminedInput() {
        XCTAssertNil(RidgeRegression.fit(rows: [[1, 2, 3]], targets: [1]))
        XCTAssertNil(RidgeRegression.fit(rows: [], targets: []))
        XCTAssertNil(RidgeRegression.fit(rows: [[1, 2], [1]], targets: [1, 2]))
    }

    // MARK: Gap model

    func testGapModelLearnsAMetronome() {
        // Bottles every 3 hours, 10 days deep — far past the sample minimum.
        let feeds = metronomeFeeds(days: 10, hours: [9, 12, 15, 18])
        let model = PredictionModel.trainGapModel(
            feeds: feeds, dateOfBirth: dob,
            nightStartMinute: nightStart, nightEndMinute: nightEnd, now: noon)
        XCTAssertNotNil(model)
        let gap = PredictionModel.predictGap(
            model!, lastFeed: at(daysAgo: 0, hour: 9), previousGap: 3 * 3600,
            dateOfBirth: dob, targetInterval: 3 * 3600,
            nightStartMinute: nightStart, nightEndMinute: nightEnd)
        XCTAssertEqual(gap, 3 * 3600, accuracy: 30 * 60)
    }

    func testGapModelNeedsEnoughSamples() {
        let feeds = metronomeFeeds(days: 3, hours: [9, 12])   // 3 usable gaps/day
        XCTAssertNil(PredictionModel.trainGapModel(
            feeds: feeds, dateOfBirth: dob,
            nightStartMinute: nightStart, nightEndMinute: nightEnd, now: noon))
    }

    func testGapPredictionRespectsTheChampionClamp() {
        // Whatever the raw model says, the surfaced gap stays in the same
        // band the statistic is held to.
        let model = TrainedModel(coefficients: [100, 0, 0, 0, 0, 0, 0], sampleCount: 50)
        let gap = PredictionModel.predictGap(
            model, lastFeed: noon, previousGap: nil,
            dateOfBirth: dob, targetInterval: 3 * 3600,
            nightStartMinute: nightStart, nightEndMinute: nightEnd)
        XCTAssertEqual(gap, 4.5 * 3600, accuracy: 1)
    }

    // MARK: Amount model

    func testAmountModelLearnsDayNightSplit() {
        // 4 oz days, 2.5 oz nights — the isNight feature carries the split a
        // single all-day median can't.
        var feeds: [(Date, Double)] = []
        for day in 1...8 {
            for hour in [9, 12, 15, 18] { feeds.append((at(daysAgo: day, hour: hour), 4.0)) }
            feeds.append((at(daysAgo: day, hour: 23), 2.5))
            feeds.append((at(daysAgo: day, hour: 3), 2.5))
        }
        let model = PredictionModel.trainAmountModel(
            feeds: feeds, dateOfBirth: dob,
            nightStartMinute: nightStart, nightEndMinute: nightEnd, now: noon)
        XCTAssertNotNil(model)
        let dayOz = PredictionModel.predictAmount(
            model!, at: at(daysAgo: 0, hour: 10), gapSinceLastFeed: 3 * 3600, lastOz: 4,
            dateOfBirth: dob, nightStartMinute: nightStart, nightEndMinute: nightEnd)
        let nightOz = PredictionModel.predictAmount(
            model!, at: at(daysAgo: 0, hour: 3), gapSinceLastFeed: 3 * 3600, lastOz: 2.5,
            dateOfBirth: dob, nightStartMinute: nightStart, nightEndMinute: nightEnd)
        XCTAssertGreaterThan(dayOz, nightOz)
        XCTAssertEqual(dayOz, 4.0, accuracy: 0.75)
        XCTAssertEqual(nightOz, 2.5, accuracy: 0.75)
        XCTAssertEqual(dayOz.truncatingRemainder(dividingBy: 0.25), 0)
    }

    // MARK: Walk-forward accuracy (Phase 4)

    func testFeedTimeReportScoresAMetronomeTightly() {
        let feeds = metronomeFeeds(days: 20, hours: [9, 12, 15, 18])
        let report = PredictionAccuracy.feedTimeReport(
            feeds: feeds, dateOfBirth: dob,
            nightStartMinute: nightStart, nightEndMinute: nightEnd,
            targetInterval: { _ in 3 * 3600 }, now: noon)
        XCTAssertNotNil(report)
        XCTAssertGreaterThan(report!.sampleCount, 10)
        XCTAssertLessThan(report!.statisticalMedianError, 15 * 60)
    }

    func testSleepDurationReportScoresConsistentNaps() {
        var sleeps: [(Date, Date?)] = []
        for day in 1...15 {
            for hour in [9, 14] {
                let start = at(daysAgo: day, hour: hour)
                sleeps.append((start, start.addingTimeInterval(50 * 60)))
            }
        }
        let report = PredictionAccuracy.sleepDurationReport(
            sleeps: sleeps, dateOfBirth: dob,
            nightStartMinute: nightStart, nightEndMinute: nightEnd, now: noon)
        XCTAssertNotNil(report)
        XCTAssertLessThan(report!.statisticalMedianError, 10 * 60)
        XCTAssertNil(report!.modelMedianError)   // sleep has no Phase 2 model
        XCTAssertFalse(report!.modelWins)
    }

    func testPromotionGateNeedsSamplesAndAMargin() {
        // Not enough model samples: no promotion, however good the number.
        XCTAssertFalse(AccuracyReport(sampleCount: 40, statisticalMedianError: 600,
                                      modelSampleCount: 5, modelMedianError: 60).modelWins)
        // Enough samples but inside the 5% noise margin: no promotion.
        XCTAssertFalse(AccuracyReport(sampleCount: 40, statisticalMedianError: 600,
                                      modelSampleCount: 30, modelMedianError: 580).modelWins)
        // Enough samples and clearly better: promoted.
        XCTAssertTrue(AccuracyReport(sampleCount: 40, statisticalMedianError: 600,
                                     modelSampleCount: 30, modelMedianError: 400).modelWins)
    }

    func testFeedTimeReportProducesModelChallengerScores() {
        // With deep history the walk-forward pass must actually train and
        // score the challenger, not just the champion.
        let feeds = metronomeFeeds(days: 25, hours: [8, 11, 14, 17])
        let report = PredictionAccuracy.feedTimeReport(
            feeds: feeds, dateOfBirth: dob,
            nightStartMinute: nightStart, nightEndMinute: nightEnd,
            targetInterval: { _ in 3 * 3600 }, now: noon)
        XCTAssertNotNil(report)
        XCTAssertGreaterThan(report!.modelSampleCount, 0)
        XCTAssertNotNil(report!.modelMedianError)
    }
}
