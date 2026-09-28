import SwiftUI

/// "Integrations" subpage — SNOO and Brightwheel.
/// Owns the SNOO login sheet's presentation state: presenting from this Form's
/// root (not from inside `SnooSettingsSection`) avoids the List-cell-recycle
/// race that tore down the sheet when it was owned by the row itself.
struct IntegrationsSettingsView: View {
    @State private var snooLogin: SnooSettingsSection.LoginPresentation?
    @State private var showBrightwheelLogin = false

    var body: some View {
        Form {
            SnooSettingsSection(login: $snooLogin)
            BrightwheelSettingsSection(showLogin: $showBrightwheelLogin)
        }
        .navigationTitle("Integrations")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $snooLogin) { presentation in
            SnooLoginSheet(prefilledEmail: presentation.email)
        }
        .sheet(isPresented: $showBrightwheelLogin) {
            BrightwheelLoginSheet()
        }
    }
}
