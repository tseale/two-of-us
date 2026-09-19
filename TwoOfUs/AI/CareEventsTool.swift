import Foundation
import FoundationModels

/// The one tool the "Ask" session gets: read the log. The model decides the
/// kind and how far back to look, the tool returns the matching events as
/// plain lines, and the model answers from those — it never sees the store
/// and never writes. Kept small on purpose: a 3B on-device model with one
/// well-described tool is far more reliable than the same model juggling
/// five, and every question a parent asks at 3am is "what happened, when".
struct CareEventsTool: Tool {
    let name = "lookUpCareEvents"
    let description = """
        Looks up the baby's logged feeds (bottles, in ounces), sleeps (with \
        durations), diaper changes (wet or dirty), and notes for the last N \
        days, newest first. Call this before answering any question about \
        what happened, when, how much, or how often.
        """

    @Generable
    struct Arguments {
        @Guide(description: "Which events to fetch: feed, sleep, diaper, note, or all.")
        var kind: String
        @Guide(description: "How many days back to look. Use 1 for today, 2 for yesterday and today, 7 for the week.", .range(1...30))
        var days: Int
    }

    /// Events per call — enough for a busy week of one kind, small enough to
    /// leave the 8K on-device context room for the answer.
    static let maximumEvents = 80

    func call(arguments: Arguments) async throws -> String {
        let days = min(max(arguments.days, 1), CareEventCatalog.indexedWindowDays)
        let kind = CareEventKind(rawValue: arguments.kind.lowercased())
        let events = await MainActor.run {
            CareEventCatalog.recent(limit: 1000, days: days)
        }
        return Self.render(events, kind: kind, days: days)
    }

    /// Pure formatting, so the shape the model reads is unit-tested.
    static func render(_ events: [CareEventEntity], kind: CareEventKind?, days: Int, now: Date = .now) -> String {
        let matching = events
            .filter { kind == nil || $0.kind == kind }
            .sorted { $0.time > $1.time }
        guard !matching.isEmpty else {
            let what = kind.map { "\($0.rawValue) events" } ?? "events"
            return "No \(what) logged in the last \(days) day\(days == 1 ? "" : "s")."
        }
        let shown = matching.prefix(maximumEvents)
        var lines = ["\(matching.count) event\(matching.count == 1 ? "" : "s") in the last \(days) day\(days == 1 ? "" : "s"), newest first:"]
        for event in shown {
            lines.append("- \(Self.line(for: event, now: now))")
        }
        if matching.count > shown.count {
            lines.append("(\(matching.count - shown.count) older events omitted)")
        }
        return lines.joined(separator: "\n")
    }

    private static func line(for event: CareEventEntity, now: Date) -> String {
        let when = "\(dayFormatter.string(from: event.time)) \(TimeFormatting.clock(event.time))"
        let who = event.loggedBy.isEmpty ? "" : " (by \(event.loggedBy))"
        switch event.kind {
        case .feed:
            return "\(when): feed, \(OzFormat.string(event.amountOz ?? 0)) oz\(who)"
        case .sleep:
            let length = event.durationMinutes.map { "slept \(TimeFormatting.duration(minutes: $0))" } ?? "still asleep"
            return "\(when): sleep started, \(length)"
        case .diaper:
            return "\(when): \(event.diaperType?.lowercased() ?? "wet") diaper\(who)"
        case .note:
            return "\(when): note — \(event.note ?? "")\(who)"
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return f
    }()
}
