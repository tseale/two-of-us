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
    /// The row the owner swiped "Merge" on — the duplicate to fold into another
    /// person. Drives a dialog listing the possible targets.
    @State private var participantToMerge: Participant?
    /// The share URL staged for "Resend link" on an existing person's row —
    /// non-nil drives the plain share sheet (no people management, no new invite).
    @State private var resendLink: ResendLink?
    /// Set when "Resend link" finds the person is no longer on the CKShare —
    /// the URL would dead-end with "Item Unavailable" on THEIR phone, so this
    /// drives an alert that routes to re-adding them via the sharing sheet.
    @State private var reinviteNeeded: Participant?
    /// SNOO's login sheet — presented from here (the Form's root) rather than
    /// from `SnooSettingsSection` itself, alongside every other Settings sheet.
    @State private var snooLogin: SnooSettingsSection.LoginPresentation?

    struct ResendLink: Identifiable {
        let url: URL
        var id: URL { url }
    }

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
                        // Common presets for quick selection. Chip styling lives
                        // INSIDE the button label (with a 44pt-min frame), so the
                        // whole capsule is tappable — not just the caption text.
                        HStack(spacing: 8) {
                            ForEach([120, 150, 180, 240], id: \.self) { mins in
                                let selected = settings.targetFeedIntervalMinutes == mins
                                Button {
                                    store.updateSettings(targetFeedIntervalMinutes: mins)
                                } label: {
                                    Text(intervalLabel(mins))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(selected ? AppColor.accentFeed : AppColor.text2)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(selected ? AppColor.accentFeed.opacity(0.15) : AppColor.card2,
                                                    in: Capsule())
                                        .frame(minHeight: 44)
                                        .contentShape(Rectangle())
                                }
                                .accessibilityLabel("Feed every \(spokenInterval(mins))")
                                .accessibilityAddTraits(selected ? [.isSelected] : [])
                            }
                            Spacer()
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let settings, canEditShared {
                    Section {
                        trackerToggle(.feed, title: "Feed", systemImage: "drop.fill",
                                      tint: AppColor.accentFeed, settings: settings)
                        trackerToggle(.sleep, title: "Sleep", systemImage: "moon.fill",
                                      tint: AppColor.accentSleep, settings: settings)
                        trackerToggle(.diaper, title: "Diaper", systemImage: "leaf.fill",
                                      tint: AppColor.accentDiaper, settings: settings)
                    } header: {
                        Text("What to track")
                    } footer: {
                        Text("Turn a tracker off to hide its button and stop logging that event — handy when logging one of them isn't worth it for a while. Existing entries are preserved, both parents see the same trackers, and at least one always stays on.")
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
                    Toggle(isOn: $prefs.nightSlotAlarmEnabled) {
                        SettingsIconLabel(title: "My slot alarm", systemImage: "alarm",
                                          tint: AppColor.accentSleep)
                    }
                    .onChange(of: prefs.nightSlotAlarmEnabled) { _, on in
                        Task { await updateSlotAlarm(enabled: on) }
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("Feed reminder alerts you when the next feed is due; My slot alarm wakes you for nighttime-schedule slots that are yours (an unassigned slot wakes both of you) — both even on Silent or Focus, and only near your own slot one of them rings. This device only.")
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

                if SnooFeature.isEnabled && !prefs.demoModeEnabled {
                    SnooSettingsSection(login: $snooLogin)
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
                        itemTitle: baby.flatMap { $0.name.isEmpty ? nil : "\($0.name) — Two of Us" } ?? "Two of Us",
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
            .sheet(item: $resendLink) { link in
                ActivityShareSheet(items: [link.url])
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $snooLogin) { presentation in
                SnooLoginSheet(prefilledEmail: presentation.email)
            }
            .alert(
                "\(reinviteNeeded?.displayName.isEmpty == false ? reinviteNeeded!.displayName : "This person") isn't on the iCloud share",
                isPresented: Binding(get: { reinviteNeeded != nil },
                                     set: { if !$0 { reinviteNeeded = nil } }),
                presenting: reinviteNeeded
            ) { _ in
                Button("Re-add them") {
                    reinviteNeeded = nil
                    showShareSheet = true
                }
                Button("Cancel", role: .cancel) { reinviteNeeded = nil }
            } message: { p in
                Text("\(p.displayName.isEmpty ? "They" : p.displayName) may have been removed or sharing was reset, so the link alone won't work for them. Re-add them from the sharing sheet — their history comes right back once they accept.")
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
                Text(baby.flatMap { $0.name.isEmpty ? nil : $0.name } ?? "Baby")
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
                    Text(me.flatMap { $0.displayName.isEmpty ? nil : $0.displayName } ?? "Your name")
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
                Text("Inviting someone? Have them install Two of Us first — the invite link only works once the app is on their iPhone. If someone already here lost their link, swipe their row to resend it.")
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
        .confirmationDialog(
            "Merge \(participantToMerge?.displayName.isEmpty == false ? participantToMerge!.displayName : "this person") into…",
            isPresented: Binding(get: { participantToMerge != nil },
                                 set: { if !$0 { participantToMerge = nil } }),
            titleVisibility: .visible, presenting: participantToMerge
        ) { dup in
            ForEach(participants.filter { $0.isActive && $0.id != dup.id }) { target in
                Button(target.id == prefs.myParticipantID
                       ? "Merge into \(target.displayName.isEmpty ? "you" : target.displayName) (you)"
                       : "Merge into \(target.displayName.isEmpty ? "—" : target.displayName)") {
                    store.mergeParticipant(dup, into: target)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { dup in
            Text("Use this when the same person shows up twice (usually after they reinstalled and re-joined). Everything \(dup.displayName.isEmpty ? "they" : dup.displayName) logged moves to the profile you pick, and the duplicate disappears. This can't be undone.")
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
                if p.isActive {
                    // Re-share the standing invite URL with someone who already
                    // has access (lost the link, new phone). The zone-wide
                    // share's URL is stable, so this never creates a new person
                    // or touches the participant list — the link simply lets an
                    // existing member reconnect. If they're no longer ON the
                    // share, the URL is useless to them ("Item Unavailable"),
                    // so the flow routes to re-adding instead.
                    Button { Task { await prepareResendLink(for: p) } } label: {
                        Label("Resend link", systemImage: "link.badge.plus")
                    }
                    .tint(AppColor.accentSleep)
                    .disabled(preparingShare)
                    // Fold a duplicate row into another person. Auto-merge
                    // handles rows that share a captured iCloud identity; this
                    // is the escape hatch for older rows it can't attribute.
                    Button { participantToMerge = p } label: {
                        Label("Merge", systemImage: "person.crop.circle.badge.checkmark")
                    }
                    .tint(AppColor.accentFeed)
                }
            }
        }
    }

    /// Fetches the existing zone-wide share and stages its URL for the plain
    /// share sheet — but only after confirming `p` is actually a member of the
    /// share. The invite-only URL does nothing for a non-member (their phone
    /// shows Apple's "Item Unavailable"), so anyone off the share is routed to
    /// the proper re-add flow instead. Reuses `makeShare` (returns the existing
    /// share when one exists) and the invite flow's error surfacing.
    private func prepareResendLink(for p: Participant) async {
        preparingShare = true
        defer { preparingShare = false }
        do {
            guard let manager = SyncManager.shared else {
                shareError = "Sync isn't running on this device."
                return
            }
            let fetched = try await manager.makeShare()
            let memberIDs = fetched.participants
                .filter { $0.role != .owner }
                .map { $0.userIdentity.userRecordID?.recordName }
            guard SyncManager.shareHasMember(cloudUserID: p.cloudUserID, memberIDs: memberIDs) else {
                share = fetched            // stage for the sharing sheet the alert offers
                reinviteNeeded = p
                return
            }
            guard let url = fetched.url else {
                shareError = "The invite link isn't ready yet — try again in a moment."
                return
            }
            resendLink = ResendLink(url: url)
        } catch {
            shareError = (error as NSError).localizedDescription
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

    // MARK: What to track

    /// One "What to track" row. The last enabled tracker's toggle locks on —
    /// with all three off the app would have nothing to log. Alarm/nudge/widget
    /// refresh rides on `EventStore.updateSettings`, so a co-parent's flip
    /// (which arrives through sync, not this view) behaves identically.
    private func trackerToggle(_ kind: EventKind, title: String, systemImage: String,
                               tint: Color, settings: SharedSettings) -> some View {
        let isLastEnabled = settings.isEnabled(kind) && settings.enabledTrackerCount == 1
        return Toggle(isOn: Binding(
            get: { settings.isEnabled(kind) },
            set: { on in
                switch kind {
                case .feed:   store.updateSettings(feedLoggingEnabled: on)
                case .sleep:  store.updateSettings(sleepLoggingEnabled: on)
                case .diaper: store.updateSettings(diaperLoggingEnabled: on)
                }
            }
        )) {
            SettingsIconLabel(title: title, systemImage: systemImage, tint: tint)
        }
        .disabled(isLastEnabled)
        .accessibilityHint(isLastEnabled
            ? "At least one tracker stays on"
            : "Turn off to hide the \(title.lowercased()) button and stop logging \(title.lowercased()) events. Existing entries are preserved.")
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
        let lastFeed = lastFeedDate()
        await FeedAlarmManager.reschedule(babyName: baby?.name ?? "Baby",
                                          lastFeed: lastFeed,
                                          interval: lastFeed.flatMap { settings?.feedInterval(after: $0) } ?? 0)
        NotificationManager.refreshScheduledReminders()      // stand the gentle feed nudge down
    }

    /// Arms or clears the loud "my slot" alarm when the toggle flips. Reverts
    /// the toggle if the user declines alarm authorization. Also re-arms the
    /// interval feed alarm, whose stand-down window depends on this state.
    private func updateSlotAlarm(enabled: Bool) async {
        if enabled {
            guard await SlotAlarmManager.requestAuthorization() else {
                prefs.nightSlotAlarmEnabled = false
                return
            }
        }
        await SlotAlarmManager.reschedule()   // arms when enabled, clears when not
        let lastFeed = lastFeedDate()
        await FeedAlarmManager.reschedule(babyName: baby?.name ?? "Baby",
                                          lastFeed: lastFeed,
                                          interval: lastFeed.flatMap { settings?.feedInterval(after: $0) } ?? 0)
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

    /// Fully spelled-out form for VoiceOver — "2h 30m" reads poorly aloud.
    private func spokenInterval(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        let hours = h == 1 ? "1 hour" : "\(h) hours"
        if m == 0 { return hours }
        let mins = m == 1 ? "1 minute" : "\(m) minutes"
        return h == 0 ? mins : "\(hours) \(mins)"
    }
}
