import SwiftUI
import WidgetKit
import ActivityKit

/// `Text(timerInterval:)` needs a concrete range end, and the counter freezes
/// once it's reached. A week is far past any real sleep but still comfortably
/// covers a timer a parent forgot to stop — test data routinely carries
/// 39-hour "sleeps" — so the card never sits on a frozen, wrong number.
private let maxSleepDuration: TimeInterval = 7 * 24 * 3600

/// While the sleep runs the range end is effectively unbounded so the timer
/// counts up; once `endedAt` is set (the final content update) the range stops
/// there, freezing the same timer text at the total duration — the "slept X"
/// summary needs no second rendering path.
private func sleepRange(from start: Date, until end: Date? = nil) -> ClosedRange<Date> {
    let cap = start.addingTimeInterval(maxSleepDuration)
    if let end { return start...min(max(end, start.addingTimeInterval(1)), cap) }
    return start...cap
}

// MARK: - Lock Screen View

/// Full live activity view shown on the lock screen while the baby sleeps.
/// A calm night scene: a glowing moon, an eyebrow, and a large rounded timer over
/// a deep-indigo gradient — the same brand gradient as the in-app "record" hero.
///
/// The trailing column is the **next-feed countdown** — "GT IS UP / 1:47:23 /
/// at 2:30 AM" — not a button. The old Wake up ☀️ button was redundant
/// (tapping the card already opens the app, where the active-sleep card keeps
/// its Wake button) and this is the question a parent actually has at 3am:
/// how long do I have, and whose turn is it. The countdown self-ticks; the
/// prediction is snapshotted into ContentState by the app (see
/// `QuickLogger.nextFeedPrediction`) and refreshed on every reconcile. With no
/// prediction the column disappears and the timer breathes.
///
/// **The layout is fixed against the timer strings' widths.** Those strings are
/// not stable: they render `1:23:45` normally, but the system re-renders the
/// card at minute granularity once the screen dims (Always-On / off), where an
/// interval can come back spelled out ("2 hours, 14 minutes") — several times
/// wider. A plain `.timer` style also jumps from `M:SS` to `H:MM:SS` at the
/// one-hour mark. Letting any of that drive layout is what cramped the card
/// and pushed "since 6:03 PM" out of frame.
///
/// Two rules keep one layout working for every one of those strings:
/// 1. The text column claims all slack (`maxWidth: .infinity`), the moon is
///    `fixedSize`, and the next-feed column has a **constant width** — so no
///    content can renegotiate the columns.
/// 2. Every line is `lineLimit(1)` with a `minimumScaleFactor`, so a long
///    string scales down inside its constant box instead of wrapping (which
///    grew the card until it clipped) or stealing width from a neighbor.
struct SleepLockScreenView: View {
    let babyName: String
    let startedAt: Date
    let endedAt: Date?
    let nextFeedAt: Date?
    let nextFeedOwnerName: String?
    let nextFeedOwnerColorHex: String?
    let predictedWakeAt: Date?

    init(babyName: String, startedAt: Date,
         endedAt: Date? = nil,
         nextFeedAt: Date? = nil,
         nextFeedOwnerName: String? = nil,
         nextFeedOwnerColorHex: String? = nil,
         predictedWakeAt: Date? = nil) {
        self.babyName = babyName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.nextFeedAt = nextFeedAt
        self.nextFeedOwnerName = nextFeedOwnerName
        self.nextFeedOwnerColorHex = nextFeedOwnerColorHex
        self.predictedWakeAt = predictedWakeAt
    }

    /// Takes plain values rather than the `ActivityViewContext` so the view can
    /// be previewed and rendered outside ActivityKit — a context can't be
    /// constructed by hand, which is why this layout went so long unverified.
    init(context: ActivityViewContext<SleepActivityAttributes>) {
        self.init(babyName: context.attributes.babyName,
                  startedAt: context.state.startedAt,
                  endedAt: context.state.endedAt,
                  nextFeedAt: context.state.nextFeedAt,
                  nextFeedOwnerName: context.state.nextFeedOwnerName,
                  nextFeedOwnerColorHex: context.state.nextFeedOwnerColorHex,
                  predictedWakeAt: context.state.predictedWakeAt)
    }

