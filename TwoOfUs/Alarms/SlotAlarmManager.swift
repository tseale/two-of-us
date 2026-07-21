import AlarmKit
import SwiftUI
import UserNotifications

/// Empty payload — AlarmKit requires a concrete `AlarmMetadata` type per alarm.
nonisolated struct SlotAlarmMetadata: AlarmMetadata {}

/// Arms ONE loud AlarmKit alarm for the next schedule slot assigned to *this*
/// device's parent — the "actually wake me for my 3am" opt-in. A Time Sensitive
/// notification won't pierce Silent; being woken on time is the assignment's
/// whole contract, so the night shift gets the same AlarmKit treatment as the
/// interval feed alarm (`FeedAlarmManager`), which stands down around an armed
/// slot so one night never rings twice.
///
/// Device-local and opt-in (`LocalPrefs.nightSlotAlarmEnabled`); re-armed from
/// the same points as every reminder (write / sync fetch / foreground), so a
/// co-parent's swap silently moves the alarm to the right phone.
enum SlotAlarmManager {
    /// Stable id so every reschedule replaces the previous pending alarm.
    private static let alarmID = UUID(uuidString: "51070000-0000-0000-0000-000000000002")!
    /// Best-effort local-notification fallback when AlarmKit scheduling fails.
    private static let fallbackNotificationID = "slotAlarm.fallback"
    /// Anything sooner is a slot already at hand — the schedule reminder (15m
    /// lead) covers it; an alarm firing in seconds would just startle.
    private static let minimumLead: TimeInterval = 60
    /// App-Group-visible fire date of the armed alarm, read by
    /// `FeedAlarmManager` to stand down its interval alarm near it.
    private static let fireDateKey = "alarms.slotFireDate"

    /// When the armed slot alarm fires, or nil while nothing is armed.
    static var armedFireDate: Date? {
        guard let t = UserDefaults.standard.object(forKey: fireDateKey) as? Double else { return nil }
        return Date(timeIntervalSinceReferenceDate: t)
    }

    /// Re-arms the alarm for my next assigned occurrence, replacing any pending
    /// one. Clears (and no-ops) when the opt-in is off, nothing is assigned to
    /// me, or the next slot is already at hand.
    static func reschedule() async {
        await cancel()
        guard LocalPrefs.shared.nightSlotAlarmEnabled,
              !LocalPrefs.shared.demoModeEnabled,
              let logger = QuickLogger.make(),
              let myID = logger.myParticipantID else { return }

        let slots = logger.planSlots
        guard !slots.isEmpty else { return }
        let engine = ScheduleEngine(
            slots: slots, overrides: logger.planOverrides,
            feeds: logger.recentFeeds(), sleeps: logger.recentSleeps(),
            targetFeedInterval: logger.targetFeedInterval
        )
        guard let next = engine.upcomingAssigned(to: myID, horizon: 24 * 3600).first else { return }
        let remaining = next.date.timeIntervalSinceNow
        guard remaining >= minimumLead else { return }
        guard await requestAuthorization() else { return }

        let babyName = logger.babyName ?? "Baby"
        let kindWord = next.kind == .sleep ? "sleep" : "bottle"
        let title = "\(babyName) — your \(TimeFormatting.clock(next.date)) \(kindWord)"
        let alert = AlarmPresentation.Alert(
            title: "\(title)",
            stopButton: AlarmButton(text: "I'm up", textColor: .white, systemImageName: "checkmark")
        )
        let attributes = AlarmAttributes<SlotAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            tintColor: next.kind == .sleep ? AppColor.accentSleep : AppColor.accentFeed
        )
        let configuration: AlarmManager.AlarmConfiguration = .timer(
            duration: remaining,
            attributes: attributes
        )
        // Publish the fire date before the (async) schedule call so a
        // concurrently re-arming FeedAlarmManager sees it as early as possible;
        // the worst race outcome is one redundant alarm, once.
        UserDefaults.standard.set(next.date.timeIntervalSinceReferenceDate, forKey: fireDateKey)
        do {
            _ = try await AlarmManager.shared.schedule(id: alarmID, configuration: configuration)
        } catch {
            AppLog.alarms.error("Slot alarm schedule failed: \(error.localizedDescription, privacy: .public)")
            // The fallback notification can't pierce Silent — retract the
            // published fire date so the feed alarm doesn't stand down against
            // an alarm that isn't actually armed.
            UserDefaults.standard.removeObject(forKey: fireDateKey)
            await scheduleFallbackNotification(after: remaining, title: title)
        }
    }

    /// Cancels the pending slot alarm, its fallback, and the published fire date.
    static func cancel() async {
        try? AlarmManager.shared.cancel(id: alarmID)
        UserDefaults.standard.removeObject(forKey: fireDateKey)
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [fallbackNotificationID])
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

    /// Best-effort local-notification reminder for when AlarmKit can't schedule.
    private static func scheduleFallbackNotification(after seconds: TimeInterval, title: String) async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        let request = UNNotificationRequest(identifier: fallbackNotificationID, content: content, trigger: trigger)
        try? await center.add(request)
    }
}
