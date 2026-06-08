import AppIntents

/// Exposes the quick-log intents to Siri ("Hey Siri, log a diaper"), Spotlight,
/// and the Shortcuts app — no separate extension needed.
struct MillerTimeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogFeedIntent(),
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
    }
}
