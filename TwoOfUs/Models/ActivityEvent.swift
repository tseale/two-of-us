import Foundation
import SwiftData

/// A daycare activity ("Tummy Time · 15m"). Instantaneous with an optional
/// duration — Brightwheel reports activities as a single entry, not a
/// start/end pair like naps.
@Model
final class ActivityEvent {
    var id: UUID = UUID()
    var baby: Baby?
    var typeRaw: String = ActivityType.freePlay.rawValue
    var timestamp: Date = Date()        // when it happened (backdatable)
    var durationMinutes: Int?           // nil when the report didn't say
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
        type: ActivityType,
        timestamp: Date = Date(),
        durationMinutes: Int? = nil,
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
        self.durationMinutes = durationMinutes
        self.notes = notes
        self.loggedByID = loggedByID
        self.loggedByName = loggedByName
        self.loggedByColorHex = loggedByColorHex
        self.deletedAt = deletedAt
        self.editOfID = editOfID
        self.sourceRaw = sourceRaw
        self.externalID = externalID
    }

    var type: ActivityType { ActivityType(rawValue: typeRaw) ?? .freePlay }
    var source: EventSource? { sourceRaw.flatMap(EventSource.init(rawValue:)) }
    var isFromDaycare: Bool { source == .brightwheel }
}
