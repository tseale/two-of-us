import SwiftUI
import SwiftData

/// The "SNOO" row in Settings — the integration's home. Renders all four
/// states (§5): not connected, connected (email + last synced), needs reauth,
/// and syncing (connected + spinner).
struct SnooSettingsSection: View {
    @Environment(\.modelContext) private var context
    @State private var coordinator = SnooSyncCoordinator.shared
    /// The household connection blob, observed reactively: when the other
    /// parent's sign-in (or sign-out) lands via CloudKit mid-session, the
    /// `.onChange` below re-runs adoption immediately — without this, the row
    /// only updated on the NEXT app-foreground, so a participant staring at
    /// Settings kept seeing "Not connected" after the owner connected.
    @Query private var settingsList: [SharedSettings]

    struct LoginPresentation: Identifiable, Equatable {
        let email: String
        var id: String { email }
    }
    /// Presenting the login sheet from state owned here (and a `.sheet`
    /// attached to this row's `Section`) let SwiftUI end up presenting on a
    /// List cell that was mid-recycle, which raced with Settings' own sheet
    /// and tore down both. Owned by `IntegrationsSettingsView` instead, and
    /// presented from that Form's root (§5).
    @Binding var login: LoginPresentation?

    var body: some View {
        Section {
            switch coordinator.connectionState {
            case .notConnected:
                Button { login = LoginPresentation(email: "") } label: {
                    row(detail: "Not connected", detailColor: AppColor.text3)
                }
                .buttonStyle(.plain)

            case .needsReauth(let email):
                Button { login = LoginPresentation(email: email) } label: {
                    row(detail: "Sign in again", detailColor: AppColor.urgencyAmberText)
                }
                .buttonStyle(.plain)

            case .connected(let email):
                NavigationLink {
                    SnooDetailView(email: email)
                } label: {
                    row(detail: email.isEmpty ? "Connected" : email,
                        detailColor: AppColor.text2,
                        subtitle: lastSyncedLine,
                        syncing: coordinator.isSyncing)
                }
            }
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Suggests sleep sessions your SNOO recorded that aren't logged here. Nothing is saved without your okay. One sign-in connects every phone sharing this data.")
                if coordinator.isDegraded {
                    Text("SNOO syncing isn't working right now — the connection still works, but session data couldn't be read. This usually resolves after an app update.")
                } else if coordinator.isRateLimited {
                    Text("Syncing paused briefly.")
                }
                Text(SnooFeature.disclaimer)
            }
        }
        .task { await coordinator.adoptHouseholdConnectionIfNeeded(context: context) }
        .onChange(of: householdBlob) {
            Task { await coordinator.adoptHouseholdConnectionIfNeeded(context: context) }
        }
    }

    private var householdBlob: String? {
        SharedSettings.canonical(settingsList)?.snooCredentials
    }

    private var lastSyncedLine: String? {
        // A publish still queued (offline, engine down, schema-rejected park)
        // means the other phones can't see the connection yet — say so
        // instead of letting "connected" masquerade as "household connected".
        if let settings = SharedSettings.canonical(settingsList),
           settings.snooCredentials?.isEmpty == false,
           SyncManager.shared?.hasPendingSave(settings.id) == true {
            return "Connecting other phones…"
        }
        guard let last = coordinator.lastSyncAt else { return nil }
        return "Last synced \(last.formatted(.relative(presentation: .named)))"
    }

    private func row(detail: String, detailColor: Color,
                     subtitle: String? = nil, syncing: Bool = false) -> some View {
        HStack {
            SettingsIconLabel(title: "SNOO", systemImage: "bed.double.fill",
                              tint: AppColor.accentSleep)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 6) {
                    if syncing { ProgressView().controlSize(.small) }
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(detailColor)
                        .lineLimit(1)
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(AppColor.text3)
                }
            }
        }
        .contentShape(Rectangle())
    }
}

/// Connected-state detail: account line, auto-log mode, Sync now, Sign out (§5).
struct SnooDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var coordinator = SnooSyncCoordinator.shared
    @State private var showSignOutConfirm = false
    @Query private var settingsList: [SharedSettings]

    let email: String

    /// The household connection blob — the auto-log flag lives inside it.
    private var sharedCreds: SnooSharedCredentials? {
        SharedSettings.canonical(settingsList)?.snooCredentials
            .flatMap(SnooSharedCredentials.init(json:))
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Account", value: email.isEmpty ? "Connected" : email)
                if let last = coordinator.lastSyncAt {
                    LabeledContent("Last synced",
                                   value: last.formatted(.relative(presentation: .named)))
                }
            }

            Section {
                Toggle("Auto-log SNOO sleep", isOn: Binding(
                    get: { sharedCreds?.autoLog ?? false },
                    set: { setAutoLog($0) }
                ))
            } footer: {
                Text("Starts the sleep timer when the SNOO starts a session and ends it when the SNOO stops — no cards to confirm, on every phone sharing this data. The SNOO is checked when the app opens, so a session lands the next time either of you checks in; times always match the SNOO's own record.")
            }

            Section {
                Button {
                    Task { await coordinator.syncNow(context: context) }
                } label: {
                    HStack {
                        Text("Sync now")
                        if coordinator.isSyncing {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(coordinator.isSyncing)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if let result = coordinator.manualSyncResult {
                        syncResultLine(result)
                    }
                    Text("Syncing checks the last day or two of SNOO sessions and suggests anything that isn't logged yet.")
                }
            }

            Section {
                Button("Sign out", role: .destructive) { showSignOutConfirm = true }
            } footer: {
                Text(SnooFeature.disclaimer)
            }
        }
        .navigationTitle("SNOO")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Sign out of SNOO?", isPresented: $showSignOutConfirm,
                            titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                Task {
                    await coordinator.signOut(context: context)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Disconnects SNOO on every phone sharing this data. Sleep sessions you already saved stay in the log.")
        }
    }

    @ViewBuilder
    private func syncResultLine(_ result: SnooSyncCoordinator.ManualSyncResult) -> some View {
        switch result {
        case .found(let summaries):
            VStack(alignment: .leading, spacing: 2) {
                Text(summaries.count == 1 ? "Found 1 SNOO session" : "Found \(summaries.count) SNOO sessions")
                    .foregroundStyle(AppColor.urgencyGreen)
                Text(summaries.joined(separator: ", "))
                    .foregroundStyle(AppColor.text2)
            }
        case .logged(let summaries):
            VStack(alignment: .leading, spacing: 2) {
                Text(summaries.count == 1 ? "Logged 1 SNOO session" : "Logged \(summaries.count) SNOO sessions")
                    .foregroundStyle(AppColor.urgencyGreen)
                Text(summaries.joined(separator: ", "))
                    .foregroundStyle(AppColor.text2)
            }
        case .noneFound:
            Text("No new SNOO sessions found")
                .foregroundStyle(AppColor.text2)
        case .failed(let message):
            Text(message)
                .foregroundStyle(AppColor.urgencyRedText)
        }
    }

    private func setAutoLog(_ on: Bool) {
        guard var creds = sharedCreds else { return }
        creds.autoLog = on
        EventStore(context: context).updateSnooCredentials(creds.jsonString)
        Haptics.tap()
    }
}
