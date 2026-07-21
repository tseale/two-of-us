import SwiftUI
import SwiftData

/// Create or edit a standing plan slot: a wall-clock time, a kind, and who's on
/// duty. House sheet idiom (Form, medium/large detents, Cancel/confirm toolbar,
/// undo toast via callback).
struct SlotEditSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Participant> { $0.isActive }, sort: \Participant.invitedAt)
    private var participants: [Participant]

    /// Nil creates a new slot.
    var slot: PlanSlot? = nil
    /// Seeds for create mode (pinning a prediction pre-fills its time).
    var initialKind: EventKind = .feed
    var initialMinute: Int = 22 * 60
    /// Reports the change back to the host for the toast (message, kind accent,
    /// undo).
    var onDone: ((String, Color, (() -> Void)?) -> Void)? = nil

    @State private var time: Date = .now
    @State private var kind: EventKind = .feed
    @State private var assignedToID: UUID?
    @State private var seeded = false

    private var editing: Bool { slot != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Time") {
                    DatePicker("Every day at", selection: $time, displayedComponents: .hourAndMinute)
                }

                Section("What") {
                    Picker("Kind", selection: $kind) {
                        Text("🍼 Bottle").tag(EventKind.feed)
                        Text("💤 Sleep").tag(EventKind.sleep)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Who's on duty") {
                    HStack(spacing: 12) {
                        ForEach(participants) { p in
                            personChip(p)
                        }
                        nobodyChip
                    }
                    .frame(maxWidth: .infinity)
                }

                if let slot {
                    Section {
                        Button("Remove from plan", role: .destructive) { remove(slot) }
                    }
                }
            }
            .navigationTitle(editing ? "Edit slot" : "Add to plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing ? "Save" : "Add") { saveAndDismiss() }
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
        let minute = slot?.minuteOfDay ?? initialMinute
        kind = slot?.kind ?? initialKind
        assignedToID = slot?.assignedToID
        time = ScheduleEngine.materialize(minuteOfDay: minute, on: .now, calendar: .current) ?? .now
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

    private var nobodyChip: some View {
        let selected = assignedToID == nil
        return Button {
            assignedToID = nil
            Haptics.tap()
        } label: {
            VStack(spacing: 6) {
                Circle()
                    .strokeBorder(selected ? AppColor.text2 : AppColor.text3.opacity(0.5),
                                  style: StrokeStyle(lineWidth: selected ? 3 : 1, dash: [4, 4]))
                    .frame(width: 52, height: 52)
                    .overlay {
                        Image(systemName: "person.slash")
                            .font(.callout)
                            .foregroundStyle(AppColor.text3)
                    }
                Text("No one")
                    .font(.caption.weight(selected ? .bold : .regular))
                    .foregroundStyle(AppColor.text2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var minuteOfDay: Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private var accent: Color { kind == .sleep ? AppColor.accentSleep : AppColor.accentFeed }

    private func saveAndDismiss() {
        let store = EventStore(context: context)
        let assignee = participants.first { $0.id == assignedToID }
        let clock = TimeFormatting.clock(time)
        if let slot {
            store.updatePlanSlot(slot, kind: kind, minuteOfDay: minuteOfDay, assignedTo: .some(assignee))
            onDone?("Updated \(clock) \(kind == .sleep ? "sleep" : "bottle")", accent, nil)
        } else {
            let created = store.addPlanSlot(kind: kind, minuteOfDay: minuteOfDay, assignedTo: assignee)
            onDone?("Added \(clock) \(kind == .sleep ? "sleep" : "bottle") to the plan", accent) {
                store.removePlanSlot(created)
            }
        }
        Haptics.success()
        dismiss()
    }

    private func remove(_ slot: PlanSlot) {
        let store = EventStore(context: context)
        store.removePlanSlot(slot)
        onDone?("Removed from the plan", accent) { store.restorePlanSlot(slot) }
        Haptics.warning()
        dismiss()
    }
}
