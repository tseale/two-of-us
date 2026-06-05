import SwiftUI
import SwiftData

/// Log a diaper: wet / dirty / both. One tap logs (with optional backdating).
struct DiaperSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let onLogged: (String, @escaping () -> Void) -> Void

    @State private var date = Date()

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
                    TimeControl(date: $date)
                }
            }
            .navigationTitle("Log a diaper 💩")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func button(for type: DiaperType) -> some View {
        Button {
            log(type)
        } label: {
            VStack(spacing: 8) {
                Text(type.emoji).font(.title)
                Text(type.label).font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(AppColor.card2, in: RoundedRectangle(cornerRadius: 16))
            .foregroundStyle(AppColor.text)
        }
        .buttonStyle(.plain)
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
