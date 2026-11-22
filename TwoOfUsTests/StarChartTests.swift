import XCTest
@testable import TwoOfUs

/// His stars (`StarChart`) against the sky lab's: every star's place, as the
/// lab's own `starsFor` cast it on the lab's page — really drawn at night at
/// fourteen ages from his first night to two years, on the cover, the spread
/// and the slab, each with the layout the page measured for that age — and
/// ten more skies cast to drive the rules those never reach (a sky of 1,500
/// nights, a long name, a bare header, a wall of words that leaves the sky a
/// narrow band, a name that ends just short of the first night's own place).
/// The lab's lists are in
/// `SkyCoreFixturesStars` (exported by
/// `design/sky-lab/tools/swift-fixtures/stars.mjs`). Then the design's rules,
/// each as a test of its own on those same skies.
final class StarChartTests: XCTestCase {
    private typealias Lab = SkyCoreFixturesStars
    private typealias Star = StarChart.Star

    // MARK: Reading the lab's skies

    /// One sky of the lab's: what it was cast for, and every night's star.
    private struct LabSky {
        /// Where it is among the fixtures' skies.
        let index: Int
        let drawn: Bool
        /// `lab` for the page's own; else the name of this script's sky.
        let name: String
        let displayName: String
        let display: SkyWorld.Display
        /// Whole days of age: the sky has one night more.
        let age: Int
        let layout: StarChart.Layout
        /// The module's own census: his stars, those in view at rest, those in view looking up.
        let census: (total: Int, rest: Int, up: Int)?
        /// The places summed, to six decimals.
        let sum: CGPoint
        /// Night by night: the looked-up place in hundredths of a point,
        /// the kind, and how many casts it took.
        let stars: [(x: Double, y: Double, kind: Star.Kind, again: Int)]

        var world: SkyWorld { display.world }
        var title: String { "\(name) \(displayName) at \(age) days" }
        var monthNights: Set<Int> {
            Set(stars.enumerated().filter { $0.element.kind == .month }.map { $0.offset + 1 })
        }

        /// The app's sky for the same night, world and layout (cast once
        /// for all the tests: `StarChartTests.casts`).
        func cast() -> [Star] {
            StarChartTests.casts[index]
        }
    }

    private static let displays: [String: SkyWorld.Display] = ["cover": .cover, "spread": .spread, "slab": .slab]

    private static func rect(_ text: String?) -> CGRect? {
        guard let text, text != "nil" else { return nil }
        let v = text.split(separator: ",").compactMap { Double($0) }
        guard v.count == 4 else { return nil }
        return CGRect(x: v[0], y: v[1], width: v[2], height: v[3])
    }

    private static func pair(_ text: String?) -> [Double] {
        (text ?? "").split(separator: ",").compactMap { Double($0) }
    }

    /// Every sky of the fixtures, parsed once.
    private static let skies: [LabSky] = {
        var out: [LabSky] = []
        var head: [String] = []
        var tokens: [String] = []
        func close() {
            guard head.count >= 5, let display = displays[head[3]], let age = Int(head[4]) else { return }
            var facts: [String: String] = [:]
            for word in head.dropFirst(5) {
                let parts = word.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 { facts[parts[0]] = parts[1] }
            }
            var layout = StarChart.Layout()
            layout.anchorX = display.anchorX
            layout.name = rect(facts["name"])
            layout.age = rect(facts["age"])
            layout.avatar = rect(facts["avatar"])
            layout.gear = rect(facts["gear"])
            if let strip = facts["strip"], let x = Double(strip) { layout.stripWindow = CGFloat(x) }
            let census = pair(facts["census"])
            let sum = pair(facts["sum"])
            let stars: [(x: Double, y: Double, kind: Star.Kind, again: Int)] = tokens.map { token in
                let parts = token.split(separator: ",").map(String.init)
                let code = parts.count > 2 ? parts[2] : ""
                let kind: Star.Kind = code.hasPrefix("m") ? .month : code.hasPrefix("f") ? .first : code.hasPrefix("t") ? .tonight : .night
                return (x: (Double(parts[0]) ?? .nan) / 100, y: (Double(parts[1]) ?? .nan) / 100, kind: kind,
                        again: Int(code.dropFirst()) ?? 0)
            }
            out.append(LabSky(index: out.count, drawn: head[1] == "drawn", name: head[2], displayName: head[3], display: display, age: age,
                              layout: layout,
                              census: census.count == 3 ? (Int(census[0]), Int(census[1]), Int(census[2])) : nil,
                              sum: sum.count == 2 ? CGPoint(x: sum[0], y: sum[1]) : .zero,
                              stars: stars))
        }
        for row in SkyCoreFixture.words(Lab.skies) {
            if row.first == "@" {
                close()
                head = row
                tokens = []
            } else {
                tokens.append(contentsOf: row)
            }
        }
        close()
        return out
    }()

    /// Each of those skies as `StarChart` casts it, in the same order.
    private static let casts: [[Star]] = skies.map {
        StarChart.cast(nights: $0.stars.count, monthNights: $0.monthNights, world: $0.world, layout: $0.layout)
    }

    private var drawn: [LabSky] { Self.skies.filter(\.drawn) }

    private func sky(_ display: String, _ age: Int, file: StaticString = #filePath, line: UInt = #line) -> LabSky {
        guard let found = Self.skies.first(where: { $0.drawn && $0.displayName == display && $0.age == age }) else {
            XCTFail("the lab drew no \(display) sky at \(age) days", file: file, line: line)
            return Self.skies[0]
        }
        return found
    }

    private func fact(_ key: String) -> [String] {
        Array(SkyCoreFixture.words(Lab.facts).first { $0.first == key }?.dropFirst() ?? [])
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        (Double(a.x - b.x) * Double(a.x - b.x) + Double(a.y - b.y) * Double(a.y - b.y)).squareRoot()
    }

    /// How far a point is from the nearest edge of a rect, inside or out.
    private func distance(_ p: CGPoint, toTheEdgeOf r: CGRect) -> Double {
        let inside = min(Double(p.x - r.minX), Double(r.maxX - p.x), Double(p.y - r.minY), Double(r.maxY - p.y))
        if inside >= 0 { return inside }
        let dx = max(Double(r.minX - p.x), 0, Double(p.x - r.maxX)), dy = max(Double(r.minY - p.y), 0, Double(p.y - r.maxY))
        return (dx * dx + dy * dy).squareRoot()
    }

    // MARK: Against the lab

    func testTheLabDrewEveryAgeOnEveryDisplay() {
        // From the first night to two years; 61 and 92 days are nights when
        // TONIGHT is a month-night, 142 the default day, 143 the day after.
        let ages = [0, 1, 7, 30, 61, 92, 142, 143, 200, 300, 367, 368, 560, 730]
        XCTAssertEqual(fact("ages").compactMap { Int($0) }, ages)
        for display in ["cover", "spread", "slab"] {
            XCTAssertEqual(drawn.filter { $0.displayName == display }.map(\.age), ages, display)
        }
        XCTAssertEqual(drawn.count, 42)
        XCTAssertEqual(fact("drawn"), ["42"])
        XCTAssertEqual(Self.skies.count, 52)
        for sky in drawn {
            XCTAssertEqual(sky.stars.count, sky.age + 1, "one star for every night of his life: \(sky.title)")
            XCTAssertEqual(sky.census?.total, sky.age + 1, sky.title)
        }
    }

    func testEveryStarStandsWhereTheLabPutIt() {
        // EVERY star of every sky, to the hundredth of a point the lab's
        // place is written to (so within half a hundredth of it) — and the
        // places summed, which the lab wrote to six decimals: no star is a
        // hair off.
        var checked = 0
        for sky in Self.skies {
            let stars = sky.cast()
            XCTAssertEqual(stars.count, sky.stars.count, sky.title)
            var sumX = 0.0, sumY = 0.0
            for (star, lab) in zip(stars, sky.stars) {
                XCTAssertEqual(star.kind, lab.kind, "\(sky.title), night \(star.night)")
                XCTAssertEqual(Double(star.up.x), lab.x, accuracy: 0.00501, "\(sky.title), night \(star.night)")
                XCTAssertEqual(Double(star.up.y), lab.y, accuracy: 0.00501, "\(sky.title), night \(star.night)")
                sumX += Double(star.up.x)
                sumY += Double(star.up.y)
                checked += 1
            }
            XCTAssertEqual(sumX, Double(sky.sum.x), accuracy: 1e-6, sky.title)
            XCTAssertEqual(sumY, Double(sky.sum.y), accuracy: 1e-6, sky.title)
            XCTAssertEqual(stars.map(\.night), Array(1...max(sky.stars.count, 1)), sky.title)
        }
        // 3 × (1 + 2 + 8 + 31 + 62 + 93 + 143 + 144 + 201 + 301 + 368 + 369 + 561 + 731) drawn, 4,892 cast
        XCTAssertEqual(checked, 3 * 3015 + 4892)
    }

