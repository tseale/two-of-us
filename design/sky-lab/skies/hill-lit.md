# Hill, lit

`skies/hill-lit.js` (+ `skies/hill-lit/place.js`, `skies/hill-lit/tree.js`) · shots in
`shots/hill-lit/review/` (`node tools/review.mjs --sky hill-lit --jobs 2 --timeout 120`)

## The idea

Picture book's place, standing in True light's air. One knoll with one grown tree on it,
the hills falling away behind, a river valley on the far page — drawn by hand as numbers,
never noise — and one light that everything answers: the twilight leans toward the sun,
each plane of land takes its colour from the sky at the horizon and sinks into the valley's
air, mist lies level between the planes, the river carries what light is left. And one
camera: at rest the horizon crosses the middle of the Duo's strip; at bedtime it looks up,
the land sinks to the foot of the display with the tree small upon it, and the sky that was
above the top edge comes down with every night of his life on it.

It starts from `true-light.js`: the same table of twilight by the sun's altitude, printed
twice (high-key for the light appearance, low-key for the dark), in one fragment shader.
What changed: the seven value-noise ridges are eight designed planes read from a table;
the cloud bank is a few designed forms; there is a valley floor with a river; the shader
answers to a camera; and a 2-D canvas above it carries the tree, his stars, the ring,
tonight's star, the caption and the season's small life.

## Composition and camera

World coordinates are points with x = 0 at the anchor window's leading edge and y the
display's y at rest (`place.js`). The camera is two numbers, `(dx, dy) = (−turn, rise) · look`:
every plane is the same picture slid by them, the near planes a little further down.

