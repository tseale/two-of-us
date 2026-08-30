import Foundation
#if canImport(FoundationModels)
import FoundationModels

/// Foundation Models fallback for questions the deterministic `QueryParser`
/// can't shape. The model's ONLY job is classification: pick a metric, a
/// period, and an optional comparison from fixed menus (guided generation, so
/// the output is a typed value — no prose parsing). It never sees event data
/// and never produces numbers; `AskEngine` computes the answer exactly as it
/// would for a parser hit.
enum AskModelParser {

    static var isAvailable: Bool { BabyIntelligence.isAvailable }

    /// The @Generable menus the model chooses from. Mirrors AskMetric /
    /// AskPeriod, plus explicit "none" escape hatches so the model isn't
    /// forced into a wrong bucket.
    @Generable
    struct Classification {
        @Guide(description: "What the question asks about. Use notes for questions about free-text notes the parents wrote (medicines, doctor advice, firsts). Use none only when nothing fits.")
        var metric: Metric

        @Guide(description: "The time window the question refers to. lastNight is the most recent night. Use allTime for 'ever' or records. Use unspecified when no window is mentioned.")
        var period: Period

        @Guide(description: "For comparison questions ('more than last week?', 'less than usual?'): the baseline window. Otherwise none.")
        var compareTo: Period

        @Guide(description: "For metric=notes only: the key words to search the notes for. Otherwise empty.")
        var noteKeywords: String

        @Generable
        enum Metric: String {
            case lastFeed, lastDiaper, sleepStatus, bedtime
            case totalSleep, nightWakes, feedTotalOunces, feedCount
            case diaperCount, averageBottle, longestSleepStretch, feedingInterval
            case nextFeed, nextNap, wakeUpTime
            case notes
            case none
        }

        @Generable
        enum Period: String {
            case today, yesterday, lastNight, thisWeek, lastWeek, allTime
            case unspecified, none
        }
    }

    /// Classifies the question, or returns nil when the model is unavailable,
    /// errors, or declines (`metric == .none`).
    static func parse(_ question: String) async -> ParsedQuery? {
        guard isAvailable else { return nil }
        let session = LanguageModelSession(instructions: """
            You classify questions that parents ask a baby-tracking app about \
            their baby's logged feeds, sleeps, diapers, and notes. Choose the \
            single best metric and time period for the question. Never answer \
            the question itself.
            """)
        do {
            let response = try await session.respond(
                to: question, generating: Classification.self
            )
            return query(from: response.content)
        } catch {
            AppLog.ai.error("Ask classification failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func query(from c: Classification) -> ParsedQuery? {
        guard let metric = askMetric(c) else { return nil }
        let period = askPeriod(c.period)
        let compare = askPeriod(c.compareTo)
        // Reuse the deterministic parser's defaulting by mapping unspecified
        // to the metric's natural window.
        let resolved = period ?? QueryParser.parse(placeholderQuestion(for: metric))?.period ?? .today
        return ParsedQuery(
            metric: metric,
            period: resolved,
            compareTo: metric.isAggregate ? compare : nil
        )
    }

    private static func askMetric(_ c: Classification) -> AskMetric? {
        switch c.metric {
        case .lastFeed: return .lastFeed
        case .lastDiaper: return .lastDiaper(nil)
        case .sleepStatus: return .sleepStatus
        case .bedtime: return .bedtime
        case .totalSleep: return .totalSleep
        case .nightWakes: return .nightWakes
        case .feedTotalOunces: return .feedOz
        case .feedCount: return .feedCount
        case .diaperCount: return .diaperCount(nil)
        case .averageBottle: return .averageBottle
        case .longestSleepStretch: return .longestStretch
        case .feedingInterval: return .averageFeedInterval
        case .nextFeed: return .nextFeed
        case .nextNap: return .nextNap
        case .wakeUpTime: return .wakeUp
        case .notes:
            let needle = c.noteKeywords.trimmingCharacters(in: .whitespacesAndNewlines)
            return needle.isEmpty ? nil : .noteSearch(needle.lowercased())
        case .none: return nil
        }
    }

    private static func askPeriod(_ p: Classification.Period) -> AskPeriod? {
        switch p {
        case .today: return .today
        case .yesterday: return .yesterday
        case .lastNight: return .lastNight
        case .thisWeek: return .thisWeek
        case .lastWeek: return .lastWeek
        case .allTime: return .allTime
        case .unspecified, .none: return nil
        }
    }

    /// A canonical question per metric, so the deterministic parser's
    /// default-period table stays the single source of truth.
    private static func placeholderQuestion(for metric: AskMetric) -> String {
        switch metric {
        case .totalSleep: return "how much did he sleep"
        case .nightWakes: return "how many times did he wake up"
        case .feedOz: return "how much did he eat"
        case .feedCount: return "how many feeds"
        case .diaperCount: return "how many diapers"
        case .averageBottle: return "average bottle"
        case .averageFeedInterval: return "how often does he eat on average"
        case .longestStretch: return "longest sleep"
        case .bedtime: return "when did he go to sleep"
        default: return "when did he last eat"
        }
    }
}
#endif
