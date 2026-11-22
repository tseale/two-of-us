import XCTest
@testable import TwoOfUs

/// The sun's own place, added to `SolarClock` for the painted hill
/// (TwoOfUs/Sky/Core/SolarClock+Position.swift): where it stands, and when
/// it next comes up through an angle. Every expected number
/// is the sky lab's (`SkyCoreFixturesNight`, exported from
/// design/sky-lab/lab/solar.js), not this file's: the signed-off mockup put
/// first light where its `sunPosition` reads −7°, so the app has to agree
/// with that function, not with an almanac.
final class SkyCoreSunTests: XCTestCase {
    private let chicago = (latitude: 41.8781, longitude: -87.6298)

    private var chicagoTime: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        chicagoTime.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func instant(_ cell: String) -> Date {
        Date(timeIntervalSince1970: SkyCoreFixture.number(cell) / 1000)
    }

    /// The lab's row for one labelled rise: after, and the rise itself (nil
    /// where the lab found none).
    private func labRise(_ label: String, file: StaticString = #filePath,
                         line: UInt = #line) throws -> (after: Date, rise: Date?) {
        let row = try XCTUnwrap(SkyCoreFixture.rows(SkyCoreFixturesNight.sunRises)
            .first { $0[0] == label }, "no fixture row \(label)", file: file, line: line)
        return (instant(row[4]), row[5] == "never" ? nil : instant(row[5]))
    }

