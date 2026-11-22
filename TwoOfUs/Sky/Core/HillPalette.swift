import Foundation

/// The palette for this minute: the painted hill's land and tree in this
/// hour's light — the ground of each season lit by the hour, snow and
/// frost, the tree's ink and the season's leaf and blossom paints — with
/// the air they are mixed in and the amounts the painter turns on (which
/// light the land answers, how much mist, how far the stars are out).
///
/// A pure function of the sun's altitude and whether it is rising, the
/// moon, the appearance, the season, and the tone (the hush and the room's
/// depth). Nothing here knows where anything stands: the sun's and the
/// lamp's places are the world's (`SkyWorld`), and no rule takes a card.
///
/// Every colour is as the table has it; it is SHOWN — hushed, dimmed, and
/// at night held under a card's own value — by `shown(_:)`.
///
/// A port, number for number, of `resolve` in the sky lab's design/sky-lab/
/// skies/hill-painted.js, with the hush at rest from lab/presence.js.
/// `HillPaletteTests` holds it against the lab's own palettes
/// (`SkyCoreFixturesPalette`): the eight standard hours in five seasons'
/// days, a summer's day hour by hour, a November dusk and dawn, asleep, and
/// under a bright moon — in both appearances. Built once a minute, not per
/// frame.
struct HillPalette: Equatable {
    // MARK: What it is asked

    /// The moon while it is above the horizon: its altitude in degrees and
    /// the lit fraction of its face (0 new … 1 full).
    struct Moon: Equatable {
        let altitude: Double
        let fraction: Double
    }

    /// Which light the land and the clouds answer, and how strongly: the
    /// sun until it is well down (its power 0 at −8°, 1 from −1°), then the
    /// moon (its power the moonlight). Where the lamp stands is the
    /// world's business.
    struct Lamp: Equatable {
        enum Kind: String, Equatable {
            case sun, moon
        }

        let kind: Kind
        let power: Double
    }

    // MARK: The air, and amounts

    /// The air the paints are mixed in: this minute's sun, appearance and
    /// tone, and this palette's moonlight.
    let air: Air
    /// The season the land is in.
    let season: SkySeason
    /// 1 at night, 0 from −8° up. (The land's own measure of night: the
    /// air's, `Air.night`, lets go a degree later.)
    let nightness: Double
    /// How much the moon lights the night, 0 … 1: more for a high moon and
    /// a full one, and nothing while the sun is up.
    let moonlight: Double
    /// Dark appearance at night stays dark: 1 once the twilight has gone
    /// (the sun under −10.6°), 0 from −9.6° and always in the light
    /// appearance. While it is 1 nothing `shown` is lighter than a card.
    let deepNight: Double
    let lamp: Lamp
    /// How much mist lies in the valleys: more in the morning, after a
    /// frost, at night and under a moon; less under a high sun and on the
    /// pale page.
    let mistAmount: Double
    /// How strongly a low sun behind the crown shines through its thin
    /// places: from −6° to 18°, fullest from −1° to 8°.
    let backlit: Double
    /// How much of the starfield is out, by the sun: none above −4°, all
    /// of it below −12°.
    let starsOut: Double

    // MARK: The land

    /// The ground: the season's own colour in this hour's light. Through
    /// the golden hour and the twilight the dark appearance's land is
    /// aubergine, not black — an illustrated place keeps colour in its
    /// shadows — and at night it goes back down.
    let ground: OKLab
    /// Snow in the light and on the side away from it. In the low key snow
    /// is not the land's own dark with a little white in it: it is the
    /// palest thing on the ground, blue-white by the sky's light — from a
    /// clear pale by day down to the night's own cap.
    let snowLit: OKLab
    let snowShade: OKLab
    /// Hoar on the ground.
    let frostLit: OKLab

    // MARK: The tree

