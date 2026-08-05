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

            HStack(spacing: 10) {
                // Only for SNOO sessions: the camera is pointed at the bassinet,
                // so off-SNOO sleeps (a contact nap, the stroller) would link to
                // a view of an empty crib.
                if sleep.isFromSnoo {
                    Button(action: openCamera) {
                        Image(systemName: "video.fill")
                            .font(.headline)
                            .frame(width: 52)
                            .padding(.vertical, 14)
                    }
                    .background(AppColor.accentSleep.opacity(0.16),
                                in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(AppColor.accentSleep)
                    .accessibilityLabel("View camera")
                    .accessibilityHint("Opens the eufy app")
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
                .accessibilityHint("Ends the sleep timer")
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .glassTile(cornerRadius: 22, tint: AppColor.accentSleep)
    }
}
