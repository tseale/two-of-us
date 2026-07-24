import SwiftUI

/// Editor for one feed-schedule slot: a recurring daily time window plus who
/// takes it. The caller owns persistence — Save hands the edited slot back via
/// `onSave` (an upsert), Remove calls `onDelete`.
struct FeedSlotEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    let isNew: Bool
    let participants: [Participant]
    let onSave: (FeedSlot) -> Void
    let onDelete: (() -> Void)?

    @State private var slot: FeedSlot

    init(slot: FeedSlot, isNew: Bool, participants: [Participant],
         onSave: @escaping (FeedSlot) -> Void, onDelete: (() -> Void)? = nil) {
        _slot = State(initialValue: slot)
        self.isNew = isNew
        self.participants = participants
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("From", selection: minutesBinding(\.startMinutes),
                               displayedComponents: .hourAndMinute)
                    DatePicker("To", selection: minutesBinding(\.endMinutes),
                               displayedComponents: .hourAndMinute)
                } footer: {
                    if slot.endMinutes <= slot.startMinutes {
                        Text("This window crosses midnight.")
                    }
                }

                Section {
                    Picker("Who's up", selection: $slot.assignedParticipantID) {
                        Text("Both").tag(UUID?.none)
                        ForEach(participants) { p in
                            Text(p.displayName.isEmpty ? "Parent" : p.displayName)
                                .tag(Optional(p.id))
                        }
                    }
                } footer: {
                    Text("Only the assigned parent's phone will alarm for a feed due in this window. “Both” alerts everyone.")
                }

                if !isNew, let onDelete {
                    Section {
                        Button("Remove slot", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New slot" : "Edit slot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(slot)
                        dismiss()
                    }
                    .disabled(slot.startMinutes == slot.endMinutes)   // zero-length slot covers nothing
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Bridges a minutes-from-midnight field to the `Date` a DatePicker needs.
    private func minutesBinding(_ keyPath: WritableKeyPath<FeedSlot, Int>) -> Binding<Date> {
        Binding(
            get: {
                let m = slot[keyPath: keyPath]
                return Calendar.current.date(bySettingHour: m / 60, minute: m % 60,
                                             second: 0, of: .now) ?? .now
            },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                slot[keyPath: keyPath] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }
}
