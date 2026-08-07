import ActivityKit
import Foundation

/// Starts, updates, and ends the Sleep Live Activity.
///
/// THE invariant, stated once: **if a sleep session is active and this process
/// can start a Live Activity, one must be running — no matter who or what
/// started the sleep.** `reconcile` is the single decision point that enforces
/// it; every surface funnels here:
/// - app foreground (`AppDelegate.applicationDidBecomeActive`),
/// - CloudKit sync fetch (`SyncManager.reconcileLiveActivity`) — co-parent,
///   watch, and SNOO-on-the-other-phone sleeps land through this,
/// - in-app writes (`EventStore` start/stop/edit/delete/undo),
/// - widget buttons and Siri (`ToggleSleepIntent.swift` — `LiveActivityIntent`
///   runs those in THIS process, so they call straight in).
///
/// Compiled into both the app and the widget extension so the intents can
/// reference it; ActivityKit only honors requests from the app process, which
/// is where `LiveActivityIntent` performs run.
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
    // request landed. Same race between `end` and an immediately following
    // `start` (stop + resume undo). All of those are the sporadic blank lock
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

    /// Ends the Live Activity.
    /// - Parameter endedAt: when the sleep actually ended. Non-nil finalizes a
    ///   running activity with a "slept X" summary card that lingers briefly on
    ///   the lock screen before dismissing itself. Nil is a sweep — undo of a
    ///   just-started sleep, deletes, "clear all logs" — where a summary would
    ///   memorialize a sleep that never really happened, so the card is torn
    ///   down immediately instead.
    @MainActor
    static func end(at endedAt: Date?) {
        enqueue { await endAll(finalizing: endedAt) }
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
    /// `lastSleepEndedAt` keeps the summary card truthful when the end arrived
    /// via sync: the sleep finished when the co-parent said it did, not when
    /// this phone found out.
    @MainActor
    static func reconcile(babyName: String, activeSleepStartedAt: Date?,
                          lastSleepEndedAt: Date? = nil, nextFeed: NextFeed?) {
        enqueue {
            await sweepDismissedCorpses()
            // Decided INSIDE the queued operation, after every earlier
            // start/end has settled — sampling `activities` at call time is
            // exactly how two back-to-back reconciles used to double-start.
            switch (activeSleepStartedAt, runningActivities.isEmpty) {
            case let (startedAt?, true):
                AppLog.liveActivity.log("Reconcile: sleep active since \(startedAt, privacy: .public) with no Live Activity — starting one")
                await requestActivity(babyName: babyName, startedAt: startedAt, nextFeed: nextFeed)
            case let (startedAt?, false):
                AppLog.liveActivity.debug("Live Activity already running for session started \(startedAt, privacy: .public)")
                await refreshRunning(startedAt: startedAt, nextFeed: nextFeed)
            case (nil, false):
                AppLog.liveActivity.log("Reconcile: no active sleep but a Live Activity is running — ending it")
                await endAll(finalizing: lastSleepEndedAt ?? .now)
            case (nil, true):
                AppLog.liveActivity.debug("Reconcile: no active sleep, no Live Activity — nothing to do")
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

    /// Clears user-swiped (`.dismissed`) husks out of `Activity.activities` so
    /// they can never crowd the per-app activity budget. Deliberately leaves
    /// `.ended` entries alone: an `.ended` activity may be the "slept X"
    /// summary card still lingering on the lock screen, and sweeping it here
    /// would cut its linger short every time the app foregrounds. The
    /// pre-request sweep in `requestActivity` clears those the moment a new
    /// sleep needs the slot.
    private static func sweepDismissedCorpses() async {
        let corpses = Activity<SleepActivityAttributes>.activities.filter {
            $0.activityState == .dismissed
        }
        guard !corpses.isEmpty else { return }
        AppLog.liveActivity.log("Cleaning up \(corpses.count) stale Live Activities")
        for corpse in corpses {
            await corpse.end(nil, dismissalPolicy: .immediate)
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
        await endAll(finalizing: nil)
        let attributes = SleepActivityAttributes(babyName: babyName)
        // Retry a couple of times before giving up: a request made the instant
        // the app becomes active (cold launch straight into
        // `applicationDidBecomeActive`) can fail transiently while the scene
        // finishes foregrounding. The old single-shot request logged the error
        // and left the lock screen blank until the NEXT foreground — one of
        // the "opened the app during a nap, no Live Activity" reports.
        for attempt in 1...3 {
            do {
                AppLog.liveActivity.log("Starting Live Activity for sleep session started \(startedAt, privacy: .public) (attempt \(attempt))")
                _ = try Activity<SleepActivityAttributes>.request(
                    attributes: attributes,
                    content: content(startedAt: startedAt, nextFeed: nextFeed),
                    pushType: nil
                )
                AppLog.liveActivity.log("Live Activity started for sleep since \(startedAt, privacy: .public)")
                return
            } catch {
                // Expected when the app isn't foreground — a co-parent's sleep
                // arriving over a silent push can't start an activity
                // (ActivityKit allows that only via push-to-start, which needs
                // a push server). The next foreground reconcile() retries: it
                // re-creates the activity whenever a sleep is active but none
                // is running.
                AppLog.liveActivity.error("Failed to start Live Activity (attempt \(attempt)): \(error.localizedDescription, privacy: .public)")
                if attempt < 3 { try? await Task.sleep(for: .seconds(1)) }
            }
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

    /// Ends every activity — ending an already-ended one is harmless, and it's
    /// what clears `.ended` survivors out of `Activity.activities`.
    ///
    /// With `endedAt` set, a still-running activity gets a final content update
    /// (frozen timer, "slept X" summary — see `SleepLockScreenView`) and
    /// lingers on the lock screen for a few minutes before dismissing itself.
    /// Already-dead entries, and every entry when `endedAt` is nil, are removed
    /// immediately.
    private static func endAll(finalizing endedAt: Date?) async {
        for activity in Activity<SleepActivityAttributes>.activities {
            let isRunning = activity.activityState == .active || activity.activityState == .stale
            if let endedAt, isRunning {
                AppLog.liveActivity.log("Ending Live Activity for completed session started \(activity.content.state.startedAt, privacy: .public)")
                var finalState = activity.content.state
                finalState.endedAt = max(endedAt, finalState.startedAt)
                await activity.end(
                    ActivityContent(state: finalState, staleDate: nil),
                    dismissalPolicy: .after(.now.addingTimeInterval(15 * 60))
                )
            } else {
                await activity.end(
                    ActivityContent(state: activity.content.state, staleDate: nil),
                    dismissalPolicy: .immediate
                )
            }
        }
    }
}
