import XCTest
@testable import TwoOfUs

final class SkyPaletteTests: XCTestCase {
    private func assertEqual(_ a: SkyPalette.RGB, _ b: SkyPalette.RGB,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.red, b.red, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(a.green, b.green, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(a.blue, b.blue, accuracy: 0.0001, file: file, line: line)
    }

    func testTheSunRisesLowOnTheLeftAndSetsLowOnTheRight() {
        let rise = SkyPalette.bodyPosition(progress: 0)
        let noon = SkyPalette.bodyPosition(progress: 0.5)
        let set = SkyPalette.bodyPosition(progress: 1)
        XCTAssertEqual(rise.x, 0.04, accuracy: 0.0001)
        XCTAssertEqual(set.x, 0.96, accuracy: 0.0001)
        XCTAssertEqual(noon.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(noon.y, 0, accuracy: 0.0001, "highest at its noon")
        XCTAssertEqual(rise.y, 0.30, accuracy: 0.0001)
        XCTAssertEqual(set.y, 0.30, accuracy: 0.0001)
    }

    func testSunriseIsWarmMiddayBlueSunsetLavender() {
        // Sunrise: periwinkle overhead, peach lower down and around the sun.
        let rise = SkyPalette.look(at: 0, in: SkyPalette.dayFrames)
        XCTAssertGreaterThan(rise.mid.red, rise.mid.blue)
        XCTAssertGreaterThan(rise.warm.red, rise.warm.blue)
        let noon = SkyPalette.look(at: 0.5, in: SkyPalette.dayFrames).top
        XCTAssertGreaterThan(noon.blue, noon.red)
        let set = SkyPalette.look(at: 1, in: SkyPalette.dayFrames).top
        XCTAssertGreaterThan(set.blue, set.green)
    }

    func testMiddayIsTheDeepestBlue() {
        let morning = SkyPalette.look(at: 0.25, in: SkyPalette.dayFrames).top
        let noon = SkyPalette.look(at: 0.5, in: SkyPalette.dayFrames).top
        XCTAssertLessThan(noon.red, morning.red)
    }

    func testTheSkyStaysQuietBehindTheCards() {
        // By day every colour the sky paints behind the cards is light and
        // nearly grey, so the app's teal, amber and lavender always lead.
        for frame in SkyPalette.dayFrames {
            let look = frame.look
            for colour in [look.top, look.mid, look.haze, look.deep] + look.hills {
                let high = max(colour.red, colour.green, colour.blue)
                let low = min(colour.red, colour.green, colour.blue)
                XCTAssertLessThan(high - low, 0.12, "barely tinted")
                XCTAssertGreaterThan(low, 0.75, "light")
            }
        }
    }

    func testTheNightIsDeeperSoTheStarsShow() {
        let night = SkyPalette.look(at: 0.5, in: SkyPalette.nightFrames).top
        let day = SkyPalette.look(at: 0.5, in: SkyPalette.dayFrames).top
        XCTAssertLessThan(night.red + night.green + night.blue, day.red + day.green + day.blue)
    }

    func testTheNightJoinsTheDayAtBothEnds() {
        assertEqual(SkyPalette.look(at: 0, in: SkyPalette.nightFrames).top,
                    SkyPalette.look(at: 1, in: SkyPalette.dayFrames).top)
        assertEqual(SkyPalette.look(at: 1, in: SkyPalette.nightFrames).top,
                    SkyPalette.look(at: 0, in: SkyPalette.dayFrames).top)
    }

    func testLooksBlendBetweenFrames() {
        let a = SkyPalette.look(at: 0, in: SkyPalette.dayFrames)
        let b = SkyPalette.look(at: 0.18, in: SkyPalette.dayFrames)
        let mid = SkyPalette.look(at: 0.09, in: SkyPalette.dayFrames)
        assertEqual(mid.top, a.top.mixed(with: b.top, by: 0.5))
        for index in 0..<4 {
            assertEqual(mid.hills[index], a.hills[index].mixed(with: b.hills[index], by: 0.5))
        }
        XCTAssertEqual(mid.mistAlpha, (a.mistAlpha + b.mistAlpha) / 2, accuracy: 0.0001)
    }

    func testMixingIsClamped() {
        let a = SkyPalette.RGB(red: 0, green: 0, blue: 0)
        let b = SkyPalette.RGB(red: 1, green: 1, blue: 1)
        assertEqual(a.mixed(with: b, by: 2), b)
        assertEqual(a.mixed(with: b, by: -1), a)
    }

    func testCloudLightingIsAlwaysOneWholeCrossfade() {
        for frames in [SkyPalette.dayFrames, SkyPalette.nightFrames] {
            for step in 0...40 {
                let light = SkyPalette.look(at: Double(step) / 40, in: frames).light
                XCTAssertEqual(light.dawn + light.day + light.dusk, 1, accuracy: 0.0001)
                XCTAssertGreaterThanOrEqual(min(light.dawn, light.day, light.dusk), 0)
            }
        }
        XCTAssertEqual(SkyPalette.look(at: 0, in: SkyPalette.dayFrames).light, .ofDawn)
        XCTAssertEqual(SkyPalette.look(at: 0.5, in: SkyPalette.dayFrames).light, .ofDay)
        XCTAssertEqual(SkyPalette.look(at: 1, in: SkyPalette.dayFrames).light, .ofDusk)
    }

    func testEveryLookHasFourHills() {
        for frames in [SkyPalette.dayFrames, SkyPalette.nightFrames] {
            for frame in frames {
                XCTAssertEqual(frame.look.hills.count, SkyPalette.ridges.count)
            }
        }
    }

    func testRidgesStackBackToFrontAlongTheBottom() {
        let height = 678.0
        let ridges = SkyPalette.ridges
        for index in 0..<(ridges.count - 1) {
            XCTAssertLessThan(ridges[index].baseline(height: height), ridges[index + 1].baseline(height: height))
            XCTAssertGreaterThan(ridges[index].blur, ridges[index + 1].blur, "the far ridges are the softer")
        }
        // Every crest stays in the bottom third, on a phone and on the open Duo.
        for ridge in ridges {
            for point in ridge.points(width: 951, height: height) {
                XCTAssertGreaterThan(Double(point.y), height * 0.68)
                XCTAssertLessThan(Double(point.y), height)
            }
        }
    }

    func testRidgePointsSpanPastBothEdges() {
        let points = SkyPalette.ridges[0].points(width: 466, height: 678)
        XCTAssertLessThan(points.first?.x ?? 0, 0)
        XCTAssertGreaterThan(points.last?.x ?? 0, 466)
    }

    func testStarsAreFixedAndHighInTheSky() {
        let phone = SkyPalette.stars(width: 466)
        XCTAssertEqual(phone, SkyPalette.stars(width: 466), "the same stars every frame")
        XCTAssertEqual(phone.count, 24)
        XCTAssertGreaterThan(SkyPalette.stars(width: 951).count, phone.count)
        for star in phone {
            XCTAssertTrue((0...1).contains(star.x))
            XCTAssertTrue((0...0.36).contains(star.y))
            XCTAssertTrue((0...1).contains(star.alpha))
            XCTAssertTrue((2.4...5.2).contains(star.period))
            XCTAssertTrue((0..<1).contains(star.phase))
        }
        XCTAssertTrue(phone.contains { $0.twinkles }, "most twinkle")
        XCTAssertTrue(phone.contains { !$0.twinkles }, "a few hold steady")
    }

    func testStarsComeOutAfterSunsetAndGoBeforeSunrise() {
        XCTAssertEqual(SkyPalette.starOpacity(nightProgress: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(SkyPalette.starOpacity(nightProgress: 0.02), 0, accuracy: 0.0001)
        XCTAssertEqual(SkyPalette.starOpacity(nightProgress: 0.05), 0.5, accuracy: 0.0001)
        XCTAssertEqual(SkyPalette.starOpacity(nightProgress: 0.08), 1, accuracy: 0.0001)
        XCTAssertEqual(SkyPalette.starOpacity(nightProgress: 0.5), 1, accuracy: 0.0001)
        XCTAssertEqual(SkyPalette.starOpacity(nightProgress: 0.95), 0.5, accuracy: 0.0001)
        XCTAssertEqual(SkyPalette.starOpacity(nightProgress: 1), 0, accuracy: 0.0001)
    }

    func testATwinkleSwellsBetweenAFifthAndFull() {
        let star = SkyPalette.Star(x: 0.5, y: 0.1, size: 2, alpha: 1, twinkles: true, period: 4, phase: 0)
        XCTAssertEqual(SkyPalette.twinkle(star, at: 0), 1, accuracy: 0.0001)
        XCTAssertEqual(SkyPalette.twinkle(star, at: 2), 0.22, accuracy: 0.0001)
        for step in 0...80 {
            let value = SkyPalette.twinkle(star, at: Double(step) / 10)
            XCTAssertGreaterThanOrEqual(value, 0.2199)
            XCTAssertLessThanOrEqual(value, 1.0001)
        }
        let steady = SkyPalette.Star(x: 0.5, y: 0.1, size: 2, alpha: 1, twinkles: false, period: 4, phase: 0)
        XCTAssertEqual(SkyPalette.twinkle(steady, at: 2), 1)
    }

    func testGlintsPulseOnTheirOwnRhythm() {
        XCTAssertEqual(SkyPalette.glints(wide: false).count, 5)
        XCTAssertEqual(SkyPalette.glints(wide: true).count, 7)
        for wide in [false, true] {
            let glints = SkyPalette.glints(wide: wide)
            XCTAssertEqual(Set(glints.map(\.phase)).count, glints.count, "out of step with one another")
            for glint in glints {
                XCTAssertTrue((0...1).contains(glint.x))
                XCTAssertTrue((0...1).contains(glint.y))
                for step in 0...40 {
                    let time = Double(step) / 4
                    let value = SkyPalette.sparkle(glint, at: time)
                    XCTAssertTrue((-0.0001...1.0001).contains(value))
                    XCTAssertEqual(value, SkyPalette.sparkle(glint, at: time + glint.period), accuracy: 0.000001)
                }
            }
        }
    }

    func testCloudsUseKnownTextures() {
        for wide in [false, true] {
            for cloud in SkyPalette.clouds(wide: wide) {
                XCTAssertTrue(SkyPalette.cloudArt.indices.contains(cloud.art))
            }
        }
    }

    // MARK: The dark appearance

    private func luminance(_ c: SkyPalette.RGB) -> Double {
        0.2126 * c.red + 0.7152 * c.green + 0.0722 * c.blue
    }

    func testTheDarkSkyStaysDeepBehindTheCards() {
        // Every colour the dark sky paints is deep, and below the zenith
        // darker than a card (#1C1C1E), so cards and white text read as on
        // the black page and nothing lights the room at night.
        for frames in [SkyPalette.darkDayFrames, SkyPalette.darkNightFrames] {
            for frame in frames {
                let look = frame.look
                for colour in [look.top, look.mid, look.haze, look.deep, look.warm] + look.hills {
                    XCTAssertLessThan(luminance(colour), 0.2, "deep")
                }
                for colour in [look.mid, look.haze, look.deep] + look.hills {
                    XCTAssertLessThan(luminance(colour), luminance(SkyPalette.RGB(hex: 0x1C1C1E)),
                                      "under a card's own grey")
                }
            }
        }
    }

    func testTheDarkNightIsTheDeepestAndPurple() {
        let night = SkyPalette.look(at: 0.5, in: SkyPalette.darkNightFrames).top
        let noon = SkyPalette.look(at: 0.5, in: SkyPalette.darkDayFrames).top
        let dusk = SkyPalette.look(at: 1, in: SkyPalette.darkDayFrames).top
        XCTAssertLessThan(luminance(night), luminance(noon))
        XCTAssertLessThan(luminance(night), luminance(dusk))
        // Twilight and night lean violet: blue first, then red over green.
        for colour in [night, dusk] {
            XCTAssertGreaterThan(colour.blue, colour.red)
            XCTAssertGreaterThan(colour.red, colour.green)
        }
    }

    func testTheDarkNightJoinsTheDarkDayAtBothEnds() {
        assertEqual(SkyPalette.look(at: 0, in: SkyPalette.darkNightFrames).top,
                    SkyPalette.look(at: 1, in: SkyPalette.darkDayFrames).top)
        assertEqual(SkyPalette.look(at: 1, in: SkyPalette.darkNightFrames).top,
                    SkyPalette.look(at: 0, in: SkyPalette.darkDayFrames).top)
    }

    func testDarkLooksHaveFourHillsAndWholeCloudCrossfades() {
        for frames in [SkyPalette.darkDayFrames, SkyPalette.darkNightFrames] {
            for frame in frames {
                XCTAssertEqual(frame.look.hills.count, SkyPalette.ridges.count)
            }
            for step in 0...40 {
                let light = SkyPalette.look(at: Double(step) / 40, in: frames).light
                XCTAssertEqual(light.dawn + light.day + light.dusk, 1, accuracy: 0.0001)
            }
        }
    }

    func testTheDarkSceneFadesToTheBlackPageWithFaintClouds() {
        let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now)!
        let light = SkyPalette.scene(at: noon, location: (40, -75))
        let dark = SkyPalette.scene(at: noon, location: (40, -75), dark: true)
        assertEqual(light.page, SkyPalette.page)
        assertEqual(dark.page, SkyPalette.darkPage)
        XCTAssertLessThan(dark.cloudStrength, light.cloudStrength)
        XCTAssertLessThan(dark.moonGlow, light.moonGlow)
        XCTAssertFalse(light.isDark)
        XCTAssertTrue(dark.isDark)
        XCTAssertLessThan(luminance(dark.look.top), luminance(light.look.top))
    }

    func testASkyBesideAnotherRunsItsRidgesOn() {
        // The spread's leading sky lays its hills out on the phone page's x,
        // so at the phone page's origin both skies' ridges are at one height.
        let origin = 485.0
        for ridge in SkyPalette.ridges {
            let leading = ridge.points(width: 951, height: 669, xOffset: origin)
            let phone = ridge.points(width: 466, height: 669)
            for point in leading {
                XCTAssertEqual(Double(point.y), ridge.y(at: Double(point.x) - origin, height: 669), accuracy: 0.0001)
            }
            let atSeam = leading.first { abs(Double($0.x) - origin - 5) < 0.001 }!
            let phoneNearSeam = phone.first { abs(Double($0.x) - 5) < 0.001 }
            if let phoneNearSeam {
                XCTAssertEqual(Double(atSeam.y), Double(phoneNearSeam.y), accuracy: 0.0001)
            }
        }
    }

    // MARK: The moon

    func testTheMoonShapeIsLitOnTheRightByFraction() {
        let rect = CGRect(x: 0, y: 0, width: 32, height: 32)
        let crescent = MoonPhaseShape(lit: 0.27).path(in: rect)
        XCTAssertGreaterThan(crescent.boundingRect.midX, 16, "lit on its right before it is turned")
        XCTAssertTrue(crescent.contains(CGPoint(x: 30, y: 16)))
        XCTAssertFalse(crescent.contains(CGPoint(x: 10, y: 16)))
        let full = MoonPhaseShape(lit: 1).path(in: rect).boundingRect
        XCTAssertEqual(full.width, 32, accuracy: 0.5, "full: the whole disc")
        let half = MoonPhaseShape(lit: 0.5).path(in: rect).boundingRect
        XCTAssertEqual(half.minX, 16, accuracy: 0.5, "half: the terminator straight down the middle")
    }

    func testTheSceneHasTheMoonOnlyWhileItIsUp() throws {
        let chicago = (latitude: 41.9, longitude: -87.6)
        // 6:16 PM CST, 2026-11-14: the crescent is up in the south-west.
        let dusk = SkyPalette.scene(at: utc("2026-11-15T00:16:00Z"), location: chicago, dark: true)
        let moon = try XCTUnwrap(dusk.moon)
        XCTAssertEqual(moon.fraction, 0.28, accuracy: 0.01)
        XCTAssertGreaterThan(moon.x, 0.5, "past the middle of its arc, towards where it sets")
        XCTAssertFalse(moon.inDaylight)
        // Midnight: it has set — no moon, no moonlight.
        let midnight = SkyPalette.scene(at: utc("2026-11-15T06:00:00Z"), location: chicago, dark: true)
        XCTAssertNil(midnight.moon)
        XCTAssertEqual(midnight.moonGlowByPhase, midnight.moonGlow * 0.35, accuracy: 1e-9)
        // Early afternoon: it is up in the daytime sky, drawn pale.
        let afternoon = SkyPalette.scene(at: utc("2026-11-14T20:00:00Z"), location: chicago)
        XCTAssertEqual(afternoon.moon?.inDaylight, true)
    }

    func testTheDarkStarsAndMoonAreQuieter() {
        let date = utc("2026-11-15T00:16:00Z")
        let light = SkyPalette.scene(at: date, location: (41.9, -87.6))
        let dark = SkyPalette.scene(at: date, location: (41.9, -87.6), dark: true)
        XCTAssertLessThan(dark.starStrength, light.starStrength)
        XCTAssertLessThan(dark.moonGlowByPhase, light.moonGlowByPhase)
        XCTAssertEqual(dark.moon, light.moon)
    }

    private func utc(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }
}
