import SwiftUI

struct TimelineRow: View {
    let entry: TimelineEntry

    var body: some View {
        HStack(spacing: 12) {
            Text(entry.kind.emoji)
                .font(.body)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.text)
                Text(TimeFormatting.clock(entry.sortDate))
                    .font(.caption)
                    .foregroundStyle(AppColor.text3)
            }
            Spacer()
            ParticipantBadge(name: entry.loggedByName, colorHex: entry.loggedByColorHex)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.title), \(TimeFormatting.clock(entry.sortDate)), logged by \(entry.loggedByName)")
    }
}
