import SwiftUI
import SwiftData

/// Shown to the joining parent right after they accept a share: the baby's data
/// has synced in (so they skip onboarding), but they still need to set their own
/// name + color so events they log are attributed to them.
struct JoinProfileView: View {
    @Environment(\.modelContext) private var context
    @Query private var babies: [Baby]

    @State private var name = ""
    @State private var colorHex = ParticipantColors.palette[1]

    private var canContinue: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("You've joined \(babies.first?.name ?? "the baby")'s log as a guest. Set up your profile so what you log shows as yours — a parent can give you full access if needed.")
                        .font(.footnote)
                        .foregroundStyle(AppColor.text3)
                }
                Section("You") {
                    TextField("Your name", text: $name)
                    ParticipantColorPicker(selection: $colorHex)
                }
            }
            .navigationTitle("Welcome")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { finish() }.disabled(!canContinue)
                }
            }
        }
    }

    private func finish() {
        // New joiners start as guests (least privilege); the owner can promote
        // the other parent to co-parent from Settings → People.
        let me = Participant(displayName: name.trimmingCharacters(in: .whitespaces),
                             colorHex: colorHex, role: .logger)
        context.insert(me)
        try? context.save()
        LocalPrefs.shared.myParticipantID = me.id
        SyncManager.shared?.enqueueSave([me.id])
        Haptics.success()
    }
}
