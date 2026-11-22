import XCTest
@testable import TwoOfUs

/// Where the sky's sun is worked out for (`SkyPlace`): the daycare's pin,
/// or the same guess today's sky makes when there is none.
final class SkyPlaceTests: XCTestCase {
    private var chicagoTime: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        chicagoTime.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func testTheDaycarePinIsThePlace() {
        let place = SkyPlace.resolve(pin: (latitude: 41.8781, longitude: -87.6298),
                                     timeZone: chicagoTime.timeZone, at: date(2026, 11, 21))
        XCTAssertEqual(place, SkyPlace(latitude: 41.8781, longitude: -87.6298))
        // The pin wins even when the phone is somewhere else for the week.
        let away = SkyPlace.resolve(pin: (latitude: 41.8781, longitude: -87.6298),
                                    timeZone: TimeZone(identifier: "Asia/Tokyo")!, at: date(2026, 11, 21))
        XCTAssertEqual(away, place)
    }

    func testWithNoPinItIsFortyNorthOnTheTimeZonesMeridian() {
        // Central time is six hours behind Greenwich: 90° west. In July the
        // clocks are an hour forward and the meridian has not moved.
        let winter = SkyPlace.resolve(pin: nil, timeZone: chicagoTime.timeZone, at: date(2026, 11, 21))
        let summer = SkyPlace.resolve(pin: nil, timeZone: chicagoTime.timeZone, at: date(2027, 7, 15))
        XCTAssertEqual(winter.latitude, 40, accuracy: 0.0001)
        XCTAssertEqual(winter.longitude, -90, accuracy: 0.0001)
        XCTAssertEqual(summer, winter)
        // The same guess today's sky makes, so the two cannot disagree.
        let old = SolarClock.approximateLocation(timeZone: chicagoTime.timeZone, at: date(2026, 11, 21))
        XCTAssertEqual(winter.latitude, old.latitude)
        XCTAssertEqual(winter.longitude, old.longitude)
    }

    func testTheGuessPutsFirstLightWithinTwentyMinutesOfChicagos() throws {
        // What a household with no pin loses: the guess is 2.4° west of the
        // real Chicago and 1.9° south, and first light moves with it — six
        // minutes late in November, eighteen in June. Enough to keep, too
        // much to forget: the night's frame is only as good as the place.
        let guess = SkyPlace.resolve(pin: nil, timeZone: chicagoTime.timeZone, at: date(2026, 11, 21))
        for (evening, minutesLate) in [(date(2026, 11, 21, 18), 5.8), (date(2027, 6, 20, 18), 17.7)] {
            let real = try XCTUnwrap(SolarClock.rises(through: -7, after: evening,
                                                      latitude: 41.8781, longitude: -87.6298))
            let guessed = try XCTUnwrap(SolarClock.rises(through: -7, after: evening,
                                                         latitude: guess.latitude, longitude: guess.longitude))
            XCTAssertEqual(guessed.timeIntervalSince(real) / 60, minutesLate, accuracy: 0.5)
        }
    }
}
