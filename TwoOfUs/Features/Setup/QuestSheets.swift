import SwiftUI
import SwiftData

/// The deferred-setup quest sheets: each hosts the matching onboarding step on
/// the same ambient backdrop, commits on the trailing toolbar action, and marks
/// its quest complete. Self-contained 30-second moments — opened from the Home
/// checklist card, Settings, or (reminders) the just-in-time offer after a feed.

// MARK: - Rhythm

struct RhythmQuestSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [SharedSettings]

    @State private var intervalMinutes = 180
    @State private var ozPresets: [Double] = [2, 3, 4]
    @State private var seeded = false
    @State private var revealed = false

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(stop: AmbientStop(subtle: true, top: AppColor.accentFeed,
                                                    bottom: AppColor.accentSleep))
                RhythmStep(intervalMinutes: $intervalMinutes, ozPresets: $ozPresets,
                           revealed: revealed, barClearance: false)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
        .onAppear {
            if !seeded, let s = settingsList.first {
                intervalMinutes = s.targetFeedIntervalMinutes
                ozPresets = s.ozPresets
                seeded = true
            }
            revealed = true
        }
    }

    private func save() {
        EventStore(context: context)
            .updateSettings(targetFeedIntervalMinutes: intervalMinutes, ozPresets: ozPresets)
        SetupProgress.shared.markComplete(.rhythm)
        Haptics.success()
        dismiss()
    }
}

// MARK: - Reminders

struct RemindersQuestSheet: View {
    /// Just-in-time variant shows what the reminder would say right now, e.g.
    /// "Next bottle around 4:30 PM".
    var contextLine: String? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var on = false
    @State private var revealed = false

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(stop: AmbientStop(subtle: true, top: AppColor.accentFeed,
                                                    bottom: AppColor.accentSleep))
                RemindersStep(on: $on, revealed: revealed, contextLine: contextLine,
                              barClearance: false)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { finish() }
                }
            }
        }
        .onAppear { revealed = true }
    }

    /// The step's toggle already secured authorization on flip, so `on` here
    /// means granted. Done with the toggle off just closes — the quest stays
    /// open in the checklist/Settings.
    private func finish() {
        guard on else { dismiss(); return }
        LocalPrefs.shared.feedReminderEnabled = true
        SetupProgress.shared.markComplete(.reminders)
        let store = EventStore(context: context)
        let babyName = store.baby?.name ?? "Baby"
        let lastFeed = store.lastEventDate(of: .feed)
        let interval = store.settings?.targetFeedInterval ?? 0
        Task { await FeedAlarmManager.reschedule(babyName: babyName, lastFeed: lastFeed,
                                                 interval: interval) }
        Haptics.success()
        dismiss()
    }
}

#Preview("Rhythm quest") {
    RhythmQuestSheet()
        .modelContainer(AppModelContainer.preview)
}

#Preview("Reminders quest") {
    RemindersQuestSheet(contextLine: "Next bottle around 4:30 PM")
        .modelContainer(AppModelContainer.preview)
}
