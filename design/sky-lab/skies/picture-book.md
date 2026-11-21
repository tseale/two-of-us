# Picture book

`skies/picture-book.js` — a page from the book you will read him.

## The idea

Home's ground is one gouache picture-book spread that happens to tell the real time: a sky
laid in dry-brushed bands, six rounded hills overlapping like cut-outs, two or three painted
clouds, a sun that is a soft disc in a painted halo, the moon in its true phase, and **one
tree on a knoll** that carries the seasons. There is one lamp (the sun, then the moon):
every hill has a lit shoulder and a shaded one, clouds are lit on that side, and the whole
palette is re-mixed in OKLab from the sun's altitude — luminous pastel in the light
appearance, ember, plum and ink in the dark one — then quietened by `presence()`. His stars
are hand-set dots, with four-point ones for the first night and the month-birthdays, exactly
one per night; tonight's is lit beside the tree.

Best frame: `shots/picture-book/review/bedtime/july/t3/cover-dark-1940-night.png`.
Weakest: `shots/picture-book/review/bedtime/november/t3/iphone-dark-1940-night.png`.

## Composition

**Duo.** The horizon is at **y = 292 pt on both cover and spread** (0.43 of the cover; the
spread only loses 9 pt at the foot), so opening the Duo widens the picture and moves nothing.
292 is the middle of the strip's clear window (y 158–396): the window shows the whole stack
— sky bands, far ridge, the next hill, the knoll, near land — and the sun's last hour and
the moonset happen in it. The gap under the hero card lies on the same line, so the spread's
three slits (margin, gutter, strip) show one horizon.

