import SwiftUI
import SwiftData

/// Settings shell. Shared settings (Full role) + per-user prefs.
/// Manage People and full notification scheduling arrive in later increments.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var babies: [Baby]
    @Query private var settingsList: [SharedSettings]
    @State private var prefs = LocalPrefs.shared

    private var baby: Baby? { babies.first }
    private var settings: SharedSettings? { settingsList.first }

    var body: some View {
        NavigationStack {
            Form {
                Section("Baby") {
                    if let baby {
                        LabeledContent("Name", value: baby.name)
                        DatePicker("Date of birth",
                                   selection: Binding(get: { baby.dateOfBirth },
                                                      set: { baby.dateOfBirth = $0; try? context.save() }),
                                   in: ...Date(), displayedComponents: .date)
                    }
                }

                if let settings {
                    Section("Feeding") {
                        Stepper(value: Binding(get: { settings.targetFeedIntervalMinutes },
                                               set: { settings.targetFeedIntervalMinutes = $0; try? context.save() }),
                                in: 60...360, step: 15) {
                            Text("Target interval: \(settings.targetFeedIntervalMinutes / 60)h \(settings.targetFeedIntervalMinutes % 60)m")
                        }
                    }
                }

                Section("My notifications") {
                    Toggle("Feeds", isOn: $prefs.notifyFeed)
                    Toggle("Sleep", isOn: $prefs.notifySleep)
                    Toggle("Diapers", isOn: $prefs.notifyDiaper)
                    Toggle("Feed reminder", isOn: $prefs.feedReminderEnabled)
                }
                .disabled(true)
                footerNote
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private var footerNote: some View {
        Section {
            Text("Manage People, sharing, and notification delivery arrive in upcoming updates.")
                .font(.footnote)
                .foregroundStyle(AppColor.text3)
        }
    }
}
