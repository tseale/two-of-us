import AppIntents

/// Logs a bottle without opening the app. With no amount supplied
/// (the widget button / "Hey Siri" case) it uses the default feed amount.
struct LogFeedIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a Feed"
    static var description = IntentDescription("Logs a bottle for your baby using your default amount.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Amount (oz)")
    var amountOz: Double?

    init() {}
    init(amountOz: Double? = nil) { self.amountOz = amountOz }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard let logger = QuickLogger.make() else {
            return .result(dialog: "Couldn't reach Two of Us.")
        }
        let name = logger.babyName ?? "Baby"
        let event = logger.logFeed(amountOz: amountOz ?? logger.defaultFeedOz)
        let oz = OzFormat.string(event.amountOz)
        return .result(
            dialog: "Logged \(oz) oz for \(name).",
            view: ConfirmationSnippet(emoji: "🍼", title: "Logged \(oz) oz",
                                      subtitle: "for \(name) · \(TimeFormatting.clock(event.timestamp))")
        )
    }
}
