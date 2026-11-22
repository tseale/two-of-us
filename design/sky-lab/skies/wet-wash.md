# Wet wash

`skies/wet-wash.js` · shots in `shots/wet-wash/review/` (`node tools/review.mjs --sky wet-wash`)

## The idea

Home's ground is one sheet of cold-pressed paper with a watercolour on it that happens to
tell the real time. A graded wash is laid along the top and pulled down; clouds are paper
left or lifted, with a shadow dropped in at the base; the sun is untouched paper in a wet
halo and the moon is lifted out of the night wash in its true phase; the land is four
transparent glazes, each with a drying edge along its top and a dissolve into wet paper
below (the valley mist), then a strip of water that is simply paper left, and a near bank.
His stars are flecks of gouache on top of all of it, one per night.

**The bloom is literal.** Colour is subtractive here: every passage is an absorbance, washes
add, and the picture is `paper × exp(−A)`. So the hush is a diluted wash — in the light
appearance the paper's white *is* the app's page and the wash simply dies away below the
top band — and a bloom is pigment arriving: the same wash, fuller, flooding down the sun's
side of the sheet, flowering wet-in-wet, pooling where it meets the land, with back-runs
opening in three chosen places. The dark appearance is the same hand with heavy washes:
indigo and neutral tint at night with the tooth showing, wine, plum and ember at the bloom.

Best frame: `shots/wet-wash/review/day/cover-dark-1610.png`.
Weakest: `shots/wet-wash/review/bedtime/november/t3/iphone-light-1940-night.png`.

## Composition

**Duo.** The horizon is **300 pt from the top on cover and spread alike** (0.44 of the
cover), so opening the Duo widens the picture and moves nothing. That puts it in the lower
middle of the strip's clear window (y 158–396): the window shows, top to bottom, the wash
running down, the long cloud bars over the glow, the sun's last hour (it goes down behind
the far ridge at x ≈ 447), the pooled line where the wash met the land, and three glaze
edges (≈ y 294, 327, 362) with mist between them. The fourth ridge, the water (y 472 →)
and the near bank (≈ 562) lie under the tab capsule and the cards: they are there for the
leading margin, the fold gutter and the two moments when the sheet is seen whole.

- **Top band** (the stage): only the upper wash — the bead along the top edge, granulation,
  one lifted cloud in the gap between his name and the gear, one back-run there at the
  bloom — and his stars. At the bloom it grades *sideways*: the colours stand tall over the
  sun and sink toward the horizon away from it, so behind his name it is violet-lilac and
  at the strip it is rose; the busiest and warmest passage is never behind the text.
- **Sun and moon** keep the baseline's clock and x. Height is the real altitude, opened out
  near the horizon (`H − 14 − span·(alt/90)^0.55`: 1.7° is 20 pt of climb, 27° about 92 pt)
  and **held under the header** — except that a body which is high (above ≈ 42°) while it
  crosses the clear gap between his name and the gear (x 203–303) comes up into the band.
  So tonight's moon sits at (220, 46) at 21:00, and a midsummer noon sun shows there too;
  the low winter sun spends the day behind the cards and comes out in the strip to set.
