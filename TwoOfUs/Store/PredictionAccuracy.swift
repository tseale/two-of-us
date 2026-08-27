import Foundation

/// Phase 4: was the prediction right? Answered retrospectively rather than
/// by snapshotting predictions at log time: the engine is pure and the event
/// history is complete, so "what would we have predicted just before this
/// event" is exactly reproducible — walk the trailing window, predict each
/// event from only the data that preceded it, and compare. That covers
/// events logged from every path (widget, Siri, the co-parent's synced-in
/// logs) that log-time capture would miss, backfills over the whole history
/// the moment the feature ships, and stores nothing.
///
/// The same walk-forward evaluation is the Phase 2 promotion gate: the model
/// trains only on data before each scored event (no leakage), and
/// `AccuracyReport.modelWins` is the ONLY thing allowed to put a model's
/// number in front of a parent.
struct AccuracyReport {
    let sampleCount: Int
    /// Median absolute error of the statistical champion — seconds for time
    /// and duration reports, ounces for amounts.
    let statisticalMedianError: Double
    let modelSampleCount: Int
    let modelMedianError: Double?

    /// Promotion: enough scored events, and meaningfully (not noise-level)
    /// better than the statistic. The 5% margin keeps the champion from
    /// flapping day to day.
    var modelWins: Bool {
        guard let model = modelMedianError,
              modelSampleCount >= PredictionAccuracy.promotionMinimumSamples else { return false }
        return model < statisticalMedianError * 0.95
    }
}

enum PredictionAccuracy {

    static let evaluationWindow: TimeInterval = 30 * 24 * 3600
    static let promotionMinimumSamples = 20

    // MARK: Feed timing

