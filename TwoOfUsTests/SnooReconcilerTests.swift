import XCTest
@testable import TwoOfUs

/// Exhaustive tests for the pure reconciliation core (SNOO spec §7/§13): the
/// filter chain, the overlap test, and ordering. No network, no SwiftData —
/// sessions and spans are built by hand and `now` is pinned.
final class SnooReconcilerTests: XCTestCase {
    /// Sat July 25 2026, 9:00 PM local.
    private let now = Date(timeIntervalSince1970: 1_785_200_400)

    private func minutes(_ m: Double) -> TimeInterval { m * 60 }
    private func hours(_ h: Double) -> TimeInterval { h * 3600 }

    private func session(id: String = UUID().uuidString,
                         startOffset: TimeInterval,
                         duration: TimeInterval? = nil) -> SnooSession {
        let start = now.addingTimeInterval(startOffset)
        return SnooSession(id: id, startedAt: start,
                           endedAt: duration.map(start.addingTimeInterval),
                           levels: [])
    }

    private func span(startOffset: TimeInterval, duration: TimeInterval?) -> LocalSleepSpan {
        let start = now.addingTimeInterval(startOffset)
        return LocalSleepSpan(startedAt: start,
                              endedAt: duration.map(start.addingTimeInterval))
    }

    private func reconcile(_ sessions: [SnooSession],
                           local: [LocalSleepSpan] = [],
                           imported: Set<String> = [],
                           dismissed: Set<String> = []) -> [SnooSuggestion] {
        SnooReconciler.suggestions(snooSessions: sessions, localSleeps: local,
                                   importedIDs: imported, dismissedIDs: dismissed, now: now)
    }

    // MARK: Basic shapes

