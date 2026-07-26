import Foundation
import SwiftData

/// App-wide settings that are shared between all participants (synced in
/// Increment 2). Stored as a single record.
@Model
final class SharedSettings {
    var id: UUID = UUID()
    var targetFeedIntervalMinutes: Int = 180   // next-feed countdown target (3h)
    var ozPresets: [Double] = [2, 3, 4]
    var defaultFeedOz: Double = 4              // one-tap feed amount (widget / Siri)
    // Per-kind tracker switches — shared, so both parents see the same buttons.
    // Turning one off hides its logging UI and blocks new events of that kind;
    // existing entries stay. Defaulted (not optional) so pre-upgrade stores and
    // records that predate the field read as "on".
    var feedLoggingEnabled: Bool = true
    var diaperLoggingEnabled: Bool = true
    var sleepLoggingEnabled: Bool = true
    var ckSystemFields: Data?                  // archived CKRecord system fields (see Baby.ckSystemFields)

    init(
        id: UUID = UUID(),
        targetFeedIntervalMinutes: Int = 180,
        ozPresets: [Double] = [2, 3, 4],
        defaultFeedOz: Double = 4,
        feedLoggingEnabled: Bool = true,
        diaperLoggingEnabled: Bool = true,
        sleepLoggingEnabled: Bool = true
    ) {
        self.id = id
        self.targetFeedIntervalMinutes = targetFeedIntervalMinutes
        self.ozPresets = ozPresets
        self.defaultFeedOz = defaultFeedOz
        self.feedLoggingEnabled = feedLoggingEnabled
        self.diaperLoggingEnabled = diaperLoggingEnabled
        self.sleepLoggingEnabled = sleepLoggingEnabled
    }

    var targetFeedInterval: TimeInterval { TimeInterval(targetFeedIntervalMinutes * 60) }

    private func rawEnabled(_ kind: EventKind) -> Bool {
        switch kind {
        case .feed: return feedLoggingEnabled
        case .diaper: return diaperLoggingEnabled
        case .sleep: return sleepLoggingEnabled
        }
    }

    /// Whether `kind` is being tracked. An all-off state can only arise from a
    /// sync merge of two parents' concurrent toggles (the UI pins the last
    /// tracker on) — it would hide every log button, so it fails open to all-on.
    func isEnabled(_ kind: EventKind) -> Bool {
        EventKind.allCases.contains(where: rawEnabled) ? rawEnabled(kind) : true
    }

    /// How many trackers are on. The UI refuses to drop below one — an app with
    /// nothing to log is a brick — and `EventStore.updateSettings` backstops it.
    var enabledTrackerCount: Int {
        EventKind.allCases.count(where: isEnabled)
    }
}
