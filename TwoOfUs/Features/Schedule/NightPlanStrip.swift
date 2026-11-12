import SwiftUI

/// The standing plan drawn to scale: one track the length of the night, each
/// parent's sleep window on it as a pill in that parent's colour — the
/// Tonight rail's bands, laid on their side. The rail beside it is spaced by
/// its bottles, not the clock; this is the one place a parent sees how long
/// each of them actually gets, and whether the two windows meet, overlap or
/// leave a gap.
///
/// The pills speak the rail's language. A real fall-asleep is a rounded end
/// with the band's knocked-out `zzz`; a real wake is rounded; a window the
/// night cuts short is squared off at the track's edge, the way a band is
/// squared where it carries on into the next row. Parents who hand the night
/// over share one row; once both are down at the same time each gets a
/// thinner row of their own, so neither pill hides the other.
///
/// Geometry arrives from `NightPlanScale` — this view only paints. It is a
/// picture of rows the page already lists, so VoiceOver gets one sentence
/// (`summary`) in place of its parts.
struct NightPlanStrip: View {
    let scale: NightPlanScale
    /// The parents' standing windows; the scale clips them to the night.
    let windows: [SleepWindow]
    /// Who the pills belong to, in the rail's lane order: a pill takes its
    /// colour from here, and the rows — when the parents overlap — their
    /// order.
    let lanes: [SleepLaneColumn.Lane]
    /// The plan in one sentence, for VoiceOver.
    let summary: String

    /// The room one hour label needs before the next, at the default text
    /// size. Scaled with the labels, so a larger size thins the marks out
    /// instead of running them together.
    @ScaledMetric(relativeTo: .caption2) private var tickClearance: CGFloat = 28

    static let trackHeight: CGFloat = 24
    /// How far the pills keep from the track's top and bottom edges.
    private static let pillInset: CGFloat = 4
    /// Between two parents' rows, when they overlap.
    private static let rowGap: CGFloat = 2
    /// A hair of track left after a pill's wake, so two windows that meet
    /// (one parent up as the other lies down) read as two.
    private static let wakeGap: CGFloat = 1.5
    /// The least pill that still holds the `zzz` clear of its ends.
    private static let zzzRoom: CGFloat = 26
    private static let tickFont = Font.caption2.weight(.medium)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            track
            hourLabels
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    // MARK: Track

    private var track: some View {
        let rows = NightPlanScale.rows(scale.pills(for: windows),
                                       parentOrder: lanes.map(\.id))
        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(rows.indices, id: \.self) { row in
                    ForEach(rows[row].indices, id: \.self) { index in
                        pillView(rows[row][index], row: row, rowCount: rows.count,
                                 width: geo.size.width)
                    }
                }
            }
        }
        .frame(height: Self.trackHeight)
        .background(AppColor.card2, in: Capsule())
        // A window the night cuts short runs square to the track's edge, and
        // the track's own round end trims it.
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func pillView(_ pill: NightPlanScale.Pill, row: Int, rowCount: Int,
                          width: CGFloat) -> some View {
        let count = CGFloat(max(rowCount, 1))
        let height = (Self.trackHeight - 2 * Self.pillInset - (count - 1) * Self.rowGap) / count
        let x = NightPlanScale.x(at: pill.start, width: width)
        let y = Self.pillInset + CGFloat(row) * (height + Self.rowGap)
        let length = max(NightPlanScale.x(at: pill.end - pill.start, width: width)
                         - (pill.endsInNight ? Self.wakeGap : 0), 2)
        let radius = height / 2
        let colorHex = lanes.first { $0.id == pill.parentID }?.colorHex ?? ""
        UnevenRoundedRectangle(
            topLeadingRadius: pill.startsInNight ? radius : 0,
            bottomLeadingRadius: pill.startsInNight ? radius : 0,
            bottomTrailingRadius: pill.endsInNight ? radius : 0,
            topTrailingRadius: pill.endsInNight ? radius : 0)
            .fill(SleepLaneColumn.bandTint(colorHex: colorHex))
            .frame(width: length, height: height)
            .offset(x: x, y: y)
        // The rail's own mark, where the sleep begins — on the single row
        // only (a split row is too thin to hold it), and only in a pill long
        // enough to keep it clear of both ends.
        if pill.startsInNight, rowCount == 1, length >= Self.zzzRoom {
            Image(systemName: "zzz")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(AppColor.row)
                .frame(height: height)
                .offset(x: x + 7, y: y)
        }
    }

    // MARK: Hour labels

    /// The marks under the track: the night's start flush with its leading
    /// end, its end flush with the trailing one, the clock's hours between
    /// them centred where they fall.
    private var hourLabels: some View {
        // One label, unseen, gives the row its height at any text size; the
        // real ones are placed over it once the width is known.
        Text(verbatim: "12a")
            .font(Self.tickFont)
            .hidden()
            .frame(maxWidth: .infinity)
            .overlay {
                GeometryReader { geo in
                    let separation = geo.size.width > 0
                        ? Double(tickClearance / geo.size.width) : 1
                    ForEach(scale.ticks(minSeparation: separation), id: \.minuteOfDay) { tick in
                        tickLabel(tick, in: geo.size)
                    }
                }
            }
    }

    @ViewBuilder
    private func tickLabel(_ tick: NightPlanScale.Tick, in size: CGSize) -> some View {
        let text = Text(verbatim: NightPlanScale.label(minuteOfDay: tick.minuteOfDay,
                                                       twentyFourHour: Self.uses24HourClock))
            .font(Self.tickFont)
            .foregroundStyle(AppColor.text3)
            .fixedSize()
        switch tick.kind {
        case .start:
            text.frame(width: size.width, height: size.height, alignment: .leading)
        case .end:
            text.frame(width: size.width, height: size.height, alignment: .trailing)
        case .hour:
            text.position(x: NightPlanScale.x(at: tick.position, width: size.width),
                          y: size.height / 2)
        }
    }

    /// Whether this phone writes its clocks without AM and PM, so the marks
    /// agree with every other time on the page.
    private static var uses24HourClock: Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0,
                                              locale: Locale.current) ?? ""
        return !format.contains("a")
    }
}

#Preview("The plan, to scale") {
    let taylor = UUID()
    let katie = UUID()
    let lanes = [SleepLaneColumn.Lane(id: taylor, name: "Taylor", colorHex: "5AC8B8"),
                 SleepLaneColumn.Lane(id: katie, name: "Katie", colorHex: "8E8EFF")]
    return VStack(spacing: 24) {
        if let scale = NightPlanScale(nightStartMinute: 21 * 60, nightEndMinute: 7 * 60) {
            // The night handed over at 2 AM.
            NightPlanStrip(scale: scale,
                           windows: [SleepWindow(parentID: taylor, startMinute: 22 * 60,
                                                 durationMinutes: 240),
                                     SleepWindow(parentID: katie, startMinute: 2 * 60,
                                                 durationMinutes: 240)],
                           lanes: lanes, summary: "")
            // Both down from 1 to 3, and Katie asleep before the night starts.
            NightPlanStrip(scale: scale,
                           windows: [SleepWindow(parentID: taylor, startMinute: 23 * 60,
                                                 durationMinutes: 240),
                                     SleepWindow(parentID: katie, startMinute: 20 * 60,
                                                 durationMinutes: 180),
                                     SleepWindow(parentID: katie, startMinute: 1 * 60,
                                                 durationMinutes: 360)],
                           lanes: lanes, summary: "")
        }
    }
    .padding(16)
    .frame(width: 350)
    .background(AppColor.card)
    .preferredColorScheme(.dark)
}
