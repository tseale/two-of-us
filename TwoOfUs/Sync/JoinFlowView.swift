import SwiftUI
import SwiftData

/// The co-parent's first-run, shown right after accepting the CloudKit share —
/// even while the owner's records are still syncing down (the copy fills in live
/// as they land). Two stops — hello → your profile — in the same visual language
/// as owner onboarding, ending in the same celebration finale. Reminders are
/// offered afterwards, as a "Getting set up" quest on Home.
struct JoinFlowView: View {
    /// Called right before the profile commit; `RootView` covers the screen with
    /// the celebration so the route flip underneath is never visible.
    var onFinished: (CelebrationData) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query private var babies: [Baby]
    @Query(filter: #Predicate<Participant> { $0.isActive }) private var participants: [Participant]

    private enum Page: Int, CaseIterable {
        case hello, profile
        var next: Page { Page(rawValue: rawValue + 1) ?? self }
    }

    @State private var page: Page = .hello
    @State private var revealed: Set<Page> = []
    @State private var name = ""
    @State private var colorHex = ParticipantColors.palette[1]
    @State private var userPickedColor = false
    @State private var photoData: Data?

    private var baby: Baby? { babies.first }
    /// The inviting parent — the first full-access participant that synced in.
    private var owner: Participant? { participants.first { $0.role == .full } }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        ZStack {
            AmbientBackground(stop: ambientStop)

            TabView(selection: $page) {
                helloPage
                    .tag(Page.hello)
                profilePage
                    .tag(Page.profile)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack {
                Spacer()
                bottomBar
            }
        }
        .ignoresSafeArea(.keyboard)
        .onChange(of: page) { _, new in revealed.insert(new) }
        .onChange(of: participants.count) { _, _ in suggestColor() }
        .onAppear {
            revealed.insert(.hello)
            suggestColor()
        }
    }

    private var ambientStop: AmbientStop {
        switch page {
        case .hello:
            .nightStage
        case .profile:
            AmbientStop(subtle: true, top: AppColor.accentSleep, bottom: AppColor.accentFeed)
        }
    }

    // MARK: Hello

    /// Copy resolves progressively as the owner's records sync in; the page
    /// re-renders live the moment the baby or owner lands.
    private var helloPage: some View {
        VStack(spacing: 28) {
            Spacer()
            CradleMark(size: 150)
            VStack(spacing: 10) {
                Text(helloTitle)
                    .font(AppFont.hero(28))
                    .foregroundStyle(.white)
                Text(helloSubtitle)
                    .font(.body)
                    .foregroundStyle(AppColor.nightlightCream.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
                if baby == nil {
                    SyncingShimmer()
                        .padding(.top, 6)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
        // Non-scrolling pages must take the pager's size explicitly — the page
        // TabView otherwise sizes them to their ideal width and text overflows.
        .containerRelativeFrame([.horizontal, .vertical])
        .onboardingEntrance(revealed.contains(.hello))
    }

    private var helloTitle: String {
        if let baby, !baby.name.isEmpty {
            if let owner, !owner.displayName.isEmpty {
                return "\(owner.displayName) invited you to \(baby.name)'s log"
            }
            return "You're in — welcome to \(baby.name)'s log"
        }
        return "You're in"
    }

    private var helloSubtitle: String {
        baby == nil
            ? "Your co-parent's log is syncing to this iPhone…"
            : "Everything they've logged is on its way to this phone."
    }

    // MARK: Profile

    private var profilePage: some View {
        ScrollView {
            VStack(spacing: 18) {
                Spacer(minLength: 16)
                OnboardingStepHeader(
                    title: "And who are you?",
                    subtitle: "Your name and color mark every entry you make."
                )
                .onboardingEntrance(revealed.contains(.profile))

                GlassField(label: "Your name", prompt: "First name", text: $name,
                           active: page == .profile)
                    .onboardingEntrance(revealed.contains(.profile), index: 1)

                GlassRow {
                    ParticipantColorPicker(selection: pickedColor)
                }
                .onboardingEntrance(revealed.contains(.profile), index: 2)

                PhotoPickCard(name: name, colorHex: colorHex, photoData: $photoData)
                    .onboardingEntrance(revealed.contains(.profile), index: 3)
                Spacer(minLength: 16)
            }
            .padding(.horizontal, 28)
        }
        .contentMargins(.bottom, OnboardingLayout.barClearance, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
    }

    private var pickedColor: Binding<String> {
        Binding(
            get: { colorHex },
            set: { colorHex = $0; userPickedColor = true; Haptics.tap() }
        )
    }

    /// Default to the first palette color the synced participants aren't using,
    /// re-suggesting as records land — until the user picks one themselves.
    private func suggestColor() {
        guard !userPickedColor else { return }
        colorHex = ParticipantColors.next(avoiding: participants.map(\.colorHex))
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        OnboardingBottomBar(
            pageCount: Page.allCases.count,
            pageIndex: page.rawValue,
            primary: primaryConfig
        )
    }

    private var primaryConfig: OnboardingBottomBar.Primary {
        switch page {
        case .hello:
            .init(title: "Continue", action: advance)
        case .profile:
            .init(title: "Finish", enabled: !trimmedName.isEmpty, action: finish)
        }
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

    private func finish() {
        Haptics.success()
        // Reminders are offered later as a Home quest. Must be off until then:
        // the pref defaults to true, and logging a feed with it on would ambush
        // the user with the AlarmKit dialog.
        LocalPrefs.shared.feedReminderEnabled = false
        SetupProgress.shared.markNewFlowComplete()
        onFinished(.joiner(babyName: baby?.name ?? ""))
        // New joiners start as guests (least privilege); the owner can promote
        // them to co-parent from Settings → People.
        let me = Participant(displayName: trimmedName, colorHex: colorHex, role: .logger)
        me.photoData = photoData
        context.insert(me)
        try? context.save()
        LocalPrefs.shared.myParticipantID = me.id
        // Held in SyncManager's pending queue if the owner's shared zone hasn't
        // been discovered yet — it uploads the moment the zone is known.
        SyncManager.shared?.enqueueSave([me.id])
    }
}

/// Holding screen for a participant whose profile is done but whose baby hasn't
/// synced down yet (rare: slow first fetch). Self-heals — `RootView` re-routes
/// to the main UI the moment the owner's records land.
struct JoinSyncingView: View {
    var body: some View {
        ZStack {
            AmbientBackground(stop: .nightStage)
            VStack(spacing: 24) {
                CradleMark(size: 150)
                VStack(spacing: 10) {
                    Text("Bringing everything over…")
                        .font(AppFont.hero(24))
                        .foregroundStyle(.white)
                    Text("Your co-parent's log is syncing to this iPhone.")
                        .font(.subheadline)
                        .foregroundStyle(AppColor.nightlightCream.opacity(0.78))
                    SyncingShimmer()
                        .padding(.top, 6)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            }
        }
    }
}

/// A soft pulsing placeholder shown while the owner's records are still syncing.
struct SyncingShimmer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Capsule()
            .fill(.white.opacity(reduceMotion ? 0.14 : (pulse ? 0.22 : 0.08)))
            .frame(width: 140, height: 10)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
            .accessibilityLabel("Syncing")
    }
}

#Preview {
    JoinFlowView(onFinished: { _ in })
        .modelContainer(AppModelContainer.make(inMemory: true))
}
