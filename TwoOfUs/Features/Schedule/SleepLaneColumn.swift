import SwiftUI

/// The per-parent sleep bands between the schedule's clock gutter and the
/// bottle rail: a solid bar in each parent's color for every stretch they're
/// planned-asleep — the Home timeline's sleep capsule, stretched down the
/// rail. A block's real fall-asleep end is rounded and carries a knocked-out
/// `zzz`; its real wake end is rounded; everywhere a block merely continues
/// into the neighboring row the bar is cut square and bled a hair past the row
/// boundary, so one window reads as one unbroken band no matter how many rows
/// it crosses. Bands never dim with their row — a block is one object, and
/// half of it fading at the NOW line reads as a break in the sleep, not a
/// break in the past.
///
/// Geometry arrives precomputed (`SleepLaneLayout` slices) — this view only
/// paints one element's worth.
struct SleepLaneColumn: View {
    /// Minimal parent identity a lane renders with, resolved by the host.
    struct Lane: Identifiable, Equatable {
        let id: UUID
        let name: String
        let colorHex: String
    }

    /// Wide enough to hold the `zzz` inside the band and to read as a block of
    /// sleep rather than a hairline.
    static let laneWidth: CGFloat = 16
    static let laneSpacing: CGFloat = 8
    /// How far a continuing end bleeds past the row boundary so adjacent
    /// rows' segments fuse into one bar.
    private static let bleed: CGFloat = 2
    /// The band's tint, softened toward the row it sits on — but FLATTENED,
    /// not translucent. Bands are drawn per row and bleed into each other, so
    /// a `.opacity(_:)` fill would composite with itself in every overlap and
    /// stripe the bar with a darker line at each row boundary.
    private static let bandAlpha = 0.85
    /// Band height the 💤 needs to sit inside its block: the 4pt inset plus
    /// the glyph, with a point to spare.
    private static let zzzHeadroom: CGFloat = 14

    static func width(for laneCount: Int) -> CGFloat {
        CGFloat(laneCount) * laneWidth + CGFloat(max(0, laneCount - 1)) * laneSpacing
    }

    let lanes: [Lane]
    let slices: [SleepLaneLayout.Slice]
    /// Band tap → the covering window's per-night actions; nil = inert (NOW cap).
    var onTap: ((Int) -> Void)? = nil

    var body: some View {
        HStack(spacing: Self.laneSpacing) {
            ForEach(Array(lanes.enumerated()), id: \.element.id) { index, lane in
                laneView(lane, index: index)
            }
        }
        .frame(width: Self.width(for: lanes.count))
        // Rows fold the lanes' meaning into their own label (and expose the
        // taps as named actions) — the bands are decoration to VoiceOver.
        .accessibilityHidden(true)
    }

