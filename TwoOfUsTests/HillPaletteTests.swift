import XCTest
@testable import TwoOfUs

/// The palette for a minute (`HillPalette`) against the painted hill's own
/// (`SkyCoreFixturesPalette`: `resolve` in design/sky-lab/skies/
/// hill-painted.js, run in the lab's page): the lab's eight standard hours
/// on its default day, in each of the four seasons and while the leaves
/// turn, a summer's day hour by hour, a November dusk and dawn and the last
/// of that dusk's light, asleep, and under a bright moon — in both
/// appearances, 220 minutes.
///
/// Tolerances as in `AirTests`: twelve decimal places, and a quarter of a
/// millionth for the paints that have the sky's ambient colour in them
/// (snow in the dark appearance, the ground under it, the leaves that face
/// the sky), which the lab keeps in single precision.
final class HillPaletteTests: XCTestCase {
    private typealias Lab = SkyCoreFixturesPalette

    private let close = 1e-12
    private let single = 2.5e-7

    /// One minute of the lab's table, read by column name.
    private struct Minute {
        let cells: [String]
        let columns: [String: Int]

        func text(_ name: String) -> String { cells[columns[name] ?? 0] }
        func number(_ name: String) -> Double { SkyCoreFixture.number(text(name)) }
        func colour(_ name: String) -> [Double] { ["L", "A", "B"].map { number(name + $0) } }

        var what: String { "\(text("group")) \(text("date")) \(text("time")) dark \(text("dark")) \(text("asleep"))" }
        var dark: Bool { text("dark") == "1" }
        var altitude: Double { number("altitude") }
        var morning: Bool { text("morning") == "1" }
        var moon: HillPalette.Moon? {
            text("moonAltitude") == "down" ? nil
                : HillPalette.Moon(altitude: number("moonAltitude"), fraction: number("moonFraction"))
        }
        var season: SkySeason { SkySeason.on(dayOfYear: number("dayOfYear"), latitude: number("latitude")) }

        /// The palette at rest for this minute, as the app would ask for it.
        var palette: HillPalette {
            HillPalette(sunAltitude: altitude, morning: morning, moon: moon, dark: dark, season: season,
                        depth: number("depth"))
        }
    }

    private var minutes: [Minute] {
        let names = SkyCoreFixture.rows(Lab.minutesColumns)[0]
        let columns = Dictionary(uniqueKeysWithValues: names.enumerated().map { ($1, $0) })
        return SkyCoreFixture.rows(Lab.minutes).map { Minute(cells: $0, columns: columns) }
    }

    private func assertColour(_ colour: OKLab, is cells: [Double], accuracy: Double, _ what: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(colour.lightness, cells[0], accuracy: accuracy, "\(what): lightness", file: file, line: line)
        XCTAssertEqual(colour.a, cells[1], accuracy: accuracy, "\(what): a", file: file, line: line)
        XCTAssertEqual(colour.b, cells[2], accuracy: accuracy, "\(what): b", file: file, line: line)
    }

    private func july() -> SkySeason { SkySeason.on(dayOfYear: 185, latitude: 41.88) }
    private func january() -> SkySeason { SkySeason.on(dayOfYear: 15, latitude: 41.88) }
    private func november() -> SkySeason { SkySeason.on(dayOfYear: 325, latitude: 41.88) }

    private func palette(_ altitude: Double, dark: Bool, season: SkySeason? = nil, moon: HillPalette.Moon? = nil,
                         morning: Bool = false, depth: Double = 0) -> HillPalette {
        HillPalette(sunAltitude: altitude, morning: morning, moon: moon, dark: dark, season: season ?? november(),
                    depth: depth)
    }

    // MARK: The lab's numbers

