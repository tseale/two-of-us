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
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(AppColor.text)
                Spacer()
                Text(Date.now, style: .time)
                    .font(.caption)
                    .foregroundStyle(AppColor.text3)
            }
            .padding(.bottom, 8)

            DayRibbonView(marks: entry.todayMarks, style: .color)
                .frame(height: 22)
                .padding(.bottom, 10)

            WidgetMetricColumns(entry: entry)
                .padding(.bottom, 10)

            // Recent timeline — the app's rail language in miniature:
            // mono time gutter, an accent node per event, emoji + detail.
            if entry.recentItems.isEmpty {
                Text("No events yet today")
                    .font(.caption)
                    .foregroundStyle(AppColor.text3)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entry.recentItems.prefix(5), id: \.self) { item in
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

    private func recentRow(item: WidgetItem) -> some View {
        HStack(spacing: 8) {
            Text(TimeFormatting.clock(item.date))
                .font(.caption.monospacedDigit())
                .foregroundStyle(AppColor.text3)
                .frame(width: 48, alignment: .trailing)
            Circle()
                .fill(accent(for: item.kind))
                .frame(width: 11, height: 11)
            Text(item.kind.emoji)
                .font(.caption)
            Text(item.detail)
                .font(.caption)
                .foregroundStyle(AppColor.text2)
            Spacer()
        }
    }

    private func accent(for kind: EventKind) -> Color {
        switch kind {
        case .feed:   return AppColor.accentFeed
        case .sleep:  return AppColor.accentSleep
        case .diaper: return AppColor.accentDiaper
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