    /// The tree: ink. (The light print's tree is not text and not land: a
    /// confident warm-dark wood — umber by day, warmer in the low sun,
    /// plum-brown at night — and it may be the darkest thing in the
    /// picture.)
    let ink: OKLab
    /// The side of the wood the lamp is on: rim-lit by the sun, silvered
    /// by the moon.
    let inkLit: OKLab
    /// The crown in leaf: the far side, cool and dark…
    let leafShade: OKLab
    /// …the near masses in three paints (the body; the lighter, yellower
    /// leaf — gold, in autumn; the deeper one — russet)…
    let leafBody: [OKLab]
    /// …their shadowed core, the leaves that catch the lamp, and the
    /// leaves that face the open sky, which take a little of its colour.
    let leafCore: OKLab
    let leafLit: OKLab
    let leafSky: OKLab
    /// The leaf's own colour, lit from within: a turned leaf burns amber,
    /// never pale. Used by `backlit`.
    let leafGlow: OKLab
    let blossom: OKLab
    let blossomShade: OKLab
    let blossomLit: OKLab
    /// Snow on the limbs: a line, not an area — in the low key it keeps a
    /// clear pale all evening and a quiet one at night.
    let snow: OKLab
    /// Frost on the twigs.
    let frost: OKLab
    /// The last leaves of autumn.
    let lastLeaf: OKLab

    // MARK: The palette for a minute

