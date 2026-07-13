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
}
