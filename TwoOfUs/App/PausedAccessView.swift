import SwiftUI

/// Full-screen block shown instead of `MainTabView` while the current user's
/// own `Participant` row is paused. Self-heals — the moment the owner resumes
/// access and it syncs down, `RootView` re-routes back to `MainTabView`
/// automatically, the same mechanism `JoinSyncingView` uses while waiting on
/// the initial sync.
struct PausedAccessView: View {
    var body: some View {
        ZStack {
            AmbientBackground(stop: .nightStage)
            VStack(spacing: 24) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(AppColor.text2)
                VStack(spacing: 10) {
                    Text("Your access is paused")
                        .font(AppFont.hero(24))
                        .foregroundStyle(AppColor.text)
                    Text("A co-parent paused your access to this shared log. You'll get everything back the moment they resume it — no need to do anything here.")
                        .font(.subheadline)
                        .foregroundStyle(AppColor.text2)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            }
        }
    }
}

#Preview {
    PausedAccessView()
}
