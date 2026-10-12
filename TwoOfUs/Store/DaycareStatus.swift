import Foundation

/// Whether the baby is at daycare right now, from the check-in/check-out
/// markers (Brightwheel-imported or hand-logged). Pure, `StatsEngine`-style:
/// callers pass fetched values, tests pass fixtures.
enum DaycareStatus {
    /// Checked in = today's latest check event (up to `now`) is a check-in
    /// with no later check-out. Scoped to today on purpose: daycares
    /// occasionally miss a check-out tap, and a stale check-in from yesterday
    /// must not strand Home in daycare mode overnight — midnight clears it.
    /// Future-dated events (a backdate typo) don't count until their time.
    static func isCheckedIn(checks: [(timestamp: Date, type: CheckType)],
                            dayStart: Date, now: Date = .now) -> Bool {
        checks
            .filter { $0.timestamp >= dayStart && $0.timestamp <= now }
            .max { $0.timestamp < $1.timestamp }?
            .type == .checkIn
    }
}
