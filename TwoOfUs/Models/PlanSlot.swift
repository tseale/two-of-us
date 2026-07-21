import Foundation
import SwiftData

/// A standing slot in the shared care plan: "the 11pm feed is Katie's, every
/// night until changed". Slots are configuration, not history — they're edited
/// in place (unlike events) and recur nightly by materializing `minuteOfDay`
/// onto concrete days at read time (see `ScheduleEngine`).
@Model
final class PlanSlot {
    var id: UUID = UUID()
    var kindRaw: String = EventKind.feed.rawValue  // .feed or .sleep only (diaper isn't schedulable)
    var minuteOfDay: Int = 0            // 0..<1440, local wall clock — survives DST unlike a Date anchor
    var assignedToID: UUID?             // → Participant.id; nil = unassigned
    var assignedToName: String = ""     // denormalized so it renders if participant removed
    var assignedToColorHex: String = ""
    var createdAt: Date = Date()
    var deletedAt: Date?                // soft delete; nil == live (removed from plan)
    var ckSystemFields: Data?           // archived CKRecord system fields (see Baby.ckSystemFields)

    var kind: EventKind {
        get { EventKind(rawValue: kindRaw) ?? .feed }
        set { kindRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        kind: EventKind,
        minuteOfDay: Int,
        assignedToID: UUID? = nil,
        assignedToName: String = "",
        assignedToColorHex: String = "",
        createdAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.minuteOfDay = minuteOfDay
        self.assignedToID = assignedToID
        self.assignedToName = assignedToName
        self.assignedToColorHex = assignedToColorHex
        self.createdAt = createdAt
        self.deletedAt = deletedAt
    }
}
