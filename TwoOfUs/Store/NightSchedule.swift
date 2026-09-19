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
/// **Timing around sleep.** Before anyone is assigned, a bottle whose rhythm
/// time lands while BOTH parents are planned-asleep slides to the nearest
/// minute where one of them is already up — at most `maxAwakeShiftMinutes`,
/// and never more than half the spacing, so the night keeps its order and its
/// shape. A 3:27am bottle against a 2:30–3:00 get-up gap becomes 2:59: the
/// parent who's up anyway takes it, and nobody gets woken. Ties go earlier (a
/// bottle slightly early beats waking someone). The night's FIRST bottle never
/// moves — it's a logged feed, an explicit choice, or the window opening.
/// Every slide is off the grid, never off the previous slide, so one nudge
/// can't cascade through the night or change how many bottles there are.
///
/// **Assignment.** The standing sleep windows decide first: a bottle that
/// lands while exactly one parent is planned-asleep goes to the one who's
/// awake — and one that lands while BOTH are planned-asleep goes to the
/// parent whose planned wake-up comes soonest (their block was ending
/// anyway; the other's long stretch stays whole; back-to-back windows chain
/// into one block). Where the windows still don't decide (nobody asleep, a
/// dead tie, no windows), slots alternate through the active parents
/// starting from the configured first-shift parent (`SharedSettings.nightFirstShiftID`;
/// nil = the first parent in join order). Any single night slot can still be
/// overridden — swapped or skipped — via the same synced `PlanOverride`
/// records the standing plan uses, keyed on the slot's deterministic
/// synthetic id, and an override beats windows and rotation alike.
///
/// **What the night still owes you.** A slot matches a logged bottle within
/// `fulfillmentWindow` — half the night's own spacing, so "nearest slot wins"
/// — and nothing logged before the anchor matches at all. Past slots the night
/// has already run PAST read `.missed`, not `.overdue`: once a later bottle is
/// in, the ones behind it are settled, whether the baby stretched or nobody
/// logged them. Only the tail after the last logged bottle is still owed, and
/// only it stays red.
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
    /// The parents' standing sleep windows. A feed during one parent's sleep
    /// goes to the parent who's awake — the sleeping phone stays dark. A feed
    /// during BOTH parents' sleep goes to whoever's planned wake-up comes
    /// soonest. Empty = pure rotation, the old behavior.
    var sleepWindows: [SleepWindow] = []
    var calendar: Calendar = .current
    var now: Date = .now

    /// A feed this close BEFORE the window opens still counts as the night's
    /// first bottle — an 8:15pm feed against a 9pm window starts the night.
    static let preWindowGraceMinutes = 60
    /// How far a bottle may slide off the rhythm to land while a parent is
    /// already awake. Always within `fulfillmentWindow`, so a bottle logged at
    /// the un-slid rhythm time still ticks its slot off.
    static let maxAwakeShiftMinutes = 45

    /// How far a logged bottle may sit from a slot and still read as "that
    /// feed". The standing plan's flat 45 minutes is far too tight for a night
    /// that runs on hours: against a 2½h rhythm a 3:45am bottle is 70 minutes
    /// past the 2:35 slot and 80 minutes short of the next one — unmistakably
    /// the 2:35 — yet the fixed window left that slot reading "Overdue" all
    /// morning with the bottle attached to nothing.
    ///
    /// Two bounds, both floored at the standing plan's window so a tight night
    /// never matches less generously than the plan does:
    /// - **half the spacing**, so a bottle is never in reach of two slots it's
    ///   equally far from — "nearest slot wins", exactly;
    /// - **`ScheduleEngine.overdueGrace`**, the same 90 minutes a slot lingers
    ///   as overdue. A fulfilled slot goes quiet — no alarm, no reminder — and
    ///   a slot the night is still hours away from must not lose its ring
    ///   because of a bottle that plainly isn't its own.
    ///
    /// Every spacing the UI offers (2h–6h) keeps this at or above
    /// `maxAwakeShiftMinutes`, so a bottle logged at a slid slot's un-slid
    /// rhythm time still ticks it off.
    var fulfillmentWindow: TimeInterval {
        max(ScheduleEngine.fulfillmentWindow,
            min(ScheduleEngine.overdueGrace, TimeInterval(spacingMinutes * 60) / 2))
    }

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
        let rhythm = Self.slotTimes(anchor: anchor,
                                    windowEnd: window.end.addingTimeInterval(lead),
                                    spacingMinutes: spacingMinutes)
        // Bottles that would land while you're BOTH down slide to the nearest
        // minute one of you is up. The anchor stays put — it already happened,
        // or you set it.
        let times = rhythm.enumerated().map { index, date in
            index == 0 ? date : awakeShifted(date)
        }
        let nightKey = ScheduleEngine.dayKey(for: window.start, calendar: calendar)
        let assignees = rotationAssignees(count: times.count)
        let liveOverrides = nightOverrides(nightKey: nightKey)
        let fulfilled = fulfillment(times: times, anchor: anchor, skippedIndices: Set(
            liveOverrides.filter { $0.value.isSkipped }.map(\.key)
        ))
        // The night only owes you the bottles it hasn't run past. Once a LATER
        // bottle is logged, every unfulfilled slot behind it is settled — the
        // baby went longer, or it went unlogged, and nobody is going back at
        // 8am to mark the 12:05. Only the tail after the last logged bottle is
        // still genuinely outstanding, so only it stays red.
        let lastFulfilled = fulfilled.keys.max()

        return times.enumerated().map { index, date in
            let override = liveOverrides[index]
            let status: ScheduleOccurrence.Status
            if override?.isSkipped == true {
                status = .skipped
            } else if let eventID = fulfilled[index] {
                status = .fulfilled(byEventID: eventID)
            } else if date < now {
                status = index < (lastFulfilled ?? -1) ? .missed : .overdue
            } else {
                status = .upcoming
            }
            // Sleep windows outrank the rotation: the parent who's awake at
            // this bottle's time takes it — and when both are asleep, the
            // one whose planned wake-up comes soonest. A per-night override
            // still beats both (applied below, same as always).
            let assignee = onDutyParent(at: date) ?? assignees[index]
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
                source: .night,
                shiftedFrom: date == rhythm[index] ? nil : rhythm[index]
            )
        }
    }

    /// The standing plan's occurrences that belong to THIS night — `engine`'s
    /// output clipped to the window the feed schedule is speaking for.
    ///
    /// The standing plan repeats every day; a night schedule is exactly one
    /// night. Ask the engine for its default rolling 24 hours and the two stop
    /// describing the same thing: at 8:40am you get last night's bottles
    /// beside tonight's sleep windows AND tomorrow morning's, and the rail's
    /// wake cap lands on a "9:00 AM" a full day out. Clipping to the night's
    /// own bounds is what keeps one screen one night.
    ///
    /// Overlap, not containment: a 10pm–5am window belongs to an 11pm-start
    /// night, and one still running at dawn belongs to the night it started in.
    func planOccurrences(from engine: ScheduleEngine) -> [ScheduleOccurrence] {
        guard let window = relevantWindow else { return [] }
        return engine
            .occurrences(lookback: max(0, now.timeIntervalSince(window.start)),
                         horizon: max(0, window.end.timeIntervalSince(now)))
            .filter { ($0.endDate ?? $0.date) >= window.start && $0.date <= window.end }
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

    // MARK: Timing around sleep

    /// A bottle's time, slid to the nearest minute where at least one parent
    /// is planned-awake — but only when its rhythm time would land while
    /// they're BOTH down. Earlier wins ties: a bottle a few minutes early
    /// beats waking someone up. The budget is capped below half the spacing so
    /// slid slots can never cross or reorder. When nothing within the budget
    /// has anyone up (a long stretch you're both asleep for), the time stands
    /// and `onDutyParent` decides who gets woken — the plan doesn't pretend a
    /// gap exists.
    private func awakeShifted(_ date: Date) -> Date {
        guard !sleepWindows.isEmpty, parents.count >= 2 else { return date }
        let minute = minuteOfDay(date)
        guard !anyoneAwake(atMinute: minute) else { return date }
        let budget = min(Self.maxAwakeShiftMinutes, spacingMinutes / 2 - 1)
        guard budget >= 1 else { return date }
        for offset in 1...budget {
            if anyoneAwake(atMinute: wrap(minute - offset)) {
                return date.addingTimeInterval(TimeInterval(-offset * 60))
            }
            if anyoneAwake(atMinute: wrap(minute + offset)) {
                return date.addingTimeInterval(TimeInterval(offset * 60))
            }
        }
        return date
    }

    /// Whether any parent still on the roster is planned-awake at a wall-clock
    /// minute. A window belonging to someone who left decides nothing.
    private func anyoneAwake(atMinute minute: Int) -> Bool {
        parents.contains { parent in
            !sleepWindows.contains {
                $0.parentID == parent.id && $0.contains(minuteOfDay: minute)
            }
        }
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

    /// The parent on duty at `date` per the standing sleep windows, or nil
    /// when the windows don't decide it. Exactly one parent awake → them.
    /// Everybody asleep → the one whose planned wake-up comes soonest (their
    /// block was ending anyway; the other's long stretch stays whole) —
    /// unless it's a dead tie. Nobody asleep, a tie, or a solo roster → nil:
    /// the rotation stands (and ultimately unassigned rings BOTH phones —
    /// the fail-open holds whenever the plan can't name one on-duty parent).
    private func onDutyParent(at date: Date) -> Parent? {
        guard !sleepWindows.isEmpty, parents.count >= 2 else { return nil }
        let minute = minuteOfDay(date)
        let untilAwake = parents.map {
            (parent: $0, minutes: minutesUntilAwake(parentID: $0.id, atMinute: minute))
        }
        let awake = untilAwake.filter { $0.minutes == 0 }
        if awake.count == 1 { return awake.first?.parent }
        guard awake.isEmpty, let soonest = untilAwake.map(\.minutes).min() else { return nil }
        let candidates = untilAwake.filter { $0.minutes == soonest }
        return candidates.count == 1 ? candidates.first?.parent : nil
    }

    /// Minutes until `parentID` is next planned-awake at wall-clock `minute` —
    /// 0 means awake right now. Back-to-back and overlapping windows read as
    /// one unbroken block (a 3:00–5:30 nap chained to 5:30–7:00 is asleep
    /// until 7:00). Windows covering the whole clock cap at a full day, so
    /// that parent never wins "soonest awake" and the walk can't loop forever.
    private func minutesUntilAwake(parentID: UUID, atMinute minute: Int) -> Int {
        let windows = sleepWindows.filter { $0.parentID == parentID }
        var wake = minute
        var total = 0
        while total < 1440 {
            // The furthest end among windows covering the current minute;
            // `contains` guarantees each step is ≥ 1 minute, so the walk
            // always advances.
            let furthest = windows.filter { $0.contains(minuteOfDay: wake) }
                .map { $0.durationMinutes - wrap(wake - $0.startMinute) }
                .max()
            guard let furthest else { break }
            total += furthest
            wake = wrap(wake + furthest)
        }
        return min(total, 1440)
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
    /// `ScheduleEngine`, at this night's own `fulfillmentWindow` so a bottle
    /// that ran late still ticks off the slot it was late for: each logged
    /// bottle covers at most one slot, resolved in a deterministic order so
    /// both phones agree. Skipped slots don't match.
    ///
    /// Nothing logged before the anchor can match anything. The anchor IS the
    /// night's first bottle by construction, so an earlier feed is either
    /// daytime or one the anchor rules deliberately passed over — a stray 9:05
    /// top-up on a night the parents moved to 10 must not then tick the 10
    /// off. Without this the widened window would start reaching back into the
    /// evening.
    private func fulfillment(times: [Date], anchor: Date,
                             skippedIndices: Set<Int>) -> [Int: UUID] {
        let live = feeds.filter { $0.deletedAt == nil && $0.timestamp >= anchor }
        struct Pair { let distance: TimeInterval; let index: Int; let eventID: UUID }
        var pairs: [Pair] = []
        for (index, date) in times.enumerated() where !skippedIndices.contains(index) {
            for feed in live {
                let distance = abs(feed.timestamp.timeIntervalSince(date))
                if distance <= fulfillmentWindow {
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
    /// ordered here (active, unpaused, co-parents only, join order) so every
    /// call site — the phones AND the watch complication — derives the same
    /// rotation both phones agree on. Guests (`.logger` — grandma, a nanny, a
    /// pet added for photo-sharing) never take a night shift and never occupy
    /// a rotation slot; including them here would also corrupt sleep-window
    /// routing below, since a guest with no sleep window reads as permanently
    /// awake. A paused co-parent is dropped the same way — pausing must pull
    /// them out of the rotation immediately, not just future invites.
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
                .filter { $0.isActive && !$0.isPaused && $0.role == .full }
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
