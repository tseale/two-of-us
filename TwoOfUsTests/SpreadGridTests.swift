import XCTest
@testable import TwoOfUs

/// Pure-geometry tests for the spread — iPhone Duo's inner display open in
/// landscape, laid out as two mirrored phone-width pages. Plain sizes and
/// bands in, frames out: no display, no `GeometryProxy`. The numbers are the
/// approved design's (docs/IPHONE_DUO.md, "The spread"): a 951 × 669 display
/// whose reader — the safe area — is 867 × 635, with the 40 pt fold band on
/// the display's midline.
final class SpreadGridTests: XCTestCase {
    /// The reader on the inner display in landscape.
    private let reader = CGSize(width: 867, height: 635)

    /// A full-height fold band in the reader's coordinates.
    private func band(minX: CGFloat, width: CGFloat = 40, height: CGFloat = 635) -> CGRect {
        CGRect(x: minX, y: 0, width: width, height: height)
    }

    private func layout(_ shape: ScreenShape, size: CGSize, band: CGRect,
                        topInset: CGFloat = 0, topOffset: CGFloat = 0) -> PaneLayout {
        PaneLayout(shape: shape, size: size, band: band, fullHeight: 669, topInset: topInset,
                   topOffset: topOffset)
    }

    private func assertFrame(_ rect: CGRect?, x: CGFloat, y: CGFloat,
                             width: CGFloat, height: CGFloat,
                             file: StaticString = #filePath, line: UInt = #line) {
        guard let rect else {
            XCTFail("expected a frame", file: file, line: line)
            return
        }
        XCTAssertEqual(rect.minX, x, accuracy: 0.001, "x", file: file, line: line)
        XCTAssertEqual(rect.minY, y, accuracy: 0.001, "y", file: file, line: line)
        XCTAssertEqual(rect.width, width, accuracy: 0.001, "width", file: file, line: line)
        XCTAssertEqual(rect.height, height, accuracy: 0.001, "height", file: file, line: line)
    }

    // MARK: The approved spread

    func testInnerLandscapeMatchesTheApprovedSpread() throws {
        // System strip trailing: the reader starts at the display's leading
        // edge, so the crease (475.5 on the display) is 475.5 here too.
        let grid = try XCTUnwrap(SpreadGrid.resolve(size: reader, band: band(minX: 455.5)))

        XCTAssertEqual(grid.pageWidth, 350, accuracy: 0.001)
        assertFrame(grid.leadingPage, x: 97.5, y: 103, width: 350, height: 532)
        assertFrame(grid.trailingPage, x: 503.5, y: 103, width: 350, height: 532)
        XCTAssertEqual(grid.leadingPage.maxX, 447.5, accuracy: 0.001)
        XCTAssertEqual(grid.trailingPage.maxX, 853.5, accuracy: 0.001)

        XCTAssertEqual(grid.headY, 22, accuracy: 0.001)
        XCTAssertEqual(grid.top, 103, accuracy: 0.001)
        XCTAssertEqual(grid.foot, 635, accuracy: 0.001, "the foot line is the reader's bottom edge")
        XCTAssertEqual(grid.pageHeight, 532, accuracy: 0.001)
        XCTAssertEqual(grid.titleHeight, 81, accuracy: 0.001)

        // 97.5 pt of margin away from the strip, 13.5 pt beside it.
        XCTAssertEqual(grid.leadingMargin, 97.5, accuracy: 0.001)
        XCTAssertEqual(grid.trailingMargin, 13.5, accuracy: 0.001)
        XCTAssertEqual(grid.gutter, 56, accuracy: 0.001)
        XCTAssertEqual(grid.marginSide, .leading)
        assertFrame(grid.avatarFrame, x: 22, y: 26, width: 52, height: 52)

        XCTAssertEqual(grid.page(.leading), grid.leadingPage)
        XCTAssertEqual(grid.page(.trailing), grid.trailingPage)
    }

    func testPagesMirrorAboutTheCreaseAndClearTheBand() throws {
        let fold = band(minX: 455.5)
        let grid = try XCTUnwrap(SpreadGrid.resolve(size: reader, band: fold))
        // 28 pt each side of the crease = 8 pt clear of the 40 pt band.
        XCTAssertEqual(fold.midX - grid.leadingPage.maxX, 28, accuracy: 0.001)
        XCTAssertEqual(grid.trailingPage.minX - fold.midX, 28, accuracy: 0.001)
        XCTAssertEqual(fold.minX - grid.leadingPage.maxX, 8, accuracy: 0.001)
        XCTAssertEqual(grid.trailingPage.minX - fold.maxX, 8, accuracy: 0.001)
    }

    // MARK: The phone turned the other way up

