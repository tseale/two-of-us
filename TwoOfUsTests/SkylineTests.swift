import XCTest
@testable import TwoOfUs

/// The land's skyline (`Skyline`) against the sky lab's: the crest lines as
/// they were set by hand, and the skyline the lab's own code draws through
/// them — its height at every whole point of world x, to the bit — on the
/// Duo's world and the slab's (`SkyCoreFixturesStars.land`, exported by
/// `design/sky-lab/tools/swift-fixtures/stars.mjs` from the page's
/// `G.skyline`; the Duo's is read on the spread, which sees the whole world,
/// and the exporter stops if the cover's differs anywhere the cover looks).
final class SkylineTests: XCTestCase {
    private let land = SkyCoreFixture.words(SkyCoreFixturesStars.land)

    private func rows(_ key: String) -> [[String]] {
        land.filter { $0.first == key }
    }

    private func number(_ text: String, file: StaticString = #filePath, line: UInt = #line) -> Double {
        guard let value = Double(text) else {
            XCTFail("not a number: \(text)", file: file, line: line)
            return .nan
        }
        return value
    }

    // MARK: The crests

    func testEveryCrestUnderTheSkyIsAsTheLabSetIt() {
        // The shapes of the planes that sink and slide with the sky (sink 1),
        // less the valley floor, in the lab's order — each with the number
        // the hand's wobble is seeded by.
        for kind in SkyWorld.Kind.allCases {
            let shapes = rows("\(kind.rawValue).shape")
            let under = shapes.filter { $0[3] == "1" && $0[6] == "crest" }
            let mine = Skyline.of(kind).crests
            XCTAssertEqual(mine.map(\.id), under.map { $0[1] }, "\(kind)")
            XCTAssertEqual(under.count, kind == .duo ? 8 : 4)
            for (crest, row) in zip(mine, under) {
                XCTAssertEqual(crest.plane.rawValue, row[2], crest.id)
                XCTAssertEqual(crest.seed, Int(row[4]), crest.id)
                XCTAssertEqual(crest.wobble, number(row[5]), crest.id)
                let set = row.dropFirst(7).map { number($0) }
                XCTAssertEqual(set.count, crest.points.count * 2, crest.id)
                for (i, point) in crest.points.enumerated() where i * 2 + 1 < set.count {
                    XCTAssertEqual(Double(point.x), set[i * 2], "\(kind) \(crest.id) point \(i)")
                    XCTAssertEqual(Double(point.y), set[i * 2 + 1], "\(kind) \(crest.id) point \(i)")
                }
            }
        }
    }

    func testTheNearPlanesAndTheValleyFloorAreNotTheSkyline() {
        // The near planes slide faster than the sky when the camera looks
        // up, and the valley floor lies under the ridges: neither holds a
        // star up.
        for kind in SkyWorld.Kind.allCases {
            let world = SkyWorld.world(kind)
            let left = rows("\(kind.rawValue).shape").filter { $0[3] != "1" || $0[6] != "crest" }
            XCTAssertEqual(left.count, kind == .duo ? 3 : 3, "\(kind)")
            for row in left {
                XCTAssertFalse(Skyline.of(kind).crests.contains { $0.id == row[1] && $0.seed == Int(row[4]) }, row[1])
            }
            for crest in Skyline.of(kind).crests {
                XCTAssertEqual(world.plane(crest.plane).sink, 1, "\(crest.id) moves with the sky")
                XCTAssertEqual(world.plane(crest.plane).slide, 1, "\(crest.id) moves with the sky")
            }
        }
    }

    // MARK: The skyline

    func testTheSkylineIsTheLabsAtEveryPoint() {
        var checked = 0
        for kind in SkyWorld.Kind.allCases {
            let skyline = Skyline.of(kind)
            for row in rows("\(kind.rawValue).skyline") {
                let from = number(row[1])
                for (i, bits) in row.dropFirst(2).enumerated() {
                    let x = from + Double(i)
                    XCTAssertEqual(skyline.top(at: x), SkyCoreFixture.float(bits: bits), "\(kind) skyline at \(x)")
                    checked += 1
                }
            }
        }
        // The Duo's world runs from −560 to 660 and the slab's from −60 to
        // 560; three points more either side, where there is no land.
        XCTAssertEqual(checked, 1227 + 627)
        XCTAssertEqual(Skyline.duo.top(at: -563), .infinity)
        XCTAssertEqual(Skyline.slab.top(at: 563), .infinity)
    }

