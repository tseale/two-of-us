import XCTest
@testable import TwoOfUs

/// The daycare-ping texts and the freshness window — the pure halves of the
/// notification path (the posting itself is UNUserNotificationCenter and
/// stays untested, gated off in tests by demo mode anyway).
final class DaycareNotificationTests: XCTestCase {

    private func date(hour: Int, minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(
            year: 2026, month: 10, day: 13, hour: hour, minute: minute))!
    }

    // MARK: Bodies

    func testFeedBodyCarriesTheOunces() {
        XCTAssertEqual(NotificationManager.DaycareText.feed("Miller", oz: 4),
                       "🍼 Miller had a 4 oz bottle")
        XCTAssertEqual(NotificationManager.DaycareText.feed("Miller", oz: 3.25),
                       "🍼 Miller had a 3.25 oz bottle")
    }

    func testDiaperAndPhotoBodies() {
        XCTAssertEqual(NotificationManager.DaycareText.diaper("Miller"),
                       "💧 Diaper change for Miller")
        XCTAssertEqual(NotificationManager.DaycareText.photo,
                       "📸 New photo from daycare")
    }

    func testNapBodiesFollowTheSleepVocabulary() {
        XCTAssertEqual(NotificationManager.DaycareText.napStarted("Miller"),
                       "💤 Miller started napping")
        // A 90-minute daytime nap is a nap…
        XCTAssertEqual(
            NotificationManager.DaycareText.napEnded(
                "Miller", start: date(hour: 9), end: date(hour: 10, minute: 30)),
            "💤 Miller woke up — napped 1h 30m")
        // …a 3h17m one has crossed the SleepLanguage threshold into sleep.
        XCTAssertEqual(
            NotificationManager.DaycareText.napEnded(
                "Miller", start: date(hour: 8, minute: 40), end: date(hour: 11, minute: 57)),
            "💤 Miller woke up — slept 3h 17m")
    }

    // MARK: Freshness window

    func testOnlyFreshEventsPing() {
        let now = date(hour: 12)
        XCTAssertTrue(NotificationManager.isFreshDaycareEvent(date(hour: 11, minute: 55), now: now))
        XCTAssertTrue(NotificationManager.isFreshDaycareEvent(date(hour: 11, minute: 50), now: now),
                      "exactly at the window edge still pings")
        XCTAssertFalse(NotificationManager.isFreshDaycareEvent(date(hour: 11, minute: 30), now: now),
                       "a bulk sync's backlog must stay silent")
        XCTAssertFalse(NotificationManager.isFreshDaycareEvent(date(hour: 13), now: now),
                       "an hour in the future is a bad clock, not an event")
        XCTAssertTrue(NotificationManager.isFreshDaycareEvent(now.addingTimeInterval(30), now: now),
                      "small clock skew from the daycare's server is forgiven")
    }
}
