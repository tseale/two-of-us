import SwiftUI
import SwiftData

/// The Schedule tab: who's up next, the next 24 hours of pinned and predicted
/// feeds/sleeps on a rail, and the standing plan editor. The whole point lives
/// in one glance — "Katie's got the 11pm, I'm the 3am" — so the hero card leads
/// with the assignee and every row carries their face.
struct ScheduleView: View {
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<PlanSlot> { $0.deletedAt == nil }, sort: \PlanSlot.minuteOfDay)
    private var slots: [PlanSlot]
    @Query(filter: #Predicate<PlanOverride> { $0.deletedAt == nil })
    private var overrides: [PlanOverride]
    @Query(filter: #Predicate<FeedEvent> { $0.deletedAt == nil }, sort: \FeedEvent.timestamp, order: .reverse)
    private var feeds: [FeedEvent]
    @Query(filter: #Predicate<SleepEvent> { $0.deletedAt == nil }, sort: \SleepEvent.startedAt, order: .reverse)
    private var sleeps: [SleepEvent]
    @Query private var participants: [Participant]
    @Query private var settingsList: [SharedSettings]

    @State private var actionTarget: ScheduleOccurrence?
    @State private var editingSlot: PlanSlot?
    @State private var addingSlot = false
    @State private var toast: ToastData?
    @State private var prefs = LocalPrefs.shared

    var body: some View {
        NavigationStack {
            // A minute tick keeps "in 2h 5m", the NOW divider, and overdue
            // states honest while the tab sits open overnight.
            TimelineView(.periodic(from: .now, by: 60)) { ctx in
                scheduleList(now: ctx.date)
            }
            .listStyle(.plain)
            .background(AppColor.bg)
            .navigationTitle("Schedule")
            .sheet(item: $actionTarget) { occ in
                SlotActionsSheet(occurrence: occ, onEditSlot: openEditor, onDone: showToast)
            }
            .sheet(item: $editingSlot) { slot in
                SlotEditSheet(slot: slot, onDone: showToast)
            }
            .sheet(isPresented: $addingSlot) {
                SlotEditSheet(onDone: showToast)
            }
            .loggedToast($toast)
        }
    }

    // MARK: List

    private func scheduleList(now: Date) -> some View {
        let occurrences = engine(now: now).occurrences()
        let upNext = occurrences.first { $0.status == .upcoming && $0.date >= now }
        return List {
            if occurrences.isEmpty {
                emptySection
            } else {
                if let upNext { heroSection(upNext, now: now) }
                timelineSection(occurrences, now: now)
            }
            planSection
        }
    }

    private func engine(now: Date) -> ScheduleEngine {
        ScheduleEngine(
            slots: slots, overrides: overrides, feeds: feeds, sleeps: sleeps,
            targetFeedInterval: TimeInterval((settingsList.first?.targetFeedIntervalMinutes ?? 180) * 60),
            now: now
        )
    }

    // MARK: Hero

    private func heroSection(_ occ: ScheduleOccurrence, now: Date) -> some View {
        let mine = isMine(occ)
        let tint = Color(hex: occ.assignedToColorHex.isEmpty ? "636366" : occ.assignedToColorHex)
        return Section {
            Button { actionTarget = occ } label: {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mine ? "You're up next" : "Up next")
                            .sectionLabelStyle(color: mine ? tint : AppColor.text2)
                        Text(TimeFormatting.clock(occ.date))
                            .font(AppFont.display(38))
                            .foregroundStyle(AppColor.text)
                        Text("\(occ.kind.emoji) \(occ.kind == .sleep ? "Sleep" : "Bottle") · in \(TimeFormatting.duration(from: now, to: occ.date))")
                            .font(.subheadline)
                            .foregroundStyle(AppColor.text2)
                    }
                    Spacer()
                    heroAssignee(occ, mine: mine)
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .glassCard()
                .overlay {
                    if mine {
                        RoundedRectangle(cornerRadius: 18).strokeBorder(tint, lineWidth: 2)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(heroAccessibilityLabel(occ, mine: mine, now: now))
            .accessibilityHint("Reassign or change this slot")
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
    }

    @ViewBuilder
    private func heroAssignee(_ occ: ScheduleOccurrence, mine: Bool) -> some View {
        if occ.assignedToID != nil {
            VStack(spacing: 4) {
                Avatar(photoData: occ.assignedToID.flatMap { participantPhoto[$0] },
                       name: occ.assignedToName, colorHex: occ.assignedToColorHex, size: 56)
                Text(mine ? "You" : occ.assignedToName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColor.text2)
                    .lineLimit(1)
            }
        } else {
            VStack(spacing: 4) {
                Circle()
                    .strokeBorder(AppColor.text3.opacity(0.6),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: "person.fill.questionmark")
                            .foregroundStyle(AppColor.text3)
                    }
                Text("Unassigned")
                    .font(.caption)
                    .foregroundStyle(AppColor.text3)
            }
        }
    }

    private func heroAccessibilityLabel(_ occ: ScheduleOccurrence, mine: Bool, now: Date) -> String {
        let kind = occ.kind == .sleep ? "sleep" : "bottle"
        let when = "\(TimeFormatting.clock(occ.date)), in \(TimeFormatting.duration(from: now, to: occ.date))"
        if mine { return "Up next: your \(kind), \(when)" }
        if occ.assignedToName.isEmpty { return "Up next: \(kind), \(when), unassigned" }
        return "Up next: \(kind), \(when), \(occ.assignedToName)'s turn"
    }

    // MARK: Timeline

    private func timelineSection(_ occurrences: [ScheduleOccurrence], now: Date) -> some View {
        let earlier = occurrences.filter { $0.date < now }
        let upcoming = occurrences.filter { $0.date >= now }
        return Section {
            ForEach(earlier) { row($0, now: now) }
            TimelineNowCap()
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            ForEach(upcoming) { row($0, now: now) }
        } header: {
            Text("Next 24 hours").foregroundStyle(AppColor.text3)
        }
    }

    private func row(_ occ: ScheduleOccurrence, now: Date) -> some View {
        ScheduleRow(
            occurrence: occ,
            caption: caption(for: occ),
            assigneePhoto: occ.assignedToID.flatMap { participantPhoto[$0] },
            isMine: isMine(occ),
            showsDay: !Calendar.current.isDate(occ.date, inSameDayAs: now)
        )
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .contentShape(Rectangle())
        .onTapGesture { actionTarget = occ }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(occ.isPinned ? "Reassign or change this slot" : "Pin this into the plan")
    }

    private func caption(for occ: ScheduleOccurrence) -> String? {
        switch occ.status {
        case .fulfilled(let eventID):
            let name = loggerName(of: eventID, kind: occ.kind)
            return name.isEmpty ? "Done ✓" : "Covered by \(name) ✓"
        case .overdue:
            return "Overdue"
        case .skipped:
            return "Skipped tonight"
        case .upcoming:
            guard occ.activeOverrideID != nil else { return nil }
            let name = participants.first { $0.id == occ.overrideCreatedByID }?.displayName ?? ""
            return name.isEmpty ? "Swapped for tonight" : "Swapped by \(name)"
        }
    }

    private func loggerName(of eventID: UUID, kind: EventKind) -> String {
        switch kind {
        case .feed: feeds.first { $0.id == eventID }?.loggedByName ?? ""
        case .sleep: sleeps.first { $0.id == eventID }?.loggedByName ?? ""
        case .diaper: ""
        }
    }

    // MARK: Empty state

    private var emptySection: some View {
        Section {
            EmptyStateView(
                emoji: "🌙",
                title: "No plan yet",
                message: "Predicted feeds show up here as you log. Pin the night bottles and split them up — so one of you can actually sleep."
            )
            .listRowBackground(Color.clear)
        }
        .listRowSeparator(.hidden)
    }

    // MARK: Standing plan

    private var planSection: some View {
        Section {
            ForEach(nightOrderedSlots) { slot in
                planRow(slot)
            }
            Button { addingSlot = true } label: {
                Label("Add a slot", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.accentFeed)
            }
            .accessibilityIdentifier("schedule.addSlot")
        } header: {
            Text("Standing plan").foregroundStyle(AppColor.text3)
        } footer: {
            if !nightOrderedSlots.isEmpty {
                Text("Repeats every day until changed. Tap a slot on the timeline to swap just one night.")
            }
        }
    }

    /// Slots in "night order" — pivoted at noon so 11pm sorts before 3am, the
    /// way parents think about a night shift.
    private var nightOrderedSlots: [PlanSlot] {
        slots.sorted { ($0.minuteOfDay + 720) % 1440 < ($1.minuteOfDay + 720) % 1440 }
    }

    private func planRow(_ slot: PlanSlot) -> some View {
        Button { editingSlot = slot } label: {
            HStack(spacing: 10) {
                Text(slot.kind.emoji).font(.callout)
                Text(slotClock(slot))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(AppColor.text)
                Spacer()
                if let assignedID = slot.assignedToID {
                    Avatar(photoData: participantPhoto[assignedID], name: slot.assignedToName,
                           colorHex: slot.assignedToColorHex, size: 20)
                    Text(slot.assignedToName)
                        .font(.caption)
                        .foregroundStyle(AppColor.text2)
                } else {
                    Text("Unassigned")
                        .font(.caption)
                        .foregroundStyle(AppColor.text3)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppColor.text3)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(slot.kind == .sleep ? "Sleep" : "Bottle") at \(slotClock(slot)), \(slot.assignedToName.isEmpty ? "unassigned" : slot.assignedToName)")
        .accessibilityHint("Edits this standing slot")
    }

    private func slotClock(_ slot: PlanSlot) -> String {
        guard let date = ScheduleEngine.materialize(minuteOfDay: slot.minuteOfDay, on: .now,
                                                    calendar: .current) else { return "" }
        return TimeFormatting.clock(date)
    }

    // MARK: Helpers

    private func isMine(_ occ: ScheduleOccurrence) -> Bool {
        occ.assignedToID != nil && occ.assignedToID == prefs.myParticipantID
    }

    /// Participant id → avatar photo; absent keys fall back to the monogram.
    private var participantPhoto: [UUID: Data] {
        Dictionary(uniqueKeysWithValues: participants.compactMap { p in
            p.photoData.map { (p.id, $0) }
        })
    }

    /// Sheet-chaining: let the actions sheet finish dismissing before the
    /// editor presents, or SwiftUI drops the second sheet.
    private func openEditor(_ slot: PlanSlot) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.45))
            editingSlot = slot
        }
    }

    private func showToast(_ message: String, undo: (() -> Void)?) {
        toast = ToastData(message: message, accent: AppColor.accentFeed, undo: undo)
    }
}

#Preview {
    ScheduleView()
        .modelContainer(AppModelContainer.preview)
}
