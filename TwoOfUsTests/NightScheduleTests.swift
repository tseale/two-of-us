import XCTest
@testable import TwoOfUs

/// Pure-logic tests for `NightSchedule`, the dynamic nighttime feed schedule:
/// window resolution (incl. the midnight wrap), the first-feed anchor, slot
/// construction from the anchor, the alternating rotation seeded by whoever
/// logged that anchor, fulfillment matching, and the waiting/day states. No
/// store, no CloudKit — models are built standalone with a pinned calendar
/// and `now`.
final class NightScheduleTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        return c
    }()

    private let taylorID = UUID()
    private let katieID = UUID()

    private var parents: [NightSchedule.Parent] {
        [NightSchedule.Parent(id: taylorID, name: "Taylor", colorHex: "#AABBCC"),
         NightSchedule.Parent(id: katieID, name: "Katie", colorHex: "#112233")]
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    /// Night 8pm–8am, every 4h, alternating, unless overridden.
    private func schedule(
        feeds: [FeedEvent] = [], now: Date,
        startMinute: Int = 20 * 60, endMinute: Int = 8 * 60,
        spacing: Int = 240, rotation: NightRotation = .alternating,
        parents: [NightSchedule.Parent]? = nil
    ) -> NightSchedule {
        NightSchedule(nightStartMinute: startMinute, nightEndMinute: endMinute,
                      spacingMinutes: spacing, rotation: rotation,
                      parents: parents ?? self.parents, feeds: feeds,
                      calendar: calendar, now: now)
    }

    private func feed(at date: Date, by loggerID: UUID? = nil, name: String = "Taylor",
                      deleted: Bool = false) -> FeedEvent {
        let f = FeedEvent(baby: nil, amountOz: 3, timestamp: date,
                          loggedByID: loggerID ?? taylorID, loggedByName: name,
                          loggedByColorHex: "")
        if deleted { f.deletedAt = date }
        return f
    }

    // MARK: States

    func testDaytimeIsDayState() {
        XCTAssertEqual(schedule(now: date(2026, 7, 21, 14, 0)).state, .day)
    }

    func testInWindowWithNoFeedIsWaiting() {
        let now = date(2026, 7, 21, 21, 0)
        let state = schedule(now: now).state
        XCTAssertEqual(state, .waiting(windowStart: date(2026, 7, 21, 20, 0),
                                       windowEnd: date(2026, 7, 22, 8, 0)))
    }

    func testAfterMidnightWindowStartWasYesterday() {
        // 2am: the window opened at 8pm YESTERDAY and closes at 8am today.
        let now = date(2026, 7, 22, 2, 0)
        let state = schedule(now: now).state
        XCTAssertEqual(state, .waiting(windowStart: date(2026, 7, 21, 20, 0),
                                       windowEnd: date(2026, 7, 22, 8, 0)))
    }

    func testDaytimeFeedDoesNotAnchorTheNight() {
        let feeds = [feed(at: date(2026, 7, 21, 17, 30))]
        if case .waiting = schedule(feeds: feeds, now: date(2026, 7, 21, 21, 0)).state {
        } else {
            XCTFail("a feed before the window opened must not start the night")
        }
    }

    func testZeroLengthWindowIsAlwaysDay() {
        let s = schedule(now: date(2026, 7, 21, 21, 0), startMinute: 20 * 60, endMinute: 20 * 60)
        XCTAssertEqual(s.state, .day)
    }

    // MARK: Construction from the anchor

    func testFirstFeedAnchorsScheduleFromItsActualTime() {
        // Spec example: 4h interval, first feed 9:30pm → 9:30 (done), 1:30am, 5:30am.
        let anchor = feed(at: date(2026, 7, 21, 21, 30))
        let occs = schedule(feeds: [anchor], now: date(2026, 7, 21, 22, 0)).occurrences()

        XCTAssertEqual(occs.map(\.date), [
            date(2026, 7, 21, 21, 30), date(2026, 7, 22, 1, 30), date(2026, 7, 22, 5, 30),
        ])
        XCTAssertEqual(occs[0].status, .fulfilled(byEventID: anchor.id),
                       "the anchor feed is slot zero, already done")
        XCTAssertEqual(occs[1].status, .upcoming)
        XCTAssertTrue(occs.allSatisfy { $0.source == .night })
        XCTAssertTrue(occs.allSatisfy { $0.kind == .feed })
    }

    func testSlotsStopAtWindowEnd() {
        // First feed 9pm, every 4h in an 8pm–8am night → 9pm, 1am, 5am; 9am is out.
        let occs = schedule(feeds: [feed(at: date(2026, 7, 21, 21, 0))],
                            now: date(2026, 7, 21, 21, 5)).occurrences()
        XCTAssertEqual(occs.count, 3)
        XCTAssertEqual(occs.last?.date, date(2026, 7, 22, 5, 0))
    }

    func testEarliestNightFeedWinsAsAnchor() {
        let first = feed(at: date(2026, 7, 21, 20, 15))
        let later = feed(at: date(2026, 7, 21, 22, 40))
        let occs = schedule(feeds: [later, first], now: date(2026, 7, 21, 23, 0)).occurrences()
        XCTAssertEqual(occs.first?.date, first.timestamp)
    }

    func testDeletedFeedCannotAnchor() {
        let ghost = feed(at: date(2026, 7, 21, 20, 15), deleted: true)
        if case .waiting = schedule(feeds: [ghost], now: date(2026, 7, 21, 21, 0)).state {
        } else {
            XCTFail("a deleted feed must not start the night")
        }
    }

    func testGarbageSpacingYieldsOnlyTheAnchorSlot() {
        let occs = schedule(feeds: [feed(at: date(2026, 7, 21, 21, 0))],
                            now: date(2026, 7, 21, 21, 5), spacing: 5).occurrences()
        XCTAssertEqual(occs.count, 1, "sub-minimum spacing must not loop the night away")
    }

    // MARK: Rotation

    func testRotationStartsFromWhoeverLoggedTheAnchor() {
        // Katie logs the first feed → Katie, Taylor, Katie.
        let anchor = feed(at: date(2026, 7, 21, 21, 30), by: katieID, name: "Katie")
        let occs = schedule(feeds: [anchor], now: date(2026, 7, 21, 22, 0)).occurrences()

        XCTAssertEqual(occs.map(\.assignedToName), ["Katie", "Taylor", "Katie"])
        XCTAssertEqual(occs[1].assignedToID, taylorID,
                       "the parent who did NOT take the first feed is up next")
    }

    func testRotationOffLeavesEverySlotUnassigned() {
        let occs = schedule(feeds: [feed(at: date(2026, 7, 21, 21, 30))],
                            now: date(2026, 7, 21, 22, 0), rotation: .none).occurrences()
        XCTAssertTrue(occs.allSatisfy { $0.assignedToID == nil },
                      "no rotation → unassigned → both phones ring")
    }

    func testSoloParentLeavesSlotsUnassigned() {
        let solo = [NightSchedule.Parent(id: taylorID, name: "Taylor", colorHex: "")]
        let occs = schedule(feeds: [feed(at: date(2026, 7, 21, 21, 30))],
                            now: date(2026, 7, 21, 22, 0), parents: solo).occurrences()
        XCTAssertTrue(occs.allSatisfy { $0.assignedToID == nil })
    }

    func testAnchorFromUnknownLoggerLeavesSlotsUnassigned() {
        let occs = schedule(feeds: [feed(at: date(2026, 7, 21, 21, 30), by: UUID())],
                            now: date(2026, 7, 21, 22, 0)).occurrences()
        XCTAssertTrue(occs.allSatisfy { $0.assignedToID == nil },
                      "can't prove whose night it is → fail open to both phones")
    }

    // MARK: Fulfillment & overdue

    func testLaterFeedFulfillsItsNearbySlot() {
        let anchor = feed(at: date(2026, 7, 21, 21, 30))
        let oneThirtyFive = feed(at: date(2026, 7, 22, 1, 35), by: katieID, name: "Katie")
        let occs = schedule(feeds: [anchor, oneThirtyFive],
                            now: date(2026, 7, 22, 2, 0)).occurrences()

        XCTAssertEqual(occs[1].status, .fulfilled(byEventID: oneThirtyFive.id),
                       "a bottle near the 1:30 slot ticks it off")
        XCTAssertEqual(occs[2].status, .upcoming)
    }

    func testUnfulfilledPastSlotReadsOverdue() {
        let anchor = feed(at: date(2026, 7, 21, 21, 30))
        let occs = schedule(feeds: [anchor], now: date(2026, 7, 22, 3, 0)).occurrences()
        XCTAssertEqual(occs[1].status, .overdue, "1:30am came and went with no bottle")
    }

    // MARK: Identity

    func testOccurrenceIDsAreStableAndKeyedToTheNight() {
        // The night is keyed to the day it STARTED, even after midnight.
        let anchor = feed(at: date(2026, 7, 21, 21, 30))
        let evening = schedule(feeds: [anchor], now: date(2026, 7, 21, 22, 0)).occurrences()
        let smallHours = schedule(feeds: [anchor], now: date(2026, 7, 22, 2, 0)).occurrences()

        XCTAssertEqual(evening.map(\.id), smallHours.map(\.id),
                       "ids must survive midnight so rows/reminders self-replace")
        XCTAssertEqual(evening[0].id, "night.20260721.0")
        XCTAssertEqual(evening.map(\.slotID), smallHours.map(\.slotID),
                       "synthetic slot ids drive reminder request ids — stable too")
    }
}
