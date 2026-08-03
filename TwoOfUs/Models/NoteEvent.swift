import Foundation
import SwiftData

/// A standalone timestamped note on the timeline ("gave vitamin D drops").
/// Distinct from the optional `notes` field attached to feed/sleep/diaper
/// events — this is its own entry, not an annotation on another one.
@Model
final class NoteEvent {
    var id: UUID = UUID()
    var baby: Baby?
    var text: String = ""
    var timestamp: Date = Date()        // when it happened (backdatable)
    var loggedByID: UUID = UUID()
    var loggedByName: String = ""       // denormalized so it renders if participant removed
    var loggedByColorHex: String = ""
    var deletedAt: Date?                // soft delete; nil == live
    var editOfID: UUID?                 // if this replaced an edited record, points to the original
    var ckSystemFields: Data?           // archived CKRecord system fields (see Baby.ckSystemFields)

    init(
        id: UUID = UUID(),
        baby: Baby?,
        text: String,
        timestamp: Date = Date(),
        loggedByID: UUID,
        loggedByName: String,
        loggedByColorHex: String,
        deletedAt: Date? = nil,
        editOfID: UUID? = nil
    ) {
        self.id = id
        self.baby = baby
        self.text = text
        self.timestamp = timestamp
        self.loggedByID = loggedByID
        self.loggedByName = loggedByName
        self.loggedByColorHex = loggedByColorHex
        self.deletedAt = deletedAt
        self.editOfID = editOfID
    }
}
