import XCTest
import SwiftUI
@testable import TwoOfUs

/// Pure-geometry tests for the light (`CradleField.Plan`): where the two
/// pools and the hinge light land for each iPhone Duo pose. The field is laid
/// out in the tab's content area (the safe area) and paints the whole
/// display, so every case is a frame plus the safe area around it — plain
/// numbers, no display. Sizes are the device's: 951 × 669 inner display with
/// an 84 pt system strip and a 34 pt home-indicator inset; 466 × 678 outer.
/// (Main-actor, like the other suites that reach into a view's types.)
@MainActor
final class CradleFieldTests: XCTestCase {
    private func insets(top: CGFloat = 0, leading: CGFloat = 0,
                        bottom: CGFloat = 0, trailing: CGFloat = 0) -> EdgeInsets {
        EdgeInsets(top: top, leading: leading, bottom: bottom, trailing: trailing)
    }

    private func assertLight(_ light: CradleField.Light?,
                             center: CGPoint, reach: CGSize, strength: Double,
                             hasCore: Bool = false,
                             file: StaticString = #filePath, line: UInt = #line) {
        guard let light else {
            XCTFail("expected a light", file: file, line: line)
            return
        }
        XCTAssertEqual(light.center.x, center.x, accuracy: 0.01, "center x", file: file, line: line)
        XCTAssertEqual(light.center.y, center.y, accuracy: 0.01, "center y", file: file, line: line)
        XCTAssertEqual(light.reach.width, reach.width, accuracy: 0.01, "reach x", file: file, line: line)
        XCTAssertEqual(light.reach.height, reach.height, accuracy: 0.01, "reach y", file: file, line: line)
        XCTAssertEqual(light.strength, strength, accuracy: 0.0001, "strength", file: file, line: line)
        XCTAssertEqual(light.hasCore, hasCore, "core", file: file, line: line)
    }

    // MARK: Open in landscape (flat or book)

    func testVerticalCreasePaintsTheWholeDisplayFromTheReadersFrame() {
        // The reader is 867 × 635; the strip (84) is trailing, the home
        // indicator (34) below. The crease is at 475.5 in the reader.
        let plan = CradleField.Plan.resolve(hinge: .verticalCrease(x: 475.5),
                                    size: CGSize(width: 867, height: 635),
                                    insets: insets(bottom: 34, trailing: 84))

        XCTAssertEqual(plan.size.width, 951, accuracy: 0.01)
        XCTAssertEqual(plan.size.height, 669, accuracy: 0.01)
        XCTAssertEqual(plan.origin, .zero)
        XCTAssertTrue(plan.paintsRoom)

        // Pools from the top outer corner of each leaf: drawn 640 × 560,
        // clear at 72 %.
        assertLight(plan.leadingPool, center: .zero,
                    reach: CGSize(width: 460.8, height: 403.2), strength: 1)
        assertLight(plan.trailingPool, center: CGPoint(x: 951, y: 0),
                    reach: CGSize(width: 460.8, height: 403.2), strength: 1)

        // His light on the crease, 62 % of the way down: drawn 280 × 500,
        // clear at 70 %, with the small core.
        assertLight(plan.hingeLight, center: CGPoint(x: 475.5, y: 414.78),
                    reach: CGSize(width: 196, height: 350), strength: 1, hasCore: true)
    }

    func testVerticalCreaseStaysOnTheHingeWithTheStripLeading() {
        // The phone turned the other way up: the reader starts 84 pt into
        // the display, so its crease is at 391.5 — still the display's
        // midline once the field has painted back out to the display's edge.
        let plan = CradleField.Plan.resolve(hinge: .verticalCrease(x: 391.5),
                                    size: CGSize(width: 867, height: 635),
                                    insets: insets(leading: 84, bottom: 34))

        XCTAssertEqual(plan.size.width, 951, accuracy: 0.01)
        XCTAssertEqual(plan.origin.x, 84, accuracy: 0.01)
        XCTAssertEqual(plan.origin.y, 0, accuracy: 0.01)
        XCTAssertEqual(plan.hingeLight?.center.x ?? -1, 475.5, accuracy: 0.01)
        // The pools still start from the display's corners, not the reader's.
        XCTAssertEqual(plan.leadingPool?.center, .zero)
        XCTAssertEqual(plan.trailingPool?.center.x ?? -1, 951, accuracy: 0.01)
    }

