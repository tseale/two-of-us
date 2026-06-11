import SwiftUI

/// A one-time feature moment shown in the main app: "it learns your rhythm"
/// right after the first feed, when there's real data to make it meaningful.
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
        .onAppear {
            // Seen the moment it appears — a swipe-down still counts, so a
            // spotlight never nags twice.
            SetupProgress.shared.markShown(spotlight)
            revealed = true
        }
    }

    private var ambientStop: AmbientStop {
        switch spotlight {
        case .rhythm:
            AmbientStop(top: AppColor.accentDiaper, bottom: AppColor.accentFeed)
        }
    }

    // MARK: It learns your rhythm

    @ViewBuilder private var rhythmContent: some View {
        OnboardingStepHeader(
            title: "It learns your rhythm",
            subtitle: "Today as a 24-hour ribbon, week-over-week trends, records and patterns — they build with every log."
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

        if BabyIntelligence.isAvailable {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(AppColor.accentFeed)
                Text("Plus a weekly digest, written on your phone — nothing leaves it.")
                    .font(.footnote)
                    .foregroundStyle(AppColor.text2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .onboardingEntrance(revealed, index: 4)
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Button {
                Haptics.tap()
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
