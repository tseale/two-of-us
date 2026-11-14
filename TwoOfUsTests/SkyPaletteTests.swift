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
