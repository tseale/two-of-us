import SwiftUI

/// The "Daycare report" glance card on Home: one line summarizing what
/// Brightwheel logged for Miller today — bottles, naps, changes — so a parent
/// arriving at pick-up reads the day without scrolling the timeline. Only
/// renders when today actually has daycare events; the per-event story stays
/// on the timeline rail with its Daycare tags.
struct DaycareReportCard: View {
    let babyName: String
    let feedCount: Int
    let feedOz: Double
    let napCount: Int
    let napSeconds: TimeInterval
    let diaperCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("\u{1F3EB}")
                Text("DAYCARE REPORT").sectionLabelStyle()
            }
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(AppColor.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .surfaceCard(cornerRadius: 14)
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        var parts: [String] = []
        if feedCount > 0 {
            parts.append("\(Plural.unit(feedCount, "bottle")) (\(OzFormat.string(feedOz)) oz total)")
        }
        if napCount > 0 {
            parts.append("\(Plural.unit(napCount, "nap")) (\(TimeFormatting.duration(minutes: Int(napSeconds / 60))))")
        }
        if diaperCount > 0 {
            parts.append(Plural.unit(diaperCount, "diaper change"))
        }
        guard !parts.isEmpty else {
            return "\(babyName) is checked in at daycare."
        }
        return "\(babyName) had " + parts.formatted(.list(type: .and)) + " at daycare today."
    }
}
