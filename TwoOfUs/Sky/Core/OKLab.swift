import Foundation

/// A colour in OKLab: the space the painted hill is mixed in, so that the
/// sky's blue can go to its orange through rose and lilac and never through
/// grey-green, and so that "lighter", "quieter" and "the same hue" are each
/// one number.
///
/// - `lightness` is 0 for black and 1 for white (the lab's `L`). The air
///   table writes lights above 1 and lets `srgb` bring them back.
/// - `a` and `b` are the two colour axes; their length is the `chroma`,
///   their angle the `hue`.
///
/// A port, number for number, of the sky lab's own colour maths: design/
/// sky-lab/lab/oklab.js (the lab's) and the colour half of skies/
/// hill-painted/air.js with `heldTo` from skies/hill-painted.js (the painted
/// hill's). `OKLabTests` holds every function here against samples exported
/// from those modules (`SkyCoreFixturesColour`). Foundation only: turning a
/// colour into a `Color` or a pixel is the renderer's business.
struct OKLab: Equatable {
    var lightness: Double
    var a: Double
    var b: Double

    init(lightness: Double, a: Double, b: Double) {
        self.lightness = lightness
        self.a = a
        self.b = b
    }

    // MARK: Value, chroma, hue

    /// A colour from its lightness, chroma and hue IN DEGREES — the way the
    /// air table is written (`lch` in air.js): 40° an ember, 90° a pale
    /// gold, 262° the night's blue.
    init(lightness: Double, chroma: Double, hueDegrees: Double) {
        // (The lab divides by 180/π; the same division here, so the two
        // agree to the last bit and not only to the eye.)
        let angle = hueDegrees / (180 / Double.pi)
        self.init(lightness: lightness, a: chroma * cos(angle), b: chroma * sin(angle))
    }

    /// A colour from its lightness, chroma and hue in RADIANS (the lab's
    /// OKLCH, `fromOklch` before it goes back to sRGB).
    init(lightness: Double, chroma: Double, hue: Double) {
        self.init(lightness: lightness, a: chroma * cos(hue), b: chroma * sin(hue))
    }

    /// How much colour it has: 0 is a grey. (Measured as the lab measures:
    /// `toOklch` takes it with `Math.hypot`.)
    var chroma: Double { SkyMath.hypot(a, b) }

    /// Which colour, in radians from the `a` axis, −π … π (`toOklch`). A
    /// grey's hue means nothing.
    var hue: Double { atan2(b, a) }

    // MARK: To and from the display

    /// A colour as a display takes it: red, green and blue, each 0 … 1,
    /// gamma-encoded sRGB — the lab's `{ r, g, b }`.
    struct SRGB: Equatable {
        var red: Double
        var green: Double
        var blue: Double

        init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        /// From 0xRRGGBB (the lab's `hex`).
        init(hex: UInt32) {
            self.init(red: Double((hex >> 16) & 0xFF) / 255,
                      green: Double((hex >> 8) & 0xFF) / 255,
                      blue: Double(hex & 0xFF) / 255)
        }

        /// The three as eight-bit levels, 0 … 255, each held to 0 … 1 and
        /// rounded to the nearest (a half goes up): what the lab's `css`
        /// hands its canvas, and so the colour a still of the mockup
        /// really shows.
        var levels: [Int] {
            [red, green, blue].map { Int((SkyMath.clamped($0) * 255).rounded(.toNearestOrAwayFromZero)) }
        }

        /// The perceptual mix: `self` toward `other` by `t` (held to
        /// 0 … 1), straight through OKLab and back by the lab's own fit —
        /// so blue to orange passes through rose and lilac (`mixOk`).
        func mixed(with other: SRGB, by t: Double) -> SRGB {
            OKLab(self).mixed(with: OKLab(other), by: SkyMath.clamped(t)).srgb(.skyLab)
        }

        /// The colour at `x` along `stops` (positions ascending), mixed in
        /// OKLab between the two it falls between (`rampOk`). At or beyond
        /// an end it is that end's colour, untouched.
        static func ramp(_ stops: [(at: Double, colour: SRGB)], at x: Double) -> SRGB {
            guard let first = stops.first, let last = stops.last else { return SRGB(red: 0, green: 0, blue: 0) }
            if x <= first.at { return first.colour }
            for index in 0..<(stops.count - 1) {
                let from = stops[index]
                let to = stops[index + 1]
                if x <= to.at {
                    let t = to.at > from.at ? (x - from.at) / (to.at - from.at) : 0
                    return from.colour.mixed(with: to.colour, by: t)
                }
            }
            return last.colour
        }
    }

    /// The OKLab of a display colour (`toOklab`).
    init(_ colour: SRGB) {
        let r = OKLab.linear(colour.red)
        let g = OKLab.linear(colour.green)
        let b = OKLab.linear(colour.blue)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        self.init(lightness: 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
                  a: 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
                  b: 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s)
    }

