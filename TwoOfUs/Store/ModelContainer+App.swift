import Foundation
import SwiftData

enum AppModelContainer {
    /// The one real (on-disk) container for the app process. Both the SwiftUI
    /// tree and `SyncManager` must use this instance — and it must be reachable
    /// WITHOUT the UI existing, because a background launch for a CloudKit
    /// silent push never connects a scene.
    static let shared: ModelContainer = make()

    /// True when the process is running against the last-resort in-memory
    /// fallback below. `SyncManager` must not persist engine fetch tokens for a
    /// throwaway store: a token written past records the REAL store never saw
    /// means those records are never fetched again after the store heals.
    private(set) static var isEphemeralFallback = false

    /// Main app container — stored in the App Group container so the widget
    /// extension can read the same data. CloudKit sync is driven by `SyncManager`
    /// (CKSyncEngine), NOT SwiftData's `.automatic`: shared-database / CKShare sync
    /// between the two parents is impossible through SwiftData, and two systems
    /// can't mirror one store. `cloudKitDatabase: .none` is load-bearing on EVERY
    /// config: the default is `.automatic`, and with the app's iCloud entitlement
    /// that silently boots SwiftData's own mirroring — a second sync channel that
    /// mints duplicate rows behind CKSyncEngine's back and re-imports long-deleted
    /// history after any store reset. Falls back to the default app-support
    /// location when the App Group entitlement is not configured (Simulator
    /// without signing).
    static func make(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        if inMemory {
            return build(schema: schema, config: ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        }

        let storeURL = AppGroup.storeURL
        let config = storeURL.map { ModelConfiguration(schema: schema, url: $0, cloudKitDatabase: .none) }
            // Fallback: Simulator / no App Group entitlement
            ?? ModelConfiguration(schema: schema, cloudKitDatabase: .none)

        do {
            return try open(schema: schema, config: config)
        } catch {
            // A store written by a newer OS/SwiftData version (e.g. an iOS-beta
            // store format), an interrupted migration, or a corrupt file makes
            // ModelContainer throw — which would otherwise crash the app on its
            // very first frame. The on-disk store is only a local cache here:
            // CloudKit (CKSyncEngine) is the source of truth and re-bootstraps
            // (see SyncManager). So move the unreadable store aside and retry
            // rather than fatal-erroring at launch.
            AppLog.store.error("ModelContainer open failed (\(error)); quarantining store and retrying.")
            if let storeURL { quarantineStore(at: storeURL) }
            // The store's rows are gone, so every piece of persisted sync state
            // is now a lie: the engine fetch tokens say "fully caught up" (the
            // fresh empty store would never re-download the family's history —
            // the owner lands back in onboarding and mints a duplicate
            // Baby/Participant into the still-populated zone) and the bootstrap
            // flag says "already uploaded". Reset both so the next engine start
            // re-fetches the whole zone into the fresh store.
            SyncManager.resetPersistedSyncStateForStoreLoss()
            do {
                return try open(schema: schema, config: config)
            } catch {
                // Last resort: launch against an in-memory store so the app still
                // opens; sync repopulates it from CloudKit on this run.
                AppLog.store.error("ModelContainer still failed after reset (\(error)); falling back to in-memory.")
                isEphemeralFallback = true
                return build(schema: schema, config: ModelConfiguration(
                    schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
            }
        }
    }

    private static func open(schema: Schema, config: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            migrationPlan: TwoOfUsMigrationPlan.self,
            configurations: [config]
        )
    }

    /// In-memory / known-good configs can't fail; if one somehow does there's no
    /// store to recover, so this is the one place a trap is still appropriate.
    private static func build(schema: Schema, config: ModelConfiguration) -> ModelContainer {
        do {
            return try open(schema: schema, config: config)
        } catch {
            fatalError("Failed to create in-memory ModelContainer: \(error)")
        }
    }

    /// Removes the SQLite store and its `-wal`/`-shm` sidecar files so the next
    /// `ModelContainer` opens a fresh, empty store. Safe because the local store
    /// is a cache that CloudKit re-bootstraps.
    private static func quarantineStore(at storeURL: URL) {
        let fm = FileManager.default
        // SQLite sidecars use a hyphen suffix: `twoofus.sqlite-wal` / `-shm`.
        let base = storeURL.deletingLastPathComponent()
        let name = storeURL.lastPathComponent
        for url in [storeURL,
                    base.appendingPathComponent(name + "-wal"),
                    base.appendingPathComponent(name + "-shm")] {
            try? fm.removeItem(at: url)
        }
    }

    /// In-memory container for SwiftUI previews and tests.
    @MainActor static let preview: ModelContainer = {
        let container = make(inMemory: true)
        SeedData.seedIfNeeded(in: container.mainContext, babyName: "Charlie")
        SeedData.seedSampleEvents(in: container.mainContext)
        return container
    }()
}
