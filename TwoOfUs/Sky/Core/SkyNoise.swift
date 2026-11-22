import Foundation

/// The sky lab's hash and noise, bit for bit — "the same picture for the same
/// state, every time". Nothing in the sky is random: where a night's star
/// stands, how the hand wobbled a crest line, the slow drift that gathers his
/// stars into loose knots are all functions of whole numbers run through
/// these. So a star cast on this phone stands where the lab put it, and where
/// the other parent's phone puts it, only if these give the lab's numbers
/// exactly — not nearly: the star chart is order-dependent (each night takes
/// a place the earlier ones left free), and one different bit in one hash
/// moves every later star.
///
/// The lab is JavaScript, whose numbers are doubles and whose bitwise
/// operators work on 32-bit integers (`| 0`, `>>> 0`, `Math.imul`). Each
/// function here says which of the lab's it is; the arithmetic is written in
/// the lab's own order, because a sum taken in another order rounds
/// differently. Two files of the lab are ported: `lab/noise.js` (`hash2`,
/// `rng`, `noise2`, `fbm2`, `fbm1`) and `lab/nights.js` (`hash`); and, from
/// the sky itself (`skies/hill-painted.js`), its own lattice noise (`vn`,
/// `fb`). (JavaScript's `Math.round` and `Math.hypot`, which the skyline and
/// the star chart also need to the bit, are `SkyMath`'s.)
///
/// Pure: `SkyNoiseTests`, against thousands of values exported from the lab
/// (`SkyCoreFixturesStars`, by `design/sky-lab/tools/swift-fixtures/stars.mjs`).
enum SkyNoise {
    // MARK: Hashes

    /// A stable 0–1 hash of a night's number and a salt (`lab/nights.js`,
    /// `hash`): what seeds everything about one night — where its star is
    /// cast, how bright it is, how warm, how it twinkles.
    static func hash(_ n: Int, salt: Int = 0) -> Double {
        var h = (low32(n) &* 0x9e37_79b1) ^ ((low32(salt) &+ 0x85eb_ca6b) &* 0xc2b2_ae35)
        h ^= h >> 15
        h = h &* 0x2c1b_3c6d
        h ^= h >> 12
        h = h &* 0x297a_2d39
        h ^= h >> 15
        return Double(h) / two32
    }

    /// A stable 0–1 hash of two whole numbers and a seed (`lab/noise.js`,
    /// `hash2`): the value at a point of a lattice.
    static func hash2(_ x: Int, _ y: Int, seed: Int = 0) -> Double {
        unit(mixed(low32(x), low32(y), seed: seed))
    }

    /// A seeded run of 0–1 numbers (`lab/noise.js`, `rng`: mulberry32) — the
    /// tree is grown from one, so it is the same tree on every phone.
    struct Stream: Equatable {
        private var state: UInt32

        /// A run that starts from `seed` (the lab's `seed >>> 0`).
        init(seed: Int = 1) {
            state = SkyNoise.low32(seed)
        }

        /// The next number of the run.
        mutating func next() -> Double {
            state = state &+ 0x6d2b_79f5
            var t = state
            t = (t ^ (t >> 15)) &* (t | 1)
            t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
            return Double(t ^ (t >> 14)) / SkyNoise.two32
        }
    }

    // MARK: Noise

    /// Smooth value noise, 0–1 (`lab/noise.js`, `noise2`): the lattice's
    /// values, eased between with a quintic.
    static func noise(_ x: Double, _ y: Double, seed: Int = 0) -> Double {
        let xi = x.rounded(.down), yi = y.rounded(.down)
        let u = fade(x - xi), v = fade(y - yi)
        let a = unit(mixed(int32(xi), int32(yi), seed: seed))
        let b = unit(mixed(int32(xi + 1), int32(yi), seed: seed))
        let c = unit(mixed(int32(xi), int32(yi + 1), seed: seed))
        let d = unit(mixed(int32(xi + 1), int32(yi + 1), seed: seed))
        return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v
    }

    /// Fractal noise, 0–1 (`lab/noise.js`, `fbm2`): `octaves` layers, each
    /// `lacunarity` times as fine and `gain` as strong.
    static func fractal(_ x: Double, _ y: Double, octaves: Int = 5, gain: Double = 0.5,
                        lacunarity: Double = 2, seed: Int = 0) -> Double {
        var x = x, y = y
        var sum = 0.0, amp = 0.5, norm = 0.0
        for octave in 0..<max(octaves, 0) {
            sum += amp * noise(x, y, seed: seed + octave * 131)
            norm += amp
            x = x * lacunarity + 17.3
            y = y * lacunarity - 9.1
            amp *= gain
        }
        return sum / norm
    }

