import Foundation
import SwiftData
import WidgetKit
import AppIntents

/// Thin layer over `ModelContext` so views never hand-roll predicates.
/// Stamps every write with the local user's identity (denormalized) and hands
/// changed record ids to `SyncManager` for CloudKit. MainActor since it's only
/// used from SwiftUI views and talks to the MainActor `SyncManager`.
@MainActor
struct EventStore {
    let context: ModelContext

    /// In demo mode the context is a throwaway in-memory store: all writes must
    /// stay local (no CloudKit, widgets, alarms, Live Activities, or Siri).
    private var demo: Bool { LocalPrefs.shared.demoModeEnabled }

    // MARK: Lookups

    var baby: Baby? {
        try? context.fetch(FetchDescriptor<Baby>()).first
    }

    /// The local user ("me"). Resolved via `LocalPrefs.myParticipantID` once
    /// sharing introduces a second participant. If that row was merged away
    /// (auto-merge tombstone), the active survivor for the same iCloud account
    /// is adopted. The last-resort fallback only fires when it is UNAMBIGUOUS —
    /// exactly one active participant: with two parents in the store, guessing
    /// attributes this device's logs to the co-parent on both phones, which is
    /// worse than refusing the write (the caller banners "couldn't tell who's
    /// logging").
    var owner: Participant? {
        if let myID = LocalPrefs.shared.myParticipantID {
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

    var settings: SharedSettings? {
        SharedSettings.canonical((try? context.fetch(FetchDescriptor<SharedSettings>())) ?? [])
    }

    var activeSleep: SleepEvent? {
        let descriptor = FetchDescriptor<SleepEvent>(
            predicate: #Predicate { $0.endedAt == nil && $0.deletedAt == nil }
        )
        return try? context.fetch(descriptor).first
    }

    /// Next-feed snapshot for the sleep Live Activity, computed over this
    /// store's own context via the shared schedule assembly.
    private var liveActivityNextFeed: SleepActivityManager.NextFeed? {
        QuickLogger(context: context).nextFeedPrediction()
    }

    /// Keeps a running sleep Live Activity's next-feed countdown honest after
    /// a write that moves the prediction (feed logged/edited/deleted while the
    /// baby sleeps — the dream-feed case). No-op when no sleep is running.
    private func refreshSleepActivityNextFeed() {
        guard !demo, let active = activeSleep else { return }
        SleepActivityManager.refresh(startedAt: active.startedAt, nextFeed: liveActivityNextFeed)
    }

    // MARK: Logging
    //
    // Every creation requires a resolved owner. The old `owner?.id ?? UUID()`
    // fallback minted events attributed to a participant that never existed —
    // rendered as the grey "?" ghost rows — and synced them to the co-parent.
    // If the owner can't be resolved something is broken enough that refusing
    // (with a banner) is strictly better than persisting an unattributed event.

    /// The resolved local user, surfacing a banner when the lookup fails.
    private func requireOwner() -> Participant? {
        guard let owner else {
            AppLog.store.error("Write refused: no participant to attribute the event to")
            if !demo {
                StoreErrorCenter.shared.report("That didn't save — couldn't tell who's logging. Open the app and try again.")
            }
            return nil
        }
        return owner
    }

    /// Whether new events of `kind` may be created. Off-trackers hide their
    /// buttons, but deep links, Siri, and stale widgets can still reach the
    /// store — refuse there too so "no new events while off" actually holds.
    private func requireTracking(_ kind: EventKind) -> Bool {
        guard settings?.isEnabled(kind) ?? true else {
            AppLog.store.error("Write refused: \(kind.rawValue) logging is turned off")
            return false
        }
        return true
    }

    @discardableResult
    func logFeed(amountOz: Double, at date: Date = .now, notes: String? = nil) -> FeedEvent? {
        guard requireTracking(.feed), let owner = requireOwner() else { return nil }
        // A bottle of nothing is never a real feed — reject instead of clamping
        // a bad parse/tap into a "0 oz" timeline row.
        guard EventBounds.isLoggableOz(amountOz) else {
            AppLog.store.error("Write refused: feed amount \(amountOz) is not loggable")
            return nil
        }
        let amountOz = EventBounds.clampOz(amountOz)
        let date = EventBounds.clampPast(date)
        let event = FeedEvent(
            baby: baby, amountOz: amountOz, timestamp: date,
            notes: EventBounds.cleanNote(notes),
            loggedByID: owner.id,
            loggedByName: owner.displayName,
            loggedByColorHex: owner.colorHex
        )
        context.insert(event)
        guard save() else { context.delete(event); return nil }
        sync(save: [event.id])
        refreshSleepActivityNextFeed()
        reloadWidgets()
        refreshLocalReminders()
        donate(LogFeedIntent(amountOz: amountOz))
        return event
    }

    @discardableResult
    func logDiaper(_ type: DiaperType, at date: Date = .now, notes: String? = nil) -> DiaperEvent? {
        guard requireTracking(.diaper), let owner = requireOwner() else { return nil }
        let date = EventBounds.clampPast(date)
        let event = DiaperEvent(
            baby: baby, type: type, timestamp: date,
            notes: EventBounds.cleanNote(notes),
            loggedByID: owner.id,
            loggedByName: owner.displayName,
            loggedByColorHex: owner.colorHex
        )
        context.insert(event)
        guard save() else { context.delete(event); return nil }
        sync(save: [event.id])
        reloadWidgets()
        refreshLocalReminders()
        donate(LogDiaperIntent(type: DiaperTypeAppEnum(rawValue: type.rawValue) ?? .wet))
        return event
    }

    /// Logs a standalone timestamped note. No tracker gate (notes have no
    /// toggle) and none of the feed/sleep/diaper side effects — notes touch no
    /// widget, reminder, or Siri surface.
    @discardableResult
    func logNote(_ text: String, at date: Date = .now) -> NoteEvent? {
        guard let owner = requireOwner() else { return nil }
        // A blank note is never a real entry — reject instead of persisting an
        // empty timeline row.
        guard let text = EventBounds.cleanNote(text, maxLength: EventBounds.noteEventMaxLength) else {
            AppLog.store.error("Write refused: note text is empty")
            return nil
        }
        let date = EventBounds.clampPast(date)
        let event = NoteEvent(
            baby: baby, text: text, timestamp: date,
            loggedByID: owner.id,
            loggedByName: owner.displayName,
            loggedByColorHex: owner.colorHex
        )
        context.insert(event)
        guard save() else { context.delete(event); return nil }
        sync(save: [event.id])
        return event
    }

    /// Starts a sleep timer. Refuses if one is already active (single-timer guard).
    @discardableResult
    func startSleep(at date: Date = .now, source: SleepSource? = nil) -> SleepEvent? {
        guard requireTracking(.sleep), activeSleep == nil, let owner = requireOwner() else { return nil }
        let date = EventBounds.clampPast(date)
        let event = SleepEvent(
            baby: baby, startedAt: date,
            loggedByID: owner.id,
            loggedByName: owner.displayName,
            loggedByColorHex: owner.colorHex,
            sourceRaw: source?.rawValue
        )
        context.insert(event)
        guard save() else { context.delete(event); return nil }
        sync(save: [event.id])
        if !demo {
            SleepActivityManager.start(babyName: baby?.name ?? "Baby", at: date,
                                       nextFeed: liveActivityNextFeed)
        }
        reloadWidgets()
        // A started sleep fulfills its schedule slot — sweep tonight's reminder.
        refreshLocalReminders()
        donate(ToggleSleepIntent())
        return event
    }

    /// Logs an already-finished sleep in one write (SNOO import accept). No
    /// Live Activity or timer — the sleep never passes through the active
    /// state, so `startSleep`'s single-timer guard doesn't apply.
    @discardableResult
    func logCompletedSleep(startedAt: Date, endedAt: Date, notes: String? = nil,
                           source: SleepSource? = nil) -> SleepEvent? {
        guard requireTracking(.sleep), let owner = requireOwner() else { return nil }
        let start = EventBounds.clampPast(startedAt)
        let end = max(start, EventBounds.clampPast(endedAt))
        let event = SleepEvent(
            baby: baby, startedAt: start, endedAt: end,
            notes: EventBounds.cleanNote(notes),
            loggedByID: owner.id,
            loggedByName: owner.displayName,
            loggedByColorHex: owner.colorHex,
            sourceRaw: source?.rawValue
        )
        context.insert(event)
        guard save() else { context.delete(event); return nil }
        sync(save: [event.id])
        reloadWidgets()
        refreshLocalReminders()
        return event
    }

    func stopSleep(_ event: SleepEvent, at date: Date = .now) {
        event.endedAt = date
        save()
        sync(save: [event.id])
        if !demo { SleepActivityManager.end() }
        reloadWidgets()
        refreshLocalReminders()
        donate(ToggleSleepIntent())
    }

    /// Undo of a just-started sleep: soft-deletes it AND tears down the Live
    /// Activity `startSleep` spun up — a plain `softDelete` would leave the
    /// lock-screen timer running for a sleep that no longer exists.
    func cancelSleep(_ event: SleepEvent) {
        if !demo { SleepActivityManager.end() }
        softDelete(event)
    }

    /// Undo of a just-ended (or just-discarded) sleep: puts the timer back as if
    /// Wake Up was never tapped — clears `endedAt`/`deletedAt` and restarts the
    /// Live Activity. Refuses if another sleep started in the meantime, keeping
    /// the single-active-sleep invariant.
    func resumeSleep(_ event: SleepEvent) {
        guard activeSleep == nil else { return }
        event.endedAt = nil
        event.deletedAt = nil
        save()
        sync(save: [event.id])
        if !demo {
            SleepActivityManager.start(babyName: baby?.name ?? "Baby", at: event.startedAt,
                                       nextFeed: liveActivityNextFeed)
        }
        reloadWidgets()
        refreshLocalReminders()
    }

    /// Best-effort Siri donation so Suggestions / Spotlight rank Two of Us
    /// actions by the family's real rhythm. Fire-and-forget; never blocks a log.
    private func donate(_ intent: some AppIntent) {
        guard !demo else { return }
        Task.detached {
            _ = try? await IntentDonationManager.shared.donate(intent: intent)
        }
    }

    // MARK: Edit (append-only: soft-delete original, insert replacement)

    @discardableResult
    func editFeed(_ original: FeedEvent, amountOz: Double, timestamp: Date, notes: String?,
                  loggedBy: Participant? = nil) -> FeedEvent {
        // Same rule as creation: a "0 oz" bottle is never a real feed, and the
        // edit path was the last way to mint one (the sweep can't remove it —
        // it carries real attribution). Refuse by returning the original.
        guard EventBounds.isLoggableOz(amountOz) else {
            AppLog.store.error("Edit refused: feed amount \(amountOz) is not loggable")
            return original
        }
        let amountOz = EventBounds.clampOz(amountOz)
        let timestamp = EventBounds.clampPast(timestamp)
        let replacement = FeedEvent(
            baby: original.baby, amountOz: amountOz, timestamp: timestamp,
            notes: EventBounds.cleanNote(notes),
            loggedByID: loggedBy?.id ?? original.loggedByID,
            loggedByName: loggedBy?.displayName ?? original.loggedByName,
            loggedByColorHex: loggedBy?.colorHex ?? original.loggedByColorHex,
            editOfID: original.id
        )
        original.deletedAt = .now
        context.insert(replacement)
        save()
        sync(save: [original.id, replacement.id])
        refreshSleepActivityNextFeed()
        reloadWidgets()
        refreshLocalReminders()
        return replacement
    }

    @discardableResult
    func editSleep(_ original: SleepEvent, startedAt: Date, endedAt: Date?, notes: String?,
                   loggedBy: Participant? = nil) -> SleepEvent {
        let replacement = SleepEvent(
            baby: original.baby, startedAt: startedAt, endedAt: endedAt,
            notes: EventBounds.cleanNote(notes),
            loggedByID: loggedBy?.id ?? original.loggedByID,
            loggedByName: loggedBy?.displayName ?? original.loggedByName,
            loggedByColorHex: loggedBy?.colorHex ?? original.loggedByColorHex,
            editOfID: original.id,
            sourceRaw: original.sourceRaw
        )
        original.deletedAt = .now
        context.insert(replacement)
        save()
        sync(save: [original.id, replacement.id])
        // The edit replaced the running sleep's identity (append-only), so the
        // Live Activity — which only knows about the old record — needs its
        // start time corrected explicitly rather than picked up automatically.
        if !demo, replacement.isActive {
            SleepActivityManager.refresh(startedAt: replacement.startedAt,
                                         nextFeed: liveActivityNextFeed)
        }
        reloadWidgets()
        return replacement
    }

    @discardableResult
    func editDiaper(_ original: DiaperEvent, type: DiaperType, timestamp: Date, notes: String?,
                    loggedBy: Participant? = nil) -> DiaperEvent {
        let replacement = DiaperEvent(
            baby: original.baby, type: type, timestamp: timestamp,
            notes: EventBounds.cleanNote(notes),
            loggedByID: loggedBy?.id ?? original.loggedByID,
            loggedByName: loggedBy?.displayName ?? original.loggedByName,
            loggedByColorHex: loggedBy?.colorHex ?? original.loggedByColorHex,
            editOfID: original.id
        )
        original.deletedAt = .now
        context.insert(replacement)
        save()
        sync(save: [original.id, replacement.id])
        reloadWidgets()
        refreshLocalReminders()
        return replacement
    }

    @discardableResult
    func editNote(_ original: NoteEvent, text: String, timestamp: Date,
                  loggedBy: Participant? = nil) -> NoteEvent {
        // Same rule as creation: editing a note down to nothing is a delete,
        // not a save — refuse by returning the original.
        guard let text = EventBounds.cleanNote(text, maxLength: EventBounds.noteEventMaxLength) else {
            AppLog.store.error("Edit refused: note text is empty")
            return original
        }
        let replacement = NoteEvent(
            baby: original.baby, text: text,
            timestamp: EventBounds.clampPast(timestamp),
            loggedByID: loggedBy?.id ?? original.loggedByID,
            loggedByName: loggedBy?.displayName ?? original.loggedByName,
            loggedByColorHex: loggedBy?.colorHex ?? original.loggedByColorHex,
            editOfID: original.id
        )
        original.deletedAt = .now
        context.insert(replacement)
        save()
        sync(save: [original.id, replacement.id])
        return replacement
    }

    // MARK: Delete / undo

    func softDelete(_ event: any SoftDeletable) {
        event.deletedAt = .now
        save()
        sync(save: [event.id])   // soft delete travels as a `deletedAt` update
        refreshSleepActivityNextFeed()
        reloadWidgets()
        // Re-arms/cancels the loud alarms too: deleting the latest feed must not
        // leave a "feed due" alarm armed for an event that no longer exists.
        refreshLocalReminders()
    }

    /// Reverses a `softDelete` — the Undo path for swipe-to-delete. Re-arms the
    /// reminders off the restored state so an undone delete leaves everything as it
    /// was before the swipe.
    func restore(_ event: any SoftDeletable) {
        event.deletedAt = nil
        save()
        sync(save: [event.id])
        refreshSleepActivityNextFeed()
        reloadWidgets()
        refreshLocalReminders()
    }

    /// Soft-deletes every live event (keeps baby, participants, settings). Used by
    /// "Clear all logs" — travels to the co-parent as ordinary `deletedAt` updates.
    func clearAllLogs() {
        var ids: [UUID] = []
        func purge<T: PersistentModel & SoftDeletable>(_ type: T.Type) {
            let all = (try? context.fetch(FetchDescriptor<T>())) ?? []
            for e in all where e.deletedAt == nil {
                e.deletedAt = .now
                ids.append(e.id)
            }
        }
        purge(FeedEvent.self)
        purge(SleepEvent.self)
        purge(DiaperEvent.self)
        purge(NoteEvent.self)
        if !demo { SleepActivityManager.end() }   // tear down any running sleep Live Activity
        save()
        sync(save: ids)
        reloadWidgets()
        // No feeds remain → this cancels the pending alarms and clears the
        // reminders/summary rather than leaving them armed for purged events.
        refreshLocalReminders()
    }

    /// Live events whose logger isn't (and never was) a participant of this
    /// household — the signature of dev fixture data that leaked in via sync:
    /// `SeedData.seedSampleEvents` stamps a fresh random UUID on every row, so
    /// no Participant record can ever match. Real events always carry a real
    /// participant's id (revoked participants keep their record, `isActive`
    /// false, so their history stays untouched).
    func ghostEvents() -> [any SoftDeletable] {
        let known = Set(((try? context.fetch(FetchDescriptor<Participant>())) ?? []).map(\.id))
        var ghosts: [any SoftDeletable] = []
        func collect<T: PersistentModel & SoftDeletable & AnyEventModel>(_ type: T.Type) {
            let all = (try? context.fetch(FetchDescriptor<T>())) ?? []
            ghosts += all.filter { $0.deletedAt == nil && !known.contains($0.loggedByID) }
        }
        collect(FeedEvent.self)
        collect(SleepEvent.self)
        collect(DiaperEvent.self)
        collect(NoteEvent.self)
        return ghosts
    }

    /// Soft-deletes every ghost event (see `ghostEvents`), syncing the deletions
    /// to the co-parent like any other removal. Returns how many were removed.
    @discardableResult
    func purgeGhostEvents() -> Int {
        let ghosts = ghostEvents()
        guard !ghosts.isEmpty else { return 0 }
        for e in ghosts { e.deletedAt = .now }
        save()
        sync(save: ghosts.map(\.id))
        reloadWidgets()
        // The newest feed may have been a ghost — re-derive alarms/reminders.
        refreshLocalReminders()
        return ghosts.count
    }

    /// Self-healing sweep, safe to run automatically (launch, foreground, after
    /// sync fetches). Two passes, narrower than the manual `purgeGhostEvents`:
    ///
    /// 1. Rows sharing one `id` are collapsed to a single row. Duplicates can
    ///    only be minted locally (a swallowed store error during the inbound
    ///    upsert used to blind-insert) and all map to ONE CloudKit record, so
    ///    the extras are hard-deleted locally, never synced — a synced delete
    ///    would soft-delete the co-parent's one real copy. The row with real
    ///    attribution wins.
    /// 2. Events carrying the exact ghost signature — EMPTY denormalized logger
    ///    name AND a logger id no Participant matches — are soft-deleted and
    ///    synced, so both phones (and the zone) clean up. Real events always
    ///    carry the logger's display name, and a removed caregiver keeps their
    ///    Participant record, so neither is ever swept.
    @discardableResult
    func autoPurgeGhostEvents() -> Int {
        let known = Set(((try? context.fetch(FetchDescriptor<Participant>())) ?? []).map(\.id))
        var syncedDeletes: [UUID] = []
        var removed = 0

        func sweep<T: PersistentModel & SoftDeletable & AnyEventModel>(_ type: T.Type) {
            let all = (try? context.fetch(FetchDescriptor<T>())) ?? []
            var byID: [UUID: [T]] = [:]
            for e in all { byID[e.id, default: []].append(e) }
            for (_, rows) in byID {
                let keep = rows.first { !$0.loggedByName.isEmpty } ?? rows[0]
                for row in rows where row !== keep {
                    context.delete(row)
                    removed += 1
                }
                if keep.deletedAt == nil, keep.loggedByName.isEmpty, !known.contains(keep.loggedByID) {
                    keep.deletedAt = .now
                    syncedDeletes.append(keep.id)
                    removed += 1
                }
            }
        }
        sweep(FeedEvent.self)
        sweep(SleepEvent.self)
        sweep(DiaperEvent.self)
        sweep(NoteEvent.self)

        // One baby can't sleep twice at once: concurrent starts on both phones
        // (each guarded only by its local single-timer check) leave two open
        // sleeps under DIFFERENT ids once they sync. Keep the earliest start —
        // deterministic, so both phones converge — and soft-delete the rest,
        // synced like any removal.
        let openSleeps = ((try? context.fetch(FetchDescriptor<SleepEvent>(
            predicate: #Predicate { $0.endedAt == nil && $0.deletedAt == nil }
        ))) ?? []).sorted { ($0.startedAt, $0.id.uuidString) < ($1.startedAt, $1.id.uuidString) }
        for extra in openSleeps.dropFirst() {
            extra.deletedAt = .now
            syncedDeletes.append(extra.id)
            removed += 1
        }

        guard removed > 0 else { return 0 }
        AppLog.store.warning("Ghost sweep removed \(removed) event row(s) (\(syncedDeletes.count) synced)")
        save()
        sync(save: syncedDeletes)
        reloadWidgets()
        // The newest feed may have been a ghost — re-derive alarms/reminders.
        refreshLocalReminders()
        return removed
    }

    // MARK: Profile / baby / settings edits
    //
    // All sync-aware: each routes the change through `sync(...)` so it reaches the
    // co-parent. (Earlier inline edits in SettingsView called `context.save()`
    // only, so baby DOB / target-interval changes never propagated.)

    /// Updates the shared Baby record (name, date of birth, optional avatar) and
    /// syncs it. `photo: .some(nil)` clears the avatar; `.none` (the default)
    /// leaves it untouched.
    func updateBaby(name: String, dateOfBirth: Date, photo: Data?? = .none) {
        guard let baby else { return }
        baby.name = name
        baby.dateOfBirth = dateOfBirth
        if case let .some(value) = photo { baby.photoData = value }
        save()
        sync(save: [baby.id])
        reloadWidgets()
        // Keep the share invite card title current — it shows the baby's name
        // and is otherwise stale if the owner renamed after the share was created.
        SyncManager.shared?.refreshShareTitleIfOwner()
    }

    /// Updates the shared feeding rhythm and syncs it. Nil fields stay as-is.
    func updateSettings(targetFeedIntervalMinutes: Int? = nil, ozPresets: [Double]? = nil,
                        defaultFeedOz: Double? = nil,
                        feedLoggingEnabled: Bool? = nil, diaperLoggingEnabled: Bool? = nil,
                        sleepLoggingEnabled: Bool? = nil) {
        guard let settings else { return }
        if let targetFeedIntervalMinutes {
            settings.targetFeedIntervalMinutes = targetFeedIntervalMinutes
        }
        if let ozPresets {
            settings.ozPresets = ozPresets.sorted()
            // Keep the one-tap (widget/Siri) amount one of the presets — same
            // rule as `SeedData.createBaby`.
            settings.defaultFeedOz = settings.ozPresets.max() ?? settings.defaultFeedOz
        }
        // Applied after the ozPresets side effect, so an explicit default (the
        // Settings picker) always wins over the presets-derived fallback.
        if let defaultFeedOz {
            settings.defaultFeedOz = defaultFeedOz
        }
        let before = EventKind.allCases.map(settings.isEnabled)
        if let feedLoggingEnabled { settings.feedLoggingEnabled = feedLoggingEnabled }
        if let diaperLoggingEnabled { settings.diaperLoggingEnabled = diaperLoggingEnabled }
        if let sleepLoggingEnabled { settings.sleepLoggingEnabled = sleepLoggingEnabled }
        // Never let the last tracker go dark (the UI disables that toggle; this
        // backstops a race with the co-parent turning another one off).
        if settings.enabledTrackerCount == 0 {
            settings.feedLoggingEnabled = true
        }
        save()
        sync(save: [settings.id])
        if EventKind.allCases.map(settings.isEnabled) != before {
            // Tracker flips change what the widgets show and which reminders
            // may fire — refresh both off the new state.
            reloadWidgets()
            refreshLocalReminders()
        }
    }

    /// Publishes (or clears, with nil) the household SNOO connection on the
    /// shared settings record (`SnooSharedCredentials` JSON — the refresh
    /// token, deliberately shared with every participant in the zone; never
    /// the password). Returns whether the write landed: with no settings row
    /// there is nothing to publish onto, and pretending otherwise is how a
    /// "signed out" household keeps a live token (the old silent `return`).
    /// `interactive` controls the failure banner: user-initiated writes
    /// (sign-in/out, the auto-log toggle) surface it; background publishes
    /// only log, per the silent-background-sync rule.
    @discardableResult
    func updateSnooCredentials(_ json: String?, interactive: Bool = true) -> Bool {
        guard let settings else {
            AppLog.store.error("SNOO credential update dropped: no SharedSettings row on this device")
            if interactive && !demo {
                StoreErrorCenter.shared.report("That didn't save — this phone hasn't finished syncing the shared settings. Try again in a moment.")
            }
            return false
        }
        settings.snooCredentials = json
        save()
        sync(save: [settings.id])
        return true
    }

    /// Updates the local user's own name + color and **backfills** that identity
    /// onto every event they logged, so past timeline rows relabel too. Syncs the
    /// participant plus all rewritten events.
    func updateMyProfile(name: String, colorHex: String, photo: Data?? = .none) {
        guard let me = owner else { return }
        me.displayName = name
        me.colorHex = colorHex
        if case let .some(value) = photo { me.photoData = value }
        var changed = [me.id]
        changed += backfillIdentity(loggerID: me.id, name: name, colorHex: colorHex)
        save()
        sync(save: changed)
        reloadWidgets()
    }

    /// Folds a duplicate People row into another (Settings → People, owner
    /// only). The auto-merge handles rows that share a captured iCloud
    /// identity; this is the explicit path for legacy duplicates that predate
    /// the capture (nil `cloudUserID`). Entries, plan assignments, and any
    /// missing profile bits move to `survivor`; the duplicate deactivates.
    func mergeParticipant(_ duplicate: Participant, into survivor: Participant) {
        let changed = ParticipantMerger.merge(duplicate, into: survivor, in: context)
        guard !changed.isEmpty else { return }
        save()
        sync(save: changed)
        reloadWidgets()
        // Slot assignments may have moved to the survivor's id — re-arm the
        // "you're up" reminders so they filter on the right identity.
        refreshLocalReminders()
    }

    /// Rewrites denormalized logger identity on every event logged by `loggerID`.
    /// Returns the ids of the events it changed.
    private func backfillIdentity(loggerID: UUID, name: String, colorHex: String) -> [UUID] {
        var ids: [UUID] = []
        func rewrite<T: PersistentModel & AnyEventModel & HasSyncID>(_ type: T.Type) {
            let all = (try? context.fetch(FetchDescriptor<T>())) ?? []
            for e in all where e.loggedByID == loggerID {
                e.loggedByName = name
                e.loggedByColorHex = colorHex
                ids.append(e.id)
            }
        }
        rewrite(FeedEvent.self)
        rewrite(SleepEvent.self)
        rewrite(DiaperEvent.self)
        rewrite(NoteEvent.self)
        // Plan slots/overrides carry the same denormalized identity under a
        // different name (assignedTo*), so a rename/recolor relabels them too.
        for slot in (try? context.fetch(FetchDescriptor<PlanSlot>())) ?? []
        where slot.assignedToID == loggerID {
            slot.assignedToName = name
            slot.assignedToColorHex = colorHex
            ids.append(slot.id)
        }
        for override in (try? context.fetch(FetchDescriptor<PlanOverride>())) ?? []
        where override.assignedToID == loggerID {
            override.assignedToName = name
            override.assignedToColorHex = colorHex
            ids.append(override.id)
        }
        return ids
    }

    /// Owner sets a co-parent's app role (full vs logger) and syncs it.
    func setRole(_ participant: Participant, _ role: ParticipantRole) {
        participant.role = role
        save()
        sync(save: [participant.id])
    }

    // MARK: Schedule plan
    //
    // The standing plan is configuration, not history: slots are edited in place
    // (their id is load-bearing — overrides and reminder request ids reference
    // it), while per-night changes are append-only `PlanOverride` inserts so
    // concurrent swaps by both parents can never conflict in CloudKit.

    /// Saves the shared nighttime-schedule settings (window, spacing, rotation)
    /// and syncs them. The schedule itself is no longer materialized as
    /// standing slots: it's computed fresh each night (`NightSchedule`) from
    /// these settings plus the feed log, anchored to tonight's first logged
    /// feed. Any standing FEED slots left over from the fixed-slot era retire
    /// here — along with their future overrides, same rule as `removePlanSlot`
    /// — so the old 10pm/2am/6am rows can't ring or render next to the dynamic
    /// schedule. Sleep slots are hand-authored and never touched.
    func applyNightSchedule(nightStartMinute: Int, nightEndMinute: Int,
                            spacingMinutes: Int, rotation: NightRotation,
                            firstShiftID: UUID? = nil, asOf now: Date = .now) {
        guard let settings else { return }
        settings.nightStartMinute = EventBounds.wrapMinuteOfDay(nightStartMinute)
        settings.nightEndMinute = EventBounds.wrapMinuteOfDay(nightEndMinute)
        settings.nightFeedSpacingMinutes = spacingMinutes
        settings.nightRotation = rotation
        settings.nightFirstShiftID = firstShiftID
        var ids: [UUID] = [settings.id]

        let feedKind = EventKind.feed.rawValue
        let liveFeedSlots = (try? context.fetch(FetchDescriptor<PlanSlot>(
            predicate: #Predicate { $0.deletedAt == nil && $0.kindRaw == feedKind }
        ))) ?? []
        let todayKey = ScheduleEngine.dayKey(for: now, calendar: .current)
        for slot in liveFeedSlots {
            slot.deletedAt = now
            ids.append(slot.id)
            let slotID = slot.id
            let orphaned = (try? context.fetch(FetchDescriptor<PlanOverride>(
                predicate: #Predicate { $0.slotID == slotID && $0.deletedAt == nil && $0.dayKey >= todayKey }
            ))) ?? []
            for o in orphaned {
                o.deletedAt = now
                ids.append(o.id)
            }
        }

        save()
        sync(save: ids)
        reloadWidgets()
        refreshLocalReminders()
    }

    @discardableResult
    func addPlanSlot(kind: EventKind, minuteOfDay: Int, assignedTo: Participant?) -> PlanSlot {
        let slot = PlanSlot(
            kind: kind,
            minuteOfDay: EventBounds.wrapMinuteOfDay(minuteOfDay),
            assignedToID: assignedTo?.id,
            assignedToName: assignedTo?.displayName ?? "",
            assignedToColorHex: assignedTo?.colorHex ?? ""
        )
        context.insert(slot)
        save()
        sync(save: [slot.id])
        refreshLocalReminders()
        return slot
    }

    /// Edits a standing slot in place. `assignedTo: .some(nil)` unassigns;
    /// `.none` (the default) leaves the assignment untouched.
    func updatePlanSlot(_ slot: PlanSlot, kind: EventKind? = nil, minuteOfDay: Int? = nil,
                        assignedTo: Participant?? = .none) {
        if let kind { slot.kind = kind }
        if let minuteOfDay { slot.minuteOfDay = EventBounds.wrapMinuteOfDay(minuteOfDay) }
        if case let .some(participant) = assignedTo {
            slot.assignedToID = participant?.id
            slot.assignedToName = participant?.displayName ?? ""
            slot.assignedToColorHex = participant?.colorHex ?? ""
        }
        save()
        sync(save: [slot.id])
        refreshLocalReminders()
    }

    /// Removes a slot from the plan (soft delete) along with any live overrides
    /// still pointing at it from today onward — a swap for a slot that no longer
    /// exists must not linger and resurrect an occurrence.
    func removePlanSlot(_ slot: PlanSlot, asOf now: Date = .now) {
        var ids = [slot.id]
        slot.deletedAt = now
        let todayKey = ScheduleEngine.dayKey(for: now, calendar: .current)
        let slotID = slot.id
        let overrides = (try? context.fetch(FetchDescriptor<PlanOverride>(
            predicate: #Predicate { $0.slotID == slotID && $0.deletedAt == nil && $0.dayKey >= todayKey }
        ))) ?? []
        for o in overrides {
            o.deletedAt = now
            ids.append(o.id)
        }
        save()
        sync(save: ids)
        refreshLocalReminders()
    }

    /// Reverses `removePlanSlot` — the Undo path. (Its overrides stay deleted;
    /// the standing plan resumes clean.)
    func restorePlanSlot(_ slot: PlanSlot) {
        slot.deletedAt = nil
        save()
        sync(save: [slot.id])
        refreshLocalReminders()
    }

    /// Reassigns one night of a slot ("Katie takes tonight's 3am") without
    /// touching the standing plan. Replaces any earlier live override for the
    /// same night so at most one override per (slot, night) is authored here;
    /// a time move already made for that night is carried forward, so swapping
    /// after moving keeps both edits.
    @discardableResult
    func overrideSlot(_ slot: PlanSlot, dayKey: Int, assignTo participant: Participant?) -> PlanOverride {
        insertOverride(slotID: slot.id, dayKey: dayKey, assignedTo: participant, isSkipped: false,
                       minuteOfDayOverride: nil, inheritPriorMove: true)
    }

    // MARK: Dynamic night-slot overrides
    //
    // Tonight's computed feed slots have no PlanSlot behind them, but their
    // synthetic slot ids are deterministic per (night, index) on both phones —
    // so the same append-only `PlanOverride` records cover "Katie takes
    // tonight's 3:30" and "skip tonight's 7:30" for the dynamic schedule too.
    // No move variant: a dynamic slot's time is derived, not authored.

    /// Reassigns one night slot of the dynamic schedule ("Katie takes
    /// tonight's 3:30") without touching the rotation.
    @discardableResult
    func overrideNightOccurrence(_ occ: ScheduleOccurrence,
                                 assignTo participant: Participant?) -> PlanOverride {
        insertOverride(slotID: occ.slotID, dayKey: occ.dayKey, assignedTo: participant,
                       isSkipped: false, minuteOfDayOverride: nil, inheritPriorMove: false)
    }

    /// Skips one night slot of the dynamic schedule — no occurrence, no
    /// reminder on either phone.
    @discardableResult
    func skipNightOccurrence(_ occ: ScheduleOccurrence) -> PlanOverride {
        insertOverride(slotID: occ.slotID, dayKey: occ.dayKey, assignedTo: nil,
                       isSkipped: true, minuteOfDayOverride: nil, inheritPriorMove: false)
    }

    /// Manually sets tonight's FIRST feed time — the whole night re-times
    /// from it (`NightSchedule` treats a live move override on the night's
    /// first slot as the anchor, beating even a logged feed). `assignedTo`
    /// carries the slot's current effective assignee so re-timing the night
    /// never drops a swap.
    @discardableResult
    func moveNightAnchor(_ occ: ScheduleOccurrence, toMinuteOfDay minute: Int,
                         assignedTo participant: Participant?) -> PlanOverride {
        insertOverride(slotID: occ.slotID, dayKey: occ.dayKey, assignedTo: participant,
                       isSkipped: false, minuteOfDayOverride: EventBounds.wrapMinuteOfDay(minute),
                       inheritPriorMove: false)
    }

    /// Moves one night of a slot to a different time ("tonight's 11pm at 11:30
    /// instead") without touching the standing plan. `assignedTo` carries the
    /// night's current effective assignee so a move never drops a swap.
    @discardableResult
    func moveSlot(_ slot: PlanSlot, dayKey: Int, toMinuteOfDay minute: Int,
                  assignedTo participant: Participant?) -> PlanOverride {
        insertOverride(slotID: slot.id, dayKey: dayKey, assignedTo: participant, isSkipped: false,
                       minuteOfDayOverride: minute, inheritPriorMove: false)
    }

    /// Skips one night of a slot — no occurrence, no reminder on either phone.
    @discardableResult
    func skipSlot(_ slot: PlanSlot, dayKey: Int) -> PlanOverride {
        insertOverride(slotID: slot.id, dayKey: dayKey, assignedTo: nil, isSkipped: true,
                       minuteOfDayOverride: nil, inheritPriorMove: false)
    }

    /// Undoes a swap/skip — the standing assignment resumes for that night.
    func clearOverride(_ override: PlanOverride) {
        override.deletedAt = .now
        save()
        sync(save: [override.id])
        refreshLocalReminders()
    }

    /// `slotID` is a standing PlanSlot's id, or a dynamic night slot's
    /// deterministic synthetic id — the override machinery is identical.
    private func insertOverride(slotID: UUID, dayKey: Int, assignedTo participant: Participant?,
                                isSkipped: Bool, minuteOfDayOverride: Int?,
                                inheritPriorMove: Bool) -> PlanOverride {
        var ids: [UUID] = []
        let priors = (try? context.fetch(FetchDescriptor<PlanOverride>(
            predicate: #Predicate { $0.slotID == slotID && $0.dayKey == dayKey && $0.deletedAt == nil }
        ))) ?? []
        // A swap replaces the night's single live override, so it must carry
        // the prior move along or "assign to Katie" would silently snap a
        // moved 11:30 back to 11:00. Skips drop the move (no occurrence).
        let inheritedMinute = inheritPriorMove
            ? priors.first { !$0.isSkipped }?.minuteOfDayOverride
            : nil
        for prior in priors {
            prior.deletedAt = .now
            ids.append(prior.id)
        }
        let override = PlanOverride(
            slotID: slotID,
            dayKey: dayKey,
            assignedToID: participant?.id,
            assignedToName: participant?.displayName ?? "",
            assignedToColorHex: participant?.colorHex ?? "",
            isSkipped: isSkipped,
            minuteOfDayOverride: minuteOfDayOverride ?? inheritedMinute,
            // Never a random UUID (the retired ghost-attribution fallback): the
            // stored identity is the next-best truth when `owner` can't resolve.
            createdByID: owner?.id ?? LocalPrefs.shared.myParticipantID ?? UUID()
        )
        context.insert(override)
        ids.append(override.id)
        save()
        sync(save: ids)
        refreshLocalReminders()
        return override
    }

    // MARK: Time-since

    /// Most recent live event of a kind, for the "time since" tiles. Note: an
    /// in-progress sleep reports its `startedAt` (it has no `endedAt` yet), so the
    /// sleep tile reads "since it began" while the active-sleep card shows the
    /// running timer — both intentionally point at the same start.
    func lastEventDate(of kind: EventKind) -> Date? {
        switch kind {
        case .feed:
            var d = FetchDescriptor<FeedEvent>(
                predicate: #Predicate { $0.deletedAt == nil },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            d.fetchLimit = 1
            return (try? context.fetch(d))?.first?.timestamp
        case .sleep:
            var d = FetchDescriptor<SleepEvent>(
                predicate: #Predicate { $0.deletedAt == nil },
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
            d.fetchLimit = 1
            // Use endedAt if available, else startedAt (in-progress shows as the active card)
            if let e = (try? context.fetch(d))?.first { return e.endedAt ?? e.startedAt }
            return nil
        case .diaper:
            var d = FetchDescriptor<DiaperEvent>(
                predicate: #Predicate { $0.deletedAt == nil },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            d.fetchLimit = 1
            return (try? context.fetch(d))?.first?.timestamp
        }
    }

    // MARK: Timeline

    /// Live events within the rolling window, newest first.
    func timeline(since: Date) -> [TimelineEntry] {
        var entries: [TimelineEntry] = []

        let feeds = (try? context.fetch(FetchDescriptor<FeedEvent>(
            predicate: #Predicate { $0.deletedAt == nil && $0.timestamp >= since }
        ))) ?? []
        entries += feeds.map(TimelineEntry.feed)

        // Sleeps: only completed ones — the active sleep shows on its own card.
        let sleeps = (try? context.fetch(FetchDescriptor<SleepEvent>(
            predicate: #Predicate { $0.deletedAt == nil && $0.startedAt >= since }
        ))) ?? []
        entries += sleeps.filter { !$0.isActive }.map(TimelineEntry.sleep)

        let diapers = (try? context.fetch(FetchDescriptor<DiaperEvent>(
            predicate: #Predicate { $0.deletedAt == nil && $0.timestamp >= since }
        ))) ?? []
        entries += diapers.map(TimelineEntry.diaper)

        let notes = (try? context.fetch(FetchDescriptor<NoteEvent>(
            predicate: #Predicate { $0.deletedAt == nil && $0.timestamp >= since }
        ))) ?? []
        entries += notes.map(TimelineEntry.note)

        // Render-level dedupe: duplicate rows sharing an id can exist between
        // sweeps (inbound upsert races, legacy data) — the timeline must never
        // show one event twice even while the store still holds both rows.
        var seen = Set<UUID>()
        return entries
            .sorted { $0.sortDate > $1.sortDate }
            .filter { seen.insert($0.id).inserted }
    }

    // MARK: Private

    /// Persists pending changes. A failure here means an optimistic log the user
    /// already saw never actually saved, so it's surfaced as a banner (not just a
    /// log line) — silent loss is the worst outcome for a tracking app. Returns
    /// whether the save landed: creation paths roll their insert back on false,
    /// because leaving the unsaved row in the context while the banner says
    /// "try again" turns the retry into a duplicate on both phones.
    @discardableResult
    private func save() -> Bool {
        do {
            try context.save()
            return true
        } catch {
            AppLog.store.error("EventStore save failed: \(error.localizedDescription, privacy: .public)")
            if !demo {
                StoreErrorCenter.shared.report("That didn't save. Check your connection and try logging again.")
            }
            return false
        }
    }

    /// Hands changed record ids to the sync engine (no-op when sync is inactive).
    private func sync(save: [UUID] = [], delete: [UUID] = []) {
        guard !demo else { return }
        SyncManager.shared?.enqueueSave(save)
        SyncManager.shared?.enqueueDelete(delete)
    }

    private func reloadWidgets() {
        guard !demo else { return }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Re-arms every reminder surface off current state after a write: the
    /// gentle nudges + daily summary, the slot "you're up" reminders (a logged
    /// feed fulfills its slot and sweeps tonight's request; a plan edit moves it
    /// — and, via sync, moves it to the right phone), and the two AlarmKit
    /// alarms as a sequenced pair — the interval feed alarm's stand-down
    /// decision reads the slot alarm's published fire date, so the slot alarm
    /// must settle first. No-ops in demo.
    private func refreshLocalReminders() {
        guard !demo else { return }
        NotificationManager.refreshScheduledReminders()
        NotificationManager.refreshDailyMilestone()   // keep the summary's counts fresh
        NotificationManager.refreshScheduleReminders()
        let last = lastEventDate(of: .feed)
        let interval = last.flatMap { settings?.feedInterval(after: $0) } ?? 0
        let name = baby?.name ?? "Baby"
        Task {
            await SlotAlarmManager.reschedule()
            await FeedAlarmManager.reschedule(babyName: name, lastFeed: last, interval: interval)
        }
    }
}

/// Sane bounds for event inputs, applied at the store boundary as defense in
/// depth. Untrusted values reach here from natural-language parsing, Siri/App
/// Intents, and the widget, none of which fully validate — clamping here means a
/// 1000 oz parse or a future-dated Shortcut can never persist a nonsense record.
enum EventBounds {
    /// Realistic single-feed range, in ounces. Zero is allowed for "comfort"
    /// nursing entries; the upper bound just blocks runaway parses.
    static let ozRange: ClosedRange<Double> = 0...32

    static func clampOz(_ oz: Double) -> Double {
        guard oz.isFinite else { return 0 }
        return min(max(oz, ozRange.lowerBound), ozRange.upperBound)
    }

    /// Whether an amount is acceptable for a NEW feed log. Unlike `clampOz`
    /// (which sanitizes edits of existing rows), creation rejects zero/negative
    /// outright: a "0 oz" bottle is never a real feed, only the residue of a
    /// bad parse or a defaulted placeholder.
    static func isLoggableOz(_ oz: Double) -> Bool {
        oz.isFinite && oz > 0
    }

    /// Events happen in the past or right now; a future timestamp (clock skew, a
    /// bad parse) is pinned to now so it can't sort ahead of reality.
    static func clampPast(_ date: Date, now: Date = .now) -> Date {
        min(date, now)
    }

    /// Normalizes a plan-slot time into 0..<1440 minutes-from-midnight, wrapping
    /// rather than clamping — 1440 is midnight again, -60 is 11pm.
    static func wrapMinuteOfDay(_ minute: Int) -> Int {
        ((minute % 1440) + 1440) % 1440
    }

    /// Longest note we keep — generous for "spit up, fussy, left side" jottings
    /// while still bounding a paste-bomb from Siri/Shortcuts.
    static let noteMaxLength = 280

    /// Longest standalone NoteEvent text. Roomier than the attached-note cap —
    /// "doctor said…" summaries need a few sentences — but still bounded.
    static let noteEventMaxLength = 500

    /// Trims a free-text note; blank/whitespace-only becomes nil so empty notes
    /// never persist, and over-long input is capped.
    static func cleanNote(_ note: String?, maxLength: Int = noteMaxLength) -> String? {
        guard let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxLength))
    }
}
