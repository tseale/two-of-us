import XCTest
import UIKit

/// Pins Home's layout on a regular (slab) iPhone, so iPhone Duo work —
/// the shared phone page, the spread, the cover's margins — can never move
/// anything on the phones the app ships to today. Run it on any iPhone
/// simulator (`make uitest`); it skips itself on iPad.
///
/// What it holds: the Today card sits at the slab iPhone's 16 pt side
/// margins (not the Duo cover's 20), spans the width between them, and
/// starts below the status bar.
final class IPhoneLayoutTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone,
                          "Regular-iPhone layout check; runs on iPhone simulators only")
        app = XCUIApplication()
        app.launchArguments += ["-seedSampleData"]
    }

    func testHomeKeepsTheIPhoneLayout() throws {
        addUIInterruptionMonitor(withDescription: "System dialog") { alert in
            for label in ["Not Now", "Allow", "OK", "Continue", "Cancel"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        app.launch()

        let window = app.windows.firstMatch.frame
        let todayCard = app.descendants(matching: .any)
            .matching(identifier: "todayCard").firstMatch
        XCTAssertTrue(todayCard.waitForExistence(timeout: 30), "Home did not present the Today card")

        let card = todayCard.frame
        // The slab iPhone's margins — 16 pt each side, never the Duo cover's 20.
        XCTAssertEqual(card.minX, window.minX + 16, accuracy: 0.5,
                       "Today card's leading margin moved: \(card)")
        XCTAssertEqual(window.maxX - card.maxX, 16, accuracy: 0.5,
                       "Today card's trailing margin moved: \(card)")
        // Below the status bar / Dynamic Island, not hugging the top edge
        // the way the Duo's cover does.
        XCTAssertGreaterThan(card.minY, window.minY + 44,
                             "Today card rose under the status bar: \(card)")
        // One column: the page is the whole window, nothing beside it.
        XCTAssertLessThan(card.width, window.width)
        XCTAssertGreaterThan(card.width, window.width - 33)

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "IPhoneLayout-Home"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
