import Foundation
import SwiftData
import CloudKit
import WidgetKit

/// CloudKit sync for the watch app — a deliberately small sibling of the
/// phone's `SyncManager`, sharing `RecordMapping`/`SyncConstants` so both
/// speak the exact same record dialect against the same zone.
///
/// The watch is a *cache device*: it never creates the zone, never creates or
/// accepts shares, and never bulk-uploads local state. The phone owns all of
/// that. The watch discovers which database holds the family's zone (shared →
/// this account joined someone's share; private → this account owns/solo),
/// runs ONE engine against it, applies fetches into its own local store, and
/// sends only the events logged here.
///
/// The phone's two invariants carry over unchanged:
/// 1. Outbound saves of existing records carry the server change tag
///    (`ckSystemFields` via `RecordMapping`).
/// 2. A queued local change may be parked but never dropped.
@MainActor
final class WatchSyncManager: NSObject, CKSyncEngineDelegate {
    static var shared: WatchSyncManager?

    static func bootstrap(container: ModelContainer) {
        if shared == nil { shared = WatchSyncManager(modelContainer: container) }
        shared?.start()
    }

    /// Which database the family zone lives in for this account. Persisted so
    /// a cold launch goes straight to the right engine; `.unknown` re-runs
    /// discovery on every start until the phone has provisioned the zone.
    enum Role: String {
        case unknown, owner, participant
    }

    private enum Keys {
        static let role = "watchsync.role"
        static let sharedZoneName = "watchsync.sharedZone.name"
        static let sharedZoneOwner = "watchsync.sharedZone.owner"
        static let pendingSaves = "watchsync.pendingSaves"
        static let pendingDeletes = "watchsync.pendingDeletes"
        /// Same per-key queue `QuickLogger.commit` writes (App Group defaults) —
        /// on the watch this process drains it into its own engine.
        static let loggerWritePrefix = "sync.widgetWrite."
        static let myParticipantID = "sync.myParticipantID"
    }

    /// Posted after a fetch batch is applied so views not driven by @Query
    /// (and the complication reload path) can react.
    static let didApplyRemoteChanges = Notification.Name("WatchSyncDidApplyRemoteChanges")

    private let modelContainer: ModelContainer
    private var engine: CKSyncEngine?
    private var discovering = false

    private var context: ModelContext { modelContainer.mainContext }

