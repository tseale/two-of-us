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

    // MARK: Configured hours (Daycare settings)

    func testConfiguredCloseMovesTheAssumedCheckOut() {
        // A 6:00 PM daycare: 5:31 is still mid-attendance, 6:00 clears it.
        let checks: [(Date, CheckType)] = [(today(hour: 7, minute: 30), .checkIn)]
        XCTAssertNotNil(DaycareStatus.attendance(
            checks: checks, firstDaycareEvent: nil, dayStart: dayStart,
            now: today(hour: 17, minute: 31), closeMinute: 18 * 60))
        XCTAssertNil(DaycareStatus.attendance(
            checks: checks, firstDaycareEvent: nil, dayStart: dayStart,
            now: today(hour: 18), closeMinute: 18 * 60))
    }

    func testEarlierConfiguredCloseClearsSooner() {
        // A 4:00 PM close must end the day before the old 5:30 default.
        let checks: [(Date, CheckType)] = [(today(hour: 7, minute: 30), .checkIn)]
        XCTAssertNil(DaycareStatus.attendance(
            checks: checks, firstDaycareEvent: nil, dayStart: dayStart,
            now: today(hour: 16, minute: 30), closeMinute: 16 * 60))
    }

    // MARK: "Home today" markers (manual check-in feature)

    func testHomeTodayMarkerIsNotACheckIn() {
        // The decode fallback maps unknown raws to .checkIn — the engine
        // must filter .notAttending before the latest-marker scan.
        XCTAssertNil(attendance(checks: [(today(hour: 7), .notAttending)],
                                now: today(hour: 10)))
    }

    func testBrightwheelEventOverridesHomeToday() {
        // Staff logging a bottle means he's there, whatever the marker says.
        let result = attendance(checks: [(today(hour: 7), .notAttending)],
                                firstEvent: today(hour: 8, minute: 15),
                                now: today(hour: 10))
        XCTAssertEqual(result, .init(since: today(hour: 8, minute: 15),
                                     basis: .firstDaycareEvent))
    }

    func testManualCheckInAfterHomeTodayWins() {
        // "Actually, taking him in" without even undoing the marker.
        let result = attendance(checks: [(today(hour: 7), .notAttending),
                                         (today(hour: 8), .checkIn)],
                                now: today(hour: 10))
        XCTAssertEqual(result?.since, today(hour: 8))
    }

    func testManualPickupEndsTheDayBeforeTheAssumedClose() {
        // Requirement: a 4:00 pickup ends daycare mode at 4:00, not 5:30.
        XCTAssertNil(attendance(
            checks: [(today(hour: 7, minute: 48), .checkIn),
                     (today(hour: 16), .checkOut)],
            now: today(hour: 16, minute: 5)))
    }

    // MARK: Pick-up control presentation

    private func pickup(now: Date, showMinute: Int = DaycareStatus.defaultPickupShowMinute,
                        geofenceMode: Bool = false, near: Bool = false) -> Bool {
        DaycareStatus.pickupVisible(now: now, showMinute: showMinute,
                                    geofenceMode: geofenceMode, nearDaycare: near)
    }

    private func dropoff(now: Date, open: Int = DaycareStatus.defaultOpenMinute,
                         close: Int = DaycareStatus.defaultCloseMinute,
                         geofenceMode: Bool, near: Bool = false) -> Bool {
        DaycareStatus.dropoffVisible(now: now, openMinute: open, closeMinute: close,
                                     geofenceMode: geofenceMode, nearDaycare: near)
    }

    func testPickupSlideHiddenAllMorning() {
        // Requirement: no pick-up control at all before the show time — a
        // bounced phone at 10 AM must have nothing to grab.
        XCTAssertFalse(pickup(now: today(hour: 10)))
        XCTAssertFalse(pickup(now: today(hour: 14, minute: 59)))
    }

    func testPickupSlideSurfacesAtTheShowTime() {
        XCTAssertTrue(pickup(now: today(hour: 15)),
                      "the show minute itself counts — 3:00 PM shows the slide")
        XCTAssertTrue(pickup(now: today(hour: 16, minute: 30)))
    }

    func testPickupSlideConfiguredShowTimeMoves() {
        XCTAssertFalse(pickup(now: today(hour: 15), showMinute: 16 * 60))
        XCTAssertTrue(pickup(now: today(hour: 16), showMinute: 16 * 60))
    }

    func testArrivingAtTheFenceSurfacesThePickupSlideEarly() {
        // The early sick-day pickup: standing at the daycare at noon
        // surfaces the slide right away — the sweep gesture is the gate
        // against accidents, so the window can open wherever the fence does.
        XCTAssertTrue(pickup(now: today(hour: 12), near: true))
        XCTAssertTrue(pickup(now: today(hour: 15, minute: 30), near: true))
    }

    // MARK: Geofence mode — the fence IS the visibility rule

    func testGeofenceModePickupFollowsTheFenceAlone() {
        // Requirement: in geofence mode the slider shows ONLY on the phone at
        // daycare — the one at work sees nothing, even late afternoon when
        // the time-based show minute has long passed.
        XCTAssertTrue(pickup(now: today(hour: 10), geofenceMode: true, near: true),
                      "arrival surfaces the slide whatever the clock says")
        XCTAssertFalse(pickup(now: today(hour: 16), geofenceMode: true, near: false),
                       "the show minute is the fallback's rule, not the fence's")
    }

    func testGeofenceModeDropoffNeedsTheFence() {
        // Requirement: sliders never show by default — a weekday morning at
        // home shows nothing until a phone actually reaches the daycare.
        XCTAssertFalse(dropoff(now: today(hour: 8), geofenceMode: true, near: false))
        XCTAssertTrue(dropoff(now: today(hour: 8), geofenceMode: true, near: true))
    }

    func testGeofenceModeDropoffRespectsOperatingHours() {
        // Requirement: an 8 PM arrival (a parents' event) is not a drop-off.
        XCTAssertFalse(dropoff(now: today(hour: 20), geofenceMode: true, near: true))
        // The grace hour before the doors open counts (parents arrive early)…
        XCTAssertTrue(dropoff(now: today(hour: 6, minute: 15), geofenceMode: true, near: true))
        // …but the night shift before it doesn't.
        XCTAssertFalse(dropoff(now: today(hour: 5, minute: 45), geofenceMode: true, near: true))
    }

    func testTimeModeDropoffFollowsTheDoors() {
        // The fallback (location off): doors-open is the gate, fence ignored.
        XCTAssertFalse(dropoff(now: today(hour: 6, minute: 59), geofenceMode: false))
        XCTAssertTrue(dropoff(now: today(hour: 7), geofenceMode: false))
    }
}
