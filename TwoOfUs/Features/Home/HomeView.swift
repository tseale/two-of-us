import SwiftUI
import UIKit
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass) private var vSize
    @Environment(\.colorScheme) private var colorScheme

    @Query private var babies: [Baby]
    @Query private var participants: [Participant]
    @Query private var settingsList: [SharedSettings]
    @Query(filter: #Predicate<FeedEvent> { $0.deletedAt == nil }, sort: \FeedEvent.timestamp, order: .reverse)
    private var feeds: [FeedEvent]
    @Query(filter: #Predicate<SleepEvent> { $0.deletedAt == nil }, sort: \SleepEvent.startedAt, order: .reverse)
    private var sleeps: [SleepEvent]
    @Query(filter: #Predicate<DiaperEvent> { $0.deletedAt == nil }, sort: \DiaperEvent.timestamp, order: .reverse)
    private var diapers: [DiaperEvent]
    @Query(filter: #Predicate<NoteEvent> { $0.deletedAt == nil }, sort: \NoteEvent.timestamp, order: .reverse)
    private var noteEvents: [NoteEvent]
    // Daycare-era event types (Brightwheel scaffolding) — interleaved on the
    // timeline and aggregated into the daycare report card.
    @Query(filter: #Predicate<ActivityEvent> { $0.deletedAt == nil }, sort: \ActivityEvent.timestamp, order: .reverse)
    private var activityEvents: [ActivityEvent]
    @Query(filter: #Predicate<MediaEvent> { $0.deletedAt == nil }, sort: \MediaEvent.timestamp, order: .reverse)
    private var mediaEvents: [MediaEvent]
    @Query(filter: #Predicate<CheckEvent> { $0.deletedAt == nil }, sort: \CheckEvent.timestamp, order: .reverse)
    private var checkEvents: [CheckEvent]
    @Query(filter: #Predicate<MedicationEvent> { $0.deletedAt == nil }, sort: \MedicationEvent.timestamp, order: .reverse)
    private var medicationEvents: [MedicationEvent]
    @Query(filter: #Predicate<HealthCheckEvent> { $0.deletedAt == nil }, sort: \HealthCheckEvent.timestamp, order: .reverse)
    private var healthCheckEvents: [HealthCheckEvent]
    @Query(filter: #Predicate<MoodEvent> { $0.deletedAt == nil }, sort: \MoodEvent.timestamp, order: .reverse)
    private var moodEvents: [MoodEvent]
    @Query(filter: #Predicate<PottyEvent> { $0.deletedAt == nil }, sort: \PottyEvent.timestamp, order: .reverse)
    private var pottyEvents: [PottyEvent]
    @Query(filter: #Predicate<MilestoneEvent> { $0.deletedAt == nil }, sort: \MilestoneEvent.timestamp, order: .reverse)
    private var milestoneEvents: [MilestoneEvent]
    @Query(filter: #Predicate<StaffNoteEvent> { $0.deletedAt == nil }, sort: \StaffNoteEvent.timestamp, order: .reverse)
    private var staffNoteEvents: [StaffNoteEvent]
    @Query(filter: #Predicate<PlanSlot> { $0.deletedAt == nil })
    private var planSlots: [PlanSlot]
    @Query(filter: #Predicate<PlanOverride> { $0.deletedAt == nil })
    private var planOverrides: [PlanOverride]

    @State private var activeSheet: ActiveSheet?
    @State private var dropoffBoard: DropoffBoardInfo?
    @State private var editing: TimelineEntry?
    @State private var viewingMedia: MediaViewing?
    @State private var editingSleepStart = false
    @State private var toast: ToastData?
    @State private var showSettings = false
    @State private var questSheet: SetupQuest?
    @State private var spotlight: SetupSpotlight?
    @State private var prefs = LocalPrefs.shared
    @State private var setup = SetupProgress.shared
    @State private var router = DeepLinkRouter.shared
    @State private var snoo = SnooSyncCoordinator.shared
    @State private var brightwheel = BrightwheelManager.shared
    @State private var geofence = DaycareGeofenceManager.shared
    @State private var didApplyDebugScreen = false
    /// The SNOO suggestion whose editor is up (presented from Home, not the card).
    @State private var editingSnoo: SnooSuggestion?
    /// The compact list's full height (content + insets ≈ the display's).
    /// Starts roomy so the first frame matches every slab iPhone.
    @State private var compactFullHeight: CGFloat = .infinity
    /// The compact list's top safe-area inset. Zero where the status bar
    /// isn't across the top — iPhone Duo's outer display, which gets a little
    /// more breathing room — and also wherever the demo-mode pill's row sits
    /// above the list, which is why `compactList` never reads it alone.
    /// Starts large so every slab iPhone is unchanged.
    @State private var compactTopInset: CGFloat = .infinity
    /// Whether the compact list starts at the very top of its window —
    /// nothing above it at all, neither a status bar nor the demo-mode
    /// pill's row. Measured in the same pass as `compactTopInset` and written
    /// with it, so the pair is never half-updated (see `compactList`). Starts
    /// false so every slab iPhone is unchanged.
    @State private var compactStartsAtWindowTop = false
    /// The compact list's side safe-area inset (the larger of the two).
    /// Non-zero only where the system's bars run down one side of an upright
    /// display — iPhone Duo's outer display. Together with the zero top inset
    /// it is what makes the list "the cover" (the top inset alone is also
    /// zero on any iPhone under the demo-mode pill). Starts at zero so every
    /// slab iPhone is unchanged.
    @State private var compactSideInset: CGFloat = 0
    /// The spread's trailing page: the height of its lead items (the Today
    /// card's daycare layer, SNOO suggestions, tonight / up next, the setup
    /// checklist), measured — what is left under them decides whether the
    /// journal fills the page or the page scrolls as a whole. Zero while
    /// there are none.
    @State private var spreadLeadHeight: CGFloat = 0
    /// Start of the current day. Advanced by a task at midnight so the "today"
    /// ribbon, counts, and 24h window refresh even if the app sits foregrounded
    /// across midnight with nothing new logged (a @Query change would otherwise
    /// be the only trigger).
    @State private var dayStart = Calendar.current.startOfDay(for: .now)

    private enum ActiveSheet: String, Identifiable { case feed, diaper, note; var id: String { rawValue } }

    /// What the compact list measures about its own top edge, as one value:
    /// the two readings change together or not at all.
    private struct CompactTopEdge: Equatable {
        /// The list's top safe-area inset.
        let inset: CGFloat
        /// The list starts at the top of its window (nothing sits above it).
        let startsAtWindowTop: Bool
    }

    /// What the photo viewer is showing: one photo from a plain row, or the
    /// whole burst from a grouped row (swiped as pages).
    struct MediaViewing: Identifiable {
        let events: [MediaEvent]
        var id: UUID { events.first?.id ?? UUID() }
    }

    private var baby: Baby? { babies.first }
    private var store: EventStore { EventStore(context: context) }

    /// Shared per-kind tracker switch (defaults on pre-sync/pre-onboarding).
    private func isTracked(_ kind: EventKind) -> Bool {
        settingsList.first?.isEnabled(kind) ?? true
    }
    private var activeSleep: SleepEvent? { sleeps.first { $0.isActive } }

    /// SNOO cards show only where they can act: sleep tracking on, real data
    /// (not demo), and something to suggest.
    private var showSnooSuggestions: Bool {
        SnooFeature.isEnabled && !prefs.demoModeEnabled
            && isTracked(.sleep) && !snoo.suggestions.isEmpty
    }
    /// Interval driving the next-bottle prediction: night spacing when the
    /// bottle after `last` lands in the night window, else the daytime target.
    private func targetFeed(after last: Date) -> TimeInterval {
        settingsList.first?.feedInterval(after: last) ?? TimeInterval(180 * 60)
    }

    /// The family-wide AI switch (Settings → Feeding & Tracking → AI Features).
    private var aiEnabled: Bool {
        settingsList.first?.aiPredictionsEnabled ?? true
    }

    private var ageInDays: Int {
        baby.map { WakeWindow.ageInDays(dateOfBirth: $0.dateOfBirth) } ?? 0
    }

    /// The phone idiom. With a non-compact screen shape — or with the compact
    /// list's cover measurements — that is only ever iPhone Duo: slab iPhones
    /// are always compact and upright, and an iPad (which resolves `.wide`
    /// too) keeps its own layouts exactly. Never a device-model check.
    private var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    var body: some View {
        NavigationStack {
            // One container whose identity never changes holds whichever
            // layout fits the display, and every sheet, task and refresh
            // hangs on it: opening or closing iPhone Duo (or entering Split
            // View) swaps the layout INSIDE it, never the presenter — so a
            // half-filled Feed sheet survives the fold.
            ZStack {
                if ScreenShape.isCompact(horizontal: hSize, vertical: vSize) {
                    compactList
                } else {
                    GeometryReader { proxy in
                        panes(PaneLayout.resolve(in: proxy, horizontal: hSize))
                    }
                    // Home has no text field of its own — every one is in a
                    // sheet — but a sheet's keyboard insets the screen behind
                    // it as well. On iPhone Duo every frame of these layouts
                    // hangs off this reader's height (the spread's foot line
                    // IS its bottom edge), so a note typed in a sheet would
                    // squeeze the pages behind it and rebuild the journal,
                    // losing the parent's place in it. So the Duo's layouts
                    // are measured without the keyboard. iPad ignores no
                    // region at all and is laid out exactly as before.
                    .ignoresSafeArea(isPhone ? .keyboard : [], edges: .bottom)
                }
            }
            // One pull refreshes everything: the daycare feed (Brightwheel)
            // and the other parent's phone (CloudKit), concurrently — the
            // native spinner holds until both finish, and the @Queries
            // re-render the Today card and timeline the moment either lands
            // anything new. No partial refreshes. (Set once here, it reaches
            // every list of every layout.)
            .refreshable {
                async let daycare: Void = {
                    _ = await brightwheel.syncNow(context: context)
                }()
                async let cloud: Void = {
                    _ = await SyncManager.shared?.handleRemoteNotification()
                }()
                _ = await (daycare, cloud)
            }
            .background(AppColor.bg)
            // Settings now lives in the header row (top-aligned with the profile),
            // so the empty inline nav bar would just add dead space above it.
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .feed: FeedSheet(onLogged: { message, undo in
                    showToast(message, undo: undo)
                    feedLogged()
                })
                case .diaper: DiaperSheet(onLogged: { message, undo in
                    showToast(message, accent: AppColor.accentDiaper, undo: undo)
                })
                case .note: NoteSheet(onLogged: { message, undo in
                    showToast(message, accent: AppColor.accentNote, undo: undo)
                })
                }
            }
            .sheet(item: $editing) { entry in
                EditEventSheet(entry: entry)
            }
            .sheet(item: $dropoffBoard) { board in
                DropoffBoardSheet(info: board)
            }
            .sheet(item: $viewingMedia) { viewing in
                MediaViewerSheet(events: viewing.events)
            }
            .sheet(isPresented: $editingSleepStart) {
                if let sleep = activeSleep {
                    SleepStartEditSheet(sleep: sleep)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(item: $questSheet) { quest in
                switch quest {
                case .rhythm: RhythmQuestSheet()
                case .reminders: RemindersQuestSheet(contextLine: reminderContextLine)
                }
            }
            .sheet(item: $spotlight) { s in
                SpotlightSheet(
                    spotlight: s,
                    // Only offer "Tune your rhythm" while the rhythm quest is still
                    // open — hide it once the rhythm's already been customized.
                    onTuneRhythm: setup.incompleteQuests(role: prefs.syncRole, settings: settingsList.first).contains(.rhythm)
                        ? chainIntoRhythmQuest : nil
                )
            }
            // A SNOO card's "Edit": presented from here rather than from the
            // card, because the card moves between panes as iPhone Duo opens
            // and closes and would take its sheet down with it.
            .sheet(item: $editingSnoo) { suggestion in
                SnooSuggestionEditSheet(suggestion: suggestion) { message in
                    toast = ToastData(message: message, accent: AppColor.accentSleep, undo: nil)
                }
            }
            #if DEBUG
            .onAppear {
                // Dev-only: `-forceSpotlight rhythm` presents the spotlight on launch.
                if let raw = UserDefaults.standard.string(forKey: "forceSpotlight"),
                   let forced = SetupSpotlight(rawValue: raw) {
                    spotlight = forced
                }
                // Dev-only: `-uiScreen feed|diaper|settings` presents that sheet once
                // on launch, for deterministic screenshot/QA captures.
                if !didApplyDebugScreen {
                    didApplyDebugScreen = true
                    switch UserDefaults.standard.string(forKey: "uiScreen") {
                    case "feed":     activeSheet = .feed
                    case "diaper":   activeSheet = .diaper
                    case "settings": showSettings = true
                    default:         break
                    }
                }
            }
            #endif
            // (The logged toast rides on the layout itself — the compact list,
            // the pane holding the log tiles, or the foot of the spread's
            // trailing page — so on the inner display it never spans the
            // fold.)
            // A tapped Feed/Diaper widget stages a sheet here: onChange catches a
            // warm launch (Home already up), onAppear a cold launch / tab switch.
            .onChange(of: router.pendingLog) { _, _ in consumeDeepLink() }
            .onAppear { consumeDeepLink() }
            .task { await advanceAtMidnight() }
            // The SNOO poll rides app foreground only (poll-on-open, throttled
            // to 5 minutes inside the coordinator — §7 of the SNOO spec).
            // `.task` covers the cold launch, where the scene can already be
            // `.active` before `onChange` attaches — without it the first open
            // after a SNOO session starts may never poll at all.
            .task {
                snoo.syncOnForeground(context: context)
                brightwheel.syncOnForeground(context: context)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    snoo.syncOnForeground(context: context)
                    brightwheel.syncOnForeground(context: context)
                }
            }
        }
    }

    // MARK: Compact layout (iPhone, iPhone Duo closed, Split View)

    /// The single column every slab iPhone shows — unchanged — and iPhone Duo's
    /// outer display held upright. The one adaptation is height: where the
    /// display is short (the Duo's outer display gives 644 pt of content, vs
    /// ≈ 760 on an iPhone 17), a running sleep uses the short sleep card so the
    /// Wake slide stays on screen.
    ///
    /// Closed, iPhone Duo is the cover: the same page, with two differences
    /// that only ever apply there. A running sleep takes the Sleep tile's
    /// footprint (the card the open pages use), so the Wake slide always
    /// clears the bottom edge; and while he sleeps the hinge — the spine, down
    /// the side away from the system strip — carries a faint bloom of his
    /// light on the otherwise black cover.
    private var compactList: some View {
        let shortCard = compactFullHeight < PaneLayout.roomyHeight
        // iPhone Duo's outer display: nothing sits across the top (the status
        // bar is in the side strip), so the header would hug the display's
        // edge. Give it room above and slightly wider side margins.
        //
        // A zero top inset alone doesn't say so. It reads zero on any device
        // while the demo-mode pill's row sits above the list (the list no
        // longer touches the status bar), and an iPad's compact window is
        // not a phone at all — both keep the margins they always had. So:
        // the phone idiom, and something measured to vouch for the Duo —
        // the side strip, or the list starting at the very top of its
        // window (under the pill it starts below the pill's row).
        //
        // Measured, not read from the demo-mode pref: the pref flips at
        // once and the inset only after the next layout, so leaving demo
        // mode on a slab iPhone would pass through a moment with the pill
        // gone and the inset still reading zero — the Duo's margins for a
        // frame. The window-top reading is taken in the same pass as the
        // inset; on a slab it is never true.
        let duoOuter = compactTopInset < 1 && isPhone
            && (compactSideInset > 0 || compactStartsAtWindowTop)
        let side: CGFloat = duoOuter ? 20 : 16
        // The cover, measured: nothing across the top AND the system's bars
        // down one side of an upright phone. The side strip is what a slab
        // iPhone never has, so everything new here waits on both. (One
        // other window measures the same: a Split View half that sits
        // against the strip on the Duo's open display. It gets the cover's
        // sleep card and bloom too — nothing a size could tell apart, the
        // half and the cover being within a few points of each other. See
        // docs/IPHONE_DUO.md.)
        let cover = duoOuter && compactSideInset > 0
        // The bloom is light on a dark ground, so the list only gives up its
        // own background (and the timeline its row backgrounds) in the dark
        // appearance. A light cover is exactly the list it always was.
        let coverLit = cover && colorScheme == .dark
        return List {
            Section {
                header
                    // Small top inset keeps the profile/settings row off the
                    // status bar now the nav bar is hidden.
                    .listRowInsets(EdgeInsets(top: duoOuter ? 22 : 8, leading: side, bottom: 2, trailing: side))
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    // 12pt matches the tile grid spacing, so the active sleep
                    // card reads as the Sleep row transformed in place.
                    let attendance = daycareAttendance(now: ctx.date)
                    // Performance: bind the computed properties once per tick
                    // instead of re-deriving them at every use below (the
                    // summary was rebuilt four times). Same values: the
                    // arrays they read are fixed for the evaluation (the
                    // summary's own clock read aside, which only matters at
                    // the instant of midnight).
                    let summary = todaySummary
                    let active = activeSleep
                    VStack(spacing: 12) {
                        // ONE hero card, every day — a day-flow strip
                        // with a breathing live-sleep glow and plain
                        // totals. Daycare arrives as layers on the same
                        // base (zone, capsule, recap line, photos), not
                        // as a different card. Between check-in and
                        // check-out the parents aren't the ones logging
                        // — they're watching — so the log tiles sit the
                        // daycare day out; checkout brings them back.
                        heroCard(now: ctx.date, attendance: attendance, summary: summary,
                                 active: active, condensedCaption: shortCard)
                        if attendance == nil {
                            logButtons(now: ctx.date, activeSleep: active)
                        }
                        if let sleep = active {
                            // On the cover, the footprint card (it takes
                            // precedence over the short one).
                            sleepCard(sleep, now: ctx.date, compact: shortCard, footprint: cover)
                                .transition(.opacity.combined(with: .scale(0.96, anchor: .top)))
                        }
                        // SNOO suggestions sit directly under the sleep
                        // button — never pushed down by the schedule card
                        // (§8: present, never modal). Inside the ticking
                        // TimelineView so an in-progress card's elapsed
                        // text stays honest, same as the schedule rows.
                        snooCards(now: ctx.date)
                        // (The old after-pickup daycare report card is
                        // gone: the hero's recap line and its
                        // "daycare 7:30 – 4:30" capsule carry the
                        // finished day all evening.)
                        scheduleRow(now: ctx.date, attendance: attendance)
                    }
                    // Keyed to the sleep state (not withAnimation at the action
                    // sites) so CloudKit- and Siri-initiated starts animate too.
                    .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.8),
                               value: active != nil)
                    // Check-in/out arrives via Brightwheel sync, never a
                    // tap — animate the tiles ↔ strip swap it causes.
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.3),
                               value: attendance != nil)
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: side, bottom: 4, trailing: side))

            // The deferred-setup checklist sits where an empty timeline
            // leaves dead space — the logging UI above stays untouched.
            checklistSection(leading: side, trailing: side)

            if coverLit {
                // The timeline's rows are the one part of this list with a
                // cell background of their own; over the light they would
                // cut it off in a band wherever they scroll.
                timelineSection(leading: side, trailing: side)
                    .listRowBackground(Color.clear)
            } else {
                timelineSection(leading: side, trailing: side)
            }
        }
        .listStyle(.plain)
        // The cover's ground is the field, so the list's own background
        // steps aside for it. (`.automatic` is the list as it always was.)
        .scrollContentBackground(coverLit ? .hidden : .automatic)
        .background {
            if coverLit {
                coverField
            }
        }
        .background(AppColor.bg)
        .loggedToast($toast)
        // The list's top edge: its top inset, and whether it starts at the
        // very top of its window — one reading, one write, so `duoOuter`
        // never sees one without the other.
        .onGeometryChange(for: CompactTopEdge.self) { proxy in
            CompactTopEdge(inset: proxy.safeAreaInsets.top,
                           startsAtWindowTop: proxy.frame(in: .global).minY < 1)
        } action: { edge in
            compactTopInset = edge.inset
            compactStartsAtWindowTop = edge.startsAtWindowTop
        }
        // The system strip: the larger side inset (it can be on either side,
        // depending on which way up the phone is held).
        .onGeometryChange(for: CGFloat.self) { proxy in
            max(proxy.safeAreaInsets.leading, proxy.safeAreaInsets.trailing)
        } action: { inset in
            compactSideInset = inset
        }
        // The display's full height picks the sleep card's layout — measured,
        // never assumed from the device. A clear layer that ignores the safe
        // area spans the whole display whichever way the list itself sizes.
        .background {
            Color.clear
                .ignoresSafeArea()
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    compactFullHeight = height
                }
        }
    }

    /// The cover's ground: true black, and while he sleeps a faint bloom of
    /// his light on the spine. Asked again once a minute: whether a daycare
    /// nap still counts can turn on the clock alone (daycare's assumed
    /// close), with no log or sync to re-render for it.
    private var coverField: some View {
        TimelineView(.everyMinute) { ctx in
            // ctx.date is the minute's start, and stays there when a @Query
            // change re-runs this closure — up to 59 s stale.
            let now = max(ctx.date, .now)
            CradleField(hinge: .spine(.oppositeSystemStrip),
                        sleepingSince: sleepingSince(now: now), now: now)
        }
    }

    /// Any sleep in progress, for the light: a parent-logged (or SNOO) one,
    /// or the nap Brightwheel has started and not yet ended while he is at
    /// daycare — the same pair that makes the Today card's strip glow, so the
    /// hinge light and the strip's bead come on, and go out, together.
    private func sleepingSince(now: Date) -> Date? {
        let liveNap = daycareAttendance(now: now) != nil ? liveNapToday : nil
        return liveNap ?? activeSleep?.startedAt
    }

    // MARK: Roomy layouts (iPhone Duo open or on its side, iPad)

    /// Home on a display with room for two panes — the inner display of iPhone
    /// Duo (and iPad), or its outer display stood on its side. One hierarchy
    /// everywhere, reflowed rather than stretched:
    /// - **wide** (open in landscape, flat or folded like a book): on iPhone
    ///   Duo, the spread — two mirrored phone-width pages (see `spread`). On
    ///   iPad, which resolves wide too, the two panes it always had: the
    ///   "now" page — header, Today card, log tiles, sleep card, what's up
    ///   next — on the leading side; the 24-hour timeline on the trailing
    ///   side.
    /// - **tall** (open in portrait, flat or folded like a laptop on a table):
    ///   everything to look at on the top half; the log tiles and the sleep
    ///   card — the things to tap — on the bottom half, the "stable base"
    ///   Apple's tabletop guidance describes. A feeding-station layout.
    /// - **short** (closed, stood on a nightstand like a tent): the Today card
    ///   on one side, the tiles, sleep card and timeline on the other.
    /// The fold always lands in the gap between panes, flat or folded, so
    /// folding the phone never moves anything.
    @ViewBuilder
    private func panes(_ layout: PaneLayout) -> some View {
        switch layout.shape {
        case .wide:
            // A grid only ever resolves for the phone idiom — iPhone Duo's
            // inner display. iPad (and a reader too narrow for two pages)
            // keeps the panes exactly as they were.
            if let grid = SpreadGrid(layout: layout, isPhone: isPhone) {
                spread(layout, grid: grid)
            } else {
                DividedPanes(layout: layout) {
                    nowPane(layout)
                        .loggedToast($toast)
                } second: {
                    logPane(layout)
                }
            }
        case .tall:
            // Minute-level: the controls pane can empty out on the clock alone
            // (daycare's assumed close), so re-ask once a minute — the
            // per-second ticking stays inside each pane.
            TimelineView(.everyMinute) { ctx in
                // ctx.date is the minute's start, and stays there when a
                // @Query change re-runs this closure — up to 59 s stale. A
                // drop-off or pick-up slid mid-minute is stamped now and must
                // count at once, as it does in the per-second panes.
                if controlsPaneHasContent(now: max(ctx.date, .now)) {
                    DividedPanes(layout: layout) {
                        glancePane(layout, includesTimeline: true)
                    } second: {
                        controlsPane(layout)
                            .loggedToast($toast)
                    }
                } else {
                    // Daycare hours with nothing to tap: the parents are
                    // watching, not logging — the Today card on top, the
                    // day's feed (daycare photos, naps) on the bottom half.
                    DividedPanes(layout: layout) {
                        glancePane(layout, includesTimeline: false)
                    } second: {
                        logPane(layout)
                            .loggedToast($toast)
                    }
                }
            }
        case .short:
            DividedPanes(layout: layout) {
                glancePane(layout, includesTimeline: false)
            } second: {
                tentControlsPane(layout)
                    .loggedToast($toast)
            }
        case .compact:
            compactList
        }
    }

    // MARK: The spread (iPhone Duo open in landscape, flat or like a book)

    /// Home on iPhone Duo's open display in landscape: two mirrored pages,
    /// each exactly a phone-width page, either side of the fold. The leading
    /// page is the cover's page — the baby's name, the Today card, the log
    /// tiles — so what was under your thumb while the phone was closed is
    /// still there when it opens; the day's journal opens beside it. Behind
    /// both, the light (`CradleField`): a pool of each parent's colour behind
    /// each leaf and, whenever he sleeps, his light in the hinge between
    /// them.
    ///
    /// Every frame comes from `SpreadGrid`: the two titles start on one head
    /// line, the first surfaces on one top line, and the last surface of each
    /// page ends on the foot line. Nothing textual or tappable sits between
    /// the pages — only the light crosses the fold, so folding the phone
    /// like a book never puts the crease on a control or a line of text.
    ///
    /// The other tabs draw this same frame — the light, the avatar, the two
    /// titled pages — through `SpreadScaffold`. Home keeps its own: its
    /// light also follows a nap at daycare, which only the queries here can
    /// tell, and its trailing title re-stacks at large text sizes. A change
    /// to the frames here belongs there too.
    private func spread(_ layout: PaneLayout, grid: SpreadGrid) -> some View {
        ZStack(alignment: .topLeading) {
            // The light, behind everything. It takes this reader's frame —
            // the one `PaneLayout` measured, so the crease is `band.midX`
            // whichever side the system strip is on — and paints out through
            // the safe area by itself. Asked again once a minute: a nap turns
            // into a night's sleep on the clock alone (the two-hour
            // crossover), with no log or sync to re-render for it.
            TimelineView(.everyMinute) { ctx in
                // ctx.date is the minute's start, and stays there when a
                // @Query change re-runs this closure — up to 59 s stale.
                let now = max(ctx.date, .now)
                // (`topOffset`: under the demo-mode pill's row the field
                // cannot reach the display's top edge, and softens its own.)
                CradleField(hinge: .verticalCrease(x: layout.band.midX),
                            sleepingSince: sleepingSince(now: now), now: now,
                            topOffset: layout.topOffset)
            }
            // The baby's avatar hangs in the wider outer margin (the side
            // away from the system strip), beside the first title. It is
            // decoration here — the title next to it reads his name.
            if let avatar = grid.avatarFrame {
                Avatar(photoData: baby?.photoData, name: baby?.name ?? "Baby",
                       colorHex: ParticipantColors.babyHex, size: avatar.width)
                    .accessibilityHidden(true)
                    .padding(.leading, avatar.minX)
                    .padding(.top, avatar.minY)
            }
            // Leading page, then trailing page: the order VoiceOver reads.
            spreadNowPage(grid)
            spreadRecentPage(grid)
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
    }

    /// The spread's leading page — the cover's page. Under the title, one
    /// column that never moves between states: the Today card, the Feed and
    /// Diaper tiles, and the Sleep tile or, while a sleep runs, the sleep
    /// card in that tile's exact footprint. The Today card takes up the
    /// page's slack, so the column ends on the foot line. During daycare
    /// hours, with no tiles to show, the Today card is the whole page.
    ///
    /// The page has room for the day — strip and totals — above the tiles
    /// and no more (≈ 18 pt to spare at the default text size). So while the
    /// tiles are here, the Today card's daycare layer (the evening's recap,
    /// a drop-off slide, "staying home") is not: it leads the facing page
    /// (`spreadLeadItems`), which is built to take lead items of any height.
    /// A recap or a slide in the card would push the Sleep tile — at
    /// bedtime, the Wake slide — past the foot line every weekday evening.
    private func spreadNowPage(_ grid: SpreadGrid) -> some View {
        VStack(spacing: 0) {
            PageTitle(baby?.name ?? "Baby",
                      subtitle: baby.map { TimeFormatting.age(from: $0.dateOfBirth) }) {
                settingsButton
            }
            // Air the title keeps under it at any text size…
            .padding(.bottom, SpreadGrid.titleAir)
            // …inside a minimum, never a fixed height: at the default text
            // size the first surface lands on the grid's top line, and a
            // larger size pushes it down instead of overlapping it.
            .frame(minHeight: grid.titleHeight, alignment: .top)
            // What is left of the page, measured, so the column fills it
            // exactly whatever the title took.
            GeometryReader { page in
                // A fixed composition wherever it fits; at a text size
                // where it can't, the page scrolls.
                ScrollView {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let attendance = daycareAttendance(now: ctx.date)
                        let summary = todaySummary
                        let active = activeSleep
                        VStack(spacing: SpreadGrid.surfaceGap) {
                            // The short live caption on the page, always:
                            // the full one is the widest thing in the
                            // totals row, and on a phone-width page it
                            // alone would drop the row to its stacked floor
                            // — ≈ 100 pt taller, off the page. The elapsed
                            // time is on the sleep card under it, or (a
                            // daycare nap) on the journal's live row.
                            heroCard(now: ctx.date, attendance: attendance, summary: summary,
                                     active: active, condensedCaption: true, fillsPage: true,
                                     layers: attendance == nil ? .day : .all)
                            // The tiles and the sleep card keep their own
                            // height whatever the column is offered — a stack
                            // sharing out a fixed height would otherwise
                            // squeeze the tiles toward their floor — so the
                            // Today card is the only thing that stretches.
                            if attendance == nil, hasLogTiles(sleeping: active != nil) {
                                logButtons(now: ctx.date, activeSleep: active)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let sleep = active {
                                sleepCard(sleep, now: ctx.date, compact: false, footprint: true)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .transition(.opacity.combined(with: .scale(0.96, anchor: .top)))
                            }
                        }
                        .modifier(SleepAndDaycareAnimations(sleeping: active != nil,
                                                           attending: attendance != nil,
                                                           reduceMotion: reduceMotion))
                        .frame(minHeight: page.size.height, alignment: .top)
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .frame(width: grid.pageWidth, height: max(grid.foot - grid.headY, 0), alignment: .top)
        // One page is read to its end before the other begins.
        .accessibilityElement(children: .contain)
        .padding(.leading, grid.leadingPage.minX)
        .padding(.top, grid.headY)
    }

    /// Whether `logButtons` has a tile to show at all: a paused tracker hides
    /// its tile, and the Sleep tile steps aside for the running-sleep card.
    /// With none, the spread leaves the row out rather than keep an empty one
    /// — and the gap under it — between the Today card and the foot line.
    private func hasLogTiles(sleeping: Bool) -> Bool {
        isTracked(.feed) || isTracked(.diaper) || (isTracked(.sleep) && !sleeping)
    }

    /// The spread's trailing page — the day beside the cover: "Recent" with
    /// its quiet "+ Add note", then whatever leads the day right now (the
    /// Today card's daycare layer, SNOO suggestions, tonight's roster or the
    /// one-line up next, the setup checklist) and the journal filling the
    /// rest of the page. The undo toast floats at this page's foot, inside
    /// its width, so it never covers the leading page's controls or spans
    /// the fold.
    private func spreadRecentPage(_ grid: SpreadGrid) -> some View {
        VStack(spacing: 0) {
            spreadRecentTitle
                // As on the leading page: the title's own air, inside the
                // minimum that puts the first surface on the top line.
                .padding(.bottom, SpreadGrid.titleAir)
                .frame(minHeight: grid.titleHeight, alignment: .top)
            GeometryReader { page in
                spreadRecentContent(pageHeight: page.size.height)
            }
        }
        .frame(width: grid.pageWidth, height: max(grid.foot - grid.headY, 0), alignment: .top)
        .loggedToast($toast, sideInset: SpreadGrid.toastSideInset,
                     bottomInset: SpreadGrid.toastLift)
        .accessibilityElement(children: .contain)
        .padding(.leading, grid.trailingPage.minX)
        .padding(.top, grid.headY)
    }

    /// "Recent / last 24 hours" — the words of the section header this title
    /// replaces — with "+ Add note" on the subtitle's line. At a text size
    /// where the two no longer fit side by side, the action drops under the
    /// title rather than squeezing "Recent" into an ellipsis.
    private var spreadRecentTitle: some View {
        ViewThatFits(in: .horizontal) {
            PageTitle("Recent", subtitle: "last 24 hours", trailingAlignment: .subtitle) {
                spreadAddNoteButton
            }
            VStack(alignment: .leading, spacing: 6) {
                PageTitle("Recent", subtitle: "last 24 hours")
                spreadAddNoteButton
            }
        }
    }

    /// The timeline header's "+ Add note", same words and style — deliberately
    /// quiet. Alone at the head of a page it gets a 44 pt touch target; the
    /// negative padding keeps its layout the single line of text it shows, so
    /// it still sits on the subtitle's baseline.
    private var spreadAddNoteButton: some View {
        Button { activeSheet = .note } label: {
            Text("+ Add note")
                .font(.footnote.weight(.medium))
                .foregroundStyle(AppColor.accentNote)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, -13)
        .accessibilityLabel("Add note")
        .accessibilityHint("Writes a timestamped note on the timeline")
    }

    /// The trailing page under its title: the lead items at their natural
    /// height, then the journal. While the journal still gets a useful height
    /// it fills the rest of the page and ends on the foot line; when the lead
    /// items leave it too little, the page scrolls as a whole instead, the
    /// journal a fixed height inside it (`SpreadGrid.journalFills`).
    @ViewBuilder
    private func spreadRecentContent(pageHeight: CGFloat) -> some View {
        let gap = SpreadGrid.leadGap(leadHeight: spreadLeadHeight)
        if SpreadGrid.journalFills(pageHeight: pageHeight, leadHeight: spreadLeadHeight) {
            VStack(spacing: 0) {
                spreadLeadItems
                spreadJournal
                    .padding(.top, gap)
            }
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    spreadLeadItems
                    spreadJournal
                        .frame(height: SpreadGrid.journalScrollingHeight)
                        .padding(.top, gap)
                }
            }
        }
    }

    /// What leads the trailing page, each only when it exists today, in the
    /// single column's order: the Today card's daycare layer (while the log
    /// tiles have that card's page — see `spreadNowPage`), SNOO suggestions,
    /// tonight's roster (or the one-line up next by day), the setup
    /// checklist. Ticking, so the roster, a check slot and an in-progress
    /// suggestion stay honest; measured, so the page knows what is left for
    /// the journal.
    private var spreadLeadItems: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let attendance = daycareAttendance(now: ctx.date)
            VStack(spacing: SpreadGrid.surfaceGap) {
                // The same test the leading page makes: he is not at
                // daycare, so the tiles are on that page and its Today card
                // is the day alone. What daycare logged today — and the
                // drop-off slide, or "staying home" — sits here instead,
                // first, as it comes first in the single column.
                if attendance == nil, hasDaycareLayer(now: ctx.date, attendance: attendance) {
                    heroCard(now: ctx.date, attendance: attendance, summary: nil,
                             active: nil, condensedCaption: false, layers: .daycare)
                }
                snooCards(now: ctx.date)
                scheduleRow(now: ctx.date, attendance: attendance)
                if showChecklist {
                    setupChecklist
                }
            }
            .frame(maxWidth: .infinity)
            // Natural height, whatever the page offers: the roster's rows
            // would otherwise stretch to fill a share of it.
            .fixedSize(horizontal: false, vertical: true)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            spreadLeadHeight = height
        }
    }

    /// The timeline as the journal page: the same rows as every other layout
    /// — NOW cap, the live daycare nap, each entry with its taps and its
    /// swipe to delete — on one solid card that ends on the foot line, with
    /// no section header (the page's title says it).
    private var spreadJournal: some View {
        // Performance: assembled once per body, as in `timelineSection`.
        let entries = timelineEntries
        return JournalCard {
            if entries.isEmpty {
                // Centred in the card — and in a scroll view of its own, so a
                // pull still refreshes on a first run with nothing to list.
                GeometryReader { card in
                    ScrollView {
                        timelineEmptyState(paneMode: true)
                            .frame(maxWidth: .infinity,
                                   minHeight: max(card.size.height - JournalCardMetrics.topInset
                                                  - JournalCardMetrics.fadeHeight, 0))
                    }
                }
            } else {
                List {
                    Section {
                        timelineRows(entries, leading: JournalCardMetrics.rowLeadingInset,
                                     trailing: JournalCardMetrics.rowTrailingInset)
                    }
                    // The rows sit on the card, not on cells of their own.
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: Panes (iPad wide; iPhone Duo in portrait and on its side)

    /// Wide layout, leading pane: everything Home's single column shows above
    /// the timeline, at the width of a roomy iPhone.
    private func nowPane(_ layout: PaneLayout) -> some View {
        let shortCard = layout.fullHeight < PaneLayout.roomyHeight
        return List {
            Section {
                header
                    .listRowInsets(paneInsets(top: 8 + layout.topBreathingRoom, bottom: 2,
                                              side: .leading, in: layout))
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let attendance = daycareAttendance(now: ctx.date)
                    let summary = todaySummary
                    let active = activeSleep
                    VStack(spacing: 12) {
                        heroCard(now: ctx.date, attendance: attendance, summary: summary,
                                 active: active, condensedCaption: false)
                        controlsBlock(now: ctx.date, attendance: attendance, active: active,
                                      compactCard: shortCard)
                        scheduleRow(now: ctx.date, attendance: attendance)
                    }
                    .modifier(SleepAndDaycareAnimations(sleeping: active != nil,
                                                       attending: attendance != nil,
                                                       reduceMotion: reduceMotion))
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(paneInsets(top: 4, bottom: 4, side: .leading, in: layout))

            checklistSection(leading: 16, trailing: PaneLayout.foldSideInset)
        }
        .listStyle(.plain)
    }

    /// The 24-hour timeline on its own page (wide: trailing pane; tall during
    /// daycare hours: bottom pane). Its header — with "+ Add note" — pins.
    private func logPane(_ layout: PaneLayout) -> some View {
        let side: HorizontalEdge = layout.shape == .tall ? .leading : .trailing
        let insets = paneInsets(top: 0, bottom: 0, side: side, in: layout)
        return List {
            timelineSection(leading: insets.leading, trailing: insets.trailing, paneMode: true)
        }
        .listStyle(.plain)
        .padding(.top, layout.shape == .tall ? 0 : layout.topBreathingRoom)
    }

    /// Tall and short layouts: the pane of things to look at — header and
    /// Today card, then (tall only) what's up next, the setup checklist and
    /// the timeline.
    private func glancePane(_ layout: PaneLayout, includesTimeline: Bool) -> some View {
        let side: HorizontalEdge = .leading
        return List {
            Section {
                header
                    .listRowInsets(paneInsets(top: 8 + layout.topBreathingRoom, bottom: 2,
                                              side: side, in: layout))
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let attendance = daycareAttendance(now: ctx.date)
                    let summary = todaySummary
                    let active = activeSleep
                    VStack(spacing: 12) {
                        heroCard(now: ctx.date, attendance: attendance, summary: summary,
                                 active: active, condensedCaption: false)
                        if layout.shape == .tall {
                            scheduleRow(now: ctx.date, attendance: attendance)
                        }
                    }
                    .modifier(SleepAndDaycareAnimations(sleeping: active != nil,
                                                       attending: attendance != nil,
                                                       reduceMotion: reduceMotion))
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(paneInsets(top: 4, bottom: 4, side: side, in: layout))

            if layout.shape == .tall {
                checklistSection(leading: 16, trailing: 16)
                if includesTimeline {
                    timelineSection(paneMode: true)
                }
            }
        }
        .listStyle(.plain)
    }

    /// Tall layout, bottom pane: the log tiles and the sleep card — everything
    /// you tap while feeding — on the half that lies flat on the table.
    /// Centred in its half, and scrolls only if a large text size makes it
    /// taller than the half.
    private func controlsPane(_ layout: PaneLayout) -> some View {
        ScrollView {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let attendance = daycareAttendance(now: ctx.date)
                let active = activeSleep
                VStack(spacing: 12) {
                    controlsBlock(now: ctx.date, attendance: attendance, active: active,
                                  compactCard: true)
                }
                .modifier(SleepAndDaycareAnimations(sleeping: active != nil,
                                                   attending: attendance != nil,
                                                   reduceMotion: reduceMotion))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .frame(minHeight: layout.bottomHeight, alignment: .center)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// Short (tent) layout, trailing pane: tiles and sleep card first — the
    /// glance-and-tap row for a phone standing on the nightstand — then what's
    /// up next, the checklist and the timeline.
    private func tentControlsPane(_ layout: PaneLayout) -> some View {
        List {
            Section {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let attendance = daycareAttendance(now: ctx.date)
                    let active = activeSleep
                    VStack(spacing: 12) {
                        controlsBlock(now: ctx.date, attendance: attendance, active: active,
                                      compactCard: true)
                        scheduleRow(now: ctx.date, attendance: attendance)
                    }
                    .modifier(SleepAndDaycareAnimations(sleeping: active != nil,
                                                       attending: attendance != nil,
                                                       reduceMotion: reduceMotion))
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(paneInsets(top: 8, bottom: 4, side: .trailing, in: layout))

            checklistSection(leading: PaneLayout.foldSideInset, trailing: 16)

            timelineSection(leading: PaneLayout.foldSideInset, trailing: 16, paneMode: true)
        }
        .listStyle(.plain)
    }

    /// Row insets for a pane: the usual 16 pt on the screen-edge side and the
    /// small fold-side inset toward the band (which already supplies the gap).
    /// Stacked panes span the full width, so both sides keep 16.
    private func paneInsets(top: CGFloat, bottom: CGFloat, side: HorizontalEdge,
                            in layout: PaneLayout) -> EdgeInsets {
        guard layout.shape != .tall else {
            return EdgeInsets(top: top, leading: 16, bottom: bottom, trailing: 16)
        }
        return side == .leading
            ? EdgeInsets(top: top, leading: 16, bottom: bottom, trailing: PaneLayout.foldSideInset)
            : EdgeInsets(top: top, leading: PaneLayout.foldSideInset, bottom: bottom, trailing: 16)
    }

    /// Whether the tall layout's controls pane has anything to show right
    /// now: the log tiles (hidden while he's at daycare), a running sleep, or
    /// a SNOO suggestion.
    private func controlsPaneHasContent(now: Date) -> Bool {
        daycareAttendance(now: now) == nil || activeSleep != nil || showSnooSuggestions
    }

    // MARK: Shared pieces (every layout builds Home from these)

    /// `fillsPage` is the spread's leading page: the card takes the height it
    /// is given (its strip absorbing the slack) and, during daycare hours —
    /// when it is the whole page — shows the day's daycare photos as tiles.
    /// `layers` is the spread's too: the card without its daycare layer
    /// while the tiles share its page, and that layer alone, as a lead item
    /// of the page beside it (`TodayHeroCard.layers`). Everywhere else the
    /// card is whole.
    private func heroCard(now: Date, attendance: DaycareStatus.Attendance?,
                          summary: DaySummary?, active: SleepEvent?,
                          condensedCaption: Bool, fillsPage: Bool = false,
                          layers: TodayHeroCard.Layers = .all) -> some View {
        let photos = fillsPage && attendance != nil ? daycarePhotosToday : []
        return TodayHeroCard(
            babyName: baby?.name ?? "Baby",
            babyPhotoData: baby?.photoData,
            // The daycare layer draws no strip: spare it the day's marks,
            // which walk every sleep on each tick.
            marks: layers == .daycare ? [] : todayMarks,
            feedCount: summary?.feedCount ?? 0,
            feedOz: summary?.feedOz ?? 0,
            diaperCount: summary?.diaperCount ?? 0,
            wetCount: todayDiaperSplit.wet,
            dirtyCount: todayDiaperSplit.dirty,
            sleepSeconds: summary?.sleepSeconds ?? 0,
            daycare: daycareToday ?? DaycareDaySummary(),
            attendingSince: attendance?.since,
            firstDaycareEventAt: firstDaycareEventToday,
            lastDaycareEventAt: lastDaycareEventToday,
            // Stops crediting the live nap the instant he's
            // no longer considered "at daycare" — an explicit
            // checkout (handled above by closing the nap
            // outright) or the assumed-close fallback once
            // nothing ever arrives. Never runs forever.
            liveNapStartedAt: attendance != nil ? liveNapToday : nil,
            activeSleepStartedAt: active?.startedAt,
            now: now,
            showFeed: isTracked(.feed),
            showSleep: isTracked(.sleep),
            showDiaper: isTracked(.diaper),
            daycareName: daycareSettings?.daycareDisplayName ?? "Daycare",
            daycareCloseMinute: daycareCloseMinute,
            checkinSlot: checkinSlot(now: now, attendance: attendance),
            onDropOff: {
                // The whiteboard card reads the data BEFORE
                // the marker lands — its answers are the
                // morning's, not the drop-off's.
                let board = dropoffBoardInfo()
                logCheck(.checkIn, toast: "Dropped off")
                dropoffBoard = board
            },
            onPickUp: { logCheck(.checkOut, toast: "Picked up") },
            onUndoHomeToday: undoHomeToday,
            // Only while a sleep card showing the elapsed time big sits
            // right below it — or on a page of the spread, whatever sleep
            // is running: a daycare nap has no sleep card, but its caption
            // would stack the totals of a phone-width page all the same
            // (and the journal's live nap row, on the facing page, counts
            // it).
            condensedLiveCaption: condensedCaption && (active != nil || fillsPage),
            fillsHeight: fillsPage,
            daycarePhotos: photos,
            // The same viewer a photo row on the timeline opens, on the
            // whole day's photos.
            onOpenPhotos: { viewingMedia = MediaViewing(events: photos) },
            layers: layers
        )
    }

    /// Whether the Today card has a daycare layer to draw right now: the
    /// recap of a daycare day, or a check slot in view. The spread's
    /// trailing page asks before it hosts that layer as a lead item.
    private func hasDaycareLayer(now: Date, attendance: DaycareStatus.Attendance?) -> Bool {
        TodayHeroCard.hasDaycareLayer(
            daycare: daycareToday ?? DaycareDaySummary(),
            checkinSlot: checkinSlot(now: now, attendance: attendance))
    }

    /// Today's daycare photos and videos, newest first (the @Query's order)
    /// — what the recap's 📸 count counts. Newest-first, so today's are a
    /// prefix.
    private var daycarePhotosToday: [MediaEvent] {
        guard let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)
        else { return [] }
        return mediaEvents.prefix(while: { $0.timestamp >= dayStart })
            .filter { $0.isFromDaycare && $0.timestamp < dayEnd }
    }

    /// The tiles, the sleep card that takes the Sleep tile's place, and any
    /// SNOO suggestions — always together, in this order, in one pane, so the
    /// tile ↔ card swap animates in place ("Feed and Diaper never move").
    @ViewBuilder
    private func controlsBlock(now: Date, attendance: DaycareStatus.Attendance?,
                               active: SleepEvent?, compactCard: Bool) -> some View {
        if attendance == nil {
            logButtons(now: now, activeSleep: active)
        }
        if let sleep = active {
            sleepCard(sleep, now: now, compact: compactCard)
                .transition(.opacity.combined(with: .scale(0.96, anchor: .top)))
        }
        snooCards(now: now)
    }

    /// `footprint` is iPhone Duo's arrangement (its open pages and its
    /// cover): the card at the Sleep tile's own size. It takes precedence
    /// over `compact`.
    private func sleepCard(_ sleep: SleepEvent, now: Date, compact: Bool,
                           footprint: Bool = false) -> some View {
        SleepActiveCard(
            sleep: sleep, now: now,
            onWake: { endSleep(sleep) },
            onEditStart: sleep.isFromSnoo ? nil : { editingSleepStart = true },
            predictedWake: predictedWake(for: sleep, now: now),
            compact: compact,
            footprint: footprint
        )
    }

    @ViewBuilder
    private func snooCards(now: Date) -> some View {
        if showSnooSuggestions {
            ForEach(snoo.suggestions) { suggestion in
                SnooSuggestionCard(
                    suggestion: suggestion, now: now,
                    onSaved: { message in
                        toast = ToastData(message: message,
                                          accent: AppColor.accentSleep, undo: nil)
                    },
                    onEdit: { editingSnoo = suggestion }
                )
            }
        }
    }

    /// Tonight's roster or the one-line "up next".
    ///
    /// Inside the ticking TimelineView so the rows stay honest on a phone left
    /// open overnight: 11pm passing greys the 11pm row and surfaces the 3am
    /// one without needing a log or sync to trigger a render. The "Tonight"
    /// card appears while the night window is open AND in the run-up to it
    /// (once the next bottle is already a night bottle, or within the grace
    /// hour) — built dynamically from tonight's first (logged or projected)
    /// feed, defaulting to the window's start, so a night in progress always
    /// has a schedule; daytime keeps the one-line up-next.
    @ViewBuilder
    private func scheduleRow(now: Date, attendance: DaycareStatus.Attendance?) -> some View {
        switch nightState(now: now) {
        case .active(let nightOccurrences), .approaching(let nightOccurrences):
            // Never while he's at daycare — the nighttime
            // roster waits for pickup. Once every slot is
            // settled (the 7:58 AM all-checkmarks state),
            // the card is a finished checklist — hidden
            // until the next evening's run-up.
            // Reuses the occurrences nightState already built
            // (same inputs), instead of rebuilding the schedule.
            let tonight = tonightOccurrences(now: now, nightOccurrences: nightOccurrences)
            if attendance == nil,
               NightSchedule.hasRemainingBusiness(tonight) {
                tonightCard(tonight, now: now)
            }
        case .day, nil:
            if let next = upNextOccurrence(now: now) {
                upNextRow(next)
            }
        }
    }

    /// The deferred-setup checklist, where an empty timeline leaves dead space.
    @ViewBuilder
    private func checklistSection(leading: CGFloat, trailing: CGFloat) -> some View {
        if showChecklist {
            Section {
                setupChecklist
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: leading, bottom: 4, trailing: trailing))
        }
    }

    /// The checklist card itself — a list row in the list layouts, a lead
    /// item on the spread's trailing page. Show it only while `showChecklist`.
    private var setupChecklist: some View {
        SetupChecklistCard(
            quests: setup.activeQuests(role: prefs.syncRole),
            isComplete: { setup.isComplete($0, settings: settingsList.first) },
            onQuest: { questSheet = $0 },
            onDismiss: { withAnimation(.easeInOut) { setup.dismissedChecklist = true } }
        )
    }

    /// Keeps `dayStart` current while Home is on screen, so the today ribbon,
    /// counts, and 24h window roll over at midnight without needing a new log or
    /// a tab switch to trigger a re-render.
    private func advanceAtMidnight() async {
        while !Task.isCancelled {
            let now = Date()
            let start = Calendar.current.startOfDay(for: now)
            if start != dayStart { dayStart = start }
            guard let nextMidnight = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return }
            try? await Task.sleep(for: .seconds(max(1, nextMidnight.timeIntervalSince(now))))
        }
    }

    /// Opens the next log sheet a tapped widget queued, draining one entry per
    /// call so two fast taps both resolve.
    private func consumeDeepLink() {
        guard let target = router.dequeue() else { return }
        switch target {
        // A stale widget can deep-link into a tracker that's been turned off —
        // don't open a log sheet the Home buttons no longer offer.
        case .feed:   if isTracked(.feed) { activeSheet = .feed }
        case .diaper: if isTracked(.diaper) { activeSheet = .diaper }
        }
    }

    // MARK: Header

    private var header: some View {
        // .top aligns the avatar, name, and the settings button along one line.
        HStack(alignment: .top, spacing: 14) {
            Avatar(photoData: baby?.photoData, name: baby?.name ?? "Baby",
                   colorHex: ParticipantColors.babyHex, size: 60)
            VStack(alignment: .leading, spacing: 2) {
                Text(baby?.name ?? "Baby")
                    .font(AppFont.hero())
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let dob = baby?.dateOfBirth {
                    Text(TimeFormatting.age(from: dob))
                        .font(.subheadline)
                        .foregroundStyle(AppColor.text2)
                }
            }
            Spacer()
            settingsButton
        }
    }

    private var settingsButton: some View {
        Button { showSettings = true } label: {
            Image(systemName: "gearshape")
                .font(.title3)
                .foregroundStyle(AppColor.text3)
                .frame(width: 44, height: 44)
                .background(AppColor.card, in: Circle())
                .overlay(Circle().strokeBorder(AppColor.separator.opacity(0.5), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
    }

    private var lastSleepEnd: Date? {
        sleeps.first(where: { $0.endedAt != nil })?.endedAt
    }

    // MARK: Today ribbon

    private var todayMarks: [RibbonMark] {
        // Reads dayStart so a midnight rollover (which bumps it) re-renders the
        // whole today section — refreshing the counts and 24h window too.
        // Newest-first @Queries: the day's feeds/diapers are a prefix (forDay
        // drops the rest anyway); sleeps stay whole since one can span midnight.
        // forDay rounds dayStart down with calendar.startOfDay, which falls
        // BEFORE a stale dayStart after a time-zone change. Cut the prefix at that
        // same start, using the same calendar, so the slice always covers it.
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: dayStart)
        return RibbonMark.forDay(dayStart,
                                 feeds: Array(feeds.prefix(while: { $0.timestamp >= start })),
                                 sleeps: sleeps,
                                 diapers: Array(diapers.prefix(while: { $0.timestamp >= start })),
                                 calendar: calendar)
    }

    /// Today's Brightwheel-imported events, aggregated for the report card.
    /// Nil (card hidden) until the daycare has logged something today — a
    /// lone drop-off note counts, so the card appears at drop-off and grows
    /// through the day.
    private var daycareToday: DaycareDaySummary? {
        guard let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)
        else { return nil }
        func isToday(_ date: Date) -> Bool { date >= dayStart && date < dayEnd }

        // Performance: every array is newest-first, so "today" starts with a
        // prefix; the isToday upper bound is kept in each predicate.
        let dayFeeds = feeds.prefix(while: { $0.timestamp >= dayStart }).filter { $0.isFromDaycare && isToday($0.timestamp) }
        let dayNaps = sleeps.prefix(while: { $0.startedAt >= dayStart }).filter { $0.isFromDaycare && isToday($0.startedAt) && $0.endedAt != nil }
        let dayDiapers = diapers.prefix(while: { $0.timestamp >= dayStart }).filter { $0.isFromDaycare && isToday($0.timestamp) }
        // ANY source — a manual drop-off/pick-up brackets the day exactly
        // like Brightwheel's markers do (capsule window, strip zone).
        // "Home today" markers aren't attendance and stay out.
        let dayChecks = checkEvents.prefix(while: { $0.timestamp >= dayStart }).filter { isToday($0.timestamp) && $0.type != .notAttending }

        var day = DaycareDaySummary()
        day.feedCount = dayFeeds.count
        day.feedOz = dayFeeds.reduce(0) { $0 + $1.amountOz }
        day.napCount = dayNaps.count
        day.napSeconds = dayNaps.reduce(0) { $0 + ($1.endedAt ?? $1.startedAt).timeIntervalSince($1.startedAt) }
        day.diaperCount = dayDiapers.count
        day.wetCount = dayDiapers.filter { $0.type == .wet || $0.type == .both }.count
        day.dirtyCount = dayDiapers.filter { $0.type == .dirty || $0.type == .both }.count
        day.activityCount = activityEvents.prefix(while: { $0.timestamp >= dayStart }).filter { $0.isFromDaycare && isToday($0.timestamp) }.count
        day.photoCount = mediaEvents.prefix(while: { $0.timestamp >= dayStart }).filter { $0.isFromDaycare && isToday($0.timestamp) }.count
        day.medicationCount = medicationEvents.prefix(while: { $0.timestamp >= dayStart }).filter { $0.isFromDaycare && isToday($0.timestamp) }.count
        day.checkIn = dayChecks.filter { $0.type == .checkIn }.map(\.timestamp).min()
        day.checkOut = dayChecks.filter { $0.type == .checkOut }.map(\.timestamp).max()
        // A lone drop-off note, mood, or staff note still counts — the card
        // appears at drop-off and grows through the day.
        day.hasAnythingElse =
            noteEvents.prefix(while: { $0.timestamp >= dayStart }).contains { $0.isFromDaycare && isToday($0.timestamp) }
            || staffNoteEvents.prefix(while: { $0.timestamp >= dayStart }).contains { $0.isFromDaycare && isToday($0.timestamp) }
            || healthCheckEvents.prefix(while: { $0.timestamp >= dayStart }).contains { $0.isFromDaycare && isToday($0.timestamp) }
            || moodEvents.prefix(while: { $0.timestamp >= dayStart }).contains { $0.isFromDaycare && isToday($0.timestamp) }
            || pottyEvents.prefix(while: { $0.timestamp >= dayStart }).contains { $0.isFromDaycare && isToday($0.timestamp) }
            || milestoneEvents.prefix(while: { $0.timestamp >= dayStart }).contains { $0.isFromDaycare && isToday($0.timestamp) }
        return day.isEmpty ? nil : day
    }

    /// Whether Miller is at daycare right now, and since when (`DaycareStatus`
    /// — check markers first, first daycare-logged event as the fallback, with
    /// the configured closing time as the assumed check-out — except while
    /// THIS phone stands inside the fence: then only a logged check-out ends
    /// the day, so a late pick-up still gets its slide). Drives the
    /// tiles-↔-strip swap and the report card's hero placement.
    private func daycareAttendance(now: Date) -> DaycareStatus.Attendance? {
        DaycareStatus.attendance(
            checks: checkEvents.map { ($0.timestamp, $0.type) },
            firstDaycareEvent: firstDaycareEventToday,
            dayStart: dayStart, now: now,
            closeMinute: daycareCloseMinute,
            atDaycare: geofenceSliderMode && geofence.isNearDaycare)
    }

    /// The shared daycare config (hours, days, name) — the canonical row, the
    /// same pick Settings edits.
    private var daycareSettings: SharedSettings? {
        SharedSettings.canonical(settingsList)
    }

    private var daycareCloseMinute: Int {
        daycareSettings?.daycareCloseMinute ?? DaycareStatus.defaultCloseMinute
    }

    /// The earliest daycare-sourced event of any kind today — the stand-in
    /// check-in when the real marker never arrived: if daycare is logging
    /// bottles, he's there. Check markers excluded (they're the primary
    /// signal), parent-logged events excluded (a home feed isn't attendance).
    /// Each @Query is newest-first, so today's slice is a prefix.
    private var firstDaycareEventToday: Date? {
        func earliest<T>(_ items: [T], at time: (T) -> Date,
                         fromDaycare: (T) -> Bool) -> Date? {
            items.prefix(while: { time($0) >= dayStart })
                .filter(fromDaycare).map(time).min()
        }
        return [
            earliest(feeds, at: \.timestamp, fromDaycare: \.isFromDaycare),
            earliest(sleeps, at: \.startedAt, fromDaycare: \.isFromDaycare),
            earliest(diapers, at: \.timestamp, fromDaycare: \.isFromDaycare),
            earliest(noteEvents, at: \.timestamp, fromDaycare: \.isFromDaycare),
            earliest(activityEvents, at: \.timestamp, fromDaycare: \.isFromDaycare),
            earliest(mediaEvents, at: \.timestamp, fromDaycare: \.isFromDaycare),
            earliest(medicationEvents, at: \.timestamp, fromDaycare: \.isFromDaycare),
            earliest(healthCheckEvents, at: \.timestamp, fromDaycare: \.isFromDaycare),
            earliest(moodEvents, at: \.timestamp, fromDaycare: \.isFromDaycare),
            earliest(pottyEvents, at: \.timestamp, fromDaycare: \.isFromDaycare),
            earliest(milestoneEvents, at: \.timestamp, fromDaycare: \.isFromDaycare),
            earliest(staffNoteEvents, at: \.timestamp, fromDaycare: \.isFromDaycare),
        ].compactMap { $0 }.min()
    }

    /// The latest daycare-sourced event of any kind today — the check-out
    /// stand-in when the real marker never arrived: the hero's capsule window
    /// and strip zone close at the last thing staff logged. A sleep counts by
    /// its END (a nap that ran past the last diaper means he was still there).
    private var lastDaycareEventToday: Date? {
        func latest<T>(_ items: [T], at time: (T) -> Date,
                       fromDaycare: (T) -> Bool) -> Date? {
            items.prefix(while: { time($0) >= dayStart })
                .filter(fromDaycare).map(time).max()
        }
        return [
            latest(feeds, at: \.timestamp, fromDaycare: \.isFromDaycare),
            latest(sleeps, at: { $0.endedAt ?? $0.startedAt }, fromDaycare: \.isFromDaycare),
            latest(diapers, at: \.timestamp, fromDaycare: \.isFromDaycare),
            latest(noteEvents, at: \.timestamp, fromDaycare: \.isFromDaycare),
            latest(activityEvents, at: \.timestamp, fromDaycare: \.isFromDaycare),
            latest(mediaEvents, at: \.timestamp, fromDaycare: \.isFromDaycare),
            latest(medicationEvents, at: \.timestamp, fromDaycare: \.isFromDaycare),
            latest(healthCheckEvents, at: \.timestamp, fromDaycare: \.isFromDaycare),
            latest(moodEvents, at: \.timestamp, fromDaycare: \.isFromDaycare),
            latest(pottyEvents, at: \.timestamp, fromDaycare: \.isFromDaycare),
            latest(milestoneEvents, at: \.timestamp, fromDaycare: \.isFromDaycare),
            latest(staffNoteEvents, at: \.timestamp, fromDaycare: \.isFromDaycare),
        ].compactMap { $0 }.max()
    }

    /// Brightwheel's in-progress nap, if it started today — guards against a
    /// stale value surviving from yesterday when the evening's last sync never
    /// saw the wake-up land.
    private var liveNapToday: Date? {
        brightwheel.liveNapStartedAt.flatMap { $0 >= dayStart ? $0 : nil }
    }

    private var todaySummary: DaySummary? {
        // Performance: the one-day summary only counts feeds/diapers on the
        // engine's own today, and the @Queries are newest-first, so today's
        // rows are a prefix. Sleeps stay whole (one started earlier can overlap
        // today). todayStart is taken before the engine's Date(), so a midnight
        // in between only makes the prefix a superset — same result.
        let todayStart = Calendar.current.startOfDay(for: .now)
        return StatsEngine(feeds: Array(feeds.prefix(while: { $0.timestamp >= todayStart })),
                           sleeps: sleeps,
                           diapers: Array(diapers.prefix(while: { $0.timestamp >= todayStart })))
            .dailySummaries(days: 1).first
    }

    /// Today's wet/dirty tallies for the hero card's split (a `.both` diaper
    /// counts toward each). The @Query is newest-first, so today is a prefix.
    private var todayDiaperSplit: (wet: Int, dirty: Int) {
        let today = diapers.prefix(while: { $0.timestamp >= dayStart })
        return (today.filter { $0.type == .wet || $0.type == .both }.count,
                today.filter { $0.type == .dirty || $0.type == .both }.count)
    }

    // MARK: Log buttons

    // `activeSleep` deliberately shadows the property so the reads below use the
    // value bound once per tick (performance; identical value).
    private func logButtons(now: Date, activeSleep: SleepEvent?) -> some View {
        let target = sleepTarget
        return LogButtons(
            feedStatus: feeds.first.flatMap {
                tileStatus(since: $0.timestamp, now: now, target: targetFeed(after: $0.timestamp))
            },
            sleepStatus: activeSleep == nil
                ? tileStatus(since: lastSleepEnd, now: now, target: target) : nil,
            diaperStatus: tileStatus(since: diapers.first?.timestamp, now: now, target: UrgencyDefaults.diaper),
            feedHint: feedHint(now: now),
            sleepHint: sleepHint(now: now, target: target),
            diaperHint: diaperHint,
            sleepDetail: lastNapDetail,
            sleepActive: activeSleep != nil,
            feedReminderArmed: feedReminderArmed(now: now),
            showFeed: isTracked(.feed),
            showSleep: isTracked(.sleep),
            showDiaper: isTracked(.diaper),
            onFeed: { activeSheet = .feed },
            onSleep: startSleep,
            onDiaper: { activeSheet = .diaper }
        )
    }

    /// The Feed tile's bell should mean "an alarm is actually counting down", not
    /// merely "reminders are enabled". Mirror `FeedAlarmManager.reschedule`'s own
    /// guards: reminders on + authorized + a logged feed whose next-due time is
    /// still ahead. (No feed yet, or already overdue, means nothing is armed.)
    private func feedReminderArmed(now: Date) -> Bool {
        guard prefs.feedReminderEnabled, FeedAlarmManager.isAuthorized,
              let last = feeds.first?.timestamp else { return false }
        return last.addingTimeInterval(targetFeed(after: last)) > now
    }

    /// The Feed tile says what's next, not just what happened. With AI on and
    /// enough of his own data, the projection comes from his observed cadence
    /// (`PredictionEngine`) with the expected bottle size appended; otherwise
    /// the same target-interval math as the reminders. The forecast never
    /// moves the alarm — the bell is a contract, the hint is a forecast.
    private func feedHint(now: Date) -> TileHint {
        guard let last = feeds.first?.timestamp else { return TileHint(text: "log a bottle") }
        if aiEnabled, let s = settingsList.first {
            // Performance: mapped once, used by both engines below.
            let feedTimes = feeds.map(\.timestamp)
            let prediction = PredictionEngine.nextFeed(
                lastFeed: last, feeds: feedTimes,
                targetInterval: targetFeed(after: last),
                nightStartMinute: s.nightStartMinute, nightEndMinute: s.nightEndMinute,
                now: now)
            if prediction.confidence != .low, prediction.date > now {
                // Champion/challenger: the trained model's date replaces the
                // statistic's only while the accuracy gate says it's winning.
                var date = prediction.date
                if let baby,
                   let modelDate = PredictionArbiter.shared.modelNextFeed(
                       lastFeed: last, feeds: feedTimes,
                       dateOfBirth: baby.dateOfBirth,
                       targetInterval: { s.feedInterval(after: $0) },
                       nightStartMinute: s.nightStartMinute, nightEndMinute: s.nightEndMinute,
                       now: now),
                   modelDate > now {
                    date = modelDate
                }
                // No "bottle" — the tile is already titled Feed, and the ✦
                // line must hold full size beside the oz suffix on a square
                // tile (spelled out, it only fit by scaling down, which made
                // the tiles' hint rows visibly inconsistent).
                let clock = TimeFormatting.clock(date)
                var text = prediction.confidence == .high
                    ? "next ~\(clock)" : "likely ~\(clock)"
                if let oz = predictedOz(at: date, now: now) {
                    text += " · ~\(OzFormat.string(oz)) oz"
                }
                return TileHint(text: text, isAI: true)
            }
        }
        let next = last.addingTimeInterval(targetFeed(after: last))
        return TileHint(text: next < now
            ? "bottle was due ~\(TimeFormatting.clock(next))"
            : "next bottle ~\(TimeFormatting.clock(next))")
    }

    /// Expected bottle size for a feed at `reference` — nil until his own
    /// data carries it (a `.low` result is just the age table, and the tile
    /// shouldn't dress a baseline up as his pattern).
    private func predictedOz(at reference: Date, now: Date) -> Double? {
        guard aiEnabled, let s = settingsList.first else { return nil }
        // Performance: mapped once, shared by both calls below.
        let samples: [(timestamp: Date, oz: Double)] = feeds.map { ($0.timestamp, $0.amountOz) }
        let prediction = PredictionEngine.feedAmount(
            feeds: samples,
            ageInDays: ageInDays, at: reference,
            nightStartMinute: s.nightStartMinute, nightEndMinute: s.nightEndMinute,
            now: now)
        guard prediction.confidence != .low else { return nil }
        if let baby,
           let modelOz = PredictionArbiter.shared.modelOz(
               at: reference, feeds: samples,
               dateOfBirth: baby.dateOfBirth,
               nightStartMinute: s.nightStartMinute, nightEndMinute: s.nightEndMinute,
               now: now) {
            return modelOz
        }
        return prediction.oz
    }

    /// Diapers aren't on a predictable schedule the way feeds/naps are, so
    /// there's no "next" to project — the useful thing to surface instead is
    /// when the last change actually happened, complementing the tile's
    /// relative "38m ago" with a fixed clock time.
    private var diaperHint: TileHint {
        guard let last = diapers.first?.timestamp else { return TileHint(text: "log a change") }
        return TileHint(text: "changed at \(TimeFormatting.clock(last))")
    }

    /// The wide Sleep row has horizontal room the square tiles don't: a
    /// trailing "last nap" stat — the number you reconstruct in your head
    /// when deciding whether baby is ready to go down again.
    private var lastNapDetail: TileDetail? {
        guard let last = sleeps.first(where: { $0.endedAt != nil }),
              let end = last.endedAt else { return nil }
        return TileDetail(label: "last \(SleepLanguage.noun(start: last.startedAt, end: end).lowercased())",
                          value: TimeFormatting.duration(from: last.startedAt, to: end))
    }

    /// Same idea for Sleep: the projected next nap, from the last wake time
    /// plus the sleep target that already drives the tile's urgency dot. With
    /// AI on and enough history, the "awake" suffix gives way to the expected
    /// nap length — the number a parent is actually planning around.
    private func sleepHint(now: Date, target: TimeInterval) -> TileHint {
        let plain = WakeWindow.napHint(lastWake: lastSleepEnd, target: target, now: now)
        guard aiEnabled, let s = settingsList.first, let lastWake = lastSleepEnd else {
            return TileHint(text: plain)
        }
        let next = lastWake.addingTimeInterval(target)
        guard next > now else { return TileHint(text: plain) }
        let duration = PredictionEngine.sleepDuration(
            startingAt: next, sleeps: sleeps.map { ($0.startedAt, $0.endedAt) },
            ageInDays: ageInDays,
            nightStartMinute: s.nightStartMinute, nightEndMinute: s.nightEndMinute,
            now: now)
        guard duration.confidence != .low, !duration.isNight else { return TileHint(text: plain) }
        // Same trim as the Feed tile: the row is titled Sleep, so "nap" is
        // dead weight the duration suffix needs back.
        return TileHint(
            text: "next ~\(TimeFormatting.clock(next)) · usually ~\(WakeWindow.shortLabel(duration.duration))",
            isAI: true)
    }

    /// Predicted end of the running sleep, for the active card and its
    /// VoiceOver readout. Nil below medium confidence or once the moment has
    /// passed — a stale "wake ~2:55" under a 3:10 clock reads as broken.
    private func predictedWake(for sleep: SleepEvent, now: Date) -> Date? {
        guard aiEnabled, let s = settingsList.first else { return nil }
        let duration = PredictionEngine.sleepDuration(
            startingAt: sleep.startedAt, sleeps: sleeps.map { ($0.startedAt, $0.endedAt) },
            ageInDays: ageInDays,
            nightStartMinute: s.nightStartMinute, nightEndMinute: s.nightEndMinute,
            now: now)
        guard duration.confidence != .low else { return nil }
        let wake = sleep.startedAt.addingTimeInterval(duration.duration)
        return wake > now ? wake : nil
    }

    /// The wake window this baby is actually working with — his age, adjusted
    /// by his own recent history. Drives both the hint and the tile's urgency
    /// dot, so the dot and the projection can never disagree. Trailing week
    /// only, matching `QuickLogger.sleepTarget` and the widgets — unwindowed,
    /// this tile would average his entire sleep history and drift from every
    /// other surface as he ages.
    private var sleepTarget: TimeInterval {
        let now = Date.now
        let weekAgo = now.addingTimeInterval(-7 * 24 * 3600)
        return WakeWindow.predicted(
            ageInDays: baby.map { WakeWindow.ageInDays(dateOfBirth: $0.dateOfBirth) } ?? 0,
            observedGaps: WakeWindow.wakeGaps(
                // Newest-first by startedAt, so the trailing week is a prefix.
                sleeps: sleeps.prefix(while: { $0.startedAt >= weekAgo })
                    .map { ($0.startedAt, $0.endedAt) },
                nightStartMinute: settingsList.first?.nightStartMinute ?? 1200,
                nightEndMinute: settingsList.first?.nightEndMinute ?? 480),
            now: now)
    }

    // MARK: Tonight (nighttime schedule card)

    /// Where tonight stands: nil before setup (no settings row yet), else the
    /// dynamic engine's read — day, approaching (the run-up to the window),
    /// or active with the constructed schedule.
    private func nightState(now: Date) -> NightSchedule.State? {
        guard let s = settingsList.first, isTracked(.feed) || !sleepSlots.isEmpty else { return nil }
        return NightSchedule(settings: s, participants: participants, feeds: feeds,
                             overrides: planOverrides, sleepSlots: sleepSlots, now: now).state
    }

    /// Standing slots minus feed ones: night feeds are computed now, so a
    /// leftover fixed-era feed slot (or one synced from an older build) must
    /// not render or ring next to the dynamic schedule.
    private var sleepSlots: [PlanSlot] {
        planSlots.filter { $0.kind != .feed }
    }

    /// The whole night at a glance: tonight's dynamically constructed feeds
    /// (anchored to the night's first logged bottle) merged with any standing
    /// sleep slots in the window, ticked-off ones included — the card is
    /// tonight's roster, not just what's left.
    private func tonightOccurrences(now: Date, nightOccurrences: [ScheduleOccurrence]) -> [ScheduleOccurrence] {
        guard let s = settingsList.first else { return [] }
        var merged = isTracked(.feed)
            ? nightOccurrences.filter { $0.status != .skipped }
            : []
        // Sleep slots come from TONIGHT's window bounds (the one the feed
        // schedule speaks for), not minute-of-day arithmetic — during the
        // run-up to the window, "time since night start" would otherwise
        // reach back into LAST night and drag its stale slots onto the card.
        if !sleepSlots.isEmpty, isTracked(.sleep) {
            // Built only where used (same inputs as nightState's schedule).
            let night = NightSchedule(settings: s, participants: participants, feeds: feeds,
                                      overrides: planOverrides, sleepSlots: sleepSlots, now: now)
            let engine = ScheduleEngine(slots: sleepSlots, overrides: planOverrides,
                                        feeds: feeds, sleeps: sleeps, now: now)
            merged += night.planOccurrences(from: engine).filter { $0.status != .skipped }
        }
        return merged.sorted { $0.date < $1.date }
    }

    private func tonightCard(_ occurrences: [ScheduleOccurrence], now: Date) -> some View {
        let rows = occurrences.filter { $0.endDate == nil }
        let spans = occurrences.filter { $0.endDate != nil && $0.status != .skipped }
        let lanes = tonightLanes(spans: spans)
        let laneSpans: [SleepLaneLayout.Span] = spans.compactMap { occ in
            guard let end = occ.endDate, let parentID = occ.assignedToID else { return nil }
            return SleepLaneLayout.Span(id: occ.id, parentID: parentID,
                                        start: occ.date, end: end)
        }
        let railDates = rows.map(\.date)
        let layout = SleepLaneLayout(
            elementDates: railDates,
            laneParentIDs: lanes.map(\.id),
            spans: laneSpans)
        let slices = { (index: Int) -> [SleepLaneLayout.Slice] in
            index < layout.slices.count ? layout.slices[index] : []
        }
        return Button {
            router.requestTab(.schedule)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text("🌙").font(.callout)
                    Text("Tonight's Schedule").sectionLabelStyle()
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppColor.text3)
                }
                .padding(.bottom, 8)
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, occ in
                        tonightRow(occ, now: now, lanes: lanes,
                                   slices: slices(index),
                                   isLast: index == rows.count - 1)
                    }
                }
                // Annotation, never a plan change: the schedule stays the
                // source of truth, the prediction is a footnote telling the
                // parent on duty how big a bottle to make.
                if let next = rows.first(where: { $0.kind == .feed && $0.status == .upcoming }),
                   let oz = predictedOz(at: next.date, now: now) {
                    AIHintText(
                        text: "usually takes ~\(OzFormat.string(oz)) oz at \(TimeFormatting.clock(next.date))",
                        font: .caption2)
                        .padding(.top, 6)
                }
                if let parts = tonightSummaryParts {
                    HStack(spacing: 6) {
                        Label(parts.interval, systemImage: "clock")
                        Text("·").foregroundStyle(AppColor.text3)
                        Label(parts.window, systemImage: "moon.stars.fill")
                    }
                    .font(.caption2)
                    .foregroundStyle(AppColor.text3)
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .surfaceCard(cornerRadius: 14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tonight's schedule, \(rows.count) slots")
        .accessibilityHint("Opens the nighttime schedule")
    }

    private func tonightLanes(spans: [ScheduleOccurrence]) -> [SleepLaneColumn.Lane] {
        guard !spans.isEmpty else { return [] }
        return participants
            .filter(\.isActive)
            .sorted { ($0.invitedAt, $0.id.uuidString) < ($1.invitedAt, $1.id.uuidString) }
            .map { .init(id: $0.id, name: $0.displayName, colorHex: $0.colorHex) }
    }

    private func tonightRow(_ occ: ScheduleOccurrence, now: Date,
                            lanes: [SleepLaneColumn.Lane],
                            slices: [SleepLaneLayout.Slice],
                            isLast: Bool) -> some View {
        let mine = occ.assignedToID == prefs.myParticipantID
        let done = { if case .fulfilled = occ.status { return true }; return false }()
        // A bottle the night ran past reads as quiet as a done one — it stays
        // on the roster so the night keeps its shape, but it's nobody's job.
        let settled = done || occ.status == .missed
        let accent = occ.kind == .sleep ? AppColor.accentSleep : AppColor.accentFeed
        return HStack(spacing: 6) {
            Text(TimeFormatting.clock(occ.date))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(settled ? AppColor.text3.opacity(0.6) : AppColor.text3)
                .frame(width: 52, alignment: .trailing)

            if !lanes.isEmpty {
                SleepLaneColumn(lanes: lanes, slices: slices)
            }

            ZStack {
                if isLast {
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(AppColor.separator.opacity(0.6))
                            .frame(width: 1.5)
                            .frame(maxHeight: .infinity)
                        Color.clear.frame(maxHeight: .infinity)
                    }
                } else {
                    Rectangle()
                        .fill(AppColor.separator.opacity(0.6))
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                }
                Circle()
                    .fill(accent.opacity(settled ? 0.35 : 1))
                    .frame(width: 8, height: 8)
                    .overlay(Circle().strokeBorder(AppColor.card, lineWidth: 1.5))
            }
            .frame(width: 12)
            .frame(minHeight: 34)

            if done {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(AppColor.accentSleep)
            } else if occ.status == .overdue {
                Text("overdue")
                    .font(.system(size: 9))
                    .foregroundStyle(AppColor.urgencyAmber)
            } else if occ.status == .missed {
                Text("skipped")
                    .font(.system(size: 9))
                    .foregroundStyle(AppColor.text3)
            }

            Spacer(minLength: 4)

            if occ.assignedToID != nil {
                Text(mine ? "You" : occ.assignedToName)
                    .font(.caption2)
                    .foregroundStyle(settled ? AppColor.text3 : AppColor.text2)
                    .lineLimit(1)
                Avatar(photoData: occ.assignedToID.flatMap { loggerPhoto[$0] },
                       name: occ.assignedToName, colorHex: occ.assignedToColorHex, size: 16)
            } else {
                Circle()
                    .strokeBorder(AppColor.text3.opacity(0.6),
                                  style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .frame(width: 16, height: 16)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tonightRowLabel(occ, mine: mine, done: done))
    }

    private func tonightRowLabel(_ occ: ScheduleOccurrence, mine: Bool, done: Bool) -> String {
        let kind = occ.kind == .sleep ? "sleep" : "bottle"
        let who = occ.assignedToID == nil ? "unassigned" : (mine ? "yours" : occ.assignedToName)
        let status = if done { ", done" }
            else if occ.status == .overdue { ", overdue" }
            else if occ.status == .missed { ", skipped, fed later" }
            else { "" }
        return "\(TimeFormatting.clock(occ.date)) \(kind), \(who)\(status)"
    }

    /// "Every 3h" / "8:00 PM–8:00 AM" — same summary the schedule tab shows, split
    /// so the footer can lay each half out under its own icon.
    private var tonightSummaryParts: (interval: String, window: String)? {
        guard let s = settingsList.first else { return nil }
        let interval = "Every \(NightScheduleSettingsSheet.spacingLabel(s.nightFeedSpacingMinutes))"
        let window = "\(NightScheduleSettingsSheet.clock(minuteOfDay: s.nightStartMinute))"
            + "–\(NightScheduleSettingsSheet.clock(minuteOfDay: s.nightEndMinute))"
        return (interval, window)
    }

    // MARK: Up next (schedule glance)

    /// The next *planned, assigned* slot within 8 hours — the one line that
    /// answers "who's up". Predictions and unassigned slots stay off Home; the
    /// Schedule tab owns the full picture.
    private func upNextOccurrence(now: Date) -> ScheduleOccurrence? {
        guard !sleepSlots.isEmpty else { return nil }
        let engine = ScheduleEngine(slots: sleepSlots, overrides: planOverrides,
                                    feeds: feeds, sleeps: sleeps, now: now)
        // First *assigned* occurrence — an unassigned slot must not hide the
        // row. Slots for a paused tracker stay off the glance too, and spans
        // (sleep windows) aren't duty — the glance answers "who's up".
        return engine.occurrences(lookback: 0, horizon: 8 * 3600)
            .first {
                $0.status == .upcoming && $0.assignedToID != nil
                    && $0.endDate == nil && isTracked($0.kind)
            }
    }

    private func upNextRow(_ occ: ScheduleOccurrence) -> some View {
        let mine = occ.assignedToID == prefs.myParticipantID
        return Button {
            router.requestTab(.schedule)
        } label: {
            HStack(spacing: 8) {
                Text(occ.kind.emoji).font(.callout)
                Text("Up next").sectionLabelStyle()
                Text(TimeFormatting.clock(occ.date))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(AppColor.text)
                Text("·").foregroundStyle(AppColor.text3)
                Avatar(photoData: occ.assignedToID.flatMap { loggerPhoto[$0] },
                       name: occ.assignedToName, colorHex: occ.assignedToColorHex, size: 18)
                Text(mine ? "You" : occ.assignedToName)
                    .font(.subheadline)
                    .foregroundStyle(AppColor.text2)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppColor.text3)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .surfaceCard(cornerRadius: 14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mine
            ? "Up next: your \(occ.kind == .sleep ? "sleep" : "bottle") at \(TimeFormatting.clock(occ.date))"
            : "Up next: \(occ.kind == .sleep ? "sleep" : "bottle") at \(TimeFormatting.clock(occ.date)), \(occ.assignedToName)'s turn")
        .accessibilityHint("Opens the schedule")
    }

    // MARK: Manual check-in/out

    /// Whether the sliders run in geofence mode ON THIS PHONE: the fence is
    /// configured and enabled (shared), and this device holds Always location
    /// (per-device). In geofence mode the sliders never show by default —
    /// only the phone standing at the daycare gets one, and a day that never
    /// touches the fence (weekend, sick day) stays silent: home is implicit.
    /// Without all three, Home falls back to the time-based schedule.
    private var geofenceSliderMode: Bool {
        daycareSettings?.daycareGeofenceEnabled == true
            && daycareSettings?.daycareCoordinate != nil
            && geofence.hasAlwaysPermission
    }

    /// Whether the co-parent's phone is standing at the daycare right now,
    /// from the synced presence value — this phone then shows the quiet
    /// "someone's at daycare" line instead of a slider.
    private func partnerAtDaycare(now: Date) -> Bool {
        daycareSettings?.daycarePresence?.isPartnerAtDaycare(
            myDeviceID: LocalPrefs.shared.deviceID, now: now) ?? false
    }

    /// The hero's manual check slot: operating days only (Settings → Daycare;
    /// Mon–Fri until configured).
    ///
    /// In geofence mode (`geofenceSliderMode`) the fence drives everything:
    /// the drop-off slide exists only while THIS phone stands at the daycare
    /// inside the operating window, the pick-up slide only while this phone
    /// returns there with him checked in — whatever the clock says, closing
    /// time included (`daycareAttendance` skips the assumed check-out inside
    /// the fence) — and a phone elsewhere shows the quiet "someone's at
    /// daycare" line when the co-parent's is inside the fence. A day that
    /// never touches the fence shows nothing at all.
    ///
    /// Without the fence (location denied, no pin), the clock decides, as
    /// before: the drop-off slide from doors-open, the pick-up slide from the
    /// configured show time. Either way the sweep gesture is its own accident
    /// gate; after checkout a quiet "picked up at" receipt holds the slot.
    private func checkinSlot(now: Date, attendance: DaycareStatus.Attendance?) -> CheckinSlot {
        let settings = daycareSettings
        guard settings?.isDaycareDay(now) ?? !Calendar.current.isDateInWeekend(now) else {
            return .hidden
        }
        let geofenceMode = geofenceSliderMode
        if attendance != nil {
            if DaycareStatus.pickupVisible(
                now: now,
                showMinute: settings?.daycarePickupShowMinute
                    ?? DaycareStatus.defaultPickupShowMinute,
                geofenceMode: geofenceMode,
                nearDaycare: geofence.isNearDaycare
            ) {
                return .pickUp
            }
            return geofenceMode && partnerAtDaycare(now: now) ? .partnerAtDaycare : .hidden
        }
        let todays = checkEvents.prefix(while: { $0.timestamp >= dayStart }).filter { $0.timestamp <= now }
        if let pickedUpAt = todays.filter({ $0.type == .checkOut }).map(\.timestamp).max() {
            return .pickedUp(pickedUpAt)
        }
        if todays.contains(where: { $0.type == .notAttending }) { return .homeToday }
        if let assumed = DaycareStatus.assumedCheckOut(dayStart: dayStart,
                                                      closeMinute: daycareCloseMinute),
           now >= assumed {
            return .hidden
        }
        if DaycareStatus.dropoffVisible(
            now: now,
            openMinute: settings?.daycareOpenMinute ?? DaycareStatus.defaultOpenMinute,
            closeMinute: settings?.daycareCloseMinute ?? DaycareStatus.defaultCloseMinute,
            geofenceMode: geofenceMode,
            nearDaycare: geofence.isNearDaycare
        ) {
            return .dropOff
        }
        return geofenceMode && partnerAtDaycare(now: now) ? .partnerAtDaycare : .hidden
    }

    /// One-tap marker + the app-standard Undo toast (undo soft-deletes the
    /// marker, which also reverses any daycare-mode flip it caused).
    private func logCheck(_ type: CheckType, toast message: String) {
        guard let event = store.logCheck(type) else { return }
        // A marker-less day's Pick up is the only checkout Brightwheel's own
        // import never sees — close any nap still live the same way it would.
        if type == .checkOut {
            brightwheel.closeLiveNapOnCheckout(at: event.timestamp, context: context)
        }
        showToast(message, accent: AppColor.accentCheck) { store.softDelete(event) }
    }

    /// The whiteboard cheat sheet's answers, from the same @Query arrays the
    /// tiles use (newest first), through the builder the geofence drop-off
    /// notification shares — so the card and the banner never disagree.
    private func dropoffBoardInfo() -> DropoffBoardInfo {
        let s = settingsList.first
        return DropoffBoard.compute(
            name: baby?.name ?? "Baby",
            feeds: feeds.map { .init(timestamp: $0.timestamp, amountOz: $0.amountOz) },
            diapers: diapers.map { .init(timestamp: $0.timestamp, typeLabel: $0.type.label) },
            sleeps: sleeps.map { .init(startedAt: $0.startedAt, endedAt: $0.endedAt) },
            notes: noteEvents.map { .init(timestamp: $0.timestamp, text: $0.text,
                                          isFromDaycare: $0.isFromDaycare) },
            nightStartMinute: s?.nightStartMinute ?? 1200,
            nightEndMinute: s?.nightEndMinute ?? 480,
            dayStart: dayStart)
    }

    /// "Actually, taking him in" — clears today's home-today marker(s).
    private func undoHomeToday() {
        Haptics.tap()
        checkEvents
            .filter { $0.timestamp >= dayStart && $0.type == .notAttending }
            .forEach { store.softDelete($0) }
    }

    private func tileStatus(since date: Date?, now: Date, target: TimeInterval) -> TileStatus? {
        guard let date else { return nil }
        return TileStatus(
            value: TimeFormatting.since(date, now: now),
            urgency: .from(since: date, now: now, target: target)
        )
    }

    private func startSleep() {
        guard let event = store.startSleep() else { return }
        // Undo must also end the Live Activity startSleep began — softDelete alone
        // would strand a running lock-screen timer.
        showToast("Started sleep", accent: AppColor.accentSleep) { store.cancelSleep(event) }
    }

    /// Wake Up is easy to mis-tap and ending a timer is otherwise unrecoverable
    /// (nothing can make a sleep active again), so it gets the Undo toast every
    /// other action has, `emphasized` for extra dwell time and a bigger Undo
    /// target. A sub-minute sleep is discarded instead of logged — the edit
    /// sheet already treats "under a minute" as invalid, so persisting one
    /// would create a row that can't be re-saved.
    private func endSleep(_ sleep: SleepEvent) {
        if Date.now.timeIntervalSince(sleep.startedAt) < 60 {
            store.cancelSleep(sleep)
            showToast("Under a minute — not saved", accent: AppColor.accentSleep, emphasized: true) {
                store.resumeSleep(sleep)
            }
        } else {
            let duration = TimeFormatting.duration(from: sleep.startedAt, to: .now)
            store.stopSleep(sleep)
            showToast("Slept \(duration)", accent: AppColor.accentSleep, emphasized: true) {
                store.resumeSleep(sleep)
            }
        }
    }

    // MARK: Timeline

    /// The "Recent · last 24 hours" section. The insets default to the
    /// single column's; panes pass their own. `paneMode` words the empty
    /// state for layouts where the tiles aren't "above".
    @ViewBuilder
    private func timelineSection(leading: CGFloat = 16, trailing: CGFloat = 16,
                                 paneMode: Bool = false) -> some View {
        // Performance: assembled once per body, not once for isEmpty and again
        // for the ForEach.
        let entries = timelineEntries
        Section {
            if entries.isEmpty {
                timelineEmptyState(paneMode: paneMode)
                    .listRowBackground(Color.clear)
            } else {
                timelineRows(entries, leading: leading, trailing: trailing)
            }
        } header: {
            HStack {
                Text("Recent · last 24 hours").foregroundStyle(AppColor.text3)
                Spacer()
                // Deliberately quiet — an inline header affordance, not a log
                // tile: notes are far less frequent than feeds/diapers.
                Button("+ Add note") { activeSheet = .note }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppColor.accentNote)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add note")
                    .accessibilityHint("Writes a timestamped note on the timeline")
            }
        }
    }

    /// The timeline's empty state. `paneMode` words it for layouts where the
    /// tiles aren't "above".
    private func timelineEmptyState(paneMode: Bool) -> some View {
        EmptyStateView(
            emoji: "🍼💤💩",
            title: "No events yet",
            message: paneMode
                ? "Tap Feed, Sleep, or Diaper to log \(baby?.name ?? "Baby")'s first event."
                : "Tap a button above to log \(baby?.name ?? "Baby")'s first feed, sleep, or diaper."
        )
    }

    /// The timeline's rows, for a list: the NOW cap, the live daycare nap,
    /// then every entry with its tap and its swipe to delete. One builder for
    /// the "Recent" section of every list layout and for the journal card on
    /// the spread, so a row behaves the same wherever it is shown.
    @ViewBuilder
    private func timelineRows(_ entries: [TimelineEntry], leading: CGFloat,
                              trailing: CGFloat) -> some View {
        TimelineNowCap()
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: leading, bottom: 0, trailing: trailing))
        // Brightwheel's in-progress nap has no SleepEvent yet (the
        // pair imports whole at wake), so its live row is synthesized
        // here at the top — it started recently, so chronology holds.
        if let napStart = liveNapToday {
            LiveDaycareNapRow(start: napStart)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: leading, bottom: 0, trailing: trailing))
        }
        ForEach(entries) { entry in
            DayTimelineRow(entry: entry, loggedByPhoto: loggerPhoto[entry.loggedByID],
                           loggedByNameFallback: loggerName[entry.loggedByID])
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: leading, bottom: 0, trailing: trailing))
                .contentShape(Rectangle())
                .accessibilityIdentifier("timelineRow")
                // Media opens the full-size viewer; the editable four
                // open the edit sheet; the other daycare types are
                // read-only (swipe-to-delete still works).
                .onTapGesture {
                    if case .media(let e) = entry {
                        viewingMedia = MediaViewing(events: [e])
                    } else if case .mediaGroup(let events) = entry {
                        viewingMedia = MediaViewing(events: events)
                    } else if entry.isEditable, !entry.isActiveSleep {
                        // A running sleep has no end to edit yet — its
                        // controls live on the active card above.
                        editing = entry
                    }
                }
                // The row is tappable but nothing tells VoiceOver that —
                // without the trait + hint it reads as inert text.
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Edits this entry")
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { delete(entry) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
        }
    }

    /// Logger id → avatar photo, for participants who set one. Absent keys fall
    /// back to the colored-initial badge in the row.
    private var loggerPhoto: [UUID: Data] {
        Dictionary(uniqueKeysWithValues: participants.compactMap { p in
            p.photoData.map { (p.id, $0) }
        })
    }

    /// Logger id → display name, the row's fallback when an event's denormalized
    /// name is empty (older builds' records) — a known logger must never render
    /// as the silhouette badge.
    private var loggerName: [UUID: String] {
        Dictionary(participants.compactMap { p in
            p.displayName.isEmpty ? nil : (p.id, p.displayName)
        }, uniquingKeysWith: { a, _ in a })
    }

    private var timelineEntries: [TimelineEntry] {
        let since = Calendar.current.date(byAdding: .hour, value: -24, to: .now) ?? .now
        var entries: [TimelineEntry] = []
        entries += feeds.prefix(while: { $0.timestamp >= since }).map(TimelineEntry.feed)
        // Active sleeps ride the timeline too — a nap in progress shows as a
        // growing bar with a counting label, not a gap until it ends.
        // Newest-first, so each window is a prefix. Sleeps additionally carry
        // ACTIVE ones of any age: exactly the elements of
        // `filter { $0.isActive || $0.startedAt >= since }`, in the same order.
        let allSleeps = sleeps
        let recentSleeps = allSleeps.prefix(while: { $0.startedAt >= since })
        entries += recentSleeps.map(TimelineEntry.sleep)
        // An active sleep older than the window still rides the timeline.
        entries += allSleeps[recentSleeps.endIndex...].filter(\.isActive).map(TimelineEntry.sleep)
        entries += diapers.prefix(while: { $0.timestamp >= since }).map(TimelineEntry.diaper)
        entries += noteEvents.prefix(while: { $0.timestamp >= since }).map(TimelineEntry.note)
        entries += activityEvents.prefix(while: { $0.timestamp >= since }).map(TimelineEntry.activity)
        entries += mediaEvents.prefix(while: { $0.timestamp >= since }).map(TimelineEntry.media)
        entries += checkEvents.prefix(while: { $0.timestamp >= since }).map(TimelineEntry.check)
        entries += medicationEvents.prefix(while: { $0.timestamp >= since }).map(TimelineEntry.medication)
        entries += healthCheckEvents.prefix(while: { $0.timestamp >= since }).map(TimelineEntry.healthCheck)
        entries += moodEvents.prefix(while: { $0.timestamp >= since }).map(TimelineEntry.mood)
        entries += pottyEvents.prefix(while: { $0.timestamp >= since }).map(TimelineEntry.potty)
        entries += milestoneEvents.prefix(while: { $0.timestamp >= since }).map(TimelineEntry.milestone)
        entries += staffNoteEvents.prefix(while: { $0.timestamp >= since }).map(TimelineEntry.staffNote)
        // Never render one event twice: duplicate rows sharing an id can exist
        // between sweeps (inbound upsert races, legacy data).
        var seen = Set<UUID>()
        let deduped = entries
            .sorted { $0.sortDate > $1.sortDate }
            .filter { seen.insert($0.id).inserted }
        return Self.groupingPhotoBursts(deduped)
    }

    /// Collapses photo bursts into one row: daycare posts several photos
    /// with the same (or near-identical) timestamp, and a strip of
    /// thumbnails on one "Photos (2)" row reads better than a stack of
    /// identical "Photo" rows. Adjacent photos within a minute of each
    /// other, same origin, chain into a group; videos and lone photos keep
    /// their plain rows.
    static func groupingPhotoBursts(_ entries: [TimelineEntry]) -> [TimelineEntry] {
        var grouped: [TimelineEntry] = []
        var burst: [MediaEvent] = []
        func flush() {
            if burst.count > 1 {
                grouped.append(.mediaGroup(burst))
            } else if let only = burst.first {
                grouped.append(.media(only))
            }
            burst = []
        }
        for entry in entries {
            if case .media(let e) = entry, e.kind == .photo {
                if let last = burst.last,
                   abs(last.timestamp.timeIntervalSince(e.timestamp)) <= 60,
                   last.isFromDaycare == e.isFromDaycare {
                    burst.append(e)
                } else {
                    flush()
                    burst = [e]
                }
            } else {
                flush()
                grouped.append(entry)
            }
        }
        flush()
        return grouped
    }

    // MARK: Actions

    private func delete(_ entry: TimelineEntry) {
        // A running sleep can't go through the generic soft-delete — that
        // would strand its Live Activity and wake alarm. cancelSleep tears
        // those down too, and Undo resumes the timer whole.
        if case .sleep(let e) = entry, e.isActive {
            Haptics.warning()
            store.cancelSleep(e)
            showToast("Deleted", accent: AppColor.urgencyAmber) { store.resumeSleep(e) }
            return
        }
        // A photo burst deletes as one gesture — all of it, one Undo.
        if case .mediaGroup(let events) = entry {
            Haptics.warning()
            events.forEach { store.softDelete($0) }
            showToast("Deleted \(Plural.count(events.count, "photo"))",
                      accent: AppColor.urgencyAmber) {
                events.forEach { store.restore($0) }
            }
            return
        }
        let event: any SoftDeletable
        switch entry {
        case .feed(let e): event = e
        case .sleep(let e): event = e
        case .diaper(let e): event = e
        case .note(let e): event = e
        case .activity(let e): event = e
        case .media(let e): event = e
        case .mediaGroup(let events): event = events[0]   // unreachable — handled above
        case .check(let e): event = e
        case .medication(let e): event = e
        case .healthCheck(let e): event = e
        case .mood(let e): event = e
        case .potty(let e): event = e
        case .milestone(let e): event = e
        case .staffNote(let e): event = e
        }
        Haptics.warning()
        store.softDelete(event)
        // Swipe-delete is fast and easy to fire by accident — offer the same Undo
        // affordance a log gets, restoring the exact event on tap.
        showToast("Deleted", accent: AppColor.urgencyAmber) { store.restore(event) }
    }

    private func showToast(_ message: String, accent: Color = AppColor.accentFeed, emphasized: Bool = false, undo: @escaping () -> Void) {
        toast = ToastData(message: message, accent: accent, undo: undo, emphasized: emphasized)
    }

    // MARK: Deferred setup & spotlights

    private var showChecklist: Bool {
        !prefs.demoModeEnabled && !setup.dismissedChecklist
    }

    /// What the reminder would say right now, for the just-in-time offer.
    private var reminderContextLine: String? {
        guard let last = feeds.first?.timestamp else { return nil }
        return "Next bottle around \(TimeFormatting.clock(last.addingTimeInterval(targetFeed(after: last))))"
    }

    /// The contextual moments that follow a feed log: the rhythm spotlight plays
    /// after the very first feed; a later feed gets the one just-in-time
    /// reminders offer. `requestPrompt` keeps it to one prompt per session and
    /// none in demo mode; the guards keep it from landing over another sheet.
    private func feedLogged() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))   // let the logged toast play out
            guard !Task.isCancelled, noSheetUp else { return }
            if !setup.hasShown(.rhythm) {
                guard setup.requestPrompt() else { return }
                spotlight = .rhythm
            } else if !setup.reminderOfferShown,
                      !setup.isComplete(.reminders, settings: settingsList.first) {
                guard setup.requestPrompt() else { return }
                setup.reminderOfferShown = true
                questSheet = .reminders
            }
        }
    }

    private var noSheetUp: Bool {
        activeSheet == nil && editing == nil && !showSettings
            && questSheet == nil && spotlight == nil && editingSnoo == nil
    }

    /// Rhythm spotlight → "Tune your rhythm": swap the spotlight for the quest.
    private func chainIntoRhythmQuest() {
        spotlight = nil
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.45))   // let the sheet dismiss settle
            questSheet = .rhythm
        }
    }

}

/// The two keyed animations every Home layout puts on the block holding the
/// log tiles and the sleep card: keyed to the sleep state (not withAnimation at
/// the action sites) so CloudKit- and Siri-initiated starts animate too, and to
/// daycare attendance, which arrives via Brightwheel sync, never a tap.
private struct SleepAndDaycareAnimations: ViewModifier {
    let sleeping: Bool
    let attending: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.8),
                       value: sleeping)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3),
                       value: attending)
    }
}

#Preview {
    HomeView()
        .modelContainer(AppModelContainer.preview)
}
