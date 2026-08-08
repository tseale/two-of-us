import WidgetKit
import SwiftUI

/// Last Feed — time since the last bottle, on every accessory family. Unlike
/// the Glance complication this one never yields the surface to a running
/// sleep: it's for the parent who wants the bottle clock pinned, always.
struct FeedEntry: TimelineEntry {
    let date: Date
    let lastFeedDate: Date?
    let lastAmountOz: Double?
    let targetInterval: TimeInterval

    var nextFeedDate: Date? {
        lastFeedDate.map { $0.addingTimeInterval(targetInterval) }
    }

    init(date: Date, snapshot: ComplicationSnapshot) {
        self.date = date
        self.lastFeedDate = snapshot.lastFeedDate
        self.lastAmountOz = snapshot.lastFeedOz
        self.targetInterval = snapshot.feedTargetInterval
    }
}

struct FeedProvider: TimelineProvider {
    func placeholder(in context: Context) -> FeedEntry {
        FeedEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (FeedEntry) -> Void) {
        let snapshot: ComplicationSnapshot = context.isPreview ? .placeholder : ComplicationStore.snapshot()
        completion(FeedEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FeedEntry>) -> Void) {
        let snapshot = ComplicationStore.snapshot()
        // Stage entries at the urgency thresholds so the tint flips at the
        // exact moment with no waking code; the relative text ticks itself.
        var entries = [FeedEntry(date: snapshot.date, snapshot: snapshot)]
        if let last = snapshot.lastFeedDate {
            entries += ComplicationTimeline
                .urgencyFlips(last: last, target: snapshot.feedTargetInterval, now: snapshot.date)
                .map { FeedEntry(date: $0, snapshot: snapshot) }
        }
        completion(Timeline(entries: entries,
                            policy: .after(ComplicationTimeline.policy(after: entries, base: snapshot.date))))
    }
}

struct FeedComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchLastFeed", provider: FeedProvider()) { entry in
            FeedComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Last Feed")
        .description("Time since the last bottle, and how much he took.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

struct FeedComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FeedEntry

    /// Feed teal at rest, urgency amber/red as the next bottle nears/passes —
    /// the same "quiet until it matters" flip as every phone surface.
    private var tint: Color {
        let urgency = Urgency.from(since: entry.lastFeedDate, now: entry.date,
                                   target: entry.targetInterval)
        return urgency.needsAttention ? urgency.color : AppColor.accentFeed
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(tint)
                        .widgetAccentable()
                    if let last = entry.lastFeedDate {
                        Text(last, style: .relative)
                            .font(.system(.caption2, design: .rounded).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .padding(.horizontal, 2)
                    } else {
                        Text("--")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }

        case .accessoryCorner:
            Image(systemName: "drop.fill")
                .font(.title3)
                .foregroundStyle(tint)
                .widgetAccentable()
                .widgetLabel {
                    if let last = entry.lastFeedDate {
                        Text(last, style: .relative)
                    } else {
                        Text("No feeds")
                    }
                }

        case .accessoryRectangular:
            HStack(spacing: 4) {
                Text("🍼")
                    .font(.subheadline)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Last feed")
                        .sectionLabelStyle(color: tint)
                        .widgetAccentable()
                    if let last = entry.lastFeedDate {
                        Text(last, style: .relative)
                            .font(.system(.headline, design: .rounded).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(caption(last: last))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    } else {
                        Text("No feeds yet")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        default: // .accessoryInline
            if let last = entry.lastFeedDate {
                Text("🍼 ") + Text(last, style: .relative)
            } else {
                Text("🍼 No feeds yet")
            }
        }
    }

    /// "3 oz · next ~2:30 PM" — amount when known, always the projection.
    private func caption(last: Date) -> String {
        let next = "next ~\(TimeFormatting.clock(entry.nextFeedDate ?? entry.date))"
        guard let oz = entry.lastAmountOz else { return next }
        return "\(OzFormat.string(oz)) oz · \(next)"
    }
}

#Preview("Rectangular", as: .accessoryRectangular) {
    FeedComplication()
} timeline: {
    FeedEntry(date: .now, snapshot: .placeholder)
    FeedEntry(date: .now, snapshot: .empty)
}

#Preview("Circular", as: .accessoryCircular) {
    FeedComplication()
} timeline: {
    FeedEntry(date: .now, snapshot: .placeholder)
    FeedEntry(date: .now, snapshot: .empty)
}
