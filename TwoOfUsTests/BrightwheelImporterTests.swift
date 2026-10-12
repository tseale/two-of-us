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
