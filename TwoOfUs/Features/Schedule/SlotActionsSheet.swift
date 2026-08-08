import SwiftUI
import SwiftData

/// The two-tap sheet behind every schedule row. Tap the other parent's face →
/// tonight is swapped, done. Below the faces: move tonight to a different
/// time, skip it, undo tonight's change, or step into the standing-slot
/// editor — every occurrence is editable, any night, any time.
///
/// Works for both sources: a standing (sleep) slot gets the full set, a
/// dynamic night feed (`source == .night`, backed by no PlanSlot) gets
/// swap/skip/undo only — its time is derived from the night's anchor, so
/// there's nothing to move or edit.
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
    private var isNight: Bool { occurrence.source == .night }
    /// The night's FIRST slot — the anchor. Moving it re-times the whole
    /// night, so it's the one dynamic row that offers "Move tonight…".
    private var isNightAnchor: Bool {
        isNight && occurrence.slotID == NightSchedule.syntheticSlotID(
            nightKey: occurrence.dayKey, index: 0)
    }
    private var slot: PlanSlot? {
        isNight ? nil : PlanSlot.fetchByID(occurrence.slotID, in: context)
    }
    private var kindWord: String { occurrence.kind == .sleep ? "sleep" : "bottle" }
    /// A span row — a parent's sleep window, not a baby-care instant.
    private var isWindow: Bool { occurrence.endDate != nil }
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
        if occurrence.status == .skipped { return "Skipped tonight — reassign?" }
        return isWindow ? "Who takes this sleep tonight?" : "Who takes tonight's \(kindWord)?"
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
        if occurrence.status != .skipped, !isNight || isNightAnchor {
            Section {
                Button {
                    withAnimation { showMovePicker.toggle() }
                } label: {
                    HStack {
                        Text(isNightAnchor ? "Set tonight's first feed…" : "Move tonight…")
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
                    Text(isNightAnchor
                         ? "Re-times the whole night: the rest of tonight's feeds follow from here, and this time wins even over a logged bottle. Undo to go back to the computed schedule."
                         : "Moves tonight only — the standing \(kindWord) keeps its usual time tomorrow.")
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
                Button(isWindow ? "Edit sleep window…" : "Edit standing slot…") {
                    dismiss()
                    onEditSlot?(slot)
                }
                Button("Remove from plan", role: .destructive) { removeSlot(slot) }
            }
        } footer: {
            Text(isNight
                 ? "Swaps and skips apply to tonight only — tomorrow night rebuilds from the schedule settings."
                 : "Swaps, moves, and skips apply to tonight only — the standing plan stays put.")
        }
    }

    // MARK: Actions

    private func assignTonight(to p: Participant) {
        // Tapping the parent already on duty just confirms — nothing to write.
        guard occurrence.status == .skipped || occurrence.assignedToID != p.id else {
            dismiss()
            return
        }
        let override: PlanOverride
        if isNight {
            override = store.overrideNightOccurrence(occurrence, assignTo: p)
        } else if let slot {
            override = store.overrideSlot(slot, dayKey: occurrence.dayKey, assignTo: p)
        } else {
            return
        }
        Haptics.success()
        onDone?(isWindow
                ? "\(p.displayName) takes the \(clock) sleep tonight"
                : "Tonight's \(clock) \(kindWord) is \(p.displayName)'s",
                accent) { store.clearOverride(override) }
        dismiss()
    }

    private func moveTonight() {
        // Preserve tonight's effective assignee — a move must never drop a swap.
        let assignee = participants.first { $0.id == occurrence.assignedToID }
        let override: PlanOverride
        if isNightAnchor {
            override = store.moveNightAnchor(occurrence, toMinuteOfDay: minuteOfDay(moveTime),
                                             assignedTo: assignee)
        } else if let slot {
            override = store.moveSlot(slot, dayKey: occurrence.dayKey,
                                      toMinuteOfDay: minuteOfDay(moveTime), assignedTo: assignee)
        } else {
            return
        }
        Haptics.success()
        onDone?(isNightAnchor
                ? "Tonight's first \(kindWord) set to \(TimeFormatting.clock(moveTime))"
                : "Moved tonight's \(kindWord) to \(TimeFormatting.clock(moveTime))", accent) {
            store.clearOverride(override)
        }
        dismiss()
    }

    private func skipTonight() {
        let override: PlanOverride
        if isNight {
            override = store.skipNightOccurrence(occurrence)
        } else if let slot {
            override = store.skipSlot(slot, dayKey: occurrence.dayKey)
        } else {
            return
        }
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
