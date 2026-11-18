import XCTest
@testable import TwoOfUs

/// What counts as daycare health news — the line between the loud alert and
/// the quiet ping.
final class DaycareHealthAlertTests: XCTestCase {

    /// Verbatim from the message that motivated this (2026-11-17).
    private let feverMessage = """
        Good afternoon, I just wanted to reach out and inform you that Miller has a low grade fever \
        he is riding 99.9 and 100.5 and a pretty snotty nose. 100.5 is our cut off to send children \
        home but since he's only at 99.9 under the other arm we will see where he is at once he wakes \
        up he just fell asleep for his afternoon nap. We will keep you updated.
        """

    func testTheFeverMessageAlerts() {
        XCTAssertTrue(DaycareHealthAlert.isConcerning(feverMessage))
        XCTAssertEqual(DaycareHealthAlert.highestTemperature(in: feverMessage), 100.5)
    }

    func testTemperatureAloneAlerts() {
        XCTAssertTrue(DaycareHealthAlert.isConcerning("He was at 100.2 after lunch"))
        XCTAssertTrue(DaycareHealthAlert.isConcerning("Reading of 101 F this morning"))
        XCTAssertFalse(DaycareHealthAlert.isConcerning("He was 98.6 all day, happy boy"))
    }

    func testPickUpAndSendHomePhrasesAlert() {
        XCTAssertTrue(DaycareHealthAlert.isConcerning("Can someone come pick him up?"))
        XCTAssertTrue(DaycareHealthAlert.isConcerning("We'll need to send Miller home"))
        XCTAssertTrue(DaycareHealthAlert.isConcerning("He threw up after his bottle"))
        XCTAssertTrue(DaycareHealthAlert.isConcerning("Small rash on his cheek"))
        XCTAssertTrue(DaycareHealthAlert.isConcerning("He bumped his head on the shelf"))
    }

    func testEverydayDaycareTextStaysQuiet() {
        XCTAssertFalse(DaycareHealthAlert.isConcerning("Miller fell asleep at 12:30 and napped great"))
        XCTAssertFalse(DaycareHealthAlert.isConcerning("Took 4oz happily, a little spit up after"))
        XCTAssertFalse(DaycareHealthAlert.isConcerning("Please use the feather provided to write down something your family is thankful for"))
        XCTAssertFalse(DaycareHealthAlert.isConcerning("We had 100 days of school party, he played with a friend for a bit"))
        XCTAssertFalse(DaycareHealthAlert.isConcerning("I'll send pictures later!"))
        XCTAssertFalse(DaycareHealthAlert.isConcerning(nil))
    }

    func testHealthCheckReadings() {
        XCTAssertTrue(DaycareHealthAlert.isConcerning(type: .temperature, value: 100.4, notes: nil))
        XCTAssertFalse(DaycareHealthAlert.isConcerning(type: .temperature, value: 98.4, notes: "All good"))
        XCTAssertTrue(DaycareHealthAlert.isConcerning(type: .weight, value: 18, notes: "Seems sick today"))
    }
}
