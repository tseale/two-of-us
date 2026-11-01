import XCTest
import SwiftData
import CloudKit
@testable import TwoOfUs

/// Fresh-install restore: a new phone signed into the same iCloud account
/// must find its family instead of offering owner onboarding (a duplicate
/// baby) or, for the co-parent, acting like a brand-new user.
@MainActor
final class CloudRestorePlanTests: XCTestCase {
    private var container: ModelContainer!

    override func setUp() {
        super.setUp()
        container = AppModelContainer.make(inMemory: true)
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    private func zone(owner: String, name: String = SyncConstants.zoneName) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: name, ownerName: owner)
    }

    // MARK: shouldCheck

    func testOnlyAFreshInstallChecks() {
        XCTAssertTrue(CloudRestorePlan.shouldCheck(role: .solo, myParticipantID: nil, demoMode: false))
        // Finished onboarding or a join leaves an identity behind.
        XCTAssertFalse(CloudRestorePlan.shouldCheck(role: .solo, myParticipantID: UUID(), demoMode: false))
        // An accepted share (even mid-join) is already routed by the join flow.
        XCTAssertFalse(CloudRestorePlan.shouldCheck(role: .participant, myParticipantID: nil, demoMode: false))
        XCTAssertFalse(CloudRestorePlan.shouldCheck(role: .owner, myParticipantID: nil, demoMode: false))
        XCTAssertFalse(CloudRestorePlan.shouldCheck(role: .solo, myParticipantID: nil, demoMode: true))
    }

    // MARK: decide

    func testAcceptedShareWinsOverPrivateFamily() {
        let shared = zone(owner: "_owner")
        XCTAssertEqual(CloudRestorePlan.decide(sharedZones: [shared], privateHasBaby: true), .joined(shared))
        XCTAssertEqual(CloudRestorePlan.decide(sharedZones: [shared], privateHasBaby: false), .joined(shared))
    }

    func testPrivateBabyMeansOwned() {
        XCTAssertEqual(CloudRestorePlan.decide(sharedZones: [], privateHasBaby: true), .owned)
    }

    func testNothingFoundMeansOnboarding() {
        XCTAssertEqual(CloudRestorePlan.decide(sharedZones: [], privateHasBaby: false), .nothingFound)
    }

    func testForeignSharedZonesAreIgnored() {
        let other = zone(owner: "_owner", name: "SomeOtherAppZone")
        XCTAssertEqual(CloudRestorePlan.decide(sharedZones: [other], privateHasBaby: false), .nothingFound)
        XCTAssertEqual(CloudRestorePlan.decide(sharedZones: [other], privateHasBaby: true), .owned)
    }

    func testTwoHouseholdsAreAmbiguous() {
        let zones = [zone(owner: "_a"), zone(owner: "_b")]
        XCTAssertEqual(CloudRestorePlan.decide(sharedZones: zones, privateHasBaby: true), .nothingFound,
                       "never guess a household — the invite link decides")
    }

    // MARK: blocksRouting

    func testCheckingBlocksOnlyAnEmptyStore() {
        XCTAssertTrue(CloudRestorePlan.blocksRouting(phase: .checking, hasBaby: false))
        XCTAssertFalse(CloudRestorePlan.blocksRouting(phase: .checking, hasBaby: true))
    }

    func testRestoringBlocksUntilIdentityIsAdopted() {
        // The baby lands before the fetch (and identity adoption) finishes.
        XCTAssertTrue(CloudRestorePlan.blocksRouting(phase: .restoring(.owner), hasBaby: true))
        XCTAssertTrue(CloudRestorePlan.blocksRouting(phase: .restoring(.coParent), hasBaby: true))
        XCTAssertTrue(CloudRestorePlan.blocksRouting(phase: .restoring(.owner), hasBaby: false))
    }

    func testFinishedNeverBlocks() {
        XCTAssertFalse(CloudRestorePlan.blocksRouting(phase: .finished, hasBaby: false))
        XCTAssertFalse(CloudRestorePlan.blocksRouting(phase: .finished, hasBaby: true))
    }

    // MARK: ownerIdentity

    private func participant(_ name: String, cloudUserID: String?, role: ParticipantRole = .full,
                             active: Bool = true) -> Participant {
        let p = Participant(displayName: name, colorHex: "5AC8B8", role: role)
        p.cloudUserID = cloudUserID
        p.isActive = active
        container.mainContext.insert(p)
        return p
    }

    func testStampedMatchWins() {
        let owner = participant("Taylor", cloudUserID: "_me")
        _ = participant("Co-parent", cloudUserID: "_coparent")
        _ = participant("Legacy", cloudUserID: nil)
        XCTAssertEqual(CloudRestorePlan.ownerIdentity(among: [owner], myCloudUserID: "_me")?.id, owner.id)
        let all = (try? container.mainContext.fetch(FetchDescriptor<Participant>())) ?? []
        XCTAssertEqual(CloudRestorePlan.ownerIdentity(among: all, myCloudUserID: "_me")?.id, owner.id)
    }

    func testSingleUnstampedFullRowIsTheLegacyOwner() {
        let owner = participant("Taylor", cloudUserID: nil)
        let coParent = participant("Co-parent", cloudUserID: "_coparent")
        let guest = participant("Grandma", cloudUserID: nil, role: .logger)
        XCTAssertEqual(CloudRestorePlan.ownerIdentity(among: [owner, coParent, guest], myCloudUserID: "_me")?.id,
                       owner.id)
    }

    func testTwoUnstampedFullRowsAreAmbiguous() {
        let a = participant("Taylor", cloudUserID: nil)
        let b = participant("Co-parent", cloudUserID: nil)
        XCTAssertNil(CloudRestorePlan.ownerIdentity(among: [a, b], myCloudUserID: "_me"))
    }

    func testInactiveRowsAreNeverAdopted() {
        let merged = participant("Taylor (old)", cloudUserID: "_me", active: false)
        XCTAssertNil(CloudRestorePlan.ownerIdentity(among: [merged], myCloudUserID: "_me"))
    }

    // MARK: isTransient

    func testNetworkErrorsAreTransient() {
        XCTAssertTrue(CloudRestorePlan.isTransient(CKError(.networkUnavailable)))
        XCTAssertTrue(CloudRestorePlan.isTransient(CKError(.notAuthenticated)))
        XCTAssertFalse(CloudRestorePlan.isTransient(CKError(.unknownItem)))
        XCTAssertFalse(CloudRestorePlan.isTransient(URLError(.badURL)))
    }
}