    func testEveryStarCameToItsPlaceAsInTheLab() {
        // Not only where, but HOW: its own first place, the k-th cast
        // again, a step of the spiral, or nowhere free at all — the lab
        // noted each as it cast, and so the rules the standard ages never
        // reach are run too.
        var first = 0, again = 0, spiral = 0, nowhere = 0, most = 0
        for sky in Self.skies {
            for (star, lab) in zip(sky.cast(), sky.stars) {
                XCTAssertEqual(star.again, lab.again, "\(sky.title), night \(star.night)")
                if star.kind == .tonight || (star.kind == .first && sky.world.firstNightUp != nil && star.again == 0
                    && star.up == sky.world.firstNightUp) { continue }
                let casts = star.kind == .night ? 30 : 270
                if star.again == 0 { first += 1 } else if star.again <= casts { again += 1 }
                else if star.again <= casts + 480 { spiral += 1 } else { nowhere += 1 }
                XCTAssertEqual(star.foundNoPlace, star.again == casts + 481)
                most = max(most, star.again)
            }
        }
        XCTAssertEqual(fact("placed"), ["first", "\(first)", "again", "\(again)", "spiral", "\(spiral)", "nowhere", "\(nowhere)", "most", "\(most)"])
        XCTAssertGreaterThan(spiral, 40, "the spiral is reached")
        XCTAssertGreaterThan(nowhere, 10, "…and a sky so full that a night finds nowhere")
        // (by an ordinary night as by a four-point star: in the walled sky
        // an ordinary night runs out of its 30 casts)
        for crowded in Self.skies where crowded.name == "crowded" {
            let stars = crowded.cast()
            XCTAssertTrue(stars.contains { $0.kind == .night && $0.again > 30 && !$0.foundNoPlace }, crowded.title)
            XCTAssertTrue(stars.contains { $0.kind == .month && $0.again > 270 }, crowded.title)
        }
        // To two years, on every display, every night finds a place.
        for sky in drawn {
            for star in sky.cast() {
                XCTAssertFalse(star.foundNoPlace, "\(sky.title), night \(star.night)")
            }
        }
    }

    func testAllHisStarsAreInViewLookingUp() {
        // "Looking up 143 on all three displays" at 142 days; at rest 60 on
        // the cover and on the spread's phone page, 28 on the slab.
        for (display, rest) in [("cover", 60), ("spread", 60), ("slab", 28)] {
            let lab = sky(display, 142)
            let stars = lab.cast()
            XCTAssertEqual(stars.count, 143)
            XCTAssertEqual(stars.filter { $0.isInViewLookingUp(lab.display) }.count, 143, display)
            XCTAssertEqual(stars.filter { $0.isInViewAtRest(lab.display) }.count, rest, display)
        }
        // …and at every age the module's own census.
        for lab in drawn {
            let stars = lab.cast()
            XCTAssertEqual(stars.filter { $0.isInViewLookingUp(lab.display) }.count, lab.census?.up, lab.title)
            XCTAssertEqual(stars.filter { $0.isInViewAtRest(lab.display) }.count, lab.census?.rest, lab.title)
            XCTAssertEqual(lab.census?.up, lab.census?.total, "every one of his stars is in view looking up: \(lab.title)")
        }
    }

    func testAStarAtRestIsItsLookedUpPlaceTurnedBackAndLowered() {
        // (The exporter stops if the lab's own rest places are anything else.)
        for lab in [sky("cover", 142), sky("slab", 142)] {
            let world = lab.world
            for star in lab.cast() where star.kind != .tonight {
                XCTAssertEqual(star.rest.x, star.up.x + world.turn, accuracy: 1e-9)
                XCTAssertEqual(star.rest.y, star.up.y - world.drop, accuracy: 1e-9)
            }
        }
    }

    func testTheKeepOutsAreTheLabs() {
        // `starKeepOuts`, at three ages (the age line's width changes with
        // it) and for the skies of a long name, a bare header, buttons only,
        // a wall of words, a name that ends short of the first night's place.
        let rows = SkyCoreFixture.words(Lab.keepOuts)
        XCTAssertEqual(rows.count, 3 * 3 + 10)
        for row in rows {
            let parts = row[0].split(separator: ".").map(String.init)
            guard let age = Int(row[1]),
                  let lab = Self.skies.first(where: { $0.displayName == parts[0] && $0.age == age && $0.name == (parts.count > 1 ? parts[1] : "lab") })
            else {
                XCTFail("no sky for \(row[0]) \(row[1])")
                continue
            }
            let mine = StarChart.keepOuts(world: lab.world, layout: lab.layout)
            XCTAssertEqual(mine.count, row.count - 2, lab.title)
            for (edges, text) in zip(mine, row.dropFirst(2)) {
                let v = Self.pair(text)
                XCTAssertEqual(edges.x0, v[0], accuracy: 1e-6, lab.title)
                XCTAssertEqual(edges.y0, v[1], accuracy: 1e-6, lab.title)
                XCTAssertEqual(edges.x1, v[2], accuracy: 1e-6, lab.title)
                XCTAssertEqual(edges.y1, v[3], accuracy: 1e-6, lab.title)
            }
        }
        // The name, the age line and the avatar are one block, with 7 pt of
        // room and one em past the last glyph: on the cover, from the
        // avatar's leading edge (20) less 7 to the name's end (188.04) and
        // 13 and 7 more; and the same block where the rest pose shows it.
        let cover = sky("cover", 142)
        let outs = StarChart.keepOuts(world: .duo, layout: cover.layout)
        XCTAssertEqual(outs.count, 7)
        XCTAssertEqual(outs[0].x0, 13, accuracy: 1e-9)
        XCTAssertEqual(outs[0].x1, 208.04, accuracy: 1e-9)
        XCTAssertEqual(outs[1].x0, outs[0].x0 - 90, accuracy: 1e-9)
        XCTAssertEqual(outs[1].y0, outs[0].y0 + 312, accuracy: 1e-9)
    }

    func testAPlaceIsFreeAsInTheLab() {
        // The rule a place is judged by, asked in two of the lab's skies
        // (the cover at 142 days, the slab at a year, all their stars
        // standing) about some 1,700 places: a tenth of a point either
        // side of tonight's clearings (30, 27 on the slab, 70; 17 at rest),
        // of the first night's (18, 60), of the room round a four-point
        // star (10.6, 20, 44, 60, 80) and an ordinary night (5.6, 10.6),
        // of every keep-out's edge and 9 pt off it, of every card's edge
        // by 10, of the display's own edges in both poses, of the land —
        // and anywhere. For an ordinary night, and for a four-point star
        // with each room it may settle for.
        var head: [String] = []
        var tokens: [String] = []
        var asked = 0
        func close() {
            guard head.count > 3, let age = Int(head[2]) else { return }
            let lab = sky(head[1], age)
            let standing = StarChart.CastSky(lab.cast(), world: lab.world, layout: lab.layout)
            var free = [0, 0, 0, 0, 0]
            for token in tokens {
                let parts = token.split(separator: ",").compactMap { Double($0) }
                guard parts.count == 3 else { return XCTFail("a place the lab was asked about: \(token)") }
                let place = CGPoint(x: parts[0], y: parts[1])
                let answers = [
                    standing.isFree(place, fourPoint: false),
                    standing.isFree(place, fourPoint: true),
                    standing.isFree(place, fourPoint: true, room: 60),
                    standing.isFree(place, fourPoint: true, room: 44),
                    standing.isFree(place, fourPoint: true, room: 20),
                ]
                for (i, answer) in answers.enumerated() {
                    XCTAssertEqual(answer, Int(parts[2]) & (1 << i) != 0, "\(lab.title): (\(parts[0]), \(parts[1])), asking \(i)")
                    if answer { free[i] += 1 }
                }
                asked += 1
            }
            XCTAssertEqual(head[3], "asked=\(tokens.count)")
            XCTAssertEqual(head[4], "free=\(free.map(String.init).joined(separator: ","))", lab.title)
            // each asking leaves a good share free and a good share taken
            XCTAssertGreaterThan(free[0], tokens.count / 3)
            XCTAssertLessThan(free[1], free[4], "more room between two four-point stars, fewer places")
        }
        for row in SkyCoreFixture.words(Lab.rooms) {
            if row.first == "@" {
                close()
                head = row
                tokens = []
            } else {
                tokens.append(contentsOf: row)
            }
        }
        close()
        XCTAssertEqual(asked, 900 + 822)
    }

