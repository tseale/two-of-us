import Foundation

/// One concrete instance on the upcoming schedule — a standing `PlanSlot`
/// materialized onto a real day (with any per-night override applied), or a
/// transient prediction derived from the log. Predictions are never persisted:
/// both phones sync identical inputs, so both derive identical predictions,
/// and only human decisions (pin / assign / swap / skip) become records.
struct ScheduleOccurrence: Identifiable, Equatable {
    enum Source: Equatable {
        case pinned(slotID: UUID)
        case predicted
    }
    enum Status: Equatable {
        case upcoming
        case fulfilled(byEventID: UUID)   // a logged event near the slot time covered it
        case overdue                      // past, unfulfilled, not skipped
        case skipped                      // per-night skip override
    }

    let id: String                        // stable: "slot.<slotID>.<dayKey>" / "pred.<kind>.<k>"
    let kind: EventKind                   // .feed or .sleep only
    let date: Date
    let dayKey: Int                       // key for creating a same-night override
    let source: Source
    let status: Status
    let assignedToID: UUID?
    let assignedToName: String
    let assignedToColorHex: String
    let activeOverrideID: UUID?           // non-nil when a live override applied (drives "swapped" + undo)
    let overrideCreatedByID: UUID?        // who made tonight's swap

    var isPinned: Bool { if case .pinned = source { return true }; return false }
    var slotID: UUID? { if case let .pinned(id) = source { return id }; return nil }
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
    let targetFeedInterval: TimeInterval  // from SharedSettings; <= 0 disables feed predictions
    var calendar: Calendar = .current
    var now: Date = .now

