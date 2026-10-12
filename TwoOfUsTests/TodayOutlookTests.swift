import XCTest
@testable import TwoOfUs

/// The outlook card is assembled from the engine's numbers, never generated —
/// these pin which rows appear when, and that every row shows its basis.
/// Clock strings are locale-formatted, so assertions check structure (kinds,
/// prefixes, the basis wording) rather than exact times.
final class TodayOutlookTests: XCTestCase {

    private let calendar = Calendar.current
    private let nightStart = 1200   // 8:00 PM
    private let nightEnd = 480      // 8:00 AM

    private var noon: Date {
        calendar.date(bySettingHour: 12, minute: 0, second: 0, of: .now)!
    }

    private func at(daysAgo: Int = 0, hour: Int, minute: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: noon)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private var dateOfBirth: Date {
        calendar.date(byAdding: .day, value: -75, to: noon)!
    }

    /// Three days of regular daytime bottles, ending mid-morning today.
    private var regularFeeds: [(timestamp: Date, oz: Double)] {
        var feeds: [(timestamp: Date, oz: Double)] = []
        for day in 1...3 {
            for hour in [8, 11, 14, 17] { feeds.append((at(daysAgo: day, hour: hour), 4.0)) }
        }
        feeds.append((at(hour: 8), 4.0))
        feeds.append((at(hour: 11), 4.0))
        return feeds
    }

    /// A week of ~45m naps plus a steady ~8:30 PM bedtime, last wake 11:30 AM.
    private var regularSleeps: [(startedAt: Date, endedAt: Date?)] {
        var sleeps: [(startedAt: Date, endedAt: Date?)] = []
        for day in 1...7 {
            let nap = at(daysAgo: day, hour: 9, minute: 30)
            sleeps.append((nap, nap.addingTimeInterval(45 * 60)))
            let afternoon = at(daysAgo: day, hour: 14)
            sleeps.append((afternoon, afternoon.addingTimeInterval(45 * 60)))
            let bed = at(daysAgo: day, hour: 20, minute: 30)
            sleeps.append((bed, bed.addingTimeInterval(5 * 3600)))
        }
        let morningNap = at(hour: 10, minute: 45)
        sleeps.append((morningNap, morningNap.addingTimeInterval(45 * 60)))
        return sleeps
    }

    private func rows(feeds: [(timestamp: Date, oz: Double)],
                      sleeps: [(startedAt: Date, endedAt: Date?)],
                      now: Date) -> [TodayOutlook.Row] {
        TodayOutlook.rows(
            feeds: feeds, sleeps: sleeps, dateOfBirth: dateOfBirth,
            targetFeedInterval: { _ in 3 * 3600 },
            nightStartMinute: nightStart, nightEndMinute: nightEnd, now: now)
    }

    func testMiddayRowsCoverFeedNapAndBedtime() {
        let rows = rows(feeds: regularFeeds, sleeps: regularSleeps, now: noon)
        XCTAssertEqual(rows.map(\.kind), [.nextFeed, .nextNap, .bedtime])

        let feed = rows[0]
        XCTAssertTrue(feed.value.hasPrefix("~"), feed.value)
        XCTAssertTrue(feed.value.contains("oz"), "steady 4 oz bottles should size the suggestion")
        XCTAssertTrue(feed.basis.contains("between feeds"), feed.basis)
        XCTAssertTrue(feed.basis.contains("last fed"), feed.basis)

        let nap = rows[1]
        XCTAssertTrue(nap.value.contains("usually ~"), "45m naps should project a length")
        XCTAssertTrue(nap.basis.contains("awake"), nap.basis)

        let bedtime = rows[2]
        XCTAssertTrue(bedtime.value.hasPrefix("~"), bedtime.value)
        XCTAssertTrue(bedtime.basis.contains("usually down"), bedtime.basis)
        XCTAssertTrue(bedtime.basis.contains("first stretch"),
                      "five-hour opening stretches should surface in the basis")
    }

    func testRunningSleepShowsWakeInsteadOfNextNap() {
        var sleeps = regularSleeps
        sleeps.append((at(hour: 11, minute: 40), nil))
        let kinds = rows(feeds: regularFeeds, sleeps: sleeps, now: noon).map(\.kind)
        XCTAssertTrue(kinds.contains(.wake), "he's down — the question is when he surfaces")
        XCTAssertFalse(kinds.contains(.nextNap))
    }

    func testDownForTheNightHidesBedtime() {
        var sleeps = regularSleeps
        sleeps.append((at(hour: 20, minute: 25), nil))
        let kinds = rows(feeds: regularFeeds, sleeps: sleeps,
                         now: at(hour: 21)).map(\.kind)
        XCTAssertFalse(kinds.contains(.bedtime), "he's already down for the night")
        XCTAssertFalse(kinds.contains(.nextNap))
    }

    func testOverdueFeedReadsAnyTimeNow() {
        // Last fed 8:00 AM against a ~3h cadence — by 12:30 the moment has
        // passed; the row degrades honestly instead of vanishing or showing a
        // stale clock time.
        var feeds = regularFeeds
        feeds.removeAll { $0.timestamp == at(hour: 11) }
        let result = rows(feeds: feeds, sleeps: regularSleeps,
                          now: at(hour: 12, minute: 30))
        guard let feed = result.first(where: { $0.kind == .nextFeed }) else {
            return XCTFail("expected a feed row")
        }
        XCTAssertTrue(feed.value.hasPrefix("any time now"), feed.value)
    }

    func testNoHistoryYieldsNoRows() {
        XCTAssertTrue(rows(feeds: [], sleeps: [], now: noon).isEmpty,
                      "better no prediction than a baseless one — the card hides")
    }

    func testThinHistoryYieldsNoFeedRow() {
        // Two feeds can't carry a cadence; the feed row must not dress the
        // configured target up as his pattern.
        let feeds: [(timestamp: Date, oz: Double)] = [
            (at(hour: 8), 4.0), (at(hour: 11), 4.0),
        ]
        let kinds = rows(feeds: feeds, sleeps: [], now: noon).map(\.kind)
        XCTAssertFalse(kinds.contains(.nextFeed))
    }
}
