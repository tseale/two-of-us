import Foundation
import SwiftData

/// A photo or video from the daycare. `remoteURL` is Brightwheel's signed CDN
/// link (works only while signed); `mediaData` is the locally cached image
/// bytes — the durable copy that syncs to the co-parent as a CKAsset. Either
/// can be nil: a just-imported photo has only the URL until the cache pass
/// lands (a later phase), and the row falls back to a placeholder.
@Model
final class MediaEvent {
    var id: UUID = UUID()
    var baby: Baby?
    var kindRaw: String = MediaKind.photo.rawValue
    var timestamp: Date = Date()        // when it was taken (backdatable)
    var caption: String?                // staff's caption, shown under the thumbnail
    var remoteURL: String?              // Brightwheel CDN link (signed, may expire)
    var mediaData: Data?                // cached image bytes; CKAsset on the wire
    var loggedByID: UUID = UUID()
    var loggedByName: String = ""       // denormalized so it renders if participant removed
    var loggedByColorHex: String = ""
    var deletedAt: Date?                // soft delete; nil == live
    var editOfID: UUID?                 // if this replaced an edited record, points to the original
    var sourceRaw: String?              // EventSource raw value; nil == logged by hand
    var externalID: String?             // originating system's id (Brightwheel object_id) — dedupe key
    var ckSystemFields: Data?           // archived CKRecord system fields (see Baby.ckSystemFields)

    init(
        id: UUID = UUID(),
        baby: Baby?,
        kind: MediaKind,
        timestamp: Date = Date(),
        caption: String? = nil,
        remoteURL: String? = nil,
        mediaData: Data? = nil,
        loggedByID: UUID,
        loggedByName: String,
        loggedByColorHex: String,
        deletedAt: Date? = nil,
        editOfID: UUID? = nil,
        sourceRaw: String? = nil,
        externalID: String? = nil
    ) {
        self.id = id
        self.baby = baby
        self.kindRaw = kind.rawValue
        self.timestamp = timestamp
        self.caption = caption
        self.remoteURL = remoteURL
        self.mediaData = mediaData
        self.loggedByID = loggedByID
        self.loggedByName = loggedByName
        self.loggedByColorHex = loggedByColorHex
        self.deletedAt = deletedAt
        self.editOfID = editOfID
        self.sourceRaw = sourceRaw
        self.externalID = externalID
    }

    var kind: MediaKind { MediaKind(rawValue: kindRaw) ?? .photo }
    var source: EventSource? { sourceRaw.flatMap(EventSource.init(rawValue:)) }
    var isFromDaycare: Bool { source == .brightwheel }
}
