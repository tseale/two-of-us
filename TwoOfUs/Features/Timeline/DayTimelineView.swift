import SwiftUI

/// One event on the Home **timeline rail**: a left time gutter, a vertical rail
/// with a colored node, then the event and who logged it. Rows stack flush (zero
/// list insets, separators hidden) so the rail reads as one continuous line down
/// the day. Sleep renders as a duration-scaled **capsule** instead of a dot, so a
/// long nap reads as a longer mark — duration becomes a shape you feel.
///
/// Replaces `TimelineRow` as Home's hero list. `TimelineRow` stays for any other
/// caller that wants the plain icon + title + time layout.
struct DayTimelineRow: View {
    let entry: TimelineEntry
    /// The logger's avatar photo, resolved by the caller from `entry.loggedByID`.
    /// Nil falls back to the colored-monogram badge (same look as before).
    var loggedByPhoto: Data? = nil
    /// Display-name fallback for events whose DENORMALIZED name is empty (older
    /// builds' records, pre-heal). Callers resolve it from `entry.loggedByID`
    /// against the participants they already query — a known logger must render
    /// as themselves, never as the silhouette "ghost" badge.
    var loggedByNameFallback: String? = nil

    private var loggedByName: String {
        entry.loggedByName.isEmpty ? (loggedByNameFallback ?? "") : entry.loggedByName
    }

    var body: some View {
        HStack(spacing: 10) {
            timeColumn

            rail

            HStack(spacing: 8) {
                Text(entry.emoji).font(.callout)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(entry.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColor.text)
                            .lineLimit(2)
                        if entry.isFromSnoo { SnooTag() }
                    }
                    if let note = entry.notes, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(AppColor.text2)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                // Shows the parent's profile photo when they have one, else the
                // colored initial — same monogram fallback as `ParticipantBadge`.
                // Sleep is the baby's doing, not a caregiver task, so it
                // carries no logger attribution.
                if !isSleep {
                    Avatar(photoData: loggedByPhoto, name: loggedByName,
                           colorHex: entry.loggedByColorHex, size: 24)
                }
            }
        }
        .frame(minHeight: 46)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accent: Color {
        switch entry {
        case .feed:   return AppColor.accentFeed
        case .sleep:  return AppColor.accentSleep
        case .diaper: return AppColor.accentDiaper
        case .note:   return AppColor.accentNote
        }
    }

    private var isSleep: Bool {
        if case .sleep = entry { return true }
        return false
    }

    private var accessibilityLabel: String {
        if case .note = entry {
            return "Note: \(entry.title), \(TimeFormatting.clock(entry.sortDate)), logged by \(loggedByName)"
        }
        var label: String
        if case .sleep(let e) = entry, let end = e.endedAt {
            label = "\(entry.title), from \(TimeFormatting.clock(e.startedAt)) to \(TimeFormatting.clock(end))"
        } else {
            label = "\(entry.title), \(TimeFormatting.clock(entry.sortDate))"
        }
        if !isSleep { label += ", logged by \(loggedByName)" }
        if entry.isFromSnoo { label += ", from SNOO" }
        if let note = entry.notes, !note.isEmpty { label += ", note: \(note)" }
        return label
    }

