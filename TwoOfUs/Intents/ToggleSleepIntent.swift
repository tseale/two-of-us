import AppIntents

/// Starts a sleep timer, or stops the running one — without opening the app.
/// The Sleep Live Activity is reconciled by the app the next time it becomes
/// active (a widget-extension process can't reliably start a Live Activity).
struct ToggleSleepIntent: AppIntent {
    static var title: LocalizedStringResource = "Start or Stop Sleep"
    static var description = IntentDescription("Starts a sleep timer for Miller, or stops the running one.")
    static var openAppWhenRun: Bool = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard let logger = QuickLogger.make() else {
            return .result(dialog: "Couldn't reach Two of Us.")
        }
        let name = logger.babyName ?? "Miller"
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
        let slept = runningStart.map { TimeFormatting.duration(from: $0, to: .now) }
        return .result(
            dialog: slept.map { "\(name) is awake — slept \($0)." } ?? "\(name) is awake.",
            view: ConfirmationSnippet(emoji: "☀️", title: "\(name) is awake",
                                      subtitle: slept.map { "Slept \($0)" })
        )
    }
}
