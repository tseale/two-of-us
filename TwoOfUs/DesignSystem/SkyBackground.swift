import SwiftUI

/// The sky outside, as Home's background in the light appearance: a sky
/// gradient that reaches about halfway down the screen, the sun (or, at
/// night, a crescent moon and stars) where it really is in the sky, a few
/// soft cumulus clouds by day, and four layers of hills along the bottom
/// edge that melt into valley mist rather than meeting at outlines. The
/// colours follow the light outside — a blush at sunrise, blue by day,
/// lilac at sunset, periwinkle at night — by the real sunrise and sunset for
/// `location` (`SolarClock`), so a winter dusk comes at a winter hour.
///
/// It is hushed on purpose: every colour keeps its hue at a fifth of its
/// strength and sits close to the page's own grey, the sun's glow and the
/// clouds are faint, so the app's teal, amber and lavender always lead. By
/// night it is a shade deeper, and the stars come out over the first hour
/// after sunset, twinkle, and a few brighter glints slowly pulse and turn
/// (still under Reduce Motion).
///
/// Nothing in it has a hard edge: the sun is a soft disc in a bloom, the
/// clouds are painted textures (`SkyCloud*`, lit separately for dawn, day
/// and dusk and crossfaded between them), each hill is blurred a little —
/// the far ones more — and a fine grain (`SkyGrain`) keeps the gradients
/// from banding.
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
            let orb = CGPoint(x: scene.body.x * size.width, y: scene.body.y * size.height)
            ZStack(alignment: .topLeading) {
                sky(in: size, orb: orb)

                if scene.isNight {
                    StarField(size: size, visibility: scene.starOpacity)
                    moon
                        .position(orb)
                } else {
                    sun
                        .position(orb)
                    clouds(in: size)
                        .opacity(scene.cloudOpacity)
                }

                hills(in: size)

                Image("SkyGrain")
                    .resizable(resizingMode: .tile)
                    .blendMode(.softLight)
                    .opacity(0.3)
            }
            .frame(width: size.width, height: size.height)
        }
    }

    // MARK: Sky

    /// The gradient (sky at the top, the page in the middle, the haze the
    /// hills stand in at the bottom), a warm pool of light around the sun or
    /// moon, and the sun's bloom.
    private func sky(in size: CGSize, orb: CGPoint) -> some View {
        let look = scene.look
        let page = SkyPalette.page
        let reach = max(size.width, size.height)
        let centre = UnitPoint(x: size.width > 0 ? orb.x / size.width : 0.5,
                               y: size.height > 0 ? orb.y / size.height : 0)
        return ZStack(alignment: .topLeading) {
            LinearGradient(
                stops: [.init(color: look.top.color, location: 0),
                        .init(color: look.top.mixed(with: look.mid, by: 0.55).color, location: 0.15),
                        .init(color: look.mid.color, location: 0.33),
                        .init(color: look.mid.mixed(with: page, by: 0.6).color, location: 0.46),
                        .init(color: page.color, location: 0.56),
                        .init(color: page.mixed(with: look.haze, by: 0.6).color, location: 0.66),
                        .init(color: look.haze.color, location: 0.74),
                        .init(color: look.haze.color, location: 1)],
                startPoint: .top, endPoint: .bottom)

            pool(look.warm, alpha: 0.45 * SkyPalette.glow, at: orb, rx: size.width * 0.7, ry: size.height * 0.36)

            if scene.isNight {
                RadialGradient(
                    stops: [.init(color: AppColor.nightlightCream.opacity(0.4), location: 0),
                            .init(color: AppColor.nightlightCream.opacity(0.12), location: 0.35),
                            .init(color: AppColor.nightlightCream.opacity(0), location: 1)],
                    center: centre, startRadius: 0, endRadius: reach * 0.25)
            } else {
                RadialGradient(
                    stops: [.init(color: look.sun.color.opacity(0.55 * SkyPalette.glow), location: 0),
                            .init(color: look.sun.color.opacity(0.25 * SkyPalette.glow), location: 0.12),
                            .init(color: look.sun.color.opacity(0.1 * SkyPalette.glow), location: 0.3),
                            .init(color: look.sun.color.opacity(0), location: 0.6)],
                    center: centre, startRadius: 0, endRadius: reach * 0.5)
            }
        }
    }

    /// A soft elliptical pool of colour centred on `point`: `color` at
    /// `alpha` in the middle, fading to nothing at radii `rx` × `ry`.
    private func pool(_ color: SkyPalette.RGB, alpha: Double, at point: CGPoint,
                      rx: CGFloat, ry: CGFloat) -> some View {
        let radius = max(rx, 1)
        return Circle()
            .fill(RadialGradient(colors: [color.color.opacity(alpha), color.color.opacity(0)],
                                 center: .center, startRadius: 0, endRadius: radius))
            .frame(width: radius * 2, height: radius * 2)
            .scaleEffect(x: 1, y: max(ry, 1) / radius)
            .position(point)
    }

    /// A soft disc — bright core, no rim — glowing into the bloom.
    private var sun: some View {
        let look = scene.look
        return Circle()
            .fill(RadialGradient(
                stops: [.init(color: look.core.color, location: 0),
                        .init(color: look.core.color, location: 0.42),
                        .init(color: look.sun.color.opacity(0.95), location: 0.72),
                        .init(color: look.sun.color.opacity(0), location: 1)],
                center: .center, startRadius: 0, endRadius: 23))
            .frame(width: 46, height: 46)
            .shadow(color: look.sun.color.opacity(0.55), radius: 17)
    }

    /// A crescent cut out of a cream disc (so the sky, whatever its colour,
    /// shows through the dark part), with a soft glow.
    private var moon: some View {
        Circle()
            .fill(AppColor.nightlightCream)
            .frame(width: 32, height: 32)
            .overlay {
                Circle()
                    .frame(width: 32, height: 32)
                    .offset(x: -10, y: 3)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
            .shadow(color: AppColor.nightlightCream.opacity(0.85), radius: 9)
    }

    // MARK: Clouds

    private func clouds(in size: CGSize) -> some View {
        let wide = size.width > SkyPalette.wideLayoutWidth
        let wisps = SkyPalette.wisps(wide: wide)
        let clouds = SkyPalette.clouds(wide: wide)
        return ZStack(alignment: .topLeading) {
            ForEach(wisps.indices, id: \.self) { index in
                let wisp = wisps[index]
                cloudImage(SkyPalette.wispArt, width: wisp.width)
                    .opacity(wisp.alpha * SkyPalette.cloudStrength)
                    .position(x: wisp.x * size.width, y: wisp.y * size.height)
            }
            ForEach(clouds.indices, id: \.self) { index in
                let cloud = clouds[index]
                let art = SkyPalette.cloudArt[cloud.art]
                // `y` is where the cloud's flat base sits: 84 % down its texture.
                cloudImage(art, width: cloud.width)
                    .opacity(SkyPalette.cloudStrength)
                    .scaleEffect(x: cloud.flipped ? -1 : 1, y: 1)
                    .position(x: cloud.x * size.width,
                              y: cloud.y * size.height - cloud.width * art.aspect * 0.34)
            }
        }
    }

    /// One cloud texture, crossfaded between its dawn, day and dusk lighting
    /// by the scene's light. The weights sum to one and the three textures
    /// share one silhouette, so adding them (`plusLighter`) is an exact
    /// crossfade that never thins the cloud mid-way.
    private func cloudImage(_ art: SkyPalette.CloudArt, width: CGFloat) -> some View {
        let light = scene.look.light
        return ZStack {
            Image(art.dawn)
                .resizable()
                .opacity(light.dawn)
            Image(art.day)
                .resizable()
                .opacity(light.day)
                .blendMode(.plusLighter)
            Image(art.dusk)
                .resizable()
                .opacity(light.dusk)
                .blendMode(.plusLighter)
        }
        .compositingGroup()
        .frame(width: width, height: width * art.aspect)
    }

    // MARK: Hills

    /// Four ridges, back to front. Each is darkest at its crest and dissolves
    /// into the valley mist below it, and each is blurred a little — the far
    /// ones more — so the layers read by tone, not by outline.
    private func hills(in size: CGSize) -> some View {
        let look = scene.look
        let height = max(Double(size.height), 1)
        let ridges = SkyPalette.ridges
        return ZStack(alignment: .topLeading) {
            ForEach(ridges.indices, id: \.self) { index in
                let ridge = ridges[index]
                let crest = look.hills[index]
                let isFront = index == ridges.count - 1
                let foot = isFront ? look.deep : crest.mixed(with: look.haze, by: 0.5)
                let footY = isFront ? height : ridges[index + 1].baseline(height: height) + 6
                RidgeShape(ridge: ridge)
                    .fill(LinearGradient(
                        colors: [crest.color, foot.color],
                        startPoint: UnitPoint(x: 0.5, y: ridge.crestTop(height: height) / height),
                        endPoint: UnitPoint(x: 0.5, y: footY / height)))
                    .blur(radius: ridge.blur)
                if !isFront {
                    mist(centreY: ridges[index + 1].baseline(height: height) - 9, width: size.width)
                }
            }
        }
    }

    /// A soft band of valley mist just above the next ridge's crest.
    private func mist(centreY: Double, width: CGFloat) -> some View {
        let mist = scene.look.mist.color
        let alpha = scene.look.mistAlpha
        return LinearGradient(
            stops: [.init(color: mist.opacity(0), location: 0),
                    .init(color: mist.opacity(alpha), location: 0.55),
                    .init(color: mist.opacity(0), location: 1)],
            startPoint: .top, endPoint: .bottom)
            .frame(width: width + 40, height: 54)
            .blur(radius: 6)
            .position(x: width / 2, y: centreY)
    }
}

