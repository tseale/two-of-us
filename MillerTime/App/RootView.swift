import SwiftUI
import SwiftData

/// Routes to onboarding until a Baby exists, then to the home screen.
struct RootView: View {
    @Query private var babies: [Baby]

    var body: some View {
        Group {
            if babies.isEmpty {
                OnboardingView()
            } else {
                HomeView()
            }
        }
        .tint(AppColor.accentFeed)
    }
}

#Preview {
    RootView()
        .modelContainer(AppModelContainer.preview)
}
