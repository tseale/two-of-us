import XCTest
import SwiftData
@testable import TwoOfUs

/// Why the watch couldn't log.
///
/// The watch has no onboarding, so unlike the phone it never sets
/// `sync.myParticipantID` directly — `WatchSyncManager.resolveIdentityIfNeeded`
/// is its ONLY path to an identity, and that path matches this device's iCloud
/// user record name against `Participant.cloudUserID`. A row whose
/// `cloudUserID` is nil can never be matched.
///
/// Owner rows created before 2026-07-29 have exactly that nil: `cloudUserID`
/// arrived with the rename (2026-06-09), joiners started being stamped on
/// 2026-06-12 (JoinFlowView), but the OWNER only started being stamped when
/// `SeedData` gained its `captureCloudUserID(for: owner.id)` call — and SeedData
/// runs once, at first onboarding. An owner who onboarded before that date is
/// never stamped by anything.
///
/// The phone doesn't care (its identity was written straight to LocalPrefs at
/// seed time), so this stayed invisible until the watch shipped and became the
/// first surface that depends solely on the `cloudUserID` match.
@MainActor
final class WatchIdentityTests: XCTestCase {
    private var container: ModelContainer!
    private var savedIdentity: String??

    private static let identityKey = "sync.myParticipantID"

    override func setUp() {
        super.setUp()
        // The watch resolves identity into the shared suite; snapshot whatever
        // this machine really has so the tests can't corrupt it.
        savedIdentity = AppGroup.userDefaults?.string(forKey: Self.identityKey)
        AppGroup.userDefaults?.removeObject(forKey: Self.identityKey)
        container = AppModelContainer.make(inMemory: true)
    }

    override func tearDown() {
        if let saved = savedIdentity, let d = AppGroup.userDefaults {
            if let saved { d.set(saved, forKey: Self.identityKey) }
            else { d.removeObject(forKey: Self.identityKey) }
        }
        container = nil
        super.tearDown()
    }

    /// Two parents, an owner row that predates stamping, and no stored identity
    /// — the exact state a watch boots into. Every write must refuse, which is
    /// the "Couldn't log — try from the phone" the watch was showing.
    private func makeTwoParentFamily() -> (owner: Participant, coParent: Participant) {
        let ctx = container.mainContext
        ctx.insert(Baby(name: "Miller", dateOfBirth: .now))
        let owner = Participant(displayName: "Taylor", colorHex: "5AC8B8", role: .full)
        owner.cloudUserID = nil                 // never stamped — the bug
        let coParent = Participant(displayName: "Taylor", colorHex: "8E8EFF", role: .full)
        coParent.cloudUserID = "_coparent_record_name"
        ctx.insert(owner)
        ctx.insert(coParent)
        try? ctx.save()
        return (owner, coParent)
    }

    // MARK: The symptom

    func testWatchCannotLogWhenOwnerRowWasNeverStamped() throws {
        _ = makeTwoParentFamily()
        let logger = QuickLogger(context: container.mainContext)

        XCTAssertNil(logger.logFeed(amountOz: 4),
                     "no resolvable identity → the feed must be refused, not misattributed")
        XCTAssertNil(logger.logDiaper(.wet))
        XCTAssertNil(logger.toggleSleep(),
                     "starting a sleep needs an owner to attribute it to")

        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<FeedEvent>()).isEmpty,
                      "a refused write must persist nothing")
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<DiaperEvent>()).isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<SleepEvent>()).isEmpty)
    }

    /// Refusing is correct here — with two active parents there is no safe guess,
    /// and misattributing shows the wrong face on BOTH phones. The sole-parent
    /// fallback is what made this invisible in the `-watchDemoData` seed, which
    /// has only one participant.
    func testSoleParentStillResolvesWithoutStamping() throws {
        let ctx = container.mainContext
        ctx.insert(Baby(name: "Miller", dateOfBirth: .now))
        ctx.insert(Participant(displayName: "Taylor", colorHex: "5AC8B8", role: .full))
        try? ctx.save()

        XCTAssertNotNil(QuickLogger(context: ctx).logFeed(amountOz: 4),
                        "one unambiguous active participant is still safe to attribute to")
    }

    // MARK: The fix

    /// Once the owner row carries this device's record name, the watch's
    /// resolution finds it and writes are attributed to the right parent.
    func testStampedOwnerRowResolvesAndAttributesCorrectly() throws {
        guard let defaults = AppGroup.userDefaults else {
            throw XCTSkip("App Group suite unavailable in this test host")
        }
        let (owner, _) = makeTwoParentFamily()
        owner.cloudUserID = "_my_record_name"
        try? container.mainContext.save()

        // What WatchSyncManager.resolveIdentityIfNeeded does with the match.
        let resolved = try XCTUnwrap(
            SyncManager.participantMatching(cloudUserID: "_my_record_name",
                                            in: container.mainContext),
            "the stamped row must be findable by this device's iCloud record name")
        XCTAssertEqual(resolved.id, owner.id)
        defaults.set(resolved.id.uuidString, forKey: Self.identityKey)

        let feed = try XCTUnwrap(QuickLogger(context: container.mainContext).logFeed(amountOz: 4),
                                 "with an identity resolved the watch can log again")
        XCTAssertEqual(feed.loggedByID, owner.id, "attributed to the watch's own parent")
        XCTAssertEqual(feed.loggedByName, "Taylor")
    }

    /// The back-fill's decision, isolated: only an active row that this device
    /// already claims as "me" and that carries no stamp may be stamped.
    func testBackfillOnlyTargetsAnUnstampedRowThisDeviceClaims() throws {
        let (owner, coParent) = makeTwoParentFamily()

        XCTAssertTrue(SyncManager.needsCloudUserIDBackfill(owner),
                      "unstamped active row this device claims → back-fill it")
        XCTAssertFalse(SyncManager.needsCloudUserIDBackfill(coParent),
                       "already stamped → leave it alone")

        owner.cloudUserID = "_my_record_name"
        XCTAssertFalse(SyncManager.needsCloudUserIDBackfill(owner),
                       "back-fill must be idempotent — never re-stamp")

        let retired = Participant(displayName: "Sitter", colorHex: "F5B971", role: .full)
        retired.isActive = false
        XCTAssertFalse(SyncManager.needsCloudUserIDBackfill(retired),
                       "a retired row is not this device's identity")
    }
}
