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

                coParentSection

                Section("My notifications") {
                    Toggle("Feeds", isOn: $prefs.notifyFeed)
                    Toggle("Sleep", isOn: $prefs.notifySleep)
                    Toggle("Diapers", isOn: $prefs.notifyDiaper)
                    Toggle("Feed reminder", isOn: $prefs.feedReminderEnabled)
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
            Text("Invite the other parent to share Miller's log in real time. Notification delivery arrives in an upcoming update.")
                .font(.footnote)
                .foregroundStyle(AppColor.text3)
        }
    }
}
