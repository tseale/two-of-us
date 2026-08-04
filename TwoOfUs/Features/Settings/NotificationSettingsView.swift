import SwiftUI
import SwiftData

/// "Notifications & Alarms" subpage: the AlarmKit reminders (feed / my slot /
/// tone), co-parent activity notifications, gentle nudges + daily summary,
/// and quiet hours. All per-device (`LocalPrefs`).
struct NotificationSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var babies: [Baby]
    @Query private var settingsList: [SharedSettings]
    @State private var prefs = LocalPrefs.shared

    private var baby: Baby? { babies.first }
    private var settings: SharedSettings? { SharedSettings.canonical(settingsList) }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $prefs.feedReminderEnabled) {
                    SettingsIconLabel(title: "Feed reminder", systemImage: "bell.badge",
                                      tint: AppColor.urgencyAmber)
                }
                .onChange(of: prefs.feedReminderEnabled) { _, on in
                    Task { await updateFeedAlarm(enabled: on) }
                }
                Toggle(isOn: $prefs.nightSlotAlarmEnabled) {
                    SettingsIconLabel(title: "My slot alarm", systemImage: "alarm",
                                      tint: AppColor.accentSleep)
                }
                .onChange(of: prefs.nightSlotAlarmEnabled) { _, on in
                    Task { await updateSlotAlarm(enabled: on) }
                }
                Picker(selection: $prefs.alarmTone) {
                    ForEach(AlarmTone.allCases) { tone in
                        Text(tone.label).tag(tone)
                    }
                } label: {
                    SettingsIconLabel(title: "Alarm sound", systemImage: "speaker.wave.2.fill",
                                      tint: AppColor.urgencyAmber)
                }
                .onChange(of: prefs.alarmTone) { _, tone in
                    AlarmTonePreview.play(tone)
                    Task { await rearmAlarms() }   // a pending alarm re-arms with the new tone
                }
            } header: {
                Text("Reminders")
            } footer: {
                Text("Feed reminder alerts you when the next feed is due; My slot alarm wakes you for nighttime-schedule slots that are yours (an unassigned slot wakes both of you) — both even on Silent or Focus, and only near your own slot one of them rings. Alarm sound applies to both. This device only.")
            }

            Section {
                Toggle(isOn: $prefs.notifyFeed) {
                    SettingsIconLabel(title: "Feeds", systemImage: "drop.fill", tint: AppColor.accentFeed)
                }
                .onChange(of: prefs.notifyFeed) { _, _ in notificationsChanged() }
                Toggle(isOn: $prefs.notifySleep) {
                    SettingsIconLabel(title: "Sleep", systemImage: "moon.fill", tint: AppColor.accentSleep)
                }
                .onChange(of: prefs.notifySleep) { _, _ in notificationsChanged() }
                Toggle(isOn: $prefs.notifyDiaper) {
                    SettingsIconLabel(title: "Diapers", systemImage: "leaf.fill", tint: AppColor.accentDiaper)
                }
                .onChange(of: prefs.notifyDiaper) { _, _ in notificationsChanged() }
            } header: {
                Text("When your co-parent logs")
            } footer: {
                Text("A quiet heads-up — with their photo — when the other parent logs. You're never notified for your own entries.")
            }

            Section {
                Toggle(isOn: $prefs.gentleRemindersEnabled) {
                    SettingsIconLabel(title: "Gentle reminders", systemImage: "bell", tint: AppColor.urgencyAmber)
                }
                .onChange(of: prefs.gentleRemindersEnabled) { _, _ in notificationsChanged() }
                Toggle(isOn: $prefs.notifyMilestones) {
                    SettingsIconLabel(title: "Daily summary", systemImage: "chart.bar.fill", tint: AppColor.accentSleep)
                }
                .onChange(of: prefs.notifyMilestones) { _, _ in notificationsChanged() }
            } header: {
                Text("Nudges")
            } footer: {
                Text("Soft “feed due / diaper check” nudges you can log or snooze right from the lock screen, plus an end-of-day recap. The feed nudge stays silent while the Feed reminder alarm is on, so you’re never told twice.")
            }

            Section {
                Toggle(isOn: $prefs.quietHoursEnabled) {
                    SettingsIconLabel(title: "Quiet hours", systemImage: "moon.zzz.fill", tint: .gray)
                }
                .onChange(of: prefs.quietHoursEnabled) { _, _ in notificationsChanged() }
                if prefs.quietHoursEnabled {
                    DatePicker("From", selection: quietStart, displayedComponents: .hourAndMinute)
                    DatePicker("To", selection: quietEnd, displayedComponents: .hourAndMinute)
                }
            } header: {
                Text("Quiet hours")
            } footer: {
                Text("Mutes co-parent and summary notifications overnight. The Feed reminder alarm still breaks through.")
            }
        }
        .navigationTitle("Notifications & Alarms")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Feed reminder

    /// Arms or clears this device's AlarmKit feed reminder when the toggle flips.
    /// Reverts the toggle if the user declines alarm authorization.
    private func updateFeedAlarm(enabled: Bool) async {
        guard enabled else {
            await FeedAlarmManager.cancel()
            NotificationManager.refreshScheduledReminders()  // gentle feed nudge may take over
            return
        }
        guard await FeedAlarmManager.requestAuthorization() else {
            prefs.feedReminderEnabled = false
            return
        }
        // Enabling reminders here (not via the primer quest) still finishes the
        // reminders setup quest — durably, so a later toggle-off won't reopen it.
        SetupProgress.shared.markComplete(.reminders)
        let lastFeed = lastFeedDate()
        await FeedAlarmManager.reschedule(babyName: baby?.name ?? "Baby",
                                          lastFeed: lastFeed,
                                          interval: lastFeed.flatMap { settings?.feedInterval(after: $0) } ?? 0)
        NotificationManager.refreshScheduledReminders()      // stand the gentle feed nudge down
    }

    /// Re-arms whichever alarms are pending so they pick up a changed tone —
    /// AlarmKit bakes the sound in at schedule time, so a tone switch has to
    /// reschedule (the managers no-op for anything disabled or not due).
    private func rearmAlarms() async {
        await SlotAlarmManager.reschedule()
        let lastFeed = lastFeedDate()
        await FeedAlarmManager.reschedule(babyName: baby?.name ?? "Baby",
                                          lastFeed: lastFeed,
                                          interval: lastFeed.flatMap { settings?.feedInterval(after: $0) } ?? 0)
    }

    /// Arms or clears the loud "my slot" alarm when the toggle flips. Reverts
    /// the toggle if the user declines alarm authorization. Also re-arms the
    /// interval feed alarm, whose stand-down window depends on this state.
    private func updateSlotAlarm(enabled: Bool) async {
        if enabled {
            guard await SlotAlarmManager.requestAuthorization() else {
                prefs.nightSlotAlarmEnabled = false
                return
            }
        }
        await SlotAlarmManager.reschedule()   // arms when enabled, clears when not
        let lastFeed = lastFeedDate()
        await FeedAlarmManager.reschedule(babyName: baby?.name ?? "Baby",
                                          lastFeed: lastFeed,
                                          interval: lastFeed.flatMap { settings?.feedInterval(after: $0) } ?? 0)
    }

    /// Requests notification authorization (once) and re-applies the schedules
    /// whenever a notification preference changes.
    private func notificationsChanged() {
        Task {
            await NotificationManager.requestAuthorization()
            NotificationManager.refreshScheduledReminders()
            NotificationManager.refreshDailyMilestone()
        }
    }

    /// Quiet-hours pickers bridge `Date` (hour+minute) to minutes-from-midnight.
    private var quietStart: Binding<Date> {
        Binding(get: { Self.date(fromMinutes: prefs.quietHoursStartMinutes) },
                set: { prefs.quietHoursStartMinutes = Self.minutes(from: $0); notificationsChanged() })
    }
    private var quietEnd: Binding<Date> {
        Binding(get: { Self.date(fromMinutes: prefs.quietHoursEndMinutes) },
                set: { prefs.quietHoursEndMinutes = Self.minutes(from: $0); notificationsChanged() })
    }
    private static func date(fromMinutes m: Int) -> Date {
        Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: .now) ?? .now
    }
    private static func minutes(from date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func lastFeedDate() -> Date? {
        var d = FetchDescriptor<FeedEvent>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first?.timestamp
    }
}
