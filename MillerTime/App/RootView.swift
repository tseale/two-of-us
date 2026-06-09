import SwiftUI
import SwiftData

/// Routes to onboarding until a Baby exists; to a join-profile prompt for a
/// parent who accepted a share but hasn't set up their own profile; otherwise to
/// the main tabbed UI.
struct RootView: View {
    @Query private var babies: [Baby]
    @State private var prefs = LocalPrefs.shared

    private var needsJoinProfile: Bool {
        prefs.syncRole == .participant && prefs.myParticipantID == nil
    }

    var body: some View {
        Group {
            if babies.isEmpty {
                OnboardingView()
            } else if needsJoinProfile {
                JoinProfileView()
            } else {
                MainTabView()
            }
        }
        .tint(AppColor.accentFeed)
        .preferredColorScheme(prefs.appearance.colorScheme)
        .overlay(alignment: .top) {
            if prefs.demoModeEnabled { demoBanner }
        }
    }

    /// Slim pill marking the demo world; tap to exit back to real data.
    private var demoBanner: some View {
        Button { prefs.demoModeEnabled = false } label: {
            Label("DEMO — tap to exit", systemImage: "theatermasks.fill")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(.thinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(AppColor.accentFeed.opacity(0.5)))
        }
        .tint(AppColor.accentFeed)
        .padding(.top, 4)
    }
}

/// Home (glance + log), History (trends), Stats (records & fun numbers).
struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
            HistoryView()
                .tabItem { Label("History", systemImage: "chart.bar.xaxis") }
            StatsView()
                .tabItem { Label("Stats", systemImage: "sparkles") }
        }
        // Collapse the glass tab bar while scrolling so content leads (iOS 26).
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

#Preview {
    RootView()
        .modelContainer(AppModelContainer.preview)
}
