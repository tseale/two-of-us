import XCTest
@testable import TwoOfUs

/// `DaycareStatus.attendance` drives Home's daycare mode (tiles collapse to a
/// strip, the report card goes hero). Check markers are the primary source;
/// the fallbacks — first daycare-logged event as the missing check-in, 5:30 PM
/// as the missing check-out — keep a skipped tap from wedging the screen.
final class DaycareStatusTests: XCTestCase {

    private let calendar = Calendar.current
    private var dayStart: Date { calendar.startOfDay(for: .now) }

    private func today(hour: Int, minute: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dayStart)!
    }
    private func yesterday(hour: Int) -> Date {
        calendar.date(byAdding: .day, value: -1, to: today(hour: hour))!
    }

    private func attendance(checks: [(Date, CheckType)] = [],
                            firstEvent: Date? = nil,
                            now: Date) -> DaycareStatus.Attendance? {
        DaycareStatus.attendance(checks: checks, firstDaycareEvent: firstEvent,
                                 dayStart: dayStart, now: now)
    }

    // MARK: Check markers (primary)

    func testCheckedInWithNoCheckoutIsAtDaycare() {
        let result = attendance(checks: [(today(hour: 7, minute: 30), .checkIn)],
                                now: today(hour: 10))
        XCTAssertEqual(result, .init(since: today(hour: 7, minute: 30), basis: .checkInEvent))
    }

    func testCheckoutEndsDaycareMode() {
        XCTAssertNil(attendance(
            checks: [(today(hour: 7, minute: 30), .checkIn),
                     (today(hour: 16, minute: 30), .checkOut)],
            now: today(hour: 17)))
    }

    func testOrderOfInputDoesNotMatter() {
        // @Query sorts newest-first; the logic must not depend on that.
        XCTAssertNil(attendance(
            checks: [(today(hour: 16, minute: 30), .checkOut),
                     (today(hour: 7, minute: 30), .checkIn)],
            now: today(hour: 17)))
    }

    func testYesterdaysUnclosedCheckInDoesNotStrandDaycareMode() {
        // Daycare forgot the check-out tap — midnight must clear the mode.
        XCTAssertNil(attendance(checks: [(yesterday(hour: 7), .checkIn)],
                                now: today(hour: 9)))
    }

    func testFutureBackdateTypoDoesNotCountYet() {
        XCTAssertNil(attendance(checks: [(today(hour: 19), .checkIn)],
                                now: today(hour: 9)))
    }

    func testReCheckInAfterCheckoutCountsAgain() {
        // Picked up for a doctor visit, dropped back off.
        let result = attendance(
            checks: [(today(hour: 7, minute: 30), .checkIn),
                     (today(hour: 11), .checkOut),
                     (today(hour: 13), .checkIn)],
            now: today(hour: 14))
        XCTAssertEqual(result?.since, today(hour: 13))
    }

    func testNoSignalsMeansNotAtDaycare() {
        XCTAssertNil(attendance(now: today(hour: 10)))
    }

    // MARK: Missing check-in — first daycare event stands in

    func testFirstDaycareEventImpliesCheckedIn() {
        // No markers, but daycare logged a 9:02 bottle: he's there.
        let result = attendance(firstEvent: today(hour: 9, minute: 2),
                                now: today(hour: 10))
        XCTAssertEqual(result, .init(since: today(hour: 9, minute: 2),
                                     basis: .firstDaycareEvent))
    }

    func testCheckMarkersOutrankTheEventFallback() {
        // An explicit check-out ends the day even while daycare events exist —
        // the 4:45 PM photo upload must not re-open it.
        XCTAssertNil(attendance(
            checks: [(today(hour: 7, minute: 30), .checkIn),
                     (today(hour: 16, minute: 30), .checkOut)],
            firstEvent: today(hour: 9),
            now: today(hour: 17)))
    }

    func testYesterdaysEventsDoNotImplyAttendanceToday() {
        XCTAssertNil(attendance(firstEvent: yesterday(hour: 9),
                                now: today(hour: 10)))
    }

    // MARK: Missing check-out — assumed out at 5:30 PM

    func testAssumedCheckOutClearsAnUnclosedCheckIn() {
        // Checked in at 7:30, check-out never recorded: by evening the mode
        // must have cleared on its own.
        let checks: [(Date, CheckType)] = [(today(hour: 7, minute: 30), .checkIn)]
        XCTAssertNotNil(attendance(checks: checks, now: today(hour: 17, minute: 29)))
        XCTAssertNil(attendance(checks: checks, now: today(hour: 17, minute: 30)))
        XCTAssertNil(attendance(checks: checks, now: today(hour: 20)))
    }

    func testAssumedCheckOutClearsTheEventFallbackToo() {
        XCTAssertNil(attendance(firstEvent: today(hour: 9),
                                now: today(hour: 18)))
    }

    func testExplicitPostCutoffCheckInIsHonored() {
        // A real check-in marker after 5:30 PM is an explicit signal — the
        // assumed check-out only covers signals from earlier in the day.
        let result = attendance(checks: [(today(hour: 17, minute: 45), .checkIn)],
                                now: today(hour: 18))
        XCTAssertEqual(result?.since, today(hour: 17, minute: 45))
    }
}
