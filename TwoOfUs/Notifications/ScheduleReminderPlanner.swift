import Foundation

/// One local notification the schedule wants pending on THIS device.
struct PlannedReminder: Equatable {
    let requestID: String        // stable per (slot, night) → re-arms self-replace
    let fireDate: Date           // occurrence time minus the lead
    let kind: EventKind
    let occurrenceDate: Date
    let title: String
    let body: String
}

/// Pure decision layer for slot reminders: which upcoming occurrences deserve a
/// notification *on this device*. The whole feature's promise lives in the
/// filter — still-upcoming slots assigned to *me*, plus unassigned ones (an
/// unclaimed slot rings BOTH phones — that's the deal: silence is earned by an
/// assignment, never by default). A slot pinned to the co-parent stays silent
/// here, so the off-duty phone sleeps by construction. Deliberately knows
/// nothing about UNUserNotificationCenter (tests cover it directly), and
/// deliberately never consults quiet hours: a 3am assigned-feed reminder IS the
/// feature — off-duty silence comes from assignment, not from muting.
enum ScheduleReminderPlanner {
    /// How far ahead of the slot the reminder fires.
    static let lead: TimeInterval = 15 * 60
    /// Pending-request budget: the next handful is plenty, and every write/sync/
    /// foreground re-plans anyway.
    static let maxPending = 6

    static func plan(
        occurrences: [ScheduleOccurrence], myID: UUID?, babyName: String, now: Date
    ) -> [PlannedReminder] {
        guard let myID else { return [] }
        let mine = occurrences
            .filter {
                $0.status == .upcoming
                    && ($0.assignedToID == myID || $0.assignedToID == nil)
            }
            .compactMap { occ -> PlannedReminder? in
                let fireDate = occ.date.addingTimeInterval(-lead)
                // A change made inside the lead window schedules nothing rather
                // than firing instantly — an immediate "you're up in 0 minutes"
                // would re-fire on every subsequent re-arm.
                guard fireDate > now else { return nil }
                let unassigned = occ.assignedToID == nil
                return PlannedReminder(
                    requestID: NotificationID.Request.scheduleSlot(slotID: occ.slotID, dayKey: occ.dayKey),
                    fireDate: fireDate,
                    kind: occ.kind,
                    occurrenceDate: occ.date,
                    title: title(kind: occ.kind, date: occ.date, babyName: babyName, unassigned: unassigned),
                    body: body(kind: occ.kind, unassigned: unassigned)
                )
            }
        return Array(mine.sorted { $0.fireDate < $1.fireDate }.prefix(maxPending))
    }

    static func title(kind: EventKind, date: Date, babyName: String, unassigned: Bool = false) -> String {
        unassigned
            ? "\(babyName) — \(TimeFormatting.clock(date)) \(kind == .sleep ? "sleep" : "bottle"), unclaimed"
            : "\(babyName) — your \(TimeFormatting.clock(date)) \(kind == .sleep ? "sleep" : "bottle")"
    }

    static func body(kind: EventKind, unassigned: Bool = false) -> String {
        if unassigned { return "Nobody's assigned in 15 minutes — first one up takes it." }
        return kind == .sleep
            ? "You're up in 15 minutes — settling duty."
            : "You're up in 15 minutes."
    }
}
