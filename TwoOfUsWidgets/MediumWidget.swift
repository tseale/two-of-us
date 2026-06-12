import SwiftUI
import WidgetKit

/// Medium home screen widget — shows time since last event for all three categories.
struct MediumWidgetView: View {
    let entry: WidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("TODAY").sectionLabelStyle()
                Spacer()
                Text(entry.babyName)
                    .font(.caption)
                    .foregroundStyle(AppColor.text3)
            }
            .padding(.bottom, 6)

            DayRibbonView(marks: entry.todayMarks, style: .color)
                .frame(height: 22)
                .padding(.bottom, 8)

            WidgetMetricColumns(entry: entry)

            Spacer(minLength: 8)
            QuickLogRow(isSleeping: entry.isActiveSleep)
        }
        .padding(14)
        .containerBackground(AppColor.card, for: .widget)
    }
}

struct HomeScreenMediumWidget: Widget {
    let kind = "HomeScreenMediumWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetProvider()) { entry in
            MediumWidgetView(entry: entry)
        }
        .configurationDisplayName("Two of Us")
        .description("Last feed, sleep, and diaper at a glance.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}
