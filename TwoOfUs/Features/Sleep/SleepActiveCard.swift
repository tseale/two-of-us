import SwiftUI
import UIKit

/// Shown on Home while a sleep timer is running. Elapsed is computed from
/// `startedAt` (never a stored ticking counter), so it survives backgrounding.
struct SleepActiveCard: View {
    @State private var wokeAt: Date?

    let sleep: SleepEvent
    let now: Date
    let onWake: () -> Void
    /// Nil for SNOO sessions — their start time is authoritative from the device.
    var onEditStart: (() -> Void)? = nil
    /// `PredictionEngine`'s expected end of this sleep. Nil (AI off, not
    /// enough history, or already past) simply hides the line.
    var predictedWake: Date? = nil
    /// The short layout: the elapsed timer beside the 💤 instead of under it,
    /// ≈ 70 pt shorter, so the Wake slide stays on screen where height is
    /// tight — iPhone Duo's outer display (644 pt of content), its tabletop
    /// controls half and its tent pose. Same content, same order, same slide.
    var compact: Bool = false

    @Environment(\.openURL) private var openURL

    private var elapsed: String {
        TimeFormatting.duration(from: sleep.startedAt, to: now)
    }

    private var babyName: String { sleep.baby?.name ?? "Baby" }

    private func openCamera() {
        Haptics.tap()
        openURL(BabyCamLink.destination { UIApplication.shared.canOpenURL($0) })
    }

    /// "napping" by day, "sleeping" by night or past the nap crossover —
    /// SleepLanguage keeps this card's word in step with the hero and rows.
    private var gerund: String {
        SleepLanguage.gerund(start: sleep.startedAt, now: now)
    }

    private var statusLabel: String {
        var label = "\(babyName) is \(gerund), \(elapsed), since \(TimeFormatting.clock(sleep.startedAt))\(sleep.isFromSnoo ? ", from SNOO" : "")"
        if let predictedWake {
            label += ", predicted wake around \(TimeFormatting.clock(predictedWake))"
        }
        return label
    }

    @ViewBuilder
    private var statusContent: some View {
        Text("💤").font(.system(size: 34))
        eyebrow
        elapsedText(size: 48)
        sinceRow
        if let predictedWake {
            predictedWakeHint(predictedWake)
                .padding(.top, 2)
        }
    }

