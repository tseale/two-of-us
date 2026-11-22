import XCTest
@testable import TwoOfUs

/// The camera (`SkyCamera`) against the sky lab's: every plane's offset for a
/// look of 0, ¼, ½, ¾ and 1, on the cover, the spread and the slab at 1×, 2×
/// and 3×, as the lab's own `planeOffset` and `onGrid` gave them on its page
/// (`SkyCoreFixturesMoment.camera`, exported by
/// `design/sky-lab/tools/swift-fixtures/moment.mjs`); tonight's star between
/// its two homes (`tonight`); and what follows the look alone (`looks`).
final class SkyCameraTests: XCTestCase {
    // (Read once for the class: XCTest makes an instance for every test.)
    private static let cameraTable = SkyCoreFixture.Table(SkyCoreFixturesMoment.camera)
    private static let homesTable = SkyCoreFixture.Table(SkyCoreFixturesMoment.tonight)
    private static let looksTable = SkyCoreFixture.Table(SkyCoreFixturesMoment.looks)
    private var camera: SkyCoreFixture.Table { Self.cameraTable }
    private var homes: SkyCoreFixture.Table { Self.homesTable }
    private var looks: SkyCoreFixture.Table { Self.looksTable }

    private let displays: [String: SkyWorld.Display] = ["cover": .cover, "spread": .spread, "slab": .slab]

    /// One row of the lab's camera table, read.
    private struct Sample {
        let name: String
        let display: SkyWorld.Display
        let scale: Double
        let plane: SkyWorld.Plane
        let look: Double
        let tilt: CGSize
        /// `planeOffset`: where the lab's plane is, between pixels or not.
        let offset: CGSize
        /// …and as the lab places the layer (`onGrid`).
        let rested: CGSize
    }

    private func samples(file: StaticString = #filePath, line: UInt = #line) -> [Sample] {
        let all: [Sample] = camera.rows.compactMap { row in
            guard let display = displays[camera.text(row, "display")],
                  let id = SkyWorld.Plane.ID(rawValue: camera.text(row, "plane")) else { return nil }
            return Sample(
                name: "\(camera.text(row, "display")) @\(camera.text(row, "scale"))× \(id.rawValue) look \(camera.text(row, "look")) tilt \(camera.text(row, "tiltX")),\(camera.text(row, "tiltY"))",
                display: display,
                scale: camera.number(row, "scale"),
                plane: display.world.plane(id),
                look: camera.number(row, "look"),
                tilt: CGSize(width: camera.number(row, "tiltX"), height: camera.number(row, "tiltY")),
                offset: CGSize(width: camera.number(row, "x"), height: camera.number(row, "y")),
                rested: CGSize(width: camera.number(row, "restedX"), height: camera.number(row, "restedY")))
        }
        // 3 displays × 3 scales × 6 planes × 5 looks × 4 tilts
        XCTAssertEqual(all.count, 1080, "the lab's camera table", file: file, line: line)
        XCTAssertEqual(all.count, camera.rows.count, "a row names a display or a plane the app does not have",
                       file: file, line: line)
        return all
    }

    private func offset(_ sample: Sample) -> CGSize {
        SkyCamera.offset(of: sample.plane, look: sample.look, tilt: sample.tilt,
                         scale: sample.scale, world: sample.display.world)
    }

    // MARK: The planes

    func testEveryPlanesOffsetIsTheLabs() {
        // No tilt (the first version has none): the lab's offset exactly, at
        // every look, on every display and scale — and it is where the lab
        // places the layer, moving or still.
        let level = samples().filter { $0.tilt == .zero }
        XCTAssertEqual(level.count, 270)
        for sample in level {
            let got = offset(sample)
            XCTAssertEqual(got.width, sample.offset.width, accuracy: 1e-6, sample.name)
            XCTAssertEqual(got.height, sample.offset.height, accuracy: 1e-6, sample.name)
            XCTAssertEqual(got.width, sample.rested.width, accuracy: 1e-6, sample.name)
            XCTAssertEqual(got.height, sample.rested.height, accuracy: 1e-6, sample.name)
        }
    }

