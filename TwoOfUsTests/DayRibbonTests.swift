import XCTest
import SwiftData
@testable import TwoOfUs

/// Covers `RibbonMark.forDay`, especially the active-sleep (`endedAt == nil`)
/// clipping the History swimlane depends on. Regression guard for the bug where
/// an in-progress sleep collapsed to a 0-width sliver at the lane's own midnight
/// instead of spanning to the lane's real end. Fixed past dates keep it
/// deterministic even though `forDay` clips an active sleep to `Date()`.
@MainActor
final class DayRibbonTests: XCTestCase {
    private var container: ModelContainer!
    private var cal = Calendar(identifier: .gregorian)

    override func setUp() {
        super.setUp()
        container = AppModelContainer.make(inMemory: true)
        cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    private func d(_ y: Int, _ mo: Int, _ dd: Int, _ h: Int, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: dd, hour: h, minute: mi))!
    }

    private func makeSleep(from: Date, to: Date?) -> SleepEvent {
        let s = SleepEvent(baby: nil, startedAt: from, endedAt: to, loggedByID: UUID(),
                           loggedByName: "T", loggedByColorHex: "#AABBCC", deletedAt: nil)
        container.mainContext.insert(s)
        return s
    }

    /// An active sleep on a past lane spans from its start to the lane's END
    /// (next midnight) — never an inverted 0-width sliver at the lane's own start.
    func testActiveSleepSpansPastLaneInsteadOfSliver() {
        let laneDay = d(2020, 1, 1, 0, 0)                 // a fixed past day
        let s = makeSleep(from: d(2020, 1, 1, 10, 0), to: nil)  // started 10:00, still going
        let marks = RibbonMark.forDay(laneDay, feeds: [], sleeps: [s], diapers: [], calendar: cal)
            .filter { $0.kind == .sleep }
        XCTAssertEqual(marks.count, 1)
        XCTAssertEqual(marks[0].start, d(2020, 1, 1, 10, 0))
        XCTAssertEqual(marks[0].end, d(2020, 1, 2, 0, 0))   // clipped to lane end, a real span
        XCTAssertGreaterThan(marks[0].end!, marks[0].start) // the bug: end <= start
    }

    /// A completed sleep crossing into the lane is clipped to the lane's bounds.
    func testCompletedSleepClippedToLaneBounds() {
        let laneDay = d(2020, 1, 1, 0, 0)
        let s = makeSleep(from: d(2019, 12, 31, 23, 0), to: d(2020, 1, 1, 1, 0))
        let marks = RibbonMark.forDay(laneDay, feeds: [], sleeps: [s], diapers: [], calendar: cal)
            .filter { $0.kind == .sleep }
        XCTAssertEqual(marks.count, 1)
        XCTAssertEqual(marks[0].start, d(2020, 1, 1, 0, 0))   // clipped to lane start
        XCTAssertEqual(marks[0].end, d(2020, 1, 1, 1, 0))
    }

    /// A sleep entirely outside the lane produces no mark.
    func testSleepOutsideLaneIsExcluded() {
        let laneDay = d(2020, 1, 1, 0, 0)
        let s = makeSleep(from: d(2020, 1, 3, 10, 0), to: d(2020, 1, 3, 11, 0))
        let marks = RibbonMark.forDay(laneDay, feeds: [], sleeps: [s], diapers: [], calendar: cal)
            .filter { $0.kind == .sleep }
        XCTAssertTrue(marks.isEmpty)
    }
}
