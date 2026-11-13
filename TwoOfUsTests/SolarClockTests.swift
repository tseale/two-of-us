import XCTest
@testable import TwoOfUs

final class SolarClockTests: XCTestCase {
    private var newYork: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        newYork.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func assertClock(_ actual: Date, _ hour: Int, _ minute: Int, tolerance: Double = 5,
                             file: StaticString = #filePath, line: UInt = #line) {
        let parts = newYork.dateComponents([.hour, .minute], from: actual)
        let got = Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
        XCTAssertEqual(got, Double(hour * 60 + minute), accuracy: tolerance, file: file, line: line)
    }

    func testNewYorkInNovember() throws {
        // Nov 13, 2026: sunrise ≈ 6:41 AM, sunset ≈ 4:40 PM (EST).
        let day = try XCTUnwrap(SolarClock.day(containing: date(2026, 11, 13), latitude: 40.71,
                                               longitude: -74.01, calendar: newYork))
        assertClock(day.sunrise, 6, 41)
        assertClock(day.sunset, 16, 40)
    }

    func testNewYorkAtMidsummer() throws {
        // Jun 21, 2026: sunrise ≈ 5:25 AM, sunset ≈ 8:31 PM (EDT).
        let day = try XCTUnwrap(SolarClock.day(containing: date(2026, 6, 21), latitude: 40.71,
                                               longitude: -74.01, calendar: newYork))
        assertClock(day.sunrise, 5, 25)
        assertClock(day.sunset, 20, 31)
    }

    func testThePolarNightHasNoSunrise() {
        XCTAssertNil(SolarClock.day(containing: date(2026, 12, 21), latitude: 80, longitude: 15,
                                    calendar: newYork))
    }

    func testPhases() throws {
        let day = SolarClock.Day(sunrise: date(2026, 11, 13, 7), sunset: date(2026, 11, 13, 17))
        XCTAssertEqual(SolarClock.phase(at: date(2026, 11, 13, 12), in: day), .day(0.5))
        XCTAssertEqual(SolarClock.phase(at: date(2026, 11, 13, 7), in: day), .day(0))
        // A 10-hour day leaves a 14-hour night: 7 PM is 2/14 through it…
        guard case .night(let evening) = SolarClock.phase(at: date(2026, 11, 13, 19), in: day)
        else { return XCTFail("expected night") }
        XCTAssertEqual(evening, 2.0 / 14, accuracy: 0.0001)
        // …and 5 AM is 2 hours short of sunrise.
        guard case .night(let early) = SolarClock.phase(at: date(2026, 11, 13, 5), in: day)
        else { return XCTFail("expected night") }
        XCTAssertEqual(early, 12.0 / 14, accuracy: 0.0001)
    }

    func testTheApproximateLocationIsTheTimeZonesMeridian() {
        let east = SolarClock.approximateLocation(timeZone: TimeZone(identifier: "America/New_York")!,
                                                  at: date(2026, 7, 1))
        XCTAssertEqual(east.longitude, -75, accuracy: 0.001, "standard time, not daylight time")
        XCTAssertEqual(east.latitude, 40, accuracy: 0.001)
    }
}
