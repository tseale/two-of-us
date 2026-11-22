# Night-light

**The idea.** Nothing is drawn. The sky is a field of soft light — the way a night-light
glows on a nursery wall — and the picture is about *where the light is*: the sun and the
moon are soft orbs whose light pools and tints everything, and their place by the real clock
moves the whole field. Into that softness goes one sharp thing: **his stars**, a crisp point
for every night of his life. At bedtime tonight's is lit, warm, and a thin ring of light
travels out through all the others.

Two layers, and that is all:

| Layer | What | Lab | SwiftUI |
|---|---|---|---|
| **field** | everything soft: the two colour ramps, the warm-to-cool turn, the sun's and moon's pools and discs, three swells of land with mist, frost, the slow unevenness of the light, the bedtime ring, the grain | one WebGL2 fragment shader + a 256 × 3 OKLab look-up row set | one small Metal shader (`colorEffect`), ~40 floats and the look-up as a `floatArray` / image |
| **points** | his 143 stars, the leading page's ordinary sky, snow / petals / leaves / fireflies, a rare shooting star, the bedtime caption | a 2-D canvas | one `Canvas` (≤ 400 fills) + one `Text` |

## Composition

- **The horizon is in the seam.** On the Duo it is at y 292 (0.43 of the cover's height): the
  12 pt gap between the Today card and the log tiles, which is also the middle of the system
  strip's clear window (y 158–396). So the last hour of the sun happens in the strip, and the
  horizon's band of light shows as one line across the page through the seam, the margin and
  (on the spread) the fold gutter — the same height in every slit. On the slab the seam is at
  y 340; since its only window is the top band, the sky's layers are spread unevenly there
  (`ePow`) so the low, colourful ones reach up into the header.
- **Sun and moon** keep the baseline's clock and x (rise at the anchor's left edge, set at its
  right). Height is remapped to this horizon: on it at rise and set, and at the top of the arc
  just under the top edge (y 12) — *above* the header's words. Where an orb's path would cross
  his name it is lifted over it (`clearOfWords`); it never sits behind text. After sunset the
  pool sinks below the horizon, widens and reddens, and lingers to about −16°.
- **The turn.** Two vertical ramps — the sun's side (ember, apricot, gold, a breath of
  celadon, blue) and the far side (earth-shadow slate, the Belt of Venus rose, lilac, blue) —
  are mixed by distance from the sun, wider along the horizon than overhead, so the warm
  colours make an arch. On the spread the leading page is the far, cool side.
- **Land** is three swells of tone, each darkest along its crest and lightening to mist at its
  foot; far ones take the air's colour. No edge is sharper than ~10 pt. Under the cards it
  settles into the page.
- **His stars** all live in the anchor window, above the horizon, placed by `nights()`
  through a fixed density map (two inverse CDFs) that puts most where sky shows — the top
  band, the strip, the leading margin — and none on his name, the avatar, the gear, the
  island or the clock. The leading page carries 84 soft, out-of-focus, nobody's stars.
- **Tonight's star** is the evening star: upper right of the strip's clear window
  (x 450, y 211 on the Duo; right of his name on the slab), off the sun's path so that at
  sunset it stands above the glow. Before he is down it waits there as a faint ring from
  dusk; lit, it is the only warm point with a pool of its own.

## The brief, point by point

- **Bloom and hush.** Palettes are written at full strength (OKLCH tables by the sun's
  altitude) and quietened with the lab's rule on OKLab directly (`quiet()` = `present` /
  `presentDark`, a slightly higher chroma floor, and the light appearance pulled less toward
  the page at night, as today's sky is). `presence()` also focuses the sun: at hush it is a
  dissolved pool, at bloom a soft orb.
- **Light / dark.** Light is luminous pastel and never deep; dark is indigo, plum, wine,
  ember. In the light appearance a star cannot be brighter than the page, so it is drawn as
  its trace: a crisp ink point in a small pool of light.
- **Seasons** are temperature (a hue turn / chroma change applied separately to warm and
  cool colours, and the land's tone: snow lighter than the sky, frost as a pale glow on the
  crests, spring and summer green-gold) and a few particles (snow, petals, leaves from
  October, fireflies low over the land from dusk).
- **Bedtime.** `ignition()` lights tonight's star; from 1.25 s a thin ring leaves it and
  crosses the display in about four seconds, each star flaring as it passes (in July, with
  the sun up, they appear with the ring and go again); `NIGHT 143` sits beside the star
  from 2 s to 6.5 s; `depth` then dims the field. Reduce Motion: no ring, no caption, the
  star simply lit.
