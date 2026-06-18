import ActivityKit
import Foundation

/// Starts, updates, and ends the Sleep Live Activity. Called by EventStore.
enum SleepActivityManager {
    private static let activityIDKey = "sleepLiveActivityID"

    static func start(babyName: String, at startedAt: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        Task {
            // Await any prior ends first (crash-recovery) so a slow teardown can't
            // flicker against the activity we're about to request.
            await endAll()

            let attributes = SleepActivityAttributes(babyName: babyName)
            let state = SleepActivityAttributes.ContentState(startedAt: startedAt)
            // Dim the Island ~1h in rather than keeping it bright all night; the
            // .timer text keeps counting regardless.
            let content = ActivityContent(state: state, staleDate: startedAt.addingTimeInterval(3600))

            do {
                let activity = try Activity<SleepActivityAttributes>.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
                AppGroup.userDefaults?.set(activity.id, forKey: activityIDKey)
            } catch {
                // The next foreground reconcile() retries: it re-creates the
                // activity whenever a sleep is active but none is running.
                AppLog.liveActivity.error("Live Activity request failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    static func end() {
        Task {
            await endAll()
            AppGroup.userDefaults?.removeObject(forKey: activityIDKey)
        }
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

    private static func endAll() async {
        for activity in Activity<SleepActivityAttributes>.activities {
            let finalContent = ActivityContent(
                state: activity.content.state,
                staleDate: nil
            )
            await activity.end(finalContent, dismissalPolicy: .immediate)
        }
    }
}
