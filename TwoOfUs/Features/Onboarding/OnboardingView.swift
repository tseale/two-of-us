import SwiftUI
import SwiftData
import CloudKit

/// First launch (owner): a deliberately small flow — welcome, a one-page tour of
/// what the app does, then three setup steps (baby → you → invite), then the
/// celebration finale. Everything else is deferred: the feeding rhythm and
/// reminders become "Getting set up" quests on Home (`SetupChecklistCard`), and
/// the rhythm/stats story plays later as a one-time contextual spotlight
/// (`SpotlightSheet`) once there's real data to hang it on.
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
        case welcome, tour, setupBaby, setupYou, invite

        var next: Page { Page(rawValue: rawValue + 1) ?? self }
    }

    @State private var page: Page = .welcome
    /// Pages whose entrance has played. Grows only — back-swipes don't replay.
    @State private var revealed: Set<Page> = []

    // MARK: Welcome intro (splash continuity)

    /// Once per process: the welcome page opens in splash pose and settles after
    /// the launch splash above has fully faded. Demo-exit rebuilds skip it.
    private static var hasPlayedIntro = false

    @State private var markSettled: Bool
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

        #if DEBUG
        // Dev-only: launch with `-onboardingPage N` (Page rawValue: 1 tour,
        // 2 baby, 3 you, 4 invite) to open straight on a page — for design
        // iteration and screenshots.
        let jump = UserDefaults.standard.integer(forKey: "onboardingPage")
        if jump > 0, let target = Page(rawValue: jump) {
            Self.hasPlayedIntro = true
            played = true
            _page = State(initialValue: target)
            _revealed = State(initialValue: [target])
        }
        // Dev-only: `-autoFinish 1` prefills the setup and commits shortly after
        // launch — exercises the celebration → Home hand-off without taps.
        if UserDefaults.standard.bool(forKey: "autoFinish") {
            Self.hasPlayedIntro = true
            played = true
            _page = State(initialValue: .invite)
            _revealed = State(initialValue: [.invite])
            _babyName = State(initialValue: "Miller")
            _ownerName = State(initialValue: "Taylor")
        }
        #endif

        _markSettled = State(initialValue: played)
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
                OnboardingWelcomePage(markSettled: markSettled, revealed: chromeRevealed)
                    .tag(Page.welcome)
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
            try? await Task.sleep(for: .seconds(3.0))   // let the splash finish first
            finish()
        }
        #endif
        .sheet(isPresented: $showShareSheet, onDismiss: { didOfferShare = true }) {
            if let share { CloudShareView(share: share) }
        }
    }

    /// Each page tints the shared ambient toward its accent; the welcome page
    /// keeps the dark night stage the mark needs.
    private var ambientStop: AmbientStop {
        switch page {
        case .welcome:
            .nightStage
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
        case .welcome:
            .init(title: "Begin", action: advance)
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
        case .welcome:
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

    // MARK: Welcome intro

    /// The welcome page's first frame matches the splash's final frame exactly
    /// (centered mark on the night-stage ambient); once the splash has faded, the
    /// mark glides to its hero pose and the copy + chrome fade in. Under Reduce
    /// Motion the mark never moves — the splash crossfades straight to the
    /// settled pose.
    @MainActor private func runIntro() async {
        guard !Self.hasPlayedIntro else { return }
        Self.hasPlayedIntro = true

        if reduceMotion { markSettled = true }

        // Settle just after the splash overlay is fully gone (it fades for 0.35s
        // once it completes), so there is exactly one mark on screen. If the
        // splash finished a while ago (e.g. exiting a demo that launched cold),
        // skip the splash pose entirely.
        let settleDelay: TimeInterval
        if let done = SplashView.completedAt {
            let elapsed = Date().timeIntervalSince(done)
            if elapsed > 1.0 {
                markSettled = true
                chromeRevealed = true
                return
            }
            settleDelay = max(0, 0.45 - elapsed)
        } else {
            // No splash timestamp yet (the usual cold launch — this task starts
            // before the splash completes): wait out the splash's run so the mark
            // glides up just as the splash fades. Mirrors SplashView's durations
            // (~2.3s motion / ~0.9s reduce) plus the hand-off buffer.
            settleDelay = reduceMotion ? 1.4 : 2.75
        }
        try? await Task.sleep(for: .seconds(settleDelay))

        if reduceMotion {
            withAnimation(.easeOut(duration: 0.4)) { chromeRevealed = true }
            return
        }

        withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) { markSettled = true }
        withAnimation(.easeOut(duration: 0.45).delay(0.25)) { chromeRevealed = true }
    }
}

#Preview {
    OnboardingView(onFinished: { _ in })
        .modelContainer(AppModelContainer.make(inMemory: true))
}
