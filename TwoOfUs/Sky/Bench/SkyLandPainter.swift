import Accelerate
import CoreGraphics
import Foundation

/// Spike 2 (plan risk 1): the lab's land painter (`paintPlane` in
/// hill-painted.js) re-drawn in Core Graphics, for the shapes that need
/// nothing but themselves — a crest with no base, no valley floor, no mist.
/// On the slab that is every hill but the knoll.
///
/// It follows the lab stroke for stroke: the fill that follows the sky
/// along x; the wash laid at a quarter of the size (the air at the foot,
/// the flank's turn, shade, light, frost) and enlarged; the dry-brushed rim;
/// the mottle; and at deep night the plane painted four times too bright
/// and dithered down. Where the lab says `filter: blur()`, this draws the
/// stroke on a layer of its own and runs three box passes over it.
///
/// Not ported here: spurs and their melting feet, the valley floor and the
/// river, mist bands, and the slab's shade under his name in snow.
enum SkyLandPainter {
    struct Shape {
        let id: String
        /// Its number among the picture's shapes, far to near.
        let index: Int
        /// How far its own colour has gone into the horizon's air.
        let haze: Double
        let hazeLight: Double?
        /// A far ridge's soft edge.
        let soft: Double
        let wobble: Double
        let rim: Double
        let grass: Double
        let points: [(Double, Double)]
    }

    struct Plane {
        let id: SkyWorld.Plane.ID
        let shapes: [Shape]
    }

    /// The slab's planes, as the lab sets them, without the knoll.
    static let slab: [Plane] = [
        Plane(id: .far, shapes: [
            Shape(id: "range", index: 1, haze: 0.90, hazeLight: nil, soft: 1.2, wobble: 0.7, rim: 0, grass: 0,
                  points: [(-60, 131), (40, 128.5), (120, 131.5), (200, 133), (280, 130), (350, 132.5),
                           (420, 129.5), (560, 132)]),
            Shape(id: "ridge", index: 2, haze: 0.74, hazeLight: nil, soft: 0.8, wobble: 0.8, rim: 0, grass: 0,
                  points: [(-60, 134), (60, 132), (150, 135), (240, 136.5), (330, 133.5), (400, 135.5),
                           (560, 132.5)]),
        ]),
        Plane(id: .mid, shapes: [
            Shape(id: "hill", index: 3, haze: 0.42, hazeLight: 0.86, soft: 0.4, wobble: 1.1, rim: 0.8, grass: 0,
                  points: [(-60, 116), (10, 106), (60, 101), (110, 101), (160, 103.5), (197, 109.5), (229, 120),
                           (258, 130), (290, 137), (330, 142), (400, 147), (560, 152)]),
        ]),
        Plane(id: .near, shapes: [
            Shape(id: "near", index: 5, haze: 0.13, hazeLight: nil, soft: 0, wobble: 1.6, rim: 0.6, grass: 0.7,
                  points: [(-60, 178), (40, 169), (120, 166), (200, 171), (280, 181), (360, 186), (440, 181),
                           (560, 174)]),
        ]),
        Plane(id: .fore, shapes: [
            Shape(id: "near2", index: 6, haze: 0.07, hazeLight: nil, soft: 0, wobble: 2.2, rim: 0.4, grass: 0,
                  points: [(-60, 334), (60, 303), (160, 292), (260, 301), (340, 322), (420, 350), (560, 384)]),
            Shape(id: "near3", index: 7, haze: 0.03, hazeLight: nil, soft: 0, wobble: 2.4, rim: 0.3, grass: 1,
                  points: [(-60, 566), (60, 524), (160, 507), (260, 514), (340, 541), (420, 577), (560, 612)]),
        ]),
    ]

    /// A painted plane: the image, and where its top-left stands in the
    /// world at rest.
    struct Plate {
        let id: SkyWorld.Plane.ID
        let image: CGImage
        let origin: CGPoint
        let size: CGSize
    }

    // MARK: Painting

