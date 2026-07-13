import Foundation
import SwiftData
import CloudKit
import WidgetKit

/// Owns the CloudKit sync layer for Two of Us.
///
/// SwiftData stays the local source of truth; this drives a `CKSyncEngine`
/// (per database scope) that mirrors records to a custom zone. The owner runs the
/// `.private` engine on a zone they can share; the joining parent runs the
/// `.shared` engine against the owner's zone. See the plan and
/// [[widget-cloudkit-architecture]] for the rationale.
///
/// Two invariants this layer must never break (both were broken once):
/// 1. Outbound saves of existing records must carry the server's change tag
///    (`ckSystemFields` via `RecordMapping`) — CloudKit rejects tag-less updates
///    as conflicts, and "handling" the conflict by taking the server copy
///    silently reverts the user's change.
/// 2. A queued local change may be parked (hold queues) but never dropped: the
///    engines come and go with iCloud account state, demo mode, and role flips,
///    and any dropped id is an event the co-parent permanently never sees.
@MainActor
final class SyncManager: NSObject, CKSyncEngineDelegate {
    static var shared: SyncManager?

    /// Builds (once) and starts the manager. Callable from any launch path —
    /// including a background launch for a silent push, where no SwiftUI scene
    /// ever connects — so sync never depends on the UI appearing first.
    static func bootstrap(container: ModelContainer) {
        if shared == nil { shared = SyncManager(modelContainer: container) }
        shared?.start()
        // Sweep any outbound asset temp files a previous run left behind (a save
        // that failed before upload leaks the file otherwise).
        RecordMapping.cleanUpStaleAssetFiles()
    }

    private let modelContainer: ModelContainer
    private var privateEngine: CKSyncEngine?
    private var sharedEngine: CKSyncEngine?

    /// The owner's zone in the shared database (the participant writes here).
    /// Backed by `Keys.sharedZoneName/Owner` — it must survive relaunches because
    /// the engine's persisted state means the zone is never re-announced via
    /// `fetchedDatabaseChanges`, and a participant whose zone is unknown can only
    /// park writes, not send them.
    private var sharedZoneID: CKRecordZone.ID?

    /// A dead private zone produces MANY signals (one per failed save in a
    /// batch, plus the database-changes deletion) — recovery must run once per
    /// engine generation, or each re-fire wipes the change tags the previous
    /// recovery just re-captured.
    private var handledPrivateZoneDeletion = false

    private enum Keys {
        static let sharedZoneName = "sync.sharedZone.name"
        static let sharedZoneOwner = "sync.sharedZone.owner"
        static let pendingSharedSaves = "sync.pendingSharedSaves"
        static let pendingSharedDeletes = "sync.pendingSharedDeletes"
        static let pendingPrivateSaves = "sync.pendingPrivateSaves"
        static let pendingPrivateDeletes = "sync.pendingPrivateDeletes"
        static let bootstrapPrivate = "sync.bootstrap.private"
        /// Legacy shared-array widget queue — drained (and cleared) for installs
        /// that queued ids before the per-key scheme below.
        static let widgetWrites = "sync.pendingWidgetWrites"
        /// Per-write widget queue: `sync.widgetWrite.<uuid>` → record id. One
        /// key per write so the extension's writes and the app's drain can
        /// never race each other (see QuickLogger.commit).
        static let widgetWritePrefix = "sync.widgetWrite."
    }

    private var context: ModelContext { modelContainer.mainContext }

