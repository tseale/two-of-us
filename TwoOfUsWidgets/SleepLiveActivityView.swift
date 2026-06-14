import SwiftUI
import WidgetKit
import ActivityKit
import AppIntents

/// `SetSleepIntent` driven to "awake" — the Live Activity's Wake button. The
/// intent runs in-process against the shared App Group store, same as the
/// widget quick-log buttons.
private func wakeIntent() -> SetSleepIntent {
    var intent = SetSleepIntent()
    intent.value = false
    return intent
}

// MARK: - Lock Screen View

/// Full live activity view shown on the lock screen while the baby sleeps.
/// A calm night scene: a glowing moon, an eyebrow, and a large rounded timer over
/// a deep-indigo gradient — the same brand gradient as the in-app "record" hero.
/// Mirrors the in-app `SleepActiveCard`, down to the Wake up ☀️ button.
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
                    .foregroundStyle(AppColor.nightlightCream)

                Text("since \(TimeFormatting.clock(context.state.startedAt))")
                    .font(.caption)
                    .foregroundStyle(AppColor.nightlightCream.opacity(0.6))
            }

            Spacer()

            wakeButton
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            LinearGradient(
                colors: [AppColor.indigoHi, AppColor.indigoNight],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
    }

    /// Ends the sleep right from the lock screen — same solid periwinkle
    /// treatment as the in-app Wake button.
    private var wakeButton: some View {
        Button(intent: wakeIntent()) {
            VStack(spacing: 2) {
                Text("Wake up")
                Text("☀️")
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(AppColor.accentSleep, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                // No action button in the Island — it stays a calm glance (zzz +
                // running timer). Waking happens from the lock-screen Live Activity
                // or the in-app card.
            } compactLeading: {
                // DESIGN.md §9: the compact island reads "💤 23:47".
                Text("💤")
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
