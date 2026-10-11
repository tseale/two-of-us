import SwiftUI

/// The launch moment: an opaque overlay `RootView` mounts above everything, so
/// a CloudKit fetch happens behind a held curtain instead of under a parent's
/// thumb (overnight events landing mid-tap used to shift the Home list right
/// as it was touched). While it's mounted nothing underneath is tappable; it
/// fades away only once the fetch has settled — or the time cap says stop
/// waiting.
///
/// Two styles of the same moment:
/// - `.coldLaunch` opens exactly where the static launch screen left off (the
///   same plain `LaunchBackground` color), then the `CradleMark` plays its
///   story in miniature: the two parents drift in and converge, the baby's
///   light blooms where they overlap, the wordmark settles beneath — and the
///   light breathes softly while the fetch runs. The whole scene then lifts
///   slightly and dissolves into the app, Home already settled.
/// - `.resume` is the condensed cut for coming back after hours away (the app
///   process was alive the whole time, so there's no launch screen to pick up
///   from): the same gesture at roughly double speed over a shorter hold —
///   familiar, not ceremonial.
///
/// Timing: never shorter than `minHold` (a flash-and-gone splash reads like a
/// glitch), never longer than the cap (content beats completeness — late
/// events can land in a settled list). A first-ever launch holds a touch
/// longer before easing into onboarding; every other launch stays snappy.
///
/// A staged widget action (tapping "log a feed" from the home screen) always
/// wins over the curtain: mounted into one it bows out instantly, and one
/// arriving mid-play cuts straight to the dissolve — a parent holding a baby
/// asked for a sheet, not a brand moment.
struct LaunchOverlay: View {
    enum Style { case coldLaunch, resume }

    /// Once per process: `RootView` is torn down and rebuilt (`.id`) when demo
    /// mode toggles the container, and the launch moment must not replay on
    /// what looks to the user like a simple mode switch. (Resume replays are
    /// driven explicitly by `RootView`, which re-mounts the overlay itself.)
    @MainActor static var hasPlayed = false

    var style: Style = .coldLaunch
    /// This launch is headed into owner onboarding (empty store, first ever
    /// run) — hold a beat longer; there's no log to hurry back to.
    var firstRun = false
    /// Called after the dissolve has fully completed; the host removes the
    /// overlay. Removal (not opacity) is what re-enables interaction, so the
    /// screen stays tap-proof through every frame of the transition.
    var onFinished: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Everything starts dark/apart and converges; `enter()` animates toward
    // the mark's resting pose, `reveal()` dissolves the lot.
    @State private var leftEntry = CradleMark.ParentEntry(
        offset: CGSize(width: -18, height: 4), scale: 0.92, opacity: 0)
    @State private var rightEntry = CradleMark.ParentEntry(
        offset: CGSize(width: 18, height: -4), scale: 0.92, opacity: 0)
    @State private var glowOpacity: Double = 0
    @State private var babyCoreOpacity: Double = 0
    @State private var babyScale: CGFloat = 1
    @State private var spotlightOpacity: Double = 0
    @State private var ambientOpacity: Double = 0
    @State private var wordmarkOpacity: Double = 0
    @State private var wordmarkOffset: CGFloat = 8
    @State private var sceneScale: CGFloat = 1
    @State private var sceneOpacity: Double

    @State private var router = DeepLinkRouter.shared
    /// Set by whichever finisher runs first — the timed reveal or a deep-link
    /// cut-short — so the dissolve can never play twice.
    @State private var finishing = false

    private let markSize: CGFloat = 170

    init(style: Style = .coldLaunch, firstRun: Bool = false,
         onFinished: @escaping () -> Void = {}) {
        self.style = style
        self.firstRun = firstRun
        self.onFinished = onFinished
        // Cold launch opens opaque (the launch screen was already this color);
        // a resume curtain appears over live UI, so it washes in instead of
        // hard-cutting. It blocks touches from frame one either way — hit
        // testing comes from `contentShape`, which opacity doesn't affect.
        _sceneOpacity = State(initialValue: style == .resume ? 0 : 1)
    }