    static func feedTimeReport(
        feeds: [Date],
        dateOfBirth: Date,
        nightStartMinute: Int, nightEndMinute: Int,
        targetInterval: (Date) -> TimeInterval,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> AccuracyReport? {
        // All feedings ever passed in — history beyond the window is the
        // training/median data for the early scored events.
        let feedings = PredictionEngine.feedings(feeds: feeds, within: .greatestFiniteMagnitude, now: now)
        let sorted = feeds.sorted()
        var statErrors: [Double] = []
        var modelErrors: [Double] = []
        var previousGap: TimeInterval?
        for (a, b) in zip(feedings, feedings.dropFirst()) {
            let gap = b.first.timeIntervalSince(a.last)
            defer { previousGap = PredictionEngine.plausibleFeedGap.contains(gap) ? gap : nil }
            guard PredictionEngine.plausibleFeedGap.contains(gap),
                  b.first > now.addingTimeInterval(-evaluationWindow) else { continue }
            let prior = Array(sorted.prefix { $0 <= a.last })

            let stat = PredictionEngine.nextFeed(
                lastFeed: a.last, feeds: prior,
                targetInterval: targetInterval(a.last),
                nightStartMinute: nightStartMinute, nightEndMinute: nightEndMinute,
                now: a.last, calendar: calendar)
            guard stat.confidence != .low else { continue }
            statErrors.append(abs(stat.date.timeIntervalSince(b.first)))

            if let model = PredictionModel.trainGapModel(
                feeds: prior, dateOfBirth: dateOfBirth,
                nightStartMinute: nightStartMinute, nightEndMinute: nightEndMinute,
                now: a.last, calendar: calendar) {
                let predicted = PredictionModel.predictGap(
                    model, lastFeed: a.last, previousGap: previousGap,
                    dateOfBirth: dateOfBirth, targetInterval: targetInterval(a.last),
                    nightStartMinute: nightStartMinute, nightEndMinute: nightEndMinute,
                    calendar: calendar)
                modelErrors.append(abs(a.last.addingTimeInterval(predicted).timeIntervalSince(b.first)))
            }
        }
        return report(statErrors: statErrors, modelErrors: modelErrors)
    }

    // MARK: Feed amounts

    static func feedAmountReport(
        feeds: [(timestamp: Date, oz: Double)],
        dateOfBirth: Date,
        nightStartMinute: Int, nightEndMinute: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> AccuracyReport? {
        let sorted = feeds.sorted { $0.timestamp < $1.timestamp }
        var statErrors: [Double] = []
        var modelErrors: [Double] = []
        for (index, feed) in sorted.enumerated() {
            guard feed.timestamp > now.addingTimeInterval(-evaluationWindow),
                  PredictionEngine.plausibleOz.contains(feed.oz) else { continue }
            let previous = index > 0 ? sorted[index - 1] : nil
            let gap = previous.map { feed.timestamp.timeIntervalSince($0.timestamp) }
            if let gap, gap < PredictionEngine.feedClusterGap { continue }   // top-off, same hunger
            let prior = Array(sorted.prefix(index))

            let stat = PredictionEngine.feedAmount(
                feeds: prior, ageInDays: WakeWindow.ageInDays(dateOfBirth: dateOfBirth,
                                                              now: feed.timestamp, calendar: calendar),
                at: feed.timestamp,
                nightStartMinute: nightStartMinute, nightEndMinute: nightEndMinute,
                now: feed.timestamp, calendar: calendar)
            guard stat.confidence != .low else { continue }
            statErrors.append(abs(stat.oz - feed.oz))

            if let model = PredictionModel.trainAmountModel(
                feeds: prior, dateOfBirth: dateOfBirth,
                nightStartMinute: nightStartMinute, nightEndMinute: nightEndMinute,
                now: feed.timestamp, calendar: calendar) {
                let predicted = PredictionModel.predictAmount(
                    model, at: feed.timestamp,
                    gapSinceLastFeed: gap, lastOz: previous?.oz,
                    dateOfBirth: dateOfBirth,
                    nightStartMinute: nightStartMinute, nightEndMinute: nightEndMinute,
                    calendar: calendar)
                modelErrors.append(abs(predicted - feed.oz))
            }
        }
        return report(statErrors: statErrors, modelErrors: modelErrors)
    }

    // MARK: Sleep durations (statistical only — no Phase 2 model for sleep)

    static func sleepDurationReport(
        sleeps: [(startedAt: Date, endedAt: Date?)],
        dateOfBirth: Date,
        nightStartMinute: Int, nightEndMinute: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> AccuracyReport? {
        let sorted = sleeps.sorted { $0.startedAt < $1.startedAt }
        var statErrors: [Double] = []
        for (index, sleep) in sorted.enumerated() {
            guard let end = sleep.endedAt,
                  sleep.startedAt > now.addingTimeInterval(-evaluationWindow) else { continue }
            let actual = end.timeIntervalSince(sleep.startedAt)
            let night = WakeWindow.isNight(sleep.startedAt, startMinute: nightStartMinute,
                                           endMinute: nightEndMinute, calendar: calendar)
            let plausible = night ? PredictionEngine.plausibleNightStretch : PredictionEngine.plausibleNap
            guard plausible.contains(actual) else { continue }

            let prediction = PredictionEngine.sleepDuration(
                startingAt: sleep.startedAt,
                sleeps: Array(sorted.prefix(index)),
                ageInDays: WakeWindow.ageInDays(dateOfBirth: dateOfBirth,
                                                now: sleep.startedAt, calendar: calendar),
                nightStartMinute: nightStartMinute, nightEndMinute: nightEndMinute,
                now: sleep.startedAt, calendar: calendar)
            guard prediction.confidence != .low else { continue }
            statErrors.append(abs(prediction.duration - actual))
        }
        return report(statErrors: statErrors, modelErrors: [])
    }

    // MARK: Shared

    private static func report(statErrors: [Double], modelErrors: [Double]) -> AccuracyReport? {
        guard let statMedian = WakeWindow.median(statErrors) else { return nil }
        return AccuracyReport(
            sampleCount: statErrors.count,
            statisticalMedianError: statMedian,
            modelSampleCount: modelErrors.count,
            modelMedianError: WakeWindow.median(modelErrors))
    }
}
