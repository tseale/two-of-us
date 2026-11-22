# Port inventory: "the painted hill" (sky lab mockup to SwiftUI)

> The mockup turned into a port inventory: every drawn element, the camera, the palette, the events.
> Written on 22 Nov 2026 by a read-only agent, against the branch at about commit `cd2b979` (the app as `origin/main` `3583e43` plus the sky lab). Line numbers are from that day and will drift. It is working context for building the painted hill (`docs/SKY_BUILD_PLAN.md`), not a maintained document.


## 0. Sources, and what I did not read

Paths (abbreviations used below):
- **BRIEF** = `design/sky-lab/BRIEF.md` (main checkout, branch at 8189336), read in full.
- Worktree root **W** = `design/sky-lab` (HEAD 4ea7dea).
- **MD** = `W/skies/hill-painted.md` (1,511 lines), read in full.
- **HP** = `W/skies/hill-painted.js` (4,464 lines), read in full except the body of `paintRiver` (HP:1943-2396), where I read only its comments and palette lines.
- **AIR** = `W/skies/hill-painted/air.js`, read in full.
- **TREE** = `W/skies/hill-painted/tree.js`: read 1-80, 262-300, 410-470 and the comments of 470-833. Not read: the growth algorithm (80-262) and `leafAt`/forms (300-410).
- **CORE** = `W/lab/core.js`: read 30-130 and 240-565 (displays, the night rule, layout estimate, state). Not read: the viewer half (567-1277).
- **PRES** = `W/lab/presence.js`, read in full. Also read because the sky depends on them: **NIGHTS** = `W/lab/nights.js` and **SEASON** = `W/lab/season.js` (in full), `W/lab/oklab.js:110-114`, `W/lab/palette.js:238-241`.
- Not read: `lab/chrome.js` (the mock UI), `solar.js`, `noise.js`, most of `palette.js`, `README.md` beyond two excerpts, `tools/*`, shots, gallery, and the Swift (`SkyBackground.swift`). The lab was not run. Every measured figure below is the mockup author's, quoted from MD.
- Deployment target is **iOS 26.0** (`project.yml:4-5`), not CLAUDE.md's "iOS 17+".

**Three things in this worktree the port must not copy as written:**
1. **`standsOpen` is withdrawn by the sign-off** (BRIEF:362-370). In code: the function HP:1127-1145; its uses for the moon HP:4009 and the sun HP:4079-4080; the halo held to a quarter where the disc is hidden HP:4032; the switches `discAsIf` HP:3997-3999. Stale prose that follows from it: MD:255-283, MD:660-684, the `standsOpen` half of port note 4 (MD:1085-1096), "Still not good enough" item 1 (MD:1242-1249), the doubled gate measurement (MD:856-873).
2. **The lab's night rule has no 4 am bound and starts at sunset in winter.** `nightHours` is true from 18:00 or sunset, whichever is earlier, until first light (CORE:309-318). BRIEF says "between 6 pm and 4 am" (BRIEF:238-241). A 17:00 November sleep or a 05:00 sleep is "the night's" in the lab and not by the brief. Needs a decision.
3. **The lab's way of changing tone during events** (a brightness/saturate filter over painted layers, HP:4310-4343) is explicitly not to be ported (MD:1144-1166).

---

## 1. The world and the camera

**Coordinates.** Points. World x = 0 at the anchor window's leading edge (`state.phone.x`); world y = the display's y in the rest pose (HP:39-42).

**Displays** (CORE:39-61):

| | size | anchor window | strip |
|---|---|---|---|
| cover (closed Duo) | 466 x 678 | x 0, width 466 | 84 pt trailing |
| spread (open Duo) | 951 x 669 | x 485, width 466; fold crease 475.5 | 84 pt trailing |
| slab (iPhone) | 402 x 874 | x 0, width 402 | none |

**Windows on one world.** Cover and spread use one hand-set world, `DUO` (HP:104-206), chosen by `state.strip` (HP:545). The spread's phone page is the cover's picture and the world runs on to the left to world x about -520 (HP:549). Everything is laid on a world grid so the two match: plane edges on multiples of 4 pt (HP:549, 616), gradient stops at multiples of 30 pt of world x (HP:1531-1538), dither and grain offset by world x (HP:1017, 1877, 4419). The spread is 9 pt shorter than the cover. **The slab is a separate hand-set arrangement** (`SLAB`, HP:208-258): its own crests, no river, no rest-pose clouds.

**Hand-set constants per display** (HP:106-126, 210-229):

| | Duo | slab |
|---|---|---|
| horizon at rest `H0` | y 292 | y 140 |
| looking up lowers it by `D` | 312 (to 604) | 630 (to 770) |
| the turn `T` (far world slides left) | 90 | 30 |
| sky table span (`e` = 1) | 292 pt | 146 pt |
| `Emax` (zenith height for sun/moon) | 500 | 620 |
| tree | x 408, 88 pt tall | x 286, 62 pt tall |
| sun / moon radius | 11.5 / 9.5 | 9 / 8 |
| star scale | 1 | 0.9 |
| tonight's star, rest | (379, 194) | (262, 66) |
| tonight's star, looking up | (412, 270) | (270, 100) |
| first night's star, looking up | (262, 43) | none |
| caption | (30, 652), 15 pt | (26, 774), 15 pt |

**Planes** (far to near), with what they carry and how they move (HP:127-152, 230-250, 704-710, 725):

| plane | sink x D | slide x T | Duo travel (down, left) | tilt x, y (pt at tilt +-1) |
|---|---|---|---|---|
| sky (with clouds, stars, sun, moon) | 1 | 1 | 312, 90 | -1.2, -0.6 |
| far (ridges, valley floor, river) | 1 | 1 | 312, 90 | 1.0, 0.5 |
| mid (the hill) | 1 | 1 | 312, 90 | 2.0, 0.9 |
| knoll (and the tree, a layer over it) | 1 | 1 | 312, 90 | 3.0, 1.3 |
| near | 1.12 (slab 1.1) | 1.1 | 349.44, 99 | 5.0, 2.0 |
| fore | 1.3 (slab 1.25) | 1.25 (slab 1.2) | 405.6, 112.5 | 8.0, 3.0 |

Slab travel: 630 down, 30 left; near 693, 33; fore 787.5, 36.

