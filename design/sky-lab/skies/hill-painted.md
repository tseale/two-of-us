# Hill, painted

`skies/hill-painted.js` (+ `skies/hill-painted/air.js`, `tree.js`) · shots in
`shots/hill-painted/review/` (`node tools/review.mjs --sky hill-painted --jobs 2`;
`review/CODE.md5` names the code they were shot from) · the pictures before the
director's finishing pass are frozen in `shots/hill-painted/review-r2a/`. This text is as of
the pass that answered the critic's report on that finishing pass (ranked list at the end).

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
a shadowed one. At bedtime the camera looks up: the land sinks to the foot of the display and
every night of his life is on screen at once.

No shader. Everything is 2-D canvas: one tall sky plane, five planes of land, sprites.

## Composition and camera

One world, in points, x = 0 at the anchor window's leading edge. Two poses; every plane
only translates between them. (Unchanged, with one exception on the slab: the big hill's right
shoulder now carries on past the end of the age line before it falls to the knoll — its crest
ran through "…s old". Horizons, the turn and the tree's places are as they were.)

| | Duo (cover and spread) | slab iPhone |
|---|---|---|
| horizon at rest | y 292 | y 140 (the header is a small landscape) |
| horizon looking up | y 604 (lowered 312) | y 770 (lowered 630), just above the capsule |
| the turn | the far world slides 78 pt left | 30 pt left |
| tree at rest | x 408 on the knoll, 88 pt tall, crown x 368–448, top y 213 | x 286, 62 pt tall, between his name and the gear |
| tree looking up | x 330, foot y 609 — clear of the tab capsule (x 392–456) | x 256, foot y 762 |
| tonight's star | (379, 194) at rest, in the strip's clear window even with a sleep running; (301, 506) looking up | (262, 66) → (232, 696) |

- **Planes and parallax.** Sky, far ridges + valley floor + river, the mid hill, the knoll
  with the tree: these move as one (sink ×1, slide ×1), so the tree keeps its place against
  the sky and tonight's star stays above its shoulder. The two near planes sink ×1.12 and
  ×1.3 and slide ×1.1 and ×1.25: near land leaves faster. Nothing is repainted for the move.
- **The spread's phone page is the cover's picture**, both poses. `measure.mjs`: 11 of 16
  pairs identical to within 2 levels, the largest mean difference 0.06 levels, no point more
  than 8 apart. Planes, gradients' knots, grass, mist pools, dither and grain are all laid on
  a world grid for that.
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
  every device). Their places are gathered a little — a slow smooth drift of the whole
  field — into loose knots with open sky between, and a place that is taken is *cast again*
  somewhere else in the sky (the nearest free place lined stars up along the keep-outs'
  edges: the dotted row in the old held frame). A real range of size and light: most are
  small and faint, a few are bright and carry a small glow. Counted (age 142, tonight's lit)
  by the module's own census (`window.__hillPainted.stars`, which lists every place): **at
  rest** 71 on the cover and on the spread's phone page (47 in the open with the cards on),
  33 on the slab; **looking up** 143 on all three, none inside the name, age, avatar, gear,
  island/clock column or capsule. `tools/measure.mjs --stars-by-age --param look=1 --param
  veil=1` says "144 of 142" on all three devices in both appearances: 142 nights, plus the
  two digits of the caption that differ from "Night 1" (tonight's star cancels).
- **The leading page's ordinary sky** — nobody's stars, on the whole tall sky: about as
  dense as his at the fold (so that, looking up, there is no boundary at the anchor window's
  edge), thinning and dimming to the far left, in three tints, fainter and smaller than his,
  answering the ring as it passes. Their number follows his (80–460): a newborn's sky is not
  upstaged by the page beside it.
- **Tonight's star** — a hair-thin four-point spark with a small warm glow, above the tree's
  left shoulder, drawn over everything, travelling with the tree. Lit when
  `state.tonightLit`; kept small while the sun is still up (a July bedtime). **Waking
  reverses bedtime** only this far: at the instant he wakes the room is still dimmed as it
  was while he slept, it un-dims over five seconds, and the star cools and goes out.
- **Night at rest** — the night's horizon light is a band as tall as the tree's crown, kept
  under the dimmed room; just behind the crown it stands a touch higher (to luminance ≈ 0.010,
  less when the moon is up) and lets go within the strip; each plane of land has its own
  value; under a moon the knoll carries a thin cool rim. It is still quiet — by the limits.
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
- **Bedtime** — `look` follows the event (0 until 0.3 s, up by 2.4 s, held to 5.3 s, down by
  7.5 s; `look=` in the URL holds any pose). The star ignites; from 1.9 s **one soft band of
  light** leaves it at 250 pt/s — a radial gradient, never a stroked circle: feathered on both
  sides, brightest at its leading edge with a *short* trail (the sky inside the arc is not
  left lighter than the sky outside: no dome), peak alpha 0.11 (dark, additive) / 0.36
  (light), fading from 30 % of the way; it is light in the sky only — it lets go between 150
  and 22 pt above the horizon, so its foot never stands on the land (on the slab it is no
  longer a rainbow over the tree). Each star swells as it passes and keeps a fifth more
  light. "✦ Night 143" stands at the foot left from 2.2 to 5.6 s. In November the moon has
  come down into the upper left of the frame with a fuller halo (only while the camera is up
  and the moon is high: at rest it is as quiet as before). In July the sun (+7°) stands in a
  wide warm column of its own light beside the crown, the far side of the sky is cool rose
  over blue, and his stars, shown by the band, keep a faint presence behind it while the
  camera is up.
- **Opening the Duo** — the valley is already there; the one thing that happens in the bare
  second is **light running down the river toward you**: a crest leaves the furthest bend at
  0.1 s and is at the foot of the page by 0.9 s, slow among the far bends and quick through the
  near reach. The water itself and the mist lying along the river's own course take it as it
  passes, keep half of it while the cards land (0.9–1.9 s in the film), and let it go by
  ≈ 4.4 s. Light added in the dark appearance; a warm pass over pale mist on the light page;
  held to a breath at night. (Watching the first film showed the earlier version — a front
  crossing the page sideways from the fold — was too faint and mostly hidden by the landing
  cards; it was replaced after that.)
- **Light appearance at night** — lilac-slate sky graded to the horizon; each star a clean
  white point on a soft, edgeless patch of slightly deeper sky, the faint ones small with
  hardly any patch (en masse they read as falling snow); the moon with a pale halo; slate
  land where it meets the sky, giving way to the paper down the page under the cards; mist
  paler than the land and nearly its colour (not blue puddles); the river mostly lost in mist.
- **Motion** — clouds drift ±8–65 pt over 40–55 minutes, valley mist breathes ±16 pt and the
  pooled mist ±7 pt over 4–8 minutes, stars twinkle, fireflies blink, a few leaves or petals
  fall, one shooting star every 140 s. `motion=0`: all of it still, no band, and the
  looked-up still cross-fades instead of moving.
- **Tilt** — six planes: sky −1.2 pt, far 1, mid 2, knoll 3, near 5, fore 8 (x; less in y).

## Gates

`node tools/measure.mjs --sky hill-painted --jobs 2` → `hill-painted: PASS` (0 FAIL, 0
AT-LIMIT, 48/48 frames); with `--asleep night --times 19:40,21:00,03:00` → `hill-painted:
PASS` (0 FAIL, 0 AT-LIMIT, 18/18). Outputs kept in `shots/hill-painted/measure*.txt`.
Closest to a limit: the light grey line on the slab (3.26 : 1, L 0.605, limit 3 : 1 / 0.55);
**the dark grey line by day, new** — the slate day sky stands behind it at luminance 0.043
(limit 0.072), 3.95 : 1 on the cover at 09:30 (limit 3 : 1; it was 4.5 : 1 or better on a
near-black sky); the dark night ground at 03:00 (0.0100 against a card's 0.0117; "AT-LIMIT"
begins at 0.0111 — the lift behind the crown is sized to stay clear of it, which is why it
is small); the dark name on the slab at dawn (9.12 : 1, limit 7). A feathered limiter sits
under each line of header text (`darken` / `lighten`; it does nothing unless the sky there is
past the limit — the dark day sky is kept a step under its cap so no patch shows).

## Cost (headless Chromium, software raster, dpr 2, canvas forced to rasterise)

| | cover | spread | slab |
|---|---|---|---|
| first `render()` (textures, tree, clouds, every plane) | 0.64–0.71 s | 1.20–1.41 s | 0.55–0.60 s |
| …before this pass, as its report gave it | 0.70–0.73 s | 1.35–1.57 s | 0.54–0.79 s |
| steady frame at night (only `t` moves), median / p90 | 3.9 / 4.4 ms | 7.4 / 8.1 ms | 3.6 / 6.1 ms |
| a held bedtime frame, compose only | 5.8 ms | 7.1 ms | 4.4 ms |

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

**Riskiest:** still the land painter — ~45 blurred strokes clipped to their shapes and washes
laid small and enlarged; that has to be re-proved in `Canvas` on a phone. Second: the tone
adjustment is an approximation of the OKLab hush, so the exact repaint that follows an event
may show as a small step — I have only seen stills.

## Still not good enough

Most serious first. (What the critic's report asked for and what became of it is in the
pass's report; this is what I would still not sign.)

1. **Night at rest in the dark appearance is still very quiet with the cards on.** The lift
   behind the crown, the separate planes and the moon's rim are there and measurable; side by
   side with the frame before, at phone size, the strip is nearly the same picture. The limit
   (nothing lighter than a card; "at the limit" from 0.0111) leaves about two levels of room.
2. **The band at bedtime is still an arc.** Shorter trail, no foot on the horizon, gone by
   5 s — a wavefront from a point is a circle, and the held 3 s still shows a faint arch.
   The move has since been filmed (tools/film.mjs, stepped frame by frame): no frame jumps
   beyond the slow tone steps, but it has not been seen at a phone's own frame rate.
3. **The leading page at night with the cards on** is stars over a black land; the river in
   the margin column is the faint held line. Looking up, it is the ordinary sky and a low
   band of land — calm, not a picture of its own.
4. **July bedtime** is better (the sun reads as a sun in its own light; rose over blue on the
   far side) but the dark sky at +7° is now a lighter slate, so his stars are fainter in it
   than they were in the old navy; and a year of nights (368) is a dense field. The light
   version is still pale.
5. **Clouds** are designed forms with a lit edge now, and the frieze has one large enough to
   see — but they are still small, soft-bodied things, and looking up before dark there are
   seven of them in view at once, which is two or three too many.
6. **The crowns in leaf** are fewer, larger, leaf-edged masses with the sunset bay open — and
   still a different, flatter hand than the bare tree's pen work (three flat tones per mass).
7. **Mist pools** are softer and ragged-ended and glow under the low sun; the one behind the
   fore hill is still a level-topped patch placed by hand.
8. **The river's near bank** has a pinched waist where the bar of land comes out; the reeds
   are tiny at phone size (they read at 2×); the "moon's broken path" is a convention, not
   geometry, and in the dark appearance it is only just there.
9. **Light appearance**: the land at midday is still close to one value; the night is pale by
   the limits' design; the river at night there is nearly gone (on purpose).
10. **Slab.** The sun never shows through the limbs at the signature hour — it sets behind
   the gear button (the baseline's x), so there it is now only its glow; no cloud at rest;
   his stars are bottom-heavy looking up; at rest fewer of his stars are in view than before
   (33, was 38; Duo 71, was 79) — the price of the looser field.
11. **Faint axis-aligned edges (~1 level) in the dark-night land** at 6× brightening are
   still there; I did not find their cause. Needs an OLED in a dark room.
12. **Waking** only un-dims the room and puts the star out; there is no gesture.
13. **Dark by day is new and was judged from stills only**: whether a slate sky a step
   lighter than the cards is right behind a whole day of dark-mode use needs a phone.
14. `close` does nothing of its own. The earth-shadow at 16:40 is slate now, not teal; the
   brown band behind the tree at 17:30 in dark is as it was.

## Lab notes

- `look=` is not a viewer parameter; the module reads `location.search` (as the brief
  asks). `--param look=1` works with `shoot.mjs` and `measure.mjs`.
- `measure.mjs --stars-by-age` counts the caption's changed digits as stars when the veil
  is up (144 of 142). Its light-appearance "bright / dark" point detector is approximate: on
  the slab it finds 136–138 bright points where the by-age count finds all of them.
- `state.t` is always finite, so a module cannot tell a frozen frame from a playing one;
  this one infers "playing" from the cadence of `render()` calls. A `state.frozen` would be cleaner.
- The disc detector takes a moon crossed by branches, or a soft-haloed star, for an
  "unknown blob" and leaves it in the ground; the star's glow here is small partly for that.
- `window.__hillPainted.timing` carries per-part timings (`geometry`, `sky`, `land`, `river`,
  `clouds`, `tree`, `treeMasks`); add `hpTiming=1` to the URL to make each frame rasterise.