    func testCompletedSessionBecomesCompletedSuggestion() {
        let s = session(id: "a", startOffset: -hours(3), duration: hours(1))
        let out = reconcile([s])
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].id, "a")
        XCTAssertEqual(out[0].kind, .completed(endedAt: s.endedAt!))
    }

    func testInProgressSessionBecomesInProgressSuggestion() {
        let out = reconcile([session(id: "run", startOffset: -hours(1))])
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].kind, .inProgress)
    }

    // MARK: Filter 1 & 2 — imported / dismissed never resurface

    func testImportedSessionIsDropped() {
        let s = session(id: "done", startOffset: -hours(3), duration: hours(1))
        XCTAssertTrue(reconcile([s], imported: ["done"]).isEmpty)
    }

    func testDismissedSessionIsDropped() {
        let s = session(id: "no", startOffset: -hours(3), duration: hours(1))
        XCTAssertTrue(reconcile([s], dismissed: ["no"]).isEmpty)
    }

    // MARK: Filter 3 — short completed sessions are noise

    func testShortCompletedSessionIsDropped() {
        XCTAssertTrue(reconcile([session(startOffset: -hours(1), duration: minutes(4))]).isEmpty)
    }

    func testFiveMinuteSessionSurvives() {
        XCTAssertEqual(reconcile([session(startOffset: -hours(1), duration: minutes(5))]).count, 1)
    }

    func testShortnessFilterDoesNotApplyToInProgress() {
        // Started 2 minutes ago, still running — not noise, it has no duration yet.
        XCTAssertEqual(reconcile([session(startOffset: -minutes(2))]).count, 1)
    }

    // MARK: Filter 4 — overlap with local sleep

    func testFullyOverlappedSessionIsDropped() {
        let s = session(startOffset: -hours(3), duration: hours(1))
        let local = span(startOffset: -hours(3), duration: hours(1))
        XCTAssertTrue(reconcile([s], local: [local]).isEmpty)
    }

    func testMajorityOverlapIsDropped() {
        // 60-min SNOO session; local sleep covers its last 40 min (67% > 50%).
        let s = session(startOffset: -minutes(60), duration: minutes(60))
        let local = span(startOffset: -minutes(40), duration: minutes(60))
        XCTAssertTrue(reconcile([s], local: [local]).isEmpty)
    }

    func testMinorityOverlapSurvives() {
        // Local sleep covers only the last 20 min of a 60-min session (33%).
        let s = session(startOffset: -minutes(60), duration: minutes(60))
        let local = span(startOffset: -minutes(20), duration: minutes(60))
        XCTAssertEqual(reconcile([s], local: [local]).count, 1)
    }

    func testExactlyHalfOverlapSurvives() {
        // The threshold is "> 50%", so exactly half stays.
        let s = session(startOffset: -minutes(60), duration: minutes(60))
        let local = span(startOffset: -minutes(30), duration: minutes(60))
        XCTAssertEqual(reconcile([s], local: [local]).count, 1)
    }

    func testOverlapAgainstOpenLocalSleepUsesNow() {
        // A local timer running since before the SNOO session covers all of it.
        let s = session(startOffset: -hours(2), duration: hours(1))
        let local = span(startOffset: -hours(3), duration: nil)
        // The open local sleep also trips filter 5 for in-progress, but this
        // session is completed — only the overlap rule applies.
        XCTAssertTrue(reconcile([s], local: [local]).isEmpty)
    }

    func testDisjointLocalSleepDoesNotDrop() {
        let s = session(startOffset: -hours(6), duration: hours(1))
        let local = span(startOffset: -hours(2), duration: hours(1))
        XCTAssertEqual(reconcile([s], local: [local]).count, 1)
    }

    func testOverlapIsPerLocalSession_NotSummed() {
        // Two local naps each cover 30% of the SNOO session (60% summed). The
        // spec's test is "overlaps any local sleep session by >50%" — max, not
        // union — so this survives.
        let s = session(startOffset: -minutes(100), duration: minutes(100))
        let a = span(startOffset: -minutes(100), duration: minutes(30))
        let b = span(startOffset: -minutes(30), duration: minutes(30))
        XCTAssertEqual(reconcile([s], local: [a, b]).count, 1)
    }

    // MARK: Filter 5 — in-progress vs an open local timer

    func testInProgressDroppedWhenLocalTimerRunning() {
        let s = session(startOffset: -minutes(30))
        let local = span(startOffset: -hours(5), duration: nil)   // no overlap, but open
        XCTAssertTrue(reconcile([s], local: [local]).isEmpty)
    }

    func testCompletedSurvivesWhenLocalTimerRunning() {
        let s = session(startOffset: -hours(8), duration: hours(1))
        let local = span(startOffset: -minutes(10), duration: nil)
        XCTAssertEqual(reconcile([s], local: [local]).count, 1)
    }

    // MARK: Filter 6 — stale in-progress

    func testStaleInProgressIsDropped() {
        XCTAssertTrue(reconcile([session(startOffset: -hours(15))]).isEmpty)
    }

    func testRecentInProgressSurvives() {
        XCTAssertEqual(reconcile([session(startOffset: -hours(13))]).count, 1)
    }

    func testFutureStartedInProgressIsDropped() {
        // Clock skew: a session "from the future" can't be backdated sanely.
        XCTAssertTrue(reconcile([session(startOffset: minutes(10))]).isEmpty)
    }

    // MARK: Ordering

    func testSuggestionsAreMostRecentFirst() {
        let old = session(id: "old", startOffset: -hours(9), duration: hours(1))
        let mid = session(id: "mid", startOffset: -hours(6), duration: hours(1))
        let new = session(id: "new", startOffset: -hours(3), duration: hours(1))
        XCTAssertEqual(reconcile([old, new, mid]).map(\.id), ["new", "mid", "old"])
    }

    // MARK: Overlap helper edge cases

    func testZeroLengthSessionCountsAsCovered() {
        let start = now.addingTimeInterval(-hours(1))
        let s = SnooSession(id: "z", startedAt: start, endedAt: start, levels: [])
        XCTAssertEqual(SnooReconciler.maxOverlapFraction(of: s, in: [], now: now), 1)
    }

    func testOverlapFractionMath() {
        let s = session(startOffset: -minutes(60), duration: minutes(60))
        let local = span(startOffset: -minutes(45), duration: minutes(30))
        XCTAssertEqual(SnooReconciler.maxOverlapFraction(of: s, in: [local], now: now),
                       0.5, accuracy: 0.0001)
    }
}