- **The strip column is the stage.** The tree stands at x 399 on its knoll (crown x 371–427,
  clear of the cards' edge at 362); the sun sets at x 447, just to its right, behind the far
  ridge; the moon sets through the same window; tonight's star is lit at (441, 211), above
  the tree's shoulder and below the status icons even with a sleep running.
  *I put the tree here rather than in the spread's leading margin, as the notes suggest:*
  the cover is the everyday window and the tree is what tells the season, so it has to be
  on it. The leading margin gets a rounded hill and a cloud.
- **The top band** is upper sky: the long cloud lies in the gap between his name and the
  gear; the noon sun passes there; a high moon (above 41°) sails in the 22 pt lane above
  his name; about 40 % of his stars are in the band. Nothing bright goes behind the name or
  the age line: stars are placed outside that rectangle, and in the dark appearance the sun
  and the moon dim to an ember while they cross it.
- **The leading page** is the world running on to the left: the cool side of the sky (the
  Belt of Venus over the earth's shadow at twilight), the wider land, the ordinary fainter
  sky at night (spatter — not his stars). Sun and moon rise out of the fold gutter (x 504).
- **Sun and moon** keep the baseline's clock and x. The sun's height is the baseline's arc
  re-based on the horizon (noon at y 14); the moon's is its real altitude — 0–30° spans the
  strip window and the cards' top, then it lifts quickly into the top lane.

**Slab iPhone.** No tall window, so the horizon is at y 140, just under the first card's
edge, and the header becomes a small complete landscape: the tree in the gap between his
name and the gear, sun and moon in the 18 pt lane under the island. His name then sits on
the horizon, where twilight is brightest, so a long bank of cloud lies along the horizon on
that side (sun and moon rise from behind it).

## How each requirement is met

- **Bloom / hush** — seven palette keys by sun altitude, light and dark, at full strength;
  `present()` / `presentDark()` with `presence(state)`. The light hush is shaped: pulled
  toward the page by day, only greyed at night, so the light appearance still has a night.
  The sky's brushwork quietens with the colour.
- **His stars** — `nights()`; a place is a function of the night alone, mapped into the sky
  above the hills and the tree, weighted mildly toward the strip column and the top band,
  never behind the name, never on top of an earlier night's star, never under the moon (one
  the moon would cover sits on its rim). Counted as blobs in the bare night shots: 143 on
  the cover, in the spread's anchor window and on the slab (368 at a year). Tonight's is
  drawn at its evening-star place and takes its own the next day.
- **Seasons** — `season()` moves the land's local colour (straw, green, gold, frost, snow)
  and the tree: bare with frost along the upper side of its limbs and a few last leaves
  (now); snow lying on the limbs over a white knoll; blossom; a full crown with fireflies
  beneath it from the last of the sun; amber and thinning, leaves on the ground. All of it
  is re-lit by the hour like the land.
- **Bedtime** — the cards fall back; his star ignites (`ignition()`); a ring of brightness
  goes out from it across the others (≈ 210 pt/s). In November they flare; in July, with
  the sun still up, the ring briefly *shows* all 368 in the daylit sky and leaves only his
  evening star. `depth` then settles the picture deeper. The page's one line of text —
  a small star and "Night 143" — arrives at the foot while the cards are away (in the app,
  a SwiftUI `Text`).
- **Opening the Duo** — nothing special is drawn: the world was already there. Presence swells.
- **Motion** — clouds drift 0.08–0.14 pt/s across the *world*, so cover and spread agree;
  one band of mist moves in the valley between the two planes of land; stars use
  `twinkle()`; fireflies blink on 4–7 s periods; a few leaves or petals fall at ≈ 2 pt/s;
  one shooting star every 140 s. `motion=0`: all of it still. Between `t=12` and `t=95`
  0.04–0.6 % of pixels differ.
- **Tilt** — three planes: sky (−1.5 pt), far land and tree (≈ 1.5 pt), near land (≈ 6 pt).

## The hard limits, measured

The review's `bare` set at dpr 2; relative luminance as a 3 pt local mean (the ground a
letter's stroke sits on, not one grain of the paper).

| | cover | spread | slab iPhone | limit |
|---|---|---|---|---|
| **Dark, full bloom** (06:50, 16:10, 16:40): name | ≥ 9.6 : 1 (L ≤ 0.059) | ≥ 9.6 : 1 (0.059) | ≥ 7.9 : 1 (0.082) | ≥ 7 : 1, L ≤ 0.10 |
| … grey line | ≥ 5.7 : 1 (L ≤ 0.016) | ≥ 5.4 : 1 (0.019) | ≥ 3.9 : 1 (0.046) | ≥ 3 : 1, L ≤ 0.072 |
| Dark, all eight hours: name / grey | 8.6 / 3.4 : 1 | 8.6 / 3.3 : 1 | 7.9 / 3.9 : 1 | |
| **Light, full bloom**: name | ≥ 12.1 : 1 | ≥ 12.1 : 1 | ≥ 12.1 : 1 | ≥ 7 : 1 |
| … grey line | ≥ 3.10 : 1 (L ≥ 0.576) | ≥ 3.06 : 1 (0.568) | ≥ 3.06 : 1 (0.568) | ≥ 3 : 1, L ≥ 0.55 |
| Light, all eight hours: grey line | ≥ 3.08 : 1 (0.573) | ≥ 3.05 : 1 (0.566) | ≥ 3.06 : 1 (0.568) | |
| **Dark night, ground below the top band** (17:30, 21:00, 03:00): median / 95th / 99th pct | 0.003 / 0.008 / 0.0116 | 0.003 / 0.007 / 0.011 | 0.002 / 0.005 / 0.007 | a card is 0.0116 |
| **Light, ground below the top band**, darkest 5 % / median: day | 0.72 / 0.77 | 0.72 / 0.77 | 0.72 | page 0.887 |
| … bloom | 0.52 / 0.63 | 0.53 / 0.63 | 0.52 | |
| … night | 0.48 / 0.56 | 0.49 / 0.56 | 0.48 | |

Closest to the limits: the dimmed morning sun crossing the age line at 09:30 in the dark
appearance (L 0.061–0.064); the cover's dark ground at 03:00, whose 99th percentile equals a
card (that percentile is the setting moon, its halo and the stars — the sky and land are a
quarter of it); and the light grey line, held just over 0.55 on purpose so the top band can
still carry colour. **The light ground at bloom is deeper than today's**: the baseline's
cover reads 0.57–0.64 (darkest 5 %) and 0.78–0.83 (median) at the same hours, because it
fades to the page behind the cards and mine does not. White cards read clearly on it, but
"close to `#F2F2F7`" is a judgement here, not a pass.

## Cost

Headless Chromium on the lab machine (software raster, four shared cores), dpr 2:

| | spread 1902 × 1338 px | cover 932 × 1356 px |
|---|---|---|
| `create()` | 30–40 ms | 30 ms |
| first `render()` (textures, every mask, all three planes) | 0.6–0.7 s | 0.4–0.55 s |
| steady `render()` (only `t` moves): median / p90 | 3–5 ms / 5–7 ms | 2–3 ms / 3 ms |
| the minute or the light changes (planes repainted from cached masks) | 0.1–0.4 s | 0.15–0.2 s |
| a frame *during* a bloom (presence moving: the same repaint) | 0.25–0.3 s | 0.15 s |

Nearly all of the first frame is cutting masks and textures the app would ship
pre-rendered. The last row is the mock-up's real weakness: while presence moves, every frame
repaints the planes, so bedtime and the opening play at 3–6 fps in the live viewer (the
review's stills are unaffected).

## SwiftUI port, layer by layer

1. **Back plane** — `Canvas`: one `LinearGradient` (OKLab-sampled stops) per side of the sky,
   the sun's side masked in with a horizontal gradient; twelve pre-rendered *band* masks
   tinted with the colour a little further down the ramp; three radial pools (rose, gold,
   gold); halo rings and disc as tinted masks. About 25 fills, once a minute.
2. **Moon** — the phase `Path` the app already has, plus a mask for its dry edge.
3. **Stars** — two symbols (a dab, a four-point); a few hundred `draw` calls in a
   `TimelineView` at 10 fps; only opacity animates.
4. **Clouds** — three small images, each with body / lit / shaded masks pre-rendered for
   about a dozen light directions, tinted, cross-faded between the nearest two.
5. **Hills** — per hill a pre-rendered edge strip and a flat `Rectangle` below it; the lit
   and shaded sides are `Canvas` paths (the crest slid toward or away from the light) with
   the speckle image stroked in `destinationOut`, recomputed when the light has moved 2.5°.
6. **Tree** — pre-rendered masks from the growth script (wood, two leaf layers, blossom,
   snow, frost, last leaves), tinted; its lit rim is the wood mask minus itself offset.
7. **Paper and mottle** — two images in `softLight` over each plane.
8. **Small life** — a dozen sprites at 10 fps, only in season.

No shader. Steady state is three image draws and the star sprites. **Riskiest part: the
bloom.** Here a presence change repaints the planes; in SwiftUI every shape has to be a
tinted mask whose colour animates from one driving value (or two pre-composed planes are
cross-faded). Tractable, but it is where the port stops being a transcription. Second risk:
`softLight` over planes with holes needs an offscreen group per plane.

## Still not good enough

1. **Bedtime on the slab is weak.** With the horizon up in the header, the cards fall back
   onto a band of sky over a tall, nearly empty land. "Night 143" is set large in it, as the
   page's text side, but it is not a showpiece. The page should slide down as the cards
   leave (horizon 140 → ≈ 370, the stars spreading with it). Not built.
2. **The bloom is repainted, not animated**, in the lab (see Cost).
3. **The light appearance's night is pale**: a lavender page, his stars white on it at about
   1.5 : 1, each on a small patch of deeper sky so it shows at all. And the light bloom's
   ground is deeper than today's (see the numbers).
4. **The leading page has no feature of its own** — hills, a cloud, faint spatter at night.
   Opening the Duo widens the picture more than it reveals something.
5. **One dry-brush texture does every edge.** At 3× the chips on the halo rings and the lit
   shoulders all have the same character; the knoll's lit shoulder reads as a path as often
   as a lit slope; the clouds are simple loaves.
6. **Collisions with the chrome**: on the slab the sun spends its last half hour behind the
   gear; on the Duo the high moon rides 6 pt above his name and, between 35° and 41° of
   altitude, crosses behind it (dimmed while it does). The slab's cloud bank is a workaround
   for contrast that happens to look like weather.
7. **The dark hush is bluer than today's grey.** The accents lead over it in my
   side-by-sides, but it is a decision to look at.
8. **Unreviewed corners**: snowfall and petals never appear in the review set; `wake` and
   `close` only move presence; mist moves in one valley; the summer crown is ten clumps and
   can read like broccoli at 3×.
