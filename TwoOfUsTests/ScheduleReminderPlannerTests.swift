import XCTest
@testable import TwoOfUs

/// Tests the pure decision layer behind slot reminders. The one invariant that
/// IS the feature: a device plans reminders for its own parent's occurrences
/// plus unassigned ones (nobody claimed it → both phones ring) — a slot pinned
/// to the co-parent keeps the off-duty phone silent by construction.
final class ScheduleReminderPlannerTests: XCTestCase {
    private let me = UUID()
    private let coParent = UUID()
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func occurrence(
        in interval: TimeInterval, assignedTo: UUID?, kind: EventKind = .feed,
        status: ScheduleOccurrence.Status = .upcoming,
        slotID: UUID = UUID(), dayKey: Int = 20_260_721
    ) -> ScheduleOccurrence {
        ScheduleOccurrence(
            id: "test", slotID: slotID, kind: kind,
            date: now.addingTimeInterval(interval), dayKey: dayKey, status: status,
            assignedToID: assignedTo, assignedToName: "", assignedToColorHex: "",
            activeOverrideID: nil, overrideCreatedByID: nil
        )
    }

    private func plan(_ occurrences: [ScheduleOccurrence], myID: UUID?) -> [PlannedReminder] {
        ScheduleReminderPlanner.plan(occurrences: occurrences, myID: myID, babyName: "Miller", now: now)
    }

    func testPlansMineAndUnassignedButNeverCoParents() {
        let planned = plan([
            occurrence(in: 2 * 3600, assignedTo: me),
            occurrence(in: 4 * 3600, assignedTo: coParent),
            occurrence(in: 6 * 3600, assignedTo: nil)
        ], myID: me)

        XCTAssertEqual(planned.count, 2,
                       "mine rings me, unassigned rings everyone, the co-parent's stays silent here")
        XCTAssertEqual(planned.map(\.occurrenceDate), [
            now.addingTimeInterval(2 * 3600), now.addingTimeInterval(6 * 3600)
        ])
    }

    func testUnassignedReminderSaysSo() {
        let planned = plan([occurrence(in: 2 * 3600, assignedTo: nil)], myID: me)

        XCTAssertEqual(planned.count, 1)
        XCTAssertTrue(planned[0].title.contains("unclaimed"),
                      "an unassigned wake-up must not read as \"your\" slot")
        XCTAssertFalse(planned[0].title.contains("your"))
    }

    func testNoIdentityPlansNothing() {
        XCTAssertTrue(plan([occurrence(in: 2 * 3600, assignedTo: me)], myID: nil).isEmpty)
    }

    func testSkipsNonUpcoming() {
        let planned = plan([
            occurrence(in: 2 * 3600, assignedTo: me, status: .fulfilled(byEventID: UUID())),
            occurrence(in: 3 * 3600, assignedTo: me, status: .skipped),
            occurrence(in: -1 * 3600, assignedTo: me, status: .overdue)
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
