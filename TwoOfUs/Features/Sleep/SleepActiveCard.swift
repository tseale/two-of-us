import SwiftUI
import UIKit

/// Shown on Home while a sleep timer is running. Elapsed is computed from
/// `startedAt` (never a stored ticking counter), so it survives backgrounding.
struct SleepActiveCard: View {
    let sleep: SleepEvent
    let now: Date
    let onWake: () -> Void
    /// Nil for SNOO sessions — their start time is authoritative from the device.
    var onEditStart: (() -> Void)? = nil

    @Environment(\.openURL) private var openURL

    private var elapsed: String {
        TimeFormatting.duration(from: sleep.startedAt, to: now)
    }

    private var babyName: String { sleep.baby?.name ?? "Baby" }

    private func openCamera() {
        Haptics.tap()
        openURL(BabyCamLink.destination { UIApplication.shared.canOpenURL($0) })
    }

    private var statusLabel: String {
        "\(babyName) is sleeping, \(elapsed), since \(TimeFormatting.clock(sleep.startedAt))\(sleep.isFromSnoo ? ", from SNOO" : "")"
    }

    @ViewBuilder
    private var statusContent: some View {
        Text("💤").font(.system(size: 34))
        Text("\(babyName.uppercased()) IS SLEEPING")
            .sectionLabelStyle(color: AppColor.accentSleep)
        Text(elapsed)
            .font(AppFont.display(48, weight: .heavy))
            .foregroundStyle(AppColor.text)
            .minimumScaleFactor(0.7)
            .lineLimit(1)
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

    var body: some View {
        VStack(spacing: 6) {
            // Combine ONLY the status readout into one element, so the Wake-up
            // button stays a separate, focusable, activatable element for
            // VoiceOver (a card-level combine swallowed it — you couldn't wake
            // the baby with VoiceOver on).
            if let onEditStart {
                VStack(spacing: 6) { statusContent }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(statusLabel)
                    .accessibilityAction(named: "Edit start time", onEditStart)
            } else {
                VStack(spacing: 6) { statusContent }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(statusLabel)
            }

            Button(action: {
                onWake()
                Haptics.success()
            }) {
                Text("Wake up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .background(AppColor.accentSleep, in: RoundedRectangle(cornerRadius: 16))
            .foregroundStyle(.white)
            .padding(.top, 8)
            .accessibilityHint("Ends the sleep timer")
        }
        .frame(maxWidth: .infinity)
        .padding(20)
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
