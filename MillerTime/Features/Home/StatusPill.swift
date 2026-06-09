import SwiftUI

/// A "time since last X" pill with an urgency dot.
struct StatusPill: View {
    let emoji: String
    let value: String
    let label: String
    let urgency: Urgency

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 4) {
                Text(emoji).font(.footnote)
                Circle()
                    .fill(urgency.color)
                    .frame(width: 6, height: 6)
            }
            Text(value)
                .font(AppFont.display(20))
                .foregroundStyle(AppColor.text)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .sectionLabelStyle(color: AppColor.text3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .padding(.horizontal, 6)
        .surfaceCard(cornerRadius: 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value), \(urgency.accessibilityWord)")
    }
}
