import XCTest
@testable import TwoOfUs

final class DayRhythmTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private let today = Date(timeIntervalSince1970: Double(1_800_000_000 - 1_800_000_000 % 86_400))
    private func at(_ hours: Double, daysAgo: Int = 0) -> Date {
        today.addingTimeInterval(hours * 3600 - Double(daysAgo) * 86_400)
    }

    func testPaceComparesWithTheUsualByTheSameClockTime() {
        let feeds: [DayRhythm.Feed] = [
            .init(time: at(2), oz: 4), .init(time: at(6), oz: 4), .init(time: at(10), oz: 4),
            // Yesterday: 3 oz by 6 AM, 9 oz by noon, 15 in all.
            .init(time: at(3, daysAgo: 1), oz: 3), .init(time: at(9, daysAgo: 1), oz: 6),
            .init(time: at(20, daysAgo: 1), oz: 6),
        ]
        let pace = DayRhythm.pace(feeds: feeds, dayStart: today, now: at(12), calendar: calendar)
        XCTAssertEqual(pace.ozSoFar, 12)
        XCTAssertEqual(pace.usualSoFar, 9)
        XCTAssertEqual(pace.usualTotal, 15)
        XCTAssertEqual(pace.today.last?.hour, 12)
        XCTAssertEqual(pace.usual.count, 25)
    }

    func testPaceWithoutHistoryHasNoUsual() {
        let pace = DayRhythm.pace(feeds: [.init(time: at(2), oz: 4)], dayStart: today, now: at(5),
                                  calendar: calendar)
        XCTAssertTrue(pace.usual.isEmpty)
        XCTAssertNil(pace.usualSoFar)
        XCTAssertEqual(pace.today.map(\.oz), [0, 0, 4, 4, 4, 4])
    }

    func testRhythmStopsEarlierDaysAtNow() {
        let feeds: [DayRhythm.Feed] = [
            .init(time: at(1), oz: 4), .init(time: at(4), oz: 4), .init(time: at(7), oz: 5),
            // Yesterday by 9 AM: every 2h, 3 oz — the 8 PM bottle comes later.
            .init(time: at(2, daysAgo: 1), oz: 3), .init(time: at(4, daysAgo: 1), oz: 3),
            .init(time: at(6, daysAgo: 1), oz: 3), .init(time: at(20, daysAgo: 1), oz: 8),
        ]
        let sleeps: [DayRhythm.Sleep] = [
            .init(start: at(2), end: at(3)),                         // night — not a nap
            .init(start: at(8.5), end: at(10)),                       // running past now
            .init(start: at(8.5, daysAgo: 1), end: at(9.5, daysAgo: 1)),
        ]
        let rhythm = DayRhythm.rhythm(feeds: feeds, sleeps: sleeps, dayStart: today, now: at(9),
                                      dayBeginsMinute: 480, calendar: calendar)
        XCTAssertEqual(rhythm.feedGap.today, 3 * 3600)
        XCTAssertEqual(rhythm.feedGap.usual, 2 * 3600)
        XCTAssertEqual(rhythm.bottle.today ?? 0, 13.0 / 3, accuracy: 0.001)
        XCTAssertEqual(rhythm.bottle.usual, 3)
        XCTAssertEqual(rhythm.naps.today, 1800)
        XCTAssertEqual(rhythm.naps.usual, 1800)
        XCTAssertEqual(rhythm.napCount, 1)
    }
}
