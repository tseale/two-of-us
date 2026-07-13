import XCTest

/// The expecting-parents path: onboarding's baby step offers a "Not born just
/// yet" toggle that flips the date-of-birth picker into a future-dated due-date
/// picker. Launches with `-wipeStore` so onboarding shows regardless of what a
/// previous test run left in the store, and `-onboardingPage 1` to land
/// directly on the baby step.
final class OnboardingDueDateTests: XCTestCase {
    func testNotBornYetTogglesDueDatePicker() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-wipeStore", "-onboardingPage", "1"]
        app.launch()

        let toggle = app.switches["Not born just yet"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 30),
                      "Baby step did not present the expecting toggle")
        XCTAssertTrue(app.staticTexts["Date of birth"].exists,
                      "Default state should label the picker as date of birth")

        toggle.tap()

        let dueLabel = app.staticTexts["Due date"]
        XCTAssertTrue(dueLabel.waitForExistence(timeout: 5),
                      "Toggling 'Not born just yet' should relabel the picker to Due date")
    }

    /// Regression: with the keyboard up, the floating Continue bar used to land
    /// on top of mid-page content (the Photo card), because the pages ignored
    /// the keyboard and their reserved bar clearance sat behind it. The page
    /// must scroll its last card fully clear of the bar while typing.
    ///
    /// Only meaningful with the SOFTWARE keyboard: with "Connect Hardware
    /// Keyboard" on, the keyboard never raises, the bar never lifts, and every
    /// assertion passes vacuously (`defaults write com.apple.iphonesimulator
    /// ConnectHardwareKeyboard -bool false` + relaunch Simulator to fix).
    func testContinueBarClearsContentWithKeyboardUp() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-wipeStore", "-onboardingPage", "1"]
        app.launch()

        // Toggle BEFORE focusing the field: interacting with controls after the
        // keyboard is up can resign focus and silently turn every geometry
        // assertion below into a keyboard-down (vacuously green) check.
        let toggle = app.switches["Not born just yet"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 30))
        toggle.tap()

        let nameField = app.textFields.firstMatch
        nameField.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                      "Tapping the name field should raise the keyboard")
        snapshot(app, "keyboard-up-at-rest")

        // Scroll the page up with a controlled upward drag — swipeUp/drag-down
        // trigger `.scrollDismissesKeyboard(.interactively)` and drop the keyboard.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
        start.press(forDuration: 0.05, thenDragTo: end)

        // Guard against vacuous green: the whole point is keyboard-up geometry.
        XCTAssertTrue(app.keyboards.firstMatch.exists,
                      "Keyboard must still be up when the clearance is asserted")

        let continueButton = app.buttons["Continue"].firstMatch
        let addPhoto = app.buttons["Add"].firstMatch
        XCTAssertTrue(continueButton.exists && addPhoto.exists)
        // At max scroll the page's last card must sit fully ABOVE the floating
        // bar. Pre-fix, the page ignored the keyboard: its bar clearance sat
        // behind the keyboard and the content wasn't even scrollable, so the
        // card could only land under the bar or under the keyboard itself.
        XCTAssertLessThanOrEqual(addPhoto.frame.maxY, continueButton.frame.minY,
                                 "The photo card must scroll fully clear of the floating bar")
        snapshot(app, "keyboard-up-scrolled")
    }

    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
