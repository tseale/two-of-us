import SwiftUI
import SwiftData

/// Configure the shared nighttime schedule: the night window, the spacing
/// between feeds, and where the first bottle lands. Saving regenerates the
/// standing feed slots (alternating between the parents by default) and syncs
/// the settings so both phones see the same night. House sheet idiom (Form,
/// detents, Cancel/confirm toolbar, undo-less toast via callback).
struct NightScheduleSettingsSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [SharedSettings]
    @Query(filter: #Predicate<Participant> { $0.isActive }, sort: \Participant.invitedAt)
    private var participants: [Participant]
    @Query(filter: #Predicate<PlanSlot> { $0.deletedAt == nil })
    private var liveSlots: [PlanSlot]
    @Query(filter: #Predicate<FeedEvent> { $0.deletedAt == nil }, sort: \FeedEvent.timestamp, order: .reverse)
    private var recentFeeds: [FeedEvent]

    var onDone: ((String, Color, (() -> Void)?) -> Void)? = nil

    @State private var nightStart: Date = .now
    @State private var nightEnd: Date = .now
    @State private var firstFeed: Date = .now
    @State private var spacingMinutes = 180
    @State private var seeded = false
    /// True when `firstFeed` was seeded from feed history rather than the
    /// previously saved setting — drives the "predicted" footer.
    @State private var firstFeedIsPredicted = false

    /// Half-hour steps from 2h to 6h — the realistic newborn range.
    private static let spacingChoices = Array(stride(from: 120, through: 360, by: 30))

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Night starts at", selection: $nightStart, displayedComponents: .hourAndMinute)
                    DatePicker("Night ends at", selection: $nightEnd, displayedComponents: .hourAndMinute)
                } header: {
                    Text("Nighttime hours")
                } footer: {
                    Text("The schedule only covers this window — daytime feeds stay ad-hoc.")
                }

                Section("Feed spacing") {
                    Picker("Hours between feeds", selection: $spacingMinutes) {
                        ForEach(Self.spacingChoices, id: \.self) { minutes in
                            Text(Self.spacingLabel(minutes)).tag(minutes)
                        }
                    }
                }

                Section {
                    DatePicker("First feed at", selection: $firstFeed, displayedComponents: .hourAndMinute)
                } footer: {
                    if !firstFeedValid {
                        Text("The first feed must fall inside the nighttime window.")
                            .foregroundStyle(AppColor.urgencyAmber)
                    } else if firstFeedIsPredicted {
                        Text("Predicted from recent feeds — adjust if needed.")
                    }
                }

                previewSection
            }
            .navigationTitle("Nighttime Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveAndDismiss() }
                        .disabled(!firstFeedValid || previewMinutes.isEmpty)
                        .accessibilityIdentifier("nightSchedule.confirm")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear(perform: seed)
    }

    // MARK: Preview

    private var previewSection: some View {
        Section {
            ForEach(Array(previewMinutes.enumerated()), id: \.offset) { index, minute in
                HStack(spacing: 10) {
                    Text("🍼").font(.callout)
                    Text(Self.clock(minuteOfDay: minute))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(AppColor.text)
                    Spacer()
                    Text(previewAssigneeName(index: index, minute: minute))
                        .font(.caption)
                        .foregroundStyle(AppColor.text2)
                }
            }
        } header: {
            Text("Tonight's feeds")
        } footer: {
            Text(previewMinutes.isEmpty
                 ? "These hours generate no feeds — widen the window or tighten the spacing."
                 : "Feeds alternate between you by default. Tap any slot on the schedule to reassign it — an unassigned slot rings both phones, an assigned one only its owner's.")
        }
    }

    /// A kept time previews its existing (possibly hand-picked) assignee; a
    /// new time previews the default rotation — exactly what Save will apply.
    private func previewAssigneeName(index: Int, minute: Int) -> String {
        if let existing = liveSlots.first(where: { $0.kind == .feed && $0.minuteOfDay == minute }) {
            return existing.assignedToID == nil ? "Unassigned" : existing.assignedToName
        }
        guard let assignee = NightScheduleGenerator.alternatingAssignee(index: index, parents: participants)
        else { return "Unassigned" }
        return assignee.displayName
    }

    private var previewMinutes: [Int] {
        NightScheduleGenerator.feedMinutes(
            nightStartMinute: minuteOfDay(nightStart),
            nightEndMinute: minuteOfDay(nightEnd),
            firstFeedMinute: minuteOfDay(firstFeed),
            spacingMinutes: spacingMinutes
        )
    }

    private var firstFeedValid: Bool {
        NightScheduleGenerator.isWithinNight(
            minuteOfDay: minuteOfDay(firstFeed),
            nightStartMinute: minuteOfDay(nightStart),
            nightEndMinute: minuteOfDay(nightEnd)
        )
    }

    // MARK: Actions

    private func seed() {
        guard !seeded, let settings = settingsList.first else { return }
        seeded = true
        nightStart = Self.date(minuteOfDay: settings.nightStartMinute)
        nightEnd = Self.date(minuteOfDay: settings.nightEndMinute)
        spacingMinutes = settings.nightFeedSpacingMinutes
        if let predicted = NightScheduleGenerator.predictedNextFeed(
            recentFeedTimestamps: recentFeeds.map(\.timestamp)
        ) {
            firstFeed = predicted
            firstFeedIsPredicted = true
        } else {
            firstFeed = Self.date(minuteOfDay: settings.nightFirstFeedMinute)
        }
    }

    private func saveAndDismiss() {
        EventStore(context: context).applyNightSchedule(
            nightStartMinute: minuteOfDay(nightStart),
            nightEndMinute: minuteOfDay(nightEnd),
            firstFeedMinute: minuteOfDay(firstFeed),
            spacingMinutes: spacingMinutes
        )
        onDone?("Nighttime schedule updated", AppColor.accentFeed, nil)
        Haptics.success()
        dismiss()
    }

    // MARK: Time bridging

    private func minuteOfDay(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private static func date(minuteOfDay: Int) -> Date {
        ScheduleEngine.materialize(minuteOfDay: minuteOfDay, on: .now, calendar: .current) ?? .now
    }

    static func clock(minuteOfDay: Int) -> String {
        TimeFormatting.clock(date(minuteOfDay: minuteOfDay))
    }

    /// "3h" / "3½h" — how parents say it, not "210 minutes".
    static func spacingLabel(_ minutes: Int) -> String {
        minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)½h"
    }
}

#Preview {
    NightScheduleSettingsSheet()
        .modelContainer(AppModelContainer.preview)
}
