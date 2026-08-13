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
        UnevenRoundedRectangle(
            topLeadingRadius: run.startsHere ? radius : 0,
            bottomLeadingRadius: run.endsHere ? radius : 0,
            bottomTrailingRadius: run.endsHere ? radius : 0,
            topTrailingRadius: run.startsHere ? radius : 0)
            .fill(tint.opacity(0.85))
            .frame(width: Self.laneWidth,
                   height: max(2, (run.range.upperBound - run.range.lowerBound) * height
                                + bleedTop + bleedBottom))
            .offset(y: run.range.lowerBound * height - bleedTop)
        if run.startsHere {
            // The block self-labels as sleep right where it begins, knocked
            // out of the band in the page color so it stays legible on any
            // parent's tint in either appearance. (The 💤 emoji's own fixed
            // blue disappears into a blue or violet band.)
            Image(systemName: "zzz")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(AppColor.bg)
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