    /// A logged event within this distance of a slot time counts as "that feed".
    static let fulfillmentWindow: TimeInterval = 45 * 60
    /// Unfulfilled past occurrences linger this long as "overdue", then drop.
    static let overdueGrace: TimeInterval = 90 * 60
    /// Predictions this close to a pinned occurrence of the same kind are
    /// suppressed — the pinned plan wins.
    static let predictionMergeWindow: TimeInterval = 60 * 60

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
        let pinned = materializedPinned(from: matchStart, to: windowEnd)
        var result = pinned.filter { $0.date >= windowStart }
        result += feedPredictions(until: windowEnd, pinned: pinned)
        result += sleepPrediction(until: windowEnd, pinned: pinned)
        return result.sorted { $0.date < $1.date }
    }

    /// Upcoming pinned occurrences assigned to one parent — the reminder
    /// planner's input (each device passes its own `myParticipantID`).
    func upcomingAssigned(to participantID: UUID,
                          horizon: TimeInterval = 12 * 3600) -> [ScheduleOccurrence] {
        occurrences(lookback: 0, horizon: horizon)
            .filter { $0.isPinned && $0.status == .upcoming && $0.assignedToID == participantID }
    }

    /// True when a pinned, upcoming occurrence of `kind` within `window` of
    /// `date` is assigned to a participant other than `me` — i.e. the schedule
    /// says that moment is somebody else's, so this device's generic reminders
    /// should stay dark. Biases toward reminding: an unknown local identity, an
    /// unassigned slot, or no nearby slot all return false (keep the reminder) —
    /// a phone that can't prove the night belongs to the other parent must
    /// never silently skip a feed alarm.
    func assignedElsewhere(near date: Date, kind: EventKind, me: UUID?,
                           window: TimeInterval = 30 * 60) -> Bool {
        guard let me else { return false }
        let horizon = max(3600, date.timeIntervalSince(now) + window)
        return occurrences(lookback: 0, horizon: horizon).contains {
            $0.isPinned && $0.kind == kind && $0.status == .upcoming
                && $0.assignedToID != nil && $0.assignedToID != me
                && abs($0.date.timeIntervalSince(date)) <= window
        }
    }

    // MARK: Helpers shared with the store/UI

    /// yyyymmdd of the local calendar day `date` falls on — the override key.
    /// Computed from the same materialized instant the occurrence uses, so
    /// creation and lookup can never disagree about "which night" 3am is.
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
            let date: Date
            let dayKey: Int
            let override: PlanOverride?
        }
        var instances: [Instance] = []
        var day = calendar.startOfDay(for: windowStart)
        while day <= windowEnd {
            for slot in liveSlots {
                guard let date = Self.materialize(minuteOfDay: slot.minuteOfDay, on: day, calendar: calendar),
                      date >= windowStart, date <= windowEnd else { continue }
                let key = Self.dayKey(for: date, calendar: calendar)
                // Concurrent swaps land as separate records; pick a
                // deterministic winner so both phones agree.
                let winner = liveOverrides
                    .filter { $0.slotID == slot.id && $0.dayKey == key }
                    .max { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
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
            let status: ScheduleOccurrence.Status
            if instance.override?.isSkipped == true {
                status = .skipped
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
                kind: instance.slot.kind,
                date: instance.date,
                dayKey: instance.dayKey,
                source: .pinned(slotID: instance.slot.id),
                status: status,
                assignedToID: override != nil ? override?.assignedToID : instance.slot.assignedToID,
                assignedToName: override?.assignedToName ?? instance.slot.assignedToName,
                assignedToColorHex: override?.assignedToColorHex ?? instance.slot.assignedToColorHex,
                activeOverrideID: override?.id,
                overrideCreatedByID: override?.createdByID
            )
        }
    }

    // MARK: Predictions (transient, future-only, always unassigned)

    /// Projects `lastFeed + k·interval` — deliberately the same arithmetic as
    /// Home's `feedHint` and the next-feed widget gauge, so every surface names
    /// the same time. Future-only: "the feed is due *now*" is Home's urgency
    /// language, not a schedule row.
    private func feedPredictions(until windowEnd: Date, pinned: [ScheduleOccurrence]) -> [ScheduleOccurrence] {
        guard targetFeedInterval > 0,
              let lastFeed = feeds.filter({ $0.deletedAt == nil }).map(\.timestamp).max()
        else { return [] }
        // Start at the first multiple after `now` — a days-stale last feed must
        // not spend the iteration budget walking through past intervals.
        let elapsed = now.timeIntervalSince(lastFeed)
        var k = max(1, Int(floor(elapsed / targetFeedInterval)) + 1)
        let maxK = k + 32   // bounds a tiny interval; real horizons need far fewer
        var result: [ScheduleOccurrence] = []
        while k < maxK {
            let date = lastFeed.addingTimeInterval(Double(k) * targetFeedInterval)
            if date > windowEnd { break }
            defer { k += 1 }
            guard date > now else { continue }
            if nearPinned(date, kind: .feed, in: pinned) { continue }
            result.append(prediction(kind: .feed, date: date, id: "pred.feed.\(k)"))
        }
        return result
    }

    /// One expected next sleep: `lastWake + UrgencyDefaults.sleep`. Silent while
    /// a sleep is running or when the plan already pins one nearby.
    private func sleepPrediction(until windowEnd: Date, pinned: [ScheduleOccurrence]) -> [ScheduleOccurrence] {
        let liveSleeps = sleeps.filter { $0.deletedAt == nil }
        guard !liveSleeps.contains(where: { $0.endedAt == nil }),
              let lastWake = liveSleeps.compactMap(\.endedAt).max()
        else { return [] }
        let date = lastWake.addingTimeInterval(UrgencyDefaults.sleep)
        guard date > now, date <= windowEnd, !nearPinned(date, kind: .sleep, in: pinned) else { return [] }
        return [prediction(kind: .sleep, date: date, id: "pred.sleep.1")]
    }

    private func nearPinned(_ date: Date, kind: EventKind, in pinned: [ScheduleOccurrence]) -> Bool {
        pinned.contains {
            $0.kind == kind && abs($0.date.timeIntervalSince(date)) <= Self.predictionMergeWindow
        }
    }

    private func prediction(kind: EventKind, date: Date, id: String) -> ScheduleOccurrence {
        ScheduleOccurrence(
            id: id, kind: kind, date: date,
            dayKey: Self.dayKey(for: date, calendar: calendar),
            source: .predicted, status: .upcoming,
            assignedToID: nil, assignedToName: "", assignedToColorHex: "",
            activeOverrideID: nil, overrideCreatedByID: nil
        )
    }
}
