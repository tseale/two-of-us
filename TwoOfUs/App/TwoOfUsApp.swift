import SwiftUI
import SwiftData

@main
struct TwoOfUsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    let realContainer = AppModelContainer.shared

    @State private var prefs = LocalPrefs.shared
    /// Throwaway in-memory store used while demo mode is on. Built on entry,
    /// dropped on exit (always a fresh demo).
    @State private var demoContainer: ModelContainer?
    /// Changes whenever `activeContainer` switches, so the `.id` below tears down
    /// and rebuilds the whole tree in lockstep with the container swap — no view
    /// keeps a model object from the previous store.
    @State private var containerToken = UUID()

    init() {
        #if DEBUG
        // Dev-only: `-wipeStore` empties the real store before anything reads
        // it, so onboarding can be exercised repeatedly (UI tests, design
        // iteration) without reinstalling the app.
        if ProcessInfo.processInfo.arguments.contains("-wipeStore") {
            let ctx = realContainer.mainContext
            try? ctx.delete(model: FeedEvent.self)
            try? ctx.delete(model: SleepEvent.self)
            try? ctx.delete(model: DiaperEvent.self)
            try? ctx.delete(model: PlanSlot.self)
            try? ctx.delete(model: PlanOverride.self)
            try? ctx.delete(model: Participant.self)
            try? ctx.delete(model: SharedSettings.self)
            try? ctx.delete(model: Baby.self)
            try? ctx.save()
        }
        // Dev-only: `-seedSampleData` populates a week of events for screenshots.
        if ProcessInfo.processInfo.arguments.contains("-seedSampleData") {
            let ctx = realContainer.mainContext
            SeedData.seedIfNeeded(in: ctx, babyName: "Charlie")
            SeedData.seedSampleEvents(in: ctx)
        }
        // Dev-only: `-previewJoin` simulates a parent who just accepted a share,
        // so the co-parent join flow can be iterated on in the simulator (the real
        // path needs a second iCloud account accepting a CloudKit invite).
        if ProcessInfo.processInfo.arguments.contains("-previewJoin") {
            LocalPrefs.shared.syncRole = .participant
            LocalPrefs.shared.myParticipantID = nil
        }
        // Dev-only: `-resetSetup` reopens the quests/spotlights as if this device
        // just finished the new flow — for iterating on the checklist with data.
        if ProcessInfo.processInfo.arguments.contains("-resetSetup") {
            SetupProgress.shared.resetForTesting()
        }
        #endif

        // Existing installs that onboarded before the quest system (which saw the
        // old full-length flow) must never get quests/spotlights retriggered.
        // Against the real store on purpose — demo data must not grandfather.
        SetupProgress.shared.grandfatherIfNeeded(in: realContainer.mainContext)

        // Build the demo store up front when launching straight into demo mode,
        // so the first frame already shows sample data (no flash of real data).
        if LocalPrefs.shared.demoModeEnabled {
            let c = AppModelContainer.make(inMemory: true)
            DemoData.seed(into: c.mainContext)
            _demoContainer = State(initialValue: c)
        }
    }

    /// The store the UI runs against: the demo store when demo mode is on (falling
    /// back to real until it's built), otherwise the real store.
    private var activeContainer: ModelContainer {
        prefs.demoModeEnabled ? (demoContainer ?? realContainer) : realContainer
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(activeContainer)
                // Teardown is keyed to the container instance, so the swap and the
                // tree rebuild always happen together. The transition pairs with
                // the `withAnimation` around token bumps in `configure()` so demo
                // enter/exit crossfades instead of hard-cutting.
                .id(containerToken)
                .transition(.opacity)
                .task(id: prefs.demoModeEnabled) { configure() }
        }
    }

    /// Builds/drops the demo store and applies the identity override. Sync runs
    /// in BOTH modes: `SyncManager` is bound to the real container for the app's
    /// lifetime (constructed at launch in `AppDelegate`, here only as a safety
    /// net), so the co-parent's changes keep landing in the real store during
    /// demo — `EventStore` gates demo writes from ever reaching the engine.
    /// Only bumps `containerToken` when the active container actually changes,
    /// so a token-driven rebuild doesn't re-trigger itself.
    @MainActor private func configure() {
        if prefs.demoModeEnabled {
            if demoContainer == nil {
                let c = AppModelContainer.make(inMemory: true)
                DemoData.seed(into: c.mainContext)
                demoContainer = c
                withAnimation(.easeInOut(duration: 0.35)) { containerToken = UUID() }
            }
            DemoSession.activate()
        } else {
            DemoSession.deactivate()
            if demoContainer != nil {
                demoContainer = nil
                withAnimation(.easeInOut(duration: 0.35)) { containerToken = UUID() }
            }
        }
        SyncManager.bootstrap(container: realContainer)
    }
}
