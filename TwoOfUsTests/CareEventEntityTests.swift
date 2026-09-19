import XCTest
@testable import TwoOfUs

/// `CareEventEntity` is what Siri, Spotlight, and Shortcuts see, so the
/// mapping from the models — and the strings Spotlight indexes — is the
/// contract. Models are built standalone (never inserted into a store).
final class CareEventEntityTests: XCTestCase {

    private let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now)!
    private let taylor = UUID()

    private func feed(oz: Double = 3, by name: String = "Taylor", notes: String? = nil) -> FeedEvent {
        FeedEvent(baby: nil, amountOz: oz, timestamp: noon, notes: notes,
                  loggedByID: taylor, loggedByName: name, loggedByColorHex: "#000000")
    }

    private func diaper(_ type: DiaperType, by name: String = "GT") -> DiaperEvent {
        DiaperEvent(baby: nil, type: type, timestamp: noon,
                    loggedByID: taylor, loggedByName: name, loggedByColorHex: "#000000")
    }

    func testFeedMapsAmountAndLogger() {
        let entity = CareEventEntity(feed: feed(oz: 3.5, notes: "sleepy"), babyName: "Miller")

        XCTAssertEqual(entity.kind, CareEventKind.feed)
        XCTAssertEqual(entity.amountOz, 3.5)
        XCTAssertEqual(entity.title, "🍼 3.5 oz bottle")
        XCTAssertTrue(entity.subtitle.hasSuffix("· Taylor"))
        XCTAssertEqual(entity.note, "sleepy")
    }

    func testSleepDurationOnlyOnceEnded() {
        let sleep = SleepEvent(baby: nil, startedAt: noon,
                               loggedByID: taylor, loggedByName: "Taylor", loggedByColorHex: "#000000")
        XCTAssertNil(CareEventEntity(sleep: sleep, babyName: "Miller").durationMinutes)
        XCTAssertEqual(CareEventEntity(sleep: sleep, babyName: "Miller").title, "💤 Sleeping")

        sleep.endedAt = noon.addingTimeInterval(95 * 60)
        let ended = CareEventEntity(sleep: sleep, babyName: "Miller")
        XCTAssertEqual(ended.durationMinutes, 95)
        XCTAssertEqual(ended.title, "💤 Slept 1h 35m")
    }

    func testDiaperTypeAndNoteText() {
        XCTAssertEqual(CareEventEntity(diaper: diaper(.dirty), babyName: "Miller").title, "💩 Dirty diaper")

        let note = NoteEvent(baby: nil, text: "First smile", timestamp: noon,
                             loggedByID: taylor, loggedByName: "Taylor", loggedByColorHex: "#000000")
        XCTAssertEqual(CareEventEntity(note: note, babyName: "Miller").title, "📝 First smile")
    }

    func testSpotlightAttributesCarryNameKindAndTime() {
        let attributes = CareEventEntity(diaper: diaper(.dirty), babyName: "Miller").attributeSet

        XCTAssertEqual(attributes.title, "💩 Dirty diaper")
        XCTAssertEqual(attributes.contentCreationDate, noon)
        XCTAssertTrue(attributes.contentDescription?.hasPrefix("Miller · ") ?? false)
        XCTAssertEqual(attributes.keywords, ["Miller", "diaper", "dirty"])
    }

    func testEmptyLoggerNameLeavesSubtitleAsTimeOnly() {
        let entity = CareEventEntity(feed: feed(by: ""), babyName: "Miller")
        XCTAssertFalse(entity.subtitle.contains("·"))
    }
}
