import XCTest
@testable import TwoOfUs

/// Pure-logic tests for `NightSchedule`, the dynamic nighttime feed schedule:
/// window resolution (incl. the midnight wrap and the upcoming-night case),
/// the projected anchor (chained from the last feed by the daytime interval),
/// re-anchoring to a real in-window feed, the first-shift rotation, per-night
/// overrides, fulfillment matching, and the day/waiting states. No store, no
/// CloudKit — models are built standalone with a pinned calendar and `now`.
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

    /// Night 9pm–8am, day interval 3h, night spacing 4h, alternating with
    /// Taylor on first shift — the user's worked example, unless overridden.
    private func schedule(
        feeds: [FeedEvent] = [], overrides: [PlanOverride] = [], now: Date,
        startMinute: Int = 21 * 60, endMinute: Int = 8 * 60,
        spacing: Int = 240, dayInterval: Int = 180,
        rotation: NightRotation = .alternating, firstShiftID: UUID? = nil,
        parents: [NightSchedule.Parent]? = nil
    ) -> NightSchedule {
        NightSchedule(nightStartMinute: startMinute, nightEndMinute: endMinute,
                      spacingMinutes: spacing, dayIntervalMinutes: dayInterval,
                      rotation: rotation, firstShiftID: firstShiftID,
                      parents: parents ?? self.parents, feeds: feeds,
                      overrides: overrides, calendar: calendar, now: now)
    }

    private func feed(at date: Date, deleted: Bool = false) -> FeedEvent {
        let f = FeedEvent(baby: nil, amountOz: 3, timestamp: date,
                          loggedByID: taylorID, loggedByName: "Taylor",
                          loggedByColorHex: "")
        if deleted { f.deletedAt = date }
        return f
    }

    // MARK: The projected anchor

    func testProjectionChainsFromLastFeedIntoTheWindow() {
        // The spec example: fed 5:30pm, day interval 3h → 8:30pm is outside
        // the 9pm–8am window, 11:30pm is inside → tonight runs 11:30, then by
        // the 4h night spacing: 3:30, 7:30.
        let feeds = [feed(at: date(2026, 7, 21, 17, 30))]
        let occs = schedule(feeds: feeds, now: date(2026, 7, 21, 22, 0)).occurrences()

        XCTAssertEqual(occs.map(\.date), [
            date(2026, 7, 21, 23, 30), date(2026, 7, 22, 3, 30), date(2026, 7, 22, 7, 30),
        ])
        XCTAssertEqual(occs[0].status, .upcoming, "the projected anchor hasn't happened yet")
        XCTAssertTrue(occs.allSatisfy { $0.source == .night && $0.kind == .feed })
    }

    func testProjectionVisibleBeforeTheWindowOpens() {
        // 7pm — the window hasn't opened, but the evening glance (and the slot
        // alarm) should already see tonight starting at 11:30.
        let feeds = [feed(at: date(2026, 7, 21, 17, 30))]
        let occs = schedule(feeds: feeds, now: date(2026, 7, 21, 19, 0)).occurrences()

        XCTAssertEqual(occs.first?.date, date(2026, 7, 21, 23, 30))
        XCTAssertTrue(occs.allSatisfy { $0.status == .upcoming })
    }

    func testProjectionStepLandingExactlyOnWindowStartAnchorsThere() {
        // Fed 6pm, every 3h → 9pm is exactly the window edge → night starts 9pm.
        let feeds = [feed(at: date(2026, 7, 21, 18, 0))]
        let occs = schedule(feeds: feeds, now: date(2026, 7, 21, 21, 30)).occurrences()
        XCTAssertEqual(occs.first?.date, date(2026, 7, 21, 21, 0))
    }

    func testRealInWindowFeedReplacesTheProjection() {
        // Projection says 11:30, but the baby actually fed at 11:10 — the
        // night re-anchors: 11:10 (done), 3:10, 7:10.
        let feeds = [feed(at: date(2026, 7, 21, 17, 30)),
                     feed(at: date(2026, 7, 21, 23, 10))]
        let occs = schedule(feeds: feeds, now: date(2026, 7, 21, 23, 30)).occurrences()

        XCTAssertEqual(occs.map(\.date), [
            date(2026, 7, 21, 23, 10), date(2026, 7, 22, 3, 10), date(2026, 7, 22, 7, 10),
        ])
        XCTAssertEqual(occs[0].status, .fulfilled(byEventID: feeds[1].id))
    }

    func testEveningFeedShiftsTheProjection() {
        // An 8:50pm top-up (still outside the window) becomes the new chain
        // start: 8:50 + 3h = 11:50 → the night moves with the baby's rhythm.
        let feeds = [feed(at: date(2026, 7, 21, 17, 30)),
                     feed(at: date(2026, 7, 21, 20, 50))]
        let occs = schedule(feeds: feeds, now: date(2026, 7, 21, 22, 0)).occurrences()
        XCTAssertEqual(occs.first?.date, date(2026, 7, 21, 23, 50))
    }

    func testDeletedFeedsCannotAnchorOrProject() {
        let feeds = [feed(at: date(2026, 7, 21, 17, 30), deleted: true)]
        XCTAssertTrue(schedule(feeds: feeds, now: date(2026, 7, 21, 22, 0)).occurrences().isEmpty)
    }

    func testGarbageDayIntervalYieldsNoProjection() {
        let feeds = [feed(at: date(2026, 7, 21, 17, 30))]
        let occs = schedule(feeds: feeds, now: date(2026, 7, 21, 22, 0), dayInterval: 5).occurrences()
        XCTAssertTrue(occs.isEmpty, "a corrupt day interval must not loop the chain")
    }

    func testSlotsStopAtWindowEnd() {
        // Anchor 11:30, 4h spacing in a night ending 8am → 11:30, 3:30, 7:30;
        // 11:30am is out.
        let feeds = [feed(at: date(2026, 7, 21, 17, 30))]
        let occs = schedule(feeds: feeds, now: date(2026, 7, 21, 22, 0)).occurrences()
        XCTAssertEqual(occs.count, 3)
    }

    func testGarbageNightSpacingYieldsOnlyTheAnchorSlot() {
        let feeds = [feed(at: date(2026, 7, 21, 17, 30))]
        let occs = schedule(feeds: feeds, now: date(2026, 7, 21, 22, 0), spacing: 5).occurrences()
        XCTAssertEqual(occs.count, 1, "sub-minimum spacing must not loop the night away")
    }

    // MARK: States

    func testDaytimeIsDayState() {
        XCTAssertEqual(schedule(now: date(2026, 7, 21, 14, 0)).state, .day)
    }

    func testInWindowWithNoFeedsAtAllIsWaiting() {
        let state = schedule(now: date(2026, 7, 21, 22, 0)).state
        XCTAssertEqual(state, .waiting(windowStart: date(2026, 7, 21, 21, 0),
                                       windowEnd: date(2026, 7, 22, 8, 0)),
                       "nothing to project from — the schedule can't exist yet")
    }

    func testAfterMidnightWindowStartWasYesterday() {
        // 2am: the window opened at 9pm YESTERDAY and closes at 8am today.
        let state = schedule(now: date(2026, 7, 22, 2, 0)).state
        XCTAssertEqual(state, .waiting(windowStart: date(2026, 7, 21, 21, 0),
                                       windowEnd: date(2026, 7, 22, 8, 0)))
    }

    func testInWindowWithProjectionIsActive() {
        let feeds = [feed(at: date(2026, 7, 21, 17, 30))]
        if case .active(let occs) = schedule(feeds: feeds, now: date(2026, 7, 21, 22, 0)).state {
            XCTAssertEqual(occs.count, 3)
        } else {
            XCTFail("a projectable night is active, not waiting")
        }
    }

    func testZeroLengthWindowIsAlwaysDay() {
        let s = schedule(now: date(2026, 7, 21, 22, 0), startMinute: 21 * 60, endMinute: 21 * 60)
        XCTAssertEqual(s.state, .day)
        XCTAssertTrue(s.occurrences().isEmpty)
    }

    // MARK: Rotation (first shift)

    func testRotationStartsFromTheConfiguredFirstShift() {
        let feeds = [feed(at: date(2026, 7, 21, 17, 30))]
        let occs = schedule(feeds: feeds, now: date(2026, 7, 21, 22, 0),
                            firstShiftID: katieID).occurrences()
        XCTAssertEqual(occs.map(\.assignedToName), ["Katie", "Taylor", "Katie"])
    }

    func testNilFirstShiftDefaultsToJoinOrder() {
        let feeds = [feed(at: date(2026, 7, 21, 17, 30))]
        let occs = schedule(feeds: feeds, now: date(2026, 7, 21, 22, 0)).occurrences()
        XCTAssertEqual(occs.map(\.assignedToName), ["Taylor", "Katie", "Taylor"],
                       "no explicit choice → the first parent in join order, same on both phones")
    }

    func testDepartedFirstShiftFallsBackToJoinOrder() {
        let feeds = [feed(at: date(2026, 7, 21, 17, 30))]
        let occs = schedule(feeds: feeds, now: date(2026, 7, 21, 22, 0),
                            firstShiftID: UUID()).occurrences()
        XCTAssertEqual(occs.first?.assignedToID, taylorID)
    }

    func testRotationOffLeavesEverySlotUnassigned() {
        let feeds = [feed(at: date(2026, 7, 21, 17, 30))]
        let occs = schedule(feeds: feeds, now: date(2026, 7, 21, 22, 0),
                            rotation: .none).occurrences()
        XCTAssertTrue(occs.allSatisfy { $0.assignedToID == nil },
                      "no rotation → unassigned → both phones ring")
    }

    func testSoloParentLeavesSlotsUnassigned() {
        let solo = [NightSchedule.Parent(id: taylorID, name: "Taylor", colorHex: "")]
        let feeds = [feed(at: date(2026, 7, 21, 17, 30))]
        let occs = schedule(feeds: feeds, now: date(2026, 7, 21, 22, 0),
                            parents: solo).occurrences()
        XCTAssertTrue(occs.allSatisfy { $0.assignedToID == nil })
    }

    // MARK: Per-night overrides

    private func override(slotID: UUID, dayKey: Int, assignedToID: UUID? = nil,
                          name: String = "", skipped: Bool = false,
                          deleted: Bool = false, createdAt: Date = .distantPast) -> PlanOverride {
        let o = PlanOverride(slotID: slotID, dayKey: dayKey,
                             assignedToID: assignedToID, assignedToName: name,
                             isSkipped: skipped, createdByID: taylorID)
        o.createdAt = createdAt
        if deleted { o.deletedAt = .distantPast }
        return o
    }

    func testOverrideReassignsOneNightSlot() {
        // Rotation says slot 1 (3:30am) is Katie's; tonight it's overridden
        // back to Taylor. The other slots keep the rotation.
        let feeds = [feed(at: date(2026, 7, 21, 17, 30))]
        let o = override(slotID: NightSchedule.syntheticSlotID(nightKey: 20_260_721, index: 1),
                         dayKey: 20_260_721, assignedToID: taylorID, name: "Taylor")
        let occs = schedule(feeds: feeds, overrides: [o], now: date(2026, 7, 21, 22, 0),
                            firstShiftID: katieID).occurrences()

        XCTAssertEqual(occs.map(\.assignedToName), ["Katie", "Taylor", "Katie"])
        XCTAssertEqual(occs[1].activeOverrideID, o.id, "the swapped row carries its override for undo")
        XCTAssertNil(occs[0].activeOverrideID)
    }

    func testSkipOverrideSilencesOneNightSlot() {
        let feeds = [feed(at: date(2026, 7, 21, 17, 30))]
        let o = override(slotID: NightSchedule.syntheticSlotID(nightKey: 20_260_721, index: 1),
                         dayKey: 20_260_721, skipped: true)
        let occs = schedule(feeds: feeds, overrides: [o], now: date(2026, 7, 21, 22, 0)).occurrences()

        XCTAssertEqual(occs[1].status, .skipped)
        XCTAssertEqual(occs[2].status, .upcoming, "only the skipped night goes quiet")
    }

    func testDeletedOverrideDoesNotApply() {
        let feeds = [feed(at: date(2026, 7, 21, 17, 30))]
        let o = override(slotID: NightSchedule.syntheticSlotID(nightKey: 20_260_721, index: 1),
                         dayKey: 20_260_721, skipped: true, deleted: true)
        let occs = schedule(feeds: feeds, overrides: [o], now: date(2026, 7, 21, 22, 0)).occurrences()
        XCTAssertEqual(occs[1].status, .upcoming, "an undone override leaves the rotation in charge")
    }

    func testOverrideSurvivesReanchoring() {
        // Override tonight's SECOND feed, then the anchor shifts (real feed at
        // 11:10 instead of the projected 11:30) — the override stays attached
        // to "tonight's second feed", whatever its time now is.
        let projected = [feed(at: date(2026, 7, 21, 17, 30))]
        let o = override(slotID: NightSchedule.syntheticSlotID(nightKey: 20_260_721, index: 1),
                         dayKey: 20_260_721, assignedToID: taylorID, name: "Taylor")
        let before = schedule(feeds: projected, overrides: [o],
                              now: date(2026, 7, 21, 22, 0), firstShiftID: katieID).occurrences()
        XCTAssertEqual(before[1].assignedToName, "Taylor")

        let anchored = projected + [feed(at: date(2026, 7, 21, 23, 10))]
        let after = schedule(feeds: anchored, overrides: [o],
                             now: date(2026, 7, 21, 23, 30), firstShiftID: katieID).occurrences()
        XCTAssertEqual(after[1].date, date(2026, 7, 22, 3, 10))
        XCTAssertEqual(after[1].assignedToName, "Taylor",
                       "slot identity is ordinal — the swap follows the re-anchored time")
    }

    func testConcurrentOverridesResolveDeterministically() {
        let feeds = [feed(at: date(2026, 7, 21, 17, 30))]
        let slotID = NightSchedule.syntheticSlotID(nightKey: 20_260_721, index: 1)
        let older = override(slotID: slotID, dayKey: 20_260_721, assignedToID: taylorID,
                             name: "Taylor", createdAt: date(2026, 7, 21, 20, 0))
        let newer = override(slotID: slotID, dayKey: 20_260_721, assignedToID: katieID,
                             name: "Katie", createdAt: date(2026, 7, 21, 20, 5))
        let occs = schedule(feeds: feeds, overrides: [older, newer],
                            now: date(2026, 7, 21, 22, 0)).occurrences()
        XCTAssertEqual(occs[1].assignedToName, "Katie", "latest createdAt wins on both phones")
    }

    // MARK: Fulfillment & overdue

    func testLaterFeedFulfillsItsNearbySlot() {
        let anchor = feed(at: date(2026, 7, 21, 23, 30))
        let threeThirtyFive = feed(at: date(2026, 7, 22, 3, 35))
        let occs = schedule(feeds: [anchor, threeThirtyFive],
                            now: date(2026, 7, 22, 4, 0)).occurrences()

        XCTAssertEqual(occs[1].status, .fulfilled(byEventID: threeThirtyFive.id),
                       "a bottle near the 3:30 slot ticks it off")
        XCTAssertEqual(occs[2].status, .upcoming)
    }

    func testUnfulfilledPastSlotReadsOverdue() {
        let anchor = feed(at: date(2026, 7, 21, 23, 30))
        let occs = schedule(feeds: [anchor], now: date(2026, 7, 22, 5, 0)).occurrences()
        XCTAssertEqual(occs[1].status, .overdue, "3:30am came and went with no bottle")
    }

    // MARK: Identity

    func testOccurrenceIDsAreStableAndKeyedToTheNight() {
        // The night is keyed to the day it STARTED, even after midnight —
        // ids, synthetic slot ids, AND dayKey (the override key) all hold.
        let anchor = feed(at: date(2026, 7, 21, 23, 30))
        let evening = schedule(feeds: [anchor], now: date(2026, 7, 21, 23, 45)).occurrences()
        let smallHours = schedule(feeds: [anchor], now: date(2026, 7, 22, 2, 0)).occurrences()

        XCTAssertEqual(evening.map(\.id), smallHours.map(\.id),
                       "ids must survive midnight so rows/reminders self-replace")
        XCTAssertEqual(evening[0].id, "night.20260721.0")
        XCTAssertEqual(evening.map(\.slotID), smallHours.map(\.slotID))
        XCTAssertTrue(evening.allSatisfy { $0.dayKey == 20_260_721 },
                      "dayKey is the NIGHT's key — overrides must match across midnight")
    }
}
