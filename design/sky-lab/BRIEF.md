# Brief — Home's sky, redrawn

## The ask

Taylor, in his words: *"I like the backgrounds you created for the duo and I want you to
keep the general sentiment — as well as the shift from day to night — but I want you to
think and design hard at making something truly breathtaking and beautiful. Something that
is a signature moment for the app."*

The sky today (`TwoOfUs/DesignSystem/SkyBackground.swift`, `skies/baseline.js` here) is the
real sky outside by the real clock: sun on its arc, the real moon in its phase, painted
clouds, twinkling stars, four misty ridges of hills. It is deliberately *hushed* — a fifth of
its colour, close to the page grey — because at full colour it fought the app's accents.
It is pleasant. It is not breathtaking. Nobody would hand you their phone to show it.

**Keep:** the real sky by the real clock (sunrise, sunset, moon, stars); sun, moon, clouds,
hills; the turn from day to night; calm above everything — *calm, not clinical; a nursery
at night*. The app is used one-handed at 3 AM holding a baby.

## What Taylor decided (21 Nov 2026)

1. **Quiet, and it blooms at moments.** Hushed ground for most of the day. At the real
   turning points — sunrise, golden hour, sunset, the first stars, Miller falling asleep,
   the Duo opening — it opens up to full beauty for a while, then settles back.
   → `lab/presence.js`: `presence(state)` gives 0 (hushed) … 1 (full). Build palettes at
   full strength and quieten them with `present()` / `presentDark()` in `lab/oklab.js`.
2. **A star for every night of his life.** Night 1 is the night he was born; the sky fills
   as he grows (143 tonight). Each night's star has its own fixed place. Tonight's star is
   warm and is lit when he goes down for the night. → `lab/nights.js`.
3. **The seasons of his first year.** The land turns with the real season: bare, frosted
   late-autumn hills now, snow, blossom, summer fireflies. → `lab/season.js`.
4. **Slow and living.** Clouds drift over minutes, mist moves in the valleys, stars twinkle,
   a rare shooting star; depth shifts gently with tilt and scroll. Nothing bounces for
   attention. Everything holds still under Reduce Motion.
5. **Two showpieces:** **opening the Duo** (the cover's sky widens into one panorama across
   both pages, like a picture book's double-page spread) and **bedtime** (he falls asleep:
   the sky dims, his star is lit, the first stars come out; waking reverses it).

## Round two — one place, in true light (21 Nov 2026)

Round one built five directions (`skies/true-light`, `picture-book`, `paper-theatre`,
`wet-wash`, `night-light`, each with a candid `.md`; the director's verdicts are in
`gallery/content.json`). Taylor looked at them and decided:

1. **Picture book's place, painted with True light's air.** The hill, the knoll and the one
   tree against the setting sun are the signature. They get True light's atmosphere: mist
   lying in the valleys, ridges that fade with distance, clouds lit from where the sun
   really is, a twilight with its true layers.
2. **Bedtime looks up.** As the cards leave, the view tilts up: the land sinks to the foot
   of the screen, his stars fill it, then it settles back.
3. **Opening the Duo finds a river valley.** The left-hand page is the far side of the land:
   a river with mist on it under the cool half of the sky.
4. **One grown tree.** Mature, on the knoll. Only its leaves change through his first year.

Everything above this section still holds (the ask, the hard limits, the windows). Where
this section differs from the older notes below, this section wins.

### What to take from round one

- **picture-book:** the composition. Horizon at y 292 on the Duo, the same points on cover
  and spread; the tree on its knoll in the strip column (x ≈ 399), the sun setting just to
  its right; on the slab the horizon at y ≈ 140 so the header is a small complete landscape
  with the tree in the gap between his name and the gear. The tree itself in four seasons.
  Hand-set stars with four-point ones for the first night and the month-nights.
  "✦ Night 143" as a caption. Its weaknesses: flat hills, loaf clouds, one dry-brush
  texture doing every edge, a tall empty land at bedtime, a plain left-hand page.
