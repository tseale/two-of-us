import XCTest
@testable import TwoOfUs

final class DayHighlightsTests: XCTestCase {
    private let day = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ hours: Double) -> Date { day.addingTimeInterval(hours * 3600) }

    func testAnEmptyDayHasNoHighlights() {
        XCTAssertTrue(DayHighlights.build(name: "Miller").isEmpty)
    }

    func testARecordStretchIsCalledOut() {
        let items = DayHighlights.build(name: "Miller",
                                        sleeps: [.init(start: at(0), end: at(4))],
                                        earlierBestStretch: 3.5 * 3600)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].emoji, "🎉")
        XCTAssertEqual(items[0].text, "Miller's longest stretch yet: 4h")
        XCTAssertEqual(items[0].detail, "beat 3h 30m from earlier this month")
    }

    func testAGoodStretchThatIsNoRecordIsStillWorthALine() {
        let items = DayHighlights.build(name: "Miller",
                                        sleeps: [.init(start: at(0), end: at(2.5))],
                                        earlierBestStretch: 5 * 3600)
        XCTAssertEqual(items.map(\.text), ["Slept 2h 30m straight"])
    }

    func testAShortNapIsRoutine() {
        XCTAssertTrue(DayHighlights.build(name: "Miller",
                                          sleeps: [.init(start: at(9), end: at(10))],
                                          earlierBestStretch: 5 * 3600).isEmpty)
    }

    func testTheBiggestBottleNeedsSomethingToBeat() {
        XCTAssertTrue(DayHighlights.build(name: "M", feeds: [.init(time: at(1), oz: 4)]).isEmpty)
        XCTAssertTrue(DayHighlights.build(name: "M", feeds: [.init(time: at(1), oz: 4),
                                                             .init(time: at(4), oz: 4)]).isEmpty)
        let items = DayHighlights.build(name: "M", feeds: [.init(time: at(1), oz: 4),
                                                           .init(time: at(4), oz: 5.5)])
        XCTAssertEqual(items.map(\.text), ["Biggest bottle: 5.5 oz"])
        XCTAssertEqual(items.first?.time, at(4))
    }

    func testPhotosBecomeOneLineAtTheFirstPhoto() {
        let items = DayHighlights.build(name: "M", photoTimes: [at(12), at(10), at(11)])
        XCTAssertEqual(items.map(\.text), ["3 photos from daycare"])
        XCTAssertEqual(items.first?.time, at(10))
        XCTAssertEqual(DayHighlights.build(name: "M", photoTimes: [at(9)]).first?.text,
                       "A photo from daycare")
    }

    func testTheHeaviestAreKeptAndToldInOrder() {
        let items = DayHighlights.build(
            name: "M",
            milestones: [.init(time: at(15), emoji: "🏆", text: "First laugh")],
            notes: [.init(time: at(8), emoji: "📝", text: "Took the slow-flow bottle")],
            activities: [.init(time: at(10), emoji: "🎨", text: "Tummy time")],
            checks: [.init(time: at(7), emoji: "🏫", text: "Dropped off at daycare")],
            limit: 3)
        // The drop-off is the lightest of the four and is left out…
        XCTAssertEqual(items.map(\.text), ["Took the slow-flow bottle", "Tummy time", "First laugh"])
        // …and what is kept runs in time order.
        XCTAssertEqual(items.map(\.time), [at(8), at(10), at(15)])
    }

    func testFormatting() {
        XCTAssertEqual(DayHighlights.duration(45 * 60), "45m")
        XCTAssertEqual(DayHighlights.duration(2 * 3600), "2h")
        XCTAssertEqual(DayHighlights.duration(3 * 3600 + 50 * 60), "3h 50m")
        XCTAssertEqual(DayHighlights.oz(4), "4")
        XCTAssertEqual(DayHighlights.oz(4.5), "4.5")
        XCTAssertEqual(DayHighlights.oz(3.75), "3.75")
    }
}