    /// The palette at a given TONE: `presence` (the hush, 0 … 1) and
    /// `depth` (the dimmed room, 0 … 1: `SleepKind.depth`, eased across a
    /// sleep's start and end by `Moment.depth`) are whatever the moment
    /// has made them. `moon` is nil while the moon is down.
    init(sunAltitude: Double, morning: Bool, moon: Moon?, dark: Bool, season: SkySeason,
         presence: Double, depth: Double) {
        let smoothstep = SkyMath.smoothstep
        let lerp = SkyMath.lerp
        self.season = season

        let nightness = 1 - smoothstep(-13, -8, sunAltitude)
        var moonlight = 0.0
        if let moon {
            moonlight = smoothstep(-1.5, 2.5, moon.altitude) * (0.2 + 0.8 * moon.fraction) * nightness
        }
        let air = Air(sunAltitude: sunAltitude, morning: morning, dark: dark, presence: presence, depth: depth,
                      moonlight: moonlight)
        self.nightness = nightness
        self.moonlight = moonlight
        self.air = air

        // Which light the land answers: the sun until it is well down,
        // then the moon.
        let byMoon = sunAltitude < -9.5 && moonlight > 0.02
        lamp = byMoon ? Lamp(kind: .moon, power: moonlight)
            : Lamp(kind: .sun, power: smoothstep(-8, -1, sunAltitude))
        deepNight = dark ? 1 - smoothstep(-10.6, -9.6, sunAltitude) : 0
        starsOut = HillPalette.starsOut(sunAltitude: sunAltitude)
        backlit = smoothstep(-6, -1, sunAltitude) * (1 - smoothstep(8, 18, sunAltitude))
        mistAmount = (0.55 + 0.25 * (morning ? 1 : 0) + 0.15 * season.frost + 0.2 * nightness + 0.25 * moonlight)
            * (1 - 0.35 * smoothstep(8, 30, sunAltitude)) * (dark ? 1 : 0.72)

        // An albedo in this hour's light, in this print: the land's tone
        // moved by how light the albedo is, its colour kept by `keep` at
        // night and wholly by day, tinted by the land's own.
        let litLand = { (albedo: Albedo, keep: Double) -> OKLab in
            let lightness = air.land.lightness + (albedo.lightness - 0.47) * air.gain
            let base = OKLab(lightness: lightness,
                             chroma: albedo.chroma * (dark ? 0.6 : 0.62) * (keep + (1 - keep) * air.day),
                             hueDegrees: albedo.hue)
            return OKLab(lightness: base.lightness, a: base.a + air.land.a * 0.8, b: base.b + air.land.b * 0.8)
        }
        let land = HillPalette.land(in: season)
        var ground = litLand(land.ground, 0.42 + 0.3 * season.grass)
        let dusk = smoothstep(-12, -5, sunAltitude) * (1 - smoothstep(9, 24, sunAltitude))
        if dark {
            ground = OKLab(lightness: ground.lightness + 0.045 * dusk,
                           a: ground.a + 0.034 * dusk * cos(318 * HillPalette.degree),
                           b: ground.b + 0.034 * dusk * sin(318 * HillPalette.degree))
        } else {
            ground = OKLab(lightness: ground.lightness - 0.035 * nightness - 0.02 * dusk,
                           a: ground.a + 0.012 * nightness * cos(275 * HillPalette.degree),
                           b: ground.b + 0.012 * nightness * sin(275 * HillPalette.degree))
        }
        let snowDay = smoothstep(-11, 1, sunAltitude)
        let snowLit: OKLab
        if dark {
            let pale = lerp(0.20, 0.52, snowDay)
            snowLit = OKLab(lightness: pale, chroma: 0.03, hueDegrees: 262)
                .mixed(with: OKLab(lightness: pale, a: air.ambient.a, b: air.ambient.b), by: 0.38)
        } else {
            snowLit = litLand(land.snow, 0.2)
        }
        let frostLit = litLand(land.frost, 0.2)
        ground = ground.mixed(with: frostLit, by: 0.34 * season.frost)
        let snowShade = dark
            ? OKLab(lightness: snowLit.lightness - lerp(0.02, 0.105, snowDay),
                    a: snowLit.a + 0.022 * cos(266 * HillPalette.degree),
                    b: snowLit.b + 0.022 * sin(266 * HillPalette.degree))
            : OKLab(lightness: snowLit.lightness - 0.05,
                    a: snowLit.a + 0.012 * cos(262 * HillPalette.degree),
                    b: snowLit.b + 0.02 * sin(262 * HillPalette.degree))
        self.ground = ground.mixed(with: snowShade, by: season.snow * 0.92)
        self.snowLit = snowLit
        self.snowShade = snowShade
        self.frostLit = frostLit

        // The tree: ink, and the season's paints re-lit by the hour.
        let inkLightness = max(0.045, air.land.lightness * 0.62)
        let lowSun = smoothstep(-6, 0, sunAltitude) * (1 - smoothstep(6, 16, sunAltitude))
        let ink = dark
            ? OKLab(lightness: inkLightness,
                    a: air.land.a * 0.9 + 0.012 * cos(330 * HillPalette.degree) * 0.6,
                    b: air.land.b * 0.9 + 0.012 * sin(330 * HillPalette.degree) * 0.6)
            : OKLab(lightness: 0.375, chroma: 0.040, hueDegrees: 58)
                .mixed(with: OKLab(lightness: 0.345, chroma: 0.055, hueDegrees: 42), by: lowSun)
                .mixed(with: OKLab(lightness: 0.37, chroma: 0.042, hueDegrees: 322), by: nightness)
        self.ink = ink
        let lampLight = byMoon ? air.silver : air.rim
        inkLit = dark
            ? OKLab(lightness: ink.lightness + 0.16, a: ink.a, b: ink.b).mixed(with: lampLight, by: 0.5)
            : OKLab(lightness: ink.lightness + 0.15, a: ink.a * 1.25, b: ink.b * 1.25).mixed(with: lampLight, by: 0.24)

        // A paint of the tree's in this hour's light: lighter or deeper
        // than the land's tone by its own albedo (and `lift`), with half
        // of its own colour at night and all of it by day.
        let paint = { (albedo: Albedo, lift: Double) -> OKLab in
            let own = 0.5 + 0.5 * air.day
            let lightness = (dark ? air.land.lightness + 0.035 : air.land.lightness - 0.225)
                + (albedo.lightness - 0.47) * (dark ? air.gain * 0.9 : 0.62) + lift
            let base = OKLab(lightness: lightness,
                             chroma: albedo.chroma * (dark ? 0.62 : 1.1)
                                 * (dark ? 0.35 + 0.65 * own : 0.55 + 0.45 * own),
                             hueDegrees: albedo.hue)
            let tint = dark ? 0.5 : 0.36
            return OKLab(lightness: base.lightness, a: base.a + air.land.a * tint, b: base.b + air.land.b * tint)
        }
        let hue = season.leafHue
        let leaf = HillPalette.leaf(hue: hue, variant: .body)
        let lighter = HillPalette.leaf(hue: hue, variant: .lighter)
        let deeper = HillPalette.leaf(hue: hue, variant: .deeper)
        let farSide = HillPalette.leaf(hue: hue, variant: .farSide)
        leafShade = paint(farSide, dark ? 0.02 : -0.02)
        leafBody = [paint(leaf, dark ? 0.03 : 0), paint(lighter, dark ? 0.03 : 0), paint(deeper, dark ? 0.03 : 0)]
        leafCore = paint(deeper, dark ? 0.03 : 0).mixed(with: paint(farSide, dark ? 0.02 : -0.02), by: 0.62)
        leafLit = paint(lighter, dark ? 0.08 : 0.10).mixed(with: air.rim, by: 0.25 * air.rimAmount)
        let openSky = OKLab(lightness: air.land.lightness + (dark ? 0.12 : 0.02), a: air.ambient.a, b: air.ambient.b)
        leafSky = paint(lighter, dark ? 0.085 : 0.07).mixed(with: openSky, by: dark ? 0.32 : 0.16)
        let green = smoothstep(92, 116, leaf.hue)
        leafGlow = OKLab(lightness: dark ? 0.50 : lerp(0.73, 0.82, green),
                         chroma: dark ? 0.12 : lerp(0.155, 0.125, green),
                         hueDegrees: lerp(leaf.hue, 70, 0.45))
        blossom = paint(Albedo(0.93, dark ? 0.10 : 0.06, 357), dark ? 0.15 : 0.05)
        blossomShade = paint(Albedo(0.84, dark ? 0.11 : 0.09, 350), dark ? 0.07 : 0)
        blossomLit = paint(Albedo(0.95, dark ? 0.07 : 0.075, 28), dark ? 0.20 : 0.045)
            .mixed(with: air.rim, by: 0.3 * air.rimAmount)
        if dark {
            let pale = lerp(0.30, 0.70, snowDay)
            snow = OKLab(lightness: pale, chroma: 0.022, hueDegrees: 258)
                .mixed(with: OKLab(lightness: pale, a: air.ambient.a, b: air.ambient.b), by: 0.3)
        } else {
            snow = paint(Albedo(0.96, 0.012, 250), 0.06)
        }
        frost = paint(Albedo(0.88, 0.02, 235), 0)
        lastLeaf = paint(Albedo(0.64, 0.13, 55), dark ? 0.03 : 0.0)
    }

