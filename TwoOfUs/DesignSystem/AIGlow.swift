import SwiftUI

/// The visual signature for on-device predictions: a ✦ mark and a fixed
/// four-stop gradient on the hint text — and nothing else. Deliberately
/// subtle: prediction lines share tiles with `Urgency`'s semantic coloring,
/// and two competing color systems on one line would read as chaos at 3 AM.
/// The gradient never touches containers, backgrounds, or borders; it marks
/// exactly the text the engine wrote.
enum AIGlow {
    static let mark = "✦"

    /// Pitched to harmonize with the app's accents (the periwinkle is
    /// `accentSleep` itself) rather than Apple's full Siri palette.
    static let colors = [
        Color(hex: "5AA8FF"),
        Color(hex: "8E8EFF"),
        Color(hex: "D984E0"),
        Color(hex: "F5A97F"),
    ]

    static var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }
}

/// A prediction hint line: "✦ next bottle ~2:30 PM · ~3.5 oz". One highlight
/// sweep on first appearance (never under Reduce Motion), static gradient
/// after — calm is load-bearing in this app.
struct AIHintText: View {
    let text: String
    var font: Font = .caption

    @State private var sweepPhase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var label: some View {
        Text("\(AIGlow.mark) \(text)")
            .font(font)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    var body: some View {
        label
            .foregroundStyle(AIGlow.gradient)
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, .white.opacity(0.6), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: max(geo.size.width / 2, 1))
                            .offset(x: sweepPhase * geo.size.width * 1.5)
                    }
                    .mask(label)
                    .allowsHitTesting(false)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.4).delay(0.3)) { sweepPhase = 1 }
                    }
                }
            }
            .accessibilityLabel("Predicted: \(text)")
    }
}
