import WidgetKit
import Foundation

/// Data snapshot the widget renders. Produced by WidgetProvider from a SwiftData
/// fetch; safe to pass across the widget/app boundary (no SwiftData objects).
struct WidgetEntry: TimelineEntry {
    let date: Date

    let lastFeedDate: Date?
    let lastSleepDate: Date?
    let lastDiaperDate: Date?

    let feedTargetInterval: TimeInterval   // from SharedSettings
    let isActiveSleep: Bool
    let activeSleepStartedAt: Date?

    /// Flat list of recent events for the large widget (newest first, max 5).
    let recentItems: [WidgetItem]

    static let placeholder = WidgetEntry(
        date: .now,
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
        ]
    )

    static let empty = WidgetEntry(
        date: .now,
        lastFeedDate: nil,
        lastSleepDate: nil,
        lastDiaperDate: nil,
        feedTargetInterval: 10800,
        isActiveSleep: false,
        activeSleepStartedAt: nil,
        recentItems: []
    )
}

struct WidgetItem {
    let kind: EventKind
    let date: Date
    let detail: String
}
