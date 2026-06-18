import SwiftUI

/// This device's role in CloudKit sharing.
enum SyncRole: String {
    case solo        // single account, no co-parent yet (owns its data)
    case owner       // created the baby and shared it with a co-parent
    case participant // accepted a co-parent's share
}

/// Light/dark appearance preference. `.system` follows iOS settings.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// nil means "don't override" — let the system decide.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
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
        static let gentleReminders = "notify.gentleReminders"
        static let notifyMilestones = "notify.milestones"
        static let quietHoursEnabled = "notify.quietHours.enabled"
        static let quietHoursStart = "notify.quietHours.start"
        static let quietHoursEnd = "notify.quietHours.end"
        static let appearance = "ui.appearance"
        static let myParticipantID = "sync.myParticipantID"
        static let syncRole = "sync.role"
        static let demoMode = "demo.enabled"
    }

    /// When on, the app runs against a throwaway in-memory store seeded with
    /// sample data (see `DemoData`). Device-local and never synced — the real
    /// store and the co-parent's data are untouched while demo mode is active.
    var demoModeEnabled: Bool {
        didSet { defaults.set(demoModeEnabled, forKey: Key.demoMode) }
    }

    var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
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

    /// Soft, snoozable "feed/diaper due" nudges (distinct from the loud AlarmKit
    /// feed alarm). When on, the gentle feed reminder defers to AlarmKit if that's
    /// also on, so you never get two feed reminders.
    var gentleRemindersEnabled: Bool {
        didSet { defaults.set(gentleRemindersEnabled, forKey: Key.gentleReminders) }
    }

    /// A calm end-of-day summary notification.
    var notifyMilestones: Bool {
        didSet { defaults.set(notifyMilestones, forKey: Key.notifyMilestones) }
    }

    /// When on, informational (co-parent / milestone) notifications are suppressed
    /// inside the quiet-hours window. The AlarmKit feed alarm still breaks through.
    var quietHoursEnabled: Bool {
        didSet { defaults.set(quietHoursEnabled, forKey: Key.quietHoursEnabled) }
    }
    /// Quiet-hours window as minutes-from-midnight (local). Defaults 22:00–07:00.
    var quietHoursStartMinutes: Int {
        didSet { defaults.set(quietHoursStartMinutes, forKey: Key.quietHoursStart) }
    }
    var quietHoursEndMinutes: Int {
        didSet { defaults.set(quietHoursEndMinutes, forKey: Key.quietHoursEnd) }
    }

    private init() {
        notifyFeed = defaults.object(forKey: Key.notifyFeed) as? Bool ?? true
        notifySleep = defaults.object(forKey: Key.notifySleep) as? Bool ?? false
        notifyDiaper = defaults.object(forKey: Key.notifyDiaper) as? Bool ?? false
        feedReminderEnabled = defaults.object(forKey: Key.feedReminder) as? Bool ?? true
        gentleRemindersEnabled = defaults.object(forKey: Key.gentleReminders) as? Bool ?? false
        notifyMilestones = defaults.object(forKey: Key.notifyMilestones) as? Bool ?? false
        quietHoursEnabled = defaults.object(forKey: Key.quietHoursEnabled) as? Bool ?? false
        quietHoursStartMinutes = defaults.object(forKey: Key.quietHoursStart) as? Int ?? (22 * 60)
        quietHoursEndMinutes = defaults.object(forKey: Key.quietHoursEnd) as? Int ?? (7 * 60)
        appearance = Appearance(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
        myParticipantID = (AppGroup.userDefaults?.string(forKey: Key.myParticipantID)).flatMap(UUID.init)
        syncRole = SyncRole(rawValue: defaults.string(forKey: Key.syncRole) ?? "") ?? .solo
        demoModeEnabled = defaults.object(forKey: Key.demoMode) as? Bool ?? false
    }
}
