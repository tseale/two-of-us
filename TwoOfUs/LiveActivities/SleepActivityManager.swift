import ActivityKit
import Foundation

/// Starts, updates, and ends the Sleep Live Activity. Called by EventStore.
enum SleepActivityManager {
    /// The next expected feed, snapshotted into the activity's ContentState.
    /// Computed app-side (`QuickLogger.nextFeedPrediction` in
    /// ScheduleAssembly.swift) because the schedule engines don't compile into
    /// the widget extension — the view only renders what's stored here.
    struct NextFeed: Equatable {
        let date: Date
        let ownerName: String?
        let ownerColorHex: String?
    }

    static func start(babyName: String, at startedAt: Date, nextFeed: NextFeed?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        Task {
            // Await any prior ends first (crash-recovery) so a slow teardown can't
            // flicker against the activity we're about to request.
            await endAll()

            let attributes = SleepActivityAttributes(babyName: babyName)
            do {
                _ = try Activity<SleepActivityAttributes>.request(
                    attributes: attributes,
                    content: content(startedAt: startedAt, nextFeed: nextFeed),
                    pushType: nil
                )
            } catch {
                // The next foreground reconcile() retries: it re-creates the
                // activity whenever a sleep is active but none is running.
                AppLog.liveActivity.error("Live Activity request failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    static func end() {
        Task { await endAll() }
    }

    /// Re-states a running activity: a backdated start time (sleep edit) or a
    /// moved next-feed prediction (feed logged/edited mid-sleep). No-ops when
    /// nothing changed, so reconcile can call it on every foreground.
    static func refresh(startedAt: Date, nextFeed: NextFeed?) {
        Task {
            let fresh = state(startedAt: startedAt, nextFeed: nextFeed)
            for activity in Activity<SleepActivityAttributes>.activities
            where activity.content.state != fresh {
                await activity.update(content(startedAt: startedAt, nextFeed: nextFeed))
            }
        }
    }

    /// Brings the Live Activity in line with the data — used when the app
    /// becomes active or a sync fetch lands, since sleeps started/stopped from
    /// a widget button or Siri can't manage the Live Activity from their own
    /// process. Also refreshes a running activity's state, so a co-parent's
    /// synced-in feed or backdated sleep start reaches this lock screen too.
    static func reconcile(babyName: String, activeSleepStartedAt: Date?, nextFeed: NextFeed?) {
        let running = !Activity<SleepActivityAttributes>.activities.isEmpty
        switch (activeSleepStartedAt, running) {
        case let (startedAt?, false):
            start(babyName: babyName, at: startedAt, nextFeed: nextFeed)
        case let (startedAt?, true):
            refresh(startedAt: startedAt, nextFeed: nextFeed)
        case (nil, true):
            end()
        case (nil, false):
            break
        }
    }

    private static func state(startedAt: Date, nextFeed: NextFeed?) -> SleepActivityAttributes.ContentState {
        SleepActivityAttributes.ContentState(
            startedAt: startedAt,
            nextFeedAt: nextFeed?.date,
            nextFeedOwnerName: nextFeed?.ownerName,
            nextFeedOwnerColorHex: nextFeed?.ownerColorHex
        )
    }

    private static func content(startedAt: Date, nextFeed: NextFeed?) -> ActivityContent<SleepActivityAttributes.ContentState> {
        // Dim the Island ~1h in rather than keeping it bright all night; the
        // .timer text keeps counting regardless.
        ActivityContent(state: state(startedAt: startedAt, nextFeed: nextFeed),
                        staleDate: startedAt.addingTimeInterval(3600))
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
