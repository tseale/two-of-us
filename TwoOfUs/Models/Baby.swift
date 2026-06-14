import Foundation
import SwiftData

/// The baby being tracked. v1 has exactly one; the model stays relational so a
/// future sibling needs a baby switcher, not a schema migration.
@Model
final class Baby {
    var id: UUID = UUID()
    var name: String = ""
    var dateOfBirth: Date = Date()
    var createdAt: Date = Date()

    /// Optional avatar, stored as a downscaled JPEG (~512px, see `ImageDownscale`)
    /// and synced to the co-parent as a CKAsset. Stored inline — small (~50KB) and
    /// inline keeps it compatible with SwiftData's CloudKit-mirroring container,
    /// which does not support external-storage attributes.
    var photoData: Data?

    /// Archived CKRecord system fields from the last server save/fetch of this
    /// record (`encodeSystemFields`). Local-only — never uploaded. CloudKit
    /// rejects updates that don't carry the server's change tag, so outbound
    /// records must be rebuilt on top of this archive (see `RecordMapping`).
    var ckSystemFields: Data?

    // Inverse relationships — required for CloudKit (NSPersistentCloudKitContainer
    // mandates that every relationship has an inverse). Optional arrays to satisfy
    // CloudKit's all-optional rule.
    //
    // INVARIANT: `.cascade` here means hard-deleting a Baby hard-deletes its
    // events locally. The app never hard-deletes a Baby during normal use —
    // routine removals are soft-deletes (`deletedAt`), and a full wipe goes
    // through `SyncManager.deleteEverything()`, which tears the CloudKit zone down
    // first. Do not introduce a `context.delete(baby)` path without confirming the
    // matching CloudKit records are also removed, or the co-parent keeps orphans.
    @Relationship(deleteRule: .cascade, inverse: \FeedEvent.baby) var feeds: [FeedEvent]? = []
    @Relationship(deleteRule: .cascade, inverse: \SleepEvent.baby) var sleeps: [SleepEvent]? = []
    @Relationship(deleteRule: .cascade, inverse: \DiaperEvent.baby) var diapers: [DiaperEvent]? = []

    init(id: UUID = UUID(), name: String, dateOfBirth: Date, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.dateOfBirth = dateOfBirth
        self.createdAt = createdAt
    }
}
