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

    var body: some View {
        HStack(spacing: 10) {
            Text(TimeFormatting.clock(entry.sortDate))
                .font(.caption.monospacedDigit())
                .foregroundStyle(AppColor.text3)
                .frame(width: 64, alignment: .trailing)

            rail

            HStack(spacing: 8) {
                Text(entry.kind.emoji).font(.callout)
                Text(entry.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.text)
                Spacer(minLength: 8)
                ParticipantBadge(name: entry.loggedByName, colorHex: entry.loggedByColorHex)
            }
        }
        .frame(minHeight: 46)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.title), \(TimeFormatting.clock(entry.sortDate)), logged by \(entry.loggedByName)")
    }

    private var accent: Color {
        switch entry.kind {
        case .feed:   return AppColor.accentFeed
        case .sleep:  return AppColor.accentSleep
        case .diaper: return AppColor.accentDiaper
        }
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
        case .sleep(let e):
            let minutes = (e.endedAt ?? e.startedAt).timeIntervalSince(e.startedAt) / 60
            // Square-root scaling so longer sleeps keep growing instead of all
            // pinning at the cap — a 4h sleep used to look identical to a 2.5h one
            // (both hit the old 30pt ceiling around ~2h40).
            let length = max(14, min(40, 14 + CGFloat(max(0, minutes)).squareRoot() * 1.6))
            Capsule()
                .fill(accent)
                .frame(width: 9, height: length)
                .overlay(Capsule().strokeBorder(AppColor.card, lineWidth: 2))
        default:
            Circle()
                .fill(accent)
                .frame(width: 11, height: 11)
                .overlay(Circle().strokeBorder(AppColor.card, lineWidth: 2))
        }
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
