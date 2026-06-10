import SwiftUI

/// One stop of the onboarding's ambient backdrop: a base layer plus two big,
/// soft accent washes. Every page re-tints the *same* two washes, so page
/// changes play as smooth color shifts — never a background swap.
struct AmbientStop: Equatable {
    /// Near-black "night stage" base (welcome / join hello — the mark's home)
    /// instead of the scheme background.
    var darkStage = false
    /// Tones the washes down (setup chapter: calmer, content leads).
    var subtle = false
    /// Upper-leading wash color.
    var top: Color
    /// Lower-trailing wash color.
    var bottom: Color
}

extension AmbientStop {
    /// The dark stage the `CradleMark` sits on, in both color schemes — periwinkle
    /// up top, the baby light's warmth pooling low. Page transitions away from it
    /// play as a gentle sunrise into the scheme palette.
    static let nightStage = AmbientStop(
        darkStage: true,
        top: AppColor.accentSleep,
        bottom: Color(red: 1.0, green: 0.957, blue: 0.910) // #FFF4E8
    )
}

/// The shared backdrop behind every onboarding/join page. Lives *outside* the
/// pager so swipes never move it; re-tints with an easeInOut when the stop
/// changes. The dark stage is its own full layer animated by opacity (a plain
/// color interpolation across that much luminance can shortcut through gray).
struct AmbientBackground: View {
    let stop: AmbientStop
    @Environment(\.colorScheme) private var scheme

    private var washOpacity: Double {
        var base = stop.darkStage ? 0.16 : (scheme == .dark ? 0.18 : 0.12)
        if stop.subtle { base *= 0.6 }
        return base
    }

    var body: some View {
        ZStack {
            AppColor.bg
            Color(hex: "070710")
                .opacity(stop.darkStage ? 1 : 0)
        }
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
                    .opacity(washOpacity)
                Circle()
                    .fill(stop.bottom)
                    .frame(width: 500, height: 500)
                    .blur(radius: 110)
                    .offset(x: 150, y: 320)
                    .opacity(washOpacity)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.5), value: stop)
        .accessibilityHidden(true)
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