- **Planes only translate; nothing is repainted for the move** (HP:30-33; MD:131-134).
- **Pixel grid:** each plane's whole travel is rounded to whole device pixels so it rests on the grid (HP:704-710). Between poses, offsets are fractional and drawn smoothed (HP:714-724).
- **Easing:** quintic `t^3(6t^2-15t+10)` (HP:650).
- **Durations** (HP:653-666; PRES:90):
  - bedtime: 0 until 0.3 s, up by 2.4 s (Duo) or 2.7 s (slab); peak 286 / 497 pt/s (MD:646);
  - `arrive`: 0 to 2.5 s;
  - `settle`: 1 until 0.1 s, down by 2.7 s.
- **Looking up is a state, not a moment:** `look` = 1 while the night has begun, else 0 (HP:646-667).
- **Tonight's star is on no plane:** a straight-line lerp in display points between its two homes, by `look` (HP:692-699).
- **Sun and moon** have one place in the world (HP:742-745, 785-796):
  - height over horizon = `Emax(1 - e^(-alt/45)) + 12(1 - e^(-alt/2.5))` pt; 8.5 pt per degree below it;
  - x = baseline fraction x anchor width, minus `T` x look. Baseline x is 0.04 at rise to 0.96 at set (`palette.js:238-241`), continuing off-screen at night (CORE:269-278);
  - a high body is above the rest view and comes down with the sky;
  - **slab exception:** on the setting side under 12 degrees, x is brought left by 62 pt (sun) or 46 pt (moon), fully by 6 degrees (HP:757-762, 224).
- **Tilt/parallax:** the table above; `state.tilt` in -1...1 per axis (HP:3926-3927). The brief also mentions scroll parallax (BRIEF:32-34); the mockup has none.
- **Reduce Motion:** no move. Both poses are composed and cross-faded over 0.6 s (HP:4402-4408; PRES:100).

---

## 2. Every drawn element

