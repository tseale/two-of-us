import Foundation
import SwiftData

/// A daycare arrival or departure — the milestone markers that bracket the
/// day ("Checked in 7:30 AM" / "Checked out 4:30 PM") and feed the report
/// card's "hours at daycare".
@Model
final class CheckEvent {
    var id: UUID = UUID()
    var baby: Baby?
    var typeRaw: String = CheckType.checkIn.rawValue
    var timestamp: Date = Date()        // when it happened (backdatable)
    var byName: String?                 // who dropped off / picked up ("Dad", "Grandma")
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
        type: CheckType,
        timestamp: Date = Date(),
        byName: String? = nil,
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
        self.byName = byName
        self.notes = notes
        self.loggedByID = loggedByID
        self.loggedByName = loggedByName
        self.loggedByColorHex = loggedByColorHex
        self.deletedAt = deletedAt
        self.editOfID = editOfID
        self.sourceRaw = sourceRaw
        self.externalID = externalID
    }

    var type: CheckType { CheckType(rawValue: typeRaw) ?? .checkIn }
    var source: EventSource? { sourceRaw.flatMap(EventSource.init(rawValue:)) }
    var isFromDaycare: Bool { source == .brightwheel }
}
