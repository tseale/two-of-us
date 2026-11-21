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
