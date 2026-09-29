import Foundation
import SwiftData

/// A medication administration ("Tylenol · 2.5ml"). Rendered in red — the one
/// event type a parent must never scroll past.
@Model
final class MedicationEvent {
    var id: UUID = UUID()
    var baby: Baby?
    var name: String = ""               // "Tylenol"
    var dosage: String?                 // "2.5 ml" — free text; units vary by med
    var timestamp: Date = Date()        // when it was given (backdatable)
    var administeredBy: String?         // staff member who gave it
    var notes: String?
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
        name: String,
        dosage: String? = nil,
        timestamp: Date = Date(),
        administeredBy: String? = nil,
        notes: String? = nil,
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
        self.name = name
        self.dosage = dosage
        self.timestamp = timestamp
        self.administeredBy = administeredBy
        self.notes = notes
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
