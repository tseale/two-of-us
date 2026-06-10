import SwiftUI

/// The launch splash. Its first frame matches the static launch screen exactly
/// (centered mark on black), so the hand-off is seamless; it then gives the baby a
/// single gentle heartbeat + glow bloom, fades in the wordmark, and dismisses via
/// `onComplete`. Honors Reduce Motion by skipping the motion and just fading in.
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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Centered exactly like the launch logo (seamless hand-off).
            CradleMark(size: markSize, babyScale: babyScale, glowOpacity: glowOpacity)

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
            glowOpacity = 1
            withAnimation(.easeIn(duration: 0.3)) {
                wordmarkOpacity = 1
                wordmarkOffset = 0
            }
            try? await Task.sleep(for: .seconds(0.85))
            Self.completedAt = .now
            onComplete()
            return
        }

        // Bloom the glow, fade the wordmark up, and give one calm heartbeat.
        withAnimation(.easeInOut(duration: 0.6)) { glowOpacity = 1 }
        withAnimation(.easeOut(duration: 0.45).delay(0.45)) {
            wordmarkOpacity = 1
            wordmarkOffset = 0
        }
        withAnimation(.easeInOut(duration: 0.7).delay(0.15)) { babyScale = 1.07 }
        withAnimation(.easeInOut(duration: 0.5).delay(0.85)) { babyScale = 1.0 }

        try? await Task.sleep(for: .seconds(1.5))
        Self.completedAt = .now
        onComplete()
    }
}

#Preview {
    SplashView(onComplete: {})
}
