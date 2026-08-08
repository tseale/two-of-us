import Foundation

/// Pure computation of tonight's dynamic feed schedule. Unlike the standing
/// `PlanSlot` plan (sleep-only), night feeds have no stored slots: the
/// schedule *constructs itself* each night from the shared config plus the
/// feed log.
///
/// **The anchor.** The night starts at its first feed, resolved in order:
/// 0. A MANUAL first-feed time set by a parent for tonight ("Move tonight…"
///    on the night's first row) — a live `PlanOverride` on the night's first
///    slot carrying `minuteOfDayOverride`. Explicitly re-timing the night is
///    the strongest signal there is, so it beats even a logged feed (the
///    correction case: a stray 9:05pm top-up anchored the night, but the
///    parents say the real night starts at 10). Undoing the change restores
///    the computed anchor.
/// 1. A logged feed inside the window — or up to an hour BEFORE it opens
///    (`preWindowGraceMinutes`): an 8:15pm bottle against a 9pm window IS the
///    night's first feed, and the schedule builds from it (8:15 → 12:15 →
///    4:15 → 8:15am — the night keeps its full length, so starting early
///    extends the far end by the same lead).
/// 2. Otherwise *projected*: the last logged feed plus the NIGHT spacing —
///    the interval the schedule itself runs on. When that predicted bottle
///    lands inside the window, it is tonight's first feed. (Night 11pm–8am
///    every 4h, last feed 7:45pm → 11:45pm falls inside → the night runs
///    11:45, 3:45, 7:45.)
/// 3. No feeds to build from, or a prediction that misses the window →
///    the window's start itself is the default first feed (11pm–8am → 11pm).
/// Later slots are anchor + k·night-spacing until the (lead-extended) window
/// closes.
///
/// **Assignment.** The standing sleep windows decide first: a bottle that
/// lands while exactly one parent is planned-asleep goes to the one who's
/// awake. Where the windows don't decide (nobody asleep, everybody asleep,
/// no windows), slots alternate through the active parents starting from
/// the configured first-shift parent (`SharedSettings.nightFirstShiftID`;
/// nil = the first parent in join order). Any single night slot can still be
/// overridden — swapped or skipped — via the same synced `PlanOverride`
/// records the standing plan uses, keyed on the slot's deterministic
/// synthetic id, and an override beats windows and rotation alike.
///
/// Nothing per-night is stored; both phones derive the identical schedule.
/// Sibling of `ScheduleEngine`/`StatsEngine`: no store access, no side
/// effects — callers pass fetched arrays, tests pass fixtures with a pinned
/// calendar and `now`.
/// A parent's standing nightly sleep window, reduced to pure wall-clock terms —
/// the shape `NightSchedule` routes feeds around. Built from a `.sleep`
/// `PlanSlot` that carries an end minute and an assignee; legacy put-down
/// slots and unassigned windows reduce to nothing.
struct SleepWindow: Equatable {
    let parentID: UUID
    let startMinute: Int          // 0..<1440 wall clock
    let durationMinutes: Int      // 1...1439, wrapping midnight

    init(parentID: UUID, startMinute: Int, durationMinutes: Int) {
        self.parentID = parentID
        self.startMinute = startMinute
        self.durationMinutes = durationMinutes
    }

    init?(slot: PlanSlot) {
        guard slot.deletedAt == nil,
              let parentID = slot.assignedToID,
              let duration = slot.windowDurationMinutes else { return nil }
        self.init(parentID: parentID, startMinute: slot.minuteOfDay, durationMinutes: duration)
    }

    /// Whether a wall-clock minute falls inside the window, wrap included:
    /// a 22:00–03:00 window contains 23:30 and 01:00, not 12:00.
    func contains(minuteOfDay minute: Int) -> Bool {
        let offset = (((minute - startMinute) % 1440) + 1440) % 1440
        return offset < durationMinutes
    }
}

struct NightSchedule {
    /// Minimal parent identity the rotation needs, decoupled from SwiftData.
    struct Parent: Equatable {
        let id: UUID
        let name: String
        let colorHex: String
    }

