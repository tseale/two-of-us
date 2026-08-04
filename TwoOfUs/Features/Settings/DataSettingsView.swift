import SwiftUI

/// "Data" subpage: the low-frequency device/app-behavior settings — theme,
/// data lifecycle (export / clear / delete via `ManageDataSections`), and
/// demo mode.
struct DataSettingsView: View {
    @State private var prefs = LocalPrefs.shared

    var body: some View {
        Form {
            Section("Appearance") {
                Picker(selection: $prefs.appearance) {
                    ForEach(Appearance.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                } label: {
                    SettingsIconLabel(title: "Theme", systemImage: "circle.lefthalf.filled",
                                      tint: AppColor.accentSleep)
                }
            }

            ManageDataSections()

            Section {
                Toggle(isOn: $prefs.demoModeEnabled) {
                    SettingsIconLabel(title: "Demo mode", systemImage: "sparkles", tint: AppColor.accentDiaper)
                }
                if prefs.demoModeEnabled {
                    Button("Reset demo data") {
                        // Re-seed by dropping back to real and re-entering demo.
                        prefs.demoModeEnabled = false
                        DispatchQueue.main.async { prefs.demoModeEnabled = true }
                    }
                }
            } header: {
                Text("Demo mode")
            } footer: {
                Text("Shows sample data so you can explore the app. Your real entries are hidden and untouched, and nothing syncs while demo mode is on.")
            }
        }
        .navigationTitle("Data")
        .navigationBarTitleDisplayMode(.inline)
    }
}
