import Foundation

/// The air: everything the painter needs to know about the light at one
/// instant — the twilight as a painter's mixing table, asked by the sun's
/// real altitude.
///
/// The table is written once, as a NEGATIVE: keyframes by the sun's
/// altitude, each colour a [value, chroma, hue°], and PRINTED twice — high
/// key for the light appearance, low key for the dark one. Between two
/// keys the prints are mixed in OKLab. From it the air answers with plain
/// colours and three functions the painter samples:
///
/// - `sky(dx:elevation:)` — the sky is TALL. Two columns of ten stops,
///   over the sun and away from it; eight span the sky the everyday view
///   shows (elevation 0, the horizon, to 1, the top of the display at
///   rest), two more carry it on to the zenith the looked-up pose reveals.
/// - `haze(dx:)` — the air between the ridges: the low sky, not only its
///   rim. A plane of land takes its colour from it.
/// - `mist(fromLight:fromSun:)` — mist catches the light near it and goes
///   to its far tint away from it.
///
/// `dx` is always the distance from the sun's x in ANCHOR WIDTHS (negative:
/// left of the sun); where the sun is, is the world's business, not the
/// air's. Colours come back as the table has them; `shown(_:)` is the one
/// door every colour leaves by — the hush and the dimmed room are applied
/// there, once, so nothing downstream can forget them.
///
/// A port, number for number, of the sky lab's design/sky-lab/skies/
/// hill-painted/air.js (`airFor`). `AirTests` holds it against the lab's own
/// output for a sweep of the sun from −20° to +62° in both appearances,
/// evening and morning, and at the lab's eight standard hours
/// (`SkyCoreFixturesAir`). Pure, and built once a minute; it is not for a
/// per-frame loop.
struct Air: Equatable {
    // MARK: What it was asked

    /// The sun's altitude in degrees, negative below the horizon.
    let sunAltitude: Double
    /// The sun is on its way up. Dawn is the same table a breath cooler and
    /// rosier, with less ember.
    let morning: Bool
    /// The appearance: the low key (dark) or the high key (light).
    let dark: Bool
    /// The hush: 0 hushed … 1 itself. Held to 0 … 1.
    let presence: Double
    /// The room dimmed because he sleeps: 0 … 1 (a night's sleep 1, a nap
    /// 0.45, eased across a sleep's start and end).
    let depth: Double
    /// How much the moon lights the night: 0 … 1, and 0 when it is down or
    /// the sun is up.
    let moonlight: Double

    // MARK: Amounts

    /// 1 while the sun is under −13°, 0 from −7° up: how much of the
    /// night's own rules apply.
    let night: Double
    /// How much of the day's own colour the land keeps: none at −2°, all
    /// of it from 16°.
    let day: Double
    /// The last of the light: 0 at −7°, 1 from −1° up.
    let lastLight: Double

    // MARK: Colours, as the table has them

    /// The sun's disc. It is not printed with the sky: it is the light. On
    /// the pale page it is a pale cream at every height, a breath warmer as
    /// it sets (a low sun printed in its own apricot was the darkest thing
    /// in its sky), and the sky's own glow carries the fire.
    let sun: OKLab
    /// The sun's own light in the air around it, and how much of it there
    /// is.
    let glow: OKLab
    let glowAmount: Double
    /// The caught light on a shoulder that faces the sun, and how much.
    let rim: OKLab
    let rimAmount: Double
    /// The land's ground tone at this hour, and how far an albedo moves a
    /// plane's value from it.
    let land: OKLab
    let gain: Double
    /// Mist near the light, and mist far from it.
    let mist: OKLab
    let mistFar: OKLab
    /// The sky a little over half way up over the sun: what open ground
    /// and leaves that face the sky take a little of.
    let ambient: OKLab
    /// Moonlight is silver: the night key's lightest value, cooled.
    let silver: OKLab
    /// A cloud's paints.
    let cloud: Cloud

    /// The paints of a cloud, low and high: the side the light is on, the
    /// side it is not, and how much of the lit paint this hour gives (none
    /// once the sun is well down: a low cloud loses it first).
    struct Cloud: Equatable {
        let lowLit: OKLab
        let lowShade: OKLab
        let lowAmount: Double
        let highLit: OKLab
        let highShade: OKLab
        let highAmount: Double
    }

    // MARK: Kept for the three functions

    /// How far the light appearance's hush pulls a colour toward the page:
    /// 0.55 by day, 0.10 at night.
    let toward: Double
    /// The two columns, `samples` colours each from the horizon to the
    /// zenith, three numbers a colour.
    private let overSun: [Float]
    private let away: [Float]
    /// The earth's shadow: its colour, how much of it, how high it stands.
    private let shadow: OKLab
    private let shadowAmount: Double
    private let shadowHeight: Double

    // MARK: The air at an instant

