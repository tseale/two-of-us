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
