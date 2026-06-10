import SwiftUI
import WidgetKit

/// Large home screen widget — all three time-since rows plus a recent event log.
struct LargeWidgetView: View {
    let entry: WidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(entry.babyName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.text)
                Spacer()
                Text(Date.now, style: .time)
                    .font(.caption)
                    .foregroundStyle(AppColor.text3)
            }
            .padding(.bottom, 10)

            // Time-since pills
            VStack(spacing: 6) {
                summaryRow(emoji: "🍼", label: "Feed",
                           date: entry.lastFeedDate,
                           color: AppColor.accentFeed,
                           urgency: Urgency.from(since: entry.lastFeedDate, target: entry.feedTargetInterval))
                summaryRow(emoji: "💤", label: "Sleep",
                           date: entry.lastSleepDate,
                           color: AppColor.accentSleep,
                           urgency: Urgency.from(since: entry.lastSleepDate, target: UrgencyDefaults.sleep))
                summaryRow(emoji: "💩", label: "Diaper",
                           date: entry.lastDiaperDate,
                           color: AppColor.accentDiaper,
                           urgency: Urgency.from(since: entry.lastDiaperDate, target: UrgencyDefaults.diaper))
            }

            Divider().overlay(AppColor.separator).padding(.vertical, 10)

            // Recent timeline
            if entry.recentItems.isEmpty {
                Text("No events yet today")
                    .font(.caption)
                    .foregroundStyle(AppColor.text3)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            } else {
                VStack(spacing: 5) {
                    ForEach(entry.recentItems.prefix(5), id: \.date) { item in
                        recentRow(item: item)
                    }
                }
            }
            Spacer(minLength: 8)
            QuickLogRow(isSleeping: entry.isActiveSleep)
        }
        .padding(14)
        .containerBackground(AppColor.card, for: .widget)
    }

    private func summaryRow(emoji: String, label: String, date: Date?, color: Color, urgency: Urgency) -> some View {
        HStack(spacing: 8) {
            Text(emoji).frame(width: 20)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(AppColor.text2)
            Spacer()
            if let date {
                Text(date, style: .relative)
                    .font(.subheadline.bold().monospacedDigit())
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

    private func recentRow(item: WidgetItem) -> some View {
        HStack(spacing: 6) {
            Text(item.kind.emoji)
                .font(.caption)
                .frame(width: 18)
            Text(TimeFormatting.clock(item.date))
                .font(.caption.monospacedDigit())
                .foregroundStyle(AppColor.text3)
            Text(item.detail)
                .font(.caption)
                .foregroundStyle(AppColor.text2)
            Spacer()
        }
    }
}

struct HomeScreenLargeWidget: Widget {
    let kind = "HomeScreenLargeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetProvider()) { entry in
            LargeWidgetView(entry: entry)
        }
        .configurationDisplayName("Two of Us — Full")
        .description("All events plus a recent timeline.")
        .supportedFamilies([.systemLarge])
        .contentMarginsDisabled()
    }
}