    /// The air for a sun at `sunAltitude` degrees. Every number must be
    /// finite; `presence` is held to 0 … 1.
    init(sunAltitude: Double, morning: Bool, dark: Bool, presence: Double, depth: Double,
         moonlight: Double = 0) {
        self.sunAltitude = sunAltitude
        self.morning = morning
        self.dark = dark
        self.presence = SkyMath.clamped(presence)
        self.depth = depth
        self.moonlight = moonlight

        // The two keys the sun stands between, and how far from the upper
        // to the lower: eased, so nothing turns at a key.
        let keys = Air.keys
        var upper = 0
        while upper < keys.count - 2 && sunAltitude < keys[upper + 1].altitude { upper += 1 }
        let k0 = keys[upper]
        let k1 = keys[upper + 1]
        let t = SkyMath.smoothstep(0, 1, SkyMath.clamped((k0.altitude - sunAltitude) / (k0.altitude - k1.altitude)))
        let printed = { (paint: (Key) -> P) -> OKLab in
            Air.print(k0, dark, Air.dawn(paint(k0), morning))
                .mixed(with: Air.print(k1, dark, Air.dawn(paint(k1), morning)), by: t)
        }
        let amount = { (number: (Key) -> Double) -> Double in SkyMath.lerp(number(k0), number(k1), t) }

        let night = 1 - SkyMath.smoothstep(-13, -7, sunAltitude)
        self.night = night
        day = SkyMath.smoothstep(-2, 16, sunAltitude)
        lastLight = SkyMath.smoothstep(-7, -1, sunAltitude)
        toward = SkyMath.lerp(0.10, 0.55, SkyMath.smoothstep(-10, 0, sunAltitude))

        // The two columns: over the sun and away from it.
        let column = { (overSun: Bool) -> [Float] in
            var stops = (0..<8).map { stop in
                printed { key in
                    if overSun { return (dark ? key.overSunDark : key.overSunLight)?[stop] ?? key.overSun[stop] }
                    return (dark ? key.awayDark : nil)?[stop] ?? key.away[stop]
                }
            }
            // Above the everyday view the sky runs on to the zenith: a
            // little deeper, a little quieter. (While there is still light
            // in the low key's sky — a summer bedtime, the sun a hand
            // above the hill — the sky the camera looks up into goes a
            // clear shade deeper toward the zenith, as an evening sky
            // does: his stars are shown against it. Nothing of the
            // everyday view changes.)
            let top = stops[7]
            let zenith = dark ? 0.016 + 0.012 * night + 0.064 * (1 - night) : 0.0
            stops.append(OKLab(lightness: top.lightness - zenith * 0.62, a: top.a * 0.96, b: top.b * 0.96))
            stops.append(OKLab(lightness: top.lightness - zenith, a: top.a * 0.9, b: top.b * 0.9))
            if !dark {
                // The light appearance's sky is held where grey text can
                // still be read on it: in the looked-up pose the header
                // sits on the upper sky. A soft floor at a lightness of
                // 0.876. (The lab's own note beside it says 0.846; its
                // code, and so the signed-off picture, 0.876.)
                stops = stops.map { stop in
                    let least = 0.876
                    let h = SkyMath.clamped(0.5 + 0.5 * (stop.lightness - least) / 0.02)
                    return OKLab(lightness: SkyMath.lerp(least, stop.lightness, h) + 0.02 * h * (1 - h),
                                 a: stop.a, b: stop.b)
                }
            }
            return Air.table(stops)
        }
        let overSunColumn = column(true)
        overSun = overSunColumn
        away = column(false)

        // The earth's shadow is slate-blue, a little toward violet (at 252°
        // it printed as a teal stripe — the app's own accent). It stands
        // away from the sun, after sunset, and is gone by −9.5°.
        let slate = P(0.20, 0.05, 268)
        shadow = Air.print(k0, dark, slate).mixed(with: Air.print(k1, dark, slate), by: t)
        shadowAmount = 0.85 * SkyMath.smoothstep(-1.5, 2.5, -sunAltitude) * (1 - SkyMath.smoothstep(6, 9.5, -sunAltitude))
        shadowHeight = SkyMath.lerp(0.06, 0.2, SkyMath.smoothstep(0, 5, -sunAltitude))

        sun = Air.disc(sunAltitude, dark)
        glow = printed { $0.glow }
        glowAmount = amount { $0.glowAmount } * (dark ? 0.4 + 0.6 * SkyMath.smoothstep(-15, -6, -sunAltitude) : 1)
        rim = printed { $0.rim }
        rimAmount = amount { $0.rimAmount }
        // (The land is not printed: its two tones are written per
        // appearance, as they are to be.)
        land = (dark ? k0.landDark : k0.landLight).colour.mixed(with: (dark ? k1.landDark : k1.landLight).colour, by: t)
        gain = amount { dark ? $0.gainDark : $0.gainLight }
        mist = printed { $0.mist }
        mistFar = printed { P($0.mist.value * 0.72, 0.045, $0.altitude > 5 ? $0.mist.hue : 302) }
        let half = Air.ramp(overSunColumn, 0.55)
        ambient = OKLab(lightness: Double(half.0), a: Double(half.1), b: Double(half.2))
        silver = Air.print(keys[keys.count - 1], dark, P(dark ? 1.55 : 1.9, 0.045, 255))
        cloud = Cloud(lowLit: printed { $0.lowLit }, lowShade: printed { $0.lowShade },
                      lowAmount: amount { $0.lowAmount },
                      highLit: printed { $0.highLit }, highShade: printed { $0.highShade },
                      highAmount: amount { $0.highAmount })
    }

