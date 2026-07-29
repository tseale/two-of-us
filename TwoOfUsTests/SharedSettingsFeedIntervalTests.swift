import XCTest
@testable import TwoOfUs

/// Pure-logic tests for `SharedSettings.feedInterval(at:)` — the single
/// source of truth for "what interval should the next-bottle prediction,
/// reminders, and widgets use right now": the night schedule's spacing while
/// inside the night window, else the daytime target. Regression coverage for
/// the bug where the feed card and reminders used the daytime target even
/// overnight, disagreeing with the Tonight card's own spacing.
final class SharedSettingsFeedIntervalTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        return c
    }()

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    /// Night 8pm–8am, daytime target 3h, night spacing 4h — the reported bug's
    /// exact configuration (Tonight card "Every 4h" vs. feed card hardcoded 3h).
    private func settings(dayMinutes: Int = 180, nightSpacingMinutes: Int = 240,
                          nightStart: Int = 20 * 60, nightEnd: Int = 8 * 60) -> SharedSettings {
        SharedSettings(targetFeedIntervalMinutes: dayMinutes,
                       nightStartMinute: nightStart, nightEndMinute: nightEnd,
                       nightFeedSpacingMinutes: nightSpacingMinutes)
    }

    func testDaytimeUsesTheDaytimeTarget() {
        let s = settings()
        XCTAssertEqual(s.feedInterval(at: date(2026, 7, 28, 14, 0), calendar: calendar),
                       TimeInterval(180 * 60))
    }

    func testInsideTheNightWindowUsesNightSpacingNotTheDaytimeTarget() {
        // 10:32pm, inside the 8pm–8am window — the exact scenario from the bug
        // report: the feed card must show +4h, not the daytime +3h default.
        let s = settings()
        XCTAssertEqual(s.feedInterval(at: date(2026, 7, 28, 22, 32), calendar: calendar),
                       TimeInterval(240 * 60))
    }

    func testAfterMidnightStillInsideTheWrappedWindowUsesNightSpacing() {
        let s = settings()
        XCTAssertEqual(s.feedInterval(at: date(2026, 7, 29, 2, 32), calendar: calendar),
                       TimeInterval(240 * 60))
    }

    func testExactlyAtNightStartUsesNightSpacing() {
        let s = settings()
        XCTAssertEqual(s.feedInterval(at: date(2026, 7, 28, 20, 0), calendar: calendar),
                       TimeInterval(240 * 60))
    }

    func testJustBeforeNightStartUsesTheDaytimeTarget() {
        let s = settings()
        XCTAssertEqual(s.feedInterval(at: date(2026, 7, 28, 19, 59), calendar: calendar),
                       TimeInterval(180 * 60))
    }

    func testJustAfterNightEndUsesTheDaytimeTarget() {
        let s = settings()
        XCTAssertEqual(s.feedInterval(at: date(2026, 7, 29, 8, 1), calendar: calendar),
                       TimeInterval(180 * 60))
    }
}
