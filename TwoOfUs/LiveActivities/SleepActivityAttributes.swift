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
        /// Set only in the final content update when the sleep ends: freezes
        /// the timer at the total duration and flips the card into its "slept
        /// X" summary form, which lingers briefly before dismissing (see
        /// `SleepActivityManager.endAll(finalizing:)`).
        var endedAt: Date? = nil
    }

    var babyName: String
}