    // MARK: The hush and the dimmed room

    /// A colour of the table as it is SHOWN: every colour leaves through
    /// here.
    ///
    /// - Dark appearance: hushed means dimmer and greyer, never lighter —
    ///   12 % nearer black and two fifths of its chroma at full hush; the
    ///   dimmed room takes 14 % more of its light and 12 % of its chroma.
    /// - Light appearance: by day the hush pulls toward the page (55 % of
    ///   the way) and greys to a fifth of the chroma; at night it all but
    ///   only greys, and less — a tenth of the way, 62 % of the chroma (a
    ///   storybook night on pale paper keeps its lilac: a pastel night
    ///   pulled toward the page would be paler than its bloom). The dimmed
    ///   room is a breath deeper and a quarter greyer.
    ///
    /// `presence`, when given, is used in place of the air's own (and is
    /// not held to 0 … 1): the tree, the water, a cloud and the sun's halo
    /// are held above the hush on the pale page.
    func shown(_ colour: OKLab, presence held: Double? = nil) -> OKLab {
        let p = held ?? presence
        var lightness = colour.lightness
        var a = colour.a
        var b = colour.b
        if dark {
            lightness *= 1 - 0.12 * (1 - p)
            let chroma = 0.4 + 0.6 * p
            a *= chroma
            b *= chroma
            lightness *= 1 - 0.14 * depth
            a *= 1 - 0.12 * depth
            b *= 1 - 0.12 * depth
        } else {
            lightness += (Air.pageLightness - lightness) * toward * (1 - p)
            let chroma = SkyMath.lerp(0.2, 0.62, night) + (1 - SkyMath.lerp(0.2, 0.62, night)) * p
            a *= chroma
            b *= chroma
            lightness -= 0.012 * depth
            a *= 1 - 0.25 * depth
            b *= 1 - 0.25 * depth
        }
        return OKLab(lightness: lightness, a: a, b: b)
    }

    // MARK: The sky, the haze, the mist

    /// The sky `dx` anchor-widths from the sun at `elevation` (table
    /// units: 0 the horizon, 1 the top of the everyday view, 2.3 the
    /// zenith) — as the table has it, before `shown`.
    ///
    /// The arch: over the sun the bands stand at their full height; away
    /// from it they sink toward the horizon, and a page away the far
    /// column takes over — the Belt of Venus over the earth's shadow. Only
    /// the table's own span leans; the sky above the everyday view is one
    /// sky.
    func sky(dx: Double, elevation: Double) -> OKLab {
        let nearSun = exp(-(dx * dx) / (Air.archWidth * Air.archWidth))
        let arch = Air.archFar + (1 - Air.archFar) * nearSun
        let e = max(0, elevation)
        let leaning = e >= 1 ? e : 1 - pow(1 - e, 1 / arch)
        let far = SkyMath.smoothstep(Air.awayFrom, Air.awayTo, abs(dx))
        let over = Air.ramp(overSun, leaning)
        let off = Air.ramp(away, e)
        var lightness = Double(over.0) + (Double(off.0) - Double(over.0)) * far
        var a = Double(over.1) + (Double(off.1) - Double(over.1)) * far
        var b = Double(over.2) + (Double(off.2) - Double(over.2)) * far
        let inShadow = shadowAmount * SkyMath.smoothstep(0.95, 1.9, abs(dx))
            * (1 - SkyMath.smoothstep(shadowHeight * 0.35, shadowHeight, e))
        if inShadow > 0 {
            lightness += (shadow.lightness - lightness) * inShadow
            a += (shadow.a - a) * inShadow
            b += (shadow.b - b) * inShadow
        }
        // (The lab keeps each sample in single precision, as it keeps its
        // tables; so does this, so that the two agree to the bit.)
        return OKLab(lightness: Double(Float(lightness)), a: Double(Float(a)), b: Double(Float(b)))
    }

    /// The air between the ridges `dx` anchor-widths from the sun: the low
    /// sky (its rim and a quarter of the way up, mixed), a little of the
    /// ambient sky in it, a little quieter than either.
    func haze(dx: Double) -> OKLab {
        let rim = sky(dx: dx, elevation: 0.012)
        let up = sky(dx: dx, elevation: 0.27)
        let far = SkyMath.smoothstep(Air.awayFrom, Air.awayTo, abs(dx))
        let mixed = rim.mixed(with: up, by: 0.55).mixed(with: ambient, by: 0.25 + 0.15 * far)
        return OKLab(lightness: mixed.lightness, a: mixed.a * 0.85, b: mixed.b * 0.85)
    }

