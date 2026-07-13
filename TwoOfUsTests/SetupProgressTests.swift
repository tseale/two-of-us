import XCTest
@testable import TwoOfUs

/// The reminders quest must complete **durably** — a one-time setup milestone, not
/// a live mirror of the feed-reminder toggle. Regression guard for the bug where
/// turning the reminder off in Settings resurrected the already-finished quest.
final class SetupProgressTests: XCTestCase {
    private var savedQuests: Set<String> = []
    private var savedReminder = false

    override func setUp() {
        super.setUp()
        // SetupProgress/LocalPrefs are singletons over UserDefaults — snapshot and
        // restore so this test can't leak state into the others.
        savedQuests = SetupProgress.shared.completedQuests
        savedReminder = LocalPrefs.shared.feedReminderEnabled
    }

    override func tearDown() {
        SetupProgress.shared.completedQuests = savedQuests
        LocalPrefs.shared.feedReminderEnabled = savedReminder
        super.tearDown()
    }

    func testRemindersQuestStaysCompleteAfterTogglingReminderOff() {
        let sp = SetupProgress.shared
        sp.completedQuests = []

        // Reminder on, but the quest was never explicitly finished → NOT complete
        // (completion no longer mirrors the live toggle).
        LocalPrefs.shared.feedReminderEnabled = true
        XCTAssertFalse(sp.isComplete(.reminders, settings: nil),
                       "the toggle being on is not, by itself, quest completion")

        // Finishing it (primer or Settings enable calls this) records the milestone.
        sp.markComplete(.reminders)
        XCTAssertTrue(sp.isComplete(.reminders, settings: nil))

        // Turning the reminder off later must NOT resurrect the finished quest.
        LocalPrefs.shared.feedReminderEnabled = false
        XCTAssertTrue(sp.isComplete(.reminders, settings: nil),
                      "a finished reminders quest stays finished after toggling off")
    }
}
