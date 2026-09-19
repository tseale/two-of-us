import SwiftUI
import SwiftData
import CloudKit

/// "People & Sharing" subpage: the participant list (with role management and
/// swipe actions), inviting a co-parent, and the leave / stop-sharing exits.
/// All the CloudKit sharing sheets and confirmation dialogs live here.
struct PeopleSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var babies: [Baby]
    @Query private var participants: [Participant]
    @State private var prefs = LocalPrefs.shared
    @State private var share: CKShare?
    @State private var showShareSheet = false
    @State private var preparingShare = false
    /// The underlying error when preparing the invite fails — drives an alert
    /// instead of the button silently doing nothing.
    @State private var shareError: String?
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

    struct ResendLink: Identifiable {
        let url: URL
        var id: URL { url }
    }

    private var baby: Baby? { babies.first }
    private var store: EventStore { EventStore(context: context) }

    var body: some View {
        Form {
            peopleSection
        }
        .navigationTitle("People & Sharing")
        .navigationBarTitleDisplayMode(.inline)
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
    }

    @ViewBuilder private var peopleSection: some View {
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
            ForEach(participants.filter { $0.isActive && !$0.isPaused && $0.id != dup.id }) { target in
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
                    .saturation(p.isPaused ? 0 : 1)
                    .opacity(p.isPaused ? 0.5 : 1)
                Text(p.displayName.isEmpty ? "—" : p.displayName)
                    .foregroundStyle(p.isPaused ? AppColor.text3 : AppColor.text)
                if p.isPaused { pausedBadge }
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
                .disabled(p.isPaused)

                Button {
                    if p.isPaused { store.resumeParticipant(p) } else { store.pauseParticipant(p) }
                } label: {
                    Label(p.isPaused ? "Resume access" : "Pause access",
                          systemImage: p.isPaused ? "play.circle" : "pause.circle")
                        .font(.subheadline.weight(.medium))
                }
                .tint(p.isPaused ? AppColor.accentSleep : AppColor.text2)
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

    /// Marks a row whose access is paused — sits beside the name, ahead of the
    /// role pill, so it reads before "Co-parent"/"Guest" rather than after.
    private var pausedBadge: some View {
        Text("Paused")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(AppColor.text3.opacity(0.16), in: Capsule())
            .foregroundStyle(AppColor.text3)
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
}