    /// Mist `fromLight` anchor-widths from the light it answers (the sun,
    /// or the moon once the sun is well down) and `fromSun` from the sun:
    /// it catches the light near it, goes to its far tint away from it,
    /// and takes a fifth to two fifths of the haze where it lies. Under a
    /// moon it is half silver at the most.
    func mist(fromLight: Double, fromSun: Double) -> OKLab {
        let lit = moonlight > 0 ? mist.mixed(with: silver, by: 0.5 * moonlight) : mist
        let far = moonlight > 0 ? mistFar.mixed(with: silver, by: 0.5 * moonlight) : mistFar
        let own = lit.mixed(with: far, by: SkyMath.smoothstep(0.12, 1.1, abs(fromLight)))
        return own.mixed(with: haze(dx: fromSun), by: 0.18 + 0.2 * SkyMath.smoothstep(0.1, 0.9, abs(fromLight)))
    }

    // MARK: The negative, and its two prints

    /// The page's lightness as the lab has it for the pale appearance's
    /// hush. (It writes 0.9612 for #F2F2F7, which is 0.9626 in OKLab; the
    /// signed-off picture was painted with 0.9612, so that is the number.)
    static let pageLightness = 0.9612

    /// Where the ten stops of a column stand: 0 the horizon … 1 the top of
    /// the everyday view; then the sky above it.
    static let elevations: [Double] = [0, 0.04, 0.10, 0.18, 0.29, 0.44, 0.68, 1, 1.5, 2.3]
    /// The zenith: the last of `elevations`.
    static let zenith = 2.3
    /// Colours kept per column, denser toward the horizon.
    private static let samples = 96

    /// The arch: how wide the bands stand at full height round the sun
    /// (anchor widths), and how far they have sunk a long way from it.
    private static let archWidth = 0.60
    private static let archFar = 0.44
    /// Where the column away from the sun starts to take over, and where
    /// it has (anchor widths from the sun).
    private static let awayFrom = 0.10
    private static let awayTo = 1.35

    /// One colour of the negative: a value (0 the print's deepest … 1 its
    /// lightest; over 1 a light), a chroma and a hue in degrees.
    private struct P {
        let value: Double
        let chroma: Double
        let hue: Double

        init(_ value: Double, _ chroma: Double, _ hue: Double) {
            self.value = value
            self.chroma = chroma
            self.hue = hue
        }

        /// The three taken as they stand: lightness, chroma, hue.
        var colour: OKLab { OKLab(lightness: value, chroma: chroma, hueDegrees: hue) }
    }

    /// How one appearance prints the negative at a key: the lightness its
    /// deepest and its lightest values come out at, the curve between them,
    /// and how much of the chroma it keeps.
    private struct Print {
        let low: Double
        let high: Double
        let gamma: Double
        let chroma: Double
    }

    /// One key of the negative: the sky and the land under a sun at
    /// `altitude`. `overSun` and `away` are the two columns' eight stops,
    /// horizon to the top of the everyday view; `…Dark` and `…Light`, where
    /// a key has them, are the column written again for that appearance
    /// alone.
    private struct Key {
        let altitude: Double
        let light: Print
        let dark: Print
        let overSun: [P]
        let away: [P]
        let overSunDark: [P]?
        let awayDark: [P]?
        let overSunLight: [P]?
        let glow: P
        let glowAmount: Double
        let lowLit: P
        let lowShade: P
        let lowAmount: Double
        let highLit: P
        let highShade: P
        let highAmount: Double
        let mist: P
        let landLight: P
        let landDark: P
        let gainLight: Double
        let gainDark: Double
        let rim: P
        let rimAmount: Double

        /// The same key under a sun at another altitude.
        func at(_ altitude: Double) -> Key {
            Key(altitude: altitude, light: light, dark: dark, overSun: overSun, away: away,
                overSunDark: overSunDark, awayDark: awayDark, overSunLight: overSunLight,
                glow: glow, glowAmount: glowAmount, lowLit: lowLit, lowShade: lowShade, lowAmount: lowAmount,
                highLit: highLit, highShade: highShade, highAmount: highAmount, mist: mist,
                landLight: landLight, landDark: landDark, gainLight: gainLight, gainDark: gainDark,
                rim: rim, rimAmount: rimAmount)
        }
    }

    /// A value of the negative, printed for an appearance.
    private static func print(_ key: Key, _ dark: Bool, _ paint: P) -> OKLab {
        let range = dark ? key.dark : key.light
        let v = paint.value
        let curved = v <= 0 ? v : v >= 1 ? 1 + (v - 1) : pow(v, range.gamma)
        // A saturated colour prints a little deeper in the high key, so
        // pastels keep their chroma.
        let lightness = range.low + (range.high - range.low) * curved - (dark ? 0 : 0.30 * paint.chroma)
        // In both prints the luminous passages carry the colour; the deep
        // ones go quiet.
        let quiet = dark ? 0.62 + 0.38 * SkyMath.clamped(v) : 0.60 + 0.40 * SkyMath.clamped(v)
        var hue = paint.hue
        var chroma = paint.chroma
        // A dim green-gold is khaki: in the low key that breath is plain
        // gold…
        if dark && hue > 88 && hue < 130 {
            hue = 72 + (hue - 88) * 0.15
            chroma *= 2.3
        }
        // …and its golds lean to apricot and ember, never mustard.
        if dark && hue > 48 && hue <= 88 { hue = 48 + (hue - 48) * 0.6 }
        return OKLab(lightness: lightness, chroma: chroma * range.chroma * quiet, hueDegrees: hue)
    }