    private func laneView(_ lane: Lane, index: Int) -> some View {
        let slice = index < slices.count ? slices[index] : SleepLaneLayout.Slice()
        let tint = Color(hex: lane.colorHex.isEmpty ? "636366" : lane.colorHex)
            .flattened(over: AppColor.row, alpha: Self.bandAlpha)
        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(slice.runs.indices, id: \.self) { i in
                    band(slice.runs[i], tint: tint, height: geo.size.height)
                }
            }
        }
        .frame(width: Self.laneWidth)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !slice.runs.isEmpty else { return }
            onTap?(index)
        }
    }

    @ViewBuilder
    private func band(_ run: SleepLaneLayout.Run, tint: Color, height: CGFloat) -> some View {
        // Continuing ends land on the element's edge — square them off and
        // bleed past the boundary so the neighbor's segment fuses seamlessly.
        // Real transitions get the rounded cap.
        let bleedTop = !run.startsHere && run.range.lowerBound < 0.001 ? Self.bleed : 0
        let bleedBottom = !run.endsHere && run.range.upperBound > 0.999 ? Self.bleed : 0
        let radius = Self.laneWidth / 2
        let span = CGFloat(run.range.upperBound - run.range.lowerBound) * height
        UnevenRoundedRectangle(
            topLeadingRadius: run.startsHere ? radius : 0,
            bottomLeadingRadius: run.endsHere ? radius : 0,
            bottomTrailingRadius: run.endsHere ? radius : 0,
            topTrailingRadius: run.startsHere ? radius : 0)
            .fill(tint)
            .frame(width: Self.laneWidth, height: max(2, span + bleedTop + bleedBottom))
            .offset(y: run.range.lowerBound * height - bleedTop)
        // The block self-labels as sleep right where it begins, knocked out of
        // the band in the row's own color so it stays legible on any parent's
        // tint in either appearance. (The 💤 emoji's own fixed blue disappears
        // into a blue or violet band.) A block too short to contain the glyph
        // goes without rather than spilling it onto the row below — a stray
        // mark floating off a stub reads as a rendering fault.
        if run.startsHere, span >= Self.zzzHeadroom {
            Image(systemName: "zzz")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(AppColor.row)
                .frame(width: Self.laneWidth)
                .offset(y: run.range.lowerBound * height + 4)
        }
    }
}

/// The strip above the rail's first element: avatar chips centered over each
/// band, so the bands never need their order memorized, and one quiet "asleep"
/// so the column explains itself once. Mirrors the row geometry (clock gutter,
/// then bands) so the chips align with the bars.
struct SleepLaneLegendRow: View {
    let lanes: [SleepLaneColumn.Lane]
    /// Participant id → avatar photo, resolved by the host.
    var photos: [UUID: Data] = [:]

    var body: some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: 64, height: 1)
            HStack(spacing: SleepLaneColumn.laneSpacing) {
                ForEach(lanes) { lane in
                    Avatar(photoData: photos[lane.id], name: lane.name,
                           colorHex: lane.colorHex, size: 16)
                        .frame(width: SleepLaneColumn.laneWidth)
                }
            }
            .frame(width: SleepLaneColumn.width(for: lanes.count))
            Text("asleep")
                .font(.caption2)
                .foregroundStyle(AppColor.text3)
            Spacer(minLength: 0)
        }
        .frame(height: 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep bands: \(lanes.map(\.name).joined(separator: ", "))")
    }
}

/// The bookend below the rail's last bottle: a hollow node at the night's last
/// wake, so sleep that outlasts the final feed ends in a rounded cap instead of
/// running off the bottom edge. Without it the rail's range stops at the last
/// bottle and the longest sleeper's band is left open — the night reads as
/// unfinished. The vertical mirror of `TimelineNowCap`: rail down into the
/// node, node centered so it lines up with the layout's node line (0.5).
struct SleepLaneWakeCap: View {
    /// The last moment anyone on the rail is asleep — this element's own time.
    let date: Date
    let lanes: [SleepLaneColumn.Lane]
    let slices: [SleepLaneLayout.Slice]

    var body: some View {
        HStack(spacing: 10) {
            Text(TimeFormatting.clock(date))
                .font(.caption.monospacedDigit())
                .foregroundStyle(AppColor.text3)
                .frame(width: 64, alignment: .trailing)

            SleepLaneColumn(lanes: lanes, slices: slices)

            ZStack {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(AppColor.separator.opacity(0.6))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                    Color.clear.frame(maxHeight: .infinity)
                }
                Circle()
                    .strokeBorder(AppColor.text3, lineWidth: 1.5)
                    .frame(width: 9, height: 9)
            }
            .frame(width: 16)
            // Sized here rather than from the outside for the same reason the
            // NOW cap is: the bands are a greedy sibling and would otherwise
            // stretch only to the label's natural height.
            .frame(height: 40)

            Text("awake")
                .font(.caption2)
                .foregroundStyle(AppColor.text3)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Everyone awake by \(TimeFormatting.clock(date))")
    }
}