    /// The leading time gutter. Sleep with a known end shows both the start
    /// (bottom, aligned with the base of the rail's capsule) and end (top,
    /// aligned with its cap) — position alone tells them apart, no labels.
    /// Everything else keeps the single centered timestamp.
    @ViewBuilder
    private var timeColumn: some View {
        if case .sleep(let e) = entry, let end = e.endedAt {
            VStack(alignment: .trailing, spacing: 0) {
                Text(TimeFormatting.clock(end))
                Spacer(minLength: 0)
                Text(TimeFormatting.clock(e.startedAt))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(AppColor.text3)
            .frame(width: 64, height: sleepBarLength, alignment: .trailing)
        } else {
            Text(TimeFormatting.clock(entry.sortDate))
                .font(.caption.monospacedDigit())
                .foregroundStyle(AppColor.text3)
                .frame(width: 64, alignment: .trailing)
        }
    }

    /// Length of the sleep duration capsule, shared by the rail's node and
    /// the time column so the two start/end labels line up with its ends.
    private var sleepBarLength: CGFloat? {
        guard case .sleep(let e) = entry else { return nil }
        let minutes = (e.endedAt ?? e.startedAt).timeIntervalSince(e.startedAt) / 60
        return max(14, min(40, 14 + CGFloat(max(0, minutes)).squareRoot() * 1.6))
    }

    /// The continuous rail line plus this row's node, centered over it. The node
    /// carries a card-colored ring so the line appears to pass cleanly behind it.
    private var rail: some View {
        ZStack {
            Rectangle()
                .fill(AppColor.separator.opacity(0.6))
                .frame(width: 2)
                .frame(maxHeight: .infinity)
            node
        }
        .frame(width: 16)
    }

    @ViewBuilder
    private var node: some View {
        switch entry {
        case .sleep:
            // Square-root scaling so longer sleeps keep growing instead of all
            // pinning at the cap — a 4h sleep used to look identical to a 2.5h one
            // (both hit the old 30pt ceiling around ~2h40).
            Capsule()
                .fill(accent)
                .frame(width: 9, height: sleepBarLength)
                .overlay(Capsule().strokeBorder(AppColor.card, lineWidth: 2))
        default:
            Circle()
                .fill(accent)
                .frame(width: 11, height: 11)
                .overlay(Circle().strokeBorder(AppColor.card, lineWidth: 2))
        }
    }
}

/// The little "SNOO" capsule on sleep rows that were imported from the SNOO
/// integration — bassinet time reads apart from hand-logged naps at a glance.
struct SnooTag: View {
    var body: some View {
        Text("SNOO")
            .font(.caption2.weight(.bold))
            .foregroundStyle(AppColor.accentSleep)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(AppColor.accentSleep.opacity(0.14), in: Capsule())
            .accessibilityHidden(true)   // rows fold it into their label
    }
}

/// The soft "NOW" marker that caps the top of the timeline rail. A hollow node
/// with the rail line dropping down to meet the newest event below it.
struct TimelineNowCap: View {
    var body: some View {
        HStack(spacing: 10) {
            Text("NOW")
                .sectionLabelStyle(color: AppColor.text3)
                .frame(width: 64, alignment: .trailing)

            VStack(spacing: 0) {
                Circle()
                    .strokeBorder(AppColor.text3, lineWidth: 1.5)
                    .frame(width: 9, height: 9)
                Rectangle()
                    .fill(AppColor.separator.opacity(0.6))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 16)

            Spacer(minLength: 0)
        }
        .frame(height: 26)
        .accessibilityHidden(true)
    }
}

#Preview {
    let now = Date()
    func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
    let me = ("Taylor", "5AC8B8")
    let mom = ("Mom", "FF8FA3")
    let entries: [TimelineEntry] = [
        .feed(FeedEvent(baby: nil, amountOz: 3, timestamp: ago(12),
                        loggedByID: UUID(), loggedByName: me.0, loggedByColorHex: me.1)),
        .sleep(SleepEvent(baby: nil, startedAt: ago(160), endedAt: ago(78),
                          loggedByID: UUID(), loggedByName: mom.0, loggedByColorHex: mom.1)),
        .diaper(DiaperEvent(baby: nil, type: .wet, timestamp: ago(190),
                            loggedByID: UUID(), loggedByName: me.0, loggedByColorHex: me.1)),
        .feed(FeedEvent(baby: nil, amountOz: 4, timestamp: ago(235),
                        loggedByID: UUID(), loggedByName: mom.0, loggedByColorHex: mom.1)),
        .sleep(SleepEvent(baby: nil, startedAt: ago(320), endedAt: ago(275),
                          loggedByID: UUID(), loggedByName: me.0, loggedByColorHex: me.1)),
    ]
    return List {
        Section {
            TimelineNowCap()
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            ForEach(entries) { entry in
                DayTimelineRow(entry: entry)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }
        } header: {
            Text("Recent")
        }
        .listRowBackground(Color.clear)
    }
    .listStyle(.plain)
    .background(AppColor.bg)
}
