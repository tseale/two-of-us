import SwiftUI
import SwiftData

/// The Nighttime Schedule tab: who's up next, the night's plan on a rail, and
/// the standing plan editor. Feed slots are generated from the shared settings
/// (night window + spacing, alternating parents by default) via
/// `NightScheduleSettingsSheet`; every row stays parent-editable — swap, move,
/// or skip any night; reassign or remove any slot. The whole point lives in
/// one glance — "Katie's got the 11pm, I'm the 3am" — so the hero card leads
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
    @State private var configuringNight = false
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
            .navigationTitle("Nighttime Schedule")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        configuringNight = true
                    } label: {
                        Label("Nighttime settings", systemImage: "moon.stars")
                    }
                    .accessibilityIdentifier("schedule.nightSettings")
                }
            }
            .sheet(isPresented: $configuringNight) {
                NightScheduleSettingsSheet(onDone: showToast)
            }
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
        let occurrences = mergedOccurrences(now: now)
        // The hero is the next FEED — a sleep window isn't a "you're up next"
        // (it's the opposite: someone lying down).
        let upNext = occurrences.first {
            $0.kind == .feed && $0.status == .upcoming && $0.date >= now
        }
        return List {
            if occurrences.isEmpty {
                emptySection(now: now)
            } else {
                if let upNext { heroSection(upNext, now: now) }
                timelineSection(occurrences, now: now)
            }
            planSection
        }
    }

    /// Standing slots minus feed ones: night feeds are dynamic now, so a
    /// leftover fixed-era feed slot (or one synced from an older build) must
    /// not render next to the constructed schedule.
    private var sleepSlots: [PlanSlot] {
        slots.filter { $0.kind != .feed }
    }

    /// The standing (sleep) plan merged with the night's dynamically
    /// constructed feed schedule — anchored to the night's first (logged or
    /// projected) bottle, per-night overrides applied.
    private func mergedOccurrences(now: Date) -> [ScheduleOccurrence] {
        var merged = engine(now: now).occurrences()
        if let s = settingsList.first {
            merged += NightSchedule(settings: s, participants: participants,
                                    feeds: feeds, overrides: overrides,
                                    sleepSlots: sleepSlots, now: now).occurrences()
        }
        return merged.sorted { $0.date < $1.date }
    }

    private func engine(now: Date) -> ScheduleEngine {
        ScheduleEngine(slots: sleepSlots, overrides: overrides, feeds: feeds, sleeps: sleeps, now: now)
    }

    // MARK: Hero

    private func heroSection(_ occ: ScheduleOccurrence, now: Date) -> some View {
        let mine = isMine(occ)
        let tint = Color(hex: occ.assignedToColorHex.isEmpty ? "636366" : occ.assignedToColorHex)
        return Section {
            Button { open(occ) } label: {
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
        .onTapGesture { open(occ) }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(occ.source == .night
            ? "Reassign or skip tonight's feed" : "Reassign, move, or change this slot")
    }

    /// Both sources open the per-night actions sheet — a dynamic night row
    /// offers swap/skip (its time is derived, so no move/edit).
    private func open(_ occ: ScheduleOccurrence) {
        actionTarget = occ
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
            if occ.activeOverrideID != nil {
                let name = participants.first { $0.id == occ.overrideCreatedByID }?.displayName ?? ""
                return name.isEmpty ? "Changed for tonight" : "Changed by \(name)"
            }
            // A window row carries its span — the start clock sits in the
            // gutter, so the line under the title says where it runs to.
            if let end = occ.endDate {
                return "Until \(TimeFormatting.clock(end)) · \(TimeFormatting.duration(from: occ.date, to: end))"
            }
            return nil
        }
    }

    private func loggerName(of eventID: UUID, kind: EventKind) -> String {
        switch kind {
        case .feed: feeds.first { $0.id == eventID }?.loggedByName ?? ""
        // Sleep carries no logger attribution in the UI — a fulfilled sleep
        // slot reads "Done ✓", not "Covered by …".
        case .sleep: ""
        case .diaper: ""
        }
    }

    // MARK: Empty state

    private func emptySection(now: Date) -> some View {
        return Section {
            EmptyStateView(
                emoji: "🌙",
                title: "No nighttime schedule yet",
                message: "Tonight builds itself: the first bottle in (or just before) your night window starts the schedule — projected from your feeding rhythm, or the window's start until there's one to project from. Tune the window, spacing, and rotation with the moon up top."
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
                Label("Add a sleep window", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.accentSleep)
            }
            .accessibilityIdentifier("schedule.addSlot")
        } header: {
            Text("Your sleep, planned").foregroundStyle(AppColor.text3)
        } footer: {
            Text("\(balanceSummary)\(nightSummary)Set when each of you sleeps — a feed that lands during someone's window goes to the other parent, and the sleeping phone stays quiet. If you're both asleep, it goes to whoever's wake-up comes soonest. Feeds build themselves each night from the first logged bottle. Windows repeat every night until changed; tap one on the timeline to change just one night.")
        }
    }

    /// "Planned sleep: Taylor 7h · Katie 6h 30m · " — whether the night's
    /// balanced, read straight off the standing windows.
    private var balanceSummary: String {
        let windows = sleepSlots.compactMap(SleepWindow.init)
        guard !windows.isEmpty else { return "" }
        let totals = Dictionary(grouping: windows, by: \.parentID)
            .mapValues { $0.reduce(0) { $0 + $1.durationMinutes } }
        let parts = participants
            .filter { totals[$0.id] != nil }
            .sorted { ($0.invitedAt, $0.id.uuidString) < ($1.invitedAt, $1.id.uuidString) }
            .map { "\($0.displayName) \(TimeFormatting.duration(minutes: totals[$0.id] ?? 0))" }
        guard !parts.isEmpty else { return "" }
        return "Planned sleep: \(parts.joined(separator: " · ")) · "
    }

    /// "Every 3h · Night 8:00 PM–8:00 AM · " — the settings tonight's feeds
    /// construct themselves from, mirrored where the parents read the plan.
    private var nightSummary: String {
        guard let s = settingsList.first else { return "" }
        let spacing = NightScheduleSettingsSheet.spacingLabel(s.nightFeedSpacingMinutes)
        let start = NightScheduleSettingsSheet.clock(minuteOfDay: s.nightStartMinute)
        let end = NightScheduleSettingsSheet.clock(minuteOfDay: s.nightEndMinute)
        return "Every \(spacing) · Night \(start)–\(end) · "
    }

    /// Slots in "night order" — pivoted at noon so 11pm sorts before 3am, the
    /// way parents think about a night shift.
    private var nightOrderedSlots: [PlanSlot] {
        sleepSlots.sorted { ($0.minuteOfDay + 720) % 1440 < ($1.minuteOfDay + 720) % 1440 }
    }

    private func planRow(_ slot: PlanSlot) -> some View {
        Button { editingSlot = slot } label: {
            HStack(spacing: 10) {
                Text(slot.kind.emoji).font(.callout)
                Text(slotRange(slot))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(AppColor.text)
                if let duration = slot.windowDurationMinutes {
                    Text(TimeFormatting.duration(minutes: duration))
                        .font(.caption)
                        .foregroundStyle(AppColor.text3)
                }
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
        .accessibilityLabel("\(slot.assignedToName.isEmpty ? "Sleep" : "\(slot.assignedToName) sleeps") \(slotRange(slot))")
        .accessibilityHint("Edits this sleep window")
    }

    /// "10:00 PM–5:00 AM" for a window; the bare start clock for a legacy
    /// instant slot.
    private func slotRange(_ slot: PlanSlot) -> String {
        let start = slotClock(minuteOfDay: slot.minuteOfDay)
        guard let end = slot.endMinuteOfDay, slot.windowDurationMinutes != nil else { return start }
        return "\(start)–\(slotClock(minuteOfDay: end))"
    }

    private func slotClock(minuteOfDay minute: Int) -> String {
        guard let date = ScheduleEngine.materialize(minuteOfDay: minute, on: .now,
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

    private func showToast(_ message: String, accent: Color, undo: (() -> Void)?) {
        toast = ToastData(message: message, accent: accent, undo: undo)
    }
}

#Preview {
    ScheduleView()
        .modelContainer(AppModelContainer.preview)
}
