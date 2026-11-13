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
| Compact on iPhone Duo, closed | Exactly the iPhone layout, with 20 pt side margins and 22 pt above the header (nothing sits across the top of the outer display). On this short display a running sleep uses the short sleep card, as on iPhone SE. Measured, never a model check: the phone idiom, no top inset, and the system strip down one side (or the list starting at the very top of its window). |
| Wide on iPhone Duo, open in landscape (flat or book) — **the spread** | **Trailing page:** the iPhone app's Home exactly — the same list the closed phone shows (`compactList(onSpread: true)`), starting at the fold band's edge and as wide as the closed phone's content (382 pt, or what the reader has left), with its own undo toast; it sits on the light instead of its own background. **Leading page** — the details a phone has no room for (`spreadDetailsPage`), following the day: **5–10 AM, the fridge** — last bottle, last diaper, next bottle, sleep, medicine and the latest note in big print; **from 5 PM until tonight's window, his book** — today's photo (tap for the viewer; a milestone's photo when daycare sent none), today's highlights (`DayHighlights`: up to eight weighted moments — milestones, a record or long sleep, notes from either parent or from daycare, the day's daycare photos, activities, a mood, a standout bottle, drop-off and pick-up — the heaviest kept, shown in time order) and a month ago today. In the light appearance the spread's ground is the sky (as on the closed phone) instead of the light; in between, with a co-parent, their side of today ("Last from …" as a timeline row, today's feeds and diapers side by side, their latest note) over "Today so far" against the 7-day average; overnight, while tonight's window is open, "Tonight · the two of you" — whether they are in their planned sleep and until when, their last entry, the night's plan to scale (`NightPlanStrip`), and since-midnight tallies. On your own (or before this phone knows its participant): "Today so far" by day, and the fridge or the book through tonight's window. See "The spread". |
| Wide on iPad | Unchanged panes. **Left:** header, Today card, log tiles, sleep card, SNOO suggestions, tonight / up next, setup checklist. **Right:** "Recent · last 24 hours" with its pinned "+ Add note" header. The undo toast sits under the left pane. |
| Tall (Duo open in portrait, flat or tabletop) | **Top half:** header, Today card, tonight / up next, checklist, timeline (scrolls). **Bottom half:** log tiles + sleep card + SNOO, centred — the feeding-station pad (on this 637 pt-wide half the short sleep card sets its Wake slide beside the timer, so tiles and card fit the half). During daycare hours, with nothing to tap, the bottom half shows the day's feed instead. |
| Short (Duo closed, stood on its side) | Header + Today card on one side; tiles, sleep card, up next and timeline on the other. |

Every sheet, task and the pull-to-refresh hang on a container that never
changes identity, and the layout switches *inside* it — so opening or closing
the phone mid-sheet keeps the sheet (and what was typed). The SNOO card's edit
sheet moved up to Home for the same reason.

#### The spread

Closed, the phone is the iPhone app. Opened, the same app is the trailing
page and the details open beside it. Home places its phone page itself (see
the Home table); every other frame comes from
`TwoOfUs/Features/Shared/SpreadGrid.swift`
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

`HomeView.spread` builds Home's two pages: `spreadDetailsPage` on the grid's
leading page, and the compact list as the phone page. The building blocks
step A added for the earlier spread (`TodayHeroCard`'s `fillsHeight` /
`layers` / `daycarePhotos`, `SleepActiveCard(footprint:)`, `JournalCard`) are
off by default and no longer used by Home.

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
| Changes | A 1.2 s cross-fade |

- **Where it is drawn.** Behind every tab's spread — the pools always, the
  hinge light while he sleeps. The closed phone is the plain iPhone app, and
  no other pose, slab iPhone or iPad draws it. (`CradleField.Hinge.spine` is
  still in `Plan`, unused.)
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

### The other tabs on the spread

On iPhone Duo open in landscape, Nighttime, History and Stats use the same
two pages as Home, drawn by one view: `Features/Shared/SpreadScaffold.swift`.
It draws the light, the margin avatar, a `PageTitle` on each page's head line,
and hands each page's content the height left under its title. It also hides
the navigation bar (the page titles are the titles) and floats a tab's undo
toast at the foot of the trailing page. `SpreadPageScroll` and
`SpreadFirstScreen` give a page a first screen that ends on the foot line with
the rest a scroll away. iPad's `.wide` and every other shape keep the code
they had. Home draws the same frame by hand (its light also follows a
daycare nap, and its trailing title re-stacks at large text sizes). The tabs'
light follows parent-logged and SNOO sleeps only — not a Brightwheel nap,
which only Home's queries can tell.

### Nighttime
Wide on iPhone Duo — the spread: **"Nighttime / Tonight"** with the Nighttime
settings button beside the title (the moon, moved from the hidden navigation
bar), then who's up next and the night's rail on one journal card down to the
foot line. **"The plan / Your sleep, planned"**: one card with the sleep
windows and "Add a sleep window", the plan drawn to scale (`NightPlanStrip`:
the night window as a track, each parent's window a pill in their colour,
clipped to the night; geometry in `NightPlanScale`, tested in
`NightPlanScaleTests`), the night's numbers (planned sleep each, feed spacing,
the window), and the explanation as three short paragraphs. Wide on iPad:
tonight on the left pane, the plan on the right. Tall: the single list with a
~600 pt readable width. Compact and short: unchanged.

### History and Stats
Wide on iPhone Duo — the spread. History: **"History / Last 7 days"** opens on
the swimlane and the longest-stretch card, whose chart takes the rest of the
page; **"Daily totals / This week"** opens on total sleep and daily formula,
sharing the page evenly. Stats: **"Stats / All time"** opens on the share row,
the record (taller, taking the slack) and the lifetime tiles; **"This week /
and what's next"** opens on the AI cards that are showing, the last one taking
the slack. Every other card is a scroll away on its page; at a text size where
a first screen needs more than its page, nothing stretches and the page
scrolls sooner.

Wide on iPad, and tall: two columns that scroll together, seam on the fold.
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
- **The mark on the spine.** Open in landscape, the safe area is off-centre
  (the strip takes 84 pt from one side), so a centred mark would sit 42 pt off
  the crease. There the launch curtain's mark stands on the crease, one
  parent's circle on each page; the restore screen draws the mark at 210 pt on
  the crease, "Welcome back" closing the leading page and the status, shimmer
  and Try again opening the trailing one, on one baseline — no word between
  the pages. `RootView` measures where the spine is
  (`Features/Shared/SpreadSpine.swift`, tested in `SpreadSpineTests`) beside
  `leadingPageWidth`; everywhere else there is none and both screens are
  unchanged.
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

1. **Closed, upright:** Home is the iPhone app, its tabs in the right-hand
   strip; start a sleep — the short sleep card, Wake slide included, without
   scrolling.
2. **Closed, stood on its side (tent):** the app turns to landscape; Today card
   on one side, tiles on the other.
3. **Open, landscape:** the right page is the iPhone app exactly; the left
   page is your partner's side of today (last entry, today's split, their
   note, today against the usual) — or, during tonight's window, "Tonight"
   with their planned sleep and the plan to scale. Fold it like a book —
   nothing sits on the crease. Start a sleep: the room dims and his light
   comes on in the hinge. Log a diaper: the undo toast is on the right page. Open a Feed sheet, pick an amount, type a note (the pages
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