    func testTheLandIsReadAtTheNearestWholePoint() {
        // Half a point rounds UP, as the lab's `Math.round` does, on either
        // side of nought.
        for kind in SkyWorld.Kind.allCases {
            let samples = rows("\(kind.rawValue).at")
            XCTAssertEqual(samples.count, 10)
            for row in samples {
                XCTAssertEqual(Skyline.of(kind).top(at: number(row[1])), SkyCoreFixture.float(bits: row[2]), "\(kind) at \(row[1])")
            }
        }
        XCTAssertEqual(Skyline.duo.top(at: 100.5), Skyline.duo.top(at: 101))
        XCTAssertEqual(Skyline.duo.top(at: -1.5), Skyline.duo.top(at: -1))
        XCTAssertEqual(Skyline.duo.top(at: 100.49999), Skyline.duo.top(at: 100))
    }

    func testTheSkylineIsTheHighestCrest() {
        for kind in SkyWorld.Kind.allCases {
            let skyline = Skyline.of(kind)
            for x in stride(from: -40.0, through: 500, by: 7) {
                let highest = skyline.crests.map { skyline.height(of: $0.id, at: x) }.min() ?? .infinity
                XCTAssertEqual(skyline.top(at: x), highest)
            }
        }
        // Under the tree the far range is the skyline, not the knoll: the
        // knoll's summit lies a few points under the horizon, and the tree
        // stands up from it against the sky.
        XCTAssertEqual(Skyline.duo.top(at: 408), Skyline.duo.height(of: "range", at: 408))
        XCTAssertLessThan(Skyline.duo.top(at: 408), Skyline.duo.height(of: "knoll", at: 408))
        XCTAssertLessThan(Skyline.slab.top(at: 286), Skyline.slab.height(of: "knoll", at: 286))
        XCTAssertEqual(Skyline.duo.height(of: "meadow", at: 100), .infinity, "no such crest")
    }

    // MARK: The tree

    func testTheTreeStandsOnTheKnoll() {
        // Its foot is the knoll's crest under the trunk and 1.2 pt into the
        // ground — the lab's own number, to the bit; and the world's.
        for kind in SkyWorld.Kind.allCases {
            let world = SkyWorld.world(kind)
            let foot = Skyline.of(kind).treeFoot(at: Double(world.tree.x))
            let lab = SkyCoreFixture.double(bits: rows("\(kind.rawValue).treeFoot").first?[1] ?? "")
            XCTAssertEqual(foot.bitPattern, lab.bitPattern, "\(kind): \(foot) against the lab's \(lab)")
            XCTAssertEqual(foot, Double(world.tree.foot), accuracy: 0.0005, "\(kind): SkyWorld's own foot")
            // the hand's wobble moves the summit by less than a point
            XCTAssertEqual(foot - 1.2, Double(world.knollSummit.y), accuracy: 1.0)
        }
    }

    func testTheCrownsOutlineIsTheTrees() {
        // tree.js `crownTop`, every hundredth of the tree's height from 0.70
        // left of the trunk to 0.70 right of it.
        var checked = 0, beside = 0
        for row in rows("crown") {
            let from = number(row[1])
            for (i, bits) in row.dropFirst(2).enumerated() {
                let u = (from + Double(i)) / 100
                let top = Skyline.crownTop(at: u)
                if bits == "nil" {
                    XCTAssertNil(top, "beside the tree at \(u)")
                    beside += 1
                } else {
                    XCTAssertEqual(top?.bitPattern, SkyCoreFixture.double(bits: bits).bitPattern, "the crown at \(u)")
                }
                checked += 1
            }
        }
        XCTAssertEqual(checked, 141)
        XCTAssertGreaterThan(beside, 30)
        // It is highest over the leader, about 0.94 of the tree's height up.
        XCTAssertEqual(Skyline.crownTop(at: 0.04) ?? 0, -0.945, accuracy: 1e-9)
        XCTAssertNil(Skyline.crownTop(at: 0.6))
    }
}
