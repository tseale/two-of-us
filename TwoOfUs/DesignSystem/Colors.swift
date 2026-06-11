import SwiftUI
import UIKit

extension Color {
    init(hex: String) {
        self.init(uiColor: UIColor(hex: hex))
    }
}

extension UIColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255
        let b = CGFloat(rgb & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

/// A color that resolves differently in light vs dark appearance.
private func dyn(light: String, dark: String) -> Color {
    Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
    })
}

/// Semantic color tokens. Views reference these, never raw hex.
enum AppColor {
    static let bg        = dyn(light: "F2F2F7", dark: "000000")
    static let card      = dyn(light: "FFFFFF", dark: "1C1C1E")
    static let card2     = dyn(light: "ECECF0", dark: "2C2C2E")
    static let separator = dyn(light: "D1D1D6", dark: "38383A")
    static let text      = dyn(light: "000000", dark: "FFFFFF")
    static let text2     = dyn(light: "6C6C70", dark: "98989F")
    static let text3     = dyn(light: "8E8E93", dark: "636366")

    static let accentFeed   = Color(hex: "5AC8B8")
    static let accentSleep  = Color(hex: "8E8EFF")
    static let accentDiaper = Color(hex: "F5B971")

    static let urgencyGreen = Color(hex: "5AD17E")
    static let urgencyAmber = Color(hex: "F5B971")
    static let urgencyRed   = Color(hex: "FF6B6B")

    /// Deep warm plum-indigo: the night-stage base ("nursery at 3am", not blue-black).
    static let nightInk = Color(hex: "130E18")
    /// Warm cream of the baby's light; text/glow color on the night stage.
    static let nightlightCream = Color(hex: "FFF4E8")
}

// MARK: - Liquid Glass (iOS 26)

extension View {
    /// Liquid Glass surface for content cards. Drop-in replacement for the old
    /// `.background(AppColor.card, in: RoundedRectangle(cornerRadius:))` pattern.
    func glassCard(cornerRadius: CGFloat = 18) -> some View {
        glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }

    /// Accent-tinted, touch-responsive glass for the primary log tiles.
    func glassTile(cornerRadius: CGFloat = 20, tint: Color) -> some View {
        glassEffect(.regular.tint(tint.opacity(0.18)).interactive(),
                    in: .rect(cornerRadius: cornerRadius))
    }

    /// A calm, *solid* content surface (no glass). Used for things you read but
    /// don't tap — status pills, data cards, timeline rows — so that the glass
    /// elements (log tiles, active sleep card, tab bar) read as the elevated,
    /// interactive layer. Hierarchy through depth: glass floats, surfaces sit.
    func surfaceCard(cornerRadius: CGFloat = 18, hairline: Bool = true) -> some View {
        self
            .background(AppColor.card, in: .rect(cornerRadius: cornerRadius))
            .overlay {
                if hairline {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(AppColor.separator.opacity(0.5), lineWidth: 0.5)
                }
            }
    }
}

/// Colors assigned to participants for their timeline initial.
enum ParticipantColors {
    /// The baby's own avatar tint (feed teal) for the monogram fallback.
    static let babyHex = "5AC8B8"

    static let palette: [String] = [
        "5AC8B8", // teal
        "8E8EFF", // periwinkle
        "F5B971", // amber
        "FF8FA3", // pink
        "7FB2FF", // blue
        "B6E36B", // green
    ]

    /// Next color not already used, falling back to cycling the palette.
    static func next(avoiding used: [String]) -> String {
        palette.first { !used.contains($0) } ?? palette[used.count % palette.count]
    }
}
