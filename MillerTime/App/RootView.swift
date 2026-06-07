import SwiftUI
import SwiftData

/// Routes to onboarding until a Baby exists, then to the main tabbed UI.
struct RootView: View {
    @Query private var babies: [Baby]

    var body: some View {
        Group {
            if babies.isEmpty {
                OnboardingView()
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
    }
}

#Preview {
    RootView()
        .modelContainer(AppModelContainer.preview)
}
