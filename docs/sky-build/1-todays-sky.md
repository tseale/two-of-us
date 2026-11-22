# Today's sky in Swift: map for the port

> A map of today's sky in Swift (`SkyBackground.swift`, `SolarClock`, `MoonClock`) for the port.
> Written on 22 Nov 2026 by a read-only agent, against the branch at about commit `cd2b979` (the app as `origin/main` `3583e43` plus the sky lab). Line numbers are from that day and will drift. It is working context for building the painted hill (`docs/SKY_BUILD_PLAN.md`), not a maintained document.


All claims are from reading the code. Nothing was built, run or profiled (no Swift toolchain here), so cost statements are structural, not measured.

Path shorthand (all absolute):
- `ROOT` = `the repository root`
- `SB` = `ROOT/TwoOfUs/DesignSystem/SkyBackground.swift`
- `SC` = `ROOT/TwoOfUs/Store/SolarClock.swift`
- `MC` = `ROOT/TwoOfUs/Store/MoonClock.swift`
- `HV` = `ROOT/TwoOfUs/Features/Home/HomeView.swift`
- `LAB` = `design/sky-lab`

Deployment target is iOS 26.0 for every target (`ROOT/project.yml:5`, `:23`), not the "iOS 17+" in CLAUDE.md. `colorEffect`/`layerEffect`, `Canvas`, `MeshGradient` and `onGeometryChange` are all available.

## 1. What SkyBackground is given, and by whom

**Parameters** (`SB:37-58`), all with defaults:

| Parameter | Type | Default | Meaning |
|---|---|---|---|
| `location` | `(latitude: Double, longitude: Double)?` | `nil` | Place for sun and moon. Nil falls back to 40°N on the time zone's meridian. |
| `showsOrb` | `Bool` | `true` | Draw the sun/moon disc. False only on the spread's leading page ("one sun to a sky"). |
| `companion` | `SkyCompanion?` | `nil` | The neighbouring sky to run on from. |
| `leadingFeather` | `CGFloat` | `0` | Width in points of a fade-in mask from the leading edge. Zero draws no mask. |

**Environment read:**
- `colorScheme`, `colorSchemeContrast`, `accessibilityReduceTransparency` on `SkyBackground` (`SB:60-62`).
- `accessibilityReduceMotion` on `StarField` only (`SB:372`).
- Not read: `scenePhase`, Dynamic Type, Low Power Mode, any sleep state, any card or layout frame.
- `colorScheme` follows the app's own appearance setting (`ROOT/TwoOfUs/App/RootView.swift:136`).

**`SkyCompanion`** (`SB:104-107`) is `struct SkyCompanion: Equatable { var originX: CGFloat; var width: CGFloat }`. It is the phone page's sky rect, expressed in the leading sky's coordinates. With it, the leading sky:
- lays its ridges on the phone page's x (`RidgeShape.xOffset`, `SB:335`);
- draws that sky's sun/moon glow, not the disc, where that sky puts it (`SB:117-128`, `:179`).

**Callers.** There are only two, both in HomeView. No widget, watch, complication or notification target compiles these files; their source lists in `ROOT/project.yml:132-177` and following omit them.

- **Phone page** (`HV:460-464`): `.scrollContentBackground(.hidden).background { SkyBackground(location: daycareSettings?.daycareCoordinate, leadingFeather: onSpread ? PhonePage.featherWidth : 0) }` on `compactList`'s `List`.
  - This covers every slab iPhone, the closed Duo, an iPad compact window, and the spread's trailing page.
  - `PhonePage.featherWidth` is 18 (`ROOT/TwoOfUs/Features/Shared/PhonePage.swift:30`).
- **Spread's leading page** (`HV:610-611`): `SkyBackground(location: …, showsOrb: false, companion: phoneSky)` in `spreadBehindPhone`.
  - `phoneSky` is built at `HV:590-594`: `SkyCompanion(originX: frame.minX + safeAreaInsets.leading, width: frame.width + safeAreaInsets.trailing)`.
- **No sky at all:** iPad regular and the Duo's tall and short poses go through `panes()` (`HV:523-573`) on flat `AppColor.bg` (`HV:222`).

**Location source.** `daycareSettings` is `SharedSettings.canonical(settingsList)` (`HV:1821-1823`). `daycareCoordinate` parses the string `daycareLocationRaw` "lat,lon" (`ROOT/TwoOfUs/Models/SharedSettings.swift:290-298`), which is CloudKit-synced (`ROOT/TwoOfUs/Sync/RecordMapping.swift:232`, `:759`). It is the daycare pin, not home and not the phone. The sky makes no CoreLocation call.

