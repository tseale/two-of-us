# Paper theatre

`skies/paper-theatre.js` · review set in `shots/paper-theatre/review/`

## The idea

Home's sky is a small lit stage of cut and torn paper. A back sheet, three depths of torn
cloud strips, eight flats of land (the far ones torn and soft, the near ones knife-cut), and on
the leading page's margin a cut tree whose leaves are loose scraps. The sun or the moon is a
lamp **behind** the stack: the sun is a round hole in the back sheet, the moon a hole in the
shape of tonight's phase, and his stars are pin-pricks in the same sheet — one more pricked
each night, tonight's a little larger and warm, with its light soaking into the paper round it.

Two lights do everything. The lamp behind soaks into the sheet around its hole, lights each
flat from peach beside it to mauve and slate away from it, shows *through* the far flats once
it has gone down behind them, and rims the edges that stand in front of it. The room in front
(soft, from below, like a footlight) gives each flat its paper colour, its lighter cut face and
the shadow it throws on the flat behind. By day the room wins: white-on-white relief. At the
bloom the lamp wins.

The two appearances are two papers, not one picture inverted. **Light:** a dyed back sheet and
*white* paper in front of it; the land takes its colour from the lamp and the season, never
deep. **Dark:** black paper in a dark room and a light box behind it; the sheet is the
brightest thing and the flats darken toward the front.

## Composition

- **Horizon.** On the Duo the far ridge sits at y ≈ 300 of 678 (0.44), the same points on the
  cover and the spread (the spread just loses 9 pt at the foot), so the sun's last hour and a
  low moon fall in the strip's clear window (y 158–396) with four crests under them. The near
  flats run on behind the cards and the tab capsule to the foot.
- **The strip's column** (cover x 362–466) is the picture: sky sheet and two or three cloud
  strips, the lamp, then a far peak (x ≈ 385) whose right flank runs down into the notch at
  x ≈ 450 where the sun sets, and behind it three flats that slope the *other* way each time.
  The same alternation is drawn into the leading margin and the fold gutter, so the three slits
  of the spread read as one stack of hills seen through mullions.
- **The top band** is kept calm for the text: sheet, lamp and stars only — the cloud strips
  live between y 130 and 260. A high sun or moon rides a lane 14 pt from the top (above the
  name); a lamp that would sit behind the name or the age line dims as it passes (see
  "unresolved").
