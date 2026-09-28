import Foundation
import SwiftData

/// A formula feed. Feeds are instantaneous — an amount at a point in time.
@Model
final class FeedEvent {
    var id: UUID = UUID()
    var baby: Baby?
    var amountOz: Double = 0            // supports half-ounce steps (2, 2.5, 3…)
    var timestamp: Date = Date()        // when the bottle was given (backdatable)
    var notes: String?                  // optional free-text note (log + edit sheets)
    var loggedByID: UUID = UUID()
    var loggedByName: String = ""       // denormalized so it renders if participant removed
    var loggedByColorHex: String = ""
    var deletedAt: Date?                // soft delete; nil == live
    var editOfID: UUID?                 // if this replaced an edited record, points to the original
    /// Where this record came from (`EventSource` raw value); nil == logged by
    /// hand. Optional String keeps the SwiftData migration lightweight and the
    /// CloudKit field additive.
    var sourceRaw: String?
    /// The originating system's own id for an imported record (Brightwheel
    /// activity object_id) — the cross-device dedupe key, so a re-import or a
    /// second connected phone can't duplicate the event.
    var externalID: String?
    var ckSystemFields: Data?           // archived CKRecord system fields (see Baby.ckSystemFields)

    init(
        id: UUID = UUID(),
        baby: Baby?,
        amountOz: Double,
        timestamp: Date = Date(),
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
        self.amountOz = amountOz
        self.timestamp = timestamp
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
