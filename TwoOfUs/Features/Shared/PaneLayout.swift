import SwiftUI

// MARK: - Screen shape

/// The shape a roomy screen takes, decided from size classes first and the
/// container's own size second — never from the device, its orientation or
/// `UIScreen` (Apple's iPhone Duo rule: "A compact width layout for the outer
/// display and a regular width layout for the inner display give you the
/// fundamentals for every pose").
///
/// | Shape | Where it happens |
/// |---|---|
/// | `.compact` | iPhone Duo closed and upright; a Split View half; every slab iPhone. The app's single column, unchanged. |
/// | `.wide` | iPhone Duo open in landscape — flat, or folded like a book; iPad. Panes side by side. |
/// | `.tall` | iPhone Duo open in portrait — flat, or folded like a laptop ("tabletop"). Panes stacked. |
/// | `.short` | iPhone Duo closed and turned on its side — stood on a nightstand like a tent. |
enum ScreenShape: Equatable {
    case compact, wide, tall, short

    /// True when the size classes alone say "single column" — callers render
    /// their existing compact layout without ever measuring anything.
    static func isCompact(horizontal: UserInterfaceSizeClass?,
                          vertical: UserInterfaceSizeClass?) -> Bool {
        horizontal != .regular && vertical != .compact
    }
}

// MARK: - Pane geometry

/// Where a non-compact screen splits into two panes, in the coordinate space
/// of the `GeometryReader` that resolved it (a reader that fills the screen's
/// content area, inside the safe area).
///
/// On iPhone Duo's inner display the split IS the fold. The fold runs down the
/// middle of the *display* — not of the safe area, which the trailing vertical
/// bar makes lopsided (455.5 pt of content before the fold, 371.5 pt after, in
/// landscape) — so the band is centred on the display's midline, worked out
/// from the reader's position in the window, its size and its trailing /
/// bottom safe-area insets. It is the same band
/// whether the phone lies flat or is partly folded, so folding never moves a
/// single view, and in book or tabletop pose the crease always lands in the
/// gap between panes — never on a control or a line of text. The band's 40 pt
/// matches the fold's reserved frame with its margins (measured on the iPhone
/// Duo simulator: a 40 pt frame centred on the midline).
///
/// No iOS 27.1 API is needed for that: the midline is where the hinge is. (A
/// later build can swap in `GeometryProxy.reservedRegions(kind: .division,
/// options: .includeInactive)` behind `#available(iOS 27.1, *)` once the
/// Xcode Cloud SDK is confirmed — see docs/IPHONE_DUO.md.)
struct PaneLayout: Equatable {
    let shape: ScreenShape
    /// The reader's size (the safe area of the screen's content).
    let size: CGSize
    /// The gap between the panes in the reader's coordinates: a vertical band
    /// for `.wide` / `.short`, a horizontal band for `.tall`.
    let band: CGRect
    /// The display's height (the window's: the reader's top in the window
    /// plus its height and bottom safe-area inset). What "is there room for
    /// the roomy version of a card" questions should ask.
    let fullHeight: CGFloat
    /// The reader's top safe-area inset. Zero on iPhone Duo's outer display and
    /// its inner display in landscape, where the status bar lives in the side
    /// strip instead of across the top.
    let topInset: CGFloat
    /// How far below the top of its window the reader starts, beyond that
    /// inset. Zero unless something sits above the reader — the demo-mode
    /// pill's row, under which the inset itself reads zero, so this is then
    /// everything above the reader: the row and, where there is one, the
    /// status bar over it. Only iPhone Duo's spread reads it (`SpreadGrid`
    /// counts it toward the air above the titles, `CradleField` softens its
    /// top edge under it); every other layout is as it was.
    var topOffset: CGFloat = 0

