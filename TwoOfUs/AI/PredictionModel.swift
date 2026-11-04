import Foundation

/// Phase 2: personal models trained on-device from the baby's own history —
/// a ridge regressor per prediction (`RidgeRegression`), fed engineered
/// features the medians can't see (time-of-day shape, age trend, the
/// previous gap). Everything here is pure; training on this data size is
/// microseconds, so models are fit on demand and never persisted.
///
/// A model NEVER speaks to the user directly: `PredictionArbiter` runs it as
/// the challenger against the statistical champion, and only the walk-forward
/// accuracy evaluation (`PredictionAccuracy`) can promote it. If it doesn't
/// measurably win, it doesn't ship — the statistic stays.
struct TrainedModel: Equatable {
    let coefficients: [Double]
    let sampleCount: Int
}

enum PredictionModel {

    /// Below this there isn't enough signal to fit seven weights honestly.
    static let minimumTrainingSamples = 24
    /// Models get more history than the statistic's 14 days — a regressor
    /// with an age feature can use older data without going stale the way a
    /// raw median would.
    static let trainingWindow: TimeInterval = 45 * 24 * 3600

    private static let hour = 3600.0

    // MARK: Features

    /// Time-of-day as a point on the circle, so 11:50 PM and 12:10 AM are
    /// neighbors rather than opposite ends of a line.
    private static func clock(_ date: Date, calendar: Calendar) -> (sin: Double, cos: Double, minuteOfDay: Int) {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let angle = 2 * Double.pi * Double(minute) / 1440
        return (Foundation.sin(angle), Foundation.cos(angle), minute)
    }

    /// The calendar-derived part of a feature row — everything that depends
    /// only on the row's own instant (with the fixed birth date and night
    /// window). Split out so the walk-forward evaluation, which retrains a
    /// model per scored event over heavily overlapping windows, can compute
    /// each instant's calendar math once per report instead of once per
    /// retrain. Values are bit-identical to computing them inline.
    struct InstantFeatures {
        let sin: Double
        let cos: Double
        let isNight: Double
        let ageHundredDays: Double
    }

    static func instantFeatures(_ date: Date, dateOfBirth: Date,
                                nightStartMinute: Int, nightEndMinute: Int,
                                calendar: Calendar = .current) -> InstantFeatures {
        let c = clock(date, calendar: calendar)
        let night = WakeWindow.isNight(date, startMinute: nightStartMinute,
                                       endMinute: nightEndMinute, calendar: calendar)
        let age = Double(WakeWindow.ageInDays(dateOfBirth: dateOfBirth, now: date, calendar: calendar))
        return InstantFeatures(sin: c.sin, cos: c.cos, isNight: night ? 1 : 0, ageHundredDays: age / 100)
    }

    /// Gap features from the feeding's anchor bottle:
    /// [bias, sin(t), cos(t), isNight, age/100d, prevGapHours, hasPrevGap].
    static func gapFeatures(anchor: Date, previousGap: TimeInterval?,
                            dateOfBirth: Date,
                            nightStartMinute: Int, nightEndMinute: Int,
                            calendar: Calendar = .current) -> [Double] {
        gapFeatures(instantFeatures(anchor, dateOfBirth: dateOfBirth,
                                    nightStartMinute: nightStartMinute, nightEndMinute: nightEndMinute,
                                    calendar: calendar),
                    previousGap: previousGap)
    }

    static func gapFeatures(_ f: InstantFeatures, previousGap: TimeInterval?) -> [Double] {
        [1, f.sin, f.cos, f.isNight, f.ageHundredDays,
         previousGap.map { min($0, 8 * hour) / hour } ?? 0,
         previousGap == nil ? 0 : 1]
    }

    /// Amount features for a bottle at `reference`:
    /// [bias, sin(t), cos(t), isNight, age/100d, gapHours, hasGap, lastOz, hasLastOz].
    static func amountFeatures(at reference: Date, gapSinceLastFeed: TimeInterval?,
                               lastOz: Double?,
                               dateOfBirth: Date,
                               nightStartMinute: Int, nightEndMinute: Int,
                               calendar: Calendar = .current) -> [Double] {
        amountFeatures(instantFeatures(reference, dateOfBirth: dateOfBirth,
                                       nightStartMinute: nightStartMinute, nightEndMinute: nightEndMinute,
                                       calendar: calendar),
                       gapSinceLastFeed: gapSinceLastFeed, lastOz: lastOz)
    }

    static func amountFeatures(_ f: InstantFeatures, gapSinceLastFeed: TimeInterval?,
                               lastOz: Double?) -> [Double] {
        [1, f.sin, f.cos, f.isNight, f.ageHundredDays,
         gapSinceLastFeed.map { min($0, 8 * hour) / hour } ?? 0,
         gapSinceLastFeed == nil ? 0 : 1,
         lastOz ?? 0,
         lastOz == nil ? 0 : 1]
    }

    // MARK: Training

