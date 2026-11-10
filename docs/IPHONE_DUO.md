# iPhone Duo

How Two of Us lays out on iPhone Duo — Apple's passport-style foldable (iOS
27.1, shipped 2026-10-23) — and why. Written 2026-11-10 from Apple's
"Designing for iPhone Duo" HIG, the six iPhone Duo Tech Talks (111461–111466),
"Preparing your app for iPhone Duo", and a survey of the third-party apps
reviewers singled out (timespent, Flighty, Things, Fantastical, Netflix, Halide).

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

## Screen by screen

### Home

| Shape | Layout |
|---|---|
| Compact (iPhone; Duo closed) | Unchanged single list. On short displays (full height < 700 pt: the Duo's outer display, iPhone SE) a running sleep uses the **short sleep card** (timer beside the 💤, ≈ 70 pt shorter) and the Today card drops the duplicate elapsed time from its live caption, so the Wake slide stays on screen without scrolling. |
| Wide (Duo open in landscape, flat or book; iPad) | **Left page:** header, Today card, log tiles, sleep card, SNOO suggestions, tonight / up next, setup checklist. **Right page:** "Recent · last 24 hours" with its pinned "+ Add note" header. The undo toast sits under the left page. |
| Tall (Duo open in portrait, flat or tabletop) | **Top half:** header, Today card, tonight / up next, checklist, timeline (scrolls). **Bottom half:** log tiles + sleep card + SNOO, centred — the feeding-station pad. During daycare hours, with nothing to tap, the bottom half shows the day's feed instead. |
| Short (Duo closed, stood on its side) | Header + Today card on one side; tiles, sleep card, up next and timeline on the other. |

Every sheet, task and the pull-to-refresh hang on a container that never
changes identity, and the layout switches *inside* it — so opening or closing
the phone mid-sheet keeps the sheet (and what was typed). The SNOO card's edit
sheet moved up to Home for the same reason.

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
- Onboarding, join and restore flows: a centred ~520 pt column and a ≤ 440 pt
  bottom button on the inner display; a smaller cradle mark in tent pose.
- Error banner ≤ 440 pt; undo toast ≤ 480 pt; slide-to-confirm ≤ 360 pt (an
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
   the whole sleep card, Wake slide included, is visible without scrolling.
2. **Closed, stood on its side (tent):** the app turns to landscape; Today card
   on one side, tiles on the other.
3. **Open, landscape:** Home is two pages; the timeline on the right. Fold it
   like a book — nothing moves, nothing sits on the crease. Open a Feed sheet,
   pick an amount, close the phone — the sheet is still there.
4. **Open, portrait; then tabletop:** log tiles on the bottom half, Today card
   and timeline on top.
5. Nighttime, History, Stats in both inner orientations: two columns/pages.
6. **Split View** with Messages: Home falls back to the phone layout.
7. **Lock Screen / StandBy:** start a sleep — the side Dynamic Island shows 💤;
   stand the phone up unplugged — the Live Activity fills the screen.
8. Launch curtain (`-forceResumeCurtain` in a debug build, or reopen after 30
   min): tapping the side tab bar does nothing while it's up.
