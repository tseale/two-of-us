import SwiftUI

/// Holding screen while `CloudRestore` checks iCloud for an existing family
/// and, when it finds one, downloads it. Shown INSTEAD of owner onboarding on
/// a fresh install, so a parent setting up a new phone can't mint a duplicate
/// baby before their log arrives. `RootView` re-routes on its own when the
/// restore finishes.
struct RestoreFromCloudView: View {
    @State private var restore = CloudRestore.shared
    /// After this long still downloading, explain and offer Try again.
    private static let patienceWindow: Duration = .seconds(30)
    @State private var tookTooLong = false
    /// Compact only on iPhone Duo's outer display stood like a tent (432 pt
    /// tall) — never on a slab iPhone, which is portrait-only.
    @Environment(\.verticalSizeClass) private var vSize

    var body: some View {
        ZStack {
            AmbientBackground(stop: .nightStage)
            VStack(spacing: 24) {
                // Smaller in the tent pose so the escape hatch still fits.
                CradleMark(size: vSize == .compact ? 100 : 150, staged: true)
                VStack(spacing: 10) {
                    Text(title)
                        .font(AppFont.hero(24))
                        .foregroundStyle(AppColor.text)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(AppColor.text2)
                    SyncingShimmer()
                        .padding(.top, 6)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .onboardingColumn()   // readable on a wide screen; no-op on a phone

                if isRestoring && (restore.failed || tookTooLong) { escapeHatch }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: restore.phase)
        .animation(.easeInOut(duration: 0.3), value: restore.failed)
        // Keyed on the flag so Try again (which resets it) restarts the window.
        .task(id: tookTooLong) {
            guard !tookTooLong else { return }
            try? await Task.sleep(for: Self.patienceWindow)
            guard !Task.isCancelled else { return }
            withAnimation { tookTooLong = true }
        }
    }

    private var isRestoring: Bool {
        if case .restoring = restore.phase { true } else { false }
    }

    private var title: String {
        isRestoring ? "Welcome back" : "Checking iCloud…"
    }

    private var subtitle: String {
        switch restore.phase {
        case .restoring(.owner):
            "Bringing your log over from iCloud."
        case .restoring(.coParent):
            "Reconnecting to your family's shared log."
        case .checking, .finished:
            "Looking for your family's log."
        }
    }

    private var escapeHatch: some View {
        VStack(spacing: 12) {
            Text(restore.failed ? "Couldn't finish downloading." : "This is taking longer than usual.")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppColor.text)
            Text("Make sure this iPhone is online and signed into iCloud, then try again. Everything is safe in iCloud.")
                .font(.footnote)
                .foregroundStyle(AppColor.text2)
                .multilineTextAlignment(.center)
            Button("Try again") {
                tookTooLong = false
                restore.retry()
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.borderedProminent)
            .tint(AppColor.accentFeed)
        }
        .padding(.horizontal, 32)
        .onboardingColumn()
        .padding(.top, 8)
        .transition(.opacity)
    }
}

#Preview {
    RestoreFromCloudView()
}