    func testThePaletteIsTheLabsMinuteByMinute() {
        let minutes = minutes
        XCTAssertEqual(minutes.count, 220)
        for minute in minutes {
            let what = minute.what
            let palette = minute.palette
            // The season the test built is the one the lab painted with.
            XCTAssertEqual(palette.season.snow, minute.number("seasonSnow"), accuracy: close, what)
            XCTAssertEqual(palette.season.frost, minute.number("seasonFrost"), accuracy: close, what)
            XCTAssertEqual(palette.season.grass, minute.number("seasonGrass"), accuracy: close, what)
            XCTAssertEqual(palette.season.leafHue, minute.number("seasonLeafHue"), accuracy: close, what)

            let amounts: [(String, Double)] = [
                ("nightness", palette.nightness), ("moonlight", palette.moonlight), ("deepNight", palette.deepNight),
                ("lampPower", palette.lamp.power), ("mistAmount", palette.mistAmount), ("backlit", palette.backlit),
                ("starsOut", palette.starsOut),
            ]
            for (name, amount) in amounts {
                XCTAssertEqual(amount, minute.number(name), accuracy: close, "\(what): \(name)")
            }
            XCTAssertEqual(palette.lamp.kind.rawValue, minute.text("lamp"), what)
            XCTAssertEqual(palette.byMoon, minute.text("byMoon") == "1", what)

            let paints: [(String, OKLab, Double)] = [
                ("ground", palette.ground, single), ("snowLit", palette.snowLit, single),
                ("snowShade", palette.snowShade, single), ("frostLit", palette.frostLit, close),
                ("ink", palette.ink, close), ("inkLit", palette.inkLit, close),
                ("leafShade", palette.leafShade, close), ("leafBody0", palette.leafBody[0], close),
                ("leafBody1", palette.leafBody[1], close), ("leafBody2", palette.leafBody[2], close),
                ("leafCore", palette.leafCore, close), ("leafLit", palette.leafLit, close),
                ("leafSky", palette.leafSky, single), ("leafGlow", palette.leafGlow, close),
                ("blossom", palette.blossom, close), ("blossomShade", palette.blossomShade, close),
                ("blossomLit", palette.blossomLit, close), ("snow", palette.snow, single),
                ("frost", palette.frost, close), ("lastLeaf", palette.lastLeaf, close),
            ]
            XCTAssertEqual(palette.leafBody.count, 3)
            for (name, paint, accuracy) in paints {
                assertColour(paint, is: minute.colour(name), accuracy: accuracy, "\(what): \(name)")
            }

            // The air it was mixed in is the air the lab asked for.
            assertColour(palette.air.land, is: minute.colour("airLand"), accuracy: close, "\(what): the air's land")
            assertColour(palette.air.rim, is: minute.colour("airRim"), accuracy: close, "\(what): the air's rim")
            XCTAssertEqual(palette.air.presence, minute.number("airPresence"), accuracy: close, what)
            XCTAssertEqual(palette.air.depth, minute.number("airDepth"), accuracy: close, what)
            XCTAssertEqual(palette.air.moonlight, minute.number("airMoonlight"), accuracy: close, what)
        }
    }

    func testTheFixtureHoldsEveryKindOfMinute() {
        // The sweep the pins above stand on: the sun from far under the
        // horizon to 60° and more over it, both appearances, all four
        // seasons, a moon up and down, the land lit by the moon, asleep.
        let minutes = minutes
        XCTAssertLessThan(minutes.map(\.altitude).min() ?? 0, -18)
        XCTAssertGreaterThan(minutes.map(\.altitude).max() ?? 0, 60)
        XCTAssertEqual(minutes.filter(\.dark).count, minutes.count / 2)
        XCTAssertEqual(Set(minutes.map { $0.season.name }), [.winter, .spring, .summer, .autumn])
        XCTAssertGreaterThan(minutes.filter { $0.moon == nil }.count, 40)
        XCTAssertGreaterThan(minutes.filter { $0.text("byMoon") == "1" }.count, 30)
        XCTAssertGreaterThan(minutes.filter { $0.number("seasonSnow") > 0.9 }.count, 10)
        XCTAssertEqual(Set(minutes.map { $0.text("asleep") }), ["awake", "nap", "night"])
        XCTAssertEqual(Set(minutes.map { $0.number("depth") }), [0, 0.45, 1],
                       "the room's depth: awake, a nap, the night")
        // The eight standard hours, on five days.
        let hours = Set(minutes.filter { $0.text("group") == "hours-default" }.map { $0.text("time") })
        XCTAssertEqual(hours, ["06:50", "09:30", "12:30", "16:10", "16:40", "17:30", "21:00", "03:00"])
        XCTAssertEqual(minutes.filter { $0.text("group").hasPrefix("hours-") }.count, 8 * 2 * 6)
        // The last of a dusk's light, where the night's own rules come in:
        // the sun between 9.6° and 10.6° down, and a crown half turned.
        XCTAssertTrue(minutes.contains { $0.dark && $0.number("deepNight") > 0.1 && $0.number("deepNight") < 0.9 })
        XCTAssertTrue(minutes.contains { $0.number("seasonLeafHue") > 0.6 && $0.number("seasonLeafHue") < 0.73 })
    }

