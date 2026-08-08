import WidgetKit
import SwiftUI

/// Last Diaper — time since the last change. There's no credible SF Symbol
/// for a diaper, so the surfaces carry the app's diaper emoji (💧/💩 by type)
/// where emoji renders well and fall back to the amber-tinted timer elsewhere.
struct DiaperEntry: TimelineEntry {
    let date: Date
    let lastChangeDate: Date?
    let lastType: DiaperType?
    /// Fixed 3h target (`UrgencyDefaults.diaper`) — diapers have no
    /// night-aware schedule, just a "it's been a while" tint.
    let targetInterval: TimeInterval = UrgencyDefaults.diaper

    init(date: Date, snapshot: ComplicationSnapshot) {
        self.date = date
        self.lastChangeDate = snapshot.lastDiaperDate
        self.lastType = snapshot.lastDiaperType
    }
}

struct DiaperProvider: TimelineProvider {
    func placeholder(in context: Context) -> DiaperEntry {
        DiaperEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (DiaperEntry) -> Void) {
        let snapshot: ComplicationSnapshot = context.isPreview ? .placeholder : ComplicationStore.snapshot()
        completion(DiaperEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DiaperEntry>) -> Void) {
        let snapshot = ComplicationStore.snapshot()
        var entries = [DiaperEntry(date: snapshot.date, snapshot: snapshot)]
        if let last = snapshot.lastDiaperDate {
            entries += ComplicationTimeline
                .urgencyFlips(last: last, target: UrgencyDefaults.diaper, now: snapshot.date)
                .map { DiaperEntry(date: $0, snapshot: snapshot) }
        }
        completion(Timeline(entries: entries,
                            policy: .after(ComplicationTimeline.policy(after: entries, base: snapshot.date))))
    }
}

struct DiaperComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchLastDiaper", provider: DiaperProvider()) { entry in
            DiaperComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Last Diaper")
        .description("Time since the last change, and what kind it was.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

struct DiaperComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DiaperEntry

    private var tint: Color {
        let urgency = Urgency.from(since: entry.lastChangeDate, now: entry.date,
                                   target: entry.targetInterval)
        return urgency.needsAttention ? urgency.color : AppColor.accentDiaper
    }

    /// The last change's own emoji (💧/💩/both); generic 💧 before any data.
    private var emoji: String { entry.lastType?.emoji ?? "💧" }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text(emoji)
                        .font(.system(size: 11))
                    if let last = entry.lastChangeDate {
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
            Text(emoji)
                .font(.title3)
                .widgetAccentable()
                .widgetLabel {
                    if let last = entry.lastChangeDate {
                        Text(last, style: .relative)
                    } else {
                        Text("No changes")
                    }
                }

        case .accessoryRectangular:
            HStack(spacing: 4) {
                Text(emoji)
                    .font(.subheadline)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Last change")
                        .sectionLabelStyle(color: tint)
                        .widgetAccentable()
                    if let last = entry.lastChangeDate {
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
                        Text("No changes yet")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        default: // .accessoryInline
            if let last = entry.lastChangeDate {
                Text("\(emoji) ") + Text(last, style: .relative)
            } else {
                Text("💧 No changes yet")
            }
        }
    }

    /// "Wet · 2:14 PM" — the kind, and when it happened.
    private func caption(last: Date) -> String {
        let clock = TimeFormatting.clock(last)
        guard let type = entry.lastType else { return clock }
        return "\(type.label) · \(clock)"
    }
}

#Preview("Rectangular", as: .accessoryRectangular) {
    DiaperComplication()
} timeline: {
    DiaperEntry(date: .now, snapshot: .placeholder)
    DiaperEntry(date: .now, snapshot: .empty)
}

#Preview("Circular", as: .accessoryCircular) {
    DiaperComplication()
} timeline: {
    DiaperEntry(date: .now, snapshot: .placeholder)
    DiaperEntry(date: .now, snapshot: .empty)
}