    func testStripOnTheLeadingSidePutsTheMarginOnTheTrailingSide() throws {
        // System strip leading: the reader starts 84 pt into the display, so
        // the crease is at 475.5 − 84 = 391.5 in its coordinates.
        let fold = band(minX: 371.5)
        XCTAssertEqual(fold.midX, 391.5, accuracy: 0.001)
        let grid = try XCTUnwrap(SpreadGrid.resolve(size: reader, band: fold))

        XCTAssertEqual(grid.pageWidth, 350, accuracy: 0.001)
        assertFrame(grid.leadingPage, x: 13.5, y: 103, width: 350, height: 532)
        assertFrame(grid.trailingPage, x: 419.5, y: 103, width: 350, height: 532)
        XCTAssertEqual(grid.leadingMargin, 13.5, accuracy: 0.001)
        XCTAssertEqual(grid.trailingMargin, 97.5, accuracy: 0.001)

        // The avatar follows the wide margin: 22 pt in from the trailing edge.
        XCTAssertEqual(grid.marginSide, .trailing)
        assertFrame(grid.avatarFrame, x: 867 - 22 - 52, y: 26, width: 52, height: 52)
    }

    // MARK: Narrower readers

    func testNarrowerReaderShrinksBothPagesAndNeverCrossesTheBand() throws {
        // 760 pt across, fold in its middle: 340 pt is all either side allows.
        let fold = band(minX: 360)
        let grid = try XCTUnwrap(SpreadGrid.resolve(size: CGSize(width: 760, height: 635),
                                                    band: fold))
        XCTAssertEqual(grid.pageWidth, 340, accuracy: 0.001)
        XCTAssertEqual(grid.leadingPage.width, grid.trailingPage.width, accuracy: 0.001)
        assertFrame(grid.leadingPage, x: 12, y: 103, width: 340, height: 532)
        assertFrame(grid.trailingPage, x: 408, y: 103, width: 340, height: 532)

        XCTAssertLessThanOrEqual(grid.leadingPage.maxX, fold.minX - 8 + 0.001)
        XCTAssertGreaterThanOrEqual(grid.trailingPage.minX, fold.maxX + 8 - 0.001)
        XCTAssertGreaterThanOrEqual(grid.leadingMargin, SpreadGrid.minOuterMargin - 0.001)
        XCTAssertGreaterThanOrEqual(grid.trailingMargin, SpreadGrid.minOuterMargin - 0.001)

        // Neither margin can hold the avatar clear of its page.
        XCTAssertNil(grid.avatarFrame)
        XCTAssertEqual(grid.marginSide, .leading, "a tie keeps the leading side")
    }

    func testTheTighterSideSetsTheWidthOfBothPages() throws {
        // The fold where it is on the display, but only 800 pt of reader: the
        // trailing side has 284.5 pt to give, so both pages take 284.5 and
        // stay against the fold.
        let fold = band(minX: 455.5)
        let grid = try XCTUnwrap(SpreadGrid.resolve(size: CGSize(width: 800, height: 635),
                                                    band: fold))
        XCTAssertEqual(grid.pageWidth, 284.5, accuracy: 0.001)
        XCTAssertEqual(grid.leadingPage.maxX, 447.5, accuracy: 0.001)
        XCTAssertEqual(grid.trailingPage.minX, 503.5, accuracy: 0.001)
        XCTAssertEqual(grid.trailingMargin, 12, accuracy: 0.001)
        XCTAssertEqual(grid.marginSide, .leading)
        XCTAssertNotNil(grid.avatarFrame, "163 pt of leading margin holds the avatar")
    }

    func testAWiderBandPushesThePagesApart() throws {
        // A 60 pt band on the same crease: the pages keep 8 pt off the band
        // rather than 28 pt off the crease.
        let fold = band(minX: 445.5, width: 60)
        let grid = try XCTUnwrap(SpreadGrid.resolve(size: reader, band: fold))
        XCTAssertEqual(grid.leadingPage.maxX, 437.5, accuracy: 0.001)
        XCTAssertEqual(grid.trailingPage.minX, 513.5, accuracy: 0.001)
        XCTAssertEqual(grid.pageWidth, 341.5, accuracy: 0.001)
        XCTAssertLessThanOrEqual(grid.trailingPage.maxX, reader.width)
    }

    func testAReaderTooNarrowForTwoPagesHasNoGrid() {
        // 252 pt before the band's clearance leaves exactly the 240 pt floor…
        XCTAssertNotNil(SpreadGrid.resolve(size: CGSize(width: 560, height: 635),
                                           band: band(minX: 260)))
        // …and anything less is not a page.
        XCTAssertNil(SpreadGrid.resolve(size: CGSize(width: 540, height: 635),
                                        band: band(minX: 250)))
        XCTAssertNil(SpreadGrid.resolve(size: CGSize(width: 320, height: 635),
                                        band: band(minX: 140)))
    }