    func testTheHushAtRestIsTheLabs() {
        // lab/presence.js: the sun's bloom, the moon's, the two together
        // with a third off the sun's while he sleeps, and the stars.
        for minute in minutes {
            let what = minute.what
            XCTAssertEqual(HillPalette.solarBloom(sunAltitude: minute.altitude), minute.number("solarBloom"),
                           accuracy: close, what)
            XCTAssertEqual(HillPalette.moonBloom(moon: minute.moon, sunAltitude: minute.altitude),
                           minute.number("moonBloom"), accuracy: close, what)
            XCTAssertEqual(HillPalette.presence(sunAltitude: minute.altitude, moon: minute.moon,
                                                depth: minute.number("depth")),
                           minute.number("presence"), accuracy: close, what)
            XCTAssertEqual(HillPalette.starsOut(sunAltitude: minute.altitude), minute.number("stars"),
                           accuracy: close, what)
        }
    }

    func testMorningIsTheFirstHalfOfTheDayAndTheSecondHalfOfTheNight() {
        for minute in minutes {
            let progress = minute.number("sunProgress")
            let phase: SolarClock.Phase = minute.text("sunNight") == "1" ? .night(progress) : .day(progress)
            XCTAssertEqual(HillPalette.isMorning(phase), minute.morning, minute.what)
        }
        XCTAssertTrue(HillPalette.isMorning(.day(0.2)))
        XCTAssertFalse(HillPalette.isMorning(.day(0.5)))
        XCTAssertFalse(HillPalette.isMorning(.night(0.5)))
        XCTAssertTrue(HillPalette.isMorning(.night(0.9)))
    }

    func testWhatTheLandShowsIsTheLabs() {
        let colours = SkyCoreFixture.rows(Lab.shownColours).map { row in
            OKLab(lightness: SkyCoreFixture.number(row[0]), a: SkyCoreFixture.number(row[1]), b: SkyCoreFixture.number(row[2]))
        }
        XCTAssertEqual(colours.count, 2)
        for minute in minutes {
            let palette = minute.palette
            assertColour(palette.shown(colours[0]), is: minute.colour("shownA"), accuracy: close, minute.what)
            assertColour(palette.shown(colours[1]), is: minute.colour("shownB"), accuracy: close, minute.what)
            // …and held above the hush, as the tree's painter asks for it
            // on the pale page: at a presence of 0.82 at the least.
            assertColour(palette.shown(colours[0], presence: max(palette.air.presence, 0.82)),
                         is: minute.colour("shownHeld"), accuracy: close, minute.what)
        }
    }

    // MARK: The design's rules

