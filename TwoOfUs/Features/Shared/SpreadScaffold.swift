import SwiftUI
import SwiftData

// MARK: - A page

/// One page of the spread, described rather than drawn: the words of its
/// title block — exactly `PageTitle`'s parameters — and the content that
/// goes under it. `SpreadScaffold` does the drawing, so a tab never frames,
/// pads or measures a page itself, and the tabs' pages cannot drift apart.
///
/// The content closure is handed the height left under the title, measured:
/// the page's own height (`SpreadGrid.pageHeight`, 532 pt on the inner
/// display) at the default text size, and less at a text size where the
/// title has outgrown its slot — so a larger title pushes the content down
/// instead of overlapping it. Whatever the closure returns is laid out in
/// exactly that box — the page's width, that height, from the top:
/// - a surface that should end on the foot line takes
///   `.frame(maxHeight: .infinity)` inside its own background (a
///   `JournalCard` already does);
/// - a page with more than one screen is a `SpreadPageScroll`, whose
///   `SpreadFirstScreen` is given the height;
/// - anything that depends on what there is to show is an `if` inside the
///   closure, never around the scaffold, so the pages — and the light behind
///   them — keep their identity when the data changes.
struct SpreadPage<Accessory: View, Content: View> {
    fileprivate let title: String
    fileprivate let subtitle: String?
    fileprivate let trailingAlignment: PageTitleTrailingAlignment
    fileprivate let accessory: Accessory
    fileprivate let content: (CGFloat) -> Content

    /// A page whose title has one control beside it: level with the title
    /// (`.title` — a round button) or on the subtitle's baseline
    /// (`.subtitle` — a quiet text action).
    init(_ title: String, subtitle: String? = nil,
         trailingAlignment: PageTitleTrailingAlignment = .title,
         @ViewBuilder trailing: () -> Accessory,
         @ViewBuilder content: @escaping (CGFloat) -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.trailingAlignment = trailingAlignment
        self.accessory = trailing()
        self.content = content
    }
}

extension SpreadPage where Accessory == EmptyView {
    /// A page with nothing beside its title.
    init(_ title: String, subtitle: String? = nil,
         @ViewBuilder content: @escaping (CGFloat) -> Content) {
        self.init(title, subtitle: subtitle, trailing: { EmptyView() }, content: content)
    }
}

// MARK: - The scaffold

