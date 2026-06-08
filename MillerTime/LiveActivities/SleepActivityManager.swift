import ActivityKit
import Foundation

/// Starts, updates, and ends the Sleep Live Activity. Called by EventStore.
enum SleepActivityManager {
    private static let activityIDKey = "sleepLiveActivityID"

    static func start(babyName: String, at startedAt: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // End any stale activities first (handles crash-recovery)
        endAll()

        let attributes = SleepActivityAttributes(babyName: babyName)
        let state = SleepActivityAttributes.ContentState(startedAt: startedAt)
        let content = ActivityContent(state: state, staleDate: nil)

        do {
            let activity = try Activity<SleepActivityAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            AppGroup.userDefaults?.set(activity.id, forKey: activityIDKey)
        } catch {
            print("SleepActivityManager.start error: \(error)")
        }
    }

    static func end() {
        endAll()
        AppGroup.userDefaults?.removeObject(forKey: activityIDKey)
    }

    /// Brings the Live Activity in line with the data — used when the app
    /// becomes active, since sleeps started/stopped from a widget button or
    /// Siri can't manage the Live Activity from their own process.
    static func reconcile(babyName: String, activeSleepStartedAt: Date?) {
        let running = !Activity<SleepActivityAttributes>.activities.isEmpty
        switch (activeSleepStartedAt, running) {
        case let (startedAt?, false):
            start(babyName: babyName, at: startedAt)
        case (nil, true):
            end()
        default:
            break
        }
    }

    private static func endAll() {
        for activity in Activity<SleepActivityAttributes>.activities {
            let finalContent = ActivityContent(
                state: activity.content.state,
                staleDate: nil
            )
            Task {
                await activity.end(finalContent, dismissalPolicy: .immediate)
            }
        }
    }
}
