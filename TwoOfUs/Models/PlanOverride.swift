import Foundation
import SwiftData

/// A one-night exception to a `PlanSlot`: "tonight the 3am feed is Taylor's"
/// or "skip tonight's 11pm". Overrides never mutate the standing slot — a swap
/// inserts a record, undo soft-deletes it — so concurrent swaps by both parents
/// can't conflict in CloudKit; `ScheduleEngine` picks a deterministic winner
/// (latest `createdAt`, then `id`) when duplicates land for the same night.
@Model
final class PlanOverride {
    var id: UUID = UUID()
    var slotID: UUID = UUID()           // → PlanSlot.id (UUID scalar, resolved locally)
    var dayKey: Int = 0                 // yyyymmdd of the occurrence's LOCAL day (tonight's 3am slot → tomorrow's key)
    var assignedToID: UUID?             // tonight's assignee; nil while !isSkipped = explicitly unassigned tonight
    var assignedToName: String = ""     // denormalized so it renders if participant removed
    var assignedToColorHex: String = ""
    var isSkipped: Bool = false         // "skip tonight" — no occurrence, no reminder
    var createdByID: UUID = UUID()      // who made the swap → "Swapped by Katie"
    var createdAt: Date = Date()
    var deletedAt: Date?                // soft delete; nil == live (undo → standing plan resumes)
    var ckSystemFields: Data?           // archived CKRecord system fields (see Baby.ckSystemFields)

    init(
        id: UUID = UUID(),
        slotID: UUID,
        dayKey: Int,
        assignedToID: UUID? = nil,
        assignedToName: String = "",
        assignedToColorHex: String = "",
        isSkipped: Bool = false,
        createdByID: UUID,
        createdAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.slotID = slotID
        self.dayKey = dayKey
        self.assignedToID = assignedToID
        self.assignedToName = assignedToName
        self.assignedToColorHex = assignedToColorHex
        self.isSkipped = isSkipped
        self.createdByID = createdByID
        self.createdAt = createdAt
        self.deletedAt = deletedAt
    }
}
