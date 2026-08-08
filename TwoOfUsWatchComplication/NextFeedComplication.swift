import WidgetKit
import SwiftUI

/// Next Feed — when the next bottle is expected, resolved by the same rule as
/// the phone's Live Activity: tonight's schedule slot when the night is live
/// (it knows whose turn it is), else last feed + the night-aware interval.
struct NextFeedEntry: TimelineEntry {
    let date: Date
    let nextFeed: ComplicationSnapshot.NextFeed?
    let lastFeedDate: Date?
    let targetInterval: TimeInterval

    init(date: Date, snapshot: ComplicationSnapshot) {
        self.date = date
        self.nextFeed = snapshot.nextFeed
        self.lastFeedDate = snapshot.lastFeedDate
        self.targetInterval = snapshot.feedTargetInterval
    }
}

struct NextFeedProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextFeedEntry {
        NextFeedEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (NextFeedEntry) -> Void) {
        let snapshot: ComplicationSnapshot = context.isPreview ? .placeholder : ComplicationStore.snapshot()
        completion(NextFeedEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextFeedEntry>) -> Void) {
        let snapshot = ComplicationStore.snapshot()
        var entries = [NextFeedEntry(date: snapshot.date, snapshot: snapshot)]
        if let last = snapshot.lastFeedDate {
            entries += ComplicationTimeline
                .urgencyFlips(last: last, target: snapshot.feedTargetInterval, now: snapshot.date)
                .map { NextFeedEntry(date: $0, snapshot: snapshot) }
        }
        // Once the predicted time passes, the shown slot is stale — pull the
        // fallback reload up to just past it so the surface rolls forward to
        // the NEXT prediction instead of waiting out the half hour.
        var reloadAt = ComplicationTimeline.policy(after: entries, base: snapshot.date)
        if let next = snapshot.nextFeed?.date, next > snapshot.date {
            reloadAt = min(reloadAt, next.addingTimeInterval(60))
        }
        completion(Timeline(entries: entries, policy: .after(reloadAt)))
    }
}

struct NextFeedComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchNextFeed", provider: NextFeedProvider()) { entry in
            NextFeedComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Next Feed")
        .description("When the next bottle is expected — and whose turn it is at night.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

struct NextFeedComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextFeedEntry

    /// Same urgency signal as the Last Feed face: the prediction IS last feed
    /// + target, so nearing/passing it warms this surface identically.
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
                    if let next = entry.nextFeed {
                        Text(clockShort(next.date))
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
                    if let next = entry.nextFeed {
                        Text("~\(TimeFormatting.clock(next.date))")
                    } else {
                        Text("No feeds")
                    }
                }

        case .accessoryRectangular:
            HStack(spacing: 4) {
                Text("🍼")
                    .font(.subheadline)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Next bottle")
                        .sectionLabelStyle(color: tint)
                        .widgetAccentable()
                    if let next = entry.nextFeed {
                        Text("~\(TimeFormatting.clock(next.date))")
                            .font(.system(.headline, design: .rounded).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if let owner = next.ownerName {
                            Text("\(owner)'s turn")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        } else {
                            // Ticks down on its own; reads "in 1 hr, 20 min".
                            (Text("in ") + Text(next.date, style: .relative))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    } else {
                        Text("No feeds yet")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        default: // .accessoryInline
            if let next = entry.nextFeed {
                if let owner = next.ownerName {
                    Text("🍼 ~\(TimeFormatting.clock(next.date)) · \(owner)")
                } else {
                    Text("🍼 ~\(TimeFormatting.clock(next.date))")
                }
            } else {
                Text("🍼 No feeds yet")
            }
        }
    }

    /// "2:30" — the small circle can't fit an AM/PM suffix at readable size.
    private func clockShort(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour12 = ((c.hour ?? 0) + 11) % 12 + 1
        return String(format: "%d:%02d", hour12, c.minute ?? 0)
    }
}

#Preview("Rectangular", as: .accessoryRectangular) {
    NextFeedComplication()
} timeline: {
    NextFeedEntry(date: .now, snapshot: .nightPlaceholder)
    NextFeedEntry(date: .now, snapshot: .placeholder)
    NextFeedEntry(date: .now, snapshot: .empty)
}

#Preview("Circular", as: .accessoryCircular) {
    NextFeedComplication()
} timeline: {
    NextFeedEntry(date: .now, snapshot: .nightPlaceholder)
    NextFeedEntry(date: .now, snapshot: .placeholder)
    NextFeedEntry(date: .now, snapshot: .empty)
}
