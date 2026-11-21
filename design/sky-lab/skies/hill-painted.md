# Hill, painted

`skies/hill-painted.js` (+ `skies/hill-painted/air.js`, `tree.js`) · shots in
`shots/hill-painted/review/` (`node tools/review.mjs --sky hill-painted --jobs 2`;
`review/CODE.md5` names the code they were shot from) · the pictures before round three are
frozen in `shots/hill-painted/review-r2b/` (and before round two's finishing pass in
`review-r2a/`). The camera, bedtime, the night, waking and the star sections are as of round
three's pass "the night stays up" (BRIEF.md); the rest is as round two left it, until the
round's drawing passes (crowns, clouds, land, river) are merged in.

## The idea

Picture book's place, painted with True light's air — the painting first.
One illustrated land: a river valley on the leading page, a few big overlapping hills, a
knoll, and one grown tree against the setting sun in the strip. Every shape is a crest line
set by hand and filled with paint; what is new is where the paint comes from. The sky is
True light's twilight table (kept almost stop for stop, printed light and dark — except the
dark print's hushed DAY, which is now a dusky slate-blue and not a second night), each plane
of land takes its colour from the horizon sky behind it at every x, mist pools in the
hollows between the planes, the flank that faces the sun turns toward its light and carries
a thin dry rim of it, the far flank turns into a cool shade, the river mirrors the sky above
each reach, and the clouds are a few designed forms — a flat base, soft lobes, a lit side and
a shadowed one. When he goes down for the night the camera looks up — the land sinks to the foot
of the display and every night of his life is on screen at once — and it **stays up for as long
as he sleeps**: the night's Home is that sky, with tonight's star in the one clear window the
cards leave.

No shader. Everything is 2-D canvas: one tall sky plane, five planes of land, sprites.

## Composition and camera

