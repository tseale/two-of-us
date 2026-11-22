import XCTest
@testable import TwoOfUs

/// The painted hill's colour maths (`OKLab`) against the sky lab's own
/// (`SkyCoreFixturesColour`, exported from design/sky-lab/lab/oklab.js,
/// skies/hill-painted/air.js and `heldTo` in skies/hill-painted.js): a few
/// thousand colours each way, and every helper the sky reaches for.
///
/// The port is the lab's arithmetic, so the two agree to the last few bits
/// of a power or a cube root; what is asserted is twelve decimal places.
/// Beside the numbers, each test states the design's rule in its own terms
/// — a colour no display can show gives up chroma, never hue — so a change
/// to the lab that kept the fixture regenerating but broke the rule would
/// still be caught here.
final class OKLabTests: XCTestCase {
    private typealias Lab = SkyCoreFixturesColour

    private let close = 1e-12

    private func numbers(_ row: [String]) -> [Double] { row.map(SkyCoreFixture.number) }

    private func srgb(hex cell: String) -> OKLab.SRGB {
        OKLab.SRGB(hex: UInt32(cell, radix: 16) ?? 0)
    }

    private func assertColour(_ colour: OKLab, is cells: ArraySlice<Double>, _ what: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        let cells = Array(cells)
        XCTAssertEqual(colour.lightness, cells[0], accuracy: close, "\(what): lightness", file: file, line: line)
        XCTAssertEqual(colour.a, cells[1], accuracy: close, "\(what): a", file: file, line: line)
        XCTAssertEqual(colour.b, cells[2], accuracy: close, "\(what): b", file: file, line: line)
    }

    private func assertColour(_ colour: OKLab.SRGB, is cells: ArraySlice<Double>, _ what: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        let cells = Array(cells)
        XCTAssertEqual(colour.red, cells[0], accuracy: close, "\(what): red", file: file, line: line)
        XCTAssertEqual(colour.green, cells[1], accuracy: close, "\(what): green", file: file, line: line)
        XCTAssertEqual(colour.blue, cells[2], accuracy: close, "\(what): blue", file: file, line: line)
    }