    /// One plane, painted inside an autorelease pool of its own: whatever
    /// Core Graphics autoreleases along the way goes when this plane is done,
    /// not when the last of the four is. Nil if the plane cannot be painted,
    /// or if the task painting it is cancelled before its last crest.
    static func paint(_ plane: Plane, minute: SkyBenchMinute, scale: Double) -> Plate? {
        autoreleasepool { plate(plane, minute: minute, scale: scale) }
    }

    private static func plate(_ plane: Plane, minute: SkyBenchMinute, scale: Double) -> Plate? {
        let world = minute.world
        let palette = minute.palette
        let air = minute.air
        let dark = air.dark
        let season = palette.season
        let left = minute.planeLeading
        let right = minute.planeTrailing
        let bottom = Double(minute.display.size.height) + 20
        let anchorWidth = Double(minute.display.anchorWidth)
        let lampX = minute.lampX
        let power = palette.lamp.power
        let byMoon = palette.byMoon
        let rimAmount = byMoon ? 0.5 * palette.moonlight : max(air.rimAmount, 0.12 * air.day)
        let bright = dark && palette.deepNight >= 1 ? 4.0 : 1.0
        let smoothstep = SkyMath.smoothstep

        let crests = plane.shapes.map { Crest($0, left: left, right: right) }
        guard let top = crests.map(\.seenTop).min(), top.isFinite else { return nil }
        let y0 = 4 * ((top - 6) / 4).rounded(.down)
        let width = Int(((right - left) * scale).rounded(.up))
        let height = Int(((bottom - y0) * scale).rounded(.up))
        guard let canvas = Layer(width: width, height: height) else { return nil }
        let px = { (x: Double) in (x - left) * scale }
        let py = { (y: Double) in (y - y0) * scale }
        let dxSun = { (x: Double) in (x - minute.sunX) / anchorWidth }

        func colour(_ lab: OKLab, _ alpha: Double = 1) -> CGColor {
            let rgb = lab.srgb(.sky)
            // (deep night: a little under — the dither adds a step and a
            // half back on average, and the bringing-down rounds up)
            let level = { (v: Double) -> CGFloat in
                bright == 1 ? CGFloat((v * 255).rounded() / 255)
                    : CGFloat(min(255, max(0, (v * 255 * bright - (bright - 0.5)).rounded())) / 255)
            }
            return CGColor(srgbRed: level(rgb.red), green: level(rgb.green), blue: level(rgb.blue),
                           alpha: CGFloat(SkyMath.clamped(alpha)))
        }
        /// A gradient along x with a stop every `step` points (`hGrad`).
        func across(_ step: Double, _ paint: (Double) -> CGColor) -> CGGradient? {
            var colours = [paint(left)]
            var places: [CGFloat] = [0]
            var x = ((left + 0.01) / step).rounded(.up) * step
            while x < right {
                colours.append(paint(x))
                places.append(CGFloat((x - left) / (right - left)))
                x += step
            }
            colours.append(paint(right))
            places.append(1)
            return CGGradient(colorsSpace: Layer.space, colors: colours as CFArray, locations: places)
        }

        for crest in crests {
            // A paint nobody is waiting for any more stops here.
            guard !Task.isCancelled else { return nil }
            let shape = crest.shape
            let haze = shape.haze
            guard let a = Layer(width: width, height: height) else { return nil }
            let body = crest.body(px: px, py: py, bottom: bottom + 40)
            let line = crest.line(px: px, py: py)

            // 1. The fill: its own colour gone `haze` of the way into the
            // horizon sky behind it, at every x.
            let own = { (x: Double) -> OKLab in
                let facing = crest.facing(x, lampX: lampX)
                let side = (facing - 0.5) * power * (1 - haze) * (dark ? 0.035 : 0.03)
                let near = dark || shape.hazeLight != nil ? 0 : pow(1 - haze, 1.2)
                let step = dark ? 0 : air.day * pow(1 - haze, 3)
                let snowDeep = dark
                    ? season.snow * (0.085 * smoothstep(0.2, 0.04, haze) + (plane.id == .mid ? 0.045 : 0))
                        * smoothstep(0.22, 0.4, palette.ground.lightness)
                    : 0
                let ground = OKLab(lightness: palette.ground.lightness + side - 0.058 * near - 0.125 * step - snowDeep,
                                   a: palette.ground.a + 0.007 * near + 0.007 * step,
                                   b: palette.ground.b + 0.006 * near + 0.016 * step)
                let mixed = ground.mixed(with: air.haze(dx: dxSun(x)), by: dark ? haze : shape.hazeLight ?? haze * 0.78)
                if dark || shape.hazeLight != nil { return mixed }
                let far = air.day * smoothstep(0.35, 0.9, haze)
                return OKLab(lightness: mixed.lightness + 0.014 * far, a: mixed.a - 0.003 * far,
                             b: mixed.b - 0.016 * far)
            }
            let nightLightness = 0.106 + 0.098 * pow(haze, 0.8)
            let temper = dark || shape.hazeLight != nil ? 0
                : air.day * (1 - air.presence) * SkyMath.lerp(-0.0075, 0.0085, smoothstep(0.50, 0.04, haze))
            let fill = { (x: Double) -> CGColor in
                var shown = palette.shown(own(x))
                shown.a += 0.3 * temper
                shown.b += temper
                if palette.deepNight > 0 {
                    let k = palette.deepNight
                    shown.lightness = SkyMath.lerp(shown.lightness, max(shown.lightness, nightLightness), k)
                    shown.a = SkyMath.lerp(shown.a, 0.030 * cos(266 * .pi / 180), 0.7 * k)
                    shown.b = SkyMath.lerp(shown.b, 0.030 * sin(266 * .pi / 180), 0.7 * k)
                }
                return colour(shown)
            }
            if shape.soft > 0 {
                // A far ridge has a soft edge: cut small and enlarged; the
                // enlarging is the softness.
                let q = shape.soft >= 1 ? 0.25 : 0.5
                guard let mask = Layer(width: Int((Double(width) * q).rounded(.up)) + 1,
                                       height: Int((Double(height) * q).rounded(.up)) + 1) else { return nil }
                mask.context.scaleBy(x: q, y: q)
                mask.context.setFillColor(CGColor(gray: 1, alpha: 1))
                mask.context.addPath(body)
                mask.context.fillPath()
                a.fill(CGRect(x: 0, y: 0, width: width, height: height), with: across(30, fill), span: px(right))
                a.context.setBlendMode(.destinationIn)
                a.draw(mask, enlargedBy: 1 / q)
                a.context.setBlendMode(.normal)
            } else {
                a.fill(body, with: across(30, fill), span: px(right))
            }
            if shape.grass > 0 {
                crest.grass(into: a, px: px, py: py, left: left, right: right, bottom: bottom,
                            gradient: across(30, fill), span: px(right))
            }

            // 2. The wash, a quarter of the size.
            let quarter = 0.25
            let washWidth = Int((Double(width) * quarter).rounded(.up)) + 1
            let washHeight = Int((Double(height) * quarter).rounded(.up)) + 1
            guard let wash = Layer(width: washWidth, height: washHeight),
                  let stroke = Layer(width: washWidth, height: washHeight) else { return nil }
            wash.context.scaleBy(x: quarter, y: quarter)
            stroke.context.scaleBy(x: quarter, y: quarter)
            let everything = CGRect(x: 0, y: 0, width: width + 8, height: height + 8)
            if haze < 0.95 {
                // Air gathers at its foot: toward the valley's own haze, level.
                let footAir = { (x: Double) -> OKLab in
                    dark ? air.haze(dx: dxSun(x))
                        : air.haze(dx: dxSun(x)).mixed(with: air.sky(dx: dxSun(x), elevation: 0.03), by: 0.7 * air.day)
                }
                wash.fill(everything, with: across(30) { colour(palette.shown(footAir($0))) }, span: px(right))
                let depth = 60 + 130 * (1 - haze)
                let amount = (1 - haze) * (dark ? 0.44 : 0.50) + 0.06
                let fall = CGGradient(colorsSpace: Layer.space, colors: [
                    CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0),
                    CGColor(srgbRed: 0, green: 0, blue: 0, alpha: CGFloat(amount * 0.55)),
                    CGColor(srgbRed: 0, green: 0, blue: 0, alpha: CGFloat(amount)),
                ] as CFArray, locations: [0, 0.5, 1])
                wash.context.setBlendMode(.destinationIn)
                wash.fillDown(everything, with: fall, from: py(crest.top + 4), to: py(crest.top + 4 + depth))
                wash.context.setBlendMode(.normal)
            }
            if !dark, palette.nightness > 0.02 {
                // The pale page at night: down the page, under the cards,
                // the land gives way to the paper.
                let paper = palette.shown(OKLab(lightness: 0.948, a: 0.014 * cos(285 * .pi / 180),
                                                b: 0.014 * sin(285 * .pi / 180)))
                let horizon = Double(world.horizon)
                let down = CGGradient(colorsSpace: Layer.space, colors: [
                    colour(paper, 0), colour(paper, 0.3 * palette.nightness), colour(paper, 0.62 * palette.nightness),
                ] as CFArray, locations: [0, 0.4, 1])
                wash.fillDown(everything, with: down, from: py(horizon + 14),
                              to: py(horizon + (world.kind == .duo ? 250 : 190)))
            }
            /// One blurred stroke along the crest, laid into the wash.
            func lay(width lineWidth: Double, blur: Double, step: Double, _ paint: (Double) -> CGColor) {
                stroke.clear()
                stroke.stroke(line, width: lineWidth * scale, with: across(step, paint), span: px(right))
                stroke.blur(radius: blur * scale * quarter)
                wash.context.saveGState()
                wash.context.scaleBy(x: 1 / quarter, y: 1 / quarter)
                wash.draw(stroke, enlargedBy: 1)
                wash.context.restoreGState()
            }
            if power > 0.03, haze < 0.8 {
                let cool = own(crest.x0 + 40).mixed(with: air.sky(dx: dxSun(crest.x0), elevation: 0.9), by: 0.5)
                let shade = OKLab(lightness: cool.lightness - (dark ? 0.03 : 0.05), a: cool.a, b: cool.b)
                let light = byMoon ? air.silver : air.rim
                if haze < 0.5 {
                    // A near hill is a round thing: its whole flank turns.
                    let turn = { (x: Double) in 0.5 + (crest.facing(x, lampX: lampX, reach: 90) - 0.5) * 0.62 }
                    let ends = { (x: Double) in
                        world.kind == .duo ? smoothstep(crest.x0 - 10, crest.x0 + 100, x) : 1
                    }
                    let k = power * (1 - haze)
                    let deeper = palette.shown(OKLab(lightness: shade.lightness - (dark ? 0.012 : 0.01),
                                                     a: shade.a, b: shade.b))
                    lay(width: 210, blur: 30, step: 24) { x in
                        colour(deeper, SkyMath.clamped((0.5 - turn(x)) * 2.4) * ends(x) * k * (dark ? 0.62 : 0.5))
                    }
                    let warm = own(lampX).mixed(with: light, by: 0.45)
                    let warmer = palette.shown(OKLab(lightness: warm.lightness + (dark ? 0.045 : 0.03),
                                                     a: warm.a, b: warm.b))
                    lay(width: 210, blur: 30, step: 24) { x in
                        colour(warmer, SkyMath.clamped((turn(x) - 0.5) * 2.4) * ends(x) * k
                            * (0.25 + 0.75 * max(air.rimAmount, 0.3 * air.day)) * (dark ? 0.5 : 0.42))
                    }
                }
                // Shade: a broad cool stroke on the side turned away…
                let shadeShown = palette.shown(shade)
                lay(width: 16 + 40 * (1 - haze), blur: 5 + 9 * (1 - haze), step: 14) { x in
                    colour(shadeShown, SkyMath.clamped((1 - crest.facing(x, lampX: lampX)) * 1.5 - 0.35)
                        * power * (1 - haze) * 0.75)
                }
                // …then the light: a soft glaze on the shoulder that faces it.
                let litBase = own(lampX).mixed(with: light, by: 0.62)
                let lit = palette.shown(OKLab(lightness: litBase.lightness + (dark ? 0.06 : 0.035),
                                              a: litBase.a, b: litBase.b))
                lay(width: 10 + 26 * (1 - haze), blur: 3 + 6 * (1 - haze), step: 14) { x in
                    colour(lit, SkyMath.clamped(SkyMath.clamped(crest.facing(x, lampX: lampX) * 2.2 - 0.9) * rimAmount
                        * (1 - haze * 0.7) * 1.5 * (0.35 + 0.65 * (shape.rim > 0 ? shape.rim : 0.5))
                        * exp(-abs(x - lampX) / (anchorWidth * 0.8))))
                }
            }
            // Frost and snow on the shoulders: where the sky reaches them.
            let white = max(season.snow, season.frost * 0.55)
            if white > 0.03, haze < 0.7 {
                let snowy = season.snow > 0.03
                let paint = snowy ? palette.snowLit : palette.frostLit
                lay(width: (5 + 16 * (1 - haze)) * (snowy ? 1.5 : 1), blur: 2 + 3 * (1 - haze), step: 20) { x in
                    colour(palette.shown(paint.mixed(with: air.haze(dx: dxSun(x)), by: haze * 0.8)),
                           white * (snowy ? 0.9 * (dark ? 1 - 0.45 * smoothstep(0.2, 0.04, haze) : 1) : 0.5))
                }
            }
            a.context.setBlendMode(.sourceAtop)
            a.draw(wash, enlargedBy: 1 / quarter)

            // 4. The rim: one thin, loaded line where the crest catches the
            // light, the brush skipping.
            if shape.rim > 0, rimAmount > 0.02, power > 0.03, haze < 0.8, !byMoon {
                guard let rim = Layer(width: width, height: height) else { return nil }
                let rimLight = palette.shown(OKLab(lightness: air.rim.lightness + 0.04, a: air.rim.a, b: air.rim.b))
                rim.context.translateBy(x: 0, y: 0.3 * scale)
                rim.stroke(line, width: (1.5 + 1.7 * (1 - haze)) * scale, cap: .round, with: across(10) { x in
                    colour(rimLight, SkyMath.clamped((0.14 + 0.86 * crest.facing(x, lampX: lampX)) * rimAmount
                        * shape.rim * (dark ? 2.6 : 1.3) * exp(-abs(x - lampX) / (anchorWidth * 0.5))))
                }, span: px(right))
                rim.context.translateBy(x: 0, y: -0.3 * scale)
                rim.context.setBlendMode(.destinationOut)
                rim.context.setAlpha(0.62)
                rim.tile(Textures.dry, at: CGPoint(x: Double(shape.index) * 37 - left * scale,
                                                   y: Double(shape.index) * 91), scale: 1)
                a.draw(rim, enlargedBy: 1)
            }
            a.context.setBlendMode(.normal)
            canvas.draw(a, enlargedBy: 1)
        }