    func testTheRoomEachRuleKeeps() {
        // The same rule in the design's own numbers, in a sky with nobody
        // in it yet (the Duo's, the cover's layout): a tenth of a point
        // inside each distance a place is taken, a tenth outside it is free.
        let lab = sky("cover", 142)
        let empty = StarChart.CastSky([], world: .duo, layout: lab.layout)
        let tonight = SkyWorld.duo.tonightUp
        func left(of p: CGPoint, by d: CGFloat) -> CGPoint { CGPoint(x: p.x - d, y: p.y) }
        // tonight's star, in its clear window: 30 pt of dark sky, and no
        // four-point star within 70
        XCTAssertFalse(empty.isFree(left(of: tonight, by: 29.9), fourPoint: false))
        XCTAssertTrue(empty.isFree(left(of: tonight, by: 30.1), fourPoint: false))
        XCTAssertFalse(empty.isFree(left(of: tonight, by: 69.9), fourPoint: true))
        XCTAssertTrue(empty.isFree(left(of: tonight, by: 70.1), fourPoint: true))
        // …and beside the tree, at rest, 17 pt (its rest home, looked up:
        // turned 90 pt and lowered 312)
        let rest = CGPoint(x: SkyWorld.duo.tonight.x - 90, y: SkyWorld.duo.tonight.y + 312)
        XCTAssertFalse(empty.isFree(left(of: rest, by: 16.9), fourPoint: false))
        XCTAssertTrue(empty.isFree(left(of: rest, by: 17.1), fourPoint: false))

        // With the first night's star at its own place: 18 pt of sky to
        // itself, and no other four-point star within 60.
        let first = StarChart.cast(nights: 2, monthNights: [], world: .duo, layout: lab.layout)
        XCTAssertEqual(first.map(\.kind), [.first, .tonight])
        let one = StarChart.CastSky(first, world: .duo, layout: lab.layout)
        let own = CGPoint(x: 262, y: 43)
        XCTAssertFalse(one.isFree(left(of: own, by: 17.9), fourPoint: false))
        XCTAssertTrue(one.isFree(left(of: own, by: 18.1), fourPoint: false))
        XCTAssertFalse(one.isFree(CGPoint(x: 262, y: 43 + 59.9), fourPoint: true, room: 20))
        XCTAssertTrue(one.isFree(CGPoint(x: 262, y: 43 + 60.1), fourPoint: true, room: 20))
        XCTAssertFalse(one.isFree(CGPoint(x: 262, y: 43 + 79.9), fourPoint: true), "80 pt between two four-point stars")
        XCTAssertTrue(one.isFree(CGPoint(x: 262, y: 43 + 80.1), fourPoint: true))

        // Round an ordinary night: never closer than 5.6 pt; a four-point
        // star 5 pt more. (Night 2 of a three-night sky, wherever it is.)
        let three = StarChart.cast(nights: 3, monthNights: [], world: .duo, layout: lab.layout)
        let two = StarChart.CastSky(Array(three.prefix(2)), world: .duo, layout: lab.layout)
        let night = three[1].up
        XCTAssertFalse(two.isFree(left(of: night, by: 5.5), fourPoint: false))
        XCTAssertTrue(two.isFree(left(of: night, by: 5.7), fourPoint: false))
        XCTAssertFalse(two.isFree(left(of: night, by: 10.5), fourPoint: true))
        XCTAssertTrue(two.isFree(left(of: night, by: 10.7), fourPoint: true))

        // A card's edge: a four-point star 10 pt inside the Today card's
        // foot (y 286.2) may stand, at 9.9 it may not; an ordinary night
        // may stand on the edge itself. And never in the 12 pt gap between
        // the Feed and Diaper tiles (x 185 – 197), where one stood.
        XCTAssertTrue(empty.isFree(CGPoint(x: 120, y: 286.2 - 10.1), fourPoint: true))
        XCTAssertFalse(empty.isFree(CGPoint(x: 120, y: 286.2 - 9.9), fourPoint: true))
        XCTAssertTrue(empty.isFree(CGPoint(x: 120, y: 286.2), fourPoint: false))
        XCTAssertFalse(empty.isFree(CGPoint(x: 191, y: 358), fourPoint: true, room: 20))
        XCTAssertTrue(empty.isFree(CGPoint(x: 191, y: 358), fourPoint: false))
    }

    func testTheFloorUnderHisStarsIsTheLabs() {
        // The lowest a star may sit: 8 pt over the skyline, 5 pt over the
        // tree's crown, 12 pt over the horizon — at every whole x of the
        // field and between.
        var checked = 0
        for kind in SkyWorld.Kind.allCases {
            let world = SkyWorld.world(kind)
            for row in SkyCoreFixture.words(Lab.land) where row.first == "\(kind.rawValue).floor" {
                guard let from = Double(row[1]), let dx = Double(row[2]) else { continue }
                for (i, text) in row.dropFirst(3).enumerated() {
                    let x = from + Double(i) + dx
                    XCTAssertEqual(StarChart.floor(at: x, world: world), Double(text) ?? .nan, accuracy: 1e-4, "\(kind) floor at \(x)")
                    checked += 1
                }
            }
            XCTAssertLessThanOrEqual(StarChart.floor(at: 100, world: world), Double(world.horizonUp) - 12)
            // over the tree it is the crown that holds them up: 5 pt over its top
            let trunk = Double(world.tree.x - world.turn)
            let crown = Skyline.of(kind).treeFoot(at: Double(world.tree.x)) + Double(world.drop) + (Skyline.crownTop(at: 0) ?? 0) * Double(world.tree.height)
            XCTAssertEqual(StarChart.floor(at: trunk, world: world), crown - 5, accuracy: 1e-9)
        }
        XCTAssertEqual(checked, 2 * (457 + 393))
    }

    func testEveryNightsOwnNumbersAreTheLabs() {
        // lab/nights.js: where the night is first cast (to the bit), how
        // strong and how warm its star, how it twinkles.
        let months = Set(fact("monthNights").compactMap { Int($0) })
        let rows = SkyCoreFixture.words(Lab.nights).dropFirst()
        // nights 1 – 160, every fourteenth after, and the last
        XCTAssertEqual(rows.count, 160 + 41 + 1)
        for row in rows {
            guard let number = Int(row[0]) else { continue }
            let night = StarChart.night(number, of: 731, monthNights: months)
            XCTAssertEqual(night.kind.rawValue, row[1], "night \(number)")
            XCTAssertEqual(night.u.bitPattern, SkyCoreFixture.double(bits: row[2]).bitPattern, "night \(number) u")
            XCTAssertEqual(night.v.bitPattern, SkyCoreFixture.double(bits: row[3]).bitPattern, "night \(number) v")
            XCTAssertEqual(night.magnitude, Double(row[4]) ?? .nan, accuracy: 1e-12, "night \(number)")
            XCTAssertEqual(night.warmth, Double(row[5]) ?? .nan, accuracy: 1e-12, "night \(number)")
            XCTAssertEqual(night.twinkle.period, Double(row[6]) ?? .nan, accuracy: 1e-12, "night \(number)")
            XCTAssertEqual(night.twinkle.phase, Double(row[7]) ?? .nan, accuracy: 1e-12, "night \(number)")
            XCTAssertEqual(night.twinkle.steady, row[8] == "1", "night \(number)")
        }
        // The lab's month-nights are every 30.44 days: nights 32, 62, 93 …
        XCTAssertEqual(Array(months.sorted().prefix(4)), [32, 62, 93, 123])
        XCTAssertEqual(months.count, 23)
    }

    func testTheLeadingPagesSkyIsTheLabs() {
        // Nobody's stars, on the open Duo's leading page: every place at
        // five ages, and at 142 days everything else about each.
        var head: [String] = []
        var tokens: [String] = []
        var pages = 0
        func close() {
            guard head.count > 3, let age = Int(head[2]) else { return }
            var facts: [String: String] = [:]
            for word in head.dropFirst(3) {
                let parts = word.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 { facts[parts[0]] = parts[1] }
            }
            var layout = sky("spread", age).layout
            layout.title = Self.rect(facts["title"])
            layout.subtitle = Self.rect(facts["subtitle"])
            let stars = StarChart.ordinarySky(nights: age + 1, world: .duo, layout: layout)
            XCTAssertEqual(stars.count, Int(facts["count"] ?? ""), "the leading page at \(age) days")
            XCTAssertEqual(stars.count, tokens.count)
            let sum = Self.pair(facts["sum"])
            XCTAssertEqual(stars.reduce(0) { $0 + Double($1.place.x) }, sum[0], accuracy: 1e-6, "at \(age) days")
            XCTAssertEqual(stars.reduce(0) { $0 + Double($1.place.y) }, sum[1], accuracy: 1e-6, "at \(age) days")
            for (i, (star, token)) in zip(stars, tokens).enumerated() {
                let parts = token.split(separator: ",").map(String.init)
                XCTAssertEqual(Double(star.place.x), (Double(parts[0]) ?? .nan) / 100, accuracy: 0.00501, "\(age) days, star \(i)")
                XCTAssertEqual(Double(star.place.y), (Double(parts[1]) ?? .nan) / 100, accuracy: 0.00501, "\(age) days, star \(i)")
                guard parts.count == 9 else { continue }
                XCTAssertEqual(star.brightness, Double(parts[2]) ?? .nan, accuracy: 1e-6)
                XCTAssertEqual(Double(star.radius), Double(parts[3]) ?? .nan, accuracy: 1e-6)
                XCTAssertEqual(star.strength, Double(parts[4]) ?? .nan, accuracy: 1e-6)
                XCTAssertEqual(star.tint.rawValue, parts[5])
                XCTAssertEqual(star.twinkle.phase, Double(parts[6]) ?? .nan, accuracy: 1e-6)
                XCTAssertEqual(star.twinkle.period, Double(parts[7]) ?? .nan, accuracy: 1e-6)
                XCTAssertEqual(star.twinkle.steady, parts[8] == "1")
            }
            // none of them is inside the anchor window, looking up or at rest:
            // the phone page's sky is his alone
            for star in stars {
                XCTAssertLessThan(Double(star.place.x), Double(SkyWorld.duo.turn))
                XCTAssertGreaterThanOrEqual(Double(star.place.x), -485)
            }
            pages += 1
        }
        for row in SkyCoreFixture.words(Lab.pages) {
            if row.first == "@" {
                close()
                head = row
                tokens = []
            } else {
                tokens.append(contentsOf: row)
            }
        }
        close()
        // (five ages, and 142 days once more behind a cut title: below)
        XCTAssertEqual(pages, 6)
    }