    /// Width of the fold band (the fold's reserved frame, margins included).
    static let foldBand: CGFloat = 40
    /// Gutter between side-by-side panes on a display with no fold (the
    /// outer display in landscape).
    static let gutter: CGFloat = 16
    /// A regular-width container narrower than this, on a display taller than
    /// wide, stacks its panes; wider ones (iPad portrait) sit side by side.
    static let sideBySideMinWidth: CGFloat = 700
    /// No pane is ever made narrower (or shorter) than this; a container too
    /// small for two such panes splits evenly instead.
    static let minPane: CGFloat = 240
    /// Padding a pane keeps on its fold-facing edge, on top of the band.
    static let foldSideInset: CGFloat = 4
    /// Below this full height (≈ the display's), cards with a roomy and a
    /// compact layout use the compact one. iPhone Duo's outer display is
    /// 678 pt tall and its inner display 669 pt in landscape; slab iPhones
    /// other than the SE are 812 pt and up.
    static let roomyHeight: CGFloat = 700

    var leadingWidth: CGFloat { max(band.minX, 0) }
    var trailingWidth: CGFloat { max(size.width - band.maxX, 0) }
    var topHeight: CGFloat { max(band.minY, 0) }
    var bottomHeight: CGFloat { max(size.height - band.maxY, 0) }

    /// Extra top padding a pane adds when the status bar isn't across the top,
    /// so its first line doesn't sit flush against the display's edge.
    var topBreathingRoom: CGFloat { max(0, 12 - topInset) }

    /// Two scrolling columns that move together (History, Stats): the side-by-
    /// side split for `.wide` / `.short`, an even split with a gutter for
    /// `.tall` (whose fold runs across the columns, which scrolling content
    /// may cross).
    var columns: (leading: CGFloat, gap: CGFloat, trailing: CGFloat) {
        switch shape {
        case .tall:
            let each = max((size.width - Self.gutter) / 2, 0)
            return (each, Self.gutter, each)
        default:
            return (leadingWidth, band.width, trailingWidth)
        }
    }

    /// Resolves the split for a non-compact screen. `horizontal` is the
    /// screen's horizontal size class: regular means the inner display (or an
    /// iPad), anything else means the outer display on its side.
    static func resolve(in proxy: GeometryProxy,
                        horizontal: UserInterfaceSizeClass?) -> PaneLayout {
        let size = proxy.size
        let insets = proxy.safeAreaInsets
        // Where the reader starts in the window. Usually that's just its
        // leading / top safe-area inset, but not when something sits above it
        // (the demo-mode pill row), so the display's edges are measured from
        // the window, not assumed from the insets. (Its trailing and bottom
        // edges do reach the window's safe area: a tab's content fills it.)
        let origin = proxy.frame(in: .global).origin
        // The whole display (the window — the display itself whenever this
        // runs on iPhone Duo, since a Split View half is compact width).
        // Shape and midlines come from it, never from the reader's own size,
        // which changes with the bars: a large title collapsing on scroll,
        // the demo pill or a big text size must not flip portrait to "wide".
        let displayWidth = origin.x + size.width + insets.trailing
        let displayHeight = origin.y + size.height + insets.bottom
        // What sits above the reader beyond its own top inset: nothing, or
        // the demo-mode pill's row. (Nothing is exactly zero: a hair of
        // measuring noise must not make two equal layouts differ.)
        let above = origin.y - insets.top
        let topOffset: CGFloat = above > 0.5 ? above : 0

        guard horizontal == .regular else {
            // The outer display has no fold: a quiet gutter down the middle
            // of the safe area, so both panes get the same width whichever
            // edge the vertical bar is on.
            let band = CGRect(x: (size.width - gutter) / 2, y: 0,
                              width: gutter, height: size.height)
            return PaneLayout(shape: .short, size: size, band: band,
                              fullHeight: displayHeight, topInset: insets.top,
                              topOffset: topOffset)
        }

        if displayWidth >= displayHeight || size.width >= sideBySideMinWidth {
            // The display's vertical midline, in the reader's coordinates.
            let mid = clamped(displayWidth / 2 - origin.x, length: size.width, band: foldBand)
            let band = CGRect(x: mid - foldBand / 2, y: 0,
                              width: foldBand, height: size.height)
            return PaneLayout(shape: .wide, size: size, band: band,
                              fullHeight: displayHeight, topInset: insets.top,
                              topOffset: topOffset)
        }

        // The display's horizontal midline, in the reader's coordinates.
        let mid = clamped(displayHeight / 2 - origin.y, length: size.height, band: foldBand)
        let band = CGRect(x: 0, y: mid - foldBand / 2,
                          width: size.width, height: foldBand)
        return PaneLayout(shape: .tall, size: size, band: band,
                          fullHeight: displayHeight, topInset: insets.top,
                          topOffset: topOffset)
    }