    /// Dawn is the same table a breath cooler and rosier, with less ember:
    /// a warm hue gives up an eighth of its chroma, and the golds and
    /// greens turn 7° toward rose.
    private static func dawn(_ paint: P, _ morning: Bool) -> P {
        guard morning else { return paint }
        let warm = paint.hue < 125 || paint.hue > 345
        return P(paint.value, paint.chroma * (warm ? 0.88 : 1),
                 warm ? (paint.hue < 125 ? paint.hue - 7 : paint.hue) : paint.hue)
    }

    /// The sun's disc at an altitude: its own five keys, mixed on a
    /// straight line between the two it stands between.
    private static func disc(_ altitude: Double, _ dark: Bool) -> OKLab {
        var upper = 0
        while upper < sunDisc.count - 2 && altitude < sunDisc[upper + 1].altitude { upper += 1 }
        let from = sunDisc[upper]
        let to = sunDisc[upper + 1]
        let t = SkyMath.clamped((from.altitude - altitude) / (from.altitude - to.altitude))
        return (dark ? from.dark : from.light).colour.mixed(with: (dark ? to.dark : to.light).colour, by: t)
    }

    // MARK: A column, kept

    /// A column's ten stops as `samples` colours from the horizon to the
    /// zenith, each channel a smooth curve through the stops; the samples
    /// stand closer together toward the horizon, where the bands are.
    private static func table(_ stops: [OKLab]) -> [Float] {
        let channels = [stops.map(\.lightness), stops.map(\.a), stops.map(\.b)]
        var out: [Float] = []
        out.reserveCapacity(samples * 3)
        for n in 0..<samples {
            let step = Double(n) / Double(samples - 1)
            let e = zenith * (step * step)
            for channel in channels { out.append(Float(hermite(elevations, channel, e))) }
        }
        return out
    }

    /// The colour of a kept column at elevation `e`.
    private static func ramp(_ table: [Float], _ e: Double) -> (Float, Float, Float) {
        let f = min(1, max(0, e / zenith)).squareRoot() * Double(samples - 1)
        let n = min(samples - 2, Int(f.rounded(.down)))
        let k = f - Double(n)
        let at = n * 3
        let channel = { (c: Int) -> Float in
            let from = Double(table[at + c])
            return Float(from + (Double(table[at + 3 + c]) - from) * k)
        }
        return (channel(0), channel(1), channel(2))
    }

    /// A smooth curve through unevenly spaced stops that never overshoots
    /// them (a cubic Hermite with harmonic-mean tangents): `ys` at `xs`
    /// (ascending), read at `x`; held at either end.
    private static func hermite(_ xs: [Double], _ ys: [Double], _ x: Double) -> Double {
        let n = xs.count
        if x <= xs[0] { return ys[0] }
        if x >= xs[n - 1] { return ys[n - 1] }
        var i = 0
        while x > xs[i + 1] { i += 1 }
        let h = xs[i + 1] - xs[i]
        let t = (x - xs[i]) / h
        let slope = { (j: Int) -> Double in
            if j == 0 { return (ys[1] - ys[0]) / (xs[1] - xs[0]) }
            if j == n - 1 { return (ys[n - 1] - ys[n - 2]) / (xs[n - 1] - xs[n - 2]) }
            let a = (ys[j] - ys[j - 1]) / (xs[j] - xs[j - 1])
            let b = (ys[j + 1] - ys[j]) / (xs[j + 1] - xs[j])
            return a * b <= 0 ? 0 : (2 * a * b) / (a + b)
        }
        let m0 = slope(i) * h
        let m1 = slope(i + 1) * h
        let t2 = t * t
        let t3 = t2 * t
        return (2 * t3 - 3 * t2 + 1) * ys[i] + (t3 - 2 * t2 + t) * m0 + (-2 * t3 + 3 * t2) * ys[i + 1] + (t3 - t2) * m1
    }

    // MARK: The table

    /// The keys, highest sun first. The long hushed day is one palette:
    /// nothing begins to turn until the sun is under 15°, so the 30° key
    /// stands again at 15°.
    private static let keys: [Key] = [key30, key30.at(15), key8, key2Point5, keyMinus0Point8, keyMinus4,
                                      keyMinus7Point5, keyMinus11, keyMinus18]

