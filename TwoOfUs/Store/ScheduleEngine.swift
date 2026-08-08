import Foundation

/// One concrete instance on the upcoming schedule — a standing `PlanSlot`
/// materialized onto a real day, with any per-night override (swap / skip /
/// move) applied. Every row is parent-authored: the schedule shows exactly
/// what was defined, nothing derived (log-based predictions were removed
/// 2026-07-25 — the plan is manual by design, and every row is editable).
struct ScheduleOccurrence: Identifiable, Equatable {
    enum Status: Equatable {
        case upcoming
        case fulfilled(byEventID: UUID)   // a logged event near the slot time covered it
        case overdue                      // past, unfulfilled, not skipped
        case skipped                      // per-night skip override
    }

    /// Where the occurrence came from — a standing `PlanSlot` (editable via
    /// overrides) or tonight's dynamic feed schedule (`NightSchedule`,
    /// computed, backed by no slot — its `slotID` is synthetic).
    enum Source: Equatable {
        case slot
        case night
    }

    let id: String                        // stable: "slot.<slotID>.<dayKey>" / "night.<nightKey>.<index>"
    let slotID: UUID                      // → the standing PlanSlot (synthetic for .night)
    let kind: EventKind                   // .feed or .sleep only
    let date: Date                        // override-adjusted (a moved night reflects its moved time)
    let dayKey: Int                       // keyed to the STANDING time's day, so lookup and undo agree
    let status: Status
    let assignedToID: UUID?
    let assignedToName: String
    let assignedToColorHex: String
    let activeOverrideID: UUID?           // non-nil when a live override applied (drives "changed" + undo)
    let overrideCreatedByID: UUID?        // who made tonight's change
    /// Non-nil makes this a SPAN — a parent's sleep window from `date` to
    /// `endDate` — rather than an instant. Spans never ring, remind, or match
    /// logged events; they exist to be seen (and swapped) on the timeline.
    var endDate: Date? = nil
    var source: Source = .slot
}

/// Pure merge of the standing plan, per-night overrides, and the event log into
/// a single upcoming timeline. Sibling of `StatsEngine`: no store access, no
/// side effects — callers pass fetched arrays, tests pass fixtures with a
/// pinned calendar and `now`.
struct ScheduleEngine {
    let slots: [PlanSlot]
    let overrides: [PlanOverride]
    let feeds: [FeedEvent]
    let sleeps: [SleepEvent]
    var calendar: Calendar = .current
    var now: Date = .now

    /// A logged event within this distance of a slot time counts as "that feed".
    static let fulfillmentWindow: TimeInterval = 45 * 60
    /// Unfulfilled past occurrences linger this long as "overdue", then drop.
    static let overdueGrace: TimeInterval = 90 * 60

    // MARK: Public API

    /// Merged occurrences in `[now - lookback, now + horizon]`, ascending.
    func occurrences(lookback: TimeInterval = 2 * 3600,
                     horizon: TimeInterval = 24 * 3600) -> [ScheduleOccurrence] {
        let windowStart = now.addingTimeInterval(-lookback)
        let windowEnd = now.addingTimeInterval(horizon)
        // Fulfillment always matches against the same recent-past set no matter
        // the caller's lookback — otherwise a lookback-0 caller (the reminder
        // planner) and the 2h-lookback tab could disagree about which slot a
        // bottle covered. The display window only filters the OUTPUT.
        let matchStart = now.addingTimeInterval(-max(lookback, Self.overdueGrace + Self.fulfillmentWindow))
        return materializedPinned(from: matchStart, to: windowEnd)
            // A span still covering the display window stays visible: last
            // night's 10pm–7am sleep window is very much "the schedule" at
            // 2am, even with its start hours outside the lookback.
            .filter { ($0.endDate ?? $0.date) >= windowStart }
            .sorted { $0.date < $1.date }
    }

    /// Upcoming occurrences assigned to one parent — the reminder planner's
    /// input (each device passes its own `myParticipantID`). Spans (sleep
    /// windows) are excluded: nobody needs a wake-up call to go to bed.
    func upcomingAssigned(to participantID: UUID,
                          horizon: TimeInterval = 12 * 3600) -> [ScheduleOccurrence] {
        occurrences(lookback: 0, horizon: horizon)
            .filter { $0.status == .upcoming && $0.assignedToID == participantID && $0.endDate == nil }
    }

