import SwiftUI
import SwiftData

@main
struct MillerTimeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    let container = AppModelContainer.make()

    init() {
        #if DEBUG
        // Dev-only: `-seedSampleData` populates a week of events for screenshots.
        if ProcessInfo.processInfo.arguments.contains("-seedSampleData") {
            let ctx = container.mainContext
            SeedData.seedIfNeeded(in: ctx, babyName: "Miller")
            SeedData.seedSampleEvents(in: ctx)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .task {
                    if SyncManager.shared == nil {
                        SyncManager.shared = SyncManager(modelContainer: container)
                    }
                    SyncManager.shared?.start()
                }
        }
        .modelContainer(container)
    }
}
