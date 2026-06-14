import SwiftUI
import WidgetKit

/// Small "time since last X" widget for a single event kind — rendered as a
/// lock screen accessory (`.accessoryRectangular`) or a small home screen tile
/// (`.systemSmall`). One instance per kind is registered below.
///
/// The home tile is a 1:1 mirror of the in-app log tile (`LogButtons.tile`):
/// emoji over title / since-line / hint, with the ⊕ "tap to add" badge. The
/// whole widget is a single tap target — `widgetURL` deep-links into the app to
/// the matching log screen (feed/diaper sheet), or starts the sleep timer — so
/// there are no in-widget buttons to intercept the tap.
struct SmallEventWidgetView: View {
    let kind: EventKind
    let entry: WidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if family == .accessoryRectangular {
                lockScreenBody
            } else {
                homeSmallBody
            }
        }
        // Tapping anywhere opens the app to this kind's action. Routed by
        // DeepLinkRouter via onOpenURL: feed/diaper present their log sheet,
        // sleep starts the timer.
        .widgetURL(deepLink)
    }

    /// `twoofus://log/feed` · `…/diaper` · `…/sleep`.
    private var deepLink: URL? {
        URL(string: "twoofus://log/\(kind.rawValue)")
    }

    // Lock screen: monochrome per DESIGN.md §9 — eyebrow above a rounded mono
    // value, no emoji. In the accessory's vibrant rendering a color emoji
    // desaturates to a gray blob and it would also steal width from the value
    // in the narrow rectangular slot; the eyebrow ("LAST FEED") names the kind.
    // The value shrinks before it truncates, per §9's "shrink to 0.7" rule, so
    // a two-component relative string ("2 hr, 5 min ago") still fits.
    private var lockScreenBody: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(captionLabel)
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(.secondary)
            valueText
                .font(.system(.headline, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    // Home screen tile — the in-app log tile (`LogButtons.tile`) exactly:
    // emoji (30) on top, then title / since-line / hint stacked leading, with
    // the ⊕ badge top-trailing and the accent-tinted ground (the widget stand-in
    // for the app's interactive glass tile).
    private var homeSmallBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(showingActiveSleep ? "💤" : kind.emoji)
                .font(.system(size: 30))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .lineLimit(1)
                statusLine
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(AppColor.text2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The ⊕ "tap to add" affordance, matching the app tile. Hidden while a
        // sleep runs — the tile is then a live timer you tap to open, not add.
        .overlay(alignment: .topTrailing) {
            if !showingActiveSleep { plusBadge.padding(14) }
        }
        .containerBackground(for: .widget) {
            ZStack {
                AppColor.card
                accentColor.opacity(0.18)
            }
        }
    }

    /// The since-line, mirroring `LogButtons.sinceLine`: calm gray text at green,
    /// tinted semibold text + an 8pt dot once attention is due. While a sleep
    /// runs it becomes the live counting timer in the sleep accent.
    @ViewBuilder private var statusLine: some View {
        if showingActiveSleep, let started = entry.activeSleepStartedAt {
            HStack(spacing: 5) {
                Text(started, style: .timer)
                    .fontWeight(.semibold)
            }
            .font(.subheadline)
            .foregroundStyle(AppColor.accentSleep)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        } else if let date = sinceDate {
            let u = urgency
            HStack(spacing: 5) {
                (Text(date, style: .relative) + Text(" ago"))
                    .fontWeight(u.needsAttention ? .semibold : .regular)
                if u.needsAttention {
                    Circle().fill(u.color).frame(width: 8, height: 8)
                }
            }
            .font(.subheadline)
            .foregroundStyle(u.sinceTextColor)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
    }

    /// "Tap to add" affordance — matches the app tile's badge.
    private var plusBadge: some View {
        Image(systemName: "plus.circle.fill")
            .font(.system(size: 22))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, accentColor)
    }

    // MARK: Content per kind

    /// The sleep widget shows a live counting timer while a sleep is in progress.
    private var showingActiveSleep: Bool {
        kind == .sleep && entry.isActiveSleep && entry.activeSleepStartedAt != nil
    }

    /// Tile title — the action name, like the in-app tile ("Feed"/"Sleep"/"Diaper").
    private var title: String {
        if showingActiveSleep { return "Sleeping" }
        switch kind {
        case .feed:   return "Feed"
        case .sleep:  return "Sleep"
        case .diaper: return "Diaper"
        }
    }

    /// The caption beneath the since-line — the in-app tile's `hint`, computed
    /// from the same data so the widget reads identically: the projected next
    /// feed/nap, the diaper options, or the active-sleep start time.
    private var hint: String {
        if showingActiveSleep, let started = entry.activeSleepStartedAt {
            return "since \(TimeFormatting.clock(started))"
        }
        switch kind {
        case .feed:
            guard let last = entry.lastFeedDate else { return "log a bottle" }
            let next = last.addingTimeInterval(entry.feedTargetInterval)
            return next < entry.date
                ? "bottle was due ~\(TimeFormatting.clock(next))"
                : "next bottle ~\(TimeFormatting.clock(next))"
        case .sleep:
            guard let lastEnd = entry.lastSleepDate else { return "start timer" }
            let next = lastEnd.addingTimeInterval(UrgencyDefaults.sleep)
            return next < entry.date
                ? "nap was due ~\(TimeFormatting.clock(next))"
                : "next nap ~\(TimeFormatting.clock(next))"
        case .diaper:
            return "wet · dirty · both"
        }
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

    /// Eyebrow above the value on the lock screen (rendered uppercase by the label styles).
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