- **Sun and moon** keep the baseline's clock and x. The sun rises at the anchor's left edge
  (cover: under the Today card's corner; spread: in the fold gutter) and sets into the notch in
  the strip; after sunset it keeps going down *behind* the flats, so its disc glows through the
  first sheets of paper. The moon's height is its real altitude, remapped to this horizon.
- **His stars** are all in the anchor window, above the highest crest (y 7–262), each night at
  its own `nights()` place, gathered a little toward the top band and the strip
  (x = 1 − (1 − u)^1.22, y = v^1.3). The leading page carries 84 fainter, uncounted pricks.
  **Tonight's star** is lit at a fixed spot in the strip's clear window (cover 444, 210 — up
  and to the right of the sun's last path), so it is findable all night with the cards on; it
  takes its `nights()` place the next day.
- **The leading page** is the wider, cooler land: the far summit (the range's highest, seen
  whole only when the Duo opens or at bedtime), the pink belt over the earth's blue shadow at a
  sunset, and in the clear margin column the tree, kept inside x 6–90 so no bough crosses the
  card's edge.
- **iPhone.** No tall window, so the stage is the header: the far ridge keeps under the first
  card behind the name and rises only in the clear part of the header (a peak at x ≈ 320, the
  sunset notch at the right edge under the gear). No cloud strips there.
- **Under the cards** the stage goes soft: a 3 pt blur and a thin vellum veil through a mask of
  the card frames (`state.cards`, fading with `veil` / `lead`), so crisp cut edges never cross a
  card border; the windows stay crisp.

## How each brief item is answered

| | |
|---|---|
| Bloom / hush | Palettes are written at full strength per appearance by solar altitude (day, gold, set, dusk, night) and quietened with the lab's hush rule; `presence(state)` drives it. The light appearance's night keeps its own lightness (no lift toward the page), otherwise night reads as a pale day. |
| Stars | `nights()`; pricks are as bright as the lamp behind them whatever their size — faint nights are small holes; month-birthdays are four-point cuts; the first night the largest. Out by `presence().stars`. |
| Seasons | The land is the season's paper (straw, white, pale green, sage; hue only, lightness stays the paper's); snow caps on the three far ranges and the near land wholly white; frost as a hair on the far crests; the tree's scraps (amber, none, blossom, green); paper snow, petals, leaves in the air; fireflies from dusk in summer. |
| Bedtime | `presence` swell and `depth`; tonight's star is pricked with `ignition()`; the others answer in a ring that travels out from it; a small "NIGHT 143" beside it while the cards are back. In July the sun is still up: the star is lit in the daylit sheet (a gold halo and a dimple ring on pale paper) and only the brightest pricks answer. |
| Opening the Duo | A pop-up: the leading page's flats hang low at the far end and swing up about the fold, far ones first (0.08 s apart, 0.95 s each, ease-out, no overshoot); cloud strips slide in from the wing; the tree stands up last. |
| Motion | Clouds drift 0.07–0.16 pt/s on a wrapping track; stars swell (`twinkle()`); scraps fall 4–9 pt/s; fireflies breathe. `motion=0`: everything at t = 0, still. |
| Tilt | Parallax: each layer translates by its depth (up to 15 × 8 pt for the nearest flat; the sheet and its holes do not move, so the land slides across the sun). |

## The measured limits

From the bare shots (`review/bare`, plus 09:30–10:30 and 17:00–19:40 where the sun and moon
pass the header text), 99.5th / 0.5th percentile of the pixels behind the text boxes.

| | name | grey line | limit |
|---|---|---|---|
| Dark, full bloom (06:50, 16:10, 16:40) | 15.1–16.0 : 1 (bg ≤ 0.019) | 5.2–5.5 : 1 (bg ≤ 0.020) | ≥ 7, ≥ 3 |
| Dark, worst of the day (10:00 sun behind the name; 09:30 behind the age line) | 10.2 : 1 | 3.6 : 1 | |
| Light, full bloom | 12.3–12.6 : 1 | 3.1–3.2 : 1 (bg ≥ 0.569) | ≥ 7, ≥ 3 (bg ≥ 0.55) |
| Light, night | 12.3 : 1 | 3.1 : 1 (bg ≥ 0.566) | |

The light appearance clears the grey-line limit by very little, on purpose: the top band is as
deep as the rule allows.

Ground below the top band (medians of 12 pt blocks in dark, 6 pt in light — areas, not points):

- **Dark, night (17:30–03:00):** lightest area 0.0070–0.0099 on cover and spread, ≤ 0.0091 on
  the iPhone (a card is 0.0116). At 03:00, with the moon low in the strip, 0.0117–0.0128 in the
  ring right against the moon's disc. Dark hush by day ≤ 0.022 (baseline 0.051). Dark bloom: the
  lamp's own glow in the strip reaches 0.19 (as the baseline's sun does).
- **Light:** darkest area on the cover 0.675 at hush, 0.42–0.47 at bloom and 0.46–0.47 at
  night (these are the cast shadows); mean 0.81 at hush, 0.69–0.72 at bloom, 0.69 at night. The baseline is
  0.63 / 0.56–0.58 / 0.40 darkest and 0.82 / 0.77–0.79 / 0.65 mean — so at bloom this sky is
  about 0.08 darker than today's below the band. On the spread the darkest thing is the tree's
  trunk (0.22, a 6 pt feature in the margin).

## Cost in the lab

`render()` on the spread at dpr 2, headless software canvas, raster forced inside the timing:
first frame ≈ 0.85–0.95 s; steady ≈ 9 ms sky alone, 25–35 ms with the card veil; a relight of
everything (the sun has moved half a point, or one 1 % step of an event) ≈ 0.55–0.75 s. Cover:
≈ 0.45 s, 14–18 ms, 0.3–0.4 s. The lab therefore plays an event (bedtime, opening) as a slide
show; the review's stills are exact.

## The SwiftUI port, layer by layer

