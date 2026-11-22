import XCTest
@testable import TwoOfUs

/// The air (`Air`) against the painted hill's own (`SkyCoreFixturesAir`,
/// exported from design/sky-lab/skies/hill-painted/air.js `airFor`): a sweep
/// of the sun from −20° to +62° in both appearances, the lab's eight
/// standard hours, the haze, the mist and the hush.
///
/// Two tolerances. What the lab works out in double precision is asserted to
/// twelve decimal places. The sky's samples, and what is mixed from them
/// (`ambient`, the haze, the mist), pass through single precision in the lab
/// and here; on one maths library the two agree to the bit, but on another
/// the last bit of a power can fall the other side of a single's rounding,
/// so they are asserted to a quarter of a millionth — two steps of a single
/// near 1, a hundred times finer than a sixteen-bit pixel.
final class AirTests: XCTestCase {
    private typealias Lab = SkyCoreFixturesAir

    private let close = 1e-12
    private let single = 2.5e-7

    private func air(_ altitude: Double, dark: Bool, morning: Bool = false, presence: Double = 0.3,
                     depth: Double = 0, moonlight: Double = 0) -> Air {
        Air(sunAltitude: altitude, morning: morning, dark: dark, presence: presence, depth: depth,
            moonlight: moonlight)
    }

    private func assertColour(_ colour: OKLab, is cells: ArraySlice<Double>, accuracy: Double, _ what: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        let cells = Array(cells)
        XCTAssertEqual(colour.lightness, cells[0], accuracy: accuracy, "\(what): lightness", file: file, line: line)
        XCTAssertEqual(colour.a, cells[1], accuracy: accuracy, "\(what): a", file: file, line: line)
        XCTAssertEqual(colour.b, cells[2], accuracy: accuracy, "\(what): b", file: file, line: line)
    }

    /// The sky's samples of one fixture row — three singles per elevation —
    /// held against the air's own at that `dx`.
    private func assertSky(_ air: Air, dx: Double, elevations: [Double], cells: ArraySlice<String>, _ what: String,
                           file: StaticString = #filePath, line: UInt = #line) {
        let cells = Array(cells)
        XCTAssertEqual(cells.count, elevations.count * 3, what, file: file, line: line)
        for (index, e) in elevations.enumerated() {
            let lab = cells[(index * 3)..<(index * 3 + 3)].map { Double(Float($0) ?? .nan) }
            assertColour(air.sky(dx: dx, elevation: e), is: lab[...], accuracy: single, "\(what) e \(e)",
                         file: file, line: line)
        }
    }

    // MARK: The lab's numbers

    func testTheAirIsTheLabsThroughTheSweep() {
        let rows = SkyCoreFixture.rows(Lab.instants)
        XCTAssertEqual(rows.count, 110)
        for row in rows {
            let cells = row.map(SkyCoreFixture.number)
            let what = "sun \(row[0])° dark \(row[1]) morning \(row[2])"
            let air = air(cells[0], dark: cells[1] == 1, morning: cells[2] == 1)
            let amounts = [air.night, air.day, air.lastLight, air.glowAmount, air.rimAmount, air.gain,
                           air.cloud.lowAmount, air.cloud.highAmount]
            let names = ["night", "day", "lastLight", "glowAmount", "rimAmount", "gain", "lowAmount", "highAmount"]
            for (index, amount) in amounts.enumerated() {
                XCTAssertEqual(amount, cells[3 + index], accuracy: close, "\(what): \(names[index])")
            }
            let colours: [(String, OKLab, Double)] = [
                ("sun", air.sun, close), ("glow", air.glow, close), ("rim", air.rim, close),
                ("land", air.land, close), ("mist", air.mist, close), ("mistFar", air.mistFar, close),
                ("ambient", air.ambient, single), ("silver", air.silver, close),
                ("lowLit", air.cloud.lowLit, close), ("lowShade", air.cloud.lowShade, close),
                ("highLit", air.cloud.highLit, close), ("highShade", air.cloud.highShade, close),
            ]
            for (index, colour) in colours.enumerated() {
                let at = 11 + index * 3
                assertColour(colour.1, is: cells[at..<(at + 3)], accuracy: colour.2, "\(what): \(colour.0)")
            }
        }
    }

