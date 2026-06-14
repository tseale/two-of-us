import XCTest
@testable import TwoOfUs

/// The widget / lock-screen deep-link parser. Pure string handling, so it's
/// unit-testable without a running app — guards the contract the widgets encode
/// (`twoofus://log/<kind>`) against the HomeView side that consumes it.
@MainActor
final class DeepLinkRouterTests: XCTestCase {
    private var router: DeepLinkRouter { DeepLinkRouter.shared }

    override func setUp() {
        super.setUp()
        router.pending = nil
    }

    private func handle(_ string: String) {
        router.handle(URL(string: string)!)
    }

    func testLogKindsStageMatchingActions() {
        handle("twoofus://log/feed")
        XCTAssertEqual(router.pending, .feed)

        handle("twoofus://log/diaper")
        XCTAssertEqual(router.pending, .diaper)

        handle("twoofus://log/sleep")
        XCTAssertEqual(router.pending, .sleep)
    }

    func testHomeLinkIsIgnored() {
        // The Live Activity's twoofus://home just foregrounds the app.
        handle("twoofus://home")
        XCTAssertNil(router.pending)
    }

    func testUnknownLinksAreIgnored() {
        handle("twoofus://log/banana")
        XCTAssertNil(router.pending)

        handle("https://example.com/log/feed")
        XCTAssertNil(router.pending)
    }
}
