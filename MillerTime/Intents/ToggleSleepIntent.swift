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
    func perform() async throws -> some IntentResult {
        QuickLogger.make()?.toggleSleep()
        return .result()
    }
}