    func testTheDarkNightsLandIsNeverLighterThanACard() {
        // "Dark appearance at night stays dark: once the twilight has gone,
        // nothing in the land (mist, water, snow, a moonlit shoulder) is
        // painted lighter than a card." A card is #1C1C1E, luminance
        // 0.0117; the cap is a lightness of 0.214.
        let card = OKLab(OKLab.SRGB(hex: 0x1C1C1E))
        XCTAssertLessThan(HillPalette.nightCap, card.lightness)
        XCTAssertLessThan(OKLab(lightness: HillPalette.nightCap, a: 0, b: 0).luminance, 0.0117)
        let white = OKLab(lightness: 1, a: 0, b: 0)
        var nights = 0
        for minute in minutes where minute.dark {
            let palette = minute.palette
            if minute.altitude < -10.6 {
                nights += 1
                XCTAssertEqual(palette.deepNight, 1, accuracy: close, minute.what)
                XCTAssertLessThanOrEqual(palette.shown(white).lightness, HillPalette.nightCap + 1e-12, minute.what)
                XCTAssertLessThanOrEqual(palette.shown(palette.snowLit).lightness, HillPalette.nightCap + 1e-12)
                XCTAssertLessThanOrEqual(palette.shown(white, presence: 1).lightness, HillPalette.nightCap + 1e-12,
                                         "held above the hush, it is still under the cap")
            } else if minute.altitude > -9.6 {
                XCTAssertEqual(palette.deepNight, 0, accuracy: close, minute.what)
                XCTAssertEqual(palette.shown(white), palette.air.shown(white), minute.what)
            }
        }
        XCTAssertGreaterThan(nights, 30)
        // The cap comes in over a degree of the sun's going, from −9.6° to
        // −10.6°: half way through, a colour is most of the way to it.
        let coming = palette(-10.1, dark: true)
        XCTAssertEqual(coming.deepNight, 0.5, accuracy: close)
        XCTAssertEqual(palette(-9.6, dark: true).deepNight, 0, accuracy: close)
        XCTAssertEqual(palette(-10.6, dark: true).deepNight, 1, accuracy: close)
        let uncapped = coming.air.shown(white).lightness
        XCTAssertEqual(coming.shown(white).lightness, (uncapped + HillPalette.nightCap) / 2, accuracy: close)
        // A colour already under the cap is left as the air shows it.
        let deep = OKLab(lightness: 0.15, a: 0.01, b: -0.02)
        XCTAssertEqual(palette(-18, dark: true).shown(deep), palette(-18, dark: true).air.shown(deep))
        // The pale page has no such cap.
        let pale = palette(-18, dark: false)
        XCTAssertEqual(pale.deepNight, 0)
        XCTAssertEqual(pale.shown(white), pale.air.shown(white))
        // Held above the hush, a colour is the air's at that presence.
        let day = palette(40, dark: false)
        let leaf = OKLab(lightness: 0.5, a: -0.05, b: 0.06)
        XCTAssertEqual(day.shown(leaf, presence: 0.82), day.air.shown(leaf, presence: 0.82))
        XCTAssertNotEqual(day.shown(leaf, presence: 0.82), day.shown(leaf))
    }

    func testTheLandAnswersTheSunUntilItIsWellDownThenTheMoon() {
        let full = HillPalette.Moon(altitude: 40, fraction: 1)
        // By day and through the twilight: the sun, whatever the moon.
        XCTAssertEqual(palette(20, dark: true, moon: full).lamp, HillPalette.Lamp(kind: .sun, power: 1))
        XCTAssertEqual(palette(-5, dark: true, moon: full).lamp.kind, .sun)
        XCTAssertEqual(palette(-8, dark: true, moon: full).lamp.power, 0, accuracy: close, "the sun has no power left")
        // From −9.5°, with a moon to speak of: the moon, as strong as it
        // lights the night.
        let moonlit = palette(-14, dark: true, moon: full)
        XCTAssertEqual(moonlit.lamp, HillPalette.Lamp(kind: .moon, power: 1))
        XCTAssertTrue(moonlit.byMoon)
        XCTAssertEqual(moonlit.moonlight, 1, accuracy: close)
        XCTAssertEqual(palette(-9.4, dark: true, moon: full).lamp.kind, .sun, "not until the sun is 9.5° down")
        XCTAssertEqual(palette(-9.6, dark: true, moon: full).lamp.kind, .moon)
        // A thin, low moon lights less; a moon that is down, nothing — and
        // the lamp is then still the sun's, with no power.
        let thin = palette(-14, dark: true, moon: HillPalette.Moon(altitude: 40, fraction: 0.1))
        XCTAssertEqual(thin.moonlight, 0.2 + 0.8 * 0.1, accuracy: close)
        XCTAssertEqual(palette(-14, dark: true, moon: nil).lamp, HillPalette.Lamp(kind: .sun, power: 0))
        XCTAssertFalse(palette(-14, dark: true, moon: HillPalette.Moon(altitude: -1.5, fraction: 1)).byMoon,
                       "a moon on its way under the horizon no longer lights the land")
        // The moon lights nothing while the sun is up.
        XCTAssertEqual(palette(3, dark: true, moon: full).moonlight, 0, accuracy: close)
        // The wood's lit side is rim-light by the sun and silver by the moon.
        let sunlit = palette(-14, dark: true, moon: nil)
        XCTAssertNotEqual(moonlit.inkLit, sunlit.inkLit)
        let ink = moonlit.ink
        XCTAssertEqual(moonlit.inkLit, OKLab(lightness: ink.lightness + 0.16, a: ink.a, b: ink.b)
            .mixed(with: moonlit.air.silver, by: 0.5))
    }

