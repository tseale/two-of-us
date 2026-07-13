import SwiftUI
import WidgetKit
import AppIntents

/// Small "time since last X" widget for a single event kind — rendered as a
/// lock screen accessory (`.accessoryRectangular`) or a small home screen tile
/// (`.systemSmall`). One instance per kind is registered below.
///
/// The home tile is a 1:1 copy of the in-app log tile (`LogButtons.tile`): emoji,
/// title, the same "quiet until it matters" since-line, and a hint — so the
/// widget reads identically to the button you'd tap inside the app. The whole
/// tile is one tap target. Feed and Diaper deep-link into the app to open their
/// log sheet; Sleep toggles the timer in-process via `ToggleSleepIntent`, so it
/// never launches the app.
struct SmallEventWidgetView: View {
    let kind: EventKind
    let entry: WidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .accessoryRectangular {
            lockScreenBody
                .widgetURL(deepLinkURL)
        } else {
            homeTile
        }
    }

    // Lock screen: MetricStack ordering — eyebrow above a rounded mono value.
    private var lockScreenBody: some View {
        HStack(spacing: 6) {
            Text(kind.emoji)
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text(lockCaption)
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

    /// `.systemSmall` home tile. Feed/Diaper carry a `widgetURL`; Sleep is the
    /// whole-tile interactive button that toggles the timer without opening the
    /// app. `containerBackground` stays outermost so WidgetKit picks it up even
    /// when the content is wrapped in the Sleep button.
    @ViewBuilder private var homeTile: some View {
        Group {
            switch kind {
            case .feed, .diaper:
                tileContent
                    .widgetURL(deepLinkURL)
            case .sleep:
                Button(intent: ToggleSleepIntent()) { tileContent }
                    .buttonStyle(.plain)
            }
        }
        .containerBackground(for: .widget) {
            ZStack {
                AppColor.card
                accentColor.opacity(0.18)
            }
        }
    }

    /// The shared visual — matches `LogButtons.tile`: emoji on top, then title /
    /// since-line / hint, leading-aligned, with the ⊕ "tap to add" badge and the
    /// accent-tinted ground standing in for the app's interactive glass (widgets
    /// can't render Liquid Glass).
    private var tileContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(kind.emoji).font(.system(size: 30))
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .lineLimit(1)
                if hasSinceLine { sinceLine }
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(AppColor.text2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(16)
        .foregroundStyle(AppColor.text)
        .overlay(alignment: .topTrailing) {
            if !showingActiveSleep { plusBadge }
        }
    }

    /// Quiet until it matters — the exact treatment from the app's log-tile
    /// since-line: plain gray at green, tinted semibold text + an 8pt dot at
    /// amber/red. While sleeping it carries the live counting timer at green.
    private var sinceLine: some View {
        HStack(spacing: 5) {
            valueText
                .fontWeight(effectiveUrgency.needsAttention ? .semibold : .regular)
            if effectiveUrgency.needsAttention {
                Circle()
                    .fill(effectiveUrgency.color)
                    .frame(width: 8, height: 8)
            }
        }
        .font(.subheadline)
        .foregroundStyle(effectiveUrgency.sinceTextColor)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    /// "Tap to add" affordance — matches the app tile's badge.
    private var plusBadge: some View {
        Image(systemName: "plus.circle.fill")
            .font(.system(size: 22))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, accentColor)
            .padding(14)
    }

    // MARK: Content per kind

    /// The sleep widget shows a live counting timer while a sleep is in progress.
    private var showingActiveSleep: Bool {
        kind == .sleep && entry.isActiveSleep && entry.activeSleepStartedAt != nil
    }

    /// Tile title, matching the app's `LogButtons` labels.
    private var title: String {
        if showingActiveSleep { return "Sleeping" }
        switch kind {
        case .feed:   return "Feed"
        case .sleep:  return "Sleep"
        case .diaper: return "Diaper"
        }
    }

    /// Only drawn when there's something to show — a prior event, or a running
    /// sleep. First-run tiles read title + hint, like the app's clean first run.
    private var hasSinceLine: Bool {
        showingActiveSleep || sinceDate != nil
    }

    private var valueText: Text {
        if showingActiveSleep, let started = entry.activeSleepStartedAt {
            return Text(started, style: .timer)
        }
        if let date = sinceDate {
            // Self-updating relative time — ticks on its own with no timeline
            // reloads. The app shows a precise "2h 31m ago"; a widget can't
            // recompute that every second, so this is the one phrasing difference.
            return Text("\(date, style: .relative) ago")
        }
        // Home tile hides the since-line entirely with no prior event
        // (`hasSinceLine`); this fallback only shows on the lock-screen accessory.
        return Text("–")
    }

    /// Green while sleeping (the running timer is calm), otherwise the real urgency.
    private var effectiveUrgency: Urgency {
        showingActiveSleep ? .green : urgency
    }

    /// The next-step hint under the since-line — the same projections HomeView
    /// shows on its tiles.
    private var hint: String {
        let now = entry.date
        switch kind {
        case .feed:
            guard let last = entry.lastFeedDate else { return "log a bottle" }
            let next = last.addingTimeInterval(entry.feedTargetInterval)
            return next < now ? "bottle was due ~\(TimeFormatting.clock(next))"
                              : "next bottle ~\(TimeFormatting.clock(next))"
        case .diaper:
            return "wet · dirty · both"
        case .sleep:
            if showingActiveSleep { return "tap to wake" }
            guard let lastEnd = entry.lastSleepDate else { return "start timer" }
            let next = lastEnd.addingTimeInterval(UrgencyDefaults.sleep)
            return next < now ? "nap was due ~\(TimeFormatting.clock(next))"
                              : "next nap ~\(TimeFormatting.clock(next))"
        }
    }

    /// Deep link for the whole-tile tap. Sleep returns nil — it toggles in-process.
    private var deepLinkURL: URL? {
        switch kind {
        case .feed:   return URL(string: "twoofus://log/feed")
        case .diaper: return URL(string: "twoofus://log/diaper")
        case .sleep:  return nil
        }
    }

    /// Eyebrow above the value on the lock-screen accessory.
    private var lockCaption: String {
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
