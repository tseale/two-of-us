import XCTest
import SwiftData
@testable import TwoOfUs

/// `QuickLogger` is the write path for widget buttons and Siri — it must mirror
/// `EventStore`'s semantics (append-only, soft delete) without the app running.
/// Constructed directly against an in-memory store; the App Group queue it
/// feeds is snapshotted and restored around every test.
@MainActor
final class QuickLoggerTests: XCTestCase {
    private var container: ModelContainer!
    private var logger: QuickLogger!
    private var savedQueue: [String: Any?] = [:]

    /// Per-write queue keys (see QuickLogger.commit — one key per write so the
    /// extension can never race the app's drain).
    private let queuePrefix = "sync.widgetWrite."

    /// Every currently-queued widget-write value in the app-group suite.
    private func queuedIDs() -> [String] {
        guard let d = AppGroup.userDefaults else { return [] }
        return d.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(queuePrefix) }
            .compactMap { d.string(forKey: $0) }
    }

    override func setUp() {
        super.setUp()
        if let d = AppGroup.userDefaults {
            let keys = d.dictionaryRepresentation().keys.filter { $0.hasPrefix(queuePrefix) }
            savedQueue = Dictionary(uniqueKeysWithValues: keys.map { ($0, d.object(forKey: $0)) })
            keys.forEach { d.removeObject(forKey: $0) }
        }

        container = AppModelContainer.make(inMemory: true)
        let ctx = container.mainContext
        ctx.insert(Baby(name: "Miller", dateOfBirth: .now))
        ctx.insert(Participant(displayName: "Taylor", colorHex: "#AABBCC"))
        try? ctx.save()
        logger = QuickLogger(context: ctx)
    }

    override func tearDown() {
        if let d = AppGroup.userDefaults {
            // Drop what tests queued, restore what the device had queued.
            for key in d.dictionaryRepresentation().keys where key.hasPrefix(queuePrefix) {
                d.removeObject(forKey: key)
            }
            for (key, value) in savedQueue {
                if let value { d.set(value, forKey: key) }
            }
        }
        logger = nil
        container = nil
        super.tearDown()
    }

    private func insertFeed(_ oz: Double, at: Date) -> FeedEvent {
        let f = FeedEvent(baby: nil, amountOz: oz, timestamp: at, loggedByID: UUID(),
                          loggedByName: "Taylor", loggedByColorHex: "#AABBCC")
        container.mainContext.insert(f)
        try? container.mainContext.save()
        return f
    }

    private func insertDiaper(at: Date) -> DiaperEvent {
        let d = DiaperEvent(baby: nil, type: .wet, timestamp: at, loggedByID: UUID(),
                            loggedByName: "Taylor", loggedByColorHex: "#AABBCC")
        container.mainContext.insert(d)
        try? container.mainContext.save()
        return d
    }

    // MARK: Tracker switches

    private func insertSettings(feed: Bool = true, diaper: Bool = true, sleep: Bool = true) {
        container.mainContext.insert(SharedSettings(
            feedLoggingEnabled: feed, diaperLoggingEnabled: diaper, sleepLoggingEnabled: sleep))
        try? container.mainContext.save()
    }

    func testDisabledTrackersRefuseWidgetAndSiriWrites() {
        insertSettings(feed: false, diaper: false)
        XCTAssertFalse(logger.isTrackingEnabled(.feed))
        XCTAssertNil(logger.logFeed(amountOz: 3), "feed tracker off must refuse the widget/Siri write")
        XCTAssertNil(logger.logDiaper(.wet), "diaper tracker off must refuse the widget/Siri write")
        XCTAssertEqual(logger.toggleSleep(), true, "the still-on sleep tracker keeps logging")
    }

    func testSleepTrackerOffRefusesStartButAllowsStop() throws {
        _ = try XCTUnwrap(logger.toggleSleep())      // start while tracking is on
        insertSettings(sleep: false)

        XCTAssertEqual(logger.toggleSleep(), false,
                       "stopping the running sleep must survive the tracker pausing")
        XCTAssertNil(logger.toggleSleep(), "a new start is refused while the tracker is off")
    }

    func testMissingSettingsRecordMeansEverythingTracks() {
        // Pre-onboarding / pre-sync stores have no SharedSettings row yet.
        XCTAssertTrue(logger.isTrackingEnabled(.feed))
        XCTAssertTrue(logger.isTrackingEnabled(.sleep))
        XCTAssertTrue(logger.isTrackingEnabled(.diaper))
    }

    // MARK: Undo

    func testUndoRemovesTheMostRecentEventAcrossKinds() throws {
        let feed = insertFeed(3, at: Date(timeIntervalSinceNow: -600))
        let diaper = insertDiaper(at: Date(timeIntervalSinceNow: -60))

        let first = try XCTUnwrap(logger.undoLastLog())
        XCTAssertTrue(first.contains("diaper"), "the newer event goes first — got: \(first)")
        XCTAssertNotNil(diaper.deletedAt)
        XCTAssertNil(feed.deletedAt)

        let second = try XCTUnwrap(logger.undoLastLog())
        XCTAssertTrue(second.contains("feed"))
        XCTAssertNotNil(feed.deletedAt)

        XCTAssertNil(logger.undoLastLog(), "nothing live left to undo")
    }

    func testUndoIsASoftDeleteNotARemoval() throws {
        _ = insertFeed(3, at: .now)
        _ = try XCTUnwrap(logger.undoLastLog())
        let all = try container.mainContext.fetch(FetchDescriptor<FeedEvent>())
        XCTAssertEqual(all.count, 1, "undo soft-deletes so the change can still sync")
    }

    // MARK: Sleep toggle

    func testToggleSleepStartsThenStops() throws {
        XCTAssertEqual(logger.toggleSleep(), true, "no sleep running → starts one")
        XCTAssertNotNil(logger.activeSleep)
        XCTAssertEqual(logger.toggleSleep(), false, "one running → stops it")
        XCTAssertNil(logger.activeSleep)
    }

    // MARK: Paused access

    func testPausedDeviceIsRefusedOnEveryWritePathIncludingUndoAndSleepStop() throws {
        // Undo and sleep-stop deliberately skip `owner`, so they need their
        // own pause gate — without it a paused person could still delete the
        // co-parent's latest event or end their running sleep timer.
        _ = insertFeed(3, at: Date(timeIntervalSinceNow: -600))
        XCTAssertEqual(logger.toggleSleep(), true, "sleep starts while unpaused")

        let me = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<Participant>()).first)
        me.pausedAt = .now
        try container.mainContext.save()

        XCTAssertNil(logger.logFeed(amountOz: 3), "logging is refused while paused")
        XCTAssertNil(logger.toggleSleep(), "the running sleep may not be stopped while paused")
        XCTAssertNotNil(logger.activeSleep, "the co-parent's timer keeps running")
        XCTAssertNil(logger.undoLastLog(), "undo is refused while paused")

        me.pausedAt = nil
        try container.mainContext.save()
        XCTAssertEqual(logger.toggleSleep(), false, "resume restores the stop path")
    }

    // MARK: One-tap feed amount

    func testDefaultFeedOzPrefersSharedSettings() {
        container.mainContext.insert(SharedSettings(defaultFeedOz: 5))
        try? container.mainContext.save()
        _ = insertFeed(2.5, at: .now)
        XCTAssertEqual(logger.defaultFeedOz, 5)
    }

    func testDefaultFeedOzFallsBackToMostRecentFeed() {
        _ = insertFeed(2.5, at: .now)
        _ = insertFeed(3.5, at: Date(timeIntervalSinceNow: -3600))
        XCTAssertEqual(logger.defaultFeedOz, 2.5)
    }

    func testDefaultFeedOzFinalFallbackIsFourOz() {
        XCTAssertEqual(logger.defaultFeedOz, 4)
    }

    // MARK: Ghost-event regressions

    func testWritesAreRefusedWithoutAnyParticipant() throws {
        // Mid-wipe / mid-join the shared store can have no participants. The
        // old fallback stamped a random logger UUID with an empty name — the
        // "?" ghost rows. Now the write is refused outright.
        let empty = AppModelContainer.make(inMemory: true)
        empty.mainContext.insert(Baby(name: "Miller", dateOfBirth: .now))
        try empty.mainContext.save()
        let orphan = QuickLogger(context: ModelContext(empty))

        XCTAssertNil(orphan.logFeed(amountOz: 3))
        XCTAssertNil(orphan.logDiaper(.wet))
        XCTAssertNil(orphan.toggleSleep(), "starting a sleep needs an owner")
        XCTAssertTrue(try empty.mainContext.fetch(FetchDescriptor<FeedEvent>()).isEmpty)
        XCTAssertTrue(try empty.mainContext.fetch(FetchDescriptor<DiaperEvent>()).isEmpty)
        XCTAssertTrue(try empty.mainContext.fetch(FetchDescriptor<SleepEvent>()).isEmpty)
    }

    func testFallbackOwnerSkipsMergedAwayTombstone() throws {
        // A fresh container the stored App Group identity can't match, holding
        // a merged-away duplicate (isActive false, older invitedAt) plus the
        // real active row: the fallback must attribute to the active one, never
        // the tombstone (participant auto-merge leaves those behind).
        let fresh = AppModelContainer.make(inMemory: true)
        let ctx = fresh.mainContext
        ctx.insert(Baby(name: "Miller", dateOfBirth: .now))
        ctx.insert(Participant(displayName: "Old Taylor", colorHex: "#000000",
                               isActive: false,
                               invitedAt: .now.addingTimeInterval(-86400)))
        let active = Participant(displayName: "Taylor", colorHex: "#AABBCC")
        ctx.insert(active)
        try ctx.save()

        let feed = try XCTUnwrap(QuickLogger(context: ModelContext(fresh)).logFeed(amountOz: 3))
        XCTAssertEqual(feed.loggedByID, active.id,
                       "fallback owner must be the active participant, not a tombstone")
        XCTAssertEqual(feed.loggedByName, "Taylor")
    }

    func testStoppingASleepNeedsNoOwner() throws {
        // Stopping only completes an existing event — it must keep working even
        // if the participant lookup breaks mid-session.
        XCTAssertEqual(logger.toggleSleep(), true)
        // Remove all participants, then stop.
        let ctx = container.mainContext
        for p in try ctx.fetch(FetchDescriptor<Participant>()) { ctx.delete(p) }
        try ctx.save()
        XCTAssertEqual(logger.toggleSleep(), false, "stop still works without an owner")
        XCTAssertNil(logger.activeSleep)
    }

    func testRapidDuplicateTapsAreAbsorbed() throws {
        // Widget/Control Center buttons and notification actions have no dialog
        // — a mashed button or a retried intent delivers the same write twice.
        // Inside the idempotency window the second write returns the first row.
        let first = try XCTUnwrap(logger.logFeed(amountOz: 3))
        let second = try XCTUnwrap(logger.logFeed(amountOz: 3))
        XCTAssertEqual(first.id, second.id, "an identical re-tap must not mint a second feed")
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<FeedEvent>()).count, 1)

        let firstDiaper = try XCTUnwrap(logger.logDiaper(.wet))
        let secondDiaper = try XCTUnwrap(logger.logDiaper(.wet))
        XCTAssertEqual(firstDiaper.id, secondDiaper.id)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<DiaperEvent>()).count, 1)
    }

    func testDifferentAmountsAreNotDeduplicated() throws {
        // Only IDENTICAL writes inside the window are treated as re-taps — a
        // deliberate second bottle with a different amount logs normally.
        let first = try XCTUnwrap(logger.logFeed(amountOz: 3))
        let second = try XCTUnwrap(logger.logFeed(amountOz: 4))
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<FeedEvent>()).count, 2)
    }

    func testOwnerFallbackRefusesWhenTwoParentsAreActive() throws {
        // A fresh container the stored identity can't match, holding TWO active
        // participants: guessing would attribute the log to the co-parent on
        // both phones — the write must refuse instead.
        let fresh = AppModelContainer.make(inMemory: true)
        let ctx = fresh.mainContext
        ctx.insert(Baby(name: "Miller", dateOfBirth: .now))
        ctx.insert(Participant(displayName: "Taylor", colorHex: "#AABBCC"))
        ctx.insert(Participant(displayName: "Katie", colorHex: "#334455"))
        try ctx.save()

        XCTAssertNil(QuickLogger(context: ModelContext(fresh)).logFeed(amountOz: 3))
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<FeedEvent>()).isEmpty)
    }

    func testZeroOunceFeedIsRefused() throws {
        XCTAssertNil(logger.logFeed(amountOz: 0), "a 0 oz bottle is never a real feed")
        XCTAssertNil(logger.logFeed(amountOz: -1))
        XCTAssertNil(logger.logFeed(amountOz: .infinity))
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<FeedEvent>()).isEmpty)
    }

    // MARK: Extension → app sync hand-off

    func testWritesQueueForTheAppToSync() throws {
        guard AppGroup.userDefaults != nil else {
            throw XCTSkip("App Group suite unavailable in this test host")
        }
        let feed = try XCTUnwrap(logger.logFeed(amountOz: 3))
        XCTAssertEqual(queuedIDs(), [feed.id.uuidString],
                       "the widget process can't reach CKSyncEngine; ids must queue for the app")
    }

    func testEachWriteQueuesUnderItsOwnKey() throws {
        guard AppGroup.userDefaults != nil else {
            throw XCTSkip("App Group suite unavailable in this test host")
        }
        let feed = try XCTUnwrap(logger.logFeed(amountOz: 3))
        let diaper = try XCTUnwrap(logger.logDiaper(.wet))
        XCTAssertEqual(Set(queuedIDs()), [feed.id.uuidString, diaper.id.uuidString],
                       "one key per write — a shared array could drop an append that races the app's drain")
    }
}
