import SwiftUI

/// The Two of Us design tokens, watch edition.
///
/// Same semantic names as the phone's `Colors.swift`/`Typography.swift` so
/// shared design-system files (`Urgency.swift`, `CradleMark.swift`) compile
/// into the watch target unchanged — but implemented without UIKit:
/// `UIColor(dynamicProvider:)` and `UIFontMetrics` don't exist on watchOS.
/// The watch renders on black, so every appearance-dynamic token resolves to
/// its dark value (DESIGN.md §2 dark column — dark is the reference mood).
extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        self.init(
            red: Double((rgb & 0xFF0000) >> 16) / 255,
            green: Double((rgb & 0x00FF00) >> 8) / 255,
            blue: Double(rgb & 0x0000FF) / 255
        )
    }
}

/// Semantic color tokens (dark appearance). Views reference these, never raw hex.
enum AppColor {
    static let bg        = Color(hex: "000000")
    static let card      = Color(hex: "1C1C1E")
    static let card2     = Color(hex: "2C2C2E")
    static let separator = Color(hex: "38383A")
    static let text      = Color(hex: "FFFFFF")
    static let text2     = Color(hex: "98989F")
    static let text3     = Color(hex: "636366")

    // Event accents — fixed across appearances; the identity of the three kinds.
    static let accentFeed   = Color(hex: "5AC8B8")
    static let accentSleep  = Color(hex: "8E8EFF")
    static let accentDiaper = Color(hex: "F5B971")

    static let urgencyGreen = Color(hex: "5AD17E")
    static let urgencyAmber = Color(hex: "F5B971")
    static let urgencyRed   = Color(hex: "FF6B6B")
    static let urgencyAmberText = Color(hex: "F0B05A")
    static let urgencyRedText   = Color(hex: "FF8A8A")

    static let nightInk        = Color(hex: "130E18")
    static let markStage       = Color(hex: "231C40")
    static let nightlightCream = Color(hex: "FFF4E8")

    // The ONE intentional gradient (sleep Live Activity runs hi → night);
    // on the watch it backs the scene — the same "glanceable night surface"
    // family as the lock-screen activity.
    static let indigoHi    = Color(hex: "2A2A4D")
    static let indigoLo    = Color(hex: "1C1C2E")
    static let indigoNight = Color(hex: "15151F")
}

/// The type ramp, minus `UIFontMetrics` (watchOS scales system styles itself;
/// fixed display sizes get `minimumScaleFactor` at the call site instead).
enum AppFont {
    /// Big glance numerals (timers, "time since"). Rounded + mono so ticking
    /// values read warm and never jitter.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
            .monospacedDigit()
    }

    /// Titles (row labels). Rounded for warmth — never used for body text.
    static func title(_ size: CGFloat = 16, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// The small ALL-CAPS section labels that sit above a value.
    static let sectionLabel = Font.caption2.weight(.semibold)
}

extension View {
    /// Quiet, tracked, uppercase eyebrow label. Pair above a display value.
    func sectionLabelStyle(color: Color = AppColor.text2) -> some View {
        self.font(AppFont.sectionLabel)
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(color)
    }
}
