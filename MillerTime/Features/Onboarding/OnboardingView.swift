import SwiftUI
import SwiftData

/// First launch (owner): a short paged story that introduces the app, offers a
/// no-commitment demo, and ends on the setup form (baby + owner profile).
/// Page bodies live in `OnboardingPages.swift`; this owns paging and the CTA bar.
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var page: Page = .welcome

    // Setup fields — lifted here so they survive paging back and forth.
    @State private var babyName = "Miller"
    @State private var dateOfBirth = Date()
    @State private var ownerName = ""
    @State private var ownerColorHex = ParticipantColors.palette[0]

    private enum Page: Int, CaseIterable {
        case welcome, track, sync, setup
        var next: Page { Page(rawValue: rawValue + 1) ?? self }
    }

    private var canContinue: Bool {
        !babyName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !ownerName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The name to greet with, falling back gracefully while the field is empty.
    private var displayBabyName: String {
        let trimmed = babyName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "your little one" : trimmed
    }

    var body: some View {
        ZStack {
            AppColor.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    OnboardingWelcomePage(babyName: displayBabyName)
                        .tag(Page.welcome)
                    OnboardingTrackPage()
                        .tag(Page.track)
                    OnboardingSyncPage()
                        .tag(Page.sync)
                    OnboardingSetupPage(babyName: $babyName, dateOfBirth: $dateOfBirth,
                                        ownerName: $ownerName, ownerColorHex: $ownerColorHex)
                        .tag(Page.setup)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                bottomBar
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 14) {
            OnboardingPageDots(count: Page.allCases.count, index: page.rawValue)

            if page == .setup {
                primaryButton(title: "Start", enabled: canContinue, action: finish)
            } else {
                primaryButton(title: "Continue", enabled: true, action: advance)
            }

            // A low-commitment way to look around before committing to setup.
            if page == .welcome {
                Button(action: startDemo) {
                    Text("Explore with sample data")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .tint(AppColor.accentFeed)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private func primaryButton(title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(AppColor.accentFeed.opacity(enabled ? 1 : 0.4), in: Capsule())
        }
        .buttonStyle(PressableTileStyle())
        .disabled(!enabled)
    }

    private func advance() {
        Haptics.tap()
        if reduceMotion {
            page = page.next
        } else {
            withAnimation(.easeInOut) { page = page.next }
        }
    }

    /// Flip into demo mode: the app swaps to the seeded in-memory store and shows
    /// the main UI with a "tap to exit" banner. Exiting returns here (real store
    /// is still empty) — see `MillerTimeApp.configure()`.
    private func startDemo() {
        Haptics.tap()
        LocalPrefs.shared.demoModeEnabled = true
    }

    private func finish() {
        SeedData.createBaby(
            name: babyName.trimmingCharacters(in: .whitespaces),
            dateOfBirth: dateOfBirth,
            ownerName: ownerName.trimmingCharacters(in: .whitespaces),
            ownerColorHex: ownerColorHex,
            in: context
        )
        Haptics.success()
    }
}

#Preview {
    OnboardingView()
        .modelContainer(AppModelContainer.make(inMemory: true))
}
