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

    /// Defaults until the Daycare settings page configures the real hours —
    /// minutes from midnight, the night-window convention. Close is pickup
    /// time with margin: with no check-out recorded, the daycare day is
    /// assumed over then. Fallback only: an explicit check-out ends the day
    /// whenever it lands, and an explicit check-in placed after close (a
    /// real, if odd, marker) is honored until midnight. Open hides the manual
    /// Drop off button through the night shift.
    static let defaultOpenMinute = 7 * 60            // 7:00 AM
    static let defaultCloseMinute = 17 * 60 + 30     // 5:30 PM
    static let defaultPickupShowMinute = 15 * 60     // pick-up control from 3:00 PM

    /// Whether the hero's pick-up slide shows while he's at daycare. The
    /// morning and midday answer is false — pick-up isn't on anyone's mind
    /// yet. From `showMinute` it surfaces, and standing inside the daycare
    /// geofence (`nearDaycare`) surfaces it at any hour — the early sick-day
    /// pickup. The slide gesture itself is the accident gate (a bounced
    /// phone can't sweep a thumb across a track), so there's no collapsed
    /// half-step anymore.
    static func pickupVisible(
        now: Date,
        showMinute: Int = defaultPickupShowMinute,
        nearDaycare: Bool,
        calendar: Calendar = .current
    ) -> Bool {
        if nearDaycare { return true }
        let minuteOfDay = calendar.component(.hour, from: now) * 60
            + calendar.component(.minute, from: now)
        return minuteOfDay >= showMinute
    }

    /// When the day is assumed over with no check-out marker: the configured
    /// close on `dayStart`'s calendar day. `bySettingHour` (not minute
    /// arithmetic) so a DST transition day still closes at the wall-clock time.
    static func assumedCheckOut(dayStart: Date, closeMinute: Int = defaultCloseMinute,
                                calendar: Calendar = .current) -> Date? {
        calendar.date(bySettingHour: closeMinute / 60, minute: closeMinute % 60,
                      second: 0, of: dayStart)
    }

    /// Nil = not at daycare. The check events are the primary source: today's
    /// latest marker decides (check-out always wins). When today has no
    /// markers at all, the first daycare-sourced event of any kind stands in
    /// for the missing check-in — if daycare is logging bottles, he's there.
    /// Fallbacks keep a missed tap from wedging Home:
    /// - no check-out by the assumed close → considered checked out then;
    /// - everything is scoped to today, so midnight clears any leftover state;
    /// - future-dated events (backdate typos) don't count until their time.
    static func attendance(
        checks: [(timestamp: Date, type: CheckType)],
        firstDaycareEvent: Date?,
        dayStart: Date,
        now: Date = .now,
        closeMinute: Int = defaultCloseMinute,
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

        if let assumedOut = assumedCheckOut(dayStart: dayStart, closeMinute: closeMinute,
                                            calendar: calendar),
           now >= assumedOut, candidate.since < assumedOut {
            return nil
        }
        return candidate
    }
}
