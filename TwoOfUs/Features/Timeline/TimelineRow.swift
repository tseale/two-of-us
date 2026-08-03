import SwiftUI

struct TimelineRow: View {
    let entry: TimelineEntry

    var body: some View {
        HStack(spacing: 12) {
            Text(entry.emoji)
                .font(.body)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.text)
                    if entry.isFromSnoo { SnooTag() }
                }
                Text(TimeFormatting.clock(entry.sortDate))
                    .font(.caption)
                    .foregroundStyle(AppColor.text3)
            }
            Spacer()
            ParticipantBadge(name: entry.loggedByName, colorHex: entry.loggedByColorHex)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.title), \(TimeFormatting.clock(entry.sortDate))\(entry.isFromSnoo ? ", from SNOO" : ""), logged by \(entry.loggedByName)")
    }
}
