import Foundation

/// Pure computation of tonight's dynamic feed schedule. Unlike the standing
/// `PlanSlot` plan (sleep-only), night feeds have no stored slots: the
/// schedule *constructs itself* each night from the shared config plus the
/// feed log.
///
/// **The anchor.** The night starts at its first feed — logged when one
/// exists, otherwise *projected*: chain forward from the last logged feed by
/// the daytime target interval, and the first step that lands inside the
/// night window is tonight's first bottle. (Day interval 3h, night 9pm–8am,
/// last feed 5:30pm → 8:30pm falls outside the window, 11:30pm falls inside
/// → the night runs 11:30, then by the night spacing: 3:30, 7:30.) Once a
/// real feed lands inside the window, it replaces the projection as the
/// anchor. Later slots are anchor + k·night-spacing until the window closes.
///
/// **Assignment.** Slots alternate through the active parents starting from
/// the configured first-shift parent (`SharedSettings.nightFirstShiftID`;
/// nil = the first parent in join order), and any single night slot can be
/// overridden — swapped or skipped — via the same synced `PlanOverride`
/// records the standing plan uses, keyed on the slot's deterministic
/// synthetic id.
///
/// Nothing per-night is stored; both phones derive the identical schedule.
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
        case waiting(windowStart: Date, windowEnd: Date)  // night's on but no feed exists to build from
        case active([ScheduleOccurrence])                 // the constructed schedule
    }

    let nightStartMinute: Int          // 0..<1440 wall clock, same convention as SharedSettings
    let nightEndMinute: Int
    let spacingMinutes: Int            // between night feeds
    let dayIntervalMinutes: Int        // daytime target interval — drives the anchor projection
    let rotation: NightRotation
    /// Who takes the first shift; nil = the first parent in `parents`.
    let firstShiftID: UUID?
    /// Active participants in join order — the rotation order both phones agree on.
    let parents: [Parent]
    let feeds: [FeedEvent]
    /// Per-night swap/skip records (shared with the standing plan). Matched by
    /// the dynamic slot's synthetic id + the night's key.
    let overrides: [PlanOverride]
    var calendar: Calendar = .current
    var now: Date = .now

    /// Below this the day interval is garbage input — no projection.
    static let minimumDayIntervalMinutes = 30
    /// Backstop on the projection chain (a 30-minute rhythm across a full day
    /// is 48 steps; anything past this is a bug, not a baby).
    static let maxProjectionSteps = 96

    // MARK: Public API

    var state: State {
        guard let window = currentWindow else { return .day }
        guard anchorDate(in: window) != nil else {
            return .waiting(windowStart: window.start, windowEnd: window.end)
        }
        return .active(occurrences())
    }

    /// The night's constructed schedule, ascending — tonight's when `now` is
    /// inside the window, the *upcoming* night's when it isn't (so evening
    /// glances and alarms see "night starts 11:30" before 9pm). Empty when
    /// there's no feed to build from.
    func occurrences() -> [ScheduleOccurrence] {
        guard let window = relevantWindow, let anchor = anchorDate(in: window) else { return [] }
        let times = Self.slotTimes(anchor: anchor, windowEnd: window.end,
                                   spacingMinutes: spacingMinutes)
        let nightKey = ScheduleEngine.dayKey(for: window.start, calendar: calendar)
        let assignees = rotationAssignees(count: times.count)
        let liveOverrides = nightOverrides(nightKey: nightKey)
        let fulfilled = fulfillment(times: times, skippedIndices: Set(
            liveOverrides.filter { $0.value.isSkipped }.map(\.key)
        ))

        return times.enumerated().map { index, date in
            let override = liveOverrides[index]
            let status: ScheduleOccurrence.Status
            if override?.isSkipped == true {
                status = .skipped
            } else if let eventID = fulfilled[index] {
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
                // The NIGHT's key, not the slot date's calendar day: an
                // override must keep matching its slot even when a re-anchor
                // slides the time across midnight.
                dayKey: nightKey,
                status: status,
                assignedToID: override != nil ? override?.assignedToID : assignee?.id,
                assignedToName: override?.assignedToName ?? assignee?.name ?? "",
                assignedToColorHex: override?.assignedToColorHex ?? assignee?.colorHex ?? "",
                activeOverrideID: override?.id,
                overrideCreatedByID: override?.createdByID,
                source: .night
            )
        }
    }

    // MARK: Window resolution

    /// The night window containing `now`, or nil while it's daytime.
    /// Materialized on real days so DST resolves per `Calendar` policy — a
    /// zero-length window (start == end) is no window at all.
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

    /// The window the schedule should speak for right now: the one containing
    /// `now`, else the next one ahead — so the upcoming night is visible (and
    /// alarmable) all evening, not only once the window opens.
    var relevantWindow: (start: Date, end: Date)? {
        if let current = currentWindow { return current }
        let start = wrap(nightStartMinute)
        let end = wrap(nightEndMinute)
        guard start != end else { return nil }
        let startDay = minuteOfDay(now) < start ? now : calendar.date(byAdding: .day, value: 1, to: now)
        let endDay = (end > start ? startDay : startDay.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) })
        guard let startDay, let endDay,
              let windowStart = ScheduleEngine.materialize(minuteOfDay: start, on: startDay, calendar: calendar),
              let windowEnd = ScheduleEngine.materialize(minuteOfDay: end, on: endDay, calendar: calendar)
        else { return nil }
        return (windowStart, windowEnd)
    }

    // MARK: Anchor

    /// When the night's first feed is (or will be): the earliest live feed
    /// already logged inside the window, else the projection from the last
    /// logged feed. Nil when there's no feed at all to build from.
    private func anchorDate(in window: (start: Date, end: Date)) -> Date? {
        let live = feeds.filter { $0.deletedAt == nil && $0.timestamp <= now }
        if let logged = live
            .filter({ $0.timestamp >= window.start })
            .min(by: { ($0.timestamp, $0.id.uuidString) < ($1.timestamp, $1.id.uuidString) }) {
            return logged.timestamp
        }
        guard let last = live.max(by: { ($0.timestamp, $0.id.uuidString) < ($1.timestamp, $1.id.uuidString) })
        else { return nil }
        return Self.projectedAnchor(lastFeed: last.timestamp,
                                    dayIntervalMinutes: dayIntervalMinutes,
                                    windowStart: window.start, windowEnd: window.end)
    }

    /// Chains forward from the last feed by the daytime interval; the first
    /// step landing inside the window is the projected first night feed. (Fed
    /// 5:30pm, every 3h, night 9pm–8am → 8:30 is out, 11:30 is in → 11:30.)
    /// Nil when the interval is garbage or the chain skips the whole window
    /// (interval longer than the window — configuration, not a schedule).
    static func projectedAnchor(lastFeed: Date, dayIntervalMinutes: Int,
                                windowStart: Date, windowEnd: Date) -> Date? {
        guard dayIntervalMinutes >= minimumDayIntervalMinutes else { return nil }
        let step = TimeInterval(dayIntervalMinutes * 60)
        var t = lastFeed
        for _ in 0..<maxProjectionSteps {
            t = t.addingTimeInterval(step)
            if t > windowEnd { return nil }
            if t >= windowStart { return t }
        }
        return nil
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

    // MARK: Assignment

    /// Slot i's parent: alternating through the roster starting from the
    /// configured first-shift parent (nil, or an id that left the roster,
    /// starts from the first parent in join order — deterministic on both
    /// phones). No rotation or a solo roster leaves every slot unassigned —
    /// and an unassigned slot rings BOTH phones, the deliberate fail-open
    /// this app uses whenever nobody owns a night.
    private func rotationAssignees(count: Int) -> [Parent?] {
        guard rotation == .alternating, parents.count >= 2 else {
            return Array(repeating: nil, count: count)
        }
        let firstIndex = firstShiftID.flatMap { id in parents.firstIndex { $0.id == id } } ?? 0
        return (0..<count).map { parents[(firstIndex + $0) % parents.count] }
    }

    /// The winning live override per slot index for this night. Concurrent
    /// overrides land as separate records; pick a deterministic winner so
    /// both phones agree (same rule as `ScheduleEngine`).
    private func nightOverrides(nightKey: Int) -> [Int: PlanOverride] {
        var winners: [Int: PlanOverride] = [:]
        for index in 0..<NightScheduleGenerator.maxSlots {
            let slotID = Self.syntheticSlotID(nightKey: nightKey, index: index)
            let winner = overrides
                .filter { $0.deletedAt == nil && $0.slotID == slotID && $0.dayKey == nightKey }
                .max { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
            if let winner { winners[index] = winner }
        }
        return winners
    }

    /// Greedy nearest-pair fulfillment against the live feed log — same rule as
    /// `ScheduleEngine`: each logged bottle covers at most one slot, resolved in
    /// a deterministic order so both phones agree. Skipped slots don't match.
    private func fulfillment(times: [Date], skippedIndices: Set<Int>) -> [Int: UUID] {
        let live = feeds.filter { $0.deletedAt == nil }
        struct Pair { let distance: TimeInterval; let index: Int; let eventID: UUID }
        var pairs: [Pair] = []
        for (index, date) in times.enumerated() where !skippedIndices.contains(index) {
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
    /// backs it). Deterministic across phones and recomputations so per-night
    /// overrides and reminder request ids stay attached to "tonight's Nth
    /// feed" even when a re-anchor shifts its time:
    /// "D1D10000-0000-4000-80II-0000DDDDDDDD".
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
