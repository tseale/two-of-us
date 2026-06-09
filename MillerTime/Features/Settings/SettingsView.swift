import SwiftUI
import SwiftData
import CloudKit

/// Settings shell. Shared settings (Full role) + per-user prefs + co-parent
/// sharing + a "Manage data" link for export/clear/delete.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var babies: [Baby]
    @Query private var settingsList: [SharedSettings]
    @Query private var participants: [Participant]
    @State private var prefs = LocalPrefs.shared
    @State private var share: CKShare?
    @State private var showShareSheet = false
    @State private var preparingShare = false

    // Editing drafts (committed through the sync-aware EventStore helpers).
    @State private var babyNameDraft = ""
    @State private var myNameDraft = ""
    @State private var myColorDraft = ParticipantColors.palette[0]

    private var baby: Baby? { babies.first }
    private var settings: SharedSettings? { settingsList.first }
    private var store: EventStore { EventStore(context: context) }

    /// This device's app role. Loggers can't change shared baby/feeding settings.
    private var myRole: ParticipantRole {
        participants.first { $0.id == prefs.myParticipantID }?.role ?? .full
    }
    private var canEditShared: Bool { myRole == .full }

    var body: some View {
        NavigationStack {
            Form {
                Section("Baby") {
                    if let baby {
                        if canEditShared {
                            TextField("Name", text: $babyNameDraft)
                                .onSubmit { commitBaby() }
                            DatePicker("Date of birth",
                                       selection: Binding(get: { baby.dateOfBirth },
                                                          set: { store.updateBaby(name: resolvedBabyName(), dateOfBirth: $0) }),
                                       in: ...Date(), displayedComponents: .date)
                        } else {
                            LabeledContent("Name", value: baby.name)
                            LabeledContent("Date of birth", value: baby.dateOfBirth.formatted(date: .abbreviated, time: .omitted))
                        }
                    }
                }

                Section("You") {
                    TextField("Your name", text: $myNameDraft)
                        .onSubmit { commitMyProfile() }
                    ParticipantColorPicker(selection: $myColorDraft)
                        .onChange(of: myColorDraft) { _, _ in commitMyProfile() }
                }

                if let settings, canEditShared {
                    Section("Feeding") {
                        Stepper(value: Binding(get: { settings.targetFeedIntervalMinutes },
                                               set: { store.updateSettings(targetFeedIntervalMinutes: $0) }),
                                in: 60...360, step: 15) {
                            Text("Target interval: \(settings.targetFeedIntervalMinutes / 60)h \(settings.targetFeedIntervalMinutes % 60)m")
                        }
                    }
                }

                coParentSection

                Section {
                    Toggle("Feed reminder", isOn: $prefs.feedReminderEnabled)
                        .onChange(of: prefs.feedReminderEnabled) { _, on in
                            Task { await updateFeedAlarm(enabled: on) }
                        }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("Alerts you when the next feed is due — even on Silent or Focus. This device only.")
                }

                Section("My notifications") {
                    Toggle("Feeds", isOn: $prefs.notifyFeed)
                    Toggle("Sleep", isOn: $prefs.notifySleep)
                    Toggle("Diapers", isOn: $prefs.notifyDiaper)
                }
                .disabled(true)

                Section {
                    NavigationLink {
                        ManageDataView()
                    } label: {
                        Label("Manage data", systemImage: "externaldrive")
                    }
                }

                footerNote
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showShareSheet) {
                if let share { CloudShareView(share: share) }
            }
            .onAppear(perform: loadDrafts)
        }
    }

    @ViewBuilder private var coParentSection: some View {
        Section("People") {
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
                        share = try? await SyncManager.shared?.makeShare()
                        preparingShare = false
                        if share != nil { showShareSheet = true }
                    }
                } label: {
                    Label("Invite someone", systemImage: "person.badge.plus")
                }
                .disabled(preparingShare)

                if prefs.syncRole == .owner {
                    Button("Stop sharing", role: .destructive) {
                        Task { await SyncManager.shared?.stopSharing() }
                    }
                }
            }
        }
    }

    /// One co-parent row. The owner can change another participant's role and
    /// remove them individually (swipe) without ending sharing for everyone.
    @ViewBuilder private func participantRow(_ p: Participant) -> some View {
        let isMe = p.id == prefs.myParticipantID
        let canManage = prefs.syncRole == .owner && !isMe

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(Color(hex: p.colorHex)).frame(width: 14, height: 14)
                Text(p.displayName.isEmpty ? "—" : p.displayName)
                if isMe {
                    Text("(you)").foregroundStyle(AppColor.text3)
                } else {
                    Text("— \(p.role.displayName)").foregroundStyle(AppColor.text3)
                }
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

    private var footerNote: some View {
        Section {
            Text("People you invite join as guests and can log entries in real time. To give the other parent full access, tap their name and choose Co-parent. Per-event push delivery arrives in an upcoming update.")
                .font(.footnote)
                .foregroundStyle(AppColor.text3)
        }
    }

    // MARK: Draft commit

    private func loadDrafts() {
        babyNameDraft = baby?.name ?? ""
        if let me = store.owner {
            myNameDraft = me.displayName
            myColorDraft = me.colorHex.isEmpty ? ParticipantColors.palette[0] : me.colorHex
        }
    }

    private func resolvedBabyName() -> String {
        let trimmed = babyNameDraft.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? (baby?.name ?? "") : trimmed
    }

    private func commitBaby() {
        guard let baby else { return }
        store.updateBaby(name: resolvedBabyName(), dateOfBirth: baby.dateOfBirth)
    }

    private func commitMyProfile() {
        let name = myNameDraft.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        store.updateMyProfile(name: name, colorHex: myColorDraft)
    }

    /// Arms or clears this device's AlarmKit feed reminder when the toggle flips.
    /// Reverts the toggle if the user declines alarm authorization.
    private func updateFeedAlarm(enabled: Bool) async {
        guard enabled else { await FeedAlarmManager.cancel(); return }
        guard await FeedAlarmManager.requestAuthorization() else {
            prefs.feedReminderEnabled = false
            return
        }
        await FeedAlarmManager.reschedule(lastFeed: lastFeedDate(),
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
