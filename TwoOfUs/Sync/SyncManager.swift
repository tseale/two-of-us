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
        // With `shared` never built, every `SyncManager.shared?` call site
        // no-ops — nothing uploads, nothing parks in the pending queues, and
        // the one-shot bootstrapReconcile can't sweep fixture data into the
        // family's zone. See SyncGate for why this is load-bearing.
        if let reason = SyncGate.blockReason {
            AppLog.sync.warning("Sync disabled for this process: \(reason, privacy: .public)")
            return
        }
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
        /// One-time re-enqueue of schedule records whose uploads were rejected
        /// (and dropped) before the schema carried their types — see
        /// `resyncScheduleRecordsIfNeeded`.
        static let resyncSchedule = "sync.resync.scheduleRecords"
        /// Record types the last-run build could apply (see
        /// `resetFetchStateIfRecordTypesExpanded`).
        static let knownRecordTypes = "sync.knownRecordTypes"
        /// The schema generation the last-run build understood — the manual
        /// counterpart of `knownRecordTypes` for FIELDS added to existing
        /// types (see `SyncConstants.RecordType.schemaGeneration`).
        static let schemaGeneration = "sync.schemaGeneration"
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
        resetFetchStateIfRecordTypesExpanded()
        switch Self.realSyncRole {
        case .solo, .owner:
            startPrivateEngine()
        case .participant:
            startSharedEngine()
        }
        resyncScheduleRecordsIfNeeded()
        mergeDuplicateSettingsIfNeeded()
        await repairMyIdentityIfDangling()
        backfillMyCloudUserIDIfMissing()
        // Parked saves (engine down, zone unknown, schema-rejected) get another
        // send attempt whenever sync (re)starts — not only on the first engine
        // build of the process, or a mid-session schema deploy would need a
        // full relaunch to heal.
        switch Self.realSyncRole {
        case .solo, .owner:
            drainPendingPrivateChanges()
        case .participant:
            if sharedZoneID != nil { drainPendingSharedChanges() }
        }
        drainExtensionQueue()
    }

    /// Self-heal for duplicate SharedSettings rows. The record is a singleton
    /// by intent, but a reinstall that re-onboards into an existing zone mints
    /// a fresh-UUID row while the whole-zone re-fetch re-inserts the old one
    /// (the upsert is by UUID — same mechanism as the duplicate Participant
    /// rows SeedData documents). Two rows split publish from read: a value
    /// one phone writes can land on a row the other phone never looks at.
    /// Every reader now picks `SharedSettings.canonical`, and this pass folds
    /// what the losers uniquely hold into that winner and deletes them — from
    /// this store and the zone, so both phones converge on the same single
    /// row. (The winner's other fields stand as-is; a lost night-window
    /// tweak is re-settable, a split SNOO connection is not.)
    ///
    /// Internal so the fold is unit-testable without a live engine
    /// (`enqueueSave`/`enqueueDelete` park to the hold queues there).
    func mergeDuplicateSettingsIfNeeded() {
        let rows = (try? context.fetch(FetchDescriptor<SharedSettings>())) ?? []
        guard rows.count > 1, let winner = SharedSettings.canonical(rows) else { return }
        var losers: [UUID] = []
        var folded = false
        for row in rows where row.id != winner.id {
            if winner.snooCredentials == nil, let creds = row.snooCredentials {
                winner.snooCredentials = creds
                folded = true
            }
            if winner.nightFirstShiftID == nil, let shift = row.nightFirstShiftID {
                winner.nightFirstShiftID = shift
                folded = true
            }
            losers.append(row.id)
            context.delete(row)
        }
        try? context.save()
        AppLog.sync.log("Merged \(losers.count) duplicate SharedSettings row(s) into \(winner.id, privacy: .public)")
        // Only re-upload the winner when the fold actually changed it — an
        // unchanged re-save just risks a conflict against a server copy this
        // device hasn't fetched yet (e.g. right after a fetch-state reset).
        if folded { enqueueSave([winner.id]) }
        enqueueDelete(losers)
    }

    /// Wake the paired watch's complication when a batch touched what it
    /// displays — feeds and sleeps. Filtering by record type is budget hygiene:
    /// participant/settings/plan churn would otherwise burn the 50/day
    /// complication-transfer allowance on records the watch face never shows.
    private func nudgeWatchIfComplicationRelevant(recordTypes: [CKRecord.RecordType]) {
        let relevant: Set<CKRecord.RecordType> = [SyncConstants.RecordType.feed,
                                                 SyncConstants.RecordType.sleep]
        guard recordTypes.contains(where: relevant.contains) else { return }
        WatchAppStatus.shared.nudgeComplication()
    }

    /// Whether `p` is a row this device should stamp with its iCloud user record
    /// name. Callers pass the row `myParticipantID` already claims, so the only
    /// questions left are "still active?" and "not already stamped?" — the second
    /// keeps the back-fill idempotent and stops it fighting a real identity.
    static func needsCloudUserIDBackfill(_ p: Participant) -> Bool {
        p.isActive && p.cloudUserID == nil
    }

    /// The active participant carrying `cloudUserID`, if any — the match
    /// `repairMyIdentityIfDangling` (phone) and `resolveIdentityIfNeeded` (watch)
    /// both make against this device's iCloud user record name.
    static func participantMatching(cloudUserID: String, in context: ModelContext) -> Participant? {
        ((try? context.fetch(FetchDescriptor<Participant>())) ?? [])
            .first { $0.isActive && $0.cloudUserID == cloudUserID }
    }

    /// Back-fill for owner rows that predate owner-side stamping.
    ///
    /// `cloudUserID` is what lets a device recognise its own participant row from
    /// the iCloud account alone. Joiners have been stamped since 2026-06-12
    /// (JoinFlowView), but the OWNER only started being stamped on 2026-07-29,
    /// in `SeedData` — which runs once, at first onboarding. An owner who
    /// onboarded before that date has a permanently nil `cloudUserID`, and
    /// nothing re-stamps it: `repairMyIdentityIfDangling` only READS the field,
    /// and it early-returns anyway because the phone's own identity is fine.
    ///
    /// The phone never noticed (its identity went straight into LocalPrefs at
    /// seed time). The watch has no onboarding and no LocalPrefs of its own, so
    /// the `cloudUserID` match is its ONLY route to an identity — an unstamped
    /// owner meant `QuickLogger.owner` came back nil and every watch log was
    /// refused with "try from the phone".
    ///
    /// Safe because it asserts exactly what `myParticipantID` already means on
    /// this device: "this iCloud account is that participant". Every phone log
    /// is already attributed on that basis, so this adds no new trust.
    private func backfillMyCloudUserIDIfMissing() {
        guard !LocalPrefs.shared.demoModeEnabled else { return }
        guard let myID = LocalPrefs.shared.myParticipantID,
              let me = Participant.fetchByID(myID, in: context),
              Self.needsCloudUserIDBackfill(me) else { return }
        AppLog.sync.log("Back-filling missing cloudUserID for \(myID, privacy: .public) — watch identity depends on it")
        captureCloudUserID(for: myID)
    }

    /// Self-heal for a dangling local identity. `myParticipantID` can point at
    /// a row that no longer exists (hard-deleted by an old build's purge, store
    /// quarantine, interrupted join) — and since writes now REFUSE rather than
    /// guess when identity is ambiguous, a dangling id must repair itself or
    /// the user is stuck unable to log. The iCloud user record name is the
    /// ground truth: if an active participant carries it, that row is "me".
    private func repairMyIdentityIfDangling() async {
        guard !LocalPrefs.shared.demoModeEnabled else { return }
        if let myID = LocalPrefs.shared.myParticipantID,
           Participant.fetchByID(myID, in: context)?.isActive == true { return }
        guard let recordName = (try? await SyncConstants.container.userRecordID())?.recordName else { return }
        guard let mine = Self.participantMatching(cloudUserID: recordName, in: context) else { return }
        guard LocalPrefs.shared.myParticipantID != mine.id else { return }
        AppLog.sync.log("Repaired dangling local identity → participant \(mine.id, privacy: .public)")
        LocalPrefs.shared.myParticipantID = mine.id
    }

    /// One-time re-enqueue of every schedule record. The nighttime schedule
    /// shipped before PlanSlot/PlanOverride existed in the DEPLOYED CloudKit
    /// schema, so the server rejected each save (`invalidArguments` — same for
    /// SharedSettings saves carrying the night-window fields) and the old
    /// failure handler dropped them from the queue for good: the owner saw his
    /// local slots, the co-parent an empty schedule. Re-enqueueing re-sends
    /// everything; if the schema still isn't deployed the saves now park (see
    /// `handleSentRecordZoneChanges`) and retry on later starts instead of
    /// vanishing again.
    ///
    /// SharedSettings re-pushes only from the owner/solo side: it's a
    /// singleton both phones hold, and re-pushing the participant's copy —
    /// whose night-window fields may still be the defaults — could clobber
    /// the owner's configured schedule.
    ///
    /// Internal so the one-shot + role routing is unit-testable without a
    /// live engine (`enqueueSave` parks to the hold queues there).
    func resyncScheduleRecordsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Keys.resyncSchedule) else { return }
        UserDefaults.standard.set(true, forKey: Keys.resyncSchedule)
        var ids: [UUID] = []
        ids += ((try? context.fetch(FetchDescriptor<PlanSlot>())) ?? []).map(\.id)
        ids += ((try? context.fetch(FetchDescriptor<PlanOverride>())) ?? []).map(\.id)
        if Self.realSyncRole != .participant {
            ids += ((try? context.fetch(FetchDescriptor<SharedSettings>())) ?? []).map(\.id)
        }
        guard !ids.isEmpty else { return }
        AppLog.sync.log("Re-enqueueing \(ids.count) schedule record(s) whose uploads predate the deployed schema")
        enqueueSave(ids)
    }

    /// One-time full re-fetch after an app update that taught this client new
    /// record types. `RecordMapping.apply` ignores types it doesn't know, and
    /// the engine checkpoints the fetched batch regardless — so a record of a
    /// type introduced in build N+1, fetched by a device still on build N, is
    /// dropped and never re-delivered (the fetch token is already past it;
    /// only a later server-side modification would resend it). Real case: a
    /// phone on a pre-schedule build fetched the co-parent's PlanSlot records,
    /// dropped them, and showed an empty schedule forever after updating.
    ///
    /// Comparing the persisted known-type set against this build's catches
    /// every future type addition with no manual version bump. An absent key
    /// (any install predating this mechanism) also triggers — that's the heal
    /// for the drops that already happened. Discarding the engine state files
    /// restarts both engines from a nil fetch token; the resulting whole-zone
    /// re-fetch is safe because `apply` upserts by record id (same recovery
    /// `resetEngineAfterFetchApplyFailure` relies on). Unsent local changes
    /// live in those same state files, so they're parked first and drain when
    /// the fresh engines start.
    private func resetFetchStateIfRecordTypesExpanded() {
        let defaults = UserDefaults.standard
        let missing = Self.newlyLearnedRecordTypes(
            sincePersisted: defaults.stringArray(forKey: Keys.knownRecordTypes))
        // Fields added to EXISTING types are invisible to the type-set diff —
        // the July 2026 hole this closes: a pre-feature build fetched the
        // SharedSettings record after the co-parent published snooCredentials,
        // dropped the unknown field, and the checkpoint moved past it for
        // good. The manual generation bump forces the same heal for fields.
        // An install with no persisted generation (0) also triggers once —
        // that IS the heal for drops that already happened.
        let generationGrew = defaults.integer(forKey: Keys.schemaGeneration)
            < SyncConstants.RecordType.schemaGeneration
        guard !missing.isEmpty || generationGrew else { return }
        // A fresh install has no fetch state to reset — record the set quietly.
        let hadState = FileManager.default.fileExists(atPath: stateURL(.private).path)
            || FileManager.default.fileExists(atPath: stateURL(.shared).path)
        if hadState {
            let reason = missing.isEmpty
                ? "schema generation \(SyncConstants.RecordType.schemaGeneration)"
                : missing.sorted().joined(separator: ", ")
            AppLog.sync.log("Client learned \(reason, privacy: .public) — resetting fetch state so records dropped by the previous build are re-delivered")
            discardFetchStateParkingUnsent(.private)
            discardFetchStateParkingUnsent(.shared)
        }
        defaults.set(SyncConstants.RecordType.all.sorted(), forKey: Keys.knownRecordTypes)
        defaults.set(SyncConstants.RecordType.schemaGeneration, forKey: Keys.schemaGeneration)
    }

    /// Record types this build understands that the previous run's build (its
    /// persisted set) did not. Non-empty means the previous build may have
    /// fetched-and-dropped records of those types. Nil (no persisted set — the
    /// install predates the mechanism) returns every type: those installs may
    /// hold drops from any past update, so they get the one-time heal too.
    static func newlyLearnedRecordTypes(sincePersisted persisted: [String]?) -> Set<String> {
        SyncConstants.RecordType.all.subtracting(persisted ?? [])
    }

    /// Deletes one scope's engine state file (nil fetch token → whole-zone
    /// re-fetch on next start) after harvesting any unsent changes out of it
    /// into the hold queues. When no engine is live for the scope, the unsent
    /// changes exist only inside the serialized state — a throwaway engine
    /// (automatic sync off, never installed as privateEngine/sharedEngine, so
    /// the `handleEvent` identity guard drops its events) reads them out.
    private func discardFetchStateParkingUnsent(_ scope: CKDatabase.Scope) {
        if let live = scope == .shared ? sharedEngine : privateEngine {
            parkUnsentChanges(live.state.pendingRecordZoneChanges, scope: scope)
            if scope == .shared {
                sharedEngine = nil
            } else {
                privateEngine = nil
                handledPrivateZoneDeletion = false
            }
        } else if let state = loadState(scope) {
            var config = CKSyncEngine.Configuration(
                database: scope == .shared
                    ? SyncConstants.container.sharedCloudDatabase
                    : SyncConstants.container.privateCloudDatabase,
                stateSerialization: state,
                delegate: self
            )
            config.automaticallySync = false
            let reader = CKSyncEngine(config)
            parkUnsentChanges(reader.state.pendingRecordZoneChanges, scope: scope)
        }
        try? FileManager.default.removeItem(at: stateURL(scope))
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
            // If our row was merged AWAY (auto-merge after a re-join), the same
            // iCloud account already has a live survivor — adopt it. Reactivating
            // the tombstone would re-mint the duplicate People row the merge
            // just collapsed, on both phones.
            if let cid = me.cloudUserID,
               let survivor = ((try? context.fetch(FetchDescriptor<Participant>())) ?? [])
                   .first(where: { $0.isActive && $0.cloudUserID == cid && $0.id != me.id }) {
                LocalPrefs.shared.myParticipantID = survivor.id
                AppLog.sync.log("Re-accept adopted surviving participant identity \(survivor.id, privacy: .public) instead of reactivating a merged-away row")
                return
            }
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

        let knownParticipants = Set(((try? context.fetch(FetchDescriptor<Participant>())) ?? []).map(\.id))

        for r in records {
            guard let loggedBy = (r["loggedByID"] as? String).flatMap(UUID.init),
                  loggedBy != myID,                    // never notify yourself
                  knownParticipants.contains(loggedBy), // never notify for ghost-shaped records
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

    /// Whether a record's save is still queued anywhere — a live engine's
    /// outbound queue or the parked hold queues. The SNOO Settings row uses
    /// this to show that a published household connection hasn't actually
    /// reached CloudKit yet (offline, engine down, or schema-rejected park)
    /// instead of letting "connected" masquerade as "household connected".
    func hasPendingSave(_ id: UUID) -> Bool {
        let name = id.uuidString
        for engine in [privateEngine, sharedEngine].compactMap({ $0 }) {
            let pending = engine.state.pendingRecordZoneChanges.contains {
                if case .saveRecord(let recordID) = $0 { return recordID.recordName == name }
                return false
            }
            if pending { return true }
        }
        let defaults = UserDefaults.standard
        return (defaults.stringArray(forKey: Keys.pendingPrivateSaves) ?? []).contains(name)
            || (defaults.stringArray(forKey: Keys.pendingSharedSaves) ?? []).contains(name)
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
        ids += (try? context.fetch(FetchDescriptor<PlanSlot>()))?.map(\.id) ?? []
        ids += (try? context.fetch(FetchDescriptor<PlanOverride>()))?.map(\.id) ?? []
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
            // save push our version. "Waiting to send" includes the UserDefaults
            // HOLD queues, not just the engine's own queue — a ghost sweep that
            // ran while the engine was down (or the shared zone unknown) parked
            // its soft-deletes there, and a fetch of the still-live server copy
            // must not resurrect the rows it tombstoned.
            var pendingSaves = Set(syncEngine.state.pendingRecordZoneChanges.compactMap {
                if case .saveRecord(let id) = $0 { id } else { nil }
            })
            let heldKey = syncEngine === sharedEngine ? Keys.pendingSharedSaves : Keys.pendingPrivateSaves
            let heldNames = Set(UserDefaults.standard.stringArray(forKey: heldKey) ?? [])
            if !heldNames.isEmpty {
                pendingSaves.formUnion(e.modifications.map(\.record.recordID)
                    .filter { heldNames.contains($0.recordName) })
            }
            do {
                for mod in e.modifications {
                    if pendingSaves.contains(mod.record.recordID) {
                        let absorbed = RecordMapping.absorbConflict(server: mod.record, in: context)
                        if !absorbed {
                            // No local model — absorbConflict fell back to apply. Persist the
                            // server's change tag now, or the next outbound send carries no tag
                            // and re-conflicts immediately.
                            RecordMapping.persistSystemFields(of: mod.record, in: context)
                        }
                    } else {
                        try RecordMapping.apply(mod.record, in: context)
                        // Cache the server change tag so a later local edit of this
                        // record saves cleanly instead of conflicting.
                        RecordMapping.persistSystemFields(of: mod.record, in: context)
                    }
                    if syncEngine === sharedEngine, sharedZoneID == nil {
                        setSharedZone(mod.record.recordID.zoneID)
                    }
                }
                for del in e.deletions {
                    try RecordMapping.delete(recordName: del.recordID.recordName, in: context)
                }
            } catch {
                // A store error during upsert. The old path swallowed it and
                // blind-inserted, minting duplicate placeholder rows ("?" ghost
                // events). Same recovery as a failed batch save: reset this
                // engine so the whole batch is re-fetched and re-applied.
                AppLog.sync.error("Sync fetch apply hit a store error: \(error.localizedDescription, privacy: .public)")
                resetEngineAfterFetchApplyFailure(syncEngine)
                return
            }
            // Events can land before their Baby record (no batch ordering
            // guarantee) — attach them once the baby exists.
            RecordMapping.relinkOrphanEvents(in: context)
            do {
                try context.save()
            } catch {
                // The engine checkpoints this batch via the following .stateUpdate
                // whether or not we stored it — a swallowed failure here would
                // permanently lose the co-parent's changes (invariant 2). The
                // applied-but-unsaved changes are still in the context, so retry
                // once; if the store still refuses, reset this engine so a fresh
                // fetch re-delivers the batch.
                AppLog.sync.error("Sync fetch apply failed to save (retrying): \(error.localizedDescription, privacy: .public)")
                do { try context.save() } catch {
                    resetEngineAfterFetchApplyFailure(syncEngine)
                    return
                }
            }
            sweepGhostsIfNeeded(from: e.modifications.map(\.record))
            mergeDuplicateParticipantsIfNeeded(from: e.modifications.map(\.record))
            healUnnamedEventsIfNeeded(from: e.modifications.map(\.record))
            reconcileLiveActivity()
            WidgetCenter.shared.reloadAllTimelines()
            notifyCoParentActivity(from: e.modifications.map(\.record))
            // The co-parent's log just landed on THIS phone — relay the wake to
            // this phone's paired watch so its complication re-fetches now
            // instead of on the next background-refresh slot. (Their phone
            // can't nudge our watch; only a paired phone can.)
            nudgeWatchIfComplicationRelevant(recordTypes: e.modifications.map(\.record.recordType))
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
        // This phone's own log is now ON the server — the earliest moment a
        // watch fetch is guaranteed to find it, so this (not the local write)
        // is when the paired watch gets its wake.
        nudgeWatchIfComplicationRelevant(recordTypes: e.savedRecords.map(\.recordType))

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
                // The record vanished server-side. Two very different causes:
                // the zone was recreated (re-upload EVERYTHING as fresh creates —
                // the recovery path), or the other parent hard-deleted exactly
                // this record. Participant rows are the only app records that
                // are ever hard-deleted (the ghost-participant purge), so a
                // Participant hitting unknownItem outside a zone recovery means
                // the co-parent purged it — re-creating it would resurrect the
                // ghost row on both phones AND re-immunize any ghost events
                // attributed to it against the sweep. Adopt the deletion instead.
                if failed.record.recordType == SyncConstants.RecordType.participant,
                   !handledPrivateZoneDeletion || syncEngine === sharedEngine,
                   // The "not my own row" check below reads the real identity —
                   // demo overrides it, so never adopt deletions mid-demo.
                   !LocalPrefs.shared.demoModeEnabled,
                   let uuid = UUID(uuidString: recordID.recordName),
                   let purged = Participant.fetchByID(uuid, in: context),
                   purged.id != LocalPrefs.shared.myParticipantID {
                    AppLog.sync.log("Participant \(recordID.recordName, privacy: .public) was deleted server-side — adopting the deletion instead of re-creating")
                    context.delete(purged)
                } else {
                    RecordMapping.clearSystemFields(forRecordName: recordID.recordName, in: context)
                    reenqueueSaves.append(.saveRecord(recordID))
                }

            case .permissionFailure:
                if syncEngine === sharedEngine { detach = true }

            case .invalidArguments, .serverRejectedRequest:
                // The server refused the record itself. In production that's
                // almost always a record type or field missing from the
                // deployed schema (JIT schema creation is development-only,
                // and TestFlight runs against Production) — exactly how the
                // nighttime schedule was lost: every PlanSlot save came back
                // `invalidArguments` and was dropped here. Dropping violates
                // invariant 2, so park the save to re-send on a later engine
                // start, by which time the schema deploy has landed.
                AppLog.sync.error("Sync save rejected server-side for \(recordID.recordName, privacy: .public) (\(failed.record.recordType, privacy: .public)) — parked for retry. Likely an undeployed CloudKit schema change: \(failed.error.localizedDescription, privacy: .public)")
                if let uuid = UUID(uuidString: recordID.recordName) {
                    park([uuid], key: syncEngine === sharedEngine
                        ? Keys.pendingSharedSaves : Keys.pendingPrivateSaves)
                }

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

    /// Runs the self-healing ghost sweep after a fetch batch that carried an
    /// event record with the ghost signature (empty logger name) — a ghost
    /// created elsewhere must not take up residence in this store, and the
    /// sweep's synced soft-deletes clean the zone for both phones. Gated so
    /// routine batches don't pay for three table scans.
    private func sweepGhostsIfNeeded(from records: [CKRecord]) {
        guard !LocalPrefs.shared.demoModeEnabled else { return }
        let eventTypes = [SyncConstants.RecordType.feed, SyncConstants.RecordType.sleep,
                          SyncConstants.RecordType.diaper, SyncConstants.RecordType.note]
        let sawGhost = records.contains { r in
            eventTypes.contains(r.recordType)
                && ((r["loggedByName"] as? String)?.isEmpty ?? true)
        }
        // A live open sleep arriving from the co-parent can collide with one
        // started here (each phone's single-timer guard is local-only) — the
        // sweep also collapses concurrent open sleeps, so run it for those.
        let sawOpenSleep = records.contains { r in
            r.recordType == SyncConstants.RecordType.sleep
                && r["endedAt"] == nil && r["deletedAt"] == nil
        }
        guard sawGhost || sawOpenSleep else { return }
        EventStore(context: context).autoPurgeGhostEvents()
    }

    /// Collapses duplicate People rows after a fetch batch that carried a
    /// participant record — a re-join by the same iCloud account creates a
    /// fresh row and strands the old one, showing one person twice. Gated so
    /// routine event batches don't pay for the table scans. Runs even when the
    /// merge already happened on the other phone: this device may still need
    /// to adopt the survivor as its own identity.
    private func mergeDuplicateParticipantsIfNeeded(from records: [CKRecord]) {
        guard !LocalPrefs.shared.demoModeEnabled else { return }
        guard records.contains(where: { $0.recordType == SyncConstants.RecordType.participant })
        else { return }
        let changed = ParticipantMerger.mergeDuplicates(in: context)
        adoptSurvivorIdentityIfNeeded()
        guard !changed.isEmpty else { return }
        AppLog.sync.log("Merged duplicate participant rows (\(changed.count) records touched)")
        do { try context.save() } catch {
            AppLog.sync.error("Participant merge failed to save: \(error.localizedDescription, privacy: .public)")
            return
        }
        enqueueSave(changed)
    }

    /// Backfills the denormalized logger name/color onto events that carry a
    /// KNOWN participant id but an empty name (records written by an older
    /// build, or a partial upload). Without this they render as silhouette
    /// "ghost" rows forever: the auto-sweep refuses to touch them (the id is
    /// known, so they're real), and the display trusts the denormalized name.
    /// Gated to batches that carried an event or participant record; synced so
    /// the zone and the co-parent heal too.
    private func healUnnamedEventsIfNeeded(from records: [CKRecord]) {
        guard !LocalPrefs.shared.demoModeEnabled else { return }
        // Only pay the table scans when the batch could have changed anything:
        // an event record arriving WITHOUT a name, or a participant record
        // (whose arrival may newly resolve previously unnamed events).
        let eventTypes = [SyncConstants.RecordType.feed, SyncConstants.RecordType.sleep,
                          SyncConstants.RecordType.diaper, SyncConstants.RecordType.note]
        let relevant = records.contains { r in
            r.recordType == SyncConstants.RecordType.participant
                || (eventTypes.contains(r.recordType)
                    && ((r["loggedByName"] as? String)?.isEmpty ?? true))
        }
        guard relevant else { return }

        let named = ((try? context.fetch(FetchDescriptor<Participant>())) ?? [])
            .filter { !$0.displayName.isEmpty }
        guard !named.isEmpty else { return }
        let byID = Dictionary(named.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        var changed: [UUID] = []
        func heal<T: PersistentModel & AnyEventModel & HasSyncID>(_ type: T.Type) {
            let all = (try? context.fetch(FetchDescriptor<T>())) ?? []
            for e in all where e.loggedByName.isEmpty {
                guard let p = byID[e.loggedByID] else { continue }
                e.loggedByName = p.displayName
                e.loggedByColorHex = p.colorHex
                changed.append(e.id)
            }
        }
        heal(FeedEvent.self)
        heal(SleepEvent.self)
        heal(DiaperEvent.self)
        guard !changed.isEmpty else { return }
        AppLog.sync.log("Backfilled logger identity onto \(changed.count) unnamed event(s)")
        do { try context.save() } catch {
            AppLog.sync.error("Unnamed-event heal failed to save: \(error.localizedDescription, privacy: .public)")
            return
        }
        enqueueSave(changed)
    }

    /// If this device's own Participant row was merged away (here or on the
    /// other phone), re-point `myParticipantID` at the surviving row for the
    /// same iCloud account so writes keep attributing to the right person.
    private func adoptSurvivorIdentityIfNeeded() {
        guard let myID = LocalPrefs.shared.myParticipantID,
              let me = Participant.fetchByID(myID, in: context), !me.isActive,
              let cid = me.cloudUserID else { return }
        let all = (try? context.fetch(FetchDescriptor<Participant>())) ?? []
        guard let survivor = all.first(where: { $0.isActive && $0.cloudUserID == cid }) else { return }
        LocalPrefs.shared.myParticipantID = survivor.id
        AppLog.sync.log("Adopted surviving participant identity \(survivor.id, privacy: .public) after merge")
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
        SleepActivityManager.reconcile(babyName: babyName, activeSleepStartedAt: active?.startedAt,
                                       nextFeed: QuickLogger(context: context).nextFeedPrediction())
    }

    /// Re-arms this device's feed alarm + gentle reminders + daily summary off the
    /// current store state, after a sync fetch changed it. Mirrors what a foreground
    /// does (`AppDelegate.applicationDidBecomeActive`) so a co-parent's synced-in or
    /// synced-away feed doesn't leave a stale "feed due" alarm pointed at an old
    /// last-feed. Cheap-guarded: default installs (all reminder prefs off) pay
    /// nothing — no store read happens unless something is actually scheduled.
    private func rearmFeedRemindersFromStore() {
        guard !LocalPrefs.shared.demoModeEnabled else { return }
        // Slot reminders re-plan on every fetch regardless of the alarm prefs —
        // this is THE cross-device path: the co-parent's swap or 2:50am logged
        // feed syncs in here, and this device's pending "you're up" request
        // moves or disappears accordingly.
        NotificationManager.refreshScheduleReminders()
        let rearmFeedAlarm = LocalPrefs.shared.feedReminderEnabled
            || LocalPrefs.shared.gentleRemindersEnabled
            || LocalPrefs.shared.notifyMilestones
        let logger = rearmFeedAlarm ? QuickLogger.make() : nil
        let haveLogger = logger != nil
        let babyName = logger?.babyName ?? "Baby"
        let lastFeed = logger?.lastFeed?.timestamp
        let interval = logger?.feedInterval(after: lastFeed) ?? 0
        Task {
            // Sequenced pair: the feed alarm's stand-down check reads the slot
            // alarm's published fire date, so the slot alarm settles first.
            await SlotAlarmManager.reschedule()
            if rearmFeedAlarm, haveLogger {
                await FeedAlarmManager.reschedule(babyName: babyName, lastFeed: lastFeed, interval: interval)
            }
        }
        guard rearmFeedAlarm, haveLogger else { return }
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

    /// Recovery for a fetched batch the local store refused to save: the engine
    /// checkpoints fetched changes regardless, so without intervention that batch
    /// is never re-delivered. Discard this engine and its persisted state — the
    /// replacement starts from a nil fetch token and re-fetches the whole zone,
    /// which is safe because `RecordMapping.apply` upserts by record name. Unsent
    /// local changes live in the same state file, so park them first (they drain
    /// on the restart). The identity guard at the top of `handleEvent` keeps the
    /// discarded engine's trailing `.stateUpdate` from resurrecting the file.
    private func resetEngineAfterFetchApplyFailure(_ engine: CKSyncEngine) {
        let scope = scope(for: engine)
        AppLog.sync.fault("Fetched changes could not be saved; resetting \(scope == .shared ? "shared" : "private", privacy: .public) engine to re-fetch.")
        parkUnsentChanges(engine.state.pendingRecordZoneChanges, scope: scope)
        if scope == .shared {
            sharedEngine = nil
        } else {
            privateEngine = nil
            handledPrivateZoneDeletion = false
        }
        try? FileManager.default.removeItem(at: stateURL(scope))
        start()
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
                } else if (try? RecordMapping.modelExists(recordName: id.recordName, in: self.context)) == false {
                    // Confirmed absent — drop the stale pending change. Only a
                    // positive "not in the store" answer may drop (invariant 2):
                    // a nil record from a transient fetch error must stay queued.
                    syncEngine.state.remove(pendingRecordZoneChanges: [change])
                } else {
                    // Store fetch failed — leave the change pending; the engine
                    // retries it on the next send cycle.
                    AppLog.sync.error("Send of \(id.recordName, privacy: .public) skipped this batch — store fetch failed; will retry.")
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
            Self.setRealRole(.owner)
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
            Self.setRealRole(.owner)
            return saved
        }
        // Save reported success without returning our record (or another device
        // created the share concurrently) — fetch the canonical copy.
        if let fetched = try? await db.record(for: shareID) as? CKShare {
            Self.setRealRole(.owner)
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
        let plan = Self.removalPlan(
            cloudUserID: participant.cloudUserID,
            shareMemberIDs: removable.map { $0.userIdentity.userRecordID?.recordName },
            isSoleCoParticipant: isSoleCoParticipant(participant)
        )

        switch plan {
        case .removeShareMember(let index):
            share.removeParticipant(removable[index])
            let results = try await db.modifyRecords(saving: [share], deleting: [])
            if let result = results.saveResults[share.recordID] { _ = try result.get() }
            participant.isActive = false
            try? context.save()
            enqueueSave([participant.id])

        case .purgeRecordOnly:
            // No share member corresponds to this record: a ghost participant
            // (a leaked dev-fixture record that was never on the share) or
            // someone who already left. The share needs no change. HARD-delete
            // only when no events reference the row — orphaning real history
            // turns it into "unknown entries" that the manual purge would then
            // destroy on both phones, and strands the timeline attribution.
            // A row with history deactivates instead (same end state as a
            // removed share member: hidden from People, events keep their name).
            let id = participant.id
            if participantHasEvents(id) {
                participant.isActive = false
                try? context.save()
                enqueueSave([id])
            } else {
                context.delete(participant)
                try? context.save()
                enqueueDelete([id])
            }
        }
    }

    /// Whether any event row (live or soft-deleted) is attributed to this
    /// participant — the guard between "safe to hard-delete" and "must keep the
    /// row so history stays attributed".
    private func participantHasEvents(_ id: UUID) -> Bool {
        var feed = FetchDescriptor<FeedEvent>(predicate: #Predicate { $0.loggedByID == id })
        feed.fetchLimit = 1
        if ((try? context.fetchCount(feed)) ?? 0) > 0 { return true }
        var sleep = FetchDescriptor<SleepEvent>(predicate: #Predicate { $0.loggedByID == id })
        sleep.fetchLimit = 1
        if ((try? context.fetchCount(sleep)) ?? 0) > 0 { return true }
        var diaper = FetchDescriptor<DiaperEvent>(predicate: #Predicate { $0.loggedByID == id })
        diaper.fetchLimit = 1
        return ((try? context.fetchCount(diaper)) ?? 0) > 0
    }

    /// Which action removing a participant should take — pure so the ghost /
    /// pending-invitee cases are unit-testable.
    ///
    /// The old logic had two traps this table closes: `nil == nil` counted as
    /// an identity match (a pending invitee's userRecordID can be nil, and a
    /// ghost record's cloudUserID always is), and an identity-less removal
    /// fell back to "the sole non-owner member" unconditionally — so removing
    /// a ghost row could kick the REAL co-parent off the share.
    static func removalPlan(
        cloudUserID: String?,
        shareMemberIDs: [String?],
        isSoleCoParticipant: Bool
    ) -> ParticipantRemovalPlan {
        if let cloudUserID, let index = shareMemberIDs.firstIndex(of: cloudUserID) {
            return .removeShareMember(index: index)
        }
        // Identity never captured, but both sides agree there's exactly one
        // other person — they must be the same one. Any ambiguity falls
        // through: touching the wrong share member is unrecoverable, deleting
        // an app record is not (the member's own device re-syncs it).
        if cloudUserID == nil, shareMemberIDs.count == 1, isSoleCoParticipant {
            return .removeShareMember(index: 0)
        }
        return .purgeRecordOnly
    }

    enum ParticipantRemovalPlan: Equatable {
        case removeShareMember(index: Int)
        case purgeRecordOnly
    }

    /// Whether a participant record corresponds to a current share member.
    /// Nil-safe like `removalPlan`: an unknown identity never matches, so a
    /// ghost record (nil cloudUserID) is correctly reported as off-share.
    /// Drives "Resend link" — the invite URL only works for current members,
    /// so anyone else must be re-ADDED via the sharing sheet instead.
    static func shareHasMember(cloudUserID: String?, memberIDs: [String?]) -> Bool {
        guard let cloudUserID else { return false }
        return memberIDs.contains(cloudUserID)
    }

    /// True when `participant` is the only active participant besides "me" in
    /// the local store — the precondition for the identity-less fallback above.
    private func isSoleCoParticipant(_ participant: Participant) -> Bool {
        let all = (try? context.fetch(FetchDescriptor<Participant>())) ?? []
        let others = all.filter { $0.isActive && $0.id != LocalPrefs.shared.myParticipantID }
        return others.count == 1 && others.first?.id == participant.id
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
        // Nothing remains to remind about — cancel both alarms and sweep any
        // pending "you're up" slot reminders.
        Task {
            await FeedAlarmManager.cancel()
            await SlotAlarmManager.cancel()
        }
        NotificationManager.cancelScheduleReminders()
        // "Delete everything" resets to a fresh install — the SNOO connection
        // (whose shared record just went with the zone) goes too, so it can't
        // resurface via the `.publishLocal` migration in whatever household
        // this device sets up next.
        Task { await SnooSyncCoordinator.shared.handleHouseholdLeft() }
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
        try? context.delete(model: PlanSlot.self)
        try? context.delete(model: PlanOverride.self)
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
                // A re-join creates a fresh row; if this same iCloud account
                // already has another active row (the pre-reinstall profile),
                // fold the two into one person right away.
                let merged = ParticipantMerger.mergeDuplicates(in: context)
                adoptSurvivorIdentityIfNeeded()
                try? context.save()
                enqueueSave([me.id] + merged)
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
        // Cancel any pending alarms and slot reminders — the baby data is gone,
        // so nothing to count down to, and an ex-member's phone must not ring
        // at 3am for a household they left. The user's reminder preferences are
        // preserved so everything auto-arms if they join or create a new
        // household.
        Task {
            await FeedAlarmManager.cancel()
            await SlotAlarmManager.cancel()
        }
        NotificationManager.cancelScheduleReminders()
        // An ex-member must not keep the household's SNOO account either: the
        // credential arrived through the zone that just revoked, and leaving
        // it in the Keychain both keeps polling the owner's bassinet and
        // re-publishes the token into any future household via the
        // `.publishLocal` migration.
        Task { await SnooSyncCoordinator.shared.handleHouseholdLeft() }
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
        Self.stateFileURL(scope)
    }

    private nonisolated static func stateFileURL(_ scope: CKDatabase.Scope) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("sync-state-\(scope == .shared ? "shared" : "private").data")
    }

    /// The local store was destroyed and replaced (quarantine of an unreadable
    /// SQLite file — see `AppModelContainer.make`). Every piece of persisted
    /// sync state describes the DEAD store, so it must die with it:
    /// - the engine fetch tokens claim "fully caught up", which would stop the
    ///   fresh empty store from ever re-downloading the family's history — the
    ///   owner would land back in onboarding and mint a duplicate
    ///   Baby/Participant into the still-populated zone;
    /// - the bootstrap flag claims "already uploaded", suppressing the
    ///   reconcile that re-links the recovered rows.
    /// The hold queues stay: their ids' models are gone, and the send path
    /// drops confirmed-absent records safely. Static (and nonisolated) because
    /// it runs during container creation, before any SyncManager exists.
    nonisolated static func resetPersistedSyncStateForStoreLoss() {
        try? FileManager.default.removeItem(at: stateFileURL(.private))
        try? FileManager.default.removeItem(at: stateFileURL(.shared))
        UserDefaults.standard.removeObject(forKey: Keys.bootstrapPrivate)
        UserDefaults.standard.removeObject(forKey: Keys.knownRecordTypes)
    }

    private func loadState(_ scope: CKDatabase.Scope) -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: stateURL(scope)) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func saveState(_ state: CKSyncEngine.State.Serialization, scope: CKDatabase.Scope) {
        // A throwaway in-memory fallback session must never advance the ON-DISK
        // fetch token: records fetched into a store that evaporates at exit
        // would otherwise never be re-delivered to the healed real store.
        guard !AppModelContainer.isEphemeralFallback else { return }
        guard let data = try? JSONEncoder().encode(state) else { return }
        let url = stateURL(scope)
        // iOS doesn't create Application Support automatically — today SwiftData's
        // default store happens to make it first, but this write must not depend
        // on that: a silently failed save here means a fresh engine next launch,
        // full re-fetch, and every unsent pending change lost.
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        // Atomic: a torn write would decode as nil next launch — same cost.
        try? data.write(to: url, options: .atomic)
    }
}
