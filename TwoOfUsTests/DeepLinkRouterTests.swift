import XCTest
@testable import TwoOfUs

/// Covers the `twoofus://` parser the Feed/Diaper widgets tap into. The Sleep
/// widget toggles in-process and intentionally has no URL, so `log/sleep` is
/// treated as garbage here.
final class DeepLinkRouterTests: XCTestCase {
    private let router = DeepLinkRouter.shared

    override func setUp() {
        super.setUp()
        router.pendingLog = nil
    }

    func testFeedURLStagesFeedSheet() {
        XCTAssertTrue(router.handle(URL(string: "twoofus://log/feed")!))
        XCTAssertEqual(router.pendingLog, .feed)
    }

    func testDiaperURLStagesDiaperSheet() {
        XCTAssertTrue(router.handle(URL(string: "twoofus://log/diaper")!))
        XCTAssertEqual(router.pendingLog, .diaper)
    }

    func testSleepURLIsNotHandled() {
        // Sleep toggles in-process — there's no deep link for it.
        XCTAssertFalse(router.handle(URL(string: "twoofus://log/sleep")!))
        XCTAssertNil(router.pendingLog)
    }

    func testUnknownHostIsIgnored() {
        XCTAssertFalse(router.handle(URL(string: "twoofus://home")!))
        XCTAssertNil(router.pendingLog)
    }

    func testForeignSchemeIsIgnored() {
        XCTAssertFalse(router.handle(URL(string: "https://example.com/log/feed")!))
        XCTAssertNil(router.pendingLog)
    }

    func testGarbageURLIsIgnored() {
        XCTAssertFalse(router.handle(URL(string: "twoofus://log/")!))
        XCTAssertNil(router.pendingLog)
    }
}
