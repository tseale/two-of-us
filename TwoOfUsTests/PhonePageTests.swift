import XCTest
@testable import TwoOfUs

/// The phone page's frame: untouched on every iPhone, and on iPhone Duo's
/// open display exactly the closed phone's width, clear of the fold.
final class PhonePageTests: XCTestCase {
    /// iPhone Duo's inner display in landscape, the system strip trailing:
    /// an 867 × 635 reader, the fold band at x 455.5–495.5.
    private let stripTrailing = PaneLayout(shape: .wide, size: CGSize(width: 867, height: 635),
                                           band: CGRect(x: 455.5, y: 0, width: 40, height: 635),
                                           fullHeight: 669, topInset: 0)
    /// The phone turned round: the strip leading, so the band sits further
    /// left in the reader (x 371.5–411.5).
    private let stripLeading = PaneLayout(shape: .wide, size: CGSize(width: 867, height: 635),
                                          band: CGRect(x: 371.5, y: 0, width: 40, height: 635),
                                          fullHeight: 669, topInset: 0)

    func testEveryIPhoneGetsTheWholeReaderUnchanged() {
        // No spread: slab iPhones (17, 17 Pro Max, SE…), the Duo closed, a
        // Split View half. The page is the reader, origin and size.
        for size in [CGSize(width: 402, height: 778), CGSize(width: 440, height: 870),
                     CGSize(width: 375, height: 647), CGSize(width: 382, height: 678)] {
            XCTAssertEqual(PhonePage.frame(spread: nil, in: size), CGRect(origin: .zero, size: size))
        }
    }

    func testOpenTheTrailingPageIsTheClosedPhonesWidthHuggingTheStrip() {
        let frame = PhonePage.frame(spread: stripTrailing, in: stripTrailing.size)
        XCTAssertEqual(frame, CGRect(x: 485, y: 0, width: 382, height: 635))
        // With the 84 pt strip, page + strip = the cover's 466 pt.
        XCTAssertEqual(frame.width + 84, 466)
    }

    func testRowsStayClearOfTheFold() {
        for layout in [stripTrailing, stripLeading] {
            let frame = PhonePage.frame(spread: layout, in: layout.size)
            XCTAssertGreaterThanOrEqual(frame.minX + PhonePage.margin,
                                        layout.band.maxX + SpreadGrid.bandClearance)
            // The ground's feather stays within the margin, under no row.
            XCTAssertLessThanOrEqual(PhonePage.featherWidth, PhonePage.margin)
        }
    }

    func testTurnedRoundItStillHugsTheTrailingEdgeAtFullWidth() {
        let frame = PhonePage.frame(spread: stripLeading, in: stripLeading.size)
        XCTAssertEqual(frame.maxX, 867)
        XCTAssertEqual(frame.width, PhonePage.closedContentWidth)
    }

    func testANarrowReaderShrinksThePageRatherThanCrossTheFold() {
        let narrow = PaneLayout(shape: .wide, size: CGSize(width: 800, height: 600),
                                band: CGRect(x: 430, y: 0, width: 40, height: 600),
                                fullHeight: 640, topInset: 0)
        let frame = PhonePage.frame(spread: narrow, in: narrow.size)
        XCTAssertEqual(frame.minX, 458)          // 470 + 8 − 20
        XCTAssertEqual(frame.maxX, 800)
    }
}
