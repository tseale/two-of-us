import SwiftUI

/// The thin per-parent sleep lanes between the schedule's clock gutter and the
/// bottle rail: a soft tinted band where that parent is planned-asleep, a
/// solid cap with a tiny clock where they fall asleep or wake, nothing where
/// they're up. Geometry arrives precomputed (`SleepLaneLayout` slices) — this
/// view only paints one element's worth, so every list row, and the NOW cap,
/// composes it independently and the bands connect edge-to-edge.
struct SleepLaneColumn: View {
    /// Minimal parent identity a lane renders with, resolved by the host.
    struct Lane: Identifiable, Equatable {
        let id: UUID
        let name: String
        let colorHex: String
    }

    static let laneWidth: CGFloat = 10
    static let laneSpacing: CGFloat = 8

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
                    let run = slice.runs[i]
                    RoundedRectangle(cornerRadius: 3)
                        .fill(tint.opacity(0.26))
                        .frame(width: Self.laneWidth,
                               height: max(2, (run.upperBound - run.lowerBound) * geo.size.height))
                        .offset(y: run.lowerBound * geo.size.height)
                }
                ForEach(slice.caps.indices, id: \.self) { i in
                    let cap = slice.caps[i]
                    Capsule()
                        .fill(tint)
                        .frame(width: Self.laneWidth, height: 2.5)
                        .offset(y: cap.y * geo.size.height - 1.25)
                    if showsLabel(for: cap) {
                        Text(cap.time, format: .dateTime
                            .hour(.defaultDigits(amPM: .omitted)).minute(.twoDigits))
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(tint)
                            .fixedSize()
                            .position(x: -16, y: cap.y * geo.size.height)
                    }
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

    /// The row's own clock sits vertically centered in the gutter the labels
    /// spill into — a cap label landing in that band would collide, so it
    /// stays quiet there (the band position still shows the transition, and
    /// the row's a11y summary carries the exact time).
    private func showsLabel(for cap: SleepLaneLayout.Cap) -> Bool {
        cap.y < 0.36 || cap.y > 0.64
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