    /// The day. (The low key's hushed day is not a night: a dusky
    /// slate-blue with its hue kept — pale along the horizon, deeper
    /// overhead, still under the limits behind the header's words — so the
    /// tree is a true silhouette on it and the planes of land can be told
    /// apart at one in the afternoon.)
    private static let key30 = Key(
        altitude: 30,
        light: Print(low: 0.872, high: 0.968, gamma: 1, chroma: 0.8),
        dark: Print(low: 0.325, high: 0.495, gamma: 1.1, chroma: 1.3),
        overSun: [P(1, 0.016, 235), P(0.97, 0.028, 238), P(0.9, 0.048, 242), P(0.78, 0.072, 246),
                  P(0.6, 0.098, 250), P(0.4, 0.114, 254), P(0.18, 0.124, 257), P(0, 0.13, 260)],
        away: [P(0.93, 0.024, 240), P(0.9, 0.034, 242), P(0.84, 0.054, 245), P(0.72, 0.078, 248),
               P(0.55, 0.1, 252), P(0.36, 0.114, 255), P(0.16, 0.124, 258), P(0, 0.13, 260)],
        overSunDark: [P(1, 0.045, 236), P(0.97, 0.052, 239), P(0.9, 0.066, 243), P(0.78, 0.082, 247),
                      P(0.6, 0.1, 251), P(0.4, 0.114, 254), P(0.18, 0.124, 257), P(0, 0.13, 260)],
        awayDark: [P(0.92, 0.05, 242), P(0.89, 0.058, 244), P(0.83, 0.07, 247), P(0.71, 0.086, 250),
                   P(0.55, 0.1, 252), P(0.36, 0.114, 255), P(0.16, 0.124, 258), P(0, 0.13, 260)],
        overSunLight: nil,
        glow: P(1.12, 0.03, 92), glowAmount: 0.42,
        lowLit: P(1.2, 0.012, 90), lowShade: P(0.42, 0.035, 255), lowAmount: 1,
        highLit: P(1.16, 0.008, 90), highShade: P(0.74, 0.03, 250), highAmount: 1,
        mist: P(1.05, 0.012, 240),
        landLight: P(0.8, 0.03, 250), landDark: P(0.165, 0.034, 258),
        gainLight: 0.26, gainDark: 0.3,
        rim: P(1.1, 0.03, 90), rimAmount: 0.1)

    /// A low sun. (Away from it the far side is already cool rose over
    /// blue: the first of the Belt of Venus.)
    private static let key8 = Key(
        altitude: 8,
        light: Print(low: 0.862, high: 0.968, gamma: 1, chroma: 0.75),
        dark: Print(low: 0.25, high: 0.46, gamma: 1.25, chroma: 1.15),
        overSun: [P(1, 0.075, 78), P(0.98, 0.065, 84), P(0.92, 0.04, 92), P(0.8, 0.022, 150),
                  P(0.62, 0.06, 245), P(0.42, 0.095, 254), P(0.24, 0.112, 258), P(0.1, 0.12, 262)],
        away: [P(0.7, 0.05, 322), P(0.73, 0.058, 338), P(0.71, 0.055, 318), P(0.62, 0.062, 276),
               P(0.5, 0.085, 255), P(0.36, 0.102, 257), P(0.21, 0.112, 259), P(0.09, 0.12, 262)],
        overSunDark: [P(1, 0.12, 66), P(0.99, 0.115, 72), P(0.94, 0.09, 80), P(0.84, 0.055, 60),
                      P(0.66, 0.06, 350), P(0.44, 0.085, 285), P(0.24, 0.108, 262), P(0.1, 0.12, 262)],
        awayDark: nil,
        overSunLight: nil,
        glow: P(1.1, 0.09, 80), glowAmount: 0.55,
        lowLit: P(1.14, 0.06, 82), lowShade: P(0.36, 0.04, 272), lowAmount: 1,
        highLit: P(1.1, 0.04, 80), highShade: P(0.62, 0.034, 266), highAmount: 1,
        mist: P(1, 0.04, 80),
        landLight: P(0.8, 0.03, 275), landDark: P(0.085, 0.02, 275),
        gainLight: 0.26, gainDark: 0.3,
        rim: P(1.1, 0.06, 80), rimAmount: 0.2)

    /// The golden hour's end.
    private static let key2Point5 = Key(
        altitude: 2.5,
        light: Print(low: 0.852, high: 0.965, gamma: 1, chroma: 0.64),
        dark: Print(low: 0.135, high: 0.52, gamma: 1.3, chroma: 0.95),
        overSun: [P(0.96, 0.13, 62), P(1, 0.12, 72), P(0.97, 0.08, 86), P(0.9, 0.04, 100),
                  P(0.78, 0.07, 15), P(0.58, 0.085, 318), P(0.36, 0.105, 280), P(0.17, 0.115, 268)],
        away: [P(0.72, 0.04, 320), P(0.75, 0.055, 342), P(0.76, 0.065, 352), P(0.7, 0.06, 325),
               P(0.58, 0.075, 290), P(0.42, 0.092, 270), P(0.27, 0.105, 266), P(0.14, 0.115, 266)],
        overSunDark: nil,
        awayDark: nil,
        overSunLight: nil,
        glow: P(1.12, 0.13, 68), glowAmount: 0.55,
        lowLit: P(1.12, 0.13, 62), lowShade: P(0.36, 0.05, 292), lowAmount: 1,
        highLit: P(1.1, 0.1, 52), highShade: P(0.62, 0.045, 300), highAmount: 1,
        mist: P(1, 0.07, 62),
        landLight: P(0.818, 0.026, 318), landDark: P(0.066, 0.018, 300),
        gainLight: 0.22, gainDark: 0.4,
        rim: P(1.08, 0.11, 66), rimAmount: 0.5)

