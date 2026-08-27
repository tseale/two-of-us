import Foundation

/// Champion/challenger referee between the statistical predictions and the
/// Phase 2 models. The statistic is always the champion; a model's number is
/// surfaced ONLY while the walk-forward evaluation says it has been
/// measurably more accurate on this baby's own recent history
/// (`AccuracyReport.modelWins`). Callers ask for a model prediction and get
/// nil in every other case — falling back to the statistic they already
/// computed.
///
/// The verdict + trained model are cached per (event count, calendar day):
/// the walk-forward pass costs ~10ms, fine once per logged event, absurd at
/// the Home screen's once-a-second tick.
@MainActor
final class PredictionArbiter {

    static let shared = PredictionArbiter()

    private struct CacheKey: Equatable {
        let eventCount: Int
        let day: Date
    }

    private var gapCache: (key: CacheKey, model: TrainedModel?)?
    private var amountCache: (key: CacheKey, model: TrainedModel?)?
    private let calendar = Calendar.current

    /// The model's next-feed date — nil unless the gap model currently beats
    /// the statistic. `feeds` is every live feed timestamp, any order.
    func modelNextFeed(lastFeed: Date, feeds: [Date], dateOfBirth: Date,
                       targetInterval: @escaping (Date) -> TimeInterval,
                       nightStartMinute: Int, nightEndMinute: Int,
                       now: Date = .now) -> Date? {
        let key = CacheKey(eventCount: feeds.count, day: calendar.startOfDay(for: now))
        if gapCache?.key != key {
            let report = PredictionAccuracy.feedTimeReport(
                feeds: feeds, dateOfBirth: dateOfBirth,
                nightStartMinute: nightStartMinute, nightEndMinute: nightEndMinute,
                targetInterval: targetInterval, now: now, calendar: calendar)
            let model = report?.modelWins == true
                ? PredictionModel.trainGapModel(feeds: feeds, dateOfBirth: dateOfBirth,
                                                nightStartMinute: nightStartMinute,
                                                nightEndMinute: nightEndMinute,
                                                now: now, calendar: calendar)
                : nil
            gapCache = (key, model)
        }
        guard let model = gapCache?.model else { return nil }
        let feedings = PredictionEngine.feedings(
            feeds: feeds, within: PredictionModel.trainingWindow, now: now)
        let previousGap: TimeInterval? = feedings.count >= 2
            ? feedings[feedings.count - 1].first.timeIntervalSince(feedings[feedings.count - 2].last)
            : nil
        let gap = PredictionModel.predictGap(
            model, lastFeed: lastFeed,
            previousGap: previousGap.flatMap { PredictionEngine.plausibleFeedGap.contains($0) ? $0 : nil },
            dateOfBirth: dateOfBirth, targetInterval: targetInterval(lastFeed),
            nightStartMinute: nightStartMinute, nightEndMinute: nightEndMinute,
            calendar: calendar)
        return lastFeed.addingTimeInterval(gap)
    }

    /// The model's bottle size for a feed at `reference` — nil unless the
    /// amount model currently beats the statistic.
    func modelOz(at reference: Date, feeds: [(timestamp: Date, oz: Double)], dateOfBirth: Date,
                 nightStartMinute: Int, nightEndMinute: Int,
                 now: Date = .now) -> Double? {
        let key = CacheKey(eventCount: feeds.count, day: calendar.startOfDay(for: now))
        if amountCache?.key != key {
            let report = PredictionAccuracy.feedAmountReport(
                feeds: feeds, dateOfBirth: dateOfBirth,
                nightStartMinute: nightStartMinute, nightEndMinute: nightEndMinute,
                now: now, calendar: calendar)
            let model = report?.modelWins == true
                ? PredictionModel.trainAmountModel(feeds: feeds, dateOfBirth: dateOfBirth,
                                                   nightStartMinute: nightStartMinute,
                                                   nightEndMinute: nightEndMinute,
                                                   now: now, calendar: calendar)
                : nil
            amountCache = (key, model)
        }
        guard let model = amountCache?.model else { return nil }
        let last = feeds.max { $0.timestamp < $1.timestamp }
        let gap = last.map { reference.timeIntervalSince($0.timestamp) }
        return PredictionModel.predictAmount(
            model, at: reference,
            gapSinceLastFeed: (gap ?? 0) > 0 ? gap : nil,
            lastOz: last?.oz, dateOfBirth: dateOfBirth,
            nightStartMinute: nightStartMinute, nightEndMinute: nightEndMinute,
            calendar: calendar)
    }
}