    /// A hue's distance from another, the short way round, in radians.
    private func turn(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 2 * .pi)
        return min(d, 2 * .pi - d)
    }

    // MARK: To OKLab

    func testADisplayColourGoesToOKLabAsTheLabTakesIt() {
        let rows = SkyCoreFixture.rows(Lab.fromSRGB)
        XCTAssertEqual(rows.count, 1516)
        for row in rows {
            assertColour(OKLab(srgb(hex: row[0])), is: numbers(row)[1...], "#\(row[0])")
        }
    }

    func testBlackIsNoLightAndWhiteIsAllOfIt() {
        let black = OKLab(OKLab.SRGB(hex: 0x000000))
        let white = OKLab(OKLab.SRGB(hex: 0xFFFFFF))
        XCTAssertEqual(black.lightness, 0, accuracy: 1e-9)
        XCTAssertEqual(white.lightness, 1, accuracy: 1e-7)
        // A grey has no colour: every one in the lab's table stands on the
        // lightness axis.
        for hex: UInt32 in [0x000000, 0x010101, 0x0A0A0A, 0x808080, 0xFFFFFF] {
            XCTAssertLessThan(OKLab(OKLab.SRGB(hex: hex)).chroma, 1e-6, String(hex, radix: 16))
        }
    }

    func testChromaAndHueAreTheLabs() {
        let rows = SkyCoreFixture.rows(Lab.oklch)
        XCTAssertEqual(rows.count, 300)
        var coloured = 0
        for row in rows {
            let cells = numbers(row)
            let colour = OKLab(srgb(hex: row[0]))
            XCTAssertEqual(colour.lightness, cells[1], accuracy: close, row[0])
            XCTAssertEqual(colour.chroma, cells[2], accuracy: close, row[0])
            // A grey's hue is the angle of a rounding error and means
            // nothing; everything else has the lab's.
            guard cells[2] > 1e-3 else { continue }
            coloured += 1
            XCTAssertEqual(colour.hue, cells[3], accuracy: 1e-9, row[0])
            // …and lightness, chroma and hue make the same colour again.
            let again = OKLab(lightness: colour.lightness, chroma: colour.chroma, hue: colour.hue)
            XCTAssertEqual(again.a, colour.a, accuracy: close, row[0])
            XCTAssertEqual(again.b, colour.b, accuracy: close, row[0])
        }
        XCTAssertGreaterThan(coloured, 280)
    }

    func testAHueInDegreesIsTheTablesWay() {
        // The air table writes [value, chroma, hue°]: 40° an ember, 90° a
        // pale gold, 262° the night's blue.
        for row in SkyCoreFixture.rows(Lab.lch) {
            let cells = numbers(row)
            assertColour(OKLab(lightness: cells[0], chroma: cells[1], hueDegrees: cells[2]), is: cells[3...],
                         row.prefix(3).joined(separator: " "))
        }
        let ember = OKLab(lightness: 0.8, chroma: 0.1, hueDegrees: 40)
        XCTAssertGreaterThan(ember.a, 0)
        XCTAssertGreaterThan(ember.b, 0)
        let night = OKLab(lightness: 0.8, chroma: 0.1, hueDegrees: 262)
        XCTAssertLessThan(night.b, -0.09, "blue")
        XCTAssertEqual(ember.chroma, 0.1, accuracy: close)
        XCTAssertEqual(ember.hue, 40 * Double.pi / 180, accuracy: close)
    }

    // MARK: Back to the display

    func testAColourThatFitsComesBackAsItWent() {
        // Every display colour, to OKLab and back by either hand, is the
        // same eight-bit colour it was.
        for row in SkyCoreFixture.rows(Lab.fromSRGB) {
            let hex = UInt32(row[0], radix: 16) ?? 0
            let levels = [Int((hex >> 16) & 0xFF), Int((hex >> 8) & 0xFF), Int(hex & 0xFF)]
            let colour = OKLab(OKLab.SRGB(hex: hex))
            XCTAssertEqual(colour.srgb(.sky).levels, levels, "#\(row[0]) by the sky's fit")
            XCTAssertEqual(colour.srgb(.skyLab).levels, levels, "#\(row[0]) by the lab's fit")
        }
    }

    func testAColourNoDisplayCanShowGivesUpChromaNeverHue() {
        let rows = SkyCoreFixture.rows(Lab.toSRGB)
        XCTAssertEqual(rows.count, 1500)
        var fitted = 0
        var asItWas = 0
        for row in rows {
            let cells = numbers(row)
            let asked = OKLab(lightness: cells[0], a: cells[1], b: cells[2])
            let shown = asked.srgb(.skyLab)
            assertColour(shown, is: cells[3...], row.prefix(3).joined(separator: " "))

            // The rule itself, on colours that have a hue to keep and light
            // enough for it to be seen. (Near black it holds only loosely:
            // the lab lets a channel stand a ten-thousandth outside 0 … 1
            // before it gives up chroma, and in a colour of lightness 0.1
            // that allowance is a tenth of a radian of hue.)
            guard asked.lightness > 0.35, asked.lightness < 0.95, asked.chroma > 0.02 else { continue }
            let back = OKLab(shown)
            if back.chroma < asked.chroma - 1e-3 {
                fitted += 1
                XCTAssertEqual(back.lightness, asked.lightness, accuracy: 0.002, "\(row): its value is kept")
                if back.chroma > 0.02 {
                    XCTAssertLessThan(turn(back.hue, asked.hue), 0.02, "\(row): its hue is kept")
                }
            } else {
                asItWas += 1
                // (to a thousandth: a colour that stands inside the lab's
                // allowance but outside 0 … 1 is clipped by it)
                XCTAssertEqual(back.lightness, asked.lightness, accuracy: 1e-3, "\(row): it fits")
                XCTAssertEqual(back.a, asked.a, accuracy: 1e-3, "\(row): it fits")
                XCTAssertEqual(back.b, asked.b, accuracy: 1e-3, "\(row): it fits")
            }
        }
        XCTAssertGreaterThan(fitted, 250, "the table holds colours that had to give up chroma")
        XCTAssertGreaterThan(asItWas, 250, "and colours that fit as they are")
    }

    func testLightnessChromaAndHueComeBackToTheDisplay() {
        // `fromOklch`: the hue in radians, any number of turns.
        for row in SkyCoreFixture.rows(Lab.fromOklch) {
            let cells = numbers(row)
            assertColour(OKLab(lightness: cells[0], chroma: cells[1], hue: cells[2]).srgb(.skyLab), is: cells[3...],
                         row.prefix(3).joined(separator: " "))
        }
    }

    func testTheSkyPaintsWithItsOwnFit() {
        // air.js `toRgb`: what every colour of the painted hill goes
        // through on its way to the display.
        let rows = SkyCoreFixture.rows(Lab.skySRGB)
        XCTAssertEqual(rows.count, 900)
        for row in rows {
            let cells = numbers(row)
            let colour = OKLab(lightness: cells[0], a: cells[1], b: cells[2])
            let what = row.prefix(3).joined(separator: " ")
            assertColour(colour.srgb(.sky), is: cells[3...5], what)
            XCTAssertEqual(colour.srgb(), colour.srgb(.sky), "\(what): the sky's fit is the one a caller gets")
            XCTAssertEqual(colour.luminance, cells[6], accuracy: close, "\(what): luminance")
            XCTAssertEqual(colour.srgb(.sky).levels, cells[7...9].map { Int($0) }, "\(what): levels")
        }
    }

    func testALightAboveWhiteIsWhiteInTheSkysHand() {
        // The air table writes its lights above 1 (the sun's 1.9, a lit
        // cloud's 1.2). The sky's fit holds the lightness to white first,
        // so such a light is white — and a value under black is black.
        XCTAssertEqual(OKLab(lightness: 1.9, a: 0, b: 0).srgb(.sky), OKLab(lightness: 1, a: 0, b: 0).srgb(.sky))
        XCTAssertEqual(OKLab(lightness: 1.9, a: 0, b: 0).srgb(.sky).levels, [255, 255, 255])
        XCTAssertEqual(OKLab(lightness: -0.1, a: 0, b: 0).srgb(.sky).levels, [0, 0, 0])
        // With colour in it, it is the colour AT white's lightness, fitted:
        // the same as asking for lightness 1.
        let sun = OKLab(lightness: 1.9, chroma: 0.085, hueDegrees: 84)
        XCTAssertEqual(sun.srgb(.sky), OKLab(lightness: 1, a: sun.a, b: sun.b).srgb(.sky))
    }

    func testTheTwoFitsPartOnlyWhereAColourDoesNotFit() {
        // Fourteen halvings against eighteen: where a colour fits and its
        // lightness is a display's, the two hands give the same colour to
        // the last bit; where it had to give up chroma they part by less
        // than a thousandth.
        var same = 0
        var parted = 0
        for row in SkyCoreFixture.rows(Lab.toSRGB) {
            let cells = numbers(row)
            let colour = OKLab(lightness: cells[0], a: cells[1], b: cells[2])
            guard colour.lightness >= 0, colour.lightness <= 1 else { continue }
            let sky = colour.srgb(.sky)
            let lab = colour.srgb(.skyLab)
            if OKLab(lab).chroma > colour.chroma - 1e-6 {
                XCTAssertEqual(sky, lab, "\(row)")
                same += 1
            } else {
                XCTAssertEqual(sky.red, lab.red, accuracy: 1e-3, "\(row)")
                XCTAssertEqual(sky.green, lab.green, accuracy: 1e-3, "\(row)")
                XCTAssertEqual(sky.blue, lab.blue, accuracy: 1e-3, "\(row)")
                if sky != lab { parted += 1 }
            }
        }
        XCTAssertGreaterThan(same, 400)
        XCTAssertGreaterThan(parted, 300)
    }

    func testLuminanceIsTheLimitsOwnNumber() {
        // WCAG's: white 1, black 0, a card in the dark appearance 0.0117
        // (BRIEF.md, "no area below the top band lighter than a card").
        XCTAssertEqual(OKLab(OKLab.SRGB(hex: 0xFFFFFF)).luminance, 1, accuracy: 1e-6)
        XCTAssertEqual(OKLab(OKLab.SRGB(hex: 0x000000)).luminance, 0, accuracy: 1e-12)
        XCTAssertEqual(OKLab(OKLab.SRGB(hex: 0x1C1C1E)).luminance, 0.0117, accuracy: 5e-5)
        // The grey line's two colours, as the brief has them.
        let greyOnLight = OKLab(OKLab.SRGB(hex: 0x6C6C70)).luminance
        let greyOnDark = OKLab(OKLab.SRGB(hex: 0x98989F)).luminance
        XCTAssertEqual((0.55 + 0.05) / (greyOnLight + 0.05), 3, accuracy: 0.35,
                       "a sky of luminance 0.55 is about 3 : 1 behind the grey line")
        XCTAssertGreaterThan((greyOnDark + 0.05) / (0.072 + 0.05), 3, "and one of 0.072 in the dark appearance")
    }

    func testLevelsRoundToTheNearestAndAHalfGoesUp() {
        for row in SkyCoreFixture.rows(Lab.levels) {
            let cells = numbers(row)
            XCTAssertEqual(OKLab.SRGB(red: cells[0], green: cells[1], blue: cells[2]).levels,
                           cells[3...5].map { Int($0) }, "\(row)")
        }
        XCTAssertEqual(OKLab.SRGB(red: 0.5 / 255, green: 1.5 / 255, blue: 254.5 / 255).levels, [1, 2, 255])
        XCTAssertEqual(OKLab.SRGB(red: -0.2, green: 1.2, blue: 0.5).levels, [0, 255, 128])
    }

    // MARK: Mixing

    func testAMixGoesStraightThroughOKLab() {
        let rows = SkyCoreFixture.rows(Lab.mixOk)
        XCTAssertEqual(rows.count, 301)
        for row in rows {
            let cells = numbers(row)
            assertColour(srgb(hex: row[0]).mixed(with: srgb(hex: row[1]), by: cells[2]), is: cells[3...],
                         row.prefix(3).joined(separator: " "))
        }
    }

    func testBlueGoesToOrangeThroughRoseAndLilacNotGreyGreen() {
        // The lab's own reason for mixing here: half way from a blue to an
        // orange the mix still has colour, and it is on the red side of
        // grey and the blue side of yellow — a dusky lilac-rose. (Green
        // would be a negative `a`.)
        let blue = OKLab.SRGB(hex: 0x2F6FDE)
        let orange = OKLab.SRGB(hex: 0xF28C28)
        let mixed = OKLab(blue.mixed(with: orange, by: 0.5))
        XCTAssertGreaterThan(mixed.a, 0.02, "toward red, not green")
        XCTAssertLessThan(mixed.b, 0, "toward blue, not yellow")
        XCTAssertGreaterThan(mixed.chroma, 0.03, "and not a grey")
        // The mix is the midpoint of the two in OKLab, exactly.
        let from = OKLab(blue)
        let to = OKLab(orange)
        XCTAssertEqual(mixed.lightness, (from.lightness + to.lightness) / 2, accuracy: 1e-6)
        XCTAssertEqual(mixed.a, (from.a + to.a) / 2, accuracy: 1e-6)
        XCTAssertEqual(mixed.b, (from.b + to.b) / 2, accuracy: 1e-6)
        // …and a mix is held to its two ends.
        XCTAssertEqual(blue.mixed(with: orange, by: -3), blue.mixed(with: orange, by: 0))
        XCTAssertEqual(blue.mixed(with: orange, by: 7), blue.mixed(with: orange, by: 1))
    }

    func testAStraightMixMayRunPastItsEnds() {
        // air.js `mix3`: `t` is not held.
        for row in SkyCoreFixture.rows(Lab.mix3) {
            let cells = numbers(row)
            let a = OKLab(lightness: cells[0], a: cells[1], b: cells[2])
            let b = OKLab(lightness: cells[3], a: cells[4], b: cells[5])
            assertColour(a.mixed(with: b, by: cells[6]), is: cells[7...], "\(row)")
        }
        let a = OKLab(lightness: 0.2, a: 0, b: 0)
        let b = OKLab(lightness: 0.4, a: 0.1, b: 0)
        XCTAssertEqual(a.mixed(with: b, by: 1.5).lightness, 0.5, accuracy: close)
        XCTAssertEqual(a.mixed(with: b, by: 0), a)
    }

    func testARampIsMixedBetweenTheTwoStopsItFallsBetween() {
        let stops = SkyCoreFixture.rows(Lab.rampStops).map { (at: SkyCoreFixture.number($0[0]), colour: srgb(hex: $0[1])) }
        XCTAssertEqual(stops.count, 6)
        for row in SkyCoreFixture.rows(Lab.ramp) {
            let cells = numbers(row)
            assertColour(OKLab.SRGB.ramp(stops, at: cells[0]), is: cells[1...], "x \(row[0])")
        }
        // Before the first stop and after the last it is that stop's own
        // colour, untouched.
        XCTAssertEqual(OKLab.SRGB.ramp(stops, at: -1), stops[0].colour)
        XCTAssertEqual(OKLab.SRGB.ramp(stops, at: 2), stops[5].colour)
        // Half way between two stops it is their mix.
        XCTAssertEqual(OKLab.SRGB.ramp(stops, at: 0.1), stops[0].colour.mixed(with: stops[1].colour, by: 0.5))
    }

    // MARK: Held to the sky

    func testAColourIsHeldWithinAContrastOfItsSky() {
        let rows = SkyCoreFixture.rows(Lab.held)
        XCTAssertEqual(rows.count, 411)
        var held = 0
        var oneLimit = 0
        for row in rows {
            let cells = row.dropLast().map(SkyCoreFixture.number)
            let colour = OKLab(lightness: cells[0], a: cells[1], b: cells[2])
            let sky = OKLab(lightness: cells[3], a: cells[4], b: cells[5])
            let out = colour.held(to: sky, up: cells[6], down: cells[7], own: cells[8])
            assertColour(out, is: cells[9...], "\(row)")
            // One limit given is both, as in the lab (`down = up`).
            if cells[6] == cells[7] {
                oneLimit += 1
                assertColour(colour.held(to: sky, up: cells[6], own: cells[8]), is: cells[9...],
                             "\(row): with the lower limit left to be the upper")
            }
            if row.last == "untouched" {
                XCTAssertEqual(out, colour, "\(row): inside both limits it is returned as it was")
                continue
            }
            XCTAssertEqual(row.last, "held")
            held += 1
            // The limits' own ratio, on luminance + 0.05 with luminance
            // taken as lightness cubed: no lighter than up : 1 against the
            // sky, no darker than down : 1.
            let skyValue = pow(max(0, sky.lightness), 3) + 0.05
            let ratio = (pow(max(0, out.lightness), 3) + 0.05) / skyValue
            // (An upper limit that falls under black is black itself.)
            XCTAssertLessThanOrEqual(ratio, max(cells[6], 0.05 / skyValue) + 1e-9, "\(row)")
            XCTAssertGreaterThanOrEqual(ratio, 1 / cells[7] - 1e-9, "\(row)")
        }
        XCTAssertGreaterThan(held, 300)
        XCTAssertGreaterThan(oneLimit, 40)
    }

    func testAColourOfTheSkysOwnLightnessIsLeftAsItIs() {
        // Held means brought back toward the sky's VALUE. A colour already
        // at it has nowhere to go, even where a limit under 1 : 1 says it
        // is past it: the lab hands it back untouched, and so does this
        // (the fixture's two rows of the kind, one for each limit).
        let colour = OKLab(lightness: 0.6, a: 0.05, b: 0.02)
        let sky = OKLab(lightness: 0.6, a: -0.02, b: -0.04)
        let rows = SkyCoreFixture.rows(Lab.held).filter { $0[0] == $0[3] && ($0[6] == "0.8" || $0[7] == "0.8") }
        XCTAssertEqual(rows.count, 2)
        for row in rows {
            XCTAssertEqual(row.last, "untouched", "\(row)")
            let limits = (up: SkyCoreFixture.number(row[6]), down: SkyCoreFixture.number(row[7]))
            XCTAssertEqual(colour.held(to: sky, up: limits.up, down: limits.down, own: 0.3), colour, "\(row)")
        }
    }

    func testAHeldColourComesBackTowardTheSkysOwn() {
        // tools/test-math.mjs's own case: an ember over a dusk-blue sky.
        let sky = OKLab(lightness: 0.30, a: -0.01, b: -0.05)
        let loud = OKLab(lightness: 0.80, a: 0.05, b: 0.10)
        let ratio = { (c: OKLab) in (pow(c.lightness, 3) + 0.05) / (pow(sky.lightness, 3) + 0.05) }

        let held = loud.held(to: sky, up: 1.3, down: 1.2)
        XCTAssertEqual(ratio(held), 1.3, accuracy: 1e-9, "a lighter colour stops at the upper ratio")
        XCTAssertLessThan(abs(held.a - sky.a), abs(loud.a - sky.a), "and has gone the sky's way in colour")
        XCTAssertLessThan(abs(held.b - sky.b), abs(loud.b - sky.b))

        // Never only darkened: with `own` 1 its value is held and its
        // colour is its own.
        let kept = loud.held(to: sky, up: 1.3, down: 1.2, own: 1)
        XCTAssertEqual(ratio(kept), 1.3, accuracy: 1e-9)
        XCTAssertEqual(kept.a, loud.a, accuracy: close)
        XCTAssertEqual(kept.b, loud.b, accuracy: close)

        let deep = OKLab(lightness: 0.05, a: 0, b: 0).held(to: sky, up: 1.3, down: 1.2)
        XCTAssertEqual(1 / ratio(deep), 1.2, accuracy: 1e-9, "a darker colour stops at the lower ratio")

        let quiet = OKLab(lightness: 0.33, a: 0, b: -0.04)
        XCTAssertEqual(quiet.held(to: sky, up: 1.3, down: 1.2), quiet, "inside both limits: untouched")
        XCTAssertEqual(sky.held(to: sky, up: 1.3), sky, "the sky itself is untouched")
        // One limit given is both — for a colour too light, and for one
        // too dark, which is where the lower limit is the one that holds.
        XCTAssertEqual(loud.held(to: sky, up: 1.3), loud.held(to: sky, up: 1.3, down: 1.3))
        let dark = OKLab(lightness: 0.05, a: 0, b: 0)
        XCTAssertEqual(dark.held(to: sky, up: 1.3), dark.held(to: sky, up: 1.3, down: 1.3))
        XCTAssertNotEqual(dark.held(to: sky, up: 1.3), dark.held(to: sky, up: 1.3, down: 1))
    }
}
