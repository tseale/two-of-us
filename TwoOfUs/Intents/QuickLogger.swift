import Foundation
import SwiftData
import WidgetKit

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
    let context: ModelContext

    static func make() -> QuickLogger? {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config: ModelConfiguration
        if let storeURL = AppGroup.storeURL {
            config = ModelConfiguration(schema: schema, url: storeURL)
        } else {
            // Fallback (Simulator without the App Group entitlement): cannot
            // actually share with the app, but keeps the intent functional.
            config = ModelConfiguration(schema: schema)
        }
        guard let container = try? ModelContainer(for: schema, configurations: [config]) else {
            return nil
        }
        return QuickLogger(context: ModelContext(container))
    }

    // MARK: Lookups

    private var baby: Baby? { try? context.fetch(FetchDescriptor<Baby>()).first }
    private var settings: SharedSettings? { try? context.fetch(FetchDescriptor<SharedSettings>()).first }

    /// The local user ("me"), resolved via the App Group-shared participant id so
    /// the extension stamps the same identity the app does. Falls back to first.
    private var owner: Participant? {
        if let s = AppGroup.userDefaults?.string(forKey: "sync.myParticipantID"), let myID = UUID(uuidString: s) {
            var d = FetchDescriptor<Participant>(predicate: #Predicate { $0.id == myID })
            d.fetchLimit = 1
            if let me = try? context.fetch(d).first { return me }
        }
        return try? context.fetch(FetchDescriptor<Participant>()).first
    }

    var babyName: String? { baby?.name }

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

    /// Shared target feed interval (seconds), defaulting to 3h. Used to re-arm
    /// the AlarmKit feed reminder on app foreground.
    var targetFeedInterval: TimeInterval { settings?.targetFeedInterval ?? TimeInterval(180 * 60) }

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

    @discardableResult
    func logFeed(amountOz: Double) -> FeedEvent {
        let event = FeedEvent(
            baby: baby, amountOz: amountOz, timestamp: .now,
            loggedByID: owner?.id ?? UUID(),
            loggedByName: owner?.displayName ?? "",
            loggedByColorHex: owner?.colorHex ?? ""
        )
        context.insert(event)
        commit(syncing: [event.id])
        return event
    }

    @discardableResult
    func logDiaper(_ type: DiaperType) -> DiaperEvent {
        let event = DiaperEvent(
            baby: baby, type: type, timestamp: .now,
            loggedByID: owner?.id ?? UUID(),
            loggedByName: owner?.displayName ?? "",
            loggedByColorHex: owner?.colorHex ?? ""
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
    /// - Returns: true if a sleep was started, false if one was stopped.
    @discardableResult
    func toggleSleep() -> Bool {
        if let active = activeSleep {
            active.endedAt = .now
            commit(syncing: [active.id])
            return false
        }
        let event = SleepEvent(
            baby: baby, startedAt: .now,
            loggedByID: owner?.id ?? UUID(),
            loggedByName: owner?.displayName ?? "",
            loggedByColorHex: owner?.colorHex ?? ""
        )
        context.insert(event)
        commit(syncing: [event.id])
        return true
    }

    private func commit(syncing ids: [UUID]) {
        do { try context.save() } catch { print("QuickLogger save error: \(error)") }
        // The extension can't reach the sync engine — queue the ids in the App
        // Group for the app to push (SyncManager.drainExtensionQueue) next launch.
        if let d = AppGroup.userDefaults {
            var arr = d.array(forKey: "sync.pendingWidgetWrites") as? [String] ?? []
            arr += ids.map(\.uuidString)
            d.set(arr, forKey: "sync.pendingWidgetWrites")
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
