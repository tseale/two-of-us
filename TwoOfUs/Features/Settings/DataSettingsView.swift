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

            Section {
                Toggle(isOn: $prefs.paintedSky) {
                    SettingsIconLabel(title: "Painted sky", systemImage: "moon.stars", tint: AppColor.accentSleep)
                }
                if prefs.paintedSky {
                    NavigationLink("Sky bench") { SkyBench() }
                }
            } header: {
                Text("In the works")
            } footer: {
                Text("Home's new sky, still being built. Only this phone is changed, and turning it off puts everything back.")
            }
        }
        .navigationTitle("Data")
        .navigationBarTitleDisplayMode(.inline)
    }
}
