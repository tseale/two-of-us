import Foundation
import SwiftData

enum AppModelContainer {
    /// Main app container — Increment 3+: stored in the App Group container so
    /// the widget extension can read the same data. Falls back to the default
    /// app-support location when the App Group entitlement is not configured
    /// (Simulator without signing).
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
                migrationPlan: MillerTimeMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    /// In-memory container for SwiftUI previews and tests.
    @MainActor static let preview: ModelContainer = {
        let container = make(inMemory: true)
        SeedData.seedIfNeeded(in: container.mainContext, babyName: "Miller")
        SeedData.seedSampleEvents(in: container.mainContext)
        return container
    }()
}
