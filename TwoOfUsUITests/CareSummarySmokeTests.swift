import XCTest

/// Smoke for the pediatrician report's home on the Stats tab: the Care summary
/// card is present, its sheet renders the page preview, and the Share button
/// becomes ready (PDF built) — including after a range flip.
final class CareSummarySmokeTests: XCTestCase {
    func testCareSummaryFromStats() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-seedSampleData"]
        app.launch()

        app.tabBars.buttons["Stats"].tap()
        let card = app.buttons["Care summary — a printable report for pediatrician visits"]
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Care summary card missing from Stats")
        card.scrollIntoViewAndTap(app: app)
        snapshot(app, "stats-care-card")

        XCTAssertTrue(app.navigationBars["Care summary"].waitForExistence(timeout: 5))
        let share = app.buttons["Share"].firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 10), "Share never became ready (PDF failed?)")
        snapshot(app, "care-summary-sheet")

        app.buttons["7 days"].tap()
        XCTAssertTrue(share.waitForExistence(timeout: 10), "Share not ready after range flip")
        snapshot(app, "care-summary-7d")
    }

    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}

private extension XCUIElement {
    /// Scrolls (up to a few swipes) until hittable, then taps.
    func scrollIntoViewAndTap(app: XCUIApplication) {
        var tries = 0
        while !isHittable && tries < 6 {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            start.press(forDuration: 0.05, thenDragTo: end)
            tries += 1
        }
        tap()
    }
}
