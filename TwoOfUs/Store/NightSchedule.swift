import Foundation

/// Pure computation of tonight's dynamic feed schedule. Unlike the standing
/// `PlanSlot` plan (now sleep-only), night feeds have no stored slots: the
/// schedule *constructs itself* each night from the shared config plus the
/// feed log. The first feed logged inside the night window anchors the night —
/// every later slot is anchor + k·spacing until the window closes, and the
/// rotation alternates through the parents starting from whoever logged that
/// anchor. Nothing here is persisted; both phones derive the identical
/// schedule from the same synced settings and events.
///
/// Sibling of `ScheduleEngine`/`StatsEngine`: no store access, no side
/// effects — callers pass fetched arrays, tests pass fixtures with a pinned
/// calendar and `now`.
struct NightSchedule {
    /// Minimal parent identity the rotation needs, decoupled from SwiftData.
    struct Parent: Equatable {
        let id: UUID
        let name: String
        let colorHex: String
    }

    /// Where tonight stands, for the Home card.
    enum State: Equatable {
        case day                                          // now is outside the night window
        case waiting(windowStart: Date, windowEnd: Date)  // night's on, no feed yet — nothing to show but the invitation
        case active([ScheduleOccurrence])                 // anchored: the constructed schedule
    }

    let nightStartMinute: Int          // 0..<1440 wall clock, same convention as SharedSettings
    let nightEndMinute: Int
    let spacingMinutes: Int
    let rotation: NightRotation
    /// Active participants in join order — the rotation order both phones agree on.
    let parents: [Parent]
    let feeds: [FeedEvent]
    var calendar: Calendar = .current
    var now: Date = .now

    // MARK: Public API

    var state: State {
        guard let window = currentWindow else { return .day }
        guard anchor != nil else { return .waiting(windowStart: window.start, windowEnd: window.end) }
        return .active(occurrences())
    }

    /// Tonight's constructed schedule, ascending — empty when the night hasn't
    /// started (no window, or no anchoring feed yet).
    func occurrences() -> [ScheduleOccurrence] {
        guard let window = currentWindow, let anchor else { return [] }
        let times = Self.slotTimes(anchor: anchor.timestamp, windowEnd: window.end,
                                   spacingMinutes: spacingMinutes)
        let assignees = rotationAssignees(count: times.count, anchorLoggerID: anchor.loggedByID)
        let fulfilled = fulfillment(times: times)
        let nightKey = ScheduleEngine.dayKey(for: window.start, calendar: calendar)

        return times.enumerated().map { index, date in
            let status: ScheduleOccurrence.Status
            if let eventID = fulfilled[index] {
                status = .fulfilled(byEventID: eventID)
            } else if date < now {
                status = .overdue
            } else {
                status = .upcoming
            }
            let assignee = assignees[index]
            return ScheduleOccurrence(
                id: "night.\(nightKey).\(index)",
                slotID: Self.syntheticSlotID(nightKey: nightKey, index: index),
                kind: .feed,
                date: date,
                dayKey: ScheduleEngine.dayKey(for: date, calendar: calendar),
                status: status,
                assignedToID: assignee?.id,
                assignedToName: assignee?.name ?? "",
                assignedToColorHex: assignee?.colorHex ?? "",
                activeOverrideID: nil,
                overrideCreatedByID: nil,
                source: .night
            )
        }
    }

    /// The night window containing `now`, or nil while it's daytime. Materialized
    /// on real days so DST resolves per `Calendar` policy (same as the standing
    /// plan) — a zero-length window (start == end) is no window at all.
    var currentWindow: (start: Date, end: Date)? {
        let start = wrap(nightStartMinute)
        let end = wrap(nightEndMinute)
        let nowMinute = minuteOfDay(now)
        guard NightScheduleGenerator.isWithinNight(
            minuteOfDay: nowMinute, nightStartMinute: start, nightEndMinute: end
        ) else { return nil }
        // The window opened today if we've passed its start minute today,
        // otherwise it opened yesterday and wraps midnight (and mirrored for
        // the close). Equality counts as inside on both edges, matching
        // `isWithinNight`'s `offset <= windowLength`.
        let startDay = nowMinute >= start ? now : calendar.date(byAdding: .day, value: -1, to: now)
        let endDay = end >= nowMinute ? now : calendar.date(byAdding: .day, value: 1, to: now)
        guard let startDay, let endDay,
              let windowStart = ScheduleEngine.materialize(minuteOfDay: start, on: startDay, calendar: calendar),
              let windowEnd = ScheduleEngine.materialize(minuteOfDay: end, on: endDay, calendar: calendar)
        else { return nil }
        return (windowStart, windowEnd)
    }

