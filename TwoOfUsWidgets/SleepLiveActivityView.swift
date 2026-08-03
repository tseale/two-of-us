import SwiftUI
import WidgetKit
import ActivityKit
import AppIntents

/// `SetSleepIntent` driven to "awake" — the Live Activity's Wake button. The
/// intent runs in-process against the shared App Group store, same as the
/// widget quick-log buttons.
private func wakeIntent() -> SetSleepIntent {
    .driving(asleep: false)
}

/// `Text(timerInterval:)` needs a concrete range end, and the counter freezes
/// once it's reached. A week is far past any real sleep but still comfortably
/// covers a timer a parent forgot to stop — test data routinely carries
/// 39-hour "sleeps" — so the card never sits on a frozen, wrong number.
private let maxSleepDuration: TimeInterval = 7 * 24 * 3600

private func sleepRange(from start: Date) -> ClosedRange<Date> {
    start...start.addingTimeInterval(maxSleepDuration)
}

// MARK: - Lock Screen View

/// Full live activity view shown on the lock screen while the baby sleeps.
/// A calm night scene: a glowing moon, an eyebrow, and a large rounded timer over
/// a deep-indigo gradient — the same brand gradient as the in-app "record" hero.
/// Mirrors the in-app `SleepActiveCard`, down to the Wake up ☀️ button.
///
/// **The layout is fixed against the timer string's width.** That string is not
/// stable: it renders `1:23:45` normally, but the system re-renders the card at
/// minute granularity once the screen dims (Always-On / off), where the elapsed
/// time can come back spelled out ("2 hours, 14 minutes") — several times wider.
/// A plain `.timer` style also jumps from `M:SS` to `H:MM:SS` at the one-hour
/// mark. Letting any of that drive layout is what cramped the card and pushed
/// "since 6:03 PM" out of frame.
///
/// Two rules keep one layout working for every one of those strings:
/// 1. The text column claims all slack (`maxWidth: .infinity`) and the moon and
///    button are `fixedSize`, so the column's width is a constant that content
///    can't renegotiate.
/// 2. Every line is `lineLimit(1)` with a `minimumScaleFactor`, so a long string
///    scales down inside that constant box instead of wrapping (which grew the
///    card until it clipped) or stealing width from the Wake button.
struct SleepLockScreenView: View {
    let babyName: String
    let startedAt: Date

    init(babyName: String, startedAt: Date) {
        self.babyName = babyName
        self.startedAt = startedAt
    }

    /// Takes plain values rather than the `ActivityViewContext` so the view can
    /// be previewed and rendered outside ActivityKit — a context can't be
    /// constructed by hand, which is why this layout went so long unverified.
    init(context: ActivityViewContext<SleepActivityAttributes>) {
        self.init(babyName: context.attributes.babyName, startedAt: context.state.startedAt)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Moon with a soft halo.
            ZStack {
                Circle()
                    .fill(AppColor.accentSleep.opacity(0.22))
                    .frame(width: 40, height: 40)
                Image(systemName: "moon.stars.fill")
                    .font(.title3)
                    .foregroundStyle(AppColor.accentSleep)
            }
            .fixedSize()

            VStack(alignment: .leading, spacing: 2) {
                Text("\(babyName.uppercased()) IS SLEEPING")
                    .sectionLabelStyle(color: AppColor.accentSleep)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                // Counts up on its own — no periodic push needed. `showsHours`
                // pins the shape to H:MM:SS from second zero, so crossing an
                // hour doesn't silently widen the string mid-sleep.
                Text(timerInterval: sleepRange(from: startedAt),
                     countsDown: false,
                     showsHours: true)
                    .font(AppFont.display(26, weight: .heavy))
                    .foregroundStyle(AppColor.nightlightCream)
                    .lineLimit(1)
                    // Floors low enough that even a dimmed-screen "2 hours, 14
                    // minutes" fits on one line rather than truncating.
                    .minimumScaleFactor(0.5)

                Text("since \(TimeFormatting.clock(startedAt))")
                    .font(.caption2)
                    .foregroundStyle(AppColor.nightlightCream.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            wakeButton
                .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
            VStack(spacing: 1) {
                Text("Wake up")
                    .lineLimit(1)
                Text("☀️")
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(AppColor.accentSleep, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                    // Same fixed H:MM:SS shape as the lock screen, so the
                    // expanded island doesn't reflow at the one-hour mark.
                    Text(timerInterval: sleepRange(from: context.state.startedAt),
                         countsDown: false,
                         showsHours: true)
                        .font(AppFont.display(20, weight: .bold, relativeTo: .title3))
                        .foregroundStyle(AppColor.accentSleep)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.trailing, 8)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("\(context.attributes.babyName) is sleeping")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                // No action button in the Island — it stays a calm glance (zzz +
                // running timer). Waking happens from the lock-screen Live Activity
                // or the in-app card.
            } compactLeading: {
                // DESIGN.md §9: the compact island reads "💤 23:47".
                Text("💤")
                    .padding(.leading, 4)
            } compactTrailing: {
                // Deliberately NOT `showsHours` — the compact pill is far too
                // narrow to spend three characters on a leading "0:" for the
                // first hour. It's already width-bounded and scales, so the
                // M:SS → H:MM:SS change costs nothing here.
                Text(context.state.startedAt, style: .timer)
                    .monospacedDigit()
                    .foregroundStyle(AppColor.accentSleep)
                    // A count-up `.timer` reserves width for an unbounded
                    // duration, which stretches the compact island to full
                    // width. Bound it to a sleep-sized H:MM:SS so the pill stays
                    // a tight "💤 1:23:45"; longer stretches scale down to fit.
                    .frame(maxWidth: 56, alignment: .trailing)
                    .minimumScaleFactor(0.7)
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

// MARK: - Previews

#Preview("Lock screen", as: .content, using: SleepActivityAttributes(babyName: "Miller")) {
    SleepLiveActivity()
} contentStates: {
    SleepActivityAttributes.ContentState(startedAt: .now.addingTimeInterval(-45))       // seconds in
    SleepActivityAttributes.ContentState(startedAt: .now.addingTimeInterval(-2 * 3600)) // past an hour
    SleepActivityAttributes.ContentState(startedAt: .now.addingTimeInterval(-11 * 3600))// long night
}
