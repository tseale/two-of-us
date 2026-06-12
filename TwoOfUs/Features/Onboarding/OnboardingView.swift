import SwiftUI
import SwiftData
import CloudKit

/// First launch (owner): a deliberately small flow — a one-page tour of what
/// the app does (which doubles as the welcome), then three setup steps
/// (baby → you → invite), then the celebration finale. Everything else is
/// deferred: the feeding rhythm and reminders become "Getting set up" quests on
/// Home (`SetupChecklistCard`), and the rhythm/stats story plays later as a
/// one-time contextual spotlight (`SpotlightSheet`) once there's real data to
/// hang it on.
///
/// One TabView holds every page; the ambient backdrop and the CTA bar live
/// outside it in a ZStack, so nothing shifts between pages. All setup data stays
/// in local state and commits once, at Finish — until then the store is empty,
/// `babies.isEmpty` remains the routing gate, and a force-quit restarts cleanly.
struct OnboardingView: View {
    /// Called right before the commit with the celebration to play; `RootView`
    /// covers the screen with it so the route flip underneath is never visible.
    var onFinished: (CelebrationData) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Paging

    private enum Page: Int, CaseIterable {
        case tour, setupBaby, setupYou, invite

        var next: Page { Page(rawValue: rawValue + 1) ?? self }
    }

    @State private var page: Page = .tour
    /// Pages whose entrance has played. Grows only — back-swipes don't replay.
    @State private var revealed: Set<Page>

    // MARK: Intro

    /// Once per process: the tour's staggered entrance plays on first
    /// appearance. Demo-exit rebuilds skip it (content shows settled).
    private static var hasPlayedIntro = false

    @State private var chromeRevealed: Bool

    // MARK: Setup state (committed once, at Finish)

    @State private var babyName = ""
    @State private var dateOfBirth = Date()
    @State private var babyPhotoData: Data?
    @State private var ownerName = ""
    @State private var ownerColorHex = ParticipantColors.palette[0]
    @State private var ownerPhotoData: Data?

    // MARK: Invite state

    @State private var cloudAvailable: Bool?     // nil while checking
    @State private var share: CKShare?
    @State private var showShareSheet = false
    @State private var preparingShare = false
    @State private var didOfferShare = false
    @State private var shareFailed = false

    init(onFinished: @escaping (CelebrationData) -> Void) {
        self.onFinished = onFinished
        var played = Self.hasPlayedIntro
        var initialPage: Page = .tour

        #if DEBUG
        // Dev-only: launch with `-onboardingPage N` (Page rawValue: 1 baby,
        // 2 you, 3 invite) to open straight on a page — for design iteration
        // and screenshots.
        let jump = UserDefaults.standard.integer(forKey: "onboardingPage")
        if jump > 0, let target = Page(rawValue: jump) {
            Self.hasPlayedIntro = true
            played = true
            initialPage = target
        }
        // Dev-only: `-autoFinish 1` prefills the setup and commits shortly after
        // launch — exercises the celebration → Home hand-off without taps.
        if UserDefaults.standard.bool(forKey: "autoFinish") {
            Self.hasPlayedIntro = true
            played = true
            initialPage = .invite
            _babyName = State(initialValue: "Miller")
            _ownerName = State(initialValue: "Taylor")
        }
        #endif

        _page = State(initialValue: initialPage)
        // On a cold launch the first page's entrance plays via `runIntro`;
        // on rebuilds it's visible immediately.
        _revealed = State(initialValue: played ? [initialPage] : [])
        _chromeRevealed = State(initialValue: played)
    }

    private var trimmedBabyName: String { babyName.trimmingCharacters(in: .whitespaces) }
    private var trimmedOwnerName: String { ownerName.trimmingCharacters(in: .whitespaces) }
    private var canFinish: Bool { !trimmedBabyName.isEmpty && !trimmedOwnerName.isEmpty }

    // MARK: Body