    var body: some View {
        VStack(spacing: 0) {
            mainRow
            // The prediction footer: a clock time in the AI gradient, phrased
            // hedged ("likely around") because overnight confidence is what it
            // is — and a clock, not a countdown, so a snapshot that outlives
            // its moment reads gracefully stale instead of frozen at 0:00.
            // Hidden on the ended summary card (the sleep answered it).
            if let predictedWakeAt, endedAt == nil {
                HStack {
                    Text("\(AIGlow.mark) likely awake around \(TimeFormatting.clock(predictedWakeAt))")
                        .font(.caption2)
                        .foregroundStyle(AIGlow.gradient)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .accessibilityLabel("Predicted: likely awake around \(TimeFormatting.clock(predictedWakeAt))")
                    Spacer(minLength: 0)
                }
                .padding(.top, 8)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(AppColor.nightlightCream.opacity(0.12))
                        .frame(height: 1)
                }
                .padding(.top, 8)
            }
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

    private var mainRow: some View {
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
                Text(endedAt == nil ? "\(babyName.uppercased()) IS SLEEPING"
                                    : "\(babyName.uppercased()) SLEPT")
                    .sectionLabelStyle(color: AppColor.accentSleep)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                // Counts up on its own — no periodic push needed. `showsHours`
                // pins the shape to H:MM:SS from second zero, so crossing an
                // hour doesn't silently widen the string mid-sleep. Once the
                // sleep ends, the bounded range freezes this same timer at the
                // total duration (the linger-summary card).
                Text(timerInterval: sleepRange(from: startedAt, until: endedAt),
                     countsDown: false,
                     showsHours: true)
                    .font(AppFont.display(26, weight: .heavy))
                    .foregroundStyle(AppColor.nightlightCream)
                    .lineLimit(1)
                    // Floors low enough that even a dimmed-screen "2 hours, 14
                    // minutes" fits on one line rather than truncating.
                    .minimumScaleFactor(0.5)

                Text(endedAt.map { "until \(TimeFormatting.clock($0))" }
                        ?? "since \(TimeFormatting.clock(startedAt))")
                    .font(.caption2)
                    .foregroundStyle(AppColor.nightlightCream.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let nextFeedAt {
                nextFeedColumn(date: nextFeedAt)
            }
        }
    }

    /// The next-feed countdown. Constant-width (rule 1): the countdown string
    /// has the same dimmed-screen instability as the sleep timer, so it scales
    /// inside a fixed box rather than pushing the text column around.
    private func nextFeedColumn(date: Date) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(nextFeedOwnerName.map { "\($0.uppercased()) IS UP" } ?? "NEXT FEED")
                .sectionLabelStyle(color: ownerColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            // Counts down to the predicted bottle, freezing at 0:00 once it's
            // due — "feed time" — until the next reconcile moves the target.
            // The range starts at the sleep start purely to satisfy
            // ClosedRange (start ≤ now ≤ end while the countdown runs).
            Text(timerInterval: min(startedAt, date)...date,
                 countsDown: true,
                 showsHours: true)
                .font(AppFont.display(18, weight: .bold))
                .foregroundStyle(AppColor.nightlightCream)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text("at \(TimeFormatting.clock(date))")
                .font(.caption2)
                .foregroundStyle(AppColor.nightlightCream.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 92, alignment: .trailing)
    }

    /// The assigned parent's color when the nighttime schedule named one,
    /// else the feed accent — never the sleep periwinkle, so the column reads
    /// as "about the next bottle" at a glance.
    private var ownerColor: Color {
        if let hex = nextFeedOwnerColorHex, !hex.isEmpty { return Color(hex: hex) }
        return AppColor.accentFeed
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
                    Text(timerInterval: sleepRange(from: context.state.startedAt,
                                                   until: context.state.endedAt),
                         countsDown: false,
                         showsHours: true)
                        .font(AppFont.display(20, weight: .bold, relativeTo: .title3))
                        .foregroundStyle(AppColor.accentSleep)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.trailing, 8)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 1) {
                        Text("\(context.attributes.babyName) is sleeping")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if let next = context.state.nextFeedAt {
                            // Static clock time, not a countdown — the center
                            // region is too narrow for a third live timer.
                            Text(islandNextFeedCaption(
                                at: next, owner: context.state.nextFeedOwnerName))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                }
                // No action button in the Island — it stays a calm glance (zzz +
                // running timer). Waking happens from the in-app card, which the
                // whole activity deep-links to.
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

private func islandNextFeedCaption(at date: Date, owner: String?) -> String {
    let time = TimeFormatting.clock(date)
    return owner.map { "next feed \(time) · \($0)" } ?? "next feed \(time)"
}

// MARK: - Previews

#Preview("Lock screen", as: .content, using: SleepActivityAttributes(babyName: "Miller")) {
    SleepLiveActivity()
} contentStates: {
    SleepActivityAttributes.ContentState(startedAt: .now.addingTimeInterval(-45))       // seconds in, no prediction
    SleepActivityAttributes.ContentState(startedAt: .now.addingTimeInterval(-2 * 3600), // daytime prediction
                                         nextFeedAt: .now.addingTimeInterval(45 * 60))
    SleepActivityAttributes.ContentState(startedAt: .now.addingTimeInterval(-3 * 3600), // night: GT's slot
                                         nextFeedAt: .now.addingTimeInterval(107 * 60),
                                         nextFeedOwnerName: "GT",
                                         nextFeedOwnerColorHex: "#E8A0BF",
                                         predictedWakeAt: .now.addingTimeInterval(100 * 60))
    SleepActivityAttributes.ContentState(startedAt: .now.addingTimeInterval(-11 * 3600),// long night, feed due
                                         nextFeedAt: .now.addingTimeInterval(-5 * 60))
    SleepActivityAttributes.ContentState(startedAt: .now.addingTimeInterval(-135 * 60), // ended: linger summary
                                         nextFeedAt: .now.addingTimeInterval(50 * 60),
                                         endedAt: .now.addingTimeInterval(-3 * 60))
}