    /// Keeps both panes at least `minPane` long; a container too small for
    /// that splits down its own middle.
    private static func clamped(_ mid: CGFloat, length: CGFloat, band: CGFloat) -> CGFloat {
        let lower = minPane + band / 2
        let upper = length - minPane - band / 2
        guard lower <= upper else { return length / 2 }
        return min(max(mid, lower), upper)
    }
}

// MARK: - Two-pane container

/// Lays two panes out along a `PaneLayout`: side by side for `.wide` /
/// `.short`, stacked for `.tall`, with the band between them left empty (the
/// screen's own background shows through — on iPhone Duo, that's the fold).
struct DividedPanes<First: View, Second: View>: View {
    let layout: PaneLayout
    @ViewBuilder var first: () -> First
    @ViewBuilder var second: () -> Second

    var body: some View {
        switch layout.shape {
        case .tall:
            VStack(spacing: 0) {
                first()
                    .frame(maxWidth: .infinity)
                    .frame(height: layout.topHeight)
                Color.clear
                    .frame(height: layout.band.height)
                    .accessibilityHidden(true)
                second()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        default:
            HStack(spacing: 0) {
                first()
                    .frame(maxHeight: .infinity)
                    .frame(width: layout.leadingWidth)
                Color.clear
                    .frame(width: layout.band.width)
                    .accessibilityHidden(true)
                second()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - The page before the fold

private struct LeadingPageWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    /// Set by `RootView` while the screen resolves to `.wide` (iPhone Duo open
    /// in landscape, flat or folded like a book; iPad): the width, from the
    /// screen's leading edge, that centred one-column content can use and
    /// still finish well before the fold. Nil everywhere else — every slab
    /// iPhone, Split View, and the Duo's portrait and tent poses — so readers
    /// fall back to exactly what they did before.
    var leadingPageWidth: CGFloat? {
        get { self[LeadingPageWidthKey.self] }
        set { self[LeadingPageWidthKey.self] = newValue }
    }
}

extension PaneLayout {
    /// The `leadingPageWidth` for a resolved layout: the page before the fold,
    /// less the band's width again as slack, so a host's own outer padding
    /// (up to ~40 pt) can never push the content onto the crease. Nil unless
    /// `.wide`.
    var leadingPage: CGFloat? {
        shape == .wide ? max(leadingWidth - Self.foldBand, 0) : nil
    }
}

/// Puts one-column content (a setup step, a bottom button, a banner) on the
/// page before the fold: at most `maxWidth` wide, centred within `page`, which
/// starts at the leading edge. With no page (nil) it is centred in the full
/// width, capped at `maxWidth` — the behaviour everywhere but `.wide`.
struct LeadingPageColumn: ViewModifier {
    let maxWidth: CGFloat
    let page: CGFloat?

    func body(content: Content) -> some View {
        // One structure for every pose — a nil page is layout-neutral — so
        // rotating or opening/closing iPhone Duo never rebuilds the content
        // (a focused field, an open picker or a running task survives).
        content
            .frame(maxWidth: min(maxWidth, page ?? CGFloat.infinity))
            .frame(width: page)   // nil: sizes to the child, a no-op
            .frame(maxWidth: .infinity, alignment: page == nil ? Alignment.center : .leading)
    }
}
