import Foundation
import SwiftData

/// Versioned schema so future increments have a migration seam from day one.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Baby.self, FeedEvent.self, SleepEvent.self, DiaperEvent.self, Participant.self, SharedSettings.self]
    }
}

enum MillerTimeMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

enum AppModelContainer {
    /// Increment 1: local store, no CloudKit. The store URL stays implicit here so
    /// Increment 3 can redirect it to the App Group container, and Increment 2 can
    /// enable CloudKit, in one place.
    static func make(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, migrationPlan: MillerTimeMigrationPlan.self, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    /// In-memory container for previews and tests.
    @MainActor static let preview: ModelContainer = {
        let container = make(inMemory: true)
        SeedData.seedIfNeeded(in: container.mainContext, babyName: "Miller")
        return container
    }()
}