    // MARK: Vertical lines

    func testTheFootLineFollowsTheReadersHeight() throws {
        let grid = try XCTUnwrap(SpreadGrid.resolve(size: CGSize(width: 867, height: 500),
                                                    band: band(minX: 455.5, height: 500)))
        XCTAssertEqual(grid.foot, 500, accuracy: 0.001)
        XCTAssertEqual(grid.pageHeight, 397, accuracy: 0.001)
        XCTAssertEqual(grid.leadingPage.maxY, 500, accuracy: 0.001)
        XCTAssertEqual(grid.trailingPage.maxY, 500, accuracy: 0.001)
    }

    func testAReaderShorterThanTheHeadHasEmptyPagesNotNegativeOnes() throws {
        let grid = try XCTUnwrap(SpreadGrid.resolve(size: CGSize(width: 867, height: 60),
                                                    band: band(minX: 455.5, height: 60)))
        XCTAssertEqual(grid.pageHeight, 0, accuracy: 0.001)
        XCTAssertEqual(grid.leadingPage.height, 0, accuracy: 0.001)
    }

    func testATopInsetStartsTheTitlesAtThePanesBreathingRoom() throws {
        // Not the Duo's landscape case (its top inset is 0): a status bar
        // across the top already supplies the air above the titles.
        let wide = layout(.wide, size: reader, band: band(minX: 455.5), topInset: 24)
        let grid = try XCTUnwrap(SpreadGrid.resolve(size: reader, band: band(minX: 455.5),
                                                    topInset: 24))
        XCTAssertEqual(grid.headY, wide.topBreathingRoom, accuracy: 0.001)
        XCTAssertEqual(grid.headY, 0, accuracy: 0.001)
        XCTAssertEqual(grid.top, 81, accuracy: 0.001)

        let slight = try XCTUnwrap(SpreadGrid.resolve(size: reader, band: band(minX: 455.5),
                                                      topInset: 5))
        XCTAssertEqual(slight.headY, 7, accuracy: 0.001)
        XCTAssertEqual(slight.top, 88, accuracy: 0.001)
        assertFrame(slight.avatarFrame, x: 22, y: 11, width: 52, height: 52)
    }

    func testARowAboveTheReaderCountsTowardTheHeadLine() throws {
        // Demo mode: the pill's row (≈ 33 pt) sits above the reader, whose
        // top inset is still 0 and which is that much shorter. The row has
        // already kept the titles off the display's edge, so they start at
        // the reader's top and the pages get the head line's 22 pt back.
        let short = CGSize(width: 867, height: 602)
        let fold = band(minX: 455.5, height: 602)
        let grid = try XCTUnwrap(SpreadGrid.resolve(size: short, band: fold, topOffset: 33))
        XCTAssertEqual(grid.headY, 0, accuracy: 0.001)
        XCTAssertEqual(grid.top, 81, accuracy: 0.001)
        XCTAssertEqual(grid.foot, 602, accuracy: 0.001)
        // 521 pt: the leading page's column (≈ 514 pt at the default text
        // size) still fits. Starting at the head line it would have 499.
        XCTAssertEqual(grid.pageHeight, 521, accuracy: 0.001)
        XCTAssertEqual(grid.titleHeight, 81, accuracy: 0.001)
        assertFrame(grid.leadingPage, x: 97.5, y: 81, width: 350, height: 521)
        assertFrame(grid.avatarFrame, x: 22, y: 4, width: 52, height: 52)

        // The same grid comes through the layout the reader resolved.
        let wide = layout(.wide, size: short, band: fold, topOffset: 33)
        XCTAssertEqual(SpreadGrid(layout: wide, isPhone: true), grid)

        // A row shorter than the head line takes only its own height off it.
        let slight = try XCTUnwrap(SpreadGrid.resolve(size: reader, band: band(minX: 455.5),
                                                      topOffset: 10))
        XCTAssertEqual(slight.headY, 12, accuracy: 0.001)
        XCTAssertEqual(slight.top, 93, accuracy: 0.001)

        // Nothing above the reader (and a stray negative): the head line.
        let none = try XCTUnwrap(SpreadGrid.resolve(size: reader, band: band(minX: 455.5),
                                                    topOffset: -3))
        XCTAssertEqual(none.headY, 22, accuracy: 0.001)

        // A status bar across the top keeps its own rule, whatever else is
        // above the reader.
        let barred = try XCTUnwrap(SpreadGrid.resolve(size: reader, band: band(minX: 455.5),
                                                      topInset: 5, topOffset: 33))
        XCTAssertEqual(barred.headY, 7, accuracy: 0.001)
    }

