import XCTest

/// End-to-end UI smoke test: launches the app against a seeded real store and
/// drives the core interactive flows that unit tests can't reach — logging a
/// feed/diaper, starting/stopping sleep, swipe-delete + Undo, the Edit-delete
/// confirmation, tab navigation, and Settings. Captures a screenshot at each
/// screen (attached to the .xcresult) so the run doubles as a visual smoke check.
///
/// Runs in its own scheme (`make uitest`) so the fast unit path (`make test`)
/// and the Xcode Cloud unit workflow stay quick.
final class SmokeWalkthroughTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        // Keep going after a soft failure so we still capture the later screens —
        // a first smoke run is as much about the screenshots as the assertions.
        continueAfterFailure = true
        app = XCUIApplication()
        // Seed a baby + a week of events so we land on the main UI with real data.
        app.launchArguments += ["-seedSampleData"]
    }

    func testSmokeWalkthrough() throws {
        // Auto-dismiss any system dialog that steals focus (iCloud sign-in nudge,
        // notification prompt) so it can't wedge the run.
        addUIInterruptionMonitor(withDescription: "System dialog") { alert in
            for label in ["Not Now", "Allow", "OK", "Continue", "Cancel"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }

        app.launch()

        // 1 — Home loads with the log tiles.
        let feedTile = app.buttons["logTile.feed"]
        XCTAssertTrue(feedTile.waitForExistence(timeout: 30), "Home did not present the Feed tile")
        snapshot("01-Home")

        // 2 — Feed sheet → log a feed.
        feedTile.tap()
        let feedConfirm = app.buttons["feedSheet.confirm"]
        XCTAssertTrue(feedConfirm.waitForExistence(timeout: 10), "Feed sheet did not present")
        snapshot("02-FeedSheet")
        feedConfirm.tap()
        XCTAssertTrue(feedTile.waitForExistence(timeout: 10), "Did not return Home after logging a feed")

        // 3 — Diaper sheet → log a diaper.
        let diaperTile = app.buttons["logTile.diaper"]
        if diaperTile.waitForExistence(timeout: 5) {
            diaperTile.tap()
            let diaperConfirm = app.buttons["diaperSheet.confirm"]
            if diaperConfirm.waitForExistence(timeout: 10) {
                snapshot("03-DiaperSheet")
                diaperConfirm.tap()
            }
        }
        _ = feedTile.waitForExistence(timeout: 10)

        // 4 — Sleep starts/stops in place (the tile is replaced by the active card).
        let sleepTile = app.buttons["logTile.sleep"]
        if sleepTile.waitForExistence(timeout: 3) { sleepTile.tap() }
        let wakeUp = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "Wake up")).firstMatch
        if wakeUp.waitForExistence(timeout: 5) {
            snapshot("04-SleepActive")
            wakeUp.tap()
        }
        _ = feedTile.waitForExistence(timeout: 10)

        // 5 — Swipe-delete a timeline row → Undo toast (verifies the new Undo path).
        let row = timelineRow()
        if row.waitForExistence(timeout: 5) {
            row.swipeLeft()
            let del = app.buttons["Delete"]
            if del.waitForExistence(timeout: 3) {
                del.tap()
                let undo = app.buttons["Undo"]
                XCTAssertTrue(undo.waitForExistence(timeout: 3), "Swipe-delete did not offer Undo")
                snapshot("05-DeleteUndoToast")
                undo.tap()   // restore the row
            }
        }

        // 6 — History + Stats tabs.
        tapTab("History"); snapshot("06-History")
        tapTab("Stats");   snapshot("07-Stats")
        tapTab("Home")
        _ = feedTile.waitForExistence(timeout: 10)

        // 7 — Settings.
        let gear = app.buttons["Settings"].firstMatch
        if gear.waitForExistence(timeout: 5) {
            gear.tap()
            _ = app.navigationBars["Settings"].waitForExistence(timeout: 8)
            snapshot("08-Settings")
            let done = app.buttons["Done"].firstMatch
            if done.exists { done.tap() }
        }

        // 8 — Edit → Delete confirmation dialog (verifies the new confirm). Last,
        // so its dialog can't wedge earlier steps.
        let row2 = timelineRow()
        if row2.waitForExistence(timeout: 5) {
            row2.tap()   // onTapGesture opens the Edit sheet
            let deleteEntry = app.buttons["Delete entry"]
            if deleteEntry.waitForExistence(timeout: 8) {
                deleteEntry.tap()
                let confirmTitle = app.staticTexts["Delete this entry?"]
                XCTAssertTrue(confirmTitle.waitForExistence(timeout: 5),
                              "Edit delete did not ask for confirmation")
                snapshot("09-DeleteConfirmDialog")
            }
        }
    }

    // MARK: Helpers

    /// The first timeline row (tagged in HomeView). Its `onTapGesture` means it
    /// surfaces as a generic element, so match on identifier across any type.
    private func timelineRow() -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "timelineRow").firstMatch
    }

    /// Taps a bottom-tab item, tolerating whether it exposes as a tab-bar button
    /// or a plain button (the iOS 26 floating tab bar).
    private func tapTab(_ name: String) {
        let tab = app.tabBars.buttons[name]
        if tab.waitForExistence(timeout: 3) { tab.tap(); return }
        let alt = app.buttons[name].firstMatch
        if alt.waitForExistence(timeout: 3) { alt.tap() }
    }

    /// Attaches a full-screen screenshot to the result bundle.
    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
