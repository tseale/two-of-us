import Foundation
import SwiftData

/// A free-text note FROM the daycare staff ("Miller was so smiley today!").
/// Distinct from NoteEvent, the parents' own notes: this one carries the
/// staff author's name and renders quote-card style.
@Model
final class StaffNoteEvent {
    var id: UUID = UUID()
    var baby: Baby?
    var text: String = ""
    var authorName: String?             // "Ms. Sarah" — the staff member who wrote it
    var timestamp: Date = Date()        // when it was written (backdatable)
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
        authorName: String? = nil,
        timestamp: Date = Date(),
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
        self.authorName = authorName
        self.timestamp = timestamp
        self.loggedByID = loggedByID
        self.loggedByName = loggedByName
        self.loggedByColorHex = loggedByColorHex
        self.deletedAt = deletedAt
        self.editOfID = editOfID
        self.sourceRaw = sourceRaw
        self.externalID = externalID
    }

    var source: EventSource? { sourceRaw.flatMap(EventSource.init(rawValue:)) }
    var isFromDaycare: Bool { source == .brightwheel }
}