        // The paint's own unevenness, over the whole plane.
        canvas.context.setBlendMode(.sourceAtop)
        canvas.context.setAlpha(bright > 1 ? 0.085 : dark ? 0.04 : 0.036)
        canvas.tile(Textures.mottle, at: CGPoint(x: -left * scale, y: -y0 * scale), scale: scale / 2 * 1.5)
        canvas.context.setAlpha(1)
        if bright > 1 {
            // …the dither, and down to its true value: the one rounding
            // the whole plane ever gets.
            canvas.tile(Textures.throwsTile(levels: Int(bright)), at: CGPoint(x: -left * scale, y: -y0 * scale),
                        scale: 1)
            canvas.context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: CGFloat(1 - 1 / bright)))
            canvas.context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        guard let image = canvas.context.makeImage() else { return nil }
        return Plate(id: plane.id, image: image, origin: CGPoint(x: left, y: y0),
                     size: CGSize(width: Double(width) / scale, height: Double(height) / scale))
    }

    // MARK: A crest

    /// A shape's crest as the hand drew it: Catmull-Rom through the set
    /// points, a sample every two points of x, the wobble added (`line`),
    /// and its height at every whole point of x.
    private struct Crest {
        let shape: Shape
        let points: [(x: Double, y: Double)]
        let x0: Double
        let x1: Double
        let top: Double
        let seenTop: Double
        private let origin: Double
        private let heights: [Double]

        init(_ shape: Shape, left: Double, right: Double) {
            self.shape = shape
            var out: [(x: Double, y: Double)] = []
            let set = shape.points
            let seed = Double(shape.index)
            let at = { (i: Int) in set[min(max(i, 0), set.count - 1)] }
            for k in 0..<(set.count - 1) {
                let p0 = at(k - 1), p1 = at(k), p2 = at(k + 1), p3 = at(k + 2)
                let length = SkyMath.hypot(p2.0 - p1.0, p2.1 - p1.1)
                let count = max(2, Int((length / 2).rounded(.up)))
                for j in (k == 0 ? 0 : 1)...count {
                    let t = Double(j) / Double(count), t2 = t * t, t3 = t2 * t
                    let spline = { (a: Double, b: Double, c: Double, d: Double) in
                        0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
                    }
                    let x = spline(p0.0, p1.0, p2.0, p3.0)
                    var y = spline(p0.1, p1.1, p2.1, p3.1)
                    y += (SkyNoise.drift(x / 70 + seed * 13.7, seed * 3.1 + 0.5, octaves: 2) - 0.5) * 2.6 * shape.wobble
                        + (SkyNoise.value(x / 11 + seed * 5.3, 7.7) - 0.5) * 0.6 * shape.wobble
                    out.append((x, y))
                }
            }
            points = out
            x0 = out.first?.x ?? 0
            x1 = out.last?.x ?? 0
            top = out.map(\.y).min() ?? .infinity
            seenTop = out.filter { $0.x >= left && $0.x <= right }.map(\.y).min() ?? .infinity
            origin = SkyMath.round(x0)
            var table = [Double](repeating: .nan, count: max(2, Int((x1 - x0).rounded(.up)) + 1))
            for i in 0..<(out.count - 1) {
                let a = out[i], b = out[i + 1]
                guard b.x > a.x else { continue }
                var x = a.x.rounded(.up)
                while x <= b.x {
                    let k = Int(x - origin)
                    if k >= 0, k < table.count { table[k] = a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x) }
                    x += 1
                }
            }
            heights = table
        }

        func height(at x: Double) -> Double {
            let k = SkyMath.round(x - origin)
            guard k >= 0, k < Double(heights.count), !heights[Int(k)].isNaN else { return .infinity }
            return heights[Int(k)]
        }

        /// How squarely the slope under the crest at x faces the light.
        func facing(_ x: Double, lampX: Double, reach: Double = 5) -> Double {
            let a = height(at: x - reach), b = height(at: x + reach)
            guard a.isFinite, b.isFinite else { return 0.5 }
            let slope = (b - a) / (2 * reach)
            return SkyMath.clamped(0.5 + min(max((lampX - x) / 60, -1), 1) * slope * 2.2)
        }

        func line(px: (Double) -> Double, py: (Double) -> Double) -> CGPath {
            let path = CGMutablePath()
            path.addLines(between: points.map { CGPoint(x: px($0.x), y: py($0.y)) })
            return path
        }

        func body(px: (Double) -> Double, py: (Double) -> Double, bottom: Double) -> CGPath {
            let path = CGMutablePath()
            path.addLines(between: points.map { CGPoint(x: px($0.x), y: py($0.y)) })
            path.addLine(to: CGPoint(x: px(x1), y: py(bottom)))
            path.addLine(to: CGPoint(x: px(x0), y: py(bottom)))
            path.closeSubpath()
            return path
        }

        /// Grass along a near crest: blades of the same paint, at fixed
        /// places in the world, so the edge is drawn, not cut.
        func grass(into layer: Layer, px: (Double) -> Double, py: (Double) -> Double, left: Double,
                   right: Double, bottom: Double, gradient: CGGradient?, span: Double) {
            let blades = CGMutablePath()
            var n = Int(((max(x0, left) + 1) / 0.55).rounded(.up))
            while Double(n) * 0.55 < min(x1, right) {
                defer { n += 1 }
                let x = Double(n) * 0.55
                let clump = SkyMath.smoothstep(0.35, 0.7, SkyNoise.value(x / 9 + Double(shape.index) * 3.3, 4.4)) * 0.85 + 0.15
                if SkyNoise.hash(n, salt: 401 + shape.index) > 0.8 * shape.grass * clump { continue }
                let y = height(at: x)
                guard y.isFinite, y <= bottom else { continue }
                let length = (0.9 + 2.9 * pow(SkyNoise.hash(n, salt: 402), 2.2) * clump) * min(1.2, shape.grass)
                let lean = (SkyNoise.hash(n, salt: 403) - 0.42) * 1.5
                let half = 0.28 + 0.26 * SkyNoise.hash(n, salt: 404)
                blades.move(to: CGPoint(x: px(x - half), y: py(y + 0.8)))
                blades.addQuadCurve(to: CGPoint(x: px(x + lean), y: py(y - length)),
                                    control: CGPoint(x: px(x + lean * 0.2 - half * 0.4), y: py(y - length * 0.6)))
                blades.addQuadCurve(to: CGPoint(x: px(x + half), y: py(y + 0.8)),
                                    control: CGPoint(x: px(x + lean * 0.2 + half * 0.6), y: py(y - length * 0.55)))
                blades.closeSubpath()
            }
            layer.fill(blades, with: gradient, span: span)
        }
    }

    // MARK: A layer

    /// A bitmap to paint on, y down as the lab's canvases are.
    private final class Layer {
        static let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let context: CGContext
        let width: Int
        let height: Int

        init?(width: Int, height: Int) {
            guard width > 0, height > 0,
                  let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: Layer.space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.interpolationQuality = .medium
            self.context = context
            self.width = width
            self.height = height
        }

        func clear() {
            guard let data = context.data else { return }
            memset(data, 0, context.bytesPerRow * height)
        }

        private func draw(_ gradient: CGGradient?, span: Double) {
            guard let gradient else { return }
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: span, y: 0),
                                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }

        func fill(_ path: CGPath, with gradient: CGGradient?, span: Double) {
            context.saveGState()
            context.addPath(path)
            context.clip()
            draw(gradient, span: span)
            context.restoreGState()
        }

        func fill(_ rect: CGRect, with gradient: CGGradient?, span: Double) {
            context.saveGState()
            context.clip(to: rect)
            draw(gradient, span: span)
            context.restoreGState()
        }

        func fillDown(_ rect: CGRect, with gradient: CGGradient?, from: Double, to: Double) {
            guard let gradient else { return }
            context.saveGState()
            context.clip(to: rect)
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: from), end: CGPoint(x: 0, y: to),
                                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            context.restoreGState()
        }

        func stroke(_ path: CGPath, width: Double, cap: CGLineCap = .butt, with gradient: CGGradient?,
                    span: Double) {
            context.saveGState()
            context.addPath(path)
            context.setLineWidth(width)
            context.setLineJoin(.round)
            context.setLineCap(cap)
            context.replacePathWithStrokedPath()
            context.clip()
            draw(gradient, span: span)
            context.restoreGState()
        }

        /// Another layer over this one, its pixels `factor` times as large,
        /// in this layer's current coordinates.
        func draw(_ other: Layer, enlargedBy factor: Double) {
            guard let image = other.context.makeImage() else { return }
            let size = CGSize(width: Double(other.width) * factor, height: Double(other.height) * factor)
            context.saveGState()
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(origin: .zero, size: size))
            context.restoreGState()
        }

        /// A tile repeated over the whole layer, its origin at `point`.
        func tile(_ image: CGImage?, at point: CGPoint, scale: Double) {
            guard let image else { return }
            context.saveGState()
            context.translateBy(x: point.x, y: point.y)
            context.scaleBy(x: scale, y: scale)
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height), byTiling: true)
            context.restoreGState()
        }

        /// A Gaussian of `radius` pixels, near enough: three box passes.
        func blur(radius: Double) {
            guard radius > 0.3, let data = context.data else { return }
            var side = UInt32((radius * 3 * (2 * Double.pi).squareRoot() / 4 + 0.5).rounded(.down))
            if side < 3 { side = 3 }
            if side % 2 == 0 { side += 1 }
            var buffer = vImage_Buffer(data: data, height: vImagePixelCount(height), width: vImagePixelCount(width),
                                       rowBytes: context.bytesPerRow)
            guard let scratch = malloc(context.bytesPerRow * height) else { return }
            defer { free(scratch) }
            var other = vImage_Buffer(data: scratch, height: buffer.height, width: buffer.width,
                                      rowBytes: buffer.rowBytes)
            let flags = vImage_Flags(kvImageEdgeExtend)
            vImageBoxConvolve_ARGB8888(&buffer, &other, nil, 0, 0, side, side, nil, flags)
            vImageBoxConvolve_ARGB8888(&other, &buffer, nil, 0, 0, side, side, nil, flags)
            vImageBoxConvolve_ARGB8888(&buffer, &other, nil, 0, 0, side, side, nil, flags)
            memcpy(data, scratch, context.bytesPerRow * height)
        }
    }

    // MARK: The paint's textures

    private enum Textures {
        /// Mottle: the paint's own unevenness, broad and low.
        static let mottle = make(512) { x, y in
            let n = SkyNoise.drift(Double(x) / 46, Double(y) / 17, octaves: 3) * 0.7
                + SkyNoise.value(Double(x) / 5.5, Double(y) / 2.6) * 0.3 - 0.5
            return (n > 0 ? 1 : 0, min(255, abs(n) * 2 * 60) / 255)
        }

        /// Dry brush: where a loaded brush skips. Only the rim uses it.
        static let dry = make(256) { x, y in
            let streak = SkyNoise.drift(Double(x) / 26, Double(y) / 3.2, octaves: 3)
            let tooth = SkyNoise.value(Double(x) / 2.1, Double(y) / 2.1) * 0.6 + SkyNoise.hash2(x, y, seed: 5) * 0.4
            return (1, SkyMath.smoothstep(0.50, 0.60, 0.7 * streak + 0.3 * tooth))
        }

        /// The dither for a plane painted `levels` times too bright: white
        /// at an alpha of a few levels, a fresh throw at every pixel.
        static func throwsTile(levels: Int) -> CGImage? {
            make(256) { x, y in
                let step = min(Double(levels - 1), (SkyNoise.hash2(x, y, seed: 77) * Double(levels)).rounded(.down))
                return (1, (step * 1.36).rounded() / 255)
            }
        }

        /// A square tile from a grey and an alpha at each pixel.
        private static func make(_ side: Int, _ pixel: (Int, Int) -> (Double, Double)) -> CGImage? {
            var bytes = [UInt8](repeating: 0, count: side * side * 4)
            for y in 0..<side {
                for x in 0..<side {
                    let (grey, alpha) = pixel(x, y)
                    let value = UInt8((grey * alpha * 255).rounded())
                    let i = (y * side + x) * 4
                    bytes[i] = value
                    bytes[i + 1] = value
                    bytes[i + 2] = value
                    bytes[i + 3] = UInt8((alpha * 255).rounded())
                }
            }
            guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
            return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                           space: Layer.space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                           provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        }
    }
}
