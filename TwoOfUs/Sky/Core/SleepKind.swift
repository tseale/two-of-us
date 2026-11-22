import Foundation

/// What a running sleep is to the room: the night's sleep dims it all the
/// way, a nap less. The one kind the whole sky shares — `NightRule` says
/// which a running sleep is (`NightState.running`), the moment eases the
/// room toward its depth (`Moment.depth`), and the palette is painted at
/// that depth (`HillPalette`).
///
/// The two depths are the lab's (lab/presence.js, `SLEEP_DEPTH`), held to
/// its own numbers in `MomentTests`.
enum SleepKind: Equatable {
    case night
    case nap

    /// How far this sleep dims the room, 0 … 1. The dimming never jumps: it
    /// eases in from 0 when the sleep starts and, when he wakes, eases out
    /// from this.
    var depth: Double {
        switch self {
        case .night: return 1
        case .nap: return 0.45
        }
    }
}
