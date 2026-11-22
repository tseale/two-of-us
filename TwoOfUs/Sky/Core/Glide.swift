import Foundation

/// A value on its way somewhere: where it started, where it is going, and
/// the ease that takes it there. The camera's `look` and the room's `depth`
/// are each one of these.
///
/// It exists for one promise of the design — NO JOIN MAY JUMP. The lab's
/// state carries one event at a time, with each value a function of that
/// event's age, so an event arriving during another snaps (the Duo opening
/// mid-rise). Here a value has a target and a current value instead: a
/// change of target eases from wherever the value is at that instant
/// (`retargeted`), so the first frame after a change is the frame before it.
///
/// Time is data: nothing here runs. `value(at:)` is a pure function of the
/// clock it is handed, so the same glide gives the same frame to both of the
/// spread's sky views. Tested in `GlideTests`, against the lab's own curves.
struct Glide: Equatable {
    /// The shape of the ease, 0 → 1 over 0 … 1.
    enum Curve: Equatable {
        /// The camera's: t³(6t² − 15t + 10), still at both ends in speed and
        /// in acceleration (skies/hill-painted.js, `lookOf`). Its fastest is
        /// 1.875 times the average, half way.
        case quintic
        /// The room's and every dissolve's: t²(3 − 2t) (lab/oklab.js,
        /// `smoothstep`; lab/presence.js, `roomDepth`).
        case smoothstep

        /// How far along it is at `t`, 0 … 1 of its time: held inside
        /// 0 … 1 (`SkyMath.quintic`, `SkyMath.smoothstep`).
        func eased(_ t: Double) -> Double {
            switch self {
            case .quintic: return SkyMath.quintic(t)
            case .smoothstep: return SkyMath.smoothstep(0, 1, t)
            }
        }
    }

    /// The value until `start`.
    let from: Double
    /// The target: the value from `start + duration` on.
    let to: Double
    /// When the value begins to move (a retarget's moment, plus any wait).
    let start: Date
    let duration: TimeInterval
    let curve: Curve

    /// A value at rest: it is `value`, and is going nowhere.
    static func resting(at value: Double) -> Glide {
        Glide(from: value, to: value, start: .distantPast, duration: 0, curve: .quintic)
    }

    /// When it arrives.
    var end: Date { start.addingTimeInterval(duration) }

    /// Whether it has arrived by `now` — nothing left to draw at 60. True
    /// only where `value(at: now)` is already the target, by the same two
    /// comparisons `value` makes: a cut (no duration) asked at its own
    /// instant still shows the frame before, so it has one more frame to
    /// draw and is not resting until then. The driver stops its clock on
    /// this; said a frame early, the old pose would stand until the next
    /// minute's tick.
    func isResting(at now: Date) -> Bool {
        let elapsed = now.timeIntervalSince(start)
        return from == to || (elapsed > 0 && elapsed >= duration)
    }

    /// The value at `now`: `from` until it starts, `to` once it has
    /// arrived, and never outside the two on the way.
    func value(at now: Date) -> Double {
        Glide.value(from: from, to: to, elapsed: now.timeIntervalSince(start), duration: duration,
                    curve: curve)
    }

    /// A glide's arithmetic, for a clock that counts seconds instead of
    /// dates: the value `elapsed` seconds after it begins to move. The
    /// moment's table is written in ages, and reads its `look` through this
    /// (`SkyEvent.Move.look`), so the table and a running glide cannot give
    /// two answers for the same instant.
    static func value(from: Double, to: Double, elapsed: TimeInterval, duration: TimeInterval,
                      curve: Curve) -> Double {
        if elapsed <= 0 { return from }
        if elapsed >= duration { return to }
        let value = from + (to - from) * curve.eased(elapsed / duration)
        return min(max(value, min(from, to)), max(from, to))
    }

    /// The same value given a new target at `now`: it holds what it has for
    /// `delay` seconds, then eases to `target` over `duration`. Whatever it
    /// was doing, it starts from where it is — continuous in value, never a
    /// jump.
    ///
    /// Given the target it already has, it is left alone, to run on at its
    /// own pace: a second sleep the same night, or the Duo opening while the
    /// view is still rising, must not restart the rise.
    func retargeted(to target: Double, at now: Date, over duration: TimeInterval,
                    after delay: TimeInterval = 0, curve: Curve = .quintic) -> Glide {
        if target == to { return self }
        return Glide(from: value(at: now), to: target, start: now.addingTimeInterval(max(0, delay)),
                     duration: max(0, duration), curve: curve)
    }
}
