import SwiftUI

/// The welcome stop of the first-launch flow, plus shared presentational
/// helpers. `OnboardingView` owns paging, the ambient backdrop, and the CTA bar;
/// setup-chapter pages live in `OnboardingSetupSteps.swift`. The old story pages
/// now play as contextual spotlights inside the main app (`SpotlightSheet`).
///
/// Every scrolling page reserves `OnboardingLayout.barClearance` at the bottom so
/// content never sits under the floating bar, and uses `basedOnSize` bounce so
/// short pages feel fixed.

enum OnboardingLayout {
    /// Height of the floating bottom bar (dots + primary + reserved secondary).
    static let barClearance: CGFloat = 160
}

// MARK: - Welcome

/// The hand-off from the launch splash: opens in "splash pose" — the mark and
/// its "Two of Us" wordmark dead-center on the night-stage ambient, exactly
/// matching `SplashView`'s final frame — then settles: mark and wordmark glide
/// up together to the hero pose and the tagline fades in. The wordmark *is* the
/// page's heading (no separate "Welcome to…" title), so the splash's wordmark
/// never fades out and back in. `OnboardingView` drives the two booleans (see
/// `runIntro`).
struct OnboardingWelcomePage: View {
    /// Mark in its settled (hero) pose vs. splash-center pose.
    let markSettled: Bool
    /// Copy visible.
    let revealed: Bool

    var body: some View {
        ZStack {
            // Sits directly on the dark night-stage ambient (near-black in both
            // schemes), so the fixed-white copy and the `.screen`-blended mark
            // always read correctly. Mark + wordmark transform as one group so
            // their splash pose is pixel-identical to `SplashView`.
            ZStack {
                CradleMark(size: 240)
                Text("Two of Us")
                    .font(AppFont.hero(26, weight: .semibold))
                    .foregroundStyle(.white)
                    .offset(y: 240 / 2 + 34)
            }
            .scaleEffect(markSettled ? 0.7 : 1)
            .offset(y: markSettled ? -96 : 0)

            Text("A calm little log for your little one's feeds, sleeps, and diapers — made for one-handed 3am taps.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .offset(y: 96)
                .opacity(revealed ? 1 : 0)
        }
        // Non-scrolling pages must take the pager's size explicitly — the page
        // TabView otherwise sizes them to their ideal width and text overflows.
        .containerRelativeFrame([.horizontal, .vertical])
    }
}

// MARK: - Presentational helpers

/// A round participant avatar with an initial — matches the timeline badge look.
/// The background-colored ring lets two of these overlap cleanly.
struct OnboardingInitialBadge: View {
    let initial: String
    let colorHex: String
    var size: CGFloat = 68

    var body: some View {
        Circle()
            .fill(Color(hex: colorHex))
            .frame(width: size, height: size)
            .overlay(
                Text(initial)
                    .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            )
            .overlay(Circle().strokeBorder(AppColor.bg, lineWidth: 4))
    }
}

/// Slim progress dots for the paged flow; the current page reads as a wider pill.
struct OnboardingPageDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? AppColor.accentFeed : AppColor.separator)
                    .frame(width: i == index ? 20 : 7, height: 7)
            }
        }
        .animation(.easeInOut, value: index)
        .accessibilityHidden(true)
    }
}
