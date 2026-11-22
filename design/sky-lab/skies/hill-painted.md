# Hill, painted

`skies/hill-painted.js` (+ `skies/hill-painted/air.js`, `tree.js`) · shots in
`shots/hill-painted/review/` (`node tools/review.mjs --sky hill-painted --jobs 2`;
`review/CODE.md5` names the code they were shot from) · the pictures before round three are
frozen in `shots/hill-painted/review-r2b/` (and before round two's finishing pass in
`review-r2a/`). The camera, the night, first light, waking, the events, the joins and the
port notes about the camera, tone and state are as of round three's pass "the night rule and
the joins" (BRIEF.md, "After the first review — the night lasts until first light"); the
bedtime timeline, the band, the caption, Reduce Motion, what the cards may bite (the tree,
the moon's and the sun's disc), the first night's star, the opening at night and the sun's
halo are as of the pass after it, "the moment and the looked-up night"; the rest is as round
two left it, until the round's drawing passes (crowns, clouds, land, river) are merged in.

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
a shadowed one. When he goes down for the night the camera looks up — the land sinks to the foot
of the display and every night of his life is on screen at once — and it **stays up until first
light**, whether he sleeps on or is up for a feed: the night's Home is that sky, with tonight's
star in the one clear window the cards leave.

No shader. Everything is 2-D canvas: one tall sky plane, five planes of land, sprites.

## Composition and camera

One world, in points, x = 0 at the anchor window's leading edge. Two poses; every plane
only translates between them. **Rest** is the everyday view. **Looking up** is the night: a
*state*, not a moment — the view is up while **the night has begun** (`state.nightBegun`):
from the moment tonight's night sleep first starts, by any means, until first light the next
morning, whether he is asleep or awake. `lookOf()` is 1 while that is true and 0 otherwise;
it does not ask which sleep is running or which one ended. Three events carry the view
between the poses and nothing else moves it (see "Events"): `bedtime` and `arrive` up, where
the night begins with them; `settle` down, at first light. A night feed moves nothing; waking
never moves the camera, at any hour, after any sleep; naps keep the rest pose. (The URL's
`look=0…1` still holds any pose.)

- **First light is the sun coming up through −7°** (`FIRST_LIGHT_DEG`, lab/core.js; 06:12 on
  21 November, 04:35 on 21 June in Chicago). Chosen by looking, at five-minute steps from −9°
  to −4.6° in both appearances, November and June, cards on and off: looking up, the sky
  still holds about twenty of his stars at −7.2° and reads as night; at −6.3° it holds four
  and at −5.5° only the first night's and tonight's, over a dawn band the pose was never
  composed for. At rest, −6.9° already has the tree's silhouette against the first band of
  dawn. So the looked-up pose is never seen in morning light, and a morning with him still
  asleep — 07:30 in November, 05:30 in June — is the day's picture, dimmed.
