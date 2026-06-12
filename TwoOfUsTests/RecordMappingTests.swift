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

    // MARK: System fields (the server change tag)

    func testSystemFieldsArchiveRoundTrip() throws {
        let id = CKRecord.ID(recordName: UUID().uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: SyncConstants.RecordType.feed, recordID: id)

        let data = RecordMapping.archivedSystemFields(of: record)
        let decoded = try XCTUnwrap(RecordMapping.decodeSystemFieldsRecord(data))

        XCTAssertEqual(decoded.recordID, id)
        XCTAssertEqual(decoded.recordType, SyncConstants.RecordType.feed)
    }

    func testBaseRecordRejectsArchiveFromAnotherZone() {
        // A participant who left a share re-uploads into their OWN zone: the
        // archived system fields still point at the old owner's zone and must
        // be discarded, or the record would be stamped with the wrong identity.
        let uuid = UUID()
        let foreignZone = CKRecordZone.ID(zoneName: SyncConstants.zoneName, ownerName: "_someoneElse")
        let foreignID = CKRecord.ID(recordName: uuid.uuidString, zoneID: foreignZone)
        let archived = RecordMapping.archivedSystemFields(
            of: CKRecord(recordType: SyncConstants.RecordType.feed, recordID: foreignID))

        let requestedID = CKRecord.ID(recordName: uuid.uuidString, zoneID: zoneID)
        let base = RecordMapping.baseRecord(type: SyncConstants.RecordType.feed,
                                            recordID: requestedID, archived: archived)

        XCTAssertEqual(base.recordID, requestedID,
                       "a zone-mismatched archive must be replaced by a fresh record with the requested identity")
    }

    func testPersistAndClearSystemFields() throws {
        let event = FeedEvent(baby: nil, amountOz: 2, timestamp: .now,
                              loggedByID: UUID(), loggedByName: "T", loggedByColorHex: "#000000")
        context.insert(event)
        try context.save()

        let server = CKRecord(recordType: SyncConstants.RecordType.feed, recordID: recordID(event.id))
        RecordMapping.persistSystemFields(of: server, in: context)
        XCTAssertNotNil(event.ckSystemFields,
                        "fetched/saved server copies must leave their change tag on the model")

        RecordMapping.clearSystemFields(forRecordName: event.id.uuidString, in: context)
        XCTAssertNil(event.ckSystemFields)
    }

    func testOutboundRecordCarriesArchivedIdentity() throws {
        let event = FeedEvent(baby: nil, amountOz: 2, timestamp: .now,
                              loggedByID: UUID(), loggedByName: "T", loggedByColorHex: "#000000")
        context.insert(event)
        try context.save()
        let id = recordID(event.id)
        RecordMapping.persistSystemFields(
            of: CKRecord(recordType: SyncConstants.RecordType.feed, recordID: id), in: context)

        let outbound = try XCTUnwrap(
            RecordMapping.record(forRecordName: event.id.uuidString, recordID: id, in: context))

        XCTAssertEqual(outbound.recordID, id)
        XCTAssertEqual(outbound["amountOz"] as? Double, 2,
                       "user fields are re-populated on top of the archived base record")
    }

    // MARK: Conflict absorption

    func testAbsorbConflictKeepsLocalContentButAdoptsTerminalFields() throws {
        let event = FeedEvent(baby: nil, amountOz: 5, timestamp: .now,
                              loggedByID: UUID(), loggedByName: "T", loggedByColorHex: "#000000")
        context.insert(event)
        try context.save()

        // The other parent's copy: different amount AND a soft delete.
        let server = CKRecord(recordType: SyncConstants.RecordType.feed, recordID: recordID(event.id))
        server["amountOz"] = 3.0
        let deletedAt = Date(timeIntervalSince1970: 1_700_000_000)
        server["deletedAt"] = deletedAt

        RecordMapping.absorbConflict(server: server, in: context)

        XCTAssertEqual(event.amountOz, 5, "local content wins the conflict (it re-uploads next)")
        XCTAssertEqual(event.deletedAt, deletedAt,
                       "but a concurrent delete must never be resurrected by the race loser")
        XCTAssertNotNil(event.ckSystemFields, "the server change tag is adopted so the re-save succeeds")
    }

    func testAbsorbConflictAdoptsConcurrentSleepStop() throws {
        let sleep = SleepEvent(baby: nil, startedAt: .now,
                               loggedByID: UUID(), loggedByName: "T", loggedByColorHex: "#000000")
        context.insert(sleep)
        try context.save()

        let server = CKRecord(recordType: SyncConstants.RecordType.sleep, recordID: recordID(sleep.id))
        let endedAt = Date(timeIntervalSince1970: 1_700_000_100)
        server["endedAt"] = endedAt

        RecordMapping.absorbConflict(server: server, in: context)

        XCTAssertEqual(sleep.endedAt, endedAt,
                       "a sleep the other parent already stopped must not restart")
    }

    // MARK: Orphaned events (event records can land before their Baby)

    func testRelinkAttachesEventsThatArrivedBeforeTheBaby() throws {
        let baby = Baby(name: "Miller", dateOfBirth: .now)
        context.insert(baby)
        let feed = FeedEvent(baby: baby, amountOz: 3, timestamp: .now,
                             loggedByID: UUID(), loggedByName: "T", loggedByColorHex: "#000000")
        context.insert(feed)
        try context.save()

        let receiver = AppModelContainer.make(inMemory: true)
        // Feed first — its babyID can't resolve yet, so it lands orphaned.
        RecordMapping.apply(try outbound(feed.id), in: receiver.mainContext)
        XCTAssertNil(try XCTUnwrap(receiver.mainContext.fetch(FetchDescriptor<FeedEvent>()).first).baby)

        RecordMapping.apply(try outbound(baby.id), in: receiver.mainContext)
        RecordMapping.relinkOrphanEvents(in: receiver.mainContext)

        let copy = try XCTUnwrap(receiver.mainContext.fetch(FetchDescriptor<FeedEvent>()).first)
        XCTAssertEqual(copy.baby?.id, baby.id,
                       "events fetched before their Baby record must attach once it lands")
    }
}