    /// Where tonight stands, for the Home card. There is no "waiting" state:
    /// the anchor always resolves (worst case, the window's start), so a
    /// night in progress always has a schedule.
    enum State: Equatable {
        case day                                          // daytime — the night isn't near yet
        case approaching([ScheduleOccurrence])            // window not open, but the next bottle is a night bottle
        case active([ScheduleOccurrence])                 // now is inside the window
    }

    let nightStartMinute: Int          // 0..<1440 wall clock, same convention as SharedSettings
    let nightEndMinute: Int
    let spacingMinutes: Int            // between night feeds — also drives the anchor projection
    let rotation: NightRotation
    /// Who takes the first shift; nil = the first parent in `parents`.
    let firstShiftID: UUID?
    /// Active participants in join order — the rotation order both phones agree on.
    let parents: [Parent]
    let feeds: [FeedEvent]
    /// Per-night swap/skip records (shared with the standing plan). Matched by
    /// the dynamic slot's synthetic id + the night's key.
    let overrides: [PlanOverride]
    /// The parents' standing sleep windows. When a feed lands during exactly
    /// one parent's sleep, it's assigned to the parent who's awake — the
    /// sleeping phone stays dark. Empty = pure rotation, the old behavior.
    var sleepWindows: [SleepWindow] = []
    var calendar: Calendar = .current
    var now: Date = .now

    /// A feed this close BEFORE the window opens still counts as the night's
    /// first bottle — an 8:15pm feed against a 9pm window starts the night.
    static let preWindowGraceMinutes = 60

    // MARK: Public API

    var state: State {
        if currentWindow != nil { return .active(occurrences()) }
        guard let window = relevantWindow else { return .day }
        // The night is *approaching* — surface the Tonight card early — once
        // the next predicted bottle is already a night bottle (the projected
        // anchor resolves), once we're inside the grace hour before the
        // window opens (which is also when a grace-logged feed can anchor),
        // or once a parent has manually set tonight's first feed.
        let graceStart = window.start.addingTimeInterval(
            -TimeInterval(Self.preWindowGraceMinutes * 60))
        let predictsIn = lastLiveFeed.map {
            Self.projectedAnchor(lastFeed: $0, spacingMinutes: spacingMinutes,
                                 windowStart: window.start, windowEnd: window.end) != nil
        } ?? false
        let manualSet = manualAnchor(in: window) != nil
        return (now >= graceStart || predictsIn || manualSet)
            ? .approaching(occurrences()) : .day
    }

