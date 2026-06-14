import SwiftUI
import SwiftData

/// "Manage data" screen: export a backup, clear the log, or permanently delete
/// everything. Reached from Settings. Destructive actions are confirmation-gated;
/// "Delete everything" runs the multi-step `DeleteEverythingFlow`.
struct ManageDataView: View {
    @Environment(\.modelContext) private var context
    @Query private var participants: [Participant]
    @State private var prefs = LocalPrefs.shared
    @State private var exportURL: URL?
    @State private var showClearConfirm = false
    @State private var showDeleteFlow = false

    private var store: EventStore { EventStore(context: context) }
    /// This device's app role — guests (loggers) can't clear/delete shared data.
    private var canEditShared: Bool {
        (participants.first { $0.id == prefs.myParticipantID }?.role ?? .full) == .full
    }
    /// Only the data owner (or a solo user) can purge the shared CloudKit zone.
    /// Hidden in demo mode — "Delete everything" acts on the real iCloud zone, which
    /// must never be touched while showing sample data.
    private var canDeleteEverything: Bool {
        !prefs.demoModeEnabled && (prefs.syncRole == .owner || prefs.syncRole == .solo)
    }

    var body: some View {
        Form {
            Section {
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Export log (CSV)", systemImage: "square.and.arrow.up")
                    }
                } else {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Preparing export…").foregroundStyle(AppColor.text2)
                    }
                }
            } header: {
                Text("Backup")
            } footer: {
                Text("Saves the current log as a CSV file. Deleted entries are not included.")
            }

            if canEditShared {
                Section {
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Label("Clear all logs", systemImage: "trash")
                    }
                } footer: {
                    Text("Removes every feed, sleep, and diaper entry. Your baby and profile settings stay.")
                }
            }

            if canDeleteEverything {
                Section {
                    Button(role: .destructive) {
                        showDeleteFlow = true
                    } label: {
                        Label("Delete everything", systemImage: "exclamationmark.triangle")
                    }
                } footer: {
                    Text("Permanently deletes all data for both parents and starts over. This cannot be undone.")
                }
            }
        }
        .navigationTitle("Manage data")
        .navigationBarTitleDisplayMode(.inline)
        .task { exportURL = LogExporter.writeTempFile(in: context) }
        .confirmationDialog("Clear all logs?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Clear all logs", role: .destructive) { store.clearAllLogs() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every logged entry for both parents. Your baby and settings are kept.")
        }
        .sheet(isPresented: $showDeleteFlow) {
            DeleteEverythingFlow {
                await SyncManager.shared?.deleteEverything()
            }
        }
    }
}

/// Multi-step gauntlet for the irreversible "Delete everything" action. No single
/// tap can trigger the delete: two acknowledgement steps, then a type-to-confirm
/// step requiring the exact phrase before the final button enables.
struct DeleteEverythingFlow: View {
    @Environment(\.dismiss) private var dismiss
    /// Runs the actual deletion once all stages pass.
    let onConfirmed: () async -> Void

    @State private var stage = 1
    @State private var typed = ""
    @State private var working = false
    @State private var deleteFailed = false

    private let phrase = "DELETE EVERYTHING"

    var body: some View {
        NavigationStack {
            Form {
                switch stage {
                case 1: stageOne
                case 2: stageTwo
                default: stageThree
                }
            }
            .navigationTitle("Delete everything")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(working)
                }
            }
            .interactiveDismissDisabled(working)
        }
    }

    // Step 1 — what will happen.
    @ViewBuilder private var stageOne: some View {
        Section {
            Label("This deletes everything", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.headline)
        }
        Section {
            Text("All feeds, sleeps, and diaper entries, your baby's profile, and every parent's access will be permanently removed — for both parents, on all devices.")
            Text("This cannot be undone.").bold()
        }
        Section {
            Button("Continue", role: .destructive) { stage = 2 }
        }
    }

    // Step 2 — consequences + export reminder.
    @ViewBuilder private var stageTwo: some View {
        Section {
            Text("If you'd like to keep a record of your baby's log, cancel and use **Export log (CSV)** first — there's no way to recover this data afterward.")
        }
        Section {
            Text("Continuing will also remove the data from the other parent's device.")
        }
        Section {
            Button("I understand, continue", role: .destructive) { stage = 3 }
            Button("Go back") { stage = 1 }
        }
    }

    // Step 3 — type the phrase to confirm.
    @ViewBuilder private var stageThree: some View {
        Section {
            Text("Type **\(phrase)** to confirm.")
            TextField(phrase, text: $typed)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .disabled(working)
        } footer: {
            if deleteFailed {
                Text("That didn't finish — check your connection and try again.")
                    .foregroundStyle(.red)
            }
        }
        Section {
            Button(role: .destructive) {
                Task {
                    working = true
                    deleteFailed = false
                    let ok = await runDeleteWithTimeout()
                    working = false
                    if ok { dismiss() } else { deleteFailed = true }
                }
            } label: {
                if working {
                    ProgressView()
                } else {
                    Text(deleteFailed ? "Try again" : "Delete everything")
                }
            }
            .disabled(typed != phrase || working)
            // Always reachable back out — a hung/failed delete must never strand
            // the user on a disabled spinner.
            Button("Go back") { stage = 2 }.disabled(working)
        }
    }

    /// Races the (non-throwing, possibly hanging) delete against a timeout so a
    /// stalled CloudKit teardown surfaces a retry instead of an endless spinner.
    private func runDeleteWithTimeout() async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { await onConfirmed(); return true }
            group.addTask { try? await Task.sleep(for: .seconds(30)); return false }
            let finished = await group.next() ?? false
            group.cancelAll()
            return finished
        }
    }
}
