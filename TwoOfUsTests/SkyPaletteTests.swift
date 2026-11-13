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

    func testSunriseIsPeachMiddayBlueSunsetLavender() {
        let rise = SkyPalette.look(at: 0, in: SkyPalette.dayFrames).top
        XCTAssertGreaterThan(rise.red, rise.blue)
        let noon = SkyPalette.look(at: 0.5, in: SkyPalette.dayFrames).top
        XCTAssertGreaterThan(noon.blue, noon.red)
        let set = SkyPalette.look(at: 1, in: SkyPalette.dayFrames).top
        XCTAssertGreaterThan(set.blue, set.green)
    }

    func testTheNightJoinsTheDayAtBothEnds() {
        assertEqual(SkyPalette.look(at: 0, in: SkyPalette.nightFrames).top,
                    SkyPalette.look(at: 1, in: SkyPalette.dayFrames).top)
        assertEqual(SkyPalette.look(at: 1, in: SkyPalette.nightFrames).top,
                    SkyPalette.look(at: 0, in: SkyPalette.dayFrames).top)
    }

    func testLooksBlendBetweenFrames() {
        let a = SkyPalette.look(at: 0, in: SkyPalette.dayFrames).top
        let b = SkyPalette.look(at: 0.18, in: SkyPalette.dayFrames).top
        assertEqual(SkyPalette.look(at: 0.09, in: SkyPalette.dayFrames).top, a.mixed(with: b, by: 0.5))
    }

    func testMixingIsClamped() {
        let a = SkyPalette.RGB(red: 0, green: 0, blue: 0)
        let b = SkyPalette.RGB(red: 1, green: 1, blue: 1)
        assertEqual(a.mixed(with: b, by: 2), b)
        assertEqual(a.mixed(with: b, by: -1), a)
    }
}
