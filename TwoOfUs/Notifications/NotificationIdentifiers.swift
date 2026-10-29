import Foundation

/// Stable string identifiers for notification categories, actions, and requests.
/// Kept in one place so the scheduler (`NotificationManager`) and the responder
/// (`AppDelegate`) can't drift apart.
enum NotificationID {

    /// Categories decide which action buttons a notification shows.
    enum Category {
        static let reminderFeed = "REMINDER_FEED"
        static let reminderDiaper = "REMINDER_DIAPER"
        /// "You're up" reminders for schedule slots assigned to this device's
        /// parent. Split by kind so a sleep slot never offers "Log feed".
        static let scheduleFeed = "SCHEDULE_FEED"
        static let scheduleSleep = "SCHEDULE_SLEEP"
        /// Informational "the other parent just logged something" notifications.
        static let coParent = "COPARENT"
        static let milestone = "MILESTONE"
        /// Informational "the daycare just logged something" notifications.
        static let daycare = "DAYCARE"
        /// Geofence arrival prompts — split by direction so the morning ask
        /// offers Dropped off and the afternoon ask offers Picked up. (No
        /// "Staying home": the prompt only fires INSIDE the fence, and a day
        /// that never reaches it is a home day by silence.)
        static let geofenceDropOff = "GEOFENCE_DROPOFF"
        static let geofencePickUp = "GEOFENCE_PICKUP"
    }

    /// Action buttons. Logging actions run in the background (no `.foreground`)
    /// and write through `QuickLogger`; the default tap opens the app.
    enum Action {
        static let logFeed = "LOG_FEED"
        static let logDiaperWet = "LOG_DIAPER_WET"
        static let logDiaperDirty = "LOG_DIAPER_DIRTY"
        static let snooze = "SNOOZE"
        static let logCheckIn = "LOG_CHECKIN"
        static let logCheckOut = "LOG_CHECKOUT"
        /// Drop-off prompt extras: a typed note for the daycare (text-input
        /// action, background) and an explicit "Open in app" — needed because
        /// the interactive whiteboard card swallows the default tap.
        static let addNote = "ADD_NOTE"
        static let openApp = "OPEN_APP"
    }

    /// Request identifiers. Scheduled reminders use a stable id so a reschedule
    /// replaces the pending one; co-parent notifications are keyed per event.
    enum Request {
        static let feedReminder = "reminder.feed"
        static let diaperReminder = "reminder.diaper"
        static let dailyMilestone = "milestone.daily"
        static func coParent(_ key: String) -> String { "coparent.\(key)" }
        static func daycare(_ key: String) -> String { "daycare.\(key)" }
        /// Geofence prompts replace by direction: a second drop-off ask (edge
        /// jitter) supersedes the first instead of stacking.
        static func geofence(_ direction: String) -> String { "geofence.\(direction)" }
        /// Namespace for every schedule reminder (per-occurrence + snooze), so a
        /// re-arm can sweep them all without knowing which nights were pending.
        static let schedulePrefix = "schedule."
        static func scheduleSlot(slotID: UUID, dayKey: Int) -> String {
            "\(schedulePrefix)slot.\(slotID.uuidString).\(dayKey)"
        }
        static let scheduleSnooze = "schedule.snooze"
    }

    /// `threadIdentifier`s group related notifications in the stack / summary.
    enum Thread {
        static let feed = "thread.feed"
        static let diaper = "thread.diaper"
        static let sleep = "thread.sleep"
        static let milestone = "thread.milestone"
        static let schedule = "thread.schedule"
        /// Daycare events group per DAY, so a busy morning stacks into one
        /// lock-screen bundle instead of a flood.
        static func daycare(day: String) -> String { "thread.daycare.\(day)" }
    }
}
