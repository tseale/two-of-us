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
    private var savedQueue: [String]?

    private let queueKey = "sync.pendingWidgetWrites"

    override func setUp() {
        super.setUp()
        savedQueue = AppGroup.userDefaults?.array(forKey: queueKey) as? [String]
        AppGroup.userDefaults?.removeObject(forKey: queueKey)

        container = AppModelContainer.make(inMemory: true)
        let ctx = container.mainContext
        ctx.insert(Baby(name: "Miller", dateOfBirth: .now))
        ctx.insert(Participant(displayName: "Taylor", colorHex: "#AABBCC"))
        try? ctx.save()
        logger = QuickLogger(context: ctx)
    }

    override func tearDown() {
        if let savedQueue {
            AppGroup.userDefaults?.set(savedQueue, forKey: queueKey)
        } else {
            AppGroup.userDefaults?.removeObject(forKey: queueKey)
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

    func testToggleSleepStartsThenStops() {
        XCTAssertTrue(logger.toggleSleep(), "no sleep running → starts one")
        XCTAssertNotNil(logger.activeSleep)
        XCTAssertFalse(logger.toggleSleep(), "one running → stops it")
        XCTAssertNil(logger.activeSleep)
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

    // MARK: Extension → app sync hand-off

    func testWritesQueueForTheAppToSync() throws {
        guard let defaults = AppGroup.userDefaults else {
            throw XCTSkip("App Group suite unavailable in this test host")
        }
        let feed = logger.logFeed(amountOz: 3)
        let queued = defaults.array(forKey: queueKey) as? [String]
        XCTAssertEqual(queued, [feed.id.uuidString],
                       "the widget process can't reach CKSyncEngine; ids must queue for the app")
    }
}
