import Foundation

/// What a geofence entry should ask, if anything. Pure, `DaycareStatus`-style:
/// the manager passes fetched state, tests pass fixtures. State decides over
/// clock: while he's there any arrival means pick-up, before that any arrival
/// in the operating window means drop-off — so a late drop-off or an early
/// pick-up still gets the right prompt.
enum DaycareGeofencePlanner {

    enum Prompt: String {
        case dropOff
        case pickUp
    }

    /// - Parameters:
    ///   - attending: `DaycareStatus.attendance(...)` is non-nil right now.
    ///   - checkedOutToday: an explicit check-out marker exists today — the
    ///     day is over; a return trip (forgotten bag) must not re-prompt.
    ///   - homeToday: a "home today" marker exists today.
    ///   - isOperatingDay: `settings.isDaycareDay(now)`.
    static func prompt(
        now: Date,
        dayStart: Date,
        openMinute: Int,
        closeMinute: Int,
        isOperatingDay: Bool,
        attending: Bool,
        checkedOutToday: Bool,
        homeToday: Bool,
        calendar: Calendar = .current
    ) -> Prompt? {
        guard isOperatingDay, !homeToday else { return nil }
        if attending { return .pickUp }
        guard !checkedOutToday else { return nil }
        // Drop-off window: a grace hour before the doors open (parents arrive
        // early) through close. Outside it — a weekend errand past the
        // building, a 9 PM drive-by — stays silent.
        let minuteOfDay = calendar.component(.hour, from: now) * 60
            + calendar.component(.minute, from: now)
        guard minuteOfDay >= openMinute - 60, minuteOfDay < closeMinute else { return nil }
        return .dropOff
    }
}