    func testTheSkyIsTheLabsThroughTheSweep() {
        let elevations = SkyCoreFixture.rows(Lab.skySweepElevations).map { SkyCoreFixture.number($0[0]) }
        let rows = SkyCoreFixture.rows(Lab.skySweep)
        XCTAssertEqual(rows.count, 550)
        for row in rows {
            let air = air(SkyCoreFixture.number(row[0]), dark: row[1] == "1", morning: row[2] == "1")
            assertSky(air, dx: SkyCoreFixture.number(row[3]), elevations: elevations, cells: row[4...],
                      "sun \(row[0])° dark \(row[1]) morning \(row[2]) dx \(row[3])")
        }
    }

    func testTheSkyIsTheLabsAtTheEightStandardHours() {
        // 06:50, 09:30, 12:30, 16:10, 16:40, 17:30, 21:00 and 03:00 on
        // 21 November 2026 in Chicago, with the hush the lab gives each:
        // a close grid, from left of the sun to two pages right of it and
        // from under the horizon to past the zenith.
        let elevations = SkyCoreFixture.rows(Lab.skyHoursElevations).map { SkyCoreFixture.number($0[0]) }
        XCTAssertEqual(elevations.count, 18)
        for stop in Air.elevations { XCTAssertTrue(elevations.contains(stop), "every stop of a column is sampled") }
        var airs: [String: Air] = [:]
        let hours = SkyCoreFixture.rows(Lab.hours)
        XCTAssertEqual(hours.count, 16)
        for hour in hours {
            airs["\(hour[0]) \(hour[1])"] = air(SkyCoreFixture.number(hour[2]), dark: hour[1] == "1", morning: hour[3] == "1",
                                                presence: SkyCoreFixture.number(hour[4]), depth: SkyCoreFixture.number(hour[5]))
        }
        let rows = SkyCoreFixture.rows(Lab.skyHours)
        XCTAssertEqual(rows.count, 16 * 11)
        var samples = 0
        var toTheBit = 0
        for row in rows {
            guard let air = airs["\(row[0]) \(row[1])"] else { return XCTFail("no hour \(row[0])") }
            let dx = SkyCoreFixture.number(row[2])
            assertSky(air, dx: dx, elevations: elevations, cells: row[3...], "\(row[0]) dark \(row[1]) dx \(row[2])")
            // The lab keeps a sample in single precision, and so does the
            // air: nearly every number is the lab's to the bit (all of them
            // where the two share a maths library).
            for (index, e) in elevations.enumerated() {
                let sky = air.sky(dx: dx, elevation: e)
                for (channel, value) in [sky.lightness, sky.a, sky.b].enumerated() {
                    samples += 1
                    if value == Double(Float(row[3 + index * 3 + channel]) ?? .nan) { toTheBit += 1 }
                }
            }
        }
        XCTAssertEqual(samples, 16 * 11 * 18 * 3)
        XCTAssertGreaterThan(Double(toTheBit), 0.99 * Double(samples))
    }

    func testTheHazeIsTheLabs() {
        let rows = SkyCoreFixture.rows(Lab.haze)
        XCTAssertEqual(rows.count, 82 * 6)
        for row in rows {
            let cells = row.map(SkyCoreFixture.number)
            assertColour(air(cells[0], dark: cells[1] == 1).haze(dx: cells[2]), is: cells[3...], accuracy: single,
                         "sun \(row[0])° dark \(row[1]) dx \(row[2])")
        }
    }

