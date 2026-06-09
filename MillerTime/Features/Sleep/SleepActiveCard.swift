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

    var body: some View {
        VStack(spacing: 6) {
            Text("💤").font(.system(size: 34))
            Text("MILLER IS SLEEPING")
                .sectionLabelStyle(color: AppColor.accentSleep)
            Text(elapsed)
                .font(AppFont.display(48, weight: .heavy))
                .foregroundStyle(AppColor.text)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text("since \(TimeFormatting.clock(sleep.startedAt))")
                .font(.caption)
                .foregroundStyle(AppColor.text3)

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
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(AppColor.accentSleep.opacity(0.18), in: RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Miller is sleeping, \(elapsed), since \(TimeFormatting.clock(sleep.startedAt))")
    }
}