- **true-light:** the light. The twilight table by solar altitude printed twice (light and
  dark), bands that stand tall over the sun and sink away from it, the Belt of Venus over
  the earth's shadow on the far side, cloud lit from the sun's real place, ridges taking
  their colour from the horizon sky, level mist. It is also the only direction that passes
  every measured limit. Its weaknesses: airbrushed spindle clouds, no subject, seasons
  that cannot be told apart with the cards on.
- **night-light:** the bedtime gesture — a thin ring of light leaves tonight's star and
  every other star answers as it passes. Soft, slow, never sonar.
- **paper-theatre:** nothing structural, but its ember-lit edges at sunset are a reminder
  that a rim of caught light on a ridge is worth more than a gradient.

The picture must not become a third thing. It is an illustrated place — shapes with
intention, drawn by a hand — standing in real air. If a frame could be a photograph, it has
lost the picture book; if it could be a sticker, it has lost the light.

### The place

Left to right across the open Duo, one continuous land:

- **The river valley** (the leading page, world x < 0). The hills fall away to a river that
  winds back into the distance. Mist lies on the water; the river is the lightest thing in
  the land and carries whatever light is in the sky: the low sun's gold at dawn (the sun
  rises out of the fold gutter and lights the mist from the right), the cool afterglow
  opposite the sunset, the moon's broken path. The leading margin column (x 0–97) and the
  gutter (x 447–505) are clear top to bottom: a bend of the river belongs in one of them.
  The valley must be worth finding on its own, bare, at `lead=0`.
- **The hills** between, fewer and better: overlapping rounded shoulders with real depth —
  far is lighter, bluer, softer; near is darker, warmer, crisper — and mist between planes.