    /// The palette AT REST: the hush is the sun's and the moon's alone
    /// (`presence(sunAltitude:moon:depth:)`), with no event's swell in it,
    /// and the room is as deep as the running sleep makes it (`depth`: 1
    /// for the night's sleep, 0.45 for a nap, 0 awake).
    init(sunAltitude: Double, morning: Bool, moon: Moon?, dark: Bool, season: SkySeason, depth: Double) {
        self.init(sunAltitude: sunAltitude, morning: morning, moon: moon, dark: dark, season: season,
                  presence: HillPalette.presence(sunAltitude: sunAltitude, moon: moon, depth: depth), depth: depth)
    }

    /// Whether the light the land answers is the moon's.
    var byMoon: Bool { lamp.kind == .moon }

    // MARK: Shown

    /// A colour as the land shows it: through the air's hush and dimmed
    /// room (`Air.shown`), and then — in the dark appearance, once the
    /// twilight has gone — held under the night's cap, a lightness of
    /// 0.214. Mist, water, snow, a moonlit shoulder: nothing in the land is
    /// painted lighter than a card. `presence`, when given, holds the
    /// colour above the hush, as the air's does.
    func shown(_ colour: OKLab, presence: Double? = nil) -> OKLab {
        var out = air.shown(colour, presence: presence)
        if deepNight > 0 && out.lightness > HillPalette.nightCap {
            out.lightness = SkyMath.lerp(out.lightness, HillPalette.nightCap, deepNight)
        }
        return out
    }

