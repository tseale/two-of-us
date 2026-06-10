import AppIntents

/// Exposes the log + query intents to Siri ("Hey Siri, log a diaper"), Spotlight,
/// and the Shortcuts app — no separate extension needed.
///
/// Note: iOS allows up to 10 App Shortcuts per app; we register 8.
struct TwoOfUsShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .teal }

    static var appShortcuts: [AppShortcut] {
        // MARK: Logging
        AppShortcut(
            intent: LogFeedIntent(),
            // Note: App Shortcut phrases can only interpolate AppEntity/AppEnum
            // parameters, not a raw Double — so a spoken ounce amount can't be a
            // phrase. The `amountOz` parameter is still settable in the Shortcuts
            // app (build a "Log 3 oz" shortcut there).
            phrases: [
                "Log a feed in \(.applicationName)",
                "Log a bottle in \(.applicationName)",
                "\(.applicationName) feed"
            ],
            shortTitle: "Log Feed",
            systemImageName: "drop.fill"
        )
        AppShortcut(
            intent: LogDiaperIntent(),
            phrases: [
                "Log a diaper in \(.applicationName)",
                "Log a diaper change in \(.applicationName)",
                "Log a \(\.$type) diaper in \(.applicationName)",
                "\(.applicationName) diaper"
            ],
            shortTitle: "Log Diaper",
            systemImageName: "leaf.fill"
        )
        AppShortcut(
            intent: ToggleSleepIntent(),
            phrases: [
                "Start sleep in \(.applicationName)",
                "Stop sleep in \(.applicationName)",
                "\(.applicationName) sleep"
            ],
            shortTitle: "Sleep",
            systemImageName: "moon.fill"
        )

        // MARK: Queries ("ask Two of Us")
        AppShortcut(
            intent: LastFeedIntent(),
            phrases: [
                "When did the baby last eat in \(.applicationName)",
                "The baby's last feed in \(.applicationName)",
                "\(.applicationName) last feed"
            ],
            shortTitle: "Last Feed",
            systemImageName: "clock.fill"
        )
        AppShortcut(
            intent: LastDiaperIntent(),
            phrases: [
                "When was the baby's last diaper in \(.applicationName)",
                "\(.applicationName) last diaper"
            ],
            shortTitle: "Last Diaper",
            systemImageName: "clock.badge.questionmark"
        )
        AppShortcut(
            intent: SleepStatusIntent(),
            phrases: [
                "Is the baby asleep in \(.applicationName)",
                "How long has the baby been sleeping in \(.applicationName)",
                "\(.applicationName) sleep status"
            ],
            shortTitle: "Sleep Status",
            systemImageName: "bed.double.fill"
        )
        AppShortcut(
            intent: TodaySummaryIntent(),
            phrases: [
                "How is the baby doing today in \(.applicationName)",
                "The baby's day in \(.applicationName)",
                "\(.applicationName) today"
            ],
            shortTitle: "Today",
            systemImageName: "sun.max.fill"
        )
        AppShortcut(
            intent: UndoLastLogIntent(),
            phrases: [
                "Undo that in \(.applicationName)",
                "Undo the last log in \(.applicationName)",
                "\(.applicationName) undo"
            ],
            shortTitle: "Undo Last Log",
            systemImageName: "arrow.uturn.backward"
        )
    }
}