    func testTheLightsScaleWithTheContainer() {
        // No safe area around it (a preview, a smaller window): the same
        // picture, in proportion.
        let plan = CradleField.Plan.resolve(hinge: .verticalCrease(x: 237.75),
                                    size: CGSize(width: 475.5, height: 334.5),
                                    insets: insets())
        XCTAssertEqual(plan.origin, .zero)
        assertLight(plan.leadingPool, center: .zero,
                    reach: CGSize(width: 230.4, height: 201.6), strength: 1)
        assertLight(plan.hingeLight, center: CGPoint(x: 237.75, y: 207.39),
                    reach: CGSize(width: 98, height: 175), strength: 1, hasCore: true)
    }

    func testNoHingeKeepsThePoolsAndLightsNothing() {
        let plan = CradleField.Plan.resolve(hinge: .none,
                                    size: CGSize(width: 867, height: 635),
                                    insets: insets(bottom: 34, trailing: 84))
        XCTAssertTrue(plan.paintsRoom)
        XCTAssertNotNil(plan.leadingPool)
        XCTAssertNotNil(plan.trailingPool)
        XCTAssertNil(plan.hingeLight)
    }

    // MARK: Under the demo-mode pill

    func testNothingAboveTheFieldLeavesItsTopEdgeAlone() {
        // Everyday use: the field paints to the display's top edge, so there
        // is nothing to soften.
        let plan = CradleField.Plan.resolve(hinge: .verticalCrease(x: 475.5),
                                    size: CGSize(width: 867, height: 635),
                                    insets: insets(bottom: 34, trailing: 84))
        XCTAssertEqual(plan.topShade, 0, accuracy: 0.001)

        // A reader that measures a hair off the top of its window is still
        // at the top of its window.
        let hair = CradleField.Plan.resolve(hinge: .verticalCrease(x: 475.5),
                                    size: CGSize(width: 867, height: 635),
                                    insets: insets(bottom: 34, trailing: 84),
                                    topOffset: 0.25)
        XCTAssertEqual(hair.topShade, 0, accuracy: 0.001)
    }

    func testARowAboveTheFieldShadesTheRoomsTopEdge() {
        // Demo mode: the pill's row (≈ 33 pt of plain background) sits above
        // the reader, which is that much shorter. The field cannot paint up
        // through the row, so the room fades in under it.
        let plan = CradleField.Plan.resolve(hinge: .verticalCrease(x: 475.5),
                                    size: CGSize(width: 867, height: 602),
                                    insets: insets(bottom: 34, trailing: 84),
                                    topOffset: 33)
        XCTAssertEqual(plan.topShade, 96, accuracy: 0.001)

        // Everything else is the picture it would be in a display that
        // tall: the pools at the painted area's top corners, the hinge light
        // 62 % of the way down it.
        XCTAssertEqual(plan.size.height, 636, accuracy: 0.01)
        XCTAssertEqual(plan.origin, .zero)
        XCTAssertEqual(plan.leadingPool?.center, .zero)
        XCTAssertEqual(plan.trailingPool?.center.x ?? -1, 951, accuracy: 0.01)
        XCTAssertEqual(plan.hingeLight?.center.y ?? -1, 394.32, accuracy: 0.01)
    }

    func testTheShadeNeverOutgrowsTheFieldAndTheCoverHasNone() {
        // A field shorter than the shade is shaded for its whole height, no
        // further.
        let sliver = CradleField.Plan.resolve(hinge: .none,
                                      size: CGSize(width: 300, height: 40),
                                      insets: insets(), topOffset: 33)
        XCTAssertEqual(sliver.topShade, 40, accuracy: 0.001)

        // The closed cover paints no room — no pools, no night ground — so
        // there is no edge to soften, pill or no pill.
        let cover = CradleField.Plan.resolve(hinge: .spine(.oppositeSystemStrip),
                                     size: CGSize(width: 382, height: 611),
                                     insets: insets(bottom: 34, trailing: 84),
                                     topOffset: 33)
        XCTAssertFalse(cover.paintsRoom)
        XCTAssertEqual(cover.topShade, 0, accuracy: 0.001)
    }

    // MARK: Open in portrait (flat or tabletop)