    /// OKLab lightness of the lightest thing the land may be at night in
    /// the dark appearance (a card, #1C1C1E, is a little over it).
    static let nightCap = 0.214

    // MARK: The hush, at rest

    /// The sun is on its way up: in the first half of the day, or the
    /// second half of the night (the lab's `morning`). Dawn's table is
    /// cooler than dusk's, and the morning has more mist.
    static func isMorning(_ phase: SolarClock.Phase) -> Bool {
        switch phase {
        case .day(let progress): return progress < 0.5
        case .night(let progress): return progress > 0.5
        }
    }

    /// The solar bloom: the sky is quiet ground for most of the day and
    /// opens at sunrise and sunset, by the sun's real altitude — it starts
    /// to open as the sun drops under 10°, is fully open from 2.5° up to
    /// 4.5° under the horizon, and has settled again by −10.5°.
    static func solarBloom(sunAltitude: Double) -> Double {
        let opening = 1 - SkyMath.smoothstep(2.5, 10, sunAltitude)
        let closing = SkyMath.smoothstep(-10.5, -4.5, sunAltitude)
        return opening * closing
    }

    /// A small bloom while a bright moon is low: under 9° (all of it under
    /// 2°), scaled by how full it is (none under 55 % lit), and only once
    /// the sun is well down (none of it above −4°, all of it under −9°).
    /// 0.35 at the most.
    static func moonBloom(moon: Moon?, sunAltitude: Double) -> Double {
        guard let moon else { return 0 }
        let low = 1 - SkyMath.smoothstep(2, 9, moon.altitude)
        let dark = 1 - SkyMath.smoothstep(-9, -4, sunAltitude)
        return 0.35 * low * dark * SkyMath.smoothstep(0.55, 0.95, moon.fraction)
    }

    /// The hush, 0 hushed … 1 itself, for a sun and a moon: the greater of
    /// the two blooms. Asleep takes a third off the solar bloom — a sunset
    /// behind a sleeping baby is still a sunset, just quieter — by the
    /// room's eased `depth`, so at a dawn wake that third comes back over
    /// the same seconds.
    ///
    /// `swell` is an event's own bloom at this instant (bedtime's breath
    /// as his star is lit, the Duo opening), 0 … 1: it opens what is still
    /// closed. The events' curves are not this type's; at rest it is 0.
    static func presence(sunAltitude: Double, moon: Moon?, depth: Double, swell: Double = 0) -> Double {
        let open = max(solarBloom(sunAltitude: sunAltitude) * (1 - 0.35 * depth),
                       moonBloom(moon: moon, sunAltitude: sunAltitude))
        return min(1, open + swell * (1 - open))
    }

    /// How much of the starfield is out, by the sun's altitude: none above
    /// −4°, all of it below −12°.
    static func starsOut(sunAltitude: Double) -> Double {
        1 - SkyMath.smoothstep(-12, -4, sunAltitude)
    }

    // MARK: The season's own colours

    /// A colour as daylight albedo: lightness, chroma, hue in degrees —
    /// the thing's own colour before any hour has lit it.
    struct Albedo: Equatable {
        let lightness: Double
        let chroma: Double
        let hue: Double

        init(_ lightness: Double, _ chroma: Double, _ hue: Double) {
            self.lightness = lightness
            self.chroma = chroma
            self.hue = hue
        }
    }

