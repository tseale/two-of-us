import SwiftUI
import SwiftData
import CloudKit

/// Settings shell. Shared settings (Full role) + per-user prefs + co-parent sharing.
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

    private var baby: Baby? { babies.first }
    private var settings: SharedSettings? { settingsList.first }

    var body: some View {
        NavigationStack {
            Form {
                Section("Baby") {
                    if let baby {
                        LabeledContent("Name", value: baby.name)
                        DatePicker("Date of birth",
                                   selection: Binding(get: { baby.dateOfBirth },
                                                      set: { baby.dateOfBirth = $0; try? context.save() }),
                                   in: ...Date(), displayedComponents: .date)
                    }
                }

                if let settings {
                    Section("Feeding") {
                        Stepper(value: Binding(get: { settings.targetFeedIntervalMinutes },
                                               set: { settings.targetFeedIntervalMinutes = $0; try? context.save() }),
                                in: 60...360, step: 15) {
                            Text("Target interval: \(settings.targetFeedIntervalMinutes / 60)h \(settings.targetFeedIntervalMinutes % 60)m")
                        }
                    }
                }

                Section("Appearance") {
                    Picker("Theme", selection: $prefs.appearance) {
                        ForEach(Appearance.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
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
                footerNote
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showShareSheet) {
                if let share { CloudShareView(share: share) }
            }
        }
    }

    @ViewBuilder private var coParentSection: some View {
        Section("Co-parent") {
            ForEach(participants.filter { $0.isActive }) { p in
                HStack {
                    Circle().fill(Color(hex: p.colorHex)).frame(width: 14, height: 14)
                    Text(p.displayName.isEmpty ? "—" : p.displayName)
                    if p.id == prefs.myParticipantID {
                        Text("(you)").foregroundStyle(AppColor.text3)
                    }
                }
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
                    Label(prefs.syncRole == .owner ? "Manage co-parent" : "Invite co-parent",
                          systemImage: "person.badge.plus")
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

    private var footerNote: some View {
        Section {
            Text("Invite the other parent to share Miller's log in real time. Per-event push delivery arrives in an upcoming update.")
                .font(.footnote)
                .foregroundStyle(AppColor.text3)
        }
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
