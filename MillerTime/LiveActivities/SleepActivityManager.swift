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
        Task {
            await endAll()
            AppGroup.userDefaults?.removeObject(forKey: activityIDKey)
        }
    }

    private static func endAll() {
        Task {
            for activity in Activity<SleepActivityAttributes>.activities {
                await activity.end(dismissalPolicy: .immediate)
            }
        }
    }
}
