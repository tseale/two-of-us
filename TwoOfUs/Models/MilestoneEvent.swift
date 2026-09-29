import Foundation
import SwiftData

/// A developmental milestone ("Rolled over!") — the timeline's achievement
/// badge, gold, with an optional photo of the moment.
@Model
final class MilestoneEvent {
    var id: UUID = UUID()
    var baby: Baby?
    var text: String = ""               // what happened — "Rolled from tummy to back!"
    var categoryRaw: String = MilestoneCategory.physical.rawValue
    var timestamp: Date = Date()        // when it happened (backdatable)
    var notes: String?
    var photoData: Data?                // optional photo of the moment; CKAsset on the wire
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
        text: String,
        category: MilestoneCategory,
        timestamp: Date = Date(),
        notes: String? = nil,
        photoData: Data? = nil,
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
        self.text = text
        self.categoryRaw = category.rawValue
        self.timestamp = timestamp
        self.notes = notes
        self.photoData = photoData
        self.loggedByID = loggedByID
        self.loggedByName = loggedByName
        self.loggedByColorHex = loggedByColorHex
        self.deletedAt = deletedAt
        self.editOfID = editOfID
        self.sourceRaw = sourceRaw
        self.externalID = externalID
    }

    var category: MilestoneCategory { MilestoneCategory(rawValue: categoryRaw) ?? .physical }
    var source: EventSource? { sourceRaw.flatMap(EventSource.init(rawValue:)) }
    var isFromDaycare: Bool { source == .brightwheel }
}
