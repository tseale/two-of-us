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

    /// Whether the hero's pick-up slide shows while he's at daycare.
    ///
    /// In geofence mode (`geofenceMode`: the fence is configured, enabled,
    /// and THIS phone holds Always location) the fence is the whole answer:
    /// the slide exists only while this phone stands at the daycare —
    /// whatever the clock says (the early sick-day pickup), and never on the
    /// phone that stayed at work. The configured show time is redundant there
    /// and ignored.
    ///
    /// Without the fence (location denied, no pin) the clock decides: hidden
    /// until `showMinute` — pick-up isn't on anyone's mind at noon — then
    /// shown. The slide gesture itself is the accident gate either way (a
    /// bounced phone can't sweep a thumb across a track).
    static func pickupVisible(
        now: Date,
        showMinute: Int = defaultPickupShowMinute,
        geofenceMode: Bool = false,
        nearDaycare: Bool,
        calendar: Calendar = .current
    ) -> Bool {
        if geofenceMode { return nearDaycare }
        if nearDaycare { return true }
        let minuteOfDay = calendar.component(.hour, from: now) * 60
            + calendar.component(.minute, from: now)
        return minuteOfDay >= showMinute
    }

    /// Whether the hero's drop-off slide shows before attendance begins.
    ///
    /// In geofence mode the slide appears only while this phone stands at the
    /// daycare AND the clock is plausibly a drop-off: a grace hour before the
    /// doors open (parents arrive early) through close — the same window the
    /// arrival prompt uses, so an 8 PM parents'-night visit shows nothing.
    /// A phone that never enters the fence never sees the slide: a home day
    /// needs no button to say so.
    ///
    /// Without the fence, the clock alone decides: from doors-open onward
    /// (the caller's assumed-close check already ends the day).
    static func dropoffVisible(
        now: Date,
        openMinute: Int = defaultOpenMinute,
        closeMinute: Int = defaultCloseMinute,
        geofenceMode: Bool,
        nearDaycare: Bool,
        calendar: Calendar = .current
    ) -> Bool {
        let minuteOfDay = calendar.component(.hour, from: now) * 60
            + calendar.component(.minute, from: now)
        if geofenceMode {
            return nearDaycare && minuteOfDay >= openMinute - 60
                && minuteOfDay < closeMinute
        }
        return minuteOfDay >= openMinute
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
    /// - no check-out by the assumed close → considered checked out then —
    ///   unless `atDaycare`: a phone standing inside the daycare fence is a
    ///   better signal than the clock, so a late pick-up (or a parents'
    ///   night with him still checked in) keeps the pick-up slide until the
    ///   check-out is actually logged;
    /// - everything is scoped to today, so midnight clears any leftover state;
    /// - future-dated events (backdate typos) don't count until their time.
    static func attendance(
        checks: [(timestamp: Date, type: CheckType)],
        firstDaycareEvent: Date?,
        dayStart: Date,
        now: Date = .now,
        closeMinute: Int = defaultCloseMinute,
        atDaycare: Bool = false,
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

        if !atDaycare,
           let assumedOut = assumedCheckOut(dayStart: dayStart, closeMinute: closeMinute,
                                            calendar: calendar),
           now >= assumedOut, candidate.since < assumedOut {
            return nil
        }
        return candidate
    }
}
