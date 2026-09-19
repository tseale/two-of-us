import XCTest
@testable import TwoOfUs

/// The raw-history digest is what the Private Cloud Compute model reads for
/// the weekly patterns card, so its shape is the contract: one block per day
/// with data, oldest first, every event spelled out, and nothing at all until
/// there's a week to compare against.
final class HistoryDigestTests: XCTestCase {

    private let calendar = Calendar.current

    private var noon: Date {
        calendar.date(bySettingHour: 12, minute: 0, second: 0, of: .now)!
    }

    private func at(daysAgo: Int, hour: Int, minute: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: noon)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private var dateOfBirth: Date { at(daysAgo: 30, hour: 8) }

    /// `days` consecutive days ending today, each with a feed, a sleep, and a diaper.
    private func history(days: Int) -> (feeds: [HistoryDigest.Feed], sleeps: [HistoryDigest.Sleep], diapers: [HistoryDigest.Diaper]) {
        var feeds: [HistoryDigest.Feed] = []
        var sleeps: [HistoryDigest.Sleep] = []
        var diapers: [HistoryDigest.Diaper] = []
        for d in 0..<days {
            feeds.append(.init(at: at(daysAgo: d, hour: 9), oz: 3))
            feeds.append(.init(at: at(daysAgo: d, hour: 6, minute: 30), oz: 2.5))
            sleeps.append(.init(start: at(daysAgo: d, hour: 10), end: at(daysAgo: d, hour: 11, minute: 15)))
            diapers.append(.init(at: at(daysAgo: d, hour: 9, minute: 30), type: d % 2 == 0 ? .dirty : .wet))
        }
        return (feeds, sleeps, diapers)
    }

    func testNilUntilAWeekOfData() {
        let h = history(days: 6)
        XCTAssertNil(HistoryDigest.render(babyName: "Miller", dateOfBirth: dateOfBirth,
                                          feeds: h.feeds, sleeps: h.sleeps, diapers: h.diapers, now: noon))
    }

    func testRendersOneBlockPerDayOldestFirst() throws {
        let h = history(days: 10)
        let digest = try XCTUnwrap(HistoryDigest.render(
            babyName: "Miller", dateOfBirth: dateOfBirth,
            feeds: h.feeds, sleeps: h.sleeps, diapers: h.diapers, now: noon))

        XCTAssertTrue(digest.hasPrefix("Miller is "))
        // Header + one block per day with data.
        XCTAssertEqual(digest.components(separatedBy: "\n\n").count, 11)
        // Day numbers ascend: the oldest block is day 21, the newest day 30.
        let dayNumbers = digest.components(separatedBy: "(day ").dropFirst()
            .compactMap { Int($0.prefix { $0.isNumber }) }
        XCTAssertEqual(dayNumbers, Array(21...30))
        // Feeds sorted within the day: 6:30 before 9:00, with the day's total.
        XCTAssertTrue(digest.contains("feeds (2, 5.5oz): \(TimeFormatting.clock(at(daysAgo: 0, hour: 6, minute: 30))) 2.5oz, "))
        XCTAssertTrue(digest.contains("diapers: 1 (1 dirty)"))
        XCTAssertTrue(digest.contains("diapers: 1 (0 dirty)"))
    }

    func testOngoingSleepAndEmptyCategoriesAreSpelledOut() throws {
        var h = history(days: 8)
        h.sleeps.append(.init(start: at(daysAgo: 0, hour: 11, minute: 30), end: nil))
        h.diapers.removeAll { calendar.isDate($0.at, inSameDayAs: noon) }
        let digest = try XCTUnwrap(HistoryDigest.render(
            babyName: "Miller", dateOfBirth: dateOfBirth,
            feeds: h.feeds, sleeps: h.sleeps, diapers: h.diapers, now: noon))

        XCTAssertTrue(digest.contains("\(TimeFormatting.clock(at(daysAgo: 0, hour: 11, minute: 30))) ongoing"))
        XCTAssertTrue(digest.contains("diapers: none logged"))
    }

    func testDaysWithoutAnythingLoggedAreSkipped() throws {
        var h = history(days: 9)
        // Blank out day 3 entirely — it must not appear as an empty block.
        let gapDay = at(daysAgo: 3, hour: 12)
        h.feeds.removeAll { calendar.isDate($0.at, inSameDayAs: gapDay) }
        h.sleeps.removeAll { calendar.isDate($0.start, inSameDayAs: gapDay) }
        h.diapers.removeAll { calendar.isDate($0.at, inSameDayAs: gapDay) }
        let digest = try XCTUnwrap(HistoryDigest.render(
            babyName: "Miller", dateOfBirth: dateOfBirth,
            feeds: h.feeds, sleeps: h.sleeps, diapers: h.diapers, now: noon))
        XCTAssertEqual(digest.components(separatedBy: "\n\n").count, 9)
        XCTAssertFalse(digest.contains("(day 27):"))
    }
}
