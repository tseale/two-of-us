import XCTest
@testable import TwoOfUs

/// Where the launch curtain and the restore screen stand the mark: on the
/// spine of iPhone Duo open in landscape, and nowhere else.
final class SpreadSpineTests: XCTestCase {
    /// The inner display in landscape with the system strip trailing: the
    /// safe area is 867 × 635, the fold band x 455.5–495.5.
    private func layout(bandMinX: CGFloat = 455.5, shape: ScreenShape = .wide) -> PaneLayout {
        PaneLayout(shape: shape, size: CGSize(width: 867, height: 635),
                   band: CGRect(x: bandMinX, y: 0, width: 40, height: 635),
                   fullHeight: 669, topInset: 0)
    }

    func testTheSpineIsOnTheCreaseWithAPageEitherSide() throws {
        let spine = try XCTUnwrap(SpreadSpine(layout: layout(), isPhone: true))
        XCTAssertEqual(spine.crease, 475.5, accuracy: 0.001)
        XCTAssertEqual(spine.leadingEdge, 447.5, accuracy: 0.001)
        XCTAssertEqual(spine.trailingEdge, 503.5, accuracy: 0.001)
        XCTAssertEqual(spine.pageWidth, 350, accuracy: 0.001)
        XCTAssertEqual(spine.gutter, 56, accuracy: 0.001)
        XCTAssertEqual(spine.leadingPageMinX, 97.5, accuracy: 0.001)
        // Centred in the safe area, the mark would be 42 pt short of the crease.
        XCTAssertEqual(spine.centreOffset, 42, accuracy: 0.001)
    }

    func testTurnedRoundTheOffsetPointsTheOtherWay() throws {
        // Strip leading: the safe area starts 84 pt in, the crease is at 391.5.
        let spine = try XCTUnwrap(SpreadSpine(layout: layout(bandMinX: 371.5), isPhone: true))
        XCTAssertEqual(spine.centreOffset, -42, accuracy: 0.001)
    }

    func testNoSpineOffThePhoneOrOffTheSpread() {
        XCTAssertNil(SpreadSpine(layout: layout(), isPhone: false))
        XCTAssertNil(SpreadSpine(layout: layout(shape: .tall), isPhone: true))
        XCTAssertNil(SpreadSpine(layout: layout(shape: .short), isPhone: true))
    }

    func testVerticalPlacementIsMeasuredOnTheDisplay() throws {
        let spine = try XCTUnwrap(SpreadSpine(layout: layout(), isPhone: true))
        // A 210 pt mark centred 40 % down the 669 pt display.
        XCTAssertEqual(spine.top(ofHeight: 210, centredAt: 0.4), 669 * 0.4 - 105, accuracy: 0.001)
        // Never above the display's top.
        XCTAssertEqual(spine.top(ofHeight: 2000, centredAt: 0.4), 0, accuracy: 0.001)
    }
}
