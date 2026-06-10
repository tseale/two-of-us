import SwiftUI
import SwiftData

/// A deferred setup task. Onboarding stays tiny (baby → you → invite); these
/// surface afterwards as the "Getting set up" card on Home and as one-tap rows
/// in Settings, each a self-contained 30-second sheet.
enum SetupQuest: String, CaseIterable, Identifiable {
    /// Feed interval + bottle presets (shared via `SharedSettings`).
    case rhythm
    /// The AlarmKit feed-reminder opt-in (per-device).
    case reminders

    var id: String { rawValue }
}

/// A one-time feature moment shown in the main app instead of a front-loaded
/// story page — each lands right when its feature becomes relevant.
enum SetupSpotlight: String, CaseIterable, Identifiable {
    /// "It learns your rhythm" — after the first logged feed.
    case rhythm
    /// Widgets / Dynamic Island / Siri / Control Center — after ~3 logged events.
    case everywhere

    var id: String { rawValue }
}

/// Per-device progress through the deferred setup: which quests are done, which
/// spotlights have played, whether the Home checklist was dismissed. Device-local
/// on purpose — spotlights are education for *this* parent, the reminders quest
/// drives a device-local alarm, and the one genuinely shared quest (rhythm) is
/// derived from the synced `SharedSettings` instead of a synced flag, so a
/// co-parent tuning it retires the quest here on the next sync.
@Observable
final class SetupProgress {
    static let shared = SetupProgress()
    private let defaults = UserDefaults.standard

    /// Version of the first-run flow that completed on this device. 0 means
    /// "before the quest system existed" — see `grandfatherIfNeeded`.
    static let currentFlowVersion = 2

    private enum Key {
        static let flowVersion = "setup.flowVersion"
        static let completedQuests = "setup.completedQuests"
        static let dismissedChecklist = "setup.dismissedChecklist"
        static let shownSpotlights = "setup.shownSpotlights"
        static let reminderOfferShown = "setup.reminderOfferShown"
    }

    var flowVersion: Int {
        didSet { defaults.set(flowVersion, forKey: Key.flowVersion) }
    }
    var completedQuests: Set<String> {
        didSet { defaults.set(Array(completedQuests), forKey: Key.completedQuests) }
    }
    var dismissedChecklist: Bool {
        didSet { defaults.set(dismissedChecklist, forKey: Key.dismissedChecklist) }
    }
    var shownSpotlights: Set<String> {
        didSet { defaults.set(Array(shownSpotlights), forKey: Key.shownSpotlights) }
    }
    /// The just-in-time reminders offer (after a feed log) fires at most once —
    /// the checklist/Settings rows remain the persistent path.
    var reminderOfferShown: Bool {
        didSet { defaults.set(reminderOfferShown, forKey: Key.reminderOfferShown) }
    }

    /// At most one spotlight/offer interrupts per foreground session, so prompts
    /// never stack up on a busy logging night. Not persisted.
    var promptShownThisSession = false

    private init() {
        flowVersion = defaults.integer(forKey: Key.flowVersion)
        completedQuests = Set(defaults.stringArray(forKey: Key.completedQuests) ?? [])
        dismissedChecklist = defaults.bool(forKey: Key.dismissedChecklist)
        shownSpotlights = Set(defaults.stringArray(forKey: Key.shownSpotlights) ?? [])
        reminderOfferShown = defaults.bool(forKey: Key.reminderOfferShown)
    }

    // MARK: Quests

    /// The quests this device should offer. Joiners only get reminders — a
    /// `.logger` can't write the shared rhythm settings.
    func activeQuests(role: SyncRole) -> [SetupQuest] {
        role == .participant ? [.reminders] : [.rhythm, .reminders]
    }

    /// Completion is flag *or* derived state, so finishing a quest through any
    /// path (Settings toggle, co-parent's edit syncing in) retires it too.
    func isComplete(_ quest: SetupQuest, settings: SharedSettings?) -> Bool {
        if completedQuests.contains(quest.rawValue) { return true }
        switch quest {
        case .reminders:
            return LocalPrefs.shared.feedReminderEnabled
        case .rhythm:
            guard let settings else { return false }
            return settings.targetFeedIntervalMinutes != 180 || settings.ozPresets != [2, 3, 4]
        }
    }

    func incompleteQuests(role: SyncRole, settings: SharedSettings?) -> [SetupQuest] {
        activeQuests(role: role).filter { !isComplete($0, settings: settings) }
    }

    func markComplete(_ quest: SetupQuest) {
        completedQuests.insert(quest.rawValue)
    }

    // MARK: Spotlights

    func hasShown(_ spotlight: SetupSpotlight) -> Bool {
        shownSpotlights.contains(spotlight.rawValue)
    }

    /// Marked on appear (not dismiss) — a swipe-down still counts as seen, so a
    /// spotlight never nags twice.
    func markShown(_ spotlight: SetupSpotlight) {
        shownSpotlights.insert(spotlight.rawValue)
    }

    /// Single gate for every contextual prompt: demo mode never prompts, and at
    /// most one prompt plays per foreground session. Claims the session slot on
    /// success — present immediately after a true return.
    func requestPrompt() -> Bool {
        guard !LocalPrefs.shared.demoModeEnabled, !promptShownThisSession else { return false }
        promptShownThisSession = true
        return true
    }

    // MARK: First-run hand-off

    /// Called by both finish() paths (owner onboarding, co-parent join).
    func markNewFlowComplete() {
        flowVersion = Self.currentFlowVersion
    }

    /// Installs that completed the old 10-page flow (which covered rhythm,
    /// reminders, and every story page) must never see quests or spotlights
    /// re-trigger: a Baby with no recorded flow version means exactly that.
    /// Runs once, at launch, against the real store only.
    @MainActor
    func grandfatherIfNeeded(in context: ModelContext) {
        guard flowVersion == 0, SeedData.isSeeded(in: context) else { return }
        completedQuests = Set(SetupQuest.allCases.map(\.rawValue))
        shownSpotlights = Set(SetupSpotlight.allCases.map(\.rawValue))
        dismissedChecklist = true
        flowVersion = Self.currentFlowVersion
    }

    #if DEBUG
    /// Dev-only (`-resetSetup`): pretend this device just finished the new flow —
    /// quests open, spotlights unseen — without touching the store.
    func resetForTesting() {
        completedQuests = []
        dismissedChecklist = false
        shownSpotlights = []
        reminderOfferShown = false
        flowVersion = Self.currentFlowVersion
    }
    #endif
}