    /// The same along a line, for ridge lines and the like (`lab/noise.js`,
    /// `fbm1`).
    static func fractal(along x: Double, octaves: Int = 5, gain: Double = 0.5,
                        lacunarity: Double = 2, seed: Int = 0) -> Double {
        fractal(x, 0.5, octaves: octaves, gain: gain, lacunarity: lacunarity, seed: seed)
    }

    // MARK: The painted hill's own lattice

    /// The sky's own smooth noise, 0–1 (`hill-painted.js`, `vn`): a 256 ×
    /// 256 lattice that repeats, eased between with a smoothstep. The hand's
    /// wobble along a crest and the drift of his stars are both read from it.
    static func value(_ x: Double, _ y: Double) -> Double {
        let xf = x.rounded(.down), yf = y.rounded(.down)
        let fx = x - xf, fy = y - yf
        let xi = Int(int32(xf) & 255), yi = Int(int32(yf) & 255)
        let x1 = (xi + 1) & 255, y1 = (yi + 1) & 255
        let u = fx * fx * (3 - 2 * fx), v = fy * fy * (3 - 2 * fy)
        let a = Double(lattice[yi * latticeSide + xi]), b = Double(lattice[yi * latticeSide + x1])
        let c = Double(lattice[y1 * latticeSide + xi]), d = Double(lattice[y1 * latticeSide + x1])
        return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v
    }

    /// A few octaves of it, 0–1 (`hill-painted.js`, `fb`): each twice as fine
    /// and half as strong, and stepped aside so the octaves do not line up.
    static func drift(_ x: Double, _ y: Double, octaves: Int = 3) -> Double {
        var x = x, y = y
        var sum = 0.0, amp = 0.5, norm = 0.0
        for octave in 0..<max(octaves, 0) {
            let o = Double(octave)
            sum += amp * value(x + o * 17.3, y + o * 9.1)
            norm += amp
            x *= 2
            y *= 2
            amp *= 0.5
        }
        return sum / norm
    }

    // MARK: Private

    private static let two32 = 4_294_967_296.0
    private static let latticeSide = 256

    /// The sky's lattice: `hash2(x, y, 23)` at every point, kept as the lab
    /// keeps it — in single precision.
    private static let lattice: [Float] = {
        var out = [Float](repeating: 0, count: latticeSide * latticeSide)
        for y in 0..<latticeSide {
            for x in 0..<latticeSide {
                out[y * latticeSide + x] = Float(hash2(x, y, seed: 23))
            }
        }
        return out
    }()

    /// JavaScript's `n | 0`, as its 32 bits: a whole number wraps.
    private static func low32(_ n: Int) -> UInt32 {
        UInt32(truncatingIfNeeded: n)
    }

    /// JavaScript's `x | 0` of a number, as its 32 bits: cut toward zero,
    /// then wrapped.
    private static func int32(_ value: Double) -> UInt32 {
        guard value.isFinite else { return 0 }
        let whole = value.rounded(.towardZero).truncatingRemainder(dividingBy: two32)
        return UInt32(truncatingIfNeeded: Int64(whole))
    }

    /// `hash2`'s 32 bits.
    private static func mixed(_ x: UInt32, _ y: UInt32, seed: Int) -> UInt32 {
        var h = (x &* 0x27d4_eb2d) ^ (y &* 0x1656_67b1) ^ ((low32(seed) &+ 1) &* 0x9e37_79b1)
        h ^= h >> 15
        h = h &* 0x85eb_ca6b
        h ^= h >> 13
        h = h &* 0xc2b2_ae35
        h ^= h >> 16
        return h
    }

    private static func unit(_ h: UInt32) -> Double {
        Double(h) / two32
    }

    /// `noise2`'s ease between lattice points: the camera's quintic, but
    /// the lab's own lines of it — never held to 0 … 1, as `SkyMath.quintic`
    /// is, because a lattice value must come out to the bit.
    private static func fade(_ t: Double) -> Double {
        t * t * t * (t * (t * 6 - 15) + 10)
    }
}
