import SwiftUI
import SwiftData

/// Configure the shared nighttime schedule: the night window, the spacing
/// between feeds, and the parent rotation. There's no fixed first-feed time
/// anymore — the schedule is dynamic: the first feed logged inside the window
/// anchors the night, and the rest of the slots march from it by the spacing,
/// alternating between the parents. Saving syncs the settings so both phones
/// build the identical night. House sheet idiom (Form, detents, Cancel/confirm
/// toolbar, undo-less toast via callback).
struct NightScheduleSettingsSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [SharedSettings]
    @Query(filter: #Predicate<Participant> { $0.isActive }, sort: \Participant.invitedAt)
    private var participants: [Participant]
    @Query(filter: #Predicate<FeedEvent> { $0.deletedAt == nil }, sort: \FeedEvent.timestamp, order: .reverse)
    private var recentFeeds: [FeedEvent]

    var onDone: ((String, Color, (() -> Void)?) -> Void)? = nil

    @State private var nightStart: Date = .now
    @State private var nightEnd: Date = .now
    @State private var spacingMinutes = 180
    @State private var rotation: NightRotation = .alternating
    @State private var seeded = false

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
                    if windowValid {
                        Text("The schedule only covers this window — daytime feeds stay ad-hoc.")
                    } else {
                        Text("The night needs to start and end at different times.")
                            .foregroundStyle(AppColor.urgencyAmber)
                    }
                }

                Section("Feed spacing") {
                    Picker("Hours between feeds", selection: $spacingMinutes) {
                        ForEach(Self.spacingChoices, id: \.self) { minutes in
                            Text(Self.spacingLabel(minutes)).tag(minutes)
                        }
                    }
                }

                Section {
                    Picker("Rotation", selection: $rotation) {
                        Text("Take turns").tag(NightRotation.alternating)
                        Text("No assignments").tag(NightRotation.none)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Who's up")
                } footer: {
                    Text(rotation == .alternating
                         ? "Whoever logs tonight's first feed takes it — the rest of the night alternates between you from there."
                         : "No one is assigned — every slot reminds both of you.")
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
                        .disabled(!windowValid)
                        .accessibilityIdentifier("nightSchedule.confirm")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear(perform: seed)
    }

    // MARK: Preview

    /// A worked example of how tonight would build, from a sample anchor (the
    /// predicted next feed when history suggests one inside the window, else
    /// the window's start) — the schedule itself always anchors to the real
    /// first feed, whenever it lands.
    private var previewSection: some View {
        Section {
            ForEach(Array(previewTimes.enumerated()), id: \.offset) { index, date in
                HStack(spacing: 10) {
                    Text("🍼").font(.callout)
                    Text(TimeFormatting.clock(date))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(AppColor.text)
                    Spacer()
                    Text(previewAssigneeLabel(index: index))
                        .font(.caption)
                        .foregroundStyle(AppColor.text2)
                }
            }
        } header: {
            Text("For example")
        } footer: {
            Text(previewTimes.isEmpty
                 ? "These hours generate no feeds — widen the window or tighten the spacing."
                 : "If the first feed landed at \(TimeFormatting.clock(previewAnchor)). The real schedule builds itself from whenever tonight's first feed is actually logged.")
        }
    }

    /// Rotation is anchored to whoever REALLY logs the first feed, so the
    /// preview can only speak in roles, not names.
    private func previewAssigneeLabel(index: Int) -> String {
        guard rotation == .alternating, participants.count >= 2 else { return "Both of you" }
        return index % participants.count == 0 ? "First feeder" : "Other parent"
    }

    /// Sample anchor for the preview: the feed-history prediction when it
    /// falls inside the configured window, else the window's start.
    private var previewAnchor: Date {
        let start = minuteOfDay(nightStart)
        if let predicted = NightScheduleGenerator.predictedNextFeed(
            recentFeedTimestamps: recentFeeds.map(\.timestamp)
        ), NightScheduleGenerator.isWithinNight(
            minuteOfDay: minuteOfDay(predicted),
            nightStartMinute: start,
            nightEndMinute: minuteOfDay(nightEnd)
        ) {
            return predicted
        }
        return Self.date(minuteOfDay: start)
    }

    private var previewTimes: [Date] {
        guard windowValid else { return [] }
        let anchor = previewAnchor
        // Window end materialized after the anchor (tonight wraps midnight).
        let start = minuteOfDay(nightStart)
        let end = minuteOfDay(nightEnd)
        let windowMinutes = ((end - start + 1440) % 1440)
            - ((minuteOfDay(anchor) - start + 1440) % 1440)
        let windowEnd = anchor.addingTimeInterval(TimeInterval(max(0, windowMinutes) * 60))
        return NightSchedule.slotTimes(anchor: anchor, windowEnd: windowEnd,
                                       spacingMinutes: spacingMinutes)
    }

    private var windowValid: Bool {
        minuteOfDay(nightStart) != minuteOfDay(nightEnd)
    }

    // MARK: Actions

    private func seed() {
        guard !seeded, let settings = settingsList.first else { return }
        seeded = true
        nightStart = Self.date(minuteOfDay: settings.nightStartMinute)
        nightEnd = Self.date(minuteOfDay: settings.nightEndMinute)
        spacingMinutes = settings.nightFeedSpacingMinutes
        rotation = settings.nightRotation
    }

    private func saveAndDismiss() {
        EventStore(context: context).applyNightSchedule(
            nightStartMinute: minuteOfDay(nightStart),
            nightEndMinute: minuteOfDay(nightEnd),
            spacingMinutes: spacingMinutes,
            rotation: rotation
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
