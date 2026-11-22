import XCTest
@testable import TwoOfUs

/// The season (`SkySeason`) against the sky lab's own output
/// (`SkyCoreFixturesSeason`, exported from design/sky-lab/lab/season.js):
/// every field, on every day of his first year. The port is the lab's
/// arithmetic, so the two agree to the last few bits of a sine; what is
/// asserted is twelve decimal places — nine for the snow in the air, whose
/// roll multiplies a sine by 43758 and with it the last bit's disagreement
/// between one maths library and another (7 × 10⁻¹² between this Linux and
/// the lab's JavaScript on 24 December).
final class SkySeasonTests: XCTestCase {
    private typealias Lab = SkyCoreFixturesSeason

    private var chicagoTime: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        chicagoTime.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    /// Holds one season against the lab's cells for it: the name, the four
    /// weights, and the ten amounts, in the fixture's column order.
    private func assertSeason(_ season: SkySeason, is cells: ArraySlice<String>, _ what: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        let cells = Array(cells)
        XCTAssertEqual(season.name.rawValue, cells[0], "\(what): name", file: file, line: line)
        let mine = [season.weights.winter, season.weights.spring, season.weights.summer, season.weights.autumn,
                    season.snow, season.snowfall, season.foliage, season.leafHue, season.leafFall,
                    season.blossom, season.petals, season.fireflies, season.grass, season.frost]
        let names = ["winter", "spring", "summer", "autumn", "snow", "snowfall", "foliage", "leafHue",
                     "leafFall", "blossom", "petals", "fireflies", "grass", "frost"]
        for (index, value) in mine.enumerated() {
            XCTAssertEqual(value, SkyCoreFixture.number(cells[index + 1]), accuracy: names[index] == "snowfall" ? 1e-9 : 1e-12,
                           "\(what): \(names[index])", file: file, line: line)
        }
    }

    // MARK: His first year

    func testTheSeasonsTurn() {
        // 2 July 2026 to 1 July 2027: each day's season by the calendar, as
        // Home will ask for it, is the lab's for that date.
        let rows = SkyCoreFixture.rows(Lab.firstYear)
        XCTAssertEqual(rows.count, 365)
        for row in rows {
            let ymd = row[0].split(separator: "-").map { Int($0) ?? 0 }
            let place = SkyPlace(latitude: SkyCoreFixture.number(row[2]), longitude: -87.63)
            let season = SkySeason.at(date(ymd[0], ymd[1], ymd[2]), place: place, calendar: chicagoTime)
            assertSeason(season, is: row[3..<18], row[0])
            // …and by the day's number, which is the lab's too.
            XCTAssertEqual(chicagoTime.ordinality(of: .day, in: .year, for: date(ymd[0], ymd[1], ymd[2])),
                           Int(SkyCoreFixture.number(row[1])), row[0])
            XCTAssertEqual(season, SkySeason.on(dayOfYear: SkyCoreFixture.number(row[1]), latitude: place.latitude), row[0])
        }
    }

    func testTheDayOfTheYearIsTheLocalOne() {
        // Late on New Year's Eve in Chicago it is already 1 January in
        // Greenwich; the hills are still on day 365.
        let lateEvening = date(2026, 12, 31, 23)
        XCTAssertEqual(SkySeason.at(lateEvening, place: SkyPlace(latitude: 41.88, longitude: -87.63),
                                    calendar: chicagoTime),
                       SkySeason.on(dayOfYear: 365, latitude: 41.88))
    }

