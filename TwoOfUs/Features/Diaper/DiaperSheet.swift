import SwiftUI
import SwiftData

/// Log a diaper: wet / dirty / both. One tap logs (with optional backdating).
struct DiaperSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var participants: [Participant]

    let onLogged: (String, @escaping () -> Void) -> Void

    @State private var date = Date()
    @State private var selected: DiaperType = .wet
    @State private var note = ""
    @State private var loggedByID: UUID?

    private var activeParticipants: [Participant] {
        participants.filter(\.isActive).sorted { $0.invitedAt < $1.invitedAt }
    }

    /// The picked participant, only when it's someone other than the local
    /// user — the owner default (nil) keeps the refusal-banner path intact
    /// when identity can't be resolved.
    private var assignedLogger: Participant? {
        guard let loggedByID, loggedByID != EventStore(context: context).owner?.id else { return nil }
        return activeParticipants.first { $0.id == loggedByID }
    }

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
                // Assign at log time — hidden with a single participant.
                // Same face row as the edit sheet and night-shift picker.
                if activeParticipants.count > 1 {
                    Section("Logged by") {
                        LoggedByPicker(participants: activeParticipants, selectedID: $loggedByID)
                    }
                }
                Section("Note") {
                    TextField("Add a note (optional)", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .onAppear {
                // Open on "me" — assigning to the co-parent is the exception.
                if loggedByID == nil {
                    loggedByID = EventStore(context: context).owner?.id
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
                        .accessibilityIdentifier("diaperSheet.confirm")
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
        // A refused log (no attributable owner) already surfaced a banner via
        // StoreErrorCenter — just close without a success toast.
        let assigned = assignedLogger
        guard let event = store.logDiaper(type, at: date, notes: note,
                                          loggedBy: assigned) else {
            dismiss()
            return
        }
        Haptics.success()
        let toast = assigned.map { "Logged diaper · \(type.label) · \($0.displayName)" }
            ?? "Logged diaper · \(type.label)"
        onLogged(toast) {
            store.softDelete(event)
        }
        dismiss()
    }
}
