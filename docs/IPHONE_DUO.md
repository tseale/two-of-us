# iPhone Duo

How Two of Us lays out on iPhone Duo — Apple's passport-style foldable (iOS
27.1, shipped 2026-10-23) — and why. Written 2026-11-10 from Apple's
"Designing for iPhone Duo" HIG, the six iPhone Duo Tech Talks (111461–111466),
"Preparing your app for iPhone Duo", and a survey of the third-party apps
reviewers singled out (timespent, Flighty, Things, Fantastical, Netflix, Halide).

Home's two everyday poses — open like a book, and closed — were redrawn
2026-11-12 as **the spread**, **the cover** and **the light** (all under
"Home" below). The other screens and poses follow: see "Still to come".

## The device, in the numbers that matter

| | Outer display (closed) | Inner display (open) |
|---|---|---|
| Points | 466 × 678 portrait, 678 × 466 landscape | 951 × 669 landscape (its native way up), 669 × 951 portrait |
| Size classes | compact width / regular height upright; compact / compact on its side | regular / regular in every pose |
| Bars | status bar, Dynamic Island, nav buttons and the **tab bar move into an 84 pt vertical strip** on the camera's edge (trailing upright) | the same vertical strip (trailing) in landscape; normal horizontal bars in portrait |
| Top inset | **0** — nothing across the top | 0 in landscape, 82 in portrait |
| Orientation lock | honoured (like any iPhone) | **ignored** — every app shows in both orientations |
| Fold | — | a band down the display's middle (40 pt incl. margins). Active — content must keep off it — when half-open: **book** (landscape) and **tabletop/laptop** (portrait) |

Built with the iOS 27.1+ SDK (Xcode Cloud's "Latest Release" — Xcode 27.1
shipped 2026-10-15 and 27.2 on 2026-10-29), the app runs edge to edge on both
displays with vertical bars. Nothing here uses an iOS 27.1
API (see "Not done" below).

## Principles (Apple's, applied)

1. **Two layouts, not one per pose.** Compact width for the outer display,
   regular width for the inner one; flat and folded look identical.
2. **Reflow, don't stretch.** "You don't want just a stretched out iPhone
   app." One tall column becomes two columns on the inner display, with the
   seam on the fold — so in book and tabletop pose the crease always lands in
   the gap between panes, never on a control or a line of text.
3. **Same hierarchy and functionality everywhere.** Nothing exists in only one
   pose; the inner display just shows more at once.
4. **Tabletop: look at the top, tap at the bottom.** The one pose-specific
   layout Apple endorses, and the one that suits a baby tracker best: set the
   phone on the table half-open during a feed.
5. **Support the tent.** The outer display stood on its side is a nightstand
   glance — so the app now turns to landscape there.

## How the split is computed

`TwoOfUs/Features/Shared/PaneLayout.swift` is the single source:

- `ScreenShape.isCompact(horizontal:vertical:)` — size classes alone say
  "single column": every slab iPhone, the Duo's outer display upright, a Split
  View half. These render exactly the layouts they always had.
- Otherwise `PaneLayout.resolve(in:horizontal:)` (inside a `GeometryReader`)
  picks **wide** (side by side), **tall** (stacked) or **short** (the outer
  display on its side), and the band between the panes.
- On regular width the band is centred on the **display's** midline — worked
  out from the reader's size plus its safe-area insets — because the fold is in
  the middle of the display, not of the safe area (the 84 pt trailing bar
  leaves 455.5 pt of content before the fold and 371.5 pt after). That is
  exactly where the hinge is, so no hinge API is needed.
- Short (tent) uses a plain 16 pt gutter in the middle of the safe area: the
  outer display has no fold.
- Home on iPhone Duo open in landscape goes one step further: `SpreadGrid`
  turns that band into two phone-width pages (see "The spread"). iPad
  resolves wide too and keeps its panes.

## Screen by screen

### Home

