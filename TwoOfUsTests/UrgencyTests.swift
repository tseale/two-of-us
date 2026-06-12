import XCTest
@testable import TwoOfUs

/// Threshold tests for the green → amber → red urgency ramp that drives the
/// Home tiles and widgets (ratio of elapsed time to the target interval:
/// green below 0.66, amber through 1.0, red past it).
final class UrgencyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let target: TimeInterval = 100

    private func urgency(elapsed: TimeInterval) -> Urgency {
        Urgency.from(since: now.addingTimeInterval(-elapsed), now: now, target: target)
    }

    func testFreshIsGreen() {
        XCTAssertEqual(urgency(elapsed: 0), .green)
        XCTAssertEqual(urgency(elapsed: 65), .green)
    }

    func testAmberBeginsAtTwoThirds() {
        XCTAssertEqual(urgency(elapsed: 66), .amber, "ratio 0.66 is the first amber")
        XCTAssertEqual(urgency(elapsed: 100), .amber, "exactly on target is still amber")
    }

    func testOverdueIsRed() {
        XCTAssertEqual(urgency(elapsed: 101), .red)
        XCTAssertEqual(urgency(elapsed: 10_000), .red)
    }

    func testNoEventYetIsGreen() {
        XCTAssertEqual(Urgency.from(since: nil, now: now, target: target), .green)
    }

    func testZeroTargetNeverEscalates() {
        XCTAssertEqual(Urgency.from(since: now.addingTimeInterval(-9999), now: now, target: 0), .green)
    }

    func testOnlyGreenNeedsNoAttention() {
        XCTAssertFalse(Urgency.green.needsAttention)
        XCTAssertTrue(Urgency.amber.needsAttention)
        XCTAssertTrue(Urgency.red.needsAttention)
    }
}
