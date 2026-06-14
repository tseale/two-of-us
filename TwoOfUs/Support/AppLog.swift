import SwiftUI
import os

/// Unified `os.Logger` channels for the app target. Replaces scattered `print`s
/// so failures land in the unified log (filterable by subsystem/category in
/// Console.app and `log stream`) instead of only Xcode's debug console — which a
/// TestFlight build never shows. Use `.error` for "a parent would care," `.debug`
/// for QA-only breadcrumbs.
enum AppLog {
    private static let subsystem = "com.taylorseale.twoofus"
    static let store = Logger(subsystem: subsystem, category: "store")
    static let sync = Logger(subsystem: subsystem, category: "sync")
    static let alarms = Logger(subsystem: subsystem, category: "alarms")
    static let widgets = Logger(subsystem: subsystem, category: "widgets")
    static let liveActivity = Logger(subsystem: subsystem, category: "liveActivity")
    static let deeplink = Logger(subsystem: subsystem, category: "deeplink")
    static let ai = Logger(subsystem: subsystem, category: "ai")
}

/// A non-fatal failure worth telling the user about, surfaced as a transient
/// banner instead of being swallowed by a log line they'll never read.
struct StoreErrorBanner: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

/// Collects user-relevant write/sync failures so a banner can show. The store
/// write path (`EventStore.save`) and the sync layer post here; `RootView`
/// observes `current` and presents it. Auto-clears after a few seconds so a
/// transient hiccup doesn't leave a sticky banner.
@MainActor
@Observable
final class StoreErrorCenter {
    static let shared = StoreErrorCenter()
    private init() {}

    /// The most recent failure worth surfacing; nil when there's nothing to show.
    private(set) var current: StoreErrorBanner?
    private var clearTask: Task<Void, Never>?

    /// Reports a failure. `message` should be plain-language and actionable —
    /// it's shown verbatim to a parent who's holding a baby.
    func report(_ message: String) {
        current = StoreErrorBanner(message: message)
        clearTask?.cancel()
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.current = nil
        }
    }

    func dismiss() {
        clearTask?.cancel()
        current = nil
    }
}