    func testSnowIsThePalestThingOnTheDarkGround() {
        // "Snow in the low key is not the land's own dark with a little
        // white in it: it is the palest thing on the ground … from a clear
        // pale by day and at sunset down to the night's own cap."
        for altitude in [30.0, 8, 1, -4, -11, -18] {
            let winter = palette(altitude, dark: true, season: january())
            let bare = palette(altitude, dark: true, season: november())
            XCTAssertGreaterThan(winter.snowLit.lightness, bare.ground.lightness + 0.05, "\(altitude)")
            XCTAssertGreaterThan(winter.snowLit.lightness, winter.snowShade.lightness, "\(altitude)")
            XCTAssertGreaterThan(winter.ground.lightness, bare.ground.lightness,
                                 "the ground under snow is paler (\(altitude))")
            XCTAssertLessThan(winter.snowLit.b, 0, "blue-white (\(altitude))")
        }
        XCTAssertEqual(palette(30, dark: true, season: january()).snowLit.lightness, 0.52, accuracy: close,
                       "a clear pale by day")
        let night = palette(-18, dark: true, season: january())
        XCTAssertEqual(night.snowLit.lightness, 0.20, accuracy: close, "down to the night's own")
        XCTAssertLessThanOrEqual(night.shown(night.snowLit).lightness, HillPalette.nightCap)
        // Snow lies from mid-December to early March; in July the ground
        // has none of the snow's shade in it.
        XCTAssertEqual(january().snow, 1, accuracy: close)
        XCTAssertEqual(july().snow, 0, accuracy: close)
    }

    func testTheDarkLandKeepsColourInItsShadowsThroughTheTwilight() {
        // "Through the golden hour and the twilight the dark appearance's
        // land is aubergine, not black. (At night it goes back down.)"
        // The aubergine is a lift of 0.045 in lightness (and 0.034 of
        // chroma at 318°), in full from −5° to 9°, gone by −12° and by
        // 24°. The lift is what the ground has over the land's tone moved
        // by the season's own albedo:
        let season = july()
        let albedo = HillPalette.land(in: season).ground
        let lift = { (p: HillPalette) -> Double in
            p.ground.lightness - (p.air.land.lightness + (albedo.lightness - 0.47) * p.air.gain)
        }
        for altitude in [-5.0, -0.8, 2, 9] {
            XCTAssertEqual(lift(palette(altitude, dark: true, season: season)), 0.045, accuracy: 1e-9, "\(altitude)")
        }
        for altitude in [-18.0, -12, 24, 40] {
            XCTAssertEqual(lift(palette(altitude, dark: true, season: season)), 0, accuracy: 1e-9, "\(altitude)")
        }
        XCTAssertLessThan(palette(-18, dark: true, season: season).ground.lightness, 0.12, "at night it goes back down")
        // The pale page's land has no such lift: toward night it goes a
        // little deeper instead (0.035 at night, 0.02 through the dusk).
        XCTAssertEqual(lift(palette(-18, dark: false, season: season)), -0.035, accuracy: 1e-9)
        XCTAssertEqual(lift(palette(2, dark: false, season: season)), -0.02, accuracy: 1e-9)
        XCTAssertEqual(lift(palette(40, dark: false, season: season)), 0, accuracy: 1e-9)
    }

