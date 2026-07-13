import XCTest
import CloudKit
import SwiftData
@testable import TwoOfUs

/// Exercises the engine-free parts of `SyncManager`: the hold queues used
/// whenever the right engine/zone isn't available yet, and the device-state
/// flip on share accept. No CKSyncEngine is ever started (`start()` is never
/// called and iCloud is unavailable in the test host), so these run anywhere
/// the simulator does.
///
/// `SyncManager` reads `LocalPrefs.shared` and `UserDefaults.standard`, which
/// the test host app also uses — every test saves and restores what it touches.
@MainActor
final class SyncQueueTests: XCTestCase {
    private var container: ModelContainer!
    private var manager: SyncManager!
    private var savedRole: SyncRole!
    private var savedParticipantID: UUID?
    private var savedDefaults: [String: Any?] = [:]

    private let sharedSavesKey = "sync.pendingSharedSaves"
    private let sharedDeletesKey = "sync.pendingSharedDeletes"
    private let privateSavesKey = "sync.pendingPrivateSaves"
    private let privateDeletesKey = "sync.pendingPrivateDeletes"
    private let zoneNameKey = "sync.sharedZone.name"
    private let zoneOwnerKey = "sync.sharedZone.owner"
    private let demoKeys = ["demo.overrideActive", "demo.bak.syncRole", "demo.bak.participantID"]
    private let legacyWidgetKey = "sync.pendingWidgetWrites"
    private let widgetPrefix = "sync.widgetWrite."
    private var savedGroupDefaults: [String: Any?] = [:]

    private var allKeys: [String] {
        [sharedSavesKey, sharedDeletesKey, privateSavesKey, privateDeletesKey, zoneNameKey, zoneOwnerKey] + demoKeys
    }

    // The test host is the real app: snapshot EVERY default these tests touch
    // (including the device identity the demo round-trip rewrites) and restore
    // the original values — deleting them would wipe a real participant's
    // persisted shared zone or widget identity on a development device.
    override func setUp() {
        super.setUp()
        container = AppModelContainer.make(inMemory: true)
        manager = SyncManager(modelContainer: container)
        savedRole = LocalPrefs.shared.syncRole
        savedParticipantID = LocalPrefs.shared.myParticipantID
        savedDefaults = Dictionary(uniqueKeysWithValues: allKeys.map { ($0, UserDefaults.standard.object(forKey: $0)) })
        allKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        // Same care for the App Group widget queue: a dev device may hold REAL
        // queued widget writes — snapshot and restore, never just delete.
        if let group = AppGroup.userDefaults {
            var snap: [String: Any?] = [legacyWidgetKey: group.object(forKey: legacyWidgetKey)]
            for key in group.dictionaryRepresentation().keys where key.hasPrefix(widgetPrefix) {
                snap[key] = group.object(forKey: key)
            }
            savedGroupDefaults = snap
            snap.keys.forEach { group.removeObject(forKey: $0) }
        }
    }

