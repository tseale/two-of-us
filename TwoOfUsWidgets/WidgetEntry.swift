import WidgetKit
import Foundation

/// Data snapshot the widget renders. Produced by WidgetProvider from a SwiftData
/// fetch; safe to pass across the widget/app boundary (no SwiftData objects).
struct WidgetEntry: TimelineEntry {
    let date: Date

    /// The baby's name as entered during onboarding, for widget headers.
    let babyName: String

    let lastFeedDate: Date?
    let lastSleepDate: Date?
    let lastDiaperDate: Date?

    let feedTargetInterval: TimeInterval   // from SharedSettings
    let isActiveSleep: Bool
    let activeSleepStartedAt: Date?

    /// Flat list of recent events for the large widget (newest first, max 5).
    let recentItems: [WidgetItem]

    /// Today's events as ribbon marks, for the "today so far" / lock-screen ribbon.
    let todayMarks: [RibbonMark]

    /// Smart Stack relevance — higher as the next feed becomes due/overdue, so the
    /// widget surfaces in the rotation at feeding time. Defaulted so existing
    /// constructors don't need to pass it.
    var relevance: TimelineEntryRelevance? = nil

    /// A copy of this snapshot re-dated to a future threshold, with its own
    /// relevance score. Used to stage urgency transitions in the timeline so the
    /// dot/accent color flips at the exact moment with no extra reloads.
    func redated(to date: Date, relevance: TimelineEntryRelevance?) -> WidgetEntry {
        WidgetEntry(
            date: date,
            babyName: babyName,
            lastFeedDate: lastFeedDate,
            lastSleepDate: lastSleepDate,
            lastDiaperDate: lastDiaperDate,
            feedTargetInterval: feedTargetInterval,
            isActiveSleep: isActiveSleep,
            activeSleepStartedAt: activeSleepStartedAt,
            recentItems: recentItems,
            todayMarks: todayMarks,
            relevance: relevance
        )
    }

    static let placeholder = WidgetEntry(
        date: .now,
        babyName: "Baby",
        lastFeedDate: Date(timeIntervalSinceNow: -7800),   // 2h 10m ago
        lastSleepDate: Date(timeIntervalSinceNow: -2700),  // 45m ago
        lastDiaperDate: Date(timeIntervalSinceNow: -4200), // 1h 10m ago
        feedTargetInterval: 10800,
        isActiveSleep: false,
        activeSleepStartedAt: nil,
        recentItems: [
            WidgetItem(kind: .feed, date: Date(timeIntervalSinceNow: -7800), detail: "3 oz"),
            WidgetItem(kind: .sleep, date: Date(timeIntervalSinceNow: -9000), detail: "1h 22m"),
            WidgetItem(kind: .diaper, date: Date(timeIntervalSinceNow: -4200), detail: "Wet"),
        ],
        todayMarks: WidgetEntry.sampleMarks
    )

    static let empty = WidgetEntry(
        date: .now,
        babyName: "Baby",
        lastFeedDate: nil,
        lastSleepDate: nil,
        lastDiaperDate: nil,
        feedTargetInterval: 10800,
        isActiveSleep: false,
        activeSleepStartedAt: nil,
        recentItems: [],
        todayMarks: []
    )

    /// Illustrative marks spread across today, for previews/placeholders.
    private static var sampleMarks: [RibbonMark] {
        let start = Calendar.current.startOfDay(for: .now)
        func at(_ h: Double) -> Date { start.addingTimeInterval(h * 3600) }
        return [
            RibbonMark(kind: .sleep, start: at(1), end: at(4)),
            RibbonMark(kind: .feed, start: at(2)),
            RibbonMark(kind: .diaper, start: at(3), diaperType: .wet),
            RibbonMark(kind: .feed, start: at(6)),
            RibbonMark(kind: .sleep, start: at(8), end: at(9.5)),
            RibbonMark(kind: .feed, start: at(10)),
            RibbonMark(kind: .diaper, start: at(11), diaperType: .dirty),
        ]
    }
}

struct WidgetItem: Hashable {
    let kind: EventKind
    let date: Date
    let detail: String
}
