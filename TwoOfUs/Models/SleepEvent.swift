import Foundation
import SwiftData

/// A sleep stretch. `endedAt == nil` while the timer is running — the only
/// running timer in the app.
@Model
final class SleepEvent {
    var id: UUID = UUID()
    var baby: Baby?
    var startedAt: Date = Date()
    var endedAt: Date?                  // nil while sleeping
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
    /// The originating system's own id for an imported record (SNOO session
    /// id, Brightwheel activity object_id) — the cross-device dedupe key, so
    /// a re-import or a second connected phone can't duplicate the event.
    var externalID: String?
    var ckSystemFields: Data?           // archived CKRecord system fields (see Baby.ckSystemFields)

    init(
        id: UUID = UUID(),
        baby: Baby?,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
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
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.notes = notes
        self.loggedByID = loggedByID
        self.loggedByName = loggedByName
        self.loggedByColorHex = loggedByColorHex
        self.deletedAt = deletedAt
        self.editOfID = editOfID
        self.sourceRaw = sourceRaw
        self.externalID = externalID
    }

    /// Whether this sleep is currently in progress.
    var isActive: Bool { endedAt == nil && deletedAt == nil }

    var source: EventSource? { sourceRaw.flatMap(EventSource.init(rawValue:)) }
    var isFromSnoo: Bool { source == .snoo }
    var isFromDaycare: Bool { source == .brightwheel }
}
