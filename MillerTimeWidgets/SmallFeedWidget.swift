import SwiftUI
import WidgetKit

/// Small feed widget — rendered as a lock screen accessory (`.accessoryRectangular`)
/// or a small home screen tile (`.systemSmall`).
struct SmallFeedWidgetView: View {
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
            Text("🍼")
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                sinceLabelText
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.primary)
                Text("last feed")
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
                Text("🍼")
                    .font(.title2)
                Spacer()
                urgencyDot
            }
            Spacer()
            sinceLabelText
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(AppColor.accentFeed)
                .minimumScaleFactor(0.65)
            Text("since last feed")
                .font(.caption)
                .foregroundStyle(AppColor.text2)
        }
        .padding(12)
        .containerBackground(AppColor.card, for: .widget)
    }

    private var sinceLabelText: Text {
        if let date = entry.lastFeedDate {
            return Text(TimeFormatting.since(date))
        }
        return Text("–")
    }

    private var urgencyDot: some View {
        let u = Urgency.from(since: entry.lastFeedDate, target: entry.feedTargetInterval)
        return Circle().fill(u.color).frame(width: 8, height: 8)
    }
}

struct LockScreenFeedWidget: Widget {
    let kind = "LockScreenFeedWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetProvider()) { entry in
            SmallFeedWidgetView(entry: entry)
        }
        .configurationDisplayName("Last Feed")
        .description("Time since Miller's last bottle.")
        .supportedFamilies([.accessoryRectangular, .systemSmall])
        .contentMarginsDisabled()
    }
}
