import XCTest
@testable import TwoOfUs

/// The tool's output is the only thing the "Ask" model reads, so its shape —
/// newest first, one line per event with the numbers spelled out, an honest
/// empty message, a cap with a count of what was omitted — is the contract.
final class CareEventsToolTests: XCTestCase {

    private let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now)!

    private func event(_ kind: CareEventKind, hoursAgo: Double, oz: Double? = nil,
                       minutes: Int? = nil, diaper: String? = nil, by: String = "Taylor") -> CareEventEntity {
        CareEventEntity(id: UUID(), babyName: "Miller", kind: kind,
                        time: noon.addingTimeInterval(-hoursAgo * 3600),
                        amountOz: oz, durationMinutes: minutes, diaperType: diaper, loggedBy: by)
    }

    func testRendersNewestFirstWithNumbers() {
        let events = [event(.feed, hoursAgo: 6, oz: 3), event(.feed, hoursAgo: 2, oz: 3.5)]
        let text = CareEventsTool.render(events, kind: .feed, days: 1, now: noon)
        let lines = text.components(separatedBy: "\n")

        XCTAssertEqual(lines[0], "2 events in the last 1 day, newest first:")
        XCTAssertTrue(lines[1].hasSuffix(": feed, 3.5 oz (by Taylor)"), lines[1])
        XCTAssertTrue(lines[2].hasSuffix(": feed, 3 oz (by Taylor)"), lines[2])
    }

    func testFiltersByKindAndReportsEmpty() {
        let events = [event(.feed, hoursAgo: 1, oz: 3), event(.diaper, hoursAgo: 3, diaper: "Dirty")]
        XCTAssertEqual(CareEventsTool.render(events, kind: .sleep, days: 7, now: noon),
                       "No sleep events logged in the last 7 days.")
        let diapers = CareEventsTool.render(events, kind: .diaper, days: 7, now: noon)
        XCTAssertTrue(diapers.contains(": dirty diaper (by Taylor)"))
        XCTAssertFalse(diapers.contains("feed"))
    }

    func testSleepShowsDurationOrStillAsleep() {
        let events = [event(.sleep, hoursAgo: 5, minutes: 95), event(.sleep, hoursAgo: 1)]
        let text = CareEventsTool.render(events, kind: nil, days: 1, now: noon)
        XCTAssertTrue(text.contains("sleep started, still asleep"))
        XCTAssertTrue(text.contains("sleep started, slept 1h 35m"))
    }

    func testCapsOutputAndCountsTheRest() {
        let events = (0..<(CareEventsTool.maximumEvents + 5)).map { event(.feed, hoursAgo: Double($0), oz: 2) }
        let text = CareEventsTool.render(events, kind: .feed, days: 30, now: noon)
        XCTAssertEqual(text.components(separatedBy: "\n- ").count - 1, CareEventsTool.maximumEvents)
        XCTAssertTrue(text.hasSuffix("(5 older events omitted)"))
    }
}
