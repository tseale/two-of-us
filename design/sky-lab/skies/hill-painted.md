# Hill, painted

`skies/hill-painted.js` (+ `skies/hill-painted/air.js`, `tree.js`) · shots in
`shots/hill-painted/review/` (`node tools/review.mjs --sky hill-painted --jobs 2`)

## The idea

Picture book's place, painted with True light's air — the painting first.
One illustrated land: a river valley on the leading page, a few big overlapping hills, a
knoll, and one grown tree against the setting sun in the strip. Every shape is a crest line
set by hand and filled with paint; what is new is where the paint comes from. The sky is
True light's twilight table (kept almost stop for stop, printed light and dark), each plane
of land takes its colour from the horizon sky behind it at every x, mist lies level between
the planes, the shoulder that faces the sun carries a glaze and a thin dry rim of its light,
the far side a cool shade, and the clouds are a few strokes of a flat brush lit along the
edge that faces the sun. At bedtime the camera looks up: the land sinks to the foot of the
display and every night of his life is on screen at once.

No shader. Everything is 2-D canvas: one tall sky plane, five planes of land, sprites.

## Composition and camera

One world, in points, x = 0 at the anchor window's leading edge. Two poses; every plane
only translates between them.

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
- **The spread's phone page is the cover's picture**, both poses: compared pixel for pixel
  (bare, dark and light, 16:10 / 21:00 / looking up) the largest difference anywhere is 3
  levels, the mean 0.005–0.06. Planes, gradients' knots, grass, dither and grain are all laid
  on a world grid for that.
- **The strip** (cover x 362–466) shows, top to bottom: the brush cloud, the twilight's
  bands, the tree with the sun setting behind and just right of the trunk (sun x 435 at
  +1.7°, 25 pt up; it sets at x 447), the knoll's lit rim, a band of mist, the near hill.
- **The river** (spread only) rises at display (242, 302) on the valley floor, winds
  toward the viewer through the leading page and runs down the **leading margin column**
  from y ≈ 466 to the foot (centre x 23–81 there). It mirrors the sky above each reach —
  the bright low sky far away, the higher sky near — so it is the lightest thing in the land.
- **Sun and moon** keep the baseline's clock and x (`state.sun.x`, `state.moon.x`) and have
  one place in the world: height = Emax·(1 − e^(−alt/45°)) + 12·(1 − e^(−alt/2.5°)) points
  over the horizon (Emax 500 Duo, 620 slab). A high moon or sun is therefore above the top
  of the everyday view and **comes down into view with the sky** when the camera looks up.
  Neither is ever drawn in the header band (Duo) or behind the status bar (slab): a body
  crossing it is out of sight until it is clear. The moon's track is **not** extended onto
  the leading page (it would change where the cover's moon is); the river carries the light.
- **Under the cards** the picture is the near hills and mist only: broad, soft, low contrast.

## How each requirement is met

- **Bloom / hush** — the table is written at full strength; `air.show()` applies the lab's
  hush with `presence(state)` (dark: 12 % deeper, two fifths of the chroma; light: toward
  the page by day, only greyed at night so a pastel night is not paler than its bloom) and
  the dimmed room (`depth`). Above 15° the palette does not change.
- **Light and dark** — two prints of one table. Dark's golden hour has its own column
  (gold → apricot → rose → blue, no mustard); the dusk land is aubergine, not black; at
  night the land is capped under a card's luminance. Light gets a painted apricot sun (a
  disc deeper than its glow) and a slate land a step under the sky at night.
