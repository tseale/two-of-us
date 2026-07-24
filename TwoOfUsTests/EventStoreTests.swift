import XCTest
import SwiftData
@testable import TwoOfUs

/// Store-semantics tests for `EventStore`: the append-only edit model,
/// soft-delete, the single-active-sleep guard, and identity backfill — the
/// invariants the CloudKit layer relies on (edits/deletes travel as updates).
///
/// Runs with demo mode ON, which turns off every side effect inside EventStore
/// (sync enqueues, widget reloads, Live Activities, alarms, Siri donations) so
/// only the SwiftData behavior is under test. The flag is restored in tearDown.
@MainActor
final class EventStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var store: EventStore!
    private var savedDemo = false
    private var savedParticipantID: UUID?

    override func setUp() {
        super.setUp()
        savedDemo = LocalPrefs.shared.demoModeEnabled
        savedParticipantID = LocalPrefs.shared.myParticipantID
        LocalPrefs.shared.demoModeEnabled = true
        LocalPrefs.shared.myParticipantID = nil

        container = AppModelContainer.make(inMemory: true)
        let ctx = container.mainContext
        ctx.insert(Baby(name: "Miller", dateOfBirth: .now))
        ctx.insert(Participant(displayName: "Taylor", colorHex: "#AABBCC"))
        ctx.insert(SharedSettings())
        try? ctx.save()
        store = EventStore(context: ctx)
    }

    override func tearDown() {
        LocalPrefs.shared.demoModeEnabled = savedDemo
        LocalPrefs.shared.myParticipantID = savedParticipantID
        store = nil
        container = nil
        super.tearDown()
    }

    func testUpdateSettingsPersistsFeedSchedule() throws {
        let slots = [FeedSlot(startMinutes: 60, endMinutes: 240, assignedParticipantID: UUID())]
        store.updateSettings(feedSlots: slots)

        let saved = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<SharedSettings>()).first)
        XCTAssertEqual(saved.feedSlots, slots)

        // Reassigning replaces, never accumulates.
        var reassigned = slots
        reassigned[0].assignedParticipantID = nil
        store.updateSettings(feedSlots: reassigned)
        XCTAssertEqual(saved.feedSlots, reassigned)
        XCTAssertEqual(saved.feedSlots.count, 1)
    }

    func testLogFeedStampsLoggerIdentity() {
        let feed = store.logFeed(amountOz: 3)
        XCTAssertEqual(feed.loggedByName, "Taylor")
        XCTAssertEqual(feed.loggedByColorHex, "#AABBCC")
        XCTAssertEqual(feed.baby?.name, "Miller")
    }

    func testEditFeedIsAppendOnly() {
        let original = store.logFeed(amountOz: 2)
        let replacement = store.editFeed(original, amountOz: 4, timestamp: original.timestamp, notes: nil)

        XCTAssertNotNil(original.deletedAt, "the edited original is soft-deleted, not mutated")
        XCTAssertEqual(replacement.editOfID, original.id)
        XCTAssertEqual(replacement.amountOz, 4)
        XCTAssertEqual(replacement.loggedByID, original.loggedByID,
                       "an edit keeps the original logger's identity")

        let live = store.timeline(since: .distantPast)
        XCTAssertEqual(live.count, 1, "the timeline shows only the replacement")
    }

    func testSoftDeleteHidesFromTimelineButKeepsTheRow() throws {
        let feed = store.logFeed(amountOz: 3)
        store.softDelete(feed)

        XCTAssertTrue(store.timeline(since: .distantPast).isEmpty)
        let all = try container.mainContext.fetch(FetchDescriptor<FeedEvent>())
        XCTAssertEqual(all.count, 1, "soft delete keeps the record so it can sync as an update")
    }

    func testOnlyOneActiveSleepAllowed() {
        XCTAssertNotNil(store.startSleep())
        XCTAssertNil(store.startSleep(), "a second running sleep must be refused")
    }

    func testStopSleepEndsTheActiveOne() throws {
        let sleep = try XCTUnwrap(store.startSleep())
        store.stopSleep(sleep)
        XCTAssertNotNil(sleep.endedAt)
        XCTAssertNil(store.activeSleep)
    }

    func testResumeSleepReversesAStop() throws {
        let sleep = try XCTUnwrap(store.startSleep())
        store.stopSleep(sleep)
        store.resumeSleep(sleep)
        XCTAssertNil(sleep.endedAt, "undoing Wake Up makes the sleep active again")
        XCTAssertNotNil(store.activeSleep)
    }

    func testResumeSleepReversesADiscard() throws {
        // The sub-minute wake path cancels (soft-deletes) instead of stopping.
        let sleep = try XCTUnwrap(store.startSleep())
        store.cancelSleep(sleep)
        XCTAssertNil(store.activeSleep)
        store.resumeSleep(sleep)
        XCTAssertNil(sleep.deletedAt)
        XCTAssertNil(sleep.endedAt)
        XCTAssertNotNil(store.activeSleep)
    }

    func testResumeSleepRefusesWhenAnotherIsActive() throws {
        let first = try XCTUnwrap(store.startSleep())
        store.stopSleep(first)
        let second = try XCTUnwrap(store.startSleep())
        store.resumeSleep(first)
        XCTAssertNotNil(first.endedAt, "resume must not create a second active sleep")
        XCTAssertTrue(second.isActive)
    }

    func testClearAllLogsSoftDeletesOnlyLiveEvents() throws {
        let feed = store.logFeed(amountOz: 3)
        store.logDiaper(.wet)
        let alreadyGone = store.logFeed(amountOz: 1)
        store.softDelete(alreadyGone)
        let priorDeletion = alreadyGone.deletedAt

        store.clearAllLogs()

        XCTAssertNotNil(feed.deletedAt)
        XCTAssertEqual(alreadyGone.deletedAt, priorDeletion,
                       "already-deleted events keep their original deletedAt")
        XCTAssertNotNil(store.baby, "clearing logs never touches the baby")
        XCTAssertNotNil(store.owner, "…or the participants")
    }

    func testUpdateMyProfileBackfillsPastEvents() {
        let feed = store.logFeed(amountOz: 3)
        store.updateMyProfile(name: "Tay", colorHex: "#001122")
        XCTAssertEqual(feed.loggedByName, "Tay")
        XCTAssertEqual(feed.loggedByColorHex, "#001122")
    }
}