## 2. What it draws, and how

**Technique.** Plain SwiftUI views in a `GeometryReader` + `ZStack(alignment: .topLeading)` (`SB:131-164`): gradients, `Shape`s, `Image`s, and `.blur`/`.shadow` modifiers. There is no `Canvas`, no `drawingGroup`, no shader and no pre-rendered scene. The app does have `Canvas` elsewhere (`ROOT/TwoOfUs/DesignSystem/DayRibbon.swift:86`, `ROOT/TwoOfUs/Features/Home/TodayHeroCard.swift:1166`), so the brief's "no Canvas either" holds for the sky only.

**Layers, back to front:**

1. **Sky gradient** (`SB:190-199`): vertical `LinearGradient`, 8 stops.
   - top 0; top→mid 0.15; mid 0.33; mid→page 0.46; page 0.56; page→haze 0.66; haze 0.74–1.
   - The upper half is sky, the middle is the page colour (`F2F2F7` light, `000000` dark), the bottom is haze.
2. **Warm pool** (`SB:201-204`, `:226-235`): a radial-gradient circle scaled to an ellipse around the sun, or around the moon at night.
   - Radii: rx = 0.7 × sky width, ry = 0.36 × height.
   - Alpha: 0.45 × `glow` (0.32), × a moon-phase factor at night.
3. **Moon glow** (`SB:206-212`): full-frame `RadialGradient` in `nightlightCream`, night only.
4. **Sun bloom** (`SB:213-220`): full-frame `RadialGradient`, end radius 0.5 × max(width, height).
5. **Night: `StarField`** (`SB:138-139`, `:368-415`).
   - Stars: `max(8, round(24·w/466))` white circles of 0.9–2.5 pt, each with its own `.shadow`. That is 21 on a 402 pt slab, 24 on the cover, 49 on the 951 pt leading sky. They sit in the top 36 % and come from a seeded generator (`SB:957-977`).
   - Glints: 5 (narrow) or 7 (wide) four-point `GlintShape`s of 12–18 pt, each scaled, rotated and given two shadows (`SB:400-412`).
6. **Day: sun disc** (`SB:141-144`, `:238-249`): a 46 pt radial-gradient circle with `.shadow(radius: 17)`.
7. **Day: clouds** (`SB:145-146`, `:272-317`).
   - 2 cumulus + 2 wisps narrow; 4 + 3 wide (above 700 pt, `SB:906-928`).
   - Each is three PNGs (dawn/day/dusk lighting) stacked with `.blendMode(.plusLighter)` in a `.compositingGroup()`.
   - Placed at hand-set fractions "where the screen's own sky shows".
8. **Moon disc** (`SB:150-154`, `:255-268`): 32 pt.
   - A 6 % cream earthshine circle, plus `MoonPhaseShape(lit:)` rotated to the real bright-limb angle, with `.shadow(radius: 9)`.
   - Drawn whenever the moon is up; 55 % opacity and no glow by day.
9. **Hills** (`SB:324-346`): 4 `RidgeShape`s.
   - Sum-of-three-sines crests, sampled every 10 pt and joined by quad curves (`SB:469-494`, `:830-868`).
   - Baselines at 24.5 / 19.5 / 14 / 7.8 % of the height up from the bottom.
   - Each is filled with a vertical crest→foot gradient and blurred: `.blur(radius:)` 3.2 / 2.2 / 1.5 / 1.0.
   - Between ridges sit 3 mist bands: a 54 pt gradient with `.blur(6)` (`SB:349-360`).
10. **Grain** (`SB:158-161`): `Image("SkyGrain")` tiled, `.blendMode(.softLight)`, opacity 0.3, full screen.

**Assets.** 13 image sets in `ROOT/TwoOfUs/Assets.xcassets/Sky` (9 cloud, 3 wisp, 1 grain; about 490 KB), generated by `ROOT/scripts/make_sky_textures.py`.

**What animates and how often:**
- The whole scene is recomputed once a minute: `TimelineView(.everyMinute)` at `SB:93`. There is no cross-fade between minutes; each minute is a discrete step.
- Only the stars animate: `TimelineView(.animation(minimumInterval: 1.0/24))` at `SB:378`, at up to 24 fps, from sunset to sunrise.
  - Twinkle is a 0.22–1.0 cosine over 2.4–5.2 s for about 65 % of stars (`SB:981-984`).
  - Glints pulse over 3.6–5.8 s (`SB:1013`, `:1022-1025`).
- Nothing animates on sleep, on wake, on opening the Duo, or on an appearance change.

