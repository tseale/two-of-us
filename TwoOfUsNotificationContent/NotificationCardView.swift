import SwiftUI

/// The custom expanded view shown when a Two of Us notification is long-pressed /
/// pulled down. Reads live state from the App Group store (`QuickLogger`) so the
/// card reflects the latest data, not whatever was true when the notification was
/// posted. Styled with the app's design tokens; action buttons (Log feed / Snooze,
/// …) still render below, supplied by the notification's category.
struct NotificationCardView: View {
    enum Style {
        case summary        // end-of-day recap
        case coParent       // the other parent just logged
        case reminder       // feed / diaper due
        case dropoffBoard   // geofence drop-off: the daycare whiteboard

        init(categoryID: String) {
            switch categoryID {
            case NotificationID.Category.milestone: self = .summary
            case NotificationID.Category.coParent: self = .coParent
            case NotificationID.Category.geofenceDropOff: self = .dropoffBoard
            default: self = .reminder
            }
        }
    }

    let style: Style
    let title: String
    var subtitle: String = ""
    let message: String
    /// The posted notification's payload — the drop-off board rides here.
    var userInfo: [AnyHashable: Any] = [:]

    private var logger: QuickLogger? { QuickLogger.make() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if style == .dropoffBoard {
                boardHeader
            } else {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppColor.text)
                if !message.isEmpty {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(AppColor.text2)
                }
            }

            Divider().opacity(0.4)

            switch style {
            case .summary: summaryStats
            case .coParent, .reminder: recentRows
            case .dropoffBoard: boardRows
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.bg)
    }

    // MARK: Drop-off — the whiteboard, big enough to read while writing

    /// Live when the App Group store opens (a bottle logged in the car after
    /// the prompt fired still shows), else the rows the notification carried.
    private var board: DropoffBoardInfo? {
        if let logger { return DropoffBoard.load(from: logger.context) }
        return DropoffBoardInfo(userInfo: userInfo)
    }

    private var boardHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppColor.text)
            Spacer()
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppColor.text3)
            }
        }
    }

    @ViewBuilder private var boardRows: some View {
        if let board {
            VStack(spacing: 10) {
                boardRow("🍼", "Last bottle", board.lastBottle, AppColor.accentFeed)
                boardRow("💧", "Last diaper", board.lastDiaper, AppColor.accentDiaper)
                boardRow("☀️", "Woke up at", board.wokeUpAt, AppColor.accentSleep)
                boardRow("💤", "Sleep", board.overnightSleep, AppColor.accentSleep)
                boardRow("📝", "Notes", board.notes ?? "None", AppColor.accentNote)
            }
        } else {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppColor.text2)
        }
    }

    /// One whiteboard column: quiet caption, the answer at display scale.
    private func boardRow(_ emoji: String, _ label: String, _ value: String?, _ tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(emoji).font(.body)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(AppColor.text2)
                Text(value ?? "—")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(value == nil ? AppColor.text3 : AppColor.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value ?? "nothing logged")")
    }

    // MARK: Summary — three stat tiles

    @ViewBuilder private var summaryStats: some View {
        if let l = logger {
            let c = l.todayCounts
            HStack(spacing: 10) {
                stat("🍼", "\(c.feeds)", "\(OzFormat.string(c.oz)) oz", AppColor.accentFeed)
                stat("💤", durationShort(l.todaySleep), "sleep", AppColor.accentSleep)
                stat("💧", "\(c.diapers)", "diapers", AppColor.accentDiaper)
            }
        }
    }

    private func stat(_ emoji: String, _ value: String, _ caption: String, _ tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(emoji).font(.system(size: 22))
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(AppColor.text)
            Text(caption)
                .font(.caption)
                .foregroundStyle(AppColor.text3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Co-parent / reminder — recent "time since" rows

    @ViewBuilder private var recentRows: some View {
        if let l = logger {
            VStack(spacing: 8) {
                row("🍼", "Last feed", feedSince(l))
                row("💧", "Last diaper", l.lastDiaper.map { TimeFormatting.since($0.timestamp) } ?? "—")
                row("💤", "Sleep", sleepStatus(l))
            }
        }
    }

    private func row(_ emoji: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(emoji)
            Text(label).foregroundStyle(AppColor.text2)
            Spacer()
            Text(value)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(AppColor.text)
        }
        .font(.subheadline)
    }

    // MARK: Derived text

    private func feedSince(_ l: QuickLogger) -> String {
        guard let feed = l.lastFeed else { return "—" }
        return "\(TimeFormatting.since(feed.timestamp)) · \(OzFormat.string(feed.amountOz)) oz"
    }

    private func sleepStatus(_ l: QuickLogger) -> String {
        if let active = l.activeSleep {
            return "\(SleepLanguage.gerund(start: active.startedAt)) \(TimeFormatting.since(active.startedAt))"
        }
        if let last = l.lastEndedSleep, let ended = last.endedAt {
            return "awake \(TimeFormatting.since(ended))"
        }
        return "—"
    }

    private func durationShort(_ t: TimeInterval) -> String {
        let minutes = Int(t / 60)
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}
