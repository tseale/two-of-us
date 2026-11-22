import XCTest
@testable import TwoOfUs

/// The bench's one painter (`SkyBenchPainter`): pictures are made one at a
/// time, in the task that asked, and a task SwiftUI has cancelled does no
/// more work. Build 234 had neither, and a drag of the Land screen's Hour
/// slider crashed the app.
///
/// No test here waits on a clock to put things in order. A paint that must
/// be "still going" says it has begun and then holds a gate until the test
/// opens it. The tests wait on the main run loop (thirty seconds stands for
/// "never"), which needs none of the threads the paints run on: a held paint
/// may be blocking the only one a small machine has.
final class SkyBenchPainterTests: XCTestCase {
    /// Counts the work done, and the most that was ever in hand at once.
    private final class Tally: @unchecked Sendable {
        private let lock = NSLock()
        private var inHand = 0
        private var mostInHand = 0
        private var begun = 0

        func begin() {
            lock.lock()
            inHand += 1
            begun += 1
            mostInHand = max(mostInHand, inHand)
            lock.unlock()
        }

        func end() {
            lock.lock()
            inHand -= 1
            lock.unlock()
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return begun
        }

        var most: Int {
            lock.lock()
            defer { lock.unlock() }
            return mostInHand
        }
    }

    /// What a request came back with, carried from its task to the test.
    private final class Kept<Picture>: @unchecked Sendable {
        private let lock = NSLock()
        private var picture: Picture?

        func keep(_ picture: Picture?) {
            lock.lock()
            self.picture = picture
            lock.unlock()
        }

        var kept: Picture? {
            lock.lock()
            defer { lock.unlock() }
            return picture
        }
    }

    /// Waits, on the main run loop, for something to have happened.
    private func waitOnTheRunLoop(for happened: XCTestExpectation,
                                  file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(XCTWaiter().wait(for: [happened], timeout: 30) == .completed,
                      "never happened: \(happened.expectationDescription)", file: file, line: line)
    }

    /// The picture a request comes back with: nil if it made none.
    private func picture<Picture: Sendable>(of request: Task<Picture?, Never>,
                                            file: StaticString = #filePath, line: UInt = #line) -> Picture? {
        let back = XCTestExpectation(description: "the request is back")
        let kept = Kept<Picture>()
        Task.detached {
            kept.keep(await request.value)
            back.fulfill()
        }
        waitOnTheRunLoop(for: back, file: file, line: line)
        return kept.kept
    }

    func testTwentyRequestsAtOnceAreDoneOneAtATime() {
        let painter = SkyBenchPainter()
        let tally = Tally()
        let requests = (0..<20).map { request in
            Task.detached {
                await painter.paint { () -> Int? in
                    tally.begin()
                    // Long enough for another to begin, were two ever let in
                    // together.
                    Thread.sleep(forTimeInterval: 0.002)
                    tally.end()
                    return request
                }
            }
        }
        let made = requests.compactMap { picture(of: $0) }
        XCTAssertEqual(tally.most, 1, "never two at once")
        XCTAssertEqual(tally.count, 20)
        XCTAssertEqual(made, Array(0..<20), "and every one of them got its own picture")
    }

    func testARequestCancelledWhileItWaitsDoesNoWork() {
        let painter = SkyBenchPainter()
        let tally = Tally()
        let gate = DispatchSemaphore(value: 0)

        // The first holds the painter until the gate opens.
        let painting = XCTestExpectation(description: "the first is painting")
        let first = Task.detached {
            await painter.paint { () -> String? in
                painting.fulfill()
                gate.wait()
                return "first"
            }
        }
        waitOnTheRunLoop(for: painting)

        // The second says it is asking, on the main actor, and goes straight
        // on to wait for the painter. The run loop this test waits on is
        // what runs it, so the wait is not over before it has gone.
        let asking = XCTestExpectation(description: "the second is asking")
        let second = Task { @MainActor () -> String? in
            asking.fulfill()
            return await painter.paint { () -> String? in
                tally.begin()
                tally.end()
                return "second"
            }
        }
        waitOnTheRunLoop(for: asking)
        second.cancel()
        gate.signal()

        XCTAssertEqual(picture(of: first), "first")
        XCTAssertNil(picture(of: second))
        XCTAssertEqual(tally.count, 0, "its work never began")
    }

    func testARequestCancelledBeforeItAsksDoesNoWork() {
        let painter = SkyBenchPainter()
        let tally = Tally()
        let request = Task.detached { () -> String? in
            // What the slider screens do first: wait, and only then ask.
            // (Cancelled, the wait ends at once.)
            try? await Task.sleep(for: .seconds(60))
            return await painter.paint { () -> String? in
                tally.begin()
                tally.end()
                return "painted"
            }
        }
        request.cancel()
        XCTAssertNil(picture(of: request))
        XCTAssertEqual(tally.count, 0)
    }

    func testAPaintCancelledPartWayCanSeeItAndStop() {
        let painter = SkyBenchPainter()
        let tally = Tally()
        let gate = DispatchSemaphore(value: 0)

        // Four planes, as the land has, looking between them as the bench
        // does. It is cancelled while it is on its second.
        let onTheSecond = XCTestExpectation(description: "the paint is on its second plane")
        let paint = Task.detached {
            await painter.paint { () -> String? in
                for plane in 1...4 {
                    guard !Task.isCancelled else { return nil }
                    tally.begin()
                    if plane == 2 {
                        onTheSecond.fulfill()
                        gate.wait()
                    }
                    tally.end()
                }
                return "four planes"
            }
        }
        waitOnTheRunLoop(for: onTheSecond)
        XCTAssertEqual(tally.count, 2)
        paint.cancel()
        gate.signal()

        XCTAssertNil(picture(of: paint), "no picture from a paint that was stopped")
        XCTAssertEqual(tally.count, 2, "the third plane was never begun")
    }

    func testOfADragsRequestsOnlyTheLastIsPainted() {
        let painter = SkyBenchPainter()
        let tally = Tally()
        let gate = DispatchSemaphore(value: 0)

        // A paint is under way…
        let painting = XCTestExpectation(description: "a paint is under way")
        var requests = [Task.detached {
            await painter.paint { () -> Int? in
                painting.fulfill()
                gate.wait()
                return Task.isCancelled ? nil : 0
            }
        }]
        waitOnTheRunLoop(for: painting)

        // …and the slider passes twenty more values. Each new request
        // cancels the one before it, as `.task(id:)` does, and goes to wait
        // for the painter.
        for value in 1...20 {
            requests.last?.cancel()
            let asking = XCTestExpectation(description: "request \(value) is asking")
            requests.append(Task { @MainActor () -> Int? in
                asking.fulfill()
                return await painter.paint { () -> Int? in
                    tally.begin()
                    tally.end()
                    return value
                }
            })
            waitOnTheRunLoop(for: asking)
        }
        gate.signal()

        let pictures = requests.map { picture(of: $0) }
        XCTAssertEqual(pictures.count, 21)
        XCTAssertEqual(pictures.compactMap { $0 }, [20], "the last value's picture arrives, and no other")
        XCTAssertEqual(tally.count, 1, "nineteen of the twenty were never begun")
    }
}
