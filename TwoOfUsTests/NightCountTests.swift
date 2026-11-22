import XCTest
@testable import TwoOfUs

/// "Night N" (`NightCount`): the nights of his life, when the number turns,
/// and which of them are month-nights. The numbers are the sky lab's
/// (`SkyCoreFixturesNight`: lab/nights.js for the count, lab/solar.js for the
/// morning the count turns, lab/presence.js for why it turns there).
///
/// He was born on 2 July 2026, which makes him 142 days old on the lab's
/// default day, 21 November: Night 143.
final class NightCountTests: XCTestCase {
    private let chicago = SkyPlace(latitude: 41.8781, longitude: -87.6298)

    private var chicagoTime: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0, _ s: Int = 0) -> Date {
        chicagoTime.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))!
    }

    /// The time on Chicago's clock, "06:29:39".
    private func clock(_ date: Date) -> String {
        String(format: "%02d:%02d:%02d", chicagoTime.component(.hour, from: date),
               chicagoTime.component(.minute, from: date), chicagoTime.component(.second, from: date))
    }

    /// Stored with the time of day the picker happened to have: 3:42 pm.
    private var born: Date { at(2026, 7, 2, 15, 42) }

    private func night(_ now: Date, born: Date? = nil) -> Int {
        NightCount.night(at: now, born: born ?? self.born, place: chicago, calendar: chicagoTime)
    }

    private func labRise(_ label: String) throws -> Date {
        let row = try XCTUnwrap(SkyCoreFixture.rows(SkyCoreFixturesNight.sunRises).first { $0[0] == label })
        return Date(timeIntervalSince1970: SkyCoreFixture.number(row[5]) / 1000)
    }

    // MARK: Tonight's number

    func testTonightIsNight143AtAge142() throws {
        // lab/nights.js: "Night 1 is the night he was born; tonight is night
        // ageDays + 1." The lab's own row for the default age:
        let row = try XCTUnwrap(SkyCoreFixture.rows(SkyCoreFixturesNight.labNights).first { $0[0] == "142" })
        XCTAssertEqual(row[2], "143")
        XCTAssertEqual(row[1], "143", "and with tonight's lit he has 143 stars")

        XCTAssertEqual(chicagoTime.dateComponents([.day], from: chicagoTime.startOfDay(for: born),
                                                  to: at(2026, 11, 21, 0)).day, 142, "142 days old")
        XCTAssertEqual(night(at(2026, 11, 21, 16, 10)), 143, "the afternoon before")
        XCTAssertEqual(night(at(2026, 11, 21, 19, 40)), 143, "at bedtime")
    }

    func testTheNightHeWasBornIsNightOne() {
        XCTAssertEqual(night(at(2026, 7, 2, 12)), 1, "the day he was born, before the hour he was")
        XCTAssertEqual(night(at(2026, 7, 2, 21)), 1)
        XCTAssertEqual(night(at(2026, 7, 3, 2)), 1, "the small hours after: still his first night")
        XCTAssertEqual(night(at(2026, 7, 3, 12)), 2)
    }

    func testEveryAgeIsTheLabsNightNumber() {
        // A spread of ages from the day he was born to past his second
        // birthday, each at ten past four in the afternoon (the lab's
        // default hour): tonight's number is the lab's.
        let rows = SkyCoreFixture.rows(SkyCoreFixturesNight.labNights)
        XCTAssertGreaterThan(rows.count, 20)
        for row in rows {
            let age = Int(SkyCoreFixture.number(row[0]))
            let day = chicagoTime.date(byAdding: .day, value: age, to: at(2026, 7, 2, 0))!
            let afternoon = chicagoTime.date(bySettingHour: 16, minute: 10, second: 0, of: day)!
            XCTAssertEqual(night(afternoon), Int(SkyCoreFixture.number(row[2])), "age \(age)")
        }
    }

    func testOnlyTheDayHeWasBornCountsNotTheHour() {
        // The picker stores a time of day nobody chose. Born at one minute
        // past midnight or one minute to, it is the same Night 143.
        for hour in [(0, 1), (15, 42), (23, 59)] {
            XCTAssertEqual(night(at(2026, 11, 21, 16, 10), born: at(2026, 7, 2, hour.0, hour.1)), 143)
        }
    }

    func testADueDateStillToComeHasNoNightsYet() {
        XCTAssertEqual(night(at(2026, 6, 20, 21)), 0)
        XCTAssertEqual(night(at(2026, 7, 1, 21)), 0, "the evening before")
        XCTAssertEqual(night(at(2026, 7, 2, 3)), 0, "the small hours of the day itself belong to the night before")
    }

    // MARK: When it turns

    func testMidnightDoesNotTurnTheCount() {
        XCTAssertEqual(night(at(2026, 11, 21, 23, 59, 59)), 143)
        XCTAssertEqual(night(at(2026, 11, 22, 0, 0, 1)), 143)
        XCTAssertEqual(night(at(2026, 11, 22, 3, 0)), 143, "the 3 am feed is under the same number as bedtime")
    }

    func testTheCountTurnsOnceTheStarsAreOut() throws {
        // First light on 22 November is 06:12:14; the count does NOT turn
        // there. It turns as the sun passes −4°, 06:29:40 by the lab's sun.
        let firstLight = try labRise("chicago-first-light-22-nov-2026")
        let turn = try labRise("chicago-count-turns-22-nov-2026")
        XCTAssertEqual(clock(turn), "06:29:39", "06:29:39.7")

        XCTAssertEqual(night(firstLight.addingTimeInterval(5)), 143, "past first light: still last night's number")
        XCTAssertEqual(night(turn.addingTimeInterval(-2)), 143)
        XCTAssertEqual(night(turn.addingTimeInterval(2)), 144)
        XCTAssertEqual(night(at(2026, 11, 22, 12)), 144)

        let mine = try XCTUnwrap(NightCount.turn(afterNightOn: at(2026, 11, 21), place: chicago, calendar: chicagoTime))
        XCTAssertEqual(mine.timeIntervalSince1970, turn.timeIntervalSince1970, accuracy: 1)

        // Why there: the lab's starlight (lab/presence.js, `stars`). At
        // first light a third of it is still out, so a new star added then
        // would be seen to arrive; where the count turns there is none.
        let starlight = SkyCoreFixture.rows(SkyCoreFixturesNight.labStarlight)
        let stars = { (label: String) in
            SkyCoreFixture.number(starlight.first { $0[0] == label }?[3] ?? "")
        }
        XCTAssertEqual(stars("first-light"), 0.316, accuracy: 0.001)
        XCTAssertEqual(stars("the-turn"), 0, accuracy: 1e-9)
        XCTAssertEqual(SkyCoreFixture.number(starlight.first { $0[0] == "the-turn" }?[2] ?? ""),
                       NightCount.turnDegrees, accuracy: 1e-6)
        // And the app's own starlight — the amount the palette is painted
        // by (`HillPalette.starsOut`) — is the lab's at each of those
        // suns, so the count and the picture cannot part: nothing is out
        // where the count turns, and something still is just before.
        XCTAssertEqual(starlight.count, 3)
        for row in starlight {
            XCTAssertEqual(HillPalette.starsOut(sunAltitude: SkyCoreFixture.number(row[2])),
                           SkyCoreFixture.number(row[3]), accuracy: 1e-12, row[0])
        }
        XCTAssertEqual(HillPalette.starsOut(sunAltitude: NightCount.turnDegrees), 0)
        XCTAssertGreaterThan(HillPalette.starsOut(sunAltitude: NightCount.turnDegrees - 0.5), 0)
        XCTAssertEqual(HillPalette.starsOut(sunAltitude: NightRule.Policy.signedOff.firstLightDegrees), 0.316,
                       accuracy: 0.001)
    }

    func testInJuneTheCountTurnsBeforeFive() throws {
        let turn = try labRise("chicago-count-turns-21-jun-2027")
        XCTAssertEqual(String(clock(turn).prefix(5)), "04:54")
        let before = night(turn.addingTimeInterval(-2))
        XCTAssertEqual(before, 354, "20 June 2027 is his 354th night")
        XCTAssertEqual(night(turn.addingTimeInterval(2)), before + 1)
    }

    func testTheCountTurnsOnceEveryMorningAllYear() {
        // Day by day through his first year, the clocks changing twice:
        // noon's number is one more than the noon before, and so is 9 pm's.
        var day = at(2026, 7, 2, 0)
        var expected = 1
        while day < at(2027, 7, 3, 0) {
            let noon = chicagoTime.date(bySettingHour: 12, minute: 0, second: 0, of: day)!
            let evening = chicagoTime.date(bySettingHour: 21, minute: 0, second: 0, of: day)!
            let small = chicagoTime.date(bySettingHour: 2, minute: 30, second: 0, of: day)!
            XCTAssertEqual(night(noon), expected, "noon")
            XCTAssertEqual(night(evening), expected, "9 pm")
            XCTAssertEqual(night(small), expected - 1, "2:30 am belongs to the night before")
            day = chicagoTime.date(byAdding: .day, value: 1, to: day)!
            expected += 1
        }
        XCTAssertEqual(expected, 367, "366 mornings, from 2 July 2026 to 2 July 2027")
    }

    func testWhereTheSunGivesNoTurnTheCountTurnsWithTheNightsEnd() throws {
        // Bergen at midsummer: no first light by the sun, so the night ends
        // at 4 am by the clock, and by then the sun is already past −4°.
        // The count turns at 4 too — once, not twice and not never.
        var osloTime = Calendar(identifier: .gregorian)
        osloTime.timeZone = TimeZone(identifier: "Europe/Oslo")!
        let bergen = SkyPlace(latitude: 60.3913, longitude: 5.3221)
        func oslo(_ d: Int, _ h: Int, _ min: Int = 0) -> Date {
            osloTime.date(from: DateComponents(year: 2027, month: 6, day: d, hour: h, minute: min))!
        }
        let turn = try XCTUnwrap(NightCount.turn(afterNightOn: oslo(20, 12), place: bergen, calendar: osloTime))
        XCTAssertEqual(turn, oslo(21, 4))
        let bornThere = osloTime.date(from: DateComponents(year: 2026, month: 7, day: 2, hour: 9))!
        let count = { (now: Date) in
            NightCount.night(at: now, born: bornThere, place: bergen, calendar: osloTime)
        }
        XCTAssertEqual(count(oslo(21, 3, 59)), 354)
        XCTAssertEqual(count(oslo(21, 4, 1)), 355)
        XCTAssertEqual(count(oslo(21, 23)), 355)
    }

    // MARK: Month-nights

    func testMonthNightsAreHisRealMonthBirthdays() {
        // Born on the 2nd: the 2nd of every month. Night 32 is 2 August,
        // night 63 is 2 September (August has 31 days), and night 244 is
        // 2 March, after a 28-day February.
        let months = NightCount.monthNights(through: 366, born: born, calendar: chicagoTime)
        XCTAssertEqual(months.sorted(), [32, 63, 93, 124, 154, 185, 216, 244, 275, 305, 336, 366])
        for number in months {
            let day = chicagoTime.date(byAdding: .day, value: number - 1, to: at(2026, 7, 2, 0))!
            XCTAssertEqual(chicagoTime.component(.day, from: day), 2, "night \(number)")
        }
        XCTAssertFalse(months.contains(1), "the first night is a mark of its own")
        // Up to and including: his first birthday is night 366.
        XCTAssertFalse(NightCount.monthNights(through: 365, born: born, calendar: chicagoTime).contains(366))
        XCTAssertEqual(NightCount.monthNights(through: 31, born: born, calendar: chicagoTime), [])
        XCTAssertEqual(NightCount.monthNights(through: 0, born: born, calendar: chicagoTime), [])
    }

    func testEachMonthNightIsWithinANightOfTheLabs() {
        // The lab has no calendar for him and counts 30.4375-day months
        // ("the app would use his real date of birth"). So the two lists are
        // not the same list — but they are the same number of marks, each
        // within one night of its twin, through 800 nights.
        let lab = SkyCoreFixture.rows(SkyCoreFixturesNight.labMonthNights)[0]
            .map { Int(SkyCoreFixture.number($0)) }
        let mine = NightCount.monthNights(through: 800, born: born, calendar: chicagoTime).sorted()
        XCTAssertEqual(lab.count, 26)
        XCTAssertEqual(mine.count, lab.count)
        for (real, labs) in zip(mine, lab) {
            XCTAssertLessThanOrEqual(abs(real - labs), 1, "night \(real) against the lab's \(labs)")
        }
        // On the default day both have passed four of them.
        let row = SkyCoreFixture.rows(SkyCoreFixturesNight.labNights).first { $0[0] == "142" }
        XCTAssertEqual(row?[3], "4")
        XCTAssertEqual(NightCount.monthNights(through: 142, born: born, calendar: chicagoTime).count, 4)
    }

    func testBornOnTheThirtyFirstHisMonthNightIsTheLastDayOfAShorterMonth() {
        // 31 August: 30 September, 31 October, 30 November, 31 December,
        // 31 January, 28 February — and 31 March again, not the 28th.
        let late = at(2026, 8, 31, 8)
        let months = NightCount.monthNights(through: 220, born: late, calendar: chicagoTime).sorted()
        let days = months.map { number -> String in
            let day = chicagoTime.date(byAdding: .day, value: number - 1, to: at(2026, 8, 31, 0))!
            return "\(chicagoTime.component(.day, from: day))/\(chicagoTime.component(.month, from: day))"
        }
        XCTAssertEqual(days, ["30/9", "31/10", "30/11", "31/12", "31/1", "28/2", "31/3"])
    }
}