One world, in points, x = 0 at the anchor window's leading edge. Two poses; every plane
only translates between them. **Rest** is the everyday view. **Looking up** is the night: a
*state*, not a moment — the view is up while `state.asleep === 'night'`, whoever started the
sleep and however Home was opened; bedtime only carries it there (once), waking brings it
back. Naps keep the rest pose. (`lookOf()`; the URL's `look=0…1` still holds any pose.)

| | Duo (cover and spread) | slab iPhone |
|---|---|---|
| horizon at rest | y 292 | y 140 (the header is a small landscape) |
| horizon looking up | y 604 (lowered 312) | y 770 (lowered 630), just above the capsule |
| the turn | the far world slides **90 pt** left (was 78) | 30 pt left |
| tree at rest | x 408 on the knoll, 88 pt tall, crown x 368–448, top y 213 | x 286, 62 pt tall, between his name and the gear |
| tree looking up | x 318, foot y 609 — clear of the tab capsule (x 392–456) with the cards away, and its whole crown (to x 358) behind the cards (to x 362) when they are on | x 256, foot y 762 |
| tonight's star, at rest | (379, 194): above the tree's left shoulder | (262, 66) |
| tonight's star, looking up | **(412, 270): in the strip's clear window** (x 362–466, y 185–396 while a sleep runs) | **(270, 100): in the header band**, the gap between his name and the gear |
| the first night's star, looking up | (262, 43): the header's clear gap | (its own cast place) |

- **Why 90.** At 78 the crown's last twigs stood 8 pt past the cards' trailing edge when the
  cards were on — a tree behind a card with its fingers showing. At 90 the whole tree is
  behind the cards. Not further: looking up, the moon is the turn away from the baseline's x,
  and `tools/measure.mjs` only takes a disc for the moon within a fifth of the anchor window
  (93 pt) of where the state puts it; at 100 the dark-night ground check fails on the moon.
  (The tool now reports that offset for the night frames: mean ≈ 69 pt, largest 89 — it is
  the camera's turn, not a moved moon; at rest the moon is where the clock puts it.)
- **The tree is not seen at night with the cards on, on any display.** I looked for a
  composition that keeps it: the Duo's one tall window is y 185–396 and the capsule takes
  y 396–644 under it, so a tree standing in that window puts the horizon near y 390 — the
  land would be the lower two fifths of the bare frame (round one's "tall empty land") and
  the view would hardly look up; under the capsule there are 34 pt; the slab has no window
  below its header. So, plainly: **with the cards on, the night's subject is tonight's star
  among his stars**, and the tree is what the cards uncover — at bedtime, and when he wakes.
  (In the light appearance the tree is a soft ghost through the sleep card's glass.)
- **Planes and parallax.** Sky, far ridges + valley floor + river, the mid hill, the knoll
  with the tree: these move as one (sink ×1, slide ×1), so the tree keeps its place against
  the sky. The two near planes sink ×1.12 and
  ×1.3 and slide ×1.1 and ×1.25: near land leaves faster. Nothing is repainted for the move.
- **The spread's phone page is the cover's picture**, both poses. `measure.mjs`, at rest: 8 of
  16 pairs identical to within 2 levels, the largest mean difference 0.16 levels; looking up
  (the `--asleep night` run): 5 of 6 identical, the largest 0.03 levels; no point more than 8
  apart in either. Planes, gradients' knots, grass, mist pools, dither and grain are all laid
  on a world grid for that — and the bedtime band keeps the anchor window's pace on both, so
  the two are the same picture at every instant of the moment too.
- **The strip** (cover x 362–466) shows, top to bottom: one compact cloud (hidden while a
  sleep runs: the longer island's status icons would sit on it), the twilight's bands, the
  tree with the sun setting behind and just right of the trunk (sun x 435 at +1.7°, 25 pt up;
  it sets at x 447), the knoll's lit rim, a pool of mist in the hollow behind the near hill,
  the near hill.
- **The river** (spread only) is drawn as water seen from the hill. Its centre line is set
  by hand; its *width* is not: the line is laid on the valley floor (a ground plane whose
  vanishing line is the horizon) and projected back, so the far meanders are level slivers
  that tighten toward the horizon and the near reach opens to ~50 pt in the leading margin
  column — and each bank wanders on its own, so the water widens and narrows (a river, not a
  road). **There is no line along either bank** (the lip and rim of the last pass made a
  moulded channel). The fill is a pale mirror of the sky a little above the horizon — the
  lightest passage of the land in both prints; on the pale page the water keeps more of its
  colour than the hush leaves the land (like the tree), or it vanishes at midday. Where a
  reach runs *across* the view the far bank lies in it as a short dark reflection, broken;
  a bar of land comes out into the river inside the near bend; reeds stand at the water's
  edge in six places, with their reflections; level streaks of sheen cross the near and
  middle reach; ten pools of mist lie on the far *and* the middle reaches (the water is erased
  under them); the bend in the leading margin column carries one soft upright smear of the low
  sky's light. At dawn the sun rises out of the fold gutter and the far reaches burn. At night
  in the dark appearance the whole river is held at one faint value (luminance 0.0076, a card
  is 0.0117); while the moon lights the night a ladder of short silver dashes lies down the
  near reach — "the moon's broken path" as a painter's convention, **not** geometry: the moon
  is over the phone page and its true path would not fall on this water.
- **Sun and moon** keep the baseline's clock and x (`state.sun.x`, `state.moon.x`) and have
  one place in the world: height = Emax·(1 − e^(−alt/45°)) + 12·(1 − e^(−alt/2.5°)) points
  over the horizon (Emax 500 Duo, 620 slab). A high moon or sun is therefore above the top
  of the everyday view and **comes down into view with the sky** when the camera looks up.
  Neither is ever drawn in the header band (Duo) or behind the status bar (slab). The moon's
  track is **not** extended onto the leading page (it would change where the cover's moon
  is); the river carries the light.
- **Clouds**: four in the Duo's everyday view, each its own silhouette — the bank over the
  tree leans toward the sunset with a tail behind it (strip); a small two-headed puff in the
  header's clear gap; **the large one** (128 × 22 pt, three unequal masses) over the clear
  stretch of the frieze between the leading page's title and the fold; a long low two-humped
  bank over the valley — and three higher up for the evenings the camera looks up before
  dark. None on the slab at rest. Each has a firm outline, a crisp edge of light on the side
  that faces the sun, a broad cooler far side, and (near sunset) the ember underside. A cloud
  fades out before any part of its box reaches the header's words, and before it would cross
  the sun's disc (a flat base cutting the disc in two is a bitten sun).
- **Under the cards** the picture is the near hills and mist only: broad, soft, low contrast.

## How each requirement is met

- **Bloom / hush** — the table is written at full strength; `air.show()` applies the lab's
  hush with `presence(state)` (dark: 12 % deeper, two fifths of the chroma; light: toward
  the page by day, only greyed at night) and the dimmed room (`depth`). Above 15° the palette
  does not change. The light print's *tree* is exempt from most of the hush (presence held
  ≥ 0.82): a ghost-grey tree on a pale page was the one thing the hush must not make.
- **Light and dark** — two prints of one table. Dark's golden hour has its own column; the
  dusk land is aubergine, not black. **Dark by day** (sun above 15°) is a dusky slate-blue,
  paler along the horizon (sky luminance ≈ 0.03 overhead, 0.07 at the horizon; it was ≈ 0.005
  — a moonless night at 1 PM), the tree a true silhouette on it and the planes of land a
  value apart; the afternoon key (8°) was raised so the sky deepens steadily from there into
  the sunset, whose keys (≤ 2.5°) are untouched. At night the land (each plane its own value
  under a paler horizon, blue), the mist (0.0078) and the river are held under a card's
  luminance. Light gets a painted apricot sun, a warm-dark wood tree with
  no halo (umber by day, warmer in the low sun, plum-brown at night — the darkest thing in the
  picture), and land whose near planes are a step deeper and warmer at the crest with more
  air gathering at each plane's foot.
- **His stars** — `nights(ageDays, { tonightLit })`, mapped over the whole looked-up sky and
  kept clear of the header (and one em past its last glyph), the strip's furniture, the
  clock at rest, the capsule, the land, the tree's crown and each other (≥ 5.6 pt apart on
  every device). **The sky is now laid out for the looked-up view**, because that is the
  night: in boxes, top to bottom, each with a density (`starsFor`) — thickest overhead and
  thinning toward the land; a few more in the header's clear gap; fewer in the strip's clear
  window, where tonight's star is to be the one bright thing; and, low down, the two parts of
  the sky the *rest* pose shows (its header gap, its strip beside the tree) weighted so the
  night he is awake is not empty. Places are still gathered a little — a slow smooth drift of
  the whole field — and a place that is taken is cast again somewhere else. Four-point stars
  (the first night, the month-nights) keep 9 pt further from the words and buttons than the
  others, and 70 pt from tonight's place: nothing near it can be taken for it. **The first
  night's star has a place of its own on the Duo — the header's clear gap, between his name
  and the gear** — so with the cards on the night shows two stars you can name: the night he
  was born, by his name, and tonight, in the strip. Counted (age 142, tonight's lit) by the
  module's own census (`window.__hillPainted.stars`): **looking up** 143 on all three
  displays, none inside the name, age, avatar, gear, island/clock column or capsule; with the
  cards on, 12 stand in the strip's clear window, tonight's among them (Duo), and 10 in the
  header's gap, the first night's among them (7 on the slab, tonight's among them). **At rest** 61 on the cover and on the spread's phone page
  (41 in the open with the cards on), 29 on the slab — it was 71 / 47 / 33: the price of
  laying the sky out for the night's view. `tools/measure.mjs --stars-by-age --param look=1
  --param veil=1` says "144 of 142" on all three devices in both appearances: 142 nights,
  plus the two digits of the caption that differ from "Night 1" (tonight's star cancels).
- **The leading page's ordinary sky** — nobody's stars, on the whole tall sky: about as
  dense as his at the fold (so that, looking up, there is no boundary at the anchor window's
  edge), thinning and dimming to the far left, in three tints, fainter and smaller than his,
  answering the band as it passes (it dies away over the leading page). Their number follows
  his (80–460): a newborn's sky is not upstaged by the page beside it.
- **Tonight's star** — lit when `state.tonightLit`, drawn over everything, and it has **two
  homes on the display**: above the tree's left shoulder at rest (a hair-thin four-point
  spark with a small warm glow: an accent to the tree), and in the clear window looking up
  (the strip between the status icons and the capsule on the Duo; the header's gap on the
  slab). It goes from one to the other *with the camera* (`tonightHome`: a straight line in
  display points, eased as the view is), so it is still wherever the view is at rest — and
  what you see at bedtime is the star lifting off the tree's shoulder and climbing as the
  land falls away. On the way up it grows into the night's one bright star: 1.4× the size, a
  fuller glow (still tight: the room stays dark), four short rays between the long ones, and
  30 pt of dark sky of its own. While the sun is still up (a July bedtime) it is a small
  evening star, kept findable in its window — at 19:40 in July it is the only star there.
- **The night, with the cards on** (the frame the parents see most). Dark and light, 19:40,
  21:00 and 03:00, `asleep=night`, no event:
  - *Closed Duo and the spread's phone page.* The strip's clear window holds tonight's star a
    little above its middle, with eleven small stars for company, mostly below it. The
    header band holds the first night's star in the gap between "Miller" and the gear, with a
    few small ones. The 12 pt gaps and the 20 pt column between the cards and the capsule show
    a star or two (one month-star stands whole in the gap under the Today card). The tiles'
    glass shows nothing at night in dark; in light, the tree's ghost lies in the lower right
    of the sleep card. Under the capsule: the near land, dark. The land itself is not seen in
    dark with the cards on.
  - *The open Duo's leading page.* Its margin column and the gutter are tall slits of the
    ordinary sky (fainter than his) over a low dark band of the valley, whose first bends of
    river lie in the 34 pt foot. Calm; not a picture of its own.
  - *The slab.* Tonight's star is in the header, where the tree stands by day — "Miller ✦ ⚙" —
    with a few small stars. Nothing else of the sky shows but the margins.
- **Night at rest** (he is awake at night: `asleep=0` at 21:00 or 03:00) is unchanged — the rest
  pose, the tree's silhouette, tonight's star lit beside it. The night's horizon light is a band
  as tall as the tree's crown, kept under the dimmed room; just behind the crown it stands a
  touch higher (to luminance ≈ 0.010, less when the moon is up) and lets go within the strip;
  each plane of land has its own value; under a moon the knoll carries a thin cool rim.
- **Seasons** — the tree: bare limbs with a few last leaves and frost (now); **snow as a
  cap** on the upper side of the limbs level enough to hold it (1.5–2 pt on the great limbs,
  about a point on the boughs, a drift in the forks, the fine twigs edged pale from above) —
  it has to be read from the strip; blossom as gathered clumps with sprays; in leaf, a few
  large unequal masses per limb with a leaf-pointed (not scalloped) edge in three depths,
  limbs showing, and **a bay of sky at the lower right** — the long arm carries only a small
  spray — so in leaf, too, the sun sets through the limbs; in autumn the twigs stay under
  the leaf (no bristles). The land: frost along the shoulders; **snow in the dark print is
  the palest thing on the ground** (blue-white by the sky's light, down to the night's cap);
  snowfall as many small flakes in depth (a dust of far ones, a few near and soft).
- **Bedtime** (a night sleep started by hand; `event=bedtime`) — once a night:

  | s | |
  |---|---|
  | 0–1.6 | the cards fall back (`veil`) |
  | 0.3–2.4 | the view rises; tonight's star, lit from the first instant (`ignition()`, its flare at 1.5 s), lifts off the tree's shoulder to its place in the clear window |
  | 2.1–4.5 | **one soft band of light** leaves the star's place — *that* place, fixed on the display, so it never wobbles with the last of the camera's move — and crosses the anchor window to its farthest corner in 2.4 s (242 pt/s on the Duo, 342 on the slab; the same pace on cover and spread). It comes up out of nothing as it leaves (never a small circle round the star: that is sonar), is fullest a third of the way across, and has gone by nine tenths; no edge on either side, peak alpha 0.085 (dark, additive) / 0.22 (light); it lets go 150–22 pt above the horizon. Each of his stars swells as it passes and keeps a fifth more light, which it gives up slowly to the settled night's own |
  | 2.2–5.1 | "✦ Night 143" at the foot, on the side away from the tree (in by 3.0 s, going from 4.5 s) |
  | 4.8–6.8 | **the cards return over the sky that is already there.** By then the band has gone (4.2 s), his last star has answered (4.5 s) and the caption is leaving: nothing is seen through a returning card but the still night |
  | after | nothing moves but the twinkle and the mist. (The tone goes on settling to 9 s — the room dimming — and the bloom lets go over 14 s: a slow fade, not a movement.) |

  There is no way back down inside the moment (`look` stays 1). In November the moon has come
  down into the upper left of the frame with a fuller halo. In July the sun (+7°) stands
  behind the crown in a column of its own light, and his stars, shown one by one by the band,
  keep a faint presence while the cards are away and are let go as the cards return (a sky
  that light has no stars). A sleep that arrives any other way plays nothing: Home is simply
  the night as it is, tonight's star lit in its window.
- **Waking** (`event=wake`, any source) — no card choreography. Behind the cards the view
  settles back to the land over 3 s (0.2–3.2 s), the room un-dims over 5 s, and tonight's star
  goes back to the tree's shoulder as it cools and goes out (0.4–4.5 s). At 06:40 in November
  that is the dawn rising into the strip as the tree arrives in it. (The alternative the
  director will name to Taylor: no move at all — the day is simply at rest next time Home is
  opened.) A wake in the night with the star still lit (a feed) brings the view down the same
  way and leaves the star lit beside the tree. *The lab's `wake` does not say which sleep
  ended, so the module takes a wake between 09:00 and 18:00 for a nap's: nothing moves.*
- **A re-settle the same night** (`event=resettle`, new in the lab; `asleep=night`) — the view
  rises quietly behind the cards over 2.5 s and the room dims again over 4 s. No veil, no band,
  no caption, no new star: the lit star just goes up to its window with the view.
- **Opening the Duo** — the valley is already there; the one thing that happens in the bare
  second is **light running down the river toward you**: a crest leaves the furthest bend at
  0.1 s and is at the foot of the page by 0.9 s, slow among the far bends and quick through the
  near reach. The water itself and the mist lying along the river's own course take it as it
  passes, keep half of it while the cards land (0.9–1.9 s in the film), and let it go by
  ≈ 4.4 s. Light added in the dark appearance; a warm pass over pale mist on the light page;
  held to a breath at night. (Watching the first film showed the earlier version — a front
  crossing the page sideways from the fold — was too faint and mostly hidden by the landing
  cards; it was replaced after that.) **At night while he sleeps the leading page arrives
  looking up**: the ordinary sky over a low band of the valley, the river's far bends at the
  very foot. The river's light is timed to what that pose shows of the river (its run ends at
  the foot of the page in either pose) and is still only a breath; so at night the one slow
  thing is the sky's: the page's stars come out from the fold outward over the bare second
  (dim until the front reaches them, a small swell as it passes), and nothing else.
- **Light appearance at night** — lilac-slate sky graded to the horizon. The stars were soft
  round white dots, and a field of those is falling snow; they are now drawn as stars are
  drawn on paper: the faint nights as small crisp points with hardly any patch, the brighter
  fifth as small four-point glints, each on its own bit of dusk (the leading page's ordinary
  sky the same, fainter). Looking up, the whole page is that sky down to the land's band at
  the foot, so behind the cards the ground is lilac (see the gates); the moon with a pale halo; slate
  land where it meets the sky, giving way to the paper down the page under the cards; mist
  paler than the land and nearly its colour (not blue puddles); the river mostly lost in mist.
- **Motion** — clouds drift ±8–65 pt over 40–55 minutes, valley mist breathes ±16 pt and the
  pooled mist ±7 pt over 4–8 minutes, stars twinkle, fireflies blink, a few leaves or petals
  fall, one shooting star every 140 s. `motion=0`: all of it still, no band, and there is no
  move — the looked-up still cross-fades in at bedtime (and at a re-settle) and out at waking,
  on the same curves.
- **Tilt** — six planes: sky −1.2 pt, far 1, mid 2, knoll 3, near 5, fore 8 (x; less in y).

## Gates

`node tools/measure.mjs --sky hill-painted --jobs 2` → `hill-painted: PASS` (0 FAIL, 0
AT-LIMIT, 48/48 frames); with `--asleep night --times 19:40,21:00,03:00` — **which now
measures the looked-up pose with the cards on** — → `hill-painted: PASS` (0 FAIL, 0 AT-LIMIT,
18/18); the looked-up star count (`… --times 19:40,03:00 --param look=1 --param veil=1
--stars-by-age`) → PASS, "144 of 142" on all three displays in both appearances.
Closest to a limit, at rest (unchanged): the light grey line on the slab (3.26 : 1, L 0.605,
limit 3 : 1 / 0.55); the dark grey line by day (0.043, limit 0.072; 3.95 : 1 on the cover at
09:30); the dark night ground at 03:00 at rest (0.0100 against a card's 0.0117; "AT-LIMIT"
begins at 0.0111); the dark name on the slab at dawn (9.12 : 1, limit 7). Looking up: the
light grey line on the slab 3.28 : 1 (L 0.609); the dark night ground **as an area** 0.0090
at 03:00 (cover; 0.0081 at 19:40 and 21:00 — it is the air round tonight's star and the
horizon's band). The *strict* figure of that check, the lightest single 8 pt block, is now
0.047 on the Duo and is tonight's star itself in its window (it was 0.009 when the star was
small and beside the tree): a point, not an area — the tool counts it as one block over a
card and passes it — but it is the brightest thing below the band at 3 AM and should be
looked at on an OLED in a dark room. The light page's ground looking up: median 0.657–0.663
(0.648–0.678 at rest in round two). The tool's unjudged line "sun and moon against the
state's x" now reads mean 69 pt, largest 89 pt for the night frames: the camera's turn. A
feathered limiter sits under each line of header text (`darken` / `lighten`; it does nothing
unless the sky there is past the limit).

## Cost (headless Chromium, software raster, dpr 2, canvas forced to rasterise)

| | cover | spread | slab |
|---|---|---|---|
| first `render()` (textures, tree, clouds, every plane) | 0.64–0.71 s | 1.20–1.41 s | 0.55–0.60 s |
| …before this pass, as its report gave it | 0.70–0.73 s | 1.35–1.57 s | 0.54–0.79 s |
| steady frame at night (only `t` moves), median / p90 | 3.9 / 4.4 ms | 7.4 / 8.1 ms | 3.6 / 6.1 ms |
| a held bedtime frame, compose only | 5.8 ms | 7.1 ms | 4.4 ms |

Round three (the same machine, with two other jobs shooting on it — read these as "the same
order", not as a comparison): first `render()` 0.71 s cover, 1.40 s spread, 0.53 s slab; a
steady frame of the looked-up night with every pixel forced to rasterise, 5.9 / 10.1 / 5.4 ms
(median; its `compose()` is under a millisecond of canvas calls); a held bedtime frame with
the band, 11.8 ms cover and 23 ms spread, rasterised. Nothing new is painted for the night's
pose; the band is one more quarter-size gradient, as before. The tone's steps were halved
(presence 1/120, the dimmed room 1/60), so a slow settling repaints the planes twice as often
*in a held frame or a film*; while an event plays live they are still not repainted at all.

Of the spread's planes the river is ≈ 0.04 s (it is skipped where the display never sees
it); it also leaves one small layer (its own shape and a run of mist puffs along its course)
for the opening's light. The clouds' masks are cut once per light direction (0.09 s cover,
0.18 s spread for all of them). The bedtime band is drawn at a quarter of the size and
enlarged (it has no detail). The move itself was not re-timed in this pass. During an event
the planes are not repainted: the camera translates them, and the change of tone is one
brightness/saturation adjustment over the painted layers; they are painted exactly again
when the tone has been still for a third of a second.

## SwiftUI port

1. **Air** — `air.js` is pure: ~250 lines of Swift giving `skyAt`, `hazeAt`, `mistAt`. Free.
2. **Sky** — the only per-pixel layer. Either a small `colorEffect` shader (two ramp
   lookups, the arch, the sun's glow, dither, and the night band kept under the dimmed room)
   or a `CGImage` filled off the main thread once a minute from the same 2-pt grid.
3. **Stars** — `Canvas`, two symbols (and one soft patch in the light appearance), ≤ 368 of
   his + ≤ 460 ordinary on the spread, `TimelineView` at 10 fps, night only.
4. **Sun, moon, tonight's star, the band** — `Canvas` paths and a few radial gradients (the
   band is one `RadialGradient` with eleven stops under a vertical `LinearGradient` mask that
   ends it above the horizon; drawn small and enlarged).
5. **Clouds** — seven small images, each with body / lit / shade / underside / lit-edge /
   far-side masks pre-rendered for a dozen light directions, tinted.
6. **Land** — five `Canvas` layers repainted once a minute and kept as images
   (`drawingGroup`): per shape a `Path` filled with a horizontal `LinearGradient` (a stop
   every 30 pt), blurred stroked paths for the flank's turn (one 210-pt stroke of shade, one
   of light), shade / light / frost drawn into a quarter-size `drawLayer`, the rim as a
   stroked path through a dry-brush image mask. The camera is an `.offset` per layer.
7. **River** — its two banks are a `Path` computed once (the projection is twenty lines);
   the fill is a vertical gradient through that path drawn eight times at slightly different
   scales about its vanishing point (the feather), then gradients, some forty soft ellipses
   (reflections, streaks, glints, mist) clipped to it, and ~80 short strokes for the reeds.
   Pre-rendering it per minute as part of the far plane is the honest plan; the opening's
   light is that same shape plus mist puffs as one alpha image, tinted and wiped by a
   gradient mask for a second.
8. **Tree** — masks pre-rendered by `tree.js` (wood, twigs, three leaf depths, blossom ×2,
   snow, frost, last leaves) at three sizes, tinted; its lit edge is a mask minus itself slid.
9. **Mist** — four level bands on the valley side (one texture, a gradient tint) and three
   pooled layers on the hill side (an alpha mask each, pre-rendered: they depend only on the
   crest in front), each with an `.offset` that breathes.
10. **Tone during events** — `.brightness` / `.saturation` on the layers. **Caption** — `Text`.
11. **The looked-up view is a state, not an animation.** `look` is derived from "a night
    sleep is running" (the app's own definition: BRIEF.md, round three — an evening sleep), so
    it **persists across launches**: Home opened cold at 3 AM is already looking up, with no
    move. Only three things animate it: a night sleep started *by hand on this phone* (the
    full moment, once a night), a re-settle by hand the same night (2.5 s, behind the cards,
    nothing else), and the night sleep ending from any source (3 s down, behind the cards; or
    no move at all if Taylor prefers the alternative). A sleep that begins any other way
    snaps to the state on the next appearance. On the open Duo the phone page's sky view and
    the leading page's are two views with two clocks: **one shared driver** (an observable
    `look`, or one `TimelineView` date passed to both) must feed both, or the horizon breaks at
    the fold during the move. Under Reduce Motion the driver is an opacity between the two
    stills, on the same curve.
12. **Tonight's star** is not on any plane: its place is `lerp(rest home, window home, look)`
    in the display's own points (the window home comes from the strip's safe-area geometry on
    the Duo and the header's on the slab — the lab reads `state.layout`). The band's centre is
    the window home, constant. The first night's star is one more hand-set place.
13. **Which sleep ended** — the port must tell the sky whether the sleep that ended was the
    night's (the view comes down) or a nap's (nothing moves); the lab guesses by the hour.

**Riskiest:** still the land painter — ~45 blurred strokes clipped to their shapes and washes
laid small and enlarged; that has to be re-proved in `Canvas` on a phone. Second: the tone
adjustment is an approximation of the OKLab hush, so the exact repaint that follows an event
may show as a small step — I have only seen stills.

## Still not good enough

Most serious first. Items 1–7 are this pass's (the night stays up); the rest stand from round
two and belong to the drawing passes of this round, which may have answered them.

1. **With the cards on, the night is two stars and their company — not a place.** That is a
   decision (see "The tree is not seen…"), and on the Duo the strip's window is a good small
   picture; but the land, the tree and the moon — everything that makes this sky *this* sky —
   are behind the cards from bedtime to waking, except the moon when it happens to cross a
   gap. In the dark appearance nothing of the land shows at all. The slab's night is one star
   beside his name.
2. **The moon is hidden most of the night, looking up, with the cards on** (behind the Today
   card while it is high; behind the sleep card as it sets through the tree at 03:00 — the
   loveliest thing in the bare frame and nobody sees it). Remapping its height for the
   looked-up pose so that it crosses the strip's window would fix it and is not done: it
   would break "one place in the world" and the bare frame.
3. **The band is still an arc.** Softer (no edge, no small circle at the start, lower), and
   it reads as a swell rather than a drawn line; a wavefront from a point is still part of a
   circle, and in the light appearance it is a pale ring on a lilac page.
4. **Tone still moves after the view is up**: the bloom and the dimming room go on settling
   for seconds after "nothing moves". In the films this shows as steps of about a third of a
   level a few times a second (the lab's exact frames are tone-quantised); on a phone it is a
   continuous `.brightness`. Judged from stepped films only — not at a phone's frame rate.
5. **Light appearance, looking up**: the whole page behind the cards is lilac sky (ground
   median ≈ 0.63–0.66 luminance against a page's 0.89; white cards read well on it, but it is
   not "close to the page"). The light-page stars are now glints and points and no longer
   snow, but the glints are one sprite at several sizes — a little mechanical at 3×. The
   tree's ghost through the lab's glass shows sharp twigs at the sleep card's right edge.
6. **The leading page at night, looking up**, is the ordinary sky over a dark low valley:
   calm, and the opening's stars-from-the-fold is slight. Its margin column — the best window
   on the device — shows a dozen faint stars and nothing else.
7. **Rest at night has fewer of his stars in view than round two** (cover 61, was 71; in the
   open with the cards on 41, was 47; slab 29, was 33), and every star's place has changed
   from round two's (the sky is laid out anew). A sky that fills over a year is dense by July
   (368): tonight's star keeps its 30 pt of dark, but its window holds twenty-seven others.
8. **July bedtime**: the dark sky at +7° is a lighter slate, so his stars are faint in it;
   seven clouds in view looking up before dark is two or three too many (clouds: not this pass).
9. **Clouds** are small, soft-bodied things. **The crowns in leaf** are a flatter hand than the
   bare tree's pen work. **Mist pools**: the one behind the fore hill is a level-topped patch.
10. **The river's near bank** has a pinched waist; the reeds are tiny at phone size; the
   "moon's broken path" is a convention, not geometry.
11. **Light appearance**: the land at midday is close to one value; the river at night is
   nearly gone (on purpose).
12. **Slab.** The sun never shows through the limbs at the signature hour (it sets behind the
   gear button); no cloud at rest.
13. **Faint axis-aligned edges (~1 level) in the dark-night land** at 6× brightening; cause
   not found. Needs an OLED in a dark room. So does the whole dark night: the star's glow
   (its one 8 pt block reads 0.047 luminance; the area around it 0.008–0.009 against a card's
   0.0117) was sized by the ruler, not by an eye in a dark room.
14. **The mist's breathing steps a quarter of a point at a time**; at dawn, where the mist is
   bright on a dark land, a step shows in a film as a one-frame shimmer along the horizon
   (0.3 % of the pixels) — the wake film has one at 0.33 s.
15. **Dark by day** was judged from stills only. `close` does nothing of its own. The
   earth-shadow at 16:40 is slate, not teal; the brown band behind the tree at 17:30 in dark
   is as it was.

## Lab notes

- `look=` is not a viewer parameter; the module reads `location.search` (as the brief
  asks). `--param look=1` works with `shoot.mjs` and `measure.mjs`.
- `measure.mjs --stars-by-age` counts the caption's changed digits as stars when the veil
  is up (144 of 142). Its light-appearance "bright / dark" point detector is approximate: on
  the slab it finds 136–138 bright points where the by-age count finds all of them.
- The viewer sets `state.frozen` on a held frame; the module draws those exactly (no
  tone adjustment over old paint).
- `event=resettle` is new (lab/core.js lists it, lab/presence.js dims the room again over 4 s
  and gives it no bloom, README; `tools/film.mjs --event resettle`, review set `resettle`).
- `tools/review.mjs` `bedtime` frames are now t0, t0_7, t1_6, t3, **t4_4**, **t5_8**, t9, t40
  (the cards return 4.8–6.8 s; round two's t5 and t6_5 have no counterpart) and `wake` has
  t2_5 as well. `asleep/` and `open/night/` are now the looked-up pose.
- The lab's `wake` does not say which sleep ended (see Waking).
- The disc detector takes a moon crossed by branches, or a soft-haloed star, for an
  "unknown blob" and leaves it in the ground; the star's glow here is small partly for that.
- `window.__hillPainted.timing` carries per-part timings (`geometry`, `sky`, `land`, `river`,
  `clouds`, `tree`, `treeMasks`); add `hpTiming=1` to the URL to make each frame rasterise.
