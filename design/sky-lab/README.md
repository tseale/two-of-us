# Sky lab

A browser mockup bench for Home's sky (`TwoOfUs/DesignSystem/SkyBackground.swift`):
the real Home screen drawn over a swappable sky, at the real display sizes, at any
time of day, in both appearances. Mockups only — the app's sky is the Swift code.

    cd design/sky-lab && python3 -m http.server 8377      # then open the viewer
    node tools/shoot.mjs --sky baseline                   # PNGs into shots/

## Files

| File | What |
|---|---|
| `index.html` | The viewer. Reads the URL, builds a `state`, mounts the sky module and the chrome. With `ui=1`, a small control panel (time slider, toggles). |
| `lab/core.js` | Device presets, URL → `state`, the animation loop. |
| `lab/solar.js` | `SolarClock` + `MoonClock` ported from Swift, plus the sun's altitude/azimuth. Pure. |
| `lab/palette.js` | `SkyPalette` ported from Swift (looks, frames, ridges, clouds, stars, `scene()`). Pure. |
| `lab/chrome.js`, `lab/chrome.css` | Home's UI as HTML: the phone page, the spread's leading page, the system strip / tab bar. |
| `skies/<id>.js` | One sky per file. `skies/baseline.js` is today's sky, ported faithfully. |
| `assets/` | The cloud and grain PNGs copied from `TwoOfUs/Assets.xcassets/Sky`. |
| `tools/shoot.mjs` | Playwright: one PNG per (device × scheme × time), and a contact sheet. |
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

## The sky module contract

```js
// skies/<id>.js  (an ES module)
export const meta = { id: 'baseline', name: "Today's sky", blurb: 'One line.' };

/** host: an empty <div> filling the display (position:absolute; inset:0; overflow:hidden).
 *  Add canvases / DOM inside it. Never touch anything outside it. */
export function create(host, env) {       // env = { assets: 'assets/', solar, palette }
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
          sunrise, sunset },            // Dates
  moon: null | { altitude, azimuth, fraction, phase, rotation, passProgress, inDaylight, x, y },
                                        // as SkyPalette.Moon (x, y fractions of the anchor window); null while it is down
  scene,                                // palette.scene(...) — the Swift `SkyPalette.Scene`, for the baseline

  asleep: false | 'nap' | 'night',      // a sleep is running
  ageDays,                              // how old he is (lab default 142)

  t,                                    // seconds, monotonic; frozen when the URL has t=
  reduceMotion,                         // true when frozen with motion=0
  cards: [ { x, y, width, height, kind } ],   // where the chrome's surfaces are, so a sky can compose around them
}
```

Rules for a sky module: draw only inside `host`; deterministic for a given `state`
(seeded randomness, no `Math.random()` at render time); resize when `width`,
`height` or `dpr` change; no network.

## The viewer's URL

`index.html?sky=baseline&device=spread&scheme=dark&time=17:10&asleep=night&chrome=1`

| Param | Values | Default |
|---|---|---|
| `sky` | a module id in `skies/` | `baseline` |
| `device` | `cover`, `spread`, `iphone` | `cover` |
| `scheme` | `light`, `dark` | `dark` |
| `date` | `YYYY-MM-DD` (local) | `2026-11-21` |
| `time` | `HH:MM` (local, 24 h) | `16:10` |
| `lat`, `lon`, `tz` | degrees, degrees, hours | `41.88`, `-87.63`, `-6` |
| `asleep` | `0`, `nap`, `night` | `0` |
| `age` | days | `142` |
| `chrome` | `1` the Home UI over the sky, `0` the sky alone | `1` |
| `t` | seconds — freezes the animation at this instant | (running) |
| `motion` | `0` = Reduce Motion | `1` |
| `dpr` | 1–3 | `2` |
| `ui` | `1` shows the control panel | `0` |
| `bezel` | `1` draws the device around the display | `0` |

The display is the element `#display`, exactly `width × height` CSS px, at the
page's top-left when `bezel=0` and `ui=0`. When a frame is fully drawn (fonts and
images loaded, the sky rendered once) the viewer sets `window.__labReady = true`.
