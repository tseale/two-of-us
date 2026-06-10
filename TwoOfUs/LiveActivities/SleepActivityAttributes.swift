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
