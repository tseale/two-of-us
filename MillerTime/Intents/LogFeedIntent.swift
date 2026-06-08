import AppIntents

/// Logs a bottle for Miller without opening the app. With no amount supplied
/// (the widget button / "Hey Siri" case) it uses the default feed amount.
struct LogFeedIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a Feed"
    static var description = IntentDescription("Logs a bottle for Miller using your default amount.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Amount (oz)")
    var amountOz: Double?

    init() {}
    init(amountOz: Double? = nil) { self.amountOz = amountOz }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let logger = QuickLogger.make() else { return .result() }
        logger.logFeed(amountOz: amountOz ?? logger.defaultFeedOz)
        return .result()
    }
}