    func testTheMistIsTheLabs() {
        let rows = SkyCoreFixture.rows(Lab.mist)
        XCTAssertEqual(rows.count, 9 * 2 * 3 * 4)
        for row in rows {
            let cells = row.map(SkyCoreFixture.number)
            let air = air(cells[0], dark: cells[1] == 1, morning: cells[2] == 1, moonlight: cells[3])
            assertColour(air.mist(fromLight: cells[4], fromSun: cells[5]), is: cells[6...], accuracy: single, "\(row)")
        }
    }

    func testEveryColourLeavesThroughTheHushAndTheDimmedRoom() {
        let rows = SkyCoreFixture.rows(Lab.shown)
        XCTAssertEqual(rows.count, 6 * 2 * 7 * 3)
        for row in rows {
            let cells = row.map(SkyCoreFixture.number)
            let air = air(cells[0], dark: cells[1] == 1, presence: cells[2], depth: cells[3])
            XCTAssertEqual(air.presence, cells[5], accuracy: close, "\(row): the presence the air keeps")
            let colour = OKLab(lightness: cells[6], a: cells[7], b: cells[8])
            // As the painter asks: its own presence, or one held above the
            // hush (`max(air.presence, 0.6)` for a cloud, 0.82 for the tree).
            let out = row[4] == "own" ? air.shown(colour) : air.shown(colour, presence: max(air.presence, cells[4]))
            assertColour(out, is: cells[9...], accuracy: close, "\(row)")
        }
    }

    // MARK: The design's rules

    func testNothingTurnsUntilTheSunIsUnderFifteen() {
        // "The long hushed day is one palette." From 15° up, in either
        // appearance, every colour of the table and the whole sky are what
        // they are at noon. (The sun's own disc is not the table's: it
        // goes on paling to 30°. And `day`, the land's own colour, has all
        // of itself from 16°.)
        for dark in [true, false] {
            let noon = air(60, dark: dark)
            for altitude in [15.0, 16, 22.5, 30, 45] {
                let then = air(altitude, dark: dark)
                XCTAssertEqual(then.glow, noon.glow, "\(altitude)")
                XCTAssertEqual(then.rim, noon.rim, "\(altitude)")
                XCTAssertEqual(then.land, noon.land, "\(altitude)")
                XCTAssertEqual(then.mist, noon.mist, "\(altitude)")
                XCTAssertEqual(then.mistFar, noon.mistFar, "\(altitude)")
                XCTAssertEqual(then.cloud, noon.cloud, "\(altitude)")
                XCTAssertEqual(then.ambient, noon.ambient, "\(altitude)")
                for dx in [-0.5, 0, 0.4, 1.5] {
                    for e in [0, 0.1, 0.5, 1, 2] {
                        XCTAssertEqual(then.sky(dx: dx, elevation: e), noon.sky(dx: dx, elevation: e), "\(altitude)")
                    }
                }
            }
            XCTAssertNotEqual(air(14, dark: dark).sky(dx: 0, elevation: 0.1), noon.sky(dx: 0, elevation: 0.1),
                              "under 15° it has begun to turn")
            XCTAssertEqual(air(16, dark: dark).day, 1, accuracy: close)
            XCTAssertEqual(air(-2, dark: dark).day, 0, accuracy: close)
        }
    }

