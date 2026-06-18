import XCTest
import SwiftData
@testable import TwoOfUs

/// `StatsEngine` is a pure aggregation struct with injectable `calendar` and
/// `now`, so every test here runs against a fixed clock (2026-06-10 12:00 UTC)
/// and a fixed UTC calendar — no flakiness at midnight or across time zones.
@MainActor
final class StatsEngineTests: XCTestCase {
    private var container: ModelContainer!
    private var calendar = Calendar(identifier: .gregorian)
    private var now = Date()

    override func setUp() {
        super.setUp()
        container = AppModelContainer.make(inMemory: true)
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        now = date(2026, 6, 10, 12, 0)
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    // MARK: Builders

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    private func feed(_ oz: Double, at: Date, by name: String = "Taylor",
                      color: String = "#AABBCC", deleted: Bool = false) -> FeedEvent {
        let f = FeedEvent(baby: nil, amountOz: oz, timestamp: at, loggedByID: UUID(),
                          loggedByName: name, loggedByColorHex: color,
                          deletedAt: deleted ? at : nil)
        container.mainContext.insert(f)
        return f
    }

    private func sleep(from: Date, to: Date?, deleted: Bool = false) -> SleepEvent {
        let s = SleepEvent(baby: nil, startedAt: from, endedAt: to, loggedByID: UUID(),
                           loggedByName: "Taylor", loggedByColorHex: "#AABBCC",
                           deletedAt: deleted ? from : nil)
        container.mainContext.insert(s)
        return s
    }

    private func diaper(at: Date, deleted: Bool = false) -> DiaperEvent {
        let d = DiaperEvent(baby: nil, type: .wet, timestamp: at, loggedByID: UUID(),
                            loggedByName: "Taylor", loggedByColorHex: "#AABBCC",
                            deletedAt: deleted ? at : nil)
        container.mainContext.insert(d)
        return d
    }

    private func engine(feeds: [FeedEvent] = [], sleeps: [SleepEvent] = [],
                        diapers: [DiaperEvent] = []) -> StatsEngine {
        StatsEngine(feeds: feeds, sleeps: sleeps, diapers: diapers,
                    calendar: calendar, now: now)
    }

    // MARK: Daily summaries

    func testDailySummariesBucketByCalendarDayAndSkipDeleted() throws {
        let feeds = [
            feed(2, at: date(2026, 6, 10, 9)),
            feed(3, at: date(2026, 6, 10, 11)),
            feed(4, at: date(2026, 6, 9, 20)),
            feed(99, at: date(2026, 6, 10, 10), deleted: true),
        ]
        let diapers = [diaper(at: date(2026, 6, 10, 8))]

        let days = engine(feeds: feeds, diapers: diapers).dailySummaries(days: 2)

        XCTAssertEqual(days.count, 2)
        let yesterday = days[0], today = days[1]
        XCTAssertEqual(yesterday.day, date(2026, 6, 9, 0))
        XCTAssertEqual(yesterday.feedOz, 4)
        XCTAssertEqual(yesterday.feedCount, 1)
        XCTAssertEqual(today.feedOz, 5, "deleted feeds must not count")
        XCTAssertEqual(today.feedCount, 2)
        XCTAssertEqual(today.diaperCount, 1)
    }

    func testCrossMidnightSleepIsSplitBetweenDays() {
        // 23:00 June 9 → 01:00 June 10: an hour credited to each day, with the
        // full 2h stretch credited to the day the sleep started.
        let s = sleep(from: date(2026, 6, 9, 23), to: date(2026, 6, 10, 1))

        let days = engine(sleeps: [s]).dailySummaries(days: 2)

        XCTAssertEqual(days[0].sleepSeconds, 3600, accuracy: 1)
        XCTAssertEqual(days[1].sleepSeconds, 3600, accuracy: 1)
        XCTAssertEqual(days[0].longestStretch, 7200, accuracy: 1)
        XCTAssertEqual(days[1].longestStretch, 0, accuracy: 1)
    }

    func testActiveSleepContributesNothingUntilItEnds() {
        let s = sleep(from: date(2026, 6, 10, 10), to: nil)
        let today = engine(sleeps: [s]).dailySummaries(days: 1)[0]
        XCTAssertEqual(today.sleepSeconds, 0, accuracy: 1)
    }

    // MARK: Lifetime & records

    func testLifetimeTotalsSkipDeletedAndActiveSleeps() {
        let feeds = [feed(2, at: date(2026, 6, 8, 9)),
                     feed(3, at: date(2026, 6, 9, 9)),
                     feed(10, at: date(2026, 6, 9, 10), deleted: true)]
        let sleeps = [sleep(from: date(2026, 6, 9, 13), to: date(2026, 6, 9, 14)),
                      sleep(from: date(2026, 6, 10, 11), to: nil)]
        let diapers = [diaper(at: date(2026, 6, 9, 9)),
                       diaper(at: date(2026, 6, 9, 10), deleted: true)]

        let totals = engine(feeds: feeds, sleeps: sleeps, diapers: diapers).lifetime()

        XCTAssertEqual(totals.totalOz, 5)
        XCTAssertEqual(totals.feedCount, 2)
        XCTAssertEqual(totals.totalSleepSeconds, 3600, accuracy: 1)
        XCTAssertEqual(totals.diaperCount, 1)
    }

    func testLongestSleepEver() throws {
        let sleeps = [sleep(from: date(2026, 6, 8, 1), to: date(2026, 6, 8, 3)),
                      sleep(from: date(2026, 6, 9, 1), to: date(2026, 6, 9, 6)),
                      sleep(from: date(2026, 6, 10, 1), to: nil)]
        let record = try XCTUnwrap(engine(sleeps: sleeps).longestSleep())
        XCTAssertEqual(record.duration, 5 * 3600, accuracy: 1)
        XCTAssertEqual(record.date, date(2026, 6, 9, 1))
    }

    // MARK: Night shift

    func testNightShiftGroupsByCaregiverSortedByCount() {
        let feeds = [
            feed(3, at: date(2026, 6, 9, 22), by: "Taylor"),
            feed(3, at: date(2026, 6, 10, 5), by: "Taylor"),
            feed(3, at: date(2026, 6, 9, 3), by: "Katie"),
            feed(3, at: date(2026, 6, 9, 23), by: "Katie"),
            feed(3, at: date(2026, 6, 10, 2), by: "Katie", color: "#112233"),
            feed(3, at: date(2026, 6, 9, 12), by: "Katie"),   // midday — not night
        ]

        let shares = engine(feeds: feeds).nightShift(days: 7)

        XCTAssertEqual(shares.map(\.name), ["Katie", "Taylor"])
        XCTAssertEqual(shares.map(\.count), [3, 2])
    }

    func testNightShiftFallsBackToUnknownForEmptyName() {
        let feeds = [feed(3, at: date(2026, 6, 9, 22), by: "")]
        XCTAssertEqual(engine(feeds: feeds).nightShift().first?.name, "Unknown")
    }

    // MARK: Hungriest hour & cadence

    func testHungriestHourPicksTheBusiestBucket() {
        let feeds = [
            feed(3, at: date(2026, 6, 9, 9, 10)),
            feed(3, at: date(2026, 6, 9, 9, 50)),
            feed(3, at: date(2026, 6, 10, 9, 30)),
            feed(3, at: date(2026, 6, 10, 11, 0)),
        ]
        XCTAssertEqual(engine(feeds: feeds).hungriestHour(days: 14), 9)
    }

    func testHungriestHourIsNilWithNoFeeds() {
        XCTAssertNil(engine().hungriestHour())
    }

    func testAverageFeedIntervalAveragesConsecutiveGaps() throws {
        // 06:00 → 08:00 → 11:00: gaps of 2h and 3h, average 2.5h.
        let feeds = [feed(3, at: date(2026, 6, 10, 6)),
                     feed(3, at: date(2026, 6, 10, 8)),
                     feed(3, at: date(2026, 6, 10, 11))]
        let avg = try XCTUnwrap(engine(feeds: feeds).averageFeedInterval(fromDaysAgo: 7, toDaysAgo: 0))
        XCTAssertEqual(avg, 2.5 * 3600, accuracy: 1)
    }

    func testAverageFeedIntervalNeedsAtLeastTwoFeeds() {
        let feeds = [feed(3, at: date(2026, 6, 10, 6))]
        XCTAssertNil(engine(feeds: feeds).averageFeedInterval(fromDaysAgo: 7, toDaysAgo: 0))
    }
}
