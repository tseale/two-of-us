import SwiftUI
import SwiftData

@main
struct MillerTimeApp: App {
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
        }
        .modelContainer(container)
    }
}
