import SwiftUI

/// The "today so far" glance card on the Home tab: a 24h ribbon of when events
/// happened, plus a one-line tally. Deep multi-day charts live in the History tab.
struct TodayRibbonCard: View {
    let marks: [RibbonMark]
    let feedCount: Int
    let sleepSeconds: TimeInterval
    let diaperCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Today so far")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.text2)
                Spacer()
                Text("🍼 \(feedCount)  ·  💤 \(sleepSummary)  ·  💩 \(diaperCount)")
                    .font(.caption)
                    .foregroundStyle(AppColor.text3)
            }

            DayRibbonView(marks: marks, style: .color)
                .frame(height: 34)

            HStack(spacing: 16) {
                legend(color: AppColor.accentFeed, label: "feed", isBar: false)
                legend(color: AppColor.accentDiaper, label: "diaper", isBar: false)
                legend(color: AppColor.accentSleep, label: "sleep", isBar: true)
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Today: \(feedCount) feeds, \(sleepSummary) sleep, \(diaperCount) diapers")
    }

    private var sleepSummary: String {
        let minutes = Int(sleepSeconds / 60)
        let h = minutes / 60
        let m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h\(m)"
    }

    private func legend(color: Color, label: String, isBar: Bool) -> some View {
        HStack(spacing: 5) {
            if isBar {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 12, height: 4)
            } else {
                Circle().fill(color).frame(width: 8, height: 8)
            }
            Text(label).font(.caption2).foregroundStyle(AppColor.text2)
        }
    }
}
