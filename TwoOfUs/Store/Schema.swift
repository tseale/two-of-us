import SwiftData

/// SwiftData versioned schema — shared between the main app and widget extension
/// so both open the same store file with an identical schema.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Baby.self, FeedEvent.self, SleepEvent.self, DiaperEvent.self, Participant.self, SharedSettings.self,
         PlanSlot.self, PlanOverride.self]
    }
}

// Adding the optional `photoData` avatars to Baby/Participant is a purely additive
// change. SwiftData's CloudKit-mirroring container performs automatic lightweight
// migration for it — existing rows just get `nil` — so no explicit migration stage
// is needed. (A hand-rolled VersionedSchema bump is actually counterproductive
// here: each VersionedSchema references the live model types, so a "v1" snapshot
// would also carry photoData and fail to match the real on-disk v1 store.)
enum TwoOfUsMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