    /// The land's own colours for a season: the ground — dormant straw
    /// going to the season's green as the grass comes, with a little of
    /// autumn's tan where it has not — and snow and frost, which are the
    /// same all year.
    static func land(in season: SkySeason) -> (ground: Albedo, snow: Albedo, frost: Albedo) {
        let weights = season.weights
        let notSummer = weights.spring / max(1e-6, weights.spring + weights.autumn + weights.winter)
        let green = mixed(mixed(Albedo(0.50, 0.06, 112), Albedo(0.60, 0.085, 128), notSummer),
                          Albedo(0.44, 0.075, 140), weights.summer)
        var ground = mixed(Albedo(0.47, 0.036, 76), green, season.grass)
        ground = mixed(ground, Albedo(0.50, 0.06, 70), 0.5 * weights.autumn * (1 - season.grass * 0.5))
        return (ground, Albedo(0.94, 0.012, 255), Albedo(0.80, 0.014, 240))
    }

    /// The paints of a crown. A crown is not one paint.
    enum LeafVariant: Equatable {
        /// Its body.
        case body
        /// The lighter, yellower leaf (gold, in autumn).
        case lighter
        /// The deeper one (russet).
        case deeper
        /// The far side of the crown: cooler and darker.
        case farSide
    }

    /// The leaf's own colour for the season, by `SkySeason.leafHue`:
    /// 0 fresh spring green · 0.5 deep summer green · 0.8 amber ·
    /// 1 russet, on straight lines between. The variants turn a green leaf
    /// and a turned one opposite ways: the lighter leaf of a green crown
    /// is yellower, of an autumn crown more golden.
    static func leaf(hue: Double, variant: LeafVariant) -> Albedo {
        let stops: [(at: Double, colour: Albedo)] = [
            (0, Albedo(0.70, 0.12, 128)), (0.5, Albedo(0.50, 0.10, 141)),
            (0.8, Albedo(0.70, 0.13, 78)), (1, Albedo(0.56, 0.12, 46)),
        ]
        var base = stops[stops.count - 1].colour
        for index in 0..<(stops.count - 1) where hue <= stops[index + 1].at {
            let t = (hue - stops[index].at) / (stops[index + 1].at - stops[index].at)
            let from = stops[index].colour
            let to = stops[index + 1].colour
            base = Albedo(SkyMath.lerp(from.lightness, to.lightness, t), SkyMath.lerp(from.chroma, to.chroma, t),
                          SkyMath.lerp(from.hue, to.hue, t))
            break
        }
        // 1 a green leaf … 0 a turned one.
        let green = SkyMath.smoothstep(92, 116, base.hue)
        switch variant {
        case .body:
            return base
        case .lighter:
            return Albedo(base.lightness + 0.04, base.chroma * 1.06, base.hue + SkyMath.lerp(9, -10, green))
        case .deeper:
            return Albedo(base.lightness - 0.04, base.chroma * 0.97, base.hue + SkyMath.lerp(-12, 9, green))
        case .farSide:
            return Albedo(base.lightness - 0.15, base.chroma * 0.72, base.hue + SkyMath.lerp(-24, 17, green))
        }
    }

    // MARK: The lab's arithmetic

    /// A degree in radians: the painter turns its own hues by multiplying.
    private static let degree = Double.pi / 180

    /// Two albedos mixed through OKLab (`t` held to 0 … 1), and read back
    /// as lightness, chroma and hue.
    private static func mixed(_ a: Albedo, _ b: Albedo, _ t: Double) -> Albedo {
        let m = OKLab(lightness: a.lightness, chroma: a.chroma, hueDegrees: a.hue)
            .mixed(with: OKLab(lightness: b.lightness, chroma: b.chroma, hueDegrees: b.hue), by: SkyMath.clamped(t))
        return Albedo(m.lightness, SkyMath.hypot(m.a, m.b), atan2(m.b, m.a) / degree)
    }
}
