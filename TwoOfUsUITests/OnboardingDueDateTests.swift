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

    /// The keyboard-up contract: the Continue bar stays pinned to the screen
    /// bottom and lets the keyboard cover it (it used to ride above the
    /// keyboard, landing mid-page in a glass card — wonky). While typing, the
    /// page's content must still scroll fully clear of the keyboard; once the
    /// keyboard drops, Continue is right there and hittable.
    ///
    /// Only meaningful with the SOFTWARE keyboard: with "Connect Hardware
    /// Keyboard" on, the keyboard never raises and every assertion passes
    /// vacuously (`defaults write com.apple.iphonesimulator
    /// ConnectHardwareKeyboard -bool false` + relaunch Simulator to fix).
    func testKeyboardCoversContinueBarUntilTypingEnds() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-wipeStore", "-onboardingPage", "1"]
        app.launch()

        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 30))
        nameField.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5),
                      "Tapping the name field should raise the keyboard")
        snapshot(app, "keyboard-up-at-rest")

        // The bar must NOT have lifted above the keyboard: its top edge stays
        // at or below the keyboard's top, i.e. covered — never mid-page.
        let continueButton = app.buttons["Continue"].firstMatch
        XCTAssertTrue(continueButton.exists)
        XCTAssertGreaterThanOrEqual(continueButton.frame.minY, keyboard.frame.minY - 1,
                                    "The Continue bar must stay behind the keyboard, not float mid-page")

        // Scroll the page up with a controlled upward drag — swipeUp/drag-down
        // trigger `.scrollDismissesKeyboard(.interactively)` and drop the keyboard.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
        start.press(forDuration: 0.05, thenDragTo: end)

        // Guard against vacuous green: the whole point is keyboard-up geometry.
        XCTAssertTrue(keyboard.exists,
                      "Keyboard must still be up when the clearance is asserted")

        // At max scroll the page's last card must clear the KEYBOARD (the page
        // still respects it even though the bar doesn't).
        let addPhoto = app.buttons["Add"].firstMatch
        XCTAssertTrue(addPhoto.exists)
        XCTAssertLessThanOrEqual(addPhoto.frame.maxY, keyboard.frame.minY,
                                 "The photo card must scroll fully clear of the keyboard")
        snapshot(app, "keyboard-up-scrolled")

        // Finish typing: submit drops the keyboard and reveals the bar in place.
        nameField.tap()
        nameField.typeText("Miller\n")
        XCTAssertTrue(waitForKeyboardGone(app, timeout: 5),
                      "Submitting should dismiss the keyboard")
        XCTAssertTrue(continueButton.isHittable,
                      "Continue must be tappable once typing ends")
        snapshot(app, "keyboard-down-bar-revealed")
    }

    private func waitForKeyboardGone(_ app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let gone = NSPredicate(format: "exists == false")
        let exp = XCTNSPredicateExpectation(predicate: gone, object: app.keyboards.firstMatch)
        return XCTWaiter().wait(for: [exp], timeout: timeout) == .completed
    }

    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