    func testTheLeadingPagesTitleKeepsPlainSkyPastItsLastGlyph() {
        // None of the page's stars stands behind its title, nor in the
        // 22 pt of plain sky past its last glyph. The lab cast 142 days
        // again behind a title cut to end so that one more star stands in
        // those 22 pt, by half a point: it gives way — one star fewer than
        // behind the page's own title — and with the title a point shorter
        // it is back.
        var own: Int?
        var cut: (title: CGRect, subtitle: CGRect?, count: Int)?
        for row in SkyCoreFixture.words(Lab.pages) where row.first == "@" && row.count > 3 && row[2] == "142" {
            var facts: [String: String] = [:]
            for word in row.dropFirst(3) {
                let parts = word.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 { facts[parts[0]] = parts[1] }
            }
            guard let count = Int(facts["count"] ?? ""), let title = Self.rect(facts["title"]) else { continue }
            if facts["cut"] == "1" { cut = (title, Self.rect(facts["subtitle"]), count) } else { own = count }
        }
        guard let own, let cut else { return XCTFail("the lab's two pages at 142 days") }
        XCTAssertEqual(cut.count, own - 1, "the lab's: one more star behind the cut title's plain sky")
        var layout = sky("spread", 142).layout
        layout.title = cut.title
        layout.subtitle = cut.subtitle
        XCTAssertEqual(StarChart.ordinarySky(nights: 143, world: .duo, layout: layout).count, cut.count)
        layout.title = CGRect(x: cut.title.minX, y: cut.title.minY, width: cut.title.width - 1, height: cut.title.height)
        XCTAssertEqual(StarChart.ordinarySky(nights: 143, world: .duo, layout: layout).count, own, "a point shorter, and the star is back")
    }

    func testTheLeadingPagesSkyFillsAsHisDoes() {
        // "A newborn's sky is not upstaged by the page beside it": 80 at
        // the least, 460 at the most, by his nights — and none where there
        // is no leading page.
        var layout = sky("spread", 142).layout
        layout.title = nil
        XCTAssertEqual(StarChart.ordinarySky(nights: 1, world: .duo, layout: layout).count, 80)
        XCTAssertEqual(StarChart.ordinarySky(nights: 143, world: .duo, layout: layout).count, 165)
        XCTAssertEqual(StarChart.ordinarySky(nights: 731, world: .duo, layout: layout).count, 460)
        XCTAssertEqual(StarChart.ordinarySky(nights: 5000, world: .duo, layout: layout).count, 460)
        XCTAssertTrue(StarChart.ordinarySky(nights: 143, world: .duo, layout: sky("cover", 142).layout).isEmpty)
        XCTAssertTrue(StarChart.ordinarySky(nights: 143, world: .slab, layout: sky("slab", 142).layout).isEmpty)
        // …and a star never changes as the sky fills: the first 80 are the newborn's.
        let few = StarChart.ordinarySky(nights: 1, world: .duo, layout: layout)
        let many = StarChart.ordinarySky(nights: 731, world: .duo, layout: layout)
        XCTAssertEqual(Array(many.prefix(80)), few)
    }

    // MARK: The design's rules

    func testANewNightMovesNoEarlierStar() {
        // Each night is judged only against the nights before it: through
        // his first year, on the Duo and on the slab, every earlier star
        // stands where it stood. (Tonight's star is the one
        // that changes: the next day it takes its permanent place among
        // the others.)
        for lab in [sky("cover", 142), sky("slab", 142)] {
            let months = Set(fact("monthNights").compactMap { Int($0) })
            var before = StarChart.cast(nights: 1, monthNights: months, world: lab.world, layout: lab.layout)
            // (night by night to 150, then ten nights at a time)
            for nights in Array(2...150) + Array(stride(from: 160, through: 370, by: 10)) {
                let after = StarChart.cast(nights: nights, monthNights: months, world: lab.world, layout: lab.layout)
                XCTAssertEqual(after.count, nights)
                for (was, now) in zip(before.dropLast(), after) {
                    guard was.up == now.up, was.rest == now.rest, was.kind == now.kind, was.again == now.again else {
                        XCTFail("\(lab.displayName): night \(nights) moved night \(was.night)")
                        return
                    }
                }
                XCTAssertNotEqual(after[before.count - 1].kind, .tonight, "last night's star has joined the rest")
                before = after
            }
        }
        // …and in the lab's own lists: the day after the default day, and
        // the day after his first year (the layout is the same on both).
        for (a, b) in [(142, 143), (367, 368)] {
            for display in ["cover", "spread", "slab"] {
                let one = sky(display, a), next = sky(display, b)
                XCTAssertEqual(one.layout, next.layout, "\(display) \(a) and \(b)")
                for (i, (was, now)) in zip(one.stars.dropLast(), next.stars).enumerated() {
                    XCTAssertEqual(was.x, now.x, "\(display): night \(i + 1) at \(a) and \(b) days")
                    XCTAssertEqual(was.y, now.y, "\(display): night \(i + 1) at \(a) and \(b) days")
                }
            }
        }
    }

    func testTonightsStarTakesNobodysPlace() {
        // It is the last of the list, at its two homes, whatever else the
        // night is — on his first night the only star, and on a
        // month-birthday's night still tonight's. Lit or not it moves no
        // other: the lab cast every sky both ways and found the same.
        XCTAssertEqual(fact("sameBeforeHeIsDown"), ["42"])
        for lab in drawn {
            let stars = lab.cast()
            guard let tonight = stars.last else { return XCTFail(lab.title) }
            XCTAssertEqual(tonight.kind, .tonight, lab.title)
            XCTAssertEqual(tonight.up, lab.world.tonightUp, lab.title)
            XCTAssertEqual(tonight.rest, lab.world.tonight, lab.title)
            XCTAssertEqual(tonight.magnitude, 0.92)
            XCTAssertEqual(tonight.warmth, 1)
            XCTAssertEqual(stars.filter { $0.kind == .tonight }.count, 1, lab.title)
        }
        XCTAssertEqual(sky("cover", 0).cast().map(\.kind), [.tonight], "his first night: one star, tonight's")
        XCTAssertTrue(sky("cover", 61).monthNights.contains(32))
        XCTAssertEqual(StarChart.night(62, of: 62, monthNights: [32, 62]).kind, .tonight)
        XCTAssertEqual(StarChart.night(62, of: 63, monthNights: [32, 62]).kind, .month)
        XCTAssertTrue(StarChart.cast(nights: 0, monthNights: [], world: .duo, layout: sky("cover", 0).layout).isEmpty)
    }

    func testNoStarStandsBehindTheHeaderTheStripOrTheCapsule() {
        // None inside the name, the age line, the avatar or the gear —
        // looking up, where they are, or at rest, where the header shows
        // that part of the sky — nor in the Duo's clock, island and status
        // icons, its capsule, or under the slab's status bar. Tonight's
        // star alone has a home (the clear window is its own).
        for lab in Self.skies {
            let world = lab.world
            let ox = lab.layout.anchorX
            let words = [lab.layout.name, lab.layout.age, lab.layout.avatar, lab.layout.gear].compactMap { $0 }
                .map { $0.offsetBy(dx: -ox, dy: 0) }
            let outs = StarChart.keepOuts(world: world, layout: lab.layout)
            for star in lab.cast() where star.kind != .tonight {
                // (a sky past two years can leave a night nowhere to go: it
                // stands where it was first cast, and is not claimed for)
                if star.foundNoPlace { continue }
                for rect in words {
                    XCTAssertFalse(rect.contains(star.up), "\(lab.title): night \(star.night) behind the header, looking up")
                    XCTAssertFalse(rect.contains(star.rest), "\(lab.title): night \(star.night) behind the header, at rest")
                }
                for out in outs {
                    XCTAssertFalse(Double(star.up.x) > out.x0 && Double(star.up.x) < out.x1 && Double(star.up.y) > out.y0 && Double(star.up.y) < out.y1,
                                   "\(lab.title): night \(star.night) at \(star.up) in a keep-out")
                }
                switch world.kind {
                case .duo:
                    let strip = (lab.layout.stripWindow.map { $0 - ox } ?? 362) + 20
                    if star.up.x > strip {
                        XCTAssertFalse(star.up.y < 192, "\(lab.title): night \(star.night) in the clock, the island or the status icons")
                    }
                    if star.up.x > strip + 4 {
                        XCTAssertFalse(star.up.y > 388 && star.up.y < 652, "\(lab.title): night \(star.night) in the capsule")
                    }
                case .slab:
                    XCTAssertGreaterThanOrEqual(star.up.y, 64, "\(lab.title): night \(star.night) under the status bar")
                }
            }
        }
    }

