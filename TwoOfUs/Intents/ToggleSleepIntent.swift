import AppIntents

/// Starts a sleep timer, or stops the running one — without opening the app.
///
/// Every sleep intent here is a `LiveActivityIntent`: the system runs its
/// `perform()` in the APP process (not the widget extension), which is the one
/// place ActivityKit accepts a start request. That's what lets a widget-button
/// or Siri sleep start put the timer on the lock screen *immediately*, instead
/// of leaving the lock screen blank until the app is next foregrounded and
/// `SleepActivityManager.reconcile` catches up. The next-feed countdown column
/// starts empty from these paths (the schedule engines don't compile into the
/// widget extension, so the prediction can't be computed here) and fills in on
/// the next reconcile.
///
/// Starts a sleep — and is a calm no-op if one is already running. Backs the
/// "Start sleep" Siri phrase: a spoken *start* must never stop a running timer
/// the way the blind toggle did when state and speech disagreed.
struct StartSleepIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Start Sleep"
    static var description = IntentDescription("Starts a sleep timer for your baby. Does nothing if one is already running.")
    static var openAppWhenRun: Bool = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard let logger = QuickLogger.make() else {
            return .result(dialog: "Couldn't reach Two of Us.")
        }
        let name = logger.babyName ?? "Baby"
        guard logger.activeSleep == nil else {
            return .result(
                dialog: "\(name) is already asleep.",
                view: ConfirmationSnippet(emoji: "💤", title: "Already asleep", subtitle: name)
            )
        }
        guard logger.isTrackingEnabled(.sleep) else {
            return .result(dialog: "Sleep logging is currently turned off in Two of Us.")
        }
        guard logger.toggleSleep() != nil else {
            return .result(dialog: "Couldn't start that sleep — open Two of Us and try again.")
        }
        SleepActivityManager.start(babyName: name,
                                   at: logger.activeSleep?.startedAt ?? .now,
                                   nextFeed: nil)
        return .result(
            dialog: "\(name) is down for sleep.",
            view: ConfirmationSnippet(emoji: "💤", title: "Sleep started", subtitle: name)
        )
    }
}

// Note: `StopSleepIntent` below calls `toggleSleep()` only while a sleep is
// running, where it completes the existing event and never needs an owner.

/// Stops the running sleep — and is a calm no-op if none is running. Backs the
/// "Stop sleep" Siri phrase; also sweeps any stray Live Activity so a stale
/// Dynamic Island timer can't outlive the sleep it counted.
struct StopSleepIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop Sleep"
    static var description = IntentDescription("Stops your baby's running sleep timer. Does nothing if the baby is awake.")
    static var openAppWhenRun: Bool = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard let logger = QuickLogger.make() else {
            return .result(dialog: "Couldn't reach Two of Us.")
        }
        let name = logger.babyName ?? "Baby"
        guard let runningStart = logger.activeSleep?.startedAt else {
            SleepActivityManager.end(at: nil)
            return .result(
                dialog: "\(name) is already awake.",
                view: ConfirmationSnippet(emoji: "☀️", title: "Already awake", subtitle: name)
            )
        }
        let endedAt = Date.now
        logger.toggleSleep()
        SleepActivityManager.end(at: endedAt)
        let slept = TimeFormatting.duration(from: runningStart, to: endedAt)
        return .result(
            dialog: "\(name) is awake — slept \(slept).",
            view: ConfirmationSnippet(emoji: "☀️", title: "\(name) is awake", subtitle: "Slept \(slept)")
        )
    }
}

struct ToggleSleepIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Start or Stop Sleep"
    static var description = IntentDescription("Starts a sleep timer for your baby, or stops the running one.")
    static var openAppWhenRun: Bool = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard let logger = QuickLogger.make() else {
            return .result(dialog: "Couldn't reach Two of Us.")
        }
        let name = logger.babyName ?? "Baby"
        // Grab the running sleep (if any) BEFORE toggling so we can report its length.
        let runningStart = logger.activeSleep?.startedAt
        // Only a *start* needs sleep tracking on — stopping a running sleep is
        // always allowed.
        guard runningStart != nil || logger.isTrackingEnabled(.sleep) else {
            return .result(dialog: "Sleep logging is currently turned off in Two of Us.")
        }
        let endedAt = Date.now
        guard let started = logger.toggleSleep() else {
            return .result(dialog: "Couldn't start that sleep — open Two of Us and try again.")
        }
        if started {
            SleepActivityManager.start(babyName: name,
                                       at: logger.activeSleep?.startedAt ?? .now,
                                       nextFeed: nil)
            return .result(
                dialog: "\(name) is down for sleep.",
                view: ConfirmationSnippet(emoji: "💤", title: "Sleep started",
                                          subtitle: name)
            )
        }
        SleepActivityManager.end(at: endedAt)
        let slept = runningStart.map { TimeFormatting.duration(from: $0, to: endedAt) }
        return .result(
            dialog: slept.map { "\(name) is awake — slept \($0)." } ?? "\(name) is awake.",
            view: ConfirmationSnippet(emoji: "☀️", title: "\(name) is awake",
                                      subtitle: slept.map { "Slept \($0)" })
        )
    }
}

/// `SetValueIntent` backing the Control Center / lock-screen sleep toggle:
/// drives sleep to the requested state, reusing `QuickLogger.toggleSleep()`
/// only when a change is needed. Lives in this shared file (not the widget
/// bundle) because `LiveActivityIntent` performs run in the app process — the
/// type must exist in the app target for the system to find it there.
struct SetSleepIntent: SetValueIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Set Sleep State"
    static var description = IntentDescription("Starts or stops your baby's sleep timer.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Asleep")
    var value: Bool

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let logger = QuickLogger.make() else { return .result() }
        let isActive = logger.activeSleep != nil
        if value != isActive { logger.toggleSleep() }
        if value {
            if let startedAt = logger.activeSleep?.startedAt {
                SleepActivityManager.start(babyName: logger.babyName ?? "Baby",
                                           at: startedAt, nextFeed: nil)
            }
        } else {
            // A stale "Wake" tapped after the sleep already stopped still
            // sweeps leftovers (endedAt nil path ends immediately).
            SleepActivityManager.end(at: isActive ? .now : nil)
        }
        return .result()
    }
}

extension SetSleepIntent {
    /// A copy driven to a specific state. Widget buttons pass the OPPOSITE of
    /// the state they rendered, so a tap means what the parent saw on screen —
    /// a stale "Wake ☀️" tapped after the co-parent already stopped the sleep
    /// is a no-op, where a blind `ToggleSleepIntent` would start a phantom
    /// session nobody asked for.
    static func driving(asleep: Bool) -> SetSleepIntent {
        var intent = SetSleepIntent()
        intent.value = asleep
        return intent
    }
}
