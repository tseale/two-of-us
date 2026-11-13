import XCTest
@testable import TwoOfUs

final class SkyPaletteTests: XCTestCase {
    private func assertEqual(_ a: SkyPalette.RGB, _ b: SkyPalette.RGB,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.red, b.red, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(a.green, b.green, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(a.blue, b.blue, accuracy: 0.0001, file: file, line: line)
    }

    func testEachKeyframeIsItsOwnColour() {
        for frame in SkyPalette.keyframes {
            assertEqual(SkyPalette.top(atMinute: frame.minute), frame.top)
        }
    }

    func testDawnIsPeachAndMiddayIsBlue() {
        let dawn = SkyPalette.top(atMinute: 6 * 60 + 30)
        XCTAssertGreaterThan(dawn.red, dawn.blue)
        let noon = SkyPalette.top(atMinute: 12 * 60)
        XCTAssertGreaterThan(noon.blue, noon.red)
    }

    func testBetweenKeyframesTheColourIsBlended() {
        let a = SkyPalette.keyframes[4].top     // 12:00
        let b = SkyPalette.keyframes[5].top     // 16:00
        assertEqual(SkyPalette.top(atMinute: 14 * 60), a.mixed(with: b, by: 0.5))
    }

    func testTheNightWrapsBackToMidnight() {
        // 23:00 sits between 22:00 and the next midnight, both night colour.
        assertEqual(SkyPalette.top(atMinute: 23 * 60), SkyPalette.keyframes[0].top)
        assertEqual(SkyPalette.top(atMinute: 1440), SkyPalette.top(atMinute: 0))
        assertEqual(SkyPalette.top(atMinute: -60), SkyPalette.top(atMinute: 23 * 60))
    }

    func testMixingIsClamped() {
        let a = SkyPalette.RGB(red: 0, green: 0, blue: 0)
        let b = SkyPalette.RGB(red: 1, green: 1, blue: 1)
        assertEqual(a.mixed(with: b, by: 2), b)
        assertEqual(a.mixed(with: b, by: -1), a)
    }
}