    func testTheGroundIsTheSeasons() {
        // The land's own colours: dormant straw in winter, the season's
        // green as the grass comes, a little of autumn's tan where it has
        // not.
        let straw = HillPalette.land(in: january()).ground
        XCTAssertEqual(straw.lightness, 0.47, accuracy: 1e-9)
        XCTAssertEqual(straw.chroma, 0.036, accuracy: 1e-9)
        XCTAssertEqual(straw.hue, 76, accuracy: 1e-6, "mid-January, no grass and no autumn in it: straw itself")

        let summer = HillPalette.land(in: july()).ground
        XCTAssertGreaterThan(summer.hue, 125, "green")
        XCTAssertLessThan(summer.hue, 141)
        XCTAssertGreaterThan(summer.chroma, 0.07)

        let autumn = HillPalette.land(in: november()).ground
        XCTAssertLessThan(autumn.hue, 80, "late November: tan")
        XCTAssertGreaterThan(autumn.chroma, straw.chroma)

        // Snow and frost are the same all year.
        for season in [january(), july(), november()] {
            XCTAssertEqual(HillPalette.land(in: season).snow, HillPalette.Albedo(0.94, 0.012, 255))
            XCTAssertEqual(HillPalette.land(in: season).frost, HillPalette.Albedo(0.80, 0.014, 240))
        }
        // In the light of day the summer ground is greener than winter's
        // bare straw, in either appearance (a negative `a` is green).
        for dark in [true, false] {
            let green = palette(40, dark: dark, season: july()).ground
            let bare = palette(40, dark: dark, season: SkySeason.on(dayOfYear: 75, latitude: 41.88)).ground
            XCTAssertLessThan(green.a, bare.a, "dark \(dark)")
        }
    }

    func testALeafGoesFromFreshGreenThroughDeepGreenToAmberAndRusset() {
        // `SkySeason.leafHue`: 0 fresh spring green · 0.5 deep summer green
        // · 0.8 amber · 1 russet.
        XCTAssertEqual(HillPalette.leaf(hue: 0, variant: .body), HillPalette.Albedo(0.70, 0.12, 128))
        XCTAssertEqual(HillPalette.leaf(hue: 0.5, variant: .body), HillPalette.Albedo(0.50, 0.10, 141))
        XCTAssertEqual(HillPalette.leaf(hue: 1, variant: .body), HillPalette.Albedo(0.56, 0.12, 46))
        let amber = HillPalette.leaf(hue: 0.8, variant: .body)
        XCTAssertEqual(amber.lightness, 0.70, accuracy: close)
        XCTAssertEqual(amber.hue, 78, accuracy: 1e-9)
        // Between the stops, a straight line.
        XCTAssertEqual(HillPalette.leaf(hue: 0.25, variant: .body).lightness, 0.60, accuracy: close)
        XCTAssertEqual(HillPalette.leaf(hue: 0.9, variant: .body).hue, 62, accuracy: 1e-9)

        // A crown is not one paint: a lighter leaf, a deeper one, and the
        // far side — cooler and darker, with less colour.
        for hue in [0.0, 0.3, 0.5, 0.8, 1] {
            let body = HillPalette.leaf(hue: hue, variant: .body)
            let lighter = HillPalette.leaf(hue: hue, variant: .lighter)
            let deeper = HillPalette.leaf(hue: hue, variant: .deeper)
            XCTAssertEqual(lighter.lightness, body.lightness + 0.04, accuracy: close)
            XCTAssertEqual(deeper.lightness, body.lightness - 0.04, accuracy: close)
            let far = HillPalette.leaf(hue: hue, variant: .farSide)
            XCTAssertEqual(far.lightness, body.lightness - 0.15, accuracy: close)
            XCTAssertEqual(far.chroma, body.chroma * 0.72, accuracy: close)
        }
        // The lighter leaf of a green crown is yellower (10° toward
        // yellow); of a turned crown, more golden (9° away from red).
        XCTAssertEqual(HillPalette.leaf(hue: 0.5, variant: .lighter).hue, 141 - 10, accuracy: 1e-9)
        XCTAssertEqual(HillPalette.leaf(hue: 1, variant: .lighter).hue, 46 + 9, accuracy: 1e-9)
        // …and the far side of a green crown is bluer, of a turned one redder.
        XCTAssertEqual(HillPalette.leaf(hue: 0.5, variant: .farSide).hue, 141 + 17, accuracy: 1e-9)
        XCTAssertEqual(HillPalette.leaf(hue: 1, variant: .farSide).hue, 46 - 24, accuracy: 1e-9)
        // A leaf is "green" from a hue of 116° up and "turned" from 92°
        // down; half way between (104°) the variants turn half each way.
        let turning: Double = 0.5 + 0.3 * (37.0 / 63.0)       // (141 − 104) of the 63° from deep green to amber
        XCTAssertEqual(HillPalette.leaf(hue: turning, variant: .body).hue, 104, accuracy: 1e-9)
        XCTAssertEqual(HillPalette.leaf(hue: turning, variant: .lighter).hue, 104 - 0.5, accuracy: 1e-9)
        XCTAssertEqual(HillPalette.leaf(hue: turning, variant: .deeper).hue, 104 - 1.5, accuracy: 1e-9)
        XCTAssertEqual(HillPalette.leaf(hue: turning, variant: .farSide).hue, 104 - 3.5, accuracy: 1e-9)
    }

