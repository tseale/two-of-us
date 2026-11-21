# True light

`skies/true-light.js` · shots in `shots/true-light/review/` (`node tools/review.mjs --sky true-light`)

## The idea

Today's sky, kept, with one thing changed: there is a single light and everything answers
it. The twilight is a real one — ember on the horizon under apricot, a breath of green-gold,
rose, lilac, into blue — and it *leans*: its bands stand tall over the sun's x and sink
toward the horizon away from it, until, a whole page away, the Belt of Venus stands over the
earth's shadow. The bank of cloud is lit from where the sun really is (fire underneath, slate
on top, once the sun is below it), the high cloud stays lit after the land has gone dark,
each ridge takes its colour from the sky at the horizon, and mist lies level in the valleys
and catches what light is left. At night the same shader is lit by the real moon.

It is one picture printed twice. The palette is a "negative" — twilight keyframes by the
sun's altitude, written as value / chroma / hue — and the light appearance is a high-key
print of it (luminous pastel, a light page), the dark appearance a low-key print (indigo,
plum, ember; near-black at night). So the two appearances are the same world, not two
palettes that happen to share a layout.

## Composition

- **Horizon: 305 pt from the top on the Duo** (0.45 of the cover; the spread uses the same
  305 pt, so the phone page's picture is identical to the point, open or closed), **350 pt
  on the slab** (0.40). On the Duo that puts the horizon in the middle of the strip's clear
  window (y 158–396): the last two hours of the sun, the bank, every colour band of the
  twilight and the first four ridges are all inside it. The twilight's stops were pulled
  down (rose at 0.29 of the sky's height, lilac at 0.44) for the same reason.
- **Top band** (the stage): only the upper sky — lilac into blue — and the high cloud: one
  long soft swath slanting across the frieze, with a few finer streaks above it, lit rose
  and gold at the bloom. Nothing else ever enters it: the sun and moon are held under the
  band on every device (their highest is just under the first card's top edge), so nothing
  bright is ever behind his name. A soft limiter (OKLab L ≤ 0.385 dark, ≥ 0.848 light)
  covers the band as a guarantee; it is rarely reached.
- **Strip**: sun or moon low over the ridges, the bank, the bands, ridge behind ridge with
  mist. Tonight's star is lit here, at x 389, y 203 — above and left of where the sun sets,
  like an evening star — and drawn over everything so a passing cloud never hides it.
- **Three slits, one horizon** on the spread: margin, gutter and strip show the same horizon
  at the same height, each in its own light — plum Belt and earth-shadow in the margin,
  rose in the gutter, ember in the strip. The sun rises out of the fold.
- **Leading page**: the world away from the sunset — cooler sky, the same ridges, and the
  near hill shouldering up into the margin column with its woods (where the season shows
  first). It carries the ordinary, fainter sky; his stars are all in the anchor window.
- **Sun and moon** keep the baseline's clock and x; their height is the real altitude,
  opened out near the horizon (1.7° is 27 pt up) and capped at 0.63 of the sky (0.57 on the
  slab). A low moon is warmer and a little dimmer. The cost of keeping them out of the
  band: with the cards on they are seen only in the strip (the last fifth of their pass),
  the margins and the gutter — and never on the slab. Their light is everywhere.
- **His stars**: `nights()` exactly — one per night, 143 on the lab's default night once
  tonight's is lit — placed by a fixed warp of (u, v) that weights them toward the top band
  and the strip. Sharp discs, each its own colour (cool, white, cream, a few rose and
  orange); the first night and each month-night carry a fine four-point glint.

## What answers what

| | |
|---|---|
| bloom / hush | `presence(state)` straight into `oklab.present` / `presentDark`, per pixel, in the shader. The sun's and moon's discs are exempt (they are the light). Above 15° the palette does not change at all. |
| appearance | two prints of one table (`print()`); the dark print's golds are turned toward ember (a dim gold is mustard), the light print gives saturated colours a little depth so pastels keep chroma. |
| bedtime | `depth` deepens the sky; tonight's star follows `ignition()`; the others answer in a ripple that leaves his star at 1.5 s and crosses the sky at 210 pt/s; a caption — NIGHT 143 — stands beside the star while the cards are back (1.7–5.6 s). In July (sun up 7°) only the brightest of his stars show; the star is lit beside the low sun. |
| opening | the `open` swell through presence; the leading page is the same world running on, so there is nothing to cross-fade. |
| seasons | `season()` → ground, woods and blossom albedos, lit by the hour. Snow lies light on the shoulders and blue in the hollows; frost silvers open ground; the woods' tops catch the last light, which is where russet, new leaf and blossom show at the bloom; fireflies over the near valley from dusk; snowfall as slow flakes at three depths (`snowfall=1` in the URL forces it — see below). |
| motion | cloud drift 7 pt/min (low) and 3 pt/min (high), mist drifting in the valleys, twinkle, a rare shooting star; quantised to 12 fps. `motion=0`: everything at rest. |
| tilt | per-layer x/y offsets (stars 1 pt, far ridge 1.2 pt … near hill 15 pt). |

## Measured (bare shots, `review/bare`, dpr 2)

Behind the header text at full bloom (06:50, 16:10, 16:40):

| | grey line | name |
|---|---|---|
| light (sky luminance, min) | 0.60–0.64 → **3.26–3.42 : 1** (limit ≥ 0.55, 3 : 1) | ≥ **13.0 : 1** |
| dark (sky luminance, 99.5th pct) | ≤ 0.050 Duo, 0.055 slab → **≥ 3.5 : 1** (limit ≤ 0.072) | ≤ 0.053 → **≥ 10.2 : 1** (limit ≤ 0.10) |

Below the top band (areas: medians of 8 pt blocks, the sun's/moon's own disc left out):

- dark, night (17:30, 21:00, 03:00): lightest ground **0.009–0.011** (a card is 0.0116); darkest 0.0003.
- dark, hushed day: lightest **0.0105**. Dark, bloom: up to **0.17–0.19** in the ember by the sun (OKLab L ≈ 0.55); discs: sun 0.71–0.80, moon 0.63–0.78.
- light: darkest ground **0.53–0.55** at bloom, 0.69 at midday, 0.67–0.72 at night (page 0.89).

`render()` at dpr 2 in the lab's headless Chromium, which is software GL (SwiftShader, 4
shared cores): spread first frame ≈ 1.1 s (≈ 0.7 s of it compiling the shader), steady
0.35–0.43 s; cover 0.16–0.20 s. Everything outside the shader (palette, uniforms, the star
canvas and its upload) is a few ms. Land is drawn front to back and the sky is skipped
under it, which halved the cost.

## The port

1. **Palette** — `KEYS`, `print`, `hermite`, `palette()`: ~150 lines of pure Swift, giving
   64 OKLab ramp samples and ~30 colours. Recomputed when the minute changes (and per frame
   during an event). Free.
2. **Shader** — one Metal fragment function, `layerEffect` on the stars' `Canvas` (it reads
   the stars from the layer, as the lab reads its texture). The GLSL ports line for line;
   uniform arrays go through `.floatArray`. Per pixel: sky = 2–3 ramp lookups + ≤ 7 cloud
   density evaluations (1-D noise but for one value-noise each); land ≈ 2 ridges on average,
   each three 1-D fbm and three value-noise. No loops over stars, no textures but the layer.
   A full screen at 12 fps is well inside budget; it can also run at half scale, or be
   drawn to an image every few seconds — at 7 pt/min nothing moves faster than that.
3. **Stars** — `Canvas`: one sprite per night of his life (366 by his first birthday) plus ~120 fainter ones on the spread's leading page; `TimelineView` at 12 fps, at night only.
4. **Over the land** — a second `Canvas` (tonight's star, ≤ 70 fireflies, ≤ 85 flakes) and a `Text`.
5. Unchanged: flat page under Reduce Transparency / Increase Contrast, hidden from VoiceOver, no touches.

Riskiest: the shader in SwiftUI's colour pipeline. It must end in the layer's working space
exactly as it ends in sRGB here, or the two measured limits move; the `sin` hash must be
replaced by the integer one throughout (Metal fast-math); and ~340 floats of uniforms plus a
sampled layer is at the edge of what `Shader` arguments are comfortable with.

## Not good enough yet

1. **The bank is the weakest drawing.** Bars of 1-D noise read as airbrushed spindles; there
   is no real billow, and after ~15 minutes of drift the main bar has left the strip. It
   wants two or three painted density textures, lit by the same walk toward the light.
2. **Night with the cards on is refined, not a showpiece.** The moon is behind the cards for
   most of its pass (my choice, to keep it off his name); on the slab neither sun nor moon
   is ever seen with the cards on.
3. **The light appearance at bloom is sweet** — pink, lilac, peach — and the land goes
   mauve. Light at night is a pale page with white points; the limits leave little room.
4. **The margin's feature is only a shoulder of hill.** The tree line is a soft fringe, not
   drawn trees; russet and blossom read as tints. In the app this should be `Canvas` paths.
5. **Hushed midday in the dark appearance is plain**: deep slate, a quiet horizon in the strip.
6. Tuned hardest at the lab's hours (+1.7°, −3.2°, −12°). Between 4° and 9° the dark print
   is murkier (July's bedtime shows it).
7. Tonight's star on a light page is a white glint on pale sky with a breath of dusk behind
   it. Findable, not lovely.
8. All seven ridges share one character (value-noise swells).
9. Motion was judged from two stills 83 s apart (mean difference 0.1–0.3 of a level), never
   watched: software GL runs the spread at about 2.5 fps.
10. With the cards on, the season is hard to tell apart at sunset — snow, fireflies and the
    margin's hill show it; the rest is behind the cards.

## Lab notes

- `lab/season.js` promises `snowfall=1` to force snow in the air; the viewer neither parses
  nor passes it. The module reads it from the URL itself (`forcedSnow()`), so
  `--param snowfall=1` works with this sky. The review's winter day has no snowfall.
- With `chrome=0` `state.cards` is empty, so the text band's foot is a per-device constant
  here (90 pt Duo, 134 pt slab) rather than read from the header's rect.
- At night `scene.body` is the night's progress, not the sun; the sun's x after sunset is
  worked out in the module (it slides 8 % of the window past its setting point).
