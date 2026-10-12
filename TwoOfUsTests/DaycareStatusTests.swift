import XCTest
@testable import TwoOfUs

/// `DaycareStatus.isCheckedIn` drives Home's daycare mode (tiles collapse to
/// a strip, the report card goes hero) — these pin when that mode is on.
final class DaycareStatusTests: XCTestCase {

    private let calendar = Calendar.current
    private var dayStart: Date { calendar.startOfDay(for: .now) }

    private func today(hour: Int, minute: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dayStart)!
    }
    private func yesterday(hour: Int) -> Date {
        calendar.date(byAdding: .day, value: -1, to: today(hour: hour))!
    }

    func testCheckedInWithNoCheckoutIsAtDaycare() {
        XCTAssertTrue(DaycareStatus.isCheckedIn(
            checks: [(today(hour: 7, minute: 30), .checkIn)],
            dayStart: dayStart, now: today(hour: 10)))
    }

    func testCheckoutEndsDaycareMode() {
        let checks: [(Date, CheckType)] = [
            (today(hour: 7, minute: 30), .checkIn),
            (today(hour: 16, minute: 30), .checkOut),
        ]
        XCTAssertFalse(DaycareStatus.isCheckedIn(
            checks: checks, dayStart: dayStart, now: today(hour: 17)))
    }

    func testOrderOfInputDoesNotMatter() {
        // @Query sorts newest-first; the logic must not depend on that.
        let checks: [(Date, CheckType)] = [
            (today(hour: 16, minute: 30), .checkOut),
            (today(hour: 7, minute: 30), .checkIn),
        ]
        XCTAssertFalse(DaycareStatus.isCheckedIn(
            checks: checks, dayStart: dayStart, now: today(hour: 17)))
    }

    func testYesterdaysUnclosedCheckInDoesNotStrandDaycareMode() {
        // Daycare forgot the check-out tap — midnight must clear the mode.
        XCTAssertFalse(DaycareStatus.isCheckedIn(
            checks: [(yesterday(hour: 7), .checkIn)],
            dayStart: dayStart, now: today(hour: 9)))
    }

    func testFutureBackdateTypoDoesNotCountYet() {
        // A check-in accidentally dated this evening must not flip the mode
        // this morning.
        XCTAssertFalse(DaycareStatus.isCheckedIn(
            checks: [(today(hour: 19), .checkIn)],
            dayStart: dayStart, now: today(hour: 9)))
    }

    func testReCheckInAfterCheckoutCountsAgain() {
        // Picked up for a doctor visit, dropped back off.
        let checks: [(Date, CheckType)] = [
            (today(hour: 7, minute: 30), .checkIn),
            (today(hour: 11), .checkOut),
            (today(hour: 13), .checkIn),
        ]
        XCTAssertTrue(DaycareStatus.isCheckedIn(
            checks: checks, dayStart: dayStart, now: today(hour: 14)))
    }

    func testNoChecksMeansNotAtDaycare() {
        XCTAssertFalse(DaycareStatus.isCheckedIn(
            checks: [], dayStart: dayStart, now: today(hour: 10)))
    }
}
