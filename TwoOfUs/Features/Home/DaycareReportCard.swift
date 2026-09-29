import SwiftUI

/// One day of daycare, aggregated for the report card. Built by HomeView from
/// today's Brightwheel-imported events; nil counts render as absent phrases.
struct DaycareDaySummary: Equatable {
    var feedCount = 0
    var feedOz: Double = 0
    var napCount = 0
    var napSeconds: TimeInterval = 0
    var diaperCount = 0
    var activityCount = 0
    var photoCount = 0
    var medicationCount = 0
    var checkIn: Date?          // first check-in of the day
    var checkOut: Date?         // last check-out of the day
    var hasAnythingElse = false // any other daycare event (note, mood, milestone…)

    var isEmpty: Bool {
        feedCount == 0 && napCount == 0 && diaperCount == 0 && activityCount == 0
            && photoCount == 0 && medicationCount == 0
            && checkIn == nil && checkOut == nil && !hasAnythingElse
    }

    /// Hours between drop-off and pick-up (or "so far" while still checked in).
    var attendanceSeconds: TimeInterval? {
        guard let checkIn else { return nil }
        let end = checkOut ?? .now
        return end > checkIn ? end.timeIntervalSince(checkIn) : nil
    }
}

/// The "Daycare report" glance card on Home: one line summarizing what
/// Brightwheel logged for Miller today — bottles, naps, changes, activities,
/// photos — plus the drop-off→pick-up span, so a parent arriving at pick-up
/// reads the day without scrolling the timeline. Only renders when today
/// actually has daycare events; the per-event story stays on the timeline
/// rail with its Daycare tags.
struct DaycareReportCard: View {
    let babyName: String
    let day: DaycareDaySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("\u{1F3EB}")
                Text("DAYCARE REPORT").sectionLabelStyle()
            }
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(AppColor.text)
                .fixedSize(horizontal: false, vertical: true)
            if let attendance {
                Text(attendance)
                    .font(.caption)
                    .foregroundStyle(AppColor.text3)
            }
            if day.medicationCount > 0 {
                // Medication gets its own red line — never buried in the list.
                Text("\(Plural.count(day.medicationCount, "medication")) given — see the timeline.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppColor.accentMedication)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .surfaceCard(cornerRadius: 14)
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        var parts: [String] = []
        if day.feedCount > 0 {
            parts.append("\(Plural.count(day.feedCount, "bottle")) (\(OzFormat.string(day.feedOz)) oz total)")
        }
        if day.napCount > 0 {
            parts.append("\(Plural.count(day.napCount, "nap")) (\(TimeFormatting.duration(minutes: Int(day.napSeconds / 60))))")
        }
        if day.diaperCount > 0 {
            parts.append(Plural.count(day.diaperCount, "diaper change"))
        }
        if day.activityCount > 0 {
            parts.append("\(day.activityCount) " + (day.activityCount == 1 ? "activity" : "activities"))
        }
        if day.photoCount > 0 {
            parts.append(Plural.count(day.photoCount, "photo"))
        }
        guard !parts.isEmpty else {
            return "\(babyName) is checked in at daycare."
        }
        return "\(babyName) had " + parts.formatted(.list(type: .and)) + " at daycare today."
    }

    /// "At daycare 7:30 AM – 4:30 PM (9h)" — or the open-ended form while
    /// he's still there.
    private var attendance: String? {
        guard let checkIn = day.checkIn, let seconds = day.attendanceSeconds else { return nil }
        let duration = TimeFormatting.duration(minutes: Int(seconds / 60))
        if let checkOut = day.checkOut {
            return "At daycare \(TimeFormatting.clock(checkIn)) – \(TimeFormatting.clock(checkOut)) (\(duration))"
        }
        return "Checked in at \(TimeFormatting.clock(checkIn)) (\(duration) so far)"
    }
}
