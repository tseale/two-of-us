import XCTest
@testable import TwoOfUs

/// The Today card's daycare layer — the recap rows and the check slot — and
/// when there is one to draw. On iPhone Duo's open display the layer leaves
/// the card while the log tiles share its page (the page has room for the
/// day above the tiles and no more) and leads the page beside it; that page
/// asks `hasDaycareLayer` first, so it never hosts an empty card.
/// (Main-actor, like the other suites that reach into a view's types.)
@MainActor
final class TodayHeroCardLayersTests: XCTestCase {
    /// A daycare day with something logged.
    private var recap: DaycareDaySummary {
        var day = DaycareDaySummary()
        day.feedCount = 1
        day.feedOz = 4
        day.checkIn = Date(timeIntervalSince1970: 1_000)
        day.checkOut = Date(timeIntervalSince1970: 30_000)
        return day
    }

    // MARK: The check slot

    func testOnlySlotsThatDrawSomethingAreShown() {
        XCTAssertTrue(CheckinSlot.dropOff.isShown)
        XCTAssertTrue(CheckinSlot.pickUp.isShown)
        XCTAssertTrue(CheckinSlot.homeToday.isShown)
        XCTAssertTrue(CheckinSlot.partnerAtDaycare.isShown)
        // Collapsed outright…
        XCTAssertFalse(CheckinSlot.hidden.isShown)
        // …and after pick-up the daycare row already carries the times.
        XCTAssertFalse(CheckinSlot.pickedUp(Date(timeIntervalSince1970: 30_000)).isShown)
    }

    // MARK: The layer

    func testAHomeDayWithNoSlotHasNoDaycareLayer() {
        XCTAssertFalse(TodayHeroCard.hasDaycareLayer(daycare: DaycareDaySummary(),
                                                     checkinSlot: .hidden))
    }

    func testTheEveningOfADaycareDayHasItsRecap() {
        // After pick-up: the slot itself draws nothing, the recap does.
        XCTAssertTrue(TodayHeroCard.hasDaycareLayer(
            daycare: recap,
            checkinSlot: .pickedUp(Date(timeIntervalSince1970: 30_000))))
        // Past the assumed close on a marker-less day: recap, no slot.
        XCTAssertTrue(TodayHeroCard.hasDaycareLayer(daycare: recap, checkinSlot: .hidden))
    }

    func testACheckSlotAloneIsALayer() {
        // A weekday morning before drop-off, or a day at home: nothing
        // logged at daycare yet, but there is something to show or slide.
        let nothingYet = DaycareDaySummary()
        XCTAssertTrue(TodayHeroCard.hasDaycareLayer(daycare: nothingYet, checkinSlot: .dropOff))
        XCTAssertTrue(TodayHeroCard.hasDaycareLayer(daycare: nothingYet, checkinSlot: .homeToday))
        XCTAssertTrue(TodayHeroCard.hasDaycareLayer(daycare: nothingYet,
                                                    checkinSlot: .partnerAtDaycare))
    }

    func testAPickUpWithNothingElseIsNoLayer() {
        // A picked-up marker with an empty day (the summary is built
        // elsewhere; this is the helper's own rule) leaves nothing to draw.
        XCTAssertFalse(TodayHeroCard.hasDaycareLayer(
            daycare: DaycareDaySummary(),
            checkinSlot: .pickedUp(Date(timeIntervalSince1970: 30_000))))
    }
}
