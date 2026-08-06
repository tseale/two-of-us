import SwiftUI
import SwiftData

@main
struct TwoOfUsWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
        .modelContainer(WatchModelContainer.shared)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            // Demo runs never touch CloudKit — the seeded store must not leak
            // into (or pull from) the family's real zone.
            guard !WatchModelContainer.isDemoRun else { return }
            WatchSyncManager.bootstrap(container: WatchModelContainer.shared)
            Task { await WatchSyncManager.shared?.fetchNow() }
        }
    }
}
