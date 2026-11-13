import SwiftUI

/// The sky outside, as Home's background in the light appearance: a sky
/// gradient that reaches about halfway down the screen, the sun (or, at
/// night, a crescent moon and stars) where it really is in the sky, a few
/// soft clouds by day, and three rolling hills along the bottom edge. The
/// colours follow the light outside — pale peach at sunrise, blue by day,
/// lavender at sunset, indigo at night — by the real sunrise and sunset for
/// `location` (`SolarClock`), so a winter dusk comes at a winter hour.
///
/// Cards and text sit in front of it as they sit on any page; it is ground,
/// not a surface. The dark appearance keeps the plain ground
/// (`AppColor.bg`). Plain `AppColor.bg` under Reduce Transparency and
/// Increase Contrast. Hidden from VoiceOver, never takes a touch. Fills the
/// whole display by itself.
struct SkyBackground: View {
    /// Where the sky is, for sunrise and sunset; nil falls back to the time
    /// zone's own meridian (`SolarClock.approximateLocation`).
    var location: (latitude: Double, longitude: Double)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if colorScheme == .dark || reduceTransparency || contrast == .increased {
                AppColor.bg
            } else {
                TimelineView(.everyMinute) { ctx in
                    SkyScene(scene: SkyPalette.scene(at: max(ctx.date, .now), location: location))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One frame of the sky, drawn at whatever size it is given.
private struct SkyScene: View {
    let scene: SkyPalette.Scene

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    stops: [.init(color: scene.top.color, location: 0),
                            .init(color: scene.top.mixed(with: SkyPalette.page, by: 0.45).color, location: 0.3),
                            .init(color: SkyPalette.page.color, location: 0.62)],
                    startPoint: .top, endPoint: .bottom)

                if scene.isNight {
                    stars(in: size)
                    moon
                        .position(x: scene.body.x * size.width, y: scene.body.y * size.height)
                } else {
                    sun
                        .position(x: scene.body.x * size.width, y: scene.body.y * size.height)
                    clouds(in: size)
                        .opacity(scene.cloudOpacity)
                }

                hills(in: size)
            }
            .frame(width: size.width, height: size.height)
        }
    }

    private var sun: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [scene.sun.color.opacity(0.75), scene.sun.color.opacity(0.25),
                                              scene.sun.color.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: 210))
                .frame(width: 420, height: 420)
            Circle()
                .fill(scene.sun.color)
                .frame(width: 60, height: 60)
                .shadow(color: scene.sun.color.opacity(0.9), radius: 20)
        }
    }

    private var moon: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [AppColor.nightlightCream.opacity(0.55),
                                              AppColor.nightlightCream.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: 150))
                .frame(width: 300, height: 300)
            Circle()
                .fill(AppColor.nightlightCream)
                .frame(width: 44, height: 44)
                .shadow(color: AppColor.nightlightCream.opacity(0.9), radius: 12)
            // The crescent: the sky's own colour over most of the disc.
            Circle()
                .fill(scene.top.color)
                .frame(width: 40, height: 40)
                .offset(x: 14, y: -8)
        }
    }

    private func stars(in size: CGSize) -> some View {
        ForEach(SkyPalette.stars.indices, id: \.self) { index in
            let star = SkyPalette.stars[index]
            Circle()
                .fill(Color.white.opacity(star.alpha))
                .frame(width: star.size, height: star.size)
                .position(x: star.x * size.width, y: star.y * size.height)
        }
    }

    private func clouds(in size: CGSize) -> some View {
        ForEach(SkyPalette.clouds.indices, id: \.self) { index in
            let cloud = SkyPalette.clouds[index]
            Ellipse()
                .fill(RadialGradient(colors: [Color.white.opacity(0.75), Color.white.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: cloud.width / 2))
                .frame(width: cloud.width, height: cloud.width * 0.28)
                .position(x: cloud.x * size.width, y: cloud.y * size.height)
        }
    }

    private func hills(in size: CGSize) -> some View {
        let height = size.height * 0.22
        return ZStack(alignment: .bottom) {
            ForEach(scene.hills.indices, id: \.self) { index in
                HillShape(layer: index)
                    .fill(scene.hills[index].color)
            }
        }
        .frame(width: size.width, height: height)
        .opacity(0.85)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

/// One of the three rolling hills along the bottom edge, back to front.
private struct HillShape: Shape {
    let layer: Int

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        // (start, control 1, control 2, mid, control 3 (mirrored), end) heights
        let profile: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (0.45, 0.10, 0.55, 0.30, 0.05, 0.35),
            (0.70, 0.40, 0.85, 0.55, 0.40, 0.62),
            (0.90, 0.70, 1.00, 0.80, 0.78, 0.85),
        ]
        let p = profile[min(max(layer, 0), profile.count - 1)]
        var path = Path()
        path.move(to: CGPoint(x: 0, y: h * p.0))
        path.addCurve(to: CGPoint(x: w * 0.55, y: h * p.3),
                      control1: CGPoint(x: w * 0.18, y: h * p.1),
                      control2: CGPoint(x: w * 0.36, y: h * p.2))
        path.addCurve(to: CGPoint(x: w, y: h * p.5),
                      control1: CGPoint(x: w * 0.74, y: h * (2 * p.3 - p.2)),
                      control2: CGPoint(x: w * 0.85, y: h * p.4))
        path.addLine(to: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: 0, y: h))
        path.closeSubpath()
        return path
    }
}

