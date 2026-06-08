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
