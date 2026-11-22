import Foundation

/// The hours a night can hold: from its evening until first light.
///
/// - `evening` is 6 pm on the night's own day: from here on a sleep can be
///   the night's.
/// - `lastStart` is the end of that welcome: 4 am, or first light where it
///   comes sooner. A sleep begun at 5 am is the morning's.
/// - `firstLight` is the sun coming up through −7° — the night is over, and
///   Home is back on the hill. Where the sun never gets that low (a northern
///   midsummer) or never that high (a polar winter) it is `lastStart`'s 4 am.
///
/// Built by `NightRule.frame`; the hours themselves are `NightRule.Policy`'s.
struct NightFrame: Equatable {
    let evening: Date
    let lastStart: Date
    let firstLight: Date

    /// Whether `date` is inside the night's hours: from the evening up to,
    /// and not including, first light.
    func contains(_ date: Date) -> Bool {
        evening <= date && date < firstLight
    }
}

/// Everything the sky needs to know about tonight, derived afresh from the
/// clock, the sun and the sleep log each time it is asked (`NightRule.state`).
/// Nothing here is stored, so Home opened cold at 3 am is already looking
/// up, and Home opened at 7 am is on the hill.
///
/// One fact drives the camera and tonight's star: THE NIGHT HAS BEGUN —
/// `hasBegun` — true from the moment tonight's night sleep first starts, by
/// any means, until first light, whether he is asleep or awake.
struct NightState: Equatable {
    /// The night whose hours we are in; nil by day (from first light until
    /// the evening).
    let frame: NightFrame?
    /// The sleep that began the night: the earliest night sleep of this
    /// frame. Nil while the night has not begun. It is here for its start
    /// time (was it just now, or hours ago?), never to be compared by id.
    let begunBy: SleepSpan?
    /// The sleep running now, if one is: the room's dimming goes by it.
    /// Independent of `hasBegun` — a night sleep still running after first
    /// light is the day's picture, dimmed.
    let running: SleepKind?

    /// The night has begun: the view is up and tonight's star is lit.
    var hasBegun: Bool { begunBy != nil }
}
