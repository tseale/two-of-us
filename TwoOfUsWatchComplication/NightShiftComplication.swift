import WidgetKit
import SwiftUI

/// Night Shift — who's up next and when, while tonight's schedule is live.
/// Outside the night window it falls back to plain next-feed content, so the
/// slot is never dead face real estate during the day.
struct NightShiftEntry: TimelineEntry {
    let date: Date
    let nightActive: Bool
    let nextFeed: ComplicationSnapshot.NextFeed?

    init(date: Date, snapshot: ComplicationSnapshot) {
        self.date = date
        self.nightActive = snapshot.nightActive
        self.nextFeed = snapshot.nextFeed
    }

    /// Night mode needs a live night AND a schedule slot to name — a plain
    /// projection during the window still renders as next-feed.
    var showsNightShift: Bool {
        nightActive && nextFeed?.isNightSlot == true
    }
}

struct NightShiftProvider: TimelineProvider {
    func placeholder(in context: Context) -> NightShiftEntry {
        NightShiftEntry(date: .now, snapshot: .nightPlaceholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (NightShiftEntry) -> Void) {
        let snapshot: ComplicationSnapshot = context.isPreview ? .nightPlaceholder : ComplicationStore.snapshot()
        completion(NightShiftEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NightShiftEntry>) -> Void) {
        let snapshot = ComplicationStore.snapshot()
        let entry = NightShiftEntry(date: snapshot.date, snapshot: snapshot)
        // Reload just past the shown slot so the face rolls to the next one
        // (and to whoever takes it); otherwise the fallback cadence is fine —
        // day/night transitions ride the sync/log reloads plus this timer.
        var reloadAt = snapshot.date.addingTimeInterval(ComplicationTimeline.fallbackReload)
        if let next = snapshot.nextFeed?.date, next > snapshot.date {
            reloadAt = min(reloadAt, next.addingTimeInterval(60))
        }
        completion(Timeline(entries: [entry], policy: .after(reloadAt)))
    }
}

struct NightShiftComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchNightShift", provider: NightShiftProvider()) { entry in
            NightShiftComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Night Shift")
        .description("Who's up next tonight, and when. Next feed during the day.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}

struct NightShiftComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NightShiftEntry

    var body: some View {
        if entry.showsNightShift, let next = entry.nextFeed {
            night(next: next)
        } else {
            day
        }
    }

    // MARK: Night — the shift roster line

    @ViewBuilder
    private func night(next: ComplicationSnapshot.NextFeed) -> some View {
        switch family {
        case .accessoryRectangular:
            HStack(spacing: 4) {
                Text("🌙")
                    .font(.subheadline)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Up next")
                        .sectionLabelStyle(color: AppColor.accentSleep)
                        .widgetAccentable()
                    // Unassigned slot = both phones ring — say so, don't blank.
                    Text("\(next.ownerName ?? "Both") · \(TimeFormatting.clock(next.date))")
                        .font(.system(.headline, design: .rounded).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    (Text("in ") + Text(next.date, style: .relative))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        default: // .accessoryInline
            Text("🌙 \(next.ownerName ?? "Both") · \(TimeFormatting.clock(next.date))")
        }
    }

    // MARK: Day — plain next-feed fallback

    @ViewBuilder
    private var day: some View {
        switch family {
        case .accessoryRectangular:
            HStack(spacing: 4) {
                Text("🍼")
                    .font(.subheadline)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Next bottle")
                        .sectionLabelStyle(color: AppColor.accentFeed)
                        .widgetAccentable()
                    if let next = entry.nextFeed {
                        Text("~\(TimeFormatting.clock(next.date))")
                            .font(.system(.headline, design: .rounded).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        (Text("in ") + Text(next.date, style: .relative))
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
            if let next = entry.nextFeed {
                Text("🍼 ~\(TimeFormatting.clock(next.date))")
            } else {
                Text("🍼 No feeds yet")
            }
        }
    }
}

#Preview("Rectangular", as: .accessoryRectangular) {
    NightShiftComplication()
} timeline: {
    NightShiftEntry(date: .now, snapshot: .nightPlaceholder)
    NightShiftEntry(date: .now, snapshot: .placeholder)
    NightShiftEntry(date: .now, snapshot: .empty)
}
