import XCTest
@testable import TwoOfUs

final class MoonClockTests: XCTestCase {
    private func utc(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    /// SunCalc's own reference case (its test suite): 2013-03-05 00:00 UTC
    /// at 50.5° N, 30.5° E.
    func testPositionMatchesTheReference() {
        let position = MoonClock.position(at: utc("2013-03-05T00:00:00Z"), latitude: 50.5, longitude: 30.5)
        XCTAssertEqual(position.azimuth, -0.9783999522438226, accuracy: 1e-9)
        XCTAssertEqual(position.altitude, 0.014551482243892251, accuracy: 1e-9)
        XCTAssertEqual(position.distance, 364121.37256256194, accuracy: 1e-3)
    }

    func testIlluminationMatchesTheReference() {
        let light = MoonClock.illumination(at: utc("2013-03-05T00:00:00Z"))
        XCTAssertEqual(light.fraction, 0.4848068202456373, accuracy: 1e-9)
        XCTAssertEqual(light.phase, 0.7548368838538762, accuracy: 1e-9)
        XCTAssertEqual(light.angle, 1.6732942678578346, accuracy: 1e-9)
    }

    func testPhaseAtKnownNewAndFullMoons() {
        let eclipse = MoonClock.illumination(at: utc("2024-04-08T18:21:00Z"))
        XCTAssertLessThan(eclipse.fraction, 0.002, "the April 2024 eclipse: new moon")
        let full = MoonClock.illumination(at: utc("2024-09-18T02:34:00Z"))
        XCTAssertGreaterThan(full.fraction, 0.999, "the September 2024 full moon")
        XCTAssertEqual(full.phase, 0.5, accuracy: 0.01)
    }

    /// SunCalc's reference moon times for 2013-03-04 at the same place:
    /// rise 23:54:29, set 07:47:58 UTC. Bisection lands within a minute of
    /// its hourly interpolation.
    func testRiseAndSetMatchTheReference() throws {
        // Up at 05:00: it rose the evening before and sets at 07:47.
        let morning = try XCTUnwrap(MoonClock.pass(around: utc("2013-03-04T05:00:00Z"), latitude: 50.5, longitude: 30.5))
        let set = try XCTUnwrap(morning.set)
        XCTAssertEqual(set.timeIntervalSince(utc("2013-03-04T07:47:58Z")), 0, accuracy: 60)
        // Up at 03:00 the next morning: it rose at 23:54.
        let night = try XCTUnwrap(MoonClock.pass(around: utc("2013-03-05T03:00:00Z"), latitude: 50.5, longitude: 30.5))
        let rise = try XCTUnwrap(night.rise)
        XCTAssertEqual(rise.timeIntervalSince(utc("2013-03-04T23:54:29Z")), 0, accuracy: 60)
    }

    func testThereIsNoPassWhileTheMoonIsDown() {
        // Midnight in Chicago, 2026-11-15: a young crescent set hours ago.
        XCTAssertNil(MoonClock.pass(around: utc("2026-11-15T06:00:00Z"), latitude: 41.9, longitude: -87.6))
        XCTAssertNil(MoonClock.passProgress(at: utc("2026-11-15T06:00:00Z"), latitude: 41.9, longitude: -87.6))
    }

    /// Dusk in Chicago, 2026-11-14 (6:16 PM CST): a waxing crescent, about
    /// 28 % lit, low in the south-west three quarters of the way through
    /// its pass (it rose at 11:29 AM and sets at 8:47 PM), lit low on its
    /// right — towards the sun that has just set.
    func testAnEveningCrescent() throws {
        let date = utc("2026-11-15T00:16:00Z")
        let light = MoonClock.illumination(at: date)
        XCTAssertEqual(light.fraction, 0.28, accuracy: 0.01)
        XCTAssertLessThan(light.phase, 0.25, "waxing")
        let progress = try XCTUnwrap(MoonClock.passProgress(at: date, latitude: 41.9, longitude: -87.6))
        XCTAssertEqual(progress, 0.729, accuracy: 0.01)
        let chi = MoonClock.brightLimbZenithAngle(at: date, latitude: 41.9, longitude: -87.6)
        let rotation = SkyPalette.brightLimbRotation(zenithAngle: chi)
        XCTAssertEqual(rotation * 180 / .pi, 34, accuracy: 2, "lit on its right, turned down towards the sunset")
    }

    func testBrightLimbRotationPointsTheLitSideAlongTheLimb() {
        // χ = −90° (bright limb due west, to the right): no turn.
        XCTAssertEqual(SkyPalette.brightLimbRotation(zenithAngle: -.pi / 2), 0, accuracy: 1e-9)
        // χ = 0 (bright limb straight up): the right side turned to the top.
        XCTAssertEqual(SkyPalette.brightLimbRotation(zenithAngle: 0), -.pi / 2, accuracy: 1e-9)
        // χ = 90° (to the left, east): turned half way round.
        XCTAssertEqual(abs(SkyPalette.brightLimbRotation(zenithAngle: .pi / 2)), .pi, accuracy: 1e-9)
    }
}
