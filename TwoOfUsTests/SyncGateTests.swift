import XCTest
@testable import TwoOfUs

/// The rule that keeps dev/test runs from polluting the family's CloudKit zone.
/// This gate is why `make uitest` / screenshot captures can never again upload
/// seeded sample events as ghost logs — treat any loosening with suspicion.
final class SyncGateTests: XCTestCase {

    func testSimulatorAlwaysBlocksSync() {
        XCTAssertEqual(SyncGate.reason(arguments: [], isSimulator: true), "simulator build")
        // Even a clean argument list doesn't help — the simulator is a dev
        // surface, and its only sync traffic is fixture data and test pokes.
        XCTAssertNotNil(SyncGate.reason(arguments: ["-AppleLanguages", "(en)"], isSimulator: true))
    }

    func testEveryFixtureArgumentBlocksSyncOnDevice() {
        for arg in SyncGate.fixtureArguments {
            XCTAssertNotNil(SyncGate.reason(arguments: ["/app/binary", arg], isSimulator: false),
                            "\(arg) mutates the real store — it must never launch with sync live")
        }
    }

    func testCleanDeviceLaunchAllowsSync() {
        XCTAssertNil(SyncGate.reason(arguments: ["/app/binary"], isSimulator: false))
        XCTAssertNil(SyncGate.reason(arguments: [], isSimulator: false))
    }

    func testSeedArgumentIsGated() {
        // The single most dangerous fixture — a week of fake events — by name,
        // so a rename can't silently drop it from the gate.
        XCTAssertTrue(SyncGate.fixtureArguments.contains("-seedSampleData"))
        XCTAssertTrue(SyncGate.fixtureArguments.contains("-wipeStore"))
    }

    func testFixtureTaintBlocksCleanLaunches() {
        // Seeded fixture rows OUTLIVE the seeding process — the taint keeps
        // sync off on later argument-less launches until the store is wiped,
        // or a bootstrap-flag reset would upload the fixtures as ghost logs.
        XCTAssertNotNil(SyncGate.reason(arguments: [], isSimulator: false, fixtureTainted: true))
        XCTAssertNil(SyncGate.reason(arguments: [], isSimulator: false, fixtureTainted: false))
    }

    func testRecordFixtureTaintLifecycle() {
        let saved = UserDefaults.standard.object(forKey: SyncGate.taintKey)
        defer {
            if let saved {
                UserDefaults.standard.set(saved, forKey: SyncGate.taintKey)
            } else {
                UserDefaults.standard.removeObject(forKey: SyncGate.taintKey)
            }
        }

        SyncGate.recordFixtureTaint(arguments: ["-seedSampleData"])
        XCTAssertTrue(UserDefaults.standard.bool(forKey: SyncGate.taintKey), "seeding taints")

        SyncGate.recordFixtureTaint(arguments: ["-wipeStore"])
        XCTAssertFalse(UserDefaults.standard.bool(forKey: SyncGate.taintKey), "a wipe restores a clean store")

        SyncGate.recordFixtureTaint(arguments: ["-wipeStore", "-seedSampleData"])
        XCTAssertTrue(UserDefaults.standard.bool(forKey: SyncGate.taintKey), "wipe-then-seed re-dirties")
    }
}
