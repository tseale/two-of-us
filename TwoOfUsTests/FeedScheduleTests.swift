import XCTest
@testable import TwoOfUs

/// The feed-schedule routing rule — the logic that decides which parent's
/// device arms a feed reminder. Sleep-critical in both directions: a wrongly
/// armed alarm wakes the off-duty parent; a wrongly skipped one means nobody
/// is reminded to feed the baby. The predicate must bias toward reminding
/// whenever the situation is ambiguous.
final class FeedScheduleTests: XCTestCase {
    private let taylor = UUID()
    private let wife = UUID()

    /// Today at `hour`:`minute` local — `FeedSlot.contains` only reads the
    /// time-of-day components, so the specific day is irrelevant.
    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now)!
    }

    private func slot(_ start: Int, _ end: Int, assignee: UUID? = nil) -> FeedSlot {
        FeedSlot(startMinutes: start, endMinutes: end, assignedParticipantID: assignee)
    }

    // MARK: Slot containment

    func testContainsSimpleWindow() {
        let s = slot(2 * 60, 4 * 60)                       // 02:00–04:00
        XCTAssertTrue(s.contains(at(2, 0)), "start is inclusive")
        XCTAssertTrue(s.contains(at(3, 59)))
        XCTAssertFalse(s.contains(at(4, 0)), "end is exclusive")
        XCTAssertFalse(s.contains(at(1, 59)))
        XCTAssertFalse(s.contains(at(14, 0)))
    }

    func testContainsWrapsPastMidnight() {
        let s = slot(22 * 60, 2 * 60)                      // 22:00–02:00
        XCTAssertTrue(s.contains(at(23, 30)))
        XCTAssertTrue(s.contains(at(0, 0)))
        XCTAssertTrue(s.contains(at(1, 59)))
        XCTAssertFalse(s.contains(at(2, 0)))
        XCTAssertFalse(s.contains(at(12, 0)))
        XCTAssertTrue(s.contains(at(22, 0)))
    }

    func testZeroLengthSlotContainsNothing() {
        let s = slot(3 * 60, 3 * 60)
        XCTAssertFalse(s.contains(at(3, 0)))
        XCTAssertFalse(s.contains(at(15, 0)))
    }

    // MARK: Routing — the non-negotiable requirement

    func testAssignedSlotRemindsOnlyTheAssignee() {
        let slots = [slot(1 * 60, 4 * 60, assignee: taylor)]   // Taylor owns 01:00–04:00
        let twoAM = at(2, 0)
        XCTAssertTrue(FeedSchedule.shouldRemind(slots: slots, at: twoAM, myParticipantID: taylor))
        XCTAssertFalse(FeedSchedule.shouldRemind(slots: slots, at: twoAM, myParticipantID: wife),
                       "the unassigned parent's device must stay dark")
    }

    func testUnassignedSlotRemindsEveryone() {
        let slots = [slot(1 * 60, 4 * 60, assignee: nil)]
        XCTAssertTrue(FeedSchedule.shouldRemind(slots: slots, at: at(2), myParticipantID: taylor))
        XCTAssertTrue(FeedSchedule.shouldRemind(slots: slots, at: at(2), myParticipantID: wife))
    }

    func testTimeOutsideAnySlotRemindsEveryone() {
        let slots = [slot(1 * 60, 4 * 60, assignee: taylor)]
        let noon = at(12, 0)
        XCTAssertTrue(FeedSchedule.shouldRemind(slots: slots, at: noon, myParticipantID: taylor))
        XCTAssertTrue(FeedSchedule.shouldRemind(slots: slots, at: noon, myParticipantID: wife))
    }

    func testNoScheduleRemindsEveryone() {
        XCTAssertTrue(FeedSchedule.shouldRemind(slots: [], at: at(2), myParticipantID: taylor))
    }

    func testAdjacentSlotsSplitTheNight() {
        let slots = [
            slot(1 * 60, 4 * 60, assignee: taylor),        // Taylor: 01:00–04:00
            slot(4 * 60, 7 * 60, assignee: wife)           // Wife:   04:00–07:00
        ]
        XCTAssertTrue(FeedSchedule.shouldRemind(slots: slots, at: at(2), myParticipantID: taylor))
        XCTAssertFalse(FeedSchedule.shouldRemind(slots: slots, at: at(2), myParticipantID: wife))
        XCTAssertFalse(FeedSchedule.shouldRemind(slots: slots, at: at(5), myParticipantID: taylor))
        XCTAssertTrue(FeedSchedule.shouldRemind(slots: slots, at: at(5), myParticipantID: wife))
    }

    // MARK: Routing — fail-safe biases (never silently skip)

    func testUnknownLocalIdentityAlwaysReminds() {
        // Before onboarding/sharing sets myParticipantID, never skip a reminder.
        let slots = [slot(1 * 60, 4 * 60, assignee: taylor)]
        XCTAssertTrue(FeedSchedule.shouldRemind(slots: slots, at: at(2), myParticipantID: nil))
    }

    func testSlotAssignedToRevokedParticipantRemindsEveryone() {
        // A slot pointing at a removed caregiver must not leave BOTH parents
        // unreminded — with the active-id set provided, it degrades to "Both".
        let revoked = UUID()
        let slots = [slot(1 * 60, 4 * 60, assignee: revoked)]
        let active: Set<UUID> = [taylor, wife]
        XCTAssertTrue(FeedSchedule.shouldRemind(slots: slots, at: at(2), myParticipantID: taylor,
                                                activeParticipantIDs: active))
        XCTAssertTrue(FeedSchedule.shouldRemind(slots: slots, at: at(2), myParticipantID: wife,
                                                activeParticipantIDs: active))
    }

    func testOverlappingSlotsRemindIfAnyCoveringSlotIsMineOrShared() {
        let slots = [
            slot(1 * 60, 4 * 60, assignee: wife),
            slot(2 * 60, 5 * 60, assignee: taylor)         // overlaps 02:00–04:00
        ]
        // In the overlap both parents are covered by "their" slot → both remind.
        XCTAssertTrue(FeedSchedule.shouldRemind(slots: slots, at: at(3), myParticipantID: taylor))
        XCTAssertTrue(FeedSchedule.shouldRemind(slots: slots, at: at(3), myParticipantID: wife))
        // Outside the overlap, ownership is exclusive again.
        XCTAssertFalse(FeedSchedule.shouldRemind(slots: slots, at: at(1, 30), myParticipantID: taylor))
        XCTAssertTrue(FeedSchedule.shouldRemind(slots: slots, at: at(4, 30), myParticipantID: taylor))
    }

    // MARK: Persistence encoding (SharedSettings.feedSlots)

    @MainActor
    func testFeedSlotsRoundTripThroughSharedSettings() {
        let settings = SharedSettings()
        XCTAssertNil(settings.feedSlotsData, "never-configured stays nil")
        XCTAssertEqual(settings.feedSlots, [])

        let slots = [slot(22 * 60, 2 * 60, assignee: taylor), slot(2 * 60, 7 * 60)]
        settings.feedSlots = slots
        XCTAssertEqual(settings.feedSlots, slots)
    }

    @MainActor
    func testClearingScheduleEncodesEmptyNotNil() {
        // [] must be a real value (it syncs and overwrites the co-parent's copy);
        // nil is reserved for "this record predates feed schedules".
        let settings = SharedSettings()
        settings.feedSlots = [slot(1 * 60, 4 * 60)]
        settings.feedSlots = []
        XCTAssertNotNil(settings.feedSlotsData)
        XCTAssertEqual(settings.feedSlots, [])
    }

    @MainActor
    func testCorruptSlotDataDegradesToNoSchedule() {
        // Garbage bytes (a future format, a bad merge) must mean "no schedule"
        // — which routes reminders to everyone — never a crash or a skip.
        let settings = SharedSettings()
        settings.feedSlotsData = Data("not json".utf8)
        XCTAssertEqual(settings.feedSlots, [])
    }
}
