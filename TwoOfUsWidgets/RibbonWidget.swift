import SwiftUI
import WidgetKit

// MARK: - Day ribbon widget (lock-screen rectangular + home-screen small)

/// "When did things happen today" — a 24h ribbon. Tinted/shape-coded on the lock
/// screen (● feed · ○ diaper · — sleep); full color as a small home-screen tile.
struct DayRibbonWidgetView: View {
    let entry: WidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .accessoryRectangular {
            lockBody
        } else {
            homeBody
        }
    }

    private var lockBody: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("Today").font(.caption2)
                Spacer()
                Text(tally).font(.caption2)
            }
            .foregroundStyle(.secondary)
            DayRibbonView(marks: entry.todayMarks, style: .tinted)
                .frame(maxHeight: .infinity)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var homeBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TODAY").sectionLabelStyle()
                Spacer()
                Text(tally).font(.caption2).foregroundStyle(AppColor.text3)
            }
            DayRibbonView(marks: entry.todayMarks, style: .color)
                .frame(maxHeight: .infinity)
        }
        .padding(12)
        .containerBackground(AppColor.card, for: .widget)
    }

    private var tally: String {
        var feeds = 0, diapers = 0
        var sleepSeconds: TimeInterval = 0
        for mark in entry.todayMarks {
            switch mark.kind {
            case .feed: feeds += 1
            case .diaper: diapers += 1
            case .sleep:
                if let end = mark.end { sleepSeconds += end.timeIntervalSince(mark.start) }
            }
        }
        let minutes = Int(sleepSeconds / 60)
        let sleep = minutes >= 60 ? "\(minutes / 60)h\(minutes % 60 == 0 ? "" : "\(minutes % 60)")" : "\(minutes)m"
        return "🍼 \(feeds) · 💤 \(sleep) · 💩 \(diapers)"
    }
}

struct DayRibbonWidget: Widget {
    let kind = "DayRibbonWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetProvider()) { entry in
            DayRibbonWidgetView(entry: entry)
        }
        .configurationDisplayName("Today Ribbon")
        .description("When your baby fed, slept, and changed across the day.")
        .supportedFamilies([.accessoryRectangular, .systemSmall])
        .contentMarginsDisabled()
    }
}

// MARK: - Next-feed gauge (lock-screen circular)

/// A ring filling toward the next feed's target interval, with remaining time in the center.
/// Uses `ProgressView(timerInterval:)` so the ring and the countdown advance on their own,
/// with no timeline reloads, falling back to a static gauge before the first feed.
struct NextFeedGaugeView: View {
    let entry: WidgetEntry

    private var due: Date? {
        guard entry.feedTargetInterval > 0, let last = entry.lastFeedDate else { return nil }
        return last.addingTimeInterval(entry.feedTargetInterval)
    }

    var body: some View {
        Group {
            if let last = entry.lastFeedDate, let due {
                ProgressView(timerInterval: last...due, countsDown: false) {
                    Image(systemName: "drop.fill")
                } currentValueLabel: {
                    Text(due, style: .relative)
                        .font(.caption2)
                        .minimumScaleFactor(0.5)
                }
                .progressViewStyle(.circular)
                .tint(AppColor.accentFeed)
            } else {
                Gauge(value: 0) {
                    Image(systemName: "drop.fill")
                } currentValueLabel: {
                    Text("—")
                }
                .gaugeStyle(.accessoryCircularCapacity)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct NextFeedGaugeWidget: Widget {
    let kind = "NextFeedGaugeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetProvider()) { entry in
            NextFeedGaugeView(entry: entry)
        }
        .configurationDisplayName("Next Feed")
        .description("How close your baby is to the next bottle.")
        .supportedFamilies([.accessoryCircular])
        .contentMarginsDisabled()
    }
}
