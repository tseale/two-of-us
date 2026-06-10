import SwiftUI
import WidgetKit
import AppIntents

/// A compact interactive widget button bound to an App Intent. Runs the intent
/// in-process (no app launch) on iOS 17+.
struct WidgetActionButton<I: AppIntent>: View {
    let title: String
    let systemImage: String
    let tint: Color
    let intent: I

    var body: some View {
        Button(intent: intent) {
            Label(title, systemImage: systemImage)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
        .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// The Feed · Diaper · Sleep quick-log row used by the medium and large widgets.
struct QuickLogRow: View {
    let isSleeping: Bool

    var body: some View {
        HStack(spacing: 6) {
            WidgetActionButton(title: "Feed", systemImage: "drop.fill",
                               tint: AppColor.accentFeed, intent: LogFeedIntent())
            WidgetActionButton(title: "Diaper", systemImage: "leaf.fill",
                               tint: AppColor.accentDiaper, intent: LogDiaperIntent())
            WidgetActionButton(title: isSleeping ? "Wake" : "Sleep",
                               systemImage: isSleeping ? "sun.max.fill" : "moon.fill",
                               tint: AppColor.accentSleep, intent: ToggleSleepIntent())
        }
    }
}
