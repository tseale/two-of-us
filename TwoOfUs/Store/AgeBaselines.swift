import Foundation

/// Published age-appropriate ranges the prediction engine falls back on and
/// clamps into — the same "age sets the range, his own data positions him
/// inside it" model `WakeWindow` established for wake windows, extended to
/// bottle sizes and sleep durations.
///
/// These are the broad ranges infant-care references commonly agree on for
/// formula-fed babies; real babies vary, and nothing here is medical advice
/// (the same line the app holds in `BabyIntelligence` and `WakeWindow`).
/// `upperBoundDays` is exclusive, mirroring `WakeWindow.Band`.
enum AgeBaselines {

    struct Band {
        let upperBoundDays: Int
        let range: ClosedRange<Double>

        var midpoint: Double { (range.lowerBound + range.upperBound) / 2 }
    }

    private static let minute = 60.0
    private static let hour = 3600.0

    /// Ounces per bottle. Newborn stomachs are tiny; by half a year a bottle
    /// plateaus around 6–8 oz as solids start carrying some of the load.
    static let ozPerFeed: [Band] = [
        Band(upperBoundDays: 14,   range: 1.0...3.0),   // first two weeks
        Band(upperBoundDays: 28,   range: 2.0...4.0),   // 2–4 weeks
        Band(upperBoundDays: 84,   range: 3.0...5.0),   // 1–3 months
        Band(upperBoundDays: 168,  range: 4.0...6.0),   // 3–6 months
        Band(upperBoundDays: 365,  range: 5.0...8.0),   // 6–12 months
        Band(upperBoundDays: .max, range: 5.0...8.0),   // 12 months+
    ]

    /// Daytime nap length. Newborn naps are wildly variable (catnap to two
    /// hours); they consolidate and shorten in count as the baby grows.
    static let napDuration: [Band] = [
        Band(upperBoundDays: 84,   range: 30 * minute...2 * hour),
        Band(upperBoundDays: 168,  range: 45 * minute...2 * hour),
        Band(upperBoundDays: 365,  range: 1 * hour...2 * hour),
        Band(upperBoundDays: .max, range: 1 * hour...2.5 * hour),
    ]

    /// A single overnight stretch (sleep start → wake for a feed), NOT total
    /// night sleep — it's what "when will he wake up" means at 11 PM.
    static let nightStretch: [Band] = [
        Band(upperBoundDays: 28,   range: 2 * hour...4 * hour),
        Band(upperBoundDays: 84,   range: 3 * hour...6 * hour),
        Band(upperBoundDays: 168,  range: 4 * hour...8 * hour),
        Band(upperBoundDays: 365,  range: 6 * hour...11 * hour),
        Band(upperBoundDays: .max, range: 8 * hour...12 * hour),
    ]

    /// The band for an age in days. Negative ages (a due date that hasn't
    /// arrived) take the first band, same rule as `WakeWindow.ageBand`.
    static func band(_ bands: [Band], ageInDays: Int) -> Band {
        let days = max(0, ageInDays)
        return bands.first { days < $0.upperBoundDays } ?? bands[bands.count - 1]
    }
}
