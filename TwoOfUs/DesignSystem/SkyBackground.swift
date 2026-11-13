import SwiftUI

/// The sky outside, as Home's background in the light appearance: a soft
/// gradient from the top of the screen whose colour follows the time of day —
/// pale peach at dawn, clean blue-white at midday, lavender at dusk, a quiet
/// lavender-grey through the night — fading into the page colour two-thirds
/// of the way down, so cards and text always sit on the plain page.
///
/// The dark appearance keeps the plain ground (`AppColor.bg`): the night ink
/// and the hinge light already belong to it. Never an urgency colour, never
/// a jump: the colour moves a little each minute. Plain `AppColor.bg` under
/// Reduce Transparency and Increase Contrast. Decoration only — hidden from
/// VoiceOver, never takes a touch. Fills the whole display by itself.
struct SkyBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if colorScheme == .dark || reduceTransparency || contrast == .increased {
                AppColor.bg
            } else {
                TimelineView(.everyMinute) { ctx in
                    let top = SkyPalette.top(at: max(ctx.date, .now))
                    LinearGradient(
                        stops: [.init(color: top.color, location: 0),
                                .init(color: top.mixed(with: SkyPalette.page, by: 0.5).color, location: 0.34),
                                .init(color: SkyPalette.page.color, location: 0.68)],
                        startPoint: .top, endPoint: .bottom)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The sky's colour at the top of the screen, through the day: a few
/// keyframes on the wall clock, blended in between. Pure, so it is
/// unit-tested (`SkyPaletteTests`).
enum SkyPalette {
    struct RGB: Equatable {
        var red: Double
        var green: Double
        var blue: Double

        init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        /// From "RRGGBB".
        init(hex: UInt32) {
            red = Double((hex >> 16) & 0xFF) / 255
            green = Double((hex >> 8) & 0xFF) / 255
            blue = Double(hex & 0xFF) / 255
        }

        func mixed(with other: RGB, by fraction: Double) -> RGB {
            let t = min(max(fraction, 0), 1)
            return RGB(red: red + (other.red - red) * t,
                       green: green + (other.green - green) * t,
                       blue: blue + (other.blue - blue) * t)
        }

        var color: Color { Color(red: red, green: green, blue: blue) }
    }

    /// The light page colour every gradient fades into (`AppColor.bg`, light).
    static let page = RGB(hex: 0xF2F2F7)

    /// (minute of day, colour at the top of the screen), in order.
    static let keyframes: [(minute: Int, top: RGB)] = [
        (0, RGB(hex: 0xDCDDEF)),          // night: quiet lavender-grey
        (5 * 60, RGB(hex: 0xE2DDF0)),
        (6 * 60 + 30, RGB(hex: 0xFBE4D6)), // dawn: pale peach
        (9 * 60, RGB(hex: 0xE8EEF7)),
        (12 * 60, RGB(hex: 0xD9E9FA)),    // midday: clean blue-white
        (16 * 60, RGB(hex: 0xE3ECF7)),
        (18 * 60, RGB(hex: 0xE3D9F6)),    // dusk: lavender
        (19 * 60 + 30, RGB(hex: 0xF0DDE6)), // the last rose of it
        (22 * 60, RGB(hex: 0xDCDDEF)),
    ]

    /// The colour at the top of the screen at `minute` (0..<1440, wrapping).
    static func top(atMinute minute: Int) -> RGB {
        let m = ((minute % 1440) + 1440) % 1440
        for (index, frame) in keyframes.enumerated() {
            let next = index + 1 < keyframes.count
                ? keyframes[index + 1]
                : (minute: keyframes[0].minute + 1440, top: keyframes[0].top)
            if m >= frame.minute && m < next.minute {
                let span = Double(next.minute - frame.minute)
                return frame.top.mixed(with: next.top, by: Double(m - frame.minute) / span)
            }
        }
        return keyframes[0].top
    }

    static func top(at date: Date, calendar: Calendar = .current) -> RGB {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return top(atMinute: (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }
}
