import SwiftData
import UIKit
import XCTest
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

    private func activity(id: String, action: String, minutesAgo: Int,
                          state: String? = nil, withPhoto: Bool = false,
                          details: [String: Any]? = nil) throws -> BrightwheelActivity {
        let when = ISO8601DateFormatter()
            .string(from: Date(timeIntervalSinceNow: -Double(minutesAgo) * 60))
        var dict: [String: Any] = ["object_id": id, "action_type": action, "event_date": when]
        if let state { dict["state"] = state }
        if let details { dict["details_blob"] = details }
        if withPhoto {
            dict["media"] = ["image_url": "https://cdn.example/\(id).jpg",
                             "thumbnail_url": "https://cdn.example/\(id)-thumb.jpg"]
        }
        return try JSONDecoder().decode(
            BrightwheelActivity.self,
            from: JSONSerialization.data(withJSONObject: dict))
    }

    private func napActivity(id: String, state: String, minutesAgo: Int) throws -> BrightwheelActivity {
        try activity(id: id, action: "ac_nap", minutesAgo: minutesAgo, state: state)
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

    func testPhotoAttachedToAFeedImportsAsItsOwnPhotoEvent() throws {
        let feed = try activity(id: "feed-1", action: "ac_food", minutesAgo: 30,
                                withPhoto: true,
                                details: ["food_type": "bottle", "amount": 4.0,
                                          "amount_type": "oz"])
        let summary = BrightwheelImporter(context: container.mainContext)
            .importActivities([feed])
        XCTAssertEqual(summary.feeds, 1)
        XCTAssertEqual(summary.media, 1, "the attached photo rides along as a photo event")

        let media = try container.mainContext.fetch(FetchDescriptor<MediaEvent>())
        XCTAssertEqual(media.first?.externalID, "feed-1-photo",
                       "derived id so the attachment dedupes apart from its host")
        XCTAssertEqual(media.first?.remoteURL, "https://cdn.example/feed-1.jpg")
    }

    func testAttachedPhotoDedupesOnReimport() throws {
        let feed = try activity(id: "feed-2", action: "ac_food", minutesAgo: 30,
                                withPhoto: true,
                                details: ["food_type": "bottle", "amount": 4.0,
                                          "amount_type": "oz"])
        let importer = BrightwheelImporter(context: container.mainContext)
        _ = importer.importActivities([feed])
        let second = importer.importActivities([feed])
        XCTAssertEqual(second.feeds, 0)
        XCTAssertEqual(second.media, 0, "the same sync re-fetched must not duplicate the photo")
    }

    func testPhotoOnAnOpenNapImportsWhileTheNapWaits() throws {
        let start = try activity(id: "nap-photo", action: "ac_nap", minutesAgo: 12,
                                 state: "1", withPhoto: true)
        let summary = BrightwheelImporter(context: container.mainContext)
            .importActivities([start])
        XCTAssertEqual(summary.sleeps, 0, "the nap still waits for its wake half")
        XCTAssertEqual(summary.media, 1, "but its photo shows up right away")
        XCTAssertEqual(summary.openNapStartedAt, start.when)
    }

    // MARK: Miller's missing 3h17m nap (2026-10-13, second daycare day)

    func testMillersDayTwoNapSurvivesMidNapPhotoRestatements() throws {
        // The real day: nap started 8:40, photos posted ON the nap record at
        // 10:52 and 10:56 (re-stating "asleep"), nap ended 11:57. The photo
        // re-statements must not usurp the true start.
        let summary = try BrightwheelImporter(context: container.mainContext)
            .importActivities([
                napActivity(id: "nap-end", state: "0", minutesAgo: 0),
                activity(id: "nap-photo-2", action: "ac_nap", minutesAgo: 61,
                         state: "1", withPhoto: true),
                activity(id: "nap-photo-1", action: "ac_nap", minutesAgo: 65,
                         state: "1", withPhoto: true),
                napActivity(id: "nap-start", state: "1", minutesAgo: 197),
            ])
        XCTAssertEqual(summary.sleeps, 1)
        XCTAssertEqual(summary.media, 2, "both mid-nap photos import")
        let sleeps = try container.mainContext.fetch(FetchDescriptor<SleepEvent>())
        let nap = try XCTUnwrap(sleeps.first)
        XCTAssertEqual(nap.endedAt.map { $0.timeIntervalSince(nap.startedAt) } ?? 0,
                       197 * 60, accuracy: 90,
                       "the full 3h17m span, not photo-to-wake")
    }

    func testOrphanWakeUpPairsWithTheCarriedLiveNapStart() throws {
        // A wake-up whose start never re-appears in the batch (updated in
        // place, or scrolled off the page) pairs with the live-nap start an
        // earlier sync remembered.
        let start = Date(timeIntervalSinceNow: -197 * 60)
        let summary = try BrightwheelImporter(context: container.mainContext)
            .importActivities([napActivity(id: "nap-end-solo", state: "0", minutesAgo: 0)],
                              carriedNapStart: start)
        XCTAssertEqual(summary.sleeps, 1)
        let nap = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<SleepEvent>()).first)
        XCTAssertEqual(nap.startedAt.timeIntervalSince(start), 0, accuracy: 1)
    }

    func testSingleRecordNapShapeImportsFromItsOwnSpan() throws {
        // Hedge against the updated-in-place wire: one ac_nap record, final
        // state "0", carrying its span in the blob.
        let start = ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: -197 * 60))
        let summary = try BrightwheelImporter(context: container.mainContext)
            .importActivities([
                activity(id: "nap-single", action: "ac_nap", minutesAgo: 0,
                         state: "0", details: ["start_time": start]),
            ])
        XCTAssertEqual(summary.sleeps, 1)
    }

    func testLoneWakeUpWithDurationWalksBackToTheStart() throws {
        let summary = try BrightwheelImporter(context: container.mainContext)
            .importActivities([
                activity(id: "nap-duration", action: "ac_nap", minutesAgo: 0,
                         state: "0", details: ["duration": 197]),
            ])
        XCTAssertEqual(summary.sleeps, 1)
        let nap = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<SleepEvent>()).first)
        XCTAssertEqual(nap.endedAt.map { $0.timeIntervalSince(nap.startedAt) } ?? 0,
                       197 * 60, accuracy: 90)
    }

    func testWordySleepStatesStillPair() throws {
        // Unknown state spellings must not silently drop a nap again.
        let summary = try BrightwheelImporter(context: container.mainContext)
            .importActivities([
                activity(id: "nap-end-w", action: "ac_nap", minutesAgo: 0, state: "awake"),
                activity(id: "nap-start-w", action: "ac_nap", minutesAgo: 50, state: "asleep"),
            ])
        XCTAssertEqual(summary.sleeps, 1)
    }

    func testNapHalvesRecognizedFromNoteTextWhenStateIsMissing() throws {
        // No state anywhere; the human-readable rows carry the halves.
        func noteActivity(_ id: String, _ note: String, minutesAgo: Int) throws -> BrightwheelActivity {
            let dict: [String: Any] = [
                "object_id": id, "action_type": "ac_nap", "note": note,
                "event_date": ISO8601DateFormatter()
                    .string(from: Date(timeIntervalSinceNow: -Double(minutesAgo) * 60)),
            ]
            return try JSONDecoder().decode(
                BrightwheelActivity.self,
                from: JSONSerialization.data(withJSONObject: dict))
        }
        let summary = try BrightwheelImporter(context: container.mainContext)
            .importActivities([
                noteActivity("nap-end-n", "Miller nap ended", minutesAgo: 0),
                noteActivity("nap-start-n", "Miller nap started", minutesAgo: 50),
            ])
        XCTAssertEqual(summary.sleeps, 1)
    }

    func testLoneWakeUpWithNothingUsableStaysSkippedNotFabricated() throws {
        let summary = try BrightwheelImporter(context: container.mainContext)
            .importActivities([napActivity(id: "nap-end-bare", state: "0", minutesAgo: 0)])
        XCTAssertEqual(summary.sleeps, 0)
        XCTAssertEqual(summary.skippedUnmapped, 1)
    }

    func testTwoPhotosAtTheSameTimestampBothImport() throws {
        // The 9:23 AM bug: distinct photo posts sharing one timestamp are two
        // photos, not a re-issue — the time-window fallback must not eat the
        // second when each carries its own object id.
        let photos = try [
            activity(id: "photo-a", action: "ac_photo", minutesAgo: 30, withPhoto: true),
            activity(id: "photo-b", action: "ac_photo", minutesAgo: 30, withPhoto: true),
        ]
        let summary = BrightwheelImporter(context: container.mainContext)
            .importActivities(photos)
        XCTAssertEqual(summary.media, 2)
        XCTAssertEqual(summary.skippedDuplicates, 0)

        // And the same two re-fetched still dedupe on their ids.
        let second = BrightwheelImporter(context: container.mainContext)
            .importActivities(photos)
        XCTAssertEqual(second.media, 0)
        XCTAssertEqual(second.skippedDuplicates, 2)
    }

    // MARK: Photo-burst grouping (the timeline's "Photos (2)" row)

    private func photoEvent(minutesAgo: Int, daycare: Bool = true) -> MediaEvent {
        MediaEvent(baby: nil, kind: .photo,
                   timestamp: Date(timeIntervalSinceNow: -Double(minutesAgo) * 60),
                   loggedByID: UUID(), loggedByName: "", loggedByColorHex: "",
                   sourceRaw: daycare ? EventSource.brightwheel.rawValue : nil)
    }

    func testSameMomentPhotosGroupIntoOneRow() {
        let a = photoEvent(minutesAgo: 30)
        let b = photoEvent(minutesAgo: 30)
        let other = photoEvent(minutesAgo: 90)
        let grouped = HomeView.groupingPhotoBursts(
            [.media(a), .media(b), .media(other)])
        XCTAssertEqual(grouped.count, 2)
        guard case .mediaGroup(let burst) = grouped[0] else {
            return XCTFail("expected the 9:23 pair to group")
        }
        XCTAssertEqual(burst.count, 2)
        XCTAssertEqual(grouped[0].detail, "Photos (2)")
        if case .mediaGroup = grouped[1] { XCTFail("a lone photo keeps its plain row") }
    }

    func testBurstsDoNotSwallowNeighborsOrMixOrigins() {
        let daycare = photoEvent(minutesAgo: 30)
        let home = photoEvent(minutesAgo: 30, daycare: false)
        let grouped = HomeView.groupingPhotoBursts([.media(daycare), .media(home)])
        XCTAssertEqual(grouped.count, 2, "a parent's photo never folds into a daycare burst")
    }

    // MARK: PhotoSaver byte sourcing (no Photos-framework access needed)

    func testPhotoSaverPrefersCachedBytes() async {
        let png = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
            .pngData { $0.fill(CGRect(x: 0, y: 0, width: 2, height: 2)) }
        let event = MediaEvent(baby: nil, kind: .photo, mediaData: png,
                               loggedByID: UUID(), loggedByName: "", loggedByColorHex: "")
        let data = await PhotoSaver.imageData(for: event)
        XCTAssertEqual(data, png, "cached bytes win — no network touch")
    }

    func testPhotoSaverReturnsNilWithoutBytesOrURL() async {
        let event = MediaEvent(baby: nil, kind: .photo,
                               loggedByID: UUID(), loggedByName: "", loggedByColorHex: "")
        let data = await PhotoSaver.imageData(for: event)
        XCTAssertNil(data, "no cache and no link means nothing to save — never junk bytes")
    }

    // MARK: Open nap never outlives checkout

    private func checkoutActivity(id: String, minutesAgo: Int) throws -> BrightwheelActivity {
        let dict: [String: Any] = [
            "object_id": id, "action_type": "ac_checkin", "note": "Picked up by Mom",
            "event_date": ISO8601DateFormatter()
                .string(from: Date(timeIntervalSinceNow: -Double(minutesAgo) * 60)),
        ]
        return try JSONDecoder().decode(
            BrightwheelActivity.self,
            from: JSONSerialization.data(withJSONObject: dict))
    }

    func testCheckoutClosesANapBrightwheelNeverEnded() throws {
        // Staff logged the fell-asleep but never the wake-up; pickup still
        // ends the nap right then instead of letting it run forever.
        let start = try napActivity(id: "nap-start", state: "1", minutesAgo: 90)
        let checkout = try checkoutActivity(id: "checkout", minutesAgo: 10)
        let summary = BrightwheelImporter(context: container.mainContext)
            .importActivities([start, checkout])
        XCTAssertEqual(summary.sleeps, 1, "the open nap closes at checkout")
        XCTAssertEqual(summary.checks, 1)
        XCTAssertNil(summary.openNapStartedAt, "nothing left running after pickup")

        let nap = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<SleepEvent>()).first)
        XCTAssertEqual(nap.startedAt.timeIntervalSince(start.when!), 0, accuracy: 1)
        XCTAssertEqual(nap.endedAt?.timeIntervalSince(checkout.when!) ?? -1, 0, accuracy: 1)
    }

    func testCheckoutWithNoOpenNapImportsNormally() throws {
        // The ordinary case: no nap running, checkout just logs the marker.
        let checkout = try checkoutActivity(id: "checkout-plain", minutesAgo: 5)
        let summary = BrightwheelImporter(context: container.mainContext)
            .importActivities([checkout])
        XCTAssertEqual(summary.sleeps, 0)
        XCTAssertEqual(summary.checks, 1)
    }

    func testReimportingTheSameCheckoutDoesNotDoubleCloseTheNap() throws {
        // A later sync re-scans the whole day again: the nap must close once,
        // not re-import as a second sleep.
        let start = try napActivity(id: "nap-start-2", state: "1", minutesAgo: 90)
        let checkout = try checkoutActivity(id: "checkout-2", minutesAgo: 10)
        let importer = BrightwheelImporter(context: container.mainContext)
        _ = importer.importActivities([start, checkout])
        let second = importer.importActivities([start, checkout])
        XCTAssertEqual(second.sleeps, 0, "the closed nap dedupes like any other re-synced activity")
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
