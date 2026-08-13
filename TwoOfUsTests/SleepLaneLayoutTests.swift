import XCTest
@testable import TwoOfUs

/// Pure-geometry tests for the schedule's sleep lanes: spans → per-element
/// band runs in row-local coordinates (0 top, 0.5 node line, 1 bottom), each
/// end flagged as a real transition (rounded, 💤 on fall-asleep) or a
/// continuation (squared and fused with the neighboring row). Same idiom as
/// the engine tests — fixtures, pinned dates, no store.
final class SleepLaneLayoutTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        return c
    }()

    private let taylorID = UUID()   // "BT" — lane 0
    private let katieID = UUID()    // "GT" — lane 1

    private func date(_ d: Int, _ h: Int, _ mi: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: d, hour: h, minute: mi))!
    }

    /// (lower, upper, startsHere, endsHere) per expected run.
    private func assertRuns(_ slice: SleepLaneLayout.Slice,
                            _ expected: [(Double, Double, Bool, Bool)],
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(slice.runs.count, expected.count, "run count", file: file, line: line)
        for (run, exp) in zip(slice.runs, expected) {
            XCTAssertEqual(run.range.lowerBound, exp.0, accuracy: 0.005, file: file, line: line)
            XCTAssertEqual(run.range.upperBound, exp.1, accuracy: 0.005, file: file, line: line)
            XCTAssertEqual(run.startsHere, exp.2, "startsHere", file: file, line: line)
            XCTAssertEqual(run.endsHere, exp.3, "endsHere", file: file, line: line)
        }
    }

    // MARK: The drifted night from the field

    /// The real night the lanes exist for: GT front-loads 8pm–2:30am then naps
    /// 3–5:30; BT sleeps 1–9am; bottles anchored 27 minutes late at 10:27pm,
    /// every 2½h. Elements are the rail's list order: NOW (8:08pm) + bottles.
    private func driftedNight() -> SleepLaneLayout {
        SleepLaneLayout(
            elementDates: [date(12, 20, 8), date(12, 22, 27), date(13, 0, 57),
                           date(13, 3, 27), date(13, 5, 57)],
            laneParentIDs: [taylorID, katieID],
            spans: [
                .init(id: "gt-night", parentID: katieID, start: date(12, 20, 0), end: date(13, 2, 30)),
                .init(id: "gt-nap1", parentID: katieID, start: date(13, 3, 0), end: date(13, 5, 30)),
                .init(id: "gt-nap2", parentID: katieID, start: date(13, 6, 0), end: date(13, 7, 45)),
                .init(id: "bt-night", parentID: taylorID, start: date(13, 1, 0), end: date(13, 9, 0)),
            ])
    }

    func testInProgressBlockRunsOffTheTopEdgeUnbroken() {
        let slices = driftedNight().slices
        // At the NOW cap, GT has been down since 8:00 — before the first
        // element — so her band fills edge to edge with both ends open
        // (squared + bled), never a per-row pill.
        assertRuns(slices[0][1], [(0, 1, false, false)])
        XCTAssertTrue(slices[0][1].asleepAtNode)
        XCTAssertEqual(slices[0][1].primarySpanID, "gt-night")
        // BT is up all evening: nothing in his lane.
        assertRuns(slices[0][0], [])
        XCTAssertNil(slices[0][0].primarySpanID)
        // And through the 10:27 bottle her band stays one open ribbon — no
        // transition flags anywhere mid-block. (The 12:57 element carries her
        // 2:30 wake, handed back from the cramped row below — see
        // `testCrampedWakeCapMovesToTheRowWithRoomForIt`.)
        assertRuns(slices[1][1], [(0, 1, false, false)])
    }

    func testFallAsleepEndIsRealBetweenRows() {
        let slices = driftedNight().slices
        // BT falls asleep 1:00 — three minutes after the 12:57 bottle. His
        // band starts just below that node (y = 0.5 + 0.5·(3/75)) with a REAL
        // top (rounded, 💤) and an open bottom continuing into the next row.
        assertRuns(slices[2][0], [(0.52, 1, true, false)])
        XCTAssertFalse(slices[2][0].asleepAtNode, "12:57 is before his window")
    }

    func testGetUpGapRendersAsAVisibleNotch() {
        let slices = driftedNight().slices
        // Between the 12:57 and 3:27 bottles GT is up 2:30–3:00. Her 3:00 nap
        // starts for real at y = 0.5·(48/75) of the 3:27 element's top half
        // (midpoint 2:12) — a rounded, 💤-bearing fall-asleep end. The notch
        // above it is the visible gap back to her 2:30 wake.
        assertRuns(slices[3][1], [(0.32, 1, true, false)])
        XCTAssertTrue(slices[3][1].asleepAtNode, "3:27 falls inside the nap")
        XCTAssertEqual(slices[3][1].primarySpanID, "gt-nap1",
                       "the band tap opens the window that covers the bottle")
        // BT sleeps through 3:27 — the both-asleep overlap reads as two
        // filled lanes side by side.
        assertRuns(slices[3][0], [(0, 1, false, false)])
        XCTAssertTrue(slices[3][0].asleepAtNode)
    }

    func testWakeEndAndClampedTailAtTheLastRow() {
        let slices = driftedNight().slices
        // GT is up at the 5:57 bottle; her nap ended 5:30 → a real wake end
        // at y = 0.5·(48/75) of the last element's top half, nothing below.
        assertRuns(slices[4][1], [(0, 0.32, false, true)])
        XCTAssertFalse(slices[4][1].asleepAtNode)
        XCTAssertEqual(slices[4][1].primarySpanID, "gt-nap1")
        // BT sleeps to 9:00 — past the rail — so his band runs off the
        // bottom edge, open-ended.
        assertRuns(slices[4][0], [(0, 1, false, false)])
    }

    func testWindowBeyondTheLastElementContributesNothing() {
        // GT's 6:00–7:45 nap starts after the last bottle (5:57): no run
        // anywhere mentions it — the standing-plan list below the timeline
        // still shows every window.
        let all = driftedNight().slices.flatMap { $0 }
        XCTAssertEqual(all.filter { $0.runs.contains(where: \.startsHere) }.count, 2,
                       "only BT's 1:00 and GT's 3:00 begin on the rail")
        XCTAssertFalse(all.contains { $0.primarySpanID == "gt-nap2" })
    }

    // MARK: Cap hand-off

    func testCrampedWakeCapMovesToTheRowWithRoomForIt() {
        let slices = driftedNight().slices
        // GT wakes 2:30, only 18 of the 3:27 element's 75-minute top half past
        // its boundary — a stub far too short to round off (and the flattened
        // corners read as a rendering bug). The wake is drawn by the 12:57
        // element instead, as a real end on its trailing run.
        assertRuns(slices[2][1], [(0, 1, false, true)])
        XCTAssertFalse(slices[3][1].runs.contains { $0.range.lowerBound < 0.001 },
                       "no leftover stub at the top of the row below")
    }

    func testCrampedFallAsleepCapMovesToTheNextRow() {
        // BT lies down at 11:39 — three minutes before the 10:27/12:57 row
        // boundary. The sliver left in the upper row can't draw the cap or
        // hold the 💤, so the whole block (cap included) starts below.
        let layout = SleepLaneLayout(
            elementDates: [date(12, 22, 27), date(13, 0, 57), date(13, 3, 27)],
            laneParentIDs: [taylorID],
            spans: [.init(id: "bt", parentID: taylorID,
                          start: date(12, 23, 39), end: date(13, 6, 0))])
        assertRuns(layout.slices[0][0], [])
        assertRuns(layout.slices[1][0], [(0, 1, true, false)])
        assertRuns(layout.slices[2][0], [(0, 1, false, false)])
    }

    func testShortWindowInsideOneRowKeepsBothItsEnds() {
        // A ten-minute doze is a whole block, not a stub of a bigger one: it
        // stays put and keeps both ends, however small the pill.
        let layout = SleepLaneLayout(
            elementDates: [date(13, 0, 57), date(13, 3, 27)],
            laneParentIDs: [katieID],
            spans: [.init(id: "doze", parentID: katieID,
                          start: date(13, 2, 0), end: date(13, 2, 10))])
        assertRuns(layout.slices[0][0], [(0.92, 0.99, true, true)])
        assertRuns(layout.slices[1][0], [])
    }

    // MARK: The rail's terminal wake element

    func testTerminalWakeElementCapsTheLongestSleeper() {
        // The last bottle is 5:57 but BT sleeps to 9:00. The schedule appends
        // an element at the night's last wake so his band ends in a real cap
        // instead of running off the bottom — and GT's 6:00 nap, wholly past
        // the last bottle, becomes visible at all.
        let layout = SleepLaneLayout(
            elementDates: [date(12, 20, 8), date(12, 22, 27), date(13, 0, 57),
                           date(13, 3, 27), date(13, 5, 57), date(13, 9, 0)],
            laneParentIDs: [taylorID, katieID],
            spans: [
                .init(id: "gt-night", parentID: katieID, start: date(12, 20, 0), end: date(13, 2, 30)),
                .init(id: "gt-nap1", parentID: katieID, start: date(13, 3, 0), end: date(13, 5, 30)),
                .init(id: "gt-nap2", parentID: katieID, start: date(13, 6, 0), end: date(13, 7, 45)),
                .init(id: "bt-night", parentID: taylorID, start: date(13, 1, 0), end: date(13, 9, 0)),
            ])
        // 5:57 is a middle element now: his band passes through open-ended…
        assertRuns(layout.slices[4][0], [(0, 1, false, false)])
        // …and ends for real on the terminal element's node line.
        assertRuns(layout.slices[5][0], [(0, 0.5, false, true)])
        // GT's nap runs 6:00–7:45, both ends real. Its wake is a stub in the
        // terminal element, so the 5:57 element draws it.
        assertRuns(layout.slices[4][1], [(0, 0.32, false, true), (0.52, 1, true, true)])
        assertRuns(layout.slices[5][1], [])
    }

    // MARK: Merging and edges

    func testTouchingWindowsMergeIntoOneBlock() {
        // 10–11pm touching 11pm–1am: one block — a single real fall-asleep at
        // 10:00 (y = 0.5 + 0.5·(30/75)) and NO seam at 11pm: the second
        // element shows one open ribbon.
        let layout = SleepLaneLayout(
            elementDates: [date(12, 21, 30), date(13, 0, 0)],
            laneParentIDs: [katieID],
            spans: [
                .init(id: "a", parentID: katieID, start: date(12, 22, 0), end: date(12, 23, 0)),
                .init(id: "b", parentID: katieID, start: date(12, 23, 0), end: date(13, 1, 0)),
            ])
        assertRuns(layout.slices[0][0], [(0.7, 1, true, false)])
        assertRuns(layout.slices[1][0], [(0, 1, false, false)])
        XCTAssertEqual(layout.slices[1][0].primarySpanID, "a",
                       "a merged block answers taps as its first window")
    }

    func testWindowsEntirelyOutsideTheRangeAreInvisible() {
        let layout = SleepLaneLayout(
            elementDates: [date(12, 20, 8), date(13, 5, 57)],
            laneParentIDs: [katieID],
            spans: [
                .init(id: "before", parentID: katieID, start: date(12, 18, 0), end: date(12, 19, 30)),
                .init(id: "after", parentID: katieID, start: date(13, 6, 30), end: date(13, 7, 0)),
            ])
        for slice in layout.slices.flatMap({ $0 }) {
            XCTAssertTrue(slice.runs.isEmpty)
            XCTAssertNil(slice.primarySpanID)
        }
    }

    func testDegenerateInputsStaySane() {
        // A zero-length span paints nothing; equal element dates (a bottle
        // logged at the NOW instant) don't divide by zero.
        let layout = SleepLaneLayout(
            elementDates: [date(13, 1, 0), date(13, 1, 0)],
            laneParentIDs: [taylorID],
            spans: [
                .init(id: "zero", parentID: taylorID, start: date(13, 2, 0), end: date(13, 2, 0)),
                .init(id: "real", parentID: taylorID, start: date(13, 0, 0), end: date(13, 3, 0)),
            ])
        XCTAssertEqual(layout.slices.count, 2)
        assertRuns(layout.slices[0][0], [(0, 1, false, false)])
        assertRuns(layout.slices[1][0], [(0, 1, false, false)])
        XCTAssertFalse(layout.slices.flatMap { $0 }.contains { $0.primarySpanID == "zero" })
    }

    func testEmptyInputsProduceNoSlices() {
        XCTAssertTrue(SleepLaneLayout(elementDates: [], laneParentIDs: [taylorID],
                                      spans: []).slices.isEmpty)
        XCTAssertTrue(SleepLaneLayout(elementDates: [date(13, 1, 0)], laneParentIDs: [],
                                      spans: []).slices.isEmpty)
    }
}