    /// The night's constructed schedule, ascending — tonight's when `now` is
    /// inside the window, the *upcoming* night's when it isn't (so evening
    /// glances and alarms see "night starts 11:30" before 9pm).
    func occurrences() -> [ScheduleOccurrence] {
        guard let window = relevantWindow else { return [] }
        let anchor = anchorDate(in: window)
        // A grace anchor starts the night early; the far end extends by the
        // same lead so the night keeps its full length (8:15pm against a
        // 9pm–8am window runs through 8:15am).
        let lead = max(0, window.start.timeIntervalSince(anchor))
        let times = Self.slotTimes(anchor: anchor,
                                   windowEnd: window.end.addingTimeInterval(lead),
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
            // Sleep windows outrank the rotation: the parent who's awake at
            // this bottle's time takes it. A per-night override still beats
            // both (applied below, same as always).
            let assignee = awakeParent(at: date) ?? assignees[index]
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

    /// When the night's first feed is (or will be): a parent's manual choice
    /// first, else the earliest live feed already logged inside the window —
    /// or within the pre-window grace hour before it — else the projection
    /// from the last logged feed, else the window's start itself (a night
    /// always has a schedule).
    private func anchorDate(in window: (start: Date, end: Date)) -> Date {
        if let manual = manualAnchor(in: window) {
            return manual
        }
        let live = feeds.filter { $0.deletedAt == nil && $0.timestamp <= now }
        let graceStart = window.start.addingTimeInterval(
            -TimeInterval(Self.preWindowGraceMinutes * 60))
        if let logged = live
            .filter({ $0.timestamp >= graceStart && $0.timestamp <= window.end })
            .min(by: { ($0.timestamp, $0.id.uuidString) < ($1.timestamp, $1.id.uuidString) }) {
            return logged.timestamp
        }
        if let last = lastLiveFeed,
           let projected = Self.projectedAnchor(lastFeed: last, spacingMinutes: spacingMinutes,
                                                windowStart: window.start, windowEnd: window.end) {
            return projected
        }
        return window.start
    }

    /// The manually set first-feed time for this window's night, if a live
    /// move override exists on the night's FIRST slot. The stored wall-clock
    /// minute materializes on the window's opening day, rolling forward a day
    /// for small-hours times (1:30am belongs to tomorrow morning); a time
    /// that lands outside the window (and its grace hour) is ignored rather
    /// than generating a nonsense night.
    private func manualAnchor(in window: (start: Date, end: Date)) -> Date? {
        let nightKey = ScheduleEngine.dayKey(for: window.start, calendar: calendar)
        guard let override = nightOverrides(nightKey: nightKey)[0],
              !override.isSkipped,
              let minute = override.minuteOfDayOverride,
              var candidate = ScheduleEngine.materialize(minuteOfDay: minute, on: window.start,
                                                         calendar: calendar)
        else { return nil }
        let graceStart = window.start.addingTimeInterval(
            -TimeInterval(Self.preWindowGraceMinutes * 60))
        if candidate < graceStart,
           let rolled = calendar.date(byAdding: .day, value: 1, to: candidate) {
            candidate = rolled
        }
        guard candidate >= graceStart, candidate <= window.end else { return nil }
        return candidate
    }

    /// Most recent live feed at or before `now` — the one predictions build on.
    private var lastLiveFeed: Date? {
        feeds.filter { $0.deletedAt == nil && $0.timestamp <= now }
            .max { ($0.timestamp, $0.id.uuidString) < ($1.timestamp, $1.id.uuidString) }?
            .timestamp
    }

    /// The last feed plus the night spacing — when that predicted bottle lands
    /// inside the window, it IS the night's first feed. (Night 11pm–8am every
    /// 4h, fed 7:45pm → 11:45pm is inside → 11:45.) Nil when the spacing is
    /// garbage or the prediction misses the window (too early — a real daytime
    /// feed will re-project — or past its end): the window-start default takes
    /// over.
    static func projectedAnchor(lastFeed: Date, spacingMinutes: Int,
                                windowStart: Date, windowEnd: Date) -> Date? {
        guard spacingMinutes >= NightScheduleGenerator.minimumSpacingMinutes else { return nil }
        let predicted = lastFeed.addingTimeInterval(TimeInterval(spacingMinutes * 60))
        return (predicted >= windowStart && predicted <= windowEnd) ? predicted : nil
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

    /// The sole awake parent at `date` per the standing sleep windows, or nil
    /// when the windows don't decide it — nobody's asleep then, everybody is,
    /// or the roster is solo. Nil falls back to the rotation (and ultimately
    /// to unassigned, which rings BOTH phones — the fail-open stands whenever
    /// the plan can't name one on-duty parent).
    private func awakeParent(at date: Date) -> Parent? {
        guard !sleepWindows.isEmpty, parents.count >= 2 else { return nil }
        let minute = minuteOfDay(date)
        let awake = parents.filter { parent in
            !sleepWindows.contains { $0.parentID == parent.id && $0.contains(minuteOfDay: minute) }
        }
        return awake.count == 1 ? awake.first : nil
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

extension NightSchedule {
    /// Builds tonight's engine from app models. Participants are filtered and
    /// ordered here (active, join order) so every call site — the phones AND
    /// the watch complication — derives the same rotation both phones agree on.
    init(settings: SharedSettings, participants: [Participant], feeds: [FeedEvent],
         overrides: [PlanOverride] = [], sleepSlots: [PlanSlot] = [],
         calendar: Calendar = .current, now: Date = .now) {
        self.init(
            nightStartMinute: settings.nightStartMinute,
            nightEndMinute: settings.nightEndMinute,
            spacingMinutes: settings.nightFeedSpacingMinutes,
            rotation: settings.nightRotation,
            firstShiftID: settings.nightFirstShiftID,
            parents: participants
                .filter(\.isActive)
                .sorted { ($0.invitedAt, $0.id.uuidString) < ($1.invitedAt, $1.id.uuidString) }
                .map { Parent(id: $0.id, name: $0.displayName, colorHex: $0.colorHex) },
            feeds: feeds,
            overrides: overrides,
            sleepWindows: sleepSlots.compactMap(SleepWindow.init),
            calendar: calendar,
            now: now
        )
    }
}
