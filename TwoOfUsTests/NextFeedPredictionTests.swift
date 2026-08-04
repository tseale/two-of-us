import XCTest
import SwiftData
@testable import TwoOfUs

/// `QuickLogger.nextFeedPrediction` feeds the sleep Live Activity's countdown
/// column — the earlier of the schedule's next upcoming feed occurrence and
/// the canonical last-feed + interval prediction, with the scheduled slot
/// winning ties (it knows whose turn it is).
///
/// Store-backed (the prediction reads through QuickLogger), so `now` is pinned
/// to wall-clock times on the CURRENT day: the internal engines run on
/// `Calendar.current`, and QuickLogger's recent-event fetches window off the
/// real clock — same-day fixtures stay inside both no matter when the suite runs.
@MainActor
final class NextFeedPredictionTests: XCTestCase {
    private var container: ModelContainer!
    private var ctx: ModelContext!

    override func setUp() {
        super.setUp()
        container = AppModelContainer.make(inMemory: true)
        ctx = container.mainContext
        ctx.insert(Baby(name: "Miller", dateOfBirth: .now))
    }

    override func tearDown() {
        ctx = nil
        container = nil
        super.tearDown()
    }

    private var logger: QuickLogger { QuickLogger(context: ctx) }

    /// Today at a fixed local wall-clock time.
    private func today(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0,
                              of: Calendar.current.startOfDay(for: .now))!
    }

    private func insertFeed(at date: Date) {
        ctx.insert(FeedEvent(baby: nil, amountOz: 4, timestamp: date,
                             loggedByID: UUID(), loggedByName: "BT",
                             loggedByColorHex: "#AABBCC"))
        try? ctx.save()
    }

    func testNothingToPredictFromGivesNil() {
        XCTAssertNil(logger.nextFeedPrediction(now: today(11, 0)))
    }

    func testOverduePredictionWithoutAScheduleGivesNil() {
        // No SharedSettings row → no night schedule; the only candidate is the
        // last-feed prediction, and it's already 3h past — a countdown born
        // frozen at 0:00 helps nobody.
        insertFeed(at: today(5, 0))
        XCTAssertNil(logger.nextFeedPrediction(now: today(11, 0)))
    }

    func testDaytimePredictionUsesTheTargetInterval() {
        // Default settings: 3h daytime target, night 8pm–8am. Fed 10am at
        // 11am → next bottle 1pm, hours before tonight's first slot — the
        // daytime prediction wins, and nobody owns a daytime bottle.
        ctx.insert(SharedSettings())
        insertFeed(at: today(10, 0))

        let next = logger.nextFeedPrediction(now: today(11, 0))

        XCTAssertEqual(next?.date, today(13, 0))
        XCTAssertNil(next?.ownerName)
        XCTAssertNil(next?.ownerColorHex)
    }

    func testNightSlotWinsTheTieAndCarriesItsOwner() {
        // Night 9pm–8am every 3h, both parents active, BT (earlier join) on
        // first shift. The 10pm bottle anchors the night AND fulfills its own
        // slot, so the next upcoming occurrence is 1am — GT's — landing on
        // exactly the same instant as last-feed + night spacing. The tie must
        // resolve to the scheduled slot: it knows whose turn it is.
        ctx.insert(SharedSettings(nightStartMinute: 21 * 60, nightEndMinute: 8 * 60,
                                  nightFeedSpacingMinutes: 180))
        ctx.insert(Participant(displayName: "BT", colorHex: "#5AC8B8",
                               invitedAt: .now.addingTimeInterval(-1000)))
        ctx.insert(Participant(displayName: "GT", colorHex: "#E8A0BF",
                               invitedAt: .now.addingTimeInterval(-500)))
        let anchor = today(22, 0)
        insertFeed(at: anchor)

        let next = logger.nextFeedPrediction(now: today(22, 30))

        XCTAssertEqual(next?.date, anchor.addingTimeInterval(3 * 3600))
        XCTAssertEqual(next?.ownerName, "GT")
        XCTAssertEqual(next?.ownerColorHex, "#E8A0BF")
    }

    func testOverdueLastFeedStillSurfacesTheNextScheduledSlot() {
        // Fed 5am, glancing at 11am: the last-feed prediction (8am) is long
        // past, but tonight's schedule still names a concrete next bottle —
        // better than an empty column.
        ctx.insert(SharedSettings())
        insertFeed(at: today(5, 0))

        let next = logger.nextFeedPrediction(now: today(11, 0))

        XCTAssertEqual(next?.date, today(20, 0), "anchor defaults to the window start")
    }
}