| Shape | Layout |
|---|---|
| Compact (iPhone; a Split View half) | Unchanged single list. On short displays (full height < 700 pt: iPhone SE) a running sleep uses the **short sleep card** (timer beside the 💤, ≈ 70 pt shorter) and the Today card drops the duplicate elapsed time from its live caption, so the Wake slide stays on screen without scrolling. |
| Compact on iPhone Duo, closed — **the cover** | The same list, with 20 pt side margins and 22 pt above the header (nothing sits across the top of the outer display). A running sleep uses the **footprint sleep card** — the card at the Sleep tile's own size: eyebrow and predicted wake on one line, the 40 pt timer and "since" on the next, then the Wake slide — so the Wake slide always clears the bottom edge; the Today card keeps the short live caption. In the dark appearance, while he sleeps, the spine (the edge away from the system strip) carries a faint bloom of his light on the otherwise black cover — see "The light". Measured, never a model check: the phone idiom, no top inset, and the system strip down one side. |
| Wide on iPhone Duo, open in landscape (flat or book) — **the spread** | Two mirrored phone-width pages either side of the fold, over the light, with the baby's avatar in the wide outer margin. **Leading page** (the cover's page): the name and age as the page title with Settings beside it, then the Today card, the Feed and Diaper tiles and the Sleep tile — or, while a sleep runs, the footprint sleep card in that tile's place. The Today card takes up the page's slack, so the column ends on the foot line and nothing moves when he falls asleep. During daycare hours, with no tiles, the Today card is the whole page: larger totals, and the day's daycare photos as up to three tiles (tap for the viewer; "+N" on the last) over what staff logged. **Trailing page:** "Recent / last 24 hours" as the title with "+ Add note" on the subtitle's line; then whatever leads the day — the Today card's daycare layer (recap, drop-off slide, "staying home") while the tiles have the other page, SNOO suggestions, tonight / up next, the setup checklist — and the timeline as a journal card filling the rest (no pinned header; the title says it). The undo toast sits at the foot of the trailing page. See "The spread". |
| Wide on iPad | Unchanged panes. **Left:** header, Today card, log tiles, sleep card, SNOO suggestions, tonight / up next, setup checklist. **Right:** "Recent · last 24 hours" with its pinned "+ Add note" header. The undo toast sits under the left pane. |
| Tall (Duo open in portrait, flat or tabletop) | **Top half:** header, Today card, tonight / up next, checklist, timeline (scrolls). **Bottom half:** log tiles + sleep card + SNOO, centred — the feeding-station pad (on this 637 pt-wide half the short sleep card sets its Wake slide beside the timer, so tiles and card fit the half). During daycare hours, with nothing to tap, the bottom half shows the day's feed instead. |
| Short (Duo closed, stood on its side) | Header + Today card on one side; tiles, sleep card, up next and timeline on the other. |

Every sheet, task and the pull-to-refresh hang on a container that never
changes identity, and the layout switches *inside* it — so opening or closing
the phone mid-sheet keeps the sheet (and what was typed). The SNOO card's edit
sheet moved up to Home for the same reason.

#### The spread

Closed, the phone is the cover. Opened, the same page stays under the left
thumb and the day opens beside it. `TwoOfUs/Features/Shared/SpreadGrid.swift`
is the single source of every frame — a pure value type resolved from the
`PaneLayout` (phone idiom and `.wide` only; iPad never gets a grid), tested in
`TwoOfUsTests/SpreadGridTests.swift`. In the reader's coordinates — the tab's
content area, 867 × 635 on the 951 × 669 display, with the fold band at
x 455.5–495.5 and the crease at 475.5:

