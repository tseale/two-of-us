import SwiftUI

/// The slim per-parent sleep lanes between the schedule's clock gutter and the
/// bottle rail: a solid line in each parent's color while they're planned-
/// asleep — the Home timeline's sleep-capsule language, stretched down the
/// rail. A block's real fall-asleep end is rounded and carries a small 💤;
/// its real wake end is rounded; everywhere a block merely continues into the
/// neighboring row the line is cut square and bled past the row boundary, so
/// one window reads as one unbroken band no matter how many rows it crosses.
/// Geometry arrives precomputed (`SleepLaneLayout` slices) — this view only
/// paints one element's worth.
struct SleepLaneColumn: View {
    /// Minimal parent identity a lane renders with, resolved by the host.
    struct Lane: Identifiable, Equatable {
        let id: UUID
        let name: String
        let colorHex: String
    }

    static let laneWidth: CGFloat = 6
    static let laneSpacing: CGFloat = 14
    /// How far a continuing end bleeds past the row boundary so adjacent
    /// rows' segments fuse into one line.
    private static let bleed: CGFloat = 3

    static func width(for laneCount: Int) -> CGFloat {
        CGFloat(laneCount) * laneWidth + CGFloat(max(0, laneCount - 1)) * laneSpacing
    }

    let lanes: [Lane]
    let slices: [SleepLaneLayout.Slice]
    /// Elements above the NOW cap render quieted, like settled rows.
    var dimmed = false
    /// Band tap → the covering window's per-night actions; nil = inert (NOW cap).
    var onTap: ((Int) -> Void)? = nil

    var body: some View {
        HStack(spacing: Self.laneSpacing) {
            ForEach(Array(lanes.enumerated()), id: \.element.id) { index, lane in
                laneView(lane, index: index)
            }
        }
        .frame(width: Self.width(for: lanes.count))
        .opacity(dimmed ? 0.45 : 1)
        // Rows fold the lanes' meaning into their own label (and expose the
        // taps as named actions) — the strips are decoration to VoiceOver.
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
            // The block self-labels as sleep right where it begins — the
            // Home timeline's 💤, sitting on the line like a station marker.
            Text("💤")
                .font(.system(size: 10))
                .fixedSize()
                .position(x: Self.laneWidth / 2,
                          y: run.range.lowerBound * height + 10)
        }
    }
}

/// The strip above the rail's first element: avatar chips centered over each
/// lane, so the lanes never need their order memorized. Mirrors the row
/// geometry (clock gutter, then lanes) so the chips align with the strips.
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
            Spacer(minLength: 0)
        }
        .frame(height: 22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep lanes: \(lanes.map(\.name).joined(separator: ", "))")
    }
}
