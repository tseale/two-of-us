import SwiftUI

/// One instance on the upcoming-schedule rail. Same visual language as the Home
/// timeline's `DayTimelineRow` — mono time gutter, continuous rail with a node,
/// emoji + title, trailing person — but future-facing: the trailing avatar is
/// who's *assigned*, not who logged, and the node distinguishes pinned plan
/// (solid) from prediction (hollow).
struct ScheduleRow: View {
    let occurrence: ScheduleOccurrence
    /// Status line under the title ("Swapped by Katie", "Covered by Taylor ✓"),
    /// built by the host, which can resolve participant/event names.
    var caption: String? = nil
    /// Assigned parent's avatar photo, resolved by the host from `assignedToID`.
    var assigneePhoto: Data? = nil
    /// True when this occurrence is assigned to this device's parent.
    var isMine: Bool = false
    /// Show the weekday under the clock when the date isn't today.
    var showsDay: Bool = false

    private var settled: Bool {   // rendered quiet: already handled or waved off
        if case .fulfilled = occurrence.status { return true }
        return occurrence.status == .skipped
    }

    private var accent: Color {
        occurrence.kind == .sleep ? AppColor.accentSleep : AppColor.accentFeed
    }

    private var assignedTint: Color {
        Color(hex: occurrence.assignedToColorHex.isEmpty ? "636366" : occurrence.assignedToColorHex)
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(timeText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(settled ? AppColor.text3.opacity(0.6) : AppColor.text3)
                if showsDay {
                    Text(occurrence.date, format: .dateTime.weekday(.abbreviated))
                        .font(.caption2)
                        .foregroundStyle(AppColor.text3.opacity(0.7))
                }
            }
            .frame(width: 64, alignment: .trailing)

            rail

            HStack(spacing: 8) {
                Text(occurrence.kind.emoji)
                    .font(.callout)
                    .opacity(settled ? 0.45 : 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(settled ? AppColor.text3 : AppColor.text)
                        .strikethrough(occurrence.status == .skipped)
                    if let caption, !caption.isEmpty {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(captionColor)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                assignee
            }
        }
        .frame(minHeight: 46)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var timeText: String {
        (occurrence.isPinned ? "" : "~") + TimeFormatting.clock(occurrence.date)
    }

    private var title: String {
        occurrence.kind == .sleep ? "Sleep" : "Bottle"
    }

    private var captionColor: Color {
        occurrence.status == .overdue ? AppColor.urgencyRedText : AppColor.text2
    }

    /// The continuous rail plus this row's node: solid = pinned in the plan,
    /// hollow = predicted from the log, dimmed once settled.
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
        if occurrence.isPinned {
            Circle()
                .fill(accent.opacity(settled ? 0.35 : 1))
                .frame(width: 11, height: 11)
                .overlay(Circle().strokeBorder(AppColor.card, lineWidth: 2))
        } else {
            Circle()
                .strokeBorder(accent, lineWidth: 2)
                .frame(width: 11, height: 11)
                .background(Circle().fill(AppColor.bg))
        }
    }

    /// Assigned parent's avatar, ringed in their color when it's *you* — the
    /// off-duty parent scans for rows without their ring. Unassigned (and all
    /// predictions) show a dashed placeholder inviting a tap to assign.
    @ViewBuilder
    private var assignee: some View {
        if occurrence.assignedToID != nil {
            Avatar(photoData: assigneePhoto, name: occurrence.assignedToName,
                   colorHex: occurrence.assignedToColorHex, size: 24)
                .opacity(settled ? 0.5 : 1)
                .overlay {
                    if isMine, !settled {
                        Circle().strokeBorder(assignedTint, lineWidth: 2)
                            .frame(width: 30, height: 30)
                    }
                }
        } else {
            Circle()
                .strokeBorder(AppColor.text3.opacity(0.6),
                              style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(width: 24, height: 24)
        }
    }

    private var accessibilityLabel: String {
        var label = "\(title), \(TimeFormatting.clock(occurrence.date))"
        label += occurrence.isPinned ? ", planned" : ", predicted"
        if !occurrence.assignedToName.isEmpty {
            label += isMine ? ", assigned to you" : ", assigned to \(occurrence.assignedToName)"
        }
        if let caption, !caption.isEmpty { label += ", \(caption)" }
        return label
    }
}