    /// Upcoming occurrences that should ring on `participantID`'s device: their
    /// own slots plus every unassigned one. Unassigned is the deliberate
    /// both-phones case — nobody claimed the 3am, so nobody gets to sleep
    /// through it silently. Only a slot pinned to the OTHER parent stays quiet
    /// here. Spans (sleep windows) never ring.
    func upcomingAlarmable(for participantID: UUID,
                           horizon: TimeInterval = 12 * 3600) -> [ScheduleOccurrence] {
        occurrences(lookback: 0, horizon: horizon)
            .filter {
                $0.status == .upcoming && $0.endDate == nil
                    && ($0.assignedToID == nil || $0.assignedToID == participantID)
            }
    }

    /// True when a live, upcoming occurrence of `kind` within `window` of
    /// `date` is assigned to a participant other than `me` — i.e. the schedule
    /// says that moment is somebody else's, so this device's generic reminders
    /// should stay dark. Biases toward reminding: an unknown local identity, an
    /// unassigned slot, or no nearby slot all return false (keep the reminder) —
    /// a phone that can't prove the night belongs to the other parent must
    /// never silently skip a feed alarm.
    func assignedElsewhere(near date: Date, kind: EventKind, me: UUID?,
                           window: TimeInterval = 30 * 60) -> Bool {
        let horizon = max(3600, date.timeIntervalSince(now) + window)
        return Self.assignedElsewhere(in: occurrences(lookback: 0, horizon: horizon),
                                      near: date, kind: kind, me: me, window: window)
    }

    /// Same test over an already-assembled occurrence list — used where the
    /// standing plan and the dynamic night schedule are merged (`QuickLogger`).
    static func assignedElsewhere(in occurrences: [ScheduleOccurrence], near date: Date,
                                  kind: EventKind, me: UUID?,
                                  window: TimeInterval = 30 * 60) -> Bool {
        guard let me else { return false }
        return occurrences.contains {
            $0.kind == kind && $0.status == .upcoming
                && $0.assignedToID != nil && $0.assignedToID != me
                && abs($0.date.timeIntervalSince(date)) <= window
        }
    }

    // MARK: Helpers shared with the store/UI

