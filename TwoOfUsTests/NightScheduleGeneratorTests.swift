import XCTest
@testable import TwoOfUs

/// Pure-logic tests for `NightScheduleGenerator`: the "first feed + spacing
/// until the window closes" math, midnight wrapping, clamping of nonsense
/// input, and the alternating-assignment default.
final class NightScheduleGeneratorTests: XCTestCase {
    private func minutes(start: Int, end: Int, first: Int, spacing: Int) -> [Int] {
        NightScheduleGenerator.feedMinutes(
            nightStartMinute: start, nightEndMinute: end,
            firstFeedMinute: first, spacingMinutes: spacing
        )
    }

    // MARK: Feed times

    func testSpecExampleNineToFiveEveryFourHours() {
        // Night 8pm–8am, first feed 9pm, every 4h → 9pm, 1am, 5am. The next
        // step (9am) falls past the window's end and must not generate.
        XCTAssertEqual(
            minutes(start: 20 * 60, end: 8 * 60, first: 21 * 60, spacing: 240),
            [21 * 60, 1 * 60, 5 * 60]
        )
    }

    func testFeedLandingExactlyAtNightEndIsIncluded() {
        // Night 8pm–9am: the 9am feed sits exactly on the window's edge — a
        // parent reading "night ends at 9" expects it.
        XCTAssertEqual(
            minutes(start: 20 * 60, end: 9 * 60, first: 21 * 60, spacing: 240),
            [21 * 60, 1 * 60, 5 * 60, 9 * 60]
        )
    }

    func testHalfHourSpacingWrapsMidnight() {
        XCTAssertEqual(
            minutes(start: 22 * 60, end: 6 * 60, first: 23 * 60, spacing: 210),
            [23 * 60, 2 * 60 + 30, 6 * 60]
        )
    }

    func testFirstFeedOutsideWindowSnapsToNightStart() {
        // A 2pm first feed is daytime nonsense — generation restarts from
        // night start rather than producing an afternoon schedule.
        XCTAssertEqual(
            minutes(start: 20 * 60, end: 8 * 60, first: 14 * 60, spacing: 240),
            [20 * 60, 0, 4 * 60, 8 * 60]
        )
    }

    func testZeroLengthWindowGeneratesNothing() {
        XCTAssertTrue(minutes(start: 20 * 60, end: 20 * 60, first: 21 * 60, spacing: 180).isEmpty)
    }

    func testGarbageSpacingGeneratesNothing() {
        XCTAssertTrue(minutes(start: 20 * 60, end: 8 * 60, first: 21 * 60, spacing: 0).isEmpty,
                      "a corrupt spacing must not loop the generator around the clock")
        XCTAssertTrue(minutes(start: 20 * 60, end: 8 * 60, first: 21 * 60, spacing: -60).isEmpty)
    }

    func testSlotCountIsCapped() {
        let all = minutes(start: 20 * 60, end: 19 * 60, first: 20 * 60, spacing: 60)
        XCTAssertLessThanOrEqual(all.count, NightScheduleGenerator.maxSlots)
    }

    // MARK: Window membership

    func testIsWithinNightWrapsMidnight() {
        XCTAssertTrue(NightScheduleGenerator.isWithinNight(
            minuteOfDay: 2 * 60, nightStartMinute: 20 * 60, nightEndMinute: 8 * 60))
        XCTAssertTrue(NightScheduleGenerator.isWithinNight(
            minuteOfDay: 20 * 60, nightStartMinute: 20 * 60, nightEndMinute: 8 * 60))
        XCTAssertTrue(NightScheduleGenerator.isWithinNight(
            minuteOfDay: 8 * 60, nightStartMinute: 20 * 60, nightEndMinute: 8 * 60))
        XCTAssertFalse(NightScheduleGenerator.isWithinNight(
            minuteOfDay: 14 * 60, nightStartMinute: 20 * 60, nightEndMinute: 8 * 60))
    }

    // MARK: Alternation

    func testAlternatesBetweenTwoParents() {
        let parents = ["Taylor", "Katie"]
        let picks = (0..<4).map { NightScheduleGenerator.alternatingAssignee(index: $0, parents: parents) }
        XCTAssertEqual(picks, ["Taylor", "Katie", "Taylor", "Katie"])
    }

    func testSoloParentGetsNoDefaultAssignment() {
        // With one parent there's no rotation — slots stay unassigned, which
        // (by the routing rule) rings every phone rather than pinning one
        // parent to every single night feed by default.
        XCTAssertNil(NightScheduleGenerator.alternatingAssignee(index: 0, parents: ["Taylor"]))
        XCTAssertNil(NightScheduleGenerator.alternatingAssignee(index: 1, parents: [String]()))
    }
}