- **The camera is on the pixel grid at rest and between pixels while it moves.** Each plane's
  whole travel is rounded to a whole number of device pixels (the near planes' 349.44 and
  405.6 pt become 349.5 and 405.5 at 2×), so a plane arrives exactly on the grid; while
  0 < look < 1 the sky and the land are drawn at fractional offsets, smoothed (with the
  canvas's better resampler: its plain bilinear one truncates and darkens a near-black layer
  by half a level for as long as the move lasts). Tracked at 30 fps, the tree's steps at the
  two ends of the rise are now 0.03, 0.13, 0.44, 0.83, 0.95, 1.17 pt and 0.94, 0.73, 0.35,
  0.30, 0.04, 0.01 pt; they were 0.40, 0.01, 1.09, 1.00 and 0.99, 0.01, 0.49, 0.00 — a hold
  and a nudge. The clouds are still placed on whole pixels during the move (their loop is
  another pass's).

| | Duo (cover and spread) | slab iPhone |
|---|---|---|
| horizon at rest | y 292 | y 140 (the header is a small landscape) |
| horizon looking up | y 604 (lowered 312) | y 770 (lowered 630), just above the capsule |
| the turn | the far world slides **90 pt** left (was 78) | 30 pt left |
| tree at rest | x 408 on the knoll, 88 pt tall, crown x 368–448, top y 213 | x 286, 62 pt tall, between his name and the gear |
| tree looking up | x 318, foot y 609 — clear of the tab capsule (x 392–456) with the cards away. Its crown reaches x 362.5 bare and x 365 in leaf (3 pt more at full tilt), past the cards' edge (x 362): with the cards on it is drawn only behind them (below, "Why 90") | x 256, foot y 762: wholly behind the sleep card |
| tonight's star, at rest | (379, 194): above the tree's left shoulder | (262, 66) |
| tonight's star, looking up | **(412, 270): in the strip's clear window** (x 362–466, y 185–396 while a sleep runs) | **(270, 100): in the header band**, the gap between his name and the gear |
| the first night's star, looking up | (262, 43): the header's clear gap, with 18 pt of sky of its own and no other four-point star within 60 pt | no place of its own (its cast place, (111, 170): under the Today card when the cards are on) |

- **Why 90, and why the turn alone is not enough.** At 78 the crown's last twigs stood 8 pt
  past the cards' trailing edge when the cards were on — a tree behind a card with its fingers
  showing. At 90 the *bare* tree at level tilt ends half a point past the edge; in leaf it
  stands 2–3.5 pt past (summer to x 366), and at full tilt 4–7 pt (measured in the light
  appearance, cards on: 2 pt² of twig in November, 22 pt² of leaf in July, 33 and 79 pt² at
  full tilt). The turn cannot go further: looking up, the moon is the turn away from the
  baseline's x, and `tools/measure.mjs` only takes a disc for the moon within a fifth of the
  anchor window (93 pt) of where the state puts it; at 100 the dark-night ground check fails
  on the moon. (The tool reports that offset for the night frames: mean ≈ 69 pt, largest 89 —
  it is the camera's turn, not a moved moon; at rest the moon is where the clock puts it.)
  Nor can the knoll slide further than the sky on its own: the sun and the moon burn through
  the crown exactly where they stand behind it, so the tree must keep its place against them.
  So the last points are the picture's to give: **with the cards on, looking up, the tree is
  drawn only behind the cards** (`treeBehind`, `drawKnollBehindCards`). Where it would stand
  past a card's edge it is not drawn, and it gives way over the last 8 pt before the edge, so
  through glass it has no cut end. That covers the sleep card's trailing edge in every season
  and at full tilt (0 pt² past the edge in all forty frames measured: five seasons, level and
  at full tilt, asleep and awake layouts, cover and spread) and the 12 pt gap under
  the shorter Sleep tile when he is awake in the night, where the trunk stood (99 pt² of it;
  now none). It is weighted by the cards' opacity and comes on only over the last 15 % of the
  rise: with the cards away the whole tree is there, and the bare picture is untouched.
- **The tree is not seen at night with the cards on, on any display.** I looked for a
  composition that keeps it: the Duo's one tall window is y 185–396 and the capsule takes
  y 396–644 under it, so a tree standing in that window puts the horizon near y 390 — the
  land would be the lower two fifths of the bare frame (round one's "tall empty land") and
  the view would hardly look up; under the capsule there are 34 pt; the slab has no window
  below its header. So, plainly: **with the cards on, the night's subject is tonight's star
  among his stars**, and the tree is what the cards uncover at bedtime — and what first light
brings back into the strip.
  (In the light appearance the tree is a soft ghost through the sleep card's glass.)
- **Planes and parallax.** Sky, far ridges + valley floor + river, the mid hill, the knoll
  with the tree: these move as one (sink ×1, slide ×1), so the tree keeps its place against
  the sky. The two near planes sink ×1.12 and
  ×1.3 and slide ×1.1 and ×1.25: near land leaves faster. Nothing is repainted for the move.
- **The spread's phone page is the cover's picture**, both poses. `measure.mjs`, at rest: 8 of
  16 pairs identical to within 2 levels, the largest mean difference 0.16 levels; looking up
  (the `--asleep night` run): 5 of 6 identical, the largest 0.03 levels; no point more than 8
  apart in either. Planes, gradients' knots, grass, mist pools, dither and grain are all laid
  on a world grid for that — and the bedtime band keeps the anchor window's pace on both, so
  the two are the same picture at every instant of the moment too.
- **The strip** (cover x 362–466) shows, top to bottom: 35 pt of plain sky under the status icons,
  then a thin bank of cloud that comes in from the trailing edge and is cut by it (never a whole
  small cloud under the icons — that is a weather symbol; hidden while a sleep runs, when the
  icons sit 34 pt lower: see Clouds), the twilight's bands, the
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
  (that reflection is a soft ribbon close under the far bank, in a few long runs of unequal
  length that thin to nothing at both ends — it was a run of like dashes down the middle of the
  water, a road's marking); a bar of sand comes out from the bank inside the near bend, a
  slender crescent that tapers at both ends (the banks never both come in at once: no waist);
  **reeds stand at the water's edge in two places on the near reach, both in the leading margin
  column and clear of the cards**: blades 6–16 pt tall, all leaning 5–12° downstream, two or
  three of a clump with a slender seed head, their reflections under them — of the land's own
  dark and a step under it, never the tree's ink (on the pale page they go most of the way to
  the water's tone, and at night with the river); level streaks of sheen cross the near reach,
  and on the middle reach four strokes of sheen of unequal length (5–18 pt) lie along the outer
  banks of its bends, none on its centre line; ten pools of mist lie on the far *and* the middle
  reaches (the water is erased under them); the bend in the leading margin column carries one
  soft upright smear of the low sky's light (at half its first strength: the sun that lights it
  is on the other page). At dawn the sun rises out of the fold gutter and the far reaches burn.
  At night in the dark appearance the whole river is held at one faint value (luminance 0.0076,
  a card is 0.0117); while the moon lights the night some forty short silver glints lie
  scattered down the near reach, close together far off and sparser toward you — "the moon's
  broken path" as a painter's convention, **not** geometry: the moon is over the phone page
  and its true path would not fall on this water.
- **Sun and moon** keep the baseline's clock and x (`state.sun.x`, `state.moon.x`) and have
  one place in the world: height = Emax·(1 − e^(−alt/45°)) + 12·(1 − e^(−alt/2.5°)) points
  over the horizon (Emax 500 Duo, 620 slab). A high moon or sun is therefore above the top
  of the everyday view and **comes down into view with the sky** when the camera looks up.
  Neither is ever drawn in the header band (Duo) or behind the status bar (slab). The moon's
  track is **not** extended onto the leading page (it would change where the cover's moon
  is); the river carries the light.
  - **A disc is drawn whole or not at all.** Looking up with the cards on, the moon's or the
    sun's disc is drawn only where the whole disc, and 3 pt round it, stands in the open
    (`standsOpen`): not under a card, not across the 12 pt gap between two (a 19 pt moon
    cannot stand in it), not in the 20 pt margin, not straddling the anchor window's leading
    edge (the cover's own edge — and the spread's phone page is the cover's picture). Its
    halo's light stays, at a quarter where the moon's disc is not drawn: the glow was sized to
    stand round a disc, and with nothing at its heart it is itself lighter than a card in the
    dark appearance (0.024 against 0.0117: the dark-night gate fails on it) and a soft white
    disc of its own on the light page, which a card's edge then bites as it bit the moon. So
    a gap or a pane of glass takes a faint glow, no more. It is weighted by
    each card's opacity, so with the cards away the bare picture is untouched; and it is not
    applied at rest, where the bodies keep the header band and the strip as round two
    composed them. **What this costs:** looking up, a body never reaches the strip (the turn
    brings it 90 pt left: x ≤ 357), so with the cards on the Duo shows the moon's disc almost
    nowhere — only in the gutter of the open Duo, left of the fold, for the minutes it crosses
    it. The moon is a glow in the gaps; its disc belongs to the bedtime moment.
  - **During the rise a body arrives in open sky.** Once the view has left the rest pose a
    body comes out from under the header over 90 pt of sky, not 15 (and on the slab from
    under the whole header, not only the status bar): the moon coming down with the sky no
    longer blinks on under the Duo's header in two frames (it fades in over 0.3 s) or rolls
    through his name on the slab. No looked-up body ever rests within those 90 pt (the Duo's
    highest moon stands at y ≈ 183, the slab's at y ≈ 250), so the standing frames are as
    they were.
  - **The sun's halo** is two soft rings. They were filled through a blur filter on every
    frame; they are now painted into sprites and kept (`drawSunHalo`; see Cost).
- **Clouds** are quiet banks, drawn the way the picture draws a hill: one top contour set by
  hand (a few rounded masses of unequal size run together — the join between two is rounded,
  never a cusp — with the crests' own wobble), crisp against the sky; a flat fill, lightest
  along that edge and gone to the body's tone by 45 % of the rise; and **no base**: the lowest
  third lets go into the air, as a plane of land does into the mist at its foot. Nothing is
  modelled in relief. Under a low sun (below about 12°) or the moon, one dry, broken rim line a
  point wide lies on the parts of the contour that face the lamp; in the afterglow the low part
  of the cloud is the warm one. Four in the Duo's everyday view:
  - *strip*: 98 × 10 pt, its foot at y 196, coming in over the tree from the trailing edge —
    a third of it is always off the display (drift ±5 pt), its top 35 pt under the battery and
    its foot 17 pt over the crown;
  - *gap*: a small low bank, 62 × 8 pt, in the header's clear gap at y 30–38, above the line
    of the name and the gear and at least 28 pt from each;
  - *bank*, the large one: 138 × 22 pt over the clear stretch of the leading page's frieze,
    between the page's title and the fold (its right end stays off the cover's picture);
  - *bar*: 250 × 13 pt over the valley, **wholly behind the leading page's cards** when they
    are on (nothing of it pokes out into the margin column): it belongs to the bare panorama.

  Looking up there is one more, a low broken bar left of the tree (176 × 11 pt; on the slab it
  lies wholly behind the sleep card), and the *strip* and *gap* banks leave as the camera rises.
  None on the slab at rest. **Quiet at every hour**: each paint is held within a contrast of
  the sky behind it (`heldTo`: body ≤ 1.3 : 1, the light on its top ≤ 1.46, the afterglow ≤ 1.5,
  the rim line ≤ 1.9 in the dark appearance; ≤ 1.3 on the pale page) and a colour past its
  limit is brought back toward the sky's own colour, not just darkened. Measured against their
  own sky, dark appearance: by day mean 1.16–1.20 : 1, 95th percentile 1.27–1.33; at sunrise
  and sunset 1.39–1.43 at the 95th percentile (they were 2.5–3.0 by day and up to 3.65 at
  sunset; round two's bank was 1.62 and 2.31. The valley bar over the sunrise reads 1.66 by
  this ruler, which takes a cloud's sky from one side of it and there counts the dawn's own
  glow across 250 pt). On the pale page ≤ 1.2 : 1. The rules:
  - a cloud fades out before any part of its box reaches the header's words (gone at 2 pt,
    whole at 11 pt), and before it would cross the sun's or the moon's disc (a body that is off
    the display hides nothing);
  - a cloud keeps 24 pt of plain sky between the status icons and its top, or it is not drawn:
    so the strip has none while a sleep runs. **A sleep that begins or ends does not pop it**:
    over the first 0.6 s of `bedtime`, `arrive` or `wake` it goes from what the
    strip's window was to what it is (`sleepJoin`; the window's two heads are 34 pt apart,
    `ISLAND_GROWS`, the lab's layout table);
  - **a cloud does not cross a card's edge**: one that is partly behind a card and partly clear
    of it goes with that card's opacity (`acrossEdge`), in either pose — so with the cards away
    (the bare panorama, the bedtime moment) it is there, and with them on it is not bitten;
  - by night it is barely there: a veil of the sky's own picture over the stars inside its
    silhouette, then a breath of its form (not visible at 1× on the frames shot).
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
  luminance. Light gets a sun that is a **pale cream disc, lighter than the sky round it** at
  every height (luminance 0.91 against 0.83 at +1.7°; printed in its own apricot it was 0.67
  against 0.80, the darkest thing in its sky) with the colour in the sky's glow about it; a
  warm-dark wood tree with no halo (umber by day, warmer in the low sun, plum-brown at night —
  the darkest thing in the picture); and land whose planes, by day, when the hush leaves them
  within a few levels of one another, are told apart by **temperature**: the far hill cool
  (219, 224, 230), the knoll neutral, the near and fore hills warm grey (to 212, 209, 205),
  each letting go at its foot into air of the low sky's own value. At dusk the pale sky goes
  from peach to blue through a pale rose and lilac (it went through a grey-green band).
- **His stars** — `nights(ageDays, { tonightLit })`, mapped over the whole looked-up sky and
  kept clear of the header (and one em past its last glyph), the strip's furniture, the
  clock at rest, the capsule, the land, the tree's crown and each other (≥ 5.6 pt apart on
  every device). **The sky is now laid out for the looked-up view**, because that is the
  night: in boxes, top to bottom, each with a density (`starsFor`) — thickest overhead and
  thinning toward the land; a few more in the header's clear gap; fewer in the strip's clear
  window, where tonight's star is to be the one bright thing; and, low down, the two parts of
  the sky the *rest* pose shows (its header gap, its strip beside the tree) weighted so the
  night he is awake is not empty. Places are still gathered a little — a slow smooth drift of
  the whole field — and a place that is taken is cast again somewhere else. Four-point stars
  (the first night, the month-nights) keep 9 pt further from the words and buttons than the
  others, and 70 pt from tonight's place: nothing near it can be taken for it. **The first
  night's star has a place of its own on the Duo — the header's clear gap, between his name
  and the gear** — so with the cards on the night shows two stars you can name: the night he
  was born, by his name, and tonight, in the strip. It was kept, and given room, after looking
  at the night with the cards on at five ages (1 day to 2 years): on his first nights it is
  the one mark in the header — "Miller ✦ ⚙" — and the picture is worth having; at two years it
  had three other four-point stars beside it in the gap and a dot 11 pt away, and could not
  be told from them. Now no star stands within 18 pt of it and no other four-point star
  within 60 pt (its nearest neighbour is 21.0, 20.5 and 19.4 pt away at 142, 368 and 730
  nights — it was 11.9, 11.9, 11.1; the nearest four-point star 134 pt at two years — it was
  40.7). **On the slab it has no place of its own**: the slab's one clear gap holds tonight's
  star, which keeps every four-point star 70 pt off; there the first night's star is wherever
  it was cast, under the Today card when the cards are on, and nothing is claimed for it.
  Counted (age 142, tonight's lit) by the
  module's own census (`window.__hillPainted.stars`): **looking up** 143 on all three
  displays, none inside the name, age, avatar, gear, island/clock column or capsule; with the
  cards on, 12 stand in the strip's clear window, tonight's among them (Duo), and 9 in the
  header's gap, the first night's among them (it was 10: one stood inside its 18 pt; 7 on the slab, tonight's among them). **At rest** 62 on the cover and on the spread's phone page
  (41 in the open with the cards on), 29 on the slab — it was 71 / 47 / 33: the price of
  laying the sky out for the night's view. `tools/measure.mjs --stars-by-age --param look=1
  --param veil=1` says "144 of 142" on all three devices in both appearances: 142 nights,
  plus the two digits of the caption that differ from "Night 1" (tonight's star cancels).
- **The leading page's ordinary sky** — nobody's stars, on the whole tall sky: about as
  dense as his at the fold (so that, looking up, there is no boundary at the anchor window's
  edge), thinning and dimming to the far left, in three tints, fainter and smaller than his,
  answering the band only in the gutter beside the phone page: the band is the phone page's,
  its light dies at the fold and so do the answers (they used to run on over the leading page
  at the same pace and were still pulsing mid-page, to 5.2 s, as its cards came back; the
  other way — letting the ripple run on to the margin column — needs four times the band's
  pace to arrive before the cards, which is a flash, not a ripple). A star of this sky is never
  drawn inside the anchor window, wherever the camera is: the phone page's sky is his alone,
  and the cover's picture (they were hidden by how far the view had turned, and for 0.6 s of
  the rise the spread's phone page showed a few that the cover does not have). Their number
  follows his (80–460): a newborn's sky is not upstaged by the page beside it.
- **Tonight's star** — lit exactly while the night has begun (`state.nightBegun`; one fact
  drives the pose and the star, so they cannot disagree), drawn over everything. It has **two
  homes on the display**: above the tree's left shoulder (a hair-thin four-point spark with a
  small warm glow: an accent to the tree), and in the clear window looking up (the strip
  between the status icons and the capsule on the Duo; the header's gap on the slab). It
  goes from one to the other *with the camera* (`tonightHome`: a straight line in display
  points, eased as the view is), so what you see at bedtime is the star lifting off the
  tree's shoulder and climbing as the land falls away. Since the view is up whenever the star
  is lit, the home beside the tree is now only where it is born (bedtime's spark; or, when
  the night's sleep arrives from elsewhere, a quiet fade-in over the first 0.8 s) and where
  it is going as it goes out at first light (gone by 2.3 s of the settle, with the last of
  the other stars). In the evening before bedtime it is unlit, as it was. **Nothing lights or
  cools it at a wake**, a nap's or the night's, and **it is lit once, from what it was**
  (`sparkOf`, lab/presence.js `litFrom`): a star that is already lit is never put out to be lit
  again, and does not flare. On the way up it grows into the night's one bright star: 1.4× the size, a
  fuller glow (still tight: the room stays dark), four short rays between the long ones, and
  30 pt of dark sky of its own — **which it keeps all the way up**: it crosses the field (236 pt
  up and 123 across on the Duo, 596 pt on the slab), and while the view is between the poses
  any star within 30 pt of it gives way (gone within 14 pt). Before, his other stars slid
  through it: one passed 0.9 pt from its centre on the cover, four within 6 pt on the slab. While the sun is still up (a July bedtime) it is a small
  evening star, kept findable in its window — at 19:40 in July it is the only star there.
- **The night, with the cards on** (the frame the parents see most). Dark and light, 19:40,
  21:00 and 03:00, `asleep=night`, no event — and the same picture, the room un-dimmed, when
  he is awake in the night (a feed at 03:00: `asleep=0` once the night has begun):
  - *Closed Duo and the spread's phone page.* The strip's clear window holds tonight's star a
    little above its middle, with eleven small stars for company, mostly below it. The
    header band holds the first night's star in the gap between "Miller" and the gear, with a
    few small ones. The 12 pt gaps and the 20 pt column between the cards and the capsule show
    a star or two (one month-star stands whole in the gap between the two tiles). The moon's
    disc is not there: it is drawn only where it stands whole in the open, and on the closed
    Duo, looking up, it never does; a gap it passes takes its glow. The tiles'
    glass shows nothing at night in dark; in light, the tree's ghost lies in the lower right
    of the sleep card, fading out before the card's edge. Under the capsule: the near land,
    dark. The land itself is not seen in dark with the cards on.
  - *The open Duo's leading page.* Its margin column and the gutter are tall slits of the
    ordinary sky (fainter than his) over a low dark band of the valley, whose first bends of
    river lie in the 34 pt foot. Calm; not a picture of its own.
  - *The slab.* Tonight's star is in the header, where the tree stands by day — "Miller ✦ ⚙" —
    with a few small stars. Nothing else of the sky shows but the margins.
- **Night at rest** is now only the evening before bedtime (awake at 18:30: dark, his stars
  out, the tree's silhouette, tonight's star not yet lit) and the last minutes before sunrise
  (from first light on: the tree against the dawn, dimmed if he still sleeps). *Awake at
  21:00 or 03:00 is no longer this picture*: the lab takes the night to have begun once the
  sample day's bedtime (20:10) has passed, so those hours look up (`begun=0` still shoots the
  rest pose at any hour). The rest pose's night is drawn as it was: the horizon light a band
  as tall as the tree's crown, kept under the dimmed room; just behind the crown it stands a
  touch higher (to luminance ≈ 0.010, less when the moon is up) and lets go within the strip;
  each plane of land has its own value; under a moon the knoll carries a thin cool rim.
- **Seasons** — the tree. *Bare* (now): limbs, twigs, a few last leaves, a hair of frost on
  the upper side of the limbs (on the pale page the frost that would lie inside the wood under
  a fork is taken off: it was a pale chevron under every crotch). *Winter*: snow **lies** — one
  unbroken cap along each stretch of limb level enough to hold it, tapering to nothing at both
  ends, 1.5–2 pt on the great limbs, its foot in a blue shade; a small pillow in the forks; a
  hair of it on the level twigs. *In leaf*: every leaf is one small pointed mark (1.2–2.9 pt)
  on a twig the tree already has — about 6,300 in a full crown, some 1,400 in mid-October —
  and they grow only inside the crown's **outline: eleven convex masses of unequal size** set
  by hand (the top, the two shoulders, the heart, the tuft on the low left bough, the spray at
  the long arm's end: 16, 12, 10, 9, 7 and 5 pt in radius on the Duo's 88 pt tree, and the
  smaller ones that join them). So the silhouette is a run of rounded masses with the sky
  between two of them coming to a point; no mass has a level top or a plumb side (the noise
  that frays them is read on a grid turned 31°: thresholded on the lab's own lattice it cut
  boxes); the edge frays into single leaves, each by its own lot. All the leaves together, a
  touch out of focus, are the far side of the crown, behind the limbs; the ones inside one of
  twelve near forms are the near foliage, in three paints, lit leaf by leaf from wherever the
  lamp is (eight directions), with eight holes of sky that are always there and nine more that
  open as it thins. **The bay at the lower right, where the sun goes down, is where no mass
  is** — open in every season; the spray at the arm's end hangs from the right shoulder and is
  part of the crown, and no leaf stands further out than 0.44 of the tree's height to either
  side (measured in July: looking up, the tree ends at x 358.5, 3.5 pt inside the cards' edge
  — it stood 3.5 pt past it; at rest it begins at x 369.5, 7.5 pt from the Today card — it was
  2 pt. The bare twigs are the skeleton's and still reach x 364 at rest and 363 looking up). A low sun behind the crown comes through leaf-shaped gaps. *Autumn*: amber,
  gold and russet, the twig ends taken first; **after sunset in the dark appearance a few leaves
  on the sunset's side stay gold until the twilight has gone**. *Spring*: flowers, not foam —
  small round marks in sprays, thickest at the twig ends, in two tones, a few sprays always
  crossing the trunk's own line under the top; the first leaves few and small. The land: frost
  along the shoulders; **snow in the dark print is the palest thing on the ground** (blue-white
  by the sky's light, down to the night's cap) on the far land and the knoll, and a step deeper
  on the hill behind the knoll and the two nearest planes, which lie under the cards; snowfall
  as many small flakes in depth (a dust of far ones, a few near and soft).
- **Bedtime** (a night sleep started by hand; `event=bedtime`) — once a night. The sky keeps its
  pace; the cards give up the time (BRIEF.md, "After the first review", item 3). One table holds
  it for the sky and for the lab's UI: lab/presence.js, `MOMENT` (`momentVeil` is what the
  cards do; tools/film.mjs and tools/review.mjs play it).

  | seconds since the tap | Duo | slab |
  |---|---|---|
  | the cards fall back (`veil`) | 0–1.0 (under 5 % at 0.88) | the same |
  | the view rises; tonight's star, lit from the first instant (`ignition()`, its flare at 1.5 s), lifts off the tree's shoulder to its place in the clear window, keeping 30 pt of dark sky round it | 0.3–2.4, peak 286 pt/s | 0.3–2.7, peak 497 pt/s (it was 0.3–2.4 and 571: the slab's sky is twice as tall) |
  | **one soft band of light** leaves the star's place — *that* place, fixed on the display — and crosses the anchor window to its farthest corner | leaves 2.1, has crossed at 4.2 (276 pt/s; it was 242) | leaves 2.3, has crossed at 4.3 (410 pt/s; it was 342) |
  | …its own light: held back until the crest is 150 pt out, fullest two fifths of the way, gone at nine tenths | over 1 level from 2.70 to 3.82 (peak 18 levels at 3.0) | from 2.75 to 3.88 (peak 18 at 3.1) |
  | each of his stars swells as it passes and keeps a fifth more light, which it gives up slowly to the settled night's own | the last star swells at 3.85; over by 4.17 | the last at 3.88; over by 4.40 |
  | "✦ Night 143" at the foot, on the side away from the tree | in 2.0–2.8, whole to 4.15, gone by 4.6 | the same |
  | **the cards return over the sky that is already there**, with an ease-out (SwiftUI's `.easeOut(duration: 1.2)`) | 4.6–5.8: half back at 5.0, 95 % at 5.6 | the same |
  | after | nothing moves but the twinkle and the mist. (The tone goes on settling to 9 s — the room dimming — and the bloom lets go over 14 s: a slow fade, not a movement.) | |

  The whole is 5.8 s (it was 6.8), and what went is card time: the cards took 1.6 s to go and
  2 s to come back. The caption is never read through a returning card and the band is never
  cut by one: the caption's last trace (3 %) is at 4.52 s, the band's own light is under half
  a level by 3.88 s (3.95 s on the slab), and the cards' first (1 %) is at 4.62 s — measured
  from 60 fps films on all three displays (in the light appearance and in July too).

  **The band's first state is not a ring round the star.** Its light used to be visible from
  46 pt out — a closed circle round the star for a third of a second: sonar. It is now held
  until the crest is 150 pt out, wider than the strip's window, so what first shows is an arc
  that already leaves the window on both sides; until then the gesture is the stars' alone
  (those nearest the star answer first). The other way — no light at all, only the answers —
  was shot beside it and is kept as a lab switch (`band=answers`). It was not chosen: with
  142 stars in a dark sky the answers alone do read, as a crescent of brighter stars moving
  out; but on his first nights there are seven stars and nothing crosses at all, and on the
  light page, where a star's swell is slight, almost nothing does at any age. The band's own
  light is what makes the gesture at every age and in both appearances.

  **In July** the sun (+7°) stands behind the crown in a column of its own light, and his stars
  are out of sight in that sky until the moment shows them. They no longer exist only behind
  the band (a hard edge of population sweeping the sky): a faint presence of all of them comes
  up over the whole sky as the view arrives (from 1.6 s, two fifths of what they keep), the band
  finds them and leaves them clearer, and they are let go as the cards return (a sky that light
  has no stars). Measured at 2.4–3.0 s, sky alone: the stars still ahead of the band stand a
  median 19 levels over their sky (the grain alone reads 5); before, none of them was there.
  The front is still plain to see — it is where the stars swell — but it is a wave of
  brightening over a sky of faint stars, not the edge of where stars exist.

  **A touch ends it at once** (the app's; the lab has no touch): the cards are back in 0.3 s,
  the band and the caption are out in 0.2 s, and **the view stays up** — wherever the rise has
  got to, it runs on to the end at its own pace; nothing comes back down. The caption has to
  leave faster than the cards arrive because it lies across the sleep card's bottom edge
  (y 640–656 on the Duo).

  There is no way back down inside the moment (`look` stays 1). In November the moon has come
  down into the upper left of the frame with a fuller halo. The moment plays only where the
  night begins with a sleep started by hand: once the night has begun (a feed, then down
  again), a sleep started by hand only dims the room — in the lab `event=bedtime` is then
  played as `arrive`, and says so.
- **Events** (lab/core.js `nightOf`, README). What moves the camera, and what does not:

  | event | camera | tonight's star | the room (lab/presence.js `roomDepth`) |
  |---|---|---|---|
  | `bedtime` (by hand, the night begins) | 0 until 0.3 s, up by 2.4 s (slab: 2.7 s), stays | the spark (`ignition`), from unlit: lit once | dims over 1.2–9 s, from 0 |
  | `arrive` (a night sleep begun elsewhere, the night begins) | up over 0–2.5 s, behind the cards. No veil, band or caption | fades in over 0–0.8 s beside the tree and rises with the view | dims over 0–4 s, from 0 |
  | `arrive` (the night had begun: put down again after a feed) | none: it is up | lit, still | dims over 0–4 s, from 0 |
  | `arrive` (a nap) | none | none | dims to 0.45 over 0–4 s |
  | `wake` (any sleep, any hour) | **none** | **nothing changes** | un-dims over 0.3–5 s **from what that sleep had** (a night's 1, a nap's 0.45), and the solar bloom is taken from that eased depth |
  | `settle` (first light) | down over 0.1–2.7 s, behind the cards | goes out over 0.1–2.3 s on its way back to the tree's shoulder | unchanged (if he still sleeps the day arrives dimmed) |

  Each event's first frame is the standing frame before it, and its last the standing frame
  after (`tools/joins.mjs`; see Gates). An event that does not fit the state is dropped or
  played as another, and `state.eventNote` says so: `wake` while a sleep runs, `arrive` or
  `bedtime` with nobody asleep, `settle` before first light or with no night begun are
  dropped; `bedtime` once the night has begun, or for a nap, plays as `arrive`.
- **Waking** (`event=wake`, any source, any hour) — nothing moves and no star lights or cools.
  The room un-dims over about five seconds from the depth that sleep had. In the night (a
  feed at 03:00) the view stays up and the star stays in its window; in the morning, after
  first light, Home is already on the hill, dimmed, and simply brightens; after a nap the
  day's picture brightens by the nap's 0.45. The lab is told which sleep ended with `woke=`
  (unsaid: the night's before 09:00 and from the sample bedtime on, a nap's in between —
  18:25, the sample day's last nap, is now a nap's).
- **First light** (`event=settle`) — if Home is on screen at the minute the sun comes up
  through −7°, the view settles back to the land behind the cards over 2.6 s as tonight's
  star goes out; the tree comes down into the strip against the first band of dawn. Otherwise
  Home is simply on the hill the next time it appears.
- **A night sleep that arrives from elsewhere** (`event=arrive`: the other phone, Siri, a
  widget, SNOO) — the quiet rise behind the cards, 2.5 s; no veil, no band, no caption. This
  replaces round three's `resettle`: a re-settle the same night no longer moves anything (the
  view never came down), it is `arrive` with the night already begun.
- **Opening the Duo** — the valley is already there; the one thing that happens in the bare
  second is **light running down the river toward you**: a crest leaves the furthest bend at
  0.1 s and is at the foot of the page by 0.9 s, slow among the far bends and quick through the
  near reach. The water itself and the mist lying along the river's own course take it as it
  passes, keep half of it while the cards land (0.9–1.9 s in the film), and let it go by
  ≈ 4.4 s. Light added in the dark appearance; a warm pass over pale mist on the light page;
  held to a breath at night. (Watching the first film showed the earlier version — a front
  crossing the page sideways from the fold — was too faint and mostly hidden by the landing
  cards; it was replaced after that.) **At night while he sleeps the leading page arrives
  looking up**: the ordinary sky over a low band of the valley, the river's far bends at the
  very foot. The river's light is timed to what that pose shows of the river (its run ends at
  the foot of the page in either pose) and is still only a breath; so at night the one slow
  thing is the sky's: the page's stars come out from the fold outward over the bare second
  (dim until the front reaches them, a swell as it passes), and nothing else. The front leaves
  the fold at 0 s and runs at 700 pt/s (it left at 0.12 s at 560): it is in the margin column
  — the one part of the page its cards never cover — by 0.55 s and has crossed it by 0.7 s,
  before the cards begin to land (0.9 s), and its swell is nearly twice as large there
  (measured: the column's starlight peaks at 122 % of its settled value at 0.70 s; it peaked
  at 109 % at 1.00 s, as the cards were already landing). ("While
  he sleeps" is now "while the night has begun": the Duo opened during a feed finds the same
  sky.)
- **Light appearance at night** — lilac-slate sky graded to the horizon. **One mark, one
  meaning, as in the dark appearance**: every ordinary night is a round white point (the faint
  ones a crisp point with no patch at all; the brighter ones a larger crisp core, 0.8–1.5 pt in
  radius, on a soft patch of dusk three and more of its radii wide and never as strong as the
  core is white), and four points are kept for the first night, the month-nights and tonight
  (the leading page's ordinary sky the same, fainter). The brighter fifth used to be small
  four-point glints: the same star was a dot in one appearance and a cross in the other. Looking up, the whole page is that sky down to the land's band at
  the foot, so behind the cards the ground is lilac (see the gates); the moon with a pale halo; slate
  land where it meets the sky, giving way to the paper down the page under the cards; mist
  paler than the land and nearly its colour (not blue puddles); the river mostly lost in mist.
- **Motion** — clouds drift ±3–18 pt over 40–50 minutes, valley mist breathes ±16 pt and the
  pooled mist ±7 pt over 4–8 minutes, stars twinkle, fireflies blink, a few leaves or petals
  fall, one shooting star every 140 s. **Reduce Motion** (`motion=0`): all of it still, no
  band, no spark, and there is no move — the looked-up still dissolves in and out, in 0.6 s
  (it used to cross-fade on the camera's own curve, 2.1 s at bedtime and 2.6 s at first light:
  two trees and two of tonight's stars on screen for most of two seconds). At bedtime the
  whole moment is about 4 s: the cards go (0–0.6 s), the dissolve runs once they are under
  10 % (0.6–1.2 s), the caption stands for two seconds (in by 1.6 s, gone by 3.4 s), the cards
  return (3.4–4.0 s). `arrive` and `settle` are the same 0.6 s dissolve behind the cards, from
  their first frame. Tonight's star belongs to the looked-up still: during a dissolve there
  is one of it on screen, not one beside the tree and one in the window.
- **Tilt** — six planes: sky −1.2 pt, far 1, mid 2, knoll 3, near 5, fore 8 (x; less in y).

## Gates

`node tools/measure.mjs --sky hill-painted --jobs 2` → `hill-painted: PASS` (0 FAIL, 0
AT-LIMIT, 48/48 frames); with `--asleep night --times 19:40,21:00,03:00` — the looked-up pose
with the cards on, the room dimmed — → `hill-painted: PASS` (0 FAIL, 0 AT-LIMIT, 18/18); the
looked-up star count (`… --times 19:40,03:00 --param look=1 --param veil=1 --stars-by-age`) →
PASS, "144 of 142" on all three displays in both appearances.

**What the first run measures has changed.** Its 21:00 and 03:00 frames are `asleep=0` after
the sample bedtime: the night has begun, so they are now the **looked-up pose with the room
un-dimmed** (a night feed), not the rest pose at night. 12 of its 48 frames are that. No
limit was changed. Their closest figure: the dark night ground as an area 0.0101 at 03:00 on
the spread (0.0100 at rest in round two; a card is 0.0117, "AT-LIMIT" begins at 0.0111). The
rest pose at night is no longer in any gate run (`--times 18:30` or `--param begun=0`
measures it; an 18:30 run of the same ruler passes).

**And the looked-up frames are now measured twice.** The tool shoots the sky alone ("bare")
and the sky as drawn beneath the real cards ("under"), and where the two differ by more than
2 levels it measures and judges both. They used to be one picture. Looking up they no longer
are: beneath the cards the tree is drawn only behind them, and the moon's disc is not drawn
where it would be bitten (its halo held to a quarter). So 12 of the first run's 48 frames
and all 18 of the second's are judged in both forms (15 and 18 dark-night ground
measurements where there were 9 and 9). Both pass in both. This is why the moon's halo is
held to a quarter where its disc is hidden: left whole, with no disc for the ruler to set
aside, the glow alone read 0.024 beneath the Today card at 21:00 and failed this check.

Closest to a limit otherwise, unchanged: the light grey line on the slab (3.26 : 1, L 0.605 at
17:30, limit 3 : 1 / 0.55); the dark grey line by day (0.043, limit 0.072; 3.95 : 1 on the
cover at 09:30); the dark name on the slab at dawn (9.12 : 1, limit 7). Looking up, asleep:
the light grey line on the slab 3.28 : 1 (L 0.609); the dark night ground as an area 0.0090
at 03:00 (cover). The light page's ground looking up: median 0.657–0.663 asleep, 0.686–0.692
awake. The tool's unjudged line "sun and moon against the state's x" reads mean 69 pt,
largest 89 pt for the night frames: the camera's turn. The cover against the spread's phone
page: 10 of 16 pairs identical to within 2 levels in the first run (largest mean difference
0.16 levels), 5 of 6 in the second (0.03); no point more than 8 apart — and in the 60 fps
films of the moment, sky alone, no frame of 511 has a pixel more than 8 levels apart (37
frames had, at the leading edge, for 0.6 s of the rise). A feathered limiter sits under each
line of header text (`darken` / `lighten`; it does nothing unless the sky there is past the
limit).

**Tonight's star, by its own numbers** (no grid; the looked-up night, asleep, dark, 21:00 and
03:00): its brightest pixel has luminance 0.889; within 22 pt of its place 82 pt² are lighter
than a card (0.0117) on the cover and on the spread, 64 pt² on the slab; the sky round it is
0.0017. The tool's unjudged "strict" figure — the lightest single 8 pt block below the band —
reads 0.047 (0.049 with the room un-dimmed), and **that figure is the cover's**: there the
8 pt grid happens to centre a block on the star (x 412). On the spread the same star, the
same pixels, falls across four blocks (x 897) and reads 0.009–0.014 (the claims review's
reading of the same run; this pass re-measured the peak and the areas); on the slab it stands
in the header band, outside this check. So the block figure says where the grid falls, not how
bright the star is. It is a point, not an area — the tool counts it as one block over a card
and passes it — but it is the brightest thing below the band at 3 AM and should be looked at
on an OLED in a dark room.

**Joins** (`node tools/joins.mjs --sky hill-painted`; BRIEF.md: no join may jump). Twelve
joins × three displays × two appearances × sky alone and cards on, each as two pairs (the
standing frame before | the event at age 0; the event at age 40 | the standing frame after):
288 pairs. Limits from the grain (a pixel stands a median 1.6 levels from its neighbours'
mean): mean ≤ 0.25 levels, ≤ 0.5 % of pixels over 2 levels, ≤ 0.02 % over 6, none over 12.
Two shots of one state are the same bytes (144 checked). Before the pass "the night rule and
the joins" 200 of 288 were within the limits; after it 264, the 24 left all one thing — the
strip's cloud (cover x 393–448, y 162–189, and the same place on the spread), which gives way
to the longer island and was switched with the clear window in the frame a sleep starts or
ends. Now **288 of 288**: the cloud that keeps clear of the status icons goes from what
the window was to what it is over the first 0.6 s of the event (`sleepJoin`, in the cloud
loop; the lab's chrome still swaps the island in one frame — port note 16). What was there before the two passes: a dawn wake stepped the frame by up to 7.1
levels (up to 85 % of the pixels over 6); a nap's wake by up to 7.4 levels, with a lit star at
midday; a night sleep arriving from elsewhere was a cut of the whole picture (up to 23
levels); bedtime at 21:00 put the lit star out for a frame (242 levels); on the spread a
leading-page star appeared the instant he went down. (One join was broken and mended inside
this pass: in July, where the sky is too light for stars, the moment's last frame drew the
first night's star faintly and the standing frame after it did not — 31 levels at (262, 43);
the moment now shows stars there only by the band and by what it leaves them.)

## Cost (headless Chromium, software raster, dpr 2, canvas forced to rasterise)

Every figure here was taken on a machine shared with other shooting jobs (load 5–8 on 4 cores):
read them as ranges and as "the same order", never as a fine comparison.

| | cover | spread | slab |
|---|---|---|---|
| first `render()` (textures, tree, clouds, every plane), bare tree | 0.64–0.85 s | 1.20–1.45 s | 0.53–0.60 s |
| first `render()` in leaf (July, October, April) | 0.65–0.86 s | 1.43–1.83 s (the verifier's) | 0.59–0.90 s (the verifier's) |
| steady frame, only `t` moves, no sun in view (12:30, 21:00, the looked-up night), median | 3.2–8.2 ms | 6.2–10.6 ms | 3.0–5.8 ms |
| steady frame **with the sun in view** (16:10 dark and light, July 20:15 at rest, July 19:40 looking up), median — before: its halo filled through a blur filter every frame | 34.5–52 ms | 57–92 ms | 37.1–44.2 ms |
| …now: the halo's two rings painted once into sprites (`drawSunHalo`) | 3.6–4.8 ms | 6.3–8.5 ms | 3.1–5.0 ms |
| a new minute (sky, tree and every plane repainted) | 0.48–0.67 s | 0.95–1.16 s | — |
| a held bedtime frame, compose only | 5.8 ms | 7.1 ms | 4.4 ms |
| a held bedtime frame with the band, rasterised (round three's first pass) | 11.8 ms | 23 ms | — |

By part, at the first `render()`:

- **The sky** 0.10–0.17 s cover, 0.17–0.22 s spread (the one per-pixel pass).
- **The land** 0.22–0.42 s cover, 0.64–0.73 s spread. Dark, at full night (sun under −10.6°), each
  plane is painted four times too bright and brought down once through a noise fixed to the
  world, and the mist layers between planes are laid through the same noise (the faint straight
  edges in the night land were washes rounding to whole levels in a range of two dozen): about
  0.04–0.05 s more on the spread there, and only there (the craft pass's figure; not re-measured). The pale page's temperature and the air at
  each plane's foot are colours, not passes: free.
- **The river** 0.04–0.06 s (spread only; skipped where the display never sees it). It also leaves
  one small layer (its own shape and a run of mist puffs along its course) for the opening's light.
- **The clouds' masks** 0.01–0.03 s for all of them (they were 0.03–0.05 s as relief, and 0.09–0.18 s
  in round two): four alpha masks a cloud, cut in one pass over a box of its own size — at most
  five times a cloud, once for each side the lamp can stand on.
- **The tree's masks**: bare and in winter 6–14 ms; in leaf 45–110 ms (17–19 masks: 77–110 ms in
  July, 49–84 in October, 77–85 in April; the outline costs nothing that shows in these runs).
  `paintTree` 8–16 ms bare, 25–37 ms in leaf. The pale page's frost is cleaned once per mask set
  (one small `getImageData`).
- **The sun's halo.** A steady frame with the sun in view was nine times the others, as the first
  review found: the halo's two rings were drawn through a `blur()` filter every frame. They are
  now painted into sprites and kept. A held frame's sprites are the old fill through the old
  blur at the sun's own sub-pixel place, so its picture is the old one to the level (the
  signature frame is byte-identical), and they are repainted only when the sun's colour, alpha
  or place changes; while the animation runs the rings are two white masks blurred once per
  display and tinted each frame, within 2 levels of the exact ones. (The "sun in view" rows:
  four runs of thirty frames each side, before and after interleaved, with other shooting
  running on the machine — inflated and noisy; the ninefold is not noise.)

Nothing new is painted for the night's pose. The bedtime band is drawn at a quarter of the size
and enlarged (it has no detail). During an event the planes are not repainted: the camera
translates them, and the change of tone is one brightness/saturation adjustment over the painted
layers; they are painted exactly again, once per event, when the tone has been still for 1.2 s.
The tone's steps are fine (presence 1/120, the dimmed room 1/60), so a slow settling repaints the
planes a few times a second *in a held frame or a film*; while an event plays live they are not
repainted at all.

## SwiftUI port

1. **Air** — `air.js` is pure: ~250 lines of Swift giving `skyAt`, `hazeAt`, `mistAt`. Free.
2. **Sky** — the only per-pixel layer. Either a small `colorEffect` shader (two ramp
   lookups, the arch, the sun's glow, dither, and the night band kept under the dimmed room)
   or a `CGImage` filled off the main thread once a minute from the same 2-pt grid.
3. **Stars** — `Canvas`, two symbols (and one soft patch in the light appearance), ≤ 368 of
   his + ≤ 460 ordinary on the spread, `TimelineView` at 10 fps, night only.
4. **Sun, moon, tonight's star, the band** — `Canvas` paths and a few radial gradients (the
   band is one `RadialGradient` with eleven stops under a vertical `LinearGradient` mask that
   ends it above the horizon; drawn small and enlarged). The sun's halo is two blurred discs:
   a pre-rendered image (or a blurred shape), never a blur per frame. **The moon's and the
   sun's disc need the cards' frames**: looking up, a disc is drawn only where it stands
   whole in the open (`standsOpen`), so the sky has to know where the list's rows are in its
   own space (an anchor preference from each row, collected by Home and handed to the sky) —
   and when the list scrolls, the rule follows the rows. The same frames mask the tree
   (`treeBehind`): the tree's layer takes an alpha mask that is the union of the rows' rects,
   each feathered 8 pt inward, weighted by the rows' opacity and by `look`.
5. **Clouds** — five small shapes (one on the slab), each a `Path` under one hand-set contour
   (the table's masses run together and smoothed: thirty lines) with four alpha images cut from
   it once — body (its foot fading to nothing), the light on its top, its low part, the rim line
   for the side the lamp is on — tinted by `paintCloud`'s few colours, each held to a contrast of
   the sky behind it (`heldTo`). The three rules that hide one are pure functions of the layout:
   the status icons' foot (and `sleepJoin` over the first 0.6 s after a sleep starts or ends),
   the cards' rects and opacity (`acrossEdge`), the sun's and moon's discs.
6. **Land** — five `Canvas` layers repainted once a minute and kept as images
   (`drawingGroup`): per shape a `Path` filled with a horizontal `LinearGradient` (a stop
   every 30 pt), blurred stroked paths for the flank's turn (one 210-pt stroke of shade, one
   of light), shade / light / frost drawn into a quarter-size `drawLayer`, the rim as a
   stroked path through a dry-brush image mask. The camera is an `.offset` per layer. On an
   OLED at full night the layers want the lab's dither (painted bright, brought down once
   through a fixed noise texture), or the washes will band; a 16-bit layer would do the same.
7. **River** — its two banks are a `Path` computed once (the projection is twenty lines);
   the fill is a vertical gradient through that path drawn eight times at slightly different
   scales about its vanishing point (the feather), then gradients, some sixty soft ellipses
   (streaks, glints, mist, the moon's forty), three or four ribbons under the far bank, four
   rotated strokes of sheen, and ~20 short filled blades for the reeds, clipped to it.
   Pre-rendering it per minute as part of the far plane is the honest plan; the opening's
   light is that same shape plus mist puffs as one alpha image, tinted and wiped by a
   gradient mask for a second.
8. **Tree** — masks pre-rendered by `tree.js` at three sizes for each state of the season,
   tinted: wood and twigs always; frost and the last leaves (now); snow and its hair on the
   twigs (winter); blossom × 2 (spring); and in leaf seventeen to nineteen — the far side, the
   twigs in sight, the near masses in three paints, the near leaves by the way each is turned
   (eight), the thin ones, and the same cut larger (the gaps a disc of light opens). The wood's
   lit edge is its mask minus itself slid. In the app these ship as images: the 45–110 ms a
   leaf state costs to cut here is not paid on the phone.
9. **Mist** — four level bands on the valley side (one texture, a gradient tint) and three
   pooled layers on the hill side: an alpha mask each, pre-rendered (they depend only on the
   crest in front) — mist lying ON the land as a thin layer along that crest, 4–23 pt deep,
   deeper where the crest dips, its top in long torn threads — each with an `.offset` that
   breathes.
10. **Tone during events — do not port what the lab does.** The lab lays a change of tone
    over the painted layers as one `brightness()` / `saturate()` filter and repaints exactly
    when the tone has come to rest. Measured live (cover, dark, 1×; `tools` of the motion
    review): on a near-black sky an 8-bit layer cannot be multiplied — its values are 5–12
    levels, so each code can only step by 10–20 %, and *any* brightness below 1 takes every
    pixel down a whole level at once (−0.98 level over the whole frame in one frame, 11 % of
    the sky's light, where the factor first leaves 1); and the exact repaint that ends an
    event is a step (+2.9 levels after a dawn wake, +1.1 after a 03:00 wake) and a dropped
    frame or ten (130–260 ms here). So in the app:
    - **never multiply 8-bit layers on a near-black sky**: no `.brightness`, no `.saturation`,
      no `.opacity` ramp of a darkening layer over them;
    - **carry `presence` and `depth` as uniforms of the sky's `colorEffect` shader, ahead of
      its dither**, so the tone is continuous in float and is quantised once, by the dither;
    - **the land's layers: paint the tone the event starts from and the tone it ends at, and
      cross-fade the two images** by opacity (or run the same shader over them) — a
      cross-fade of two dithered images is still dithered;
    - **repaint off the main thread and swap the finished image in**, so a settling tone never
      costs a frame.
    What this pass changed in the lab is only that the planes are repainted exactly *once*
    per event (the tone is judged still by its true value, not its stepped one: the old test
    went back and forth between the exact paint and a filter of 0.999 three times at the end
    of bedtime), and that no filter is applied within 0.2 % of 1. The steps above remain in
    the lab's live play; its stills and films are painted exactly at every frame.
    **Caption** — `Text`.
11. **The looked-up view is a state, and the app derives it; it stores nothing.** *The night
    has begun* is a pure function of the clock, the sun and the sleep log: true from the
    start of tonight's first night sleep (the app's own definition of one: BRIEF.md, round
    three — an evening sleep, 6 pm to 4 am) until the sun next comes up through −7° at the
    household's place. `look` rests at 1 while it is true and at 0 otherwise, so it **persists
    across launches** — Home opened cold at 3 AM is already looking up, and Home opened at
    7 AM is on the hill — and tonight's star is lit by the same fact. **`look` and `depth` are
    their own animated values**, each with a target and a current value, not functions of one
    event's age: a change of target (the night begins or ends; a sleep starts or stops) eases
    the current value from wherever it is, so one event arriving during another — the Duo
    opening mid-rise, a wake a second after bedtime — cannot jump the camera. (The lab's state
    carries one event at a time and cannot show this: there `open` during `bedtime` snaps.)
    What animates `look`: a night sleep started *by hand on this phone* that begins the night
    (the full moment, once a night); a night sleep that begins the night from anywhere else
    while Home is on screen (the quiet rise, 2.5 s, behind the cards); first light while Home
    is on screen (the quiet settle, 2.6 s). Nothing else: not a wake, not a feed, not a second
    sleep the same night. If Home was not on screen, it is simply in the right pose when it
    appears. `depth` eases across every sleep's start (from 0) and end (from that sleep's own
    depth) so the first frame after a change is the frame before it. On the open Duo the
    phone page's sky view and the leading page's are two views with two clocks: **one shared
    driver** (an observable `look`, or one `TimelineView` date passed to both) must feed both,
    or the horizon breaks at the fold during the move. Under Reduce Motion the driver is an
    opacity between the two stills, 0.6 s long (not the camera's curve: a two-second dissolve
    is two trees on screen for two seconds), and tonight's star is drawn with the looked-up
    still only.
12. **Tonight's star** is not on any plane: its place is `lerp(rest home, window home, look)`
    in the display's own points (the window home comes from the strip's safe-area geometry on
    the Duo and the header's on the slab — the lab reads `state.layout`). The band's centre is
    the window home, constant. The first night's star is one more hand-set place (the Duo's
    only). While `look` is between 0 and 1 every other star within 30 pt of tonight's gives
    way (an opacity by distance: nothing runs through it on the way up).
13. **Which sleep ended** — the port tells the sky which sleep ended only for the room's
    dimming (un-dim from a night's 1 or a nap's 0.45); the camera does not need it. The lab
    takes `woke=`, or goes by the hour.
14. **The layers' resting offsets must be on the pixel grid.** `.offset` is fractional, so the
    move itself is clean on a phone; but the near planes' looked-up offsets (349.44 and
    405.6 pt down, 99 and 112.5 pt left) are not on a ⅓-pt grid, and a layer left there sits
    resampled — soft — all night. Round each layer's offset at each pose to whole device
    pixels (the lab rounds each plane's whole travel: 349.5 and 405.5 pt at 2×), and let the
    move run between the two rounded values.
15. **The bedtime moment is one timeline, and a touch ends it.** lab/presence.js `MOMENT` is the
    table (seconds since the tap): cards out 0–1.0 (`.easeInOut`), the rise 0.3–2.4 on the Duo
    and 0.3–2.7 on a slab (a quintic; pick the duration from the travel so the peak stays
    under about 500 pt/s), the band from 2.1 (2.3), the caption 2.0–4.6, cards back 4.6–5.8
    (`.easeOut(duration: 1.2)`). **Any touch on Home ends it at once**: the cards are back in
    0.3 s, the band and the caption are out in 0.2 s, and the view stays up — `look` keeps
    its target of 1 and runs on at its own pace; nothing is brought back down, and the star
    stays lit. So the cards, the caption and the band need their own cancellable animations
    (a touch replaces their targets); `look` is not among the things a touch changes. The lab
    has no touch and shows none of this. Under Reduce Motion the table is `MOMENT.reduced`.
16. **The strip's clear window must follow the island as it animates.** The lab's chrome swaps
    the longer island in within one frame when a sleep starts or ends; the strip's cloud,
    which gives way to the longer island, follows over 0.6 s (`sleepJoin`), or it pops. In the app, drive whatever hides behind the island from the
    island's own animation (or simply from the sleep's start, over the same 0.6 s).

**Riskiest:** still the land painter — ~45 blurred strokes clipped to their shapes and washes
laid small and enlarged; that has to be re-proved in `Canvas` on a phone. Second: tone during
events (note 10) — the lab's own way steps by whole levels on the dark sky, measured; the way
proposed there (uniforms ahead of the dither, a cross-fade of two paintings) has not been
built anywhere yet.

## Still not good enough

Most serious first. Items 1–7 are the night's, as they stand after the passes "the night stays
up", "the night rule and the joins" and "the moment and the looked-up night"; the rest stand
from round two and belong to the drawing passes of this round, which may have answered them.

1. **With the cards on, the night is two stars and their company — not a place.** That is a
   decision (see "The tree is not seen…"), and on the Duo the strip's window is a good small
   picture; but the land, the tree and the moon — everything that makes this sky *this* sky —
   are behind the cards from bedtime to first light. In the dark appearance nothing of the
   land shows at all. The slab's night is one star beside his name.
2. **With the cards on, looking up, the closed Duo never shows the moon's disc** — the price
   of "a disc is drawn whole or not at all". It used to show when it happened to cross a gap,
   bitten; now a gap takes only its glow, which is faint (the halo was made "barely there" so
   the room stays dark) and on the light page nearly nothing. The open Duo shows the whole
   disc in the gutter for about twenty minutes of a rising moon's evening. Two ways to give
   the moon back, neither done: let it stand whole in the header's clear gap when it is high
   (the Duo never draws a body in the header band; the gap is 128 pt wide and now holds the
   first night's star), or remap its height for the looked-up pose so that it crosses the
   strip's window (which breaks "one place in the world", the bare frame and the tree's
   burn). The same rule hides the sun's disc behind the sleep card on a July evening; there
   the glass carries a broad warm glow and it reads.
3. **The band is still an arc.** Its first state is no longer a ring round the star: its
   light is held until the crest is 150 pt out. But a wavefront from a point is part of a
   circle; at 2.8–3.0 s it is a large "C" across the sky, and in the light appearance a pale
   ring on a lilac page. Without its light (the answers alone) there is no gesture on a
   newborn's sky or on the light page, so the light stays.
4. **Tone still moves after the view is up, and the lab cannot play it live without steps**:
   the bloom and the dimming room go on settling for seconds after "nothing moves". In the
   films this shows as steps of about a sixth of a level a few times a second from 4 s on (the
   lab's exact frames are tone-quantised) — every "pop" the motion helper still lists inside
   the sky is one of these. Played live, the lab's filter over 8-bit layers still steps by
   a whole level where it first leaves 1 (−0.98 level at 5.2 s of bedtime, at 0.23 s of an
   `arrive`) and the one exact repaint that ends an event is a step after a wake (+2.9 levels
   at a dawn wake, +1.1 at a 03:00 wake, 1.2 s after the tone has come to rest). Port note 10
   says how the app must carry tone instead; none of that is built. **A night feed un-dims
   the room** from depth 1 to 0 over five seconds with the view up — 14 % more light in the
   dark sky; nobody has looked at that in a dark room. Played live, the sun's halo is a
   tinted mask and stands up to 2 levels from the held frame's exact one (inside the halo).
5. **The moment's edges that are specified and not shown.** A touch that ends the moment
   (cards back in 0.3 s, band and caption out in 0.2 s, the view stays up) is written down
   (Bedtime; port note 15) and nothing in the lab plays it. One event at a time: the Duo
   opening during the rise still snaps in the lab. Under Reduce Motion the 0.6 s dissolve
   still has two trees on screen for its length — that is what a dissolve is — and was judged
   from stepped frames only, as all the motion was.
6. **The slab's moment is tighter than the Duo's.** Its sky is twice as tall, so its rise
   was lengthened (0.3–2.7 s) to keep the peak under 500 pt/s, while the cards keep one
   timeline: its band leaves 0.4 s before the view is fully up (2.3 s, the star then 22 pt
   from its place — the band's light is held, so nothing shows the mismatch) and crosses 20 %
   faster than it did (410 pt/s, was 342), and its lowest stars finish answering 0.2 s
   before the cards return, not 0.4 s. A slab's cards could wait 0.3 s longer instead; that
   would be a second timeline.
7. **Light appearance, looking up**: the whole page behind the cards is lilac sky (ground
   median ≈ 0.63–0.66 luminance against a page's 0.89; white cards read well on it, but it is
   not "close to the page"). The light-page stars are now glints and points and no longer
   snow, but the glints are one sprite at several sizes — a little mechanical at 3×. The
   tree's ghost through the lab's glass now fades out before the card's edge; awake in the
   night, under the shorter Sleep tile, that leaves a crown and limbs with no trunk beneath
   them (the trunk stood in the 12 pt gap), which is clean and a little odd.
   **The leading page at night, looking up**, is the ordinary sky over a dark low valley:
   calm, and the opening's stars-from-the-fold is still slight, though its front now reaches
   the margin column before the cards land. During the bedtime moment the leading page does
   nothing at all now (the band and its answers are the phone page's): it is a bare, still
   sky for three seconds.
   **Rest at night is now a rare picture, and thinner than round two's** (cover 62 of his
   stars in view, was 71; in the open with the cards on 41, was 47; slab 29, was 33): it is
   seen only in the evening before bedtime and from first light to sunrise. The tree's
   silhouette under his stars at 21:00 and 03:00 — round two's awake night — is no longer
   shown at all once the night has begun; that follows from the director's reading of
   "looking back down is too much", which has not been put to Taylor. A sky that fills over a
   year is dense by July (368): tonight's star keeps its 30 pt of dark, but its window holds
   twenty-seven others. **The first night's star has a place of its own only on the Duo**; on
   the slab it is under the Today card. **The strip's cloud follows the island over 0.6 s**
   across a sleep's start and end (`sleepJoin`) because the lab's chrome swaps the island in one
   frame; the distance (34 pt, `ISLAND_GROWS`) is the lab's layout, hard-coded. **During a move the clouds
   are still on whole pixels** while the sky and the land are between them (their loop is the
   day pass's). **The lab's awake rule is a stand-in** (the sample bedtime, 20:10): the app has
   the sleep log.
8. **July bedtime**: the dark sky at +7° is a lighter slate, so his stars are faint in it;
   seven clouds in view looking up before dark is two or three too many (clouds: not this pass).
9. **The drawing, as it stands after round three's three passes** (the crowns, the craft pass,
   the last drawing pass), most serious first:
   - *Clouds* are quiet now, and at 1× in the dark appearance by day the strip's and the gap's
     banks are close to not there (mean 1.17 : 1). Each is one contour and a ramp: at 3× a
     soft rounded mass with a crisp top and nothing inside it. The large bank still stands at
     the height of the leading page's title, to its right (it cannot be longer than 138 pt
     without showing on the cover). The cover has no large cloud, by the first review's wish.
   - *The pale page's stars* are round points; 368 white points on a pale page can still be
     taken for flecks at arm's length. In both appearances the month-nights' four-point marks
     are no stronger than the brightest ordinary nights: their size is drawStars' (the
     half-span 0.52; the illustrator asked for about 0.70) and was not changed.
   - *Crowns in leaf*: the outline is rounded masses now; the twelve near forms inside it are
     the crowns pass's hand-set ellipses, and top-lit a few of them still read as pads at 3×.
     Spring leaves single flowers standing outside the masses. Autumn in the dark appearance
     after sunset rests on a few gold leaves and the patches' silhouette. Lit by eight
     directions; not filmed through a day.
   - *The pale page's land at midday*: the planes are told apart by temperature, and are still
     within about eight levels of one another in value — a pale page, by the hush's design.
   - *The river*: two small clumps of reeds (6–16 pt), nearly gone on the pale page; the
     moon's path is a convention, not geometry; the middle reach's four strokes of sheen are
     slight.
   - *Winter dusk, dark*: the ground under the Feed and Diaper tiles is still four to five
     times a card's luminance (0.047 and 0.060; it was 0.055 and 0.068); only the Sleep tile's
     came down by a third (0.050 → 0.034). The knoll's snow, in the strip, was kept.
   - *The daytime land's one-level plaid* (quarter-size washes, a gradient stop every 30 pt) is
     still there with the levels stretched: the dither runs only at full night, for its cost.
   - *The pooled mist's threads* can read as level streaks.
   - Left to the sun's and the moon's own drawing: the pale page's sun has no edge of its own
     and its halo is paler than the sky; by day the moon is a flat ghost disc; at sunrise the
     sun's glare lies over the land in front of it; on the slab the sun sets behind the gear.
10. **Answered since round two** (so the list's history reads): the clouds as small soft-bodied
   things (redrawn twice); the crowns in leaf as a flatter hand; the level-topped mist pool;
   the river's pinched waist and tick-sized reeds; the brown band behind the tree at 17:30 in
   dark (item 15's last clause: the low key has its own ember-to-plum column there); the faint
   straight edges in the dark-night land (item 13's first sentence: they were washes rounding
   to whole levels in a range of two dozen — the planes are dithered there now, and a faint
   contour remains round lit mist at 8×).
11. **Light appearance**: the river at night is nearly gone (on purpose).
12. **Slab.** The sun never shows through the limbs at the signature hour (it sets behind the
   gear button); no cloud at rest.
13. **Faint axis-aligned edges (~1 level) in the dark-night land** at 6× brightening; cause
   not found. Needs an OLED in a dark room. So does the whole dark night: the star's glow
   (peak luminance 0.889, 82 pt² of it lighter than a card — see Gates; the cover's one 8 pt
   block reads 0.047; the area around it 0.008–0.009 against a card's
   0.0117) was sized by the ruler, not by an eye in a dark room.
14. **The mist's breathing steps a quarter of a point at a time**; at dawn, where the mist is
   bright on a dark land, a step shows in a film as a one-frame shimmer along the horizon
   (0.3 % of the pixels) — the wake film has one at 0.33 s.
15. **Dark by day** was judged from stills only. `close` does nothing of its own. The
   earth-shadow at 16:40 is slate, not teal; the brown band behind the tree at 17:30 in dark
   is as it was.

## Lab notes

- `look=` is not a viewer parameter; the module reads `location.search` (as the brief
  asks). `--param look=1` works with `shoot.mjs` and `measure.mjs`.
- `measure.mjs --stars-by-age` counts the caption's changed digits as stars when the veil
  is up (144 of 142). Its light-appearance "bright / dark" point detector is approximate: on
  the slab it finds 136–138 bright points where the by-age count finds all of them.
- The viewer sets `state.frozen` on a held frame; the module draws those exactly (no
  tone adjustment over old paint).
- `event=resettle` is gone; `arrive` and `settle` are new, `wake` takes `woke=night|nap`, and
  `begun=1|0` (once `lit=`) forces "the night has begun" — README has the table of what the
  lab does with each event and with one that does not fit. `state.nightBegun` is the fact;
  `state.tonightLit` is the same boolean, kept for the other skies and `tools/measure.mjs`.
- `tools/review.mjs` `bedtime` frames are t0, **t0_5**, **t1**, t3, **t4_1**, **t5**, t9, t40:
  the tap, the cards half away, the cards gone and the view rising, the band crossing, the
  poster (the band gone, the caption still whole), the cards half back, back, settled. Four
  folders changed name with the timeline — `t0_7` → `t0_5`, `t1_6` → `t1`, `t4_4` → `t4_1`,
  `t5_8` → `t5` (the cards went over 1.6 s and returned over 4.8–6.8 s); `t0`, `t3`, `t9` and
  `t40` are the same instants as before. The sets `wake` and
  `resettle` are gone; `night`, `arrive`, `settle` and `joins` are new (718 shots in all).
  `asleep/` and `open/night/` are the looked-up pose, **and so are the `day`, `bare` and
  `tilt` sets' 21:00 and 03:00** (awake after the sample bedtime: the night has begun).
- `tools/film.mjs` opens on the standing state *before* its event (`--before`), so a film
  shows the join at its own first frame; `--event arrive|settle|wake` are new. A bedtime film
  runs 7 s by default (it was 8: the cards are back at 5.8 s, and 1.2 s of stillness follows);
  its cards follow lab/presence.js `momentVeil`, and with `--param motion=0` the shorter
  Reduce Motion moment.
- `band=answers` (read from `location.search`, like `look=`; `--param band=answers`) plays the
  bedtime band without its own light — only the stars' answers — to compare with the held
  band, and to measure the band's light alone (the difference of two films).
- `tools/joins.mjs` measures every join (see Gates). It looks only at an event's two ends;
  what happens inside the bedtime timeline is in the 60 fps films. The strip's cloud, which
  the lab's chrome switched off and on with the clear window in the frame a sleep starts or
  ends, no longer shows in it: the cloud follows the window over 0.6 s (`sleepJoin`).
- The disc detector takes a moon crossed by branches, or a soft-haloed star, for an
  "unknown blob" and leaves it in the ground; the star's glow here is small partly for that.
- `window.__hillPainted.timing` carries per-part timings (`geometry`, `sky`, `land`, `river`,
  `clouds`, `tree`, `treeMasks`); add `hpTiming=1` to the URL to make each frame rasterise.