**Comments on cost.** The only one is on `StarField`: "Animated on its own timeline (only at night, only while it is on screen)" (`SB:365-366`). The file says nothing about battery or Low Power Mode. By contrast the sibling ground `CradleField` declares itself cheap and turns off under Low Power (`ROOT/TwoOfUs/DesignSystem/CradleField.swift:19-22`, `:80`, `:94-96`, `:128-132`).

## 3. Time, sun, moon, place, palette

**Time.** There is no injected clock.
- The view uses `max(ctx.date, .now)` from the minute timeline (`SB:94`). Stars use `context.date.timeIntervalSinceReferenceDate` (`SB:379`).
- The pure entry point is `SkyPalette.scene(at: Date, location:, dark: Bool = false, calendar: Calendar = .current) -> Scene` (`SB:737-759`).
- There is no debug time override and no `#Preview` for the sky.

**SolarClock** (`SC`, pure enum, NOAA approximation):
- `day(containing:latitude:longitude:calendar:) -> Day?`, where `Day` is `{sunrise, sunset: Date}` (`SC:19-43`). Nil in polar day or night.
- `approximateLocation(timeZone:at:)` gives 40°N and standard-offset hours × 15° (`SC:47-52`).
- `phase(at:in:) -> .day(p) | .night(q)`, each 0–1 (`SC:56-71`).
- Time zone handling: `calendar` picks the local day (local noon, then the UTC day-of-year); results are absolute `Date`s.
- Night length is taken as 24 h minus today's daylight (`SC:63`).
- Polar fallback is a fixed 06:45–18:15 day (`SB:818-822`).
- There is no sun altitude or azimuth anywhere in Swift.

**MoonClock** (`MC`, pure enum, SunCalc series, absolute time only, no calendar):
- `position(at:latitude:longitude:) -> Position{azimuth (from south, positive west), altitude (refracted), distance, parallacticAngle}` (`MC:41-53`).
- `illumination(at:) -> {fraction, phase, angle}` (`MC:55-72`).
- `brightLimbZenithAngle` (`MC:77-80`).
- `pass(around:…) -> (rise: Date?, set: Date?)?`: a 10-minute step search over ±30 h, then bisection to the second (`MC:97-130`).
- `passProgress -> Double?` (`MC:135-139`).
- The sun's coordinates, sidereal time, altitude and azimuth helpers exist but are `private` (`MC:179-205`).

**Placement on screen:**
- Sun: `bodyPosition(progress:)` gives x = 0.04 + 0.92p and y = 0.30 − 0.30·sin(πp), as fractions of the whole view (`SB:697-700`). That is a fixed arc by fraction of daylight, not real altitude. At solar noon the disc's centre is on the top edge at mid-width, every day of the year.
- Moon: x is the same arc by pass progress; y is real altitude through `altitudeHeight`, from 0.30 at the horizon to 0 at the zenith (`SB:789-807`).

**Palette** (`SkyPalette`, `SB:498-1026`):
- `Look` has `top, mid, sun, core, warm, haze, mist, mistAlpha, hills[4], deep, light` (`SB:555-582`).
- Five keyframes each for light (`SB:603-627`) and dark (`SB:641-665`).
- Frame tables (`SB:668-682`):
  - day: (0 dawn, 0.18 morning, 0.5 noon, 0.82 morning, 1 dusk);
  - night: (0 dusk, 0.12 night, 0.88 night, 1 dawn).
- `look(at:in:)` is piecewise linear, mixed in sRGB (`SB:684-692`).
- Clouds fade over the first and last 10 % of daylight (`SB:751`).
- `starOpacity` is 0 until q = 0.02, 1 from 0.08 to 0.92, and 0 by 0.98 (`SB:935-939`).
- The "hushed" rule (a fifth of the chroma, 55 % towards the page) is baked into the hex values (`SB:600-602`). Swift has no full-strength palette and no OKLab code.

## 4. Appearance, accessibility, sleep

- **colorScheme:** dark selects the dark frames and page `000000`, with cloud strength 0.16 (0.8 light), moon glow ×0.4 and star strength ×0.6 (`SB:586-598`, `:713-723`). Light-appearance night is a mid-grey sky (top `9C9FAD`), not a dark one.
- **Reduce Transparency or Increase Contrast:** plain `AppColor.bg`, with no timeline at all (`SB:89-90`).
- **Reduce Motion:** stars are drawn still at full brightness and glints held at 0.6 open (`SB:375-376`, `:392`, `:402`). Nothing else moves anyway.
- **Dynamic Type:** not handled. Everything is fixed points and there is no text.
- **VoiceOver and touch:** `.accessibilityHidden(true)`, `.allowsHitTesting(false)` (`SB:83-84`).
- **Low Power Mode:** not handled.
- **Sleep:** the sky has no sleep input and never dims.
  - "A 3 AM feed never lights the room" rests on the dark palette alone (`SB:26-31`).
  - Asleep dimming exists only in `CradleField(hinge:asleep:night:)`, behind the other tabs' spreads (`ROOT/TwoOfUs/Features/Shared/SpreadScaffold.swift:239-248`).