    func testHisFirstYearReadsInTheHills() throws {
        // The design's own calendar (lab/season.js): bare by mid-November,
        // snow from mid-December to early March, blossom from mid-April to
        // mid-May, fireflies from June to mid-August. On the lab's default
        // day, 21 November, the tree is bare and the first frost is down.
        let rows = SkyCoreFixture.rows(Lab.firstYear)
        let on = { (day: String) -> SkySeason in
            let ymd = day.split(separator: "-").map { Int($0) ?? 0 }
            return SkySeason.at(self.date(ymd[0], ymd[1], ymd[2]),
                                place: SkyPlace(latitude: 41.88, longitude: -87.63), calendar: self.chicagoTime)
        }
        XCTAssertNotNil(rows.first { $0[0] == "2026-11-21" })

        let november = on("2026-11-21")
        XCTAssertEqual(november.name, .autumn)
        XCTAssertEqual(november.foliage, 0, accuracy: 1e-12, "bare")
        XCTAssertEqual(november.snow, 0, accuracy: 1e-12)
        XCTAssertGreaterThan(november.frost, 0.9)

        let january = on("2027-01-15")
        XCTAssertEqual(january.name, .winter)
        XCTAssertEqual(january.snow, 1, accuracy: 1e-12)
        XCTAssertEqual(january.frost, 0, accuracy: 1e-12, "no hoar where snow lies")

        let may = on("2027-05-01")
        XCTAssertEqual(may.name, .spring)
        XCTAssertEqual(may.blossom, 1, accuracy: 1e-12)
        XCTAssertEqual(may.petals, 0.8, accuracy: 1e-12)
        XCTAssertLessThan(may.leafHue, 0.25, "fresh green")

        let july = on("2026-07-15")
        XCTAssertEqual(july.name, .summer)
        XCTAssertEqual(july.foliage, 1, accuracy: 1e-12)
        XCTAssertEqual(july.fireflies, 1, accuracy: 1e-12)
        XCTAssertEqual(july.leafHue, 0.5, accuracy: 1e-12, "deep summer green")

        let october = on("2026-10-20")
        XCTAssertGreaterThan(october.leafHue, 0.9, "turned")
        XCTAssertEqual(october.leafFall, 1, accuracy: 1e-12)
    }

    func testThereIsNoDayOnWhichTheHillsChange() {
        // "Everything is continuous." From one day to the next no amount
        // moves by more than an eighth. Two things are not amounts of that
        // kind: the snow in the air, which is a day's weather; and the
        // leaf's hue, which the lab winds back from russet to fresh green
        // once a year — on New Year's Eve, when there is not a leaf on the
        // tree to show it.
        var previous = SkySeason.on(dayOfYear: 364, latitude: 41.88)
        var hueResets: [Int] = []
        for day in Array(365...365) + Array(1...364) {
            let season = SkySeason.on(dayOfYear: Double(day), latitude: 41.88)
            let pairs = [(season.snow, previous.snow), (season.foliage, previous.foliage),
                         (season.leafFall, previous.leafFall), (season.blossom, previous.blossom),
                         (season.fireflies, previous.fireflies), (season.grass, previous.grass),
                         (season.frost, previous.frost), (season.weights.winter, previous.weights.winter),
                         (season.weights.spring, previous.weights.spring),
                         (season.weights.summer, previous.weights.summer),
                         (season.weights.autumn, previous.weights.autumn)]
            for (now, before) in pairs {
                XCTAssertLessThan(abs(now - before), 0.125, "day \(day)")
            }
            if abs(season.leafHue - previous.leafHue) >= 0.125 {
                hueResets.append(day)
                XCTAssertEqual(season.foliage, 0, accuracy: 1e-12, "bare when the hue winds back")
                XCTAssertEqual(season.leafFall, 0, accuracy: 1e-12)
            }
            XCTAssertEqual(season.weights.winter + season.weights.spring + season.weights.summer
                           + season.weights.autumn, 1, accuracy: 1e-12)
            previous = season
        }
        XCTAssertEqual(hueResets, [365])
    }

    // MARK: Elsewhere, and told

    func testSouthOfTheEquatorTheYearIsHalfAYearOutOfStep() {
        let rows = SkyCoreFixture.rows(Lab.elsewhere)
        XCTAssertGreaterThan(rows.count, 50)
        var south = 0
        for row in rows {
            let told = row[3] == "own" ? nil : SkyCoreFixture.number(row[3])
            let season = SkySeason.on(dayOfYear: SkyCoreFixture.number(row[1]), latitude: SkyCoreFixture.number(row[2]), snowfall: told)
            assertSeason(season, is: row[4..<19], "\(row[0]) day \(row[1])")
            if row[0] == "south" { south += 1 }
        }
        XCTAssertGreaterThan(south, 30)
        // Sydney's mid-January is high summer.
        let sydney = SkySeason.on(dayOfYear: 15, latitude: -33.8688)
        XCTAssertEqual(sydney.name, .summer)
        XCTAssertEqual(sydney.snow, 0, accuracy: 1e-12)
        XCTAssertEqual(sydney.foliage, 1, accuracy: 1e-12)
    }

