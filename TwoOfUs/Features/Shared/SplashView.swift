import SwiftUI

/// The launch splash. It opens on solid black (matching the static launch screen)
/// and the two parent circles materialize like lights coming into focus — each
/// contracts, drifts inward, and brightens into place, left first — while the
/// stage dawns from black into the night-stage ambient. The baby's light is born
/// at their union and the "Two of Us" wordmark fades up. The splash ends on the
/// same `AmbientBackground(stop: .nightStage)` the join pages sit on, so that
/// hand-off dissolves between two identical backdrops; owner onboarding
/// crossfades from the night stage into the tour's tinted ambient. Honors
/// Reduce Motion by skipping the motion and just fading in.
struct SplashView: View {
    /// Called once the splash has finished; the host fades it away.
    var onComplete: () -> Void

    /// When the splash finished (fade-out start), if it has. Onboarding times
    /// its opening entrance off this, so the tour builds in just as the splash
    /// fades.
    static var completedAt: Date?

    /// How long `run()` takes before calling `onComplete` — the single source
    /// of truth for anyone (see `OnboardingView.runIntro`) that must wait out
    /// a splash still in flight.
    static func runDuration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0.7 : 1.1
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
    /// so the backdrop is fully lit before the hand-off.
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
        } else {
            // Two lights drift home — each contracts, brightens, and settles,
            // the right trailing the left so it feels like a gathering — while
            // the stage dawns out of black. As they overlap, the baby's light
            // is born and the wordmark rises softly. Brisk timings, soft eases:
            // the pace is snappy but nothing ever snaps.
            withAnimation(.easeInOut(duration: 0.65)) { leftEntry = .identity }
            withAnimation(.easeInOut(duration: 0.65).delay(0.15)) { rightEntry = .identity }
            withAnimation(.easeInOut(duration: 0.7).delay(0.05)) { stageLit = true }
            withAnimation(.easeInOut(duration: 0.5).delay(0.4)) { glowOpacity = 1 }
            withAnimation(.easeOut(duration: 0.4).delay(0.5)) { babyCore = 1 }
            withAnimation(.easeOut(duration: 0.45).delay(0.55)) {
                wordmarkOpacity = 1
                wordmarkOffset = 0
            }
        }

        try? await Task.sleep(for: .seconds(Self.runDuration(reduceMotion: reduceMotion)))
        Self.completedAt = .now
        onComplete()
    }
}

#Preview {
    SplashView(onComplete: {})
}
