import SwiftUI
import SwiftData

/// Configure the shared nighttime schedule: the night window, the spacing
/// between feeds, and the parent rotation (who takes the first shift; slots
/// alternate from them). There's no fixed first-feed time — the schedule is
/// dynamic: the night's first feed is projected from the last logged feed by
/// the daytime interval (the first step landing inside the window), a real
/// in-window feed replaces the projection, and the rest of the slots march
/// from the anchor by the night spacing. Saving syncs the settings so both
/// phones build the identical night. House sheet idiom (Form, detents,
/// Cancel/confirm toolbar, undo-less toast via callback).
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
    @State private var firstShiftID: UUID?
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
                    if rotation == .alternating, participants.count >= 2 {
                        firstShiftPicker
                    }
                } header: {
                    Text("Who's up")
                } footer: {
                    Text(rotation == .alternating
                         ? "The first shift takes the night's first feed; you alternate from there. Tap any slot on the schedule to swap just one night."
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

    // MARK: First shift

    private var firstShiftPicker: some View {
        HStack(spacing: 12) {
            ForEach(participants) { p in
                let selected = effectiveFirstShiftID == p.id
                Button {
                    firstShiftID = p.id
                    Haptics.tap()
                } label: {
                    VStack(spacing: 6) {
                        Avatar(photoData: p.photoData, name: p.displayName,
                               colorHex: p.colorHex, size: 44)
                            .overlay {
                                if selected {
                                    Circle().strokeBorder(Color(hex: p.colorHex), lineWidth: 3)
                                        .frame(width: 52, height: 52)
                                }
                            }
                        Text(selected ? "\(p.displayName) · first shift" : p.displayName)
                            .font(.caption.weight(selected ? .bold : .regular))
                            .foregroundStyle(AppColor.text)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(selected
                    ? "\(p.displayName) takes the first shift"
                    : "Give \(p.displayName) the first shift")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// What the engine will actually use: the chosen parent, defaulting to the
    /// first in join order (mirrors `NightSchedule.rotationAssignees`).
    private var effectiveFirstShiftID: UUID? {
        firstShiftID ?? participants.first?.id
    }

    // MARK: Preview

    /// Tonight, as the schedule would actually build it: the anchor projected
    /// from the last logged feed by the daytime interval (first step landing
    /// inside the window), then the night spacing — the same math the Home
    /// card and alarms run.
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
            Text("Tonight would run")
        } footer: {
            Text(previewFooter)
        }
    }

    private var previewFooter: String {
        if previewTimes.isEmpty {
            return "These hours generate no feeds — widen the window or tighten the spacing."
        }
        return "Projected from the last logged feed and your daytime interval — the night re-anchors to the first bottle actually logged in (or within an hour before) the window."
    }

    private func previewAssigneeLabel(index: Int) -> String {
        guard rotation == .alternating, participants.count >= 2,
              let firstIndex = participants.firstIndex(where: { $0.id == effectiveFirstShiftID })
        else { return "Both of you" }
        return participants[(firstIndex + index) % participants.count].displayName
    }

    private var previewTimes: [Date] {
        guard windowValid, let window = previewWindow else { return [] }
        let anchor: Date
        // Same precedence as the engine: a feed already logged inside the
        // window (or the grace hour before it) anchors the night; otherwise
        // project from the last feed; otherwise the window's start itself.
        let graceStart = window.start.addingTimeInterval(
            -TimeInterval(NightSchedule.preWindowGraceMinutes * 60))
        if let logged = recentFeeds.reversed()
            .first(where: { $0.timestamp >= graceStart && $0.timestamp <= window.end })?
            .timestamp {
            anchor = logged
        } else if let last = recentFeeds.first?.timestamp,
                  let projected = NightSchedule.projectedAnchor(
                      lastFeed: last,
                      dayIntervalMinutes: settingsList.first?.targetFeedIntervalMinutes ?? 180,
                      windowStart: window.start, windowEnd: window.end
                  ) {
            anchor = projected
        } else {
            anchor = window.start
        }
        let lead = max(0, window.start.timeIntervalSince(anchor))
        return NightSchedule.slotTimes(anchor: anchor,
                                       windowEnd: window.end.addingTimeInterval(lead),
                                       spacingMinutes: spacingMinutes)
    }

    /// Tonight's window from the PENDING (unsaved) start/end values, wrapping
    /// midnight when the end minute precedes the start.
    private var previewWindow: (start: Date, end: Date)? {
        let start = Self.date(minuteOfDay: minuteOfDay(nightStart))
        var end = Self.date(minuteOfDay: minuteOfDay(nightEnd))
        if end <= start {
            end = Calendar.current.date(byAdding: .day, value: 1, to: end) ?? end
        }
        return (start, end)
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
        firstShiftID = settings.nightFirstShiftID
    }

    private func saveAndDismiss() {
        EventStore(context: context).applyNightSchedule(
            nightStartMinute: minuteOfDay(nightStart),
            nightEndMinute: minuteOfDay(nightEnd),
            spacingMinutes: spacingMinutes,
            rotation: rotation,
            firstShiftID: firstShiftID
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
