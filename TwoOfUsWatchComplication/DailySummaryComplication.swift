import WidgetKit
import SwiftUI

/// Daily Summary — today's tallies at a glance: bottles, sleep, diapers.
/// Rectangular for the wide face slots, inline for the top line.
struct SummaryEntry: TimelineEntry {
    let date: Date
    let feedCount: Int
    let feedOz: Double
    let sleepMinutes: Int
    let diaperCount: Int

    init(date: Date, snapshot: ComplicationSnapshot) {
        self.date = date
        self.feedCount = snapshot.todayFeedCount
        self.feedOz = snapshot.todayFeedOz
        self.sleepMinutes = snapshot.todaySleepMinutes
        self.diaperCount = snapshot.todayDiaperCount
    }

    init(date: Date, feedCount: Int, feedOz: Double, sleepMinutes: Int, diaperCount: Int) {
        self.date = date
        self.feedCount = feedCount
        self.feedOz = feedOz
        self.sleepMinutes = sleepMinutes
        self.diaperCount = diaperCount
    }

    var hasData: Bool { feedCount > 0 || sleepMinutes > 0 || diaperCount > 0 }
}

struct SummaryProvider: TimelineProvider {
    func placeholder(in context: Context) -> SummaryEntry {
        SummaryEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SummaryEntry) -> Void) {
        let snapshot: ComplicationSnapshot = context.isPreview ? .placeholder : ComplicationStore.snapshot()
        completion(SummaryEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SummaryEntry>) -> Void) {
        let snapshot = ComplicationStore.snapshot()
        var entries = [SummaryEntry(date: snapshot.date, snapshot: snapshot)]
        // At midnight the tallies genuinely are zero (even a still-running
        // sleep has banked no minutes of the new day at 00:00 sharp), so a
        // pre-staged zero entry keeps the face honest until the next reload
        // even if the budget starves one overnight.
        if let midnight = Calendar.current.date(byAdding: .day, value: 1,
                                                to: Calendar.current.startOfDay(for: snapshot.date)) {
            entries.append(SummaryEntry(date: midnight, feedCount: 0, feedOz: 0,
                                        sleepMinutes: 0, diaperCount: 0))
        }
        completion(Timeline(entries: entries,
                            policy: .after(snapshot.date.addingTimeInterval(ComplicationTimeline.fallbackReload))))
    }
}

struct DailySummaryComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchDailySummary", provider: SummaryProvider()) { entry in
            DailySummaryComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Today's feeds, sleep, and diapers in one line.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}

struct DailySummaryComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SummaryEntry

    private var sleepText: String {
        TimeFormatting.duration(minutes: entry.sleepMinutes)
    }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("Today")
                    .sectionLabelStyle(color: AppColor.accentFeed)
                    .widgetAccentable()
                if entry.hasData {
                    // Each tally in its kind's accent — the same three-color
                    // identity as the phone's log tiles.
                    HStack(spacing: 5) {
                        metric("🍼", "\(entry.feedCount)", AppColor.accentFeed)
                        metric("😴", sleepText, AppColor.accentSleep)
                        metric("💩", "\(entry.diaperCount)", AppColor.accentDiaper)
                    }
                    Text("\(OzFormat.string(entry.feedOz)) oz total")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else {
                    Text("Nothing logged yet")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        default: // .accessoryInline — one line, tightest form of the same row
            if entry.hasData {
                Text("🍼\(entry.feedCount) 😴\(sleepText) 💩\(entry.diaperCount)")
            } else {
                Text("🍼 Nothing logged yet")
            }
        }
    }

    private func metric(_ emoji: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 2) {
            Text(emoji)
                .font(.caption2)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
                .widgetAccentable()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

#Preview("Rectangular", as: .accessoryRectangular) {
    DailySummaryComplication()
} timeline: {
    SummaryEntry(date: .now, snapshot: .placeholder)
    SummaryEntry(date: .now, snapshot: .empty)
}
