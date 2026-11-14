import XCTest
@testable import TwoOfUs

final class AgeMarksTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func testTheNextMonthBirthday() {
        let mark = AgeMarks.next(after: day(2026, 11, 14), dateOfBirth: day(2026, 8, 20),
                                 calendar: calendar)
        XCTAssertEqual(mark, AgeMarks.Mark(date: day(2026, 11, 20), title: "3 months old"))
    }

    func testARoundDayCountComesFirstWhenItIsSooner() {
        // Born Aug 20: 100 days old on Nov 28, 4 months on Dec 20.
        let mark = AgeMarks.next(after: day(2026, 11, 21), dateOfBirth: day(2026, 8, 20),
                                 calendar: calendar)
        XCTAssertEqual(mark, AgeMarks.Mark(date: day(2026, 11, 28), title: "100 days old"))
    }

    func testTodayCountsAndAYearReadsAsAYear() {
        let mark = AgeMarks.next(after: day(2027, 8, 20), dateOfBirth: day(2026, 8, 20),
                                 calendar: calendar)
        XCTAssertEqual(mark?.title, "1 year old")
        XCTAssertEqual(mark?.date, day(2027, 8, 20))
    }

    func testNothingTooFarAhead() {
        XCTAssertNil(AgeMarks.next(after: day(2026, 11, 21), dateOfBirth: day(2026, 8, 20),
                                   withinDays: 3, calendar: calendar))
    }
}
