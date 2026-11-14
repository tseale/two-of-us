import CoreGraphics

/// Where Home's phone page goes — the single column every iPhone shows, and
/// on iPhone Duo both the closed phone's screen and the open spread's
/// trailing page (the same view, moved: see `HomeView.body`). Pure geometry
/// (`PhonePageTests`).
///
/// Without a spread — every slab iPhone, iPhone Duo closed, a Split View
/// half — the page is exactly the reader, as it always was.
///
/// On the spread it is the closed phone's screen again, so opening the phone
/// moves nothing on it: exactly the closed phone's content width, hugging
/// the display's trailing edge the way it does on the cover. With the
/// system strip on the trailing side that is x 485–867 on the 867 pt
/// reader — the page plus the strip is 466 pt, the cover's own width, so
/// the page's ground (its own sky) is the cover's sky. Its leading edge
/// reaches back over the fold band, but its rows start `margin` in, which
/// keeps them `SpreadGrid.bandClearance` clear of the band; the ground
/// feathers out across that margin (`featherWidth`) into the leading page's.
enum PhonePage {
    /// The closed phone's content width: the outer display (466 pt) beside
    /// its 84 pt system strip.
    static let closedContentWidth: CGFloat = 382

    /// The page's side margin on the cover and the spread (Home's `duoOuter`).
    static let margin: CGFloat = 20

    /// How far the page's ground fades in from its leading edge on the
    /// spread — across the fold band, never under a row.
    static let featherWidth: CGFloat = 18

    /// The page's frame in the reader's coordinates. `spread` is the open
    /// display's layout, nil everywhere else.
    static func frame(spread layout: PaneLayout?, in size: CGSize) -> CGRect {
        guard let layout else { return CGRect(origin: .zero, size: size) }
        // The rows (at `margin`) must start `bandClearance` past the band.
        let earliest = layout.band.maxX + SpreadGrid.bandClearance - margin
        let x = max(size.width - closedContentWidth, earliest)
        let width = max(min(closedContentWidth, size.width - x), 0)
        return CGRect(x: x, y: 0, width: width, height: layout.size.height)
    }
}
