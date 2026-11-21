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
| `lab/presence.js`, `oklab.js`, `nights.js`, `season.js`, `noise.js` | Helpers for new skies (see `BRIEF.md`): the bloom, OKLab colour and the hush, a star per night, the season, seeded noise. The baseline uses none of them. `season(state)` (or `season(dayOfYear, latitude)`) answers with the URL's `snowfall`. |
| `skies/<id>.js` | One sky per file. `skies/baseline.js` is today's sky, ported faithfully. |
| `skies/index.js` | The ids the panel's picker lists (`sky=<id>` loads any file in `skies/`). |
| `assets/` | The cloud and grain PNGs copied from `TwoOfUs/Assets.xcassets/Sky`; `fonts/` is Nunito, the chrome's stand-in for SF Rounded. |
| `tools/shoot.mjs` | Playwright: one PNG per (device × scheme × time), and a contact sheet. |
| `tools/review.mjs` | The review set: every sky shot the same way (day, bare, asleep, seasons, bedtime, the Duo opening, stillness, the header's text, tilt, snowfall, waking) into `shots/<sky>/review/`. `--list` shows it. |
| `tools/measure.mjs` | One shared measurement of `BRIEF.md`'s hard limits for any sky; `--help` lists options. |
| `tools/test-math.mjs` | The Swift unit tests for the sun, moon and palette, ported, and the port checked against the Swift source; then what the viewer adds to the state (`sun.x`, `tonightLit`, `snowfall`). |
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
  tonightLit,                           // boolean: tonight's star has been lit (below)

  t,                                    // seconds, monotonic; frozen when the URL has t=
  reduceMotion,                         // true with motion=0
  cards: [ { x, y, width, height, kind, opacity } ],   // where the chrome is, so a sky can compose around it ([] with chrome=0)
  layout: { name, age, avatar, gear,    // rects { x, y, width, height }: the header's text and buttons (below)
            firstCardTop,               // y of the first card under the header
            stripClear,                 // null | { x, width, yMin, yMax }: the Duo strip's clear window
            title, subtitle,            // null | rects: the spread's leading page's title and the line under it
            measured },                 // true; false only where no chrome could be laid out

  tilt:  { x, y },                      // −1…1 each, for parallax; 0, 0 unless tilt= (or the panel's pointer tilt)
  event: null | { kind, age },          // 'bedtime' | 'wake' | 'open' | 'close', and seconds since (lab/presence.js)
  lead,                                 // only with lead=: the spread's leading page's opacity, 0–1
  veil,                                 // only with veil=: how far the phone page's cards have fallen back, 0–1
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

`tonightLit` is true while `asleep` is `night`, and otherwise from the sample day's
bedtime to its morning wake, 20:10–06:40 (`lab/chrome.js`); `lit=` forces it. Hand it
to `nights()`. `snowfall` is absent unless the URL has it; `season(state)` — and
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
renders once more before it calls the frame drawn.

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
| `event`, `eventAge` | `bedtime`, `wake`, `open`, `close`; seconds since it began | (none), `0` |
| `lead` | 0–1, the spread's leading page's opacity (`0`: the panorama before its cards arrive) | (1) |
| `veil` | 0–1, how far the phone page's cards have fallen back (`1`: only the header and the system strip remain — the bedtime moment) | (0) |
| `tilt` | `x,y`, −1…1 each | `0,0` |
| `toast` | `1` shows the undo toast | `0` |
| `snowfall` | 0–1, snow in the air whatever the day (`1`: falling hard; `0`: a clear day) → `state.snowfall`, `season().snowfall` | (the day's own) |
| `lit` | `1`, `0`: tonight's star lit or not → `state.tonightLit` | (by `asleep` and the hour) |
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
`--veil 1`, `--tilt 1,0.5`, `--snowfall 1`, `--lit 1` — reuse those names, so give each
its own `--out`. `--help` lists every option.

    node tools/review.mjs --sky baseline                  # the whole review set
    node tools/review.mjs --sky baseline --only bedtime,open
    node tools/review.mjs --sky baseline --out /tmp/try   # somewhere else than shots/baseline/review

The review set, one folder each under `shots/<sky>/review/`:

| Set | What |
|---|---|
| `day`, `bare` | The standard matrix with the UI, and without. Sheets. |
| `asleep` | A night sleep at 19:40, 21:00, 03:00; `nap/` at 09:30, 13:10. |
| `seasons` | Four dates of his first year, 14 min before sunset and 40 after: all three devices; `<season>-bare/` the spread alone. |
| `bedtime`, `open` | The two showpieces, frame by frame (`BRIEF.md`). |
| `still` | `motion=0`, and `t=95` against the day set's `t=12`. |
| `text` | The minutes the sun (09:30–10:30) and the moon (17:00–19:40) pass behind the header's text: all three devices, with the UI and in `bare/`. Sheets. |
| `tilt` | `left-up/` (`tilt=-1,-0.5`) and `right-down/` (`1,0.5`): cover and spread, 16:10 and 21:00. |
| `snow` | The winter date with `snowfall=1`: cover and spread, its two times. |
| `wake` | `event=wake` at 06:40, the sample day's wake: `t0`, `t1_5`, `t4`, `t9`. (`tonightLit` is false from 06:40; `event.age` carries the change.) |

502 shots and 36 sheets in 57 runs of `shoot.mjs`. A 2-D canvas sky takes about three
minutes (the baseline: 188 s). A shader sky does not: headless Chromium draws WebGL in
software, about 3 s a shot at `--jobs 2` for the heaviest (wet-wash: 151 s for `day`
alone), so some 25 minutes for everything. Give those `--jobs 2 --timeout 120`, and
reshoot single sets with `--only`.
