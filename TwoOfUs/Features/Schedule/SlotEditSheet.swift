import SwiftUI
import SwiftData

/// Create or edit a standing SLEEP WINDOW: when one of the parents sleeps,
/// every night until changed. The window is whose sleep it is (required — an
/// unowned window can't route anything) plus a falls-asleep and wakes time;
/// feeds that land inside it are assigned to the other parent
/// (`NightSchedule.onDutyParent`). House sheet idiom (Form, medium/large
/// detents, Cancel/confirm toolbar, undo toast via callback).
struct SlotEditSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Participant> { $0.isActive && $0.pausedAt == nil }, sort: \Participant.invitedAt)
    private var participants: [Participant]

    /// Nil creates a new window.
    var slot: PlanSlot? = nil
    /// Seed start for create mode.
    var initialMinute: Int = 22 * 60
    /// Reports the change back to the host for the toast (message, kind accent,
    /// undo).
    var onDone: ((String, Color, (() -> Void)?) -> Void)? = nil

    @State private var start: Date = .now
    @State private var end: Date = .now
    @State private var assignedToID: UUID?
    @State private var seeded = false

    private var editing: Bool { slot != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        ForEach(participants) { p in
                            personChip(p)
                        }
                    }
                    .frame(maxWidth: .infinity)
                } header: {
                    Text("Who's sleeping")
                } footer: {
                    Text("Feeds during this window go to the other parent — this phone stays quiet.")
                }

                Section("Every night") {
                    DatePicker("Falls asleep", selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker("Wakes", selection: $end, displayedComponents: .hourAndMinute)
                }

                if let slot {
                    Section {
                        Button("Remove from plan", role: .destructive) { remove(slot) }
                    }
                }
            }
            .navigationTitle(editing ? "Edit sleep window" : "Add sleep window")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing ? "Save" : "Add") { saveAndDismiss() }
                        .disabled(assignedToID == nil || startMinute == endMinute)
                        .accessibilityIdentifier("slotEditSheet.confirm")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear(perform: seed)
    }

    private func seed() {
        guard !seeded else { return }
        seeded = true
        let startSeed = slot?.minuteOfDay ?? initialMinute
        // Default a fresh window to start + 7h — a real night's sleep to edit
        // from, not a zero-length one the confirm button refuses.
        let endSeed = slot?.endMinuteOfDay ?? (startSeed + 7 * 60) % 1440
        assignedToID = slot?.assignedToID ?? LocalPrefs.shared.myParticipantID
        start = ScheduleEngine.materialize(minuteOfDay: startSeed, on: .now, calendar: .current) ?? .now
        end = ScheduleEngine.materialize(minuteOfDay: endSeed, on: .now, calendar: .current) ?? .now
    }

    private func personChip(_ p: Participant) -> some View {
        let selected = assignedToID == p.id
        return Button {
            assignedToID = p.id
            Haptics.tap()
        } label: {
            VStack(spacing: 6) {
                Avatar(photoData: p.photoData, name: p.displayName, colorHex: p.colorHex, size: 52)
                    .overlay {
                        if selected {
                            Circle().strokeBorder(Color(hex: p.colorHex), lineWidth: 3)
                                .frame(width: 60, height: 60)
                        }
                    }
                Text(p.displayName)
                    .font(.caption.weight(selected ? .bold : .regular))
                    .foregroundStyle(AppColor.text)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var startMinute: Int {
        minuteOfDay(start)
    }

    private var endMinute: Int {
        minuteOfDay(end)
    }

    private func minuteOfDay(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private var rangeLabel: String {
        "\(TimeFormatting.clock(start))–\(TimeFormatting.clock(end))"
    }

    private func saveAndDismiss() {
        let store = EventStore(context: context)
        guard let assignee = participants.first(where: { $0.id == assignedToID }) else { return }
        if let slot {
            store.updatePlanSlot(slot, kind: .sleep, minuteOfDay: startMinute,
                                 endMinuteOfDay: .some(endMinute), assignedTo: .some(assignee))
            onDone?("Updated \(assignee.displayName)'s \(rangeLabel) sleep", AppColor.accentSleep, nil)
        } else {
            let created = store.addPlanSlot(kind: .sleep, minuteOfDay: startMinute,
                                            endMinuteOfDay: endMinute, assignedTo: assignee)
            onDone?("\(assignee.displayName) sleeps \(rangeLabel) — added to the plan",
                    AppColor.accentSleep) {
                store.removePlanSlot(created)
            }
        }
        Haptics.success()
        dismiss()
    }

    private func remove(_ slot: PlanSlot) {
        let store = EventStore(context: context)
        store.removePlanSlot(slot)
        onDone?("Removed from the plan", AppColor.accentSleep) { store.restorePlanSlot(slot) }
        Haptics.warning()
        dismiss()
    }
}
