import AppIntents

/// Starts a sleep timer, or stops the running one — without opening the app.
/// The Sleep Live Activity is reconciled by the app the next time it becomes
/// active (a widget-extension process can't reliably start a Live Activity).
/// Starts a sleep — and is a calm no-op if one is already running. Backs the
/// "Start sleep" Siri phrase: a spoken *start* must never stop a running timer
/// the way the blind toggle did when state and speech disagreed.
struct StartSleepIntent: AppIntent {
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
        logger.toggleSleep()
        return .result(
            dialog: "\(name) is down for sleep.",
            view: ConfirmationSnippet(emoji: "💤", title: "Sleep started", subtitle: name)
        )
    }
}

/// Stops the running sleep — and is a calm no-op if none is running. Backs the
/// "Stop sleep" Siri phrase; also sweeps any stray Live Activity so a stale
/// Dynamic Island timer can't outlive the sleep it counted.
struct StopSleepIntent: AppIntent {
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
            await SleepActivityAttributes.endAllRunning()
            return .result(
                dialog: "\(name) is already awake.",
                view: ConfirmationSnippet(emoji: "☀️", title: "Already awake", subtitle: name)
            )
        }
        logger.toggleSleep()
        await SleepActivityAttributes.endAllRunning()
        let slept = TimeFormatting.duration(from: runningStart, to: .now)
        return .result(
            dialog: "\(name) is awake — slept \(slept).",
            view: ConfirmationSnippet(emoji: "☀️", title: "\(name) is awake", subtitle: "Slept \(slept)")
        )
    }
}

struct ToggleSleepIntent: AppIntent {
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
        let started = logger.toggleSleep()
        if started {
            return .result(
                dialog: "\(name) is down for sleep.",
                view: ConfirmationSnippet(emoji: "💤", title: "Sleep started",
                                          subtitle: name)
            )
        }
        // Sleep just stopped — tear down the Live Activity now. This intent can
        // run outside the app (Siri / Shortcuts), where the foreground reconcile
        // won't fire, so the Dynamic Island would otherwise keep counting.
        await SleepActivityAttributes.endAllRunning()
        let slept = runningStart.map { TimeFormatting.duration(from: $0, to: .now) }
        return .result(
            dialog: slept.map { "\(name) is awake — slept \($0)." } ?? "\(name) is awake.",
            view: ConfirmationSnippet(emoji: "☀️", title: "\(name) is awake",
                                      subtitle: slept.map { "Slept \($0)" })
        )
    }
}
