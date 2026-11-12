import CoreGraphics

/// The spread: iPhone Duo's inner display open in landscape — flat, or folded
/// like a book — laid out as two mirrored pages, each exactly a phone-width
/// page, on either side of the fold. The page that was under your thumb while
/// the phone was closed stays there when it opens, and the day opens beside
/// it.
///
/// Every frame on the spread is read from here, so the two pages can never
/// drift apart: their titles start on one head line, their first surfaces on
/// one top line, and their last surfaces end on one foot line — the reader's
/// bottom edge, the same line as the bottom of the system's tab capsule.
/// Nothing textual or tappable ever sits between the pages; only the light
/// (`CradleField`) crosses the fold.
///
/// All values are in the coordinate space of the `GeometryReader` that
/// `PaneLayout.resolve(in:horizontal:)` measured (the tab's content area,
/// inside the safe area). On the 951 × 669 display that reader is 867 × 635
/// and the fold band is x 455.5–495.5, which gives:
///
/// | | |
/// |---|---|
/// | Leading page | x 97.5–447.5 |
/// | Trailing page | x 503.5–853.5 |
/// | Head line (titles) | y 22 |
/// | First surface | y 103 |
/// | Foot line | y 635 |
/// | Avatar (52 pt) | x 22, y 26 — in the wider outer margin |
///
/// A pure value type (CoreGraphics and the `PaneLayout` it is derived from),
/// so the numbers are unit-tested without a display: `SpreadGridTests`.
struct SpreadGrid: Equatable {
    /// One of the spread's two outer margins.
    enum Side: Equatable {
        case leading, trailing
    }

    // MARK: The grid's rules

    /// A page is a phone-width page, and no wider.
    static let idealPageWidth: CGFloat = 350
    /// Narrower than this isn't a page any more: no grid is resolved, and the
    /// caller keeps the panes it had.
    static let minPageWidth: CGFloat = 240
    /// Each page stops this far short of the crease…
    static let innerMargin: CGFloat = 28
    /// …and never comes closer than this to the fold band itself.
    static let bandClearance: CGFloat = 8
    /// The least a page keeps from the reader's outer edges before it gives
    /// up width instead. (On the strip side the reader's edge is already the
    /// safe area's: 13.5 pt of margin there, with the system strip beyond.)
    static let minOuterMargin: CGFloat = 12
    /// Where the page titles start when nothing sits across the top of the
    /// display (the status bar is in the side strip).
    static let headLine: CGFloat = 22
    /// Head line to first surface: the title block (≈ 61 pt at the default
    /// text size) and the air under it.
    static let titleSlot: CGFloat = 81
    /// The least air a title keeps between itself and the first surface.
    /// At the default text size the slot already leaves more (≈ 20 pt), so
    /// this changes nothing there; at the largest sizes, where the title
    /// block alone outgrows the slot, it is what stops the first surface
    /// sitting flush against the subtitle.
    static let titleAir: CGFloat = 12
    /// The gap between two surfaces stacked on a page.
    static let surfaceGap: CGFloat = 12
    /// The baby's avatar, hung in the wider outer margin…
    static let avatarSize: CGFloat = 52
    /// …this far in from the display's edge…
    static let avatarEdgeInset: CGFloat = 22
    /// …with its top this far under the head line, beside the title…
    static let avatarDrop: CGFloat = 4
    /// …and only when the margin holds it with this much to spare before the
    /// page.
    static let avatarClearance: CGFloat = 8
    /// The undo toast floats this far above the foot line, inside its page…
    static let toastLift: CGFloat = 12
    /// …and this far in from the page's sides.
    static let toastSideInset: CGFloat = 16
    /// The journal (the timeline's page surface) needs at least this much of
    /// its page; with less left under the lead items, the page scrolls as a
    /// whole and the journal takes `journalScrollingHeight`.
    ///
    /// The floor is set by the fullest everyday page: the evening of a
    /// daycare day, when the day's daycare recap (≈ 56 pt) leads the page
    /// over the Tonight card (≈ 230 pt). That leaves the journal ≈ 222 pt —
    /// the NOW cap and four rows — and it should still end on the foot line
    /// there, not tip the page into scrolling for the sake of 8 pt.
    static let journalMinHeight: CGFloat = 200
    static let journalScrollingHeight: CGFloat = 320

    // MARK: A page that ends in the journal

    /// The space between a page's lead items — `leadHeight` of them, as
    /// measured — and the journal under them: one surface gap, or nothing
    /// when there are no lead items and the journal starts on the top line
    /// itself.
    static func leadGap(leadHeight: CGFloat) -> CGFloat {
        leadHeight > 0.5 ? surfaceGap : 0
    }

    /// Whether the journal can simply fill what is left of a page
    /// `pageHeight` tall under `leadHeight` of lead items: it can while that
    /// leaves it `journalMinHeight`. With less, the page scrolls as a whole
    /// and the journal takes `journalScrollingHeight`.
    static func journalFills(pageHeight: CGFloat, leadHeight: CGFloat) -> Bool {
        pageHeight - leadHeight - leadGap(leadHeight: leadHeight) >= journalMinHeight
    }

    // MARK: The resolved frames

    /// The reader's size the grid was resolved for.
    let size: CGSize
    /// The width of each page: `idealPageWidth`, or less in a reader too
    /// narrow for two of them.
    let pageWidth: CGFloat
    /// The page before the fold, from `top` to `foot`.
    let leadingPage: CGRect
    /// The page after the fold, from `top` to `foot`.
    let trailingPage: CGRect
    /// Where both page titles start.
    let headY: CGFloat
    /// Where the first surface of each page starts.
    let top: CGFloat
    /// The foot line: where the last surface of each page ends.
    let foot: CGFloat
    /// The wider of the two outer margins — the side away from the system
    /// strip, whichever way up the phone is held.
    let marginSide: Side
    /// Where the avatar hangs in that margin. Nil when no margin is wide
    /// enough to hold it clear of the page.
    let avatarFrame: CGRect?

