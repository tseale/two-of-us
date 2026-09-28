import SwiftUI

/// The "Brightwheel" row in Settings → Integrations. Phase 1: connect /
/// connected / disconnect, plus the debug fetch that verifies the JSON pull
/// (docs/BRIGHTWHEEL-INTEGRATION.md §8). Login-sheet presentation is owned by
/// `IntegrationsSettingsView` for the same cell-recycle reason as SNOO's.
struct BrightwheelSettingsSection: View {
    @State private var manager = BrightwheelManager.shared
    @Binding var showLogin: Bool

    var body: some View {
        Section {
            if let session = manager.session {
                NavigationLink {
                    BrightwheelDetailView(session: session)
                } label: {
                    row(detail: session.email.isEmpty ? "Connected" : session.email,
                        detailColor: AppColor.text2)
                }
            } else {
                Button { showLogin = true } label: {
                    row(detail: "Not connected", detailColor: AppColor.text3)
                }
                .buttonStyle(.plain)
            }
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Reads the daily report Miller's daycare logs in Brightwheel. Early preview: connects and fetches, nothing is saved to the log yet.")
                Text(BrightwheelFeature.disclaimer)
            }
        }
    }

    private func row(detail: String, detailColor: Color) -> some View {
        HStack {
            SettingsIconLabel(title: "Brightwheel", systemImage: "building.2.fill",
                              tint: AppColor.accentDiaper)
            Spacer()
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(detailColor)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }
}

/// Connected-state detail: account + student, the phase-1 "Fetch today's
/// report" debug console, and disconnect.
struct BrightwheelDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var manager = BrightwheelManager.shared
    @State private var isFetching = false
    @State private var fetchOutput: String?
    @State private var fetchError: String?
    @State private var showDisconnectConfirm = false

    let session: BrightwheelSession

    var body: some View {
        Form {
            Section("Account") {
                LabeledContent("Signed in as", value: session.email)
                LabeledContent("Student", value: session.studentName)
                LabeledContent("Connected",
                               value: session.signedInAt.formatted(date: .abbreviated,
                                                                   time: .shortened))
            }

            Section {
                Button {
                    fetchToday()
                } label: {
                    HStack {
                        Text("Fetch today's report")
                        if isFetching {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isFetching)
            } footer: {
                if let fetchError {
                    Text(fetchError).foregroundStyle(AppColor.urgencyRed)
                } else {
                    Text("Pulls today's activities as raw JSON — the phase-1 check that the connection actually works.")
                }
            }

            if let fetchOutput {
                Section {
                    ScrollView(.horizontal) {
                        Text(fetchOutput)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 360)
                } header: {
                    HStack {
                        Text("Response")
                        Spacer()
                        ShareLink(item: fetchOutput) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .font(.footnote)
                    }
                }
            }

            Section {
                Button("Disconnect Brightwheel", role: .destructive) {
                    showDisconnectConfirm = true
                }
            } footer: {
                Text("Removes the connection from this phone. Nothing changes on Brightwheel's side.")
            }
        }
        .navigationTitle("Brightwheel")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Disconnect Brightwheel?", isPresented: $showDisconnectConfirm,
                            titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) {
                manager.disconnect()
                dismiss()
            }
        }
    }

    private func fetchToday() {
        isFetching = true
        fetchError = nil
        Task {
            defer { isFetching = false }
            do {
                fetchOutput = try await manager.fetchTodayRawJSON()
                Haptics.success()
            } catch let error as BrightwheelAPIError {
                fetchError = error.userMessage
            } catch {
                fetchError = "Something went wrong. Try again."
            }
        }
    }
}
