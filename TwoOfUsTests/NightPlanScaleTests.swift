import XCTest
@testable import TwoOfUs

/// The plan drawn to scale on Nighttime's spread page: the night window as a
/// ruler, each parent's standing window clipped to it, the rows they share
/// and the hour marks under them.
final class NightPlanScaleTests: XCTestCase {
    private let taylor = UUID()
    private let katie = UUID()

    /// 9 PM – 7 AM: ten hours, wrapping midnight.
    private var night: NightPlanScale {
        NightPlanScale(nightStartMinute: 21 * 60, nightEndMinute: 7 * 60)!
    }

    // MARK: The ruler

    func testANightThatWrapsMidnightIsOneUnbrokenLength() {
        XCTAssertEqual(night.startMinute, 21 * 60)
        XCTAssertEqual(night.lengthMinutes, 600)
        XCTAssertEqual(night.endMinute, 7 * 60)
    }

    func testAZeroLengthNightIsNoNight() {
        XCTAssertNil(NightPlanScale(nightStartMinute: 22 * 60, nightEndMinute: 22 * 60))
    }

    func testMinutesMapAcrossTheNight() {
        XCTAssertEqual(night.position(ofMinute: 21 * 60)!, 0, accuracy: 1e-9)
        XCTAssertEqual(night.position(ofMinute: 2 * 60)!, 0.5, accuracy: 1e-9)
        XCTAssertEqual(night.position(ofMinute: 7 * 60)!, 1, accuracy: 1e-9)
        // Noon is not part of this night.
        XCTAssertNil(night.position(ofMinute: 12 * 60))
        XCTAssertEqual(night.x(ofMinute: 2 * 60, width: 300)!, 150, accuracy: 1e-9)
        XCTAssertEqual(NightPlanScale.x(at: 0.25, width: -10), 0, accuracy: 1e-9)
    }

    // MARK: Windows → pills

    func testAHandOverIsTwoPillsOnOneRow() {
        let windows = [SleepWindow(parentID: taylor, startMinute: 22 * 60, durationMinutes: 240),
                       SleepWindow(parentID: katie, startMinute: 2 * 60, durationMinutes: 240)]
        let pills = night.pills(for: windows)
        XCTAssertEqual(pills.count, 2)
        XCTAssertEqual(pills[0].parentID, taylor)
        XCTAssertEqual(pills[0].start, 0.1, accuracy: 1e-9)
        XCTAssertEqual(pills[0].end, 0.5, accuracy: 1e-9)
        XCTAssertTrue(pills[0].startsInNight && pills[0].endsInNight)
        XCTAssertEqual(pills[1].parentID, katie)
        XCTAssertEqual(pills[1].start, 0.5, accuracy: 1e-9)
        XCTAssertEqual(pills[1].end, 0.9, accuracy: 1e-9)
        // Meeting end to end is not overlapping: one row.
        XCTAssertFalse(NightPlanScale.overlaps(pills))
        XCTAssertEqual(NightPlanScale.rows(pills, parentOrder: [taylor, katie]).count, 1)
    }

    func testAWindowIsClippedToTheNightAndItsCutEndFlagged() {
        // 8 PM – 11 PM: the hour before 9 PM is outside the night.
        let pills = night.pills(for: [SleepWindow(parentID: katie, startMinute: 20 * 60,
                                                  durationMinutes: 180)])
        XCTAssertEqual(pills.count, 1)
        XCTAssertEqual(pills[0].start, 0, accuracy: 1e-9)
        XCTAssertEqual(pills[0].end, 0.2, accuracy: 1e-9)
        XCTAssertFalse(pills[0].startsInNight)
        XCTAssertTrue(pills[0].endsInNight)
    }

    func testAWindowWhollyOutsideTheNightDrawsNothing() {
        XCTAssertTrue(night.pills(for: [SleepWindow(parentID: taylor, startMinute: 12 * 60,
                                                    durationMinutes: 120)]).isEmpty)
    }

    func testOverlappingParentsGetARowEach() {
        let windows = [SleepWindow(parentID: taylor, startMinute: 23 * 60, durationMinutes: 240),
                       SleepWindow(parentID: katie, startMinute: 1 * 60, durationMinutes: 360)]
        let pills = night.pills(for: windows)
        XCTAssertTrue(NightPlanScale.overlaps(pills))
        let rows = NightPlanScale.rows(pills, parentOrder: [katie, taylor])
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].first?.parentID, katie)
        XCTAssertEqual(rows[1].first?.parentID, taylor)
    }

    func testOneParentsTouchingWindowsMerge() {
        let windows = [SleepWindow(parentID: taylor, startMinute: 22 * 60, durationMinutes: 120),
                       SleepWindow(parentID: taylor, startMinute: 0, durationMinutes: 120)]
        let pills = night.pills(for: windows)
        XCTAssertEqual(pills.count, 1)
        XCTAssertEqual(pills[0].start, 0.1, accuracy: 1e-9)
        XCTAssertEqual(pills[0].end, 0.5, accuracy: 1e-9)
    }

    // MARK: Hour marks

    func testMarksAreTheNightsEndsAndTheClocksThreeHourlyHours() {
        let ticks = night.ticks()
        XCTAssertEqual(ticks.map(\.minuteOfDay), [21 * 60, 0, 3 * 60, 6 * 60, 7 * 60])
        XCTAssertEqual(ticks.first?.kind, .start)
        XCTAssertEqual(ticks.last?.kind, .end)
    }

    func testCrowdedMarksThinOut() {
        // 6 AM sits a tenth of the strip from the 7 AM end: too close at 0.15.
        let ticks = night.ticks(minSeparation: 0.15)
        XCTAssertFalse(ticks.contains { $0.minuteOfDay == 6 * 60 })
        XCTAssertEqual(ticks.first?.kind, .start)
        XCTAssertEqual(ticks.last?.kind, .end)
    }

    func testLabelsAreShort() {
        XCTAssertEqual(NightPlanScale.label(minuteOfDay: 21 * 60), "9p")
        XCTAssertEqual(NightPlanScale.label(minuteOfDay: 0), "12a")
        XCTAssertEqual(NightPlanScale.label(minuteOfDay: 20 * 60 + 30), "8:30p")
        XCTAssertEqual(NightPlanScale.label(minuteOfDay: 21 * 60, twentyFourHour: true), "21")
        XCTAssertEqual(NightPlanScale.label(minuteOfDay: 5, twentyFourHour: true), "0:05")
    }
}
