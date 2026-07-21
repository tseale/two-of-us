import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query private var babies: [Baby]
    @Query private var participants: [Participant]
    @Query private var settingsList: [SharedSettings]
    @Query(filter: #Predicate<FeedEvent> { $0.deletedAt == nil }, sort: \FeedEvent.timestamp, order: .reverse)
    private var feeds: [FeedEvent]
    @Query(filter: #Predicate<SleepEvent> { $0.deletedAt == nil }, sort: \SleepEvent.startedAt, order: .reverse)
    private var sleeps: [SleepEvent]
    @Query(filter: #Predicate<DiaperEvent> { $0.deletedAt == nil }, sort: \DiaperEvent.timestamp, order: .reverse)
    private var diapers: [DiaperEvent]
    @Query(filter: #Predicate<PlanSlot> { $0.deletedAt == nil })
    private var planSlots: [PlanSlot]
    @Query(filter: #Predicate<PlanOverride> { $0.deletedAt == nil })
    private var planOverrides: [PlanOverride]

    @State private var activeSheet: ActiveSheet?
    @State private var editing: TimelineEntry?
    @State private var toast: ToastData?
    @State private var showSettings = false
    @State private var questSheet: SetupQuest?
    @State private var spotlight: SetupSpotlight?
    @State private var prefs = LocalPrefs.shared
    @State private var setup = SetupProgress.shared
    @State private var router = DeepLinkRouter.shared
    @State private var didApplyDebugScreen = false
    /// Start of the current day. Advanced by a task at midnight so the "today"
    /// ribbon, counts, and 24h window refresh even if the app sits foregrounded
    /// across midnight with nothing new logged (a @Query change would otherwise
    /// be the only trigger).
    @State private var dayStart = Calendar.current.startOfDay(for: .now)

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
                        // Small top inset keeps the profile/settings row off the
                        // status bar now the nav bar is hidden.
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 2, trailing: 16))
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
                                SleepActiveCard(sleep: sleep, now: ctx.date) { endSleep(sleep) }
                                    .transition(.opacity.combined(with: .scale(0.96, anchor: .top)))
                            }
                            // Inside the ticking TimelineView so the row stays
                            // honest on a phone left open overnight: 11pm passing
                            // drops the 11pm row and surfaces the 3am one without
                            // needing a log or sync to trigger a render.
                            if let next = upNextOccurrence(now: ctx.date) {
                                upNextRow(next)
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
                }
            }
            .sheet(item: $editing) { entry in
                EditEventSheet(entry: entry)
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
            .loggedToast($toast)
            // A tapped Feed/Diaper widget stages a sheet here: onChange catches a
            // warm launch (Home already up), onAppear a cold launch / tab switch.
            .onChange(of: router.pendingLog) { _, _ in consumeDeepLink() }
            .onAppear { consumeDeepLink() }
            .task { await advanceAtMidnight() }
        }
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
        case .feed:   activeSheet = .feed
        case .diaper: activeSheet = .diaper
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
        RibbonMark.forDay(dayStart, feeds: feeds, sleeps: sleeps, diapers: diapers)
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
            feedReminderArmed: feedReminderArmed(now: now),
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
        return last.addingTimeInterval(targetFeed) > now
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

    // MARK: Up next (schedule glance)

    /// The next *planned, assigned* slot within 8 hours — the one line that
    /// answers "who's up". Predictions and unassigned slots stay off Home; the
    /// Schedule tab owns the full picture.
    private func upNextOccurrence(now: Date) -> ScheduleOccurrence? {
        guard !planSlots.isEmpty else { return nil }
        let engine = ScheduleEngine(slots: planSlots, overrides: planOverrides,
                                    feeds: feeds, sleeps: sleeps,
                                    targetFeedInterval: targetFeed, now: now)
        // First *planned, assigned* occurrence — a nearer prediction or
        // unassigned slot must not hide the row.
        return engine.occurrences(lookback: 0, horizon: 8 * 3600)
            .first { $0.isPinned && $0.status == .upcoming && $0.assignedToID != nil }
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
    /// (nothing can make a sleep active again), so it gets the same Undo toast
    /// every other action has. A sub-minute sleep is discarded instead of logged
    /// — the edit sheet already treats "under a minute" as invalid, so persisting
    /// one would create a row that can't be re-saved.
    private func endSleep(_ sleep: SleepEvent) {
        if Date.now.timeIntervalSince(sleep.startedAt) < 60 {
            store.cancelSleep(sleep)
            showToast("Under a minute — not saved", accent: AppColor.accentSleep) {
                store.resumeSleep(sleep)
            }
        } else {
            let duration = TimeFormatting.duration(from: sleep.startedAt, to: .now)
            store.stopSleep(sleep)
            showToast("Slept \(duration)", accent: AppColor.accentSleep) {
                store.resumeSleep(sleep)
            }
        }
    }

    // MARK: Timeline

    @ViewBuilder
    private var timelineSection: some View {
        Section {
            if timelineEntries.isEmpty {
                EmptyStateView(
                    emoji: "🍼💤💩",
                    title: "No events yet",
                    message: "Tap a button above to log \(baby?.name ?? "Baby")'s first feed, sleep, or diaper."
                )
                .listRowBackground(Color.clear)
            } else {
                TimelineNowCap()
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                ForEach(timelineEntries) { entry in
                    DayTimelineRow(entry: entry, loggedByPhoto: loggerPhoto[entry.loggedByID])
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .contentShape(Rectangle())
                        .accessibilityIdentifier("timelineRow")
                        .onTapGesture { editing = entry }
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
        } header: {
            Text("Recent · last 24 hours").foregroundStyle(AppColor.text3)
        }
    }

    /// Logger id → avatar photo, for participants who set one. Absent keys fall
    /// back to the colored-initial badge in the row.
    private var loggerPhoto: [UUID: Data] {
        Dictionary(uniqueKeysWithValues: participants.compactMap { p in
            p.photoData.map { (p.id, $0) }
        })
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
        let event: any SoftDeletable
        switch entry {
        case .feed(let e): event = e
        case .sleep(let e): event = e
        case .diaper(let e): event = e
        }
        store.softDelete(event)
        Haptics.warning()
        // Swipe-delete is fast and easy to fire by accident — offer the same Undo
        // affordance a log gets, restoring the exact event on tap.
        showToast("Deleted", accent: AppColor.urgencyAmber) { store.restore(event) }
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
        activeSheet == nil && editing == nil && !showSettings
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

}

#Preview {
    HomeView()
        .modelContainer(AppModelContainer.preview)
}
