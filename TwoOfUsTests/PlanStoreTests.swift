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

    // MARK: Per-night moves

    func testMoveSlotCreatesOverrideCarryingAssignee() {
        let slot = store.addPlanSlot(kind: .feed, minuteOfDay: 23 * 60, assignedTo: taylor)
        let override = store.moveSlot(slot, dayKey: tonightKey, toMinuteOfDay: 23 * 60 + 30,
                                      assignedTo: taylor)

        XCTAssertEqual(override.minuteOfDayOverride, 23 * 60 + 30)
        XCTAssertEqual(override.assignedToID, taylor.id, "a move never drops the assignment")
        XCTAssertFalse(override.isSkipped)
    }

    func testSwapAfterMoveKeepsTheMovedTime() {
        // Move tonight to 11:30, then hand it to Katie: the replacing override
        // must carry the move along — "assign to Katie" silently snapping the
        // night back to 11:00 would betray "edit anything at any time".
        let katie = Participant(displayName: "Katie", colorHex: "#112233")
        context.insert(katie)
        let slot = store.addPlanSlot(kind: .feed, minuteOfDay: 23 * 60, assignedTo: taylor)

        let moved = store.moveSlot(slot, dayKey: tonightKey, toMinuteOfDay: 23 * 60 + 30,
                                   assignedTo: taylor)
        let swapped = store.overrideSlot(slot, dayKey: tonightKey, assignTo: katie)

        XCTAssertNotNil(moved.deletedAt, "one live override per night")
        XCTAssertEqual(swapped.assignedToID, katie.id)
        XCTAssertEqual(swapped.minuteOfDayOverride, 23 * 60 + 30, "the move survives the swap")
    }

    func testSkipAfterMoveDropsTheMove() {
        let slot = store.addPlanSlot(kind: .feed, minuteOfDay: 23 * 60, assignedTo: taylor)
        store.moveSlot(slot, dayKey: tonightKey, toMinuteOfDay: 23 * 60 + 30, assignedTo: taylor)
        let skipped = store.skipSlot(slot, dayKey: tonightKey)

        XCTAssertTrue(skipped.isSkipped)
        XCTAssertNil(skipped.minuteOfDayOverride, "a skipped night has no time to move")
    }

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

    // MARK: Nighttime schedule regeneration

    private func insertSettings() -> SharedSettings {
        let settings = SharedSettings()
        context.insert(settings)
        try? context.save()
        return settings
    }

    @discardableResult
    private func insertKatie() -> Participant {
        let katie = Participant(displayName: "Katie", colorHex: "#112233")
        // A later join date keeps the rotation order (taylor first) stable.
        katie.invitedAt = taylor.invitedAt.addingTimeInterval(60)
        context.insert(katie)
        try? context.save()
        return katie
    }

    private func liveFeedSlots() -> [PlanSlot] {
        let all = (try? context.fetch(FetchDescriptor<PlanSlot>())) ?? []
        return all.filter { $0.deletedAt == nil && $0.kind == .feed }
            .sorted { ($0.minuteOfDay + 720) % 1440 < ($1.minuteOfDay + 720) % 1440 }
    }

    func testApplyNightScheduleGeneratesAlternatingSlots() {
        let settings = insertSettings()
        insertKatie()

        // Night 8pm–8am, first feed 9pm, every 4h → 9pm, 1am, 5am.
        store.applyNightSchedule(nightStartMinute: 20 * 60, nightEndMinute: 8 * 60,
                                 firstFeedMinute: 21 * 60, spacingMinutes: 240)

        let slots = liveFeedSlots()
        XCTAssertEqual(slots.map(\.minuteOfDay), [21 * 60, 1 * 60, 5 * 60])
        XCTAssertEqual(slots.map(\.assignedToName), ["Taylor", "Katie", "Taylor"],
                       "the default rotation alternates in night order")
        XCTAssertEqual(settings.nightFeedSpacingMinutes, 240)
        XCTAssertEqual(settings.nightFirstFeedMinute, 21 * 60)
    }

    func testApplyNightScheduleSoloParentLeavesSlotsUnassigned() {
        insertSettings()
        store.applyNightSchedule(nightStartMinute: 20 * 60, nightEndMinute: 8 * 60,
                                 firstFeedMinute: 21 * 60, spacingMinutes: 240)

        XCTAssertTrue(liveFeedSlots().allSatisfy { $0.assignedToID == nil },
                      "no co-parent yet → nothing to rotate; unassigned rings every phone")
    }

    func testReapplyKeepsSurvivingSlotAndItsManualAssignment() throws {
        insertSettings()
        let katie = insertKatie()
        store.applyNightSchedule(nightStartMinute: 20 * 60, nightEndMinute: 8 * 60,
                                 firstFeedMinute: 21 * 60, spacingMinutes: 240)
        // Hand the generated 1am (Katie's by rotation) to Taylor by hand…
        let oneAM = try XCTUnwrap(liveFeedSlots().first { $0.minuteOfDay == 60 })
        store.updatePlanSlot(oneAM, assignedTo: .some(taylor))
        _ = katie

        // …then tighten the window so 9pm/1am survive and 5am drops.
        store.applyNightSchedule(nightStartMinute: 20 * 60, nightEndMinute: 4 * 60,
                                 firstFeedMinute: 21 * 60, spacingMinutes: 240)

        let slots = liveFeedSlots()
        XCTAssertEqual(slots.map(\.minuteOfDay), [21 * 60, 1 * 60])
        let kept = slots.first { $0.minuteOfDay == 60 }
        XCTAssertEqual(kept?.id, oneAM.id, "a surviving time keeps its slot id (overrides point at it)")
        XCTAssertEqual(kept?.assignedToID, taylor.id, "…and the hand-picked assignee")
    }

    func testReapplyRetiresStaleSlotWithItsFutureOverrides() throws {
        insertSettings()
        store.applyNightSchedule(nightStartMinute: 20 * 60, nightEndMinute: 8 * 60,
                                 firstFeedMinute: 21 * 60, spacingMinutes: 240)
        let fiveAM = try XCTUnwrap(liveFeedSlots().first { $0.minuteOfDay == 5 * 60 })
        let override = store.overrideSlot(fiveAM, dayKey: tonightKey, assignTo: taylor)

        store.applyNightSchedule(nightStartMinute: 20 * 60, nightEndMinute: 4 * 60,
                                 firstFeedMinute: 21 * 60, spacingMinutes: 240)

        XCTAssertNotNil(fiveAM.deletedAt, "a time outside the new plan retires")
        XCTAssertNotNil(override.deletedAt, "…and its future override must not linger")
    }

    func testApplyNightScheduleLeavesSleepSlotsAlone() {
        insertSettings()
        let sleep = store.addPlanSlot(kind: .sleep, minuteOfDay: 19 * 60, assignedTo: taylor)

        store.applyNightSchedule(nightStartMinute: 20 * 60, nightEndMinute: 8 * 60,
                                 firstFeedMinute: 21 * 60, spacingMinutes: 240)

        XCTAssertNil(sleep.deletedAt, "sleep slots are hand-authored, never regenerated")
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
