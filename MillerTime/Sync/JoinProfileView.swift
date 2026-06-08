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
                    Text("You've joined \(babies.first?.name ?? "the baby")'s log. Set up your profile so what you log shows as yours.")
                        .font(.footnote)
                        .foregroundStyle(AppColor.text3)
                }
                Section("You") {
                    TextField("Your name", text: $name)
                    colorPicker
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

    private var colorPicker: some View {
        HStack(spacing: 12) {
            Text("Your color")
            Spacer()
            ForEach(ParticipantColors.palette, id: \.self) { hex in
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 28, height: 28)
                    .overlay(Circle().stroke(AppColor.text, lineWidth: colorHex == hex ? 2 : 0))
                    .onTapGesture { colorHex = hex }
                    .accessibilityLabel("Color \(hex)")
            }
        }
    }

    private func finish() {
        let me = Participant(displayName: name.trimmingCharacters(in: .whitespaces),
                             colorHex: colorHex, role: .full)
        context.insert(me)
        try? context.save()
        LocalPrefs.shared.myParticipantID = me.id
        SyncManager.shared?.enqueueSave([me.id])
        Haptics.success()
    }
}