    func testDawnIsTheSameTableCoolerWithLessEmber() {
        // A warm colour gives up an eighth of its chroma in the morning;
        // a cool one is the same at either end of the day. At sunset's own
        // key the glow is an ember; the night's key has nothing warm in it.
        for dark in [true, false] {
            let dusk = air(-0.8, dark: dark, morning: false)
            let dawn = air(-0.8, dark: dark, morning: true)
            XCTAssertEqual(dawn.glow.chroma, dusk.glow.chroma * 0.88, accuracy: 1e-9, "dark \(dark)")
            XCTAssertEqual(dawn.rim.chroma, dusk.rim.chroma * 0.88, accuracy: 1e-9, "dark \(dark)")
            XCTAssertNotEqual(dawn.glow.hue, dusk.glow.hue, "and its hue has turned")
            // (In the low key its value is untouched; the high key prints
            // a quieter colour a little lighter, as it does any pastel.)
            if dark {
                XCTAssertEqual(dawn.glow.lightness, dusk.glow.lightness, accuracy: close)
            } else {
                XCTAssertGreaterThan(dawn.glow.lightness, dusk.glow.lightness)
            }
            // The land is not printed, and has no dawn of its own.
            XCTAssertEqual(dawn.land, dusk.land)

            let night = air(-20, dark: dark, morning: false)
            let small = air(-20, dark: dark, morning: true)
            let cells = { (c: OKLab) in [c.lightness, c.a, c.b][...] }
            assertColour(small.glow, is: cells(night.glow), accuracy: close, "glow")
            assertColour(small.mist, is: cells(night.mist), accuracy: close, "mist")
            assertColour(small.cloud.highShade, is: cells(night.cloud.highShade), accuracy: close, "cloud")
            assertColour(small.sky(dx: 0.3, elevation: 0.2), is: cells(night.sky(dx: 0.3, elevation: 0.2)),
                         accuracy: single, "sky")
        }
    }

    func testThePalePagesSkyStaysWhereGreyTextCanBeRead() {
        // In the looked-up pose the header's words stand on the upper sky.
        // The light appearance's sky is floored at a lightness of 0.876,
        // at every hour, everywhere within a page of the sun (beyond it
        // the earth's shadow is let a little under).
        let elevations = SkyCoreFixture.rows(Lab.skySweepElevations).map { SkyCoreFixture.number($0[0]) }
        var lowest = 1.0
        for row in SkyCoreFixture.rows(Lab.skySweep) where row[1] == "0" {
            let dx = SkyCoreFixture.number(row[3])
            guard abs(dx) <= 0.95 else { continue }
            let air = air(SkyCoreFixture.number(row[0]), dark: false, morning: row[2] == "1")
            for e in elevations { lowest = min(lowest, air.sky(dx: dx, elevation: e).lightness) }
        }
        XCTAssertGreaterThanOrEqual(lowest, 0.876 - 1e-6)
        XCTAssertLessThan(lowest, 0.88, "and the floor is reached: the night's zenith stands on it")
    }

    func testTheLowKeysSkyDeepensTowardTheZenith() {
        // Above the everyday view the dark appearance's sky runs on a
        // little deeper and quieter — and a clear shade deeper while there
        // is still light in it, so that his stars show on a summer bedtime.
        for altitude in [-18.0, -9, -4, 2.5, 8, 30] {
            let air = air(altitude, dark: true)
            let top = air.sky(dx: 0, elevation: 1)
            let zenith = air.sky(dx: 0, elevation: Air.zenith)
            XCTAssertLessThan(zenith.lightness, top.lightness, "\(altitude)")
            XCTAssertLessThan(zenith.chroma, top.chroma, "\(altitude)")
        }
        let drop = { (altitude: Double) -> Double in
            let air = self.air(altitude, dark: true)
            return air.sky(dx: 0, elevation: 1).lightness - air.sky(dx: 0, elevation: Air.zenith).lightness
        }
        XCTAssertEqual(drop(-18), 0.028, accuracy: 1e-4, "at night: 0.016 + 0.012")
        XCTAssertEqual(drop(8), 0.080, accuracy: 1e-4, "with light in the sky: 0.016 + 0.064")
        // The pale page's is not deepened at all, only quietened.
        let pale = air(8, dark: false)
        XCTAssertLessThan(pale.sky(dx: 0, elevation: Air.zenith).chroma, pale.sky(dx: 0, elevation: 1).chroma)
    }

