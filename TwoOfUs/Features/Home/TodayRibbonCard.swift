import SwiftUI

/// The Home glance header: today's rhythm as a slim 24-hour **ribbon** (see
/// `DayRibbonView`) with the day's three glance numbers beneath it. The full
/// event story lives in the timeline rail (`DayTimelineRow`) just below. Deep
/// multi-day charts live in the History tab.
struct TodayRibbonCard: View {
    let marks: [RibbonMark]
    let feedCount: Int
    let sleepSeconds: TimeInterval
    let diaperCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TODAY").sectionLabelStyle()

            DayRibbonView(marks: marks)
                .frame(height: 40)

            HStack(spacing: 0) {
                metric(emoji: "🍼", value: "\(feedCount)", label: Plural.unit(feedCount, "feed"), color: AppColor.accentFeed)
                metricDivider
                metric(emoji: "💤", value: sleepSummary, label: "sleep", color: AppColor.accentSleep)
                metricDivider
                metric(emoji: "💩", value: "\(diaperCount)", label: Plural.unit(diaperCount, "change"), color: AppColor.accentDiaper)
            }
        }
        .padding(16)
        .surfaceCard(cornerRadius: 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Today: \(Plural.count(feedCount, "feed")), \(sleepSummary) sleep, \(Plural.count(diaperCount, "diaper"))")
    }

    private func metric(emoji: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(emoji).font(.footnote)
            Text(value)
                .font(AppFont.display(26))
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label).sectionLabelStyle(color: AppColor.text3)
                // Shrink-to-fit rather than break mid-word ("CHANG ES") at large
                // Dynamic Type in the narrow third-of-width column.
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(AppColor.separator.opacity(0.5))
            .frame(width: 0.5, height: 34)
    }

    private var sleepSummary: String {
        let minutes = Int(sleepSeconds / 60)
        let h = minutes / 60
        let m = minutes % 60
        if h == 0 { return "\(m)m" }
        // Match TimeFormatting's spaced style ("2h 45m") rather than "2h45".
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}