    /// yyyymmdd of the local calendar day `date` falls on — the override key.
    /// Computed from the STANDING materialized instant (never the moved one),
    /// so creation and lookup can never disagree about "which night" 3am is.
    static func dayKey(for date: Date, calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 0) * 10_000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    /// Concrete instant for a wall-clock slot time on a given day. DST-correct:
    /// a nonexistent spring-forward time resolves per `Calendar` policy (to the
    /// next valid instant) instead of drifting the way a stored Date would.
    static func materialize(minuteOfDay: Int, on day: Date, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60,
                      second: 0, of: calendar.startOfDay(for: day))
    }

    // MARK: Pinned slots

    private func materializedPinned(from windowStart: Date, to windowEnd: Date) -> [ScheduleOccurrence] {
        let liveSlots = slots.filter { $0.deletedAt == nil }
        guard !liveSlots.isEmpty else { return [] }
        let liveOverrides = overrides.filter { $0.deletedAt == nil }

        // Every (slot × day) instant inside the window, override applied.
        struct Instance {
            let slot: PlanSlot
            let date: Date                // override-adjusted (moved nights)
            let dayKey: Int               // from the STANDING instant
            let override: PlanOverride?
        }
        var instances: [Instance] = []
        // One day of extra reach-back so a window that STARTED before the
        // fetch window but is still running inside it (yesterday 10pm–7am,
        // now 2am) gets materialized; instants keep zero reach and fall to
        // the same guard as before.
        var day = calendar.date(byAdding: .day, value: -1,
                                to: calendar.startOfDay(for: windowStart))
            ?? calendar.startOfDay(for: windowStart)
        while day <= windowEnd {
            for slot in liveSlots {
                let reach = TimeInterval((slot.windowDurationMinutes ?? 0) * 60)
                guard let standing = Self.materialize(minuteOfDay: slot.minuteOfDay, on: day, calendar: calendar),
                      standing >= windowStart.addingTimeInterval(-reach), standing <= windowEnd else { continue }
                let key = Self.dayKey(for: standing, calendar: calendar)
                // Concurrent overrides land as separate records; pick a
                // deterministic winner so both phones agree.
                let winner = liveOverrides
                    .filter { $0.slotID == slot.id && $0.dayKey == key }
                    .max { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
                let date = movedDate(standing: standing, on: day, override: winner) ?? standing
                instances.append(Instance(slot: slot, date: date, dayKey: key, override: winner))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        // Greedy nearest-pair fulfillment: each logged event covers at most one
        // occurrence, so one 11:05pm bottle can't tick off two nearby slots.
        var fulfilledBy = [Int: UUID]()   // instance index → event id
        var usedEvents = Set<UUID>()
        struct Pair { let distance: TimeInterval; let instanceIndex: Int; let eventID: UUID }
        var pairs: [Pair] = []
        for (i, instance) in instances.enumerated() where !(instance.override?.isSkipped ?? false) {
            // Sleep WINDOWS (parent sleep) never match logged events — the
            // window is the parent's sleep, not the baby's, so a logged baby
            // sleep neither fulfills it nor makes it overdue. Legacy instant
            // sleep slots keep the old put-down matching.
            if instance.slot.windowDurationMinutes != nil { continue }
            let candidates: [(UUID, Date)] = switch instance.slot.kind {
            case .feed: feeds.filter { $0.deletedAt == nil }.map { ($0.id, $0.timestamp) }
            case .sleep: sleeps.filter { $0.deletedAt == nil }.map { ($0.id, $0.startedAt) }
            case .diaper: []
            }
            for (eventID, eventDate) in candidates {
                let distance = abs(eventDate.timeIntervalSince(instance.date))
                if distance <= Self.fulfillmentWindow {
                    pairs.append(Pair(distance: distance, instanceIndex: i, eventID: eventID))
                }
            }
        }
        // Deterministic order all the way down: distance, then occurrence time,
        // then event id — so both phones (and every call site, whatever order
        // its fetch returned) resolve an exact tie identically.
        for pair in pairs.sorted(by: {
            ($0.distance, instances[$0.instanceIndex].date, $0.eventID.uuidString)
                < ($1.distance, instances[$1.instanceIndex].date, $1.eventID.uuidString)
        }) {
            guard fulfilledBy[pair.instanceIndex] == nil, !usedEvents.contains(pair.eventID) else { continue }
            fulfilledBy[pair.instanceIndex] = pair.eventID
            usedEvents.insert(pair.eventID)
        }

        return instances.enumerated().compactMap { i, instance in
            // A moved window keeps its standing duration — shifting the start
            // shifts the whole night's sleep, it doesn't stretch it.
            let endDate = instance.slot.windowDurationMinutes.map {
                instance.date.addingTimeInterval(TimeInterval($0 * 60))
            }
            let status: ScheduleOccurrence.Status
            if instance.override?.isSkipped == true {
                status = .skipped
            } else if let endDate {
                // A window is "upcoming" until it fully ends (in progress
                // counts — it's still tonight's plan), then drops without an
                // overdue phase: sleep that already happened can't be late.
                guard endDate > now else { return nil }
                status = .upcoming
            } else if let eventID = fulfilledBy[i] {
                status = .fulfilled(byEventID: eventID)
            } else if instance.date < now {
                // Unfulfilled and past: show as overdue briefly, then drop —
                // a stale "was due 3am" row all morning helps no one.
                guard now.timeIntervalSince(instance.date) <= Self.overdueGrace else { return nil }
                status = .overdue
            } else {
                status = .upcoming
            }
            let override = instance.override
            return ScheduleOccurrence(
                id: "slot.\(instance.slot.id.uuidString).\(instance.dayKey)",
                slotID: instance.slot.id,
                kind: instance.slot.kind,
                date: instance.date,
                dayKey: instance.dayKey,
                status: status,
                assignedToID: override != nil ? override?.assignedToID : instance.slot.assignedToID,
                assignedToName: override?.assignedToName ?? instance.slot.assignedToName,
                assignedToColorHex: override?.assignedToColorHex ?? instance.slot.assignedToColorHex,
                activeOverrideID: override?.id,
                overrideCreatedByID: override?.createdByID,
                endDate: endDate
            )
        }
    }

    /// The moved instant for a night whose override carries a time change, or
    /// nil to keep the standing time. Wall-clock minutes materialize on the
    /// standing occurrence's day, then snap to the interpretation nearest the
    /// standing time — so moving an 11:30pm slot "to 12:15" means fifteen past
    /// midnight TONIGHT (45 minutes later), never this morning (23 hours ago).
    private func movedDate(standing: Date, on day: Date, override: PlanOverride?) -> Date? {
        guard let minute = override?.minuteOfDayOverride,
              var moved = Self.materialize(minuteOfDay: minute, on: day, calendar: calendar)
        else { return nil }
        let half: TimeInterval = 12 * 3600
        if moved.timeIntervalSince(standing) > half,
           let back = calendar.date(byAdding: .day, value: -1, to: moved) {
            moved = back
        } else if moved.timeIntervalSince(standing) < -half,
                  let forward = calendar.date(byAdding: .day, value: 1, to: moved) {
            moved = forward
        }
        return moved
    }
}
