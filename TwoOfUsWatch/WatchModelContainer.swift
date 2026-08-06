import Foundation
import SwiftData

enum WatchModelContainer {
    /// The one on-disk container for the watch process. Lives in the watch's
    /// App Group container so the complication extension reads the same store.
    /// (The watch's App Group is device-local — it is NOT the phone's store;
    /// the two devices converge through CloudKit, not shared files.)
    @MainActor static let shared: ModelContainer = make()

    /// True when running against the in-memory fallback below — the sync layer
    /// must not persist fetch tokens for a throwaway store (see the phone's
    /// `AppModelContainer.isEphemeralFallback` for the full rationale).
    private(set) static var isEphemeralFallback = false

    #if DEBUG
    /// Demo run (`-watchDemoData` launch argument): in-memory store seeded
    /// with sample data so the UI is try-able on a simulator with no iCloud
    /// account. `TwoOfUsWatchApp` also skips the sync bootstrap under this
    /// flag, so nothing here can ever reach the family's real zone.
    static var isDemoRun: Bool {
        ProcessInfo.processInfo.arguments.contains("-watchDemoData")
    }
    #else
    static let isDemoRun = false
    #endif

    @MainActor
    static func make() -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        #if DEBUG
        if isDemoRun {
            isEphemeralFallback = true  // belt-and-braces: never persist sync state for a demo store
            do {
                let container = try open(schema: schema, config: ModelConfiguration(
                    schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
                seedDemoData(in: container)
                return container
            } catch {
                fatalError("Failed to create demo ModelContainer: \(error)")
            }
        }
        #endif
        // `cloudKitDatabase: .none` is load-bearing: with the watch app's
        // iCloud entitlement, the default `.automatic` would boot SwiftData's
        // own mirroring — a second sync channel fighting WatchSyncManager.
        let storeURL = AppGroup.storeURL
        let config = storeURL.map { ModelConfiguration(schema: schema, url: $0, cloudKitDatabase: .none) }
            ?? ModelConfiguration(schema: schema, cloudKitDatabase: .none)

        do {
            return try open(schema: schema, config: config)
        } catch {
            // The watch store is purely a cache of the zone — quarantine an
            // unreadable file, drop the (now lying) fetch token, and retry.
            AppLog.store.error("Watch ModelContainer open failed (\(error)); quarantining store and retrying.")
            if let storeURL { quarantineStore(at: storeURL) }
            resetPersistedSyncState()
            do {
                return try open(schema: schema, config: config)
            } catch {
                AppLog.store.error("Watch ModelContainer still failed after reset (\(error)); falling back to in-memory.")
                isEphemeralFallback = true
                do {
                    return try open(schema: schema, config: ModelConfiguration(
                        schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
                } catch {
                    fatalError("Failed to create in-memory ModelContainer: \(error)")
                }
            }
        }
    }

    #if DEBUG
    /// One baby, one active participant (so QuickLogger's sole-participant
    /// fallback resolves identity with no iCloud), and a recent event of each
    /// kind. Timestamps are relative so the rows always show something alive.
    @MainActor
    private static func seedDemoData(in container: ModelContainer) {
        let ctx = container.mainContext
        let baby = Baby(name: "Miller", dateOfBirth: Calendar.current.date(byAdding: .month, value: -2, to: .now) ?? .now)
        ctx.insert(baby)
        let me = Participant(displayName: "Taylor", colorHex: "5AC8B8", role: .full)
        ctx.insert(me)
        let settings = SharedSettings()
        ctx.insert(settings)
        ctx.insert(FeedEvent(baby: baby, amountOz: 4, timestamp: .now.addingTimeInterval(-135 * 60),
                             loggedByID: me.id, loggedByName: me.displayName, loggedByColorHex: me.colorHex))
        ctx.insert(DiaperEvent(baby: baby, type: .wet, timestamp: .now.addingTimeInterval(-45 * 60),
                               loggedByID: me.id, loggedByName: me.displayName, loggedByColorHex: me.colorHex))
        let nap = SleepEvent(baby: baby, startedAt: .now.addingTimeInterval(-4 * 3600),
                             loggedByID: me.id, loggedByName: me.displayName, loggedByColorHex: me.colorHex)
        nap.endedAt = .now.addingTimeInterval(-3 * 3600)
        ctx.insert(nap)
        try? ctx.save()
    }
    #endif

    private static func open(schema: Schema, config: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            migrationPlan: TwoOfUsMigrationPlan.self,
            configurations: [config]
        )
    }

    /// The store was destroyed — the engine fetch token describes the dead
    /// store and would stop the fresh one from ever re-fetching the zone.
    private static func resetPersistedSyncState() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("watch-sync-state.data"))
    }

    private static func quarantineStore(at storeURL: URL) {
        let fm = FileManager.default
        let base = storeURL.deletingLastPathComponent()
        let name = storeURL.lastPathComponent
        for url in [storeURL,
                    base.appendingPathComponent(name + "-wal"),
                    base.appendingPathComponent(name + "-shm")] {
            try? fm.removeItem(at: url)
        }
    }
}