    var body: some View {
        ZStack {
            AmbientBackground(stop: ambientStop)

            TabView(selection: $page) {
                OnboardingTourPage(revealed: revealed.contains(.tour))
                    .tag(Page.tour)
                BabyStep(name: $babyName, dateOfBirth: $dateOfBirth, photoData: $babyPhotoData,
                         revealed: revealed.contains(.setupBaby), active: page == .setupBaby)
                    .tag(Page.setupBaby)
                YouStep(name: $ownerName, colorHex: $ownerColorHex, photoData: $ownerPhotoData,
                        revealed: revealed.contains(.setupYou), active: page == .setupYou)
                    .tag(Page.setupYou)
                InviteStep(cloudAvailable: cloudAvailable, didOfferShare: didOfferShare,
                           shareFailed: shareFailed, revealed: revealed.contains(.invite),
                           ownerName: trimmedOwnerName, ownerColorHex: ownerColorHex)
                    .tag(Page.invite)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack {
                Spacer()
                bottomBar
                    .opacity(chromeRevealed ? 1 : 0)
                    .allowsHitTesting(chromeRevealed)
            }
        }
        .ignoresSafeArea(.keyboard)
        .onChange(of: page) { _, new in
            revealed.insert(new)
            if new == .invite { refreshCloudStatus() }
        }
        .task { await runIntro() }
        .task { cloudAvailable = await CloudAccount.isAvailable() }
        #if DEBUG
        .task {
            guard UserDefaults.standard.bool(forKey: "autoFinish") else { return }
            try? await Task.sleep(for: .seconds(1.0))   // let the intro settle first
            finish()
        }
        #endif
        .sheet(isPresented: $showShareSheet, onDismiss: { didOfferShare = true }) {
            if let share { CloudShareView(share: share) }
        }
    }

    /// Each page tints the shared ambient toward its accent.
    private var ambientStop: AmbientStop {
        switch page {
        case .tour:
            AmbientStop(top: AppColor.accentFeed, bottom: AppColor.accentDiaper)
        case .invite:
            AmbientStop(top: AppColor.accentSleep, bottom: AppColor.accentFeed)
        case .setupBaby, .setupYou:
            AmbientStop(subtle: true, top: AppColor.accentFeed, bottom: AppColor.accentSleep)
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        OnboardingBottomBar(
            pageCount: Page.allCases.count,
            pageIndex: page.rawValue,
            primary: primaryConfig,
            secondary: secondaryConfig
        )
    }

    private var primaryConfig: OnboardingBottomBar.Primary {
        switch page {
        case .tour:
            .init(title: "Continue", action: advance)
        case .setupBaby:
            .init(title: "Continue", enabled: !trimmedBabyName.isEmpty, action: advance)
        case .setupYou:
            .init(title: "Continue", enabled: !trimmedOwnerName.isEmpty, action: advance)
        case .invite:
            if cloudAvailable == true && !didOfferShare && !shareFailed {
                .init(title: "Invite my partner", loading: preparingShare, action: prepareShare)
            } else {
                .init(title: "Finish", enabled: canFinish, action: finish)
            }
        }
    }

    private var secondaryConfig: OnboardingBottomBar.Secondary? {
        switch page {
        case .tour:
            // A low-commitment way to look around before committing to setup.
            .init(title: "Explore with sample data", action: startDemo)
        case .invite:
            if !canFinish {
                // The flow is freely swipeable, so names can be missing here —
                // the hint jumps back to whichever step needs attention.
                .init(title: missingHint, prominent: true, action: jumpToMissing)
            } else if cloudAvailable == true && !didOfferShare && !shareFailed {
                .init(title: "Finish — invite later from Settings", action: finish)
            } else {
                nil
            }
        default:
            nil
        }
    }

    private var missingHint: String {
        trimmedBabyName.isEmpty ? "Add your baby's name to finish" : "Add your name to finish"
    }

    // MARK: Actions

    private func advance() {
        Haptics.tap()
        if reduceMotion {
            page = page.next
        } else {
            withAnimation(.easeInOut) { page = page.next }
        }
    }

    private func jumpToMissing() {
        Haptics.tap()
        let target: Page = trimmedBabyName.isEmpty ? .setupBaby : .setupYou
        if reduceMotion {
            page = target
        } else {
            withAnimation(.easeInOut) { page = target }
        }
    }

    private func refreshCloudStatus() {
        Task { cloudAvailable = await CloudAccount.isAvailable() }
    }

    /// The zone-wide share can be created before the baby exists — the records
    /// land in the zone at commit (see `SeedData.createBaby`'s enqueue).
    private func prepareShare() {
        Haptics.tap()
        preparingShare = true
        Task {
            defer { preparingShare = false }
            if let s = try? await SyncManager.shared?.makeShare() {
                share = s
                showShareSheet = true
            } else {
                shareFailed = true
            }
        }
    }

    /// Flip into demo mode: the app swaps to the seeded in-memory store and shows
    /// the main UI with a "tap to exit" banner. Exiting returns here (real store
    /// is still empty) — see `TwoOfUsApp.configure()`.
    private func startDemo() {
        Haptics.tap()
        LocalPrefs.shared.demoModeEnabled = true
    }

    /// The one atomic commit: celebration first (it covers the screen), then the
    /// store write — `RootView`'s gate flips to Home underneath the overlay.
    private func finish() {
        Haptics.success()
        // Reminders are now asked in their own moment (quest / after a feed).
        // Must be off until then: the pref defaults to true, and logging a feed
        // with it on would ambush the user with the AlarmKit dialog.
        LocalPrefs.shared.feedReminderEnabled = false
        SetupProgress.shared.markNewFlowComplete()
        onFinished(.owner(babyName: trimmedBabyName))
        SeedData.createBaby(
            name: trimmedBabyName,
            dateOfBirth: dateOfBirth,
            babyPhoto: babyPhotoData,
            ownerName: trimmedOwnerName,
            ownerColorHex: ownerColorHex,
            ownerPhoto: ownerPhotoData,
            in: context
        )
    }

    // MARK: Intro

    /// Plays the tour's staggered entrance once, on first appearance — one
    /// short beat after launch so the build-in animates against a settled
    /// first frame instead of racing the launch transition.
    @MainActor private func runIntro() async {
        guard !Self.hasPlayedIntro else { return }
        Self.hasPlayedIntro = true

        try? await Task.sleep(for: .seconds(0.15))
        revealed.insert(.tour)
        withAnimation(.easeOut(duration: 0.45).delay(reduceMotion ? 0 : 0.15)) {
            chromeRevealed = true
        }
    }
}

#Preview {
    OnboardingView(onFinished: { _ in })
        .modelContainer(AppModelContainer.make(inMemory: true))
}
