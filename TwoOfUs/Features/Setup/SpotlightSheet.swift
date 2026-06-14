import SwiftUI

/// A one-time feature moment shown in the main app: "The story builds with
/// every log" — right after the first feed, when there's real data to make it
/// meaningful. (The `.rhythm` enum case keeps its raw value for persistence.)
/// Same ambient + entrance language as onboarding, ending in a single "Got it".
struct SpotlightSheet: View {
    let spotlight: SetupSpotlight
    /// Rhythm spotlight only: chains into the rhythm quest sheet (the host
    /// dismisses this sheet and presents that one).
    var onTuneRhythm: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var revealed = false

    var body: some View {
        ZStack {
            AmbientBackground(stop: ambientStop)

            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 36)
                    switch spotlight {
                    case .rhythm: rhythmContent
                    }
                    Spacer(minLength: 16)
                }
                .padding(.horizontal, 28)
            }
            .contentMargins(.bottom, 140, for: .scrollContent)
            .scrollBounceBehavior(.basedOnSize)

            VStack {
                Spacer()
                bottomBar
            }
        }
        .onAppear { revealed = true }
    }

    private var ambientStop: AmbientStop {
        switch spotlight {
        case .rhythm:
            AmbientStop(top: AppColor.accentDiaper, bottom: AppColor.accentFeed)
        }
    }

    // MARK: The story builds with every log

    @ViewBuilder private var rhythmContent: some View {
        OnboardingStepHeader(
            title: "The story builds with every log",
            subtitle: "Today as a 24-hour ribbon, week-over-week trends, records, milestones and a both-of-you split — they grow with every log."
        )
        .onboardingEntrance(revealed)

        VStack(spacing: 14) {
            MockRibbonCard()
                .onboardingEntrance(revealed, index: 1)
            MockTrendCard(progress: revealed ? 1 : 0)
                .onboardingEntrance(revealed, index: 2)
            MockNightMVPCard()
                .onboardingEntrance(revealed, index: 3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A 24-hour ribbon of the day, a rising longest-sleep trend, and a weekly Night MVP.")

        // Tease the shareable recap — the new delight payoff of all that logging.
        teaser(icon: "square.and.arrow.up", tint: AppColor.accentSleep, index: 4,
               text: "Share a weekly recap — a card made for the grandparents.")

        if BabyIntelligence.isAvailable {
            teaser(icon: "sparkles", tint: AppColor.accentFeed, index: 5,
                   text: "Plus a weekly digest, written on your phone — nothing leaves it.")
        }
    }

    private func teaser(icon: String, tint: Color, index: Int, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text)
                .font(.footnote)
                .foregroundStyle(AppColor.text2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .onboardingEntrance(revealed, index: index)
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Button {
                Haptics.tap()
                // Mark seen on explicit acknowledgment, not on appear — a stray
                // swipe-away before reading lets it return rather than burning
                // the one-shot. (One-prompt-per-session still prevents nagging.)
                SetupProgress.shared.markShown(spotlight)
                dismiss()
            } label: {
                Text("Got it")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(AppColor.accentFeed, in: Capsule())
            }
            .buttonStyle(PressableTileStyle())

            if spotlight == .rhythm, let onTuneRhythm {
                Button {
                    Haptics.tap()
                    SetupProgress.shared.markShown(spotlight)
                    onTuneRhythm()
                } label: {
                    Text("Tune your rhythm")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .tint(AppColor.accentFeed)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

#Preview("Rhythm") {
    SpotlightSheet(spotlight: .rhythm, onTuneRhythm: {})
}

#Preview("Rhythm · dark") {
    SpotlightSheet(spotlight: .rhythm)
        .preferredColorScheme(.dark)
}
