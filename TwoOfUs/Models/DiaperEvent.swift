import Foundation
import SwiftData

/// A diaper change at a point in time.
@Model
final class DiaperEvent {
    var id: UUID = UUID()
    var baby: Baby?
    var typeRaw: String = DiaperType.wet.rawValue
    var timestamp: Date = Date()
    var notes: String?
    var loggedByID: UUID = UUID()
    var loggedByName: String = ""
    var loggedByColorHex: String = ""
    var deletedAt: Date?
    var editOfID: UUID?
    /// Where this record came from (`EventSource` raw value); nil == logged by
    /// hand. Optional String keeps the SwiftData migration lightweight and the
    /// CloudKit field additive.
    var sourceRaw: String?
    /// The originating system's own id for an imported record (Brightwheel
    /// activity object_id) — the cross-device dedupe key, so a re-import or a
    /// second connected phone can't duplicate the event.
    var externalID: String?
    var ckSystemFields: Data?           // archived CKRecord system fields (see Baby.ckSystemFields)

    /// Stored as a raw string for CloudKit friendliness; accessed as the enum.
    var type: DiaperType {
        get { DiaperType(rawValue: typeRaw) ?? .wet }
        set { typeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        baby: Baby?,
        type: DiaperType,
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
        self.typeRaw = type.rawValue
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
