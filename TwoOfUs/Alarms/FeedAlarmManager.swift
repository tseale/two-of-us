import AlarmKit
import SwiftUI
import UserNotifications

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
    /// Id for the best-effort local-notification fallback used when AlarmKit
    /// scheduling fails (so a failed alarm still leaves *some* reminder behind).
    private static let fallbackNotificationID = "feedReminder.fallback"
    /// Below this the "interval" is garbage (0 / a corrupt setting); arming an
    /// alarm that fires in seconds would just annoy. Refuse it.
    private static let minimumInterval: TimeInterval = 60
    /// One-shot flag so the "reminders need permission" prompt surfaces once, not
    /// after every single feed.
    private static let denialSurfacedKey = "alarms.denialSurfaced"

    static var isAuthorized: Bool {
        AlarmManager.shared.authorizationState == .authorized
    }

    /// Requests alarm authorization if undecided. Returns whether it's granted.
    @discardableResult
    static func requestAuthorization() async -> Bool {
        switch AlarmManager.shared.authorizationState {
        case .authorized:
            UserDefaults.standard.set(false, forKey: denialSurfacedKey)
            return true
        case .denied:
            await surfaceDenialIfNeeded()
            return false
        default:
            let state = try? await AlarmManager.shared.requestAuthorization()
            return state == .authorized
        }
    }

    /// Re-arms the feed alarm for `interval` after `lastFeed`, replacing any
    /// pending one. Clears the alarm (and no-ops) when reminders are off, no feed
    /// exists yet, the interval is nonsense, or the next feed is already overdue.
    static func reschedule(babyName: String, lastFeed: Date?, interval: TimeInterval) async {
        await cancel()
        guard LocalPrefs.shared.feedReminderEnabled,
              let lastFeed, interval >= minimumInterval else { return }

        let fireDate = lastFeed.addingTimeInterval(interval)
        let remaining = fireDate.timeIntervalSinceNow
        guard remaining > 0 else { return }              // already due — nothing to count down

        // Feed-schedule routing: when the fire time lands in a slot assigned to
        // the other parent, this device stays dark — their phone arms its own
        // alarm off the same shared state. `cancel()` above already cleared any
        // previously-armed alarm, so a slot that changed hands can't leave a
        // stale alarm behind. The fallback notification sits below this guard
        // and inherits the same routing.
        if let logger = QuickLogger.make() {
            guard FeedSchedule.shouldRemind(
                slots: logger.feedSlots, at: fireDate,
                myParticipantID: LocalPrefs.shared.myParticipantID,
                activeParticipantIDs: logger.activeParticipantIDs
            ) else { return }
        }

        guard await requestAuthorization() else { return }

        let alert = AlarmPresentation.Alert(
            title: "\(babyName) — feed due",
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
        do {
            _ = try await AlarmManager.shared.schedule(id: alarmID, configuration: configuration)
        } catch {
            // A swallowed failure leaves the parent with no reminder and no clue;
            // log it and fall back to a normal local notification so something
            // still fires (it won't pierce Silent/Focus, but it beats silence).
            AppLog.alarms.error("Feed alarm schedule failed: \(error.localizedDescription, privacy: .public)")
            await scheduleFallbackNotification(after: remaining, babyName: babyName)
        }
    }

    /// Cancels the pending feed alarm and any fallback notification, if present.
    static func cancel() async {
        try? AlarmManager.shared.cancel(id: alarmID)
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [fallbackNotificationID])
    }

    /// Best-effort local-notification reminder for when AlarmKit can't schedule.
    private static func scheduleFallbackNotification(after seconds: TimeInterval, babyName: String) async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(babyName) — feed due"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        let request = UNNotificationRequest(identifier: fallbackNotificationID, content: content, trigger: trigger)
        try? await center.add(request)
    }

    /// Tells the user once that reminders are on but blocked, so they're not left
    /// wondering why feeds never alert. Only fires while reminders are enabled.
    @MainActor
    private static func surfaceDenialIfNeeded() {
        guard LocalPrefs.shared.feedReminderEnabled,
              !UserDefaults.standard.bool(forKey: denialSurfacedKey) else { return }
        UserDefaults.standard.set(true, forKey: denialSurfacedKey)
        StoreErrorCenter.shared.report("Feed reminders need permission — enable alarms for Two of Us in Settings.")
    }
}
