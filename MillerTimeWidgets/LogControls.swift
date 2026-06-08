import WidgetKit
import SwiftUI
import AppIntents

// Control Center / Lock Screen / Action button controls (iOS 18+).
// Each is a one-press button that runs an existing App Intent — no new write
// path. Gated with @available so the iOS 17 deployment target keeps compiling;
// the WidgetBundle includes them behind `if #available`.

@available(iOS 18.0, *)
struct LogFeedControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.taylorseale.millertime.control.feed") {
            ControlWidgetButton(action: LogFeedIntent()) {
                Label("Log Feed", systemImage: "drop.fill")
            }
        }
        .displayName("Log Feed")
        .description("Log a bottle for Miller using your default amount.")
    }
}

@available(iOS 18.0, *)
struct LogDiaperControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.taylorseale.millertime.control.diaper") {
            ControlWidgetButton(action: LogDiaperIntent()) {
                Label("Log Diaper", systemImage: "leaf.fill")
            }
        }
        .displayName("Log Diaper")
        .description("Log a wet diaper change for Miller.")
    }
}

@available(iOS 18.0, *)
struct ToggleSleepControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.taylorseale.millertime.control.sleep") {
            ControlWidgetButton(action: ToggleSleepIntent()) {
                Label("Sleep", systemImage: "moon.fill")
            }
        }
        .displayName("Start / Stop Sleep")
        .description("Start a sleep timer for Miller, or stop the running one.")
    }
}