    /// The feed that started tonight: the earliest live feed inside the window
    /// so far. Nil until the first nighttime bottle is logged.
    var anchor: FeedEvent? {
        guard let window = currentWindow else { return nil }
        return feeds
            .filter { $0.deletedAt == nil && $0.timestamp >= window.start && $0.timestamp <= now }
            .min { ($0.timestamp, $0.id.uuidString) < ($1.timestamp, $1.id.uuidString) }
    }

    // MARK: Slot construction

    /// Anchor + k·spacing until the window closes (inclusive — a feed landing
    /// exactly at night's end still belongs to the night). Elapsed-time steps,
    /// not wall-clock: "every 4 hours" stays 4 real hours across a DST shift.
    /// Garbage spacing (below the generator's minimum) yields just the anchor
    /// slot instead of looping the night away.
    static func slotTimes(anchor: Date, windowEnd: Date, spacingMinutes: Int) -> [Date] {
        guard spacingMinutes >= NightScheduleGenerator.minimumSpacingMinutes else { return [anchor] }
        var times: [Date] = []
        var t = anchor
        while t <= windowEnd, times.count < NightScheduleGenerator.maxSlots {
            times.append(t)
            t = t.addingTimeInterval(TimeInterval(spacingMinutes * 60))
        }
        return times
    }

    /// Slot i's parent: alternating through the roster starting from whoever
    /// logged the anchor. No rotation, a solo roster, or an anchor logged by
    /// someone off the roster (a removed caregiver) leaves every slot
    /// unassigned — and an unassigned slot rings BOTH phones, the deliberate
    /// fail-open this app uses whenever it can't prove whose night it is.
    private func rotationAssignees(count: Int, anchorLoggerID: UUID) -> [Parent?] {
        guard rotation == .alternating, parents.count >= 2,
              let anchorIndex = parents.firstIndex(where: { $0.id == anchorLoggerID })
        else { return Array(repeating: nil, count: count) }
        return (0..<count).map { parents[(anchorIndex + $0) % parents.count] }
    }

    /// Greedy nearest-pair fulfillment against the live feed log — same rule as
    /// `ScheduleEngine`: each logged bottle covers at most one slot, resolved in
    /// a deterministic order so both phones agree.
    private func fulfillment(times: [Date]) -> [Int: UUID] {
        let live = feeds.filter { $0.deletedAt == nil }
        struct Pair { let distance: TimeInterval; let index: Int; let eventID: UUID }
        var pairs: [Pair] = []
        for (index, date) in times.enumerated() {
            for feed in live {
                let distance = abs(feed.timestamp.timeIntervalSince(date))
                if distance <= ScheduleEngine.fulfillmentWindow {
                    pairs.append(Pair(distance: distance, index: index, eventID: feed.id))
                }
            }
        }
        var fulfilled: [Int: UUID] = [:]
        var usedEvents = Set<UUID>()
        for pair in pairs.sorted(by: {
            ($0.distance, times[$0.index], $0.eventID.uuidString)
                < ($1.distance, times[$1.index], $1.eventID.uuidString)
        }) {
            guard fulfilled[pair.index] == nil, !usedEvents.contains(pair.eventID) else { continue }
            fulfilled[pair.index] = pair.eventID
            usedEvents.insert(pair.eventID)
        }
        return fulfilled
    }

    // MARK: Helpers

    /// Stable synthetic id for a dynamic occurrence's `slotID` (no PlanSlot
    /// backs it). Deterministic across phones and recomputations so reminder
    /// request ids stay stable: "D1D10000-0000-4000-80II-0000DDDDDDDD".
    static func syntheticSlotID(nightKey: Int, index: Int) -> UUID {
        UUID(uuidString: String(format: "D1D10000-0000-4000-80%02d-0000%08d",
                                index % 100, nightKey)) ?? UUID()
    }

    private func minuteOfDay(_ date: Date) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func wrap(_ minute: Int) -> Int {
        ((minute % 1440) + 1440) % 1440
    }
}
