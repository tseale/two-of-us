import XCTest
import SwiftData
@testable import TwoOfUs

/// Nap-pairing behavior of the Brightwheel importer: naps arrive as separate
/// fell-asleep/woke-up activities, and an unpaired start is the live-nap
/// signal Home's daycare card pulses on — surfaced, never persisted.
@MainActor
final class BrightwheelImporterTests: XCTestCase {
    private var container: ModelContainer!
    private var savedDemo = false

    override func setUp() {
        super.setUp()
        savedDemo = LocalPrefs.shared.demoModeEnabled
        LocalPrefs.shared.demoModeEnabled = true
        container = AppModelContainer.make(inMemory: true)
        let ctx = container.mainContext
        ctx.insert(Baby(name: "Miller", dateOfBirth: .now))
        ctx.insert(Participant(displayName: "Taylor", colorHex: "#AABBCC"))
        ctx.insert(SharedSettings())
    }

    override func tearDown() {
        LocalPrefs.shared.demoModeEnabled = savedDemo
        container = nil
        super.tearDown()
    }

    private func napActivity(id: String, state: String, minutesAgo: Int) throws -> BrightwheelActivity {
        let when = ISO8601DateFormatter()
            .string(from: Date(timeIntervalSinceNow: -Double(minutesAgo) * 60))
        let dict: [String: Any] = ["object_id": id, "action_type": "ac_nap",
                                   "event_date": when, "state": state]
        return try JSONDecoder().decode(
            BrightwheelActivity.self,
            from: JSONSerialization.data(withJSONObject: dict))
    }

    func testUnpairedNapStartSurfacesAsLiveNapWithoutPersisting() throws {
        let start = try napActivity(id: "nap-start", state: "1", minutesAgo: 12)
        let summary = BrightwheelImporter(context: container.mainContext)
            .importActivities([start])
        XCTAssertEqual(summary.sleeps, 0,
                       "an open nap must not persist — the pair imports whole on wake")
        XCTAssertEqual(summary.openNapStartedAt, start.when)
    }

    func testPairedNapImportsAndReportsNoLiveNap() throws {
        let summary = BrightwheelImporter(context: container.mainContext)
            .importActivities([
                try napActivity(id: "nap-end", state: "0", minutesAgo: 5),
                try napActivity(id: "nap-start", state: "1", minutesAgo: 50),
            ])   // newest-first, like the API delivers
        XCTAssertEqual(summary.sleeps, 1)
        XCTAssertNil(summary.openNapStartedAt)
    }

    func testCompletedNapPlusNewStartIsALiveNap() throws {
        // Morning nap done, afternoon nap under way.
        let afternoon = try napActivity(id: "nap2-start", state: "1", minutesAgo: 10)
        let summary = BrightwheelImporter(context: container.mainContext)
            .importActivities([
                afternoon,
                try napActivity(id: "nap1-end", state: "0", minutesAgo: 120),
                try napActivity(id: "nap1-start", state: "1", minutesAgo: 165),
            ])
        XCTAssertEqual(summary.sleeps, 1)
        XCTAssertEqual(summary.openNapStartedAt, afternoon.when)
    }
}
