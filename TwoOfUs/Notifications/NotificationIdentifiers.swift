import Foundation

/// Stable string identifiers for notification categories, actions, and requests.
/// Kept in one place so the scheduler (`NotificationManager`) and the responder
/// (`AppDelegate`) can't drift apart.
enum NotificationID {

    /// Categories decide which action buttons a notification shows.
    enum Category {
        static let reminderFeed = "REMINDER_FEED"
        static let reminderDiaper = "REMINDER_DIAPER"
        /// Informational "the other parent just logged something" notifications.
        static let coParent = "COPARENT"
        static let milestone = "MILESTONE"
    }

    /// Action buttons. Logging actions run in the background (no `.foreground`)
    /// and write through `QuickLogger`; the default tap opens the app.
    enum Action {
        static let logFeed = "LOG_FEED"
        static let logDiaperWet = "LOG_DIAPER_WET"
        static let logDiaperDirty = "LOG_DIAPER_DIRTY"
        static let snooze = "SNOOZE"
    }

    /// Request identifiers. Scheduled reminders use a stable id so a reschedule
    /// replaces the pending one; co-parent notifications are keyed per event.
    enum Request {
        static let feedReminder = "reminder.feed"
        static let diaperReminder = "reminder.diaper"
        static let dailyMilestone = "milestone.daily"
        static func coParent(_ key: String) -> String { "coparent.\(key)" }
    }

    /// `threadIdentifier`s group related notifications in the stack / summary.
    enum Thread {
        static let feed = "thread.feed"
        static let diaper = "thread.diaper"
        static let sleep = "thread.sleep"
        static let milestone = "thread.milestone"
    }
}
