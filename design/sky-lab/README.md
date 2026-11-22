# Sky lab

A browser mockup bench for Home's sky (`TwoOfUs/DesignSystem/SkyBackground.swift`):
the real Home screen drawn over a swappable sky, at the real display sizes, at any
time of day, in both appearances. Mockups only — the app's sky is the Swift code.

    cd design/sky-lab && python3 -m http.server 8377      # then open http://localhost:8377/?ui=1
    node tools/shoot.mjs --sky baseline --sheet           # PNGs into shots/baseline/
    node tools/test-math.mjs                              # the maths against the Swift

`BRIEF.md` is the design brief a new sky answers to.

## Files

| File | What |
|---|---|
| `index.html` | The viewer. Reads the URL, builds a `state`, mounts the sky module and the chrome. With `ui=1`, a small control panel (time slider, toggles). |
| `lab/core.js` | Device presets, URL → `state`, the animation loop. |
| `lab/solar.js` | `SolarClock` + `MoonClock` ported from Swift, plus the sun's altitude/azimuth. Pure. |
| `lab/palette.js` | `SkyPalette` ported from Swift (looks, frames, ridges, clouds, stars, `scene()`). Pure. |
| `lab/chrome.js`, `lab/chrome.css` | Home's UI as HTML: the phone page, the spread's leading page, the system strip / tab bar. Sample data, one fixed day. Also measures `state.cards` and `state.layout`. |
| `lab/presence.js`, `oklab.js`, `nights.js`, `season.js`, `noise.js` | Helpers for new skies (see `BRIEF.md`): the bloom, the room's dimming and the bedtime moment's one timeline (`MOMENT`, `momentVeil`: what the cards do, which `film.mjs` and `review.mjs` play and a sky reads), OKLab colour and the hush, a star per night, the season, seeded noise. The baseline uses none of them. `season(state)` (or `season(dayOfYear, latitude)`) answers with the URL's `snowfall`. |
| `skies/<id>.js` | One sky per file. `skies/baseline.js` is today's sky, ported faithfully. |
| `skies/index.js` | The ids the panel's picker lists (`sky=<id>` loads any file in `skies/`). |
| `assets/` | The cloud and grain PNGs copied from `TwoOfUs/Assets.xcassets/Sky`; `fonts/` is Nunito, the chrome's stand-in for SF Rounded. |
| `tools/shoot.mjs` | Playwright: one PNG per (device × scheme × time), and a contact sheet. |
| `tools/review.mjs` | The review set: every sky shot the same way (day, bare, asleep, seasons, bedtime, the Duo opening, stillness, the header's text, tilt, snowfall, the night as it stands, a night sleep arriving, first light, the joins) into `shots/<sky>/review/`. `--list` shows it and counts it. |
| `tools/film.mjs` | A moment (bedtime, a night sleep arriving, first light, waking, the Duo opening) as a video: the viewer stepped one frame at a time and joined by ffmpeg, so the timing is exact at any render cost. It opens on the standing state *before* the event, so a film shows its own first frame's join. Bedtime runs 7 s by default (the cards are back at 5.8 s); `--fps 60` for judging motion; `--param motion=0` plays Reduce Motion's shorter moment. Into `gallery/film/<sky>/`. |
| `tools/joins.mjs` | No join may jump: for every change of state, the standing frame before against the event's first frame, and the event's last frame against the standing frame after, measured (below). Exit code 1 if one jumps. |
| `tools/measure.mjs` | One shared measurement of `BRIEF.md`'s hard limits for any sky; `--help` lists options. |
| `tools/test-math.mjs` | The Swift unit tests for the sun, moon and palette, ported, and the port checked against the Swift source; then what the viewer adds to the state (`sun.x`, `nightBegun` and what an event means in it, the room's dimming across a sleep's start and end, `snowfall`). |
| `tools/chrome-preview.html` | The chrome alone over a flat gradient, for working on `lab/chrome.js`. |
| `shots/` | Output. Not committed. |

## Displays

Points; canvases are drawn at `state.dpr`.

| `device` | Size | Notes |
|---|---|---|
| `cover` | 466 × 678 | iPhone Duo closed. System strip (status, Dynamic Island, tab bar) is an 84 pt column on the trailing edge. Content margins 20 pt, 22 pt above the header. |
| `spread` | 951 × 669 | iPhone Duo open, landscape. Strip 84 pt trailing. Fold crease x 475.5, band x 455.5–495.5. Leading page x 97.5–447.5; phone page x 485–867 (its rows at 505–847). Head line y 22, top line y 103, foot line y 635. |
| `iphone` | 402 × 874 | A slab iPhone. Status bar on top, floating tab capsule at the bottom, 16 pt margins. |

**One world, two windows.** The cover's sky is the anchor. On the spread, the phone
page keeps exactly the cover's sky where it was (`state.phone = {x: 485, width: 466}`),
and the leading page shows the same world running on to the left. A sky module
draws one continuous picture across the whole display, with the world's x = 0 at
`state.phone.x`. On `cover` and `iphone`, `state.phone = {x: 0, width: state.width}`.
(The spread is 9 pt shorter than the cover. The baseline, like the Swift, lays its
sky out on each display's own height, so open and closed differ by up to 9 pt in y.)

## The sky module contract

```js
// skies/<id>.js  (an ES module)
export const meta = { id: 'baseline', name: "Today's sky", blurb: 'One line.' };

/** host: an empty <div> filling the display (position:absolute; inset:0; overflow:hidden;
 *  isolation:isolate — its own stacking context, so a z-index inside it never comes out
 *  above the chrome). Add canvases / DOM inside it. Never touch anything outside it. */
export function create(host, env) {       // env = { assets: 'assets/', solar, palette } (the two lab modules)
  return {
    render(state) {},                     // called every animation frame, or once when frozen
    destroy() {},
  };
}
```

`state` (all lengths in points):

```js
{
  device: 'cover' | 'spread' | 'iphone',
  width, height, dpr,
  phone:  { x, width },                 // the anchor window (see above)
  fold:   null | { x, bandMinX, bandMaxX },
  strip:  null | { side: 'trailing', width: 84 },
  scheme: 'light' | 'dark',

  date,                                 // a JS Date (the instant)
  tzOffsetHours,                        // local = UTC + this (lab default −6, America/Chicago in November)
  latitude, longitude,                  // lab default 41.88, −87.63
  dayOfYear, localHour,                 // conveniences (localHour is fractional, 0–24)

  sun:  { altitude, azimuth,            // radians; altitude < 0 below the horizon; azimuth from north, clockwise
          isNight, progress,            // SolarClock.phase: 0–1 through the day, or through the night
          sunrise, sunset,              // Dates
          x },                          // the sun's own x, a fraction of the anchor window, day and night (below)
  moon: null | { altitude, azimuth, fraction, phase, rotation, passProgress, inDaylight, x, y },
                                        // as SkyPalette.Moon (x, y fractions of the anchor window); null while it is down
  scene,                                // palette.scene(...) — the Swift `SkyPalette.Scene`, for the baseline

  asleep: false | 'nap' | 'night',      // a sleep is running
  ageDays,                              // how old he is (lab default 142)
  nightBegun,                           // boolean: THE NIGHT HAS BEGUN — from the start of tonight's night sleep until first light (below)
  tonightLit,                           // the same boolean under its first name: tonight's star is lit exactly while the night has begun

  t,                                    // seconds, monotonic; frozen when the URL has t=
  frozen,                               // true while the clock is held (t=): the frame stands alone, so draw it exactly
  reduceMotion,                         // true with motion=0
  cards: [ { x, y, width, height, kind, opacity } ],   // where the chrome is, so a sky can compose around it ([] with chrome=0)
  layout: { name, age, avatar, gear,    // rects { x, y, width, height }: the header's text and buttons (below)
            firstCardTop,               // y of the first card under the header
            stripClear,                 // null | { x, width, yMin, yMax }: the Duo strip's clear window
            title, subtitle,            // null | rects: the spread's leading page's title and the line under it
            measured },                 // true; false only where no chrome could be laid out

  tilt:  { x, y },                      // −1…1 each, for parallax; 0, 0 unless tilt= (or the panel's pointer tilt)
  event: null | { kind, age,            // 'bedtime' | 'arrive' | 'settle' | 'wake' | 'open' | 'close', and seconds since (below)
                  begunBefore,          // had the night begun before the event?
                  woke },               // a wake's only: 'night' | 'nap', the sleep that ended
  lead,                                 // only with lead=: the spread's leading page's opacity, 0–1
  veil,                                 // only with veil=: how far the phone page's cards have fallen back, 0–1 (in the bedtime moment: lab/presence.js, momentVeil(event.age))
  snowfall,                             // only with snowfall=: snow in the air, 0–1 — what season() then says
}
```

`cards[].kind`: `hero`, `timeline` and `detail` (the leading page's cards, Tonight's
Schedule) are opaque; `tile`, `sleep` and `tabbar` are glass — the sky comes through,
blurred and tinted; `toast` is the undo toast. Two are not surfaces but text and icons
on bare sky: `header` (the avatar, name and age; the leading page's title) and `strip`
(the Duo's whole 84 pt column, or the slab's status bar). `cards[].opacity` is what the
card is drawn at: 1; `1 − veil` for the phone page's cards under the veil (they stay in
the list at 0; the header, strip and tab bar stay at 1); `lead` for the leading page's
(at `lead=0` they are not in the list).

`layout` is where the text on the sky is, measured from the chrome's own DOM — and laid
out, unpainted, with `chrome=0` too, so it is the same with the UI on or off. `name`,
`age`, `title` and `subtitle` are the boxes of the glyphs themselves (their ink: on the
cover "Miller" is x 96–188, y 29–55, and "4 months old" x 94–185, y 68–80), not their
rows. Against the rendered pixels the ink never reaches more than 0.3 pt outside a box,
and a box is never more than 1.5 pt outside the ink (the top edge of a line with capitals
or digits is the loosest); `avatar` and `gear` are the 60 pt and 44 pt circles' boxes.
`title` and `subtitle` are null except on the spread, and there even at `lead=0` (they
arrive with the cards, at opacity `lead`). `stripClear` is the Duo's column between the
status icons under the Dynamic Island and the tab capsule, from the cards' trailing
edge to the display's (cover: x 362, width 104, y 151–396; `yMin` is 185 while a sleep
runs and the island is longer); null on `iphone`.

**The night has begun** (`nightBegun`; `BRIEF.md`, "After the first review"). One fact:
true from the moment tonight's night sleep first starts until first light the next
morning, whether he is asleep or awake. While it is true a sky looks up and tonight's
star is lit (hand it to `nights()` as `tonightLit`). In the app it is a pure function of
the clock, the sun and the sleep log. The lab has no sleep log, so (`lab/core.js`,
`nightHasBegun`, `nightOf`):

- **the night's hours** run from the evening — sunset, or 18:00 while the sun is still
  up — to **first light**, the morning minute the sun comes up through
  `FIRST_LIGHT_DEG` = −7° (06:12 on the default day, 04:35 on 21 June). Outside them it
  is false whatever `asleep` says: a summer morning with him still asleep is the day's
  picture, dimmed;
- inside them it is true while `asleep` is `night`, after a `wake` whose `woke` is
  `night` (a feed: the night goes on), and — awake or napping — once the sample day's
  bedtime has passed (20:10, `SAMPLE_NIGHT`). So awake at 18:30 is not yet the night;
  awake at 21:00 or 03:00 is;
- `begun=1|0` forces it (`lit=` is the parameter's old name). With an `event` it says
  how the night stood *before* the event;
- the lab keeps nothing from one state to the next. So the awake frame that stands after a
  night sleep begun early and ended before 20:10 (down at 19:40, awake at 19:55) has to be
  told `begun=1` — by the hour alone the night has not begun there — and the wake itself
  `woke=night` (`tools/joins.mjs`, `wake-night-early`, shoots exactly that).

**Events** say that something changed `eventAge` seconds ago (`event.age` then runs on
with the clock). What it changed *from* is the lab's to work out, or the URL's to say:

| `event` | What happened | What a sky does | Where it does not fit |
|---|---|---|---|
| `bedtime` | A night sleep was started by hand, and the night begins with it (`asleep=night`) | the moment (`BRIEF.md`): the view rises, the star is lit, the band, the cards return | The night had already begun (a feed; any hour after the sample bedtime), or `asleep=nap`: there is no moment — it is played as `arrive`. `begun=0` says the night had not begun. `asleep=0`: dropped |
| `arrive` | A sleep began elsewhere (the other phone, Siri, a widget, SNOO) | a night sleep that begins the night: the quiet rise behind the cards. Otherwise (a nap; the night had begun) only the room dims | `asleep=0`: dropped |
| `wake` | The sleep that was running has ended; `woke=night\|nap` says which (unsaid: the night's before 09:00 and from 20:10, a nap's between) | nothing moves; the room un-dims from what that sleep had (a night's 1, a nap's 0.45), and the sky has no bloom for it | a sleep is running: dropped. A night sleep that ends in the evening before 20:10 must be said (`woke=night`): unsaid it is a nap's, and `state.eventNote` says so |
| `settle` | First light: the night that had begun is over | the quiet settle behind the cards | not morning, not yet first light, more than half a degree past it (`SETTLE_WITHIN_DEG`: three to five minutes), or no night had begun: dropped |
| `open`, `close` | The Duo opened, closed | (the sky's own) | |

A dropped event leaves the standing frame (`event: null`). Whenever the lab drops an
event or plays it as another, `state.eventNote` says so (the panel shows it; `film.mjs`
prints it). The room's dimming (`presence().depth`) eases across every one of these, so
an event's first frame is the standing frame before it.

`snowfall` is absent unless the URL has it; `season(state)` — and
`season(dayOfYear, latitude)`, which the viewer tells too — then answers with it,
whatever the date (the snow lying on the land is still the date's).

`sun.altitude` is the centre of the disc without refraction, so it reads about −0.8°
at `sunrise` and `sunset`; `sun.isNight` turns exactly there. In `scene.body` and
`moon.x` the anchor window looks south: both rise at its left and set at its right.
At night `scene.body` is the baseline's night-progress arc, not the sun; `sun.x` is
the sun: `scene.body.x` while it is up (0.04 at sunrise, 0.96 at sunset), then on at
the same pace off to the right (> 1), and back from the left (< 0) to 0.04 at sunrise —
continuous through both. It jumps from far right to far left once, mid-night; and at
local midnight it hops by up to 0.004 (2 pt on the cover — the Swift night clock handing
one day's sunrise and sunset over to the next), always while it is outside the window.

Rules for a sky module: draw only inside `host`; deterministic for a given `state`
(seeded randomness, no `Math.random()` at render time); resize when `width`,
`height` or `dpr` change; no network. Optional: `create()` may be async, `render()`
may return a promise (the viewer never overlaps two renders), and the object may
carry `ready`, a Promise for textures still loading — the viewer waits for it and
renders once more before it calls the frame drawn. A sky whose camera turns may say where it
drew the sun and the moon, `window.__skyBodies = { sun, moon }` (display points, or null):
`tools/measure.mjs` then also takes a disc within 12 pt of that place for that body (the
tool's own notes on method, `disc`, printed with `--json`).

## The viewer's URL

`index.html?sky=baseline&device=spread&scheme=dark&time=17:10&asleep=night&chrome=1`

| Param | Values | Default |
|---|---|---|
| `sky` | a module id in `skies/` | `baseline` |
| `device` | `cover`, `spread`, `iphone` | `cover` |
| `scheme` | `light`, `dark` | `dark` |
| `date` | `YYYY-MM-DD` (local) | `2026-11-21` |
| `time` | `HH:MM` (local, 24 h) | `16:10` |
| `lat`, `lon`, `tz` | degrees, degrees, hours (a fixed offset: Chicago in summer is `-5`) | `41.88`, `-87.63`, `-6` |
| `asleep` | `0`, `nap`, `night` (the night's sleep: the cards say "sleeping" whenever it began. The app itself — `SleepLanguage.swift` — calls a sleep that starts before 8 PM "napping" for its first two hours, so its 19:40 would read "MILLER IS NAPPING") | `0` |
| `age` | days | `142` |
| `chrome` | `1` the Home UI over the sky, `0` the sky alone | `1` |
| `t` | seconds — freezes the animation at this instant | (running) |
| `motion` | `0` = Reduce Motion | `1` |
| `dpr` | 1–3 | `2` |
| `ui` | `1` shows the control panel | `0` |
| `bezel` | `1` draws the device around the display | `0` |
| `event`, `eventAge` | `bedtime`, `arrive`, `settle`, `wake`, `open`, `close` (above); seconds since it began | (none), `0` |
| `woke` | `night`, `nap`: the sleep an `event=wake` ended | (by the hour) |
| `lead` | 0–1, the spread's leading page's opacity (`0`: the panorama before its cards arrive) | (1) |
| `veil` | 0–1, how far the phone page's cards have fallen back (`1`: only the header and the system strip remain — the bedtime moment) | (0) |
| `tilt` | `x,y`, −1…1 each | `0,0` |
| `toast` | `1` shows the undo toast | `0` |
| `snowfall` | 0–1, snow in the air whatever the day (`1`: falling hard; `0`: a clear day) → `state.snowfall`, `season().snowfall` | (the day's own) |
| `begun` | `1`, `0`: the night has begun, or has not → `state.nightBegun` (the view up, tonight's star lit); with an `event`, as it was before it. `lit` is its old name | (by `asleep`, the hour and the sun) |
| `zoom` | 0.25–4, the display's size on screen; with `ui=1` or `bezel=1` only | `1` |

The display is the element `#display`, exactly `width × height` CSS px, at the
page's top-left when `bezel=0` and `ui=0`. When a frame is fully drawn (fonts and
images loaded, the sky rendered once) the viewer sets `window.__labReady = true`.
If the sky cannot be drawn, `window.__labError` holds the message instead. For
tools, `window.__lab` has `params`, `state`, `cards`, `layout` and `set(patch)`.

## Shots

    node tools/shoot.mjs --sky baseline --sheet
    node tools/shoot.mjs --sky baseline --sheet --devices cover,spread --times 21:00,03:00 --asleep night
    node tools/shoot.mjs --sky baseline --sheet --chrome 0 --out shots/baseline-bare

All three devices, both schemes, eight times of day (06:50 09:30 12:30 16:10 16:40
17:30 21:00 03:00), at `dpr` 2 with the animation frozen at `t=12`; the same command
gives the same bytes. Files are `<device>-<scheme>-<HHMM>[-<asleep>].png` and
`sheet-<device>-<scheme>[-<asleep>].png`, in `shots/<sky>/` unless `--out` says
otherwise (a relative `--out` is relative to where you run it). Other variants —
`--chrome 0`, `--date`, `--event bedtime --event-age 3`, `--event open --lead 0`,
`--veil 1`, `--tilt 1,0.5`, `--snowfall 1`, `--begun 1`, `--event wake --woke nap` —
reuse those names, so give each its own `--out`. `--help` lists every option.

    node tools/review.mjs --sky baseline                  # the whole review set
    node tools/review.mjs --sky baseline --only bedtime,open
    node tools/review.mjs --sky baseline --out /tmp/try   # somewhere else than shots/baseline/review

The review set, one folder each under `shots/<sky>/review/`:

| Set | What |
|---|---|
| `day`, `bare` | The standard matrix with the UI, and without. Sheets. |
| `asleep` | A night sleep at 19:40, 21:00, 03:00; `nap/` at 09:30, 13:10. |
| `seasons` | Four dates of his first year, 14 min before sunset and 40 after: all three devices; `<season>-bare/` the spread alone. |
| `bedtime`, `open` | The two showpieces, frame by frame (`BRIEF.md`). Bedtime is shot in November at 19:40 and in July at 19:55 (at 19:40 there the sun's disc stands exactly on top of the tree: `skies/hill-painted.md`). Its cards fall back over 0–1.0 s and return over 4.6–5.8 s with an ease-out — `lab/presence.js`, `momentVeil`, the same curve as `tools/film.mjs`: `t0`, `t0_5`, `t1`, `t3`, `t4_1`, `t5`, `t9`, `t40` (they were `t0_7`, `t1_6`, `t4_4`, `t5_8` while the cards took 1.6 s to go and 2 s to return). |
| `still` | `motion=0`, and `t=95` against the day set's `t=12`. |
| `text` | The minutes the sun (09:30–10:30) and the moon (17:00–19:40) pass behind the header's text: all three devices, with the UI and in `bare/`. Sheets. |
| `tilt` | `left-up/` (`tilt=-1,-0.5`) and `right-down/` (`1,0.5`): cover and spread, 16:10 and 21:00. |
| `snow` | The winter date with `snowfall=1`: cover and spread, its two times. |
| `night` | The night as it stands: `awake/` at 18:30 (before bedtime: at rest), 21:00 and 03:00 (the night has begun: up, star lit); `asleep-nov/` at 06:10 (up) and 07:30 (past first light: at rest, dimmed); `asleep-jun/` at 05:30 and 08:00 on 21 June (the day, dimmed). Each again as `…-bare/`. Sheets. |
| `arrive` | `event=arrive` at 19:40 with `asleep=night`, the quiet rise: `t0`, `t0_8`, `t1_25`, `t2_5`, `t6`. No veil. |
| `settle` | `event=settle` at first light (06:12) with `asleep=night`, the quiet settle: `t0`, `t0_9`, `t1_4`, `t2_7`, `t6`. |
| `joins` | The pairs `tools/joins.mjs` measures, for the eye: `<join>/before`, `age0`, `age40`, `after` — cover, both schemes, UI on. |

726 shots and 72 sheets in 121 runs of `shoot.mjs` (`--list` counts them; it was 532, 36
and 62, then 718, 72 and 117 before the thirteenth join). The whole set has not been timed since it grew: the 532 took a 2-D canvas sky
about three minutes (the baseline: 188 s), and the three new still sets (`night`, `arrive`,
`settle`: 144 shots, 16 runs) took hill-painted 123 s at `--jobs 2` on a busy machine. A
shader sky is slower: headless Chromium draws WebGL in software, about 3 s a shot at
`--jobs 2` for the heaviest (wet-wash: 151 s for `day` alone). Give those `--jobs 2
--timeout 120`, and reshoot single sets with `--only`. (The sets `wake` and `resettle` are
gone: waking moves nothing now, and a re-settle the same night is `arrive` with the night
begun.)

## Joins

    node tools/joins.mjs --sky hill-painted               # every join (13), 3 displays × 2 schemes × sky alone and cards on: 312 pairs
    node tools/joins.mjs --sky hill-painted --only wake-night,settle-nov --devices cover --save /tmp/pairs
    node tools/joins.mjs --list

`BRIEF.md`: for every change of state, the frame before and the first frame after must be
the same picture, and the last frame of every event must be the standing frame that
follows. For each join the tool shoots the standing frame before, the event at age 0, the
event at age 40 and the standing frame after, and prints for both pairs the mean
difference in levels, the share of pixels more than 2 and more than 6 levels apart, and
the largest difference with its place. Sky alone it counts the whole frame but the
header's words; with the cards on, only the open sky (the chrome itself changes when a
sleep starts). Limits, from the picture's grain (a pixel stands about 1.7 levels from its
neighbours' mean): mean ≤ 0.25 levels, ≤ 0.5 % of pixels over 2, ≤ 0.02 % over 6, no
pixel over 12. `--self` shoots each standing frame twice and must print 0. The joins:
bedtime in November and July, a night feed (`wake`, then `arrive`), an early night's wake
before the sample bedtime (`wake-night-early`: told `woke=night`, and its standing frame after
`begun=1`), a nap's wake at 13:10 and 16:10, a nap arriving, a night sleep arriving, first light in November and June, the
morning wake after first light, and bedtime by hand once the night has begun.
