import Foundation
import SwiftData

/// A standing slot in the shared care plan. Slots are configuration, not
/// history — they're edited in place (unlike events) and recur nightly by
/// materializing `minuteOfDay` onto concrete days at read time (see
/// `ScheduleEngine`).
///
/// Two eras of `.sleep` slot share this model:
/// - legacy put-down slots (`endMinuteOfDay == nil`): a single instant,
///   "baby goes down at 8" — kept decoding for records from older builds;
/// - **parent sleep windows** (`endMinuteOfDay != nil`): "`assignedTo` sleeps
///   from `minuteOfDay` to `endMinuteOfDay`, every night until changed" — the
///   plan the night's feed routing steers around (see `NightSchedule`).
@Model
final class PlanSlot {
    var id: UUID = UUID()
    var kindRaw: String = EventKind.feed.rawValue  // .feed or .sleep only (diaper isn't schedulable)
    var minuteOfDay: Int = 0            // 0..<1440, local wall clock — survives DST unlike a Date anchor
    var endMinuteOfDay: Int?            // sleep windows: wall-clock end (may wrap midnight); nil = legacy instant
    var assignedToID: UUID?             // → Participant.id; nil = unassigned (a window: whose sleep this is)
    var assignedToName: String = ""     // denormalized so it renders if participant removed
    var assignedToColorHex: String = ""
    var createdAt: Date = Date()
    var deletedAt: Date?                // soft delete; nil == live (removed from plan)
    var ckSystemFields: Data?           // archived CKRecord system fields (see Baby.ckSystemFields)

    var kind: EventKind {
        get { EventKind(rawValue: kindRaw) ?? .feed }
        set { kindRaw = newValue.rawValue }
    }

    /// Minutes a sleep window spans, wrapping midnight (22:00→03:00 = 300).
    /// Nil for legacy instants, non-sleep slots, and degenerate zero-length
    /// windows (start == end has no sane reading — not "all day").
    var windowDurationMinutes: Int? {
        guard kind == .sleep, let end = endMinuteOfDay else { return nil }
        let duration = (((end - minuteOfDay) % 1440) + 1440) % 1440
        return duration == 0 ? nil : duration
    }

    init(
        id: UUID = UUID(),
        kind: EventKind,
        minuteOfDay: Int,
        endMinuteOfDay: Int? = nil,
        assignedToID: UUID? = nil,
        assignedToName: String = "",
        assignedToColorHex: String = "",
        createdAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.minuteOfDay = minuteOfDay
        self.endMinuteOfDay = endMinuteOfDay
        self.assignedToID = assignedToID
        self.assignedToName = assignedToName
        self.assignedToColorHex = assignedToColorHex
        self.createdAt = createdAt
        self.deletedAt = deletedAt
    }
}
