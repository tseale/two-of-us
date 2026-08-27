import SwiftUI
import SwiftData

/// "Feeding & Tracking" subpage: the shared feed-interval target and the
/// what-to-track toggles. Settings hides the row for loggers, but each section
/// still gates on the role so a mid-session role change degrades gracefully.
struct FeedingSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [SharedSettings]
    @Query private var participants: [Participant]
    @Query private var babies: [Baby]
    @State private var prefs = LocalPrefs.shared

    private var settings: SharedSettings? { SharedSettings.canonical(settingsList) }
    private var babyName: String { babies.first?.name ?? "your baby" }
    private var store: EventStore { EventStore(context: context) }

    private var canEditShared: Bool {
        (participants.first { $0.id == prefs.myParticipantID }?.role ?? .full) == .full
    }

    var body: some View {
        Form {
            if let settings, canEditShared {
                Section("Feeding") {
                    Stepper(value: Binding(get: { settings.targetFeedIntervalMinutes },
                                           set: { store.updateSettings(targetFeedIntervalMinutes: $0) }),
                            in: 60...360, step: 15) {
                        SettingsIconLabel(
                            title: "Feed every \(intervalLabel(settings.targetFeedIntervalMinutes))",
                            systemImage: "timer", tint: AppColor.accentFeed)
                    }
                    // Common presets for quick selection. Chip styling lives
                    // INSIDE the button label (with a 44pt-min frame), so the
                    // whole capsule is tappable — not just the caption text.
                    HStack(spacing: 8) {
                        ForEach([120, 150, 180, 240], id: \.self) { mins in
                            let selected = settings.targetFeedIntervalMinutes == mins
                            Button {
                                store.updateSettings(targetFeedIntervalMinutes: mins)
                            } label: {
                                Text(intervalLabel(mins))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(selected ? AppColor.accentFeed : AppColor.text2)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(selected ? AppColor.accentFeed.opacity(0.15) : AppColor.card2,
                                                in: Capsule())
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel("Feed every \(spokenInterval(mins))")
                            .accessibilityAddTraits(selected ? [.isSelected] : [])
                        }
                        Spacer()
                    }
                    .buttonStyle(.plain)

                    Stepper(value: Binding(get: { settings.defaultFeedOz },
                                           set: { store.updateSettings(defaultFeedOz: $0) }),
                            in: 0.5...20, step: 0.5) {
                        SettingsIconLabel(
                            title: "Default amount \(OzFormat.string(settings.defaultFeedOz)) oz",
                            systemImage: "drop.fill", tint: AppColor.accentFeed)
                    }
                    HStack(spacing: 8) {
                        ForEach([1.0, 2.0, 3.0, 4.0], id: \.self) { oz in
                            let selected = settings.defaultFeedOz == oz
                            Button {
                                store.updateSettings(defaultFeedOz: oz)
                            } label: {
                                Text("\(OzFormat.string(oz)) oz")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(selected ? AppColor.accentFeed : AppColor.text2)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(selected ? AppColor.accentFeed.opacity(0.15) : AppColor.card2,
                                                in: Capsule())
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel("Default amount \(OzFormat.string(oz)) oz")
                            .accessibilityAddTraits(selected ? [.isSelected] : [])
                        }
                        Spacer()
                    }
                    .buttonStyle(.plain)
                }

                Section {
                    trackerToggle(.feed, title: "Feed", systemImage: "drop.fill",
                                  tint: AppColor.accentFeed, settings: settings)
                    trackerToggle(.sleep, title: "Sleep", systemImage: "moon.fill",
                                  tint: AppColor.accentSleep, settings: settings)
                    trackerToggle(.diaper, title: "Diaper", systemImage: "leaf.fill",
                                  tint: AppColor.accentDiaper, settings: settings)
                } header: {
                    Text("What to track")
                } footer: {
                    Text("Turn a tracker off to hide its button and stop logging that event — handy when logging one of them isn't worth it for a while. Existing entries are preserved, both parents see the same trackers, and at least one always stays on.")
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { settings.aiPredictionsEnabled },
                        set: { store.updateSettings(aiPredictionsEnabled: $0) }
                    )) {
                        SettingsIconLabel(title: "Predictions & Insights", systemImage: "sparkles",
                                          tint: AppColor.accentSleep)
                    }
                } header: {
                    Text("AI Features")
                } footer: {
                    Text("Predicts the next bottle, amounts, and wake times from your own logs, and writes the weekly insights summary. Everything is computed on your iPhone — nothing about \(babyName) leaves your device. Shared with your co-parent. Not medical advice.")
                }
            }
        }
        .navigationTitle("Feeding & Tracking")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// One "What to track" row. The last enabled tracker's toggle locks on —
    /// with all three off the app would have nothing to log. Alarm/nudge/widget
    /// refresh rides on `EventStore.updateSettings`, so a co-parent's flip
    /// (which arrives through sync, not this view) behaves identically.
    private func trackerToggle(_ kind: EventKind, title: String, systemImage: String,
                               tint: Color, settings: SharedSettings) -> some View {
        let isLastEnabled = settings.isEnabled(kind) && settings.enabledTrackerCount == 1
        return Toggle(isOn: Binding(
            get: { settings.isEnabled(kind) },
            set: { on in
                switch kind {
                case .feed:   store.updateSettings(feedLoggingEnabled: on)
                case .sleep:  store.updateSettings(sleepLoggingEnabled: on)
                case .diaper: store.updateSettings(diaperLoggingEnabled: on)
                }
            }
        )) {
            SettingsIconLabel(title: title, systemImage: systemImage, tint: tint)
        }
        .disabled(isLastEnabled)
        .accessibilityHint(isLastEnabled
            ? "At least one tracker stays on"
            : "Turn off to hide the \(title.lowercased()) button and stop logging \(title.lowercased()) events. Existing entries are preserved.")
    }

    /// "2h", "2h 30m", "3h" — omits the "0m" that made the stepper label verbose.
    private func intervalLabel(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// Fully spelled-out form for VoiceOver — "2h 30m" reads poorly aloud.
    private func spokenInterval(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        let hours = h == 1 ? "1 hour" : "\(h) hours"
        if m == 0 { return hours }
        let mins = m == 1 ? "1 minute" : "\(m) minutes"
        return h == 0 ? mins : "\(hours) \(mins)"
    }
}
