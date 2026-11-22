import XCTest
@testable import TwoOfUs

/// The palette asked the way Home will ask it — from a date, the
/// household's place and its calendar, through the app's own clocks
/// (`SolarClock`, `MoonClock`, `SkySeason`) — against the lab's palette for
/// that minute (`SkyCoreFixturesPalette`, which carries each row's date and
/// local time in Chicago).
///
/// `HillPaletteTests` hands the palette the lab's own sun and moon and
/// agrees to twelve places; this spans the types to hold the UNITS and the
/// rules between them: degrees, not radians; the moon's altitude with
/// refraction, and no moon at all while it is down; morning from the solar
/// day; the season from the local day of the year. The clocks are the lab's
/// to a billionth of a radian (`SkyCoreSunTests`, the lab's own
/// test-math.mjs), so the paints agree to a millionth.
final class SkyCoreLightTests: XCTestCase {
    private typealias Lab = SkyCoreFixturesPalette

    /// The lab's default place.
    private let chicago = SkyPlace(latitude: 41.88, longitude: -87.63)

    private var chicagoTime: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }

    /// One minute of the lab's table, read by column name.
    private struct Minute {
        let cells: [String]
        let columns: [String: Int]

        func text(_ name: String) -> String { cells[columns[name] ?? 0] }
        func number(_ name: String) -> Double { SkyCoreFixture.number(text(name)) }
        var what: String { "\(text("date")) \(text("time")) dark \(text("dark")) \(text("asleep"))" }
    }

    private var minutes: [Minute] {
        let names = SkyCoreFixture.rows(Lab.minutesColumns)[0]
        let columns = Dictionary(uniqueKeysWithValues: names.enumerated().map { ($1, $0) })
        return SkyCoreFixture.rows(Lab.minutes).map { Minute(cells: $0, columns: columns) }
    }

    /// The row's instant: its date and local time, by Chicago's calendar.
    /// (The lab is told the hours from UTC for each date — −6 in November
    /// and January, −5 in October, April and July — which is Chicago's own
    /// clock on those days.)
    private func date(of minute: Minute) -> Date {
        let ymd = minute.text("date").split(separator: "-").map { Int($0) ?? 0 }
        let hm = minute.text("time").split(separator: ":").map { Int($0) ?? 0 }
        return chicagoTime.date(from: DateComponents(year: ymd[0], month: ymd[1], day: ymd[2],
                                                     hour: hm[0], minute: hm[1]))!
    }

    /// What Home works out before it can ask for a palette: the sun's
    /// altitude in degrees, whether it is on its way up, and the moon while
    /// it is above the horizon.
    private func light(at date: Date) throws -> (sunAltitude: Double, morning: Bool, moon: HillPalette.Moon?) {
        let altitude = SolarClock.altitudeInDegrees(at: date, latitude: chicago.latitude, longitude: chicago.longitude)
        let day = try XCTUnwrap(SolarClock.day(containing: date, latitude: chicago.latitude,
                                               longitude: chicago.longitude, calendar: chicagoTime))
        let morning = HillPalette.isMorning(SolarClock.phase(at: date, in: day))
        var moon: HillPalette.Moon?
        if MoonClock.passProgress(at: date, latitude: chicago.latitude, longitude: chicago.longitude) != nil {
            let position = MoonClock.position(at: date, latitude: chicago.latitude, longitude: chicago.longitude)
            moon = HillPalette.Moon(altitude: position.altitude * 180 / .pi,
                                    fraction: MoonClock.illumination(at: date).fraction)
        }
        return (altitude, morning, moon)
    }

    func testTheAppsClocksGiveTheLabsLight() throws {
        let minutes = minutes
        XCTAssertEqual(minutes.count, 220)
        var moonsUp = 0
        for minute in minutes {
            let light = try light(at: date(of: minute))
            XCTAssertEqual(light.sunAltitude, minute.number("altitude"), accuracy: 1e-6, minute.what)
            XCTAssertEqual(light.morning, minute.text("morning") == "1", minute.what)
            if minute.text("moonAltitude") == "down" {
                XCTAssertNil(light.moon, "\(minute.what): the moon is down")
            } else {
                moonsUp += 1
                let moon = try XCTUnwrap(light.moon, "\(minute.what): the moon is up")
                XCTAssertEqual(moon.altitude, minute.number("moonAltitude"), accuracy: 1e-6, minute.what)
                XCTAssertEqual(moon.fraction, minute.number("moonFraction"), accuracy: 1e-9, minute.what)
            }
            // The season is the local day's.
            XCTAssertEqual(chicagoTime.ordinality(of: .day, in: .year, for: date(of: minute)),
                           Int(minute.number("dayOfYear")), minute.what)
        }
        XCTAssertEqual(moonsUp, 150)
    }

    func testAskedByTheClockThePaletteIsTheLabs() throws {
        let paints = ["ground", "snowLit", "snowShade", "frostLit", "ink", "inkLit", "leafShade", "leafBody0",
                      "leafBody1", "leafBody2", "leafCore", "leafLit", "leafSky", "leafGlow", "blossom",
                      "blossomShade", "blossomLit", "snow", "frost", "lastLeaf"]
        for minute in minutes {
            let date = date(of: minute)
            let light = try light(at: date)
            let palette = HillPalette(sunAltitude: light.sunAltitude, morning: light.morning, moon: light.moon,
                                      dark: minute.text("dark") == "1",
                                      season: SkySeason.at(date, place: chicago, calendar: chicagoTime),
                                      depth: minute.number("depth"))
            let mine = [palette.ground, palette.snowLit, palette.snowShade, palette.frostLit, palette.ink,
                        palette.inkLit, palette.leafShade, palette.leafBody[0], palette.leafBody[1],
                        palette.leafBody[2], palette.leafCore, palette.leafLit, palette.leafSky, palette.leafGlow,
                        palette.blossom, palette.blossomShade, palette.blossomLit, palette.snow, palette.frost,
                        palette.lastLeaf]
            for (name, paint) in zip(paints, mine) {
                XCTAssertEqual(paint.lightness, minute.number(name + "L"), accuracy: 1e-6, "\(minute.what): \(name)")
                XCTAssertEqual(paint.a, minute.number(name + "A"), accuracy: 1e-6, "\(minute.what): \(name)")
                XCTAssertEqual(paint.b, minute.number(name + "B"), accuracy: 1e-6, "\(minute.what): \(name)")
            }
            XCTAssertEqual(palette.air.presence, minute.number("presence"), accuracy: 1e-6, minute.what)
            XCTAssertEqual(palette.moonlight, minute.number("moonlight"), accuracy: 1e-6, minute.what)
            XCTAssertEqual(palette.mistAmount, minute.number("mistAmount"), accuracy: 1e-6, minute.what)
            XCTAssertEqual(palette.starsOut, minute.number("stars"), accuracy: 1e-6, minute.what)
            XCTAssertEqual(palette.lamp.kind.rawValue, minute.text("lamp"), minute.what)
        }
    }

    func testTheSignatureMinute() throws {
        // 21 November 2026, 4:10 pm in Chicago, dark appearance — the frame
        // the design was signed off on, "the tree against the setting sun":
        // the sun under two degrees and going down, the sky fully open, the
        // tree bare with frost on the ground, the land lit by the sun.
        let date = chicagoTime.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 16, minute: 10))!
        let light = try light(at: date)
        XCTAssertEqual(light.sunAltitude, 1.75, accuracy: 0.01)
        XCTAssertFalse(light.morning)
        let season = SkySeason.at(date, place: chicago, calendar: chicagoTime)
        XCTAssertEqual(season.foliage, 0, accuracy: 1e-9, "bare")
        let palette = HillPalette(sunAltitude: light.sunAltitude, morning: light.morning, moon: light.moon,
                                  dark: true, season: season, depth: 0)
        XCTAssertEqual(palette.air.presence, 1, accuracy: 1e-9, "the sunset's bloom is whole")
        XCTAssertEqual(palette.lamp, HillPalette.Lamp(kind: .sun, power: 1))
        XCTAssertEqual(palette.starsOut, 0)
        XCTAssertEqual(palette.deepNight, 0)
        XCTAssertGreaterThan(palette.backlit, 0.99, "the low sun burns through the crown")
        // The sun's disc is a warm gold, the lightest thing in the picture;
        // the ink of the tree against it is near black.
        XCTAssertGreaterThan(palette.air.sun.lightness, 0.85)
        XCTAssertLessThan(palette.ink.lightness, 0.06)
        XCTAssertLessThan(palette.shown(palette.ink).luminance, 0.002)
    }
}
