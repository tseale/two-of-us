import SwiftUI
import SwiftData

/// First launch (owner): name, date of birth, and the owner's display name + color.
struct OnboardingView: View {
    @Environment(\.modelContext) private var context

    @State private var babyName = "Miller"
    @State private var dateOfBirth = Date()
    @State private var ownerName = ""
    @State private var ownerColorHex = ParticipantColors.palette[0]

    private var canContinue: Bool {
        !babyName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !ownerName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The name to greet with, falling back gracefully while the field is empty.
    private var displayBabyName: String {
        let trimmed = babyName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "your little one" : trimmed
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        Text("👶").font(.system(size: 52))
                        Text("Welcome to Miller Time")
                            .font(AppFont.hero(26))
                            .multilineTextAlignment(.center)
                        Text("A calm little log for \(displayBabyName)'s feeds, sleeps, and diapers — made for one-handed 3am taps.")
                            .font(.subheadline)
                            .foregroundStyle(AppColor.text2)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .listRowBackground(Color.clear)
                }

                Section("Baby") {
                    TextField("Name", text: $babyName)
                    DatePicker("Date of birth", selection: $dateOfBirth, in: ...Date(), displayedComponents: .date)
                }

                Section("You") {
                    TextField("Your name", text: $ownerName)
                    ParticipantColorPicker(selection: $ownerColorHex)
                }
            }
            .navigationTitle("Welcome")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") { finish() }
                        .disabled(!canContinue)
                }
            }
        }
    }

    private func finish() {
        SeedData.createBaby(
            name: babyName.trimmingCharacters(in: .whitespaces),
            dateOfBirth: dateOfBirth,
            ownerName: ownerName.trimmingCharacters(in: .whitespaces),
            ownerColorHex: ownerColorHex,
            in: context
        )
        Haptics.success()
    }
}

#Preview {
    OnboardingView()
        .modelContainer(AppModelContainer.make(inMemory: true))
}