    /// The resume cut is the same choreography compressed: every entrance
    /// duration and delay is scaled by this.
    private var tempo: Double { style == .resume ? 0.55 : 1 }

    var body: some View {
        ZStack {
            // The exact color the static launch screen painted — frame one of
            // this overlay is pixel-identical to it, so there's no seam between
            // "iOS showing the launch image" and "the app is alive".
            AppColor.bg.ignoresSafeArea()

            // The nursery mood (soft washes, stars in dark mode) blooms in
            // over the plain base rather than arriving with it.
            AmbientBackground(stop: .nightStage)
                .opacity(ambientOpacity)

            VStack(spacing: 20) {
                CradleMark(
                    size: markSize,
                    babyScale: babyScale,
                    glowOpacity: glowOpacity,
                    leftEntry: leftEntry,
                    rightEntry: rightEntry,
                    babyCoreOpacity: babyCoreOpacity
                )
                // The mark's spotlight is applied here rather than via
                // `staged:` so it can bloom with the parents instead of
                // sitting there before anything exists.
                .background {
                    MarkSpotlight(diameter: markSize * 1.8)
                        .opacity(spotlightOpacity)
                }

                Text("Two of Us")
                    .font(AppFont.hero(28))
                    .foregroundStyle(AppColor.text)
                    .opacity(wordmarkOpacity)
                    .offset(y: wordmarkOffset)
            }
            .scaleEffect(sceneScale)
        }
        .opacity(sceneOpacity)
        // The whole point: a full-screen hit target so nothing underneath can
        // be touched while the UI beneath may still be shifting.
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Two of Us is opening")
        .task { await run() }
        // A widget tap staged mid-curtain: stop holding and dissolve now, so
        // the log sheet isn't presented over a lingering splash.
        .onChange(of: router.pendingLog != nil || router.pendingTab != nil) { _, staged in
            if staged { Task { await finish() } }
        }
    }

    @MainActor private func run() async {
        // Mounted INTO a staged widget action (a feed-widget tap cold-launched
        // the app): skip the moment entirely — the sheet is the content.
        if router.pendingLog != nil || router.pendingTab != nil {
            Self.hasPlayed = true
            onFinished()
            return
        }

        enter()

        let clock = ContinuousClock()
        let start = clock.now
        // Hold for the fetch, but never past the cap — and never release
        // before the minimum, even if sync settles instantly.
        await Self.launchFetchSettled(cap: .seconds(style == .resume ? 2.5 : 3.0))
        // 0.9s lets the cold entrance fully land before the dissolve begins;
        // the first-ever run lingers a touch longer on its way into
        // onboarding, and the resume cut gets the whole thought out by ~0.5s.
        let minHold: Duration = switch style {
        case .resume: .seconds(0.6)
        case .coldLaunch: .seconds(firstRun ? 1.5 : 0.9)
        }
        let elapsed = clock.now - start
        if elapsed < minHold {
            try? await Task.sleep(for: minHold - elapsed)
        }

        await finish()
    }

    /// The single exit door: dissolve, mark played, hand back to the host.
    /// Guarded so the timed reveal and a deep-link cut-short can't both run it.
    @MainActor private func finish() async {
        guard !finishing else { return }
        finishing = true
        await reveal()
        Self.hasPlayed = true
        onFinished()
    }

