import SwiftUI

/// Shown on Home while a sleep timer is running. Elapsed is computed from
/// `startedAt` (never a stored ticking counter), so it survives backgrounding.
struct SleepActiveCard: View {
    let sleep: SleepEvent
    let now: Date
    let onWake: () -> Void

    private var elapsed: String {
        TimeFormatting.duration(from: sleep.startedAt, to: now)
    }

    private var babyName: String { sleep.baby?.name ?? "Baby" }

    var body: some View {
        VStack(spacing: 6) {
            // Combine ONLY the status readout into one element, so the Wake-up
            // button stays a separate, focusable, activatable element for
            // VoiceOver (a card-level combine swallowed it — you couldn't wake
            // the baby with VoiceOver on).
            VStack(spacing: 6) {
                Text("💤").font(.system(size: 34))
                Text("\(babyName.uppercased()) IS SLEEPING")
                    .sectionLabelStyle(color: AppColor.accentSleep)
                Text(elapsed)
                    .font(AppFont.display(48, weight: .heavy))
                    .foregroundStyle(AppColor.text)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text("since \(TimeFormatting.clock(sleep.startedAt))")
                    .font(.caption)
                    .foregroundStyle(AppColor.text3)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(babyName) is sleeping, \(elapsed), since \(TimeFormatting.clock(sleep.startedAt))")

            Button(action: {
                onWake()
                Haptics.success()
            }) {
                Text("Wake up ☀️")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .background(AppColor.accentSleep, in: RoundedRectangle(cornerRadius: 16))
            .foregroundStyle(.white)
            .padding(.top, 8)
            .accessibilityLabel("Wake up")
            .accessibilityHint("Ends the sleep timer")
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .glassTile(cornerRadius: 22, tint: AppColor.accentSleep)
    }
}
