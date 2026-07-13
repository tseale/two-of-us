import XCTest

/// Captures the App Store listing screenshots against seeded data, in the order
/// of `docs/appstore/SCREENSHOT_SHOTLIST.md`. Non-destructive apart from one
/// logged feed (used to show the sheet mid-interaction; it reads as normal data
/// in the later shots). Run per device/appearance via
/// `scripts/capture_appstore_screenshots.sh`, which sets the simulator
/// appearance and a clean status bar, then exports the attachments as PNGs.
final class AppStoreScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-seedSampleData"]
    }

    func testCaptureListingScreenshots() throws {
        addUIInterruptionMonitor(withDescription: "System dialog") { alert in
            for label in ["Not Now", "Allow", "OK", "Continue", "Cancel"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }

        app.launch()

        // 1 — Home: time-since tiles + quick-log buttons (the hero shot).
        let feedTile = app.buttons["logTile.feed"]
        XCTAssertTrue(feedTile.waitForExistence(timeout: 30), "Home did not present the Feed tile")
        snapshot("01-home")

        // 2 — Feed sheet mid-interaction ("log in a tap or two").
        feedTile.tap()
        let feedConfirm = app.buttons["feedSheet.confirm"]
        if feedConfirm.waitForExistence(timeout: 10) {
            snapshot("02-log-sheet")
            feedConfirm.tap()   // dismisses; the extra feed reads fine later
        }
        _ = feedTile.waitForExistence(timeout: 10)

        // 3 — History: a lived-in day of feeds/sleep/diapers.
        tapTab("History")
        snapshot("03-history")

        // 4 — Stats: the rhythm charts over the seeded week.
        tapTab("Stats")
        snapshot("04-stats")

        // 5 — Settings: sharing/people section.
        tapTab("Home")
        _ = feedTile.waitForExistence(timeout: 10)
        let gear = app.buttons["Settings"].firstMatch
        if gear.waitForExistence(timeout: 5) {
            gear.tap()
            _ = app.navigationBars["Settings"].waitForExistence(timeout: 8)
            snapshot("05-settings")
        }
    }

    // MARK: Helpers (same tolerant matching as SmokeWalkthroughTests)

    private func tapTab(_ name: String) {
        let tab = app.tabBars.buttons[name]
        if tab.waitForExistence(timeout: 3) { tab.tap(); return }
        let alt = app.buttons[name].firstMatch
        if alt.waitForExistence(timeout: 3) { alt.tap() }
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
