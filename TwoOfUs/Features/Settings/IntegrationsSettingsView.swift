import SwiftUI

/// "Integrations" subpage — SNOO today, with room for future integrations.
/// Owns the SNOO login sheet's presentation state: presenting from this Form's
/// root (not from inside `SnooSettingsSection`) avoids the List-cell-recycle
/// race that tore down the sheet when it was owned by the row itself.
struct IntegrationsSettingsView: View {
    @State private var snooLogin: SnooSettingsSection.LoginPresentation?

    var body: some View {
        Form {
            SnooSettingsSection(login: $snooLogin)
        }
        .navigationTitle("Integrations")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $snooLogin) { presentation in
            SnooLoginSheet(prefilledEmail: presentation.email)
        }
    }
}