**Draw order** (HP:3924-4271, then 4414-4425): sky plane; stars and leading-page stars; shooting star; moon halo and disc; sun halo and disc; clouds; land (per plane: its mist behind it, the plane, the tree on the knoll, river light on the far plane, the sun's haze on the mid plane), with the snow shade over it; sun glare; fallen leaves and fireflies; tonight's star and the band; snowfall; caption; text guards; grain.

**Cadence, as the mockup keys it:**
- **G** = once per display and scale (HP:4281-4294).
- **S** = once per season state, rounded to 1/40 (HP:4304).
- **M** = repainted when the "minute key" changes: sun altitude by 1/8 degree, sun x by 0.5 pt, moonlight, lamp place, presence by 1/120, depth by 1/60 (HP:4307-4309, 4345-4355). At the lab's own figure for the sun's climb near first light (a sixth of a degree a minute in November, CORE:303), a 1/8-degree step is roughly every 45 seconds (my arithmetic).
- **F** = every frame, from the animation clock.
- **E** = only during an event.

**Cost** is from MD:975-1042 (headless Chromium, software raster, scale 2, loaded machine: "ranges, the same order").

| # | element | inputs | cadence | how the mockup draws it | size | lab cost |
|---|---|---|---|---|---|---|
| 1 | **Sky field** (HP:952-1033; AIR:247-398) | sun altitude, sun x, appearance, morning, presence, depth, moonlight | M | Tall plane sampled in OKLab on a 2 pt grid, bilinear to device pixels, one-level TPDF dither. Includes the sun's glow in the air (HP:977-982), a warm column at 2.5-17 degrees (HP:966, 983-987), brush-drag noise (HP:989-990), the night horizon band kept under the dimmed room (HP:962, 994) and a small lift behind the crown (HP:969, 995-998) | Duo 660 pt tall, slab 826; width cover 663, spread 1147, slab 521 pt (HP:549-552, 608-610) | 0.10-0.17 s cover, 0.17-0.22 s spread per repaint: "the one per-pixel pass" |
| 2 | **Sun disc** (HP:4049-4097; AIR:148-161) | altitude, place, `seen`, appearance, text and button clearances, tonight's star during a move, cards (to be dropped) | place M; opacity F during events | Wobbled 64-gon path, flat fill. Dark: its own colour by altitude. Light: pale cream plus a 1.2 pt apricot inner edge (radial gradient) | r 11.5 / 9 | negligible |
| 3 | **Sun halo** (HP:1158-1210, 4062-4069) | as above, presence | M (sprites kept) | Two blurred discs at 3.3 and 1.95 radii, alpha 0.22 / 0.34, blur 1.4 pt; light set deeper and softer (blur 6.5 / 3.2). Painted once into sprites, tinted | about 76 pt across (Duo) | Was 9x a frame through a per-frame blur (34-92 ms); as sprites 3.6-8.5 ms |
| 4 | **Sun's haze over the far land** (HP:3903-3919) | sun x, glow amount, altitude | M | Radial gradient r 150 pt, squashed 1.7 x 0.3, clipped to a 70 pt band at the horizon, drawn after the mid plane | 510 x 90 pt | in land composite |
| 5 | **Sun glare** (HP:4216-4265) | altitude, skyline under the sun | M | Radial gradient r = 4.6 (dark, additive) or 3.4 (light) sun radii, over land and tree. Withdrawn from the land as the disc centre goes from 1.6 to 0.6 radii above the skyline, clipped to a skyline path with a 10 pt let-go | about 106 pt across | negligible |
| 6 | **Moon** (HP:1214-1294, 4005-4047) | phase fraction, bright-limb rotation, altitude, sun altitude, sky colour behind it, text clearance | sprite M | Whole disc barely there; lit part as a two-arc phase path in cream; two soft ellipses for the seas | r 9.5 / 8; sprite 6r square | negligible |
| 7 | **Day moon** (HP:1235, 1265-1267, 1277) | sun altitude -3 to +7 degrees | M | Same sprite; colour goes to a pale tint held within 1.15:1 of the sky; soft limb (0.85 pt blur); no halo | same | same |
| 8 | **Moon halo** (HP:4032-4042) | nightness, phase, `seen`, look | M | Two soft sprites at 5.2 and 2.6 radii. Dark alpha 0.05 / 0.09, up to 2.3x fuller looking up; light 0.5 / 0.7 | about 99 pt across | negligible |
| 9 | **His stars, ordinary nights** (HP:3269-3408) | age, stars-out (sun altitude), twinkle, depth, horizon distance, moon place, tonight's place during a move, band, appearance, density | layout G plus age and layout; draw F | Dot sprite. Dark: four tints (cool, plain, warm, rose) and a small glow on the brightest. Light: crisp white point, the brightest on a soft dusk patch. Thinned and laddered once dense (180 to 330 nights; HP:3265-3266, 3325, 3385-3398) | radius 0.52-1.15 pt, peak luminance capped 0.85 (HP:268, 3377-3378) | steady frame 3-10 ms for the whole composite; 368 of his plus up to 460 ordinary on the spread |
| 10 | **Month-night stars** (HP:3340-3373; NIGHTS:34-36, 56-60) | as 9, plus cards where they are (glass), moon | F | Four-point polygon sprite, arms 10 / 7.2 / 9.3 / 6.9 pt with a 1.6 pt core, in tonight's cream at half warmth. Becomes a round point under glass or within 40 pt of the moon | about 9.5 x 13 pt | with stars |
| 11 | **First night's star** (same code) | as 10 | F | Same mark, larger, warm tint. Own hand-set place on the Duo | about 11.7 x 16 pt (MD:502) | with stars |
| 12 | **Tonight's star** (HP:3415-3469, 679-699) | night-has-begun, event, look, sun altitude, appearance | F | Hair-thin four-arm sprite (arms 12.5 / 8.6 / 11.4 / 8.2 pt, core 1.55 pt). Looking up: 1.42x, plus a second copy rotated 45 degrees at 0.44 scale. Dark: two tight warm glows (12-15 and 6 pt). Light: ivory on a 26 pt dusk patch. Breathes on 5.2 s. Drawn over everything | about 25 x 17 pt at rest, 35 x 24 looking up | negligible |
| 13 | **Leading page's ordinary sky** (HP:3084-3107, 3194-3255) | age (count 80-460), fold, title rect, lead, band, open event | layout G; draw F | Fainter dots in three tints; never drawn inside the anchor window; answer the band only within about 75 pt of the fold | r up to 1.05 pt | with stars |
| 14 | **Shooting star** (HP:3655-3680) | clock, dark only, stars-out at least 0.9 | F, rare | 1 pt gradient line, 90 pt travel, 1.1 s, once per 140 s. None under Reduce Motion | 30 pt tail | negligible |
| 15 | **Bedtime band** (HP:3122-3137, 3470-3542) | bedtime event age, tonight's looked-up home, anchor window | E | Radial gradient with a 13-stop profile, masked by a vertical gradient (ends 22-150 pt above the horizon) and a conic gradient (full on the bearing to the middle of the open sky, gone 80 degrees either side). Drawn at quarter size and enlarged; additive in dark | width (54 + 0.14R) x 1.8 pt; peak alpha 0.068 dark, 0.275 light | held bedtime frame 11.8 ms cover, 23 ms spread |
| 16 | **Caption** "Night N" (HP:3684-3708) | veil, event age, look, age | E | Small four-point glint plus text, semibold rounded 15 pt. N = whole days + 1. In the app: a SwiftUI `Text` | Duo (30, 652); slab (26, 774) | negligible |
| 17 | **Clouds** (HP:188-205, 252-257, 1318-1511, 4099-4183) | sun altitude, lamp side, sky behind, appearance, stars-out, look, header text rects, strip window and sleep state, card rects and opacity, sun and moon discs | masks per lamp side (5 values); paint M; place F | Each: one hand-set top contour; five alpha masks (body, lit top, lit side, underside, rim), tinted, each paint held to a contrast of the sky behind it (`heldTo`, HP:280-288). At night a veil of the sky itself over the stars inside the silhouette | strip 98 x 10; gap 62 x 9; bank 100 x 20; bar 250 x 13; looked-up bar 176 x 11 (also the slab's only one) | masks 0.01-0.03 s for all |
| 18 | **Land planes** (five) (HP:1627-1885) | palette (ground, haze by x, lamp, rim), season, deep night, crest tables | M | Per shape: a path filled with a horizontal gradient (stop every 30 pt); soft ridges and melting feet cut small and enlarged; grass blades along near crests (one per 0.55 pt, clumped); a quarter-size wash (air at the foot, a 210 pt blurred stroke of shade and one of light for the flank's turn, crest strokes of shade and light, frost or snow); a rim stroke through a dry-brush mask; mottle. Dark full night: painted 4x bright and dithered down once (HP:1590-1621, 1873-1883) | display-wide; down to display foot + 20 pt | 0.22-0.42 s cover, 0.64-0.73 s spread; night dither about +0.05 s. "Riskiest": about 45 blurred strokes |
| 19 | **Knoll** | as 18 | M | The plane the tree stands on: rim 1, grass 1. Under a moon it alone carries a thin cool rim (HP:1836) | crest peaks at (408, 296.5) Duo | in 18 |
| 20 | **Tree** (TREE; HP:2522-2750, 3772-3782, 3854-3860) | season; lamp direction and power; appearance; "burns" (sun or moon behind it, HP:4366-4374); look and the phone page's cards' opacity | masks S; paint M; opacity F | White alpha masks cut from one tree grown from a fixed seed (20260702, TREE:59), tinted and composited. Opacity = `1 - smoothstep(0.05, 0.45, look) x cards' opacity` | 88 / 62 pt tall; mask 1.4H x 1.2H (TREE:421-424) | masks 6-14 ms bare, 45-110 ms in leaf; paint 8-16 ms bare, 25-37 ms in leaf |
| 21 | **Tree: bare** (default day) | frost, leaf fall | S/M | wood, twigs, a frost hairline (cleaned inside forks on the pale page, HP:2722-2736), last leaves | | |
| 22 | **Tree: in leaf** (TREE:295-470; HP:2661-2708) | foliage, leaf hue, backlight | S/M | 17-19 masks: far side, twigs in sight, near masses in three paints, leaves by turn in eight directions, thin leaves, gaps. About 6,300 leaf marks in a full crown inside eleven hand-set convex masses (MD:591-596). After sunset in dark, autumn leaves on the sunset side stay gold (HP:2687-2694) | leaf marks 1.2-2.9 pt | |
| 23 | **Tree: blossom, snow** | blossom, snow | S/M | Blossom in two masks; snow cap with a blue foot (cap minus itself shifted 0.5 pt, HP:2739-2749); snow hairline on twigs | caps 1.5-2 pt | |
| 24 | **Mist** (HP:393-408, 489-541, 2403-2518, 3845-3852, 4189) | palette by x, mist amount (HP:903), deep night | paint M; offset F | Valley side: level bands from one 2048 x 48 pt texture with a gradient tint. Hill side: pooled masks computed from the crest in front (4-23 pt deep). Breathing offset +-16 pt (bands) or +-7 pt (pools), period 240 + 37 x seed seconds, in quarter-point steps. Dark night: held to OKLab L 0.198 (HP:266) and dithered | Duo: 4 bands, 3 pooled layers; slab: 4 bands | in land |
| 25 | **River** (spread only) (HP:161-167, 1892-1926, 1936-2396) | palette, lamp, moonlight, deep night | M (part of the far plane) | Banks by projecting a hand-set centre line onto a ground plane; a fill mirroring the low sky; a far-bank reflection in a few ribbons; one upright smear in the margin-column bend; level streaks on the near reach; four sheen strokes on the middle reach; glints; a sandbar; ten mist pools. Dark night: held to L 0.196 (HP:267) | near reach about 50 pt wide | 0.04-0.06 s |
| 26 | **Moon's path on the river** (HP:2268 area) | lit by the moon, moonlight above 0.05 | M | A scatter of short silver glints down the near reach; MD says "some forty", the loop runs 46. A convention, not geometry (MD:172-176) | each about half a point deep | in 25 |
| 27 | **Reeds** | palette | M | Two clumps in the leading margin column; blades 6-16 pt, leaning 5-12 degrees downstream, with reflections (MD:162-166) | | in 25 |
| 28 | **River's opening light** (HP:3867-3902) | open event age, look, night | E | Kept alpha layer (water plus mist puffs) tinted through a 65-stop vertical gradient: a crest runs from the far bend at 0.1 s to the page foot at 0.9 s (position proportional to run^2.2), holds half, gone by about 4.4 s. Additive in dark | river's box | negligible |
| 29 | **Fallen leaves, petals** (HP:3560-3591) | season, tree opacity, clock | F | Small ellipse sprite: 4-22 lying under the tree, up to 7 adrift (30-46 s falls) | 0.7-1.2 pt | negligible |
| 30 | **Fireflies** (HP:3593-3625) | season (June to mid-August, SEASON:84), sun altitude under +3.5, depth | F | 12 by the tree plus 14 over the anchor window's land plus the leading page's own. Glow sprite 5.5 pt and a 1.5 pt core; blink 3.6-6.8 s; drift +-5 / +-3 pt; ride the knoll's offset | | negligible |
| 31 | **Snow on the ground** (HP:889-901, 1669, 1819-1826) | season snow (mid-December to early March, SEASON:78), sun altitude | M | Ground mixed 92% to a snow shade; a blurred stroke of lit snow along each crest. Dark: palest thing on the land, a step deeper on the mid, near and fore planes | | in land |
| 32 | **Snow under glass tiles** (HP:264, 3795-3836) | dark and snow; tile and sleep-card rects and opacity; hour | M/E | One soft-edged black rect over the land only, from the first glass tile's top to the foot, 12 pt feather; amount from the snow's lightness against a 0.029 cap | | forces a land recompose each frame of the opening |
| 33 | **Slab: shade behind the name in snow** (HP:1654, 1672-1674) | dark, slab, snow | M | The mid hill capped at L 0.345 under the words, returning over world x 196-256 | | free |
| 34 | **Snowfall** (HP:3630-3652) | snowfall amount (about two winter days in five, SEASON:89-93), clock | F | Flake sprites fixed to the display: count = width x height / 620 x amount (cover about 510, spread about 1,030, slab about 570 at 1.0); fall 6-26 pt/s | radius 0.55-1.55 pt | not separately timed |
| 35 | **Dimming while he sleeps** (`depth`) (PRES:143-157; AIR:262-280) | sleep kind, event age | E, then constant | Not a layer: every colour passes through `show()`. Dark: L x (1 - 0.14 depth), chroma x (1 - 0.12 depth). Light: L - 0.012 depth, chroma x (1 - 0.25 depth). Also: twinkle amplitude x (1 - 0.6 depth) (HP:3147), stars +10% (HP:3156), fireflies -40% (HP:3621), solar bloom -35% (PRES:180) | | a full repaint per tone step in a still |
| 36 | **Text guards** (HP:3713-3756) | header rects, appearance, lead | M | Blurred rounded rect under each header line, darken blend (caps L 0.43 name, 0.36 age) or lighten (0.868); does nothing unless the sky is past the limit | rect + 16 pt | made 39-69 canvases mid-move before being fixed (MD:1022-1030) |
| 37 | **Grain** (HP:367-378, 4416-4425) | appearance | G | 512 px tile of black/white specks at up to 10% alpha, over the whole frame at 0.5 (dark) / 0.42 (light), fixed to the display | | negligible |
| 38 | **Dither** | | with 1 and 18 | Sky: one-level TPDF (HP:424-426, 1017-1027). Land: only at full night in dark (row 18). By day the land has a one-level "plaid", not visible at 1x (MD:1394-1396) | | |

**Whole-frame cost** (MD:980-989):

| | cover | spread | slab |
|---|---|---|---|
| first render | 0.64-0.85 s | 1.20-1.83 s | 0.53-0.90 s |
| steady frame | 3.2-8.2 ms | 6.2-10.6 ms | 3.0-5.8 ms |
| a new minute | 0.48-0.67 s | 0.95-1.16 s | not given |
| live bedtime move, per frame (before fixes; not re-measured) | 70 ms | 208 ms | 117 ms |

The untouched cost in a live move is the land's composite, which is "what a phone's `.offset` on kept layers does not pay" (MD:1022-1034).

### Star placement, in full (HP:2879-3110; NIGHTS:20-71)

**Inputs:** whole days of age; night-has-begun; display kind; header rects (name, age, avatar, gear, and the spread's title and subtitle); the strip window's x; the fixed card tables; the skyline and the crown's outline (`crownTop`, TREE:273-282); `T`, `D`. The layout is cached on exactly these (HP:2913-2915).

1. **Per night n:** u = frac(0.5 + n/rho), v = frac(0.5 + n/rho^2), rho = 1.3247 (the plastic number), jitter +-0.009 by an integer hash. Magnitude 0.22 + 0.5 x roll^2.6; month-nights 0.78; first 1; tonight 0.92. Month-night = every 30.4375 days in the lab; "the app would use his real date of birth" (NIGHTS:34-36).
2. **Places are in looked-up display points.** Rest-pose place = (x + T, y - D) (HP:3079).
3. **Boxes with densities** (a box's share is area x density; v picks the box and the height in it; u picks x through weighted columns). Duo (HP:2940-2946):
   - header gap x 207-313, y 7-97, density 0.85;
   - x 5 to strip+16, y 99-187, 0.80;
   - full width, y 187-312, 0.70 (strip column x 0.85);
   - y 312-400 (the rest pose's header band), 0.95, columns weighted 0.12 / 1.7 / 0.9 / 0.55;
   - y 400-594 (the rest pose's strip beside the tree), 0.70, columns 0.7 / 2.3 / 0.5.
   
   Slab: three boxes (HP:2947-2949).
4. **A slow drift** of every place: +-30 pt (Duo) or +-26 (slab), from two-octave value noise at 150 pt (HP:2968-2970). Reproducing places exactly needs the lab's noise lattice (HP:69-91).
5. **Floor:** 8 pt above the skyline, 5 pt above the crown, 12 pt above the horizon (HP:2924-2930).
6. **Keep-outs** (HP:2879-2905), in both poses:
   - the avatar, name and age block, padded 7 pt plus one em (13 pt) past the last glyph;
   - the gear, padded 3 pt;
   - Duo: the strip's furniture as hard-coded rects (y -10 to 192, the clock at rest y 14-44, the capsule y 388-652);
   - slab: y under 64.
7. **Spacing** (`free`, HP:3000-3021):
   - ordinary nights at least 5.6 pt apart;
   - four-point stars 9 pt further from words and buttons, 10 pt from every card edge in the fixed tables (HP:2982-2995), 80 pt from each other (falling to 60, then 44);
   - nothing within 30 pt of tonight's looked-up home (70 pt for four-point) or 17 pt of its rest home;
   - nothing within 18 pt of the first night's own place (60 pt for four-point).
8. **A taken place is cast again:** u += k x 0.618, v += k x 0.7549 for k up to 30 (ordinary) or 90 (four-point), then a spiral search (HP:3036-3056). Each night is judged only against earlier nights.
9. **Determinism:** pure functions of the night number; no random state. Earlier stars never move when a night is added, as long as the layout rects and card tables do not change.

**Rules that are drawn, not placed:**
- under a glass card a four-point star becomes a round point, wholly by the time the card is at a fifth of its opacity, eased over 7 pt at an edge (`underGlass`, HP:1099-1110);
- within 40 pt of the moon it is a point, four points again at 60 pt, by how strongly the moon stands in the sky, not by whether a card hides it (HP:3289-3292);
- stand-off from the moon: 14.5 pt ordinary, 32 pt four-point (HP:3297-3301);
- during a move every star within 14-30 pt of tonight's gives way (HP:3187-3191);
- stars fade in by brightness as stars-out rises; stars-out = `1 - smoothstep(-12, -4, sun altitude)` (PRES:182; HP:3311-3314).

**Counts** (MD:490-499): looking up, 143 on all three displays at age 142. At rest, 60 on the cover (39 in the open with cards on) and 28 on the slab.

---

## 3. The palette

**Colour space.** OKLab throughout. Colours are written as value / chroma / hue and "printed" per appearance (AIR:128-142). Out-of-gamut colours give up chroma, never hue (AIR:205-220).

**The table** (AIR:30-125):
- keyed by the sun's altitude: 30 degrees (copied to 15, so nothing turns above 15), 8, 2.5, -0.8, -4, -7.5, -11, -18;
- each key carries: a print range per appearance (L min, L max, gamma, chroma gain); two eight-stop sky columns (over the sun, away from it) with per-appearance overrides; the sun, the glow and its amount, cloud lit and shade for low and high cloud, mist, land per appearance, gain, rim and its amount;
- between keys: smoothstep on altitude, mixed in OKLab (AIR:248-253);
- dawn is the same table a little cooler: chroma x 0.88 and hue -7 degrees on warm hues (AIR:164-169);
- the sun's disc has its own five-key table (AIR:148-161).

**Vertical.** Ten elevation stops (0, .04, .10, .18, .29, .44, .68, 1, 1.5, 2.3 in table units; 1 = the top of the rest view), monotone cubic through them (AIR:171-190, 308-326).

**Horizontal** (distance from the sun in anchor widths; AIR:331-351):
- the bands stand tall over the sun and sink away from it ("the arch": width 0.60, far value 0.44);
- the away column takes over from 0.10 to 1.35 widths;
- the earth's shadow, slate at hue 268, beyond 0.95 widths after sunset.

**Land.**
- Each plane: season albedo (HP:803-813) lit by the hour (HP:878-882), mixed toward the horizon haze at that x by its `haze` (0.90 far to 0.05 fore; HP:1671).
- Dark at dusk: aubergine (HP:886-887).
- Dark full night: each plane its own value, L = 0.106 + 0.098 x haze^0.8, blue; everything capped at L 0.214 (HP:866-872, 1681, 1690-1695).
- Light by day: planes told apart by temperature (HP:1686-1689).
- Light at night: a paper wash down the page from 14 pt under the horizon (HP:1776-1783).

**Light versus dark.** Two prints of one table (MD:372-395).
- Dark: its own golden-hour column; dusky slate-blue by day (sky luminance about 0.03 overhead, 0.07 at the horizon); near-black with tints at night.
- Light: sky stops floored at L 0.876 (AIR:296-304; the comment there says 0.846, the code says 0.876); cream sun; warm-dark wood tree.
- Dark hue remaps: green-gold to gold, golds to apricot (AIR:136-140).

**The hush** (`presence`, 0 to 1).
- Sources (PRES:31-61, 168-184):
  - solar bloom = `(1 - smoothstep(2.5, 10, alt)) x smoothstep(-10.5, -4.5, alt)`, less 35% x depth;
  - a small moon bloom, up to 0.35, for a low, nearly full moon;
  - event swells: bedtime peak 0.55 (attack 1.6 s, hold 2.4, release 14); open 0.45 (0.5, 0.9, 5); close 0.15.
- Applied in `show()` (AIR:260-280):
  - dark: L x (1 - 0.12(1 - p)), chroma x (0.4 + 0.6p);
  - light: L pulled toward the page (OKLab L 0.9612) by 55% x (1 - p) by day, 10% at night; chroma x 0.2 at hush by day, 0.62 at night.
- Held above the hush on the pale page: the tree (presence at least 0.82, HP:2534), the water (0.56), clouds (0.6, HP:1475), the sun's halo and glare (0.6, HP:4057, 4219).

**Legibility gates** (BRIEF:395-410, 467-471; MD:842-934):
- text on the sky with no scrim: name at least 7:1, secondary line at least 3:1;
- light: sky luminance behind the grey line (`#6C6C70`) at least 0.55; ground below the top band stays near `#F2F2F7`;
- dark: at most 0.072 behind the grey line (`#98989F`), at most 0.10 behind the white name;
- dark at night: no area below the top band lighter than a card (`#1C1C1E`, luminance 0.0117; "at limit" from 0.0111). Points of starlight are exempt;
- the accents teal, periwinkle and amber are not borrowed;
- closest figures at sign-off: slab light grey line 3.27:1; dark night ground 0.0101 (spread, 03:00); dark grey line by day 0.043; tonight's star peak 0.889 with 82 pt^2 lighter than a card (MD:900-929).

**Carrying tone smoothly** (port note 10, MD:1144-1166):
- never multiply 8-bit layers on a near-black sky: no `.brightness`, `.saturation` or opacity ramp of a darkening layer. Measured in the lab: any factor under 1 drops every pixel a whole level;
- carry presence and depth as uniforms of the sky's shader, ahead of its dither;
- for the land: paint the tone the event starts from and the tone it ends at, and cross-fade the two dithered images;
- repaint off the main thread and swap in.

None of this has been built anywhere.

---

## 4. State and events

**The night rule** (CORE:286-336; BRIEF:303-333, 356-361).

One fact, *the night has begun*, drives both the pose and tonight's star (HP:634, 657, 682).

- True from the first start of tonight's night sleep, by any means, until first light.
- **First light** = the sun rising through -7 degrees (CORE:300).
- **"Night hours" in the lab** (CORE:314-318): while the sun is up, only the evening side from 18:00; from sunset to mid-night always; then until -7 degrees. So summer bedtimes before sunset count, as the sign-off requires (BRIEF:358-361).
- **Discrepancy to decide:** no 4 am end and a winter start at sunset, against the brief's "6 pm to 4 am" (see section 0).
- The lab has no sleep log: awake, it assumes the night began at a sample 20:10 bedtime (CORE:284, 322). That is a stand-in, not a rule.
- In the app: a pure function of clock, sun and sleep log; nothing stored; it persists across launches (MD:1168-1174).
- What the app must define: which sleeps are "night sleeps" (BRIEF:221-225), and "started by hand on this phone's Home".

**Events** (MD:737-753; HP:646-687; PRES:146-157; CORE:373-418):

| event | camera | tonight's star | room |
|---|---|---|---|
| `bedtime` (by hand; the night begins) | up 0.3-2.4 s (slab 2.7), stays | spark from unlit: `1 - e^(-t/0.55) + 0.35 e^(-((t-1.5)/0.9)^2)` (NIGHTS:83-89) | dims `smoothstep(1.2, 9)` |
| `arrive` (night sleep from elsewhere; the night begins) | up 0-2.5 s behind the cards; no veil, band or caption | fades in 0-0.8 s beside the tree, rises with the view | dims 0-4 s |
| `arrive` (night already begun, or a nap) | none | unchanged | dims to 1, or 0.45 for a nap, over 0-4 s |
| `wake` (any sleep, any hour) | none | unchanged | un-dims 0.3-5 s from that sleep's depth; no bloom |
| `settle` (first light, Home on screen) | down 0.1-2.7 s behind the cards | out 0.1-2.3 s on its way back to the tree | unchanged |
| `open` (the Duo opens) | none | none | bloom 0.45; river light by day, page's stars from the fold at night |
| `close` | none | none | bloom 0.15 only (MD:1400) |

- Misfits are dropped or downgraded: bedtime once the night has begun, or for a nap, plays as `arrive`. `settle` plays only while the sun is within 0.5 degrees above -7, about 3-5 minutes (CORE:304, 405-414).
- The full moment plays once a night (MD:730-734).
- Across a sleep's start or end, the strip's cloud and a disc under the icons follow the longer island over 0.6 s (HP:305-308, 3963-3976, 4125-4134).

**The bedtime moment** (PRES:88-101; MD:643-658), seconds since the tap:

| beat | Duo | slab | easing |
|---|---|---|---|
| cards fall back | 0-1.0 | same | smoothstep; port: `.easeInOut` (MD:1209) |
| view rises; star lit from the first instant, flare at 1.5 s, climbs to its window keeping 30 pt of dark | 0.3-2.4 | 0.3-2.7 | quintic |
| rest-pose clouds leave / looked-up cloud arrives | by look 0.1-0.55 / 0.35-0.85 | same | smoothstep (HP:4120-4121) |
| band leaves the star's looked-up place and crosses to the farthest corner | leaves 2.1, crossed 4.2 (276 pt/s) | 2.3, 4.3 (410 pt/s) | linear radius; strength in over 0.4 s |
| band's own light: held until the crest is 150 pt out, fullest about 0.42 of the way, gone at 0.9 | visible 2.75-3.80 | 2.80-3.85 | HP:3483 |
| each star swells as the crest passes (+45% size), keeps +22% light, which fades over 5.5-12 s | last star 3.85 | 3.88 | gaussian pulse (HP:3158-3167, 3318) |
| caption | in 2.0-2.8, out 4.15-4.6 | same | smoothstep, x veil^2 |
| cards return | 4.6-5.8 | same | `.easeOut(duration: 1.2)`, cubic (0, 0, 0.58, 1) (PRES:105-116) |
| tree goes with the cards' return | 4.6-5.8 | same | HP:3772-3782 |
| after | room dims to 9 s; bloom lets go over 14 s | | |

Whole: 5.8 s.

In a sky too light for stars (July): all his stars come up faintly from about 1.6 s at 0.34 strength, the band leaves them clearer, and they are let go as the cards return (HP:3171-3180).

**Reduce Motion** (PRES:94-100; MD:829-837):
- no move, band, spark, twinkle or drift;
- bedtime is about 4 s: cards out 0-0.6; looked-up still dissolves in 0.6-1.2; caption in 1.2-1.6, out 3.0-3.4; cards back 3.4-4.0;
- `arrive` and `settle` are a 0.6 s dissolve;
- tonight's star is drawn with the looked-up still only (HP:3419-3422);
- a returning card hides things no faster than the full moment's cards would (`leavingPace`, HP:1083-1088).

**A touch during the moment** (specified only; the lab has no touch; MD:724-728, 1208-1217): cards back in 0.3 s; band and caption out in 0.2 s; the view stays up and runs on at its own pace; the star stays lit. So cards, caption and band need their own cancellable animations.

**Overlapping events.** The lab carries one event at a time and snaps (the Duo opening mid-rise). The port makes `look` and `depth` their own animated values, each with a target, so a new target eases from wherever the value is (MD:1174-1179). On the open Duo both sky views need one shared driver (MD:1186-1189; BRIEF:217-218).

---

## 5. Layout dependencies

**Read live from the lab's layout** (must come from the real layout):
- anchor window origin and width, and whether there is a strip (HP:545-547);
- header rects (name, age, avatar, gear; the spread's title and subtitle), used for: star keep-outs (HP:2879-2895), cloud fade (HP:1514-1525), disc clearance (HP:1049-1073), text guards (HP:3713-3756), the leading page's stars (HP:3091, 3215-3234);
- the first card's top (default 88.6 Duo, 136.6 slab): where a body comes out from under the header (HP:789-793);
- the strip's clear window (x 362, width 104, top 151 awake / 185 asleep, bottom 396; CORE:449): discs under the icons (HP:3963-3980), the strip cloud (HP:4125-4134), the star boxes (HP:2939);
- every card's rect, kind and opacity. Kinds the sky distinguishes: header, strip, tab bar, toast, tile, sleep. Used for: tree opacity (HP:3772-3782), stars under glass (HP:1099-1110), clouds across an edge (HP:4137-4141), snow shade (HP:3795-3825), whether the strip is present (HP:3967), and the withdrawn disc rule;
- the leading page's opacity (HP:3148, 3717) and the veil for the caption (HP:3685-3691).

**Hard-coded numbers that must come from the real layout:**
- the composition itself: `H0`, `D`, `T`, tree x, every crest line, the cloud places (all tuned to the mock UI's header, strip and capsule);
- tonight's two homes, the first night's place, the caption's place (HP:112-114, 126, 216-217, 229);
- the card tables a four-point star keeps clear of, and which are glass (HP:123-125, 226-228). These must be measured once per layout in both night layouts, never from whatever is on screen (MD:1054-1059);
- the island's growth while a sleep runs, 34 pt (HP:300);
- star keep-out rects for the strip's furniture and capsule, and the slab's status bar (HP:2896-2903);
- star box coordinates (HP:2940-2949), including the header gap x 207-313 and x 116-232;
- the icon rules: a disc's top 16 pt clear of the icons, ramp 6 pt (sun) or 12 pt (moon) (HP:3968-3980); a cloud keeps 10-24 pt (HP:4130); the slab's status-bar foot y 58 (HP:789);
- the band's far corner uses the display foot as horizon + 74 (Duo) or + 104 (slab) (HP:3130);
- the slab's setting-side shift, 62 / 46 pt (HP:224, 760), set against a gear button at x 342-386;
- the slab's shade behind the name, world x 196-256 (HP:1654);
- the leading page: margin-column fallback `anchor x - 388` (HP:3204), fold fades at 10-75 pt left of the anchor (HP:3203, 3208), and the river's bends, reeds and smear composed for the margin column (x 0-97) and the gutter (x 447-505) (BRIEF:90-92);
- the caption lies across the sleep card's bottom edge (y 640-656 on the Duo; MD:726-728).

**Layout facts that change star places.** The star layout's key includes name and age widths (HP:2913-2914). A different name, Dynamic Type or locale would re-cast stars near the header.

---

## 6. The author's port notes, and the open items

**Port notes** (MD:1044-1227):

1. **Air:** about 250 lines of pure Swift (`skyAt`, `hazeAt`, `mistAt`). Free.
2. **Sky:** the only per-pixel layer. Either a small `colorEffect` shader (two ramp lookups, the arch, the sun's glow, dither, the night band) or an image filled off the main thread once a minute from the 2 pt grid.
3. **Stars:** `Canvas` with three symbols and one soft patch for light; `TimelineView` at 10 fps, night only. Places are cast from card frames measured once per layout. The glass and moon rules need the rows where they are, by anchor preferences, and a floor in time of 0.15 s.
4. **Sun, moon, tonight's star, band:** `Canvas` paths and radial gradients.
   - Band: one `RadialGradient` under a vertical `LinearGradient` and an `AngularGradient`, drawn small. The note says eleven stops; the code has thirteen (HP:3499).
   - Sun halo: pre-rendered, never a per-frame blur; two sets.
   - Glare: clipped to a skyline path.
   - The slab's `bodyX` shift.
   - **The `standsOpen` half of this note is withdrawn.** The icon rule stays in some form.
5. **Clouds:** five shapes (one on the slab), five alpha images each, tinted, held to the sky. Three hiding rules as pure functions of layout. A cloud is a child of the sky's layer.
6. **Land:** five `Canvas` layers repainted once a minute and kept (`drawingGroup`); camera = `.offset` per layer. OLED night needs the dither or a 16-bit layer. The snow shade under glass rows: check on a phone whether real glass needs it.
7. **River:** pre-render per minute as part of the far plane; the opening's light is one alpha image wiped by a gradient mask.
8. **Tree:** its own layer over the knoll's with one opacity; no mask, no card frames. Masks ship as pre-rendered images at three sizes per season state.
9. **Mist:** four level bands and three pooled masks, pre-rendered, each with a breathing `.offset`.
10. **Tone during events:** see section 3. Caption = `Text`.
11. **The looked-up view is derived state:** see section 4. One shared driver for the two sky views. Reduce Motion is a 0.6 s opacity between two stills.
12. **Tonight's star:** `lerp(rest home, window home, look)`. The window home comes from the strip's safe-area geometry (Duo) or the header's (slab). The band's centre is the window home.
13. **Which sleep ended** matters only for the un-dim (1 or 0.45).
14. **Resting offsets on the pixel grid:** round each layer's offset at each pose to whole device pixels (349.44 and 405.6 pt are not on a third-point grid).
15. **One timeline (`MOMENT`), and a touch ends it.**
16. **The strip's clear window must follow the island's own animation** (0.6 s).

**Riskiest, by the author:** the land painter in `Canvas`; then tone during events.

**"Still not good enough"** (MD:1229-1441):

1. **Cards-on night is two stars, not a place.** Inherited by design. **The disc-hiding parts are reversed by the sign-off.** Summer daylight look-up is accepted by the owner.
2. **Everything that moves was judged from stepped frames.** Inherited; first device builds are the first real viewing. Touch and overlapping events were never played.
3. **Clouds are slight;** hard to find at 1x in dark by day; "hollow shell" at sunset; seven clouds in a July looked-up frame is two or three too many. Inherit or tune.
4. **Light appearance at night:** ground behind the cards is lilac (luminance 0.63-0.66 against the page's 0.89). The year-old sky is thinned; the count is not visible at 1x. **Undecided: whether the band should be spared the thinning.**
5. **Tone still settles after the view is up;** a night feed un-dims by 14% more light. Needs note 10 built and a dark-room look.
6. **Lab stand-ins:** no sleep log; layout numbers written into the sky in several places; at rest stars stand round the status icons (not touched); small rules untested.
7. **The tree in leaf:** wire loops outside the leaf masses in summer; separate balls; autumn after sunset; single flowers up to 8 pt outside the crown; the bare tree's lowest left spray is 2 pt from the Today card. Inherited if the masks ship as they are.
8. **The slab:** the sun whole under the signal bars; its radius is 9 pt where 8 was asked; the moon's shift (46 pt) was set by a tool's tolerance and the fuller shift was not made (decide); a dusk-dark snow hill; no cloud at rest; no first-night place.
9. **Winter dusk in dark:** the tab capsule's ground is unshaded (0.033-0.045); the shade's feather darkens 12 pt of the strip. Needs a phone.
10. **Sun and moon drawing:** the day moon is nearly nothing in dark; a grey disc for about 20 minutes at dawn; the pale sun's orange edge was not looked at in summer; tonight's star is gone 1.9 s into the settle while about twenty stars stand on.
11. **The rest pose at night is rare and thinner;** tonight's window holds 27 others at a year; two four-point stars can stand 44 pt apart at two years.
12. **Smaller drawing things:** midday pale land within about eight levels; reeds faint; the daytime plaid; mist threads; mist breathing in quarter-point steps (a `.offset` removes this); the earth-shadow is slate.
13. **The dark night wants an OLED in a dark room.**
14. **One night, two marks** (point under glass or beside the moon). By choice; real glass may change it.
15. A history of what was answered; the measuring tool's naming of discs is not a port concern.

**Decisions the port must make that neither file settles:**
- **The icon exception's width.** The sign-off says "directly behind the Wi-Fi and battery glyphs" (BRIEF:368-370); the mockup hides a disc across the whole strip column until its top is 16 pt clear (HP:3953-3959).
- **Whether the header rules stay.** A disc is never drawn in the Duo's header band or behind the slab's status bar (`seen`, HP:785-796), nor behind the avatar or gear (HP:1063-1073). These are not cards and the sign-off does not mention them.
- **What a disc does while cards fade back in at bedtime.** With the rule withdrawn, the moon is read through the returning Today card for about half a second (the reason the rule existed, MD:660-667).
- **The moon's halo under a card** now that the disc is drawn there (the quarter rule was a gate workaround, MD:259-264).
- **The 6 pm to 4 am bound** against the lab's rule.
- **Month-nights by real calendar month-birthdays.**

---

## 7. What cannot be known until it runs on a phone

- **Whether the land painter survives `Canvas`:** about 45 blurred strokes, washes laid small and enlarged, a dry-brush mask. Look and cost are unproven (MD:1223-1224).
- **Tone carried by shader uniforms ahead of the dither, and cross-faded land images:** never built (MD:1225-1227).
- **Motion at speed:** nothing was watched at real speed. The rise, the band as a film, the tree leaving and returning, a disc going under a card, star rays drawing in, the touch cancel, overlapping events (MD:1256-1275).
- **Real frame cost:** GPU compositing of offset layers against the lab's software raster; stars at 10 fps; memory for five kept planes at spread width and 3x; pre-rendered tree masks at 3x.
- **3x displays:** all figures are at scale 2; the pixel-grid rounding and 1-level effects change on a third-point grid (MD:1202-1207).
- **Real glass:** tiles, the tab capsule and the toast are "a guess" in the lab (BRIEF:472). Open: the snow shade, points under glass, what a sun or moon looks like through a tile, the tab bar minimising on scroll (BRIEF:216).
- **OLED in a dark room:** tonight's star (peak 0.889, 82 pt^2 lighter than a card), the night feed's un-dim, banding or contours in the near-black land, the moon's halo under cards.
- **Real layout:** SF Rounded against the lab's Nunito; Dynamic Type; name length; real card heights; the island's real growth and animation; safe areas; the real Duo's geometry; the list scrolling (the lab is scroll-top only; the header scrolls away and the sky stays, BRIEF:213-215).
- **Fading list rows as "cards fall back"** on both pages without touching the sky or the toast (BRIEF:226-227).
- **The Duo opening:** nothing observes it today and the layout swap has no animation (BRIEF:219-220); two sky views with two clocks.
- **Real place and time:** the daycare pin or the 40 degrees north fallback against the lab's Chicago; the sun's and moon's tracks at other latitudes; summer evenings before sunset; whether first light at -7 degrees still reads right elsewhere.
- **Sync timing:** a night sleep arriving by CloudKit while Home is on screen (`arrive`), and cold launches at 3 AM.
- **Colour:** the lab is sRGB 8-bit; the phone is P3. The 3:1 and 0.0117 gates want re-measuring on real output.
- **The pale page's stars at 1x at a year old,** and the slab's minutes of dim sun under the status bar.
- **Throttling:** Low Power Mode, backgrounding, and the minute-repaint swapping in off the main thread without a dropped frame.
