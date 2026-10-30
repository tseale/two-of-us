import XCTest
@testable import TwoOfUs

/// `DropoffBoard.compute` answers the daycare's morning whiteboard — last
/// bottle, last diaper, wake time, overnight sleep, notes — for both Home's
/// card and the geofence drop-off notification. Pure: fixtures in, display
/// strings out. Clock strings go through `TimeFormatting.clock` so the
/// assertions hold in any simulator locale.
final class DropoffBoardTests: XCTestCase {

    private let calendar = Calendar.current
    private var dayStart: Date { calendar.startOfDay(for: .now) }

    private func today(hour: Int, minute: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dayStart)!
    }
    private func yesterday(hour: Int, minute: Int = 0) -> Date {
        calendar.date(byAdding: .day, value: -1, to: today(hour: hour, minute: minute))!
    }

    private func board(
        feeds: [DropoffBoard.Feed] = [],
        diapers: [DropoffBoard.Diaper] = [],
        sleeps: [DropoffBoard.Sleep] = [],
        notes: [DropoffBoard.Note] = [],
        now: Date? = nil
    ) -> DropoffBoardInfo {
        DropoffBoard.compute(
            name: "Miller",
            feeds: feeds, diapers: diapers, sleeps: sleeps, notes: notes,
            nightStartMinute: 20 * 60, nightEndMinute: 7 * 60,
            dayStart: dayStart, now: now ?? today(hour: 7, minute: 45),
            calendar: calendar)
    }

    // MARK: Rows

    func testLastBottleAndDiaperAreTheNewestRows() {
        let info = board(
            feeds: [.init(timestamp: today(hour: 6, minute: 45), amountOz: 4),
                    .init(timestamp: yesterday(hour: 22), amountOz: 5)],
            diapers: [.init(timestamp: today(hour: 7, minute: 10), typeLabel: "Wet")])
        XCTAssertEqual(info.lastBottle, "\(TimeFormatting.clock(today(hour: 6, minute: 45))) · 4 oz")
        XCTAssertEqual(info.lastDiaper, "\(TimeFormatting.clock(today(hour: 7, minute: 10))) · wet")
    }

    func testEmptyMorningLeavesEveryRowNil() {
        let info = board()
        XCTAssertNil(info.lastBottle)
        XCTAssertNil(info.lastDiaper)
        XCTAssertNil(info.wokeUpAt)
        XCTAssertNil(info.overnightSleep)
        XCTAssertNil(info.notes)
    }

    func testOvernightSumsOnlyTheNightWindow() {
        // 9:30 PM → 6:30 AM stretch counts whole (9h); a 4 PM nap yesterday
        // counts nothing; the live 7:30 AM nap (no end) hasn't entered tonight.
        let info = board(sleeps: [
            .init(startedAt: today(hour: 7, minute: 30), endedAt: nil),
            .init(startedAt: yesterday(hour: 21, minute: 30), endedAt: today(hour: 6, minute: 30)),
            .init(startedAt: yesterday(hour: 16), endedAt: yesterday(hour: 17)),
        ])
        XCTAssertEqual(info.overnightSleep, "9h — slept well")
        XCTAssertEqual(info.wokeUpAt, TimeFormatting.clock(today(hour: 6, minute: 30)),
                       "wake time is the newest ENDED sleep, not the live nap")
    }

    func testSleepQualityThresholds() {
        XCTAssertEqual(
            board(sleeps: [.init(startedAt: yesterday(hour: 22), endedAt: today(hour: 5, minute: 30))])
                .overnightSleep, "7h 30m — slept okay")
        XCTAssertEqual(
            board(sleeps: [.init(startedAt: yesterday(hour: 23), endedAt: today(hour: 4))])
                .overnightSleep, "5h — a restless night")
    }

    func testNotesAreTheParentsOwnSinceTheNightOpenedOldestFirst() {
        let info = board(notes: [
            .init(timestamp: today(hour: 7), text: "Teething", isFromDaycare: false),
            .init(timestamp: today(hour: 6), text: "Had a great day!", isFromDaycare: true),
            .init(timestamp: yesterday(hour: 22), text: "A little congested", isFromDaycare: false),
            .init(timestamp: yesterday(hour: 15), text: "Yesterday's errand", isFromDaycare: false),
        ])
        XCTAssertEqual(info.notes, "A little congested · Teething")
    }
}
