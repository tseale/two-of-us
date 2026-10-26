import SwiftUI

/// A slide-to-confirm capsule staged as a tiny journey: the emoji thumb (the
/// car) sits at the start of a dashed road, the destination (the little
/// house) waits at the far end, and the label shimmers slide-to-unlock style
/// so the gesture explains itself. The thumb must travel the whole track
/// before the action fires — a pocket tap, a toddler grab, or a bounced
/// phone can never log it by accident.
///
/// The affordances, in order of loudness:
/// - a shimmer sweeping through the label toward the destination,
/// - a chevron pair riding behind the label, pointing the way,
/// - the car itself revving — a gentle nudge forward every few seconds,
/// - the dashed road connecting car to house.
/// On arrival the car drives itself the last stretch, the house springs up
/// to greet it, a sparkle pops, and only then does the action fire — the
/// moment lands before the receipt row takes over. All idle motion respects
/// Reduce Motion; VoiceOver sees a plain button instead of a drag.
struct SlideToConfirm: View {
    let emoji: String
    let label: String
    /// What the thumb is sliding home to — drawn at the track's far end.
    var destinationEmoji: String? = nil
    /// Most vehicle emoji face left; mirroring one makes it drive forward.
    var mirrorThumb = false
    var tint: Color = AppColor.accentCheck
    let onConfirm: () -> Void

    @State private var dragX: CGFloat = 0
    @State private var confirmed = false
    @State private var arrived = false
    @State private var shimmering = false
    @State private var revving = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    private let height: CGFloat = 50
    private let inset: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            let travel = max(geo.size.width - height, 1)
            let progress = min(max(dragX / travel, 0), 1)

            ZStack(alignment: .leading) {
                track(progress: progress)
                road(width: geo.size.width)
                labelView(width: geo.size.width, progress: progress)
                if let destinationEmoji {
                    destination(destinationEmoji, progress: progress)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                thumb(progress: progress)
                    .gesture(dragGesture(travel: travel))
            }
            .onAppear { startIdleMotion() }
        }
        .frame(height: height)
        .accessibilityRepresentation {
            Button(label) { finish() }
        }
    }

    // MARK: Layers

    /// The glass track, filling with the tint behind the car — the road
    /// already traveled.
    private func track(progress: CGFloat) -> some View {
        Capsule()
            .fill(.clear)
            .glassEffect(.regular.tint(AppColor.text2.opacity(0.1)), in: Capsule())
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(tint.opacity(0.22))
                    .frame(width: height + dragX)
            }
            .clipShape(Capsule())
    }

    /// The dashed center line of the road, car to house.
    private func road(width: CGFloat) -> some View {
        RoadDashes()
            .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 8]))
            .foregroundStyle(AppColor.text3.opacity(0.35))
            .padding(.leading, height + 6)
            .padding(.trailing, destinationEmoji == nil ? 18 : 40)
            .allowsHitTesting(false)
    }

    /// The instruction, shimmering toward the destination with a chevron
    /// pair tucked behind it — the classic "slide this way" cue.
    private func labelView(width: CGFloat, progress: CGFloat) -> some View {
        labelContent
            .foregroundStyle(AppColor.text2)
            .overlay {
                // Always in the hierarchy: were it inserted the moment
                // `shimmering` flips, the repeatForever animation would
                // land in the same transaction and never attach.
                LinearGradient(colors: [.clear, .white.opacity(0.85), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 70)
                    .offset(x: shimmerSweep(width: width))
                    .animation(.linear(duration: 2.4).repeatForever(autoreverses: false)
                                   .delay(0.6),
                               value: shimmering)
                    .mask(labelContent)
                    .opacity(reduceMotion ? 0 : 1)
            }
            .frame(maxWidth: .infinity)
        .padding(.leading, height - 6)       // optical center past the parked car
        .padding(.trailing, destinationEmoji == nil ? 10 : 30)
        // The words get out of the car's way as it rolls over them.
        .opacity(1 - Double(progress) * 1.7)
        .allowsHitTesting(false)
    }

    private var labelContent: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Image(systemName: "chevron.right.2")
                .font(.caption.weight(.semibold))
        }
    }

    /// Where the journey ends: the house leans in as the car gets close,
    /// springs up on arrival, and a sparkle pops overhead.
    private func destination(_ destinationEmoji: String, progress: CGFloat) -> some View {
        Text(destinationEmoji)
            .font(.body)
            .scaleEffect(arrived ? 1.3 : 0.9 + 0.2 * progress)
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: arrived)
            .opacity(0.65 + 0.35 * Double(progress))
            .overlay(alignment: .top) {
                Text("✨")
                    .font(.caption2)
                    .scaleEffect(arrived ? 1.2 : 0.1)
                    .opacity(arrived ? 1 : 0)
                    .offset(y: arrived ? -14 : -4)
                    .animation(.spring(response: 0.35, dampingFraction: 0.55), value: arrived)
            }
            .padding(.trailing, 14)
            .allowsHitTesting(false)
    }

    /// The car: revs forward a few points every few seconds while idle, tips
    /// onto its nose while being driven, and hops when it reaches the house.
    private func thumb(progress: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(tint)
                .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
            Text(emoji)
                .font(.body)
                .scaleEffect(x: mirrorThumb ? -1 : 1)
                .rotationEffect(.degrees(mirrorThumb ? Double(progress) * 7
                                                     : Double(progress) * -7))
        }
        .frame(width: height - inset * 2, height: height - inset * 2)
        .padding(inset)
        .scaleEffect(arrived ? 1.12 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.5), value: arrived)
        .offset(x: dragX + (revving && dragX == 0 && !confirmed ? 5 : 0))
        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true).delay(1.2),
                   value: revving)
    }

    // MARK: Motion

    private func dragGesture(travel: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard !confirmed else { return }
                let along = layoutDirection == .rightToLeft
                    ? -value.translation.width
                    : value.translation.width
                dragX = min(max(along, 0), travel)
            }
            .onEnded { _ in
                guard !confirmed else { return }
                if dragX >= travel * 0.82 {
                    finish(travel: travel)
                } else {
                    // Not all the way home — the car rolls back to the start.
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        dragX = 0
                    }
                }
            }
    }

    /// Drive the last stretch, celebrate, then fire — the arrival moment
    /// gets its beat before the slot swaps to the receipt row.
    private func finish(travel: CGFloat? = nil) {
        guard !confirmed else { return }
        confirmed = true
        if let travel {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dragX = travel }
        }
        arrived = true
        Haptics.success()
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.5)) {
            onConfirm()
        }
    }

    private func startIdleMotion() {
        guard !reduceMotion else { return }
        shimmering = true
        revving = true
    }

    /// Shimmer travel: from just past the thumb to the track's far end.
    private func shimmerSweep(width: CGFloat) -> CGFloat {
        shimmering ? width / 2 + 35 : -(width / 2 + 35)
    }
}

/// A straight dashed line through the vertical center — the road's lane
/// markings.
private struct RoadDashes: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
