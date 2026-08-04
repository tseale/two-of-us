import ActivityKit
import Foundation

/// Attributes for the Sleep Live Activity. Static attributes are set when the
/// activity starts; ContentState is updated while the sleep is active.
struct SleepActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// When the sleep started — used by views as a `.timer`-style Text source
        /// so no periodic push updates are needed.
        var startedAt: Date
        /// Predicted next feed, shown as a self-ticking countdown in the
        /// trailing column (where the Wake button used to be). Computed
        /// app-side when the activity starts and refreshed on every reconcile —
        /// the schedule engines don't compile into the widget extension. Nil
        /// hides the column (no feeds to predict from yet, or prediction
        /// already past when computed).
        var nextFeedAt: Date? = nil
        /// Who the next feed belongs to, when the nighttime schedule assigns
        /// it ("GT"). Nil for the generic daytime prediction.
        var nextFeedOwnerName: String? = nil
        var nextFeedOwnerColorHex: String? = nil
    }

    var babyName: String
}

extension SleepActivityAttributes {
    /// Ends every running Sleep Live Activity immediately. Lives in the shared
    /// attributes file (compiled into both the app and the widget extension) so
    /// the stop paths that run *outside* the app — the home-screen widget Wake
    /// button and the Siri "awake" intent — can tear the Island down the moment
    /// sleep ends, instead of leaving it counting until the app is next
    /// foregrounded and `SleepActivityManager.reconcile` catches up.
    static func endAllRunning() async {
        for activity in Activity<SleepActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
