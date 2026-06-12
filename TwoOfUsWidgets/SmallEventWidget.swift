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

    // Lock screen: MetricStack ordering — eyebrow above a rounded mono value.
    private var lockScreenBody: some View {
        HStack(spacing: 6) {
            Text(kind.emoji)
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text(captionLabel)
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                valueText
                    .font(.system(.headline, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    // Small home screen tile — a mini log tile: accent-tinted ground, emoji,
    // eyebrow above the display value, urgency only when it's earned.
    private var homeSmallBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(kind.emoji)
                .font(.system(size: 28))
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(captionLabel)
                    .sectionLabelStyle(color: showingActiveSleep ? AppColor.accentSleep : AppColor.text2)
                WidgetSinceLine(value: valueText,
                                urgency: showingActiveSleep ? .green : urgency,
                                font: AppFont.display(26, relativeTo: .title2))
            }
            quickLogButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .containerBackground(for: .widget) {
            ZStack {
                AppColor.card
                accentColor.opacity(0.18)
            }
        }
    }

    /// One-tap logging straight from the home-screen tile (no app launch).
    @ViewBuilder private var quickLogButton: some View {
        switch kind {
        case .feed:
            WidgetActionButton(title: "Log feed", emoji: "🍼", tint: accentColor,
                               intent: LogFeedIntent())
        case .diaper:
            WidgetActionButton(title: "Log diaper", emoji: "💩", tint: accentColor,
                               intent: LogDiaperIntent())
        case .sleep:
            WidgetActionButton(title: showingActiveSleep ? "Wake up" : "Start sleep",
                               emoji: showingActiveSleep ? "☀️" : "💤",
                               tint: accentColor, intent: ToggleSleepIntent())
        }
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
            // Self-updating relative time — ticks on its own with no timeline reloads.
            return Text(date, style: .relative)
        }
        return Text("–")
    }

    /// Eyebrow above the value (rendered uppercase by the label styles).
    private var captionLabel: String {
        if showingActiveSleep { return "sleeping now" }
        switch kind {
        case .feed:   return "last feed"
        case .sleep:  return "last sleep"
        case .diaper: return "last diaper"
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

    private var urgency: Urgency {
        Urgency.from(since: sinceDate, target: targetInterval)
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
        .description("Time since your baby's last bottle.")
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
        .description("Time since your baby's last sleep — or a live timer while sleeping.")
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
        .description("Time since your baby's last diaper change.")
        .supportedFamilies([.accessoryRectangular, .systemSmall])
        .contentMarginsDisabled()
    }
}
