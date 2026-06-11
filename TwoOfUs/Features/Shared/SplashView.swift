import SwiftUI

/// The launch splash. It opens on solid black (matching the static launch screen)
/// and the two parent circles *materialize* like lights coming into focus: each
/// begins large, soft, and faint, then gently contracts, drifts inward, and
/// brightens into place — left first, the right a dreamy beat later. As they
/// converge the stage dawns from black into the onboarding's night-stage ambient,
/// the baby's light is born at their union and breathes once, and the "Two of Us"
/// wordmark fades up. Because the splash ends on the same
/// `AmbientBackground(stop: .nightStage)` the welcome and join pages sit on, the
/// host's crossfade dissolves between two identical backdrops. Honors Reduce
/// Motion by skipping the motion and just fading in.
struct SplashView: View {
    /// Called once the splash has finished; the host fades it away.
    var onComplete: () -> Void

    /// When the splash finished (fade-out start), if it has. The onboarding
    /// welcome page times its splash-pose settle off this, so exactly one mark
    /// is ever on screen during the hand-off.
    static var completedAt: Date?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var babyScale: CGFloat = 1
    @State private var glowOpacity: Double = 0
    @State private var wordmarkOpacity: Double = 0
    @State private var wordmarkOffset: CGFloat = 6

    private let markSize: CGFloat = 240

    // The parents begin oversized, transparent, and drifted gently up-and-out (a
    // little asymmetry so they swirl together rather than mirror); they ease to
    // `.identity` (resting). The baby core stays hidden until they meet, and the
    // stage stays black until the dawn begins. (glowOpacity starts at 0 too, so
    // the first frame is genuinely black.)
    @State private var leftEntry = CradleMark.ParentEntry(
        offset: CGSize(width: -40, height: -44), scale: 1.55, opacity: 0)
    @State private var rightEntry = CradleMark.ParentEntry(
        offset: CGSize(width: 44, height: 30), scale: 1.55, opacity: 0)
    @State private var babyCore: Double = 0
    /// Lifts the black cover off the night-stage ambient as the parents converge,
    /// so the splash's backdrop becomes the welcome page's before the hand-off.
    @State private var stageLit = false

    var body: some View {
        ZStack {
            AmbientBackground(stop: .nightStage)

            // Solid black on the first frame (matching the static launch screen),
            // then dissolves to reveal the ambient underneath.
            Color.black
                .opacity(stageLit ? 0 : 1)
                .ignoresSafeArea()

            CradleMark(size: markSize,
                       babyScale: babyScale,
                       glowOpacity: glowOpacity,
                       leftEntry: leftEntry,
                       rightEntry: rightEntry,
                       babyCoreOpacity: babyCore)

            Text("Two of Us")
                .font(AppFont.hero(26, weight: .semibold))
                .foregroundStyle(AppColor.nightlightCream)
                .opacity(wordmarkOpacity)
                .offset(y: markSize / 2 + 34 + wordmarkOffset)
        }
        .task { await run() }
    }

    @MainActor private func run() async {
        if reduceMotion {
            // No motion: settle the mark on the lit stage instantly, only fade
            // the wordmark.
            leftEntry = .identity
            rightEntry = .identity
            glowOpacity = 1
            babyCore = 1
            stageLit = true
            withAnimation(.easeIn(duration: 0.3)) {
                wordmarkOpacity = 1
                wordmarkOffset = 0
            }
            try? await Task.sleep(for: .seconds(0.9))
            Self.completedAt = .now
            onComplete()
            return
        }

        // Two lights drift home: each parent contracts, brightens, and settles on
        // a long, soft ease — the right trailing the left so it feels like a
        // gathering, not a clap — while the stage slowly dawns out of black.
        withAnimation(.easeInOut(duration: 1.3).delay(0.05)) { leftEntry = .identity }
        withAnimation(.easeInOut(duration: 1.3).delay(0.35)) { rightEntry = .identity }
        withAnimation(.easeInOut(duration: 1.5).delay(0.15)) { stageLit = true }

        // As they overlap, the baby's light is born — glow blooms, core fades in —
        // then a single slow breath, and the wordmark rises softly.
        withAnimation(.easeInOut(duration: 0.9).delay(0.95)) { glowOpacity = 1 }
        withAnimation(.easeOut(duration: 0.6).delay(1.05)) { babyCore = 1 }
        withAnimation(.easeInOut(duration: 0.95).delay(1.15)) { babyScale = 1.06 }
        withAnimation(.easeInOut(duration: 0.7).delay(2.0)) { babyScale = 1.0 }
        withAnimation(.easeOut(duration: 0.7).delay(1.35)) {
            wordmarkOpacity = 1
            wordmarkOffset = 0
        }

        try? await Task.sleep(for: .seconds(2.3))
        Self.completedAt = .now
        onComplete()
    }
}

#Preview {
    SplashView(onComplete: {})
}