    func testThePalePagesTreeIsAWarmDarkWood() {
        // "Umber by day, warmer in the low sun, plum-brown at night — and
        // it may be the darkest thing in the picture."
        let day = palette(40, dark: false).ink
        let lowSun = palette(3, dark: false).ink
        let night = palette(-18, dark: false).ink
        XCTAssertEqual(day, OKLab(lightness: 0.375, chroma: 0.040, hueDegrees: 58))
        XCTAssertEqual(lowSun.lightness, 0.345, accuracy: 1e-9)
        XCTAssertGreaterThan(lowSun.chroma, day.chroma, "warmer in the low sun")
        XCTAssertEqual(night.lightness, 0.37, accuracy: 1e-9)
        XCTAssertLessThan(night.b, 0, "plum at night")
        for altitude in [40.0, 3, -18] {
            let pale = palette(altitude, dark: false)
            XCTAssertLessThan(pale.ink.lightness, pale.ground.lightness - 0.3, "darker than the land (\(altitude))")
        }
        // In the dark appearance the ink is the land's own dark, deeper:
        // 62 % of its tone, and never under 0.045.
        let dusk = palette(-3, dark: true)
        XCTAssertEqual(dusk.ink.lightness, max(0.045, dusk.air.land.lightness * 0.62), accuracy: close)
        XCTAssertEqual(palette(-7.5, dark: true).ink.lightness, 0.045, accuracy: close, "the floor, at dusk's own key")
    }

    func testMistGathersInTheMorningAndAtNight() {
        // 0.55 of it at an afternoon's rest; a quarter more in the
        // morning, more after a frost, at night and under a moon; a third
        // less under a high sun; and the pale page carries 72 % of it.
        let season = july()
        XCTAssertEqual(palette(5, dark: true, season: season).mistAmount, 0.55, accuracy: close)
        XCTAssertEqual(palette(5, dark: true, season: season, morning: true).mistAmount, 0.80, accuracy: close)
        XCTAssertEqual(palette(-18, dark: true, season: season).mistAmount, 0.75, accuracy: close)
        let full = HillPalette.Moon(altitude: 40, fraction: 1)
        XCTAssertEqual(palette(-18, dark: true, season: season, moon: full).mistAmount, 1.0, accuracy: close)
        XCTAssertEqual(palette(40, dark: true, season: season).mistAmount, 0.55 * 0.65, accuracy: close)
        XCTAssertEqual(palette(5, dark: false, season: season).mistAmount, 0.55 * 0.72, accuracy: close)
        XCTAssertGreaterThan(palette(5, dark: true, season: november()).mistAmount, 0.55, "frost on the ground")
    }

    func testAsleepTakesAThirdOffTheSunsBloom() {
        // "A sunset behind a sleeping baby is still a sunset, just
        // quieter." At sunset the sky is fully open (1); asleep for the
        // night it is 0.65; in a nap, 1 − 0.35 × 0.45.
        XCTAssertEqual(HillPalette.presence(sunAltitude: 0, moon: nil, depth: 0), 1, accuracy: close)
        XCTAssertEqual(HillPalette.presence(sunAltitude: 0, moon: nil, depth: 1), 0.65, accuracy: close)
        XCTAssertEqual(HillPalette.presence(sunAltitude: 0, moon: nil, depth: 0.45), 1 - 0.35 * 0.45, accuracy: close)
        // The sky is quiet ground for most of the day, and at night.
        XCTAssertEqual(HillPalette.presence(sunAltitude: 30, moon: nil, depth: 0), 0, accuracy: close)
        XCTAssertEqual(HillPalette.presence(sunAltitude: 10, moon: nil, depth: 0), 0, accuracy: close)
        XCTAssertEqual(HillPalette.presence(sunAltitude: -10.5, moon: nil, depth: 0), 0, accuracy: close)
        XCTAssertEqual(HillPalette.solarBloom(sunAltitude: 2.5), 1, accuracy: close)
        XCTAssertEqual(HillPalette.solarBloom(sunAltitude: -4.5), 1, accuracy: close)
        // A low, full moon opens it a little, once the sun is well down;
        // the sleeping room does not quieten the moon's bloom.
        let lowFull = HillPalette.Moon(altitude: 1, fraction: 1)
        XCTAssertEqual(HillPalette.presence(sunAltitude: -20, moon: lowFull, depth: 0), 0.35, accuracy: close)
        XCTAssertEqual(HillPalette.presence(sunAltitude: -20, moon: lowFull, depth: 1), 0.35, accuracy: close)
        XCTAssertEqual(HillPalette.moonBloom(moon: HillPalette.Moon(altitude: 30, fraction: 1), sunAltitude: -20), 0,
                       accuracy: close, "not a high moon")
        XCTAssertEqual(HillPalette.moonBloom(moon: HillPalette.Moon(altitude: 1, fraction: 0.5), sunAltitude: -20), 0,
                       accuracy: close, "not a half moon")
        XCTAssertEqual(HillPalette.moonBloom(moon: lowFull, sunAltitude: -3), 0, accuracy: close, "not in the twilight")
    }

