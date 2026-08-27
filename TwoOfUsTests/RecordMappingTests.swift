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
        try RecordMapping.apply(try outbound(baby.id), in: receiver.mainContext)
        try RecordMapping.apply(try outbound(original.id), in: receiver.mainContext)

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
        try RecordMapping.apply(try outbound(original.id), in: receiver.mainContext)

        let copy = try XCTUnwrap(receiver.mainContext.fetch(FetchDescriptor<SleepEvent>()).first)
        XCTAssertEqual(copy.startedAt, original.startedAt)
        XCTAssertNil(copy.endedAt, "a running sleep must still be running on the other phone")
        XCTAssertTrue(copy.isActive)
        XCTAssertNil(copy.sourceRaw, "a hand-logged sleep must not grow a source in transit")
    }

    func testSnooSleepRoundTripKeepsSource() throws {
        let original = SleepEvent(
            baby: nil, startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_007_200),
            loggedByID: UUID(), loggedByName: "T", loggedByColorHex: "#000000",
            sourceRaw: SleepSource.snoo.rawValue
        )
        context.insert(original)
        try context.save()

        let receiver = AppModelContainer.make(inMemory: true)
        try RecordMapping.apply(try outbound(original.id), in: receiver.mainContext)

        let copy = try XCTUnwrap(receiver.mainContext.fetch(FetchDescriptor<SleepEvent>()).first)
        XCTAssertEqual(copy.sourceRaw, "snoo",
                       "the SNOO tag must survive to the co-parent's phone")
        XCTAssertTrue(copy.isFromSnoo)
    }

    func testDiaperRoundTrip() throws {
        let original = DiaperEvent(
            baby: nil, type: .both, timestamp: .now,
            loggedByID: UUID(), loggedByName: "T", loggedByColorHex: "#000000"
        )
        context.insert(original)
        try context.save()

        let receiver = AppModelContainer.make(inMemory: true)
        try RecordMapping.apply(try outbound(original.id), in: receiver.mainContext)

        let copy = try XCTUnwrap(receiver.mainContext.fetch(FetchDescriptor<DiaperEvent>()).first)
        XCTAssertEqual(copy.type, .both)
        XCTAssertEqual(copy.timestamp, original.timestamp)
    }

    func testNoteRoundTrip() throws {
        let baby = Baby(name: "Miller", dateOfBirth: .now)
        context.insert(baby)
        let original = NoteEvent(
            baby: baby, text: "gave vitamin D drops",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            loggedByID: UUID(), loggedByName: "Taylor", loggedByColorHex: "#AABBCC",
            editOfID: UUID()
        )
        context.insert(original)
        try context.save()

        let receiver = AppModelContainer.make(inMemory: true)
        try RecordMapping.apply(try outbound(baby.id), in: receiver.mainContext)
        try RecordMapping.apply(try outbound(original.id), in: receiver.mainContext)

        let notes = try receiver.mainContext.fetch(FetchDescriptor<NoteEvent>())
        XCTAssertEqual(notes.count, 1)
        let copy = try XCTUnwrap(notes.first)
        XCTAssertEqual(copy.id, original.id)
        XCTAssertEqual(copy.text, "gave vitamin D drops")
        XCTAssertEqual(copy.timestamp, original.timestamp)
        XCTAssertEqual(copy.loggedByID, original.loggedByID)
        XCTAssertEqual(copy.loggedByName, "Taylor")
        XCTAssertEqual(copy.loggedByColorHex, "#AABBCC")
        XCTAssertEqual(copy.editOfID, original.editOfID)
        XCTAssertNil(copy.deletedAt)
        XCTAssertEqual(copy.baby?.id, baby.id)
    }

    /// A note record missing its required fields must be skipped, never
    /// materialized as a placeholder row (the ghost-event rule).
    func testNoteMissingRequiredFieldsIsSkipped() throws {
        let receiver = AppModelContainer.make(inMemory: true)
        let id = UUID()
        let bare = CKRecord(recordType: SyncConstants.RecordType.note, recordID: recordID(id))
        bare["timestamp"] = Date()
        // no text, no logger identity
        try RecordMapping.apply(bare, in: receiver.mainContext)

        XCTAssertTrue(try receiver.mainContext.fetch(FetchDescriptor<NoteEvent>()).isEmpty,
                      "junk on the server must not become a local row")
    }

    func testBabyRoundTripIncludingPhotoAsset() throws {
        let original = Baby(name: "Miller", dateOfBirth: Date(timeIntervalSince1970: 1_690_000_000))
        original.photoData = Data([0xDE, 0xAD, 0xBE, 0xEF])
        context.insert(original)
        try context.save()

        let receiver = AppModelContainer.make(inMemory: true)
        try RecordMapping.apply(try outbound(original.id), in: receiver.mainContext)

        let copy = try XCTUnwrap(receiver.mainContext.fetch(FetchDescriptor<Baby>()).first)
        XCTAssertEqual(copy.name, "Miller")
        XCTAssertEqual(copy.dateOfBirth, original.dateOfBirth)
        XCTAssertEqual(copy.createdAt, original.createdAt)
        XCTAssertEqual(copy.photoData, original.photoData, "avatar must survive the CKAsset round trip")
    }

    /// A present-but-unreadable photo asset (transient fetch failure) must NOT
    /// wipe a good local avatar.
    func testUnreadablePhotoAssetKeepsLocalAvatar() throws {
        let receiver = AppModelContainer.make(inMemory: true)
        let local = Baby(name: "Miller", dateOfBirth: Date(timeIntervalSince1970: 1_690_000_000))
        local.photoData = Data([0x01, 0x02, 0x03])
        receiver.mainContext.insert(local)
        try receiver.mainContext.save()

        let r = CKRecord(recordType: SyncConstants.RecordType.baby, recordID: recordID(local.id))
        r["name"] = "Miller"
        r["dateOfBirth"] = local.dateOfBirth
        r["photoData"] = CKAsset(fileURL: URL(fileURLWithPath: NSTemporaryDirectory() + "missing-\(UUID().uuidString)"))
        try RecordMapping.apply(r, in: receiver.mainContext)

        let copy = try XCTUnwrap(Baby.fetchByID(local.id, in: receiver.mainContext))
        XCTAssertEqual(copy.photoData, Data([0x01, 0x02, 0x03]),
                       "a transiently unreadable asset must not erase the local avatar")
    }

    /// A genuinely absent photo field (the photo was cleared upstream) clears the
    /// local avatar.
    func testAbsentPhotoFieldClearsLocalAvatar() throws {
        let receiver = AppModelContainer.make(inMemory: true)
        let local = Baby(name: "Miller", dateOfBirth: Date(timeIntervalSince1970: 1_690_000_000))
        local.photoData = Data([0x09])
        receiver.mainContext.insert(local)
        try receiver.mainContext.save()

        let r = CKRecord(recordType: SyncConstants.RecordType.baby, recordID: recordID(local.id))
        r["name"] = "Miller"
        r["dateOfBirth"] = local.dateOfBirth
        // no photoData field → the photo was cleared
        try RecordMapping.apply(r, in: receiver.mainContext)

        let copy = try XCTUnwrap(Baby.fetchByID(local.id, in: receiver.mainContext))
        XCTAssertNil(copy.photoData, "an absent photo field should clear the local avatar")
    }

    func testParticipantRoundTrip() throws {
        let original = Participant(displayName: "Katie", colorHex: "#112233",
                                   role: .logger, cloudUserID: "_abc123", isActive: false)
        context.insert(original)
        try context.save()

        let receiver = AppModelContainer.make(inMemory: true)
        try RecordMapping.apply(try outbound(original.id), in: receiver.mainContext)

        let copy = try XCTUnwrap(receiver.mainContext.fetch(FetchDescriptor<Participant>()).first)
        XCTAssertEqual(copy.displayName, "Katie")
        XCTAssertEqual(copy.colorHex, "#112233")
        XCTAssertEqual(copy.role, .logger)
        XCTAssertEqual(copy.cloudUserID, "_abc123")
        XCTAssertFalse(copy.isActive)
        XCTAssertEqual(copy.invitedAt, original.invitedAt)
    }

    func testApplyParticipantSkipsRecordsMissingDisplayName() throws {
        // A junk participant record must not become a nameless local row — its
        // id would count as "known", immunizing ghost events attributed to it
        // against every sweep.
        let receiver = AppModelContainer.make(inMemory: true)
        let bare = CKRecord(recordType: SyncConstants.RecordType.participant, recordID: recordID(UUID()))
        try RecordMapping.apply(bare, in: receiver.mainContext)

        XCTAssertTrue(try receiver.mainContext.fetch(FetchDescriptor<Participant>()).isEmpty,
                      "a name-less participant record must not materialize")
    }

    func testApplyParticipantKeepsLocalCloudUserIDWhenFieldAbsent() throws {
        // An older build's record carries no cloudUserID — applying it must not
        // nil a locally captured identity, or the duplicate-participant
        // auto-merge is permanently disarmed.
        let receiver = AppModelContainer.make(inMemory: true)
        let local = Participant(displayName: "Katie", colorHex: "#112233", cloudUserID: "_abc123")
        receiver.mainContext.insert(local)
        try receiver.mainContext.save()

        let sparse = CKRecord(recordType: SyncConstants.RecordType.participant,
                              recordID: recordID(local.id))
        sparse["displayName"] = "Katie"
        sparse["colorHex"] = "#112233"
        try RecordMapping.apply(sparse, in: receiver.mainContext)

        XCTAssertEqual(local.cloudUserID, "_abc123", "an absent field keeps the captured identity")
    }

    func testPausedParticipantRoundTrip() throws {
        let pausedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let original = Participant(displayName: "Grandma", colorHex: "#112233",
                                   role: .logger, pausedAt: pausedAt)
        context.insert(original)
        try context.save()

        let receiver = AppModelContainer.make(inMemory: true)
        try RecordMapping.apply(try outbound(original.id), in: receiver.mainContext)

        let copy = try XCTUnwrap(receiver.mainContext.fetch(FetchDescriptor<Participant>()).first)
        XCTAssertEqual(copy.pausedAt, pausedAt)
        XCTAssertTrue(copy.isPaused)
    }

    func testResumeTravelsAsExplicitDistantPastNotAnAbsentField() throws {
        // CloudKit never transmits an unset key, so a resume encoded as bare
        // nil would leave the other phone paused forever. The outbound record
        // must carry distantPast explicitly, and applying it must un-pause.
        let original = Participant(displayName: "Grandma", colorHex: "#112233", role: .logger)
        context.insert(original)
        try context.save()

        let record = try outbound(original.id)
        XCTAssertEqual(record["pausedAt"] as? Date, .distantPast,
                       "resume must write an explicit sentinel, never an absent key")

        let receiver = AppModelContainer.make(inMemory: true)
        // Same person id on the receiver, locally still paused.
        let paused = Participant(id: original.id, displayName: "Grandma",
                                 colorHex: "#112233", role: .logger, pausedAt: .now)
        receiver.mainContext.insert(paused)
        try receiver.mainContext.save()
        try RecordMapping.apply(record, in: receiver.mainContext)

        XCTAssertNil(paused.pausedAt, "an explicit distantPast must clear the pause")
    }

    func testApplyParticipantKeepsLocalPauseWhenFieldAbsent() throws {
        // An older build's record predates pausedAt — applying it must not
        // silently resume someone the owner paused.
        let receiver = AppModelContainer.make(inMemory: true)
        let local = Participant(displayName: "Grandma", colorHex: "#112233",
                                role: .logger, pausedAt: .now)
        receiver.mainContext.insert(local)
        try receiver.mainContext.save()

        let sparse = CKRecord(recordType: SyncConstants.RecordType.participant,
                              recordID: recordID(local.id))
        sparse["displayName"] = "Grandma"
        sparse["colorHex"] = "#112233"
        try RecordMapping.apply(sparse, in: receiver.mainContext)

        XCTAssertNotNil(local.pausedAt, "an absent field keeps the local pause")
    }

    func testAbsorbConflictAdoptsAServerPauseOverALocalRacingSave() throws {
        // The paused person's own device races a profile save against the
        // owner's pause: local-wins must not resurrect their access.
        let pausedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let serverCopy = Participant(displayName: "Grandma", colorHex: "#112233",
                                     role: .logger, pausedAt: pausedAt)
        context.insert(serverCopy)
        try context.save()
        let serverRecord = try outbound(serverCopy.id)

        let receiver = AppModelContainer.make(inMemory: true)
        let localCopy = Participant(id: serverCopy.id, displayName: "Grandma",
                                    colorHex: "#FFEEDD", role: .logger)
        receiver.mainContext.insert(localCopy)
        try receiver.mainContext.save()

        XCTAssertTrue(RecordMapping.absorbConflict(server: serverRecord, in: receiver.mainContext))
        XCTAssertEqual(localCopy.pausedAt, pausedAt, "the owner's pause survives the race")
        XCTAssertEqual(localCopy.colorHex, "#FFEEDD", "local content otherwise wins, as always")
    }

    func testSettingsRoundTrip() throws {
        let firstShift = UUID()
        let original = SharedSettings(targetFeedIntervalMinutes: 150,
                                      ozPresets: [2, 2.5, 5], defaultFeedOz: 5,
                                      sleepLoggingEnabled: false,
                                      nightStartMinute: 21 * 60, nightEndMinute: 7 * 60,
                                      nightFirstFeedMinute: 22 * 60, nightFeedSpacingMinutes: 210,
                                      nightRotation: .none, nightFirstShiftID: firstShift)
        context.insert(original)
        try context.save()

        let receiver = AppModelContainer.make(inMemory: true)
        try RecordMapping.apply(try outbound(original.id), in: receiver.mainContext)

        let copy = try XCTUnwrap(receiver.mainContext.fetch(FetchDescriptor<SharedSettings>()).first)
        XCTAssertEqual(copy.targetFeedIntervalMinutes, 150)
        XCTAssertEqual(copy.ozPresets, [2, 2.5, 5])
        XCTAssertEqual(copy.defaultFeedOz, 5)
        XCTAssertTrue(copy.feedLoggingEnabled)
        XCTAssertTrue(copy.diaperLoggingEnabled)
        XCTAssertFalse(copy.sleepLoggingEnabled, "the paused sleep tracker must travel to the co-parent")
        XCTAssertEqual(copy.nightStartMinute, 21 * 60, "the night window is a shared setting")
        XCTAssertEqual(copy.nightEndMinute, 7 * 60)
        XCTAssertEqual(copy.nightFirstFeedMinute, 22 * 60)
        XCTAssertEqual(copy.nightFeedSpacingMinutes, 210)
        XCTAssertEqual(copy.nightRotation, NightRotation.none,
                       "the rotation pattern is a shared setting")
        XCTAssertEqual(copy.nightFirstShiftID, firstShift,
                       "who takes the first shift is a shared setting")
    }

    /// The household SNOO connection travels on the settings record: present
    /// syncs, empty clears (sign-out anywhere disconnects everyone), absent
    /// (an older build's record) keeps the local copy.
    func testSnooCredentialsTravelClearAndSurviveOldRecords() throws {
        let receiver = AppModelContainer.make(inMemory: true)
        let original = SharedSettings()
        original.snooCredentials = #"{"refreshToken":"rt","email":"t@e.com"}"#
        context.insert(original)
        try context.save()

        try RecordMapping.apply(try outbound(original.id), in: receiver.mainContext)
        let copy = try XCTUnwrap(receiver.mainContext.fetch(FetchDescriptor<SharedSettings>()).first)
        XCTAssertEqual(copy.snooCredentials, original.snooCredentials,
                       "one parent's sign-in must reach the co-parent")

        let old = CKRecord(recordType: SyncConstants.RecordType.settings, recordID: recordID(original.id))
        old["targetFeedIntervalMinutes"] = 120
        try RecordMapping.apply(old, in: receiver.mainContext)
        XCTAssertNotNil(copy.snooCredentials, "an older build's record keeps the connection")

        let cleared = CKRecord(recordType: SyncConstants.RecordType.settings, recordID: recordID(original.id))
        cleared["snooCredentials"] = ""
        try RecordMapping.apply(cleared, in: receiver.mainContext)
        XCTAssertEqual(copy.snooCredentials, "",
                       "an explicit sign-out lands as empty (disconnect), distinct from never-set nil")
    }

    /// Locks the sign-out-is-terminal conflict rule: a device whose pending
    /// settings save races the other parent's SNOO sign-out must adopt the ""
    /// instead of re-uploading the stale token blob it still holds — the old
    /// blanket local-wins policy silently resurrected the connection.
    func testAbsorbConflictAdoptsSnooSignOut() throws {
        let original = SharedSettings()
        original.snooCredentials = #"{"refreshToken":"rt","email":"t@e.com"}"#
        context.insert(original)
        try context.save()

        let server = CKRecord(recordType: SyncConstants.RecordType.settings,
                              recordID: recordID(original.id))
        server["snooCredentials"] = ""
        RecordMapping.absorbConflict(server: server, in: context)
        XCTAssertEqual(original.snooCredentials, "",
                       "a household sign-out must survive a race with a stale settings save")
    }

    /// A sign-in stamped NEWER than the sign-out must survive it: parent A
    /// re-connecting right after parent B signed out is a legitimate new
    /// connection, not a stale blob to tombstone. (A locally-built server
    /// record has no modificationDate, which reads as an ancient sign-out.)
    func testAbsorbConflictKeepsSignInFresherThanTheSignOut() throws {
        let fresh = SnooSharedCredentials(refreshToken: "new", email: "t@e.com",
                                          babyID: nil, signedInAt: .now)
        let original = SharedSettings()
        original.snooCredentials = fresh.jsonString
        context.insert(original)
        try context.save()

        let server = CKRecord(recordType: SyncConstants.RecordType.settings,
                              recordID: recordID(original.id))
        server["snooCredentials"] = ""
        RecordMapping.absorbConflict(server: server, in: context)
        XCTAssertEqual(original.snooCredentials, fresh.jsonString,
                       "a sign-in newer than the sign-out must not be destroyed by it")
    }

    /// Local nil means "this build/row never held the field" — a conflict
    /// during the whole-zone re-fetch heal must ADOPT the server blob, not
    /// re-drop it under local-wins (that re-drop was the healed bug back).
    func testAbsorbConflictAdoptsServerCredentialsOntoLocalNil() throws {
        let original = SharedSettings()
        context.insert(original)
        try context.save()

        let server = CKRecord(recordType: SyncConstants.RecordType.settings,
                              recordID: recordID(original.id))
        server["snooCredentials"] = #"{"refreshToken":"rt","email":"t@e.com"}"#
        RecordMapping.absorbConflict(server: server, in: context)
        XCTAssertEqual(original.snooCredentials, #"{"refreshToken":"rt","email":"t@e.com"}"#,
                       "a re-delivered household connection must survive a pending local save")
    }

    /// The inverse race: a FRESH sign-in racing an older server blob keeps the
    /// local (newer) credentials — only the explicit sign-out is terminal.
    func testAbsorbConflictKeepsFreshSignInOverServerBlob() throws {
        let fresh = #"{"refreshToken":"new","email":"t@e.com"}"#
        let original = SharedSettings()
        original.snooCredentials = fresh
        context.insert(original)
        try context.save()

        let server = CKRecord(recordType: SyncConstants.RecordType.settings,
                              recordID: recordID(original.id))
        server["snooCredentials"] = #"{"refreshToken":"old","email":"t@e.com"}"#
        RecordMapping.absorbConflict(server: server, in: context)
        XCTAssertEqual(original.snooCredentials, fresh,
                       "a re-sign-in racing an older blob must win the conflict")
    }

    /// Clearing the first shift must actually travel: nil is written as an
    /// empty string (CloudKit never transmits an unset key), and an empty
    /// inbound value clears the co-parent's copy — while a record with no
    /// field at all (an older build's) leaves the local choice alone.
    func testFirstShiftClearTravelsButAbsentFieldKeepsLocal() throws {
        let receiver = AppModelContainer.make(inMemory: true)
        let local = SharedSettings(nightFirstShiftID: UUID())
        receiver.mainContext.insert(local)
        try receiver.mainContext.save()

        let old = CKRecord(recordType: SyncConstants.RecordType.settings, recordID: recordID(local.id))
        old["targetFeedIntervalMinutes"] = 120
        try RecordMapping.apply(old, in: receiver.mainContext)
        XCTAssertNotNil(local.nightFirstShiftID, "absent field (older build) keeps the local choice")

        let cleared = CKRecord(recordType: SyncConstants.RecordType.settings, recordID: recordID(local.id))
        cleared["nightFirstShiftID"] = ""
        try RecordMapping.apply(cleared, in: receiver.mainContext)
        XCTAssertNil(local.nightFirstShiftID, "an explicit clear must reach the co-parent")
    }

    /// A settings record written by an app version that predates the nighttime
    /// schedule carries none of its fields — applying it must keep the local
    /// night window, not zero it into a midnight–midnight nothing.
    func testSettingsRecordWithoutNightFieldsKeepsLocalWindow() throws {
        let receiver = AppModelContainer.make(inMemory: true)
        let local = SharedSettings(nightStartMinute: 19 * 60, nightFeedSpacingMinutes: 240)
        receiver.mainContext.insert(local)
        try receiver.mainContext.save()

        let r = CKRecord(recordType: SyncConstants.RecordType.settings, recordID: recordID(local.id))
        r["targetFeedIntervalMinutes"] = 120
        try RecordMapping.apply(r, in: receiver.mainContext)

        let copy = try XCTUnwrap(receiver.mainContext.fetch(FetchDescriptor<SharedSettings>()).first)
        XCTAssertEqual(copy.nightStartMinute, 19 * 60)
        XCTAssertEqual(copy.nightFeedSpacingMinutes, 240)
        XCTAssertEqual(copy.nightRotation, .alternating,
                       "an absent rotation field reads as the default, not a blank")
    }

    /// A settings record written by an app version that predates the tracker
    /// switches carries none of the fields — applying it must leave the local
    /// flags alone (default on), not reset a paused tracker.
    func testSettingsRecordWithoutTrackerFieldsKeepsLocalFlags() throws {
        let receiver = AppModelContainer.make(inMemory: true)
        let local = SharedSettings(diaperLoggingEnabled: false)
        receiver.mainContext.insert(local)
        try receiver.mainContext.save()

        let r = CKRecord(recordType: SyncConstants.RecordType.settings, recordID: recordID(local.id))
        r["targetFeedIntervalMinutes"] = 120
        try RecordMapping.apply(r, in: receiver.mainContext)

        let copy = try XCTUnwrap(receiver.mainContext.fetch(FetchDescriptor<SharedSettings>()).first)
        XCTAssertEqual(copy.targetFeedIntervalMinutes, 120)
        XCTAssertTrue(copy.feedLoggingEnabled)
        XCTAssertFalse(copy.diaperLoggingEnabled, "an absent field must not flip a local tracker back on")
    }

    // MARK: Sync semantics

    /// A record without the fields every real event carries (timestamp, amount,
    /// logger identity) must be skipped, not materialized: the old placeholder
    /// insert minted "0 oz / wet / now / random logger" rows — the "?" ghost
    /// events — from any junk record in the zone.
    func testApplySkipsEventRecordsMissingRequiredFields() throws {
        let receiver = AppModelContainer.make(inMemory: true)

        let bareFeed = CKRecord(recordType: SyncConstants.RecordType.feed, recordID: recordID(UUID()))
        try RecordMapping.apply(bareFeed, in: receiver.mainContext)

        let bareDiaper = CKRecord(recordType: SyncConstants.RecordType.diaper, recordID: recordID(UUID()))
        try RecordMapping.apply(bareDiaper, in: receiver.mainContext)

        let bareSleep = CKRecord(recordType: SyncConstants.RecordType.sleep, recordID: recordID(UUID()))
        try RecordMapping.apply(bareSleep, in: receiver.mainContext)

        XCTAssertTrue(try receiver.mainContext.fetch(FetchDescriptor<FeedEvent>()).isEmpty,
                      "a field-less feed record must not become a 0 oz ghost row")
        XCTAssertTrue(try receiver.mainContext.fetch(FetchDescriptor<DiaperEvent>()).isEmpty)
        XCTAssertTrue(try receiver.mainContext.fetch(FetchDescriptor<SleepEvent>()).isEmpty)
    }

    /// A partially-populated event record (timestamp but no logger identity)
    /// is also refused — attribution is required to materialize.
    func testApplySkipsEventRecordsMissingLoggerIdentity() throws {
        let receiver = AppModelContainer.make(inMemory: true)
        let r = CKRecord(recordType: SyncConstants.RecordType.feed, recordID: recordID(UUID()))
        r["amountOz"] = 3.0
        r["timestamp"] = Date()
        // no loggedByID
        try RecordMapping.apply(r, in: receiver.mainContext)
        XCTAssertTrue(try receiver.mainContext.fetch(FetchDescriptor<FeedEvent>()).isEmpty)
    }

    /// Updates to an EXISTING row keep working even when the incoming record is
    /// sparse (only the changed fields matter once the row exists).
    func testSparseUpdateStillAppliesToExistingRow() throws {
        let receiver = AppModelContainer.make(inMemory: true)
        let existing = FeedEvent(baby: nil, amountOz: 2, timestamp: .now,
                                 loggedByID: UUID(), loggedByName: "T", loggedByColorHex: "#000000")
        receiver.mainContext.insert(existing)
        try receiver.mainContext.save()

        let r = CKRecord(recordType: SyncConstants.RecordType.feed, recordID: recordID(existing.id))
        r["amountOz"] = 4.0
        r["loggedByName"] = "T"
        try RecordMapping.apply(r, in: receiver.mainContext)
        XCTAssertEqual(existing.amountOz, 4)
    }

    func testApplyIsAnUpsertNotAnInsert() throws {
        let original = FeedEvent(baby: nil, amountOz: 2, timestamp: .now,
                                 loggedByID: UUID(), loggedByName: "T", loggedByColorHex: "#000000")
        context.insert(original)
        try context.save()
        let record = try outbound(original.id)

        let receiver = AppModelContainer.make(inMemory: true)
        try RecordMapping.apply(record, in: receiver.mainContext)
        try RecordMapping.apply(record, in: receiver.mainContext)

        XCTAssertEqual(try receiver.mainContext.fetch(FetchDescriptor<FeedEvent>()).count, 1)
    }

    func testSoftDeleteTravelsAsAnUpdate() throws {
        let original = FeedEvent(baby: nil, amountOz: 2, timestamp: .now,
                                 loggedByID: UUID(), loggedByName: "T", loggedByColorHex: "#000000")
        context.insert(original)
        try context.save()

        let receiver = AppModelContainer.make(inMemory: true)
        try RecordMapping.apply(try outbound(original.id), in: receiver.mainContext)

        // The co-parent soft-deletes; the change syncs as a deletedAt update.
        original.deletedAt = .now
        try context.save()
        try RecordMapping.apply(try outbound(original.id), in: receiver.mainContext)

        let feeds = try receiver.mainContext.fetch(FetchDescriptor<FeedEvent>())
        XCTAssertEqual(feeds.count, 1)
        XCTAssertNotNil(feeds.first?.deletedAt)
    }

    func testHardDeleteRemovesLocalModel() throws {
        let original = DiaperEvent(baby: nil, type: .wet, timestamp: .now,
                                   loggedByID: UUID(), loggedByName: "T", loggedByColorHex: "#000000")
        context.insert(original)
        try context.save()

        try RecordMapping.delete(recordName: original.id.uuidString, in: context)
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
        try RecordMapping.apply(try outbound(feed.id), in: receiver.mainContext)
        XCTAssertNil(try XCTUnwrap(receiver.mainContext.fetch(FetchDescriptor<FeedEvent>()).first).baby)

        try RecordMapping.apply(try outbound(baby.id), in: receiver.mainContext)
        RecordMapping.relinkOrphanEvents(in: receiver.mainContext)

        let copy = try XCTUnwrap(receiver.mainContext.fetch(FetchDescriptor<FeedEvent>()).first)
        XCTAssertEqual(copy.baby?.id, baby.id,
                       "events fetched before their Baby record must attach once it lands")
    }

    // MARK: Schedule plan (PlanSlot / PlanOverride)

    func testPlanSlotRoundTrip() throws {
        let assignee = UUID()
        let original = PlanSlot(kind: .feed, minuteOfDay: 1380,
                                assignedToID: assignee, assignedToName: "Katie",
                                assignedToColorHex: "#FF8FA3")
        context.insert(original)
        try context.save()

        let receiver = AppModelContainer.make(inMemory: true)
        try RecordMapping.apply(try outbound(original.id), in: receiver.mainContext)

        let copy = try XCTUnwrap(receiver.mainContext.fetch(FetchDescriptor<PlanSlot>()).first)
        XCTAssertEqual(copy.id, original.id)
        XCTAssertEqual(copy.kind, .feed)
        XCTAssertEqual(copy.minuteOfDay, 1380)
        XCTAssertEqual(copy.assignedToID, assignee)
        XCTAssertEqual(copy.assignedToName, "Katie")
        XCTAssertEqual(copy.assignedToColorHex, "#FF8FA3")
        XCTAssertEqual(copy.createdAt, original.createdAt)
        XCTAssertNil(copy.deletedAt)
    }

    func testSleepWindowSlotRoundTripKeepsEndMinute() throws {
        let assignee = UUID()
        let original = PlanSlot(kind: .sleep, minuteOfDay: 22 * 60, endMinuteOfDay: 5 * 60,
                                assignedToID: assignee, assignedToName: "Katie",
                                assignedToColorHex: "#FF8FA3")
        context.insert(original)
        try context.save()

        let receiver = AppModelContainer.make(inMemory: true)
        try RecordMapping.apply(try outbound(original.id), in: receiver.mainContext)

        let copy = try XCTUnwrap(receiver.mainContext.fetch(FetchDescriptor<PlanSlot>()).first)
        XCTAssertEqual(copy.endMinuteOfDay, 5 * 60)
        XCTAssertEqual(copy.windowDurationMinutes, 7 * 60, "22:00–05:00 wraps to a 7h window")
    }

    func testLegacyPlanSlotRecordDecodesWithNilEndMinute() throws {
        // A record from a build that predates sleep windows carries no
        // endMinuteOfDay field — it must land as a legacy instant, not crash
        // or invent a window.
        let original = PlanSlot(kind: .sleep, minuteOfDay: 20 * 60, endMinuteOfDay: 3 * 60)
        context.insert(original)
        try context.save()
        let record = try outbound(original.id)
        record["endMinuteOfDay"] = nil

        let receiver = AppModelContainer.make(inMemory: true)
        try RecordMapping.apply(record, in: receiver.mainContext)

        let copy = try XCTUnwrap(receiver.mainContext.fetch(FetchDescriptor<PlanSlot>()).first)
        XCTAssertNil(copy.endMinuteOfDay)
        XCTAssertNil(copy.windowDurationMinutes)
    }

    func testUnassignedPlanSlotRoundTripStaysUnassigned() throws {
        let original = PlanSlot(kind: .sleep, minuteOfDay: 1170)
        context.insert(original)
        try context.save()

        let receiver = AppModelContainer.make(inMemory: true)
        try RecordMapping.apply(try outbound(original.id), in: receiver.mainContext)

        let copy = try XCTUnwrap(receiver.mainContext.fetch(FetchDescriptor<PlanSlot>()).first)
        XCTAssertEqual(copy.kind, .sleep)
        XCTAssertNil(copy.assignedToID, "unassigned must not become someone on the other phone")
        XCTAssertEqual(copy.assignedToName, "")
    }

    func testPlanOverrideRoundTrip() throws {
        let original = PlanOverride(slotID: UUID(), dayKey: 20_260_722,
                                    assignedToID: UUID(), assignedToName: "Taylor",
                                    assignedToColorHex: "#5AC8B8", isSkipped: false,
                                    minuteOfDayOverride: 23 * 60 + 30,
                                    createdByID: UUID())
        context.insert(original)
        try context.save()

        let receiver = AppModelContainer.make(inMemory: true)
        try RecordMapping.apply(try outbound(original.id), in: receiver.mainContext)

        let copy = try XCTUnwrap(receiver.mainContext.fetch(FetchDescriptor<PlanOverride>()).first)
        XCTAssertEqual(copy.slotID, original.slotID)
        XCTAssertEqual(copy.dayKey, 20_260_722)
        XCTAssertEqual(copy.assignedToID, original.assignedToID)
        XCTAssertEqual(copy.assignedToName, "Taylor")
        XCTAssertFalse(copy.isSkipped)
        XCTAssertEqual(copy.minuteOfDayOverride, 23 * 60 + 30, "a tonight-move travels with the override")
        XCTAssertEqual(copy.createdByID, original.createdByID)
    }

    func testSkipOverrideRoundTripStaysSkipped() throws {
        let original = PlanOverride(slotID: UUID(), dayKey: 20_260_722,
                                    isSkipped: true, createdByID: UUID())
        context.insert(original)
        try context.save()

        let receiver = AppModelContainer.make(inMemory: true)
        try RecordMapping.apply(try outbound(original.id), in: receiver.mainContext)

        let copy = try XCTUnwrap(receiver.mainContext.fetch(FetchDescriptor<PlanOverride>()).first)
        XCTAssertTrue(copy.isSkipped, "a skipped night must stay skipped on the other phone")
        XCTAssertNil(copy.assignedToID)
    }

    /// Locks the `absorbConflict` generalization: a slot the other parent
    /// deleted must not be resurrected by this device's concurrent edit.
    func testPlanSlotConflictServerDeleteWins() throws {
        let slot = PlanSlot(kind: .feed, minuteOfDay: 1380, assignedToName: "Katie")
        context.insert(slot)
        try context.save()

        let server = CKRecord(recordType: SyncConstants.RecordType.planSlot, recordID: recordID(slot.id))
        let deletedAt = Date(timeIntervalSince1970: 1_700_000_000)
        server["deletedAt"] = deletedAt

        RecordMapping.absorbConflict(server: server, in: context)

        XCTAssertEqual(slot.deletedAt, deletedAt,
                       "a concurrently deleted slot must never be resurrected by the race loser")
        XCTAssertNotNil(slot.ckSystemFields, "the server change tag is adopted so the re-save succeeds")
    }

    /// Documents the chosen policy for concurrent slot edits: last writer wins
    /// on content — the local (about-to-re-upload) assignment survives.
    func testPlanSlotConflictLocalAssignmentWins() throws {
        let mine = UUID()
        let slot = PlanSlot(kind: .feed, minuteOfDay: 1380,
                            assignedToID: mine, assignedToName: "Taylor",
                            assignedToColorHex: "#5AC8B8")
        context.insert(slot)
        try context.save()

        let server = CKRecord(recordType: SyncConstants.RecordType.planSlot, recordID: recordID(slot.id))
        server["assignedToID"] = UUID().uuidString
        server["assignedToName"] = "Katie"

        RecordMapping.absorbConflict(server: server, in: context)

        XCTAssertEqual(slot.assignedToID, mine,
                       "local content wins the conflict (it re-uploads next)")
        XCTAssertEqual(slot.assignedToName, "Taylor")
    }
}
