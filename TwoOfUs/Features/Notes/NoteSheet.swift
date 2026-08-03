import SwiftUI
import SwiftData

/// Compose a standalone timestamped note for the timeline.
struct NoteSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// Reports the logged note back to the host for the "Note added · Undo" toast.
    let onLogged: (String, @escaping () -> Void) -> Void

    @State private var text = ""
    @State private var date = Date()
    @FocusState private var focused: Bool

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What happened?", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($focused)
                } header: {
                    Text("Note")
                } footer: {
                    // The counter only surfaces near the cap — routine notes
                    // shouldn't read like they're being metered.
                    if text.count > EventBounds.noteEventMaxLength - 100 {
                        Text("\(text.count)/\(EventBounds.noteEventMaxLength)")
                            .foregroundStyle(text.count > EventBounds.noteEventMaxLength
                                             ? AppColor.urgencyAmberText : AppColor.text3)
                    }
                }

                Section("Time") {
                    TimeControl(date: $date, tint: AppColor.accentNote)
                }
            }
            .navigationTitle("New note 📝")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save note") { log() }
                        .disabled(!canSave)
                        .accessibilityIdentifier("noteSheet.confirm")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { focused = true }
    }

    private func log() {
        let store = EventStore(context: context)
        guard let event = store.logNote(text, at: date) else { return }
        Haptics.success()
        onLogged("Note added") { store.softDelete(event) }
        dismiss()
    }
}

#Preview {
    NoteSheet(onLogged: { _, _ in })
        .modelContainer(AppModelContainer.preview)
}
