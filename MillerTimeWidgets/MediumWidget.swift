import SwiftUI
import WidgetKit

/// Medium home screen widget — shows time since last event for all three categories.
struct MediumWidgetView: View {
    let entry: WidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Miller")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColor.text2)
                Spacer()
                Circle()
                    .fill(AppColor.urgencyGreen)
                    .frame(width: 6, height: 6)
            }
            .padding(.bottom, 8)

            VStack(spacing: 6) {
                eventRow(emoji: "🍼", label: "Feed",
                         date: entry.lastFeedDate,
                         color: AppColor.accentFeed,
                         urgency: Urgency.from(since: entry.lastFeedDate, target: entry.feedTargetInterval))
                Divider().overlay(AppColor.separator)
                eventRow(emoji: "💤", label: "Sleep",
                         date: entry.lastSleepDate,
                         color: AppColor.accentSleep,
                         urgency: Urgency.from(since: entry.lastSleepDate, target: UrgencyDefaults.sleep))
                Divider().overlay(AppColor.separator)
                eventRow(emoji: "💩", label: "Diaper",
                         date: entry.lastDiaperDate,
                         color: AppColor.accentDiaper,
                         urgency: Urgency.from(since: entry.lastDiaperDate, target: UrgencyDefaults.diaper))
            }
        }
        .padding(14)
        .containerBackground(AppColor.card, for: .widget)
    }

    private func eventRow(emoji: String, label: String, date: Date?, color: Color, urgency: Urgency) -> some View {
        HStack(spacing: 8) {
            Text(emoji)
                .font(.body)
                .frame(width: 20)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(AppColor.text2)
            Spacer()
            if let date {
                Text(TimeFormatting.since(date))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(urgency.color)
                Text("ago")
                    .font(.caption)
                    .foregroundStyle(AppColor.text3)
            } else {
                Text("–")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.text3)
            }
        }
    }
}

struct HomeScreenMediumWidget: Widget {
    let kind = "HomeScreenMediumWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetProvider()) { entry in
            MediumWidgetView(entry: entry)
        }
        .configurationDisplayName("Miller Time")
        .description("Last feed, sleep, and diaper at a glance.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}
