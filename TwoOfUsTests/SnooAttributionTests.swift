import XCTest
import SwiftData
@testable import TwoOfUs

/// Locks in who a SNOO-imported sleep is attributed to: the LOCAL participant
/// on the device that accepts (or auto-logs) the suggestion — never a fixed
/// person. Both card-accept and auto-log go through the same
/// `SnooSyncCoordinator.accept(_:store:)` path, so these tests cover both.
///
/// Runs with demo mode ON (no sync/widget/Live Activity side effects) and a
/// throwaway UserDefaults suite for the coordinator's bookkeeping so real
/// device state is never touched.
@MainActor
final class SnooAttributionTests: XCTestCase {
    private var container: ModelContainer!
    private var store: EventStore!
    private var coordinator: SnooSyncCoordinator!
    private var syncState: SnooSyncState!
    private var testDefaults: UserDefaults!
    private var boyTaylor: Participant!
    private var girlTaylor: Participant!
    private var savedDemo = false
    private var savedParticipantID: UUID?

    private static let defaultsSuite = "SnooAttributionTests"

    override func setUp() {
        super.setUp()
        savedDemo = LocalPrefs.shared.demoModeEnabled
        savedParticipantID = LocalPrefs.shared.myParticipantID
        LocalPrefs.shared.demoModeEnabled = true

        testDefaults = UserDefaults(suiteName: Self.defaultsSuite)
        testDefaults.removePersistentDomain(forName: Self.defaultsSuite)
        syncState = SnooSyncState(defaults: testDefaults)
        coordinator = SnooSyncCoordinator(state: syncState)

        container = AppModelContainer.make(inMemory: true)
        let ctx = container.mainContext
        ctx.insert(Baby(name: "Miller", dateOfBirth: .now))
        boyTaylor = Participant(displayName: "Boy Taylor", colorHex: "#AABBCC")
        girlTaylor = Participant(displayName: "Girl Taylor", colorHex: "#CCBBAA")
        ctx.insert(boyTaylor)
        ctx.insert(girlTaylor)
        ctx.insert(SharedSettings())
        try? ctx.save()
        store = EventStore(context: ctx)
    }

    override func tearDown() {
        LocalPrefs.shared.demoModeEnabled = savedDemo
        LocalPrefs.shared.myParticipantID = savedParticipantID
        testDefaults.removePersistentDomain(forName: Self.defaultsSuite)
        store = nil
        coordinator = nil
        container = nil
        super.tearDown()
    }

    private func completedSuggestion(id: String = "session-1") -> SnooSuggestion {
        SnooSuggestion(id: id,
                       startedAt: .now.addingTimeInterval(-3600),
                       kind: .completed(endedAt: .now.addingTimeInterval(-600)))
    }

    func testAcceptedCompletedSessionAttributesToLocalParticipant() throws {
        LocalPrefs.shared.myParticipantID = girlTaylor.id

        XCTAssertTrue(coordinator.accept(completedSuggestion(), store: store))

        let sleep = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<SleepEvent>()).first)
        XCTAssertEqual(sleep.loggedByID, girlTaylor.id,
                       "the accepting device's user gets the credit, not whoever connected the SNOO")
        XCTAssertEqual(sleep.loggedByName, "Girl Taylor")
        XCTAssertEqual(sleep.sourceRaw, SleepSource.snoo.rawValue)
        XCTAssertTrue(syncState.importedSessionIDs.contains("session-1"),
                      "a saved accept marks the session imported so it never resurfaces")
    }

    func testAcceptedInProgressSessionAttributesToLocalParticipant() throws {
        LocalPrefs.shared.myParticipantID = boyTaylor.id
        let suggestion = SnooSuggestion(id: "session-2",
                                        startedAt: .now.addingTimeInterval(-1200),
                                        kind: .inProgress)

        XCTAssertTrue(coordinator.accept(suggestion, store: store))

        let sleep = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<SleepEvent>()).first)
        XCTAssertEqual(sleep.loggedByID, boyTaylor.id)
        XCTAssertNil(sleep.endedAt, "in-progress accept starts the live timer")
    }

    func testAttributionFollowsTheDeviceNotTheFirstAccepter() throws {
        // Same household, two phones: each accept lands on its own device's user.
        LocalPrefs.shared.myParticipantID = boyTaylor.id
        XCTAssertTrue(coordinator.accept(completedSuggestion(id: "his"), store: store))

        LocalPrefs.shared.myParticipantID = girlTaylor.id
        XCTAssertTrue(coordinator.accept(completedSuggestion(id: "hers"), store: store))

        let sleeps = try container.mainContext.fetch(FetchDescriptor<SleepEvent>())
        XCTAssertEqual(Set(sleeps.map(\.loggedByID)), [boyTaylor.id, girlTaylor.id])
    }

    func testAcceptRefusedWhenLocalParticipantUnresolvable() {
        // Two active participants and no local identity: guessing would
        // attribute this device's log to the co-parent, so the write refuses
        // (and the suggestion must NOT be marked imported — it can retry).
        LocalPrefs.shared.myParticipantID = nil
        let suggestion = completedSuggestion()

        XCTAssertFalse(coordinator.accept(suggestion, store: store))

        let sleeps = (try? container.mainContext.fetch(FetchDescriptor<SleepEvent>())) ?? []
        XCTAssertTrue(sleeps.isEmpty, "no unattributed ghost event may be persisted")
        XCTAssertFalse(syncState.importedSessionIDs.contains(suggestion.id),
                       "a refused accept must stay eligible to retry")
    }
}
