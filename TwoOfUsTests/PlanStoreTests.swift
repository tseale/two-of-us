import XCTest
import SwiftData
@testable import TwoOfUs

/// Store-semantics tests for the schedule plan: slot CRUD, per-night overrides
/// (append-only, replace-prior), identity denormalization + backfill, and the
/// minute-of-day normalization. Mirrors `EventStoreTests`' demo-mode setup so
/// no side effects (sync, widgets, alarms) run.
@MainActor
final class PlanStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var store: EventStore!
    private var taylor: Participant!
    private var savedDemo = false
    private var savedParticipantID: UUID?

    private var context: ModelContext { container.mainContext }

    override func setUp() {
        super.setUp()
        savedDemo = LocalPrefs.shared.demoModeEnabled
        savedParticipantID = LocalPrefs.shared.myParticipantID
        LocalPrefs.shared.demoModeEnabled = true

        container = AppModelContainer.make(inMemory: true)
        context.insert(Baby(name: "Miller", dateOfBirth: .now))
        taylor = Participant(displayName: "Taylor", colorHex: "#AABBCC")
        context.insert(taylor)
        try? context.save()
        // Pin "me" — some tests add a second participant, so the first-record
        // fallback would be nondeterministic.
        LocalPrefs.shared.myParticipantID = taylor.id
        store = EventStore(context: context)
    }

    override func tearDown() {
        LocalPrefs.shared.demoModeEnabled = savedDemo
        LocalPrefs.shared.myParticipantID = savedParticipantID
        store = nil
        container = nil
        taylor = nil
        super.tearDown()
    }

    private var tonightKey: Int { ScheduleEngine.dayKey(for: .now, calendar: .current) }

    // MARK: Slots

    func testAddPlanSlotStampsDenormalizedAssignment() {
        let slot = store.addPlanSlot(kind: .feed, minuteOfDay: 23 * 60, assignedTo: taylor)

        XCTAssertEqual(slot.minuteOfDay, 23 * 60)
        XCTAssertEqual(slot.assignedToID, taylor.id)
        XCTAssertEqual(slot.assignedToName, "Taylor")
        XCTAssertEqual(slot.assignedToColorHex, "#AABBCC")
        XCTAssertNil(slot.deletedAt)
    }

    func testMinuteOfDayWraps() {
        XCTAssertEqual(store.addPlanSlot(kind: .feed, minuteOfDay: 1500, assignedTo: nil).minuteOfDay,
                       60, "25:00 wraps to 1:00")
        let slot = store.addPlanSlot(kind: .feed, minuteOfDay: 0, assignedTo: nil)
        store.updatePlanSlot(slot, minuteOfDay: -60)
        XCTAssertEqual(slot.minuteOfDay, 23 * 60, "-1:00 wraps to 11pm")
    }

    func testUpdatePlanSlotCanUnassignWithoutTouchingTime() {
        let slot = store.addPlanSlot(kind: .feed, minuteOfDay: 23 * 60, assignedTo: taylor)
        store.updatePlanSlot(slot, assignedTo: .some(nil))

        XCTAssertNil(slot.assignedToID)
        XCTAssertEqual(slot.assignedToName, "")
        XCTAssertEqual(slot.minuteOfDay, 23 * 60, "omitted fields stay put")
    }

    // MARK: Overrides

    func testOverrideLeavesStandingSlotUntouched() {
        let katie = Participant(displayName: "Katie", colorHex: "#FF8FA3")
        context.insert(katie)
        let slot = store.addPlanSlot(kind: .feed, minuteOfDay: 23 * 60, assignedTo: taylor)

        let override = store.overrideSlot(slot, dayKey: tonightKey, assignTo: katie)

        XCTAssertEqual(slot.assignedToID, taylor.id, "the standing plan never moves on a swap")
        XCTAssertEqual(override.slotID, slot.id)
        XCTAssertEqual(override.dayKey, tonightKey)
        XCTAssertEqual(override.assignedToName, "Katie")
        XCTAssertEqual(override.createdByID, taylor.id, "the swap records who made it")
    }

    func testSecondOverrideSameNightReplacesFirst() {
        let slot = store.addPlanSlot(kind: .feed, minuteOfDay: 23 * 60, assignedTo: taylor)
        let first = store.overrideSlot(slot, dayKey: tonightKey, assignTo: nil)
        let second = store.skipSlot(slot, dayKey: tonightKey)

        XCTAssertNotNil(first.deletedAt, "at most one live override per (slot, night) from this device")
        XCTAssertNil(second.deletedAt)
        XCTAssertTrue(second.isSkipped)
    }

    func testClearOverrideSoftDeletes() {
        let slot = store.addPlanSlot(kind: .feed, minuteOfDay: 23 * 60, assignedTo: taylor)
        let override = store.overrideSlot(slot, dayKey: tonightKey, assignTo: nil)

        store.clearOverride(override)
        XCTAssertNotNil(override.deletedAt)
    }

    func testRemovePlanSlotAlsoRetiresItsFutureOverrides() {
        let slot = store.addPlanSlot(kind: .feed, minuteOfDay: 23 * 60, assignedTo: taylor)
        let tonight = store.overrideSlot(slot, dayKey: tonightKey, assignTo: nil)
        let lastWeek = PlanOverride(slotID: slot.id, dayKey: tonightKey - 7, createdByID: taylor.id)
        context.insert(lastWeek)
        try? context.save()

        store.removePlanSlot(slot)

        XCTAssertNotNil(slot.deletedAt)
        XCTAssertNotNil(tonight.deletedAt, "a swap for a removed slot must not linger")
        XCTAssertNil(lastWeek.deletedAt, "history is left alone")

        store.restorePlanSlot(slot)
        XCTAssertNil(slot.deletedAt)
        XCTAssertNotNil(tonight.deletedAt, "undo restores the slot, not the retired swap")
    }

    // MARK: Identity backfill

    func testProfileEditBackfillsAssignedIdentity() {
        let slot = store.addPlanSlot(kind: .feed, minuteOfDay: 23 * 60, assignedTo: taylor)
        let override = store.overrideSlot(slot, dayKey: tonightKey, assignTo: taylor)

        store.updateMyProfile(name: "Tay", colorHex: "#112233")

        XCTAssertEqual(slot.assignedToName, "Tay")
        XCTAssertEqual(slot.assignedToColorHex, "#112233")
        XCTAssertEqual(override.assignedToName, "Tay",
                       "denormalized assignment relabels on rename, like loggedBy* does")
    }
}
