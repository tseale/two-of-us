import XCTest
@testable import TwoOfUs

final class NightReportTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    /// Midnight UTC, 2027-01-15.
    private let midnight = Date(timeIntervalSince1970: Double(1_800_000_000 - 1_800_000_000 % 86_400))
    private func at(_ hours: Double) -> Date { midnight.addingTimeInterval(hours * 3600) }
    private let me = UUID()
    private let you = UUID()

    // MARK: The window

    func testInTheMorningTheNightIsLastNight() {
        let night = NightReport.night(containing: at(9), startMinute: 1200, endMinute: 480,
                                      calendar: calendar)
        XCTAssertEqual(night.start, at(-4))
        XCTAssertEqual(night.end, at(8))
    }

    func testAfterTheWindowOpensTheNightIsTonight() {
        let night = NightReport.night(containing: at(21), startMinute: 1200, endMinute: 480,
                                      calendar: calendar)
        XCTAssertEqual(night.start, at(20))
        XCTAssertEqual(night.end, at(32))
    }

    func testPriorNightsShiftTheMomentToo() {
        let night = DateInterval(start: at(20), end: at(32))
        let prior = NightReport.priorNights(before: night, now: at(23), count: 2, calendar: calendar)
        XCTAssertEqual(prior.map(\.night.start), [at(-4), at(-28)])
        XCTAssertEqual(prior.map(\.now), [at(-1), at(-25)])
    }

    // MARK: The summary

    func testAsleepIsClippedToTheWindowButTheStretchIsWhole() {
        let night = DateInterval(start: at(20), end: at(32))
        let report = NightReport.summarize(
            night: night, now: at(33),
            sleeps: [.init(start: at(19.5), end: at(23.5)),
                     .init(start: at(24), end: at(29)),
                     .init(start: at(29.5), end: at(33))],
            feeds: [], diapers: [])
        // 3.5h (clipped from 19:30) + 5h + 2.5h (clipped to 8 AM)
        XCTAssertEqual(report.asleep, 11 * 3600)
        XCTAssertEqual(report.longestStretch, 5 * 3600)
        XCTAssertEqual(report.wakeUps, 2)
        XCTAssertTrue(report.isComplete)
    }

    func testAShortResettleIsNotAWakeUpAndDoesNotBreakTheStretch() {
        let night = DateInterval(start: at(20), end: at(32))
        let report = NightReport.summarize(
            night: night, now: at(33),
            sleeps: [.init(start: at(21), end: at(23)),
                     .init(start: at(23) + 120, end: at(25))],
            feeds: [], diapers: [])
        XCTAssertEqual(report.wakeUps, 0)
        XCTAssertEqual(report.longestStretch, 4 * 3600, accuracy: 121)
    }

    func testANightStillGoingStopsAtNowAndCountsTheRunningSleep() {
        let night = DateInterval(start: at(20), end: at(32))
        let report = NightReport.summarize(
            night: night, now: at(23),
            sleeps: [.init(start: at(21), end: nil)],
            feeds: [], diapers: [])
        XCTAssertFalse(report.isComplete)
        XCTAssertEqual(report.window.end, at(23))
        XCTAssertEqual(report.asleep, 2 * 3600)
    }

    func testFeedsAndDiapersAreSharedOutByWhoLoggedThem() {
        let night = DateInterval(start: at(20), end: at(32))
        let report = NightReport.summarize(
            night: night, now: at(33), sleeps: [],
            feeds: [.init(time: at(19), oz: 4, loggedByID: me),     // before the night
                    .init(time: at(22), oz: 4, loggedByID: me),
                    .init(time: at(25), oz: 3.5, loggedByID: you),
                    .init(time: at(28), oz: 4, loggedByID: me)],
            diapers: [.init(time: at(25), loggedByID: you)])
        XCTAssertEqual(report.feeds, 3)
        XCTAssertEqual(report.oz, 11.5)
        XCTAssertEqual(report.shares[me], NightReport.Share(feeds: 2, oz: 8, diapers: 0))
        XCTAssertEqual(report.shares[you], NightReport.Share(feeds: 1, oz: 3.5, diapers: 1))
    }

    func testTheUsualSkipsUntrackedNights() {
        let night = DateInterval(start: at(20), end: at(32))
        let slept = NightReport.summarize(night: night, now: at(33),
                                          sleeps: [.init(start: at(21), end: at(31))],
                                          feeds: [], diapers: [])
        let empty = NightReport.summarize(night: night, now: at(33), sleeps: [], feeds: [], diapers: [])
        XCTAssertEqual(NightReport.usualAsleep([slept, empty]), 10 * 3600)
        XCTAssertNil(NightReport.usualAsleep([empty]))
    }
}
