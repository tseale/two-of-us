import WidgetKit
import SwiftUI
import AppIntents

// Control Center / Lock Screen / Action button controls (iOS 18+).
// Each runs an existing App Intent — no new write path. Gated with @available
// because the ControlWidget APIs are iOS 18+; the WidgetBundle includes them
// behind `if #available`.

@available(iOS 18.0, *)
struct LogFeedControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.taylorseale.twoofus.control.feed") {
            ControlWidgetButton(action: LogFeedIntent()) {
                Label("Log Feed", systemImage: "drop.fill")
            }
            .tint(AppColor.accentFeed)
        }
        .displayName("Log Feed")
        .description("Log a bottle for your baby using your default amount.")
    }
}

@available(iOS 18.0, *)
struct LogDiaperControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.taylorseale.twoofus.control.diaper") {
            ControlWidgetButton(action: LogDiaperIntent()) {
                Label("Log Diaper", systemImage: "leaf.fill")
            }
            .tint(AppColor.accentDiaper)
        }
        .displayName("Log Diaper")
        .description("Log a wet diaper change for your baby.")
    }
}

/// Stateful sleep toggle — reflects whether a sleep is currently running and
/// drives it to the requested state, rather than a one-press blind toggle.
@available(iOS 18.0, *)
struct ToggleSleepControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "com.taylorseale.twoofus.control.sleep",
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
        .displayName("Start / Stop Sleep")
        .description("Start a sleep timer for your baby, or stop the running one.")
    }
}

/// Supplies the current sleep state (asleep = a sleep is running) to the toggle.
@available(iOS 18.0, *)
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
    static var description = IntentDescription("Starts or stops your baby's sleep timer.")

    @Parameter(title: "Asleep")
    var value: Bool

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let logger = QuickLogger.make() else { return .result() }
        let isActive = logger.activeSleep != nil
        if value != isActive { logger.toggleSleep() }
        // Waking up: end the Live Activity right here. This intent backs the
        // lock-screen / Dynamic Island Wake button and runs in the widget
        // process, which can't rely on the app foregrounding to reconcile.
        if !value { await SleepActivityAttributes.endAllRunning() }
        return .result()
    }
}
