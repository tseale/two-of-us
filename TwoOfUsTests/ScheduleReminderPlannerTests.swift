import XCTest
@testable import TwoOfUs

/// Tests the pure decision layer behind slot reminders. The one invariant that
/// IS the feature: a device plans reminders only for occurrences assigned to
/// its own parent — the off-duty phone stays silent by construction.
final class ScheduleReminderPlannerTests: XCTestCase {
    private let me = UUID()
    private let coParent = UUID()
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func occurrence(
        in interval: TimeInterval, assignedTo: UUID?, kind: EventKind = .feed,
        source: ScheduleOccurrence.Source? = nil,
        status: ScheduleOccurrence.Status = .upcoming,
        slotID: UUID = UUID(), dayKey: Int = 20_260_721
    ) -> ScheduleOccurrence {
        ScheduleOccurrence(
            id: "test", kind: kind, date: now.addingTimeInterval(interval), dayKey: dayKey,
            source: source ?? .pinned(slotID: slotID), status: status,
            assignedToID: assignedTo, assignedToName: "", assignedToColorHex: "",
            activeOverrideID: nil, overrideCreatedByID: nil
        )
    }

    private func plan(_ occurrences: [ScheduleOccurrence], myID: UUID?) -> [PlannedReminder] {
        ScheduleReminderPlanner.plan(occurrences: occurrences, myID: myID, babyName: "Miller", now: now)
    }

    func testPlansOnlyMyAssignedOccurrences() {
        let planned = plan([
            occurrence(in: 2 * 3600, assignedTo: me),
            occurrence(in: 4 * 3600, assignedTo: coParent),
            occurrence(in: 6 * 3600, assignedTo: nil)
        ], myID: me)

        XCTAssertEqual(planned.count, 1, "the co-parent's and unassigned slots stay silent here")
    }

    func testNoIdentityPlansNothing() {
        XCTAssertTrue(plan([occurrence(in: 2 * 3600, assignedTo: me)], myID: nil).isEmpty)
    }

    func testSkipsNonUpcomingAndPredicted() {
        let planned = plan([
            occurrence(in: 2 * 3600, assignedTo: me, status: .fulfilled(byEventID: UUID())),
            occurrence(in: 3 * 3600, assignedTo: me, status: .skipped),
            occurrence(in: -1 * 3600, assignedTo: me, status: .overdue),
            occurrence(in: 4 * 3600, assignedTo: me, source: .predicted)
        ], myID: me)

        XCTAssertTrue(planned.isEmpty)
    }

    func testLeadTimeAndStableRequestID() {
        let slotID = UUID()
        let planned = plan(
            [occurrence(in: 2 * 3600, assignedTo: me, slotID: slotID, dayKey: 20_260_722)],
            myID: me
        )

        let reminder = planned[0]
        XCTAssertEqual(reminder.fireDate, now.addingTimeInterval(2 * 3600 - ScheduleReminderPlanner.lead))
        XCTAssertEqual(reminder.requestID, "schedule.slot.\(slotID.uuidString).20260722",
                       "stable per (slot, night) so re-arms replace instead of stacking")
        XCTAssertTrue(reminder.title.contains("Miller"))
    }

    func testOccurrenceInsideLeadWindowSchedulesNothing() {
        // 10 minutes out: the fire date is already past — firing instantly would
        // re-fire on every subsequent re-arm, so it plans nothing instead.
        XCTAssertTrue(plan([occurrence(in: 10 * 60, assignedTo: me)], myID: me).isEmpty)
    }

    func testCapsPendingRequests() {
        let many = (1...10).map { occurrence(in: TimeInterval($0) * 3600, assignedTo: me) }
        let planned = plan(many, myID: me)

        XCTAssertEqual(planned.count, ScheduleReminderPlanner.maxPending)
        XCTAssertEqual(planned.first?.fireDate,
                       now.addingTimeInterval(1 * 3600 - ScheduleReminderPlanner.lead))
        XCTAssertEqual(planned.last?.fireDate,
                       now.addingTimeInterval(6 * 3600 - ScheduleReminderPlanner.lead),
                       "the SOONEST slots make the cut, ascending — not just any sorted six")
    }

    /// Locks the product position: slot reminders bypass quiet hours entirely —
    /// a 3am assigned-feed reminder IS the feature; off-duty silence comes from
    /// the assignment filter, never from muting. The planner therefore must not
    /// consult quiet-hours prefs at all.
    func testQuietHoursDoNotSuppressSlotReminders() {
        let savedEnabled = LocalPrefs.shared.quietHoursEnabled
        defer { LocalPrefs.shared.quietHoursEnabled = savedEnabled }
        LocalPrefs.shared.quietHoursEnabled = true   // 22:00–07:00 default window

        let planned = plan([occurrence(in: 2 * 3600, assignedTo: me)], myID: me)
        XCTAssertEqual(planned.count, 1,
                       "an assigned slot plans its reminder no matter the quiet-hours window")
    }
}
