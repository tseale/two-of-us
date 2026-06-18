import ActivityKit
import Foundation

/// Attributes for the Sleep Live Activity. Static attributes are set when the
/// activity starts; ContentState is updated while the sleep is active.
struct SleepActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// When the sleep started — used by views as a `.timer`-style Text source
        /// so no periodic push updates are needed.
        var startedAt: Date
    }

    var babyName: String
}

extension SleepActivityAttributes {
    /// Ends every running Sleep Live Activity immediately. Lives in the shared
    /// attributes file (compiled into both the app and the widget extension) so
    /// the stop paths that run *outside* the app — the lock-screen / Dynamic
    /// Island Wake button and the Siri "awake" intent — can tear the Island down
    /// the moment sleep ends, instead of leaving it counting until the app is
    /// next foregrounded and `SleepActivityManager.reconcile` catches up.
    static func endAllRunning() async {
        for activity in Activity<SleepActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