    /// The entrance: parents converge, the shared light blooms, the name
    /// settles, then the light breathes while we hold.
    @MainActor private func enter() {
        if style == .resume {
            withAnimation(.easeOut(duration: 0.2)) { sceneOpacity = 1 }
        }
        if reduceMotion {
            // Calm fades only — nothing drifts, scales, or breathes.
            leftEntry = .identity
            rightEntry = .identity
            withAnimation(.easeIn(duration: 0.45 * tempo)) {
                spotlightOpacity = 1
                ambientOpacity = 1
                glowOpacity = 1
                babyCoreOpacity = 1
            }
            withAnimation(.easeIn(duration: 0.45 * tempo).delay(0.15 * tempo)) {
                wordmarkOpacity = 1
                wordmarkOffset = 0
            }
            return
        }

        // The whole entrance lands inside the minimum hold (~0.85s cold,
        // ~0.5s resumed), so even the fastest launch plays the complete
        // thought before dissolving.
        withAnimation(.spring(response: 0.75 * tempo, dampingFraction: 0.9)) {
            leftEntry = .identity
            rightEntry = .identity
        }
        withAnimation(.easeInOut(duration: 0.6 * tempo).delay(0.1 * tempo)) {
            spotlightOpacity = 1
            ambientOpacity = 1
        }
        // The light blooms once the circles are visibly overlapping, its crisp
        // core popping just after — the same beat the celebration plays.
        withAnimation(.easeInOut(duration: 0.55 * tempo).delay(0.25 * tempo)) { glowOpacity = 1 }
        withAnimation(.easeOut(duration: 0.35 * tempo).delay(0.4 * tempo)) { babyCoreOpacity = 1 }
        withAnimation(.easeOut(duration: 0.4 * tempo).delay(0.35 * tempo)) {
            wordmarkOpacity = 1
            wordmarkOffset = 0
        }
        // A soft breath on the baby light while we wait — a heartbeat at rest,
        // not a spinner. Starts after the entrance has fully landed.
        withAnimation(
            .easeInOut(duration: 1.1).repeatForever(autoreverses: true).delay(1.0 * tempo)
        ) {
            babyScale = 1.05
        }
    }

    /// The hand-off: the scene swells just slightly as it dissolves — the app
    /// "arrives through" the mark rather than after it.
    @MainActor private func reveal() async {
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.45)) { sceneOpacity = 0 }
            try? await Task.sleep(for: .seconds(0.5))
            return
        }
        // Setting the scale with a fresh animation also retires the breathing
        // loop (a new animation on the same property replaces repeatForever).
        withAnimation(.easeOut(duration: 0.5)) { babyScale = 1 }
        withAnimation(.easeIn(duration: 0.5)) { sceneScale = 1.04 }
        withAnimation(.easeOut(duration: 0.5)) { sceneOpacity = 0 }
        try? await Task.sleep(for: .seconds(0.55))
    }

    /// Resolves when a full launch fetch (both engines) has settled, or `cap`
    /// elapses — whichever comes first. The fetch itself is NOT abandoned at
    /// the cap: it keeps running and its changes land in the settled UI.
    ///
    /// When sync can't deliver anything — never bootstrapped (demo-tainted
    /// process, sync gated) or no iCloud account — this returns right away
    /// instead of letting a doomed fetch burn the whole cap, so a signed-out
    /// device still gets the snappy minimum-hold launch. The account check is
    /// a local daemon query, not a network round-trip.
    private static func launchFetchSettled(cap: Duration) async {
        guard await MainActor.run(body: { SyncManager.shared }) != nil,
              await CloudAccount.isAvailable() else { return }
        var first = AsyncStream<Void> { continuation in
            Task { @MainActor in
                _ = await SyncManager.shared?.handleRemoteNotification()
                continuation.yield()
            }
            Task {
                try? await Task.sleep(for: cap)
                continuation.yield()
            }
        }.makeAsyncIterator()
        _ = await first.next()
    }
}

#Preview("Launch") {
    LaunchOverlay()
}

#Preview("First run · dark") {
    LaunchOverlay(firstRun: true)
        .preferredColorScheme(.dark)
}

#Preview("Resume · dark") {
    LaunchOverlay(style: .resume)
        .preferredColorScheme(.dark)
}
