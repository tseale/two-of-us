import SwiftUI
import SwiftData

/// Log a diaper: wet / dirty / both. One tap logs (with optional backdating).
struct DiaperSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let onLogged: (String, @escaping () -> Void) -> Void

    @State private var date = Date()
    @State private var selected: DiaperType = .wet

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 10) {
                        ForEach(DiaperType.allCases) { type in
                            button(for: type)
                        }
                    }
                }
                Section("Time") {
                    TimeControl(date: $date, tint: AppColor.accentDiaper)
                }
            }
            .navigationTitle("Log a diaper 💩")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                // Select a type, then confirm — a selected highlight plus an
                // explicit label so a stray tap can't log the wrong thing
                // (parity with the Feed sheet's preset chips).
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log \(selected.label)") { log(selected) }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func button(for type: DiaperType) -> some View {
        let isSelected = selected == type
        return Button {
            selected = type
            Haptics.tap()
        } label: {
            VStack(spacing: 8) {
                Text(type.emoji).font(.title)
                Text(type.label).font(.system(.subheadline, design: .rounded).weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(isSelected ? AppColor.accentDiaper.opacity(0.25) : AppColor.card2,
                        in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(AppColor.accentDiaper, lineWidth: isSelected ? 2 : 0)
            )
            .foregroundStyle(AppColor.text)
        }
        .buttonStyle(PressableTileStyle())
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func log(_ type: DiaperType) {
        let store = EventStore(context: context)
        let event = store.logDiaper(type, at: date)
        Haptics.success()
        onLogged("Logged diaper · \(type.label)") {
            store.softDelete(event)
        }
        dismiss()
    }
}
