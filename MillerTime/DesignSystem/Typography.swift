import SwiftUI

/// The Miller Time type ramp.
///
/// Two ideas drive it:
/// 1. **Glance values are display-scale.** Anything you read in 1.5 seconds at 3am
///    — a timer, a "time since", a record — is large, bold, and `monospacedDigit`
///    so it never jitters as it ticks.
/// 2. **Numerals are rounded, labels are not.** SF Rounded on the big numbers reads
///    as warm and human ("calm, not clinical"); body/label text stays SF Pro for
///    legibility. This pairing is Apple's own convention in Fitness/Sleep/Health.
///
/// Everything scales with Dynamic Type via `.relativeTo` text styles, so XXL still
/// works without clipping.
enum AppFont {
    /// Big glance numerals (timers, "time since", record values). Rounded + mono.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold,
                        relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        .system(size: size, weight: weight, design: .rounded)
            .monospacedDigit()
    }

    /// Screen / hero titles (the baby's name). Rounded for warmth.
    static func hero(_ size: CGFloat = 34, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// The small ALL-CAPS section labels that sit above a value or card.
    static let sectionLabel = Font.caption2.weight(.semibold)
}

extension View {
    /// Quiet, tracked, uppercase eyebrow label. Pair above a display value.
    /// Uses `text2` so it recedes behind the number it introduces.
    func sectionLabelStyle(color: Color = AppColor.text2) -> some View {
        self.font(AppFont.sectionLabel)
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(color)
    }
}

/// A vertically-stacked "eyebrow label + big value + optional caption" metric —
/// the core glance unit reused across Home, the active sleep card, and Stats.
struct MetricStack: View {
    let label: String
    let value: String
    var caption: String? = nil
    var valueSize: CGFloat = 34
    var valueColor: Color = AppColor.text
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(label).sectionLabelStyle()
            Text(value)
                .font(AppFont.display(valueSize))
                .foregroundStyle(valueColor)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(AppColor.text3)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
    }
}
