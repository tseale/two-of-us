import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var context

    @Query private var babies: [Baby]
    @Query private var settingsList: [SharedSettings]
    @Query(filter: #Predicate<FeedEvent> { $0.deletedAt == nil }, sort: \FeedEvent.timestamp, order: .reverse)
    private var feeds: [FeedEvent]
    @Query(filter: #Predicate<SleepEvent> { $0.deletedAt == nil }, sort: \SleepEvent.startedAt, order: .reverse)
    private var sleeps: [SleepEvent]
    @Query(filter: #Predicate<DiaperEvent> { $0.deletedAt == nil }, sort: \DiaperEvent.timestamp, order: .reverse)
    private var diapers: [DiaperEvent]

    @State private var activeSheet: ActiveSheet?
    @State private var editing: TimelineEntry?
    @State private var toast: ToastData?
    @State private var showSettings = false
    @State private var showNLLog = false
    @State private var questSheet: SetupQuest?
    @State private var spotlight: SetupSpotlight?
    @State private var prefs = LocalPrefs.shared
    @State private var setup = SetupProgress.shared

    private enum ActiveSheet: String, Identifiable { case feed, diaper; var id: String { rawValue } }

    private var baby: Baby? { babies.first }
    private var store: EventStore { EventStore(context: context) }
    private var activeSleep: SleepEvent? { sleeps.first { $0.isActive } }
    private var targetFeed: TimeInterval {
        TimeInterval((settingsList.first?.targetFeedIntervalMinutes ?? 180) * 60)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                    TodayRibbonCard(
                        marks: todayMarks,
                        feedCount: todaySummary?.feedCount ?? 0,
                        sleepSeconds: todaySummary?.sleepSeconds ?? 0,
                        diaperCount: todaySummary?.diaperCount ?? 0
                    )
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        VStack(spacing: 18) {
                            statusRow(now: ctx.date)
                            if let sleep = activeSleep {
                                SleepActiveCard(sleep: sleep, now: ctx.date) { store.stopSleep(sleep) }
                            }
                            logButtons
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

                // The deferred-setup checklist sits where an empty timeline
                // leaves dead space — the logging UI above stays untouched.
                if showChecklist {
                    Section {
                        SetupChecklistCard(
                            quests: setup.activeQuests(role: prefs.syncRole),
                            isComplete: { setup.isComplete($0, settings: settingsList.first) },
                            onQuest: { questSheet = $0 },
                            onDismiss: { withAnimation(.easeInOut) { setup.dismissedChecklist = true } }
                        )
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }

                timelineSection
            }
            .listStyle(.plain)
            .background(AppColor.bg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if BabyIntelligence.isAvailable {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showNLLog = true } label: { Image(systemName: "sparkles") }
                            .tint(AppColor.accentFeed)
                            .accessibilityLabel("Log in words")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .tint(AppColor.text3)
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .feed: FeedSheet(onLogged: { message, undo in
                    showToast(message, undo: undo)
                    feedLogged()
                })
                case .diaper: DiaperSheet(onLogged: showToast)
                }
            }
            .sheet(item: $editing) { entry in
                EditEventSheet(entry: entry)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showNLLog) {
                NLLogSheet(onApply: applyParsed)
                    .presentationDetents([.medium])
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
                    onTuneRhythm: setup.activeQuests(role: prefs.syncRole).contains(.rhythm)
                        ? chainIntoRhythmQuest : nil
                )
            }
            #if DEBUG
            .onAppear {
                // Dev-only: `-forceSpotlight rhythm` presents the spotlight on launch.
                if let raw = UserDefaults.standard.string(forKey: "forceSpotlight"),
                   let forced = SetupSpotlight(rawValue: raw) {
                    spotlight = forced
                }
            }
            #endif
            .loggedToast($toast)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(baby?.name ?? "Baby")
                    .font(AppFont.hero())
                if let dob = baby?.dateOfBirth {
                    Text(TimeFormatting.age(from: dob))
                        .font(.subheadline)
                        .foregroundStyle(AppColor.text2)
                }
            }
            Spacer()
        }
    }

    // MARK: Status row

    private func statusRow(now: Date) -> some View {
        HStack(spacing: 8) {
            StatusPill(
                emoji: "🍼",
                value: feeds.first.map { TimeFormatting.since($0.timestamp, now: now) } ?? "—",
                label: "SINCE FEED",
                urgency: .from(since: feeds.first?.timestamp, now: now, target: targetFeed)
            )
            if activeSleep == nil {
                StatusPill(
                    emoji: "💤",
                    value: lastSleepEnd.map { TimeFormatting.since($0, now: now) } ?? "—",
                    label: "SINCE SLEEP",
                    urgency: .from(since: lastSleepEnd, now: now, target: UrgencyDefaults.sleep)
                )
            }
            StatusPill(
                emoji: "💩",
                value: diapers.first.map { TimeFormatting.since($0.timestamp, now: now) } ?? "—",
                label: "SINCE DIAPER",
                urgency: .from(since: diapers.first?.timestamp, now: now, target: UrgencyDefaults.diaper)
            )
        }
    }

    private var lastSleepEnd: Date? {
        sleeps.first(where: { $0.endedAt != nil })?.endedAt
    }

    // MARK: Today ribbon

    private var todayMarks: [RibbonMark] {
        RibbonMark.forDay(.now, feeds: feeds, sleeps: sleeps, diapers: diapers)
    }

    private var todaySummary: DaySummary? {
        StatsEngine(feeds: feeds, sleeps: sleeps, diapers: diapers)
            .dailySummaries(days: 1).first
    }

    // MARK: Log buttons

    private var logButtons: some View {
        LogButtons(
            sleepActive: activeSleep != nil,
            onFeed: { activeSheet = .feed },
            onSleep: startSleep,
            onDiaper: { activeSheet = .diaper }
        )
    }

    private func startSleep() {
        guard let event = store.startSleep() else { return }
        showToast("Started sleep") { store.softDelete(event) }
    }

    // MARK: Timeline

    @ViewBuilder
    private var timelineSection: some View {
        Section {
            if timelineEntries.isEmpty {
                EmptyStateView(
                    emoji: "🍼",
                    title: "No events yet",
                    message: "Tap a button above to log \(baby?.name ?? "Baby")'s first feed."
                )
                .listRowBackground(Color.clear)
            } else {
                TimelineNowCap()
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                ForEach(timelineEntries) { entry in
                    DayTimelineRow(entry: entry)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .contentShape(Rectangle())
                        .onTapGesture { editing = entry }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { delete(entry) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        } header: {
            Text("Recent").foregroundStyle(AppColor.text3)
        }
    }

    private var timelineEntries: [TimelineEntry] {
        let since = Calendar.current.date(byAdding: .hour, value: -24, to: .now) ?? .now
        var entries: [TimelineEntry] = []
        entries += feeds.filter { $0.timestamp >= since }.map(TimelineEntry.feed)
        entries += sleeps.filter { !$0.isActive && $0.startedAt >= since }.map(TimelineEntry.sleep)
        entries += diapers.filter { $0.timestamp >= since }.map(TimelineEntry.diaper)
        return entries.sorted { $0.sortDate > $1.sortDate }
    }

    // MARK: Actions

    private func delete(_ entry: TimelineEntry) {
        switch entry {
        case .feed(let e): store.softDelete(e)
        case .sleep(let e): store.softDelete(e)
        case .diaper(let e): store.softDelete(e)
        }
        Haptics.warning()
    }

    private func showToast(_ message: String, undo: @escaping () -> Void) {
        toast = ToastData(message: message, undo: undo)
    }

    // MARK: Deferred setup & spotlights

    private var showChecklist: Bool {
        !prefs.demoModeEnabled && !setup.dismissedChecklist
    }

    /// What the reminder would say right now, for the just-in-time offer.
    private var reminderContextLine: String? {
        guard let last = feeds.first?.timestamp else { return nil }
        return "Next bottle around \(TimeFormatting.clock(last.addingTimeInterval(targetFeed)))"
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
        activeSheet == nil && editing == nil && !showSettings && !showNLLog
            && questSheet == nil && spotlight == nil
    }

    /// Rhythm spotlight → "Tune your rhythm": swap the spotlight for the quest.
    private func chainIntoRhythmQuest() {
        spotlight = nil
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.45))   // let the sheet dismiss settle
            questSheet = .rhythm
        }
    }

    // MARK: Natural-language logging

    /// Turns a parsed entry into the matching store write, backdating by the
    /// model's `minutesAgo`. Mirrors the tap-driven log paths (toast + undo).
    private func applyParsed(_ p: BabyIntelligence.ParsedLog) {
        let date = Calendar.current.date(byAdding: .minute, value: -max(0, p.minutesAgo), to: .now) ?? .now
        switch p.kind {
        case "feed":
            let oz = p.amountOz ?? settingsList.first?.defaultFeedOz ?? 4
            let event = store.logFeed(amountOz: oz, at: date)
            showToast("Logged \(OzFormat.string(oz)) oz feed") { store.softDelete(event) }
            feedLogged()
        case "diaper":
            let type = DiaperType(rawValue: p.diaperType ?? "wet") ?? .wet
            let event = store.logDiaper(type, at: date)
            showToast("Logged \(type.label.lowercased()) diaper") { store.softDelete(event) }
        case "sleepStart":
            if let event = store.startSleep(at: date) {
                showToast("Started sleep") { store.softDelete(event) }
            }
        case "sleepEnd":
            if let active = activeSleep {
                store.stopSleep(active, at: date)
                showToast("Ended sleep") {}
            }
        default:
            break
        }
        Haptics.tap()
    }
}

#Preview {
    HomeView()
        .modelContainer(AppModelContainer.preview)
}
