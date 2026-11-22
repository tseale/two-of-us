import XCTest
@testable import TwoOfUs

/// The two hand-set worlds of the painted hill (`SkyWorld`) against the sky
/// lab's own: every number is compared with what the lab's code says
/// (`SkyCoreFixturesMoment.world`, exported by
/// `design/sky-lab/tools/swift-fixtures/moment.mjs`), and every record the
/// lab exports must be read by a test — so a number changed in the lab, or
/// one added to its worlds, fails here rather than being found by eye.
final class SkyWorldTests: XCTestCase {
    /// The lab's records, and which of them a test has read.
    private final class Ledger {
        let records = SkyCoreFixture.records(SkyCoreFixturesMoment.world)
        private(set) var read: Set<String> = []

        func words(_ key: String, file: StaticString = #filePath, line: UInt = #line) -> [String] {
            read.insert(key)
            guard let values = records[key] else {
                XCTFail("the lab exports no \(key)", file: file, line: line)
                return []
            }
            return values
        }

        /// The numbers of a record; empty where the lab says `nil`.
        func numbers(_ key: String, file: StaticString = #filePath, line: UInt = #line) -> [Double] {
            let values = words(key, file: file, line: line)
            if values == ["nil"] { return [] }
            return values.map { Double($0) ?? .nan }
        }

        func unread(under prefix: String) -> [String] {
            records.keys.filter { $0.hasPrefix(prefix) && !read.contains($0) }.sorted()
        }
    }