- **The knoll and the tree** (the phone page's strip column). A grown, broad-crowned tree,
  drawn with care at three sizes (it is ~55 pt tall on the Duo; it must also hold up in the
  3× lightbox): a trunk that divides into real limbs, a crown with a silhouette you would
  recognise. Late autumn now: bare limbs, a few last leaves, frost. Winter: snow on the
  limbs and the knoll. Spring: blossom. Summer: a full green crown, fireflies from dusk.
  Autumn: amber, thinning. The sun sets behind and just to the right of it; the moon passes
  over it. The season must be legible from the strip alone, cards on.

Sun and moon keep the baseline's clock and x inside the anchor window (README). If you can
extend the moon's track onto the leading page without changing what the cover and the slab
show, do, and say how; otherwise the river carries its light and you say so plainly.

### The camera (new)

The world is now seen through a camera with two poses, and every layer answers to it.

- **Rest** — the everyday view. Duo: horizon y ≈ 292 (cover and spread identical in points).
  Slab: horizon y ≈ 140, the header's small landscape.
- **Looking up** — bedtime. The camera pitches up and turns a little toward the tree. The
  land sinks to a low band at the foot of the display with the tree small upon it, and the
  sky that was above the top edge comes down into view. Aim: Duo horizon y ≈ 590–620 with
  the tree brought left, clear of the tab capsule (x 392–456, y 396–644), to about
  x 300–350; slab horizon just above the floating capsule (y 791), tree clear of nothing.
  Check the measured rects in `state.layout` and `state.cards`; do not trust these numbers.
- One camera for the whole world: the spread's phone page is the cover's picture in both
  poses and at every instant between. Parallax between planes during the move is welcome
  (near land sinks faster than far); gaps and popping are not.
- `look` (0 rest … 1 up) is the sky's own function of `state.event` for `bedtime`: 0 until
  0.3 s, eased to 1 by about 2.4 s, held to 5.3 s, eased back to 0 by 7.5 s (the cards are
  away from 1 s to 5.5 s: `state.veil`). Also read a URL override `look=0…1` (parse
  `location.search` yourself) so any pose can be shot at any hour.
- Under Reduce Motion there is no move: the looked-up still cross-fades in and out.

### His stars, on a tall sky

His stars now live on the whole sky the looked-up pose reveals, not only the part the rest
pose shows. `nights()` still gives each night its fixed place; map it over the tall sky
(all inside the anchor window's width, allowing for the turn). At rest you see the lower
sky — in the header band and the strip, weighted so those are never empty at night. At
bedtime the rest come down into view and for five seconds every night of his life is on
screen at once. That is the point of the moment: count them (`tools/measure.mjs
--stars-by-age` counts for you) — in the looked-up pose, veil up, all of them must be
visible and none behind the header text, the island or the capsule.

Tonight's star is lit beside the tree — the evening star, above its shoulder — and stays
with the tree through the move. It is findable all night at rest with the cards on (the
strip's clear window, `state.layout.stripClear`, which shrinks when a sleep is running).
Draw it when `state.tonightLit` is true. It takes its permanent place the next day.

### Bedtime, looking up

When a night sleep starts (cover, November, full dark):

- 0–1 s: the cards fall back. The camera begins to rise.
- ~1.5 s: tonight's star ignites beside the tree (`ignition()`).
- ~2–5 s: the camera is up. The ring leaves the star and crosses the whole sky once,
  slowly; each of his stars swells as it passes and settles a little brighter than before.
  "✦ Night 143" stands quietly at the foot, on the side away from the tree.
- 5.3–7.5 s: the camera comes down, the cards return. The star stays lit.

In July the sun is still up at 19:40 (+7°): looking up, the tree stands against the low
sun; his stars are not visible in that sky until the ring shows them, one by one, and lets
them go again. That frame was round one's best picture — make it the showpiece it nearly
was. Both must be right in both appearances.

The held frame (3–5 s) is the single most important picture in this round. Compose it as a
poster: where the tree sits, where the caption sits, where the moon is (it comes down into
view with the sky), how the stars are spread, what the land's low band is doing.

### Opening the Duo, onto the valley

Unchanged in timing: the leading page arrives bare (`lead=0`), holds about a second while
the sky swells, then its cards land by 1.8 s. What is new is that there is something to
find. In that second the valley is the picture: let one slow thing happen in it — the mist
on the river brightening from the fold outward as the light reaches it, for instance — and
nothing else. No pop-up, no parallax trick.

### Light appearance at night

Every round-one direction was a pale flat page with faint specks here. It needs a real
answer inside the limits (behind the grey text the sky stays ≥ 0.55 luminance; below the
band the ground stays a light page). Treat it as a storybook night on pale paper: the
deepest lilac-slate the limits allow at the top of the sky, graded; a luminous moon with a
soft halo; stars as small clean lights with a slightly deeper sky around each; the land in
soft slate with mist paler than the sky. Most people will be in the dark appearance at
night, so this matters less than dusk and dawn in light — but it must not look broken.

### Gates

`node tools/measure.mjs --sky <id>` (and again with `--asleep night --times
19:40,21:00,03:00`) is the same ruler for everyone; its verdicts were checked
independently. Round one, frames failing of 96 at the standard and text-crossing hours:
baseline 52, true-light 0, picture-book 15, paper-theatre 2, wet-wash 0, night-light 9
(`shots/_prep/verify/measure-rederived/table.txt`). A round-two sky ships with **0 FAIL**
in both runs, and says which checks are AT-LIMIT. What failed in picture-book and must not
come back: the moon's and the lit star's glow making dark-night ground lighter than a card;
the light grey line at 2.66:1 with a night sleep running; the dimmed sun crossing the age
line at 09:30.

New in the lab since round one (README): `state.layout` (the real text rects — stop
hard-coding them), `cards[].opacity`, `state.tonightLit`, `state.sun.x` after sunset,
`snowfall=1`, a sky host that can no longer paint over the UI, and review sets `text`,
`tilt`, `snow`, `wake`.

### What the app gives the port (read from the Swift, 21 Nov 2026)

Checked twice against the code (files named in each point). None of this changes what a
sky module does in the lab, but the picture has to survive it.

- **Place and time.** The sky already takes the household's daycare pin for the sun and
  moon (`HomeView` passes `daycareSettings?.daycareCoordinate`); with no pin it assumes 40°N
  on the time zone's meridian (`SolarClock.approximateLocation`). The lab's Chicago is a
  stand-in. His birth date is stored,
  so the night count is real; a due date in the future means no nights yet.
- **iOS 26 is the floor** (`project.yml`), so a Metal shader through `colorEffect` /
  `layerEffect` is available. None exists in the app today, and no `Canvas` either: the sky
  is SwiftUI shapes, gradients, blurs and five images, recomputed once a minute, with the
  stars alone on a 24 fps timeline.
- **Home is one `List`; the sky is its background** (`HomeView.swift`). The header is the list's first row and
  scrolls away; the sky stays put. So the composition is right at scroll-top and must
  simply stay calm when cards ride up over the horizon.
- **The tab bar is system glass** and minimises on scroll (`RootView.swift`). Home does not own its frame.
- **On the open Duo there are two sky views** (the phone page's and the leading page's),
  each with its own clock. A camera move needs one shared driver for both.
- **Nothing observes the Duo opening today,** and the layout swap has no animation. The
  opening moment has to be built; the leading page's first appearance is the natural cue.
- **"Night sleep" has no single meaning in the app.** The wording rule (`SleepLanguage.swift`) calls any sleep begun
  before 20:00 a nap for its first two hours; the night schedule is a separate, adjustable
  window (`SharedSettings`, default 20:00–08:00). A 19:40 bedtime is outside both. The port must define what
  starts the bedtime moment, and only a tap on this phone's Home can be told from a synced
  or Siri-started sleep.
- **Cards fading back** means fading list rows one by one (the timeline's card is a row
  background), on both pages of the spread, without touching the sky or the undo toast.

## Round three — the night stays up, and better drawn (21 Nov 2026)

Taylor looked at round two (`skies/hill-painted`, its gallery and its films) and decided:

1. **The painted hill is the picture.** The one thing he does not like is the bedtime moment
   looking up and then looking back down. In his words: "It should just look up to the sky,
   show the star animation, and then the cards. Looking back down is too much."
2. **Better drawn** — not bolder, not simpler. The same picture and the same restraint, with
   finer craft: clouds, leaves, light on the land, the stars.
3. **What starts the moment: an evening sleep started by hand.** A sleep started with Home's
   Sleep button between 6 pm and 4 am plays the moment on that phone. A sleep that arrives any
   other way (the other phone, Siri, a widget, SNOO) plays nothing: Home shows the night as it
   already is, tonight's star lit.
4. The Swift will be built and run on Taylor's Mac, once the design is signed off.

Where this section differs from round two above, this section wins.

### The night stays up

- **`look`** for `bedtime` is 0 until 0.3 s, eased to 1 by about 2.4 s, and then it **stays
  at 1 for as long as the night sleep runs.** There is no way back down inside the moment.
- **The moment:** the cards fall back (0–1.6 s) while the view rises; tonight's star ignites
  (~1.5 s); the band of light leaves it and his stars answer; "✦ Night 143" stands at the
  foot; then **the cards return over the sky that is already there** (from about 4.8 s, back
  by about 6.8 s). Once the view is up, nothing in the picture moves again except what always
  moves (twinkle, the mist's breathing).
- **The night is the looked-up sky.** While a night sleep runs — whoever started it, however
  Home was opened — Home looks up, still: `state.asleep === 'night'` is that pose with no
  event at all. This is now the frame the parents see most at night (every night feed), with
  the cards on, so it must be composed as a picture *with the cards on*, on all three
  displays: what stands in the strip column above the capsule and in the header band, what
  shows through the gaps and the glass. **Tonight's star must be findable all night with the
  cards on** — in the strip's clear window on the Duo (`state.layout.stripClear`, which
  shrinks while a sleep runs), in the header band on the slab. It may have two homes on
  screen (beside the tree at rest; in that window looking up) and travel between them with
  the camera, so that it is still wherever the view comes to rest.
- **Waking** (any source): no card choreography. Behind the cards the view settles back to
  the land, slowly (about 3 s), as tonight's star cools. This will be shown to Taylor as a
  film with the alternative named (no move at all; the day is simply at rest next time).
- **A re-settle the same night** (the sleep was ended for a feed and started again by hand):
  the view rises quietly behind the cards (about 2.5 s). No veil, no band, no caption, no new
  star. The full moment plays once a night.
- **Naps:** the rest pose, as before. **Reduce Motion:** the looked-up still cross-fades in at
  bedtime and out at waking.
- Everything round two required of the looked-up pose still holds with the cards away: all of
  his stars in view and none behind the header text, the island or the capsule; the cover is
  the spread's phone page at every instant. And both `tools/measure.mjs` runs must still
  print PASS — the `--asleep night` run now measures the looked-up pose with the cards on.
- The lab's own timelines follow: `tools/review.mjs` (`BEDTIME`) and `tools/film.mjs`
  (`UI.bedtime`) bring the cards back from about 4.8 s to 6.8 s.

### Better drawn

The picture is right; the drawing is not all at the level of the bare tree against the sun.
In the order the director would fix them:

- **Crowns in leaf.** The bare tree is fine pen work; the leafed trees are flat clumps in
  three tones, a different hand. Leaves want to be many small marks gathered along the
  twigs, turned to the light, with sky showing through — spring, summer and autumn each
  recognisable at strip size and good at 3×. Snow caps are still a little blocky.
- **Clouds.** Formed now, but small and soft-bodied and close to one recipe. A few designed
  forms of different families and sizes, properly lit from where the sun is.
- **Light on the land.** Midday in the light appearance is close to one value; the mist pool
  behind the fore hill is a level-topped patch; a dull brown band stands behind the tree at
  17:30 in dark; faint axis-aligned edges (about one level) show in the dark-night land.
- **The river.** A pinched waist where the bar cuts in; reeds too small to read at phone
  size; the moon's path a ladder of dashes.
- **The stars** in the light appearance at night still read as falling snow en masse.
- **July bedtime.** His stars are faint in the lighter evening sky and there are too many
  clouds in the looked-up frame.

None of this may cost the signature frame (`day/cover-dark-1610`), the gates, the star
count or the render budget.

### After the first review — the night lasts until first light (22 Nov 2026)

Two independent reviewers measured the first build of this round. Bedtime does what Taylor
asked on all three displays. What they found wrong is at its edges, and the fixes change
three things above. **Where this subsection differs from "The night stays up", this
subsection wins.** The first item is the director's reading of Taylor's "looking back down
is too much"; it has not been put to him yet, and it will be shown to him as such.

1. **Home looks up from the start of tonight's night sleep until first light**, not "while a
   night sleep runs". One fact, *the night has begun*, is true from the moment tonight's
   night sleep first starts (by any means) until first light the next morning (the sun
   coming up through about −6°). While it is true the view is up and tonight's star is lit,
   whether he is asleep or awake.
   - **A night feed moves nothing.** He wakes at 3 a.m.: the room un-dims a little, the view
     stays up, the star stays in its window. He is put down again: the room dims. There is
     no `resettle` any more.
   - **Waking never moves the camera**, at any hour, after any sleep. The room only un-dims,
     from the depth that sleep had (a night's 1, a nap's 0.45), so the first frame after he
     wakes is the frame before it.
   - **First light brings the view down.** If Home is on screen at that minute, it is a
     quiet settle behind the cards (the event `settle`). Otherwise Home is simply on the hill
     the next time it appears. So the looked-up pose is never seen in morning daylight, and
     a summer morning with him still asleep is the day's picture, dimmed.
   - **A night sleep that begins anywhere else** (the other phone, Siri, a widget, SNOO)
     while Home is on screen plays a quiet rise behind the cards (the event `arrive`): no
     veil, no band, no caption. If Home was not on screen it is simply up when it appears.
   - In the app this is a pure function of the clock, the sun and the sleep log; it needs
     no stored camera state.
2. **No join may jump.** For every change of state, the frame before and the first frame
   after must be the same picture (to within the grain), and the last frame of every event
   must be the standing frame that follows it: sleep starting and ending (night and nap),
   the moment's start and end, `arrive`, `settle`, a cloud hiding or showing in the strip, a
   star lighting. The review set must show these pairs.
3. **The moment is shorter where it was only cards.** The sky keeps its pace (Taylor chose
   "slow and living"): the rise, the band and the caption are about as they were. The cards
   fall back in about 1 s instead of 1.6, and return in about 1.2 s with an ease-out, soon
   after the caption has gone. The whole is under 6 s. In the app a touch ends it at once:
   cards back in 0.3 s, band and caption out in 0.2 s, the view stays up.
4. **With the cards on, nothing is bitten.** Looking up, the moon's or the sun's disc is
   drawn only where the whole disc stands in the open; the tree is wholly behind the cards
   in every season and under tilt; a cloud does not cross a card's edge.
5. **Nothing in the strip may read as a status icon.** A small cloud directly under the
   Wi-Fi and battery glyphs reads as a weather symbol.

## What the canvas really is

Look at `shots/baseline/` before drawing anything. The sky is **ground behind cards**, and
the cards cover most of it. What actually shows (`state.cards` has the exact rects):

- **cover (466 × 678):** a band across the top about 95 pt tall, with his avatar, name and
  age drawn on it; the **84 pt system strip** down the trailing edge, full height, with the
  Dynamic Island and tab icons on it — the one tall window; 20 pt margins and 12 pt gaps;
  and whatever comes through the three **glass log tiles**, blurred and tinted.
- **spread (951 × 669):** a frieze across the top 103 pt (951 wide — a true panorama, with
  the two page titles on it); the leading margin column (97 pt); the fold gutter (57 pt);
  the strip (84 pt); a 34 pt band along the foot.
- **iphone (402 × 874):** the top ~150 pt behind the status bar and header; 16 pt margins;
  the glass tiles; around the floating tab capsule at the bottom.

So a design that is only beautiful with the cards removed has failed, and so has one that
ignores the two moments when the picture *is* seen whole: the Duo opening (the leading
page's cards arrive a beat after the panorama, `lead=0`) and whatever you propose for
bedtime. Compose for the slivers first — the top band is the stage — and make the whole
picture worth revealing.

Hard limits:

- **Text sits on the sky** in the top band (his name, age, the page titles) in the app's own
  colours — black / `#6C6C70` in light, white / `#98989F` in dark — with no scrim. At full
  bloom the name must stay ≥ 7:1 and the secondary line ≥ 3:1. Keep the busiest, brightest
  and most saturated passages off the text.
- **Dark appearance at night stays dark.** A 3 AM feed never lights the room: night in the
  dark appearance is near-black with tints, the moon's glow is quiet, and nothing below the
  top band is lighter than a card (`#1C1C1E`). Dark blooms are deep and glowing, not bright.
- **Light appearance stays a light page** below the top band: cards are white on it; the
  ground behind them must stay close to `#F2F2F7` in value so a white card still reads.
- **The accents lead.** Teal `#5AC8B8`, periwinkle `#8E8EFF`, amber `#F5B971` belong to feed,
  sleep and diaper. At hush the sky never competes with them. At bloom it may sing, but it
  does not borrow them as its own.
- **No detail fights a card edge.** High-contrast lines crossing behind card borders read as
  glitches. Under the cards the picture goes soft and low-contrast.
- **One world, two windows** (README): the cover's sky is the anchor; on the spread the
  phone page keeps it exactly where it was and the world runs on to the left.
- **It must be buildable in SwiftUI at low cost.** Fair game: gradients; `Canvas` paths; a few
  hundred sprites; pre-rendered textures (a script like `scripts/make_sky_textures.py`);
  a Metal fragment shader through SwiftUI's `colorEffect`/`layerEffect` (GLSL here ports
  almost line for line); `TimelineView` at ~10–15 fps for drift (slow drift does not need
  more) and only where something moves. Not fair game: anything that needs 60 fps
  full-screen heavy shading to look right, video, 3-D engines, per-pixel CPU work per frame.
- Unchanged: flat page under Reduce Transparency / Increase Contrast; still under Reduce
  Motion; hidden from VoiceOver; never takes a touch.

## Director's notes — composing for the windows

Measured from the lab (`state.cards`, points). Read these with a baseline shot open.

**cover, 466 × 678.** The header *is* the top band: avatar x 20–80, name and age x 94–210,
gear x 318–362, all y 22–83; the first card starts at y 88.6 and cards run x 20–362 to the
foot, 12 pt apart. The only clear sky up there is x 210–318 and the 22 pt above the header.
The **strip** is the picture's real window: x 362–466 (the 20 pt gap and the 84 pt column),
with the clock at the top, the Dynamic Island at y 50–124 (to 158 with a sleep running),
wifi/battery to y 150 (185), then **nothing from y ≈ 158 (192) to 396**, the glass tab capsule
y 396–644, and a foot. Plus the 20 pt leading margin.

**spread, 951 × 669.** The leading margin, x 0–97.5, is clear from top to bottom — the best
window on the device. Page titles on the sky at y 22–83; leading cards y 103–635, x 97.5–447.5;
a 34 pt foot band. The fold gutter x 447.5–505 is clear top to bottom (crease at 475.5). The
phone page is the cover moved 485 pt right; strip x 847–951, capsule y 387–635.

**iphone, 402 × 874.** Status bar to y 62 (island x 138–264), header y 70–131, cards x 16–386
from y 136.6 to the foot, the glass tab capsule floating at y 791–853. No tall window at all:
here the sky is the header's ground, two 16 pt margins and what the glass lets through.

What follows from that:

- **Tall slits show vertical structure.** A twilight's whole layering — zenith, the colour
  bands, the horizon, ridge behind ridge — reads in an 84 pt column; a wide cloudscape does
  not. Compose in *bands*, and let the three slits of the spread (margin, gutter, strip) show
  the same horizon at the same height, so the eye joins them into one landscape behind the
  cards, like a view through a window with mullions.
- **Put the horizon where it can be seen.** Today the hills lie in the bottom quarter, behind
  the tab capsule, and the sun "sets" 300 pt above them into empty sky. On the Duo a horizon
  somewhere around 0.40–0.50 of the height puts the last hour of the sun, and the moonrise,
  in the strip's clear window (y 158–396) — exactly when the sky blooms. The land below it
  runs behind the cards and the capsule: keep it soft there.
- **Sun and moon keep the baseline's clock and x:** they rise at the anchor window's left edge
  and set at its right (`state.scene.body`, `state.moon`). You may remap their height to your
  horizon. So on the cover the sun sets inside the strip (x ≈ 447); on the spread it rises
  out of the fold gutter (x ≈ 504) and sets in the strip (x ≈ 932).
- **The leading page is the world running on to the left**, away from the sunset: the cooler
  side of the sky, the wider land. Its clear margin column deserves the land's one feature
  (if your land has one — a lone tree is where the seasons can live).
- **His stars are all inside the anchor window**, so every phone shows the same sky and the
  same count; the leading page may carry the ordinary, fainter sky. Weight them toward where
  they can be seen (the top band, the strip, the margins). **Tonight's star must be findable
  all night with the cards on** — e.g. it is lit low in the strip's clear window, like an
  evening star, and takes its permanent place among the others the next day.
- **Contrast, in numbers.** Light: behind the grey line (`#6C6C70`) the sky's relative
  luminance must stay ≥ 0.55 (about `#C4C4C4` or lighter) — so a light bloom is luminous
  pastel, never deep. Dark: behind the grey line (`#98989F`) ≤ 0.072 (about `#4C4C4C` or
  darker), behind the white name ≤ 0.10 — so a dark bloom is ember, wine, plum, indigo.
  "Nothing lighter than a card" is about areas, not star points.
- **The lab's glass is a guess** (blur + tint). Do not lean on what shows through a tile.

**Bedtime, as directed** (the same for every direction, so they can be compared): when a
night sleep starts, Home's cards fall back for a few seconds and the sky has the whole
display — header and system strip stay. `state.veil` (0–1) is how far back the cards are:
0 → 1 over the first second, held to about 5.5 s, back by 7.5 s. In that time the sky
deepens, tonight's star is lit (`ignition()` in `lab/nights.js` peaks at 1.5 s), and the
others answer. A touch would end it at once; under Reduce Motion it is a cross-fade. In
November 19:40 is full dark; in July the sun is still up — it has to be right in both.
A nap gets no moment, only a softer sky.

**Opening the Duo, as directed:** the cover's sky is already on the phone page; the leading
page arrives as bare panorama (`lead=0`), holds for about a second while the sky swells
(`EVENTS.open`), and then its cards land (`lead` → 1 by 1.8 s).

`node tools/review.mjs --sky <id>` shoots all of this the same way for every direction.

## The craft bar

"Breathtaking" will not come from saturation. It comes from:

- **Light that is true.** One light source, where the sun or moon really is, and everything
  answers it: the horizon glow leans toward it, clouds are rim-lit on that side and shadowed
  on the other, ridges catch it, haze thickens under it. Twilight has its real layers
  (ember at the horizon, then apricot, a hint of green-gold, rose, lilac, deepening blue;
  opposite the sun, the pink Belt of Venus over the earth's blue shadow).
- **Colour built in OKLab**, with hue carried all the way into the hush — never grey. Real
  skies: peach, apricot, rose, lilac, slate, ink. Never neon, never candy.
- **Depth.** Atmospheric perspective that reads at a glance: far is lighter, bluer, softer;
  near is darker, warmer, crisper. Mist that sits *in* valleys. Overlap.
- **Restraint.** Fewer, better shapes. One focal point per frame. Room to breathe.
- **Finish.** No banding (dither/grain), no aliasing, no muddy mixes, no repeated tiles,
  no clip-art. A still from any minute of the day should be worth looking at.
- **Stillness in motion.** If you would notice it move, it is too fast.

Avoid: generic weather-app gradient; stock "landscape wallpaper"; kitsch (lens flares, sparkle
overload, cartoon faces on the moon); anything that reads as a different app from the cards
in front of it; imitating a specific artist or film.

## What a direction delivers

1. `skies/<id>.js` — a sky module (README contract) that answers to all of: the time and the
   sun's real altitude at **any** hour; `scheme`; all three devices as one anchored world;
   `asleep`; `ageDays` (his stars); the date (season); `presence(state)`; `state.event`
   (`bedtime`, `open` — at least sensible stills at a few ages); `t` (slow motion) and
   `reduceMotion`; `state.tilt` (−1…1 each axis) if you use parallax.
2. Shots, taken with `tools/shoot.mjs` and **looked at**, iterated until they are right;
   and at the end the whole review set, `node tools/review.mjs --sky <id>`: the standard
   matrix, the bare panorama, asleep, the four seasons, bedtime, the Duo opening, stillness.
3. `skies/<id>.md` — short: the idea in a few lines; the composition decisions (where the
   horizon is and why, what lives in the top band, what the strip column shows); how each
   layer ports to SwiftUI and what it would cost; what is still unresolved. Candid.