Everything is paths, gradients, blurs and one tile; nothing needs a frame rate.

1. **Geometry** — eight crest polylines, six strips, the tree: the same splines and seeded
   noise in Swift, built once per display and season (or baked by a script next to
   `scripts/make_sky_textures.py`).
2. **Back sheet** — one rectangle through a ~30-line Metal `colorEffect` (two-stop vertical
   mix, belt and earth-shadow term, three lamp lobes, two moon lobes, in OKLab — the lab's
   GLSL chunk ports as is), or the 238 × 168 image the mock computes, redrawn when the sun has
   moved. Sun: `Circle` + `RadialGradient` + two hairline strokes. Moon: the app's
   `MoonPhaseShape` + a radial halo. Fibre: one 320 pt tile, drawn twice.
3. **Stars** — a `Canvas` in a `TimelineView` at ~12 fps, only at night: ≤ 400 dots with one
   resolved glow symbol.
4. **Each flat** — what I would build: bake the flat's *shape mask* and its *blurred shadow
   mask* once (they never change), and tint both at draw time with one small `layerEffect`
   shader that takes the lamp's position and the palette as uniforms (paper by depth, lamp
   falloff, lift toward the foot, the disc showing through, the rim from a pre-blurred edge
   channel). Relighting is then free; what is cached is static. Parallax is `.offset` per layer;
   the pop-up is a per-layer shear (`CGAffineTransform(a:1, b:-k, c:0, d:1, …)`) on the leading
   half.
5. **Scraps, fireflies** — `Canvas` in the same timeline, ≤ 60 small paths.
6. **Card veil** — a blur and tint on the sky masked by the cards' frames (anchor
   preferences); static, so cached.

**Riskiest part:** memory and the bake. Fifteen full-width layer masks at 3× is large if kept
whole (a spread flat is 2853 px wide); each flat only needs the band from its crest to a little
under the next crest but one, which brings it to roughly 15 MB at 2× — that cropping, and
keeping the hand-tuned OKLab palettes identical once they live in a shader's uniforms, is where
the port can go wrong. The mock's own route (CPU colour fields + cached bitmaps relit every
half-point of sun) would work but relights too slowly during an event.

## Unresolved — most serious first

1. **Dark night is the weakest state for the idea.** Under the "nothing lighter than a card"
   rule the land is relief at the edge of visibility; on the cover at 21:00 the strip is a
   starfield with a moon, and "paper" barely reads. The pricks and the moon carry it.
2. **The clouds are the weakest drawing.** Long torn strips are right for the slits, but as
   shapes they are generic; on the bare panorama a strip seen whole has a lens look.
3. **The near land (flats 4–8) is calm to the point of plain** on the bare panorama: evenly
   rolling, no feature on the phone page. It is meant to sit under cards, but the Duo opening
   and bedtime show it whole.
4. **Light bloom is darker than today's sky below the band** (mean ≈ 0.70 against ≈ 0.78;
   shadows 0.45). Cards read well on it; it is not "close to #F2F2F7" in the strict sense.
5. **A lamp behind the header text is dimmed, which is a patch.** The moon climbing past the
   name (about an hour each evening) is a dull disc; the lane above the name is tight (a 20 pt
   moon in a 27 pt gap), and tighter on the iPhone.
6. **The iPhone gets a small version:** the stage is one peak in the header, the sun sets
   behind and under the gear, there are no clouds, and the season shows only as paper colour in
   the margins and through the glass.
7. **Seasons on the cover are colour and scraps only** — the tree lives on the spread. Spring
   and summer differ little in a sunset frame.
8. **Sunrise on the cover is mostly hidden** (the sun comes up under the Today card's corner).
9. **Events are not real-time in the lab** (see cost).
10. Not done: a rare shooting star; mist moving in the valleys. Paper thickness is only a
    hairline and a contact shadow; the fibre is deliberately faint and nearly invisible in the
    light appearance.
11. **A deviation from `season()`:** on winter days with `snowfall = 0` a few flakes still
    drift (so the review's January shows paper snow). And the two or three brightest stars'
    halos (12 pt across) are lighter than a card at night — points, but large ones.