    func testAnEventsSwellOpensWhatIsStillClosed() {
        // Bedtime's breath of bloom is 0.55 at its peak (lab/presence.js,
        // `EVENTS`): on a night sky that is hushed, it opens it to 0.55; on
        // a sky half open already, half of the rest; on an open one,
        // nothing more. The curves are the moment's, not this type's.
        XCTAssertEqual(HillPalette.presence(sunAltitude: -20, moon: nil, depth: 0, swell: 0.55), 0.55, accuracy: close)
        let half = HillPalette.presence(sunAltitude: -7.5, moon: nil, depth: 0)
        XCTAssertEqual(half, 0.5, accuracy: close)
        XCTAssertEqual(HillPalette.presence(sunAltitude: -7.5, moon: nil, depth: 0, swell: 0.55), 0.5 + 0.55 * 0.5,
                       accuracy: close)
        XCTAssertEqual(HillPalette.presence(sunAltitude: 0, moon: nil, depth: 0, swell: 0.55), 1, accuracy: close)
        XCTAssertEqual(HillPalette.presence(sunAltitude: 0, moon: nil, depth: 0, swell: 0), 1, accuracy: close)
    }

    func testThePaletteAtRestIsThePaletteAtTheRestingTone() {
        // The tone can be given (the moment's, mid-event) or left at rest.
        let moon = HillPalette.Moon(altitude: 3, fraction: 0.9)
        let atRest = HillPalette(sunAltitude: -14, morning: false, moon: moon, dark: true, season: january(), depth: 1)
        let presence = HillPalette.presence(sunAltitude: -14, moon: moon, depth: 1)
        XCTAssertGreaterThan(presence, 0)
        XCTAssertEqual(atRest, HillPalette(sunAltitude: -14, morning: false, moon: moon, dark: true, season: january(),
                                           presence: presence, depth: 1))
        // The paints are the table's and do not move with the tone: only
        // what is SHOWN does.
        let open = HillPalette(sunAltitude: -14, morning: false, moon: moon, dark: true, season: january(),
                               presence: 1, depth: 0)
        XCTAssertEqual(open.ground, atRest.ground)
        XCTAssertEqual(open.leafBody, atRest.leafBody)
        let ember = OKLab(lightness: 0.18, a: 0.03, b: 0.02)
        XCTAssertNotEqual(open.shown(ember), atRest.shown(ember))
    }

    func testTheStarsComeOutByTheSun() {
        XCTAssertEqual(HillPalette.starsOut(sunAltitude: -4), 0, accuracy: close)
        XCTAssertEqual(HillPalette.starsOut(sunAltitude: -12), 1, accuracy: close)
        XCTAssertEqual(HillPalette.starsOut(sunAltitude: -8), 0.5, accuracy: close)
        // At first light (−7°) a third of their light is still out: the
        // figure the count's turn at −4° was chosen by (`NightCount`).
        XCTAssertEqual(HillPalette.starsOut(sunAltitude: -7), 0.316, accuracy: 0.001)
        XCTAssertEqual(palette(-7, dark: true).starsOut, HillPalette.starsOut(sunAltitude: -7))
    }
}