    /// The height every page has to fill, top line to foot line.
    var pageHeight: CGFloat { max(foot - top, 0) }
    /// The room a title block has before the first surface. Give the title
    /// (padded underneath by `titleAir`) this as a *minimum* height,
    /// top-aligned: at the default text size the first surface then lands
    /// exactly on `top`, and a larger text size pushes it down instead of
    /// overlapping it.
    var titleHeight: CGFloat { max(top - headY, 0) }
    /// Empty space before the leading page.
    var leadingMargin: CGFloat { leadingPage.minX }
    /// Empty space after the trailing page.
    var trailingMargin: CGFloat { max(size.width - trailingPage.maxX, 0) }
    /// The space between the pages, the fold band in its middle.
    var gutter: CGFloat { max(trailingPage.minX - leadingPage.maxX, 0) }

    /// The page on one side of the fold.
    func page(_ side: Side) -> CGRect {
        side == .leading ? leadingPage : trailingPage
    }

    /// The page on one side of the fold with its title: from the head line
    /// to the foot line, at the page's own x and width. A page's views — the
    /// title block, then everything from `top` down — are framed to this
    /// size and placed at this origin as one column, so the title can push
    /// its page's surfaces down (a larger text size) without ever moving the
    /// foot line.
    func titledPage(_ side: Side) -> CGRect {
        let page = self.page(side)
        return CGRect(x: page.minX, y: headY, width: page.width, height: max(foot - headY, 0))
    }

    // MARK: Resolving

    /// The grid for a reader of `size` whose fold band is `band`, or nil when
    /// the reader is too narrow for two pages. `topInset` is the reader's top
    /// safe-area inset: zero on iPhone Duo in landscape, the only place the
    /// spread is used — anything else starts the titles at the pane's usual
    /// breathing room instead of the head line. `topOffset` is the height of
    /// anything that sits above the reader all the same
    /// (`PaneLayout.topOffset`: the demo-mode pill's row), which counts
    /// toward the head line.
    ///
    /// Plain numbers in, plain numbers out — no `GeometryProxy` — so every
    /// case is unit-tested.
    static func resolve(size: CGSize, band: CGRect, topInset: CGFloat = 0,
                        topOffset: CGFloat = 0) -> SpreadGrid? {
        let crease = band.midX
        // The pages' fold-side edges mirror each other about the crease, and
        // stay clear of the band however wide it is.
        let leadingEdge = min(crease - innerMargin, band.minX - bandClearance)
        let trailingEdge = max(crease + innerMargin, band.maxX + bandClearance)
        // Both pages are one width: what the tighter side allows, at most a
        // phone's.
        let width = min(idealPageWidth,
                        leadingEdge - minOuterMargin,
                        size.width - trailingEdge - minOuterMargin)
        guard width >= minPageWidth else { return nil }

        // Same rule as `PaneLayout.topBreathingRoom` where a status bar does
        // run across the top. Where none does, the head line is there to
        // keep the titles off the display's edge — and a row that already
        // sits above the reader (the demo-mode pill's) has kept them off it
        // by its own height. Counting that row gives the pages back the
        // height it took: without it the leading page's column, which has
        // only a few points to spare, would no longer fit and would scroll.
        let headY = topInset > 0
            ? max(0, 12 - topInset)
            : max(headLine - max(topOffset, 0), 0)
        let top = headY + titleSlot
        let foot = size.height
        let height = max(foot - top, 0)
        let leadingPage = CGRect(x: leadingEdge - width, y: top, width: width, height: height)
        let trailingPage = CGRect(x: trailingEdge, y: top, width: width, height: height)

        // The system strip takes its 84 pt from one side of the display, so
        // one outer margin is wide and the other a sliver. Which one depends
        // on which way up the phone is — measured, never assumed.
        let leadingMargin = leadingPage.minX
        let trailingMargin = size.width - trailingPage.maxX
        let side: Side = trailingMargin > leadingMargin ? .trailing : .leading
        let margin = max(leadingMargin, trailingMargin)
        var avatarFrame: CGRect? = nil
        if margin >= avatarEdgeInset + avatarSize + avatarClearance {
            let x = side == .leading
                ? avatarEdgeInset
                : size.width - avatarEdgeInset - avatarSize
            avatarFrame = CGRect(x: x, y: headY + avatarDrop,
                                 width: avatarSize, height: avatarSize)
        }

        return SpreadGrid(size: size, pageWidth: width,
                          leadingPage: leadingPage, trailingPage: trailingPage,
                          headY: headY, top: top, foot: foot,
                          marginSide: side, avatarFrame: avatarFrame)
    }
}

extension SpreadGrid {
    /// The spread for a resolved layout — only ever iPhone Duo open in
    /// landscape. Nil for every other shape (`.tall`, `.short`, `.compact`),
    /// and nil off the phone idiom: iPad resolves `.wide` too and keeps its
    /// own panes exactly, so the caller has to say which it is
    /// (`UIDevice.current.userInterfaceIdiom == .phone`) before it can get a
    /// grid at all.
    init?(layout: PaneLayout, isPhone: Bool) {
        guard isPhone, layout.shape == .wide,
              let grid = SpreadGrid.resolve(size: layout.size, band: layout.band,
                                            topInset: layout.topInset,
                                            topOffset: layout.topOffset)
        else { return nil }
        self = grid
    }
}
