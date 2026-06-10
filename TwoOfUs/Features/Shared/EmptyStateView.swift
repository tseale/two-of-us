import SwiftUI

/// A warm, characterful empty state: a softly bobbing emoji, a rounded title, and
/// a friendly line of guidance. Used wherever there's "nothing here yet" so first
/// runs feel inviting rather than blank. The bob is disabled under Reduce Motion.
struct EmptyStateView: View {
    let emoji: String
    let title: String
    let message: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bob = false

    var body: some View {
        VStack(spacing: 10) {
            Text(emoji)
                .font(.system(size: 46))
                .offset(y: bob ? -5 : 4)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 1.9).repeatForever(autoreverses: true),
                    value: bob
                )
            Text(title)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(AppColor.text)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppColor.text2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 24)
        .onAppear { bob = true }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(message)")
    }
}
