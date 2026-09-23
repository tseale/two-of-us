import XCTest
@testable import TwoOfUs

/// `TimeFormatting.age` — both directions: age counting up after birth, and
/// the due-date countdown for a future date of birth (expecting parents can
/// set up before the arrival; a future DOB *is* the due date).
final class TimeFormattingTests: XCTestCase {
    private let cal = Calendar.current
    private let now = Date()

    private func daysFromNow(_ days: Int) -> Date {
        cal.date(byAdding: .day, value: days, to: now)!
    }

    // MARK: Countdown (not born yet)

    func testDueTomorrow() {
        XCTAssertEqual(TimeFormatting.age(from: daysFromNow(1), now: now), "due tomorrow")
    }

    func testDueInDays() {
        XCTAssertEqual(TimeFormatting.age(from: daysFromNow(10), now: now), "due in 10 days")
    }

    func testDueInSingleWeek() {
        XCTAssertEqual(TimeFormatting.age(from: daysFromNow(13), now: now), "due in 13 days",
                       "13 days stays in days — the week bracket starts at 14")
        XCTAssertEqual(TimeFormatting.age(from: daysFromNow(14), now: now), "due in 2 weeks")
    }

    func testDueInWeeks() {
        XCTAssertEqual(TimeFormatting.age(from: daysFromNow(25), now: now), "due in 3 weeks")
    }

    func testDueInMonths() {
        XCTAssertEqual(TimeFormatting.age(from: daysFromNow(70), now: now), "due in 2 months")
    }

    // MARK: Age (born)

    func testBornDaysOld() {
        XCTAssertEqual(TimeFormatting.age(from: daysFromNow(-1), now: now), "1 day old")
        XCTAssertEqual(TimeFormatting.age(from: daysFromNow(-10), now: now), "10 days old")
    }

    func testBornWeeksOld() {
        XCTAssertEqual(TimeFormatting.age(from: daysFromNow(-21), now: now), "3 weeks old")
    }

    func testBornMonthsOldIgnoresTimeOfDay() {
        // Regression: a dob later in the day than "now" must not shave a
        // month off the count — only calendar days should matter.
        let dob = cal.date(from: DateComponents(year: 2026, month: 7, day: 23, hour: 15, minute: 0))!
        let checkedAt = cal.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 10, minute: 0))!
        XCTAssertEqual(TimeFormatting.age(from: dob, now: checkedAt), "2 months old")
    }
}
