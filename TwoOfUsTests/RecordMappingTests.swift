import XCTest
import CloudKit
import SwiftData
@testable import TwoOfUs

/// Round-trips every record type through `RecordMapping` — the same trip a
/// record takes between the two parents' phones (build the CKRecord on the
/// sender, apply it to a separate empty store on the receiver). No CloudKit
/// server involved; this validates the field mapping and upsert semantics.
@MainActor
final class RecordMappingTests: XCTestCase {
    private var sender: ModelContainer!
    private var context: ModelContext { sender.mainContext }

    private let zoneID = CKRecordZone.ID(zoneName: SyncConstants.zoneName,
                                         ownerName: CKCurrentUserDefaultName)

    override func setUp() {
        super.setUp()
        sender = AppModelContainer.make(inMemory: true)
    }

    override func tearDown() {
        sender = nil
        super.tearDown()
    }

    private func recordID(_ id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    }

    /// Builds the outbound record for `id` from the sender store.
    private func outbound(_ id: UUID) throws -> CKRecord {
        try XCTUnwrap(
            RecordMapping.record(forRecordName: id.uuidString, recordID: recordID(id), in: context),
            "no outbound record built for \(id)"
        )
    }

    // MARK: Per-type round trips

    func testFeedRoundTrip() throws {
        let baby = Baby(name: "Miller", dateOfBirth: .now)
        context.insert(baby)
        let original = FeedEvent(
            baby: baby, amountOz: 3.5, timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            notes: "fussy", loggedByID: UUID(), loggedByName: "Taylor", loggedByColorHex: "#AABBCC",
            editOfID: UUID()
        )
        context.insert(original)
        try context.save()

        let receiver = AppModelContainer.make(inMemory: true)
        // Baby must land before the feed for the relationship to resolve.
        RecordMapping.apply(try outbound(baby.id), in: receiver.mainContext)
        RecordMapping.apply(try outbound(original.id), in: receiver.mainContext)

        let feeds = try receiver.mainContext.fetch(FetchDescriptor<FeedEvent>())
        XCTAssertEqual(feeds.count, 1)
        let copy = try XCTUnwrap(feeds.first)
        XCTAssertEqual(copy.id, original.id)
        XCTAssertEqual(copy.amountOz, 3.5)
        XCTAssertEqual(copy.timestamp, original.timestamp)
        XCTAssertEqual(copy.notes, "fussy")
        XCTAssertEqual(copy.loggedByID, original.loggedByID)
        XCTAssertEqual(copy.loggedByName, "Taylor")
        XCTAssertEqual(copy.loggedByColorHex, "#AABBCC")
        XCTAssertEqual(copy.editOfID, original.editOfID)
        XCTAssertNil(copy.deletedAt)
        XCTAssertEqual(copy.baby?.id, baby.id)
    }

    func testActiveSleepRoundTripStaysActive() throws {
        let original = SleepEvent(
            baby: nil, startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            loggedByID: UUID(), loggedByName: "T", loggedByColorHex: "#000000"
        )
        context.insert(original)
        try context.save()

        let receiver = AppModelContainer.make(inMemory: true)
        RecordMapping.apply(try outbound(original.id), in: receiver.mainContext)

        let copy = try XCTUnwrap(receiver.mainContext.fetch(FetchDescriptor<SleepEvent>()).first)
        XCTAssertEqual(copy.startedAt, original.startedAt)
        XCTAssertNil(copy.endedAt, "a running sleep must still be running on the other phone")
        XCTAssertTrue(copy.isActive)
    }

    func testDiaperRoundTrip() throws {
        let original = DiaperEvent(
            baby: nil, type: .both, timestamp: .now,
            loggedByID: UUID(), loggedByName: "T", loggedByColorHex: "#000000"
        )
        context.insert(original)
        try context.save()

        let receiver = AppModelContainer.make(inMemory: true)
        RecordMapping.apply(try outbound(original.id), in: receiver.mainContext)

        let copy = try XCTUnwrap(receiver.mainContext.fetch(FetchDescriptor<DiaperEvent>()).first)
        XCTAssertEqual(copy.type, .both)
        XCTAssertEqual(copy.timestamp, original.timestamp)
    }

