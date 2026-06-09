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

    // Inverse relationships — required for CloudKit (NSPersistentCloudKitContainer
    // mandates that every relationship has an inverse). Optional arrays to satisfy
    // CloudKit's all-optional rule.
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
