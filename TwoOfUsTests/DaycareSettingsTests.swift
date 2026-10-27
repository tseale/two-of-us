import XCTest
@testable import TwoOfUs

/// The SharedSettings daycare helpers (days CSV, display name, location
/// three-state) and `DaycareGeofencePlanner` — the decision of what an
/// arrival at the fence should ask.
final class DaycareSettingsTests: XCTestCase {

    private let calendar = Calendar.current
    private var dayStart: Date { calendar.startOfDay(for: .now) }

    private func today(hour: Int, minute: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dayStart)!
    }

    // MARK: SharedSettings helpers

    func testDisplayNameFallsBackToGenericWord() {
        let s = SharedSettings()
        XCTAssertEqual(s.daycareDisplayName, "Daycare")
        s.daycareName = "Little Owls"
        XCTAssertEqual(s.daycareDisplayName, "Little Owls")
    }

    func testDaysDefaultToWeekdaysAndRoundTripThroughCSV() {
        let s = SharedSettings()
        XCTAssertEqual(s.daycareDays, [2, 3, 4, 5, 6], "Mon–Fri until configured")
        s.daycareDays = [2, 4, 6]
        XCTAssertEqual(s.daycareDaysRaw, "2,4,6")
        XCTAssertEqual(s.daycareDays, [2, 4, 6])
    }

    func testGarbageDaysRawReadsAsTheDefault() {
        let s = SharedSettings()
        s.daycareDaysRaw = "banana,99"
        XCTAssertEqual(s.daycareDays, [2, 3, 4, 5, 6],
                       "an unparseable value must not turn every day into a home day")
    }

    func testIsDaycareDayFollowsTheConfiguredSet() {
        let s = SharedSettings()
        s.daycareDays = [2]   // Mondays only
        let monday = calendar.nextDate(after: .now, matching: DateComponents(weekday: 2),
                                       matchingPolicy: .nextTime)!
        let tuesday = calendar.date(byAdding: .day, value: 1, to: monday)!
        XCTAssertTrue(s.isDaycareDay(monday))
        XCTAssertFalse(s.isDaycareDay(tuesday))
    }

    func testLocationThreeState() {
        let s = SharedSettings()
        XCTAssertNil(s.daycareLocationRaw, "never set is nil — it must not travel")
        XCTAssertNil(s.daycareCoordinate)
        s.daycareCoordinate = (37.3349, -122.0090)
        XCTAssertEqual(s.daycareCoordinate?.latitude, 37.3349)
        XCTAssertEqual(s.daycareCoordinate?.longitude, -122.0090)
        s.daycareCoordinate = nil
        XCTAssertEqual(s.daycareLocationRaw, "", "clearing writes the explicit empty that syncs")
        XCTAssertNil(s.daycareCoordinate)
        s.daycareLocationRaw = "garbage"
        XCTAssertNil(s.daycareCoordinate, "an unparseable pin reads as no pin")
    }

    // MARK: Daycare presence (the multi-device slider gate)

    func testPresenceRoundTripsThroughJSON() throws {
        let presence = DaycarePresence(deviceID: UUID(),
                                       timestamp: today(hour: 7, minute: 48),
                                       type: .arrival)
        let decoded = try XCTUnwrap(DaycarePresence.decode(presence.encoded))
        XCTAssertEqual(decoded.deviceID, presence.deviceID)
        XCTAssertEqual(decoded.type, .arrival)
        XCTAssertEqual(decoded.timestamp.timeIntervalSince1970,
                       presence.timestamp.timeIntervalSince1970, accuracy: 1,
                       "ISO-8601 keeps the crossing's second")
        XCTAssertNil(DaycarePresence.decode(nil))
        XCTAssertNil(DaycarePresence.decode("garbage"), "an unparseable value reads as no presence")
    }

    func testPartnerAtDaycareNeedsTheOtherPhonesArrivalToday() {
        let mine = UUID(), theirs = UUID()
        let arrival = DaycarePresence(deviceID: theirs, timestamp: today(hour: 7, minute: 50),
                                      type: .arrival)
        // Requirement: the phone NOT at daycare sees "someone's there"…
        XCTAssertTrue(arrival.isPartnerAtDaycare(myDeviceID: mine, now: today(hour: 8)))
        // …but a phone never reads its OWN crossing as a partner's.
        XCTAssertFalse(arrival.isPartnerAtDaycare(myDeviceID: theirs, now: today(hour: 8)))
    }

    func testPartnerPresenceClearsOnDepartureAndAtMidnight() {
        let mine = UUID()
        let departure = DaycarePresence(deviceID: UUID(), timestamp: today(hour: 8),
                                        type: .departure)
        XCTAssertFalse(departure.isPartnerAtDaycare(myDeviceID: mine, now: today(hour: 9)))
        // A phone that died inside the fence yesterday mustn't read as
        // "someone's at daycare" forever — the day scopes it.
        let stale = DaycarePresence(
            deviceID: UUID(),
            timestamp: calendar.date(byAdding: .day, value: -1, to: today(hour: 8))!,
            type: .arrival)
        XCTAssertFalse(stale.isPartnerAtDaycare(myDeviceID: mine, now: today(hour: 8)))
    }

    // MARK: Geofence planner

    private func prompt(now: Date,
                        openMinute: Int = DaycareStatus.defaultOpenMinute,
                        closeMinute: Int = DaycareStatus.defaultCloseMinute,
                        isOperatingDay: Bool = true,
                        attending: Bool = false,
                        checkedOutToday: Bool = false,
                        homeToday: Bool = false) -> DaycareGeofencePlanner.Prompt? {
        DaycareGeofencePlanner.prompt(
            now: now, dayStart: dayStart, openMinute: openMinute, closeMinute: closeMinute,
            isOperatingDay: isOperatingDay, attending: attending,
            checkedOutToday: checkedOutToday, homeToday: homeToday)
    }

    func testMorningArrivalAsksToDropOff() {
        XCTAssertEqual(prompt(now: today(hour: 7, minute: 45)), .dropOff)
    }

    func testArrivalWhileAttendingAsksToPickUp() {
        XCTAssertEqual(prompt(now: today(hour: 16, minute: 30), attending: true), .pickUp)
        // Even mid-morning — a sick-day pickup is still a pickup.
        XCTAssertEqual(prompt(now: today(hour: 10), attending: true), .pickUp)
    }

    func testNonOperatingDayStaysSilent() {
        XCTAssertNil(prompt(now: today(hour: 7, minute: 45), isOperatingDay: false))
    }

    func testHomeTodayStaysSilent() {
        XCTAssertNil(prompt(now: today(hour: 7, minute: 45), homeToday: true))
    }

    func testAfterCheckoutAReturnTripStaysSilent() {
        // Forgot the bag at 5:45 after a 4:30 pickup — no second ask.
        XCTAssertNil(prompt(now: today(hour: 16, minute: 45), checkedOutToday: true))
    }

    func testDropOffWindowHasAGraceHourBeforeOpen() {
        XCTAssertEqual(prompt(now: today(hour: 6, minute: 15)), .dropOff,
                       "parents arrive a little before the doors open")
        XCTAssertNil(prompt(now: today(hour: 5, minute: 30)),
                     "a pre-dawn drive past the building is not a drop-off")
        XCTAssertNil(prompt(now: today(hour: 19)),
                     "an evening drive-by after close is not a drop-off")
    }
}
