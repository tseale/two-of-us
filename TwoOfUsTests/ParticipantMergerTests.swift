import XCTest
import SwiftData
@testable import TwoOfUs

/// `ParticipantMerger` collapses duplicate People rows for the same iCloud
/// account (a re-join creates a fresh row and strands the old one). These
/// tests pin the survivor rule, what the survivor absorbs, and that every
/// reference — events, plan slots, overrides — follows the merge.
@MainActor
final class ParticipantMergerTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() {
        super.setUp()
        container = AppModelContainer.make(inMemory: true)
        context = container.mainContext
    }

    override func tearDown() {
        context = nil
        container = nil
        super.tearDown()
    }

    private func participant(_ name: String, cloudUserID: String? = nil,
                             role: ParticipantRole = .full, isActive: Bool = true,
                             invitedAt: Date = .now, photo: Data? = nil) -> Participant {
        let p = Participant(displayName: name, colorHex: "#AABBCC", role: role,
                            cloudUserID: cloudUserID, isActive: isActive, invitedAt: invitedAt)
        p.photoData = photo
        context.insert(p)
        return p
    }

    private func feed(by p: Participant) -> FeedEvent {
        let f = FeedEvent(baby: nil, amountOz: 3, timestamp: .now, loggedByID: p.id,
                          loggedByName: p.displayName, loggedByColorHex: p.colorHex)
        context.insert(f)
        return f
    }

    // MARK: Auto-merge by cloudUserID

    func testMergesActiveRowsSharingCloudUserID() throws {
        let old = participant("Girl Taylor", cloudUserID: "_wife",
                              invitedAt: .now.addingTimeInterval(-86_400),
                              photo: Data([1, 2, 3]))
        let new = participant("GT", cloudUserID: "_wife")
        let event = feed(by: old)
        try context.save()

        let changed = ParticipantMerger.mergeDuplicates(in: context)

        XCTAssertTrue(new.isActive, "the newest join survives")
        XCTAssertFalse(old.isActive, "the stale row deactivates")
        XCTAssertEqual(event.loggedByID, new.id, "history moves to the survivor")
        XCTAssertEqual(event.loggedByName, "GT", "denormalized identity is rewritten too")
        XCTAssertEqual(new.photoData, Data([1, 2, 3]), "the survivor absorbs the old photo when it has none")
        XCTAssertTrue(changed.contains(event.id), "rewritten events are reported for sync")
        XCTAssertTrue(changed.contains(old.id) && changed.contains(new.id))
    }

    func testDistinctAccountsAreNotMerged() throws {
        let wife = participant("GT", cloudUserID: "_wife")
        let grandma = participant("Grandma", cloudUserID: "_grandma")
        try context.save()

        XCTAssertTrue(ParticipantMerger.mergeDuplicates(in: context).isEmpty)
        XCTAssertTrue(wife.isActive)
        XCTAssertTrue(grandma.isActive)
    }

    func testNilCloudUserIDIsNeverAutoMerged() throws {
        // A row that predates identity capture could be anyone — only the
        // explicit Settings merge may claim it.
        _ = participant("Girl Taylor", cloudUserID: nil)
        _ = participant("GT", cloudUserID: "_wife")
        try context.save()

        XCTAssertTrue(ParticipantMerger.mergeDuplicates(in: context).isEmpty)
        XCTAssertEqual((try context.fetch(FetchDescriptor<Participant>())).filter(\.isActive).count, 2)
    }

    func testMergeNeverDemotesRole() throws {
        let old = participant("GT", cloudUserID: "_wife", role: .full,
                              invitedAt: .now.addingTimeInterval(-86_400))
        let new = participant("GT", cloudUserID: "_wife", role: .logger)
        try context.save()

        ParticipantMerger.mergeDuplicates(in: context)

        XCTAssertFalse(old.isActive)
        XCTAssertEqual(new.role, .full, "merging two rows of one person must keep the stronger role")
    }

    func testStragglerEventsReattachToSurvivor() throws {
        // A write from the other phone can land AFTER its row was merged away —
        // the next pass re-attaches it to the account's live row.
        let tombstone = participant("Girl Taylor", cloudUserID: "_wife", isActive: false)
        let survivor = participant("GT", cloudUserID: "_wife")
        let straggler = feed(by: tombstone)
        try context.save()

        let changed = ParticipantMerger.mergeDuplicates(in: context)

        XCTAssertEqual(straggler.loggedByID, survivor.id)
        XCTAssertTrue(changed.contains(straggler.id))
    }

    func testPlanAssignmentsFollowTheMerge() throws {
        let old = participant("Girl Taylor", cloudUserID: "_wife",
                              invitedAt: .now.addingTimeInterval(-86_400))
        let new = participant("GT", cloudUserID: "_wife")
        let slot = PlanSlot(kind: .feed, minuteOfDay: 23 * 60, assignedToID: old.id,
                            assignedToName: old.displayName, assignedToColorHex: old.colorHex)
        context.insert(slot)
        let override = PlanOverride(slotID: slot.id, dayKey: 20_260_726,
                                    assignedToID: old.id, createdByID: old.id)
        context.insert(override)
        try context.save()

        ParticipantMerger.mergeDuplicates(in: context)

        XCTAssertEqual(slot.assignedToID, new.id, "the 11pm slot stays hers under the surviving row")
        XCTAssertEqual(slot.assignedToName, "GT")
        XCTAssertEqual(override.assignedToID, new.id)
        XCTAssertEqual(override.createdByID, new.id)
    }

    // MARK: Manual merge (legacy rows without a captured identity)

    func testManualMergeClaimsALegacyRow() throws {
        let legacy = participant("Girl Taylor", cloudUserID: nil, photo: Data([9]))
        let current = participant("GT", cloudUserID: "_wife")
        let event = feed(by: legacy)
        try context.save()

        let changed = ParticipantMerger.merge(legacy, into: current, in: context)

        XCTAssertFalse(legacy.isActive)
        XCTAssertEqual(event.loggedByID, current.id)
        XCTAssertEqual(current.photoData, Data([9]))
        XCTAssertFalse(changed.isEmpty)
    }

    func testManualMergeAbsorbsCloudUserID() throws {
        // Reverse direction: the duplicate is the one that captured its id.
        let captured = participant("GT", cloudUserID: "_wife")
        let survivor = participant("Girl Taylor", cloudUserID: nil)
        try context.save()

        ParticipantMerger.merge(captured, into: survivor, in: context)

        XCTAssertEqual(survivor.cloudUserID, "_wife",
                       "the surviving row inherits the iCloud identity so future auto-merges work")
    }

    func testMergingARowIntoItselfIsANoOp() throws {
        let p = participant("GT", cloudUserID: "_wife")
        try context.save()

        XCTAssertTrue(ParticipantMerger.merge(p, into: p, in: context).isEmpty)
        XCTAssertTrue(p.isActive)
    }

    func testPauseSurvivesTheMergeOnTheLiveRow() throws {
        // Merging away a paused duplicate must move the pause to the survivor:
        // left on the tombstone, the Resume button vanishes from the People
        // list while the pause itself lives on.
        let old = participant("Grandma", cloudUserID: "_gma",
                              invitedAt: .now.addingTimeInterval(-86_400))
        old.pausedAt = .now
        let new = participant("Gran", cloudUserID: "_gma")
        try context.save()

        ParticipantMerger.mergeDuplicates(in: context)

        XCTAssertFalse(old.isActive)
        XCTAssertNil(old.pausedAt, "the tombstone must not keep a stale pause")
        XCTAssertTrue(new.isPaused, "the pause follows the person onto the live row")
    }
}
