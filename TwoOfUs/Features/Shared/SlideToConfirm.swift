import SwiftUI
import UIKit

/// A slide-to-confirm pill in the slide-to-power-off family: a frosted glass
/// capsule, a clean circular thumb (a tinted disc with a single glyph), the instruction shimmering through the center, and a
/// checkmark condensing out of the far end as the thumb approaches. The thumb
/// must travel the whole track before the action fires — a pocket tap, a
/// toddler grab, or a bounced phone can never log it by accident.
///
/// The affordances, quietest to loudest:
/// - the tinted glass itself, reading as one interactive surface,
/// - a shimmer sweeping through the label, slide-to-unlock style,
/// - a chevron pair tucked behind the label, pointing the way,
/// - the checkmark fading in ahead as progress builds.
/// On arrival the track floods with the tint, the checkmark springs, a heavy
/// impact lands, and only then does the action fire — the moment gets its
/// beat before the receipt row takes over. Idle motion respects Reduce
/// Motion; VoiceOver sees a plain button instead of a drag.
struct SlideToConfirm: View {
    let label: String
    var tint: Color = AppColor.accentCheck
    /// The glyph on the thumb's tinted disc.
    var thumbSymbol: String = "chevron.right.2"
    let onConfirm: () -> Void

    @State private var dragX: CGFloat = 0
    @State private var confirmed = false
    @State private var arrived = false
    @State private var shimmering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    private let height: CGFloat = 56
    private let inset: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let travel = max(geo.size.width - height, 1)
            let progress = min(max(dragX / travel, 0), 1)

            ZStack(alignment: .leading) {
                track(progress: progress)
                labelView(progress: progress)
                checkmark(progress: progress)
                    .frame(maxWidth: .infinity, alignment: .trailing)
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

    /// The frosted pill: tinted glass with a hairline, and a soft gradient
    /// wake filling in behind the thumb — the stretch already traveled. On
    /// arrival the wake floods the whole track.
    private func track(progress: CGFloat) -> some View {
        Capsule()
            .fill(.clear)
            .glassEffect(.regular.tint(tint.opacity(0.10)), in: Capsule())
            .overlay(alignment: .leading) {
                // A capsule, so the leading edge curves around the thumb.
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.38), tint.opacity(0.16)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: height + dragX)
            }
            .overlay {
                // Arrival flood — the pill turns the tint for its beat.
                Capsule()
                    .fill(tint.opacity(0.85))
                    .opacity(arrived ? 1 : 0)
                    .animation(.easeOut(duration: 0.25), value: arrived)
            }
            .overlay {
                Capsule()
                    .strokeBorder(tint.opacity(0.22), lineWidth: 1)
            }
            .clipShape(Capsule())
    }

    /// The instruction, shimmering toward the checkmark with a chevron pair
    /// tucked behind it — the classic "slide this way" cue. It thins out of
    /// the thumb's way as the slide begins.
    private func labelView(progress: CGFloat) -> some View {
        labelContent
            .foregroundStyle(AppColor.text2)
            .overlay {
                // One bright band sweeping across the label's own bounds,
                // masked by the label itself — a single layer of text.
                // Always in the hierarchy: were it inserted the moment
                // `shimmering` flips, the repeatForever animation would
                // land in the same transaction and never attach.
                Rectangle()
                    .fill(LinearGradient(colors: [.clear, .white.opacity(0.85), .clear],
                                         startPoint: UnitPoint(x: shimmerPhase - 1, y: 0.5),
                                         endPoint: UnitPoint(x: shimmerPhase, y: 0.5)))
                    .animation(.linear(duration: 2.4).repeatForever(autoreverses: false)
                                   .delay(0.6),
                               value: shimmering)
                    .mask(labelContent)
                    .opacity(reduceMotion ? 0 : 1)
            }
            .frame(maxWidth: .infinity)
            .padding(.leading, height - 10)      // optical center past the parked thumb
            .padding(.trailing, 26)
            // The words get out of the thumb's way as it slides over them.
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

    /// Where the slide ends: a checkmark that condenses out of the glass as
    /// the thumb approaches, then springs white on arrival.
    private func checkmark(progress: CGFloat) -> some View {
        Image(systemName: "checkmark")
            .font(.body.weight(.bold))
            .foregroundStyle(arrived ? AnyShapeStyle(.white)
                                     : AnyShapeStyle(tint))
            .scaleEffect(arrived ? 1.15 : 0.5 + 0.5 * progress)
            .opacity(arrived ? 1 : 0.15 + 0.85 * Double(progress))
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: arrived)
            .padding(.trailing, 20)
            .allowsHitTesting(false)
    }

    /// The thumb: a tinted disc with a glyph. It lifts slightly on arrival.
    private func thumb(progress: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [tint, tint.opacity(0.8)],
                                     startPoint: .top, endPoint: .bottom))
            Image(systemName: thumbSymbol)
                .font(.body.weight(.bold))
                .foregroundStyle(.white)
        }
        .frame(width: height - inset * 2, height: height - inset * 2)
        .shadow(color: tint.opacity(0.35), radius: 6, y: 2)
        .padding(inset)
        .scaleEffect(arrived ? 1.08 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.5), value: arrived)
        .offset(x: dragX)
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
                    // Not all the way — the thumb settles back to the start.
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        dragX = 0
                    }
                }
            }
    }

    /// Glide the last stretch, flood the pill, land the heavy impact, then
    /// fire — the arrival moment gets its beat before the slot swaps to the
    /// receipt row.
    private func finish(travel: CGFloat? = nil) {
        guard !confirmed else { return }
        confirmed = true
        if let travel {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dragX = travel }
        }
        arrived = true
        Haptics.heavy()
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.5)) {
            onConfirm()
        }
    }

    private func startIdleMotion() {
        guard !reduceMotion else { return }
        shimmering = true
    }

    /// Shimmer position: the band's trailing edge, from before the label to past it.
    private var shimmerPhase: CGFloat { shimmering ? 2 : 0 }
}
