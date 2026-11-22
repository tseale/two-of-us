import Foundation

/// The lab's arithmetic: the few small functions every rule of the painted
/// hill is written in — a number held to 0 … 1, eased, mixed, rounded, a
/// distance measured.
///
/// They are in one place for one reason. The sky is the sky lab's to the
/// number (its colours to twelve places, his stars' places to the bit), and
/// that holds only while each of these is the lab's own function, in the
/// lab's own order of operations: `clamp01`, `smoothstep` and `lerp` from
/// design/sky-lab/lab/oklab.js (the one copy the sky module, air.js,
/// season.js and presence.js all import), the camera's ease from
/// skies/hill-painted.js (`lookOf`), and the two places where JavaScript's
/// arithmetic is not Swift's — `Math.round` and `Math.hypot`. The lab has
/// one of each, and so has the app: with a copy in every type, a change to
/// one would move the tree's colour and leave the air's where it was.
///
/// Pure: `SkyMathTests`, against the lab's own answers
/// (`SkyCoreFixturesColour`, `SkyCoreFixturesStars`).
enum SkyMath {
    // MARK: Held, eased, mixed

    /// `x` held to 0 … 1 (the lab's `clamp01`). Not a number: 0.
    static func clamped(_ x: Double) -> Double {
        min(1, max(0, x))
    }

    /// 0 at `a`, 1 at `b`, eased between and held outside (the lab's
    /// `smoothstep`): t²(3 − 2t), still at both ends. `a` may be the greater
    /// of the two: the amount then falls as `x` rises.
    static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = clamped((x - a) / (b - a))
        return t * t * (3 - 2 * t)
    }

    /// `a` toward `b` by `t`, NOT held to 0 … 1 (the lab's `lerp`): the
    /// painter sometimes means a little past an end.
    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    /// The camera's ease, 0 → 1 over 0 … 1: t³(6t² − 15t + 10), still at
    /// both ends in speed and in acceleration, so the view leaves rest and
    /// comes to rest without a start or a stop (skies/hill-painted.js,
    /// `lookOf`). Its fastest is 1.875 times the average, half way.
    ///
    /// Held to 0 … 1 on the way in and on the way out: a hair short of the
    /// end, the polynomial's own arithmetic rounds to a hair past it, and a
    /// `look` of more than 1 is not a pose.
    static func quintic(_ t: Double) -> Double {
        let t = clamped(t)
        return clamped(t * t * t * (t * (t * 6 - 15) + 10))
    }

    // MARK: Where JavaScript's arithmetic is not Swift's

    /// JavaScript's `Math.round`: to the nearest whole number, a half going
    /// UP (−2.5 → −2), where Swift's `rounded()` sends it away from zero.
    /// The land's height is looked up by it, and a crest half a point to one
    /// side is another crest; a plane comes to rest on the pixel grid by it.
    static func round(_ value: Double) -> Double {
        let down = value.rounded(.down)
        return value - down >= 0.5 ? down + 1 : down
    }

    /// The distance the lab measures with (`Math.hypot`, as the lab's
    /// browser computes it: the two legs scaled by the larger, their squares
    /// summed with a correction, the root scaled back). The system's `hypot`
    /// may differ from it in the last bit — and from one system to another —
    /// and "never closer than 5.6 pt" is decided by a comparison.
    static func hypot(_ a: Double, _ b: Double) -> Double {
        let x = abs(a), y = abs(b)
        let largest = max(x, y)
        if largest == .infinity { return .infinity }
        if a.isNaN || b.isNaN { return .nan }
        if largest == 0 { return 0 }
        var sum = 0.0, compensation = 0.0
        for leg in [x, y] {
            let n = leg / largest
            let summand = n * n - compensation
            let preliminary = sum + summand
            compensation = (preliminary - sum) - summand
            sum = preliminary
        }
        return sum.squareRoot() * largest
    }
}
