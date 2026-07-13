import SwiftUI
import SwiftData
import CloudKit

/// Settings shell. A baby profile header + your identity card, then shared
/// settings (Full role), per-user prefs, co-parent sharing, a "Manage data" link,
/// and an About footer. Editing baby / your profile happens in focused sheets;
/// everything else is inline with Apple-Settings-style colored icon rows.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var babies: [Baby]
    @Query private var settingsList: [SharedSettings]
    @Query private var participants: [Participant]
    @State private var prefs = LocalPrefs.shared
    @State private var setup = SetupProgress.shared
    @State private var share: CKShare?
    @State private var showShareSheet = false
    @State private var preparingShare = false
    /// The underlying error when preparing the invite fails — drives an alert
    /// instead of the button silently doing nothing.
    @State private var shareError: String?
    @State private var showBabyEdit = false
    @State private var showProfileEdit = false
    @State private var questSheet: SetupQuest?
    // Confirmation gates for the irreversible sharing actions.
    @State private var showLeaveConfirm = false
    @State private var showStopSharingConfirm = false
    @State private var participantToRemove: Participant?

    private var baby: Baby? { babies.first }
    private var settings: SharedSettings? { settingsList.first }
    private var store: EventStore { EventStore(context: context) }

    /// The local user's own participant record (for the "You" card).
    private var me: Participant? {
        participants.first { $0.id == prefs.myParticipantID } ?? participants.first
    }

    /// This device's app role. Loggers can't change shared baby/feeding settings.
    private var myRole: ParticipantRole {
        participants.first { $0.id == prefs.myParticipantID }?.role ?? .full
    }
    private var canEditShared: Bool { myRole == .full }

    var body: some View {
        NavigationStack {
            Form {
                babySection
                youSection
                setupSection

                if let settings, canEditShared {
                    Section("Feeding") {
                        Stepper(value: Binding(get: { settings.targetFeedIntervalMinutes },
                                               set: { store.updateSettings(targetFeedIntervalMinutes: $0) }),
                                in: 60...360, step: 15) {
                            SettingsIconLabel(
                                title: "Feed every \(intervalLabel(settings.targetFeedIntervalMinutes))",
                                systemImage: "timer", tint: AppColor.accentFeed)
                        }
                        // Common presets for quick selection.
                        HStack(spacing: 8) {
                            ForEach([120, 150, 180, 240], id: \.self) { mins in
                                let selected = settings.targetFeedIntervalMinutes == mins
                                Button(intervalLabel(mins)) {
                                    store.updateSettings(targetFeedIntervalMinutes: mins)
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(selected ? AppColor.accentFeed : AppColor.text2)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(selected ? AppColor.accentFeed.opacity(0.15) : AppColor.card2,
                                            in: Capsule())
                            }
                            Spacer()
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("Appearance") {
                    Picker(selection: $prefs.appearance) {
                        ForEach(Appearance.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    } label: {
                        SettingsIconLabel(title: "Theme", systemImage: "circle.lefthalf.filled",
                                          tint: AppColor.accentSleep)
                    }
                }

                coParentSection

                Section {
                    Toggle(isOn: $prefs.feedReminderEnabled) {
                        SettingsIconLabel(title: "Feed reminder", systemImage: "bell.badge",
                                          tint: AppColor.urgencyAmber)
                    }
                    .onChange(of: prefs.feedReminderEnabled) { _, on in
                        Task { await updateFeedAlarm(enabled: on) }
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("Alerts you when the next feed is due — even on Silent or Focus. This device only.")
                }

                Section {
                    Toggle(isOn: $prefs.notifyFeed) {
                        SettingsIconLabel(title: "Feeds", systemImage: "drop.fill", tint: AppColor.accentFeed)
                    }
                    .onChange(of: prefs.notifyFeed) { _, _ in notificationsChanged() }
                    Toggle(isOn: $prefs.notifySleep) {
                        SettingsIconLabel(title: "Sleep", systemImage: "moon.fill", tint: AppColor.accentSleep)
                    }
                    .onChange(of: prefs.notifySleep) { _, _ in notificationsChanged() }
                    Toggle(isOn: $prefs.notifyDiaper) {
                        SettingsIconLabel(title: "Diapers", systemImage: "leaf.fill", tint: AppColor.accentDiaper)
                    }
                    .onChange(of: prefs.notifyDiaper) { _, _ in notificationsChanged() }
                } header: {
                    Text("When your co-parent logs")
                } footer: {
                    Text("A quiet heads-up — with their photo — when the other parent logs. You're never notified for your own entries.")
                }

                Section {
                    Toggle(isOn: $prefs.gentleRemindersEnabled) {
                        SettingsIconLabel(title: "Gentle reminders", systemImage: "bell", tint: AppColor.urgencyAmber)
                    }
                    .onChange(of: prefs.gentleRemindersEnabled) { _, _ in notificationsChanged() }
                    Toggle(isOn: $prefs.notifyMilestones) {
                        SettingsIconLabel(title: "Daily summary", systemImage: "chart.bar.fill", tint: AppColor.accentSleep)
                    }
                    .onChange(of: prefs.notifyMilestones) { _, _ in notificationsChanged() }
                } footer: {
                    Text("Soft “feed due / diaper check” nudges you can log or snooze right from the lock screen, plus an end-of-day recap. The feed nudge stays silent while the Feed reminder alarm is on, so you’re never told twice.")
                }

                Section {
                    Toggle(isOn: $prefs.quietHoursEnabled) {
                        SettingsIconLabel(title: "Quiet hours", systemImage: "moon.zzz.fill", tint: .gray)
                    }
                    .onChange(of: prefs.quietHoursEnabled) { _, _ in notificationsChanged() }
                    if prefs.quietHoursEnabled {
                        DatePicker("From", selection: quietStart, displayedComponents: .hourAndMinute)
                        DatePicker("To", selection: quietEnd, displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("Quiet hours")
                } footer: {
                    Text("Mutes co-parent and summary notifications overnight. The Feed reminder alarm still breaks through.")
                }

                Section {
                    NavigationLink {
                        ManageDataView()
                    } label: {
                        SettingsIconLabel(title: "Manage data", systemImage: "externaldrive", tint: .gray)
                    }
                }

                demoSection
                aboutSection
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showShareSheet) {
                if let share {
                    CloudShareView(
                        share: share,
                        itemTitle: (baby?.name.isEmpty == false) ? "\(baby!.name) — Two of Us" : "Two of Us",
                        itemThumbnail: baby?.photoData
                    )
                }
            }
            .alert("Couldn't update sharing", isPresented: Binding(
                get: { shareError != nil }, set: { if !$0 { shareError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(shareError ?? "")
            }
            .sheet(isPresented: $showBabyEdit) {
                if let baby { BabyEditSheet(baby: baby) }
            }
            .sheet(isPresented: $showProfileEdit) {
                ProfileEditSheet()
            }
            .sheet(item: $questSheet) { quest in
                switch quest {
                case .rhythm: RhythmQuestSheet()
                case .reminders: RemindersQuestSheet()
                }
            }
        }
    }

    // MARK: Finish setting up

    /// Quests deferred out of onboarding that haven't been done yet — the
    /// persistent home for anything the Home checklist card was dismissed with.
    @ViewBuilder private var setupSection: some View {
        let pending = setup.incompleteQuests(role: prefs.syncRole, settings: settings)
        if !prefs.demoModeEnabled && !pending.isEmpty {
            Section("Finish setting up") {
                ForEach(pending) { quest in
                    Button { questSheet = quest } label: {
                        HStack {
                            SettingsIconLabel(title: quest.title, systemImage: quest.icon,
                                              tint: quest.tint)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(AppColor.text3)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Baby profile header

    @ViewBuilder private var babySection: some View {
        Section {
            if canEditShared {
                Button { showBabyEdit = true } label: { babyHeader(showChevron: true) }
                    .buttonStyle(.plain)
            } else {
                babyHeader(showChevron: false)
            }
        }
    }

    private func babyHeader(showChevron: Bool) -> some View {
        HStack(spacing: 14) {
            Avatar(photoData: baby?.photoData, name: baby?.name ?? "",
                   colorHex: ParticipantColors.babyHex, size: 64)
            VStack(alignment: .leading, spacing: 3) {
                Text(baby?.name.isEmpty == false ? baby!.name : "Baby")
                    .font(AppFont.hero(26))
                    .foregroundStyle(AppColor.text)
                if let baby {
                    // The age string already says "due in …" for a future date,
                    // so the suffix carries just the date to avoid "due … due".
                    Text("\(TimeFormatting.age(from: baby.dateOfBirth)) · \(baby.isBorn ? "born " : "")\(baby.dateOfBirth.formatted(.dateTime.month().day()))")
                        .font(.subheadline)
                        .foregroundStyle(AppColor.text2)
                }
            }
            Spacer()
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppColor.text3)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    // MARK: You

    @ViewBuilder private var youSection: some View {
        Section("You") {
            Button { showProfileEdit = true } label: {
                HStack(spacing: 12) {
                    Avatar(photoData: me?.photoData, name: me?.displayName ?? "",
                           colorHex: me?.colorHex ?? ParticipantColors.palette[0], size: 40)
                    Text(me?.displayName.isEmpty == false ? me!.displayName : "Your name")
                        .foregroundStyle(AppColor.text)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppColor.text3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: People (co-parent sharing)

    @ViewBuilder private var coParentSection: some View {
        Section {
            ForEach(participants.filter { $0.isActive }) { p in
                participantRow(p)
            }

            if prefs.syncRole == .participant {
                Button("Leave shared baby", role: .destructive) { showLeaveConfirm = true }
            } else {
                Button {
                    Task {
                        preparingShare = true
                        do {
                            if let manager = SyncManager.shared {
                                share = try await manager.makeShare()
                            } else {
                                shareError = "Sync isn't running on this device."
                            }
                        } catch {
                            share = nil
                            shareError = (error as NSError).localizedDescription
                        }
                        preparingShare = false
                        if share != nil { showShareSheet = true }
                    }
                } label: {
                    SettingsIconLabel(title: "Invite someone", systemImage: "person.badge.plus",
                                      tint: AppColor.accentSleep)
                }
                .disabled(preparingShare)

                if prefs.syncRole == .owner {
                    Button("Stop sharing", role: .destructive) { showStopSharingConfirm = true }
                }
            }
        } header: {
            let count = participants.filter { $0.isActive }.count
            Text("People")
                .accessibilityLabel("People, \(count) member\(count == 1 ? "" : "s")")
        } footer: {
            if prefs.syncRole != .participant {
                Text("Inviting someone? Have them install Two of Us first — the invite link only works once the app is on their iPhone.")
            }
        }
        // Confirm the irreversible sharing actions — each runs CloudKit teardown
        // the instant it's tapped, so a mis-tap otherwise revokes access or wipes
        // the shared log from this phone with no undo.
        .confirmationDialog("Leave this shared log?", isPresented: $showLeaveConfirm, titleVisibility: .visible) {
            Button("Leave", role: .destructive) {
                Task {
                    do { try await SyncManager.shared?.leaveShare() }
                    catch { shareError = (error as NSError).localizedDescription }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the shared baby from this iPhone. Your co-parent keeps the log, and you can be re-invited later.")
        }
        .confirmationDialog("Stop sharing?", isPresented: $showStopSharingConfirm, titleVisibility: .visible) {
            Button("Stop sharing", role: .destructive) {
                Task {
                    do { try await SyncManager.shared?.stopSharing() }
                    catch { shareError = (error as NSError).localizedDescription }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your co-parent loses access to the shared log. You keep everything on this iPhone.")
        }
        .confirmationDialog(
            "Remove \(participantToRemove?.displayName ?? "this person")?",
            isPresented: Binding(get: { participantToRemove != nil },
                                 set: { if !$0 { participantToRemove = nil } }),
            titleVisibility: .visible, presenting: participantToRemove
        ) { p in
            Button("Remove", role: .destructive) {
                Task {
                    do { try await SyncManager.shared?.removeParticipant(p) }
                    catch { shareError = (error as NSError).localizedDescription }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { p in
            Text("\(p.displayName.isEmpty ? "This person" : p.displayName) loses access to the shared log. You can invite them again later.")
        }
    }

    /// One co-parent row: avatar + name + a role pill. The owner can change another
    /// participant's role and remove them individually (swipe) without ending
    /// sharing for everyone.
    @ViewBuilder private func participantRow(_ p: Participant) -> some View {
        let isMe = p.id == prefs.myParticipantID
        let canManage = prefs.syncRole == .owner && !isMe

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Avatar(photoData: p.photoData, name: p.displayName, colorHex: p.colorHex, size: 36)
                Text(p.displayName.isEmpty ? "—" : p.displayName)
                Spacer()
                rolePill(isMe: isMe, role: p.role)
            }
            if canManage {
                Picker("Access", selection: Binding(get: { p.role },
                                                    set: { store.setRole(p, $0) })) {
                    Text(ParticipantRole.full.displayName).tag(ParticipantRole.full)
                    Text(ParticipantRole.logger.displayName).tag(ParticipantRole.logger)
                }
                .pickerStyle(.segmented)
            }
        }
        .swipeActions {
            if canManage {
                // Confirm before removing — the teardown (which only flips the
                // local row once the server actually dropped them) runs from the
                // dialog on the section.
                Button("Remove", role: .destructive) { participantToRemove = p }
            }
        }
    }

    private func rolePill(isMe: Bool, role: ParticipantRole) -> some View {
        let tint: Color = isMe ? AppColor.text3 : (role == .full ? AppColor.accentFeed : AppColor.text2)
        return Text(isMe ? "You" : role.displayName)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(tint.opacity(0.16), in: Capsule())
            .foregroundStyle(tint)
    }

    // MARK: Demo mode

    @ViewBuilder private var demoSection: some View {
        Section {
            Toggle(isOn: $prefs.demoModeEnabled) {
                SettingsIconLabel(title: "Demo mode", systemImage: "sparkles", tint: AppColor.accentDiaper)
            }
            if prefs.demoModeEnabled {
                Button("Reset demo data") {
                    // Re-seed by dropping back to real and re-entering demo.
                    prefs.demoModeEnabled = false
                    DispatchQueue.main.async { prefs.demoModeEnabled = true }
                }
            }
        } header: {
            Text("Demo mode")
        } footer: {
            Text("Shows sample data so you can explore the app. Your real entries are hidden and untouched, and nothing syncs while demo mode is on.")
        }
    }

    // MARK: About

    private var aboutSection: some View {
        Section {
            VStack(spacing: 8) {
                AppIconBadge(size: 60)
                Text("Two of Us")
                    .font(AppFont.hero(20))
                    .foregroundStyle(AppColor.text)
                Text(AppInfo.versionString)
                    .font(.caption)
                    .foregroundStyle(AppColor.text3)
                Text("Made with love for \(baby?.name ?? "your little one") 🤍")
                    .font(.footnote)
                    .foregroundStyle(AppColor.text2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
    }

    // MARK: Feed reminder

    /// Arms or clears this device's AlarmKit feed reminder when the toggle flips.
    /// Reverts the toggle if the user declines alarm authorization.
    private func updateFeedAlarm(enabled: Bool) async {
        guard enabled else {
            await FeedAlarmManager.cancel()
            NotificationManager.refreshScheduledReminders()  // gentle feed nudge may take over
            return
        }
        guard await FeedAlarmManager.requestAuthorization() else {
            prefs.feedReminderEnabled = false
            return
        }
        // Enabling reminders here (not via the primer quest) still finishes the
        // reminders setup quest — durably, so a later toggle-off won't reopen it.
        SetupProgress.shared.markComplete(.reminders)
        await FeedAlarmManager.reschedule(babyName: baby?.name ?? "Baby",
                                          lastFeed: lastFeedDate(),
                                          interval: settings?.targetFeedInterval ?? 0)
        NotificationManager.refreshScheduledReminders()      // stand the gentle feed nudge down
    }

    /// Requests notification authorization (once) and re-applies the schedules
    /// whenever a notification preference changes.
    private func notificationsChanged() {
        Task {
            await NotificationManager.requestAuthorization()
            NotificationManager.refreshScheduledReminders()
            NotificationManager.refreshDailyMilestone()
        }
    }

    /// Quiet-hours pickers bridge `Date` (hour+minute) to minutes-from-midnight.
    private var quietStart: Binding<Date> {
        Binding(get: { Self.date(fromMinutes: prefs.quietHoursStartMinutes) },
                set: { prefs.quietHoursStartMinutes = Self.minutes(from: $0); notificationsChanged() })
    }
    private var quietEnd: Binding<Date> {
        Binding(get: { Self.date(fromMinutes: prefs.quietHoursEndMinutes) },
                set: { prefs.quietHoursEndMinutes = Self.minutes(from: $0); notificationsChanged() })
    }
    private static func date(fromMinutes m: Int) -> Date {
        Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: .now) ?? .now
    }
    private static func minutes(from date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func lastFeedDate() -> Date? {
        var d = FetchDescriptor<FeedEvent>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first?.timestamp
    }

    /// "2h", "2h 30m", "3h" — omits the "0m" that made the stepper label verbose.
    private func intervalLabel(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}