    func testBabyRoundTripIncludingPhotoAsset() throws {
        let original = Baby(name: "Miller", dateOfBirth: Date(timeIntervalSince1970: 1_690_000_000))
        original.photoData = Data([0xDE, 0xAD, 0xBE, 0xEF])
        context.insert(original)
        try context.save()

        let receiver = AppModelContainer.make(inMemory: true)
        RecordMapping.apply(try outbound(original.id), in: receiver.mainContext)

        let copy = try XCTUnwrap(receiver.mainContext.fetch(FetchDescriptor<Baby>()).first)
        XCTAssertEqual(copy.name, "Miller")
        XCTAssertEqual(copy.dateOfBirth, original.dateOfBirth)
        XCTAssertEqual(copy.createdAt, original.createdAt)
        XCTAssertEqual(copy.photoData, original.photoData, "avatar must survive the CKAsset round trip")
    }

    func testParticipantRoundTrip() throws {
        let original = Participant(displayName: "Katie", colorHex: "#112233",
                                   role: .logger, cloudUserID: "_abc123", isActive: false)
        context.insert(original)
        try context.save()

        let receiver = AppModelContainer.make(inMemory: true)
        RecordMapping.apply(try outbound(original.id), in: receiver.mainContext)

        let copy = try XCTUnwrap(receiver.mainContext.fetch(FetchDescriptor<Participant>()).first)
        XCTAssertEqual(copy.displayName, "Katie")
        XCTAssertEqual(copy.colorHex, "#112233")
        XCTAssertEqual(copy.role, .logger)
        XCTAssertEqual(copy.cloudUserID, "_abc123")
        XCTAssertFalse(copy.isActive)
        XCTAssertEqual(copy.invitedAt, original.invitedAt)
    }

    func testSettingsRoundTrip() throws {
        let original = SharedSettings(targetFeedIntervalMinutes: 150,
                                      ozPresets: [2, 2.5, 5], defaultFeedOz: 5)
        context.insert(original)
        try context.save()

        let receiver = AppModelContainer.make(inMemory: true)
        RecordMapping.apply(try outbound(original.id), in: receiver.mainContext)

        let copy = try XCTUnwrap(receiver.mainContext.fetch(FetchDescriptor<SharedSettings>()).first)
        XCTAssertEqual(copy.targetFeedIntervalMinutes, 150)
        XCTAssertEqual(copy.ozPresets, [2, 2.5, 5])
        XCTAssertEqual(copy.defaultFeedOz, 5)
    }

    // MARK: Sync semantics

    func testApplyIsAnUpsertNotAnInsert() throws {
        let original = FeedEvent(baby: nil, amountOz: 2, timestamp: .now,
                                 loggedByID: UUID(), loggedByName: "T", loggedByColorHex: "#000000")
        context.insert(original)
        try context.save()
        let record = try outbound(original.id)

        let receiver = AppModelContainer.make(inMemory: true)
        RecordMapping.apply(record, in: receiver.mainContext)
        RecordMapping.apply(record, in: receiver.mainContext)

        XCTAssertEqual(try receiver.mainContext.fetch(FetchDescriptor<FeedEvent>()).count, 1)
    }

    func testSoftDeleteTravelsAsAnUpdate() throws {
        let original = FeedEvent(baby: nil, amountOz: 2, timestamp: .now,
                                 loggedByID: UUID(), loggedByName: "T", loggedByColorHex: "#000000")
        context.insert(original)
        try context.save()

        let receiver = AppModelContainer.make(inMemory: true)
        RecordMapping.apply(try outbound(original.id), in: receiver.mainContext)

        // The co-parent soft-deletes; the change syncs as a deletedAt update.
        original.deletedAt = .now
        try context.save()
        RecordMapping.apply(try outbound(original.id), in: receiver.mainContext)

        let feeds = try receiver.mainContext.fetch(FetchDescriptor<FeedEvent>())
        XCTAssertEqual(feeds.count, 1)
        XCTAssertNotNil(feeds.first?.deletedAt)
    }

    func testHardDeleteRemovesLocalModel() throws {
        let original = DiaperEvent(baby: nil, type: .wet, timestamp: .now,
                                   loggedByID: UUID(), loggedByName: "T", loggedByColorHex: "#000000")
        context.insert(original)
        try context.save()

        RecordMapping.delete(recordName: original.id.uuidString, in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<DiaperEvent>()).count, 0)
    }

    func testNoRecordBuiltForUnknownID() {
        let record = RecordMapping.record(forRecordName: UUID().uuidString,
                                          recordID: recordID(UUID()), in: context)
        XCTAssertNil(record, "a stale pending change must produce no record (the engine drops it)")
    }
}