    func testAFourPointStarKeepsFurtherFromTheWords() {
        // "Beside a line of text it is an asterisk": 9 pt more than an
        // ordinary night, from every keep-out.
        for lab in drawn {
            let outs = StarChart.keepOuts(world: lab.world, layout: lab.layout)
            for star in lab.cast() where star.kind == .month || (star.kind == .first && star.up != lab.world.firstNightUp) {
                for out in outs {
                    let x = Double(star.up.x), y = Double(star.up.y)
                    XCTAssertFalse(x > out.x0 - 9 && x < out.x1 + 9 && y > out.y0 - 9 && y < out.y1 + 9,
                                   "\(lab.title): night \(star.night)")
                }
            }
        }
    }

    func testNoStarIsInTheLandOrTheTreesCrown() {
        for lab in drawn {
            for star in lab.cast() where star.kind != .tonight {
                XCTAssertLessThanOrEqual(Double(star.up.y), StarChart.floor(at: Double(star.up.x), world: lab.world),
                                         "\(lab.title): night \(star.night)")
                XCTAssertLessThanOrEqual(Double(star.up.y), Double(lab.world.horizonUp) - 12, lab.title)
                XCTAssertGreaterThanOrEqual(Double(star.up.x), Double(lab.world.starInset))
                XCTAssertLessThanOrEqual(Double(star.up.x), Double(lab.world.anchor.width - lab.world.starInset))
                XCTAssertGreaterThanOrEqual(Double(star.up.y), Double(lab.world.starTop))
            }
        }
    }

    func testNoTwoStarsAreCloserThanFivePointSix() {
        // "≥ 5.6 pt apart on every device" (on the light page two stars'
        // soft patches would run together) — and 5 pt more round a
        // four-point star or tonight's.
        for lab in drawn {
            let stars = lab.cast()
            var nearest = Double.infinity
            for (i, a) in stars.enumerated() {
                for b in stars[..<i] {
                    let d = distance(a.up, b.up)
                    nearest = min(nearest, d)
                    if a.isFourPoint || b.isFourPoint {
                        XCTAssertGreaterThanOrEqual(d, 10.6 - 1e-9, "\(lab.title): nights \(b.night) and \(a.night)")
                    }
                }
            }
            if stars.count > 1 {
                XCTAssertGreaterThanOrEqual(nearest, 5.6 - 1e-9, lab.title)
            }
        }
    }

    func testTonightsStarHasItsDarkSky() {
        // In the clear window nothing stands within 30 pt of it (27 on the
        // slab, whose stars are a tenth smaller) and no four-point star
        // within 70 — "nothing near it can be taken for it"; beside the
        // tree, at rest, a smaller clearing of 17 pt.
        for lab in drawn {
            let world = lab.world
            for star in lab.cast() where star.kind != .tonight {
                let up = distance(star.up, world.tonightUp)
                XCTAssertGreaterThanOrEqual(up, 30 * Double(world.starScale) - 1e-9, "\(lab.title): night \(star.night)")
                if star.isFourPoint && star.up != world.firstNightUp {
                    XCTAssertGreaterThanOrEqual(up, 70 - 1e-9, "\(lab.title): night \(star.night), a four-point star")
                }
                XCTAssertGreaterThanOrEqual(distance(star.rest, world.tonight), 17 - 1e-9, "\(lab.title): night \(star.night), at rest")
            }
        }
        XCTAssertEqual(SkyWorld.slab.starScale * 30, 27, accuracy: 1e-9)
    }

    func testTheFirstNightsStarHasAPlaceOfItsOwnOnTheDuo() {
        // In the header's clear gap, between his name and the gear: no star
        // within 18 pt of it and no other four-point star within 60 pt, "at
        // two years as on the first day".
        for display in ["cover", "spread"] {
            for age in [1, 7, 142, 368, 730] {
                let lab = sky(display, age)
                let stars = lab.cast()
                XCTAssertEqual(stars[0].kind, .first)
                XCTAssertEqual(stars[0].up, CGPoint(x: 262, y: 43), lab.title)
                XCTAssertEqual(stars[0].magnitude, 1, "the brightest star in his sky")
                for star in stars.dropFirst() {
                    XCTAssertGreaterThanOrEqual(distance(star.up, stars[0].up), 18 - 1e-9, "\(lab.title): night \(star.night)")
                    if star.kind == .month {
                        XCTAssertGreaterThanOrEqual(distance(star.up, stars[0].up), 60 - 1e-9, "\(lab.title): night \(star.night)")
                    }
                }
            }
        }
        // On the slab it has no place of its own: the one clear gap holds
        // tonight's star. It is wherever it was cast — (111, 170), under
        // the Today card when the cards are on.
        let slab = sky("slab", 142).cast()
        XCTAssertEqual(slab[0].kind, .first)
        XCTAssertEqual(Double(slab[0].up.x), 111.44, accuracy: 0.01)
        XCTAssertEqual(Double(slab[0].up.y), 169.60, accuracy: 0.01)
        XCTAssertNil(SkyWorld.slab.firstNightUp)
    }

    func testTheFirstNightsOwnPlaceIsAskedForAsAnOrdinaryNights() {
        // The first night's star has its own place "if that place is free
        // on this display" — free as for an ORDINARY night, though the star
        // is drawn with four points. So a name whose block ends 5 pt short
        // of the place, nearer than the 9 pt a four-point star otherwise
        // keeps from the words, does not send it away: the lab cast that
        // sky, and the star is in its place.
        guard let lab = Self.skies.first(where: { $0.name == "nameEnds" }), let own = lab.world.firstNightUp else {
            return XCTFail("no such sky")
        }
        let block = StarChart.keepOuts(world: lab.world, layout: lab.layout)[0]
        let short = Double(own.x) - block.x1
        XCTAssertGreaterThan(short, 0, "the words do not reach the place")
        XCTAssertLessThan(short, 9, "…but end nearer than a four-point star may stand to them")
        XCTAssertTrue(Double(own.y) > block.y0 && Double(own.y) < block.y1, "beside the words, not over them")
        XCTAssertEqual(lab.stars[0].kind, .first)
        XCTAssertEqual(lab.stars[0].x, Double(own.x), "the lab's first night")
        XCTAssertEqual(lab.stars[0].y, Double(own.y), "the lab's first night")
        let stars = lab.cast()
        XCTAssertEqual(stars[0].kind, .first)
        XCTAssertEqual(stars[0].up, own)
        XCTAssertEqual(stars[0].again, 0)
        // (a month-night could not stand there)
        let empty = StarChart.CastSky([], world: lab.world, layout: lab.layout)
        XCTAssertTrue(empty.isFree(own, fourPoint: false))
        XCTAssertFalse(empty.isFree(own, fourPoint: true, room: 20))
        // A name that runs on over the place takes it: the first night is
        // then cast like any other four-point star, somewhere else.
        guard let long = Self.skies.first(where: { $0.name == "longName" && $0.displayName == "cover" }) else {
            return XCTFail("no such sky")
        }
        XCTAssertEqual(long.cast()[0].kind, .first)
        XCTAssertNotEqual(long.cast()[0].up, own)
        XCTAssertNotEqual(long.stars[0].x, Double(own.x), "the lab's")
    }

    func testTheFirstNightsClearingIsRoundTheStarNotThePlace() {
        // "Nothing within 18 pt of it": of the STAR. Where its own place is
        // taken — here his name's block runs 2 pt past it — the first night
        // is cast like any other, and the place it could not take keeps no
        // clearing: a night may stand 14 pt beside it, as it may not where
        // the first night's star stands there.
        guard let own = SkyWorld.duo.firstNightUp else { return XCTFail("the Duo has a first-night place") }
        let lab = sky("cover", 142).layout
        var long = lab
        guard let name = lab.name else { return XCTFail("the lab's layout has his name") }
        // (the block ends 13 pt of clear sky and 7 pt of room past the name's last glyph)
        long.name = CGRect(x: name.minX, y: name.minY, width: own.x + 2 - 20 - name.minX, height: name.height)
        XCTAssertEqual(StarChart.keepOuts(world: .duo, layout: long)[0].x1, Double(own.x) + 2, accuracy: 1e-9)

        let beside = CGPoint(x: own.x + 14, y: own.y)
        let moved = StarChart.cast(nights: 2, monthNights: [], world: .duo, layout: long)
        XCTAssertEqual(moved.map(\.kind), [.first, .tonight])
        XCTAssertNotEqual(moved[0].up, own, "the place is behind his name")
        XCTAssertGreaterThan(distance(moved[0].up, beside), 18, "…and the star is nowhere near")
        XCTAssertTrue(StarChart.CastSky(moved, world: .duo, layout: long).isFree(beside, fourPoint: false))

        let kept = StarChart.cast(nights: 2, monthNights: [], world: .duo, layout: lab)
        XCTAssertEqual(kept[0].up, own)
        XCTAssertFalse(StarChart.CastSky(kept, world: .duo, layout: lab).isFree(beside, fourPoint: false))
    }

