import AppIntents
import SwiftUI

struct TimelineRow: View {
    let entry: TimelineEntry

    var body: some View {
        HStack(spacing: 12) {
            Text(entry.emoji)
                .font(.body)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.text)
                    if entry.isFromSnoo { SnooTag() }
                    if entry.isFromDaycare { DaycareTag() }
                }
                Text(TimeFormatting.clock(entry.sortDate))
                    .font(.caption)
                    .foregroundStyle(AppColor.text3)
            }
            Spacer()
            // Sleep carries no logger attribution — it's the baby's doing,
            // not a caregiver task.
            if !isSleep && !entry.isFromDaycare {
                ParticipantBadge(name: entry.loggedByName, colorHex: entry.loggedByColorHex)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.title), \(TimeFormatting.clock(entry.sortDate))\(entry.isFromSnoo ? ", from SNOO" : "")\(entry.isFromDaycare ? ", at daycare" : "")\(isSleep || entry.isFromDaycare ? "" : ", logged by \(entry.loggedByName)")")
        .appEntityIdentifier(EntityIdentifier(for: CareEventEntity.self, identifier: entry.id))
    }

    private var isSleep: Bool {
        if case .sleep = entry { return true }
        return false
    }
}