## 5. What the tests pin

**`ROOT/TwoOfUsTests/SkyPaletteTests.swift`** (27 tests):
- Arc endpoints: x 0.04 / 0.5 / 0.96, y 0.30 / 0 / 0.30 (`:12-22`).
- Hue ordering at sunrise, noon and sunset (`:24-39`).
- "Quiet behind the cards": every day-frame colour has max−min < 0.12 and min > 0.75 (`:41-53`).
- Night is deeper than day; night and day join at both ends (`:55-66`).
- Linear blending and clamped mixing (`:68-84`).
- Cloud-light weights sum to 1 (`:86-97`).
- Four hills per look; ridges ordered, blur decreasing, all crests in the bottom 32 % at 951 × 678 (`:99-121`); ridge points overhang both edges (`:123-127`).
- Stars are deterministic: 24 at 466 pt, y ≤ 0.36, period 2.4–5.2 s (`:129-143`).
- `starOpacity` values (`:145-153`); twinkle range 0.22–1 (`:155-166`).
- 5 or 7 glints with distinct phases, periodic (`:168-185`).
- Dark colours: luminance < 0.2, and mid/haze/deep/hills darker than a card (`1C1C1E`) (`:201-217`); dark night is the deepest and violet (`:219-230`).
- Dark scene constants (`:251-262`).
- Companion ridges run on (`:264-280`).
- `MoonPhaseShape` geometry (`:284-294`).
- Moon present only while up, with Chicago fixtures (`:296-311`); moon height from altitude (`:313-324`); dark is quieter (`:326-333`).

**`ROOT/TwoOfUsTests/SolarClockTests.swift`** (5 tests): New York sunrise/sunset on Nov 13 and Jun 21 2026 within ±5 min; polar night is nil; phase fractions; the meridian fallback uses standard time.

**`ROOT/TwoOfUsTests/MoonClockTests.swift`** (7 tests): SunCalc reference position and illumination to 1e-9; known new and full moons; rise and set within ±60 s; no pass while the moon is down; an evening crescent (fraction 0.28, progress 0.729, rotation 34°); `brightLimbRotation` at three angles.

**`ROOT/TwoOfUsTests/PhonePageTests.swift:39-40`**: `featherWidth ≤ margin`.

**The lab mirrors all of this.** `LAB/tools/test-math.mjs:8-12` ports these tests one for one and adds checks for a `sunPosition` (`:290-402`) that Swift lacks.

## 6. What a replacement must keep, and what is free

**Keep, or change the two HomeView call sites with it:**
- **The ground contract.** It fills the display by itself (`.ignoresSafeArea()`, `SB:82`), never takes a touch, is hidden from VoiceOver, and becomes flat `AppColor.bg` under Reduce Transparency or Increase Contrast. The brief restates this (`ROOT/design/sky-lab/BRIEF.md:419-420`).
- **It is a `List` background.** It stays put while rows scroll over it.
- **Text sits directly on it.** The header (name in primary colour, age in `text2`) is at top-left (`HV:1686-1705`), and the empty-timeline header and empty state sit on it too (`HV:2540-2548`).
- **Glass sits on it.** Liquid Glass tiles and the system glass tab bar are above it (`ROOT/TwoOfUs/App/RootView.swift:344`).
- **The phone page is one view instance, moved between cover and spread** (`HV:153-163`).
  - Its sky goes from 466 × 678 to 466 × 669 with the system strip trailing (`ROOT/docs/IPHONE_DUO.md:74`).
  - The picture must not shift on opening.
  - The leading sky must continue it with no seam and no second sun or moon. Today that is done by `companion` plus an 18 pt feather.
- **Location input** `daycareSettings?.daycareCoordinate`, and the fallback when it is nil.
- **SolarClock and MoonClock** are used by nothing but the sky and are safe to extend. Their tests carry reference values worth keeping.

**Already matches the sign-off.** Discs are drawn wherever they stand and cards simply cover them. Today's sky knows nothing about card frames or status glyphs.