    func testTheBandsStandTallOverTheSunAndSinkAwayFromIt() {
        // The arch. Close beside the sun (before the far column begins to
        // take over, at a tenth of a page) the sky at an elevation is the
        // sky over the sun at a HIGHER one: the bands have sunk. The lean
        // is 1 − (1 − e)^(1/arch), with the arch 1 over the sun, falling
        // to 0.44 far from it over 0.60 of a page.
        let sunset = air(-0.8, dark: true, presence: 1)
        let dx = 0.09
        let arch = 0.44 + (1 - 0.44) * exp(-(dx * dx) / (0.60 * 0.60))
        XCTAssertLessThan(arch, 1)
        for e in [0.05, 0.2, 0.4, 0.7] {
            let leaning = 1 - pow(1 - e, 1 / arch)
            XCTAssertGreaterThan(leaning, e)
            let beside = sunset.sky(dx: dx, elevation: e)
            let over = sunset.sky(dx: 0, elevation: leaning)
            XCTAssertEqual(beside.lightness, over.lightness, accuracy: 1e-6, "e \(e)")
            XCTAssertEqual(beside.a, over.a, accuracy: 1e-6, "e \(e)")
            XCTAssertEqual(beside.b, over.b, accuracy: 1e-6, "e \(e)")
        }
        // Only the table's own span leans; the sky above the everyday
        // view is one sky.
        for e in [1.0, 1.4, 2.0, Air.zenith] {
            XCTAssertEqual(sunset.sky(dx: dx, elevation: e), sunset.sky(dx: 0, elevation: e), "e \(e)")
        }
        // Under the horizon is the horizon; past the zenith is the zenith.
        XCTAssertEqual(sunset.sky(dx: 0.3, elevation: -0.4), sunset.sky(dx: 0.3, elevation: 0))
        XCTAssertEqual(sunset.sky(dx: 0.3, elevation: 3), sunset.sky(dx: 0.3, elevation: Air.zenith))
        // …and the sky is the same either side of the sun.
        XCTAssertEqual(sunset.sky(dx: -0.8, elevation: 0.3), sunset.sky(dx: 0.8, elevation: 0.3))
    }

    func testTheEarthsShadowStandsAwayFromTheSunAfterSunset() {
        // Beyond 0.95 of a page from the sun, low over the horizon, from
        // sunset until the sun is 9.5° down: a slate-blue. It is not there
        // by day, nor at night, nor near the sun, nor high up — there the
        // sky is the two columns' own mix and nothing else.
        let far = 2.0
        let low = 0.02
        // How far two colours stand apart, the largest of the three.
        let apart = { (p: OKLab, q: OKLab) -> Double in
            max(abs(p.lightness - q.lightness), abs(p.a - q.a), abs(p.b - q.b))
        }
        let slate = { (altitude: Double) -> Bool in
            // With the shadow in it, the far sky is no longer the far
            // column alone (which is all it is, two pages from the sun).
            let air = self.air(altitude, dark: true, presence: 1)
            return apart(air.sky(dx: far, elevation: low), air.sky(dx: 1.36, elevation: low)) > 1e-4
        }
        XCTAssertTrue(slate(-4))
        XCTAssertTrue(slate(-0.8))
        XCTAssertFalse(slate(8), "not by day")
        XCTAssertFalse(slate(1.5), "not until the sun is at the horizon")
        XCTAssertFalse(slate(-9.5), "gone by −9.5°")
        XCTAssertFalse(slate(-18), "not at night")
        let dusk = air(-4, dark: true, presence: 1)
        XCTAssertLessThan(apart(dusk.sky(dx: far, elevation: 0.3), dusk.sky(dx: 1.36, elevation: 0.3)), 1e-6,
                          "not above its own height")
        // The shadow is deeper than the far column it stands in.
        XCTAssertLessThan(dusk.sky(dx: far, elevation: low).lightness, dusk.sky(dx: 1.36, elevation: low).lightness)
    }