    func testTheTitlesOwnAirFitsInsideItsSlotAtTheDefaultTextSize() {
        // The title block is ≈ 61 pt at the default text size (a 41 pt title
        // line, 2 pt, a 20 pt subtitle line — allow a few points for the
        // rounded face). With its air under it, it must still fit the slot,
        // or the first surface would leave the top line (y 103).
        let titleBlock: CGFloat = 64
        XCTAssertLessThanOrEqual(titleBlock + SpreadGrid.titleAir, SpreadGrid.titleSlot)
        // And the air is real: a title that has outgrown the slot still
        // keeps a surface gap's worth above the first surface.
        XCTAssertGreaterThanOrEqual(SpreadGrid.titleAir, SpreadGrid.surfaceGap)
    }

    // MARK: A page that ends in the journal

    func testTheJournalFillsThePageUnderShortLeadItems() {
        // No lead items: the journal is the whole page, from the top line.
        XCTAssertEqual(SpreadGrid.leadGap(leadHeight: 0), 0, accuracy: 0.001)
        XCTAssertTrue(SpreadGrid.journalFills(pageHeight: 532, leadHeight: 0))

        // The approved night spread: the Tonight card (230 pt) and one
        // surface gap leave the journal 290 pt of the 532 pt page.
        XCTAssertEqual(SpreadGrid.leadGap(leadHeight: 230), SpreadGrid.surfaceGap, accuracy: 0.001)
        XCTAssertTrue(SpreadGrid.journalFills(pageHeight: 532, leadHeight: 230))

        // The evening of a daycare day — the fullest everyday page: the
        // day's daycare recap (56 pt) over the Tonight card, a surface gap
        // between them. The journal keeps 222 pt and still ends on the foot
        // line.
        XCTAssertTrue(SpreadGrid.journalFills(pageHeight: 532, leadHeight: 56 + 12 + 230))

        // Exactly the floor still fills: 532 − 320 − 12 = 200.
        XCTAssertTrue(SpreadGrid.journalFills(pageHeight: 532, leadHeight: 320))
    }

    func testThePageScrollsWhenLeadItemsLeaveTheJournalTooLittle() {
        // One point past the floor, and well past it.
        XCTAssertFalse(SpreadGrid.journalFills(pageHeight: 532, leadHeight: 321))
        XCTAssertFalse(SpreadGrid.journalFills(pageHeight: 532, leadHeight: 600))
        // A page pushed down by a large title has less to give.
        XCTAssertFalse(SpreadGrid.journalFills(pageHeight: 440, leadHeight: 230))
        XCTAssertFalse(SpreadGrid.journalFills(pageHeight: 0, leadHeight: 0))
        // Scrolling, the journal is taller than the least it accepts in place.
        XCTAssertGreaterThan(SpreadGrid.journalScrollingHeight, SpreadGrid.journalMinHeight)
    }

    func testAMeasurementThatRoundsToNothingIsNoLeadItems() {
        // Sub-point noise from measuring an empty stack must not open a gap.
        XCTAssertEqual(SpreadGrid.leadGap(leadHeight: 0.25), 0, accuracy: 0.001)
        XCTAssertEqual(SpreadGrid.leadGap(leadHeight: 1), SpreadGrid.surfaceGap, accuracy: 0.001)
    }

    // MARK: Which layouts get a grid

    func testOnlyAWideLayoutOnAPhoneGetsAGrid() throws {
        let fold = band(minX: 455.5)
        let wide = layout(.wide, size: reader, band: fold)

        // iPhone Duo open in landscape: the same grid the plain numbers give.
        let grid = try XCTUnwrap(SpreadGrid(layout: wide, isPhone: true))
        XCTAssertEqual(grid, SpreadGrid.resolve(size: reader, band: fold))

        // iPad resolves `.wide` too and keeps its own panes.
        XCTAssertNil(SpreadGrid(layout: wide, isPhone: false))
    }

    func testTallShortAndCompactLayoutsGetNoGrid() {
        // Open in portrait / tabletop: the band runs across the display.
        let portrait = CGSize(width: 669, height: 763)
        let tall = layout(.tall, size: portrait,
                          band: CGRect(x: 0, y: 373.5, width: 669, height: 40),
                          topInset: 82)
        XCTAssertNil(SpreadGrid(layout: tall, isPhone: true))

        // The outer display on its side (tent): a 16 pt gutter, no fold.
        let tent = CGSize(width: 594, height: 432)
        let short = layout(.short, size: tent,
                           band: CGRect(x: 289, y: 0, width: 16, height: 432))
        XCTAssertNil(SpreadGrid(layout: short, isPhone: true))

        // Never produced by `PaneLayout.resolve`, but no grid either way.
        let compact = layout(.compact, size: reader, band: band(minX: 455.5))
        XCTAssertNil(SpreadGrid(layout: compact, isPhone: true))
    }
}
