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
                                title: "Feed every \(settings.targetFeedIntervalMinutes / 60)h \(settings.targetFeedIntervalMinutes % 60)m",
                                systemImage: "timer", tint: AppColor.accentFeed)
                        }
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
                if let share { CloudShareView(share: share) }
            }
            .alert("Couldn't prepare the invite", isPresented: Binding(
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
                    Text("\(TimeFormatting.age(from: baby.dateOfBirth)) · born \(baby.dateOfBirth.formatted(.dateTime.month().day()))")
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
                Button("Leave shared baby", role: .destructive) {
                    SyncManager.shared?.leaveShare()
                }
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
                    Button("Stop sharing", role: .destructive) {
                        Task { await SyncManager.shared?.stopSharing() }
                    }
                }
            }
        } header: {
            Text("People")
        } footer: {
            if prefs.syncRole != .participant {
                Text("Inviting someone? Have them install Two of Us first — the invite link only works once the app is on their iPhone.")
            }
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
                Button("Remove", role: .destructive) {
                    Task { await SyncManager.shared?.removeParticipant(p) }
                }
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
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppColor.accentFeed)
                    .frame(width: 60, height: 60)
                    .overlay { Text("🍼").font(.system(size: 30)) }
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
        guard enabled else { await FeedAlarmManager.cancel(); return }
        guard await FeedAlarmManager.requestAuthorization() else {
            prefs.feedReminderEnabled = false
            return
        }
        await FeedAlarmManager.reschedule(babyName: baby?.name ?? "Baby",
                                          lastFeed: lastFeedDate(),
                                          interval: settings?.targetFeedInterval ?? 0)
    }

    private func lastFeedDate() -> Date? {
        var d = FetchDescriptor<FeedEvent>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first?.timestamp
    }
}
