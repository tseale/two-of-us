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

    // MARK: Serialized operations
    //
    // Every ActivityKit call runs through this chain, one operation at a time,
    // in call order. The old shape — a detached `Task {}` per call, off any
    // actor — gave the operations no ordering at all: the foreground reconcile
    // and the sync-fetch reconcile that lands right behind it (AppDelegate
    // kicks a fetch on every foreground) could BOTH observe "sleep active, no
    // activity running" and both request one, and the second request's
    // end-all-first sweep could tear down the activity the first had just
    // created — with nothing left if the app lost foreground before the second
    // request landed. Same race between `end()` and an immediately following
    // `start()` (stop + resume undo). All of those are the sporadic blank lock
    // screen during an active sleep.

    @MainActor private static var chain: Task<Void, Never>?

    @MainActor private static func enqueue(_ op: @escaping @MainActor () async -> Void) {
        chain = Task { [previous = chain] in
            await previous?.value
            await op()
        }
    }

    @MainActor
    static func start(babyName: String, at startedAt: Date, nextFeed: NextFeed?) {
        enqueue { await requestActivity(babyName: babyName, startedAt: startedAt, nextFeed: nextFeed) }
    }

    @MainActor
    static func end() {
        enqueue { await endAll() }
    }

    /// Re-states a running activity: a backdated start time (sleep edit) or a
    /// moved next-feed prediction (feed logged/edited mid-sleep). No-ops when
    /// nothing changed, so reconcile can call it on every foreground.
    @MainActor
    static func refresh(startedAt: Date, nextFeed: NextFeed?) {
        enqueue { await refreshRunning(startedAt: startedAt, nextFeed: nextFeed) }
    }

    /// Brings the Live Activity in line with the data — used when the app
    /// becomes active or a sync fetch lands, since sleeps started/stopped from
    /// a widget button or Siri can't manage the Live Activity from their own
    /// process. Also refreshes a running activity's state, so a co-parent's
    /// synced-in feed or backdated sleep start reaches this lock screen too.
    @MainActor
    static func reconcile(babyName: String, activeSleepStartedAt: Date?, nextFeed: NextFeed?) {
        enqueue {
            // Decided INSIDE the queued operation, after every earlier
            // start/end has settled — sampling `activities` at call time is
            // exactly how two back-to-back reconciles used to double-start.
            switch (activeSleepStartedAt, runningActivities.isEmpty) {
            case let (startedAt?, true):
                await requestActivity(babyName: babyName, startedAt: startedAt, nextFeed: nextFeed)
            case let (startedAt?, false):
                await refreshRunning(startedAt: startedAt, nextFeed: nextFeed)
            case (nil, false):
                await endAll()
            case (nil, true):
                break
            }
        }
    }

    // MARK: ActivityKit

    /// Activities still showing a live timer. `.ended`/`.dismissed` ones — the
    /// user swiped the card away, or iOS force-ended the activity at its
    /// 8-hour cap (routine for an overnight sleep) — must not count as
    /// running, or reconcile would keep "refreshing" a dead activity all
    /// night instead of requesting a fresh one.
    private static var runningActivities: [Activity<SleepActivityAttributes>] {
        Activity<SleepActivityAttributes>.activities.filter {
            $0.activityState == .active || $0.activityState == .stale
        }
    }

    private static func requestActivity(babyName: String, startedAt: Date, nextFeed: NextFeed?) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            // Not silent: "Live Activities are off for this app in Settings"
            // must be distinguishable from a request failure in the logs.
            AppLog.liveActivity.error("Live Activity not requested: Live Activities are disabled for this app")
            return
        }
        // Sweep survivors first (crash recovery, the 8-hour system end) so the
        // per-app activity limit can never starve the new request.
        await endAll()
        let attributes = SleepActivityAttributes(babyName: babyName)
        do {
            _ = try Activity<SleepActivityAttributes>.request(
                attributes: attributes,
                content: content(startedAt: startedAt, nextFeed: nextFeed),
                pushType: nil
            )
            AppLog.liveActivity.log("Live Activity started for sleep since \(startedAt, privacy: .public)")
        } catch {
            // Expected when the app isn't foreground — a co-parent's sleep
            // arriving over a silent push can't start an activity (ActivityKit
            // allows that only via push-to-start, which needs a push server).
            // The next foreground reconcile() retries: it re-creates the
            // activity whenever a sleep is active but none is running.
            AppLog.liveActivity.error("Live Activity request failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func refreshRunning(startedAt: Date, nextFeed: NextFeed?) async {
        let fresh = state(startedAt: startedAt, nextFeed: nextFeed)
        for activity in runningActivities where activity.content.state != fresh {
            await activity.update(content(startedAt: startedAt, nextFeed: nextFeed))
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

    /// Ends every activity regardless of state — ending an already-ended one
    /// is harmless, and it's what clears `.ended` survivors out of
    /// `Activity.activities`.
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
