import Foundation
import SwiftData
import WidgetKit
import os

/// Minimal write path used by App Intents (widget buttons + Siri/Shortcuts).
///
/// This mirrors the relevant parts of `EventStore`, but is intentionally
/// self-contained so it can compile into BOTH the app and the widget extension.
/// `EventStore` can't be shared into the widget target because it references the
/// app's `TimelineEntry` enum, whose name collides with WidgetKit's
/// `TimelineEntry` protocol inside the widget module.
///
/// Opens the App Group-shared SwiftData store directly (no CloudKit mirroring in
/// this process — only the main app drives sync; widget-process writes still
/// persist locally and the app's syncing container picks them up).
struct QuickLogger {
    // Local logger (not AppLog): this file also compiles into the widget and
    // notification-content extensions, which don't include AppLog.swift.
    private static let log = Logger(subsystem: "com.taylorseale.twoofus", category: "quicklogger")

    let context: ModelContext

    static func make() -> QuickLogger? {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config: ModelConfiguration
        // `cloudKitDatabase: .none` is required, not hygiene: this code also runs
        // in the APP process (reminder re-arming), whose iCloud entitlement would
        // otherwise flip the default `.automatic` into SwiftData's own CloudKit
        // mirroring — a second sync system fighting CKSyncEngine over one store.
        if let storeURL = AppGroup.storeURL {
            config = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        } else {
            // Fallback (Simulator without the App Group entitlement): cannot
            // actually share with the app, but keeps the intent functional.
            config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        }
        guard let container = try? ModelContainer(for: schema, configurations: [config]) else {
            return nil
        }
        return QuickLogger(context: ModelContext(container))
    }

    // MARK: Lookups

    private var baby: Baby? { try? context.fetch(FetchDescriptor<Baby>()).first }
    private var settings: SharedSettings? { try? context.fetch(FetchDescriptor<SharedSettings>()).first }

    /// The shared settings row, exposed for the app-side schedule assembly
    /// (`scheduleOccurrences` in ScheduleAssembly.swift).
    var sharedSettings: SharedSettings? { settings }

    /// Every participant — the schedule assembly filters/orders them itself so
    /// the rotation order matches the app's views exactly.
    var allParticipants: [Participant] {
        (try? context.fetch(FetchDescriptor<Participant>())) ?? []
    }

    /// The local user ("me"), resolved via the App Group-shared participant id so
    /// the extension stamps the same identity the app does. While demo mode is
    /// active the shared id is overridden with a demo-store id that matches
    /// nothing here — the real identity lives in the demo backup. Mirrors
    /// `EventStore.owner`: a merged-away row hands over to its survivor, and the
    /// last-resort fallback fires only when UNAMBIGUOUS (exactly one active
    /// participant) — guessing between two parents misattributes the log on both
    /// phones, which is worse than the intent refusing. A paused local user
    /// resolves to nil outright, same as `EventStore.owner` — Siri must refuse
    /// to log for someone whose access is paused.
    private var owner: Participant? {
        guard let resolved = resolvedSelf, !resolved.isPaused else { return nil }
        return resolved
    }

    /// True when this device's identity resolves to a paused row. The surfaces
    /// that bypass `owner` on purpose (undo, sleep-stop, alarm/reminder arming)
    /// check this instead — a paused device must neither mutate the shared log
    /// nor ring for slots it can't act on.
    var selfIsPaused: Bool { resolvedSelf?.isPaused ?? false }

