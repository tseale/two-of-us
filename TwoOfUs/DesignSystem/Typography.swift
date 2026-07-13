import SwiftUI
import UIKit

/// The Two of Us type ramp.
///
/// Two ideas drive it:
/// 1. **Glance values are display-scale.** Anything you read in 1.5 seconds at 3am
///    — a timer, a "time since", a record — is large, bold, and `monospacedDigit`
///    so it never jitters as it ticks.
/// 2. **Numerals are rounded, labels are not.** SF Rounded on the big numbers reads
///    as warm and human ("calm, not clinical"); body/label text stays SF Pro for
///    legibility. This pairing is Apple's own convention in Fitness/Sleep/Health.
///
/// Both `display` and `hero` scale with Dynamic Type: the fixed point size is run
/// through `UIFontMetrics` for the mapped text style, so a low-vision parent's
/// larger text setting grows the glance numbers and the hero title too. The scale
/// is bounded (see `scaled`) so the tight glance layouts don't explode at AX5.
enum AppFont {
    /// Big glance numerals (timers, "time since", record values). Rounded + mono.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold,
                        relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        .system(size: scaled(size, relativeTo: style), weight: weight, design: .rounded)
            .monospacedDigit()
    }

    /// Screen / hero titles (the baby's name). Rounded for warmth.
    static func hero(_ size: CGFloat = 34, weight: Font.Weight = .bold,
                     relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        .system(size: scaled(size, relativeTo: style), weight: weight, design: .rounded)
    }

    /// The small ALL-CAPS section labels that sit above a value or card.
    static let sectionLabel = Font.caption2.weight(.semibold)

    /// Scales a fixed point size against the user's Dynamic Type setting via
    /// `UIFontMetrics`. Re-evaluated whenever a SwiftUI body re-runs (which it
    /// does on a content-size-category change), so it tracks live. The growth is
    /// capped at 1.6× because the glance surfaces (square tiles, the timer row,
    /// the 2×2 stats grid) are height/width-constrained — uncapped AX5 scaling
    /// would clip them. Bigger accessibility text still lands; it just doesn't
    /// run away. Full AX3–AX5 layout verification is a device task.
    private static func scaled(_ size: CGFloat, relativeTo style: Font.TextStyle) -> CGFloat {
        let metrics = UIFontMetrics(forTextStyle: style.uiTextStyle)
        return min(metrics.scaledValue(for: size), size * 1.6)
    }
}

private extension Font.TextStyle {
    /// Maps a SwiftUI text style to its UIKit counterpart for `UIFontMetrics`.
    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
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
