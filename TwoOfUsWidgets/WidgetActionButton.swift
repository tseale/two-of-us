import SwiftUI
import WidgetKit
import AppIntents

/// A compact interactive widget button bound to an App Intent. Runs the intent
/// in-process (no app launch) on iOS 17+. Emoji-led, like the in-app log tiles —
/// emoji are the event iconography (🍼 💩 💤), pill styling matches the app's chips.
struct WidgetActionButton<I: AppIntent>: View {
    let title: String
    let emoji: String
    let tint: Color
    let intent: I

    var body: some View {
        Button(intent: intent) {
            HStack(spacing: 4) {
                Text(emoji)
                Text(title)
            }
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
        .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// The Feed · Diaper · Sleep quick-log row used by the medium and large widgets.
struct QuickLogRow: View {
    let isSleeping: Bool

    var body: some View {
        HStack(spacing: 6) {
            WidgetActionButton(title: "Feed", emoji: "🍼",
                               tint: AppColor.accentFeed, intent: LogFeedIntent())
            WidgetActionButton(title: "Diaper", emoji: "💩",
                               tint: AppColor.accentDiaper, intent: LogDiaperIntent())
            WidgetActionButton(title: isSleeping ? "Wake" : "Sleep",
                               emoji: isSleeping ? "☀️" : "💤",
                               tint: AppColor.accentSleep, intent: ToggleSleepIntent())
        }
    }
}

/// The Today-card glance unit shared by the medium and large widgets: three
/// centered metric columns (emoji → time-since value → eyebrow label) split by
/// 0.5pt hairlines — the same arrangement as the in-app `TodayRibbonCard`.
struct WidgetMetricColumns: View {
    let entry: WidgetEntry

    var body: some View {
        HStack(spacing: 0) {
            column(emoji: "🍼", label: "feed",
                   value: value(for: entry.lastFeedDate),
                   urgency: Urgency.from(since: entry.lastFeedDate, target: entry.feedTargetInterval))
            hairline
            sleepColumn
            hairline
            column(emoji: "💩", label: "diaper",
                   value: value(for: entry.lastDiaperDate),
                   urgency: Urgency.from(since: entry.lastDiaperDate, target: UrgencyDefaults.diaper))
        }
    }

    /// The sleep column becomes a live counting timer while a sleep runs.
    @ViewBuilder private var sleepColumn: some View {
        if entry.isActiveSleep, let started = entry.activeSleepStartedAt {
            column(emoji: "💤", label: "sleeping",
                   value: Text(started, style: .timer),
                   urgency: .green, labelColor: AppColor.accentSleep)
        } else {
            column(emoji: "💤", label: "sleep",
                   value: value(for: entry.lastSleepDate),
                   urgency: Urgency.from(since: entry.lastSleepDate, target: UrgencyDefaults.sleep))
        }
    }

    private func value(for date: Date?) -> Text {
        // `.relative` self-updates — ticks with no timeline reloads.
        date.map { Text($0, style: .relative) } ?? Text("–")
    }

    private func column(emoji: String, label: String, value: Text,
                        urgency: Urgency, labelColor: Color = AppColor.text3) -> some View {
        VStack(spacing: 3) {
            Text(emoji).font(.footnote)
            WidgetSinceLine(value: value, urgency: urgency,
                            font: AppFont.display(18, relativeTo: .title3))
                .multilineTextAlignment(.center)
            Text(label).sectionLabelStyle(color: labelColor)
        }
        .frame(maxWidth: .infinity)
    }

    private var hairline: some View {
        Rectangle()
            .fill(AppColor.separator.opacity(0.5))
            .frame(width: 0.5, height: 34)
    }
}

/// "Quiet until it matters" for widget time values — the same treatment as the
/// app's log-tile since-line: plain at green, tinted text + an 8pt dot once
/// attention is due. Takes a `Text` so self-updating `.relative` / `.timer`
/// styles keep ticking without timeline reloads.
struct WidgetSinceLine: View {
    let value: Text
    let urgency: Urgency
    var font: Font
    var quietColor: Color = AppColor.text

    var body: some View {
        HStack(spacing: 5) {
            value
                .font(font)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
            if urgency.needsAttention {
                Circle()
                    .fill(urgency.color)
                    .frame(width: 8, height: 8)
            }
        }
        .foregroundStyle(urgency.needsAttention ? urgency.sinceTextColor : quietColor)
    }
}
