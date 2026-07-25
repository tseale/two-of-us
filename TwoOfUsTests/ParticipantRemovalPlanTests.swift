import XCTest
@testable import TwoOfUs

/// The decision table for removing a person from the household — who gets
/// removed from the CKShare vs. which app records just get purged. The stakes:
/// removing the wrong share member kicks the real co-parent out of the shared
/// log, and an unmatchable record must clean itself up instead of stranding an
/// unremovable "?" row (the ghost-participant bug).
@MainActor
final class ParticipantRemovalPlanTests: XCTestCase {

    func testMatchesShareMemberByCloudUserID() {
        XCTAssertEqual(
            SyncManager.removalPlan(cloudUserID: "_katie",
                                    shareMemberIDs: ["_pending", "_katie"],
                                    isSoleCoParticipant: false),
            .removeShareMember(index: 1)
        )
    }

    func testGhostRecordNeverKicksTheSoleRealMemberOffTheShare() {
        // The ghost bug: a leaked participant record (nil cloudUserID) being
        // removed while the real co-parent is the share's only non-owner
        // member. The old fallback removed HER; the plan must purge the ghost
        // record only.
        XCTAssertEqual(
            SyncManager.removalPlan(cloudUserID: nil,
                                    shareMemberIDs: ["_katie"],
                                    isSoleCoParticipant: false),
            .purgeRecordOnly
        )
    }

    func testNilIdentityNeverMatchesNilMemberID() {
        // A pending invitee can have a nil userRecordID; a ghost has a nil
        // cloudUserID. nil == nil must not count as an identity match.
        XCTAssertEqual(
            SyncManager.removalPlan(cloudUserID: nil,
                                    shareMemberIDs: [nil, "_katie"],
                                    isSoleCoParticipant: false),
            .purgeRecordOnly
        )
    }

    func testLegacySoleCoParentFallbackStillWorks() {
        // Identity never captured, exactly one member on the share, exactly one
        // other active participant locally — both sides agree who this is.
        XCTAssertEqual(
            SyncManager.removalPlan(cloudUserID: nil,
                                    shareMemberIDs: ["_katie"],
                                    isSoleCoParticipant: true),
            .removeShareMember(index: 0)
        )
    }

    func testAmbiguousShareMembershipRefusesTheFallback() {
        // Two share members (co-parent + pending invite): even the sole local
        // co-participant can't be attributed safely — never guess on the share.
        XCTAssertEqual(
            SyncManager.removalPlan(cloudUserID: nil,
                                    shareMemberIDs: ["_katie", nil],
                                    isSoleCoParticipant: true),
            .purgeRecordOnly
        )
    }

    // MARK: shareHasMember (the Resend-link membership gate)

    func testResendRequiresCurrentShareMembership() {
        // On the share → the standing URL works, resend it.
        XCTAssertTrue(SyncManager.shareHasMember(cloudUserID: "_katie",
                                                 memberIDs: [nil, "_katie"]))
        // Off the share (removed / sharing reset) → the URL dead-ends with
        // "Item Unavailable" on their phone; the flow must re-add instead.
        XCTAssertFalse(SyncManager.shareHasMember(cloudUserID: "_katie",
                                                  memberIDs: ["_someoneElse"]))
        XCTAssertFalse(SyncManager.shareHasMember(cloudUserID: "_katie", memberIDs: []))
        // Unknown identity never matches — nil == nil is not membership.
        XCTAssertFalse(SyncManager.shareHasMember(cloudUserID: nil, memberIDs: [nil, "_katie"]))
    }

    func testAlreadyLeftMemberCleansUpTheRecord() {
        // cloudUserID known but no longer on the share — they left on their
        // own. Finish the removal instead of throwing and stranding the row.
        XCTAssertEqual(
            SyncManager.removalPlan(cloudUserID: "_gone",
                                    shareMemberIDs: ["_katie"],
                                    isSoleCoParticipant: false),
            .purgeRecordOnly
        )
    }
}
