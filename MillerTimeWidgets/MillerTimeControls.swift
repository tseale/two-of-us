import AppIntents
import SwiftUI
import WidgetKit

// Control Center / Lock Screen / Action Button surfaces (iOS 18+).
//
// These reuse the existing App Intents that already back the home-screen widget
// buttons and Siri, so a tap here goes through the same QuickLogger write path
// (App Group store + `sync.pendingWidgetWrites` queue, drained by the app).

/// One-tap "Log feed" control — uses the default feed amount.
struct LogFeedControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.taylorseale.millertime.control.feed") {
            ControlWidgetButton(action: LogFeedIntent()) {
                Label("Log Feed", systemImage: "drop.fill")
            }
            .tint(AppColor.accentFeed)
        }
        .displayName("Log Feed")
        .description("Log a bottle for Miller.")
    }
}

/// One-tap "Log diaper" control — defaults to a wet change.
struct LogDiaperControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.taylorseale.millertime.control.diaper") {
            ControlWidgetButton(action: LogDiaperIntent()) {
                Label("Log Diaper", systemImage: "leaf.fill")
            }
            .tint(AppColor.accentDiaper)
        }
        .displayName("Log Diaper")
        .description("Log a diaper change for Miller.")
    }
}

/// Sleep on/off toggle — reflects whether a sleep is currently running.
struct SleepToggleControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "com.taylorseale.millertime.control.sleep",
            provider: SleepStateProvider()
        ) { isAsleep in
            ControlWidgetToggle(
                "Sleep",
                isOn: isAsleep,
                action: SetSleepIntent()
            ) { asleep in
                Label(asleep ? "Asleep" : "Awake",
                      systemImage: asleep ? "moon.zzz.fill" : "sun.max.fill")
            }
            .tint(AppColor.accentSleep)
        }
        .displayName("Sleep Timer")
        .description("Start or stop Miller's sleep.")
    }
}

/// Supplies the current sleep state to `SleepToggleControl`.
struct SleepStateProvider: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        QuickLogger.make()?.activeSleep != nil
    }
}

/// `SetValueIntent` backing the sleep toggle: drives sleep to the requested
/// state, reusing `QuickLogger.toggleSleep()` only when a change is needed.
struct SetSleepIntent: SetValueIntent {
    static var title: LocalizedStringResource = "Set Sleep State"
    static var description = IntentDescription("Starts or stops Miller's sleep timer.")

    @Parameter(title: "Asleep")
    var value: Bool

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let logger = QuickLogger.make() else { return .result() }
        let isActive = logger.activeSleep != nil
        if value != isActive { logger.toggleSleep() }
        return .result()
    }
}
