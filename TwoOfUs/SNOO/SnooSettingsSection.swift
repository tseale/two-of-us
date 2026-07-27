import SwiftUI
import SwiftData

/// The "SNOO" row in Settings — the integration's home. Renders all four
/// states (§5): not connected, connected (email + last synced), needs reauth,
/// and syncing (connected + spinner).
struct SnooSettingsSection: View {
    @Environment(\.modelContext) private var context
    @State private var coordinator = SnooSyncCoordinator.shared

    struct LoginPresentation: Identifiable, Equatable {
        let email: String
        var id: String { email }
    }
    /// Presenting the login sheet from state owned here (and a `.sheet`
    /// attached to this row's `Section`) let SwiftUI end up presenting on a
    /// List cell that was mid-recycle, which raced with Settings' own sheet
    /// and tore down both. Owned by `SettingsView` instead, alongside its
    /// other sheets, and presented from the Form's root (§5).
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
        } header: {
            Text("Integrations")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Suggests sleep sessions your SNOO recorded that aren't logged here. Nothing is saved without your okay.")
                if coordinator.isDegraded {
                    Text("SNOO syncing isn't working right now — the connection still works, but session data couldn't be read. This usually resolves after an app update.")
                } else if coordinator.isRateLimited {
                    Text("Syncing paused briefly.")
                }
                Text(SnooFeature.disclaimer)
            }
        }
    }

    private var lastSyncedLine: String? {
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

/// Connected-state detail: account line, Sync now, Sign out (§5).
struct SnooDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var coordinator = SnooSyncCoordinator.shared
    @State private var showSignOutConfirm = false

    let email: String

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
                Text("Syncing checks the last day or two of SNOO sessions and suggests anything that isn't logged yet.")
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
                    await coordinator.signOut()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes the connection from this iPhone. Sleep sessions you already saved stay in the log.")
        }
    }
}
