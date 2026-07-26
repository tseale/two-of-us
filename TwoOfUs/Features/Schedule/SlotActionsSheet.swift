import SwiftUI
import SwiftData

/// The two-tap sheet behind every schedule row. Tap the other parent's face →
/// tonight is swapped, done. Below the faces: move tonight to a different
/// time, skip it, undo tonight's change, or step into the standing-slot
/// editor — every occurrence is editable, any night, any time.
struct SlotActionsSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Participant> { $0.isActive }, sort: \Participant.invitedAt)
    private var participants: [Participant]

    let occurrence: ScheduleOccurrence
    /// Host opens the standing-slot editor after this sheet dismisses.
    var onEditSlot: ((PlanSlot) -> Void)? = nil
    /// Reports the change back to the host for the toast (message, kind accent,
    /// undo) — the accent keeps a sleep-slot Undo periwinkle, not feed teal.
    var onDone: ((String, Color, (() -> Void)?) -> Void)? = nil

    @State private var showMovePicker = false
    @State private var moveTime: Date = .now

    private var store: EventStore { EventStore(context: context) }
    private var slot: PlanSlot? {
        PlanSlot.fetchByID(occurrence.slotID, in: context)
    }
    private var kindWord: String { occurrence.kind == .sleep ? "sleep" : "bottle" }
    private var accent: Color { occurrence.kind == .sleep ? AppColor.accentSleep : AppColor.accentFeed }
    private var clock: String { TimeFormatting.clock(occurrence.date) }

    var body: some View {
        NavigationStack {
            Form {
                Section(whoSectionTitle) {
                    HStack(spacing: 12) {
                        ForEach(participants) { p in
                            personButton(p)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                actions
            }
            .navigationTitle("\(occurrence.kind.emoji) \(clock)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { moveTime = occurrence.date }
    }

    private var whoSectionTitle: String {
        occurrence.status == .skipped ? "Skipped tonight — reassign?" : "Who takes tonight's \(kindWord)?"
    }

    private func personButton(_ p: Participant) -> some View {
        let current = occurrence.status != .skipped && occurrence.assignedToID == p.id
        return Button {
            assignTonight(to: p)
        } label: {
            VStack(spacing: 6) {
                Avatar(photoData: p.photoData, name: p.displayName, colorHex: p.colorHex, size: 56)
                    .overlay {
                        if current {
                            Circle().strokeBorder(Color(hex: p.colorHex), lineWidth: 3)
                                .frame(width: 64, height: 64)
                        }
                    }
                Text(current ? "\(p.displayName) · on duty" : p.displayName)
                    .font(.caption.weight(current ? .bold : .regular))
                    .foregroundStyle(AppColor.text)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(current
            ? "\(p.displayName), on duty"
            : "Assign to \(p.displayName)")
    }

    @ViewBuilder
    private var actions: some View {
        if occurrence.status != .skipped {
            Section {
                Button {
                    withAnimation { showMovePicker.toggle() }
                } label: {
                    HStack {
                        Text("Move tonight…")
                        Spacer()
                        Image(systemName: showMovePicker ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppColor.text3)
                    }
                }
                if showMovePicker {
                    DatePicker("Tonight at", selection: $moveTime, displayedComponents: .hourAndMinute)
                    if minuteOfDay(moveTime) != minuteOfDay(occurrence.date) {
                        Button("Move to \(TimeFormatting.clock(moveTime))") { moveTonight() }
                            .font(.body.weight(.semibold))
                            .foregroundStyle(accent)
                    }
                }
            } footer: {
                if showMovePicker {
                    Text("Moves tonight only — the standing \(kindWord) keeps its usual time tomorrow.")
                }
            }
        }

        Section {
            if occurrence.activeOverrideID != nil {
                Button("Undo tonight's change") { undoOverride() }
            }
            if occurrence.status != .skipped {
                Button("Skip tonight") { skipTonight() }
            }
            if let slot {
                Button("Edit standing slot…") {
                    dismiss()
                    onEditSlot?(slot)
                }
                Button("Remove from plan", role: .destructive) { removeSlot(slot) }
            }
        } footer: {
            Text("Swaps, moves, and skips apply to tonight only — the standing plan stays put.")
        }
    }

    // MARK: Actions

    private func assignTonight(to p: Participant) {
        guard let slot else { return }
        // Tapping the parent already on duty just confirms — nothing to write.
        guard occurrence.status == .skipped || occurrence.assignedToID != p.id else {
            dismiss()
            return
        }
        let override = store.overrideSlot(slot, dayKey: occurrence.dayKey, assignTo: p)
        Haptics.success()
        onDone?("Tonight's \(clock) \(kindWord) is \(p.displayName)'s", accent) { store.clearOverride(override) }
        dismiss()
    }

    private func moveTonight() {
        guard let slot else { return }
        // Preserve tonight's effective assignee — a move must never drop a swap.
        let assignee = participants.first { $0.id == occurrence.assignedToID }
        let override = store.moveSlot(slot, dayKey: occurrence.dayKey,
                                      toMinuteOfDay: minuteOfDay(moveTime), assignedTo: assignee)
        Haptics.success()
        onDone?("Moved tonight's \(kindWord) to \(TimeFormatting.clock(moveTime))", accent) {
            store.clearOverride(override)
        }
        dismiss()
    }

    private func skipTonight() {
        guard let slot else { return }
        let override = store.skipSlot(slot, dayKey: occurrence.dayKey)
        Haptics.warning()
        onDone?("Skipped tonight's \(clock) \(kindWord)", accent) { store.clearOverride(override) }
        dismiss()
    }

    private func undoOverride() {
        guard let id = occurrence.activeOverrideID,
              let override = PlanOverride.fetchByID(id, in: context) else { return }
        store.clearOverride(override)
        Haptics.tap()
        onDone?("Back to the standing plan", accent, nil)
        dismiss()
    }

    private func removeSlot(_ slot: PlanSlot) {
        store.removePlanSlot(slot)
        Haptics.warning()
        onDone?("Removed \(clock) \(kindWord) from the plan", accent) { store.restorePlanSlot(slot) }
        dismiss()
    }

    private func minuteOfDay(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}