    func testHorizontalCreaseLightsTheBandAcrossTheDisplay() {
        // 669 × 951 with an 82 pt status bar above the reader and 106 pt
        // below it; the crease (475.5 on the display) is at 393.5 in the
        // reader.
        let plan = CradleField.Plan.resolve(hinge: .horizontalCrease(y: 393.5),
                                    size: CGSize(width: 669, height: 763),
                                    insets: insets(top: 82, bottom: 106))

        XCTAssertEqual(plan.size.width, 669, accuracy: 0.01)
        XCTAssertEqual(plan.size.height, 951, accuracy: 0.01)
        XCTAssertEqual(plan.origin.y, 82, accuracy: 0.01)

        // The pools take the two far corners of the two leaves.
        assertLight(plan.leadingPool, center: .zero,
                    reach: CGSize(width: 446.4, height: 403.2), strength: 1)
        assertLight(plan.trailingPool, center: CGPoint(x: 669, y: 951),
                    reach: CGSize(width: 446.4, height: 403.2), strength: 1)
        assertLight(plan.hingeLight, center: CGPoint(x: 334.5, y: 475.5),
                    reach: CGSize(width: 392, height: 154), strength: 1, hasCore: true)
    }

    // MARK: The outer display

    func testRidgeLightsTheTopEdgeOverTheContent() {
        // Tent: 678 × 466, the strip trailing. The ridge is the top edge;
        // the light is centred over the content (297), not the display (339).
        let plan = CradleField.Plan.resolve(hinge: .ridge,
                                    size: CGSize(width: 594, height: 432),
                                    insets: insets(bottom: 34, trailing: 84))

        XCTAssertEqual(plan.size.width, 678, accuracy: 0.01)
        XCTAssertEqual(plan.size.height, 466, accuracy: 0.01)
        XCTAssertTrue(plan.paintsRoom)
        assertLight(plan.hingeLight, center: CGPoint(x: 297, y: 0),
                    reach: CGSize(width: 392, height: 196), strength: 0.8)
        // The pools rise from the bottom corners, the trailing one fainter.
        assertLight(plan.leadingPool, center: CGPoint(x: 0, y: 466),
                    reach: CGSize(width: 403.2, height: 331.2), strength: 1)
        assertLight(plan.trailingPool, center: CGPoint(x: 678, y: 466),
                    reach: CGSize(width: 374.4, height: 302.4), strength: 0.8)
    }

    func testTheClosedCoverStaysBlackWithOnlyABloomOnTheSpine() {
        // Closed and upright: 466 × 678, the strip trailing — so the spine
        // is the leading edge.
        let size = CGSize(width: 382, height: 644)
        let plan = CradleField.Plan.resolve(hinge: .spine(.oppositeSystemStrip), size: size,
                                    insets: insets(bottom: 34, trailing: 84))

        XCTAssertFalse(plan.paintsRoom, "no pools and no night ground on the cover")
        XCTAssertNil(plan.leadingPool)
        XCTAssertNil(plan.trailingPool)
        assertLight(plan.hingeLight, center: CGPoint(x: 0, y: 420.36),
                    reach: CGSize(width: 154, height: 294), strength: 0.55)
    }

    func testTheSpineIsTheEdgeAwayFromTheSystemStrip() {
        let size = CGSize(width: 382, height: 644)

        // Strip leading → spine trailing, at the display's far edge.
        let flipped = CradleField.Plan.resolve(hinge: .spine(.oppositeSystemStrip), size: size,
                                       insets: insets(leading: 84, bottom: 34))
        XCTAssertEqual(flipped.hingeLight?.center.x ?? -1, 466, accuracy: 0.01)

        // No safe area to go on: the leading edge.
        let bare = CradleField.Plan.resolve(hinge: .spine(.oppositeSystemStrip), size: size,
                                    insets: insets())
        XCTAssertEqual(bare.hingeLight?.center.x ?? -1, 0, accuracy: 0.01)

        // A named edge is taken at its word, whatever the insets say.
        let leading = CradleField.Plan.resolve(hinge: .spine(.leading), size: size,
                                       insets: insets(leading: 84, bottom: 34))
        XCTAssertEqual(leading.hingeLight?.center.x ?? -1, 0, accuracy: 0.01)
        let trailing = CradleField.Plan.resolve(hinge: .spine(.trailing), size: size,
                                        insets: insets(bottom: 34, trailing: 84))
        XCTAssertEqual(trailing.hingeLight?.center.x ?? -1, 466, accuracy: 0.01)
    }
}