    /// The row this device's identity resolves to, pause NOT yet applied —
    /// the pause check must run on the row the handover lands on, never the
    /// stored row alone (a merged-away duplicate keeping a stale `pausedAt`
    /// must not lock the survivor out, and vice versa).
    private var resolvedSelf: Participant? {
        let group = AppGroup.userDefaults
        let storedID = group?.bool(forKey: "demo.overrideActive") == true
            ? group?.string(forKey: "demo.bak.participantID")
            : group?.string(forKey: "sync.myParticipantID")
        if let s = storedID, let myID = UUID(uuidString: s) {
            var d = FetchDescriptor<Participant>(predicate: #Predicate { $0.id == myID })
            d.fetchLimit = 1
            if let me = try? context.fetch(d).first {
                if me.isActive { return me }
                if let cid = me.cloudUserID,
                   let survivor = ((try? context.fetch(FetchDescriptor<Participant>())) ?? [])
                       .first(where: { $0.isActive && $0.cloudUserID == cid && $0.id != me.id }) {
                    return survivor
                }
                return me
            }
        }
        let active = (try? context.fetch(FetchDescriptor<Participant>(
            predicate: #Predicate { $0.isActive }
        ))) ?? []
        return active.count == 1 ? active.first : nil
    }

    var babyName: String? { baby?.name }

    /// Whether new events of `kind` may be logged (shared tracker switches in
    /// SharedSettings). Intents check this first so Siri can explain *why* a
    /// log was refused; the write methods below also guard on it as a backstop
    /// for surfaces with no dialog (widget buttons, notification actions).
    func isTrackingEnabled(_ kind: EventKind) -> Bool {
        settings?.isEnabled(kind) ?? true
    }

    var activeSleep: SleepEvent? {
        try? context.fetch(FetchDescriptor<SleepEvent>(
            predicate: #Predicate { $0.endedAt == nil && $0.deletedAt == nil }
        )).first
    }

    /// How long the running sleep has lasted, or nil if the baby is awake.
    var activeSleepDuration: TimeInterval? {
        guard let s = activeSleep else { return nil }
        return Date.now.timeIntervalSince(s.startedAt)
    }

    /// Most recent live feed (by timestamp).
    var lastFeed: FeedEvent? {
        var d = FetchDescriptor<FeedEvent>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    /// Feed interval that should drive reminders/predictions after the given
    /// feed — night spacing when the bottle it predicts lands in the nighttime
    /// window, else the daytime target, defaulting to 3h when settings haven't
    /// synced yet (or when there's no feed to predict from). See
    /// `SharedSettings.feedInterval(after:)`, the single source both live and
    /// background (widget/notification-extension) contexts read. Used to re-arm
    /// the AlarmKit feed reminder on app foreground.
    func feedInterval(after lastFeed: Date?) -> TimeInterval {
        guard let settings else { return TimeInterval(180 * 60) }
        guard let lastFeed else { return TimeInterval(settings.targetFeedIntervalMinutes * 60) }
        return settings.feedInterval(after: lastFeed)
    }

    /// This device's own participant id — the schedule-reminder planner filters
    /// "my" assigned slots with it. Strictly the STORED identity, with no
    /// first-participant fallback (unlike `owner`): guessing wrong could arm
    /// the co-parent's 3am reminders on this phone. No identity → no reminders.
    var myParticipantID: UUID? {
        (AppGroup.userDefaults?.string(forKey: "sync.myParticipantID")).flatMap(UUID.init)
    }

    /// Live standing plan, for the schedule reminder planner / widget glance.
    var planSlots: [PlanSlot] {
        (try? context.fetch(FetchDescriptor<PlanSlot>(
            predicate: #Predicate { $0.deletedAt == nil }
        ))) ?? []
    }

    var planOverrides: [PlanOverride] {
        (try? context.fetch(FetchDescriptor<PlanOverride>(
            predicate: #Predicate { $0.deletedAt == nil }
        ))) ?? []
    }

    /// Live feeds/sleeps from the last couple of days — enough for the schedule
    /// engine's fulfillment matching and predictions without loading the log.
    func recentFeeds(hours: Int = 48) -> [FeedEvent] {
        let since = Date.now.addingTimeInterval(TimeInterval(-hours * 3600))
        return (try? context.fetch(FetchDescriptor<FeedEvent>(
            predicate: #Predicate { $0.deletedAt == nil && $0.timestamp >= since }
        ))) ?? []
    }

    func recentSleeps(hours: Int = 48) -> [SleepEvent] {
        let since = Date.now.addingTimeInterval(TimeInterval(-hours * 3600))
        return (try? context.fetch(FetchDescriptor<SleepEvent>(
            predicate: #Predicate { $0.deletedAt == nil && $0.startedAt >= since }
        ))) ?? []
    }

    /// The projected wake window — how long this baby comfortably stays awake
    /// between sleeps, from his age and his own recent history (`WakeWindow`).
    ///
    /// The single source for every "next nap" projection outside the app
    /// process (watch, widgets), mirroring how `feedInterval(after:)` serves the
    /// feed side. Falls back to the age table when history is thin, and to the
    /// newborn band when there's no baby row yet.
    var sleepTarget: TimeInterval {
        let ageInDays = baby.map { WakeWindow.ageInDays(dateOfBirth: $0.dateOfBirth) } ?? 0
        let gaps = WakeWindow.wakeGaps(
            sleeps: recentSleeps(hours: 7 * 24).map { ($0.startedAt, $0.endedAt) },
            nightStartMinute: settings?.nightStartMinute ?? 1200,
            nightEndMinute: settings?.nightEndMinute ?? 480)
        return WakeWindow.predicted(ageInDays: ageInDays, observedGaps: gaps)
    }

    /// When the next nap is projected to be due, or nil with nothing to project
    /// from (no completed sleep yet).
    var nextNapAt: Date? {
        lastEndedSleep?.endedAt?.addingTimeInterval(sleepTarget)
    }

    /// Most recent live diaper (by timestamp).
    var lastDiaper: DiaperEvent? {
        var d = FetchDescriptor<DiaperEvent>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    /// Most recent completed sleep (by end time), ignoring any running one.
    var lastEndedSleep: SleepEvent? {
        var d = FetchDescriptor<SleepEvent>(
            predicate: #Predicate { $0.deletedAt == nil && $0.endedAt != nil },
            sortBy: [SortDescriptor(\.endedAt, order: .reverse)]
        )
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    /// Today's running totals (since local start-of-day).
    var todayCounts: (feeds: Int, oz: Double, diapers: Int) {
        let dayStart = Calendar.current.startOfDay(for: .now)
        let feeds = (try? context.fetch(FetchDescriptor<FeedEvent>(
            predicate: #Predicate { $0.deletedAt == nil && $0.timestamp >= dayStart }
        ))) ?? []
        let diapers = (try? context.fetch(FetchDescriptor<DiaperEvent>(
            predicate: #Predicate { $0.deletedAt == nil && $0.timestamp >= dayStart }
        ))) ?? []
        return (feeds.count, feeds.reduce(0) { $0 + $1.amountOz }, diapers.count)
    }

    /// Total sleep time that falls within today (clips sessions that span
    /// midnight, and counts the running session up to now). Used by the
    /// dynamic daily summary + the rich notification card.
    var todaySleep: TimeInterval {
        let now = Date.now
        let dayStart = Calendar.current.startOfDay(for: now)
        let sleeps = (try? context.fetch(FetchDescriptor<SleepEvent>(
            predicate: #Predicate { $0.deletedAt == nil }
        ))) ?? []
        var total: TimeInterval = 0
        for s in sleeps {
            let start = max(s.startedAt, dayStart)
            let end = s.endedAt ?? now
            if end > start { total += end.timeIntervalSince(start) }
        }
        return total
    }

    /// Default feed amount for one-tap logging: SharedSettings.defaultFeedOz,
    /// else the most-recent feed's amount, else 4 oz.
    var defaultFeedOz: Double {
        if let oz = settings?.defaultFeedOz, oz > 0 { return oz }
        var d = FetchDescriptor<FeedEvent>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        d.fetchLimit = 1
        if let oz = (try? context.fetch(d))?.first?.amountOz, oz > 0 { return oz }
        return 4
    }

    // MARK: Writes
    //
    // Every write requires a resolved owner. The old `owner?.id ?? UUID()`
    // fallback stamped a participant that never existed (grey "?" ghost rows,
    // synced to the co-parent) whenever the store was mid-rebuild or a lookup
    // failed — e.g. a 1am notification-action log on a locked phone. Refusing
    // is strictly better: the intent reports failure and nothing persists.

    /// Idempotency window for the no-dialog surfaces (widget buttons, Control
    /// Center, notification actions): a re-tap inside this window is the same
    /// intent delivered twice (button mash, intent retry), not a second bottle —
    /// it must not mint a second row. 15s is far below any real logging cadence.
    static let duplicateWriteWindow: TimeInterval = 15

    @discardableResult
    func logFeed(amountOz: Double) -> FeedEvent? {
        guard isTrackingEnabled(.feed) else {
            Self.log.error("logFeed refused: feed logging is turned off")
            return nil
        }
        guard let owner else {
            Self.log.error("logFeed refused: no participant to attribute the event to")
            return nil
        }
        // Shortcuts/Siri can hand us a bad amount. A zero/negative/non-finite
        // bottle is never a real feed — refuse; clamp only the absurdly large.
        // (Mirrors EventBounds in the app target, which the extension can't see.)
        guard amountOz.isFinite, amountOz > 0 else {
            Self.log.error("logFeed refused: amount \(amountOz) is not loggable")
            return nil
        }
        let amountOz = min(amountOz, 32)
        if let recent = lastFeed, recent.amountOz == amountOz,
           Date.now.timeIntervalSince(recent.timestamp) < Self.duplicateWriteWindow {
            Self.log.log("logFeed absorbed a duplicate tap (identical feed \(recent.timestamp, privacy: .public))")
            return recent
        }
        let event = FeedEvent(
            baby: baby, amountOz: amountOz, timestamp: .now,
            loggedByID: owner.id,
            loggedByName: owner.displayName,
            loggedByColorHex: owner.colorHex
        )
        context.insert(event)
        commit(syncing: [event.id])
        return event
    }

    @discardableResult
    func logDiaper(_ type: DiaperType) -> DiaperEvent? {
        guard isTrackingEnabled(.diaper) else {
            Self.log.error("logDiaper refused: diaper logging is turned off")
            return nil
        }
        guard let owner else {
            Self.log.error("logDiaper refused: no participant to attribute the event to")
            return nil
        }
        if let recent = lastDiaper, recent.type == type,
           Date.now.timeIntervalSince(recent.timestamp) < Self.duplicateWriteWindow {
            Self.log.log("logDiaper absorbed a duplicate tap (identical diaper \(recent.timestamp, privacy: .public))")
            return recent
        }
        let event = DiaperEvent(
            baby: baby, type: type, timestamp: .now,
            loggedByID: owner.id,
            loggedByName: owner.displayName,
            loggedByColorHex: owner.colorHex
        )
        context.insert(event)
        commit(syncing: [event.id])
        return event
    }

    /// Soft-deletes the single most-recent live event across all three kinds.
    /// Mirrors the app's append-only model (sets `deletedAt`, never hard-deletes).
    /// - Returns: a human label of what was removed, or nil if there was nothing.
    @discardableResult
    func undoLastLog() -> String? {
        // Undo is household-wide (it may delete the co-parent's event), so a
        // paused device gets no say — this path skips `owner` and needs its
        // own gate.
        guard !selfIsPaused else {
            Self.log.error("undoLastLog refused: this device's access is paused")
            return nil
        }
        let feed = lastFeed
        let diaper = lastDiaper
        // For "undo" the relevant sleep instant is whichever the user just touched:
        // a running sleep (started) or the most recently ended one.
        let sleep = activeSleep ?? lastEndedSleep

        let feedAt = feed?.timestamp ?? .distantPast
        let diaperAt = diaper?.timestamp ?? .distantPast
        let sleepAt = sleep.map { $0.endedAt ?? $0.startedAt } ?? .distantPast

        let newest = max(feedAt, diaperAt, sleepAt)
        guard newest > .distantPast else { return nil }

        if newest == feedAt, let feed {
            feed.deletedAt = .now
            commit(syncing: [feed.id])
            return "feed of \(OzFormat.string(feed.amountOz)) oz"
        }
        if newest == diaperAt, let diaper {
            diaper.deletedAt = .now
            commit(syncing: [diaper.id])
            return "\(diaper.type.label.lowercased()) diaper"
        }
        if newest == sleepAt, let sleep {
            sleep.deletedAt = .now
            commit(syncing: [sleep.id])
            return sleep.endedAt == nil ? "sleep that just started" : "last sleep"
        }
        return nil
    }

    /// Starts a sleep if none is running, otherwise stops the running one.
    /// The Live Activity is reconciled by the app on next foreground
    /// (`SleepActivityManager.reconcile`) since it can't reliably start from a
    /// widget-extension process.
    /// - Returns: true if a sleep was started, false if one was stopped, nil if
    ///   the toggle was refused (no owner to attribute a start to, or this
    ///   device is paused). Stopping needs no owner — it only completes an
    ///   existing event.
    @discardableResult
    func toggleSleep() -> Bool? {
        if let active = activeSleep {
            // Stopping only completes an existing event — allowed even with
            // sleep tracking off (a sleep started before the toggle flip must
            // remain endable) — but never from a paused device: ending the
            // co-parent's running timer is still mutating the shared log.
            guard !selfIsPaused else {
                Self.log.error("toggleSleep refused: this device's access is paused")
                return nil
            }
            active.endedAt = .now
            commit(syncing: [active.id])
            return false
        }
        guard isTrackingEnabled(.sleep) else {
            Self.log.error("toggleSleep refused: sleep logging is turned off")
            return nil
        }
        guard let owner else {
            Self.log.error("toggleSleep refused: no participant to attribute the sleep to")
            return nil
        }
        let event = SleepEvent(
            baby: baby, startedAt: .now,
            loggedByID: owner.id,
            loggedByName: owner.displayName,
            loggedByColorHex: owner.colorHex
        )
        context.insert(event)
        commit(syncing: [event.id])
        return true
    }

    private func commit(syncing ids: [UUID]) {
        do { try context.save() } catch { Self.log.error("QuickLogger save error: \(error)") }
        // The extension can't reach the sync engine — queue the ids in the App
        // Group for the app to push (SyncManager.drainExtensionQueue) next launch.
        // ONE KEY PER WRITE, not a shared array: UserDefaults has no atomic
        // read-modify-write across processes, so appending to an array here
        // while the app drains it could lose the append. With unique keys the
        // drain only ever removes the exact keys it read.
        if let d = AppGroup.userDefaults {
            for id in ids {
                d.set(id.uuidString, forKey: "sync.widgetWrite.\(UUID().uuidString)")
            }
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
