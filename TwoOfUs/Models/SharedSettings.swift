import Foundation
import SwiftData

/// One recurring daily window of the feed schedule ("the 2am feed"). When the
/// next feed reminder would fire inside a slot, only the assigned parent's
/// device arms its alarm/nudge; an unassigned slot (`nil`) alerts everyone.
struct FeedSlot: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var startMinutes: Int          // minutes from local midnight, 0..<1440
    var endMinutes: Int            // exclusive; may be < start (wraps past midnight)
    var assignedParticipantID: UUID?

    /// Whether `date`'s local time-of-day falls inside this slot. Half-open and
    /// wrap-aware: 22:00–02:00 covers 23:30 and 01:59, not 02:00. A zero-length
    /// slot (start == end) contains nothing.
    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        if startMinutes == endMinutes { return false }
        return startMinutes < endMinutes
            ? (m >= startMinutes && m < endMinutes)
            : (m >= startMinutes || m < endMinutes)
    }
}

/// The routing rule every feed reminder goes through (the AlarmKit alarm, its
/// notification fallback, and the gentle nudge).
enum FeedSchedule {
    /// True when THIS device should arm a feed reminder firing at `fireDate`.
    ///
    /// Biases toward reminding: an uncovered time, an unassigned slot, an
    /// unknown local identity, or an assignee who is no longer an active
    /// participant all remind everyone — a silently skipped overnight alarm
    /// (nobody feeds the baby) is worse than a needlessly woken parent. The
    /// device stays dark only when every slot covering the fire time is
    /// assigned to somebody else.
    static func shouldRemind(
        slots: [FeedSlot], at fireDate: Date, myParticipantID: UUID?,
        activeParticipantIDs: Set<UUID>? = nil, calendar: Calendar = .current
    ) -> Bool {
        let covering = slots.filter { $0.contains(fireDate, calendar: calendar) }
        guard !covering.isEmpty else { return true }
        guard let me = myParticipantID else { return true }
        return covering.contains { slot in
            guard let assignee = slot.assignedParticipantID else { return true }
            if let active = activeParticipantIDs, !active.contains(assignee) { return true }
            return assignee == me
        }
    }
}

/// App-wide settings that are shared between all participants (synced in
/// Increment 2). Stored as a single record.
@Model
final class SharedSettings {
    var id: UUID = UUID()
    var targetFeedIntervalMinutes: Int = 180   // next-feed countdown target (3h)
    var ozPresets: [Double] = [2, 3, 4]
    var defaultFeedOz: Double = 4              // one-tap feed amount (widget / Siri)
    var feedSlotsData: Data?                   // JSON [FeedSlot]; nil = never configured
    var ckSystemFields: Data?                  // archived CKRecord system fields (see Baby.ckSystemFields)

    init(
        id: UUID = UUID(),
        targetFeedIntervalMinutes: Int = 180,
        ozPresets: [Double] = [2, 3, 4],
        defaultFeedOz: Double = 4
    ) {
        self.id = id
        self.targetFeedIntervalMinutes = targetFeedIntervalMinutes
        self.ozPresets = ozPresets
        self.defaultFeedOz = defaultFeedOz
    }

    var targetFeedInterval: TimeInterval { TimeInterval(targetFeedIntervalMinutes * 60) }

    /// The feed schedule, decoded. Setting always encodes — even `[]` — so
    /// "cleared the schedule" travels to the co-parent as a real value; `nil`
    /// data is reserved for "never configured" (and for records written by app
    /// versions that predate the schedule, which must not wipe a local one).
    var feedSlots: [FeedSlot] {
        get {
            guard let feedSlotsData else { return [] }
            return (try? JSONDecoder().decode([FeedSlot].self, from: feedSlotsData)) ?? []
        }
        set {
            feedSlotsData = try? JSONEncoder().encode(newValue)
        }
    }
}
