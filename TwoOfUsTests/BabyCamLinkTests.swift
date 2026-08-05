import XCTest
@testable import TwoOfUs

/// Covers the eufy hand-off the sleep card's camera button uses. The real
/// `canOpenURL` needs a device, so these drive the injected predicate instead —
/// what matters is the probe order and that a phone with no eufy app still
/// lands somewhere useful rather than nowhere.
final class BabyCamLinkTests: XCTestCase {
    private func destination(installed: Set<String>) -> URL {
        BabyCamLink.destination { installed.contains($0.scheme ?? "") }
    }

    func testPrefersUnifiedEufyApp() {
        XCTAssertEqual(destination(installed: ["eufysecurity"]).scheme, "eufysecurity")
    }

    func testFallsBackToLegacyBabyApp() {
        XCTAssertEqual(destination(installed: ["eufybaby"]).scheme, "eufybaby")
        XCTAssertEqual(destination(installed: ["eufycare"]).scheme, "eufycare")
    }

    func testUnifiedAppWinsWhenBothInstalled() {
        // A phone mid-migration has both. Send it to the one eufy is still
        // developing, not the app being folded away.
        let url = destination(installed: ["eufybaby", "eufycare", "eufysecurity"])
        XCTAssertEqual(url.scheme, "eufysecurity")
    }

    func testNoEufyAppFallsBackToAppStore() {
        XCTAssertEqual(destination(installed: []), BabyCamLink.appStore)
    }

    func testAppStoreLinkPointsAtUnifiedApp() {
        // 1424956516 is the unified "eufy" app, not the legacy eufy Baby app
        // (1544694845) — see docs/BABY-CAM-INTEGRATION.md. The slug has to stay
        // in: the slugless form is a 301, and universal-link matching happens
        // before redirects, so dropping it can route to Safari instead of the
        // App Store app.
        XCTAssertEqual(BabyCamLink.appStore.absoluteString,
                       "https://apps.apple.com/us/app/eufy/id1424956516")
    }

    /// Each scheme also has to appear in the app's LSApplicationQueriesSchemes
    /// (project.yml), or canOpenURL returns false with no error and every tap
    /// silently detours to the App Store. This bundle is unhosted so it can't
    /// read the app's Info.plist — the list is pinned here so adding a scheme
    /// without wiring the plist fails loudly instead of at 3am on a real phone.
    func testProbedSchemesMatchThePlistWiring() {
        XCTAssertEqual(BabyCamLink.schemes, ["eufysecurity", "eufybaby", "eufycare"],
                       "Update LSApplicationQueriesSchemes in project.yml to match")
    }
}
