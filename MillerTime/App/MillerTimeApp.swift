import SwiftUI
import SwiftData

@main
struct MillerTimeApp: App {
    let container = AppModelContainer.make()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