/// The spread, drawn once for every tab: iPhone Duo's inner display open in
/// landscape — flat, or folded like a book — as two mirrored phone-width
/// pages either side of the fold. The scaffold draws what the tabs' spreads
/// have in common and nothing else: the light behind everything, the baby's
/// avatar in the wider outer margin, and the two pages — each a `PageTitle`
/// on the head line with its content under it, down to the foot line. Every
/// frame is read from `SpreadGrid`, so Nighttime, History and Stats open on
/// the same lines Home does, and nothing textual or tappable ever sits
/// between the pages.
///
/// **Where it may be built.** Only where `SpreadGrid(layout:isPhone:)`
/// resolves: the phone idiom and a `.wide` layout, which together are only
/// ever iPhone Duo open in landscape. iPad resolves `.wide` too and gets no
/// grid, so it never reaches this view; nor does any slab iPhone.
///
/// **No navigation bar.** On a spread the page titles are the titles, so the
/// scaffold hides the bar itself — from in here, the spread's own branch,
/// rather than on the tab's container. The container keeps its
/// `.navigationTitle`, its toolbar, sheets and tasks exactly where they
/// were, and has its bar back the moment the layout is anything else.
/// Whatever lived in that toolbar has to be reachable on a page instead (a
/// title's trailing control).
///
/// **The toast.** An undo toast floats at the foot of the trailing page,
/// inside its width — never over the leading page's controls, never across
/// the fold — as Home's does.
///
/// VoiceOver reads the leading page to its end, then the trailing page. The
/// avatar is decoration here; the light is hidden and takes no touches.
///
/// Home draws this same frame by hand (`HomeView.spread`): its light also
/// follows a nap at daycare, which only Home's own queries can tell (see
/// `SpreadLight`), and its trailing title re-stacks at large text sizes. A
/// change to the frames here belongs there too.
struct SpreadScaffold<LeadingAccessory: View, LeadingContent: View,
                      TrailingAccessory: View, TrailingContent: View>: View {
    private let layout: PaneLayout
    private let grid: SpreadGrid
    private let baby: Baby?
    private let toast: Binding<ToastData?>
    private let leading: SpreadPage<LeadingAccessory, LeadingContent>
    private let trailing: SpreadPage<TrailingAccessory, TrailingContent>

    /// - Parameters:
    ///   - layout: The layout the tab's reader resolved — the one `grid`
    ///     came from. The spread takes its size, and the light its crease.
    ///   - grid: `SpreadGrid(layout:isPhone:)`, unwrapped by the caller:
    ///     having one is what says this is the spread.
    ///   - baby: Whose avatar hangs in the margin.
    ///   - toast: The tab's undo toast, if it has one.
    ///   - leading: The page before the fold.
    ///   - trailing: The page after it.
    init(layout: PaneLayout, grid: SpreadGrid, baby: Baby?,
         toast: Binding<ToastData?> = .constant(nil),
         leading: SpreadPage<LeadingAccessory, LeadingContent>,
         trailing: SpreadPage<TrailingAccessory, TrailingContent>) {
        self.layout = layout
        self.grid = grid
        self.baby = baby
        self.toast = toast
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The light, behind everything. It is given this reader's frame
            // and paints out through the safe area by itself.
            SpreadLight(layout: layout)
            // The baby's avatar hangs in the wider outer margin (the side
            // away from the system strip), beside the first title. It is
            // decoration here: the tabs' titles name the screen, and Home's
            // reads his name.
            if let avatar = grid.avatarFrame {
                Avatar(photoData: baby?.photoData, name: baby?.name ?? "Baby",
                       colorHex: ParticipantColors.babyHex, size: avatar.width)
                    .accessibilityHidden(true)
                    .padding(.leading, avatar.minX)
                    .padding(.top, avatar.minY)
            }
            // Leading page, then trailing page: the order VoiceOver reads.
            SpreadPageColumn(page: leading, titleHeight: grid.titleHeight,
                             size: grid.titledPage(.leading).size)
                // One page is read to its end before the other begins.
                .accessibilityElement(children: .contain)
                .padding(.leading, grid.titledPage(.leading).minX)
                .padding(.top, grid.titledPage(.leading).minY)
            SpreadPageColumn(page: trailing, titleHeight: grid.titleHeight,
                             size: grid.titledPage(.trailing).size)
                // On the page's own frame, so the toast keeps to its width
                // and sits just above the foot line.
                .loggedToast(toast, sideInset: SpreadGrid.toastSideInset,
                             bottomInset: SpreadGrid.toastLift)
                .accessibilityElement(children: .contain)
                .padding(.leading, grid.titledPage(.trailing).minX)
                .padding(.top, grid.titledPage(.trailing).minY)
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
        // The page titles are the titles. Hidden from inside the spread, so
        // every other layout of the tab keeps its bar.
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// One page, drawn: the title block, then the content in what is left of
/// the page under it.
private struct SpreadPageColumn<Accessory: View, Content: View>: View {
    let page: SpreadPage<Accessory, Content>
    /// The room the title has before the first surface
    /// (`SpreadGrid.titleHeight`).
    let titleHeight: CGFloat
    /// The whole page, title included: head line to foot line.
    let size: CGSize

    var body: some View {
        VStack(spacing: 0) {
            PageTitle(page.title, subtitle: page.subtitle,
                      trailingAlignment: page.trailingAlignment) {
                page.accessory
            }
            // Air the title keeps under it at any text size…
            .padding(.bottom, SpreadGrid.titleAir)
            // …inside a minimum, never a fixed height: at the default text
            // size the first surface lands on the grid's top line, and a
            // larger size pushes it down instead of overlapping it.
            .frame(minHeight: titleHeight, alignment: .top)
            // What is left of the page, measured, so the content can fill it
            // exactly whatever the title took.
            GeometryReader { proxy in
                page.content(proxy.size.height)
                    // Exactly the box that is left, from the top: content
                    // that is shorter starts on the top line, and content
                    // that fills ends on the foot line.
                    .frame(width: proxy.size.width, height: proxy.size.height,
                           alignment: .top)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
    }
}

// MARK: - The light

/// The light behind a spread: `CradleField` with its hinge on the crease —
/// a pool of each parent's colour behind each leaf and, while he sleeps, his
/// light in the fold between them. It owns the one thing the field needs to
/// be told, whether he is asleep and since when, so no tab works that out
/// for itself.
///
/// Asleep, here, is a sleep in progress that a parent started or SNOO
/// reported: the newest sleep with no end, the same one Home's sleep card is
/// showing. It is asked again once a minute, as Home's light is — a nap
/// becomes a night's sleep on the clock alone.
///
/// It does not follow a nap at daycare. Home's light also comes on for a nap
/// Brightwheel has started and not yet ended while he is attending, and
/// "attending" is Home's to say: the day's check markers, the first thing
/// daycare logged today of any of twelve kinds, the closing time and whether
/// this phone stands inside the daycare's fence — a dozen of Home's own
/// queries. Deriving that again here would be a second copy of Home's
/// daycare logic inside a background, free to drift from the first. So
/// during a daycare nap Home's hinge is lit and these tabs' rooms stay as
/// they are awake; every sleep that shows on Home's sleep card lights all
/// four tabs the same.
struct SpreadLight: View {
    private let layout: PaneLayout

    /// Sleeps still running, newest first — the rows Home's `activeSleep`
    /// chooses from, so the two lights follow the same sleep. A daycare nap
    /// is never one of them: it is stored only once staff log the wake.
    @Query(filter: #Predicate<SleepEvent> { $0.deletedAt == nil && $0.endedAt == nil },
           sort: \SleepEvent.startedAt, order: .reverse)
    private var runningSleeps: [SleepEvent]

    /// - Parameter layout: The layout the tab's reader resolved. The field
    ///   takes that reader's frame, so the crease is `band.midX` whichever
    ///   side the system strip is on.
    init(layout: PaneLayout) {
        self.layout = layout
    }

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            // ctx.date is the minute's start, and stays there when a @Query
            // change re-runs this closure — up to 59 s stale.
            let now = max(ctx.date, .now)
            // (`topOffset`: under the demo-mode pill's row the field cannot
            // reach the display's top edge, and softens its own.)
            CradleField(hinge: .verticalCrease(x: layout.band.midX),
                        sleepingSince: runningSleeps.first?.startedAt, now: now,
                        topOffset: layout.topOffset)
        }
    }
}

// MARK: - Pages that scroll

/// A page's content when it has more than one screen: one column of
/// surfaces, a surface gap apart, scrolling on its own under the page's
/// fixed title. It only bounces when there is something to scroll to, so a
/// page that fits stays the fixed composition it looks like.
///
/// Put a `SpreadFirstScreen` first and the page opens ending exactly on the
/// foot line, with the rest a scroll away.
struct SpreadPageScroll<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: SpreadGrid.surfaceGap) {
                content
            }
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        // The page ends on the foot line, which is also the safe area's
        // bottom edge — and a scroll view that touches that edge shows its
        // content on through it, to the display's own. Left alone, the top
        // of the next surface would show under the foot line of a first
        // screen that is meant to end there.
        .clipped()
    }
}

