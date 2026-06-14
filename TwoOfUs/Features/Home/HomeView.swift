import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
    @State private var router = DeepLinkRouter.shared

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
                        // 12pt matches the tile grid spacing, so the active sleep
                        // card reads as the Sleep row transformed in place.
                        VStack(spacing: 12) {
                            logButtons(now: ctx.date)
                            if let sleep = activeSleep {
                                SleepActiveCard(sleep: sleep, now: ctx.date) { store.stopSleep(sleep) }
                                    .transition(.opacity.combined(with: .scale(0.96, anchor: .top)))
                            }
                        }
                        // Keyed to the sleep state (not withAnimation at the action
                        // sites) so CloudKit- and Siri-initiated starts animate too.
                        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.8),
                                   value: activeSleep != nil)
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
                case .diaper: DiaperSheet(onLogged: { message, undo in
                    showToast(message, accent: AppColor.accentDiaper, undo: undo)
                })
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
                    // Only offer "Tune your rhythm" while the rhythm quest is still
                    // open — hide it once the rhythm's already been customized.
                    onTuneRhythm: setup.incompleteQuests(role: prefs.syncRole, settings: settingsList.first).contains(.rhythm)
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
            // A tapped Feed/Diaper widget stages a sheet here: onChange catches a
            // warm launch (Home already up), onAppear a cold launch / tab switch.
            .onChange(of: router.pendingLog) { _, _ in consumeDeepLink() }
            .onAppear { consumeDeepLink() }
        }
    }

    /// Opens the log sheet a tapped widget asked for, then clears the request so
    /// it doesn't re-fire on the next appear.
    private func consumeDeepLink() {
        guard let target = router.pendingLog else { return }
        switch target {
        case .feed:   activeSheet = .feed
        case .diaper: activeSheet = .diaper
        }
        router.pendingLog = nil
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            Avatar(photoData: baby?.photoData, name: baby?.name ?? "Baby",
                   colorHex: ParticipantColors.babyHex, size: 60)
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

    private func logButtons(now: Date) -> some View {
        LogButtons(
            feedStatus: tileStatus(since: feeds.first?.timestamp, now: now, target: targetFeed),
            sleepStatus: activeSleep == nil
                ? tileStatus(since: lastSleepEnd, now: now, target: UrgencyDefaults.sleep) : nil,
            diaperStatus: tileStatus(since: diapers.first?.timestamp, now: now, target: UrgencyDefaults.diaper),
            feedHint: feedHint(now: now),
            sleepHint: sleepHint(now: now),
            sleepDetail: lastNapDetail,
            sleepActive: activeSleep != nil,
            onFeed: { activeSheet = .feed },
            onSleep: startSleep,
            onDiaper: { activeSheet = .diaper }
        )
    }

    /// The Feed tile says what's next, not just what happened: the projected
    /// next-bottle time, from the same target-interval math as the reminders.
    private func feedHint(now: Date) -> String {
        guard let last = feeds.first?.timestamp else { return "log a bottle" }
        let next = last.addingTimeInterval(targetFeed)
        return next < now
            ? "bottle was due ~\(TimeFormatting.clock(next))"
            : "next bottle ~\(TimeFormatting.clock(next))"
    }

    /// The wide Sleep row has horizontal room the square tiles don't: a
    /// trailing "last nap" stat — the number you reconstruct in your head
    /// when deciding whether baby is ready to go down again.
    private var lastNapDetail: TileDetail? {
        guard let last = sleeps.first(where: { $0.endedAt != nil }),
              let end = last.endedAt else { return nil }
        return TileDetail(label: "last nap",
                          value: TimeFormatting.duration(from: last.startedAt, to: end))
    }

    /// Same idea for Sleep: the projected next nap, from the last wake time
    /// plus the sleep target that already drives the tile's urgency dot.
    private func sleepHint(now: Date) -> String {
        guard let lastEnd = lastSleepEnd else { return "start timer" }
        let next = lastEnd.addingTimeInterval(UrgencyDefaults.sleep)
        return next < now
            ? "nap was due ~\(TimeFormatting.clock(next))"
            : "next nap ~\(TimeFormatting.clock(next))"
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
        showToast("Started sleep", accent: AppColor.accentSleep) { store.softDelete(event) }
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

    private func showToast(_ message: String, accent: Color = AppColor.accentFeed, undo: @escaping () -> Void) {
        toast = ToastData(message: message, accent: accent, undo: undo)
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
    /// Returns a user-facing message when the parsed values are out of range
    /// (nothing is written), or nil on success.
    @discardableResult
    private func applyParsed(_ p: BabyIntelligence.ParsedLog) -> String? {
        if let problem = BabyIntelligence.outOfRangeMessage(for: p) { return problem }
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
            showToast("Logged \(type.label.lowercased()) diaper", accent: AppColor.accentDiaper) { store.softDelete(event) }
        case "sleepStart":
            if let event = store.startSleep(at: date) {
                showToast("Started sleep", accent: AppColor.accentSleep) { store.softDelete(event) }
            }
        case "sleepEnd":
            if let active = activeSleep {
                store.stopSleep(active, at: date)
                showToast("Ended sleep", accent: AppColor.accentSleep) {}
            }
        default:
            break
        }
        Haptics.tap()
        return nil
    }
}

#Preview {
    HomeView()
        .modelContainer(AppModelContainer.preview)
}
