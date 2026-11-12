import SwiftUI

/// The spine, for a screen that fills the display rather than sitting in a
/// tab — the launch curtain, the restore screen. On iPhone Duo open in
/// landscape (flat, or folded like a book) the safe area is off-centre: the
/// system strip takes 84 pt from one side, so the middle of what a view is
/// given sits 42 pt to one side of the crease. The app is called Two of Us
/// and the display has two leaves, so its mark belongs on the spine — one
/// parent's circle on each page, the baby's light on the fold. The mark is
/// the one thing allowed to cross the fold (it is light, not a word or a
/// control); everything else a screen says keeps to a page, and this is
/// where the pages' fold-side edges come from.
///
/// A spine exists exactly where the spread does (`SpreadGrid`): the phone
/// idiom and a `.wide` layout, which together are only ever iPhone Duo open
/// in landscape. Everywhere else — every slab iPhone, iPad, the Duo closed,
/// open in portrait or stood like a tent — there is none, and a screen that
/// asks stays exactly what it was.
///
/// `RootView` measures it once, beside `leadingPageWidth`, and hands it down
/// (`EnvironmentValues.spreadSpine`). Every x is in that reader's
/// coordinates: the safe area's, from its leading edge — the space a
/// full-screen view that keeps to the safe area is laid out in. A pure value
/// type, so the numbers are unit-tested without a display:
/// `SpreadSpineTests`.
struct SpreadSpine: Equatable {
    /// The width the spine was measured across: the safe area's.
    let width: CGFloat
    /// The crease.
    let crease: CGFloat
    /// The leading page's fold-side edge: where a line on that page ends.
    let leadingEdge: CGFloat
    /// The trailing page's fold-side edge: where a line on that page starts.
    let trailingEdge: CGFloat
    /// The width of a page: the most a line on either one may run.
    let pageWidth: CGFloat
    /// The display's height — taller than the safe area by the home
    /// indicator's inset. "So far down the display" is asked of this, so a
    /// composition sits where it looks centred on the glass, not in the
    /// safe area.
    let displayHeight: CGFloat

    /// The spine of a resolved layout, or nil when it is not the spread's:
    /// off the phone idiom (iPad resolves `.wide` too), in any other shape,
    /// or in a reader too narrow for two pages. The same test the tabs make
    /// before they draw a spread, so a screen is on the spine exactly when
    /// they are.
    init?(layout: PaneLayout, isPhone: Bool) {
        guard let grid = SpreadGrid(layout: layout, isPhone: isPhone) else { return nil }
        width = layout.size.width
        crease = layout.band.midX
        leadingEdge = grid.leadingPage.maxX
        trailingEdge = grid.trailingPage.minX
        pageWidth = grid.pageWidth
        displayHeight = layout.fullHeight
    }

    /// How far something centred in the safe area has to move sideways to
    /// stand on the crease: 42 pt toward the system strip on the inner
    /// display, whichever side the strip is on.
    var centreOffset: CGFloat { crease - width / 2 }
    /// The space between the pages, the fold in its middle. Nothing but the
    /// mark goes here.
    var gutter: CGFloat { max(trailingEdge - leadingEdge, 0) }
    /// Where the leading page starts: a line that ends on `leadingEdge` can
    /// begin no earlier.
    var leadingPageMinX: CGFloat { leadingEdge - pageWidth }

    /// The top of something `height` tall whose centre sits `fraction` of
    /// the way down the display — never above the display's own top. (On
    /// the inner display in landscape nothing runs across the top, so the
    /// safe area starts where the display does and the two share a y.)
    func top(ofHeight height: CGFloat, centredAt fraction: CGFloat) -> CGFloat {
        max(displayHeight * fraction - height / 2, 0)
    }
}

private struct SpreadSpineKey: EnvironmentKey {
    static let defaultValue: SpreadSpine? = nil
}

extension EnvironmentValues {
    /// Set by `RootView` while the screen is iPhone Duo open in landscape:
    /// where the spine is, for the full-screen views that put the mark on
    /// it. Nil everywhere else — every slab iPhone, iPad, and the Duo's
    /// other poses — so readers fall back to exactly what they did before.
    var spreadSpine: SpreadSpine? {
        get { self[SpreadSpineKey.self] }
        set { self[SpreadSpineKey.self] = newValue }
    }
}