    private func assertEqual(_ actual: [CGFloat], _ expected: [Double], _ what: String, accuracy: Double = 1e-6,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, "\(what): how many", file: file, line: line)
        for (got, want) in zip(actual, expected) {
            XCTAssertEqual(Double(got), want, accuracy: accuracy, what, file: file, line: line)
        }
    }

    // MARK: The lab's numbers

    func testEveryNumberOfTheDuosWorldIsTheLabs() {
        assertWorld(.duo, isTheLabs: "duo")
    }

    func testEveryNumberOfTheSlabsWorldIsTheLabs() {
        assertWorld(.slab, isTheLabs: "slab")
    }

    private func assertWorld(_ world: SkyWorld, isTheLabs k: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let lab = Ledger()
        func check(_ actual: [CGFloat], _ key: String, accuracy: Double = 1e-6) {
            assertEqual(actual, lab.numbers("\(k).\(key)"), "\(k).\(key)", accuracy: accuracy, file: file, line: line)
        }

        check([world.horizon], "H0")
        check([world.drop], "D")
        check([world.turn], "T")
        check([world.skySpan], "table")
        check([world.zenith], "Emax")
        check([world.anchor.width, world.anchor.height], "anchor")
        check([world.tree.x, world.tree.height], "tree")
        // (the foot is the knoll's wobbled crest under the trunk, read off the lab's page)
        check([world.tree.foot], "treeFoot", accuracy: 0.001)
        check([world.knollSummit.x, world.knollSummit.y], "knollSummit")
        check([world.tonight.x, world.tonight.y], "tonight")
        check([world.tonightUp.x, world.tonightUp.y], "tonightUp")
        check(world.firstNightUp.map { [$0.x, $0.y] } ?? [], "firstUp")
        check([world.sunRadius], "sunR")
        check([world.moonRadius], "moonR")
        check([world.starScale], "starScale")
        check(world.sets.map { [$0.sun, $0.moon] } ?? [], "sets")
        check([world.caption.origin.x, world.caption.origin.y, world.caption.size], "caption")
        check([world.skyTop, world.skyFoot], "tallSky")
        check([SkyWorld.marginLeading, SkyWorld.marginTrailing], "pad")
        check([world.starInset, world.anchor.width - world.starInset, world.starTop], "starField")
        check(world.labStripWindow.map { [$0] } ?? [], "stripWindow")

        // The planes, far to near, and the sky's own.
        check([world.sky.sink, world.sky.slide, world.sky.tilt.width, world.sky.tilt.height], "sky")
        XCTAssertEqual(world.planes.map(\.id.rawValue), lab.words("\(k).planes"), "the planes, far to near",
                       file: file, line: line)
        for plane in world.planes {
            check([plane.sink, plane.slide, plane.tilt.width, plane.tilt.height], "plane.\(plane.id.rawValue)")
        }

        // The clouds' tables.
        XCTAssertEqual(world.clouds.map(\.id), lab.words("\(k).clouds"), "the clouds", file: file, line: line)
        for cloud in world.clouds {
            let key = "\(k).cloud.\(cloud.id)"
            let words = lab.words(key, file: file, line: line)
            guard words.count == 10 else {
                XCTFail("\(key): the lab's cloud has \(words.count) fields", file: file, line: line)
                continue
            }
            assertEqual([cloud.x, cloud.lift, cloud.length, cloud.rise, cloud.span, CGFloat(cloud.period),
                         CGFloat(cloud.phase), cloud.wobble],
                        words.prefix(8).map { Double($0) ?? .nan }, key, file: file, line: line)
            XCTAssertEqual(cloud.belongs.rawValue, words[8], "\(key): the view it belongs to", file: file, line: line)
            XCTAssertEqual(cloud.high ? "high" : "low", words[9], key, file: file, line: line)
            check(cloud.top.flatMap { [$0.centre, $0.halfWidth, $0.height] }, "cloud.\(cloud.id).top")
        }

        // The lab's own layout: its cards, which are glass, its star boxes.
        check([CGFloat(world.labCards.count)], "cards")
        for (index, card) in world.labCards.enumerated() {
            check([card.minX, card.minY, card.maxX, card.maxY], "card.\(index)")
        }
        check(world.labGlass.map { CGFloat($0) }, "glass")
        let boxes = world.starBoxes()
        check([CGFloat(boxes.count)], "boxes")
        for (index, box) in boxes.enumerated() {
            check([box.x0, box.x1, box.y0, box.y1, CGFloat(box.density)], "box.\(index)")
            check(box.columns.flatMap { [$0.x0, $0.x1, CGFloat($0.weight)] }, "box.\(index).columns")
        }

        // What stays in the lab until the painting is ported — and nothing else.
        XCTAssertEqual(lab.words("\(k).notCarried"), ["river", "planes.shapes", "planes.mists"],
                       "the lab's world has a field SkyWorld does not carry", file: file, line: line)
        XCTAssertEqual(lab.unread(under: "\(k)."), [], "records of the lab's world no test reads",
                       file: file, line: line)
    }

    func testTheDisplaysAreTheLabs() {
        let lab = Ledger()
        let displays: [(String, SkyWorld.Display)] = [("cover", .cover), ("spread", .spread), ("slab", .slab)]
        for (name, display) in displays {
            let key = "display.\(name)"
            assertEqual([display.size.width, display.size.height], lab.numbers("\(key).size"), "\(key).size")
            assertEqual([display.anchorX, display.anchorWidth], lab.numbers("\(key).anchor"), "\(key).anchor")
            // The strip is a column on the trailing edge, or there is none.
            let strip = lab.words("\(key).strip")
            XCTAssertEqual(display.strip.map { ["trailing", String(Int($0))] } ?? ["nil"], strip, "\(key).strip")
            assertEqual(display.fold.map { [$0] } ?? [], lab.numbers("\(key).fold"), "\(key).fold")
            XCTAssertEqual([display.kind.rawValue], lab.words("\(key).world"), "\(key).world")
            XCTAssertEqual(display.world.kind, display.kind)
        }
        XCTAssertEqual(lab.unread(under: "display."), [], "display records no test reads")
    }

    // MARK: The design's rules

    func testTheCoverIsTheSpreadsPhonePage() {
        // One world, two windows: the spread's phone page is the cover's
        // picture, the same width, with the world running on to its left.
        XCTAssertEqual(SkyWorld.Display.cover.world, SkyWorld.Display.spread.world)
        XCTAssertEqual(SkyWorld.Display.cover.anchorWidth, SkyWorld.Display.spread.anchorWidth)
        XCTAssertEqual(SkyWorld.Display.cover.anchorX, 0)
        XCTAssertEqual(SkyWorld.Display.spread.anchorX + SkyWorld.Display.spread.anchorWidth,
                       SkyWorld.Display.spread.size.width, "the phone page is the spread's trailing page")
        XCTAssertNotEqual(SkyWorld.duo, SkyWorld.slab, "the slab is a world of its own")
        for display in [SkyWorld.Display.cover, .slab] {
            XCTAssertEqual(display.world.anchor, display.size, "the world is composed for its own display")
        }
    }

    func testLookingUpLowersTheHorizonToJustAboveTheCapsule() {
        // "Looking up lowers it this far (→ 604)"; the slab's "→ 770, just
        // above the floating capsule".
        XCTAssertEqual(SkyWorld.duo.horizonUp, 604)
        XCTAssertEqual(SkyWorld.slab.horizonUp, 770)
        for world in [SkyWorld.duo, .slab] {
            XCTAssertLessThan(world.horizonUp, world.anchor.height, "the land is still in view, looking up")
            // The tall sky covers the display in both poses: above the top of
            // the looked-up view, and under the horizon at rest.
            XCTAssertLessThan(world.skyTop + world.drop, 0)
            XCTAssertGreaterThan(world.skyFoot, world.horizon)
        }
    }

    func testTheNearPlanesTravelFasterThanTheSky() {
        for world in [SkyWorld.duo, .slab] {
            XCTAssertEqual(world.sky.sink, 1)
            XCTAssertEqual(world.sky.slide, 1)
            XCTAssertEqual(world.planes.map(\.id), [.far, .mid, .knoll, .near, .fore], "far to near")
            // The far ones go with the sky; the near ones faster.
            for (farther, nearer) in zip(world.planes, world.planes.dropFirst()) {
                XCTAssertGreaterThanOrEqual(nearer.sink, farther.sink)
                XCTAssertGreaterThanOrEqual(nearer.slide, farther.slide)
                XCTAssertGreaterThan(nearer.tilt.width, farther.tilt.width)
                XCTAssertGreaterThan(nearer.tilt.height, farther.tilt.height)
            }
            XCTAssertEqual(world.plane(.knoll).sink, 1, "the tree's knoll goes with the sky")
            XCTAssertGreaterThan(world.plane(.fore).sink, 1)
            XCTAssertLessThan(world.sky.tilt.width, 0, "the sky leans against the land")
            XCTAssertEqual(world.plane(.sky), world.sky)
        }
    }

    func testTheTreeStandsOnTheKnoll() {
        for world in [SkyWorld.duo, .slab] {
            XCTAssertEqual(world.tree.x, world.knollSummit.x, "the tree is on the top of the knoll")
            // Its foot is the crest there, a little into the ground: within a
            // few points of the hand-set summit (the hand's wobble).
            XCTAssertEqual(world.tree.foot, world.knollSummit.y, accuracy: 3)
            XCTAssertGreaterThan(world.tree.foot, world.horizon - 10, "the knoll stands at the horizon")
        }
    }

    func testTonightsStarRestsAboveTheTreesLeftShoulder() {
        for world in [SkyWorld.duo, .slab] {
            let crown = world.tree.foot - world.tree.height
            XCTAssertLessThan(world.tonight.x, world.tree.x, "left of the trunk")
            XCTAssertGreaterThan(world.tonight.x, world.tree.x - world.tree.height * 0.6, "…but by the tree")
            XCTAssertLessThan(world.tonight.y, crown, "above the crown")
        }
    }

    func testTonightsStarIsFindableWithTheCardsOn() {
        // "Tonight's star must be findable all night with the cards on": its
        // looked-up home stands clear of every card of the lab's table — in
        // the strip's clear window on the Duo, in the header band on a slab.
        for world in [SkyWorld.duo, .slab] {
            for card in world.labCards {
                XCTAssertFalse(card.insetBy(dx: -20, dy: -20).contains(world.tonightUp),
                               "\(world.kind): within 20 pt of a card")
            }
            XCTAssertLessThan(world.tonightUp.y, world.horizonUp, "in the sky, not on the land")
        }
        let duo = SkyWorld.duo
        XCTAssertGreaterThan(duo.tonightUp.x, try XCTUnwrap(duo.labStripWindow), "in the strip's window")
        XCTAssertLessThan(SkyWorld.slab.tonightUp.y, SkyWorld.slab.labCards[0].minY, "in the header band")
    }

    func testTheFirstNightsStarHasAPlaceOfItsOwnOnTheDuoOnly() throws {
        // In the header's clear gap, between his name and the gear: above
        // the first card, and inside the first star box (the gap's own).
        let first = try XCTUnwrap(SkyWorld.duo.firstNightUp)
        let gap = SkyWorld.duo.starBoxes()[0]
        XCTAssertTrue(first.x > gap.x0 && first.x < gap.x1 && first.y > gap.y0 && first.y < gap.y1)
        XCTAssertLessThan(first.y, SkyWorld.duo.labCards[0].minY)
        XCTAssertNil(SkyWorld.slab.firstNightUp, "the slab has no first-night place")
    }

    func testNothingStandsAmongHisStarsButOneLowCloud() {
        // The everyday view's clouds leave as the camera looks up; the
        // looked-up view has one broken bar, low, left of the tree.
        for world in [SkyWorld.duo, .slab] {
            let up = world.clouds.filter { $0.belongs == .up }
            XCTAssertEqual(up.count, 1)
            XCTAssertLessThan(up[0].x, world.tree.x, "left of the tree")
            XCTAssertLessThan(up[0].lift, 100, "low")
        }
        XCTAssertEqual(SkyWorld.duo.clouds.filter { $0.belongs == .rest }.map(\.id), ["strip", "gap"])
        XCTAssertEqual(SkyWorld.slab.clouds.count, 1, "no cloud in the slab's everyday view")
    }

    func testACloudIsAFewMassesOfUnequalSize() {
        for cloud in SkyWorld.duo.clouds + SkyWorld.slab.clouds {
            XCTAssertGreaterThanOrEqual(cloud.top.count, 5, cloud.id)
            XCTAssertEqual(cloud.top.map(\.height).max(), 1, "\(cloud.id): one mass is the whole rise")
            XCTAssertGreaterThan(Set(cloud.top.map(\.halfWidth)).count, 3, "\(cloud.id): never a run of like scallops")
            for mass in cloud.top {
                XCTAssertTrue(mass.centre >= -1 && mass.centre <= 1 && mass.height > 0 && mass.height <= 1, cloud.id)
            }
        }
    }

    func testTheStarBoxesRunFromTheTopOfTheSkyToTheLand() {
        for world in [SkyWorld.duo, .slab] {
            let boxes = world.starBoxes()
            XCTAssertEqual(boxes.first?.y0, world.starTop, "from the top")
            for (upper, lower) in zip(boxes, boxes.dropFirst()) {
                XCTAssertGreaterThanOrEqual(lower.y0, upper.y1, "top to bottom, never overlapping")
            }
            for box in boxes {
                XCTAssertLessThan(box.y1, world.horizonUp, "no star on the land")
                XCTAssertGreaterThanOrEqual(box.x0, world.starInset)
                XCTAssertLessThanOrEqual(box.x1, world.anchor.width - world.starInset)
                // Columns tile the box's width, side by side.
                if let first = box.columns.first, let last = box.columns.last {
                    XCTAssertEqual(first.x0, box.x0)
                    XCTAssertEqual(last.x1, box.x1)
                    for (left, right) in zip(box.columns, box.columns.dropFirst()) {
                        XCTAssertEqual(left.x1, right.x0)
                    }
                }
            }
            // The band the REST pose shows as the header starts where the
            // camera's drop puts the top of the everyday view.
            XCTAssertTrue(boxes.contains { $0.y0 == world.drop || $0.y1 == world.drop } || world.kind == .slab)
        }
    }

    func testTheStripsWindowMovesTheBoxesBesideIt() {
        // Where the strip's window begins is the layout's to say: the boxes
        // that end at it, or thin out in it, follow.
        let lab = SkyWorld.duo.starBoxes()
        let moved = SkyWorld.duo.starBoxes(stripWindow: 350)
        XCTAssertEqual(SkyWorld.duo.starBoxes(stripWindow: 362), lab, "the lab's own window")
        XCTAssertEqual(moved[0], lab[0], "the header's gap does not know the strip")
        XCTAssertEqual(moved[1].x1, lab[1].x1 - 12)
        XCTAssertEqual(moved[2].columns[0].x1, 350)
        XCTAssertEqual(moved[4].x1, lab[4].x1 - 12)
        XCTAssertEqual(SkyWorld.slab.starBoxes(stripWindow: 350), SkyWorld.slab.starBoxes(),
                       "a slab has no strip")
    }

    func testTheLabsGlassCardsAreAmongItsCards() {
        for world in [SkyWorld.duo, .slab] {
            XCTAssertEqual(world.labCards.count, 7, "three standing, two asleep, two awake")
            for index in world.labGlass { XCTAssertTrue(world.labCards.indices.contains(index)) }
            // The Today card is opaque; the Feed and Diaper tiles are glass.
            XCTAssertFalse(world.labGlass.contains(0))
            XCTAssertTrue(world.labGlass.contains(1) && world.labGlass.contains(2))
            for card in world.labCards {
                XCTAssertGreaterThanOrEqual(card.minX, 16)
                XCTAssertLessThanOrEqual(card.maxY, world.anchor.height)
            }
        }
    }
}
