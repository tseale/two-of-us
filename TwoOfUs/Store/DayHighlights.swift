import Foundation

/// The day's highlights, for the evening book page on iPhone Duo's open
/// display: a short list that grows through the day and keeps only what is
/// worth remembering — a milestone, a record stretch of sleep, a note, the
/// day's photos, what he did at daycare — and leaves out the routine.
///
/// Every candidate carries a weight. The list keeps the heaviest `limit`
/// and shows them in the order they happened, so a quiet morning still
/// shows its one good moment and a full day keeps its best. Pure and
/// store-free: plain values in, plain items out (`DayHighlightsTests`).
enum DayHighlights {
    struct Item: Equatable, Identifiable {
        let id: String
        let time: Date
        let emoji: String
        let text: String
        /// A quiet second line (who wrote a note, when a sleep ran).
        let detail: String?
        let weight: Int
    }

    struct Feed {
        let time: Date
        let oz: Double
    }

    struct Sleep {
        let start: Date
        let end: Date
    }

    /// Anything already worded: a milestone, a note, an activity, a mood, a
    /// drop-off.
    struct Moment {
        let time: Date
        let emoji: String
        let text: String
        var detail: String? = nil
    }

    /// The weights, heaviest first.
    enum Weight {
        static let milestone = 100
        static let recordSleep = 90
        static let note = 70
        static let photos = 60
        static let activity = 50
        static let longSleep = 40
        static let mood = 35
        static let bottle = 30
        static let check = 20
    }

    /// A sleep at least this long is worth a line even when it is no record.
    static let longSleep: TimeInterval = 2 * 3600

    static func build(name: String,
                      feeds: [Feed] = [],
                      sleeps: [Sleep] = [],
                      earlierBestStretch: TimeInterval = 0,
                      milestones: [Moment] = [],
                      notes: [Moment] = [],
                      activities: [Moment] = [],
                      moods: [Moment] = [],
                      checks: [Moment] = [],
                      photoTimes: [Date] = [],
                      limit: Int = 8) -> [Item] {
        var items: [Item] = []

        for m in milestones {
            items.append(Item(id: "milestone-\(m.time.timeIntervalSince1970)", time: m.time,
                              emoji: "🏆", text: m.text, detail: m.detail, weight: Weight.milestone))
        }

        // The day's longest sleep: a record against the rest of the month, or
        // just a good stretch.
        if let best = sleeps.max(by: { $0.end.timeIntervalSince($0.start) < $1.end.timeIntervalSince($1.start) }) {
            let length = best.end.timeIntervalSince(best.start)
            if earlierBestStretch > 0, length > earlierBestStretch {
                items.append(Item(id: "sleep-record", time: best.start, emoji: "🎉",
                                  text: "\(name)'s longest stretch yet: \(duration(length))",
                                  detail: "beat \(duration(earlierBestStretch)) from earlier this month",
                                  weight: Weight.recordSleep))
            } else if length >= longSleep {
                items.append(Item(id: "sleep-long", time: best.start, emoji: "💤",
                                  text: "Slept \(duration(length)) straight", detail: nil,
                                  weight: Weight.longSleep))
            }
        }

        for n in notes {
            items.append(Item(id: "note-\(n.time.timeIntervalSince1970)", time: n.time,
                              emoji: n.emoji, text: n.text, detail: n.detail, weight: Weight.note))
        }

        if let first = photoTimes.min() {
            let count = photoTimes.count
            items.append(Item(id: "photos", time: first, emoji: "📸",
                              text: count == 1 ? "A photo from daycare" : "\(count) photos from daycare",
                              detail: nil, weight: Weight.photos))
        }

        for a in activities {
            items.append(Item(id: "activity-\(a.time.timeIntervalSince1970)", time: a.time,
                              emoji: a.emoji, text: a.text, detail: a.detail, weight: Weight.activity))
        }
        for m in moods {
            items.append(Item(id: "mood-\(m.time.timeIntervalSince1970)", time: m.time,
                              emoji: m.emoji, text: m.text, detail: m.detail, weight: Weight.mood))
        }

        // The biggest bottle — only once there are at least two to compare,
        // and only when one stands out.
        let sortedFeeds = feeds.sorted { $0.oz > $1.oz }
        if sortedFeeds.count >= 2, sortedFeeds[0].oz > sortedFeeds[1].oz {
            let top = sortedFeeds[0]
            items.append(Item(id: "bottle", time: top.time, emoji: "🍼",
                              text: "Biggest bottle: \(oz(top.oz)) oz", detail: nil, weight: Weight.bottle))
        }

        for c in checks {
            items.append(Item(id: "check-\(c.time.timeIntervalSince1970)", time: c.time,
                              emoji: c.emoji, text: c.text, detail: c.detail, weight: Weight.check))
        }

        // Keep the heaviest, then tell them in order.
        let kept = items.enumerated()
            .sorted { ($0.element.weight, -$0.offset) > ($1.element.weight, -$1.offset) }
            .prefix(max(limit, 0))
            .map(\.element)
        return kept.sorted { $0.time < $1.time }
    }

    /// "3h 50m", "45m", "2h".
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int((seconds / 60).rounded())
        let h = total / 60, m = total % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// "4", "4.5", "3.75".
    static func oz(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        return text
    }
}
