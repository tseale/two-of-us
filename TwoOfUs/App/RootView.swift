import SwiftUI
import SwiftData

/// Routes between the three top-level worlds and owns the transitions between
/// them, so no route change ever hard-cuts:
/// - a parent who accepted a share but has no profile yet → the join flow
///   (checked FIRST: right after accepting, the owner's records may not have
///   synced down yet, and the empty-store check would wrongly show owner
///   onboarding — inviting a duplicate baby),
/// - an empty store → owner onboarding,
/// - otherwise → the main tabbed UI.
///
/// Route swaps crossfade, and both setup flows end by handing a `CelebrationData`
/// up here: the opaque celebration overlay covers the screen while the store
/// commit flips the route underneath, then fades away to reveal Home settled.
struct RootView: View {
    @Query private var babies: [Baby]
    @State private var prefs = LocalPrefs.shared
    @State private var celebration: CelebrationData?
    @State private var shareAcceptance = ShareAcceptance.shared
    @State private var storeErrors = StoreErrorCenter.shared

    private var needsJoinProfile: Bool {
        prefs.syncRole == .participant && prefs.myParticipantID == nil
    }

    private enum Route: Equatable { case join, joinSyncing, onboarding, main }

    private var route: Route {
        if needsJoinProfile { .join }
        // A participant whose profile exists but whose baby hasn't synced down
        // yet must never see owner onboarding (they'd create a duplicate baby in
        // the shared zone) — hold on a syncing screen until the records land.
        else if babies.isEmpty && prefs.syncRole == .participant { .joinSyncing }
        else if babies.isEmpty { .onboarding }
        else { .main }
    }

    var body: some View {
        // The demo pill sits in its own row ABOVE the routed content (a VStack, not
        // a floating overlay), so it can never land on the Home header / baby name
        // — and, unlike a top safeAreaInset over the TabView's List, the content
        // below isn't rendered up under the pill and clipped.
        VStack(spacing: 0) {
            if prefs.demoModeEnabled {
                demoBanner
                    .frame(maxWidth: .infinity)   // center the pill in its strip
                    .padding(.bottom, 6)          // breathing room above content
                    .background(AppColor.bg)      // strip matches the app background
            }
            routedContent
        }
        .animation(.easeInOut(duration: 0.35), value: route)
        .animation(.easeInOut(duration: 0.35), value: prefs.demoModeEnabled)
        .tint(AppColor.accentFeed)
        .preferredColorScheme(prefs.appearance.colorScheme)
        // A tapped Feed/Diaper home-screen widget opens the app on this URL;
        // the router stages the sheet for HomeView to present.
        .onOpenURL { DeepLinkRouter.shared.handle($0) }
        .overlay(alignment: .bottom) {
            if let banner = storeErrors.current { errorBanner(banner) }
        }
        .animation(.spring(duration: 0.3), value: storeErrors.current)
        .overlay {
            if let celebration {
                CelebrationView(data: celebration) { dismissCelebration() }
                    // Appears instantly (the same frame the route flips beneath it,
                    // so the swap is never visible), fades away once it has played.
                    .transition(.asymmetric(insertion: .identity, removal: .opacity))
                    .zIndex(2)
            }
        }
        // A failed share accept otherwise strands the joining parent on owner
        // onboarding with no clue the link did anything at all.
        .alert("Couldn't accept the invite", isPresented: acceptFailed) {
            Button("Try Again") { shareAcceptance.retry() }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text(shareAcceptance.failureMessage)
        }
        // The link was tapped on a phone that already has its own log (solo
        // onboarding happened here first). Joining silently would leave two
        // babies in the store — make the replacement an explicit choice.
        .alert("Join the shared log?", isPresented: confirmJoin) {
            Button("Replace & Join", role: .destructive) {
                shareAcceptance.confirmJoinReplacingLocalData()
            }
            Button("Cancel", role: .cancel) { shareAcceptance.cancelJoin() }
        } message: {
            Text("This iPhone already has its own log. Joining replaces everything on this phone — and its iCloud copy — with your co-parent's shared log. This can't be undone.")
        }
    }

    private var acceptFailed: Binding<Bool> {
        Binding(get: { shareAcceptance.failed }, set: { shareAcceptance.failed = $0 })
    }

    private var confirmJoin: Binding<Bool> {
        Binding(get: { shareAcceptance.confirmReplace != nil },
                set: { if !$0 { shareAcceptance.cancelJoin() } })
    }

    /// Handed to the setup flows; they call it right before committing data.
    private func celebrate(_ data: CelebrationData) {
        celebration = data
    }

    /// The active top-level world; crossfades between routes.
    @ViewBuilder private var routedContent: some View {
        ZStack {
            switch route {
            case .join:
                JoinFlowView(onFinished: celebrate)
                    .transition(.opacity)
            case .joinSyncing:
                JoinSyncingView()
                    .transition(.opacity)
            case .onboarding:
                OnboardingView(onFinished: celebrate)
                    .transition(.opacity)
            case .main:
                MainTabView()
                    .transition(.opacity)
            }
        }
    }

    private func dismissCelebration() {
        withAnimation(.easeOut(duration: 0.5)) { celebration = nil }
    }

    /// Transient banner for a write/sync failure the user should know about.
    /// Tap to dismiss; otherwise it clears itself after a few seconds.
    private func errorBanner(_ banner: StoreErrorBanner) -> some View {
        Button { storeErrors.dismiss() } label: {
            Label(banner.message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.medium))
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(AppColor.urgencyAmber.opacity(0.5))
                )
        }
        .buttonStyle(.plain)
        .tint(AppColor.urgencyAmber)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityHint("Double tap to dismiss")
    }

    /// Slim pill marking the demo world; tap to exit back to real data.
    private var demoBanner: some View {
        Button { prefs.demoModeEnabled = false } label: {
            Label("DEMO — tap to exit", systemImage: "theatermasks.fill")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(AppColor.accentFeed.opacity(0.5)))
        }
        .buttonStyle(.plain)
        .tint(AppColor.accentFeed)
        .padding(.top, 4)
        .accessibilityLabel("Exit demo mode")
        .accessibilityHint("You're viewing sample data")
    }
}

/// Home (glance + log), History (trends), Stats (records & fun numbers).
struct MainTabView: View {
    enum Tab: Hashable { case home, history, stats }
    @State private var selection: Tab = MainTabView.initialTab
    @State private var router = DeepLinkRouter.shared

    /// DEBUG-only: `-uiScreen history|stats` launches straight into that tab, for
    /// deterministic screenshot/QA captures. Mirrors the `-forceSpotlight` hook.
    static var initialTab: Tab {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "uiScreen") {
        case "history": return .history
        case "stats": return .stats
        default: return .home
        }
        #else
        return .home
        #endif
    }

    var body: some View {
        TabView(selection: $selection) {
            HomeView()
                .tag(Tab.home)
                .tabItem { Label("Home", systemImage: "house.fill") }
            HistoryView()
                .tag(Tab.history)
                .tabItem { Label("History", systemImage: "chart.bar.xaxis") }
            StatsView()
                .tag(Tab.stats)
                .tabItem { Label("Stats", systemImage: "sparkles") }
        }
        // Collapse the glass tab bar while scrolling so content leads (iOS 26).
        .tabBarMinimizeBehavior(.onScrollDown)
        // A tapped Feed/Diaper widget routes to a log sheet HomeView owns — pull
        // Home on screen first so it's mounted to present it.
        .onChange(of: router.pendingLog) { _, pending in
            if pending != nil { selection = .home }
        }
    }
}

#Preview {
    RootView()
        .modelContainer(AppModelContainer.preview)
}