    func testTheSunsDiscIsAPaleCreamOnThePalePage() {
        // "On the pale page a light is LIGHTER than the paper round it and
        // the colour is in what surrounds it": a pale cream at every
        // height, a breath warmer as it sets. In the dark appearance it is
        // its own colour, down to an ember.
        var last = 0.0
        for altitude in stride(from: 60.0, through: -6, by: -1.5) {
            let pale = air(altitude, dark: false).sun
            XCTAssertGreaterThanOrEqual(pale.lightness, 0.955 - 1e-9, "\(altitude)")
            XCTAssertLessThanOrEqual(pale.chroma, 0.06 + 1e-9, "\(altitude)")
            XCTAssertGreaterThanOrEqual(pale.chroma, last - 1e-9, "warmer as it sets (\(altitude))")
            last = pale.chroma
        }
        let cream = OKLab(lightness: 0.992, chroma: 0.02, hueDegrees: 95)
        assertColour(air(40, dark: false).sun, is: [cream.lightness, cream.a, cream.b][...], accuracy: close, "high")
        let ember = OKLab(lightness: 0.62, chroma: 0.17, hueDegrees: 40)
        assertColour(air(-5, dark: true).sun, is: [ember.lightness, ember.a, ember.b][...], accuracy: close, "set")
        let gold = OKLab(lightness: 0.895, chroma: 0.125, hueDegrees: 78)
        assertColour(air(8, dark: true).sun, is: [gold.lightness, gold.a, gold.b][...], accuracy: close, "low")
    }

    func testMoonlightIsSilverWhateverTheSunDoes() {
        // The night key's lightest value, cooled: one colour per
        // appearance, the same at every hour. Mist under a full moon is
        // half silver.
        for dark in [true, false] {
            let silver = air(-18, dark: dark).silver
            for altitude in [-11.0, -4, 2.5, 30] { XCTAssertEqual(air(altitude, dark: dark).silver, silver) }
            XCTAssertEqual(silver.hue, 255 * Double.pi / 180 - 2 * .pi, accuracy: 1e-9, "a cool blue")
        }
        let moonless = air(-18, dark: true, moonlight: 0)
        let full = air(-18, dark: true, moonlight: 1)
        // At the light itself the mist is its lit tint, and 18 % haze.
        let haze = moonless.haze(dx: 0.4)
        let expectMoonless = moonless.mist.mixed(with: haze, by: 0.18)
        let expectFull = full.mist.mixed(with: full.silver, by: 0.5).mixed(with: haze, by: 0.18)
        XCTAssertEqual(moonless.mist(fromLight: 0, fromSun: 0.4), expectMoonless)
        XCTAssertEqual(full.mist(fromLight: 0, fromSun: 0.4), expectFull)
        // The moon lights the mist; it does not touch the sky.
        XCTAssertEqual(full.sky(dx: 0.2, elevation: 0.3), moonless.sky(dx: 0.2, elevation: 0.3))
    }

    func testTheHushNeverLightensTheDarkAppearance() {
        // Dark: hushed means dimmer and greyer, never lighter — 12 % nearer
        // black and two fifths of the chroma at full hush; the dimmed room
        // takes 14 % of the light that is left and 12 % of the chroma.
        let colour = OKLab(lightness: 0.5, a: 0.04, b: -0.08)
        let itself = air(-3, dark: true, presence: 1, depth: 0)
        XCTAssertEqual(itself.shown(colour), colour, "at full presence, awake, a colour is itself")

        let hushed = air(-3, dark: true, presence: 0, depth: 0).shown(colour)
        XCTAssertEqual(hushed.lightness, 0.5 * 0.88, accuracy: close)
        XCTAssertEqual(hushed.chroma, colour.chroma * 0.4, accuracy: close)
        XCTAssertEqual(hushed.hue, colour.hue, accuracy: 1e-9, "its hue is kept")

        let asleep = air(-3, dark: true, presence: 1, depth: 1).shown(colour)
        XCTAssertEqual(asleep.lightness, 0.5 * 0.86, accuracy: close)
        XCTAssertEqual(asleep.chroma, colour.chroma * 0.88, accuracy: close)

        let nap = air(-3, dark: true, presence: 1, depth: 0.45).shown(colour)
        XCTAssertLessThan(nap.lightness, colour.lightness)
        XCTAssertGreaterThan(nap.lightness, asleep.lightness, "a nap dims the room less than the night")
        for presence in stride(from: 0.0, through: 1, by: 0.1) {
            for depth in [0.0, 0.45, 1] {
                XCTAssertLessThanOrEqual(air(-3, dark: true, presence: presence, depth: depth).shown(colour).lightness,
                                         colour.lightness)
            }
        }
    }

