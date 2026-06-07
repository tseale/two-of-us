import SwiftUI
import WidgetKit
import ActivityKit

// MARK: - Lock Screen View

/// Full live activity view shown on the lock screen while Miller sleeps.
struct SleepLockScreenView: View {
    let context: ActivityViewContext<SleepActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "moon.zzz.fill")
                .font(.title2)
                .foregroundStyle(AppColor.accentSleep)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(context.attributes.babyName) is sleeping")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                // `.timer` style counts up automatically — no periodic update push needed.
                Text(context.state.startedAt, style: .timer)
                    .font(.title2.monospacedDigit())
                    .foregroundStyle(AppColor.accentSleep)
            }

            Spacer()

            VStack(spacing: 2) {
                Image(systemName: "hand.tap")
                    .font(.caption)
                    .foregroundStyle(AppColor.text3)
                Text("open app\nto wake")
                    .font(.caption2)
                    .foregroundStyle(AppColor.text3)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppColor.card)
    }
}

// MARK: - Live Activity Widget

/// Registered in the WidgetBundle — renders all Sleep Live Activity surfaces
/// (lock screen + Dynamic Island compact/expanded/minimal).
struct SleepLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SleepActivityAttributes.self) { context in
            SleepLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.title3)
                        .foregroundStyle(AppColor.accentSleep)
                        .padding(.leading, 8)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.startedAt, style: .timer)
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(AppColor.accentSleep)
                        .padding(.trailing, 8)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("\(context.attributes.babyName) is sleeping")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Tap to open app · Wake Up button in app")
                        .font(.caption2)
                        .foregroundStyle(AppColor.text3)
                        .padding(.bottom, 4)
                }
            } compactLeading: {
                Image(systemName: "moon.zzz.fill")
                    .foregroundStyle(AppColor.accentSleep)
                    .padding(.leading, 4)
            } compactTrailing: {
                Text(context.state.startedAt, style: .timer)
                    .monospacedDigit()
                    .foregroundStyle(AppColor.accentSleep)
                    .padding(.trailing, 4)
            } minimal: {
                Image(systemName: "moon.zzz.fill")
                    .foregroundStyle(AppColor.accentSleep)
            }
            .widgetURL(URL(string: "millertime://home"))
            .keylineTint(AppColor.accentSleep)
        }
    }
}
