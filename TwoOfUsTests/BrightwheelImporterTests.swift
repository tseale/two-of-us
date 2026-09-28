import XCTest
import SwiftData
@testable import TwoOfUs

/// The Brightwheel import pipeline against the mock day — which is raw JSON
/// in the live API's wire format, decoded by the same path a network
/// response takes. These tests are the contract the real integration
/// inherits on Miller's first day. Demo mode ON silences EventStore side
/// effects, same as `EventStoreTests`.
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

    private func decode(_ json: String) throws -> [BrightwheelActivity] {
        try JSONDecoder().decode(BrightwheelActivityPage.self, from: Data(json.utf8)).activities
    }

    // MARK: Mock day import (11 wire activities -> 9 events; naps are pairs)

    func testMockDayImportsTheFullReport() throws {
        let summary = BrightwheelImporter(context: context).importActivities(mockDay)

        XCTAssertEqual(summary.feeds, 3)
        XCTAssertEqual(summary.sleeps, 2, "four nap half-activities pair into two sleeps")
        XCTAssertEqual(summary.diapers, 2)
        XCTAssertEqual(summary.notes, 2, "drop-off and pick-up import as notes")
        XCTAssertEqual(summary.skippedDuplicates, 0)
        XCTAssertEqual(summary.skippedUnmapped, 0)

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
        XCTAssertTrue(sleeps.allSatisfy { $0.externalID?.hasSuffix("-end") == true },
                      "a paired sleep is keyed on its woke-up activity")

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

    // MARK: Nap pairing edges

    func testInProgressNapWaitsForItsWakeUp() throws {
        let start = ISO8601DateFormatter().string(
            from: Calendar.current.date(byAdding: .hour, value: -2, to: .now)!)
        let json = """
        { "activities": [
            { "object_id": "n-start", "action_type": "ac_nap",
              "event_date": "\(start)", "state": "1" }
        ] }
        """
        let summary = BrightwheelImporter(context: context)
            .importActivities(try decode(json))

        XCTAssertEqual(summary.sleeps, 0, "no wake-up yet — nothing to log")
        XCTAssertEqual(summary.skippedUnmapped, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SleepEvent>()), 0)
    }

    func testOrphanWakeUpIsSkippedNotFabricated() throws {
        let json = """
        { "activities": [
            { "object_id": "n-end", "action_type": "ac_nap",
              "event_date": "2026-09-27T14:15:00.000Z", "state": "0" }
        ] }
        """
        let summary = BrightwheelImporter(context: context)
            .importActivities(try decode(json))

        XCTAssertEqual(summary.sleeps, 0,
                       "a wake-up whose start predates the fetch window can't invent a span")
        XCTAssertEqual(summary.skippedUnmapped, 1)
    }

    func testNapStateInsideDetailsBlobStillPairs() throws {
        let json = """
        { "activities": [
            { "object_id": "n-end", "action_type": "ac_nap",
              "event_date": "2026-09-27T14:15:00.000Z", "details_blob": { "state": "0" } },
            { "object_id": "n-start", "action_type": "ac_nap",
              "event_date": "2026-09-27T12:45:00.000Z", "details_blob": { "state": 1 } }
        ] }
        """
        let summary = BrightwheelImporter(context: context)
            .importActivities(try decode(json))

        XCTAssertEqual(summary.sleeps, 1,
                       "state travels top-level or in the blob, string or number — all pair")
    }

    // MARK: Food edges

    func testSolidFoodImportsAsNoteNotFeed() throws {
        let json = """
        { "activities": [
            { "object_id": "f-solid", "action_type": "ac_food",
              "event_date": "2026-09-27T12:00:00.000Z",
              "details_blob": { "amount": "most", "kind": "lunch" },
              "menu_item_tags": [ { "name": "Cheese" }, { "name": "Crackers" } ] }
        ] }
        """
        let summary = BrightwheelImporter(context: context)
            .importActivities(try decode(json))

        XCTAssertEqual(summary.feeds, 0, "never fabricate an oz amount from 'most'")
        XCTAssertEqual(summary.notes, 1)
        let note = try XCTUnwrap(context.fetch(FetchDescriptor<NoteEvent>()).first)
        XCTAssertTrue(note.text.contains("Cheese"))
        XCTAssertTrue(note.isFromDaycare)
    }

    func testMlBottleConvertsToOz() throws {
        let json = """
        { "activities": [
            { "object_id": "f-ml", "action_type": "ac_food",
              "event_date": "2026-09-27T12:00:00.000Z",
              "details_blob": { "food_type": "bottle", "amount": 120, "amount_type": "ml" } }
        ] }
        """
        let summary = BrightwheelImporter(context: context)
            .importActivities(try decode(json))

        XCTAssertEqual(summary.feeds, 1)
        let feed = try XCTUnwrap(context.fetch(FetchDescriptor<FeedEvent>()).first)
        XCTAssertEqual(feed.amountOz, 4, accuracy: 0.1, "120 ml is a 4 oz bottle")
    }

    // MARK: Diaper edges

    func testDryDiaperCheckImportsAsNote() throws {
        let json = """
        { "activities": [
            { "object_id": "d-dry", "action_type": "ac_potty",
              "event_date": "2026-09-27T10:45:00.000Z",
              "details_blob": { "potty_type": "dry", "potty_extras": [] } }
        ] }
        """
        let summary = BrightwheelImporter(context: context)
            .importActivities(try decode(json))

        XCTAssertEqual(summary.diapers, 0, "a dry check is an observation, not a change")
        XCTAssertEqual(summary.notes, 1)
    }

    // MARK: Wire-format decoding (per the sources in the research doc §3)

    func testDecodesRealWireShapes() throws {
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
              "details_blob": { "food_type": "bottle", "amount": "4.5", "amount_type": "oz" },
              "menu_item_tags": [ { "name": "Bottle" } ],
              "actor": { "object_id": "st-1", "first_name": "Amanda", "last_name": "R" },
              "target": { "object_id": "stu-1" },
              "room": { "name": "Infant Room" }
            },
            {
              "object_id": "def456",
              "action_type": "ac_potty",
              "event_date": "2026-09-28T15:10:00Z",
              "details_blob": { "potty_type": "wet", "potty_extras": ["diaper_cream"] }
            }
          ],
          "count": 2, "offset": 0, "page": 0, "page_size": 100
        }
        """
        let page = try JSONDecoder().decode(BrightwheelActivityPage.self, from: Data(json.utf8))

        XCTAssertEqual(page.activities.count, 2)
        let feed = page.activities[0]
        XCTAssertTrue(feed.isBottle)
        XCTAssertEqual(feed.bottleOz, 4.5, "string-encoded amounts must parse")
        XCTAssertNotNil(feed.when)
        let potty = page.activities[1]
        XCTAssertNotNil(potty.when, "timestamps without fractional seconds must parse")
        XCTAssertEqual(potty.detailsBlob?.pottyType, "wet")
    }

    func testMockResponseIsValidWireJSON() throws {
        let data = BrightwheelMockDay.responseData()
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(object["activities"])
        XCTAssertEqual(object["page_size"] as? Int, 100)
        XCTAssertEqual((object["activities"] as? [[String: Any]])?.count, 11)
    }
}