    func testThePalePagesHushGoesTowardThePageByDayAndOnlyGreysAtNight() {
        let colour = OKLab(lightness: 0.6, a: 0.05, b: -0.06)
        // By day: 55 % of the way to the page's lightness (the lab's
        // 0.9612) at a fifth of the chroma — today's sky's own hush.
        let day = air(30, dark: false, presence: 0, depth: 0).shown(colour)
        XCTAssertEqual(day.lightness, 0.6 + (0.9612 - 0.6) * 0.55, accuracy: close)
        XCTAssertEqual(day.chroma, colour.chroma * 0.2, accuracy: close)
        // At night: a tenth of the way, and 62 % of the chroma — "a
        // storybook night on pale paper keeps its lilac".
        let night = air(-18, dark: false, presence: 0, depth: 0).shown(colour)
        XCTAssertEqual(night.lightness, 0.6 + (0.9612 - 0.6) * 0.10, accuracy: close)
        XCTAssertEqual(night.chroma, colour.chroma * 0.62, accuracy: close)
        // At full presence, awake, a colour is itself at any hour.
        XCTAssertEqual(air(30, dark: false, presence: 1, depth: 0).shown(colour), colour)
        XCTAssertEqual(air(-18, dark: false, presence: 1, depth: 0).shown(colour), colour)
        // The dimmed room: a breath deeper (0.012) and a quarter greyer.
        let asleep = air(-18, dark: false, presence: 1, depth: 1).shown(colour)
        XCTAssertEqual(asleep.lightness, 0.6 - 0.012, accuracy: close)
        XCTAssertEqual(asleep.chroma, colour.chroma * 0.75, accuracy: close)
        // The tree is held above the hush: asked at 0.82, it keeps more of
        // itself than the sky round it does.
        let hushed = air(30, dark: false, presence: 0.1, depth: 0)
        XCTAssertGreaterThan(hushed.shown(colour, presence: 0.82).chroma, hushed.shown(colour).chroma)
        XCTAssertLessThan(hushed.shown(colour, presence: 0.82).lightness, hushed.shown(colour).lightness)
    }

    func testThePresenceIsHeldBetweenHushedAndItself() {
        XCTAssertEqual(air(5, dark: true, presence: 1.4).presence, 1)
        XCTAssertEqual(air(5, dark: true, presence: -0.2).presence, 0)
        XCTAssertEqual(air(5, dark: true, presence: 1.4), air(5, dark: true, presence: 1))
    }

    func testTheSameInstantIsTheSameAir() {
        // Nothing is stored and nothing is random: the air is a value.
        XCTAssertEqual(air(-3.2, dark: true, morning: true, presence: 0.7, depth: 0.45, moonlight: 0.2),
                       air(-3.2, dark: true, morning: true, presence: 0.7, depth: 0.45, moonlight: 0.2))
        XCTAssertNotEqual(air(-3.2, dark: true), air(-3.2, dark: false))
        XCTAssertNotEqual(air(-3.2, dark: true), air(-3.3, dark: true))
    }
}