- **Opening the Duo.** `presence()`'s swell, plus the light crossing the leading page from
  the fold over the first 1.2 s; at night the ordinary stars arrive from the fold outward.
- **Motion.** The unevenness drifts ~1 pt/s, the mist breathes on 41–67 s periods, stars
  twinkle (halo only — a core never goes grey), a shooting star about every 97 s of a clear
  night. Reduce Motion freezes all of it (`t` is ignored). Tilt shifts stars 3 pt, orbs
  1.5 pt, swells 2–8 pt.

## Measured (bare shots, relative luminance)

| | limit | measured |
|---|---|---|
| dark, behind the name, full bloom | ≤ 0.10 | 0.017–0.019 Duo (15.6:1), 0.040 slab (11.7:1) |
| dark, behind the grey line, full bloom | ≤ 0.072 | 0.019 Duo, 0.057 slab (06:50) |
| light, behind the grey line, full bloom | ≥ 0.55 | 0.61 (16:40) – 0.65 Duo, 0.68–0.70 slab; name ≥ 13:1 |
| dark, 21:00, lightest ground below the top band | card 0.0116 | 0.0104 (cover, slab) – 0.0116 (spread); darkest 0.0019 |
| dark, 03:00, moon setting in the strip | card 0.0116 | 0.017 outside 20 pt of the moon — its glow is over the limit there |
| dark, 17:30, the last after-glow at the horizon | — | 0.025 |
| dark bloom, 16:10 | — | sun's disc 0.62; pool 0.18 at 20 pt, 0.10 at 60 pt, 0.04 at 180 pt |
| light, darkest ground below the top band | page 0.886 | 0.61 at bloom, 0.64–0.68 at night, 0.81 at midday (today's sky: 0.55–0.63 by day, 0.40 at night) |

`render()` on the spread at dpr 2: JavaScript 17–26 ms for the first frame, 0.2 ms (day) to
1.2 ms (night, ~230 points) steady. The shader itself could only be timed on the lab's
software GL (SwiftShader, on the CPU): ~0.27 s a frame at 1902 × 1338, ~0.5 s the first.
On a real GPU it is a few texture taps, five `exp`, three value-noise lookups and one
OKLab → sRGB per pixel; it has not been measured on a phone.

## Port

1. **Field** → `Rectangle().colorEffect(ShaderLibrary.nightLight(…))`. The GLSL ports line for
   line. Nothing in it needs 60 fps: redraw when the minute changes, during an event, and at
   ≤ 12 fps (`TimelineView`) for the drift; it could even be drawn at half size and scaled,
   with only the grain at full size. Without a shader it is five gradients (two
   `.perceptual` linear ramps cross-faded by a mask, two radial pools, three blurred swell
   shapes) plus a grain tile — at the cost of the dither and the unevenness.
2. **Points** → a `Canvas`: filled circles, one resolved glow symbol, a few ellipses; at
   night a 10 fps `TimelineView` for the twinkle, otherwise still.
3. The star map (a 120 × 76 weight grid) is built once per device; star places are constants.

Of the five directions this should be the cheapest. **Riskiest:** banding. The whole look
rests on dark gradients that span ~12 eight-bit steps; here the shader dithers per device
pixel. In SwiftUI the shader's output passes through the layer's colour management, and the
dither must be re-proved on a phone (and under Low Power Mode).

## Unresolved

- **Light appearance at night.** Ink-point stars are a decision, not a triumph: they read as
  a star chart, not as light. The light appearance earns its place at the blooms.
- **It is still a gradient at hush.** At 12:30 in light it is nearly the page: a paler top, a
  soft whiter pool where the sun is, a line of cream in the seam. Easy to live with; nobody
  would hand over their phone for it.
- **The slab.** The horizon — where everything happens — is behind cards; only the top band,
  the seam and the glass tell it. The setting sun is a pool at the edge of a card.
- **The ring** was judged from stills only. A thin circle of light can read as sonar; its
  speed and softness need eyes on a device.
- **The moon** by day in the light appearance is a pale dot; it has no surface (by design).
- **Particles** are sparse where the sky shows (two to five in the strip at a time); night
  snow is softened but can still be taken for faint stars.
- **Fixed numbers.** The seam (y 292 / 340), the words' rectangle and the star map's holes
  are Home's layout written down; a taller banner or Dynamic Type would move them. In the
  app they should come from the cards' frames.
- **Tonight's waiting ring** is the one outline in the picture. `wake` has no choreography
  of its own beyond the swell. No scroll parallax.
- Needs WebGL2 in the lab; there is no fallback.
