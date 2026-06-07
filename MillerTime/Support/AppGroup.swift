import Foundation

/// Shared App Group constants — used by both the main app and the widget extension
/// to point at the same SQLite store and UserDefaults suite.
enum AppGroup {
    static let id = "group.com.taylorseale.millertime"

    /// The App Group container directory. Returns nil in Simulator when the
    /// entitlement is not configured (e.g. Increment 1 / no signing).
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
    }

    /// Shared SQLite store URL — both app and widget point here.
    static var storeURL: URL? {
        containerURL?.appendingPathComponent("millertime.sqlite")
    }

    /// Shared UserDefaults suite — used by SleepActivityManager to persist the
    /// live-activity ID across app relaunches.
    static var userDefaults: UserDefaults? {
        UserDefaults(suiteName: id)
    }
}
