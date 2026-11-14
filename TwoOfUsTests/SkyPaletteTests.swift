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
}
