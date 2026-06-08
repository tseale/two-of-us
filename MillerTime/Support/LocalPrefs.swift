import Foundation

/// This device's role in CloudKit sharing.
enum SyncRole: String {
    case solo        // single account, no co-parent yet (owns its data)
    case owner       // created the baby and shared it with a co-parent
    case participant // accepted a co-parent's share
}

/// Per-user, device-local preferences. These never sync (they're device identity
/// + UI prefs). Sharing identity (`myParticipantID`, `syncRole`) lives here so
/// each device knows who "me" is and which CloudKit engine to drive.
@Observable
final class LocalPrefs {
    static let shared = LocalPrefs()
    private let defaults = UserDefaults.standard

    private enum Key {
        static let notifyFeed = "notify.feed"
        static let notifySleep = "notify.sleep"
        static let notifyDiaper = "notify.diaper"
        static let feedReminder = "notify.feedReminder"
        static let myParticipantID = "sync.myParticipantID"
        static let syncRole = "sync.role"
    }

    /// The local user's own Participant id — used to stamp logger identity and to
    /// resolve "me" once two participants exist. Stored in the App Group suite so
    /// the widget/Siri extension (`QuickLogger`) resolves the same identity.
    var myParticipantID: UUID? {
        didSet { AppGroup.userDefaults?.set(myParticipantID?.uuidString, forKey: Key.myParticipantID) }
    }

    var syncRole: SyncRole {
        didSet { defaults.set(syncRole.rawValue, forKey: Key.syncRole) }
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
        myParticipantID = (AppGroup.userDefaults?.string(forKey: Key.myParticipantID)).flatMap(UUID.init)
        syncRole = SyncRole(rawValue: defaults.string(forKey: Key.syncRole) ?? "") ?? .solo
    }
}
