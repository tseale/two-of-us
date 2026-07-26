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

    // MARK: Tracker switches

    func testDisabledTrackersRefuseNewEventsButKeepHistory() throws {
        let feed = try XCTUnwrap(store.logFeed(amountOz: 3))

        store.updateSettings(feedLoggingEnabled: false, sleepLoggingEnabled: false)

        XCTAssertNil(store.logFeed(amountOz: 3), "feed tracker off must refuse a new feed")
        XCTAssertNil(store.startSleep(), "sleep tracker off must refuse a new sleep")
        XCTAssertNotNil(store.logDiaper(.wet), "the still-on tracker keeps logging")
        XCTAssertNil(feed.deletedAt, "pausing a tracker must not touch existing events")
    }

    func testStopSleepStillWorksAfterSleepTrackerTurnsOff() throws {
        let sleep = try XCTUnwrap(store.startSleep())
        store.updateSettings(sleepLoggingEnabled: false)

        store.stopSleep(sleep)
        XCTAssertNotNil(sleep.endedAt, "a running sleep must stay stoppable after the tracker pauses")
    }

    func testUpdateSettingsNeverLeavesEveryTrackerOff() throws {
        store.updateSettings(feedLoggingEnabled: false, diaperLoggingEnabled: false,
                             sleepLoggingEnabled: false)

        let settings = try XCTUnwrap(store.settings)
        XCTAssertGreaterThan(settings.enabledTrackerCount, 0,
                             "the store must backstop the UI's last-tracker rule")
    }

    func testPurgeGhostEventsRemovesOnlyUnknownLoggers() throws {
        // Real entries by the household participant…
        let mine = try XCTUnwrap(store.logFeed(amountOz: 3))
        let myDiaper = try XCTUnwrap(store.logDiaper(.wet))

        // …and ghost entries stamped with logger ids no Participant matches —
        // the shape of leaked SeedData sample events.
        let ctx = container.mainContext
        let baby = try XCTUnwrap(ctx.fetch(FetchDescriptor<Baby>()).first)
        ctx.insert(FeedEvent(baby: baby, amountOz: 3, timestamp: .now,
                             loggedByID: UUID(), loggedByName: "Mom", loggedByColorHex: ""))
        ctx.insert(SleepEvent(baby: baby, startedAt: .now.addingTimeInterval(-3600),
                              endedAt: .now,
                              loggedByID: UUID(), loggedByName: "Dad", loggedByColorHex: ""))
        ctx.insert(DiaperEvent(baby: baby, type: .wet, timestamp: .now,
                               loggedByID: UUID(), loggedByName: "Dad", loggedByColorHex: ""))
        try ctx.save()

        XCTAssertEqual(store.ghostEvents().count, 3)
        XCTAssertEqual(store.purgeGhostEvents(), 3)

        XCTAssertNil(mine.deletedAt, "the household's own entries are untouched")
        XCTAssertNil(myDiaper.deletedAt)
        XCTAssertTrue(store.ghostEvents().isEmpty, "purge is complete")
        XCTAssertEqual(store.purgeGhostEvents(), 0, "second run finds nothing")
    }

    func testRevokedParticipantsEventsAreNotGhosts() throws {
        // A removed caregiver keeps their Participant record (isActive false) —
        // their history must never be treated as ghost data.
        let ctx = container.mainContext
        let nanny = Participant(displayName: "Nanny", colorHex: "#123456",
                                role: .logger, isActive: false)
        ctx.insert(nanny)
        let baby = try XCTUnwrap(ctx.fetch(FetchDescriptor<Baby>()).first)
        ctx.insert(FeedEvent(baby: baby, amountOz: 2, timestamp: .now,
                             loggedByID: nanny.id, loggedByName: "Nanny", loggedByColorHex: "#123456"))
        try ctx.save()

        XCTAssertTrue(store.ghostEvents().isEmpty)
        XCTAssertEqual(store.purgeGhostEvents(), 0)
    }

    func testLogFeedStampsLoggerIdentity() throws {
        let feed = try XCTUnwrap(store.logFeed(amountOz: 3))
        XCTAssertEqual(feed.loggedByName, "Taylor")
        XCTAssertEqual(feed.loggedByColorHex, "#AABBCC")
        XCTAssertEqual(feed.baby?.name, "Miller")
    }

    func testEditFeedIsAppendOnly() throws {
        let original = try XCTUnwrap(store.logFeed(amountOz: 2))
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
        let feed = try XCTUnwrap(store.logFeed(amountOz: 3))
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
        let feed = try XCTUnwrap(store.logFeed(amountOz: 3))
        store.logDiaper(.wet)
        let alreadyGone = try XCTUnwrap(store.logFeed(amountOz: 1))
        store.softDelete(alreadyGone)
        let priorDeletion = alreadyGone.deletedAt

        store.clearAllLogs()

        XCTAssertNotNil(feed.deletedAt)
        XCTAssertEqual(alreadyGone.deletedAt, priorDeletion,
                       "already-deleted events keep their original deletedAt")
        XCTAssertNotNil(store.baby, "clearing logs never touches the baby")
        XCTAssertNotNil(store.owner, "…or the participants")
    }

    func testUpdateMyProfileBackfillsPastEvents() throws {
        let feed = try XCTUnwrap(store.logFeed(amountOz: 3))
        store.updateMyProfile(name: "Tay", colorHex: "#001122")
        XCTAssertEqual(feed.loggedByName, "Tay")
        XCTAssertEqual(feed.loggedByColorHex, "#001122")
    }

    // MARK: Ghost-event regressions

    func testWritesAreRefusedWithoutAnyParticipant() throws {
        // A store with no participants (mid-wipe, mid-join re-fetch) must refuse
        // to log rather than mint an unattributed "?" ghost event.
        let empty = AppModelContainer.make(inMemory: true)
        empty.mainContext.insert(Baby(name: "Miller", dateOfBirth: .now))
        try empty.mainContext.save()
        let orphanStore = EventStore(context: empty.mainContext)

        XCTAssertNil(orphanStore.logFeed(amountOz: 3))
        XCTAssertNil(orphanStore.logDiaper(.wet))
        XCTAssertNil(orphanStore.startSleep())
        XCTAssertTrue(try empty.mainContext.fetch(FetchDescriptor<FeedEvent>()).isEmpty)
        XCTAssertTrue(try empty.mainContext.fetch(FetchDescriptor<DiaperEvent>()).isEmpty)
        XCTAssertTrue(try empty.mainContext.fetch(FetchDescriptor<SleepEvent>()).isEmpty)
    }

    func testZeroOunceFeedIsRefused() throws {
        XCTAssertNil(store.logFeed(amountOz: 0), "a 0 oz bottle is never a real feed")
        XCTAssertNil(store.logFeed(amountOz: -2))
        XCTAssertNil(store.logFeed(amountOz: .nan))
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<FeedEvent>()).isEmpty)
    }

    func testAutoPurgeSweepsGhostSignatureEvents() throws {
        let mine = try XCTUnwrap(store.logFeed(amountOz: 3))
        let ctx = container.mainContext
        let baby = try XCTUnwrap(ctx.fetch(FetchDescriptor<Baby>()).first)
        // The exact ghost shape: empty logger name + a logger id no Participant
        // matches (what the old `owner?.id ?? UUID()` fallback and the inbound
        // placeholder inserts produced).
        ctx.insert(FeedEvent(baby: baby, amountOz: 0, timestamp: .now,
                             loggedByID: UUID(), loggedByName: "", loggedByColorHex: ""))
        ctx.insert(DiaperEvent(baby: baby, type: .wet, timestamp: .now,
                               loggedByID: UUID(), loggedByName: "", loggedByColorHex: ""))
        // A named event from an unknown logger (e.g. a caregiver whose record
        // hasn't synced in yet) must NOT be auto-swept.
        ctx.insert(FeedEvent(baby: baby, amountOz: 4, timestamp: .now,
                             loggedByID: UUID(), loggedByName: "Katie", loggedByColorHex: "#112233"))
        try ctx.save()

        XCTAssertEqual(store.autoPurgeGhostEvents(), 2)
        XCTAssertNil(mine.deletedAt)
        XCTAssertEqual(store.timeline(since: .distantPast).count, 2,
                       "my feed and the named unknown-logger feed survive")
        XCTAssertEqual(store.autoPurgeGhostEvents(), 0, "second run finds nothing")
    }

    func testAutoPurgeCollapsesDuplicateRowsSharingAnID() throws {
        let ctx = container.mainContext
        let baby = try XCTUnwrap(ctx.fetch(FetchDescriptor<Baby>()).first)
        let sharedID = UUID()
        let me = try XCTUnwrap(store.owner)
        // The real row and a placeholder duplicate minted under the same id (the
        // swallowed-store-error upsert bug).
        ctx.insert(FeedEvent(id: sharedID, baby: baby, amountOz: 3, timestamp: .now,
                             loggedByID: me.id, loggedByName: me.displayName,
                             loggedByColorHex: me.colorHex))
        ctx.insert(FeedEvent(id: sharedID, baby: baby, amountOz: 0, timestamp: .now,
                             loggedByID: UUID(), loggedByName: "", loggedByColorHex: ""))
        try ctx.save()

        XCTAssertEqual(store.autoPurgeGhostEvents(), 1)
        let remaining = try ctx.fetch(FetchDescriptor<FeedEvent>())
        XCTAssertEqual(remaining.count, 1, "duplicates collapse to one row")
        XCTAssertEqual(remaining.first?.amountOz, 3, "the attributed row wins")
        XCTAssertNil(remaining.first?.deletedAt,
                     "the surviving real row is not soft-deleted — a synced delete would kill the co-parent's copy")
    }
}