**Free to change:**
- Everything private: `SkyScene`, `StarField`, `GlintShape`, `RidgeShape`.
- `SkyPalette` and `MoonPhaseShape`, which only the tests and the lab's `palette.js` mirror reference.
- The textures and their script, the arc rule, clouds, hills, the 24 fps star timeline, `wideLayoutWidth`.
- The shape of `SkyCompanion`, `showsOrb` and `leadingFeather`.

**Docs to update with it:** `ROOT/docs/DESIGN.md:51`, `ROOT/docs/IPHONE_DUO.md:74` and `:152-155`.

## 7. Surprising or fragile

1. **No sun altitude in Swift.** "First light at −7°" has no source. The lab's `sunPosition` (`LAB/lab/solar.js:248-258`) is built from MoonClock's private helpers; the port must add it. Reference checks exist in `test-math.mjs`. The lab's `Moon` also carries `altitude`, `azimuth` and `passProgress`, and `state.sun.x` continues past sunset (`LAB/lab/core.js:269-278`). Swift's `SkyPalette.Moon` has none of these.
2. **The place is the daycare pin, else 40°N on the zone meridian.** A household with no pin, or one far from 40°N, gets sunrise and first light off by tens of minutes. The new camera state would inherit that error.
3. **The solar day is chosen by the phone's calendar** (`SC:22-26`).
   - If the phone's time zone is far from the pin's longitude (travel), or in UTC+13/+14, the wrong day's sunrise and sunset are used and the phase sticks. This is derived by reading, not run.
   - `testTheSceneHasTheMoonOnlyWhileItIsUp` uses `Calendar.current`, so it depends on the test machine's zone the same way.
4. **Two sky views on the spread, each with its own minute timeline and its own 24 fps star timeline.**
   - The leading sky is laid out 951 pt wide, but roughly its right half is covered by the opaque phone-page sky.
   - Several wide-layout clouds and glints (x 0.885–0.965, `SB:913`, `:1005`) are therefore drawn and never seen.
   - Clouds and stars do not continue across the fold; only the ridges and glows do.
5. **With the strip on the leading side**, the companion width is 382, not 466 (`HV:592-593`), so the phone page's sky is narrower than the cover's and its picture would shift on opening. This is inferred; docs only describe the trailing-strip case.
6. **Structural cost at night.** Per-star shadows are re-rendered at up to 24 fps with no flattening, under four blurred full-width shapes, three blurred bands and a full-screen soft-light layer, with glass tiles sampling it. There is no Low Power or `scenePhase` gate. The star timeline also runs for the roughly 17 minutes at each end of a long night when star opacity is 0.
7. **Demo mode.** The pill is a row above Home (`ROOT/TwoOfUs/App/RootView.swift:96-104`), so the sky cannot reach the display's top and has no top shade as `CradleField` has. This probably shows as a hard edge; I did not see it.
8. **One test is vacuous.** The seam assertion in `testASkyBesideAnotherRunsItsRidgesOn` looks up a phone point at x = 5, which never exists because samples are multiples of 10 (`SkyPaletteTests.swift:275-278`).
9. **Unused fields.** `Scene.body` at night and `Moon.phase` are computed and never drawn. `Scene` and `Look` are not `Equatable`.
10. **"Night sleep" has no Swift definition matching the design.** `SleepLanguage` uses 20:00–06:00 (`ROOT/TwoOfUs/Store/SleepLanguage.swift:16-17`); the brief uses 18:00–04:00. `EventSource` has only `.snoo` and `.brightwheel` (`ROOT/TwoOfUs/Models/Enums.swift:34-36`), so "started by hand on this phone" is knowable only at the tap site.
11. **Stale docs.**
    - Root `ROOT/DESIGN.md` predates the sky and never mentions it. It says glass sits on `--bg` and a second gradient is "a flag to pause" (`:283`, `:385`).
    - `ROOT/CHANGELOG.md:43` says dark mode keeps a black ground.
    - CLAUDE.md says iOS 17+.

## Not read

- `HV` beyond lines 1–640, 1686–1718, 1818–1827 and 2520–2569.
- `PaneLayout`, `SpreadGrid`, `ScreenShape`, `TodayHeroCard`.
- `ROOT/docs/IPHONE_DUO.md` beyond lines 74 and 140–175.
- Root `DESIGN.md` beyond its head and grep hits.
- In the lab: `hill-painted.js`, `air.js`, `tree.js`, `presence.js`, `palette.js` past its header, and `hill-painted.md` outside its "SwiftUI port" section (`:1044-1227`). `core.js` was read at `:240-345` and `:462-565` only; `solar.js` was read in full.
- `BRIEF.md` was read at `:1-60`, `:195-236`, `:405-425` plus grep hits.
