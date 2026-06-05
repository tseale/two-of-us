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
        editOfID: UUID? = nil
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
    }

    /// Whether this sleep is currently in progress.
    var isActive: Bool { endedAt == nil && deletedAt == nil }
}
