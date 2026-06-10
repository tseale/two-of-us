import SwiftUI

/// The five story stops in the first-launch flow, plus shared presentational
/// helpers. `OnboardingView` owns paging, the ambient backdrop, and the CTA bar;
/// setup-chapter pages live in `OnboardingSetupSteps.swift`.
///
/// Every scrolling page reserves `OnboardingLayout.barClearance` at the bottom so
/// content never sits under the floating bar, and uses `basedOnSize` bounce so
/// short pages feel fixed.

enum OnboardingLayout {
    /// Height of the floating bottom bar (dots + primary + reserved secondary).
    static let barClearance: CGFloat = 160
}

// MARK: - Welcome

/// The hand-off from the launch splash: opens in "splash pose" — the mark
/// dead-center on the night-stage ambient, exactly matching `SplashView`'s final
/// frame — then settles: the mark glides up and the copy fades in.
/// `OnboardingView` drives the two booleans (see `runIntro`).
struct OnboardingWelcomePage: View {
    /// Mark in its settled (hero) pose vs. splash-center pose.
    let markSettled: Bool
    /// Copy visible.
    let revealed: Bool

    var body: some View {
        ZStack {
            // Sits directly on the dark night-stage ambient (near-black in both
            // schemes), so the fixed-white copy and the `.screen`-blended mark
            // always read correctly.
            CradleMark(size: 240)
                .scaleEffect(markSettled ? 0.7 : 1)
                .offset(y: markSettled ? -96 : 0)

            VStack(spacing: 10) {
                Text("Welcome to Two of Us")
                    .font(AppFont.hero(30))
                    .foregroundStyle(.white)
                Text("A calm little log for your little one's feeds, sleeps, and diapers — made for one-handed 3am taps.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
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

// MARK: - Three things, a tap away

/// Shows the three things you log, styled exactly like the Home tiles.
struct OnboardingTrackPage: View {
    let revealed: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 24)
                OnboardingStepHeader(
                    title: "Three things, a tap away",
                    subtitle: "Feeds, sleep, and diapers — logged in a tap or two, even with a baby in your other arm."
                )
                .onboardingEntrance(revealed)

                GlassEffectContainer(spacing: 12) {
                    VStack(spacing: 12) {
                        OnboardingShowcaseTile(emoji: "🍼", title: "Feed", hint: "log a bottle", tint: AppColor.accentFeed)
                            .onboardingEntrance(revealed, index: 1)
                        OnboardingShowcaseTile(emoji: "💤", title: "Sleep", hint: "start a timer", tint: AppColor.accentSleep)
                            .onboardingEntrance(revealed, index: 2)
                        OnboardingShowcaseTile(emoji: "💩", title: "Diaper", hint: "wet · dirty · both", tint: AppColor.accentDiaper)
                            .onboardingEntrance(revealed, index: 3)
                    }
                }
                Spacer(minLength: 16)
            }
            .padding(.horizontal, 28)
        }
        .contentMargins(.bottom, OnboardingLayout.barClearance, for: .scrollContent)
        .scrollBounceBehavior(.basedOnSize)
    }
}

// MARK: - Everywhere you are

/// Widgets, the Dynamic Island, Siri, Control Center — a loose collage of
/// miniatures so the app's reach is *seen*, not listed.
struct OnboardingEverywherePage: View {
    let revealed: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                Spacer(minLength: 24)
                OnboardingStepHeader(
                    title: "Everywhere you are",
                    subtitle: "Widgets on your lock screen, a live timer in the Dynamic Island, Siri, and Control Center — log and glance without opening the app."
                )
                .onboardingEntrance(revealed)

                VStack(spacing: 20) {
                    MockDynamicIsland()
                        .rotationEffect(.degrees(-2))
                        .onboardingEntrance(revealed, index: 1)
                    HStack(alignment: .center, spacing: 22) {
                        MockSmallWidget()
                            .rotationEffect(.degrees(1.5))
                            .onboardingEntrance(revealed, index: 2)
                        MockControlToggle()
                            .onboardingEntrance(revealed, index: 3)
                    }
                    MockSiriChip()
                        .rotationEffect(.degrees(-1))
                        .onboardingEntrance(revealed, index: 4)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Lock screen widgets, a live sleep timer in the Dynamic Island, Siri phrases, and Control Center controls.")
                Spacer(minLength: 16)
            }
            .padding(.horizontal, 28)
        }
        .contentMargins(.bottom, OnboardingLayout.barClearance, for: .scrollContent)
        .scrollBounceBehavior(.basedOnSize)
    }
}

// MARK: - It learns your rhythm

/// The history/stats story: the day ribbon, a rising trend, the Night MVP —
/// and, on capable hardware, the on-device AI digest.
struct OnboardingRhythmPage: View {
    let revealed: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 24)
                OnboardingStepHeader(
                    title: "It learns your rhythm",
                    subtitle: "Today as a 24-hour ribbon, week-over-week trends, records and patterns."
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
                Spacer(minLength: 16)
            }
            .padding(.horizontal, 28)
        }
        .contentMargins(.bottom, OnboardingLayout.barClearance, for: .scrollContent)
        .scrollBounceBehavior(.basedOnSize)
    }
}

// MARK: - Made for both of you

/// The two-parent / CloudKit story; the badges drift together as the page lands.
struct OnboardingTogetherPage: View {
    let revealed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 120)
                HStack(spacing: revealed || reduceMotion ? -16 : 24) {
                    OnboardingInitialBadge(initial: "A", colorHex: ParticipantColors.palette[0])
                    OnboardingInitialBadge(initial: "J", colorHex: ParticipantColors.palette[1])
                }
                .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.75), value: revealed)
                .onboardingEntrance(revealed)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Two parents")

                OnboardingStepHeader(
                    title: "Made for both of you",
                    subtitle: "Log from either phone and it syncs over iCloud — you both see the latest within seconds. No account, no server."
                )
                .onboardingEntrance(revealed, index: 1)
                Spacer(minLength: 16)
            }
            .padding(.horizontal, 28)
        }
        .contentMargins(.bottom, OnboardingLayout.barClearance, for: .scrollContent)
        .scrollBounceBehavior(.basedOnSize)
    }
}

// MARK: - Presentational helpers

/// A non-interactive twin of the Home log tile — same glass + emoji + copy.
struct OnboardingShowcaseTile: View {
    let emoji: String
    let title: String
    let hint: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            Text(emoji).font(.system(size: 30))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(.title3, design: .rounded).weight(.bold))
                Text(hint).font(.caption).foregroundStyle(AppColor.text2)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(18)
        .glassTile(cornerRadius: 20, tint: tint)
        .foregroundStyle(AppColor.text)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(hint)")
    }
}

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