    private(set) var role: Role {
        get { Role(rawValue: UserDefaults.standard.string(forKey: Keys.role) ?? "") ?? .unknown }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Keys.role) }
    }

    /// The zone events are written to: the owner's zone in the shared database
    /// (participant) or this account's own private zone (owner/solo).
    private var zoneID: CKRecordZone.ID? {
        switch role {
        case .participant:
            guard let name = UserDefaults.standard.string(forKey: Keys.sharedZoneName),
                  let owner = UserDefaults.standard.string(forKey: Keys.sharedZoneOwner) else { return nil }
            return CKRecordZone.ID(zoneName: name, ownerName: owner)
        case .owner:
            return CKRecordZone.ID(zoneName: SyncConstants.zoneName, ownerName: CKCurrentUserDefaultName)
        case .unknown:
            return nil
        }
    }

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        super.init()
        NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: nil) { _ in
            Task { @MainActor in WatchSyncManager.shared?.start() }
        }
    }

    // MARK: Lifecycle

    func start() {
        Task { await ensureStarted() }
    }

    func ensureStarted() async {
        guard (try? await SyncConstants.container.accountStatus()) == .available else { return }
        if role == .unknown {
            await discoverRole()
        }
        guard role != .unknown else { return }
        startEngine()
        drainLoggerQueue()
        drainPendingChanges()
        await resolveIdentityIfNeeded()
    }

    /// Foreground refresh: pull whatever the phones pushed since last time.
    /// This is the watch's primary freshness path — there's no reliable
    /// background push on watchOS, so every activation fetches.
    func fetchNow() async {
        await ensureStarted()
        guard let engine else { return }
        try? await engine.fetchChanges()
    }

    /// Finds the family zone. Shared database wins: an account attached to a
    /// share must write to the owner's zone even if a stale pre-join private
    /// zone still exists server-side (the phone's join flow wipes the local
    /// copy but leaves the old private zone behind).
    private func discoverRole() async {
        guard !discovering else { return }
        discovering = true
        defer { discovering = false }

        if let zones = try? await SyncConstants.container.sharedCloudDatabase.allRecordZones(),
           let zone = zones.first(where: { $0.zoneID.zoneName == SyncConstants.zoneName }) {
            UserDefaults.standard.set(zone.zoneID.zoneName, forKey: Keys.sharedZoneName)
            UserDefaults.standard.set(zone.zoneID.ownerName, forKey: Keys.sharedZoneOwner)
            role = .participant
            AppLog.sync.log("Watch discovered role: participant (zone owner \(zone.zoneID.ownerName, privacy: .public))")
            return
        }
        if let zones = try? await SyncConstants.container.privateCloudDatabase.allRecordZones(),
           zones.contains(where: { $0.zoneID.zoneName == SyncConstants.zoneName }) {
            role = .owner
            AppLog.sync.log("Watch discovered role: owner")
            return
        }
        // Either the phone hasn't set up yet or a zone listing failed —
        // stay unknown and retry on the next activation.
        AppLog.sync.log("Watch role discovery found no family zone yet")
    }

    private func startEngine() {
        guard engine == nil, let db = database else { return }
        var config = CKSyncEngine.Configuration(
            database: db,
            stateSerialization: loadState(),
            delegate: self
        )
        config.automaticallySync = true
        engine = CKSyncEngine(config)
    }

    private var database: CKDatabase? {
        switch role {
        case .participant: SyncConstants.container.sharedCloudDatabase
        case .owner: SyncConstants.container.privateCloudDatabase
        case .unknown: nil
        }
    }

    /// The family zone is no longer reachable for this role (share revoked,
    /// owner deleted everything, account switched). The watch holds only a
    /// cache — drop it and rediscover from scratch next activation.
    private func resetToUnknown(reason: String) {
        AppLog.sync.warning("Watch sync reset (\(reason, privacy: .public)) — wiping local cache and rediscovering")
        if let engine {
            parkUnsentChanges(engine.state.pendingRecordZoneChanges)
        }
        engine = nil
        try? FileManager.default.removeItem(at: stateURL())
        role = .unknown
        UserDefaults.standard.removeObject(forKey: Keys.sharedZoneName)
        UserDefaults.standard.removeObject(forKey: Keys.sharedZoneOwner)
        AppGroup.userDefaults?.removeObject(forKey: Keys.myParticipantID)
        wipeLocalModels()
        WidgetCenter.shared.reloadAllTimelines()
        NotificationCenter.default.post(name: Self.didApplyRemoteChanges, object: nil)
    }

    private func wipeLocalModels() {
        try? context.delete(model: FeedEvent.self)
        try? context.delete(model: SleepEvent.self)
        try? context.delete(model: DiaperEvent.self)
        try? context.delete(model: NoteEvent.self)
        try? context.delete(model: PlanSlot.self)
        try? context.delete(model: PlanOverride.self)
        try? context.delete(model: Participant.self)
        try? context.delete(model: SharedSettings.self)
        try? context.delete(model: Baby.self)
        try? context.save()
    }

    // MARK: Identity

    /// Resolves "me" from the iCloud account so `QuickLogger` (which reads
    /// `sync.myParticipantID` from the App Group defaults, same as on the
    /// phone) attributes watch logs to the right parent. Both parents' rows
    /// carry `cloudUserID` — the owner's is stamped by SeedData, a joiner's by
    /// the join flow.
    private func resolveIdentityIfNeeded() async {
        let defaults = AppGroup.userDefaults
        if let s = defaults?.string(forKey: Keys.myParticipantID), let id = UUID(uuidString: s),
           Participant.fetchByID(id, in: context)?.isActive == true { return }
        guard let recordName = (try? await SyncConstants.container.userRecordID())?.recordName else { return }
        let all = (try? context.fetch(FetchDescriptor<Participant>())) ?? []
        guard let mine = all.first(where: { $0.isActive && $0.cloudUserID == recordName }) else { return }
        defaults?.set(mine.id.uuidString, forKey: Keys.myParticipantID)
        AppLog.sync.log("Watch resolved local identity → participant \(mine.id, privacy: .public)")
    }

    // MARK: Outbound

    /// Queues record saves for upload, parking when the engine isn't up yet.
    func enqueueSave(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        guard let engine, let zoneID else {
            park(ids, key: Keys.pendingSaves); return
        }
        engine.state.add(pendingRecordZoneChanges: ids.map {
            .saveRecord(CKRecord.ID(recordName: $0.uuidString, zoneID: zoneID))
        })
    }

    private func park(_ ids: [UUID], key: String) {
        let held = UserDefaults.standard.stringArray(forKey: key) ?? []
        UserDefaults.standard.set(held + ids.map(\.uuidString), forKey: key)
    }

    private func parkUnsentChanges(_ changes: [CKSyncEngine.PendingRecordZoneChange]) {
        var saves: [UUID] = []
        var deletes: [UUID] = []
        for change in changes {
            switch change {
            case .saveRecord(let id):
                if let uuid = UUID(uuidString: id.recordName) { saves.append(uuid) }
            case .deleteRecord(let id):
                if let uuid = UUID(uuidString: id.recordName) { deletes.append(uuid) }
            @unknown default:
                break
            }
        }
        if !saves.isEmpty { park(saves, key: Keys.pendingSaves) }
        if !deletes.isEmpty { park(deletes, key: Keys.pendingDeletes) }
    }

    private func drainPendingChanges() {
        guard let engine, let zoneID else { return }
        if let raw = UserDefaults.standard.stringArray(forKey: Keys.pendingSaves), !raw.isEmpty {
            UserDefaults.standard.removeObject(forKey: Keys.pendingSaves)
            engine.state.add(pendingRecordZoneChanges: raw.compactMap(UUID.init).map {
                .saveRecord(CKRecord.ID(recordName: $0.uuidString, zoneID: zoneID))
            })
        }
        if let raw = UserDefaults.standard.stringArray(forKey: Keys.pendingDeletes), !raw.isEmpty {
            UserDefaults.standard.removeObject(forKey: Keys.pendingDeletes)
            engine.state.add(pendingRecordZoneChanges: raw.compactMap(UUID.init).map {
                .deleteRecord(CKRecord.ID(recordName: $0.uuidString, zoneID: zoneID))
            })
        }
    }

    /// Drains the ids `QuickLogger.commit` queued (per-key, race-free) into
    /// the engine. On the watch the queue and its drain live in the same
    /// process, so this runs right after every log action as well as on start.
    func drainLoggerQueue() {
        guard let defaults = AppGroup.userDefaults else { return }
        var ids: [UUID] = []
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Keys.loggerWritePrefix) {
            if let s = defaults.string(forKey: key), let id = UUID(uuidString: s) { ids.append(id) }
            defaults.removeObject(forKey: key)
        }
        guard !ids.isEmpty else { return }
        enqueueSave(ids)
    }

    // MARK: CKSyncEngineDelegate

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard syncEngine === engine else { return }

        switch event {
        case .stateUpdate(let e):
            saveState(e.stateSerialization)

        case .fetchedDatabaseChanges(let e):
            if role == .participant {
                for change in e.modifications where change.zoneID.zoneName == SyncConstants.zoneName {
                    UserDefaults.standard.set(change.zoneID.zoneName, forKey: Keys.sharedZoneName)
                    UserDefaults.standard.set(change.zoneID.ownerName, forKey: Keys.sharedZoneOwner)
                }
            }
            if e.deletions.contains(where: { $0.zoneID.zoneName == SyncConstants.zoneName }) {
                resetToUnknown(reason: "family zone deleted server-side")
            }

        case .fetchedRecordZoneChanges(let e):
            applyFetchedChanges(e, syncEngine: syncEngine)

        case .sentRecordZoneChanges(let e):
            handleSentChanges(e, syncEngine: syncEngine)

        case .accountChange(let e):
            switch e.changeType {
            case .signOut, .switchAccounts:
                resetToUnknown(reason: "iCloud account changed")
            case .signIn:
                start()
            default:
                break
            }

        default:
            break
        }
    }

    private func applyFetchedChanges(_ e: CKSyncEngine.Event.FetchedRecordZoneChanges, syncEngine: CKSyncEngine) {
        // A fetched copy must not clobber a local change still waiting to send
        // (engine queue or hold queue) — keep local content, adopt the server's
        // change tag, let the pending save push our version.
        var pendingSaves = Set(syncEngine.state.pendingRecordZoneChanges.compactMap {
            if case .saveRecord(let id) = $0 { id } else { nil }
        })
        let heldNames = Set(UserDefaults.standard.stringArray(forKey: Keys.pendingSaves) ?? [])
        if !heldNames.isEmpty {
            pendingSaves.formUnion(e.modifications.map(\.record.recordID)
                .filter { heldNames.contains($0.recordName) })
        }
        do {
            for mod in e.modifications {
                if pendingSaves.contains(mod.record.recordID) {
                    let absorbed = RecordMapping.absorbConflict(server: mod.record, in: context)
                    if !absorbed {
                        RecordMapping.persistSystemFields(of: mod.record, in: context)
                    }
                } else {
                    try RecordMapping.apply(mod.record, in: context)
                    RecordMapping.persistSystemFields(of: mod.record, in: context)
                }
            }
            for del in e.deletions {
                try RecordMapping.delete(recordName: del.recordID.recordName, in: context)
            }
        } catch {
            AppLog.sync.error("Watch sync fetch apply hit a store error: \(error.localizedDescription, privacy: .public)")
            resetEngineAfterFetchApplyFailure()
            return
        }
        RecordMapping.relinkOrphanEvents(in: context)
        do {
            try context.save()
        } catch {
            AppLog.sync.error("Watch sync fetch apply failed to save (retrying): \(error.localizedDescription, privacy: .public)")
            do { try context.save() } catch {
                resetEngineAfterFetchApplyFailure()
                return
            }
        }
        Task { await resolveIdentityIfNeeded() }
        WidgetCenter.shared.reloadAllTimelines()
        NotificationCenter.default.post(name: Self.didApplyRemoteChanges, object: nil)
    }

    /// A fetched batch the store refused to save would be checkpointed and
    /// never re-delivered — same recovery as the phone: discard the engine and
    /// its state so a fresh one re-fetches the whole zone (safe: `apply`
    /// upserts by record name).
    private func resetEngineAfterFetchApplyFailure() {
        if let engine {
            parkUnsentChanges(engine.state.pendingRecordZoneChanges)
        }
        engine = nil
        try? FileManager.default.removeItem(at: stateURL())
        start()
    }

    private func handleSentChanges(_ e: CKSyncEngine.Event.SentRecordZoneChanges, syncEngine: CKSyncEngine) {
        for saved in e.savedRecords {
            RecordMapping.persistSystemFields(of: saved, in: context)
        }

        var reenqueue: [CKSyncEngine.PendingRecordZoneChange] = []
        var lostZone = false

        for failed in e.failedRecordSaves {
            let recordID = failed.record.recordID
            switch failed.error.code {
            case .serverRecordChanged:
                guard let server = failed.error.serverRecord else {
                    AppLog.sync.error("Watch sync: serverRecordChanged without a server record for \(recordID.recordName, privacy: .public)")
                    continue
                }
                RecordMapping.absorbConflict(server: server, in: context)
                reenqueue.append(.saveRecord(recordID))

            case .zoneNotFound, .userDeletedZone, .permissionFailure:
                // The zone this watch was writing to is gone (or access was
                // revoked). Park the save first — if the same household comes
                // back after rediscovery it still sends.
                if let uuid = UUID(uuidString: recordID.recordName) {
                    park([uuid], key: Keys.pendingSaves)
                }
                lostZone = true

            case .unknownItem:
                RecordMapping.clearSystemFields(forRecordName: recordID.recordName, in: context)
                reenqueue.append(.saveRecord(recordID))

            case .invalidArguments, .serverRejectedRequest:
                AppLog.sync.error("Watch sync save rejected server-side for \(recordID.recordName, privacy: .public) — parked for retry")
                if let uuid = UUID(uuidString: recordID.recordName) {
                    park([uuid], key: Keys.pendingSaves)
                }

            default:
                AppLog.sync.error("Watch sync save failed for \(recordID.recordName, privacy: .public): \(failed.error.localizedDescription, privacy: .public)")
            }
        }
        for (recordID, error) in e.failedRecordDeletes where error.code != .unknownItem {
            AppLog.sync.error("Watch sync delete failed for \(recordID.recordName, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }

        if !reenqueue.isEmpty { syncEngine.state.add(pendingRecordZoneChanges: reenqueue) }
        do { try context.save() } catch {
            AppLog.sync.error("Watch sync bookkeeping failed to save: \(error.localizedDescription, privacy: .public)")
        }
        if lostZone { resetToUnknown(reason: "zone unreachable on send") }
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !pending.isEmpty else { return nil }

        var records: [CKRecord.ID: CKRecord] = [:]
        for change in pending {
            if case .saveRecord(let id) = change {
                if let r = RecordMapping.record(forRecordName: id.recordName, recordID: id, in: self.context) {
                    records[id] = r
                } else if (try? RecordMapping.modelExists(recordName: id.recordName, in: self.context)) == false {
                    syncEngine.state.remove(pendingRecordZoneChanges: [change])
                } else {
                    AppLog.sync.error("Watch send of \(id.recordName, privacy: .public) skipped this batch — store fetch failed; will retry.")
                }
            }
        }
        let builtRecords = records
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            builtRecords[recordID]
        }
    }

    // MARK: State persistence

    private func stateURL() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("watch-sync-state.data")
    }

    private func loadState() -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: stateURL()) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func saveState(_ state: CKSyncEngine.State.Serialization) {
        guard !WatchModelContainer.isEphemeralFallback else { return }
        guard let data = try? JSONEncoder().encode(state) else { return }
        let url = stateURL()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