    func testLayersRestOnThePixelGrid() {
        // The near planes' looked-up offsets, 349.44 and 405.6 pt down, are
        // not on any pixel grid: 349.44 becomes 349.5 at 2×.
        let near = SkyWorld.duo.plane(.near), fore = SkyWorld.duo.plane(.fore)
        XCTAssertEqual(SkyWorld.duo.drop * near.sink, 349.44, accuracy: 1e-9)
        XCTAssertEqual(SkyCamera.offset(of: near, look: 1, scale: 2, world: .duo).height, 349.5, accuracy: 1e-9)
        XCTAssertEqual(SkyCamera.offset(of: fore, look: 1, scale: 2, world: .duo).height, 405.5, accuracy: 1e-9)
        XCTAssertEqual(SkyCamera.offset(of: fore, look: 1, scale: 2, world: .duo).width, -112.5, accuracy: 1e-9)
        XCTAssertEqual(SkyCamera.offset(of: near, look: 1, scale: 3, world: .duo).height, 1048.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(SkyCamera.offset(of: fore, look: 1, scale: 3, world: .duo).height, 1217.0 / 3, accuracy: 1e-9)
        // The slab's: 693 and 787.5 down, 33 and 36 left.
        XCTAssertEqual(SkyCamera.offset(of: SkyWorld.slab.plane(.near), look: 1, scale: 2, world: .slab),
                       CGSize(width: -33, height: 693))
        XCTAssertEqual(SkyCamera.offset(of: SkyWorld.slab.plane(.fore), look: 1, scale: 2, world: .slab),
                       CGSize(width: -36, height: 787.5))

        // At either pose every layer is on whole device pixels — under a tilt
        // too — and it is the pixel the lab puts it on.
        for sample in samples() where sample.look == 0 || sample.look == 1 {
            let got = offset(sample)
            for (points, lab) in [(got.width, sample.rested.width), (got.height, sample.rested.height)] {
                let pixels = Double(points) * sample.scale
                XCTAssertEqual(pixels, pixels.rounded(), accuracy: 1e-6, "\(sample.name): between pixels at rest")
                XCTAssertEqual(Double(points), Double(lab), accuracy: 1e-6, sample.name)
            }
        }
    }

    func testDuringAMoveALayerTravelsBetweenPixels() {
        // On the way the offset is not rounded: three tenths of the way up,
        // the Duo's near plane at 3× is 314.4 pixels down, as it is in the lab.
        let onTheWay = SkyCamera.offset(of: SkyWorld.duo.plane(.near), look: 0.3, scale: 3, world: .duo)
        XCTAssertEqual(Double(onTheWay.height) * 3, 314.4, accuracy: 1e-9)

        // Under a tilt the move still runs between the two rested offsets —
        // never more than half a pixel from where the lab's plane is…
        for sample in samples() where sample.look > 0 && sample.look < 1 {
            let got = offset(sample)
            let halfAPixel = CGFloat(0.5 / sample.scale + 1e-6)
            XCTAssertEqual(got.width, sample.offset.width, accuracy: halfAPixel, sample.name)
            XCTAssertEqual(got.height, sample.offset.height, accuracy: halfAPixel, sample.name)
        }
        // …and no join jumps: the first frame of a move is the frame before
        // it, and its last frame is the standing frame that follows.
        let tilt = CGSize(width: 0.37, height: -0.61)
        for world in [SkyWorld.duo, .slab] {
            for plane in [world.sky] + world.planes {
                for scale in [2.0, 3.0] {
                    let rest = SkyCamera.offset(of: plane, look: 0, tilt: tilt, scale: scale, world: world)
                    let start = SkyCamera.offset(of: plane, look: 1e-9, tilt: tilt, scale: scale, world: world)
                    let end = SkyCamera.offset(of: plane, look: 1 - 1e-9, tilt: tilt, scale: scale, world: world)
                    let up = SkyCamera.offset(of: plane, look: 1, tilt: tilt, scale: scale, world: world)
                    XCTAssertEqual(start.width, rest.width, accuracy: 1e-5)
                    XCTAssertEqual(start.height, rest.height, accuracy: 1e-5)
                    XCTAssertEqual(end.width, up.width, accuracy: 1e-5)
                    XCTAssertEqual(end.height, up.height, accuracy: 1e-5)
                }
            }
        }
    }

    func testAPlanesTravelIsAWholeNumberOfPixels() {
        for world in [SkyWorld.duo, .slab] {
            for plane in [world.sky] + world.planes {
                for scale in [1.0, 2.0, 3.0] {
                    let travel = SkyCamera.travel(of: plane, scale: scale, world: world)
                    for points in [travel.width, travel.height] {
                        let pixels = Double(points) * scale
                        XCTAssertEqual(pixels, pixels.rounded(), accuracy: 1e-9)
                    }
                    // …within half a pixel of the hand-set travel, left and down.
                    let halfAPixel = CGFloat(0.5 / scale + 1e-9)
                    XCTAssertEqual(travel.width, -world.turn * plane.slide, accuracy: halfAPixel)
                    XCTAssertEqual(travel.height, world.drop * plane.sink, accuracy: halfAPixel)
                    XCTAssertEqual(SkyCamera.offset(of: plane, look: 1, scale: scale, world: world), travel)
                    XCTAssertEqual(SkyCamera.offset(of: plane, look: 0, scale: scale, world: world), .zero)
                }
            }
        }
    }

    func testTheFarWorldGoesWithTheSkyAndTheNearPlanesFaster() {
        for world in [SkyWorld.duo, .slab] {
            for look in [0.25, 0.5, 1.0] {
                let sky = SkyCamera.offset(of: world.sky, look: look, scale: 3, world: world)
                XCTAssertEqual(sky.width, -world.turn * CGFloat(look), accuracy: 1e-9)
                XCTAssertEqual(sky.height, world.drop * CGFloat(look), accuracy: 1e-9)
                for id in [SkyWorld.Plane.ID.far, .mid, .knoll] {
                    XCTAssertEqual(SkyCamera.offset(of: world.plane(id), look: look, scale: 3, world: world), sky)
                }
                let near = SkyCamera.offset(of: world.plane(.near), look: look, scale: 3, world: world)
                let fore = SkyCamera.offset(of: world.plane(.fore), look: look, scale: 3, world: world)
                XCTAssertGreaterThan(near.height, sky.height)
                XCTAssertGreaterThan(fore.height, near.height)
                XCTAssertLessThan(fore.width, near.width)
                XCTAssertLessThan(near.width, sky.width)
            }
        }
    }

    func testTheTurnTakesTheTreeClearOfTheTabCapsule() {
        // "The turn slides the far world this far left: the tree to x 318,
        // clear of the tab capsule (x 392 – 456) with the cards away."
        let duo = SkyWorld.duo
        let knoll = SkyCamera.offset(of: duo.plane(.knoll), look: 1, scale: 3, world: duo)
        XCTAssertEqual(duo.tree.x + knoll.width, 318, accuracy: 1e-9)
        XCTAssertEqual(duo.horizon + knoll.height, 604, accuracy: 1e-9)
    }

    func testALookOutsideItsRangeIsHeldAtAPose() {
        let near = SkyWorld.duo.plane(.near)
        XCTAssertEqual(SkyCamera.offset(of: near, look: -0.2, scale: 2, world: .duo), .zero)
        XCTAssertEqual(SkyCamera.offset(of: near, look: 1.3, scale: 2, world: .duo),
                       SkyCamera.travel(of: near, scale: 2, world: .duo))
        // A scale that is not one is taken as 1×: whole points.
        XCTAssertEqual(SkyCamera.travel(of: near, scale: 0, world: .duo), CGSize(width: -99, height: 349))
    }

    func testTheTiltLeansTheSkyAgainstTheLand() {
        // Tilt is not built in the first version; the parameter is kept, and
        // at a pose it is the lab's (the table's tilted rows, above). Each
        // plane has its own reach, the near ones further.
        let tilt = CGSize(width: 1, height: 1)
        let duo = SkyWorld.duo
        XCTAssertEqual(SkyCamera.offset(of: duo.sky, look: 0, tilt: tilt, scale: 1, world: duo),
                       CGSize(width: -1, height: -1), "−1.2 and −0.6 pt, on the 1× grid")
        XCTAssertEqual(SkyCamera.offset(of: duo.plane(.fore), look: 0, tilt: tilt, scale: 2, world: duo),
                       CGSize(width: 8, height: 3))
        // A tilt past ±1 is held there.
        XCTAssertEqual(SkyCamera.offset(of: duo.plane(.fore), look: 0, tilt: CGSize(width: 5, height: -5),
                                        scale: 2, world: duo), CGSize(width: 8, height: -3))
    }

    // MARK: Tonight's star

    func testTonightsStarTravelsBetweenItsTwoHomesAsInTheLab() {
        XCTAssertEqual(homes.rows.count, 180)   // 3 displays × 3 scales × 5 looks × 4 tilts
        for row in homes.rows {
            let name = homes.text(row, "display")
            guard let display = displays[name] else { return XCTFail("no display \(name)") }
            let tilt = CGSize(width: homes.number(row, "tiltX"), height: homes.number(row, "tiltY"))
            let home = SkyCamera.tonightHome(look: homes.number(row, "look"), tilt: tilt,
                                             world: display.world, anchorX: display.anchorX)
            XCTAssertEqual(Double(home.x), homes.number(row, "x"), accuracy: 1e-6, row.joined(separator: " "))
            XCTAssertEqual(Double(home.y), homes.number(row, "y"), accuracy: 1e-6, row.joined(separator: " "))
        }
    }

    func testTonightsStarIsStillWhereverTheViewComesToRest() {
        for display in [SkyWorld.Display.cover, .spread, .slab] {
            let world = display.world
            let rest = SkyCamera.tonightHome(look: 0, world: world, anchorX: display.anchorX)
            let up = SkyCamera.tonightHome(look: 1, world: world, anchorX: display.anchorX)
            // Above the tree's shoulder at rest; in its clear window looking up.
            XCTAssertEqual(rest, CGPoint(x: display.anchorX + world.tonight.x, y: world.tonight.y))
            XCTAssertEqual(up, CGPoint(x: display.anchorX + world.tonightUp.x, y: world.tonightUp.y))
            // A straight line between them — it is on no plane: half-way up
            // it is half-way across, while the sky has gone its own way.
            let half = SkyCamera.tonightHome(look: 0.5, world: world, anchorX: display.anchorX)
            XCTAssertEqual(half.x, (rest.x + up.x) / 2, accuracy: 1e-9)
            XCTAssertEqual(half.y, (rest.y + up.y) / 2, accuracy: 1e-9)
        }
        // On the Duo it crosses 76 pt of the display while the sky drops 312.
        let duo = SkyCamera.tonightHome(look: 1, world: .duo)
        XCTAssertEqual(duo.y - SkyWorld.duo.tonight.y, 76)
        // The spread's phone page is the cover's picture: the same place, 485 pt along.
        XCTAssertEqual(SkyCamera.tonightHome(look: 0.3, world: .duo, anchorX: 485).x,
                       SkyCamera.tonightHome(look: 0.3, world: .duo).x + 485, accuracy: 1e-9)
    }

    // MARK: What follows the look

    func testWhatFollowsTheLookIsTheLabs() {
        XCTAssertEqual(looks.rows.count, 101)   // every hundredth of the look
        for row in looks.rows {
            let look = looks.number(row, "look")
            let name = "look \(look)"
            XCTAssertEqual(SkyCamera.onTheWay(look), looks.number(row, "onTheWay"), accuracy: 1e-6, name)
            XCTAssertEqual(SkyCamera.cloudShown(.rest, look: look), looks.number(row, "cloudRest"), accuracy: 1e-6, name)
            XCTAssertEqual(SkyCamera.cloudShown(.up, look: look), looks.number(row, "cloudUp"), accuracy: 1e-6, name)
            XCTAssertEqual(SkyCamera.cloudShown(.always, look: look), looks.number(row, "cloudAlways"), accuracy: 1e-6, name)
            XCTAssertEqual(SkyCamera.treeShown(look: look, cards: 1), looks.number(row, "treeCardsOn"), accuracy: 1e-6, name)
            XCTAssertEqual(SkyCamera.treeShown(look: look, cards: 0.5), looks.number(row, "treeCardsHalf"), accuracy: 1e-6, name)
            XCTAssertEqual(SkyCamera.treeShown(look: look, cards: 0), looks.number(row, "treeCardsAway"), accuracy: 1e-6, name)
            // (an opacity past 1 or under 0 — a spring's overshoot — is held to its range, as the lab holds it)
            XCTAssertEqual(SkyCamera.treeShown(look: look, cards: 1.5), looks.number(row, "treeCardsOver"), accuracy: 1e-6, name)
            XCTAssertEqual(SkyCamera.treeShown(look: look, cards: -0.5), looks.number(row, "treeCardsUnder"), accuracy: 1e-6, name)
        }
    }

    func testTheTreeIsNotDrawnLookingUpWithTheCardsOn() {
        XCTAssertEqual(SkyCamera.treeShown(look: 0, cards: 1), 1, "all of it at rest")
        XCTAssertEqual(SkyCamera.treeShown(look: 1, cards: 1), 0, "none of it looking up with the cards on")
        XCTAssertEqual(SkyCamera.treeShown(look: 1, cards: 0), 1, "the bare poster of the bedtime moment")
        // It leaves early in a rise behind the cards: gone before the view is half-way up.
        XCTAssertEqual(SkyCamera.treeShown(look: 0.45, cards: 1), 0)
        XCTAssertEqual(SkyCamera.treeShown(look: 0.05, cards: 1), 1)
        // It goes with the cards' return, one for one.
        XCTAssertEqual(SkyCamera.treeShown(look: 1, cards: 0.3), 0.7, accuracy: 1e-12)
        // A card's opacity past its range is held to it: never less than no
        // tree, never more than the tree.
        XCTAssertEqual(SkyCamera.treeShown(look: 1, cards: 1.5), 0)
        XCTAssertEqual(SkyCamera.treeShown(look: 1, cards: -0.5), 1)
    }

    func testNothingStandsAmongHisStars() {
        // The everyday view's clouds have left before the looked-up view's
        // own is half there; at either pose each is wholly there or gone.
        XCTAssertEqual(SkyCamera.cloudShown(.rest, look: 0), 1)
        XCTAssertEqual(SkyCamera.cloudShown(.rest, look: 0.55), 0)
        XCTAssertEqual(SkyCamera.cloudShown(.rest, look: 1), 0)
        XCTAssertEqual(SkyCamera.cloudShown(.up, look: 0), 0)
        XCTAssertEqual(SkyCamera.cloudShown(.up, look: 0.35), 0)
        XCTAssertEqual(SkyCamera.cloudShown(.up, look: 1), 1)
        XCTAssertLessThan(SkyCamera.cloudShown(.up, look: 0.55), 0.5)
    }

    func testNothingIsOnTheWayAtAPose() {
        XCTAssertEqual(SkyCamera.onTheWay(0), 0)
        XCTAssertEqual(SkyCamera.onTheWay(1), 0)
        XCTAssertEqual(SkyCamera.onTheWay(0.5), 1)
        XCTAssertEqual(SkyCamera.onTheWay(0.08), 1)
        XCTAssertEqual(SkyCamera.onTheWay(0.92), 1)
    }
}