    /// Whose hand brings a colour that no display can show back into sRGB.
    /// Both give up chroma and never hue: an ember too bright to show comes
    /// back a paler ember, not an orange. They differ only in how finely,
    /// and in what they make of a light above white.
    enum Fitting {
        /// The painted hill's (`toRgb` in air.js): the lightness is first
        /// held to 0 … 1, then the chroma is halved in on fourteen times.
        /// Every colour the sky paints goes this way.
        case sky
        /// The sky lab's own (`fromOklab` in lab/oklab.js): the lightness
        /// as it is, the chroma halved in on eighteen times. What
        /// `SRGB.mixed` and `SRGB.ramp` use, as the lab's do.
        case skyLab
    }

    /// The colour as a display takes it. One that fits is converted as it
    /// stands; one that does not gives up chroma — both axes by the same
    /// share, so its hue is kept — until it does (`fitting`).
    func srgb(_ fitting: Fitting = .sky) -> SRGB {
        let held = fitting == .sky ? SkyMath.clamped(lightness) : lightness
        var light = Linear(lightness: held, a: a, b: b)
        if !light.fits {
            var low = 0.0
            var high = 1.0
            for _ in 0..<(fitting == .sky ? 14 : 18) {
                let share = (low + high) / 2
                if Linear(lightness: held, a: a * share, b: b * share).fits { low = share } else { high = share }
            }
            light = Linear(lightness: held, a: a * low, b: b * low)
        }
        let channel = { (v: Double) in SkyMath.clamped(OKLab.gamma(SkyMath.clamped(v))) }
        return SRGB(red: channel(light.red), green: channel(light.green), blue: channel(light.blue))
    }

    /// WCAG relative luminance, 0 … 1 — the number the legibility limits
    /// are written in (a card in the dark appearance is 0.0117). Taken from
    /// the colour as it stands, lightness held to 0 … 1 and each linear
    /// channel to 0 … 1, with no fitting first (`luminance` in air.js).
    var luminance: Double {
        let light = Linear(lightness: SkyMath.clamped(lightness), a: a, b: b)
        return 0.2126 * SkyMath.clamped(light.red) + 0.7152 * SkyMath.clamped(light.green)
            + 0.0722 * SkyMath.clamped(light.blue)
    }

    // MARK: Mixing

    /// `self` toward `other` by `t`, each of the three numbers on a
    /// straight line. `t` is NOT held to 0 … 1 (`mix3` in air.js): the
    /// painter sometimes means a little past an end.
    func mixed(with other: OKLab, by t: Double) -> OKLab {
        OKLab(lightness: lightness + (other.lightness - lightness) * t,
              a: a + (other.a - a) * t,
              b: b + (other.b - b) * t)
    }

    // MARK: Held to the sky

    /// The colour held within a contrast of `sky`: not lighter than
    /// `up` : 1 against it, not darker than `down` : 1 — the legibility
    /// limits' own ratio, on luminance + 0.05, with luminance taken as
    /// lightness cubed. What keeps a cloud quiet at every hour.
    ///
    /// A colour past a limit is brought back TOWARD THE SKY'S OWN — value,
    /// and with it chroma and hue — never only darkened: an ember held down
    /// in value alone is a dark red. `own`, 0 … 1, is how much of its own
    /// colour it keeps on the way back (0: it goes the sky's way; 1: only
    /// its value is held). A colour inside both limits is returned
    /// untouched. (`heldTo` in skies/hill-painted.js.)
    func held(to sky: OKLab, up: Double, down: Double? = nil, own: Double = 0) -> OKLab {
        let down = down ?? up
        let value = pow(max(0, lightness), 3)
        let skyValue = pow(max(0, sky.lightness), 3)
        let most = up * (skyValue + 0.05) - 0.05
        let least = max(0, (skyValue + 0.05) / down - 0.05)
        let limit: Double
        if value > most {
            limit = cbrt(max(0, most))
        } else if value < least {
            limit = cbrt(least)
        } else {
            return self
        }
        if lightness == sky.lightness { return self }
        let t = SkyMath.clamped((limit - sky.lightness) / (lightness - sky.lightness))
        let kept = t + (1 - t) * SkyMath.clamped(own)
        return OKLab(lightness: limit, a: sky.a + (a - sky.a) * kept, b: sky.b + (b - sky.b) * kept)
    }

    // MARK: The lab's arithmetic

    /// One sRGB channel, gamma-encoded → linear light.
    private static func linear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// One channel of linear light → gamma-encoded sRGB.
    private static func gamma(_ c: Double) -> Double {
        c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
    }

    /// A colour as linear light, red, green and blue, not held to anything:
    /// a channel under 0 or over 1 is a colour no display can show.
    private struct Linear {
        let red: Double
        let green: Double
        let blue: Double

        init(lightness: Double, a: Double, b: Double) {
            let l = pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3)
            let m = pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3)
            let s = pow(lightness - 0.0894841775 * a - 1.291485548 * b, 3)
            red = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
            green = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
            blue = -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s
        }

        /// Whether a display can show it: each channel within a
        /// ten-thousandth of 0 … 1 (the lab's own allowance, the same in
        /// both of its fits).
        var fits: Bool {
            red >= -1e-4 && red <= 1.0001 && green >= -1e-4 && green <= 1.0001
                && blue >= -1e-4 && blue <= 1.0001
        }
    }
}
