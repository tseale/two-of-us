import SwiftUI
import SwiftData

/// The two-tap sheet behind every schedule row. Pinned occurrence: tap the
/// other parent's face → tonight is swapped, done. Predicted occurrence: tap a
/// face → the prediction is pinned into the standing plan, assigned. Everything
/// else (skip, undo, edit, remove) is a row below the faces.
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

    private var store: EventStore { EventStore(context: context) }
    private var slot: PlanSlot? {
        occurrence.slotID.flatMap { PlanSlot.fetchByID($0, in: context) }
    }
    private var kindWord: String { occurrence.kind == .sleep ? "sleep" : "bottle" }
    private var accent: Color { occurrence.kind == .sleep ? AppColor.accentSleep : AppColor.accentFeed }
    private var clock: String { TimeFormatting.clock(occurrence.date) }

    var body: some View {
        NavigationStack {
            Form {
                Section(occurrence.isPinned ? whoSectionTitle : "Pin into the plan") {
                    HStack(spacing: 12) {
                        ForEach(participants) { p in
                            personButton(p)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                if occurrence.isPinned {
                    pinnedActions
                } else {
                    Section {
                        Button("Pin without assigning") { pin(to: nil) }
                    } footer: {
                        Text("Predicted from recent \(kindWord)s. Pinning makes it a standing \(clock) slot every day.")
                    }
                }
            }
            .navigationTitle("\(occurrence.kind.emoji) \(clock)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var whoSectionTitle: String {
        occurrence.status == .skipped ? "Skipped tonight — reassign?" : "Who takes tonight's \(kindWord)?"
    }

    private func personButton(_ p: Participant) -> some View {
        let current = occurrence.status != .skipped && occurrence.assignedToID == p.id
        return Button {
            occurrence.isPinned ? assignTonight(to: p) : pin(to: p)
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
    private var pinnedActions: some View {
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
            Text("Swaps and skips apply to tonight only — the standing plan stays put.")
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

    private func pin(to p: Participant?) {
        // Predictions land on odd minutes ("~2:47 AM"); a standing slot wants a
        // round one.
        let c = Calendar.current.dateComponents([.hour, .minute], from: occurrence.date)
        let minute = ((c.hour ?? 0) * 60 + (c.minute ?? 0) + 2) / 5 * 5
        let created = store.addPlanSlot(kind: occurrence.kind, minuteOfDay: minute, assignedTo: p)
        Haptics.success()
        let clock = TimeFormatting.clock(
            ScheduleEngine.materialize(minuteOfDay: created.minuteOfDay, on: occurrence.date,
                                       calendar: .current) ?? occurrence.date)
        let who = p.map { " · \($0.displayName)" } ?? ""
        onDone?("Pinned \(clock) \(kindWord)\(who)", accent) { store.removePlanSlot(created) }
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
}
