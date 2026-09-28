import SwiftUI
import SwiftData

/// The "Brightwheel" row in Settings → Integrations: connect / connected /
/// disconnect, auto-import, the sample-day preview, and the raw-JSON debug
/// fetch. Login-sheet presentation is owned by `IntegrationsSettingsView`
/// for the same cell-recycle reason as SNOO's.
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
                        detailColor: AppColor.text2,
                        subtitle: lastSyncedLine,
                        syncing: manager.isSyncing)
                }
            } else {
                Button { showLogin = true } label: {
                    row(detail: "Not connected", detailColor: AppColor.text3)
                }
                .buttonStyle(.plain)
            }
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Brings the daily report Miller's daycare logs in Brightwheel — feeds, naps, diapers, notes — into the timeline, tagged so daycare entries read apart from yours. Connecting one phone is enough; imported events reach both of you through sync.")
                Text(BrightwheelFeature.disclaimer)
            }
        }
    }

    private var lastSyncedLine: String? {
        guard let last = manager.lastSyncAt else { return nil }
        return "Last synced \(last.formatted(.relative(presentation: .named)))"
    }

    private func row(detail: String, detailColor: Color,
                     subtitle: String? = nil, syncing: Bool = false) -> some View {
        HStack {
            SettingsIconLabel(title: "Brightwheel", systemImage: "building.2.fill",
                              tint: AppColor.accentDiaper)
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

/// Connected-state detail: account + student, auto-import, sync now, the
/// sample-day preview, the raw-JSON debug console, and disconnect.
struct BrightwheelDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var manager = BrightwheelManager.shared
    @State private var isFetching = false
    @State private var fetchOutput: String?
    @State private var fetchError: String?
    @State private var sampleResult: String?
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
                Toggle("Auto-import daily report", isOn: $manager.autoImport)
                Button {
                    Task {
                        let summary = await manager.syncNow(context: context)
                        sampleResult = summary?.line ?? "Sync failed — try the raw fetch below."
                    }
                } label: {
                    HStack {
                        Text("Sync now")
                        if manager.isSyncing {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(manager.isSyncing)
                if let last = manager.lastSyncAt {
                    LabeledContent("Last synced",
                                   value: last.formatted(.relative(presentation: .named)))
                }
            } footer: {
                Text("Auto-import pulls today's report each time the app opens. Imported events land on the timeline with a Daycare tag and sync to both phones.")
            }

            Section {
                Button("Load sample daycare day") {
                    let summary = manager.loadSampleDay(context: context)
                    Haptics.success()
                    sampleResult = summary.imported == 0
                        ? "Sample day is already loaded."
                        : summary.line
                }
                Button("Remove sample day", role: .destructive) {
                    let removed = manager.removeSampleDay(context: context)
                    sampleResult = removed == 0
                        ? "No sample events to remove."
                        : "Removed \(removed) sample events."
                }
            } header: {
                Text("Preview")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if let sampleResult {
                        Text(sampleResult).foregroundStyle(AppColor.text)
                    }
                    Text("Loads a realistic simulated daycare day (drop-off through pick-up) so you can see how the timeline, report card, and stats will look before Miller's first day. Runs through the same import pipeline real data will use. Remove takes back exactly what it added — on both phones.")
                }
            }

            Section {
                Button {
                    fetchToday()
                } label: {
                    HStack {
                        Text("Fetch today's report (raw)")
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
                    Text("Debug view of exactly what Brightwheel returns, for diagnosing the unofficial API.")
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
                Text("Removes the connection from this phone. Nothing changes on Brightwheel's side, and already-imported events stay.")
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
