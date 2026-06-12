import Foundation
import SwiftData

enum AppModelContainer {
    /// The one real (on-disk) container for the app process. Both the SwiftUI
    /// tree and `SyncManager` must use this instance — and it must be reachable
    /// WITHOUT the UI existing, because a background launch for a CloudKit
    /// silent push never connects a scene.
    static let shared: ModelContainer = make()

    /// Main app container — stored in the App Group container so the widget
    /// extension can read the same data. CloudKit sync is driven by `SyncManager`
    /// (CKSyncEngine), NOT SwiftData's `.automatic`: shared-database / CKShare sync
    /// between the two parents is impossible through SwiftData, and two systems
    /// can't mirror one store. Falls back to the default app-support location when
    /// the App Group entitlement is not configured (Simulator without signing).
    static func make(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else if let storeURL = AppGroup.storeURL {
            config = ModelConfiguration(schema: schema, url: storeURL)
        } else {
            // Fallback: Simulator / no App Group entitlement
            config = ModelConfiguration(schema: schema)
        }
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: TwoOfUsMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    /// In-memory container for SwiftUI previews and tests.
    @MainActor static let preview: ModelContainer = {
        let container = make(inMemory: true)
        SeedData.seedIfNeeded(in: container.mainContext, babyName: "Charlie")
        SeedData.seedSampleEvents(in: container.mainContext)
        return container
    }()
}
