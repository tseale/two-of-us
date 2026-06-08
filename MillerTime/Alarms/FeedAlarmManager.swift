import AlarmKit
import SwiftUI

/// Empty payload — AlarmKit requires a concrete `AlarmMetadata` type per alarm.
nonisolated struct FeedAlarmMetadata: AlarmMetadata {}

/// Schedules a single "next feed due" countdown via AlarmKit (iOS 26).
///
/// AlarmKit alarms break through Silent and Focus, so an overnight feed reminder
/// actually wakes a parent — unlike a normal notification. The reminder is
/// device-local and opt-in (`LocalPrefs.feedReminderEnabled`); each parent's
/// phone arms its own alarm off the shared feed log + target interval.
enum FeedAlarmManager {
    /// Stable id so every reschedule replaces the previous pending alarm.
    private static let alarmID = UUID(uuidString: "FEED0000-0000-0000-0000-000000000001")!

    static var isAuthorized: Bool {
        AlarmManager.shared.authorizationState == .authorized
    }

    /// Requests alarm authorization if undecided. Returns whether it's granted.
    @discardableResult
    static func requestAuthorization() async -> Bool {
        switch AlarmManager.shared.authorizationState {
        case .authorized:
            return true
        case .denied:
            return false
        default:
            let state = try? await AlarmManager.shared.requestAuthorization()
            return state == .authorized
        }
    }

    /// Re-arms the feed alarm for `interval` after `lastFeed`, replacing any
    /// pending one. Clears the alarm (and no-ops) when reminders are off, no feed
    /// exists yet, or the next feed is already overdue.
    static func reschedule(lastFeed: Date?, interval: TimeInterval) async {
        await cancel()
        guard LocalPrefs.shared.feedReminderEnabled,
              let lastFeed, interval > 0 else { return }

        let remaining = lastFeed.addingTimeInterval(interval).timeIntervalSinceNow
        guard remaining > 0 else { return }              // already due — nothing to count down
        guard await requestAuthorization() else { return }

        let alert = AlarmPresentation.Alert(
            title: "Miller — feed due",
            stopButton: AlarmButton(text: "Done", textColor: .white, systemImageName: "checkmark")
        )
        let attributes = AlarmAttributes<FeedAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            tintColor: AppColor.accentFeed
        )
        let configuration: AlarmManager.AlarmConfiguration = .timer(
            duration: remaining,
            attributes: attributes
        )
        _ = try? await AlarmManager.shared.schedule(id: alarmID, configuration: configuration)
    }

    /// Cancels the pending feed alarm, if any.
    static func cancel() async {
        try? AlarmManager.shared.cancel(id: alarmID)
    }
}
