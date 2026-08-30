import XCTest
import SwiftData
@testable import TwoOfUs

/// AskEngine + QueryParser are pure with injectable `calendar`/`now`, so every
/// test runs against a fixed clock (2026-06-10 12:00 UTC) and UTC calendar —
/// same conventions as StatsEngineTests.
@MainActor
final class AskEngineTests: XCTestCase {
    private var container: ModelContainer!
    private var calendar = Calendar(identifier: .gregorian)
    private var now = Date()

    override func setUp() {
        super.setUp()
        container = AppModelContainer.make(inMemory: true)
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        now = date(2026, 6, 10, 12, 0)
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    // MARK: Builders

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    private func feed(_ oz: Double, at: Date, by name: String = "Taylor",
                      deleted: Bool = false) -> FeedEvent {
        let f = FeedEvent(baby: nil, amountOz: oz, timestamp: at, loggedByID: UUID(),
                          loggedByName: name, loggedByColorHex: "#AABBCC",
                          deletedAt: deleted ? at : nil)
        container.mainContext.insert(f)
        return f
    }

    private func sleep(from: Date, to: Date?, deleted: Bool = false) -> SleepEvent {
        let s = SleepEvent(baby: nil, startedAt: from, endedAt: to, loggedByID: UUID(),
                           loggedByName: "Taylor", loggedByColorHex: "#AABBCC",
                           deletedAt: deleted ? from : nil)
        container.mainContext.insert(s)
        return s
    }

    private func diaper(_ type: DiaperType = .wet, at: Date, deleted: Bool = false) -> DiaperEvent {
        let d = DiaperEvent(baby: nil, type: type, timestamp: at, loggedByID: UUID(),
                            loggedByName: "Taylor", loggedByColorHex: "#AABBCC",
                            deletedAt: deleted ? at : nil)
        container.mainContext.insert(d)
        return d
    }

    private func note(_ text: String, at: Date) -> NoteEvent {
        let n = NoteEvent(baby: nil, text: text, timestamp: at, loggedByID: UUID(),
                          loggedByName: "Taylor", loggedByColorHex: "#AABBCC")
        container.mainContext.insert(n)
        return n
    }

    private func engine(feeds: [FeedEvent] = [], sleeps: [SleepEvent] = [],
                        diapers: [DiaperEvent] = [], notes: [NoteEvent] = []) -> AskEngine {
        var e = AskEngine()
        e.feeds = feeds
        e.sleeps = sleeps
        e.diapers = diapers
        e.notes = notes
        e.babyName = "Miller"
        e.calendar = calendar
        e.now = now
        return e
    }

    // MARK: - QueryParser: the motivating questions

    func testParserBedtimeLastNight() {
        let q = QueryParser.parse("What time did he go to sleep last night?")
        XCTAssertEqual(q, ParsedQuery(metric: .bedtime, period: .lastNight))
    }

    func testParserTotalSleepLastNight() {
        let q = QueryParser.parse("How much did he sleep last night?")
        XCTAssertEqual(q, ParsedQuery(metric: .totalSleep, period: .lastNight))
    }

    func testParserTotalSleepDefaultsToLastNight() {
        XCTAssertEqual(QueryParser.parse("how long did he sleep")?.period, .lastNight)
    }

    func testParserNightWakes() {
        let q = QueryParser.parse("How many times did he wake up last night?")
        XCTAssertEqual(q, ParsedQuery(metric: .nightWakes, period: .lastNight))
    }

    func testParserFeedOzToday() {
        let q = QueryParser.parse("How many ounces did he eat today?")
        XCTAssertEqual(q, ParsedQuery(metric: .feedOz, period: .today))
    }

    func testParserFeedCount() {
        let q = QueryParser.parse("How many times did he eat today?")
        XCTAssertEqual(q, ParsedQuery(metric: .feedCount, period: .today))
    }

    func testParserSleepComparisonThisWeekVsLastWeek() {
        let q = QueryParser.parse("Is he sleeping more this week than last week?")
        XCTAssertEqual(q, ParsedQuery(metric: .totalSleep, period: .thisWeek, compareTo: .lastWeek))
    }

    func testParserEatingMoreThanUsual() {
        let q = QueryParser.parse("Is he eating more than usual?")
        XCTAssertEqual(q?.metric, .feedOz)
        XCTAssertEqual(q?.compareTo, .lastWeek)
    }

    func testParserLongestStretchDefaultsAllTime() {
        let q = QueryParser.parse("What's his longest sleep stretch?")
        XCTAssertEqual(q, ParsedQuery(metric: .longestStretch, period: .allTime))
    }

    func testParserLongestStretchThisWeek() {
        XCTAssertEqual(QueryParser.parse("longest sleep this week")?.period, .thisWeek)
    }

    func testParserLastFeed() {
        XCTAssertEqual(QueryParser.parse("When did he last eat?")?.metric, .lastFeed)
        XCTAssertEqual(QueryParser.parse("when was the last bottle")?.metric, .lastFeed)
    }

    func testParserLastDiaperWithType() {
        XCTAssertEqual(QueryParser.parse("When was his last dirty diaper?")?.metric,
                       .lastDiaper(.dirty))
        XCTAssertEqual(QueryParser.parse("when was the last wet diaper")?.metric,
                       .lastDiaper(.wet))
    }

    func testParserDidHePoopToday() {
        let q = QueryParser.parse("Did he poop today?")
        XCTAssertEqual(q, ParsedQuery(metric: .diaperCount(.dirty), period: .today))
    }

    func testParserSleepStatus() {
        XCTAssertEqual(QueryParser.parse("Is he still asleep?")?.metric, .sleepStatus)
        XCTAssertEqual(QueryParser.parse("how long has he been sleeping")?.metric, .sleepStatus)
    }

    func testParserPredictions() {
        XCTAssertEqual(QueryParser.parse("When will he want to eat next?")?.metric, .nextFeed)
        XCTAssertEqual(QueryParser.parse("when is his next nap")?.metric, .nextNap)
        XCTAssertEqual(QueryParser.parse("when will he wake up")?.metric, .wakeUp)
    }

    func testParserAverageBottle() {
        XCTAssertEqual(QueryParser.parse("what's his average bottle size")?.metric, .averageBottle)
    }

    func testParserFeedInterval() {
        XCTAssertEqual(QueryParser.parse("how often does he eat")?.metric, .averageFeedInterval)
    }

    func testParserNoteSearch() {
        guard case .noteSearch(let needle)? = QueryParser.parse("when did we start vitamin d drops")?.metric else {
            return XCTFail("expected noteSearch")
        }
        XCTAssertTrue(needle.contains("vitamin"))
        XCTAssertTrue(needle.contains("drops"))
    }

    func testParserGibberishReturnsNil() {
        XCTAssertNil(QueryParser.parse("purple monkey dishwasher"))
        XCTAssertNil(QueryParser.parse(""))
    }

    // MARK: - Engine: night window

    /// Night = 20:00–08:00 defaults. At noon on Jun 10, "last night" is
    /// Jun 9 20:00 → Jun 10 08:00.
    func testLastNightWindowAtNoon() {
        let e = engine()
        let w = e.interval(for: .lastNight)
        XCTAssertEqual(w.start, date(2026, 6, 9, 20, 0))
        XCTAssertEqual(w.end, date(2026, 6, 10, 8, 0))
    }

    /// At 3am the night is in progress: started yesterday 20:00, ends "now".
    func testLastNightWindowAt3am() {
        var e = engine()
        e.now = date(2026, 6, 10, 3, 0)
        let w = e.interval(for: .lastNight)
        XCTAssertEqual(w.start, date(2026, 6, 9, 20, 0))
        XCTAssertEqual(w.end, date(2026, 6, 10, 3, 0))
    }

    /// At 11pm "last night" is TONIGHT, which started an hour ago.
    func testLastNightWindowAt11pm() {
        var e = engine()
        e.now = date(2026, 6, 10, 23, 0)
        let w = e.interval(for: .lastNight)
        XCTAssertEqual(w.start, date(2026, 6, 10, 20, 0))
        XCTAssertEqual(w.end, date(2026, 6, 10, 23, 0))
    }

    // MARK: - Engine: the motivating question, end to end

    func testBedtimeLastNight() {
        // Nap that RAN INTO the window must not count as bedtime; the 19:45
        // start is before nightStart, the 20:30 one is the real bedtime.
        let sleeps = [
            sleep(from: date(2026, 6, 9, 16, 0), to: date(2026, 6, 9, 17, 0)),
            sleep(from: date(2026, 6, 9, 20, 30), to: date(2026, 6, 10, 2, 0)),
            sleep(from: date(2026, 6, 10, 2, 40), to: date(2026, 6, 10, 7, 30)),
        ]
        let a = engine(sleeps: sleeps).answer(ParsedQuery(metric: .bedtime, period: .lastNight))
        XCTAssertTrue(a.sentence.contains("Miller went down at"), a.sentence)
        // Clock strings render in the device time zone — compare via the
        // same formatter rather than assuming UTC.
        XCTAssertTrue(a.sentence.contains(TimeFormatting.clock(date(2026, 6, 9, 20, 30))), a.sentence)
        XCTAssertEqual(a.facts.first?.label, "Down at")
    }

    func testTotalSleepLastNightClipsToWindow() {
        // 19:00–21:00 sleep: only 20:00–21:00 falls inside the night window.
        // Plus 22:00–06:00 = 8h. Total = 9h.
        let sleeps = [
            sleep(from: date(2026, 6, 9, 19, 0), to: date(2026, 6, 9, 21, 0)),
            sleep(from: date(2026, 6, 9, 22, 0), to: date(2026, 6, 10, 6, 0)),
        ]
        let a = engine(sleeps: sleeps).answer(ParsedQuery(metric: .totalSleep, period: .lastNight))
        XCTAssertTrue(a.sentence.contains("9h"), a.sentence)
    }

    func testNightWakesCountsGapsBetweenSessions() {
        let sleeps = [
            sleep(from: date(2026, 6, 9, 20, 30), to: date(2026, 6, 10, 1, 0)),
            sleep(from: date(2026, 6, 10, 1, 30), to: date(2026, 6, 10, 4, 0)),
            sleep(from: date(2026, 6, 10, 4, 30), to: date(2026, 6, 10, 7, 0)),
        ]
        let a = engine(sleeps: sleeps).answer(ParsedQuery(metric: .nightWakes, period: .lastNight))
        XCTAssertTrue(a.sentence.contains("woke 2 times"), a.sentence)
    }

    // MARK: - Engine: aggregates & comparison

    func testFeedOzTodayIgnoresDeletedAndYesterday() {
        let feeds = [
            feed(3, at: date(2026, 6, 10, 8, 0)),
            feed(4, at: date(2026, 6, 10, 11, 0)),
            feed(5, at: date(2026, 6, 10, 9, 0), deleted: true),
            feed(6, at: date(2026, 6, 9, 9, 0)),
        ]
        let a = engine(feeds: feeds).answer(ParsedQuery(metric: .feedOz, period: .today))
        XCTAssertTrue(a.sentence.contains("7 oz"), a.sentence)
        XCTAssertTrue(a.sentence.contains("2 feeds"), a.sentence)
    }

    func testSleepComparisonMoreThanLastWeek() {
        var sleeps: [SleepEvent] = []
        // This week (Jun 4–10): 10h/night. Last week (May 28–Jun 3): 8h/night.
        for day in 4...9 {
            sleeps.append(sleep(from: date(2026, 6, day, 21, 0), to: date(2026, 6, day + 1, 7, 0)))
        }
        for day in 28...31 {
            sleeps.append(sleep(from: date(2026, 5, day, 21, 0),
                                to: calendar.date(byAdding: .hour, value: 8, to: date(2026, 5, day, 21, 0))!))
        }
        for day in 1...2 {
            sleeps.append(sleep(from: date(2026, 6, day, 21, 0), to: date(2026, 6, day + 1, 5, 0)))
        }
        let a = engine(sleeps: sleeps).answer(
            ParsedQuery(metric: .totalSleep, period: .thisWeek, compareTo: .lastWeek))
        XCTAssertTrue(a.sentence.contains("more than last week"), a.sentence)
    }

    func testComparisonAgainstEmptyBaselineOmitted() {
        let feeds = [feed(4, at: date(2026, 6, 10, 8, 0))]
        let a = engine(feeds: feeds).answer(
            ParsedQuery(metric: .feedOz, period: .today, compareTo: .lastWeek))
        XCTAssertFalse(a.sentence.contains("%"), a.sentence)
    }

    func testDirtyDiaperCountFiltersType() {
        let ds = [
            diaper(.wet, at: date(2026, 6, 10, 8, 0)),
            diaper(.dirty, at: date(2026, 6, 10, 9, 0)),
            diaper(.dirty, at: date(2026, 6, 10, 10, 0)),
        ]
        let a = engine(diapers: ds).answer(ParsedQuery(metric: .diaperCount(.dirty), period: .today))
        XCTAssertTrue(a.sentence.contains("2 dirty"), a.sentence)
    }

    // MARK: - Engine: lookups & predictions

    func testLastFeedIncludesWho() {
        let feeds = [feed(4, at: date(2026, 6, 10, 9, 0), by: "Girl Taylor")]
        let a = engine(feeds: feeds).answer(ParsedQuery(metric: .lastFeed, period: .today))
        XCTAssertTrue(a.sentence.contains("Girl Taylor"), a.sentence)
        XCTAssertTrue(a.facts.contains { $0.label == "Logged by" && $0.value == "Girl Taylor" })
    }

    func testSleepStatusActive() {
        let sleeps = [sleep(from: date(2026, 6, 10, 11, 0), to: nil)]
        let a = engine(sleeps: sleeps).answer(ParsedQuery(metric: .sleepStatus, period: .today))
        XCTAssertTrue(a.sentence.contains("has been asleep for 1h"), a.sentence)
    }

    func testNextFeedUsesInjectedInterval() {
        var e = engine(feeds: [feed(4, at: date(2026, 6, 10, 11, 0))])
        e.feedIntervalAfter = { _ in 3 * 3600 }
        let a = e.answer(ParsedQuery(metric: .nextFeed, period: .today))
        XCTAssertTrue(a.sentence.contains(TimeFormatting.clock(date(2026, 6, 10, 14, 0))), a.sentence)
    }

    func testWakeUpUsesMedianOfRecentSleeps() {
        var sleeps: [SleepEvent] = []
        for day in 7...9 {   // three 2h naps this week → median 2h
            sleeps.append(sleep(from: date(2026, 6, day, 13, 0), to: date(2026, 6, day, 15, 0)))
        }
        sleeps.append(sleep(from: date(2026, 6, 10, 11, 30), to: nil))
        let a = engine(sleeps: sleeps).answer(ParsedQuery(metric: .wakeUp, period: .today))
        XCTAssertTrue(a.sentence.contains(TimeFormatting.clock(date(2026, 6, 10, 13, 30))), a.sentence)
    }

    // MARK: - Engine: notes

    func testNoteSearchFindsEarliestBestMatch() {
        let ns = [
            note("Started vitamin D drops today", at: date(2026, 6, 2, 9, 0)),
            note("Vitamin D drops given", at: date(2026, 6, 8, 9, 0)),
        ]
        let a = engine(notes: ns).answer(
            ParsedQuery(metric: .noteSearch("vitamin d drops"), period: .allTime))
        XCTAssertTrue(a.sentence.contains("Jun 2"), a.sentence)
        XCTAssertTrue(a.sentence.contains("Started vitamin D drops"), a.sentence)
    }

    func testNoteSearchNoMatch() {
        let a = engine().answer(ParsedQuery(metric: .noteSearch("zebra"), period: .allTime))
        XCTAssertTrue(a.sentence.contains("No notes mention"), a.sentence)
    }
}