    private func clock(_ date: Date) -> String {
        let parts = chicagoTime.dateComponents([.hour, .minute, .second], from: date)
        return String(format: "%02d:%02d:%02d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }

    // MARK: Where the sun stands

    func testTheSunStandsWhereTheLabPutsIt() {
        // Eight places, five days, day and night: the same series, so the
        // same radians. A billionth of a radian is a hair on the moon; what
        // is left over is the last bit of each platform's sin and atan2.
        let rows = SkyCoreFixture.rows(SkyCoreFixturesNight.sunPositions)
        XCTAssertGreaterThan(rows.count, 300)
        for row in rows {
            let sun = SolarClock.position(at: instant(row[1]),
                                          latitude: SkyCoreFixture.number(row[2]),
                                          longitude: SkyCoreFixture.number(row[3]))
            XCTAssertEqual(sun.altitude, SkyCoreFixture.number(row[4]), accuracy: 1e-9,
                           "altitude, \(row[0]) at \(row[1])")
            XCTAssertEqual(sun.azimuth, SkyCoreFixture.number(row[5]), accuracy: 1e-9,
                           "azimuth, \(row[0]) at \(row[1])")
        }
    }

    func testTheAzimuthIsReckonedFromNorthThroughEast() {
        // A November day in Chicago: the sun comes up in the south-east,
        // stands due south at its highest, and goes down in the south-west.
        let morning = SolarClock.position(at: date(2026, 11, 21, 8), latitude: chicago.latitude,
                                          longitude: chicago.longitude)
        let afternoon = SolarClock.position(at: date(2026, 11, 21, 15), latitude: chicago.latitude,
                                            longitude: chicago.longitude)
        XCTAssertGreaterThan(morning.azimuth, .pi / 2)
        XCTAssertLessThan(morning.azimuth, .pi)
        XCTAssertGreaterThan(afternoon.azimuth, .pi)
        XCTAssertLessThan(afternoon.azimuth, 3 * .pi / 2)

        var highest = (altitude: -Double.infinity, azimuth: 0.0)
        for minute in stride(from: 0, to: 24 * 60, by: 1) {
            let sun = SolarClock.position(at: date(2026, 11, 21, 0, minute), latitude: chicago.latitude,
                                          longitude: chicago.longitude)
            if sun.altitude > highest.altitude { highest = sun }
        }
        XCTAssertEqual(highest.azimuth, .pi, accuracy: 0.005, "due south at its highest")
        // 90° − 41.88° − the sun's 20° south of the equator that day.
        XCTAssertEqual(highest.altitude * 180 / .pi, 28.1, accuracy: 0.3)
    }

    func testSunriseAndSunsetAreTheSunJustUnderTheHorizon() throws {
        // The two halves of SolarClock agree: NOAA's sunrise and sunset are
        // the upper limb on a refracted horizon, which is the centre 0.83°
        // under it. (Half a degree of slack: they are different series.)
        let day = try XCTUnwrap(SolarClock.day(containing: date(2026, 11, 21), latitude: chicago.latitude,
                                               longitude: chicago.longitude, calendar: chicagoTime))
        for moment in [day.sunrise, day.sunset] {
            XCTAssertEqual(SolarClock.altitudeInDegrees(at: moment, latitude: chicago.latitude,
                                               longitude: chicago.longitude), -0.833, accuracy: 0.5)
        }
    }

    // MARK: When it rises through an angle

    func testFirstLightIsTheSunThroughMinusSeven() throws {
        // The lab's own two mornings (skies/hill-painted.md, "First light is
        // the sun coming up through −7°: 06:12 on 22 November"), from the
        // evening before, as the night's frame asks for it.
        //
        // The tolerance is one second: the lab's instant is exact to the
        // millisecond, and `rises` bisects until its bracket is a second
        // wide and answers with the middle.
        let november = try labRise("chicago-first-light-22-nov-2026")
        XCTAssertEqual(november.after, date(2026, 11, 21, 18), "the fixture's evening is 6 pm in Chicago")
        let first = try XCTUnwrap(SolarClock.rises(through: -7, after: date(2026, 11, 21, 18),
                                                   latitude: chicago.latitude, longitude: chicago.longitude))
        XCTAssertEqual(first.timeIntervalSince1970, try XCTUnwrap(november.rise).timeIntervalSince1970,
                       accuracy: 1)
        XCTAssertEqual(clock(first), "06:12:14", "CST")

        let june = try labRise("chicago-first-light-21-jun-2027")
        XCTAssertEqual(june.after, date(2027, 6, 20, 18))
        let summer = try XCTUnwrap(SolarClock.rises(through: -7, after: date(2027, 6, 20, 18),
                                                    latitude: chicago.latitude, longitude: chicago.longitude))
        XCTAssertEqual(summer.timeIntervalSince1970, try XCTUnwrap(june.rise).timeIntervalSince1970,
                       accuracy: 1)
        XCTAssertEqual(clock(summer), "04:34:12", "CDT")
    }

    func testEveryRiseIsTheLabsToTheSecond() {
        // First light on a year of Chicago mornings, the nights the clocks
        // change, sunrise's own angle and a high one, the equator, the
        // south, and the far north — including the places where there is
        // none.
        let rows = SkyCoreFixture.rows(SkyCoreFixturesNight.sunRises)
        XCTAssertGreaterThan(rows.count, 40)
        for row in rows {
            let rise = SolarClock.rises(through: SkyCoreFixture.number(row[3]), after: instant(row[4]),
                                        latitude: SkyCoreFixture.number(row[1]),
                                        longitude: SkyCoreFixture.number(row[2]))
            if row[5] == "never" {
                XCTAssertNil(rise, row[0])
            } else if let rise {
                XCTAssertEqual(rise.timeIntervalSince1970, instant(row[5]).timeIntervalSince1970,
                               accuracy: 1, row[0])
            } else {
                XCTFail("\(row[0]): the lab's sun rises through \(row[3])° and this one never does")
            }
        }
    }

    func testASummerNightTooFarNorthHasNoFirstLight() throws {
        // Bergen at midsummer: the sun bottoms out at −6.2°, so it never
        // comes up through −7°. Tromsø's does not set at all.
        for label in ["bergen-first-light-21-jun-2027", "tromso-first-light-21-jun-2027"] {
            let lab = try labRise(label)
            XCTAssertNil(lab.rise, "\(label): the lab finds none either")
        }
        let midsummerEvening = Date(timeIntervalSince1970: 1_813_507_200)   // 20 Jun 2027, 18:00 in Oslo
        XCTAssertNil(SolarClock.rises(through: -7, after: midsummerEvening, latitude: 60.3913, longitude: 5.3221))
        XCTAssertNil(SolarClock.rises(through: -7, after: midsummerEvening, latitude: 69.6492, longitude: 18.9553))
        // …while Stockholm, a degree south of Bergen, is under −7° for one
        // hour that night and still has one, at about 01:19.
        XCTAssertNotNil(SolarClock.rises(through: -7, after: midsummerEvening, latitude: 59.3293, longitude: 18.0686))
    }

    func testADipOfUnderHalfAnHourIsStillARise() throws {
        // Uppsala on the night of 1 July 2027: the first night after
        // midsummer that gets as dark as −7° at all, and only for
        // twenty-four minutes. A search that stepped by the half hour from
        // 18:07 would step clean over it, and the night would be given no
        // first light; this one steps by ten minutes and finds the lab's,
        // 01:05:32 by Stockholm's clock.
        let uppsala = (latitude: 59.8586, longitude: 17.6389)
        let lab = try labRise("uppsala-first-light-2-jul-2027")
        let rise = try XCTUnwrap(SolarClock.rises(through: -7, after: lab.after, latitude: uppsala.latitude,
                                                  longitude: uppsala.longitude))
        XCTAssertEqual(rise.timeIntervalSince1970, try XCTUnwrap(lab.rise).timeIntervalSince1970, accuracy: 1)
        // The dip really is that short: the sun is under the angle twelve
        // minutes before the rise, and was still over it at twenty-five.
        let altitude = { (minutesBefore: Double) in
            SolarClock.altitudeInDegrees(at: rise.addingTimeInterval(-minutesBefore * 60),
                                         latitude: uppsala.latitude, longitude: uppsala.longitude)
        }
        XCTAssertLessThan(altitude(12), -7)
        XCTAssertGreaterThan(altitude(25), -7)
    }

    func testAPolarNightHasNoFirstLight() {
        // Longyearbyen at midwinter: the noon sun is 11° under the horizon.
        let midwinterEvening = Date(timeIntervalSince1970: 1_797_872_400)   // 21 Dec 2026, 18:00 there
        XCTAssertNil(SolarClock.rises(through: -7, after: midwinterEvening, latitude: 78.2232, longitude: 15.6267))
        // Nor is there one at the poles themselves, where the formulas run
        // out of horizon: an answer, not a crash.
        XCTAssertNil(SolarClock.rises(through: -7, after: midwinterEvening, latitude: 90, longitude: 0))
        XCTAssertNil(SolarClock.rises(through: -7, after: midwinterEvening, latitude: -90, longitude: 0))
    }

    func testARiseIsTheSunGoingUpNotComingDown() throws {
        // Asked in the afternoon, the answer is tomorrow morning's crossing,
        // not this evening's on the way down; and either side of it the sun
        // is under, then over.
        let afternoon = date(2026, 11, 21, 15)
        let rise = try XCTUnwrap(SolarClock.rises(through: -7, after: afternoon, latitude: chicago.latitude,
                                                  longitude: chicago.longitude))
        XCTAssertEqual(clock(rise), "06:12:14")
        XCTAssertGreaterThan(rise, date(2026, 11, 22, 0))
        let before = SolarClock.altitudeInDegrees(at: rise.addingTimeInterval(-30), latitude: chicago.latitude,
                                         longitude: chicago.longitude)
        let after = SolarClock.altitudeInDegrees(at: rise.addingTimeInterval(30), latitude: chicago.latitude,
                                        longitude: chicago.longitude)
        XCTAssertLessThan(before, -7)
        XCTAssertGreaterThan(after, -7)
        // Asked a second after it, the answer is the next morning's.
        let next = try XCTUnwrap(SolarClock.rises(through: -7, after: rise.addingTimeInterval(1),
                                                  latitude: chicago.latitude, longitude: chicago.longitude))
        XCTAssertEqual(next.timeIntervalSince(rise), 86_400, accuracy: 120)
    }
}
