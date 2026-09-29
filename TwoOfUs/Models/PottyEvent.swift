import Foundation
import SwiftData

/// A toilet-training event — distinct from DiaperEvent (what was in a
/// diaper). Not relevant at 2 months; modeled now so the CloudKit schema is
/// already additive-complete when Miller gets there.
@Model
final class PottyEvent {
    var id: UUID = UUID()
    var baby: Baby?
    var outcomeRaw: String = PottyOutcome.attempt.rawValue
    var timestamp: Date = Date()        // when it happened (backdatable)
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
        outcome: PottyOutcome,
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
        self.outcomeRaw = outcome.rawValue
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

    var outcome: PottyOutcome { PottyOutcome(rawValue: outcomeRaw) ?? .attempt }
    var source: EventSource? { sourceRaw.flatMap(EventSource.init(rawValue:)) }
    var isFromDaycare: Bool { source == .brightwheel }
}
