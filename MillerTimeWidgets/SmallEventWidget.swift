import SwiftUI
import WidgetKit

/// Small "time since last X" widget for a single event kind — rendered as a
/// lock screen accessory (`.accessoryRectangular`) or a small home screen tile
/// (`.systemSmall`). One instance per kind is registered below.
struct SmallEventWidgetView: View {
    let kind: EventKind
    let entry: WidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .accessoryRectangular {
            lockScreenBody
        } else {
            homeSmallBody
        }
    }

    // Lock screen: "🍼 2h 15m / last feed"
    private var lockScreenBody: some View {
        HStack(spacing: 6) {
            Text(kind.emoji)
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                valueText
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.primary)
                Text(captionLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    // Small home screen tile
    private var homeSmallBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(kind.emoji)
                    .font(.title2)
                Spacer()
                if !showingActiveSleep {
                    urgencyDot
                }
            }
            Spacer()
            valueText
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(accentColor)
                .minimumScaleFactor(0.65)
            Text(captionLabel)
                .font(.caption)
                .foregroundStyle(AppColor.text2)
        }
        .padding(12)
        .containerBackground(AppColor.card, for: .widget)
    }

    // MARK: Content per kind

    /// The sleep widget shows a live counting timer while a sleep is in progress.
    private var showingActiveSleep: Bool {
        kind == .sleep && entry.isActiveSleep && entry.activeSleepStartedAt != nil
    }

    private var valueText: Text {
        if showingActiveSleep, let started = entry.activeSleepStartedAt {
            return Text(started, style: .timer)
        }
        if let date = sinceDate {
            return Text(TimeFormatting.since(date))
        }
        return Text("–")
    }

    private var captionLabel: String {
        if showingActiveSleep { return "sleeping now" }
        switch kind {
        case .feed:   return "since last feed"
        case .sleep:  return "since last sleep"
        case .diaper: return "since last diaper"
        }
    }

    private var sinceDate: Date? {
        switch kind {
        case .feed:   return entry.lastFeedDate
        case .sleep:  return entry.lastSleepDate
        case .diaper: return entry.lastDiaperDate
        }
    }

    private var targetInterval: TimeInterval {
        switch kind {
        case .feed:   return entry.feedTargetInterval
        case .sleep:  return UrgencyDefaults.sleep
        case .diaper: return UrgencyDefaults.diaper
        }
    }

    private var accentColor: Color {
        switch kind {
        case .feed:   return AppColor.accentFeed
        case .sleep:  return AppColor.accentSleep
        case .diaper: return AppColor.accentDiaper
        }
    }

    private var urgencyDot: some View {
        let u = Urgency.from(since: sinceDate, target: targetInterval)
        return Circle().fill(u.color).frame(width: 8, height: 8)
    }
}

// MARK: - Widget registrations (one per event kind)

struct LastFeedWidget: Widget {
    let kind = "LastFeedWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetProvider()) { entry in
            SmallEventWidgetView(kind: .feed, entry: entry)
        }
        .configurationDisplayName("Last Feed")
        .description("Time since Miller's last bottle.")
        .supportedFamilies([.accessoryRectangular, .systemSmall])
        .contentMarginsDisabled()
    }
}

struct LastSleepWidget: Widget {
    let kind = "LastSleepWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetProvider()) { entry in
            SmallEventWidgetView(kind: .sleep, entry: entry)
        }
        .configurationDisplayName("Last Sleep")
        .description("Time since Miller's last sleep — or a live timer while sleeping.")
        .supportedFamilies([.accessoryRectangular, .systemSmall])
        .contentMarginsDisabled()
    }
}

struct LastDiaperWidget: Widget {
    let kind = "LastDiaperWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetProvider()) { entry in
            SmallEventWidgetView(kind: .diaper, entry: entry)
        }
        .configurationDisplayName("Last Diaper")
        .description("Time since Miller's last diaper change.")
        .supportedFamilies([.accessoryRectangular, .systemSmall])
        .contentMarginsDisabled()
    }
}