    func testANightFoundOnTheSpiralsLastStepHasFoundAPlace() {
        // An ordinary night is cast again 30 times, a four-point star 270
        // (90 for each room it may settle for); then the spiral's 480
        // steps. The 480th step is still a place found: only one more than
        // every try says there was nowhere.
        func star(_ kind: Star.Kind, again: Int) -> Star {
            Star(night: 9, kind: kind, up: .zero, rest: .zero, magnitude: 0.5, warmth: 0,
                 twinkle: StarChart.Twinkle(period: 3, phase: 0, steady: true), radius: 1, reach: 0, rank: 1, again: again)
        }
        XCTAssertFalse(star(.night, again: 0).foundNoPlace)
        XCTAssertFalse(star(.night, again: 30 + 480).foundNoPlace)
        XCTAssertTrue(star(.night, again: 30 + 481).foundNoPlace)
        XCTAssertFalse(star(.month, again: 30 + 481).foundNoPlace, "a four-point star has more casts")
        XCTAssertFalse(star(.month, again: 270 + 480).foundNoPlace)
        XCTAssertTrue(star(.month, again: 270 + 481).foundNoPlace)
        XCTAssertTrue(star(.first, again: 270 + 481).foundNoPlace)
        // The lab's own most is that one more: 751, a four-point star in a sky of 1,500 nights.
        XCTAssertEqual(fact("placed").last, "\(270 + 481)")
    }

    func testAStarIsInViewOnlyInsideTheWindow() {
        // The lab's census (`window.__hillPainted.stars`): a star is in view
        // LOOKING UP when it is more than 2 pt inside the anchor window's
        // sides and top and above the display's foot; AT REST by the same
        // sides and top (there the land is its foot). His stars are cast
        // well inside all of these, so no sky of the lab's stands at an
        // edge: the edges are asked here.
        func star(up: CGPoint = CGPoint(x: 100, y: 100), rest: CGPoint = CGPoint(x: 100, y: 100)) -> Star {
            Star(night: 9, kind: .night, up: up, rest: rest, magnitude: 0.5, warmth: 0,
                 twinkle: StarChart.Twinkle(period: 3, phase: 0, steady: true), radius: 1, reach: 0, rank: 1, again: 0)
        }
        let cover = SkyWorld.Display.cover, spread = SkyWorld.Display.spread
        XCTAssertTrue(star().isInViewLookingUp(cover))
        XCTAssertFalse(star(up: CGPoint(x: 2, y: 100)).isInViewLookingUp(cover), "at the leading side")
        XCTAssertFalse(star(up: CGPoint(x: 464, y: 100)).isInViewLookingUp(cover), "at the trailing side")
        XCTAssertFalse(star(up: CGPoint(x: 100, y: 2)).isInViewLookingUp(cover), "at the top")
        XCTAssertTrue(star(up: CGPoint(x: 100, y: 677)).isInViewLookingUp(cover))
        XCTAssertFalse(star(up: CGPoint(x: 100, y: 678)).isInViewLookingUp(cover), "at the foot")
        // (the spread is 9 pt shorter than the cover, and its anchor window as wide)
        XCTAssertTrue(star(up: CGPoint(x: 100, y: 670)).isInViewLookingUp(cover))
        XCTAssertFalse(star(up: CGPoint(x: 100, y: 670)).isInViewLookingUp(spread))
        XCTAssertFalse(star(up: CGPoint(x: 464, y: 100)).isInViewLookingUp(spread))
        XCTAssertTrue(star(rest: CGPoint(x: 3, y: 3)).isInViewAtRest(cover))
        XCTAssertFalse(star(rest: CGPoint(x: 2, y: 100)).isInViewAtRest(cover), "at the leading side")
        XCTAssertFalse(star(rest: CGPoint(x: 464, y: 100)).isInViewAtRest(cover), "at the trailing side")
        XCTAssertFalse(star(rest: CGPoint(x: 100, y: 2)).isInViewAtRest(cover), "above the top: most of his stars, at rest")
        XCTAssertFalse(star(rest: CGPoint(x: 100, y: -200)).isInViewAtRest(cover))
    }

    func testNoFourPointStarIsWithinTenPointsOfACardsEdge() {
        // "A four-point star is never at a card's edge": 10 pt from every
        // edge of every card of the lab's standing layouts — the night's
        // two, and the Today card at rest — so one is whole in the open or
        // well behind a card, never in a 12 pt gap; nor is one cut by the
        // display's own edge, in either pose.
        var marks = 0
        var nearest = Double.infinity
        for lab in drawn {
            let world = lab.world
            guard let today = world.labCards.first else { return XCTFail("no cards") }
            let atRest = today.offsetBy(dx: -world.turn, dy: world.drop)
            let width = Double(world.anchor.width)
            for star in lab.cast() where star.kind == .month || (star.kind == .first && star.up != world.firstNightUp) {
                for card in world.labCards + [atRest] {
                    let d = distance(star.up, toTheEdgeOf: card)
                    nearest = min(nearest, d)
                    XCTAssertGreaterThanOrEqual(d, 10 - 1e-9, "\(lab.title): night \(star.night) at \(star.up), \(d) pt from a card's edge")
                }
                // the display's own edges, looking up…
                XCTAssertGreaterThanOrEqual(Double(star.up.x), 7)
                XCTAssertLessThanOrEqual(Double(star.up.x), width - 7)
                XCTAssertGreaterThanOrEqual(Double(star.up.y), Double(world.starTop) + 2)
                // …and at rest: not across the top of the everyday view, nor its trailing side
                XCTAssertGreaterThanOrEqual(abs(Double(star.rest.y)), 9 - 1e-9, "\(lab.title): night \(star.night) is cut by the top of the rest view")
                if star.rest.y > -9 {
                    XCTAssertGreaterThanOrEqual(abs(Double(star.rest.x) - width), 7 - 1e-9, "\(lab.title): night \(star.night) is cut by the side of the rest view")
                }
                marks += 1
            }
        }
        XCTAssertGreaterThan(marks, 150)
        // "The nearest any comes to a card's edge is 10.0 pt."
        XCTAssertEqual(nearest, 10.0, accuracy: 0.05)
    }

    func testFourPointStarsAreNotNeighbours() {
        // 80 pt between two of them while the sky has the room — through
        // his first year on every display; at two years it settles for 60,
        // then 44, before it settles for a card's edge.
        func nearestPair(_ stars: [Star]) -> Double {
            let marks = stars.filter { $0.kind == .month || $0.kind == .first }
            var nearest = Double.infinity
            for (i, a) in marks.enumerated() {
                for b in marks[..<i] {
                    nearest = min(nearest, distance(a.up, b.up))
                }
            }
            return nearest
        }
        for lab in drawn {
            let stars = lab.cast()
            let marks = stars.filter { $0.kind == .month }
            guard marks.count > 1 || (marks.count == 1 && stars[0].kind == .first) else { continue }
            let settledFor = marks.map(\.again).max() ?? 0
            let room: Double = settledFor <= 90 ? 80 : settledFor <= 180 ? 60 : settledFor <= 270 ? 44 : 20
            // (the first night's own place is its own rule: 60 pt)
            let monthsOnly = nearestPair(marks)
            XCTAssertGreaterThanOrEqual(monthsOnly, room - 1e-9, lab.title)
            if lab.age <= 368 {
                XCTAssertEqual(room, 80, "through his first year the sky has the room: \(lab.title)")
            }
        }
        // "Two four-point stars can still stand 44 pt apart at two years."
        for display in ["cover", "slab"] {
            let months = sky(display, 730).cast().filter { $0.kind == .month }
            XCTAssertEqual(months.count, 23)
            XCTAssertGreaterThanOrEqual(nearestPair(months), 44 - 1e-9)
            XCTAssertLessThan(nearestPair(months), 80)
        }
    }

    func testTheCoverAndTheSpreadsPhonePageAreOneSky() {
        // The spread's phone page is the cover's picture: the same stars in
        // the same places, the layout being the same 485 pt to the right.
        for age in [142, 368, 730] {
            let cover = sky("cover", age).cast(), spread = sky("spread", age).cast()
            XCTAssertEqual(cover.count, spread.count)
            for (a, b) in zip(cover, spread) {
                XCTAssertEqual(a.up.x, b.up.x, accuracy: 1e-9, "night \(a.night) at \(age) days")
                XCTAssertEqual(a.up.y, b.up.y, accuracy: 1e-9, "night \(a.night) at \(age) days")
            }
        }
    }

