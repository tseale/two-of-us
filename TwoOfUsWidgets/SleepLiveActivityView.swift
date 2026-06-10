import SwiftUI
import WidgetKit
import ActivityKit

// MARK: - Lock Screen View

/// Full live activity view shown on the lock screen while Miller sleeps.
/// A calm night scene: a glowing moon, an eyebrow, and a large rounded timer over
/// a deep-indigo gradient — the same brand gradient as the in-app "record" hero.
struct SleepLockScreenView: View {
    let context: ActivityViewContext<SleepActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            // Moon with a soft halo.
            ZStack {
                Circle()
                    .fill(AppColor.accentSleep.opacity(0.22))
                    .frame(width: 46, height: 46)
                Image(systemName: "moon.stars.fill")
                    .font(.title2)
                    .foregroundStyle(AppColor.accentSleep)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("\(context.attributes.babyName.uppercased()) IS SLEEPING")
                    .sectionLabelStyle(color: AppColor.accentSleep)

                // `.timer` style counts up automatically — no periodic update push needed.
                Text(context.state.startedAt, style: .timer)
                    .font(AppFont.display(30, weight: .heavy))
                    .foregroundStyle(.white)
            }

            Spacer()

            VStack(spacing: 3) {
                Image(systemName: "hand.tap")
                    .font(.caption)
                Text("open app\nto wake")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white.opacity(0.55))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            LinearGradient(
                colors: [Color(hex: "2A2A4D"), Color(hex: "15151F")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
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
                        .font(AppFont.display(20, weight: .bold, relativeTo: .title3))
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
            .widgetURL(URL(string: "twoofus://home"))
            .keylineTint(AppColor.accentSleep)
        }
    }
}