    private var privateZoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: SyncConstants.zoneName, ownerName: CKCurrentUserDefaultName)
    }

    /// The device's actual sync role. During demo, `LocalPrefs.syncRole` is
    /// overridden to `.owner` for the UI — routing engine work by that would
    /// send a real participant's writes to the wrong queue, so the sync layer
    /// always reads through here.
    static var realSyncRole: SyncRole {
        DemoSession.realSyncRole ?? LocalPrefs.shared.syncRole
    }

    /// Writes the device's REAL role: straight to prefs normally, but only to
    /// the demo backup while the override is active — clobbering the override
    /// would flip the demo UI's People controls mid-demo, while skipping the
    /// backup would let demo exit restore a stale role.
    private static func setRealRole(_ role: SyncRole) {
        if DemoSession.realSyncRole != nil {
            DemoSession.noteRealRole(role)
        } else {
            LocalPrefs.shared.syncRole = role
        }
    }

    /// The iCloud user record name of the share owner this participant is
    /// attached to, if any (`ShareAcceptance` uses it to spot a link from a
    /// DIFFERENT household, which must run the replace flow, not merge).
    static func persistedSharedZoneOwnerName() -> String? {
        UserDefaults.standard.string(forKey: Keys.sharedZoneOwner)
    }

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        super.init()
        // iCloud sign-in after launch must start sync mid-session; without an
        // engine there is no `.accountChange` event to react to, so the only
        // signal is the system notification. `start()` is idempotent.
        NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: nil) { _ in
            Task { @MainActor in SyncManager.shared?.start() }
        }
    }

    // MARK: Lifecycle

    /// Gate for every CloudKit touchpoint: true when an iCloud account is signed
    /// in (`CKAccountStatus.available`). iCloud Drive is intentionally NOT
    /// required — CloudKit works without it, and the ubiquity-token shortcut this
    /// replaced wrongly read Drive-off as iCloud-off and disabled sync.
    private func cloudAvailable() async -> Bool {
        await CloudAccount.isAvailable()
    }

    /// Starts the engine(s) appropriate to this device's role. Safe to call
    /// repeatedly (launch, foreground, account changes, role flips); no-ops
    /// without iCloud (the app still works fully offline/local).
    func start() {
        Task { await ensureStarted() }
    }

    /// Awaitable form of `start()` — callers that fetch right after (the silent
    /// push handler) must be able to wait for the engines to actually exist,
    /// not race the account check on a cold background launch.
    func ensureStarted() async {
        guard await cloudAvailable() else { return }
        switch Self.realSyncRole {
        case .solo, .owner:
            startPrivateEngine()
        case .participant:
            startSharedEngine()
        }
        drainExtensionQueue()
    }

    private func startPrivateEngine() {
        guard privateEngine == nil else { return }
        var config = CKSyncEngine.Configuration(
            database: SyncConstants.container.privateCloudDatabase,
            stateSerialization: loadState(.private),
            delegate: self
        )
        config.automaticallySync = true
        handledPrivateZoneDeletion = false
        privateEngine = CKSyncEngine(config)
        // Ensure the custom zone exists, then push anything not yet uploaded.
        // (The engine always sends zone saves before record saves.)
        privateEngine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: privateZoneID))])
        bootstrapReconcileIfNeeded()
        drainPendingPrivateChanges()
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
        if sharedZoneID == nil { sharedZoneID = persistedSharedZoneID() }
        if sharedZoneID != nil { drainPendingSharedChanges() }
    }

    private func tearDownEngines() {
        privateEngine = nil
        sharedEngine = nil
        sharedZoneID = nil
        handledPrivateZoneDeletion = false
    }

    /// Whether the real store already holds a baby — `ShareAcceptance` asks
    /// before replacing a device's own log with a shared one.
    var hasLocalBaby: Bool {
        ((try? context.fetchCount(FetchDescriptor<Baby>())) ?? 0) > 0
    }

    /// Device-state half of accepting a share: flips the role and records the
    /// owner's zone from the share metadata (the ONLY reliable source — the
    /// engine never re-announces a zone it has already fetched). Static so
    /// `ShareAcceptance` can record the accept even when the manager doesn't
    /// exist yet (cold-launch link tap) — the next `start()` brings the shared
    /// engine up from this state.
    static func markShareAccepted(zoneID: CKRecordZone.ID? = nil) {
        // If the link was tapped while demo mode was on, the real role lives in
        // the demo backup — `setRealRole` writes whichever is authoritative, so
        // exiting demo can never restore a stale role over the accept.
        setRealRole(.participant)
        if let zoneID {
            UserDefaults.standard.set(zoneID.zoneName, forKey: Keys.sharedZoneName)
            UserDefaults.standard.set(zoneID.ownerName, forKey: Keys.sharedZoneOwner)
        }
        DemoSession.noteRealParticipantID(nil)
    }

    /// Called after the user accepts a share — becomes a participant and starts
    /// syncing the owner's shared zone. The role flip is unconditional (accepting
    /// a share proves an account exists); only the engine work awaits the check.
    func didAcceptShare() {
        Task {
            guard await cloudAvailable() else { return }
            // A re-accept can attach us to a DIFFERENT zone than the engine was
            // following (re-join after a leave/revoke, or a new household) —
            // the old engine state belongs to the wrong zone, so start fresh.
            if let persisted = persistedSharedZoneID(), sharedZoneID != persisted {
                sharedEngine = nil
                sharedZoneID = nil
                try? FileManager.default.removeItem(at: stateURL(.shared))
            }
            startSharedEngine()
            do {
                try await sharedEngine?.fetchChanges()
                // Only after a SUCCESSFUL fetch: judging our profile against a
                // half-fetched store could wrongly re-run the join flow.
                reclaimIdentityAfterAccept()
            } catch {
                AppLog.sync.error("Post-accept fetch failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// A re-accept on a device that already had a profile must not leave a ghost:
    /// the profile may have been deactivated when the owner stopped sharing or
    /// removed us (nothing else ever reactivates it — the joiner would sync fine
    /// but be invisible in both People lists, and skew the NEXT joiner's role).
    private func reclaimIdentityAfterAccept() {
        guard let myID = LocalPrefs.shared.myParticipantID else { return }
        guard let me = Participant.fetchByID(myID, in: context) else {
            // Our profile is gone from the shared data — run the join flow again.
            LocalPrefs.shared.myParticipantID = nil
            DemoSession.noteRealParticipantID(nil)
            return
        }
        if !me.isActive {
            me.isActive = true
            try? context.save()
            enqueueSave([me.id])
        }
    }

    /// Pulls remote changes now (silent push, foreground refresh) — this is what
    /// keeps the other parent's widget fresh. Returns false when no engine could
    /// run (signed out / still unavailable) OR every fetch attempt threw, so
    /// push handlers report `.noData`/`.newData` honestly to iOS's push budget.
    @discardableResult
    func handleRemoteNotification() async -> Bool {
        await ensureStarted()
        var fetched = false
        if let engine = privateEngine, (try? await engine.fetchChanges()) != nil { fetched = true }
        if let engine = sharedEngine, (try? await engine.fetchChanges()) != nil { fetched = true }
        return fetched
    }

    // MARK: Shared zone persistence

    private func persistedSharedZoneID() -> CKRecordZone.ID? {
        guard let name = UserDefaults.standard.string(forKey: Keys.sharedZoneName),
              let owner = UserDefaults.standard.string(forKey: Keys.sharedZoneOwner) else { return nil }
        return CKRecordZone.ID(zoneName: name, ownerName: owner)
    }

    private func setSharedZone(_ zoneID: CKRecordZone.ID) {
        guard zoneID.zoneName == SyncConstants.zoneName else { return }
        sharedZoneID = zoneID
        UserDefaults.standard.set(zoneID.zoneName, forKey: Keys.sharedZoneName)
        UserDefaults.standard.set(zoneID.ownerName, forKey: Keys.sharedZoneOwner)
        drainPendingSharedChanges()
    }

    private func clearPersistedSharedZone() {
        UserDefaults.standard.removeObject(forKey: Keys.sharedZoneName)
        UserDefaults.standard.removeObject(forKey: Keys.sharedZoneOwner)
    }

    // MARK: Co-parent activity notifications

    /// Posts a calm local notification for each freshly-synced event the *other*
    /// parent just logged. Skips your own logs, edits, deletes, and anything
    /// outside the recency window (so a participant joining — which pulls full
    /// history — doesn't fire a flood). `NotificationManager` applies the per-kind
    /// toggle, quiet hours, and dedupe.
    private func notifyCoParentActivity(from records: [CKRecord]) {
        // Without a known local identity we can't tell "me" from "them", so we'd
        // risk self-notifying — bail until onboarding/sharing has set it.
        guard let myID = LocalPrefs.shared.myParticipantID else { return }
        let babyName = (try? context.fetch(FetchDescriptor<Baby>()))?.first?.name ?? "Baby"

        for r in records {
            guard let loggedBy = (r["loggedByID"] as? String).flatMap(UUID.init),
                  loggedBy != myID,                    // never notify yourself
                  r["deletedAt"] == nil,               // skip soft-deletes
                  r["editOfID"] == nil,                // skip edits
                  let eventID = UUID(uuidString: r.recordID.recordName)
            else { continue }

            let senderName = (r["loggedByName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? "Your co-parent"
            let photo = participantPhoto(loggedBy)

            switch r.recordType {
            case SyncConstants.RecordType.feed:
                guard let at = r["timestamp"] as? Date, isRecent(at) else { continue }
                let oz = r["amountOz"] as? Double ?? 0
                NotificationManager.postCoParentActivity(
                    eventID: eventID, dedupeSuffix: "", kind: .feed,
                    senderName: senderName, senderPhoto: photo,
                    body: "Fed \(babyName) \(OzFormat.string(oz)) oz",
                    threadID: NotificationID.Thread.feed)

            case SyncConstants.RecordType.diaper:
                guard let at = r["timestamp"] as? Date, isRecent(at) else { continue }
                let type = DiaperType(rawValue: r["typeRaw"] as? String ?? "") ?? .wet
                NotificationManager.postCoParentActivity(
                    eventID: eventID, dedupeSuffix: "", kind: .diaper,
                    senderName: senderName, senderPhoto: photo,
                    body: "Logged a \(type.label.lowercased()) diaper for \(babyName)",
                    threadID: NotificationID.Thread.diaper)

            case SyncConstants.RecordType.sleep:
                let started = r["startedAt"] as? Date
                if let ended = r["endedAt"] as? Date, isRecent(ended) {
                    let duration = started.map { TimeFormatting.duration(from: $0, to: ended) }
                    let body = duration.map { "Ended \(babyName)'s nap · \($0)" } ?? "Ended \(babyName)'s nap"
                    NotificationManager.postCoParentActivity(
                        eventID: eventID, dedupeSuffix: "end", kind: .sleep,
                        senderName: senderName, senderPhoto: photo,
                        body: body, threadID: NotificationID.Thread.sleep)
                } else if let started, isRecent(started) {
                    NotificationManager.postCoParentActivity(
                        eventID: eventID, dedupeSuffix: "start", kind: .sleep,
                        senderName: senderName, senderPhoto: photo,
                        body: "Started a nap for \(babyName)",
                        threadID: NotificationID.Thread.sleep)
                }

            default:
                continue
            }
        }
    }

    private func isRecent(_ date: Date) -> Bool {
        abs(date.timeIntervalSinceNow) <= NotificationManager.coParentRecencyWindow
    }

    private func participantPhoto(_ id: UUID) -> Data? {
        let all = (try? context.fetch(FetchDescriptor<Participant>())) ?? []
        return all.first { $0.id == id }?.photoData
    }

    // MARK: Enqueue local changes

    func enqueueSave(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        if Self.realSyncRole == .participant {
            // The shared zone may be unknown (first session before discovery) or
            // the engine down (signed out) — park, never drop.
            guard let engine = sharedEngine, let zoneID = sharedZoneID else {
                park(ids, key: Keys.pendingSharedSaves); return
            }
            engine.state.add(pendingRecordZoneChanges: ids.map {
                .saveRecord(CKRecord.ID(recordName: $0.uuidString, zoneID: zoneID))
            })
        } else {
            // Solo/owner writes get the same parking when the private engine
            // isn't up (iCloud signed out, mid-session resets).
            guard let engine = privateEngine else {
                park(ids, key: Keys.pendingPrivateSaves); return
            }
            engine.state.add(pendingRecordZoneChanges: ids.map {
                .saveRecord(CKRecord.ID(recordName: $0.uuidString, zoneID: privateZoneID))
            })
        }
    }

    func enqueueDelete(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        if Self.realSyncRole == .participant {
            guard let engine = sharedEngine, let zoneID = sharedZoneID else {
                park(ids, key: Keys.pendingSharedDeletes); return
            }
            engine.state.add(pendingRecordZoneChanges: ids.map {
                .deleteRecord(CKRecord.ID(recordName: $0.uuidString, zoneID: zoneID))
            })
        } else {
            guard let engine = privateEngine else {
                park(ids, key: Keys.pendingPrivateDeletes); return
            }
            engine.state.add(pendingRecordZoneChanges: ids.map {
                .deleteRecord(CKRecord.ID(recordName: $0.uuidString, zoneID: privateZoneID))
            })
        }
    }

    private func park(_ ids: [UUID], key: String) {
        let held = UserDefaults.standard.stringArray(forKey: key) ?? []
        UserDefaults.standard.set(held + ids.map(\.uuidString), forKey: key)
    }

    /// Moves record changes an engine never got to send into the hold queues,
    /// keyed by scope. Used right before an engine's state file (which is where
    /// those pending changes live) is deleted. Internal so the queue routing is
    /// unit-testable without a live engine.
    func parkUnsentChanges(_ changes: [CKSyncEngine.PendingRecordZoneChange], scope: CKDatabase.Scope) {
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
        if !saves.isEmpty {
            park(saves, key: scope == .shared ? Keys.pendingSharedSaves : Keys.pendingPrivateSaves)
        }
        if !deletes.isEmpty {
            park(deletes, key: scope == .shared ? Keys.pendingSharedDeletes : Keys.pendingPrivateDeletes)
        }
    }

    /// Re-enqueues saves/deletes held while the shared zone was still unknown.
    private func drainPendingSharedChanges() {
        if let raw = UserDefaults.standard.stringArray(forKey: Keys.pendingSharedSaves), !raw.isEmpty {
            UserDefaults.standard.removeObject(forKey: Keys.pendingSharedSaves)
            enqueueSave(raw.compactMap(UUID.init))
        }
        if let raw = UserDefaults.standard.stringArray(forKey: Keys.pendingSharedDeletes), !raw.isEmpty {
            UserDefaults.standard.removeObject(forKey: Keys.pendingSharedDeletes)
            enqueueDelete(raw.compactMap(UUID.init))
        }
    }

    /// Re-enqueues solo/owner saves/deletes held while the private engine was down.
    private func drainPendingPrivateChanges() {
        if let raw = UserDefaults.standard.stringArray(forKey: Keys.pendingPrivateSaves), !raw.isEmpty {
            UserDefaults.standard.removeObject(forKey: Keys.pendingPrivateSaves)
            enqueueSave(raw.compactMap(UUID.init))
        }
        if let raw = UserDefaults.standard.stringArray(forKey: Keys.pendingPrivateDeletes), !raw.isEmpty {
            UserDefaults.standard.removeObject(forKey: Keys.pendingPrivateDeletes)
            enqueueDelete(raw.compactMap(UUID.init))
        }
    }

    /// Drains record ids written by the widget/Siri extension (which can't reach
    /// the engine) and enqueues them. Called when the app becomes active and
    /// after engines start. Deferred during demo: the role/identity overrides
    /// would route the ids to the wrong engine, and `enqueueSave` ids handed over
    /// during demo would be parked under the wrong scope.
    ///
    /// KNOWN CONSTRAINT: this is the *only* drain point. A feed logged from the
    /// widget/Control Center while offline persists locally and shows in widgets,
    /// but does NOT sync to the co-parent until the app is next opened (the
    /// extension process has no CKSyncEngine, and there's no background drain).
    /// Acceptable for a 2-user app where the app is opened regularly; documented
    /// in docs/RELEASE_POLISH_PLAN.md §10 so it isn't mistaken for a sync bug.
    func drainExtensionQueue() {
        guard !LocalPrefs.shared.demoModeEnabled else { return }
        guard let defaults = AppGroup.userDefaults else { return }

        var ids: [UUID] = []
        // Legacy shared-array queue (pre per-key): drain once on upgrade.
        if let raw = defaults.array(forKey: Keys.widgetWrites) as? [String], !raw.isEmpty {
            ids += raw.compactMap(UUID.init)
            defaults.removeObject(forKey: Keys.widgetWrites)
        }
        // Per-key queue: only remove the exact keys read here — a key the
        // extension writes after this snapshot survives untouched for the next
        // drain, so a concurrent widget log can never be dropped.
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Keys.widgetWritePrefix) {
            if let s = defaults.string(forKey: key), let id = UUID(uuidString: s) { ids.append(id) }
            defaults.removeObject(forKey: key)
        }

        guard !ids.isEmpty else { return }
        // enqueueSave parks when no engine is up, so handing the ids over (and
        // clearing the extension queue) can never lose them.
        enqueueSave(ids)
    }

    /// One-time push of all existing local records into the (new) private zone.
    private func bootstrapReconcileIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Keys.bootstrapPrivate) else { return }
        enqueueSave(allLocalIDs())
        UserDefaults.standard.set(true, forKey: Keys.bootstrapPrivate)
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
        // Events from an engine we already discarded (account change, reset)
        // must not touch state — a stale engine's stateUpdate would resurrect
        // the state file we just deleted.
        guard syncEngine === privateEngine || syncEngine === sharedEngine else { return }

        switch event {
        case .stateUpdate(let e):
            saveState(e.stateSerialization, scope: scope(for: syncEngine))

        case .fetchedDatabaseChanges(let e):
            if syncEngine === sharedEngine {
                // Participant: capture the owner's shared zone, then flush any
                // changes that were held while the zone was unknown.
                for change in e.modifications {
                    setSharedZone(change.zoneID)
                }
                // The owner revoking the share (or deleting everything) arrives
                // here as a zone deletion in the shared database. Without this,
                // the device stays a "participant" driving a dead engine forever.
                // Detaching wipes our local copy — when the owner pulls access,
                // the data leaves this phone too. Match the FULL zone ID when we
                // know our zone: after a re-invite, the dead old zone and the
                // freshly joined one share a name, and a name-only match would
                // detach the share the user just accepted.
                let attached = sharedZoneID ?? persistedSharedZoneID()
                let revoked = e.deletions.contains { del in
                    if let attached { return del.zoneID == attached }
                    return del.zoneID.zoneName == SyncConstants.zoneName
                }
                if revoked {
                    detachFromShare()
                }
            } else {
                // Owner/solo: the private zone vanished server-side (deleted from
                // another device, iCloud storage purge, encrypted-data reset).
                if e.deletions.contains(where: { $0.zoneID.zoneName == SyncConstants.zoneName }) {
                    handlePrivateZoneDeleted()
                }
            }

        case .fetchedRecordZoneChanges(let e):
            // A fetched copy must not clobber a local edit still waiting in the
            // send queue: for those records keep the local content, adopt the
            // server's change tag (and terminal fields), and let the pending
            // save push our version.
            let pendingSaves = Set(syncEngine.state.pendingRecordZoneChanges.compactMap {
                if case .saveRecord(let id) = $0 { id } else { nil }
            })
            for mod in e.modifications {
                if pendingSaves.contains(mod.record.recordID) {
                    RecordMapping.absorbConflict(server: mod.record, in: context)
                } else {
                    RecordMapping.apply(mod.record, in: context)
                    // Cache the server change tag so a later local edit of this
                    // record saves cleanly instead of conflicting.
                    RecordMapping.persistSystemFields(of: mod.record, in: context)
                }
                if syncEngine === sharedEngine, sharedZoneID == nil {
                    setSharedZone(mod.record.recordID.zoneID)
                }
            }
            for del in e.deletions {
                RecordMapping.delete(recordName: del.recordID.recordName, in: context)
            }
            // Events can land before their Baby record (no batch ordering
            // guarantee) — attach them once the baby exists.
            RecordMapping.relinkOrphanEvents(in: context)
            do { try context.save() } catch {
                AppLog.sync.error("Sync fetch apply failed to save: \(error.localizedDescription, privacy: .public)")
            }
            reconcileLiveActivity()
            WidgetCenter.shared.reloadAllTimelines()
            notifyCoParentActivity(from: e.modifications.map(\.record))
            // A co-parent's feed (or a synced-in delete) changes what "next feed"
            // is on THIS device — re-arm the alarm/reminders off the new state so
            // we don't fire a stale/false overnight alarm.
            rearmFeedRemindersFromStore()

        case .sentRecordZoneChanges(let e):
            handleSentRecordZoneChanges(e, syncEngine: syncEngine)

        case .accountChange(let e):
            handleAccountChange(e)

        default:
            break
        }
    }

    private func handleSentRecordZoneChanges(_ e: CKSyncEngine.Event.SentRecordZoneChanges, syncEngine: CKSyncEngine) {
        // Successful saves: capture the new change tags — without this the
        // SECOND edit of any record conflicts again.
        for saved in e.savedRecords {
            RecordMapping.persistSystemFields(of: saved, in: context)
        }

        var reenqueueSaves: [CKSyncEngine.PendingRecordZoneChange] = []
        var detach = false

        for failed in e.failedRecordSaves {
            let recordID = failed.record.recordID
            switch failed.error.code {
            case .serverRecordChanged:
                // A real concurrent edit by the other parent. Adopt the server's
                // change tag, keep our content (deletes/sleep-stops win either
                // way — see RecordMapping.absorbConflict), and re-send.
                // CloudKit always attaches the server record to this error; if
                // that ever fails to hold, at least say so before dropping.
                guard let server = failed.error.serverRecord else {
                    AppLog.sync.error("serverRecordChanged without a server record for \(recordID.recordName, privacy: .public) — change dropped")
                    continue
                }
                RecordMapping.absorbConflict(server: server, in: context)
                reenqueueSaves.append(.saveRecord(recordID))

            case .zoneNotFound, .userDeletedZone:
                if syncEngine === sharedEngine {
                    // Owner's zone is gone from our shared database — our access
                    // was revoked between fetches.
                    detach = true
                } else {
                    handlePrivateZoneDeleted()
                    reenqueueSaves.append(.saveRecord(recordID))
                }

            case .unknownItem:
                // The record vanished server-side (e.g. zone recreated): drop the
                // stale change tag and re-upload as a fresh create.
                RecordMapping.clearSystemFields(forRecordName: recordID.recordName, in: context)
                reenqueueSaves.append(.saveRecord(recordID))

            case .permissionFailure:
                if syncEngine === sharedEngine { detach = true }

            default:
                // Transient errors (network, throttling, zone busy…) are retried
                // by the engine itself; anything else is logged so it's visible
                // in Console rather than silently swallowed.
                AppLog.sync.error("Sync save failed for \(recordID.recordName, privacy: .public): \(failed.error.localizedDescription, privacy: .public)")
            }
        }
        for (recordID, error) in e.failedRecordDeletes where error.code != .unknownItem {
            // Deleting an already-gone record is success; log the rest.
            AppLog.sync.error("Sync delete failed for \(recordID.recordName, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }

        if !reenqueueSaves.isEmpty { syncEngine.state.add(pendingRecordZoneChanges: reenqueueSaves) }
        do { try context.save() } catch {
            AppLog.sync.error("Sync sent-changes bookkeeping failed to save: \(error.localizedDescription, privacy: .public)")
        }
        if detach { detachFromShare() }
    }

    /// Keeps the sleep Live Activity truthful when the change arrives via sync:
    /// the co-parent stopping (or starting) a sleep must end/start the timer on
    /// this lock screen too, not only after the next app foreground.
    private func reconcileLiveActivity() {
        guard !LocalPrefs.shared.demoModeEnabled else { return }
        let babyName = (try? context.fetch(FetchDescriptor<Baby>()))?.first?.name ?? "Baby"
        var d = FetchDescriptor<SleepEvent>(
            predicate: #Predicate { $0.endedAt == nil && $0.deletedAt == nil }
        )
        d.fetchLimit = 1
        let active = try? context.fetch(d).first
        SleepActivityManager.reconcile(babyName: babyName, activeSleepStartedAt: active?.startedAt)
    }

    /// Re-arms this device's feed alarm + gentle reminders + daily summary off the
    /// current store state, after a sync fetch changed it. Mirrors what a foreground
    /// does (`AppDelegate.applicationDidBecomeActive`) so a co-parent's synced-in or
    /// synced-away feed doesn't leave a stale "feed due" alarm pointed at an old
    /// last-feed. Cheap-guarded: default installs (all reminder prefs off) pay
    /// nothing — no store read happens unless something is actually scheduled.
    private func rearmFeedRemindersFromStore() {
        guard !LocalPrefs.shared.demoModeEnabled else { return }
        guard LocalPrefs.shared.feedReminderEnabled
            || LocalPrefs.shared.gentleRemindersEnabled
            || LocalPrefs.shared.notifyMilestones else { return }
        guard let logger = QuickLogger.make() else { return }
        let babyName = logger.babyName ?? "Baby"
        let lastFeed = logger.lastFeed?.timestamp
        let interval = logger.targetFeedInterval
        Task { await FeedAlarmManager.reschedule(babyName: babyName, lastFeed: lastFeed, interval: interval) }
        NotificationManager.refreshScheduledReminders()
        NotificationManager.refreshDailyMilestone()
    }

    /// The private zone was deleted server-side. Bias to preserving the family's
    /// data: recreate the zone and re-upload everything local. (`.purged`
    /// technically asks apps not to re-upload automatically, but for a two-person
    /// family tracker, silently losing the baby's history is the worse failure —
    /// in-app "Delete everything" is the supported way to actually erase.)
    private func handlePrivateZoneDeleted() {
        guard !handledPrivateZoneDeletion else { return }
        handledPrivateZoneDeletion = true
        AppLog.sync.warning("Private zone deleted server-side — clearing change tags and re-uploading all local records. If the subsequent re-upload fails, the family log will not be visible to the other parent until the app is relaunched.")
        // Every cached change tag pointed at the dead zone's records.
        RecordMapping.clearAllSystemFields(in: context)
        if Self.realSyncRole == .owner {
            // The zone-wide share died with the zone.
            applyStopSharingBookkeeping()
        }
        try? context.save()
        UserDefaults.standard.removeObject(forKey: Keys.bootstrapPrivate)
        privateEngine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: privateZoneID))])
        bootstrapReconcileIfNeeded()
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
        let builtRecords = records
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            builtRecords[recordID]
        }
    }

    // MARK: Sharing (owner)

    enum SyncError: LocalizedError {
        case iCloudUnavailable
        case shareUnavailable
        case participantNotFound

        var errorDescription: String? {
            switch self {
            case .iCloudUnavailable:
                "iCloud isn't available on this device — check that you're signed in and try again."
            case .shareUnavailable:
                "Couldn't reach the shared log — check your connection and try again."
            case .participantNotFound:
                "Couldn't match this person on the iCloud share — they may have already left."
            }
        }
    }

    /// Creates (or returns the existing) zone-wide CKShare so the owner can invite
    /// the co-parent. Marks this device the owner only once the share actually
    /// exists server-side — a failed save must not leave the device "owner" of
    /// nothing.
    func makeShare() async throws -> CKShare {
        // Demo mode runs against a throwaway store; never touch the real iCloud zone.
        guard !LocalPrefs.shared.demoModeEnabled else { throw SyncError.iCloudUnavailable }
        guard await cloudAvailable() else { throw SyncError.iCloudUnavailable }
        startPrivateEngine()
        let db = SyncConstants.container.privateCloudDatabase

        // Ensure the zone exists before sharing it.
        _ = try? await db.save(CKRecordZone(zoneID: privateZoneID))

        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: privateZoneID)
        if let existing = try? await db.record(for: shareID) as? CKShare {
            LocalPrefs.shared.syncRole = .owner
            await refreshShareMetadata(existing, db: db)
            return existing
        }
        let share = CKShare(recordZoneID: privateZoneID)
        share[CKShare.SystemFieldKey.title] = shareTitle() as CKRecordValue
        if let thumb = shareThumbnail() {
            share[CKShare.SystemFieldKey.thumbnailImageData] = thumb as CKRecordValue
        }
        let results = try await db.modifyRecords(saving: [share], deleting: [])
        // Return the SERVER's copy: only it carries the share URL that the share
        // sheet's Messages bubble resolves (the local instance's `.url` stays
        // nil, which left the invite spinning forever). `get()` also surfaces
        // per-record failures that `modifyRecords` itself doesn't throw for, so
        // a failed save shows as an error instead of hanging.
        if let result = results.saveResults[share.recordID],
           let saved = try result.get() as? CKShare {
            LocalPrefs.shared.syncRole = .owner
            return saved
        }
        // Save reported success without returning our record (or another device
        // created the share concurrently) — fetch the canonical copy.
        if let fetched = try? await db.record(for: shareID) as? CKShare {
            LocalPrefs.shared.syncRole = .owner
            return fetched
        }
        throw SyncError.iCloudUnavailable
    }

    /// The invite card title — personalized once the baby exists (the share is
    /// created during onboarding, before the baby record).
    private func shareTitle() -> String {
        if let name = (try? context.fetch(FetchDescriptor<Baby>()))?.first?.name, !name.isEmpty {
            return "\(name) — Two of Us"
        }
        return "Two of Us"
    }

    private func shareThumbnail() -> Data? {
        (try? context.fetch(FetchDescriptor<Baby>()))?.first?.photoData
    }

    /// Best-effort: refresh the invite card's title/thumbnail when the baby's name
    /// or photo changes after the share was created. No-op if offline or not the owner.
    func refreshShareTitleIfOwner() {
        guard Self.realSyncRole == .owner,
              !LocalPrefs.shared.demoModeEnabled else { return }
        Task {
            guard await cloudAvailable() else { return }
            let db = SyncConstants.container.privateCloudDatabase
            let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: privateZoneID)
            guard let share = try? await db.record(for: shareID) as? CKShare else { return }
            await refreshShareMetadata(share, db: db)
        }
    }

    /// Best-effort: keep the invite card's title/thumbnail current on an existing
    /// share (it was created before the baby had a name or photo).
    private func refreshShareMetadata(_ share: CKShare, db: CKDatabase) async {
        let title = shareTitle()
        let thumb = shareThumbnail()
        let titleStale = (share[CKShare.SystemFieldKey.title] as? String) != title
        let thumbStale = thumb != nil && (share[CKShare.SystemFieldKey.thumbnailImageData] as? Data) != thumb
        guard titleStale || thumbStale else { return }
        share[CKShare.SystemFieldKey.title] = title as CKRecordValue
        if let thumb { share[CKShare.SystemFieldKey.thumbnailImageData] = thumb as CKRecordValue }
        _ = try? await db.modifyRecords(saving: [share], deleting: [])
    }

    /// Owner stops sharing: deletes the share (everyone else loses access).
    /// Throws when the server delete fails — the UI must not pretend access was
    /// revoked when it wasn't.
    func stopSharing() async throws {
        guard !LocalPrefs.shared.demoModeEnabled else { return }
        guard await cloudAvailable() else { throw SyncError.iCloudUnavailable }
        let db = SyncConstants.container.privateCloudDatabase
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: privateZoneID)
        let results = try await db.modifyRecords(saving: [], deleting: [shareID])
        if let result = results.deleteResults[shareID] {
            do { try result.get() } catch let error as CKError where error.code == .unknownItem {
                // Already gone — that's the state we wanted.
            }
        }
        applyStopSharingBookkeeping()
    }

    /// Local consequences of the share ending (owner side): back to solo, and
    /// everyone who only had access through the share is no longer active.
    /// Shared by `stopSharing`, the system share sheet's Stop Sharing button,
    /// and the private-zone-deleted recovery.
    private func applyStopSharingBookkeeping() {
        Self.setRealRole(.solo)
        let myID = LocalPrefs.shared.myParticipantID
        var changed: [UUID] = []
        for p in (try? context.fetch(FetchDescriptor<Participant>())) ?? [] where p.id != myID && p.isActive {
            p.isActive = false
            changed.append(p.id)
        }
        try? context.save()
        enqueueSave(changed)
    }

    /// The system share sheet finished a "Stop Sharing" (owner) or "Remove Me"
    /// (participant) — mirror the state our own buttons would have set.
    func handleShareSheetStopped() {
        if Self.realSyncRole == .participant {
            detachFromShare()
        } else {
            applyStopSharingBookkeeping()
        }
    }

    /// Owner removes a single person from the share — the others keep access
    /// (unlike `stopSharing`, which removes everyone). Matches the CKShare
    /// participant by `cloudUserID` when known; with only one co-parent it falls
    /// back to removing the sole non-owner participant. Only marks the local
    /// record inactive once the server actually dropped them — pretending
    /// otherwise leaves a "removed" person with live access.
    func removeParticipant(_ participant: Participant) async throws {
        // In demo the participant belongs to the in-memory store and there's no real
        // share to mutate — leave the seeded People list intact.
        guard !LocalPrefs.shared.demoModeEnabled else { return }
        guard await cloudAvailable() else { throw SyncError.iCloudUnavailable }
        let db = SyncConstants.container.privateCloudDatabase
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: privateZoneID)
        guard let share = try? await db.record(for: shareID) as? CKShare else {
            throw SyncError.shareUnavailable
        }
        let removable = share.participants.filter { $0.role != .owner }
        guard let target = removable.first(where: { $0.userIdentity.userRecordID?.recordName == participant.cloudUserID })
            ?? (removable.count == 1 ? removable.first : nil) else {
            throw SyncError.participantNotFound
        }
        share.removeParticipant(target)
        let results = try await db.modifyRecords(saving: [share], deleting: [])
        if let result = results.saveResults[share.recordID] { _ = try result.get() }
        participant.isActive = false
        try? context.save()
        enqueueSave([participant.id])
    }

    /// Permanently deletes ALL data and resets this device to a fresh solo install.
    /// Owner/solo: deletes the private zone (server-side cascade removes every
    /// record and the zone-wide share, so the co-parent loses the data too).
    /// Participant: can't delete the owner's zone — leaves the share and wipes
    /// the local copy. Either way the local store is cleared, sync state dropped,
    /// and `LocalPrefs` reset — `RootView` then returns to onboarding.
    ///
    /// Throws when a server copy exists but its deletion can't be confirmed
    /// (offline, or the delete failed): wiping only the local cache while the
    /// zone survives is an illusion — the next full fetch resurrects everything
    /// the user just typed DELETE EVERYTHING to destroy. A device that never
    /// pushed to a server (never signed in / never bootstrapped) deletes
    /// locally without needing the network.
    func deleteEverything() async throws {
        guard !LocalPrefs.shared.demoModeEnabled else { return }
        let wasParticipant = Self.realSyncRole == .participant
        let oldSharedZone = sharedZoneID ?? persistedSharedZoneID()
        let cloud = await cloudAvailable()

        let hasServerCopy = Self.requiresServerDeletion(
            isParticipant: wasParticipant,
            sharedZoneKnown: oldSharedZone != nil,
            hasBootstrappedUpload: UserDefaults.standard.bool(forKey: Keys.bootstrapPrivate)
        )
        guard cloud || !hasServerCopy else { throw SyncError.iCloudUnavailable }

        let me = LocalPrefs.shared.myParticipantID.flatMap { Participant.fetchByID($0, in: context) }
        if cloud, wasParticipant {
            // The owner's People list renders our Participant record (not the
            // CKShare) — flip it inactive and push while the engine still
            // exists, or the owner shows a ghost co-parent forever and the
            // NEXT joiner's role is computed against it.
            if let me, me.isActive {
                me.isActive = false
                try? context.save()
                enqueueSave([me.id])
                try? await sharedEngine?.sendChanges()
            }
        }

        if wasParticipant {
            // Leave the share so the owner's list reflects reality. Must be
            // confirmed: silently keeping membership while wiping locally
            // strands a live participant the owner can't tell has "deleted".
            // The shared engine stays up through this so a failure can roll
            // the isActive push back; it's torn down right after success.
            if cloud {
                do {
                    if let zoneID = oldSharedZone {
                        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
                        let results = try await SyncConstants.container.sharedCloudDatabase.modifyRecords(saving: [], deleting: [shareID])
                        if let result = results.deleteResults[shareID] {
                            do { try result.get() } catch let error as CKError where error.code == .unknownItem {
                                // Share already gone (owner revoked first) — same outcome.
                            }
                        }
                    }
                } catch {
                    // Same rollback contract as `leaveShare`: the share delete
                    // failed, so we still have access — undo the isActive=false
                    // push so the owner's list reflects reality, and surface the
                    // failure (the delete flow shows retry).
                    if let me, !me.isActive {
                        me.isActive = true
                        try? context.save()
                        enqueueSave([me.id])
                        try? await sharedEngine?.sendChanges()
                    }
                    AppLog.sync.error("deleteEverything: share leave failed, rolled back isActive: \(error.localizedDescription, privacy: .public)")
                    throw error
                }
            }
            tearDownEngines()
        } else {
            // Tear down BEFORE deleting the zone: a live private engine that
            // observes its zone vanishing runs the zone-recovery path
            // (`handlePrivateZoneDeleted`) and re-uploads everything we are
            // deleting. On a thrown failure the engines stay down with local
            // data intact — the delete flow offers retry, and the next
            // `start()` (foreground) rebuilds them either way.
            tearDownEngines()
            if cloud {
                let db = SyncConstants.container.privateCloudDatabase
                let results = try await db.modifyRecordZones(saving: [], deleting: [privateZoneID])
                if let result = results.deleteResults[privateZoneID] {
                    do { try result.get() } catch let error as CKError
                        where error.code == .zoneNotFound || error.code == .userDeletedZone {
                        // Already gone — that's the state we wanted.
                    }
                }
            }
        }

        clearSyncBookkeeping()
        wipeLocalModels()

        Self.setRealRole(.solo)
        LocalPrefs.shared.myParticipantID = nil
        DemoSession.noteRealParticipantID(nil)
        WidgetCenter.shared.reloadAllTimelines()
        // Fresh start in-session: onboarding runs next, and its commits need a
        // live engine (previously writes were silently dropped until relaunch).
        start()
    }

    /// Whether "Delete everything" must reach the server to be truthful: any
    /// device attached to a server copy (a participant with a known shared
    /// zone, or an owner/solo device that has bootstrapped an upload) would
    /// otherwise watch the "deleted" data resurrect on the next full fetch.
    /// Pure so the gate is unit-testable.
    static func requiresServerDeletion(isParticipant: Bool, sharedZoneKnown: Bool, hasBootstrappedUpload: Bool) -> Bool {
        isParticipant ? sharedZoneKnown : hasBootstrappedUpload
    }

    /// Drops every piece of persisted sync state: engine checkpoints, bootstrap
    /// marker, hold queues, the persisted shared zone, and the widget queue.
    private func clearSyncBookkeeping() {
        try? FileManager.default.removeItem(at: stateURL(.private))
        try? FileManager.default.removeItem(at: stateURL(.shared))
        UserDefaults.standard.removeObject(forKey: Keys.bootstrapPrivate)
        UserDefaults.standard.removeObject(forKey: Keys.pendingSharedSaves)
        UserDefaults.standard.removeObject(forKey: Keys.pendingSharedDeletes)
        UserDefaults.standard.removeObject(forKey: Keys.pendingPrivateSaves)
        UserDefaults.standard.removeObject(forKey: Keys.pendingPrivateDeletes)
        clearPersistedSharedZone()
        if let defaults = AppGroup.userDefaults {
            defaults.removeObject(forKey: Keys.widgetWrites)
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Keys.widgetWritePrefix) {
                defaults.removeObject(forKey: key)
            }
        }
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

    /// Stamps the local user's CloudKit identity onto their own Participant
    /// record (best effort, async). `removeParticipant` matches CKShare
    /// participants against this, so each joiner records it right after creating
    /// their profile — without it, removal only works while there's a single
    /// co-parent (the sole-non-owner fallback).
    func captureCloudUserID(for participantID: UUID) {
        guard !LocalPrefs.shared.demoModeEnabled else { return }
        Task {
            guard await cloudAvailable() else { return }
            // Retry up to 3 times with back-off: transient auth/network errors
            // should resolve quickly; without this id, removeParticipant can
            // remove the wrong person when there are 2+ caregivers.
            for attempt in 1...3 {
                guard let recordName = (try? await SyncConstants.container.userRecordID())?.recordName else {
                    if attempt < 3 {
                        try? await Task.sleep(for: .seconds(Double(attempt) * 2))
                        continue
                    }
                    AppLog.sync.error("captureCloudUserID: couldn't resolve userRecordID after 3 attempts for \(participantID, privacy: .public)")
                    return
                }
                guard let me = Participant.fetchByID(participantID, in: context), me.cloudUserID != recordName else { return }
                me.cloudUserID = recordName
                try? context.save()
                enqueueSave([me.id])
                return
            }
        }
    }

    /// Participant leaves the share: tells the owner's side, removes themselves
    /// from the share, then detaches locally. Throws when the server can't be
    /// reached — silently flipping to solo while the share still lists this
    /// user (with live access) would lie to both sides. Detaching wipes the
    /// local copy of the shared log (leaving is a clean break), so the device
    /// returns to onboarding.
    func leaveShare() async throws {
        guard !LocalPrefs.shared.demoModeEnabled else { return }
        guard await cloudAvailable() else { throw SyncError.iCloudUnavailable }
        // Deactivate our profile and push it while we can still write to the
        // owner's zone (after the self-removal below, we can't).
        let me = LocalPrefs.shared.myParticipantID.flatMap { Participant.fetchByID($0, in: context) }
        if let me, me.isActive {
            me.isActive = false
            try? context.save()
            enqueueSave([me.id])
            try? await sharedEngine?.sendChanges()
        }
        do {
            // Deleting the share record from the SHARED database is CloudKit's
            // documented participant self-removal.
            if let zoneID = sharedZoneID ?? persistedSharedZoneID() {
                let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
                let results = try await SyncConstants.container.sharedCloudDatabase.modifyRecords(saving: [], deleting: [shareID])
                if let result = results.deleteResults[shareID] {
                    do { try result.get() } catch let error as CKError where error.code == .unknownItem {
                        // Share already gone (owner revoked first) — same outcome.
                    }
                }
            }
        } catch {
            // Partial-rollback: the CKShare delete failed, so the participant still
            // has server-side access. Undo the isActive=false push so the owner's
            // People list reflects reality (still there, still has access).
            // Recovery for the user: tap "Leave shared baby" again — it's idempotent
            // once the network comes back. If the rollback push also fails, the
            // owner will see the ghost entry clear on their next fetch.
            if let me, !me.isActive {
                me.isActive = true
                try? context.save()
                enqueueSave([me.id])
                try? await sharedEngine?.sendChanges()
            }
            AppLog.sync.error("leaveShare failed (server delete threw), rolled back isActive: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        // Wipes the local store and resets to a fresh solo install — there is
        // no kept "me" record to re-activate afterwards.
        detachFromShare()
    }

    /// Tears down all participant state and wipes the local copy of the shared
    /// log. Shared by the user-initiated leave and the owner-revoked paths (zone
    /// deletion, save-time permission failures, the system share sheet's
    /// "Remove Me"). Losing access — whether you left or the owner removed you —
    /// clears the data from this device: the family's log lives in the share,
    /// not on an ex-member's phone. The device resets to a fresh solo install,
    /// so `RootView` returns to onboarding. Mirrors `deleteEverything`'s local
    /// reset, minus the server delete (we no longer have access to that zone).
    private func detachFromShare() {
        guard Self.realSyncRole == .participant else { return }
        tearDownEngines()
        clearSyncBookkeeping()
        wipeLocalModels()
        Self.setRealRole(.solo)
        LocalPrefs.shared.myParticipantID = nil
        DemoSession.noteRealParticipantID(nil)
        // Cancel any pending feed alarm — the baby data is gone, so nothing to
        // count down to. The user's reminder preference is preserved so it
        // auto-arms if they join or create a new household.
        Task { await FeedAlarmManager.cancel() }
        WidgetCenter.shared.reloadAllTimelines()
        start()
    }

    // MARK: Account changes & state persistence

    private func handleAccountChange(_ event: CKSyncEngine.Event.AccountChange) {
        switch event.changeType {
        case .signOut:
            // Engines belong to the old account: discard them and every
            // checkpoint. Local data stays. The bootstrap marker deliberately
            // stays SET: writes made while signed out park in the hold queues,
            // and the cached change tags still match the same account's zone —
            // a blanket re-push here would flood the pending queue and, under
            // the local-wins conflict policy, silently revert every edit the
            // co-parent made during the sign-out window.
            //
            // The state files deleted below are ALSO the engines' outbound
            // queue — move any still-unsent record changes into the hold
            // queues first, or an edit made in an offline window just before
            // sign-out is dropped for good (invariant 2). They drain on the
            // next start with this same account; a switch to a different
            // account clears them via detach/bootstrap instead.
            if let engine = privateEngine {
                parkUnsentChanges(engine.state.pendingRecordZoneChanges, scope: .private)
            }
            if let engine = sharedEngine {
                parkUnsentChanges(engine.state.pendingRecordZoneChanges, scope: .shared)
            }
            tearDownEngines()
            try? FileManager.default.removeItem(at: stateURL(.private))
            try? FileManager.default.removeItem(at: stateURL(.shared))

        case .switchAccounts:
            tearDownEngines()
            try? FileManager.default.removeItem(at: stateURL(.private))
            try? FileManager.default.removeItem(at: stateURL(.shared))
            UserDefaults.standard.removeObject(forKey: Keys.bootstrapPrivate)
            // The new account has no access to the old owner's share, and any
            // cached change tags reference the old account's zones.
            RecordMapping.clearAllSystemFields(in: context)
            try? context.save()
            if Self.realSyncRole == .participant {
                detachFromShare()
            } else {
                start()
            }

        case .signIn:
            start()

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
        // Atomic: a torn write here would decode as nil next launch, starting a
        // fresh engine — full re-fetch, and every unsent pending change lost.
        try? data.write(to: stateURL(scope), options: .atomic)
    }
}
