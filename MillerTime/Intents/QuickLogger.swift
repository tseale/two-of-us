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

    func logFeed(amountOz: Double) {
        let event = FeedEvent(
            baby: baby, amountOz: amountOz, timestamp: .now,
            loggedByID: owner?.id ?? UUID(),
            loggedByName: owner?.displayName ?? "",
            loggedByColorHex: owner?.colorHex ?? ""
        )
        context.insert(event)
        commit(syncing: [event.id])
    }

    func logDiaper(_ type: DiaperType) {
        let event = DiaperEvent(
            baby: baby, type: type, timestamp: .now,
            loggedByID: owner?.id ?? UUID(),
            loggedByName: owner?.displayName ?? "",
            loggedByColorHex: owner?.colorHex ?? ""
        )
        context.insert(event)
        commit(syncing: [event.id])
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
