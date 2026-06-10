import SwiftUI

/// The launch splash. It opens on solid black (matching the static launch screen,
/// which is now a plain black field) and flies the two parent circles in from
/// opposite off-screen edges; they meet, the baby's light is born at their union,
/// it gives one gentle heartbeat, fades in the wordmark, and dismisses via
/// `onComplete` — settling into the centered mark the onboarding welcome inherits.
/// Honors Reduce Motion by skipping the motion and just fading in.
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

    // Parent circles start off-screen on opposite edges; the baby core stays hidden
    // until they meet. (glowOpacity already starts at 0, so the first frame is black.)
    // ±384 ≈ 1.6× markSize, which clears any iPhone half-width so each circle begins
    // fully off the black field (a literal, since @State defaults can't read members).
    @State private var leftEntry: CGFloat = -384
    @State private var rightEntry: CGFloat = 384
    @State private var babyCore: Double = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CradleMark(size: markSize,
                       babyScale: babyScale,
                       glowOpacity: glowOpacity,
                       leftEntryOffsetX: leftEntry,
                       rightEntryOffsetX: rightEntry,
                       babyCoreOpacity: babyCore)

            Text("Two of Us")
                .font(AppFont.hero(26, weight: .semibold))
                .foregroundStyle(.white)
                .opacity(wordmarkOpacity)
                .offset(y: markSize / 2 + 34 + wordmarkOffset)
        }
        .task { await run() }
    }

    @MainActor private func run() async {
        if reduceMotion {
            // No fly-in: settle the mark instantly, only fade the wordmark.
            leftEntry = 0
            rightEntry = 0
            glowOpacity = 1
            babyCore = 1
            withAnimation(.easeIn(duration: 0.3)) {
                wordmarkOpacity = 1
                wordmarkOffset = 0
            }
            try? await Task.sleep(for: .seconds(0.85))
            Self.completedAt = .now
            onComplete()
            return
        }

        // The two parents glide in from opposite edges (slight stagger so it reads
        // as a meeting, not a symmetric clap)…
        withAnimation(.spring(response: 0.6, dampingFraction: 0.78)) { leftEntry = 0 }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.78).delay(0.08)) { rightEntry = 0 }

        // …and as they overlap, the baby's light is born: the glow blooms and the
        // crisp core pops in, then one calm heartbeat and the wordmark fades up.
        withAnimation(.easeInOut(duration: 0.6).delay(0.40)) { glowOpacity = 1 }
        withAnimation(.easeOut(duration: 0.3).delay(0.45)) { babyCore = 1 }
        withAnimation(.easeInOut(duration: 0.6).delay(0.55)) { babyScale = 1.07 }
        withAnimation(.easeInOut(duration: 0.45).delay(1.15)) { babyScale = 1.0 }
        withAnimation(.easeOut(duration: 0.45).delay(0.80)) {
            wordmarkOpacity = 1
            wordmarkOffset = 0
        }

        try? await Task.sleep(for: .seconds(1.5))
        Self.completedAt = .now
        onComplete()
    }
}

#Preview {
    SplashView(onComplete: {})
}