- **His stars** — `nights(ageDays, { tonightLit })`, mapped over the whole looked-up sky and
  kept clear of the header, the strip's furniture, the capsule, the land, the tree's crown
  and each other. Counted (age 142, tonight's lit): **at rest** 79 in the view on the cover
  and on the spread's phone page (50 in the open with the cards on: 30 in the top band, 13
  in the strip's clear window — 7 while a sleep runs), 38 on the slab, all in the header
  band; **looking up** 143 on all three. `tools/measure.mjs --stars-by-age --param look=1
  --param veil=1` says "144 of 142": 142 nights, plus the two digits of the caption that
  differ from "Night 1" (tonight's star is the same at both ages and cancels). The leading
  page carries a fainter ordinary sky that is nobody's.
- **Tonight's star** — a hair-thin four-point spark with a small warm breath, above the
  tree's left shoulder, drawn over everything, travelling with the tree. Lit when
  `state.tonightLit`; on `wake` it cools over four seconds.
- **Seasons** — the tree: bare limbs with a few last leaves and frost (now), snow lying
  along the limbs, blossom, a full crown in lobes with fireflies from dusk, amber and
  thinning with leaves on the ground; the land: frost or snow laid along the shoulders,
  green or straw underneath; snowfall as slow flakes at three depths.
- **Bedtime** — `look` follows the event (0 until 0.3 s, up by 2.4 s, held to 5.3 s, down by
  7.5 s; `look=` in the URL holds any pose). The star ignites; from 1.9 s a soft ring leaves
  it at 250 pt/s and each star swells as it passes and keeps a fifth more light. "✦ Night
  143" stands at the foot left, away from the tree, from 2.2 to 5.6 s. In November the moon
  has come down into the upper left of the frame. In July the tree stands against the low
  sun and his stars show only where the ring has just passed.
- **Opening the Duo** — the valley is already there; the one thing that happens is the
  mist on the river brightening from the fold outward (≈ 400 pt/s) and settling.
- **Light appearance at night** — lilac-slate sky graded to the horizon, each star a clean
  white point on a small patch of deeper sky, the moon with a pale halo, slate land with
  paler mist.
- **Motion** — clouds drift ±30–65 pt over 40–55 minutes, mist bands breathe ±16 pt over
  4–8 minutes, stars twinkle, fireflies blink, a few leaves or petals fall, one shooting
  star every 140 s. `motion=0`: all of it still, no ring, and the looked-up still
  cross-fades instead of moving.
- **Tilt** — six planes: sky −1.2 pt, far 1, mid 2, knoll 3, near 5, fore 8 (x; less in y).

## Gates

`node tools/measure.mjs --sky hill-painted --jobs 2` → `hill-painted: PASS` (0 FAIL, 0
AT-LIMIT, 48/48 frames); with `--asleep night --times 19:40,21:00,03:00` → `hill-painted:
PASS` (0 FAIL, 0 AT-LIMIT, 18/18). Closest to a limit: the light grey line on the slab
(3.27 : 1, L 0.607, limit 3 : 1 / 0.55); the dark night ground on the cover at 17:30
(0.0096 against a card's 0.0117); the dark name on the slab at dawn (8.95 : 1, limit 7).
A feathered limiter sits under each line of header text (`darken` / `lighten`, so it does
nothing unless the sky there is past the limit).

## Cost (headless Chromium, software raster, dpr 2, canvas forced to rasterise)

| | cover | spread | slab |
|---|---|---|---|
| first `render()` (textures, tree, every plane) | 0.5–0.7 s | 1.0–1.1 s | 0.5 s |
| steady frame (only `t` moves), median / p90 | 6–7 / 12–13 ms | 9–11 / 16–21 ms | 4–5 / 11–12 ms |
| a frame during the bedtime move | 34 ms | 59 ms | 36 ms |
| a new minute (sky + five planes repainted) | 0.39 s | 0.8 s | 0.42 s |

During an event the planes are not repainted: the camera translates them, and the change
of tone (bloom, dimmed room) is one brightness/saturation adjustment over the painted
layers; they are painted exactly again when the tone has been still for a third of a second.

## SwiftUI port

1. **Air** — `air.js` is pure: ~250 lines of Swift giving `skyAt`, `hazeAt`, `mistAt`. Free.
2. **Sky** — the only per-pixel layer. Either a small `colorEffect` shader (two ramp
   lookups, the arch, the sun's glow, dither — the one Metal shader) or a `CGImage` filled
   off the main thread once a minute from the same 2-pt grid. One tall image, translated.
3. **Stars** — `Canvas`, two symbols, ≤ 368 + ~250 draws, `TimelineView` at 10 fps, night only.
4. **Sun, moon, tonight's star, ring** — `Canvas` paths and a few radial gradients.
5. **Clouds** — seven small images, each with body / lit / shade masks pre-rendered for a
   dozen light directions, tinted.
6. **Land** — five `Canvas` layers repainted once a minute and kept as images
   (`drawingGroup`): per shape a `Path` filled with a horizontal `LinearGradient` (a stop
   every 30 pt), blurred stroked paths for shade / light / frost drawn into a quarter-size
   `drawLayer`, the rim as a stroked path through a dry-brush image mask. The camera is an
   `.offset` per layer driven by one animated value.
7. **Tree** — masks pre-rendered by `tree.js` (wood, twigs, three leaf depths, blossom,
   snow, frost, last leaves) at three sizes, tinted; its lit edge is a mask minus itself slid.
8. **Mist** — nine bands: one texture, a gradient tint, an `.offset` that breathes.
9. **Tone during events** — `.brightness` / `.saturation` on the layers. **Caption** — `Text`.

**Riskiest:** the land painter. Its look rests on ~40 blurred strokes clipped to their
shapes (`sourceAtop`) and on the washes being laid small and enlarged; that has to be
re-proved in `Canvas` on a phone, and its once-a-minute cost there is unknown. Second:
the tone adjustment is an approximation of the OKLab hush, so the exact repaint that
follows an event may show as a small step — I have only seen stills.

## Still not good enough

1. **Night at rest, cards on, is quiet.** Stars in the band and the strip, the tree's
   silhouette, a nearly black land. The moon is above the frame for most of the night
   (that is what lets it come down at bedtime) and the valley and river all but vanish
   under the "nothing lighter than a card" limit.
2. **The light appearance is sweet and shallow.** Pink, peach and lilac at the bloom over a
   pale mauve land; depth reads far less than in the dark print. Its bedtime ring is a slate line.
3. **Flatness between the knoll and the foreground.** The big near shapes are smooth
   expanses; mist and the rim carry the depth, and in the bare spread the two mist bands
   by the knoll can read as stripes.
4. **Clouds are one family** — level strokes. Better than loaves, still modest; the one
   beside his name is a smudge at phone size; among July's bedtime stars they read as streaks.
5. **The tree in leaf.** The bare tree is the drawing I would stand behind. The summer,
   autumn and blossom crowns are dabs gathered into lobes: a clear silhouette at 55 pt, but
   lumpy at 3×. Snow on the limbs is a little like icing.
6. **Slab.** The sun sets behind the gear button (the baseline's x); the moon is never
   seen at rest; at a year old 98 stars crowd the header band.
7. **Motion was never watched.** Ring speed and softness, the camera's easing, the mist's
   breathing and the opening's sweep were judged from stills.
8. **Hushed midday in dark** is a slate field with a faint tree: correct, plain.
9. At rest his stars start 83 pt in from the anchor window's leading edge (the price of the turn).
10. `close` does nothing of its own; `wake` only cools tonight's star.

## Lab notes

- `look=` is not a viewer parameter; the module reads `location.search` (as the brief
  asks). `--param look=1` works with `shoot.mjs` and `measure.mjs`.
- `measure.mjs --stars-by-age` counts the caption's changed digits as stars when the veil
  is up (144 of 142).
- `state.t` is always finite, so a module cannot tell a frozen frame from a playing one;
  this one infers "playing" from the cadence of `render()` calls. A `state.frozen` would be cleaner.
- The disc detector takes a moon crossed by branches, or a soft-haloed star, for an
  "unknown blob" and leaves it in the ground; the star's halo here is small partly for that.
