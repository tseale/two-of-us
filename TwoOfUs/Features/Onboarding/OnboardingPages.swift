import SwiftUI

/// The welcome and tour stops of the first-launch flow, plus shared
/// presentational helpers. `OnboardingView` owns paging, the ambient backdrop,
/// and the CTA bar; setup-chapter pages live in `OnboardingSetupSteps.swift`.
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

// MARK: - Tour

/// The whole story on one chaptered page: what you log, where the app lives
/// (widgets, Dynamic Island, Siri, Control Center), what it learns, and a sync
/// teaser — replacing the old five-page story block without losing its content.
struct OnboardingTourPage: View {
    let revealed: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                Spacer(minLength: 24)
                OnboardingStepHeader(
                    title: "Three things, a tap away",
                    subtitle: "Feeds, sleep, and diapers — logged in a tap or two, even with a baby in your other arm."
                )
                .onboardingEntrance(revealed)

                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        TourLogTile(emoji: "🍼", title: "Feed", tint: AppColor.accentFeed)
                        TourLogTile(emoji: "💤", title: "Sleep", tint: AppColor.accentSleep)
                        TourLogTile(emoji: "💩", title: "Diaper", tint: AppColor.accentDiaper)
                    }
                }
                .onboardingEntrance(revealed, index: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Log feeds, sleep, and diapers.")

                tourSection("Everywhere you are", index: 2) {
                    VStack(spacing: 14) {
                        MockDynamicIsland()
                            .rotationEffect(.degrees(-2))
                        HStack(alignment: .center, spacing: 18) {
                            MockSmallWidget()
                                .rotationEffect(.degrees(1.5))
                            MockControlToggle()
                        }
                        MockSiriChip()
                            .rotationEffect(.degrees(-1))
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Lock screen widgets, a live sleep timer in the Dynamic Island, Siri phrases, and Control Center controls.")
                }

                tourSection("It learns your rhythm", index: 3) {
                    MockTrendCard(progress: revealed ? 1 : 0)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("A rising longest-sleep trend.")
                }

                HStack(spacing: 10) {
                    Image(systemName: "icloud")
                        .foregroundStyle(AppColor.accentSleep)
                    Text("Logs sync to your co-parent's iPhone in seconds — more on that in a minute.")
                        .font(.footnote)
                        .foregroundStyle(AppColor.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .onboardingEntrance(revealed, index: 4)

                Spacer(minLength: 16)
            }
            .padding(.horizontal, 28)
        }
        .contentMargins(.bottom, OnboardingLayout.barClearance, for: .scrollContent)
        .scrollBounceBehavior(.basedOnSize)
    }

    private func tourSection(_ label: String, index: Int,
                             @ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 14) {
            Text(label).sectionLabelStyle()
            content()
        }
        .onboardingEntrance(revealed, index: index)
    }
}

/// A compact, non-interactive twin of the Home log tiles for the tour row.
private struct TourLogTile: View {
    let emoji: String
    let title: String
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            Text(emoji).font(.system(size: 26))
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(AppColor.text)
        }
        .frame(maxWidth: .infinity, minHeight: 78)
        .glassTile(cornerRadius: 18, tint: tint)
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
