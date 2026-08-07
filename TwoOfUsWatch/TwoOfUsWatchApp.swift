import SwiftUI
import SwiftData
import WatchKit

@main
struct TwoOfUsWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase

    /// Matched against the `userInfo` string of a scheduled refresh — that's
    /// how watchOS routes a `WKApplicationRefreshBackgroundTask` to the
    /// `.backgroundTask(.appRefresh(_:))` handler below.
    private static let refreshTaskID = "sync-refresh"

    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
        .modelContainer(WatchModelContainer.shared)
        .onChange(of: scenePhase) { _, phase in
            // Demo runs never touch CloudKit — the seeded store must not leak
            // into (or pull from) the family's real zone.
            guard !WatchModelContainer.isDemoRun else { return }
            switch phase {
            case .active:
                WatchSyncManager.bootstrap(container: WatchModelContainer.shared)
                Task { await WatchSyncManager.shared?.fetchNow() }
            case .background:
                // Foreground activation used to be the ONLY fetch trigger,
                // which meant the complication could only ever be as fresh as
                // the last time the app was opened: a feed logged on a phone,
                // or a sleep started/ended there, never reached the watch face
                // until the next open. Backgrounding is where the chain starts.
                Self.scheduleBackgroundSync()
            default:
                break
            }
        }
        // The complication's freshness heartbeat. Fetch → the sync engine
        // applies changes into the App Group store → `applyFetchedChanges`
        // reloads the complication timelines. Then re-arm: each task schedules
        // the next, so the chain survives as long as watchOS grants budget
        // (roughly 4/hour with a complication on the active face — the
        // preferred date asks for the ceiling and lets the system throttle).
        .backgroundTask(.appRefresh(Self.refreshTaskID)) {
            await Self.backgroundSync()
        }
    }

    @MainActor
    private static func backgroundSync() async {
        guard !WatchModelContainer.isDemoRun else { return }
        // Background launches skip `.active`, so bootstrap here too (idempotent).
        WatchSyncManager.bootstrap(container: WatchModelContainer.shared)
        await WatchSyncManager.shared?.fetchNow()
        scheduleBackgroundSync()
    }

    private static func scheduleBackgroundSync(after interval: TimeInterval = 15 * 60) {
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: .now.addingTimeInterval(interval),
            userInfo: refreshTaskID as NSString
        ) { error in
            if let error {
                AppLog.sync.error("Watch background refresh scheduling failed: \(error.localizedDescription, privacy: .public)")
            } else {
                AppLog.sync.log("Watch background refresh scheduled (~\(Int(interval / 60), privacy: .public)m)")
            }
        }
    }
}