    /// Fits the feed-gap regressor from consecutive plausible feedings.
    /// Target is the gap in hours from a feeding's last bottle to the next
    /// feeding's first — the same measurement the statistic medians.
    /// `featuresAt` lets `PredictionAccuracy` share one per-instant memo of
    /// the calendar features across retrains; nil computes them inline.
    static func trainGapModel(feeds: [Date], dateOfBirth: Date,
                              nightStartMinute: Int, nightEndMinute: Int,
                              now: Date = .now,
                              calendar: Calendar = .current,
                              featuresAt: ((Date) -> InstantFeatures)? = nil) -> TrainedModel? {
        let feedings = PredictionEngine.feedings(feeds: feeds, within: trainingWindow, now: now)
        var rows: [[Double]] = []
        var targets: [Double] = []
        var previousGap: TimeInterval?
        for (a, b) in zip(feedings, feedings.dropFirst()) {
            let gap = b.first.timeIntervalSince(a.last)
            defer { previousGap = PredictionEngine.plausibleFeedGap.contains(gap) ? gap : nil }
            guard PredictionEngine.plausibleFeedGap.contains(gap) else { continue }
            let f = featuresAt?(a.last)
                ?? instantFeatures(a.last, dateOfBirth: dateOfBirth,
                                   nightStartMinute: nightStartMinute, nightEndMinute: nightEndMinute,
                                   calendar: calendar)
            rows.append(gapFeatures(f, previousGap: previousGap))
            targets.append(gap / hour)
        }
        guard rows.count >= minimumTrainingSamples,
              let w = RidgeRegression.fit(rows: rows, targets: targets) else { return nil }
        return TrainedModel(coefficients: w, sampleCount: rows.count)
    }

    /// Fits the amount regressor from each feeding's first bottle (top-offs
    /// would double-count the same hunger). `featuresAt` is the same optional
    /// per-instant memo hook as in `trainGapModel`.
    static func trainAmountModel(feeds: [(timestamp: Date, oz: Double)], dateOfBirth: Date,
                                 nightStartMinute: Int, nightEndMinute: Int,
                                 now: Date = .now,
                                 calendar: Calendar = .current,
                                 featuresAt: ((Date) -> InstantFeatures)? = nil) -> TrainedModel? {
        let usable = feeds
            .filter { $0.timestamp > now.addingTimeInterval(-trainingWindow) && $0.timestamp <= now
                && PredictionEngine.plausibleOz.contains($0.oz) }
            .sorted { $0.timestamp < $1.timestamp }
        var rows: [[Double]] = []
        var targets: [Double] = []
        var previous: (timestamp: Date, oz: Double)?
        for feed in usable {
            defer { previous = feed }
            let gap = previous.map { feed.timestamp.timeIntervalSince($0.timestamp) }
            if let gap, gap < PredictionEngine.feedClusterGap { continue }   // top-off
            let f = featuresAt?(feed.timestamp)
                ?? instantFeatures(feed.timestamp, dateOfBirth: dateOfBirth,
                                   nightStartMinute: nightStartMinute, nightEndMinute: nightEndMinute,
                                   calendar: calendar)
            rows.append(amountFeatures(f, gapSinceLastFeed: gap, lastOz: previous?.oz))
            targets.append(feed.oz)
        }
        guard rows.count >= minimumTrainingSamples,
              let w = RidgeRegression.fit(rows: rows, targets: targets) else { return nil }
        return TrainedModel(coefficients: w, sampleCount: rows.count)
    }

    // MARK: Prediction

    /// The model's next-feed gap, clamped by the SAME policy as the
    /// statistic (the target band ∩ plausibility) — a challenger gets no
    /// license the champion doesn't have.
    static func predictGap(_ model: TrainedModel, lastFeed: Date, previousGap: TimeInterval?,
                           dateOfBirth: Date, targetInterval: TimeInterval,
                           nightStartMinute: Int, nightEndMinute: Int,
                           calendar: Calendar = .current) -> TimeInterval {
        let raw = RidgeRegression.predict(
            coefficients: model.coefficients,
            features: gapFeatures(anchor: lastFeed, previousGap: previousGap,
                                  dateOfBirth: dateOfBirth,
                                  nightStartMinute: nightStartMinute, nightEndMinute: nightEndMinute,
                                  calendar: calendar)) * hour
        let lower = max(PredictionEngine.plausibleFeedGap.lowerBound, targetInterval * 0.6)
        let upper = min(PredictionEngine.plausibleFeedGap.upperBound, max(lower, targetInterval * 1.5))
        return min(max(raw, lower), upper)
    }

    /// The model's bottle size, clamped to the same stretched age band as
    /// the statistic and rounded to quarter ounces.
    static func predictAmount(_ model: TrainedModel, at reference: Date,
                              gapSinceLastFeed: TimeInterval?, lastOz: Double?,
                              dateOfBirth: Date,
                              nightStartMinute: Int, nightEndMinute: Int,
                              calendar: Calendar = .current) -> Double {
        let raw = RidgeRegression.predict(
            coefficients: model.coefficients,
            features: amountFeatures(at: reference, gapSinceLastFeed: gapSinceLastFeed,
                                     lastOz: lastOz, dateOfBirth: dateOfBirth,
                                     nightStartMinute: nightStartMinute, nightEndMinute: nightEndMinute,
                                     calendar: calendar))
        let ageInDays = WakeWindow.ageInDays(dateOfBirth: dateOfBirth, now: reference, calendar: calendar)
        let band = AgeBaselines.band(AgeBaselines.ozPerFeed, ageInDays: ageInDays)
        let clamp = max(0.5, band.range.lowerBound - 1.5)...(band.range.upperBound + 1.5)
        let clamped = min(max(raw, clamp.lowerBound), clamp.upperBound)
        return (clamped * 4).rounded() / 4
    }
}