/// The first screen of a page that scrolls: a column of surfaces, a surface
/// gap apart, that is at least the page tall — so at the default text size
/// its last surface ends on the foot line, and at a size where the surfaces
/// need more than the page it simply grows and the page scrolls.
///
/// The column has `height` to share out, so each surface in it has to say
/// which kind it is. One that keeps its natural height takes
/// `.fixedSize(horizontal: false, vertical: true)` — without it a stack
/// sharing out a fixed height can hand a card less than its text needs. One
/// that takes up the slack is flexible inside its own background — a chart
/// with `maxHeight: .infinity`, a `Spacer` under its last line — so the
/// surface grows with it; two of those share the slack evenly.
struct SpreadFirstScreen<Content: View>: View {
    private let height: CGFloat
    private let content: Content

    /// - Parameter height: The height left under the page's title — what
    ///   `SpreadPage`'s content closure is handed.
    init(height: CGFloat, @ViewBuilder content: () -> Content) {
        self.height = height
        self.content = content()
    }

    var body: some View {
        VStack(spacing: SpreadGrid.surfaceGap) {
            content
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: height, alignment: .top)
    }
}

/// The inner display's reader, for the preview: a page that scrolls beside a
/// page that is one card.
private struct SpreadScaffoldPreview: View {
    private let layout = PaneLayout(shape: .wide, size: CGSize(width: 867, height: 635),
                                    band: CGRect(x: 455.5, y: 0, width: 40, height: 635),
                                    fullHeight: 669, topInset: 0)

    var body: some View {
        if let grid = SpreadGrid(layout: layout, isPhone: true) {
            SpreadScaffold(
                layout: layout, grid: grid, baby: nil,
                leading: SpreadPage("History", subtitle: "Last 7 days") { height in
                    SpreadPageScroll {
                        SpreadFirstScreen(height: height) {
                            Text("Day in the life")
                                .frame(maxWidth: .infinity, minHeight: 220)
                                .surfaceCard()
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Longest sleep stretch")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .surfaceCard()
                        }
                        Text("Feed times")
                            .frame(maxWidth: .infinity, minHeight: 240)
                            .surfaceCard()
                    }
                },
                trailing: SpreadPage("Daily totals", subtitle: "This week") { _ in
                    Text("Total sleep per day")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .surfaceCard()
                })
        }
    }
}

#Preview("Two pages") {
    SpreadScaffoldPreview()
        .frame(width: 867, height: 635)
        .background(AppColor.bg)
        .modelContainer(AppModelContainer.preview)
        .preferredColorScheme(.dark)
}