    override func tearDown() {
        LocalPrefs.shared.syncRole = savedRole
        LocalPrefs.shared.myParticipantID = savedParticipantID
        for (key, value) in savedDefaults {
            if let value {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        if let group = AppGroup.userDefaults {
            // Drop anything a test left, then restore the pre-test queue.
            for key in group.dictionaryRepresentation().keys where key.hasPrefix(widgetPrefix) {
                group.removeObject(forKey: key)
            }
            for (key, value) in savedGroupDefaults {
                if let value { group.set(value, forKey: key) } else { group.removeObject(forKey: key) }
            }
        }
        manager = nil
        container = nil
        super.tearDown()
    }

    private func held(_ key: String) -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    // MARK: Participant hold queue

    func testParticipantSavesHeldWhileZoneUnknown() {
        LocalPrefs.shared.syncRole = .participant
        let id = UUID()
        manager.enqueueSave([id])
        XCTAssertEqual(held(sharedSavesKey), [id.uuidString],
                       "saves made before the owner's zone is discovered must be parked, not dropped")
    }

    func testParticipantDeletesHeldWhileZoneUnknown() {
        LocalPrefs.shared.syncRole = .participant
        let id = UUID()
        manager.enqueueDelete([id])
        XCTAssertEqual(held(sharedDeletesKey), [id.uuidString],
                       "deletes get the same hold as saves (previously they were silently dropped)")
    }

    func testHeldChangesAccumulateAcrossCalls() {
        LocalPrefs.shared.syncRole = .participant
        let a = UUID(), b = UUID()
        manager.enqueueSave([a])
        manager.enqueueSave([b])
        XCTAssertEqual(held(sharedSavesKey), [a.uuidString, b.uuidString])
    }

    // MARK: Solo/owner hold queue (no engine → park, never drop)

    func testSoloSavesHeldWhileEngineDown() {
        LocalPrefs.shared.syncRole = .solo
        let id = UUID()
        manager.enqueueSave([id])
        XCTAssertEqual(held(privateSavesKey), [id.uuidString],
                       "solo/owner writes used to be silently dropped when the private engine wasn't running")
    }

    func testOwnerDeletesHeldWhileEngineDown() {
        LocalPrefs.shared.syncRole = .owner
        let id = UUID()
        manager.enqueueDelete([id])
        XCTAssertEqual(held(privateDeletesKey), [id.uuidString])
    }

    func testEmptyEnqueueLeavesNoTrace() {
        LocalPrefs.shared.syncRole = .participant
        manager.enqueueSave([])
        manager.enqueueDelete([])
        XCTAssertTrue(held(sharedSavesKey).isEmpty)
        XCTAssertTrue(held(sharedDeletesKey).isEmpty)
    }

    // MARK: Sign-out harvesting (engine state → hold queues)

    func testParkUnsentChangesRoutesPrivateScopeToPrivateQueues() {
        let save = UUID(), delete = UUID()
        let changes: [CKSyncEngine.PendingRecordZoneChange] = [
            .saveRecord(CKRecord.ID(recordName: save.uuidString)),
            .deleteRecord(CKRecord.ID(recordName: delete.uuidString)),
        ]

        manager.parkUnsentChanges(changes, scope: .private)

        XCTAssertEqual(held(privateSavesKey), [save.uuidString],
                       "sign-out deletes the engine state file — unsent saves must land in the hold queue first")
        XCTAssertEqual(held(privateDeletesKey), [delete.uuidString])
        XCTAssertTrue(held(sharedSavesKey).isEmpty, "private-scope changes must not leak into the shared queues")
    }

    func testParkUnsentChangesRoutesSharedScopeToSharedQueues() {
        let save = UUID()
        manager.parkUnsentChanges([.saveRecord(CKRecord.ID(recordName: save.uuidString))], scope: .shared)

        XCTAssertEqual(held(sharedSavesKey), [save.uuidString])
        XCTAssertTrue(held(privateSavesKey).isEmpty)
    }

    func testParkUnsentChangesAppendsAfterExistingHeldIDs() {
        LocalPrefs.shared.syncRole = .solo
        let first = UUID(), second = UUID()
        manager.enqueueSave([first])   // parked (no engine)

        manager.parkUnsentChanges([.saveRecord(CKRecord.ID(recordName: second.uuidString))], scope: .private)

        XCTAssertEqual(held(privateSavesKey), [first.uuidString, second.uuidString],
                       "harvested engine changes must append to, not clobber, already-parked ids")
    }

    func testParkUnsentChangesIgnoresNonUUIDRecordNames() {
        // The zone-wide share record lives in the same zone; its name is not a
        // model UUID and must not be replayed through the model save path.
        manager.parkUnsentChanges([.saveRecord(CKRecord.ID(recordName: CKRecordNameZoneWideShare))], scope: .private)

        XCTAssertTrue(held(privateSavesKey).isEmpty)
    }

    // MARK: Delete-everything server gate

    func testDeleteRequiresServerWhenOwnerHasBootstrapped() {
        XCTAssertTrue(SyncManager.requiresServerDeletion(
            isParticipant: false, sharedZoneKnown: false, hasBootstrappedUpload: true),
            "an owner who has uploaded must not local-wipe offline — the zone would resurrect everything")
    }

    func testDeleteAllowsLocalWipeWhenNeverSynced() {
        XCTAssertFalse(SyncManager.requiresServerDeletion(
            isParticipant: false, sharedZoneKnown: false, hasBootstrappedUpload: false),
            "a device that never pushed anywhere can delete locally without the network")
    }

    func testDeleteRequiresServerForAttachedParticipant() {
        XCTAssertTrue(SyncManager.requiresServerDeletion(
            isParticipant: true, sharedZoneKnown: true, hasBootstrappedUpload: false))
    }

    func testDeleteAllowsLocalWipeForParticipantWithUnknownZone() {
        XCTAssertFalse(SyncManager.requiresServerDeletion(
            isParticipant: true, sharedZoneKnown: false, hasBootstrappedUpload: false),
            "a participant whose zone was never discovered has nothing server-side to confirm")
    }

    // MARK: Widget extension queue (per-key scheme)

    func testDrainPicksUpPerKeyWidgetWritesAndRemovesThem() throws {
        let group = try XCTUnwrap(AppGroup.userDefaults, "test host should have the app-group suite")
        LocalPrefs.shared.syncRole = .solo
        let a = UUID(), b = UUID()
        group.set(a.uuidString, forKey: widgetPrefix + "test-a")
        group.set(b.uuidString, forKey: widgetPrefix + "test-b")

        manager.drainExtensionQueue()

        XCTAssertEqual(Set(held(privateSavesKey)), [a.uuidString, b.uuidString],
                       "widget-origin ids must land in the hold queue (no engine in tests)")
        XCTAssertNil(group.string(forKey: widgetPrefix + "test-a"),
                     "drained keys must be removed so ids aren't re-enqueued forever")
        XCTAssertNil(group.string(forKey: widgetPrefix + "test-b"))
    }

    func testDrainMigratesLegacyArrayQueue() throws {
        let group = try XCTUnwrap(AppGroup.userDefaults)
        LocalPrefs.shared.syncRole = .solo
        let legacy = UUID(), perKey = UUID()
        group.set([legacy.uuidString], forKey: legacyWidgetKey)
        group.set(perKey.uuidString, forKey: widgetPrefix + "test-new")

        manager.drainExtensionQueue()

        XCTAssertEqual(Set(held(privateSavesKey)), [legacy.uuidString, perKey.uuidString],
                       "an upgrade must drain ids queued under the old shared-array key too")
        XCTAssertNil(group.array(forKey: legacyWidgetKey))
    }

    func testDrainIgnoresGarbagePerKeyValues() throws {
        let group = try XCTUnwrap(AppGroup.userDefaults)
        LocalPrefs.shared.syncRole = .solo
        group.set("not-a-uuid", forKey: widgetPrefix + "test-junk")

        manager.drainExtensionQueue()

        XCTAssertTrue(held(privateSavesKey).isEmpty)
        XCTAssertNil(group.string(forKey: widgetPrefix + "test-junk"),
                     "junk keys must still be cleared, not re-scanned every drain")
    }

    // MARK: Share accept device state

    func testMarkShareAcceptedFlipsRoleWithoutAManager() {
        // The whole point of the static: a cold-launch link tap accepts before
        // SyncManager.shared exists.
        LocalPrefs.shared.syncRole = .solo

        SyncManager.markShareAccepted()

        XCTAssertEqual(LocalPrefs.shared.syncRole, .participant)
    }

    func testMarkShareAcceptedPersistsOwnersZone() {
        // The shared zone ID must survive relaunches: the engine never
        // re-announces an already-fetched zone, so without this every
        // participant write after a relaunch parks forever.
        LocalPrefs.shared.syncRole = .solo
        let zoneID = CKRecordZone.ID(zoneName: SyncConstants.zoneName, ownerName: "_ownerRecordName")

        SyncManager.markShareAccepted(zoneID: zoneID)

        XCTAssertEqual(UserDefaults.standard.string(forKey: zoneNameKey), SyncConstants.zoneName)
        XCTAssertEqual(UserDefaults.standard.string(forKey: zoneOwnerKey), "_ownerRecordName")
    }

    // MARK: Real role during demo

    func testRealSyncRoleSeesThroughDemoOverride() {
        LocalPrefs.shared.syncRole = .participant
        DemoSession.activate()   // overrides LocalPrefs to .owner
        defer { DemoSession.deactivate() }

        XCTAssertEqual(LocalPrefs.shared.syncRole, .owner, "demo override should be visible to the UI")
        XCTAssertEqual(SyncManager.realSyncRole, .participant,
                       "the sync layer must route by the REAL role, not the demo override")
    }

    func testMarkShareAcceptedSurvivesDemoExit() {
        // Accepting an invite mid-demo used to be clobbered: exiting demo
        // restored the pre-demo role backup over the freshly-set .participant.
        LocalPrefs.shared.syncRole = .solo
        DemoSession.activate()

        SyncManager.markShareAccepted()
        DemoSession.deactivate()

        XCTAssertEqual(LocalPrefs.shared.syncRole, .participant,
                       "exiting demo must not restore the stale pre-demo role over an accepted share")
    }
}