/// The sky's colours and where its sun goes, through the day. Pure, so it
/// is unit-tested (`SkyPaletteTests`).
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

        /// From 0xRRGGBB.
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

    /// One keyframe of the day: the sky at the top of the screen, the sun's
    /// colour, and the three hills, back to front.
    struct Look {
        let top: RGB
        let sun: RGB
        let hills: [RGB]

        func mixed(with other: Look, by t: Double) -> Look {
            Look(top: top.mixed(with: other.top, by: t),
                 sun: sun.mixed(with: other.sun, by: t),
                 hills: zip(hills, other.hills).map { $0.mixed(with: $1, by: t) })
        }
    }

    private static let night = Look(top: RGB(hex: 0x8E96D0), sun: RGB(hex: 0xFFF4E8),
                                    hills: [RGB(hex: 0xC2C5E3), RGB(hex: 0xAEB3D9), RGB(hex: 0x9CA2CF)])
    private static let dawn = Look(top: RGB(hex: 0xF6B993), sun: RGB(hex: 0xFFB07A),
                                   hills: [RGB(hex: 0xEBCFD6), RGB(hex: 0xDDC3D6), RGB(hex: 0xCDB8D3)])
    private static let day = Look(top: RGB(hex: 0x9CC8F2), sun: RGB(hex: 0xFFF3C4),
                                  hills: [RGB(hex: 0xCFE4DA), RGB(hex: 0xBCD9CD), RGB(hex: 0xA9CDC0)])
    private static let dusk = Look(top: RGB(hex: 0xB7A2EA), sun: RGB(hex: 0xFF9478),
                                   hills: [RGB(hex: 0xD9C3E4), RGB(hex: 0xC9B1DC), RGB(hex: 0xB7A1D2)])

    /// The day's looks against its own light: 0 at sunrise, 1 at sunset.
    static let dayFrames: [(at: Double, look: Look)] = [
        (0, dawn), (0.18, day), (0.82, day), (1, dusk),
    ]
    /// The night's: 0 at sunset, 1 at the next sunrise.
    static let nightFrames: [(at: Double, look: Look)] = [
        (0, dusk), (0.12, night), (0.88, night), (1, dawn),
    ]

    static func look(at progress: Double, in frames: [(at: Double, look: Look)]) -> Look {
        let p = min(max(progress, 0), 1)
        for index in 0..<(frames.count - 1) where p <= frames[index + 1].at {
            let a = frames[index], b = frames[index + 1]
            let span = b.at - a.at
            return a.look.mixed(with: b.look, by: span > 0 ? (p - a.at) / span : 0)
        }
        return frames[frames.count - 1].look
    }

    /// Where the sun (or moon) sits, as fractions of the screen: low on the
    /// left as it rises, highest — just peeking over the top edge — at its
    /// noon, low on the right as it sets.
    static func bodyPosition(progress: Double) -> (x: Double, y: Double) {
        let p = min(max(progress, 0), 1)
        return (x: 0.04 + 0.92 * p, y: 0.30 - 0.30 * sin(Double.pi * p))
    }

    /// Everything one frame of the sky needs.
    struct Scene {
        let top: RGB
        let sun: RGB
        let hills: [RGB]
        let isNight: Bool
        let body: (x: Double, y: Double)
        /// Clouds are a daytime thing: faded in after sunrise, out before sunset.
        let cloudOpacity: Double
    }

    static func scene(at date: Date, location: (latitude: Double, longitude: Double)?,
                      calendar: Calendar = .current) -> Scene {
        let place = location ?? SolarClock.approximateLocation(at: date)
        let solar = SolarClock.day(containing: date, latitude: place.latitude,
                                   longitude: place.longitude, calendar: calendar)
            ?? fallbackDay(containing: date, calendar: calendar)
        switch SolarClock.phase(at: date, in: solar) {
        case .day(let p):
            let look = look(at: p, in: dayFrames)
            return Scene(top: look.top, sun: look.sun, hills: look.hills, isNight: false,
                         body: bodyPosition(progress: p),
                         cloudOpacity: min(1, min(p, 1 - p) / 0.1))
        case .night(let q):
            let look = look(at: q, in: nightFrames)
            return Scene(top: look.top, sun: look.sun, hills: look.hills, isNight: true,
                         body: bodyPosition(progress: q), cloudOpacity: 0)
        }
    }

    /// Where the sun neither rises nor sets: a plain 6:45-to-6:15 day.
    private static func fallbackDay(containing date: Date, calendar: Calendar) -> SolarClock.Day {
        let start = calendar.startOfDay(for: date)
        return SolarClock.Day(sunrise: start.addingTimeInterval(6.75 * 3600),
                              sunset: start.addingTimeInterval(18.25 * 3600))
    }

    /// Fixed stars (fractions of the screen; the top third), so they don't
    /// jump between frames.
    static let stars: [(x: Double, y: Double, size: CGFloat, alpha: Double)] = [
        (0.06, 0.05, 1.6, 0.9), (0.14, 0.18, 1.2, 0.7), (0.22, 0.09, 2.2, 0.85),
        (0.31, 0.24, 1.2, 0.6), (0.38, 0.04, 1.6, 0.8), (0.46, 0.15, 1.2, 0.65),
        (0.55, 0.07, 2.2, 0.9), (0.61, 0.21, 1.6, 0.7), (0.69, 0.12, 1.2, 0.75),
        (0.76, 0.03, 1.6, 0.85), (0.83, 0.19, 2.2, 0.7), (0.91, 0.08, 1.2, 0.8),
        (0.95, 0.26, 1.6, 0.6), (0.11, 0.29, 1.2, 0.55), (0.50, 0.30, 1.2, 0.55),
    ]

    /// A few wisps of cloud (fractions of the screen; width in points).
    static let clouds: [(x: Double, y: Double, width: CGFloat)] = [
        (0.22, 0.13, 220), (0.48, 0.23, 170), (0.80, 0.19, 240),
    ]
}
