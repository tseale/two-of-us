import Foundation

/// The land's skyline: at any world x, the highest crest of the planes that
/// move with the sky (the far ridges, the hill, the knoll) — where the sky
/// ends and the land begins. His stars never sit lower: "kept clear of the
/// land, the tree's crown and each other". The near planes are not part of
/// it: they slide faster than the sky when the camera looks up, so no star
/// can be laid out against them.
///
/// Every shape of land is a crest line set by hand, a few points in rest-pose
/// world points, drawn through with a Catmull-Rom curve (a sample every 2 pt)
/// and given "the hand's wobble" from the hill's own noise, seeded by the
/// shape's number in the picture. The lab then keeps each crest's height at
/// every whole point of x, in single precision, and reads it at the nearest;
/// so does this, because a star's lowest place is that number less 8 pt and
/// the star chart is to be the lab's to the hundredth of a point.
///
/// Only the crests under the sky are here (`design/sky-lab/skies/hill-painted.js`,
/// `DUO.planes` and `SLAB.planes`, the shapes of the planes whose `sink` is
/// 1, less the valley floor). The near planes' crests, the spurs' feet, haze
/// and softness stay in the lab until the land is painted.
///
/// Pure: `SkylineTests`, against the lab's own skyline at every whole x
/// (`SkyCoreFixturesStars.land`).
struct Skyline: Equatable {
    /// One crest line as it was set by hand.
    struct Crest: Equatable {
        /// Its name in the lab: `range`, `ridge`, `hill`, `knoll`, and the
        /// leading page's spurs `l1`, `r1`, `l2`, `l3`.
        let id: String
        /// The plane it is a shape of.
        let plane: SkyWorld.Plane.ID
        /// Its number among the picture's shapes, far to near: what the
        /// hand's wobble is seeded with (the valley floor and the near
        /// planes' shapes are counted, so the numbers have gaps).
        let seed: Int
        /// The hand: how far the drawn line wanders from the set points.
        let wobble: Double
        /// The set points, leading to trailing, in rest-pose world points.
        let points: [CGPoint]
    }

    /// A crest as the lab keeps it: its height at every whole point of x.
    private struct Line: Equatable {
        let id: String
        /// World x of the first height.
        let origin: Double
        /// Rest-pose y at `origin`, `origin + 1`, …; infinity where the
        /// crest has not been drawn.
        let heights: [Float]

        func height(at x: Double) -> Double {
            let index = SkyMath.round(x - origin)
            guard index >= 0, index < Double(heights.count) else { return .infinity }
            return Double(heights[Int(index)])
        }
    }

    /// The crest lines, far to near.
    let crests: [Crest]
    private let lines: [Line]

    /// The skyline of these crest lines.
    init(crests: [Crest]) {
        self.crests = crests
        lines = crests.map(Self.line)
    }

    // MARK: Asking it

    /// Rest-pose y of the skyline at world x: the highest crest there (the
    /// smallest y). Infinity where the world has no land under the sky.
    func top(at x: Double) -> Double {
        var y = Double.infinity
        for line in lines {
            y = min(y, line.height(at: x))
        }
        return y
    }

    /// Rest-pose y of one crest at world x; infinity where it does not
    /// reach, or there is no crest of that name.
    func height(of id: String, at x: Double) -> Double {
        lines.first { $0.id == id }?.height(at: x) ?? .infinity
    }

    /// Rest-pose y of the tree's foot: the knoll's crest under the trunk,
    /// and 1.2 pt into the ground.
    func treeFoot(at x: Double) -> Double {
        height(of: "knoll", at: x) + 1.2
    }

    // MARK: The two worlds'

    /// The skyline of a world.
    static func of(_ kind: SkyWorld.Kind) -> Skyline {
        switch kind {
        case .duo: return duo
        case .slab: return slab
        }
    }

    /// The Duo's: the far range and ridge, the spurs that come down to the
    /// river on the leading page, the hill, and the knoll the tree stands on.
    static let duo = Skyline(crests: [
        crest("range", .far, 1, wobble: 0.8, [
            (-560, 285), (-430, 281), (-330, 285.5), (-250, 289.5), (-170, 285), (-90, 281.5), (20, 285),
            (120, 288), (200, 284.5), (300, 287.5), (400, 289.5), (520, 286), (660, 287),
        ]),
        crest("ridge", .far, 2, wobble: 1.0, [
            (-560, 289), (-440, 286.5), (-340, 284), (-270, 291), (-235, 294.5), (-190, 290.5), (-110, 287),
            (-30, 285.5), (60, 289.5), (160, 292.5), (260, 291.5), (340, 289), (430, 292), (520, 290), (660, 288),
        ]),
        crest("l1", .far, 4, wobble: 1.0, [(-560, 289), (-460, 290.5), (-380, 294), (-310, 299), (-262, 303.5)]),
        crest("r1", .far, 5, wobble: 1.0, [(-220, 304.5), (-170, 299), (-110, 293.5), (-40, 290), (40, 289), (150, 292)]),
        crest("l2", .far, 6, wobble: 1.2, [(-560, 296), (-470, 299), (-400, 304), (-330, 311), (-264, 317.5)]),
        crest("hill", .mid, 7, wobble: 1.6, [
            (-216, 339), (-170, 328), (-120, 316), (-60, 306), (10, 298.5), (90, 290.5), (170, 285),
            (240, 287), (310, 295), (370, 302), (450, 307), (540, 311), (660, 314),
        ]),
        crest("l3", .mid, 8, wobble: 1.6, [(-560, 316), (-500, 326), (-452, 341), (-418, 357), (-394, 372)]),
        crest("knoll", .knoll, 9, wobble: 1.0, [
            (-150, 452), (-60, 428), (20, 418), (90, 413), (150, 406), (200, 396), (240, 382), (272, 364),
            (300, 344), (330, 322), (360, 305.5), (385, 298.6), (408, 296.5), (430, 298.2), (456, 305),
            (486, 318), (520, 335), (570, 356), (660, 384),
        ]),
    ])

