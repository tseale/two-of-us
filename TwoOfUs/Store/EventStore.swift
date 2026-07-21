import Foundation
import SwiftData
import WidgetKit
import AppIntents

/// Anything that can be soft-deleted.
protocol SoftDeletable: AnyObject {
    var deletedAt: Date? { get set }
    var id: UUID { get }
}
extension FeedEvent: SoftDeletable {}
extension SleepEvent: SoftDeletable {}
extension DiaperEvent: SoftDeletable {}
extension PlanSlot: SoftDeletable {}
extension PlanOverride: SoftDeletable {}

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
    /// sharing introduces a second participant; falls back to the first record.
    var owner: Participant? {
        if let myID = LocalPrefs.shared.myParticipantID {
            var d = FetchDescriptor<Participant>(predicate: #Predicate { $0.id == myID })
            d.fetchLimit = 1
            if let me = try? context.fetch(d).first { return me }
        }
        return try? context.fetch(FetchDescriptor<Participant>()).first
    }

    var settings: SharedSettings? {
        try? context.fetch(FetchDescriptor<SharedSettings>()).first
    }

    var activeSleep: SleepEvent? {
        let descriptor = FetchDescriptor<SleepEvent>(
            predicate: #Predicate { $0.endedAt == nil && $0.deletedAt == nil }
        )
        return try? context.fetch(descriptor).first
    }

    // MARK: Logging

    @discardableResult
    func logFeed(amountOz: Double, at date: Date = .now, notes: String? = nil) -> FeedEvent {
        let amountOz = EventBounds.clampOz(amountOz)
        let date = EventBounds.clampPast(date)
        let event = FeedEvent(
            baby: baby, amountOz: amountOz, timestamp: date,
            notes: EventBounds.cleanNote(notes),
            loggedByID: owner?.id ?? UUID(),
            loggedByName: owner?.displayName ?? "",
            loggedByColorHex: owner?.colorHex ?? ""
        )
        context.insert(event)
        save()
        sync(save: [event.id])
        reloadWidgets()
        scheduleFeedReminder()
        refreshLocalReminders()
        donate(LogFeedIntent(amountOz: amountOz))
        return event
    }

    @discardableResult
    func logDiaper(_ type: DiaperType, at date: Date = .now, notes: String? = nil) -> DiaperEvent {
        let date = EventBounds.clampPast(date)
        let event = DiaperEvent(
            baby: baby, type: type, timestamp: date,
            notes: EventBounds.cleanNote(notes),
            loggedByID: owner?.id ?? UUID(),
            loggedByName: owner?.displayName ?? "",
            loggedByColorHex: owner?.colorHex ?? ""
        )
        context.insert(event)
        save()
        sync(save: [event.id])
        reloadWidgets()
        refreshLocalReminders()
        donate(LogDiaperIntent(type: DiaperTypeAppEnum(rawValue: type.rawValue) ?? .wet))
        return event
    }

    /// Starts a sleep timer. Refuses if one is already active (single-timer guard).
    @discardableResult
    func startSleep(at date: Date = .now) -> SleepEvent? {
        guard activeSleep == nil else { return nil }
        let date = EventBounds.clampPast(date)
        let event = SleepEvent(
            baby: baby, startedAt: date,
            loggedByID: owner?.id ?? UUID(),
            loggedByName: owner?.displayName ?? "",
            loggedByColorHex: owner?.colorHex ?? ""
        )
        context.insert(event)
        save()
        sync(save: [event.id])
        if !demo { SleepActivityManager.start(babyName: baby?.name ?? "Baby", at: date) }
        reloadWidgets()
        donate(ToggleSleepIntent())
        return event
    }

    func stopSleep(_ event: SleepEvent, at date: Date = .now) {
        event.endedAt = date
        save()
        sync(save: [event.id])
        if !demo { SleepActivityManager.end() }
        reloadWidgets()
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
        if !demo { SleepActivityManager.start(babyName: baby?.name ?? "Baby", at: event.startedAt) }
        reloadWidgets()
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
    func editFeed(_ original: FeedEvent, amountOz: Double, timestamp: Date, notes: String?) -> FeedEvent {
        let amountOz = EventBounds.clampOz(amountOz)
        let timestamp = EventBounds.clampPast(timestamp)
        let replacement = FeedEvent(
            baby: original.baby, amountOz: amountOz, timestamp: timestamp,
            notes: EventBounds.cleanNote(notes),
            loggedByID: original.loggedByID,
            loggedByName: original.loggedByName,
            loggedByColorHex: original.loggedByColorHex,
            editOfID: original.id
        )
        original.deletedAt = .now
        context.insert(replacement)
        save()
        sync(save: [original.id, replacement.id])
        reloadWidgets()
        scheduleFeedReminder()
        refreshLocalReminders()
        return replacement
    }

    @discardableResult
    func editSleep(_ original: SleepEvent, startedAt: Date, endedAt: Date?, notes: String?) -> SleepEvent {
        let replacement = SleepEvent(
            baby: original.baby, startedAt: startedAt, endedAt: endedAt,
            notes: EventBounds.cleanNote(notes),
            loggedByID: original.loggedByID,
            loggedByName: original.loggedByName,
            loggedByColorHex: original.loggedByColorHex,
            editOfID: original.id
        )
        original.deletedAt = .now
        context.insert(replacement)
        save()
        sync(save: [original.id, replacement.id])
        reloadWidgets()
        return replacement
    }

    @discardableResult
    func editDiaper(_ original: DiaperEvent, type: DiaperType, timestamp: Date, notes: String?) -> DiaperEvent {
        let replacement = DiaperEvent(
            baby: original.baby, type: type, timestamp: timestamp,
            notes: EventBounds.cleanNote(notes),
            loggedByID: original.loggedByID,
            loggedByName: original.loggedByName,
            loggedByColorHex: original.loggedByColorHex,
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

    // MARK: Delete / undo

    func softDelete(_ event: any SoftDeletable) {
        event.deletedAt = .now
        save()
        sync(save: [event.id])   // soft delete travels as a `deletedAt` update
        reloadWidgets()
        // Re-arm/cancel the loud alarm too: deleting the latest feed must not leave
        // a "feed due" alarm armed for an event that no longer exists.
        scheduleFeedReminder()
        refreshLocalReminders()
    }

    /// Reverses a `softDelete` — the Undo path for swipe-to-delete. Re-arms the
    /// reminders off the restored state so an undone delete leaves everything as it
    /// was before the swipe.
    func restore(_ event: any SoftDeletable) {
        event.deletedAt = nil
        save()
        sync(save: [event.id])
        reloadWidgets()
        scheduleFeedReminder()
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
        if !demo { SleepActivityManager.end() }   // tear down any running sleep Live Activity
        save()
        sync(save: ids)
        reloadWidgets()
        // No feeds remain → these cancel the pending alarm and clear the gentle
        // reminders/summary rather than leaving them armed for purged events.
        scheduleFeedReminder()
        refreshLocalReminders()
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
    func updateSettings(targetFeedIntervalMinutes: Int? = nil, ozPresets: [Double]? = nil) {
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
        save()
        sync(save: [settings.id])
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
    /// same night so at most one override per (slot, night) is authored here.
    @discardableResult
    func overrideSlot(_ slot: PlanSlot, dayKey: Int, assignTo participant: Participant?) -> PlanOverride {
        insertOverride(slot, dayKey: dayKey, assignedTo: participant, isSkipped: false)
    }

    /// Skips one night of a slot — no occurrence, no reminder on either phone.
    @discardableResult
    func skipSlot(_ slot: PlanSlot, dayKey: Int) -> PlanOverride {
        insertOverride(slot, dayKey: dayKey, assignedTo: nil, isSkipped: true)
    }

    /// Undoes a swap/skip — the standing assignment resumes for that night.
    func clearOverride(_ override: PlanOverride) {
        override.deletedAt = .now
        save()
        sync(save: [override.id])
        refreshLocalReminders()
    }

    private func insertOverride(_ slot: PlanSlot, dayKey: Int, assignedTo participant: Participant?,
                                isSkipped: Bool) -> PlanOverride {
        var ids: [UUID] = []
        let slotID = slot.id
        let priors = (try? context.fetch(FetchDescriptor<PlanOverride>(
            predicate: #Predicate { $0.slotID == slotID && $0.dayKey == dayKey && $0.deletedAt == nil }
        ))) ?? []
        for prior in priors {
            prior.deletedAt = .now
            ids.append(prior.id)
        }
        let override = PlanOverride(
            slotID: slot.id,
            dayKey: dayKey,
            assignedToID: participant?.id,
            assignedToName: participant?.displayName ?? "",
            assignedToColorHex: participant?.colorHex ?? "",
            isSkipped: isSkipped,
            createdByID: owner?.id ?? UUID()
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

        return entries.sorted { $0.sortDate > $1.sortDate }
    }

    // MARK: Private

    /// Persists pending changes. A failure here means an optimistic log the user
    /// already saw never actually saved, so it's surfaced as a banner (not just a
    /// log line) — silent loss is the worst outcome for a tracking app.
    private func save() {
        do {
            try context.save()
        } catch {
            AppLog.store.error("EventStore save failed: \(error.localizedDescription, privacy: .public)")
            guard !demo else { return }
            StoreErrorCenter.shared.report("That didn't save. Check your connection and try logging again.")
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

    /// Re-arms this device's AlarmKit feed reminder off the latest feed + the
    /// shared target interval. Honors the per-device opt-in inside the manager.
    private func scheduleFeedReminder() {
        guard !demo else { return }
        let interval = settings?.targetFeedInterval ?? 0
        let last = lastEventDate(of: .feed)
        let name = baby?.name ?? "Baby"
        Task { await FeedAlarmManager.reschedule(babyName: name, lastFeed: last, interval: interval) }
    }

    /// Re-arms the gentle "feed/diaper due" local notifications off current state.
    /// Distinct from `scheduleFeedReminder` (the loud AlarmKit alarm); no-ops in
    /// demo and when the user hasn't opted into gentle reminders.
    private func refreshLocalReminders() {
        guard !demo else { return }
        NotificationManager.refreshScheduledReminders()
        NotificationManager.refreshDailyMilestone()   // keep the summary's counts fresh
        // Slot reminders + the opt-in slot alarm re-plan off every write: a
        // logged feed fulfills its slot (sweeping tonight's request), and a plan
        // edit moves both to the right time — and, via sync, the right phone.
        NotificationManager.refreshScheduleReminders()
        Task { await SlotAlarmManager.reschedule() }
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

    /// Trims a free-text note; blank/whitespace-only becomes nil so empty notes
    /// never persist, and over-long input is capped.
    static func cleanNote(_ note: String?) -> String? {
        guard let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(noteMaxLength))
    }
}
