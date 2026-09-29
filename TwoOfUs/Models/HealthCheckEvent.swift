import Foundation
import SwiftData

/// A health measurement from the daycare ("Temp 98.6°F"). The value is a bare
/// number; `HealthCheckType` owns the display unit (°F / lb) until the real
/// wire format teaches us whether Brightwheel sends units.
@Model
final class HealthCheckEvent {
    var id: UUID = UUID()
    var baby: Baby?
    var typeRaw: String = HealthCheckType.temperature.rawValue
    var value: Double = 0
    var timestamp: Date = Date()        // when it was measured (backdatable)
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
        type: HealthCheckType,
        value: Double,
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
        self.value = value
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

    var type: HealthCheckType { HealthCheckType(rawValue: typeRaw) ?? .temperature }
    var source: EventSource? { sourceRaw.flatMap(EventSource.init(rawValue:)) }
    var isFromDaycare: Bool { source == .brightwheel }
}