    /// The slab's: its small landscape high in the header. The hill's
    /// shoulder carries on past the end of the age line before it falls to
    /// the knoll, so the whole line sits on the hill.
    static let slab = Skyline(crests: [
        crest("range", .far, 1, wobble: 0.7, [
            (-60, 131), (40, 128.5), (120, 131.5), (200, 133), (280, 130), (350, 132.5), (420, 129.5), (560, 132),
        ]),
        crest("ridge", .far, 2, wobble: 0.8, [
            (-60, 134), (60, 132), (150, 135), (240, 136.5), (330, 133.5), (400, 135.5), (560, 132.5),
        ]),
        crest("hill", .mid, 3, wobble: 1.1, [
            (-60, 116), (10, 106), (60, 101), (110, 101), (160, 103.5), (197, 109.5), (229, 120), (258, 130),
            (290, 137), (330, 142), (400, 147), (560, 152),
        ]),
        crest("knoll", .knoll, 4, wobble: 0.8, [
            (150, 190), (200, 162), (228, 148), (252, 139), (272, 133.5), (286, 132), (300, 133.5), (318, 138.5),
            (345, 148), (380, 160), (420, 172), (560, 196),
        ]),
    ])

    // MARK: The tree's crown

    /// The crown's outline at unit x (0 at the trunk, 1 the tree's height;
    /// y is measured up from the foot, so it is negative): the highest any
    /// of its lobes reaches there, or nil beside the tree. "For keeping
    /// stars clear": a star stands 5 pt over it at the least. The lobes are
    /// the tree's own (`skies/hill-painted/tree.js`, `LOBES`: the leader's,
    /// the great left limb's, the right limb's, a low left bough, the long
    /// arm's, the heart of the crown).
    static func crownTop(at x: Double) -> Double? {
        var top: Double?
        for lobe in crownLobes {
            let u = (x - lobe.cx) / lobe.rx
            if abs(u) >= 1 { continue }
            let y = lobe.cy - lobe.ry * (1 - u * u).squareRoot()
            if top == nil || y < (top ?? y) { top = y }
        }
        return top
    }

    // MARK: Private

    private static let crownLobes: [(cx: Double, cy: Double, rx: Double, ry: Double)] = [
        (0.040, -0.775, 0.225, 0.170),
        (-0.265, -0.615, 0.200, 0.180),
        (0.275, -0.655, 0.200, 0.170),
        (-0.350, -0.405, 0.125, 0.100),
        (0.385, -0.405, 0.125, 0.100),
        (0.005, -0.540, 0.230, 0.170),
    ]

    private static func crest(_ id: String, _ plane: SkyWorld.Plane.ID, _ seed: Int, wobble: Double,
                              _ points: [(Double, Double)]) -> Crest {
        Crest(id: id, plane: plane, seed: seed, wobble: wobble,
              points: points.map { CGPoint(x: $0.0, y: $0.1) })
    }

    /// The lab's `line` and the lookup it builds from it (`buildGeometry`):
    /// a Catmull-Rom curve through the set points, a sample every 2 pt of
    /// its length, the hand's wobble added; then the height at every whole
    /// x, between the samples either side of it, kept in single precision.
    private static func line(_ crest: Crest) -> Line {
        let points = crest.points.map { (x: Double($0.x), y: Double($0.y)) }
        guard points.count >= 2 else { return Line(id: crest.id, origin: 0, heights: []) }
        let seed = Double(crest.seed), wobble = crest.wobble
        func point(_ index: Int) -> (x: Double, y: Double) {
            points[min(max(index, 0), points.count - 1)]
        }

        var drawn: [(x: Double, y: Double)] = []
        for k in 0..<(points.count - 1) {
            let p0 = point(k - 1), p1 = point(k), p2 = point(k + 1), p3 = point(k + 2)
            let length = SkyMath.hypot(p2.x - p1.x, p2.y - p1.y)
            let steps = max(2, Int((length / 2).rounded(.up)))
            for j in (k == 0 ? 0 : 1)...steps {
                let t = Double(j) / Double(steps), t2 = t * t, t3 = t2 * t
                func through(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
                    0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
                }
                let x = through(p0.x, p1.x, p2.x, p3.x)
                var y = through(p0.y, p1.y, p2.y, p3.y)
                if wobble != 0 {
                    let slow = (SkyNoise.drift(x / 70 + seed * 13.7, seed * 3.1 + 0.5, octaves: 2) - 0.5) * 2.6 * wobble
                    let quick = (SkyNoise.value(x / 11 + seed * 5.3, 7.7) - 0.5) * 0.6 * wobble
                    y += slow + quick
                }
                drawn.append((x, y))
            }
        }

        let first = drawn[0].x, last = drawn[drawn.count - 1].x
        let origin = SkyMath.round(first)
        let count = max(2, Int((last - first).rounded(.up)) + 1)
        var heights = [Float](repeating: .infinity, count: count)
        for i in 0..<(drawn.count - 1) {
            let a = drawn[i], b = drawn[i + 1]
            guard b.x > a.x else { continue }
            var x = a.x.rounded(.up)
            while x <= b.x {
                let index = x - origin
                if index >= 0, index < Double(count) {
                    heights[Int(index)] = Float(a.y + ((b.y - a.y) * (x - a.x)) / (b.x - a.x))
                }
                x += 1
            }
        }
        return Line(id: crest.id, origin: origin, heights: heights)
    }
}
