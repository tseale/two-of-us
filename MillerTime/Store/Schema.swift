import SwiftData

/// SwiftData versioned schema — shared between the main app and widget extension
/// so both open the same store file with an identical schema.
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