    /// Sunset.
    private static let keyMinus0Point8 = Key(
        altitude: -0.8,
        light: Print(low: 0.846, high: 0.962, gamma: 1, chroma: 0.68),
        dark: Print(low: 0.128, high: 0.575, gamma: 1.4, chroma: 1),
        overSun: [P(0.84, 0.18, 42), P(0.95, 0.16, 58), P(1, 0.11, 80), P(0.93, 0.04, 100),
                  P(0.8, 0.09, 12), P(0.6, 0.1, 318), P(0.38, 0.105, 284), P(0.17, 0.11, 270)],
        away: [P(0.6, 0.05, 320), P(0.64, 0.07, 345), P(0.68, 0.085, 352), P(0.64, 0.08, 336),
               P(0.52, 0.08, 302), P(0.38, 0.09, 280), P(0.25, 0.1, 272), P(0.14, 0.11, 270)],
        overSunDark: nil,
        awayDark: nil,
        overSunLight: nil,
        glow: P(1.04, 0.17, 52), glowAmount: 0.58,
        lowLit: P(1.08, 0.18, 44), lowShade: P(0.27, 0.05, 286), lowAmount: 1,
        highLit: P(1.08, 0.12, 40), highShade: P(0.54, 0.05, 300), highAmount: 1,
        mist: P(0.92, 0.1, 40),
        landLight: P(0.815, 0.028, 310), landDark: P(0.06, 0.02, 300),
        gainLight: 0.2, gainDark: 0.4,
        rim: P(1, 0.15, 44), rimAmount: 0.7)

    /// Civil twilight.
    private static let keyMinus4 = Key(
        altitude: -4,
        light: Print(low: 0.842, high: 0.955, gamma: 1, chroma: 0.68),
        dark: Print(low: 0.112, high: 0.53, gamma: 1.45, chroma: 1),
        overSun: [P(0.62, 0.175, 36), P(0.84, 0.165, 52), P(1, 0.12, 78), P(0.92, 0.04, 102),
                  P(0.76, 0.1, 8), P(0.54, 0.1, 318), P(0.32, 0.105, 286), P(0.13, 0.105, 272)],
        away: [P(0.4, 0.055, 300), P(0.44, 0.065, 325), P(0.48, 0.075, 345), P(0.48, 0.08, 335),
               P(0.4, 0.08, 306), P(0.29, 0.09, 282), P(0.18, 0.1, 274), P(0.1, 0.105, 272)],
        overSunDark: nil,
        awayDark: nil,
        overSunLight: nil,
        glow: P(0.95, 0.17, 44), glowAmount: 0.5,
        lowLit: P(0.82, 0.17, 24), lowShade: P(0.17, 0.05, 276), lowAmount: 0.42,
        highLit: P(0.98, 0.13, 8), highShade: P(0.42, 0.05, 292), highAmount: 1,
        mist: P(0.62, 0.08, 350),
        landLight: P(0.815, 0.03, 296), landDark: P(0.052, 0.02, 290),
        gainLight: 0.18, gainDark: 0.34,
        rim: P(0.8, 0.14, 30), rimAmount: 0.2)

    /// Dusk. (The high key's dusk: between its peach and its blue the
    /// table's green-gold breath, hushed, prints as a grey-green band over
    /// the horizon. On the pale page the way from one to the other is
    /// through a pale rose and lilac — here and in the next key.)
    private static let keyMinus7Point5 = Key(
        altitude: -7.5,
        light: Print(low: 0.84, high: 0.935, gamma: 1, chroma: 0.6),
        dark: Print(low: 0.092, high: 0.42, gamma: 1.55, chroma: 0.95),
        overSun: [P(0.6, 0.16, 38), P(0.8, 0.14, 58), P(0.85, 0.08, 90), P(0.68, 0.04, 150),
                  P(0.48, 0.06, 250), P(0.32, 0.08, 265), P(0.16, 0.085, 268), P(0.03, 0.085, 268)],
        away: [P(0.15, 0.045, 255), P(0.17, 0.05, 258), P(0.2, 0.055, 262), P(0.2, 0.06, 265),
               P(0.17, 0.07, 266), P(0.12, 0.075, 268), P(0.06, 0.08, 268), P(0, 0.085, 268)],
        overSunDark: nil,
        awayDark: nil,
        overSunLight: [P(0.6, 0.16, 38), P(0.8, 0.14, 58), P(0.85, 0.07, 72), P(0.7, 0.042, 0),
                       P(0.5, 0.056, 296), P(0.32, 0.08, 265), P(0.16, 0.085, 268), P(0.03, 0.085, 268)],
        glow: P(0.82, 0.16, 42), glowAmount: 0.34,
        lowLit: P(0.5, 0.1, 20), lowShade: P(0.1, 0.04, 268), lowAmount: 0,
        highLit: P(0.62, 0.09, 350), highShade: P(0.22, 0.045, 276), highAmount: 0.3,
        mist: P(0.34, 0.04, 280),
        landLight: P(0.815, 0.032, 285), landDark: P(0.05, 0.018, 280),
        gainLight: 0.16, gainDark: 0.28,
        rim: P(0.6, 0.1, 30), rimAmount: 0)