/// The night's stars: most twinkle slowly, out of step with one another, and
/// a few brighter four-point glints pulse and turn, where the screen's own
/// sky shows. Animated on its own timeline (only at night, only while it is
/// on screen); held still under Reduce Motion. `visibility` fades the whole
/// field in after sunset and out before sunrise.
private struct StarField: View {
    let size: CGSize
    let visibility: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            field(at: nil)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 24)) { context in
                field(at: context.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    /// One frame; `time` nil draws the stars still (full brightness, glints
    /// part-way open).
    private func field(at time: TimeInterval?) -> some View {
        let stars = SkyPalette.stars(width: size.width)
        let glints = SkyPalette.glints(wide: size.width > SkyPalette.wideLayoutWidth)
        return ZStack(alignment: .topLeading) {
            ForEach(stars.indices, id: \.self) { index in
                let star = stars[index]
                let twinkle = time.map { SkyPalette.twinkle(star, at: $0) } ?? 1
                Circle()
                    .fill(Color.white)
                    .frame(width: star.size, height: star.size)
                    .shadow(color: Color.white.opacity(0.9), radius: star.size > 2 ? 2.5 : 1)
                    .opacity(star.alpha * twinkle * visibility)
                    .position(x: star.x * size.width, y: star.y * size.height)
            }
            ForEach(glints.indices, id: \.self) { index in
                let glint = glints[index]
                let sparkle = time.map { SkyPalette.sparkle(glint, at: $0) } ?? 0.6
                GlintShape()
                    .fill(SkyPalette.glintColor.color)
                    .frame(width: glint.size, height: glint.size)
                    .scaleEffect(CGFloat(0.45 + 0.55 * sparkle))
                    .rotationEffect(.degrees(25 * sparkle))
                    .shadow(color: SkyPalette.glintColor.color.opacity(0.95), radius: 2)
                    .shadow(color: AppColor.nightlightCream.opacity(0.7), radius: 6)
                    .opacity((0.3 + 0.7 * sparkle) * visibility)
                    .position(x: glint.x * size.width, y: glint.y * size.height)
            }
        }
    }
}

/// A four-point star: long thin rays meeting at a small waist.
private struct GlintShape: Shape {
    func path(in rect: CGRect) -> Path {
        let corners: [(CGFloat, CGFloat)] = [(0.5, 0), (0.56, 0.44), (1, 0.5), (0.56, 0.56),
                                             (0.5, 1), (0.44, 0.56), (0, 0.5), (0.44, 0.44)]
        var path = Path()
        for (index, corner) in corners.enumerated() {
            let point = CGPoint(x: rect.minX + corner.0 * rect.width, y: rect.minY + corner.1 * rect.height)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

/// One ridge of hills, filled down to (and past) the bottom edge.
private struct RidgeShape: Shape {
    let ridge: SkyPalette.Ridge

    func path(in rect: CGRect) -> Path {
        let points = ridge.points(width: Double(rect.width), height: Double(rect.height))
        var path = Path()
        guard points.count > 2, let first = points.first, let last = points.last else { return path }
        path.move(to: first)
        // Through the midpoints, with each sample as the control point: a
        // smooth line that never overshoots.
        for index in 1..<(points.count - 1) {
            let point = points[index], next = points[index + 1]
            path.addQuadCurve(to: CGPoint(x: (point.x + next.x) / 2, y: (point.y + next.y) / 2),
                              control: point)
        }
        path.addLine(to: last)
        path.addLine(to: CGPoint(x: rect.width + 30, y: rect.height + 20))
        path.addLine(to: CGPoint(x: -30, y: rect.height + 20))
        path.closeSubpath()
        return path
    }
}

/// The sky's colours, its hills, clouds and stars, and where its sun goes,
/// through the day. Pure, so it is unit-tested (`SkyPaletteTests`).
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

    /// The light page colour the sky fades into (`AppColor.bg`, light).
    static let page = RGB(hex: 0xF2F2F7)

    /// How much of each cloud lighting (dawn, day, dusk) to show. A
    /// keyframe is all of one; between keyframes the weights still sum to 1.
    struct CloudLight: Equatable {
        var dawn: Double
        var day: Double
        var dusk: Double

        static let ofDawn = CloudLight(dawn: 1, day: 0, dusk: 0)
        static let ofDay = CloudLight(dawn: 0, day: 1, dusk: 0)
        static let ofDusk = CloudLight(dawn: 0, day: 0, dusk: 1)

        func mixed(with other: CloudLight, by fraction: Double) -> CloudLight {
            let t = min(max(fraction, 0), 1)
            return CloudLight(dawn: dawn + (other.dawn - dawn) * t,
                              day: day + (other.day - day) * t,
                              dusk: dusk + (other.dusk - dusk) * t)
        }
    }

    /// One keyframe of the day: the sky at the top and in the middle, the
    /// sun's colour and its core, the warm pool around it, the haze the hills
    /// stand in, the valley mist, the four hills' crests (back to front) and
    /// the front hill's foot, and which lighting the clouds wear.
    struct Look {
        let top: RGB
        let mid: RGB
        let sun: RGB
        let core: RGB
        let warm: RGB
        let haze: RGB
        let mist: RGB
        let mistAlpha: Double
        let hills: [RGB]
        let deep: RGB
        let light: CloudLight

        func mixed(with other: Look, by fraction: Double) -> Look {
            let t = min(max(fraction, 0), 1)
            return Look(top: top.mixed(with: other.top, by: t),
                        mid: mid.mixed(with: other.mid, by: t),
                        sun: sun.mixed(with: other.sun, by: t),
                        core: core.mixed(with: other.core, by: t),
                        warm: warm.mixed(with: other.warm, by: t),
                        haze: haze.mixed(with: other.haze, by: t),
                        mist: mist.mixed(with: other.mist, by: t),
                        mistAlpha: mistAlpha + (other.mistAlpha - mistAlpha) * t,
                        hills: zip(hills, other.hills).map { $0.mixed(with: $1, by: t) },
                        deep: deep.mixed(with: other.deep, by: t),
                        light: light.mixed(with: other.light, by: t))
        }
    }

    /// How strong the sun's glow and warm pool are, against the original
    /// (fully coloured) sky.
    static let glow = 0.32
    /// How opaque the clouds and wisps are.
    static let cloudStrength = 0.8

    // The keyframes, hushed: each colour keeps its hue at a fifth of its
    // chroma (OKLCH) and sits 55 % of the way to the page's lightness (night
    // a little less, so the stars show). Mist stays near white.
    private static let sageHills = [RGB(hex: 0xE4E8EA), RGB(hex: 0xDDE3E2), RGB(hex: 0xD5DDDB), RGB(hex: 0xCED7D3)]

    private static let dawn = Look(
        top: RGB(hex: 0xD3D5DF), mid: RGB(hex: 0xEDE8E9), sun: RGB(hex: 0xDEBEAE), core: RGB(hex: 0xF9F4EF),
        warm: RGB(hex: 0xEFE4DE), haze: RGB(hex: 0xF1EDEC), mist: RGB(hex: 0xFFF0EC), mistAlpha: 0.6,
        hills: [RGB(hex: 0xEBE7EA), RGB(hex: 0xE5E0E4), RGB(hex: 0xDEDAE0), RGB(hex: 0xD8D3DA)],
        deep: RGB(hex: 0xD1CDD5), light: .ofDawn)
    private static let morning = Look(
        top: RGB(hex: 0xCED8E3), mid: RGB(hex: 0xE5E9EE), sun: RGB(hex: 0xF0E6CA), core: RGB(hex: 0xFEFDF8),
        warm: RGB(hex: 0xF4F2E9), haze: RGB(hex: 0xEEF0F2), mist: RGB(hex: 0xFFFFFF), mistAlpha: 0.62,
        hills: sageHills, deep: RGB(hex: 0xC8D2CE), light: .ofDay)
    private static let noon = Look(
        top: RGB(hex: 0xC7D2DF), mid: RGB(hex: 0xE1E7ED), sun: RGB(hex: 0xF4EED8), core: RGB(hex: 0xFFFFFC),
        warm: RGB(hex: 0xF6F4EE), haze: RGB(hex: 0xEEF0F2), mist: RGB(hex: 0xFFFFFF), mistAlpha: 0.62,
        hills: sageHills, deep: RGB(hex: 0xC8D2CE), light: .ofDay)
    private static let dusk = Look(
        top: RGB(hex: 0xCAC8D8), mid: RGB(hex: 0xEAE2E4), sun: RGB(hex: 0xD9B2A4), core: RGB(hex: 0xF5ECE6),
        warm: RGB(hex: 0xEDE0D9), haze: RGB(hex: 0xEEEAEB), mist: RGB(hex: 0xFFECF2), mistAlpha: 0.55,
        hills: [RGB(hex: 0xE8E4E9), RGB(hex: 0xE1DDE3), RGB(hex: 0xDAD5DE), RGB(hex: 0xD2CDD7)],
        deep: RGB(hex: 0xCBC7D2), light: .ofDusk)
    private static let night = Look(
        top: RGB(hex: 0x9C9FAD), mid: RGB(hex: 0xC3C5CE), sun: RGB(hex: 0xFAF5F0), core: RGB(hex: 0xFFFFFF),
        warm: RGB(hex: 0xD3D2DA), haze: RGB(hex: 0xDBDBE1), mist: RGB(hex: 0xDEE0F6), mistAlpha: 0.4,
        hills: [RGB(hex: 0xD1D2D9), RGB(hex: 0xC5C6CF), RGB(hex: 0xB9BBC5), RGB(hex: 0xAEB0BC)],
        deep: RGB(hex: 0xA7A9B5), light: .ofDay)

    /// The day's looks against its own light: 0 at sunrise, 1 at sunset.
    static let dayFrames: [(at: Double, look: Look)] = [
        (0, dawn), (0.18, morning), (0.5, noon), (0.82, morning), (1, dusk),
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
        let look: Look
        let isNight: Bool
        let body: (x: Double, y: Double)
        /// Clouds are a daytime thing: faded in after sunrise, out before sunset.
        let cloudOpacity: Double
        /// Stars are a night thing: out over the first hour after sunset, in
        /// before sunrise (`starOpacity(nightProgress:)`).
        let starOpacity: Double
    }

    static func scene(at date: Date, location: (latitude: Double, longitude: Double)?,
                      calendar: Calendar = .current) -> Scene {
        let place = location ?? SolarClock.approximateLocation(at: date)
        let solar = SolarClock.day(containing: date, latitude: place.latitude,
                                   longitude: place.longitude, calendar: calendar)
            ?? fallbackDay(containing: date, calendar: calendar)
        switch SolarClock.phase(at: date, in: solar) {
        case .day(let p):
            return Scene(look: look(at: p, in: dayFrames), isNight: false,
                         body: bodyPosition(progress: p),
                         cloudOpacity: min(1, min(p, 1 - p) / 0.1), starOpacity: 0)
        case .night(let q):
            return Scene(look: look(at: q, in: nightFrames), isNight: true,
                         body: bodyPosition(progress: q), cloudOpacity: 0,
                         starOpacity: starOpacity(nightProgress: q))
        }
    }

    /// Where the sun neither rises nor sets: a plain 6:45-to-6:15 day.
    private static func fallbackDay(containing date: Date, calendar: Calendar) -> SolarClock.Day {
        let start = calendar.startOfDay(for: date)
        return SolarClock.Day(sunrise: start.addingTimeInterval(6.75 * 3600),
                              sunset: start.addingTimeInterval(18.25 * 3600))
    }

    // MARK: Hills

    /// One ridge line: a baseline (fraction of the screen's height up from
    /// the bottom) with three slow waves on it, so it never visibly repeats.
    /// Frequencies are per 466 pt — the Duo's outer display — so a wider
    /// screen shows more hills rather than stretched ones.
    struct Ridge {
        let base: Double
        let amplitude: Double
        let frequencies: (Double, Double, Double)
        let phases: (Double, Double, Double)
        /// Softening, in points: more for the far ridges.
        let blur: CGFloat

        func y(at x: Double, height: Double) -> Double {
            let k = 2 * Double.pi * x / 466
            let wave = 0.55 * sin(k * frequencies.0 + phases.0)
                + 0.17 * sin(k * frequencies.1 + phases.1)
                + 0.45 * sin(k * frequencies.2 + phases.2)
            return height - base * height + amplitude * height * wave
        }

        func baseline(height: Double) -> Double { height - base * height }

        /// Where the crest colour starts (just under the highest crests).
        func crestTop(height: Double) -> Double { height - base * height - amplitude * height * 0.8 }

        /// Samples every 10 pt, from just past the left edge to just past the right.
        func points(width: Double, height: Double) -> [CGPoint] {
            stride(from: -30.0, through: width + 30, by: 10).map { CGPoint(x: $0, y: y(at: $0, height: height)) }
        }
    }

    /// Back to front.
    static let ridges: [Ridge] = [
        Ridge(base: 0.245, amplitude: 0.022, frequencies: (0.9, 2.3, 0.31), phases: (0.6, 2.1, 0.9), blur: 3.2),
        Ridge(base: 0.195, amplitude: 0.024, frequencies: (0.75, 1.9, 0.38), phases: (2.4, 0.3, 2.6), blur: 2.2),
        Ridge(base: 0.14, amplitude: 0.022, frequencies: (1.1, 2.6, 0.45), phases: (4.1, 1.2, 4.3), blur: 1.5),
        Ridge(base: 0.078, amplitude: 0.016, frequencies: (0.6, 1.7, 0.52), phases: (1.3, 3.3, 6.0), blur: 1.0),
    ]

    // MARK: Clouds

    /// A cloud texture in its three lightings, and its height over its width.
    struct CloudArt {
        let dawn: String
        let day: String
        let dusk: String
        let aspect: CGFloat
    }

    static let cloudArt: [CloudArt] = [
        CloudArt(dawn: "SkyCloud1Dawn", day: "SkyCloud1Day", dusk: "SkyCloud1Dusk", aspect: 388.0 / 700),
        CloudArt(dawn: "SkyCloud2Dawn", day: "SkyCloud2Day", dusk: "SkyCloud2Dusk", aspect: 312.0 / 500),
        CloudArt(dawn: "SkyCloud3Dawn", day: "SkyCloud3Day", dusk: "SkyCloud3Dusk", aspect: 312.0 / 800),
    ]
    static let wispArt = CloudArt(dawn: "SkyWispDawn", day: "SkyWispDay", dusk: "SkyWispDusk", aspect: 150.0 / 800)

    /// A cloud: which texture, where its flat base sits (fractions of the
    /// screen), how wide (points), and whether it is mirrored.
    struct CloudPlacement {
        let art: Int
        let x: Double
        let y: Double
        let width: CGFloat
        let flipped: Bool
    }

    /// A wisp: its centre (fractions of the screen), width, and opacity.
    struct WispPlacement {
        let x: Double
        let y: Double
        let width: CGFloat
        let alpha: Double
    }

    /// Wider than this (the Duo open, an iPad) the sky gets the wide layout.
    static let wideLayoutWidth: CGFloat = 700

    /// Placed where the screen's own sky shows: beside the column of cards
    /// and behind the header on a phone; in the margins and between the
    /// pages on the open Duo.
    static func clouds(wide: Bool) -> [CloudPlacement] {
        wide
            ? [CloudPlacement(art: 0, x: 0.885, y: 0.27, width: 210, flipped: false),
               CloudPlacement(art: 1, x: 0.515, y: 0.12, width: 130, flipped: true),
               CloudPlacement(art: 2, x: 0.06, y: 0.44, width: 240, flipped: false),
               CloudPlacement(art: 1, x: 0.035, y: 0.13, width: 120, flipped: false)]
            : [CloudPlacement(art: 0, x: 0.9, y: 0.27, width: 200, flipped: false),
               CloudPlacement(art: 1, x: 0.66, y: 0.095, width: 132, flipped: true)]
    }

    static func wisps(wide: Bool) -> [WispPlacement] {
        wide
            ? [WispPlacement(x: 0.27, y: 0.05, width: 340, alpha: 0.55),
               WispPlacement(x: 0.5, y: 0.42, width: 220, alpha: 0.45),
               WispPlacement(x: 0.93, y: 0.5, width: 200, alpha: 0.45)]
            : [WispPlacement(x: 0.26, y: 0.045, width: 300, alpha: 0.5),
               WispPlacement(x: 0.92, y: 0.43, width: 190, alpha: 0.5)]
    }

    // MARK: Stars

    /// How much of the starfield shows, `nightProgress` 0 at sunset to 1 at
    /// sunrise: none for the first ~20 minutes, all of it about an hour after
    /// sunset (as the sky darkens), and gone again by sunrise.
    static func starOpacity(nightProgress q: Double) -> Double {
        let rise = (q - 0.02) / 0.06
        let fall = (0.98 - q) / 0.06
        return min(1, max(0, min(rise, fall)))
    }

    /// A star: where (fractions of the screen), how big (points), how bright,
    /// and — for the two in three that twinkle — how long one twinkle takes
    /// (seconds) and where in it the star starts (a fraction of the period).
    struct Star: Equatable {
        let x: Double
        let y: Double
        let size: CGFloat
        let alpha: Double
        let twinkles: Bool
        let period: Double
        let phase: Double
    }

    /// Fixed stars (the same every frame, so they never jump), in the top
    /// 36 % of the sky, thinning and dimming towards the horizon; about 24
    /// across a phone, more across a wider screen.
    static func stars(width: Double) -> [Star] {
        var seed: UInt64 = 7
        func next() -> Double {
            seed = (seed * 16807) % 2_147_483_647
            return Double(seed - 1) / 2_147_483_646
        }
        let count = max(8, Int((24 * width / 466).rounded()))
        var stars: [Star] = []
        for _ in 0..<count {
            let depth = pow(next(), 1.4)
            let size = 0.9 + next() * 1.6
            let x = next()
            let alpha = (0.45 + next() * 0.5) * (1 - 0.55 * depth)
            let period = 2.4 + next() * 2.8
            let twinkles = next() < 0.65
            let phase = twinkles ? next() : 0
            stars.append(Star(x: x, y: depth * 0.36, size: CGFloat(size), alpha: alpha,
                              twinkles: twinkles, period: period, phase: phase))
        }
        return stars
    }

    /// A star's brightness at `time` (seconds, any epoch), as a fraction of
    /// its own: a slow swell between 22 % and full; 1 for the steady ones.
    static func twinkle(_ star: Star, at time: TimeInterval) -> Double {
        guard star.twinkles, star.period > 0 else { return 1 }
        return 0.61 + 0.39 * cos(2 * Double.pi * (time / star.period + star.phase))
    }

    /// A brighter four-point glint: its centre (fractions of the screen), its
    /// size (points), and its slow pulse (period in seconds, starting phase).
    struct Glint: Equatable {
        let x: Double
        let y: Double
        let size: CGFloat
        let period: Double
        let phase: Double
    }

    /// The glints' warm white.
    static let glintColor = RGB(hex: 0xFFFBF2)

    /// Where the screen's own sky shows: beside the cards and behind the
    /// header on a phone; the margins and between the pages on the open Duo.
    static func glints(wide: Bool) -> [Glint] {
        let spots: [(x: Double, y: Double, size: CGFloat)]
        if wide {
            spots = [(x: 0.035, y: 0.22, size: 17), (x: 0.07, y: 0.62, size: 13), (x: 0.49, y: 0.1, size: 16),
                     (x: 0.505, y: 0.47, size: 12), (x: 0.935, y: 0.32, size: 14), (x: 0.965, y: 0.07, size: 18),
                     (x: 0.27, y: 0.035, size: 13)]
        } else {
            spots = [(x: 0.93, y: 0.07, size: 17), (x: 0.84, y: 0.3, size: 13), (x: 0.6, y: 0.115, size: 14),
                     (x: 0.965, y: 0.5, size: 12), (x: 0.03, y: 0.42, size: 12)]
        }
        var glints: [Glint] = []
        for (index, spot) in spots.enumerated() {
            let period = 3.6 + Double(index % 3) * 1.1
            let phase = (Double(index) * 1.37).truncatingRemainder(dividingBy: period) / period
            glints.append(Glint(x: spot.x, y: spot.y, size: spot.size, period: period, phase: phase))
        }
        return glints
    }

    /// How open a glint is at `time` (seconds, any epoch): 0 at rest (small,
    /// dim, upright), 1 at full sparkle (full size and brightness, turned 25°).
    static func sparkle(_ glint: Glint, at time: TimeInterval) -> Double {
        guard glint.period > 0 else { return 0 }
        return 0.5 - 0.5 * cos(2 * Double.pi * (time / glint.period + glint.phase))
    }
}
