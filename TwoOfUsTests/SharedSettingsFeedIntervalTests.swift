import XCTest
@testable import TwoOfUs

/// Pure-logic tests for `SharedSettings.feedInterval(after:)` — the single
/// source of truth for "what interval should the next-bottle prediction,
/// reminders, and widgets use after this feed": the night spacing when the
/// bottle it predicts lands inside the night window (that bottle IS the
/// night's first — or next — feed under the anchor rules), else the daytime
/// target. Regression coverage for the bug where a 7:45pm feed against an
/// 11pm–8am / 4h night predicted a daytime 10:45pm bottle instead of the
/// night's 11:45pm first feed.
final class SharedSettingsFeedIntervalTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        return c
    }()

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    /// Daytime target 3h, night spacing 4h. Default window 8pm–8am; the
    /// reported bug's exact configuration uses 11pm–8am.
    private func settings(dayMinutes: Int = 180, nightSpacingMinutes: Int = 240,
                          nightStart: Int = 20 * 60, nightEnd: Int = 8 * 60) -> SharedSettings {
        SharedSettings(targetFeedIntervalMinutes: dayMinutes,
                       nightStartMinute: nightStart, nightEndMinute: nightEnd,
                       nightFeedSpacingMinutes: nightSpacingMinutes)
    }

    func testMiddayFeedPredictsByTheDaytimeTarget() {
        // Fed 2pm: +4h = 6pm is nowhere near the 8pm window → daytime 3h.
        let s = settings()
        XCTAssertEqual(s.feedInterval(after: date(2026, 7, 28, 14, 0), calendar: calendar),
                       TimeInterval(180 * 60))
    }

    func testEveningFeedPredictingIntoTheWindowUsesNightSpacing() {
        // THE reported bug: window 11pm–8am, spacing 4h, fed 7:45pm. The
        // predicted bottle (11:45pm) lands inside the window — it's the
        // night's first feed, so the interval is 4h, not the daytime 3h
        // (which would have claimed a 10:45pm daytime bottle).
        let s = settings(nightStart: 23 * 60)
        XCTAssertEqual(s.feedInterval(after: date(2026, 7, 28, 19, 45), calendar: calendar),
                       TimeInterval(240 * 60))
    }

    func testEveningFeedPredictingShortOfTheWindowStaysDaytime() {
        // Window 11pm–8am, fed 5pm: +4h = 9pm still misses the window →
        // there's a normal daytime bottle first, on the 3h target.
        let s = settings(nightStart: 23 * 60)
        XCTAssertEqual(s.feedInterval(after: date(2026, 7, 28, 17, 0), calendar: calendar),
                       TimeInterval(180 * 60))
    }

    func testInWindowFeedUsesNightSpacing() {
        // Fed 10:32pm inside the 8pm–8am window: +4h = 2:32am is still inside.
        let s = settings()
        XCTAssertEqual(s.feedInterval(after: date(2026, 7, 28, 22, 32), calendar: calendar),
                       TimeInterval(240 * 60))
    }

    func testAfterMidnightStillInsideTheWrappedWindowUsesNightSpacing() {
        let s = settings()
        XCTAssertEqual(s.feedInterval(after: date(2026, 7, 29, 2, 32), calendar: calendar),
                       TimeInterval(240 * 60))
    }

    func testPredictionLandingExactlyOnWindowEndCountsAsNight() {
        // Fed 4am: +4h = 8am, exactly the window's close — inclusive, same as
        // the slot builder's `through:` (a feed landing at night's end still
        // belongs to the night).
        let s = settings()
        XCTAssertEqual(s.feedInterval(after: date(2026, 7, 29, 4, 0), calendar: calendar),
                       TimeInterval(240 * 60))
    }

    func testLateNightFeedPredictingPastTheWindowFlipsToDaytime() {
        // Fed 5am: +4h = 9am is past the 8am close — the next bottle is a
        // morning bottle, back on the daytime target.
        let s = settings()
        XCTAssertEqual(s.feedInterval(after: date(2026, 7, 29, 5, 0), calendar: calendar),
                       TimeInterval(180 * 60))
    }

    func testMorningFeedAfterTheWindowUsesTheDaytimeTarget() {
        let s = settings()
        XCTAssertEqual(s.feedInterval(after: date(2026, 7, 29, 8, 1), calendar: calendar),
                       TimeInterval(180 * 60))
    }
}
