import XCTest
@testable import TwoOfUs

/// The one sleep vocabulary (SleepLanguage): night (8 PM – 6 AM by start) is
/// always "sleep"; a daytime sleep is a "nap" until the 2-hour crossover.
final class SleepLanguageTests: XCTestCase {

    private func date(hour: Int, minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(
            year: 2026, month: 10, day: 13, hour: hour, minute: minute))!
    }

    func testDaytimeShortSleepIsANap() {
        let start = date(hour: 10)
        XCTAssertEqual(SleepLanguage.gerund(start: start, now: start.addingTimeInterval(45 * 60)), "napping")
        XCTAssertEqual(SleepLanguage.noun(start: start, end: start.addingTimeInterval(45 * 60)), "Nap")
    }

    func testDaytimeSleepCrossesIntoSleepAtTwoHours() {
        let start = date(hour: 10)
        XCTAssertEqual(SleepLanguage.gerund(start: start, now: start.addingTimeInterval(119 * 60)), "napping")
        XCTAssertEqual(SleepLanguage.gerund(start: start, now: start.addingTimeInterval(2 * 3600)), "sleeping")
        XCTAssertEqual(SleepLanguage.noun(start: start, end: start.addingTimeInterval(3 * 3600)), "Sleep")
    }

    func testNightIsAlwaysSleepRegardlessOfLength() {
        let evening = date(hour: 20, minute: 30)
        XCTAssertEqual(SleepLanguage.gerund(start: evening, now: evening.addingTimeInterval(5 * 60)), "sleeping")
        let smallHours = date(hour: 2)
        XCTAssertEqual(SleepLanguage.noun(start: smallHours, end: smallHours.addingTimeInterval(40 * 60)), "Sleep")
    }

    func testEarlyMorningDozeIsANap() {
        // 6 AM is the day's edge — a 6:30 doze is a morning nap, 5:59 is night.
        let sixThirty = date(hour: 6, minute: 30)
        XCTAssertEqual(SleepLanguage.gerund(start: sixThirty, now: sixThirty.addingTimeInterval(30 * 60)), "napping")
        let fiveFiftyNine = date(hour: 5, minute: 59)
        XCTAssertEqual(SleepLanguage.gerund(start: fiveFiftyNine, now: fiveFiftyNine.addingTimeInterval(30 * 60)), "sleeping")
    }

    func testPredictedNounFollowsTheClock() {
        XCTAssertEqual(SleepLanguage.predictedNoun(at: date(hour: 14)), "nap")
        XCTAssertEqual(SleepLanguage.predictedNoun(at: date(hour: 20, minute: 30)), "sleep")
        XCTAssertEqual(SleepLanguage.predictedNoun(at: date(hour: 5)), "sleep")
    }
}
