import Foundation

/// The structured form every natural-language question is reduced to before
/// anything is computed. Both the deterministic `QueryParser` and the
/// Foundation Models fallback produce this; `AskEngine` consumes it. The
/// model never computes an answer — it only ever picks one of these.
struct ParsedQuery: Equatable {
    var metric: AskMetric
    var period: AskPeriod
    /// For "is he sleeping more this week than last week?" — the baseline
    /// period the metric is measured against. Only meaningful for
    /// aggregating metrics.
    var compareTo: AskPeriod?

    init(metric: AskMetric, period: AskPeriod, compareTo: AskPeriod? = nil) {
        self.metric = metric
        self.period = period
        self.compareTo = compareTo
    }
}

/// What is being asked about.
enum AskMetric: Equatable {
    // Lookups (single event / current state)
    case lastFeed
    case lastDiaper(DiaperType?)      // nil = any type
    case sleepStatus                  // asleep now? since when? / last woke
    case bedtime                      // when did he go down for the night

    // Aggregates (over a period)
    case totalSleep
    case nightWakes
    case feedOz
    case feedCount
    case diaperCount(DiaperType?)
    case averageBottle
    case longestStretch
    case averageFeedInterval

    // Predictions
    case nextFeed
    case nextNap
    case wakeUp

    // Free text against NoteEvents ("when did we start vitamin D drops?")
    case noteSearch(String)

    /// Whether the metric aggregates over a period (and therefore supports
    /// a `compareTo` baseline). Lookups and predictions don't.
    var isAggregate: Bool {
        switch self {
        case .totalSleep, .nightWakes, .feedOz, .feedCount, .diaperCount,
             .averageBottle, .longestStretch, .averageFeedInterval:
            return true
        default:
            return false
        }
    }
}

/// When — resolved to concrete dates by `AskEngine` using its injected
/// calendar, clock, and the family's configured night window.
enum AskPeriod: Equatable {
    case today
    case yesterday
    /// The most recent night window (SharedSettings.nightStartMinute →
    /// nightEndMinute). At 3am this is the night in progress.
    case lastNight
    /// Rolling 7 days ending now (matches StatsEngine's rolling windows).
    case thisWeek
    /// The 7 days before `thisWeek`.
    case lastWeek
    case allTime
}

/// A computed answer: the sentence Siri speaks (or a snippet shows), plus the
/// individual facts it was built from — so a surface can render receipts and
/// a wrong answer is diagnosable. Facts always come from the engine's own
/// arithmetic, never parsed back out of prose.
struct AskAnswer: Equatable {
    var sentence: String
    var facts: [Fact]

    struct Fact: Equatable {
        var label: String
        var value: String
    }

    init(_ sentence: String, facts: [Fact] = []) {
        self.sentence = sentence
        self.facts = facts
    }
}
