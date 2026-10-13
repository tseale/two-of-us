import Foundation

/// Whether the baby is at daycare right now, from the check-in/check-out
/// markers (Brightwheel-imported or hand-logged) with fallbacks for the days
/// the markers don't arrive. Pure, `StatsEngine`-style: callers pass fetched
/// values, tests pass fixtures.
enum DaycareStatus {

    struct Attendance: Equatable {
        enum Basis: Equatable {
            case checkInEvent        // an actual check-in marker
            case firstDaycareEvent   // inferred: daycare started logging without one
        }
        /// When the daycare day effectively began.
        let since: Date
        let basis: Basis
    }

    /// With no check-out recorded, the daycare day is assumed over at 5:30 PM
    /// — pickup time with margin. Fallback only: an explicit check-out ends
    /// the day whenever it lands, and an explicit check-in placed after 5:30
    /// (a real, if odd, marker) is honored until midnight.
    static let assumedCheckOutHour = 17
    static let assumedCheckOutMinute = 30

    /// Daycare opens at 7 AM — the manual Drop off button stays hidden
    /// before then. (Someday a Daycare settings page can own these hours.)
    static let opensHour = 7

    /// Nil = not at daycare. The check events are the primary source: today's
    /// latest marker decides (check-out always wins). When today has no
    /// markers at all, the first daycare-sourced event of any kind stands in
    /// for the missing check-in — if daycare is logging bottles, he's there.
    /// Fallbacks keep a missed tap from wedging Home:
    /// - no check-out by `assumedCheckOut` → considered checked out then;
    /// - everything is scoped to today, so midnight clears any leftover state;
    /// - future-dated events (backdate typos) don't count until their time.
    static func attendance(
        checks: [(timestamp: Date, type: CheckType)],
        firstDaycareEvent: Date?,
        dayStart: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Attendance? {
        func isLive(_ t: Date) -> Bool { t >= dayStart && t <= now }

        let candidate: Attendance?
        // "Home today" markers are not attendance markers — they only hide
        // the Drop off button. Filtered here so one can never read as a
        // check-in, and so a Brightwheel event arriving anyway still flips
        // attendance on through the fallback below (staff logging bottles
        // overrides a stale "home today").
        if let latest = checks.filter({ isLive($0.timestamp) && $0.type != .notAttending })
            .max(by: { $0.timestamp < $1.timestamp }) {
            guard latest.type == .checkIn else { return nil }
            candidate = Attendance(since: latest.timestamp, basis: .checkInEvent)
        } else {
            candidate = firstDaycareEvent.flatMap {
                isLive($0) ? Attendance(since: $0, basis: .firstDaycareEvent) : nil
            }
        }
        guard let candidate else { return nil }

        if let assumedOut = calendar.date(bySettingHour: assumedCheckOutHour,
                                          minute: assumedCheckOutMinute,
                                          second: 0, of: dayStart),
           now >= assumedOut, candidate.since < assumedOut {
            return nil
        }
        return candidate
    }
}
