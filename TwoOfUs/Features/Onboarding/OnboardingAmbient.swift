import SwiftUI

/// One stop of the onboarding's ambient backdrop: a base layer plus two big,
/// soft accent washes. Every page re-tints the *same* two washes, so page
/// changes play as smooth color shifts — never a background swap.
struct AmbientStop: Equatable {
    /// The "night stage" mood (welcome / join hello — the mark's home): warmer,
    /// asymmetric washes and a scatter of stars in dark mode. The base stays the
    /// scheme background, so the scene still follows the appearance toggle — the
    /// `CradleMark` carries its own scheme-aware spotlight (see `CradleMark.staged`).
    var darkStage = false
    /// Tones the washes down (setup chapter: calmer, content leads).
    var subtle = false
    /// Upper-leading wash color.
    var top: Color
    /// Lower-trailing wash color.
    var bottom: Color
}

extension AmbientStop {
    /// The dark stage the `CradleMark` sits on, in both color schemes — lavender
    /// night sky up top, the baby light's lamp-warmth pooling low. Page
    /// transitions away from it play as a gentle sunrise into the scheme palette.
    /// (Both colors are deliberately softer/warmer than the raw accents: this is
    /// a nursery at night, not a brand hero.)
    static let nightStage = AmbientStop(
        darkStage: true,
        top: Color(hex: "A99BEC"),    // accentSleep desaturated toward lavender
        bottom: Color(hex: "FFE6C7")  // nightlight cream pushed toward lamp amber
    )
}

/// The shared backdrop behind every onboarding/join page. Lives *outside* the
/// pager so swipes never move it; re-tints with an easeInOut when the stop
/// changes. The dark stage is its own full layer animated by opacity (a plain
/// color interpolation across that much luminance can shortcut through gray).
struct AmbientBackground: View {
    let stop: AmbientStop
    @Environment(\.colorScheme) private var scheme

    // On the dark stage the washes carry different weight on purpose: the warm
    // bottom wash (the nightlight) pools visibly low while the cool top wash
    // recedes. Everywhere else they stay symmetric.
    private var topWashOpacity: Double {
        var base = stop.darkStage ? 0.14 : (scheme == .dark ? 0.18 : 0.12)
        if stop.subtle { base *= 0.6 }
        return base
    }

    private var bottomWashOpacity: Double {
        var base = stop.darkStage ? 0.30 : (scheme == .dark ? 0.18 : 0.12)
        if stop.subtle { base *= 0.6 }
        return base
    }

    var body: some View {
        // The base follows the appearance toggle — no forced near-black. The
        // night stage's depth comes from the warm washes and (in dark mode) the
        // stars; the mark brings its own spotlight where it needs one.
        AppColor.bg
        // The washes live in an overlay so their big blurred frames never
        // contribute to layout — the backdrop always reports exactly the
        // proposed size (an oversized sibling here inflates the whole pager).
        .overlay {
            ZStack {
                Circle()
                    .fill(stop.top)
                    .frame(width: 560, height: 560)
                    .blur(radius: 120)
                    .offset(x: -130, y: -280)
                    .opacity(topWashOpacity)
                Circle()
                    .fill(stop.bottom)
                    .frame(width: 500, height: 500)
                    .blur(radius: 110)
                    .offset(x: 150, y: 320)
                    .opacity(bottomWashOpacity)
                // Stars only read on a genuinely dark base, so keep them to dark
                // mode — in light mode the cream points would vanish on the bg.
                NightStars()
                    .opacity(stop.darkStage && scheme == .dark ? 1 : 0)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.5), value: stop)
        .accessibilityHidden(true)
    }
}

/// A sparse, static scatter of faint star points for the dark stage. Hand-placed
/// in unit coordinates: denser in the upper "sky", clear of the mark's center
/// and the warm pool low. Deliberately no twinkle — calm, Reduce Motion safe,
/// and free at render time (the host fades the whole layer with `darkStage`).
private struct NightStars: View {
    private struct Star {
        let x: CGFloat      // unit position
        let y: CGFloat
        let size: CGFloat   // point diameter
        let opacity: Double
        var halo: Bool { size >= 2.5 }
    }

    private static let stars: [Star] = [
        Star(x: 0.12, y: 0.08, size: 2.0, opacity: 0.22),
        Star(x: 0.30, y: 0.14, size: 1.5, opacity: 0.14),
        Star(x: 0.55, y: 0.06, size: 2.5, opacity: 0.26),
        Star(x: 0.78, y: 0.11, size: 1.5, opacity: 0.16),
        Star(x: 0.90, y: 0.20, size: 2.0, opacity: 0.20),
        Star(x: 0.07, y: 0.24, size: 1.5, opacity: 0.12),
        Star(x: 0.42, y: 0.20, size: 1.5, opacity: 0.10),
        Star(x: 0.68, y: 0.26, size: 2.0, opacity: 0.18),
        Star(x: 0.16, y: 0.40, size: 2.5, opacity: 0.28),
        Star(x: 0.88, y: 0.42, size: 1.5, opacity: 0.13),
        Star(x: 0.06, y: 0.58, size: 2.0, opacity: 0.16),
        Star(x: 0.93, y: 0.60, size: 2.5, opacity: 0.24),
    ]

    var body: some View {
        GeometryReader { geo in
            ForEach(Self.stars.indices, id: \.self) { i in
                let star = Self.stars[i]
                Circle()
                    .fill(AppColor.nightlightCream)
                    .frame(width: star.size, height: star.size)
                    .background {
                        // The few larger stars get a soft halo so one or two
                        // points feel near, the rest far.
                        if star.halo {
                            Circle()
                                .fill(AppColor.nightlightCream)
                                .frame(width: star.size * 3, height: star.size * 3)
                                .blur(radius: 2)
                                .opacity(0.5)
                        }
                    }
                    .opacity(star.opacity)
                    .position(x: star.x * geo.size.width,
                              y: star.y * geo.size.height)
            }
        }
    }
}

#Preview("Night stage") {
    AmbientBackground(stop: .nightStage)
}

#Preview("Teal · light") {
    AmbientBackground(stop: AmbientStop(top: AppColor.accentFeed, bottom: AppColor.accentDiaper))
}

#Preview("Subtle · dark") {
    AmbientBackground(stop: AmbientStop(subtle: true, top: AppColor.accentFeed, bottom: AppColor.accentSleep))
        .preferredColorScheme(.dark)
}
