import SwiftUI
import SwiftData

/// Settings shell. A baby profile header + your identity card + any pending
/// setup quests stay inline; everything else is a short list of category rows,
/// each pushing a focused subpage (Apple-Settings style) — kept scannable for
/// a parent holding a baby. Editing baby / your profile happens in focused
/// sheets presented from here.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var babies: [Baby]
    @Query private var settingsList: [SharedSettings]
    @Query private var participants: [Participant]
    @State private var prefs = LocalPrefs.shared
    @State private var setup = SetupProgress.shared
    @State private var watchStatus = WatchAppStatus.shared
    @State private var showBabyEdit = false
    @State private var showProfileEdit = false
    @State private var questSheet: SetupQuest?

    private var baby: Baby? { babies.first }
    private var settings: SharedSettings? { SharedSettings.canonical(settingsList) }

    /// The local user's own participant record (for the "You" card).
    private var me: Participant? {
        participants.first { $0.id == prefs.myParticipantID } ?? participants.first
    }

    /// This device's app role. Loggers can't change shared baby/feeding
    /// settings, so the Feeding & Tracking category is hidden for them.
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

                Section {
                    if canEditShared {
                        NavigationLink {
                            FeedingSettingsView()
                        } label: {
                            SettingsIconLabel(title: "Feeding & Tracking", systemImage: "drop.fill",
                                              tint: AppColor.accentFeed)
                        }
                    }
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        SettingsIconLabel(title: "Notifications & Alarms", systemImage: "bell.badge",
                                          tint: AppColor.urgencyAmber)
                    }
                    NavigationLink {
                        PeopleSettingsView()
                    } label: {
                        SettingsIconLabel(title: "People & Sharing", systemImage: "person.2.fill",
                                          tint: AppColor.accentSleep)
                    }
                    if SnooFeature.isEnabled && !prefs.demoModeEnabled {
                        NavigationLink {
                            IntegrationsSettingsView()
                        } label: {
                            SettingsIconLabel(title: "Integrations", systemImage: "puzzlepiece.extension.fill",
                                              tint: AppColor.accentDiaper)
                        }
                    }
                }

                Section {
                    // Read-only: whether the companion app is on the paired
                    // watch. There is no "connection" beyond this — the watch
                    // syncs through CloudKit, never through the phone.
                    if let watchLabel = watchStatus.state.label {
                        LabeledContent {
                            Text(watchLabel)
                        } label: {
                            SettingsIconLabel(title: "Apple Watch", systemImage: "applewatch",
                                              tint: .gray)
                        }
                    }
                    NavigationLink {
                        DataSettingsView()
                    } label: {
                        SettingsIconLabel(title: "Data", systemImage: "externaldrive", tint: .gray)
                    }
                    NavigationLink {
                        AboutSettingsView()
                    } label: {
                        SettingsIconLabel(title: "About", systemImage: "info.circle", tint: .gray)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
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
                Text(baby.flatMap { $0.name.isEmpty ? nil : $0.name } ?? "Baby")
                    .font(AppFont.hero(26))
                    .foregroundStyle(AppColor.text)
                if let baby {
                    // The age string already says "due in …" for a future date,
                    // so the suffix carries just the date to avoid "due … due".
                    Text("\(TimeFormatting.age(from: baby.dateOfBirth)) · \(baby.isBorn ? "born " : "")\(baby.dateOfBirth.formatted(.dateTime.month().day()))")
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
                    Text(me.flatMap { $0.displayName.isEmpty ? nil : $0.displayName } ?? "Your name")
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
}
