import SwiftUI

/// A "time since last X" pill with an urgency dot.
struct StatusPill: View {
    let emoji: String
    let value: String
    let label: String
    let urgency: Urgency

    var body: some View {
        VStack(spacing: 3) {
            Text(emoji).font(.headline)
            HStack(spacing: 4) {
                Circle()
                    .fill(urgency.color)
                    .frame(width: 7, height: 7)
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppColor.text)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(AppColor.text3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .glassCard(cornerRadius: 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value), \(urgency.accessibilityWord)")
    }
}
