import XCTest

/// Daycare readiness smoke: seeds the standard sample store plus the
/// Brightwheel mock day (`-seedDaycareSampleDay`), then verifies the pieces a
/// daycare day touches — the Home report card, daycare-tagged timeline rows,
/// and Settings → Integrations — capturing a screenshot of each.
final class DaycareReadinessTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-seedSampleData", "-seedDaycareSampleDay"]
    }

    func testDaycareDayRendersEverywhere() throws {
        addUIInterruptionMonitor(withDescription: "System dialog") { alert in
            for label in ["Not Now", "Allow", "OK", "Continue", "Cancel"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }

        app.launch()

        // 1 — Home loads; the daycare report card aggregates the mock day.
        let feedTile = app.buttons["logTile.feed"]
        XCTAssertTrue(feedTile.waitForExistence(timeout: 30), "Home did not present the Feed tile")
        let reportCard = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "at daycare")).firstMatch
        XCTAssertTrue(reportCard.waitForExistence(timeout: 10),
                      "Home shows no daycare report card after the mock day import")
        snapshot("01-Home-DaycareReportCard")

        // 2 — Timeline rows carry the daycare tag (accessibility label ends
        // ", at daycare"). The timeline is lazy, so scroll until daycare rows
        // from the (morning-heavy) mock day are instantiated.
        let daycareRows = app.descendants(matching: .any)
            .matching(identifier: "timelineRow")
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "at daycare"))
        var found = daycareRows.firstMatch.exists
        for _ in 0..<8 where !found {
            app.swipeUp()
            found = daycareRows.firstMatch.exists
        }
        XCTAssertTrue(found, "No daycare-tagged rows on the Home timeline")
        snapshot("02-Home-Timeline")
        app.swipeUp()
        snapshot("03-Home-Timeline-Morning")

        // 4 — Settings → Integrations: the Brightwheel row is present
        // alongside SNOO (disconnected in the simulator, so it reads
        // "Not connected" — the sample-day button itself lives behind a
        // real session).
        let gear = app.buttons["Settings"].firstMatch
        if gear.waitForExistence(timeout: 5) {
            gear.tap()
            _ = app.navigationBars["Settings"].waitForExistence(timeout: 8)
            let integrations = app.buttons["Integrations"].firstMatch
            let integrationsCell = integrations.exists
                ? integrations
                : app.staticTexts["Integrations"].firstMatch
            XCTAssertTrue(integrationsCell.waitForExistence(timeout: 5),
                          "Settings has no Integrations row")
            integrationsCell.tap()
            let brightwheel = app.staticTexts["Brightwheel"].firstMatch
            XCTAssertTrue(brightwheel.waitForExistence(timeout: 8),
                          "Integrations page has no Brightwheel row")
            XCTAssertTrue(app.staticTexts["SNOO"].firstMatch.exists
                          || app.staticTexts.containing(
                              NSPredicate(format: "label CONTAINS[c] %@", "SNOO")).firstMatch.exists,
                          "Integrations page has no SNOO row")
            snapshot("04-Settings-Integrations")
        }
    }

    // MARK: Helpers

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