    /// The short layout's readout: the same lines, set beside the 💤 and
    /// leading-aligned, with a slightly smaller timer.
    private var compactStatusContent: some View {
        HStack(alignment: .center, spacing: 14) {
            Text("💤").font(.system(size: 30))
            VStack(alignment: .leading, spacing: 2) {
                eyebrow
                elapsedText(size: 40)
                sinceRow
                if let predictedWake {
                    predictedWakeHint(predictedWake)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// Whichever readout this card shows.
    @ViewBuilder
    private var status: some View {
        if compact {
            compactStatusContent
        } else {
            VStack(spacing: 6) { statusContent }
        }
    }

    private var eyebrow: some View {
        Text("\(babyName.uppercased()) IS \(gerund.uppercased())")
            .sectionLabelStyle(color: AppColor.accentSleep)
    }

    private func elapsedText(size: CGFloat) -> some View {
        Text(elapsed)
            .font(AppFont.display(size, weight: .heavy))
            .foregroundStyle(AppColor.text)
            .minimumScaleFactor(0.7)
            .lineLimit(1)
    }

    private func predictedWakeHint(_ predictedWake: Date) -> some View {
        AIHintText(text: "predicted wake ~\(TimeFormatting.clock(predictedWake))",
                   font: .caption)
            // The combined status element above already reads the
            // prediction in `statusLabel`.
            .accessibilityHidden(true)
    }

    private var sinceRow: some View {
        HStack(spacing: 6) {
            if let onEditStart {
                // A plain Button still works for sighted taps even inside the
                // accessibilityElement(children: .combine) applied below —
                // combine only affects the accessibility tree, not touch
                // handling — so VoiceOver reachability comes from the
                // .accessibilityAction attached to the combined element instead.
                Button(action: onEditStart) {
                    HStack(spacing: 4) {
                        Text("since \(TimeFormatting.clock(sleep.startedAt))")
                        Image(systemName: "pencil")
                            .font(.caption2)
                    }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(AppColor.text3)
            } else {
                Text("since \(TimeFormatting.clock(sleep.startedAt))")
                    .font(.caption)
                    .foregroundStyle(AppColor.text3)
            }
            // Same tag as the timeline rows: this timer is the SNOO's.
            if sleep.isFromSnoo { SnooTag() }
        }
    }

    /// The status readout as ONE accessibility element, so the Wake-up
    /// button stays a separate, focusable, activatable element for VoiceOver
    /// (a card-level combine swallowed it — you couldn't wake the baby with
    /// VoiceOver on).
    @ViewBuilder
    private var accessibleStatus: some View {
        if let onEditStart {
            status
                .accessibilityElement(children: .combine)
                .accessibilityLabel(statusLabel)
                .accessibilityAction(named: "Edit start time", onEditStart)
        } else {
            status
                .accessibilityElement(children: .combine)
                .accessibilityLabel(statusLabel)
        }
    }

    /// Manual sleeps only: a SNOO session ends itself when the device reports
    /// the wake, so its card never needs — or shows — the wake-up slide. (The
    /// SnooTag above already says whose timer it is.)
    private var wakeSlide: some View {
        SlideToConfirmView(label: "Slide to wake up",
                           tintColor: AppColor.accentSleep,
                           thumbIcon: "sun.max",
                           completionMessage: { "Woke up at \(TimeFormatting.clock($0))" }) {
            withAnimation { wokeAt = .now }
            onWake()
        }
        .accessibilityHint("Ends the sleep timer")
    }

    /// The readout over the slide — every card on a phone.
    private var stackedContent: some View {
        VStack(spacing: 6) {
            accessibleStatus
            if !sleep.isFromSnoo {
                wakeSlide
                    .padding(.top, 8)
            }
        }
    }

    var body: some View {
        Group {
            if compact {
                // A wide short card (iPhone Duo's tabletop controls half, 637 pt
                // across) sets the Wake slide beside the readout instead of under
                // it — ≈ 70 pt shorter again, so the tiles and the card fit the
                // half that lies on the table. Narrower ones (the outer display,
                // a landscape page) don't have the room and stack as before.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 16) {
                        accessibleStatus
                        if !sleep.isFromSnoo {
                            wakeSlide
                                .frame(width: 300)
                        }
                    }
                    stackedContent
                }
            } else {
                stackedContent
            }
        }
        .frame(maxWidth: .infinity)
        .padding(compact ? 16 : 20)
        .glassTile(cornerRadius: 22, tint: AppColor.accentSleep)
        // Corner badge in the same spot and idiom as the log tiles' plus badges.
        // Only for SNOO sessions: the camera is pointed at the bassinet, so
        // off-SNOO sleeps (a contact nap, the stroller) would link to an empty
        // crib. The 44pt frame keeps the tap target honest — the glyph alone is
        // well under it.
        //
        // Applied AFTER .glassTile (not before): the tile's glassEffect(.interactive())
        // installs one shared gesture recognizer across everything inside its
        // subtree, and this button's taps were landing on Wake up's action
        // instead of opening the camera. Stacking the overlay on top of the
        // already-glass-styled card keeps it a fully independent tap target.
        .overlay(alignment: .topTrailing) {
            if sleep.isFromSnoo {
                Button(action: openCamera) {
                    Image(systemName: "video.circle.fill")
                        .font(.system(size: 26))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, AppColor.accentSleep)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(5)
                .accessibilityLabel("View camera")
                .accessibilityHint("Opens the eufy app")
            }
        }
    }
}