    func testTheCardsAreTheLayoutsWhereItTellsThem() {
        // What a four-point star keeps clear of is the layout's own table
        // of cards, in display points like the rest of it; told the lab's
        // table (485 pt to the right on the spread), the sky is the lab's.
        let lab = sky("spread", 368)
        var told = lab.layout
        told.cards = SkyWorld.duo.labCards.map { $0.offsetBy(dx: lab.layout.anchorX, dy: 0) }
        let stars = StarChart.cast(nights: 369, monthNights: lab.monthNights, world: .duo, layout: told)
        for (a, b) in zip(stars, lab.cast()) {
            XCTAssertEqual(a.up.x, b.up.x, accuracy: 1e-9, "night \(a.night)")
            XCTAssertEqual(a.up.y, b.up.y, accuracy: 1e-9, "night \(a.night)")
        }
        // …and with no cards at all a month-night may stand where a card's
        // edge would have sent it away: night 62 goes back to the gap
        // between the Feed and Diaper tiles — (190.5, 358.1), "the app's
        // own sparkle mark".
        var none = sky("cover", 142).layout
        none.cards = []
        let open = StarChart.cast(nights: 143, monthNights: sky("cover", 142).monthNights, world: .duo, layout: none)
        XCTAssertTrue(open.contains { $0.kind == .month && abs(Double($0.up.x) - 190.5) < 0.051 && abs(Double($0.up.y) - 358.1) < 0.051 })
    }

    func testAHeaderWithNoWordsStillKeepsItsButtonsClear() {
        // Before the name is measured the avatar keeps 2 pt and the gear 3.
        guard let lab = Self.skies.first(where: { $0.name == "buttons" }) else { return XCTFail("no such sky") }
        XCTAssertNil(lab.layout.name)
        let outs = StarChart.keepOuts(world: lab.world, layout: lab.layout)
        XCTAssertEqual(outs.count, 7)
        XCTAssertEqual(outs[0].x0, 18, accuracy: 1e-9)
        XCTAssertEqual(outs[0].x1, 82, accuracy: 1e-9)
        XCTAssertEqual(outs[2].x0, 315, accuracy: 1e-9)
        // …and with nothing told at all only the strip's furniture is kept
        // clear (the lab's own strip window, 362 pt in).
        guard let bare = Self.skies.first(where: { $0.name == "bare" && $0.displayName == "cover" }) else { return XCTFail("no such sky") }
        XCTAssertNil(bare.layout.stripWindow)
        XCTAssertEqual(StarChart.keepOuts(world: .duo, layout: bare.layout).map(\.x0), [380, 300, 386])
        XCTAssertEqual(StarChart.keepOuts(world: .slab, layout: StarChart.Layout()).map(\.y1), [64])
    }

    func testTheSkysOwnNotesStillHold() {
        // What the sky's author measured on the lab's page when these
        // rules were set (skies/hill-painted.md, "His stars"), found again
        // in the app's sky at 142 days.
        let cover = sky("cover", 142), slab = sky("slab", 142)
        let stars = cover.cast()
        func stands(_ star: Star, _ x: Double, _ y: Double) -> Bool {
            abs(Double(star.up.x) - x) < 0.051 && abs(Double(star.up.y) - y) < 0.051
        }
        // "At 142 nights two month-stars moved on the Duo for it — (190.5,
        // 358.1) → (224.2, 257.9), and (288.6, 316.8) → (153.2, 215.3)":
        // one stood in the gap between the Feed and Diaper tiles, the app's
        // own sparkle mark; "no ordinary star moved, and the count is what
        // it was".
        let months = stars.filter { $0.kind == .month }
        XCTAssertEqual(months.count, 4)
        XCTAssertTrue(months.contains { stands($0, 224.2, 257.9) && $0.again > 0 })
        XCTAssertTrue(months.contains { stands($0, 153.2, 215.3) && $0.again > 0 })
        XCTAssertFalse(stars.contains { stands($0, 190.5, 358.1) || stands($0, 288.6, 316.8) })
        // "With the cards on, 12 stand in the strip's clear window,
        // tonight's among them" (x from 362, between the status icons at
        // y 185 while he sleeps and the capsule at 396)…
        let window = stars.filter { $0.up.x > 362 && $0.up.y > 185 && $0.up.y < 396 }
        XCTAssertEqual(window.count, 12)
        XCTAssertTrue(window.contains { $0.kind == .tonight })
        // "…and 9 in the header's gap, the first night's among them" —
        // between the end of his name and the gear, over the first card…
        func gap(_ lab: LabSky, _ stars: [Star]) -> [Star] {
            guard let name = lab.layout.name, let gear = lab.layout.gear, let today = lab.world.labCards.first else { return [] }
            return stars.filter { $0.up.x > name.maxX && $0.up.x < gear.minX && $0.up.y < today.minY }
        }
        XCTAssertEqual(gap(cover, stars).count, 9)
        XCTAssertTrue(gap(cover, stars).contains { $0.kind == .first })
        // "…7 on the slab, tonight's among them."
        let slabs = gap(slab, slab.cast())
        XCTAssertEqual(slabs.count, 7)
        XCTAssertTrue(slabs.contains { $0.kind == .tonight })
        // The first night's star: "its nearest neighbour is 21.0, 20.5 and
        // 19.4 pt away at 142, 368 and 730 nights".
        for (age, nearest) in [(142, 21.0), (368, 20.5), (730, 19.4)] {
            let sky = sky("cover", age).cast()
            XCTAssertEqual(sky.dropFirst().map { distance($0.up, sky[0].up) }.min() ?? 0, nearest, accuracy: 0.05, "at \(age) days")
        }
    }

    // MARK: Rank, size and light

    func testTheOrderOfRank() {
        // "Tonight's star, then the first night's, then the month-nights,
        // then the ordinary nights" — and among those the strongest first.
        for lab in [sky("cover", 142), sky("slab", 368), sky("cover", 730)] {
            let stars = lab.cast()
            let ranked = stars.sorted { $0.rank < $1.rank }
            XCTAssertEqual(ranked.map(\.rank), Array(1...stars.count), lab.title)
            XCTAssertEqual(ranked[0].kind, .tonight)
            XCTAssertEqual(ranked[1].kind, .first)
            let months = lab.monthNights.count
            XCTAssertTrue(ranked[2..<(2 + months)].allSatisfy { $0.kind == .month }, lab.title)
            let ordinary = ranked[(2 + months)...]
            XCTAssertTrue(ordinary.allSatisfy { $0.kind == .night }, lab.title)
            for (a, b) in zip(ordinary, ordinary.dropFirst()) {
                XCTAssertGreaterThanOrEqual(a.magnitude, b.magnitude, lab.title)
            }
            // …and of two equal lights (every month-night's is 0.78) the
            // earlier night stands first: the order is the same on every phone.
            let monthNights = ranked[2..<(2 + months)].map(\.night)
            XCTAssertEqual(monthNights, monthNights.sorted(), lab.title)
            XCTAssertGreaterThan(monthNights.count, 1, lab.title)
            // by class of light it is the same order
            for (a, b) in zip(ranked, ranked.dropFirst()) {
                XCTAssertGreaterThanOrEqual(a.light, b.light, lab.title)
            }
        }
        XCTAssertEqual(Star.Light.allCases, [.ordinary, .brighter, .monthNight, .firstNight, .tonight])
    }

    func testAMonthNightIsNeverAGhost() {
        // The first night is the brightest star in his sky (1), tonight
        // 0.92, a month-night 0.78 — over the brightest ordinary night
        // (0.72 at the most): out before any of them as the sky darkens.
        let stars = sky("cover", 368).cast()
        let ordinary = stars.filter { $0.kind == .night }
        XCTAssertEqual(stars.filter { $0.kind == .month }.map(\.magnitude), Array(repeating: 0.78, count: 12))
        XCTAssertLessThanOrEqual(ordinary.map(\.magnitude).max() ?? 1, 0.72)
        XCTAssertGreaterThanOrEqual(ordinary.map(\.magnitude).min() ?? 0, 0.22)
        for star in ordinary {
            XCTAssertGreaterThan(star.comesOut, (1 - 0.78) * 0.8)
            XCTAssertEqual(star.comesOut, (1 - star.magnitude) * 0.8, accuracy: 1e-12)
        }
        // Most nights are small faint lights, a few are bright.
        XCTAssertGreaterThan(Double(ordinary.filter { $0.brightness < 0.25 }.count) / Double(ordinary.count), 0.5)
        // A four-point star's light is past the top of the ordinary range:
        // its brightness is held at 1, as the lab holds its `m`.
        for star in stars where star.isFourPoint {
            XCTAssertEqual(star.brightness, 1, "\(star.kind)")
        }
        XCTAssertEqual(stars.filter(\.isFourPoint).count, 12 + 2)
    }