| | On the inner display | In `SpreadGrid` |
|---|---|---|
| Pages | 350 pt each. Leading x 97.5–447.5, trailing x 503.5–853.5: 28 pt either side of the crease, 8 pt clear of the band | `idealPageWidth`, `innerMargin`, `bandClearance` → `leadingPage`, `trailingPage` |
| Head line | y 22 — both page titles start here (the 34 pt rounded title over a subheadline, ≈ 61 pt) | `headLine` → `headY` |
| Top line | y 103 — the first surface of each page (an 81 pt title slot; a larger text size pushes the surface down, still 12 pt clear, rather than overlap it) | `titleSlot`, `titleAir` → `top` |
| Foot line | y 635 — the reader's bottom edge, level with the bottom of the system's tab capsule. Each page's last surface ends on it | `foot` |
| Between surfaces | 12 pt | `surfaceGap` |
| Avatar | 52 pt, in the wider outer margin — the side away from the system strip, measured (the phone can be turned round) — 22 pt from the display's edge, its top at y 26 | `avatarSize`, `avatarEdgeInset`, `avatarDrop` → `avatarFrame`, `marginSide` |
| Undo toast | At the foot of the trailing page, inside its width: x 519.5–837.5 (16 pt in from the page's sides), 12 pt above the foot line. Never over the leading page's controls, never across the fold | `toastSideInset`, `toastLift` |

- Nothing textual or tappable sits between x 447.5 and 503.5; only the light
  crosses the fold.
- A narrower reader shrinks both pages together (never past 12 pt of outer
  margin, never closer than 8 pt to the band); under 240 pt a page there is no
  grid and Home keeps its panes. A margin too narrow to hold the avatar 8 pt
  clear of its page goes without it.
- The leading page is a fixed composition wherever it fits (its column has a
  few points to spare at the default text size) and scrolls at a text size
  where it doesn't. The trailing page's journal fills what its lead items
  leave; with less than 200 pt left, the page scrolls as a whole and the
  journal takes a fixed 320 pt (`journalFills`).
- VoiceOver reads the leading page, then the trailing page. The avatar is
  decoration there (the title beside it reads his name).
- The pages are measured without a sheet's keyboard: Home has no text field of
  its own, and a note typed in a sheet must not squeeze the pages behind it.
  (So are the Duo's other roomy layouts; iPad is measured as before.)
- In demo mode the pill's row sits above the reader. It counts toward the head
  line (the titles start right under it), so the pages keep their height.

`HomeView.spread` builds the two pages (`spreadNowPage`, `spreadRecentPage`)
from four pieces, new or extended for it. Each extension is off by default, so
every other caller is unchanged:

| Piece | Where | On the page |
|---|---|---|
| Page title | `Features/Shared/PageTitle.swift` | The header's own type without the avatar, and one trailing control: Settings level with the title, "+ Add note" on the subtitle's baseline (under the title at a text size where it can't sit beside it) |
| Today card | `TodayHeroCard`: `fillsHeight`, `layers`, `daycarePhotos` | Takes the height it is given: the strip grows from 62 pt to at most 110, the rest is air around the strip and totals. `.day` beside the tiles, `.daycare` as the trailing page's lead item, whole (`.all`: 34 pt totals, photo tiles) during daycare hours |
| Sleep card | `SleepActiveCard(footprint:)`; `LogTileFootprint` in `LogButtons.swift` | The Sleep tile's own height, taller only when a large text size needs it: 11 pt above and below, 16 pt at the sides, the tiles' 20 pt corners, a 40 pt timer. Its lines re-stack before the timer would truncate |
| Journal | `Features/Shared/JournalCard.swift` | The timeline's rows on one solid card (18 pt corners, a hairline), the last 44 pt dissolving into it. Taps, swipe to delete and pull to refresh as in every list |

#### The light

`TwoOfUs/DesignSystem/CradleField.swift` — the app's mark at the size of the
phone: a pool of one parent's colour behind each leaf and, whenever he sleeps,
his light in the hinge between them. One view, behind the content, hidden from
VoiceOver, never taking a touch; it paints out through the safe area by
itself, so the pools reach the display's corners and run under the system
strip. Where everything goes is plain geometry (`CradleField.Plan`), tested in
`TwoOfUsTests/CradleFieldTests.swift`.

| | |
|---|---|
| Ground | `AppColor.bg`. In the dark appearance, during a night's sleep ("sleeping", not "napping", by `SleepLanguage`'s rule): `nightInk`, a tenth of the way back to black. The light appearance never changes ground |
| Pools | Periwinkle (`accentSleep`) from the top corner of the leading leaf, teal (`accentFeed`) from the trailing one. Drawn 640 × 560 on the 951 × 669 display and clear at 72 % of that (≈ 461 × 403), scaled with the display. Peak opacity 0.13 / 0.10 awake; **0.07 / 0.055 asleep** — falling asleep dims the room, it never brightens it. Half of those in the light appearance |
| Hinge light | Only while he sleeps. `nightlightCream`, centred on the crease 62 % of the way down: drawn 280 × 500, clear at 70 % (196 × 350), peak 0.17, with an 80 pt core at 0.20. It breathes between 0.6 and 1 of that on the day strip's own constant (ease in-out, 2.6 s) |
| The cover | No pools and no night ground: plain black. While he sleeps, in the dark appearance, a bloom on the spine edge 62 % of the way down: drawn 220 × 420 (154 × 294), at 0.55 strength |
| Changes | A 1.2 s cross-fade |

- **Where it is drawn.** Behind Home's spread — the pools always, the hinge
  light while he sleeps — and behind the cover in the dark appearance (a
  light cover is the list it always was). No other screen or pose draws it
  yet, and no slab iPhone or iPad ever does.
- **On.** "Asleep" is any sleep in progress: a parent-logged or SNOO one, or
  a nap Brightwheel has started and not ended while he is at daycare — the
  same pair that makes the Today card's strip glow, so the two come on, and
  go out, together. The field is asked again once a minute (a nap becomes a
  night's sleep on the clock alone).
- **Off** — plain `AppColor.bg` — under Reduce Transparency, Increase
  Contrast, or Low Power Mode. Every layout is complete without it.
- Reduce Motion: the hinge light holds still and state changes cut.
- Placing it: give it the frame of the content it sits behind (Home hands it
  the reader `PaneLayout` measured, so the crease is `band.midX` whichever
  side the strip is on) and never wrap it in `ignoresSafeArea`. A list over
  it hides its own background.
- No stars, no hue by the clock, never an urgency colour.
- Under the demo-mode pill the field cannot reach the display's top edge (the
  pill's row is a band of plain background above it), so its top 96 pt fade in
  from that colour instead of starting at a hard line.
- The portrait crease and the tent's ridge are already in `Plan` (and tested);
  nothing draws them until tabletop and tent get their layouts (see "Still to
  come").

### Nighttime
Wide: tonight (hero + timeline) on the left page, the sleep-window plan on the
right. Tall: the single list with a ~600 pt readable width. Compact and short:
unchanged.

### History and Stats
Wide and tall: two columns that scroll together, seam on the fold.
History — left "rhythm" (swimlane, longest stretch, feed heatmap), right
"daily totals" (sleep, volume, diapers), with taller charts. Stats — left "the
glance" (Wrapped, record, lifetime tiles, today, milestones, care summary),
right "this week + AI" (insights, outlook, patterns, night shift, teamwork,
cadence, accuracy). Empty states top-align instead of centring on the fold.

### Shell, setup flows, sheets
- Tent pose: `OrientationPolicy` (via `AppDelegate`) lets near-square phone
  displays (long ÷ short < 1.6 — the Duo is ≈ 1.45, every slab iPhone ≥ 1.78)
  rotate; slab iPhones stay portrait-only, iPad keeps all orientations.
- Onboarding, join and restore flows: a readable ~520 pt column and a
  ≤ 440 pt bottom button on the inner display — centred in portrait, and on the
  page before the fold in landscape (`leadingPageWidth`, measured once in
  `RootView`), so nothing sits on the crease in book pose; a smaller cradle
  mark in tent pose.
- The error banner sits on the page before the fold in landscape (centred in
  the safe area it would straddle it) and is capped at 440 pt. Undo toasts
  ride on a pane or page, never across the fold, capped at 480 pt: Home's sits
  at the foot of the spread's trailing page. Slide-to-confirm ≤ 360 pt (an
  80%-of-width slide on the inner display crossed the fold).
- Launch curtain blocks touches across the whole display, side strip included.
- Feed, baby and profile sheets don't re-seed their fields if `onAppear` fires
  again on a fold; the Diaper sheet can expand to large (the outer display's
  half sheet hid Logged by and Note).
- Daycare map is shorter in tent pose.

### System surfaces
- **Dynamic Island:** the Duo shows compact Live Activities in a 28 pt circle
  (`isDynamicIslandLimitedInWidth`). The compact view now shows just 💤 and an
  empty trailing view, which Apple says the system hides — instead of a timer
  that truncated after the first hour.
- **StandBy** (either display, no charger needed): the sleep Live Activity sets
  `activityBackgroundTint` so it fills the screen; small widgets drop the hint
  and ⊕ badge and enlarge the since-line when their background is removed.

## Still to come

Approved with the spread (2026-11-12), not built yet. Until each lands, the
screens and poses it names are exactly as described above.

- **Nighttime, History and Stats on the grid.** Page titles on the head line,
  the avatar in the margin, first screens that end on the foot line, the light
  behind them; Nighttime's plan drawn as a to-scale strip; the launch /
  restore mark on the spine. Changes the Wide layouts on iPhone Duo under
  "Nighttime" and "History and Stats".
- **Tabletop and tent.** Open in portrait: a poster on the top half, an
  anchored pad on the bottom; while he sleeps, the timer upright as a face and
  the Wake slide on the flat half. Tent: the Today card and three tiles by
  day, a night-light poster while he sleeps. Both get the light. Changes
  Home's Tall and Short rows.
- **The page-turn composer.** On the open display, logging turns the page
  into the composer instead of raising a sheet. Sheets stay as they are until
  then.

## Not done (deliberately)

- **iOS 27.1 APIs** (`reservedRegions`, `onHingeChange`, `presentationPlacement`,
  `toolbarVerticalEdge`): Xcode Cloud's SDK couldn't be confirmed from here, and
  an undeclared symbol fails the build even behind `#available`. The display
  midline gives the same split on the Duo. Once the workflow environment is
  confirmed on Xcode 27.1+, `PaneLayout.resolve` can prefer
  `proxy.reservedRegions(kind: .division, options: .includeInactive)` and
  sheets in tabletop pose can keep their controls off the fold.
- **Sidebar tab bar** on the inner display — Apple reserves it for
  information-dense apps; four flat tabs would lose a third of the width.
- **Extra-large Today View widget** (`systemExtraLargePortrait`) — Apple's
  sources disagree on iPhone support.
- **App Store:** iPhone Duo screenshots (outer 1398 × 2034 / 2034 × 1398, inner
  2007 × 2853 / 2853 × 2007) are required for submissions from April 2027.

## Device checklist (first night with the Duo)

1. **Closed, upright:** Home's tabs sit in the right-hand strip; start a sleep —
   the sleep card takes the Sleep tile's place at the tile's size, Wake slide
   included, without scrolling. In dark mode a faint warm bloom appears on the
   hinge edge while he sleeps, and goes when he wakes.
2. **Closed, stood on its side (tent):** the app turns to landscape; Today card
   on one side, tiles on the other.
3. **Open, landscape:** Home is the spread — his page on the left (name,
   Today card, tiles), "Recent" on the right, his avatar in the wide margin;
   both pages end on one line, level with the tab capsule's bottom. Fold it
   like a book — nothing moves, nothing sits on the crease. Start a sleep: the
   Sleep tile becomes the sleep card in place, the room dims and his light
   comes on in the hinge. Log a diaper: the undo toast is at the foot of the
   right page. Open a Feed sheet, pick an amount, type a note (the pages
   behind the sheet stay put), close the phone — the sheet is still there.
   Turn on Low Power Mode: the light is off and nothing else changes.
4. **Open, portrait; then tabletop:** log tiles on the bottom half, Today card
   and timeline on top.
5. Nighttime, History, Stats in both inner orientations: two columns/pages.
6. **Split View** with Messages: Home falls back to the phone layout. Known
   and accepted: open in landscape, the half that sits against the system
   strip measures exactly like the closed cover (phone idiom, no top inset,
   the strip down one side — and within a few points of its size), so it
   gets the cover's version of that layout: the Sleep-tile-sized sleep card
   and, in the dark while he sleeps, the faint bloom on its divider edge.
   The other half is the plain list. Look at both halves once; if the bloom
   reads wrong on the divider, `cover` in `HomeView.compactList` needs a
   discriminator a size can't give (the window scene filling its screen).
7. **Lock Screen / StandBy:** start a sleep — the side Dynamic Island shows 💤;
   stand the phone up unplugged — the Live Activity fills the screen.
8. Launch curtain (`-forceResumeCurtain` in a debug build, or reopen after 30
   min): tapping the side tab bar does nothing while it's up.
