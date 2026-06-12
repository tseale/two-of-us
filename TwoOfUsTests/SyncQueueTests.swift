import XCTest
import SwiftData
@testable import TwoOfUs

/// Exercises the engine-free parts of `SyncManager`: the hold queues a
/// participant uses before the owner's shared zone is known, and the
/// device-state flip on share accept. No CKSyncEngine is ever started
/// (`start()` is never called and iCloud is unavailable in the test host), so
/// these run anywhere the simulator does.
///
/// `SyncManager` reads `LocalPrefs.shared` and `UserDefaults.standard`, which
/// the test host app also uses — every test saves and restores what it touches.
@MainActor
final class SyncQueueTests: XCTestCase {
    private var container: ModelContainer!
    private var manager: SyncManager!
    private var savedRole: SyncRole!

    private let savesKey = "sync.pendingSharedSaves"
    private let deletesKey = "sync.pendingSharedDeletes"
    private let bootstrapSharedKey = "sync.bootstrap.shared"

    override func setUp() {
        super.setUp()
        container = AppModelContainer.make(inMemory: true)
        manager = SyncManager(modelContainer: container)
        savedRole = LocalPrefs.shared.syncRole
        UserDefaults.standard.removeObject(forKey: savesKey)
        UserDefaults.standard.removeObject(forKey: deletesKey)
        UserDefaults.standard.removeObject(forKey: bootstrapSharedKey)
    }

    override func tearDown() {
        LocalPrefs.shared.syncRole = savedRole
        UserDefaults.standard.removeObject(forKey: savesKey)
        UserDefaults.standard.removeObject(forKey: deletesKey)
        UserDefaults.standard.removeObject(forKey: bootstrapSharedKey)
        manager = nil
        container = nil
        super.tearDown()
    }

    private func held(_ key: String) -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    func testParticipantSavesHeldWhileZoneUnknown() {
        LocalPrefs.shared.syncRole = .participant
        let id = UUID()
        manager.enqueueSave([id])
        XCTAssertEqual(held(savesKey), [id.uuidString],
                       "saves made before the owner's zone is discovered must be parked, not dropped")
    }

    func testParticipantDeletesHeldWhileZoneUnknown() {
        LocalPrefs.shared.syncRole = .participant
        let id = UUID()
        manager.enqueueDelete([id])
        XCTAssertEqual(held(deletesKey), [id.uuidString],
                       "deletes get the same hold as saves (previously they were silently dropped)")
    }

    func testHeldChangesAccumulateAcrossCalls() {
        LocalPrefs.shared.syncRole = .participant
        let a = UUID(), b = UUID()
        manager.enqueueSave([a])
        manager.enqueueSave([b])
        XCTAssertEqual(held(savesKey), [a.uuidString, b.uuidString])
    }

    func testEmptyEnqueueLeavesNoTrace() {
        LocalPrefs.shared.syncRole = .participant
        manager.enqueueSave([])
        manager.enqueueDelete([])
        XCTAssertTrue(held(savesKey).isEmpty)
        XCTAssertTrue(held(deletesKey).isEmpty)
    }

    func testMarkShareAcceptedFlipsRoleWithoutAManager() {
        // The whole point of the static: a cold-launch link tap (or demo mode)
        // accepts before SyncManager.shared exists.
        LocalPrefs.shared.syncRole = .solo
        UserDefaults.standard.set(true, forKey: bootstrapSharedKey)

        SyncManager.markShareAccepted()

        XCTAssertEqual(LocalPrefs.shared.syncRole, .participant)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: bootstrapSharedKey),
                       "a re-accept must re-run the shared bootstrap")
    }
}
