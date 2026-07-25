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
}
