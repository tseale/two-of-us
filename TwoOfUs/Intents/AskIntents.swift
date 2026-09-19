import AppIntents
import Foundation

// The parameterized query catalog: structured intents Siri's model can fill
// from natural phrasing (AppEnum parameters — the thing phrase matching CAN
// interpolate), plus a free-text catch-all. All of them read through
// AskEngine, so every number is computed by the same tested arithmetic.

// MARK: - Enums Siri can fill

enum StatMetricAppEnum: String, AppEnum {
    case totalSleep, nightWakes, feedTotal, feedCount, averageBottle
    case feedingRhythm, diapers, longestStretch, bedtime

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Stat")
    static var caseDisplayRepresentations: [StatMetricAppEnum: DisplayRepresentation] = [
        .totalSleep: "Total sleep",
        .nightWakes: "Night wake-ups",
        .feedTotal: "Total ounces",
        .feedCount: "Number of feeds",
        .averageBottle: "Average bottle size",
        .feedingRhythm: "Time between feeds",
        .diapers: "Diaper count",
        .longestStretch: "Longest sleep stretch",
        .bedtime: "Bedtime",
    ]

    var askMetric: AskMetric {
        switch self {
        case .totalSleep: return .totalSleep
        case .nightWakes: return .nightWakes
        case .feedTotal: return .feedOz
        case .feedCount: return .feedCount
        case .averageBottle: return .averageBottle
        case .feedingRhythm: return .averageFeedInterval
        case .diapers: return .diaperCount(nil)
        case .longestStretch: return .longestStretch
        case .bedtime: return .bedtime
        }
    }
}

enum StatPeriodAppEnum: String, AppEnum {
    case today, yesterday, lastNight, thisWeek, lastWeek, allTime

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Period")
    static var caseDisplayRepresentations: [StatPeriodAppEnum: DisplayRepresentation] = [
        .today: "Today",
        .yesterday: "Yesterday",
        .lastNight: "Last night",
        .thisWeek: "This week",
        .lastWeek: "Last week",
        .allTime: "All time",
    ]

    var askPeriod: AskPeriod {
        switch self {
        case .today: return .today
        case .yesterday: return .yesterday
        case .lastNight: return .lastNight
        case .thisWeek: return .thisWeek
        case .lastWeek: return .lastWeek
        case .allTime: return .allTime
        }
    }
}

enum NextUpKindAppEnum: String, AppEnum {
    case feed, nap, wakeUp

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "What's Next")
    static var caseDisplayRepresentations: [NextUpKindAppEnum: DisplayRepresentation] = [
        .feed: "Next feed",
        .nap: "Next nap",
        .wakeUp: "Wake-up time",
    ]

    var askMetric: AskMetric {
        switch self {
        case .feed: return .nextFeed
        case .nap: return .nextNap
        case .wakeUp: return .wakeUp
        }
    }
}

// MARK: - Shared plumbing

@MainActor
private func askAnswer(for query: ParsedQuery) -> AskAnswer? {
    guard let logger = QuickLogger.make() else { return nil }
    return AskEngine.fromStore(logger).answer(query)
}

// MARK: - Intents

/// "Get a stat from Two of Us" — the enum-parameterized workhorse. Siri (and
/// on iOS 27, the Siri app) fills metric + period from natural phrasing.
struct GetStatIntent: AppIntent {
    static var title: LocalizedStringResource = "Get a Baby Stat"
    static var description = IntentDescription(
        "Answers a question about the baby's sleep, feeds, or diapers over a time period — total sleep last night, ounces today, wake-ups, longest stretch, and more."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Stat", default: .totalSleep)
    var metric: StatMetricAppEnum

    @Parameter(title: "Period", default: .lastNight)
    var period: StatPeriodAppEnum

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let query = ParsedQuery(metric: metric.askMetric, period: period.askPeriod)
        guard let answer = askAnswer(for: query) else {
            return .result(dialog: "Couldn't reach Two of Us.")
        }
        return .result(dialog: "\(answer.sentence)")
    }
}

/// "Compare a stat in Two of Us" — the same catalog with a baseline window.
struct CompareStatIntent: AppIntent {
    static var title: LocalizedStringResource = "Compare a Baby Stat"
    static var description = IntentDescription(
        "Compares a stat across two periods — is the baby sleeping more this week than last week?"
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Stat", default: .totalSleep)
    var metric: StatMetricAppEnum

    @Parameter(title: "Period", default: .thisWeek)
    var period: StatPeriodAppEnum

    @Parameter(title: "Compared To", default: .lastWeek)
    var baseline: StatPeriodAppEnum

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let query = ParsedQuery(
            metric: metric.askMetric,
            period: period.askPeriod,
            compareTo: baseline.askPeriod
        )
        guard let answer = askAnswer(for: query) else {
            return .result(dialog: "Couldn't reach Two of Us.")
        }
        return .result(dialog: "\(answer.sentence)")
    }
}

/// "What's next for the baby?" — routes to the prediction machinery.
struct NextUpIntent: AppIntent {
    static var title: LocalizedStringResource = "What's Next for the Baby"
    static var description = IntentDescription(
        "Predicts what's coming — the next feed, the next nap, or when the baby will likely wake up."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "What", default: .feed)
    var kind: NextUpKindAppEnum

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let query = ParsedQuery(metric: kind.askMetric, period: .today)
        guard let answer = askAnswer(for: query) else {
            return .result(dialog: "Couldn't reach Two of Us.")
        }
        return .result(dialog: "\(answer.sentence)")
    }
}

/// "Ask Two of Us…" — the free-text catch-all. Deterministic parser first;
/// the on-device model (when available) classifies what the parser can't;
/// unmatched questions fall through to a notes search, then to a help reply.
struct AskTwoOfUsIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask Two of Us"
    static var description = IntentDescription(
        "Answers a spoken or typed question about the baby from the app's own data — \"what time did he go to sleep last night?\", \"is he eating more than usual?\", \"when did we start vitamin D drops?\""
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Question", requestValueDialog: "What do you want to ask?")
    var question: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let logger = QuickLogger.make() else {
            return .result(dialog: "Couldn't reach Two of Us.")
        }
        let engine = AskEngine.fromStore(logger)

        if let query = QueryParser.parse(question) {
            return .result(dialog: "\(engine.answer(query).sentence)")
        }

        #if canImport(FoundationModels)
        if let query = await AskModelParser.parse(question) {
            return .result(dialog: "\(engine.answer(query).sentence)")
        }
        #endif

        // Last resorts: maybe it's about a note; otherwise say what works.
        let fallback = engine.answer(ParsedQuery(
            metric: .noteSearch(question.lowercased()), period: .allTime
        ))
        if !fallback.sentence.hasPrefix("No notes mention") {
            return .result(dialog: "\(fallback.sentence)")
        }
        return .result(dialog: """
            I couldn't match that one. Try asking about feeds, sleep, or diapers — \
            like "how much did he sleep last night?" or "is he eating more than usual?"
            """)
    }
}