- **His stars** are `nights()` exactly — one per night, 143 on the lab's default night once
  tonight's is lit — placed by a fixed warp of (u, v): 46 % in the top band, 24 % in the
  strip's columns, moved clear of the avatar, his name and age, the gear, the island and the
  clock (to the 20 pt lane above, the gap, or the strip's window). First-night and
  month-birthday stars carry a hand-drawn four-point glint.
- **Tonight's star** is lit at (386, 210): in the strip's clear window, under the wifi and
  battery even with a sleep running, like an evening star. It is warm gouache with a soft
  wet halo, so it is the one warm point in the column all night.
- **The leading page** is the world running on to the left, away from the sunset: the
  thinner, cooler side of the wash, the far ridge rising to its one high shoulder in the
  margin column (peak at world x −432), a back-run in the margin's sky, the water and the
  bank the full width. At night it carries the ordinary sky — spatter flicked off the brush
  and one long river of it — not his stars. Sun and moon rise out of the fold gutter.
- **Three slits, one horizon** on the spread: margin, gutter and strip are where the
  glazes' edges are "found" (crisp, with their drying line); between them, under the cards,
  the same edges are "lost" (soft, a third of the edge-darkening).

**Slab iPhone.** No tall window, so the horizon stays out of the way at y 352 (0.40) and the
header is pure sky: the wash, a lifted cloud, a back-run and tonight's star in the gap
between his name and the gear, his stars weighted into the top 134 pt. The land shows only
in the 16 pt margins, through the glass, and as a line of glow between the hero card and
the tiles at the bloom. This is the weakest display for this direction.

## What answers what

| | |
|---|---|
| bloom / hush | `presence(state)` drives three things at once: the palette (`quiet()`: light — 36 % toward the page's lightness and half the chroma at hush; dark — 10 % darker, 0.52 of the chroma), **how much of the wash is on the paper** (light: below the top band the cover runs from 0.05 at hush to 0.4–1.0 at the bloom, more on the sun's side), and how wet it is (wet-in-wet warp and feathering, back-run size, the cloud bars, the pooled line at the horizon). |
| light / dark | One model, two loads of pigment: thin washes on the page's own white; heavy washes (absorbance 3–5) in which every modulation is scaled down so a lift never flashes. The light night is not pulled toward the page, only greyed, so it is still a night. |
| his stars | Dark: gouache flecks, cool to warm by `warmth`, slow `twinkle()`. Light: flecks of the night's own indigo on the pale wash (white gouache would not show). None is drawn behind the moon's disc. |
| seasons | `season()` tints the glazes — the nearer, the more of their own colour: umber now, russet in October, paper-white snow with blue shadow and lighter moonlit ridges, sap green, deep green — plus hoar-frost lifted under the drying edges, blossom dropped in wet along the two near crests, fireflies over the water on summer evenings, slow snow on the days `season()` says it falls. |
| bedtime | The sheet deepens with `depth`; tonight's star follows `ignition()` with a wet ring opening around it (the bloom, literally); the others answer in a ripple that leaves his star at 1.5 s and crosses the sky at 190 pt/s; `NIGHT 143` stands beside the star while the cards are back (1.5–6.4 s). The moon lays a broken path on the water. In July (sun up 7°) the star is lit beside the low sun and only the brightest of his stars answer. A nap gets no moment: the dark sheet is a touch deeper and any bloom a little quieter. |
| opening the Duo | The `open` swell through presence; and the leading page starts with a first, thinner pass of the wash that a second pass crosses from the fold in 1.5 s. |
| motion | Clouds sway ±19 pt over ten minutes and come back; mist creeps (about 7 pt a minute); during a bloom the feathered edges creep at 6–10 pt a minute; stars twinkle. The wash is repainted at most every 4 s (a step is under half a point). `motion=0`: byte-identical at any `t`. No shooting star yet. |
| tilt | The glazes slide by depth (far ridge 1.5 pt … near ridge 8 pt, bank 12 pt in x; a little in y). The sky is the paper and stays put. |

## Measured (bare shots, `review/bare`, dpr 2)

Behind the header text — the 0.5th-percentile luminance (light) or the 99.5th (dark) over
the text's own rectangle, so the granulation's darkest pits and lightest flecks count:

| | grey line (`#6C6C70` / `#98989F`) | name (and the leading page's title) |
|---|---|---|
| light, full bloom (06:50, 16:10, 16:40) | sky ≥ 0.593 (limit 0.55) → **3.20–3.44 : 1**; leading subtitle ≥ 0.583 → 3.15–3.22 | **≥ 12.4 : 1** (title ≥ 12.1) |
| light, night | ≥ 0.636 → 3.42–3.76 : 1 | ≥ 13.1 : 1 |
| dark, full bloom | sky ≤ 0.051 (limit 0.072) → **3.62–4.88 : 1** | ≤ 0.044 (limit 0.10) → **11.1–14.8 : 1** |
| dark, night | ≤ 0.016 → ≥ 5.5 : 1 | ≥ 15.5 : 1 |

Below the top band (medians of 8 pt blocks):

- **dark, night** (17:30, 21:00, 03:00): mean ground 0.005–0.006, 99th percentile ≤ 0.011
  (a card is 0.0116). In 24 pt blocks nothing but the block holding the moon's own disc is
  above 0.0115; the wash right beside a low moon is 0.011, the rest of the sky ≤ 0.0108.
  0–0.4 % of the 8 pt blocks are over a card: the moon and the small halos of a few bright
  stars. The moon's disc is 0.80.
- dark, hushed day: mean 0.006–0.008; the sun's disc (0.73) and its halo, both behind the
  cards on the Duo, are the only light.
- dark, bloom: ember beside the sun up to 0.23, the sun's disc 0.74–0.80, mean 0.017–0.030.
- **light**: darkest ground at the bloom **0.52–0.54 on the Duo, 0.50 on the slab** (the
  third glaze's drying edge and the cloud bars); mean ground 0.74–0.77 at the bloom, 0.85
  at hush, 0.81–0.83 at night (the page is 0.891).

## Cost

`render()` on the spread at dpr 2 (1902 × 1338), in the lab's headless Chromium, which draws
WebGL in software (SwiftShader) on a shared 4-core VM:

- first frame ≈ **3.1 s**, about 2 s of it compiling the shader;
- a repaint of the wash ≈ **1.0–1.1 s** (cover ≈ 0.6 s);
- a steady frame — only the stars move — **0.2–1.6 ms**.

The wash is repainted when the state changes, otherwise at most every 4 s while anything in
it moves, and once under Reduce Motion or a frozen `t`. (Measured with a blocking one-pixel
readback: set `globalThis.__wetWashMeasure = true`; the numbers are in `window.__wetWash`.)
These are CPU numbers for a GPU job — about 75 gradient-noise taps a pixel. On a phone's GPU
I would expect a repaint in single-digit milliseconds, but I have not measured that.

## The SwiftUI port, layer by layer

1. **The wash — one Metal fragment shader.** The GLSL here is a single pass with no loops
   over data and ports line for line (`uint` hash, gradient noise, `mat2`). About 35
   uniforms (the palette as absorbances, sun/moon, a few layout numbers) computed in Swift
   from the same OKLCH tables. Do **not** run it per frame: render it into an image when
   its inputs change — the minute ticks, presence moves, scheme or size change — and
   cross-fade (an offscreen `MTKView`/`CIImage` render, or `colorEffect` inside a
   `Canvas` that is only invalidated then). During a bloom that is one repaint every 4 s;
   otherwise one a minute. Worth doing: bake the paper tooth and the warp noise into one
   tiling-free 1024² two-channel texture (`scripts/make_sky_textures.py`) — that takes the
   shader from ~75 noise taps a pixel to ~15.
2. **His stars, spatter, fireflies, snow — a SwiftUI `Canvas`**, ≤ 143 ellipses (+ ~360
   spatter dots on the spread's leading page), in a `TimelineView` at 10 fps that only
   runs at night; paused under Reduce Motion.
3. **Tonight's star and its ring — the same `Canvas`** (two radial gradients, a glint
   path); **the caption** a `Text` in SF Rounded.
4. **Reduce Transparency / Increase Contrast:** the flat page, as today.

Riskiest part: the wash shader's weight and its first compile if it is ported unbaked, and
matching the subtractive mix exactly (it is computed in linear sRGB and dithered; on a P3
display the absorbances should be derived in the display's space or the plum and ember
shift). Second: the dark appearance's lifts — at absorbance 4 a 10 % change of load is a
1.5× change of light, which is why every modulation there is scaled by `uMul`.

## Still unresolved

- **The light night** is a pale lavender page with indigo flecks. It is calm and it is
  honest about the constraint, but it is not a night sky, and the lifted moon is faint.
- **The slab** shows almost none of the picture with the cards on.
- **Under the cards in the light appearance** the glazes' edges still show as short lines
  in the 12 pt gaps between cards; soft, but they are lines.
- **The gap rule for sun and moon** is a discontinuity: a high moon climbs ~60 pt in about
  ten minutes as it enters the gap, and drops as it leaves.
- **Sameness.** The clouds, bars and back-runs are placed, not weathered: the same three
  blooms open in the same places every evening. They should be seeded by the day.
- **Opening the Duo** is modest — a swell and a second pass. Pigment actually flooding
  across the leading page from the fold would be the real showpiece; I did not trust the
  first frame (a half-bare page) enough to ship it.
- **Seasons** live in the land's colour, which the cover mostly hides; there is no leaf
  fall or petals in the air, and the blossom is small.
- In July the low sun and tonight's star are 45 pt apart in the strip; it reads, but it is
  crowded.
- The lab's software GL makes the shader look expensive (a second a repaint); see Cost.