    func testSnowInTheAirCanBeToldAndTheSnowOnTheLandCannot() {
        // The bench's switch (the lab's `snowfall=`): told, the air holds
        // that much, kept to 0 … 1; the land is still the date's.
        let july = SkySeason.on(dayOfYear: 196, latitude: 41.88, snowfall: 1.3)
        XCTAssertEqual(july.snowfall, 1)
        XCTAssertEqual(july.snow, 0, accuracy: 1e-12, "no snow lies in July, whatever falls")
        XCTAssertEqual(SkySeason.on(dayOfYear: 196, latitude: 41.88, snowfall: -1).snowfall, 0)
        XCTAssertEqual(SkySeason.on(dayOfYear: 7, latitude: 41.88, snowfall: 0).snowfall, 0,
                       "a clear day, told, on a day that has snow of its own")
        XCTAssertGreaterThan(SkySeason.on(dayOfYear: 7, latitude: 41.88).snowfall, 0.5)
        XCTAssertEqual(SkySeason.on(dayOfYear: 7, latitude: 41.88, snowfall: .nan),
                       SkySeason.on(dayOfYear: 7, latitude: 41.88), "nonsense is not a telling")
    }

    func testSnowFallsOnAboutTwoWinterDaysInFive() {
        // The day's own roll, counted over his first winter: of the days
        // with snow lying (more than half), how many have it in the air.
        // The lab's count is 33 days of 79, and the app rolls the same days.
        let rows = SkyCoreFixture.rows(Lab.firstYear)
        let labLying = rows.filter { SkyCoreFixture.number($0[8]) > 0.5 }.map { $0[0] }
        let labFalling = rows.filter { SkyCoreFixture.number($0[9]) > 0 }.map { $0[0] }
        XCTAssertEqual(labLying.count, 79)
        XCTAssertEqual(labFalling.count, 33)

        var lying: [String] = []
        var falling: [String] = []
        for row in rows {
            let season = SkySeason.on(dayOfYear: SkyCoreFixture.number(row[1]), latitude: SkyCoreFixture.number(row[2]))
            if season.snow > 0.5 { lying.append(row[0]) }
            if season.snowfall > 0 {
                falling.append(row[0])
                XCTAssertGreaterThan(season.snow, 0.5, "\(row[0]): never in the air without lying on the land")
                XCTAssertGreaterThanOrEqual(season.snowfall, 0.5)
                XCTAssertLessThan(season.snowfall, 0.9)
            }
        }
        XCTAssertEqual(lying, labLying)
        XCTAssertEqual(falling, labFalling)
    }

    // MARK: The tree's step

    func testTheTreeIsCutOnlyWhenTheSeasonHasMovedAFortieth() {
        // The lab keys its tree masks on seven amounts rounded to fortieths
        // (skies/hill-painted.js, `seaKey`). Day for day the step is the
        // lab's, so the app cuts the tree on the same days the mockup did:
        // 186 different trees in his first year, and the same one for the
        // 77 days from 2 July.
        let rows = SkyCoreFixture.rows(Lab.firstYear)
        var steps: Set<[Int]> = []
        var run = 0
        var longest = 0
        var previous: [Int]?
        for row in rows {
            let season = SkySeason.on(dayOfYear: SkyCoreFixture.number(row[1]), latitude: SkyCoreFixture.number(row[2]))
            let labs = row[18..<25].map { Int(SkyCoreFixture.number($0)) }
            XCTAssertEqual(season.step, labs, row[0])
            steps.insert(season.step)
            run = season.step == previous ? run + 1 : 1
            longest = max(longest, run)
            previous = season.step
        }
        XCTAssertEqual(steps.count, 186)
        XCTAssertEqual(longest, 77)
        XCTAssertEqual(SkySeason.on(dayOfYear: 183, latitude: 41.88).step, [40, 0, 0, 0, 0, 40, 20],
                       "2 July: full leaf, green grass, deep summer green")
    }
}
