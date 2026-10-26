import SwiftUI

/// A slide-to-confirm capsule: the thumb must travel the whole track before
/// the action fires, so a pocket tap, a toddler grab, or a bounced phone can
/// never log it by accident. Visually it wears the same glass as the check
/// buttons — a quiet track with the label resting in the middle, fading as
/// the thumb sweeps over it.
///
/// VoiceOver doesn't drag: the control presents itself as a plain button, so
/// the deliberate-gesture gate is a sighted-touch concern only.
struct SlideToConfirm: View {
    let emoji: String
    let label: String
    var tint: Color = AppColor.accentCheck
    let onConfirm: () -> Void

    @GestureState private var dragX: CGFloat = 0
    @State private var confirmed = false
    @Environment(\.layoutDirection) private var layoutDirection

    private let height: CGFloat = 50
    private let inset: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            let travel = max(geo.size.width - height, 1)
            let offset = confirmed ? travel : min(max(dragX, 0), travel)
            let progress = offset / travel

            ZStack(alignment: .leading) {
                // The track: same whisper-tinted glass as the check buttons,
                // filling with the tint behind the thumb as it travels.
                Capsule()
                    .fill(tint.opacity(0.12 + 0.22 * progress))
                    .glassEffect(.regular.tint(AppColor.text2.opacity(0.1)),
                                 in: Capsule())

                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.text2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity)
                    .padding(.leading, height / 2)   // optical center past the thumb
                    .opacity(1 - progress * 1.6)

                // The thumb — the car rides the track.
                ZStack {
                    Circle()
                        .fill(tint)
                        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                    Text(emoji).font(.body)
                }
                .frame(width: height - inset * 2, height: height - inset * 2)
                .padding(inset)
                .offset(x: offset)
                .gesture(
                    DragGesture()
                        .updating($dragX) { value, state, _ in
                            guard !confirmed else { return }
                            // Track the finger along the reading direction.
                            state = layoutDirection == .rightToLeft
                                ? -value.translation.width
                                : value.translation.width
                        }
                        .onEnded { value in
                            guard !confirmed else { return }
                            let final = layoutDirection == .rightToLeft
                                ? -value.translation.width
                                : value.translation.width
                            if final >= travel * 0.85 {
                                confirmed = true
                                Haptics.success()
                                onConfirm()
                            }
                        }
                )
                .animation(.spring(response: 0.32, dampingFraction: 0.8),
                           value: dragX == 0)
                .animation(.spring(response: 0.32, dampingFraction: 0.8),
                           value: confirmed)
            }
        }
        .frame(height: height)
        .accessibilityRepresentation {
            Button(label) {
                guard !confirmed else { return }
                confirmed = true
                Haptics.success()
                onConfirm()
            }
        }
    }
}
