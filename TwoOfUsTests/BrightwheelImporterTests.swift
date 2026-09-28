import XCTest
import SwiftData
@testable import TwoOfUs

/// The Brightwheel import pipeline against the mock day — the same DTOs and
/// importer the live API will feed, so these tests are the contract the real
/// integration inherits. Demo mode ON silences EventStore side effects, same
/// as `EventStoreTests`.
@MainActor
final class BrightwheelImporterTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var savedDemo = false
    private var savedParticipantID: UUID?

    override func setUp() {
        super.setUp()
        savedDemo = LocalPrefs.shared.demoModeEnabled
        savedParticipantID = LocalPrefs.shared.myParticipantID
        LocalPrefs.shared.demoModeEnabled = true
        LocalPrefs.shared.myParticipantID = nil

        container = AppModelContainer.make(inMemory: true)
        context.insert(Baby(name: "Miller", dateOfBirth: .now))
        context.insert(Participant(displayName: "Taylor", colorHex: "#AABBCC"))
        context.insert(SharedSettings())
        try? context.save()
    }

    override func tearDown() {
        LocalPrefs.shared.demoModeEnabled = savedDemo
        LocalPrefs.shared.myParticipantID = savedParticipantID
        container = nil
        super.tearDown()
    }

    /// Yesterday's schedule: every mock time is safely in the past, so
    /// `EventBounds.clampPast` can't move anything no matter when CI runs.
    private var mockDay: [BrightwheelActivity] {
        let yesterday = Calendar.current.date(
            byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: .now))!
        return BrightwheelMockDay.activities(for: yesterday)
    }

    // MARK: Mock day import

    func testMockDayImportsTheFullReport() throws {
        let summary = BrightwheelImporter(context: context)
            .importActivities(mockDay)

        XCTAssertEqual(summary.feeds, 3)
        XCTAssertEqual(summary.sleeps, 2)
        XCTAssertEqual(summary.diapers, 2)
        XCTAssertEqual(summary.notes, 2, "drop-off and pick-up import as notes")
        XCTAssertEqual(summary.skippedDuplicates, 0)

        let feeds = try context.fetch(FetchDescriptor<FeedEvent>())
        XCTAssertEqual(feeds.reduce(0) { $0 + $1.amountOz }, 13,
                       "4 + 5 + 4 oz — the day's total the report card shows")
        XCTAssertTrue(feeds.allSatisfy(\.isFromDaycare))
        XCTAssertTrue(feeds.allSatisfy { $0.externalID?.hasPrefix(BrightwheelMockDay.idPrefix) == true })

        let sleeps = try context.fetch(FetchDescriptor<SleepEvent>())
        let napSeconds = sleeps.reduce(0.0) {
            $0 + ($1.endedAt ?? $1.startedAt).timeIntervalSince($1.startedAt)
        }
        XCTAssertEqual(napSeconds, (45 + 90) * 60, "45 min + 1 h 30 min naps")
        XCTAssertTrue(sleeps.allSatisfy { !$0.isActive }, "imported naps never run the timer")

        let diapers = try context.fetch(FetchDescriptor<DiaperEvent>())
        XCTAssertEqual(Set(diapers.map(\.type)), [.wet, .dirty])
    }

    func testReimportIsIdempotent() throws {
        let importer = BrightwheelImporter(context: context)
        importer.importActivities(mockDay)
        let second = importer.importActivities(mockDay)

        XCTAssertEqual(second.imported, 0, "deterministic ids make re-import a no-op")
        XCTAssertEqual(second.skippedDuplicates, 9)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FeedEvent>()), 3)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SleepEvent>()), 2)
    }

    func testDeletedImportDoesNotResurrect() throws {
        let importer = BrightwheelImporter(context: context)
        importer.importActivities(mockDay)

        let store = EventStore(context: context)
        for feed in try context.fetch(FetchDescriptor<FeedEvent>()) {
            store.softDelete(feed)
        }
        let again = importer.importActivities(mockDay)

        XCTAssertEqual(again.feeds, 0,
                       "a daycare entry the parents deleted must stay deleted on re-sync")
        let live = try context.fetch(FetchDescriptor<FeedEvent>())
            .filter { $0.deletedAt == nil }
        XCTAssertTrue(live.isEmpty)
    }

    func testSampleDayRemovalSweepsOnlyMockEvents() throws {
        BrightwheelImporter(context: context).importActivities(mockDay)
        // A real hand-logged feed must survive the sweep.
        let store = EventStore(context: context)
        let kept = try XCTUnwrap(store.logFeed(amountOz: 3, at: .now))

        let removed = BrightwheelManager().removeSampleDay(context: context)

        XCTAssertEqual(removed, 9)
        let liveFeeds = try context.fetch(FetchDescriptor<FeedEvent>())
            .filter { $0.deletedAt == nil }
        XCTAssertEqual(liveFeeds.map(\.id), [kept.id])
    }

    // MARK: Feed amount fallback

    func testFeedWithoutParseableAmountImportsAsNote() throws {
        let activity = BrightwheelActivity(
            objectID: "bw-f-noamount", actionType: "ac_food",
            eventDate: ISO8601DateFormatter().string(from: .now),
            note: "Bottle refused",
            detailsBlob: nil
        )
        let summary = BrightwheelImporter(context: context).importActivities([activity])

        XCTAssertEqual(summary.feeds, 0, "never fabricate a 0 oz bottle")
        XCTAssertEqual(summary.notes, 1)
        let note = try XCTUnwrap(context.fetch(FetchDescriptor<NoteEvent>()).first)
        XCTAssertTrue(note.text.contains("Bottle"))
        XCTAssertTrue(note.isFromDaycare)
    }

    // MARK: DTO decoding (the shape the research doc records)

    func testDecodesActivitiesPayload() throws {
        let json = """
        {
          "activities": [
            {
              "object_id": "abc123",
              "action_type": "ac_food",
              "event_date": "2026-09-28T14:00:00.000Z",
              "created_at": "2026-09-28T14:01:30.000Z",
              "note": "Took the whole bottle",
              "staff_only": false,
              "details_blob": { "tags": [], "amount": "4.5" },
              "actor": { "first_name": "Ms.", "last_name": "Rivera" },
              "room": { "name": "Infant Room" }
            },
            {
              "object_id": "def456",
              "action_type": "ac_potty",
              "event_date": "2026-09-28T15:10:00Z",
              "details_blob": { "tags": ["Wet", "BM"] }
            }
          ],
          "count": 2, "offset": 0, "page": 0, "page_size": 100
        }
        """
        let page = try JSONDecoder().decode(BrightwheelActivityPage.self, from: Data(json.utf8))

        XCTAssertEqual(page.activities.count, 2)
        let feed = page.activities[0]
        XCTAssertEqual(feed.detailsBlob?.amount, 4.5, "string-encoded amounts must parse")
        XCTAssertNotNil(feed.when)
        let potty = page.activities[1]
        XCTAssertNotNil(potty.when, "timestamps without fractional seconds must parse")
        XCTAssertEqual(potty.detailsBlob?.tags, ["Wet", "BM"])
    }
}