    /// The last light. (The low key's is not the high key's: its gold
    /// and its green-gold breath, hushed, print as a brown band behind the
    /// tree. There the dying glow is one thin ember line that goes up
    /// through wine and plum into the indigo — and it is written strong
    /// enough to stay a colour.)
    private static let keyMinus11 = Key(
        altitude: -11,
        light: Print(low: 0.84, high: 0.905, gamma: 1, chroma: 1.1),
        dark: Print(low: 0.125, high: 0.28, gamma: 1.5, chroma: 0.9),
        overSun: [P(0.75, 0.12, 42), P(0.85, 0.09, 65), P(0.7, 0.045, 120), P(0.5, 0.05, 235),
                  P(0.36, 0.065, 258), P(0.22, 0.075, 266), P(0.1, 0.08, 268), P(0, 0.08, 270)],
        away: [P(0.24, 0.05, 258), P(0.24, 0.055, 260), P(0.21, 0.06, 264), P(0.17, 0.065, 266),
               P(0.12, 0.07, 268), P(0.07, 0.075, 269), P(0.03, 0.08, 270), P(0, 0.08, 270)],
        overSunDark: [P(0.66, 0.2, 34), P(0.7, 0.17, 41), P(0.52, 0.09, 20), P(0.42, 0.06, 332),
                      P(0.36, 0.065, 275), P(0.22, 0.075, 266), P(0.1, 0.08, 268), P(0, 0.08, 270)],
        awayDark: nil,
        overSunLight: [P(0.75, 0.12, 42), P(0.85, 0.09, 65), P(0.72, 0.05, 24), P(0.52, 0.05, 318),
                       P(0.36, 0.064, 272), P(0.22, 0.075, 266), P(0.1, 0.08, 268), P(0, 0.08, 270)],
        glow: P(0.8, 0.1, 45), glowAmount: 0.16,
        lowLit: P(0.4, 0.05, 20), lowShade: P(0.05, 0.04, 268), lowAmount: 0,
        highLit: P(0.4, 0.05, 300), highShade: P(0.16, 0.045, 270), highAmount: 0,
        mist: P(0.42, 0.04, 265),
        landLight: P(0.818, 0.03, 278), landDark: P(0.068, 0.02, 272),
        gainLight: 0.14, gainDark: 0.26,
        rim: P(0.5, 0.05, 30), rimAmount: 0)

    /// Night. (The night's horizon light is a BAND, not a line: it
    /// stands as high as the tree's crown before it lets go — so at night
    /// the tree is a silhouette against it, a shade lighter than the
    /// land.)
    private static let keyMinus18 = Key(
        altitude: -18,
        light: Print(low: 0.84, high: 0.892, gamma: 1, chroma: 1.4),
        dark: Print(low: 0.148, high: 0.234, gamma: 1.1, chroma: 1),
        overSun: [P(1, 0.055, 262), P(0.97, 0.058, 263), P(0.93, 0.062, 265), P(0.87, 0.068, 267),
                  P(0.76, 0.075, 269), P(0.5, 0.081, 271), P(0.16, 0.085, 273), P(0, 0.085, 274)],
        away: [P(1, 0.055, 262), P(0.97, 0.058, 263), P(0.93, 0.062, 265), P(0.87, 0.068, 267),
               P(0.76, 0.075, 269), P(0.5, 0.081, 271), P(0.16, 0.085, 273), P(0, 0.085, 274)],
        overSunDark: nil,
        awayDark: nil,
        overSunLight: nil,
        glow: P(1, 0.03, 262), glowAmount: 0,
        lowLit: P(1, 0.03, 262), lowShade: P(-0.1, 0.05, 268), lowAmount: 0,
        highLit: P(1, 0.03, 262), highShade: P(0.45, 0.05, 268), highAmount: 0,
        mist: P(1.2, 0.055, 258),
        landLight: P(0.82, 0.03, 274), landDark: P(0.092, 0.026, 268),
        gainLight: 0.12, gainDark: 0.3,
        rim: P(0.5, 0.02, 260), rimAmount: 0)

    /// The sun's disc by altitude, for the dark appearance and the light:
    /// lightness, chroma, hue as they stand.
    private static let sunDisc: [(altitude: Double, dark: P, light: P)] = [
        (30, P(0.9, 0.035, 95), P(0.992, 0.02, 95)),
        (8, P(0.895, 0.125, 78), P(0.985, 0.04, 92)),
        (2.5, P(0.9, 0.105, 76), P(0.975, 0.045, 84)),
        (-0.8, P(0.85, 0.13, 62), P(0.968, 0.055, 76)),
        (-3, P(0.62, 0.17, 40), P(0.955, 0.06, 66)),
    ]
}
