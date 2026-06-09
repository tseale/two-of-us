import Foundation
import SwiftData
import CloudKit
import WidgetKit

/// Owns the CloudKit sync layer for Miller Time.
///
/// SwiftData stays the local source of truth; this drives a `CKSyncEngine`
/// (per database scope) that mirrors records to a custom zone. The owner runs the
/// `.private` engine on a zone they can share; the joining parent runs the
/// `.shared` engine against the owner's zone. See the plan and
/// [[widget-cloudkit-architecture]] for the rationale.
@MainActor
final class SyncManager: NSObject, CKSyncEngineDelegate {
    static var shared: SyncManager?

    private let modelContainer: ModelContainer
    private var privateEngine: CKSyncEngine?
    private var sharedEngine: CKSyncEngine?

    /// Discovered when the participant fetches the shared database's zones.
    private var sharedZoneID: CKRecordZone.ID?

    private var context: ModelContext { modelContainer.mainContext }

    private var privateZoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: SyncConstants.zoneName, ownerName: CKCurrentUserDefaultName)
    }

    /// The engine + zone this device writes through, based on its role.
    private var activeEngine: CKSyncEngine? {
        LocalPrefs.shared.syncRole == .participant ? sharedEngine : privateEngine
    }
    private var activeZoneID: CKRecordZone.ID? {
        LocalPrefs.shared.syncRole == .participant ? sharedZoneID : privateZoneID
    }

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        super.init()
    }

    // MARK: Lifecycle

    /// True only when the device can actually use CloudKit. Guards against
    /// `CKContainer(identifier:)` fatal-trapping when the iCloud entitlement/
    /// container isn't available (unsigned builds, or no iCloud account signed in).
    private var cloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    /// Starts the engine(s) appropriate to this device's role. Safe to call once
    /// at launch; no-ops without iCloud (the app still works fully offline/local).
    func start() {
        guard cloudAvailable else { return }
        switch LocalPrefs.shared.syncRole {
        case .solo, .owner:
            startPrivateEngine()
        case .participant:
            startSharedEngine()
        }
    }

    private func startPrivateEngine() {
        guard privateEngine == nil else { return }
        var config = CKSyncEngine.Configuration(
            database: SyncConstants.container.privateCloudDatabase,
            stateSerialization: loadState(.private),
            delegate: self
        )
        config.automaticallySync = true
        privateEngine = CKSyncEngine(config)
        // Ensure the custom zone exists, then push anything not yet uploaded.
        privateEngine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: privateZoneID))])
        bootstrapReconcileIfNeeded(scope: "private")
    }

    private func startSharedEngine() {
        guard sharedEngine == nil else { return }
        var config = CKSyncEngine.Configuration(
            database: SyncConstants.container.sharedCloudDatabase,
            stateSerialization: loadState(.shared),
            delegate: self
        )
        config.automaticallySync = true
        sharedEngine = CKSyncEngine(config)
    }

    /// Called after the user accepts a share — becomes a participant and starts
    /// syncing the owner's shared zone.
    func didAcceptShare() {
        guard cloudAvailable else { return }
        LocalPrefs.shared.syncRole = .participant
        UserDefaults.standard.removeObject(forKey: "sync.bootstrap.shared")
        startSharedEngine()
        Task { try? await sharedEngine?.fetchChanges() }
    }

    /// Forward a received remote (silent push) notification so the engine pulls
    /// changes promptly — this is what keeps the other parent's widget fresh.
    func handleRemoteNotification() {
        Task {
            try? await privateEngine?.fetchChanges()
            try? await sharedEngine?.fetchChanges()
        }
    }

    // MARK: Enqueue local changes

    func enqueueSave(_ ids: [UUID]) {
        guard let engine = activeEngine, let zoneID = activeZoneID, !ids.isEmpty else { return }
        let changes = ids.map { CKSyncEngine.PendingRecordZoneChange.saveRecord(CKRecord.ID(recordName: $0.uuidString, zoneID: zoneID)) }
        engine.state.add(pendingRecordZoneChanges: changes)
    }

    func enqueueDelete(_ ids: [UUID]) {
        guard let engine = activeEngine, let zoneID = activeZoneID, !ids.isEmpty else { return }
        let changes = ids.map { CKSyncEngine.PendingRecordZoneChange.deleteRecord(CKRecord.ID(recordName: $0.uuidString, zoneID: zoneID)) }
        engine.state.add(pendingRecordZoneChanges: changes)
    }

    /// Drains record ids written by the widget/Siri extension (which can't reach
    /// the engine) and enqueues them. Called when the app becomes active.
    func drainExtensionQueue() {
        let key = "sync.pendingWidgetWrites"
        guard let raw = AppGroup.userDefaults?.array(forKey: key) as? [String], !raw.isEmpty else { return }
        enqueueSave(raw.compactMap(UUID.init))
        AppGroup.userDefaults?.removeObject(forKey: key)
    }

    /// One-time push of all existing local records into the (new) zone.
    private func bootstrapReconcileIfNeeded(scope: String) {
        let key = "sync.bootstrap.\(scope)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        enqueueSave(allLocalIDs())
        UserDefaults.standard.set(true, forKey: key)
    }

    private func allLocalIDs() -> [UUID] {
        var ids: [UUID] = []
        ids += (try? context.fetch(FetchDescriptor<Baby>()))?.map(\.id) ?? []
        ids += (try? context.fetch(FetchDescriptor<Participant>()))?.map(\.id) ?? []
        ids += (try? context.fetch(FetchDescriptor<SharedSettings>()))?.map(\.id) ?? []
        ids += (try? context.fetch(FetchDescriptor<FeedEvent>()))?.map(\.id) ?? []
        ids += (try? context.fetch(FetchDescriptor<SleepEvent>()))?.map(\.id) ?? []
        ids += (try? context.fetch(FetchDescriptor<DiaperEvent>()))?.map(\.id) ?? []
        return ids
    }

    // MARK: CKSyncEngineDelegate

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let e):
            saveState(e.stateSerialization, scope: scope(for: syncEngine))

        case .fetchedDatabaseChanges(let e):
            // Participant: capture the owner's shared zone the first time we see it.
            if syncEngine === sharedEngine {
                for change in e.modifications {
                    sharedZoneID = change.zoneID
                }
            }

        case .fetchedRecordZoneChanges(let e):
            for mod in e.modifications {
                RecordMapping.apply(mod.record, in: context)
            }
            for del in e.deletions {
                RecordMapping.delete(recordName: del.recordID.recordName, in: context)
            }
            try? context.save()
            WidgetCenter.shared.reloadAllTimelines()

        case .sentRecordZoneChanges(let e):
            for failed in e.failedRecordSaves {
                if let ckError = failed.error as? CKError, ckError.code == .serverRecordChanged,
                   let serverRecord = ckError.serverRecord {
                    // Last-writer-wins: take the server's copy.
                    RecordMapping.apply(serverRecord, in: context)
                }
            }
            try? context.save()

        case .accountChange(let e):
            handleAccountChange(e)

        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !pending.isEmpty else { return nil }

        // Pre-build records on the main actor (SwiftData reads) so the provider is a pure lookup.
        var records: [CKRecord.ID: CKRecord] = [:]
        for change in pending {
            if case .saveRecord(let id) = change {
                if let r = RecordMapping.record(forRecordName: id.recordName, recordID: id, in: self.context) {
                    records[id] = r
                } else {
                    // No live local model — drop the stale pending change.
                    syncEngine.state.remove(pendingRecordZoneChanges: [change])
                }
            }
        }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            records[recordID]
        }
    }

    // MARK: Sharing (owner)

    /// Creates (or returns the existing) zone-wide CKShare so the owner can invite
    /// the co-parent. Marks this device the owner.
    enum SyncError: Error { case iCloudUnavailable }

    func makeShare() async throws -> CKShare {
        // Demo mode runs against a throwaway store; never touch the real iCloud zone.
        guard !LocalPrefs.shared.demoModeEnabled else { throw SyncError.iCloudUnavailable }
        guard cloudAvailable else { throw SyncError.iCloudUnavailable }
        LocalPrefs.shared.syncRole = .owner
        startPrivateEngine()
        let db = SyncConstants.container.privateCloudDatabase

        // Ensure the zone exists before sharing it.
        _ = try? await db.save(CKRecordZone(zoneID: privateZoneID))

        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: privateZoneID)
        if let existing = try? await db.record(for: shareID) as? CKShare {
            return existing
        }
        let share = CKShare(recordZoneID: privateZoneID)
        share[CKShare.SystemFieldKey.title] = "Miller Time" as CKRecordValue
        _ = try await db.modifyRecords(saving: [share], deleting: [])
        return share
    }

    /// Owner stops sharing: deletes the share (co-parent loses access).
    func stopSharing() async {
        guard !LocalPrefs.shared.demoModeEnabled else { return }
        let db = SyncConstants.container.privateCloudDatabase
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: privateZoneID)
        _ = try? await db.modifyRecords(saving: [], deleting: [shareID])
        LocalPrefs.shared.syncRole = .solo
    }

    /// Owner removes a single co-parent from the share — the others keep access
    /// (unlike `stopSharing`, which removes everyone). Matches the CKShare
    /// participant by `cloudUserID` when known; with only one co-parent it falls
    /// back to removing the sole non-owner participant. Marks the local record
    /// inactive (its past logs still render via denormalized identity) and syncs.
    func removeParticipant(_ participant: Participant) async {
        // In demo the participant belongs to the in-memory store and there's no real
        // share to mutate — leave the seeded People list intact.
        guard !LocalPrefs.shared.demoModeEnabled else { return }
        if cloudAvailable {
            let db = SyncConstants.container.privateCloudDatabase
            let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: privateZoneID)
            if let share = try? await db.record(for: shareID) as? CKShare {
                let removable = share.participants.filter { $0.role != .owner }
                let target = removable.first { $0.userIdentity.userRecordID?.recordName == participant.cloudUserID }
                    ?? (removable.count == 1 ? removable.first : nil)
                if let target {
                    share.removeParticipant(target)
                    _ = try? await db.modifyRecords(saving: [share], deleting: [])
                }
            }
        }
        participant.isActive = false
        try? context.save()
        enqueueSave([participant.id])
    }

    /// Permanently deletes ALL data and resets this device to a fresh solo install.
    /// Owner/solo: deletes the private zone (server-side cascade removes every
    /// record and the zone-wide share, so the co-parent loses the data too).
    /// Participant: can't delete the owner's zone, so this just wipes the local
    /// copy. Either way the local store is cleared, sync state dropped, and
    /// `LocalPrefs` reset — `RootView` then returns to onboarding.
    func deleteEverything() async {
        guard !LocalPrefs.shared.demoModeEnabled else { return }
        if cloudAvailable, LocalPrefs.shared.syncRole != .participant {
            let db = SyncConstants.container.privateCloudDatabase
            _ = try? await db.modifyRecordZones(saving: [], deleting: [privateZoneID])
        }
        // Stop engines and drop persisted sync state so a fresh start re-bootstraps.
        privateEngine = nil
        sharedEngine = nil
        sharedZoneID = nil
        try? FileManager.default.removeItem(at: stateURL(.private))
        try? FileManager.default.removeItem(at: stateURL(.shared))
        UserDefaults.standard.removeObject(forKey: "sync.bootstrap.private")
        UserDefaults.standard.removeObject(forKey: "sync.bootstrap.shared")

        wipeLocalModels()

        LocalPrefs.shared.syncRole = .solo
        LocalPrefs.shared.myParticipantID = nil
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Hard-deletes every local model (events cascade from Baby, but we clear all
    /// types explicitly to also drop participants and settings).
    private func wipeLocalModels() {
        try? context.delete(model: FeedEvent.self)
        try? context.delete(model: SleepEvent.self)
        try? context.delete(model: DiaperEvent.self)
        try? context.delete(model: Participant.self)
        try? context.delete(model: SharedSettings.self)
        try? context.delete(model: Baby.self)
        try? context.save()
    }

    // MARK: Sharing (participant)

    /// Participant leaves the share: stops the shared engine and reverts to solo.
    /// Local copies of the owner's data remain on-device but stop updating.
    func leaveShare() {
        guard !LocalPrefs.shared.demoModeEnabled else { return }
        sharedEngine = nil
        sharedZoneID = nil
        try? FileManager.default.removeItem(at: stateURL(.shared))
        UserDefaults.standard.removeObject(forKey: "sync.bootstrap.shared")
        LocalPrefs.shared.syncRole = .solo
    }

    // MARK: State persistence

    private func handleAccountChange(_ event: CKSyncEngine.Event.AccountChange) {
        switch event.changeType {
        case .signOut, .switchAccounts:
            // Drop sync state; local data stays. A fresh sign-in re-bootstraps.
            try? FileManager.default.removeItem(at: stateURL(.private))
            try? FileManager.default.removeItem(at: stateURL(.shared))
        default:
            break
        }
    }

    private func scope(for engine: CKSyncEngine) -> CKDatabase.Scope {
        engine === sharedEngine ? .shared : .private
    }

    private func stateURL(_ scope: CKDatabase.Scope) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("sync-state-\(scope == .shared ? "shared" : "private").data")
    }

    private func loadState(_ scope: CKDatabase.Scope) -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: stateURL(scope)) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func saveState(_ state: CKSyncEngine.State.Serialization, scope: CKDatabase.Scope) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateURL(scope))
    }
}