| | Duo (cover and spread) | slab iPhone |
|---|---|---|
| horizon at rest | y 292 (the gap under the Today card; the middle of the strip's window) | y 140 (the header is a small landscape) |
| horizon looking up | y 600 | y 768 (the capsule is at 791) |
| the turn | 79 pt toward the tree | 38 pt |
| tree at rest | x 396, foot y 281, crown x 364–430, top y ≈ 217 | x 285, foot y 127, in the gap between his name and the gear |
| tree looking up | x 317, foot y 589 (the capsule begins at x 392) | x 247, foot y 755 |
| near planes | sink 40 / 90 / 150 pt further than the horizon | 30 / 70 / 120 / 170 pt |

- **The strip is the stage.** The tree stands at x 396 so that its crown ends at x 430: the
  sun, which sets at x 447, spends its last quarter of an hour kissing the outer twigs and
  goes down behind the far ridge just right of the knoll. The moon sets through the same
  place. Tonight's star is lit at (439, 201): above the tree's right shoulder, below the
  status icons even with a sleep running.
- **The spread's phone page is the cover's picture** in both poses: the same world, the
  same camera, and a dither counted from the anchor window's corner. Measured on bare
  shots: no pixel more than 2 levels apart at rest or looking up.
- **The river valley** is world x < 0, the leading page. The far range has a gap; the
  river comes through it, shows a bend in the fold gutter (x −36, 70 pt below the horizon),
  swings back under the leading cards round a low hill, and comes down the leading margin
  column as a broad reach (x −446…−462, 212–268 pt below the horizon) before it leaves by
  the foot band. A wooded hill stands on the far bank in the margin column; pollards and
  poplars stand along the water. The knoll's side of the valley ends at the fold in one
  rounded bluff.
- **Sun and moon** keep the baseline's clock and x. Their height is the real altitude on
  the tall sky: the low sky is opened out (1.7° is 30 pt up, 7° is 63 pt, 30° is 186 pt);
  from 30° a body is above the frame at rest — you see it when the camera looks up — so
  nothing bright ever stands in the Duo's header. On the slab the header *is* the visible
  sky, so a low sun or moon shows in the gap beside the tree, and its disc fades where it
  would stand behind his name or age.
- **The moon's track is not extended** onto the leading page (its x there would no longer
  be the baseline's); the river carries its light instead — a sheen and a broken path of
  glints that lean toward the moon's side.

## What answers what

| | |
|---|---|
| bloom / hush | `presence(state)` per pixel in the shader (the lab's rule, as true-light ported it), and the same numbers in JS for what the canvas draws. Shaped by the hour in the light appearance: by day today's hush; at night it keeps half its lilac and its depth. Sun and moon discs are never hushed. |
| light and dark | two prints of one table. Dark: the long day is slate-blue, not black, so the tree reads at noon; golds lean to apricot and ember; mist and haze lose their yellow (rose-gold, never mustard). Light: luminous pastel; the tree is a slate-plum silhouette. |
| his stars | `nights()` mapped over the whole sky the looked-up pose shows (the anchor window's width, shifted by the turn; 600 pt tall on the Duo, 768 on the slab), a little denser in the strip's column and in the band the header shows at rest, squeezed above the skyline, then each moved — judged only against earlier nights — out of the header's words, the avatar, the gear, the status column, the capsule, the tree, the caption, and off any earlier star. Counted with `measure --stars-by-age`: looking up, all 142 on every device; at rest 61 on the Duo, 41 on the slab. |
| tonight's star | drawn when `state.tonightLit`, beside the tree, on the tree's plane, so it rides the move with it; a small warm four-point with a tight halo (it never makes an area lighter than a card). |
| seasons | `season(state)` → the land's albedos in the shader (straw, green, frost, snow lit and shaded, the woods on two crests) and the tree's dress: bare with a thin frost line and a few last leaves; snow lying along the upper side of the limbs over a pale knoll; blossom; a full crown in masses that follow the limbs, three tones; amber and thinning, leaves on the ground. Fireflies under the tree from dusk; petals, leaves, snow in the air. The river's trees dress the same way. |
| bedtime | `look` from the event: 0 until 0.3 s, eased to 1 by 2.4 s, held to 5.3 s, back by 7.5 s (`look=` in the URL overrides). Tonight's star follows `ignition()`. From 1.9 s a soft ring leaves it and crosses the sky once; each star swells as it passes and settles a sixth brighter. In July, with the sun still up, the stars show only as the ring passes. "✦ Night 143" stands at the foot, away from the tree, from 1.9 to 5.7 s. |
| opening the Duo | the presence swell, and one slow thing: the mist on the river is thin when the page arrives and fills with light from the fold outward over 1.25 s. |
| light appearance at night | a periwinkle-lilac page (the deepest the grey line allows), the land in soft slate with paler mist, the river paler still, each star a clean white point in a small breath of deeper sky, the tree in slate. |
| motion | clouds form, drift 14–40 pt in ~10 minutes and thin away again where they began (so none wanders across his name); mist drifts in the valleys; the river's glints shimmer; twinkle; fireflies; a rare shooting star. All of it at ≤ 12 fps. |
| Reduce Motion | nothing moves; at bedtime the looked-up still cross-fades in over the rest view and out again (two passes blended), no ring, the stars simply shown. |
| tilt | per-plane offsets: sky 1 pt, far range 1.4 pt … nearest hill 13 pt; the tree rides its knoll. |

## Cost

Headless Chromium here draws WebGL in software (SwiftShader, 4 shared cores), dpr 2, with a
read-back forced so the GL work is inside the clock:

| | first frame | steady frame | a frame during the bedtime move |
|---|---|---|---|
| spread 1902 × 1338 | 1.4 s (≈ 0.9 s compiling) | 0.43 s | 0.35 s |
| cover 932 × 1356 | 1.2 s | 0.17 s | 0.15 s |
| slab 804 × 1748 | 1.4 s | 0.24 s | — |

Everything outside the shader — palette, ~70 uniforms, the canvas (≤ 500 star sprites, the
tree's cached sprite, the small life) — is 1–4 ms. Growing the tree once is ≈ 40 ms;
repainting its sprite (a new minute's light) ≈ 5 ms. None of this is a GPU number.

## The port

1. **Palette and camera** — pure Swift: `KEYS`, `print`, `palette()`, `bodyAt()`, the
   tables in `place.js`. Recomputed when the minute changes; per frame during an event.
2. **The planes** — one Metal fragment function (`colorEffect`), the GLSL line for line.
   Because every plane is the same picture slid by the camera, the app need not shade per
   frame: render **three layers once** — the tall sky (W + turn wide, 600 pt tall), the far
   land with the valley and the knoll, the near hills — each `drawingGroup()`ed, and animate
   their `offset` for the bedtime move; bloom and the room's dimming are `opacity` between
   two renders or a `colorMultiply`. Steady state is a re-render when the minute changes, or
   at 10 fps while mist and cloud drift is on screen.
3. **The tree** — `tree.js` is a build script: wood, lit rim, three leaf tones, blossom,
   snow, frost, last leaves as mask images (five seasons), tinted by the hour. Here it is a
   cached sprite.
4. **Stars, ring, tonight's star, small life** — one `Canvas` of sprites in a `TimelineView`
   at 10–12 fps, at night or in season only; the caption is a `Text`.
5. Unchanged: flat page under Reduce Transparency / Increase Contrast, hidden from VoiceOver.

**Riskiest:** the one thing that is not a plane — the soft limiter that keeps the sky quiet
behind the header's words (it is in screen space, so it cannot be baked into a sliding
layer). In the app it must either stay in a final cheap pass or become a designed patch of
the sky. Second: the shader's colour must land in SwiftUI's working space exactly as it
lands in sRGB here, or the measured limits move (true-light's risk, inherited).
