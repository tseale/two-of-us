import Foundation

/// Per-user, device-local preferences. These never sync (Increment 2+ keeps them local).
/// Increment 1 only needs a couple; the notification prefs land in Increment 4.
@Observable
final class LocalPrefs {
    static let shared = LocalPrefs()
    private let defaults = UserDefaults.standard

    private enum Key {
        static let notifyFeed = "notify.feed"
        static let notifySleep = "notify.sleep"
        static let notifyDiaper = "notify.diaper"
        static let feedReminder = "notify.feedReminder"
    }

    var notifyFeed: Bool {
        didSet { defaults.set(notifyFeed, forKey: Key.notifyFeed) }
    }
    var notifySleep: Bool {
        didSet { defaults.set(notifySleep, forKey: Key.notifySleep) }
    }
    var notifyDiaper: Bool {
        didSet { defaults.set(notifyDiaper, forKey: Key.notifyDiaper) }
    }
    var feedReminderEnabled: Bool {
        didSet { defaults.set(feedReminderEnabled, forKey: Key.feedReminder) }
    }

    private init() {
        notifyFeed = defaults.object(forKey: Key.notifyFeed) as? Bool ?? true
        notifySleep = defaults.object(forKey: Key.notifySleep) as? Bool ?? false
        notifyDiaper = defaults.object(forKey: Key.notifyDiaper) as? Bool ?? false
        feedReminderEnabled = defaults.object(forKey: Key.feedReminder) as? Bool ?? true
    }
}