    func testTheBrighterFifthHaveALargerCore() {
        // "The brighter fifth: 21 % of his ordinary nights at a year" — and
        // the brightest tenth (11 %) keep the core once his sky is dense.
        let ordinary = sky("cover", 368).cast().filter { $0.kind == .night }
        let fifth = Double(ordinary.filter { $0.light == .brighter }.count) / Double(ordinary.count)
        let tenth = Double(ordinary.filter { $0.brightness > 0.76 }.count) / Double(ordinary.count)
        XCTAssertEqual(fifth, 0.21, accuracy: 0.01)
        XCTAssertEqual(tenth, 0.11, accuracy: 0.01)
        XCTAssertEqual(StarChart.brighterFrom, 0.6)
        XCTAssertTrue(ordinary.allSatisfy { ($0.light == .brighter) == ($0.brightness > 0.6) })
    }

    func testEachStarsSize() {
        // An ordinary night is a round point of 0.52 – 1.15 pt (capped); a
        // month-night's mark about 10 × 13 pt, the first night's about
        // 16 pt across, tonight's the largest. The slab's are a tenth
        // smaller.
        let duo = sky("cover", 368).cast(), slab = sky("slab", 368).cast()
        for star in duo {
            switch star.kind {
            case .night:
                XCTAssertEqual(star.reach, 0)
                XCTAssertFalse(star.isFourPoint)
                XCTAssertGreaterThanOrEqual(star.radius, 0.52)
                XCTAssertLessThanOrEqual(star.radius, 1.15)
                XCTAssertEqual(Double(star.radius), min(1.15, 0.52 + 0.95 * pow(star.brightness, 0.85)), accuracy: 1e-12)
            case .month:
                XCTAssertEqual(star.reach, 9.8, accuracy: 1e-9)
                XCTAssertEqual(star.radius, 1.15, accuracy: 1e-9, "under glass or beside the moon it is the brightest ordinary night's point")
            case .first:
                XCTAssertEqual(star.reach, 12.04, accuracy: 1e-9)
            case .tonight:
                XCTAssertEqual(star.reach, 14, accuracy: 1e-9)
            }
            XCTAssertEqual(star.isFourPoint, star.reach > 0)
        }
        XCTAssertEqual(duo.filter { $0.kind == .night }.map(\.radius).max() ?? 0, 1.15, accuracy: 1e-9, "the brightest are at the cap")
        for (a, b) in zip(duo, slab) {
            XCTAssertEqual(b.radius, a.radius * 0.9, accuracy: 1e-9)
            XCTAssertEqual(b.reach, a.reach * 0.9, accuracy: 1e-9)
            XCTAssertEqual(a.twinkle, b.twinkle, "a night twinkles the same on every display")
            XCTAssertEqual(a.tint, b.tint)
        }
    }

    func testEachStarKeepsWhatTheDrawingWillAsk() {
        // Its swell (2.4 – 5.6 s, a third of them steady), and in the dark
        // print its tint: warm or cool by its warmth, and of the rest one
        // in ten is rose.
        let ordinary = sky("cover", 730).cast().filter { $0.kind == .night }
        for star in ordinary {
            XCTAssertGreaterThanOrEqual(star.twinkle.period, 2.4)
            XCTAssertLessThan(star.twinkle.period, 5.6)
            XCTAssertGreaterThanOrEqual(star.twinkle.phase, 0)
            XCTAssertLessThan(star.twinkle.phase, 1)
            XCTAssertLessThanOrEqual(abs(star.warmth), 0.55)
            XCTAssertEqual(star.steppingAside, SkyNoise.hash(star.night, salt: 9))
            switch star.tint {
            case .warm: XCTAssertGreaterThan(star.warmth, 0.3)
            case .cool: XCTAssertLessThan(star.warmth, -0.25)
            case .rose: XCTAssertGreaterThan(SkyNoise.hash(star.night, salt: 8), 0.9)
            case .plain: XCTAssertLessThanOrEqual(SkyNoise.hash(star.night, salt: 8), 0.9)
            }
        }
        let steady = Double(ordinary.filter(\.twinkle.steady).count) / Double(ordinary.count)
        XCTAssertEqual(steady, 0.35, accuracy: 0.05)
        let rose = Double(ordinary.filter { $0.tint == .rose }.count) / Double(ordinary.count)
        XCTAssertEqual(rose, 0.05, accuracy: 0.03)
    }

    func testTheMonthNightsAreToldNotCounted() {
        // The lab counts 30.44-day months; the app passes his real
        // month-birthdays' nights. The chart takes whichever it is told:
        // the night before or after is an ordinary night.
        let lab = sky("cover", 142)
        let told: Set<Int> = [31, 62, 92, 123]
        let stars = StarChart.cast(nights: 143, monthNights: told, world: .duo, layout: lab.layout)
        XCTAssertEqual(Set(stars.filter { $0.kind == .month }.map(\.night)), told)
        XCTAssertEqual(stars[31].kind, .night, "night 32 is the lab's month-night, not his")
        XCTAssertEqual(stars[0].kind, .first, "the first night is the first night's, whatever is told")
        XCTAssertEqual(StarChart.night(1, of: 143, monthNights: [1]).kind, .first)
        XCTAssertEqual(StarChart.night(31, of: 143, monthNights: told).magnitude, 0.78)
        // Telling it otherwise moves only what stands in a month-night's
        // way: the nights before the first difference keep their places.
        let labs = lab.cast()
        for (a, b) in zip(stars.prefix(30), labs.prefix(30)) {
            XCTAssertEqual(a.up, b.up)
        }
    }

    // MARK: With the app's own count

    func testTonightsSkyByTheAppsOwnCountKeepsEveryPromise() throws {
        // The whole chain as Home will ask it — 21 November 2026, 9 pm in
        // Chicago, born 2 July. `NightCount` says it is Night 143 and which
        // nights are his month-birthdays' (the 2nd of each month: 32, 63,
        // 93, 124 — from the second on, a night later than the lab's
        // 30.44-day months), and the chart casts that sky. It is not the
        // lab's sky star for star: a month-night told differently moves
        // what stands in its way. So the design's promises are asked of it
        // again, on all three displays: a star for every night, every one
        // in view looking up, a place found for each, the four-point stars
        // never neighbours, and tomorrow night moving none of tonight's.
        var chicagoTime = Calendar(identifier: .gregorian)
        chicagoTime.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
        let born = try XCTUnwrap(chicagoTime.date(from: DateComponents(year: 2026, month: 7, day: 2, hour: 15, minute: 42)))
        let now = try XCTUnwrap(chicagoTime.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 21)))
        let chicago = SkyPlace(latitude: 41.8781, longitude: -87.6298)

        let tonight = NightCount.night(at: now, born: born, place: chicago, calendar: chicagoTime)
        XCTAssertEqual(tonight, 143)
        let months = NightCount.monthNights(through: tonight, born: born, calendar: chicagoTime)
        XCTAssertEqual(months, [32, 63, 93, 124])
        XCTAssertEqual(Set(fact("monthNights").compactMap { Int($0) }.filter { $0 <= tonight }), [32, 62, 93, 123],
                       "the lab's, for comparison")

        for display in ["cover", "spread", "slab"] {
            let lab = sky(display, 142)
            let stars = StarChart.cast(nights: tonight, monthNights: months, world: lab.world, layout: lab.layout)
            XCTAssertEqual(stars.count, 143, display)
            XCTAssertEqual(stars.filter { $0.isInViewLookingUp(lab.display) }.count, 143, display)
            XCTAssertEqual(stars.first?.kind, .first, display)
            XCTAssertEqual(stars.last?.kind, .tonight, display)
            XCTAssertEqual(Set(stars.filter { $0.kind == .month }.map(\.night)), months, display)
            XCTAssertFalse(stars.contains { $0.foundNoPlace }, display)
            // The nights before the first difference stand where the lab's do.
            for (mine, labs) in zip(stars.prefix(61), lab.cast().prefix(61)) {
                XCTAssertEqual(mine.up, labs.up, "\(display): night \(mine.night)")
            }
            let marks = stars.filter { $0.kind == .month || $0.kind == .first }
            XCTAssertEqual(marks.count, 5, display)
            for (index, one) in marks.enumerated() {
                for other in marks.dropFirst(index + 1) {
                    XCTAssertGreaterThanOrEqual(distance(one.up, other.up), 80,
                                                "\(display): nights \(one.night) and \(other.night)")
                }
            }
            let next = StarChart.cast(nights: tonight + 1,
                                      monthNights: NightCount.monthNights(through: tonight + 1, born: born, calendar: chicagoTime),
                                      world: lab.world, layout: lab.layout)
            XCTAssertEqual(next.count, 144, display)
            for (was, then) in zip(stars.dropLast(), next) {
                XCTAssertEqual(was.up, then.up, "\(display): night \(was.night)")
                XCTAssertEqual(was.kind, then.kind, "\(display): night \(was.night)")
            }
        }
    }
}
