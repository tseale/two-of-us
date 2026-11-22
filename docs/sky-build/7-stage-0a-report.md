# Stage 0a, integrated: the report

> The integration report of stage 0a (the pure layer, commit `b203d0c`): what was built, what may differ on a Mac, and the decisions the code pins one way.
> Written on 22 Nov 2026 by the agent that integrated the stage. It is working context for building the painted hill (`docs/SKY_BUILD_PLAN.md`), not a maintained document.


STAGE 0a, INTEGRATED — REPORT

Both lanes are in one tree and are one module. On Linux: 280 tests, 0 failures, 0 warnings in a clean build. All eight fixtures regenerate byte-identically from the lab. Nothing has been compiled or run on a Mac, so by the plan's own rule this is not "done" yet.

Worktree: (a scratch file of the session that wrote this; not kept)
Patch (59 new files, no existing file changed; applied to an empty tree it reproduces the worktree byte for byte): (a scratch file of the session that wrote this; not kept)
Progress notes: (a scratch file of the session that wrote this; not kept)
Final test log: (a scratch file of the session that wrote this; not kept)
No commit, stage, stash, branch switch or push; only the prescribed `git add -N .`. w1, w2 and the main checkout were not written to.

LAST LINES OF THE FINAL RUN (verbatim; clean build)
```
Test Case 'StarChartTests.testTonightsStarTakesNobodysPlace' passed (0.001 seconds)
Test Suite 'StarChartTests' passed at 2026-11-22 18:56:51.016
	 Executed 38 tests, with 0 failures (0 unexpected) in 2.821 (2.821) seconds
Test Suite 'debug.xctest' passed at 2026-11-22 18:56:51.016
	 Executed 280 tests, with 0 failures (0 unexpected) in 10.408 (10.408) seconds
Test Suite 'All tests' passed at 2026-11-22 18:56:51.016
	 Executed 280 tests, with 0 failures (0 unexpected) in 10.408 (10.408) seconds
◇ Test run started.
↳ Testing Library Version: 6.2 (3fdabe5392108d8)
↳ Target Platform: x86_64-unknown-linux-gnu
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
```
XCTest on Linux does not print an assertion count. Per suite: Air 18, Glide 9, HillPalette 17, Moment 32, NightCount 13, NightRule 25, OKLab 19, SkyCamera 14, SkyCoreLight 3, SkyCoreSun 9, SkyEvent 7, SkyMath 7, SkyNoise 10, SkyPlace 3, SkyScript 21, SkySeason 8, SkyWorld 15, Skyline 7, SolarClock 5 (existing), StarChart 38. The two lanes together had 274 before integration.

FILES (lines)

TwoOfUs/Sky/Core/ — 21 files, 4,770 lines
Air 708, Glide 101, HillPalette 438, Moment 345, NightCount 104, NightRule 161, NightState 49, OKLab 248, SkyCamera 140, SkyEvent 109, SkyMath 87 (new), SkyNoise 187, SkyPlace 25, SkyScript 160, SkySeason 145, SkyWorld 503, Skyline 237, SleepKind 24 (new file), SleepSpan 22, SolarClock+Position 105, StarChart 872.

TwoOfUsTests/ — 19 test files and one reader, 6,842 lines
AirTests 434, GlideTests 220, HillPaletteTests 498, MomentTests 780, NightCountTests 237, NightRuleTests 568, OKLabTests 397, SkyCameraTests 302, SkyCoreLightTests 149, SkyCoreSunTests 212, SkyEventTests 137, SkyMathTests 131 (new), SkyNoiseTests 206, SkyPlaceTests 55, SkyScriptTests 470, SkySeasonTests 231, SkyWorldTests 318, SkylineTests 164, StarChartTests 1,234, SkyCoreFixture 99 (new, hand-written).

Generated fixtures (TwoOfUsTests/, data only)
SkyCoreFixturesAir 1,918 lines / 382 KB; Colour 6,010 / 431 KB; Look 187 / 5 KB; Moment 7,948 / 379 KB; Night 1,063 / 89 KB; Palette 270 / 344 KB; Season 452 / 54 KB; Stars 3,129 / 397 KB.

Exporters (design/sky-lab/tools/swift-fixtures/)
air.mjs 226, colour.mjs 275, look.mjs 139, moment.mjs 557, night.mjs 272, palette.mjs 241, season.mjs 100, stars.mjs 685, emit.mjs 144 (the shared writer), README.md 45 (new).

WHAT I MERGED OR RENAMED

The lanes' files were disjoint: no file collided and nothing was merged by hand at the file level.

1. One set of arithmetic: new `SkyMath` (clamped, smoothstep, lerp, quintic, round, hypot).
   - Removed: `Air.smoothstep`, `Air.lerp`, `Air.clamp01`, `OKLab.clamp01`, and the private smoothstep / clamp / quintic copies in SkySeason, SkyCamera, Moment and Glide.
   - `SkyNoise.round` and `SkyNoise.hypot` moved to `SkyMath`; their tests moved with them, as did the smoothstep/lerp test from AirTests.
   - `SkyNoise.fade` stays private and unclamped, with a note: it must match the lab to the bit.
   - Three small numeric effects, all inside existing tolerances:
     - `look` is now held to 0 … 1 everywhere. The lab's raw quintic runs one ulp past 1 just short of the end.
     - `OKLab.chroma` and HillPalette's albedo mix use the lab's `Math.hypot` algorithm, not the system's.
     - `SkyCamera` rounds with the exact `Math.round` port.
2. One `SleepKind`, in its own file. `Moment.Sleep` is gone.
3. One dissolve length: `SkyEvent.dissolveDuration`. `Moment.dissolve` is gone.
4. Every `look` curve is written once, in `SkyEvent.Move` (`.bedtime(world:reduced:)`, `.arrive`, `.settle`, `.dissolve`).
   - `SkyEvent.move(world:reduced:)` is no longer optional. Bedtime's rise comes from `Moment.beats`.
   - `Moment.frame`, `Moment.arrive` and `Moment.settle` read `look` through the same moves, by a new `Glide.value(from:to:elapsed:duration:curve:)`.
   - This closes the lane 1 review's open item: an Undo mid-rise now settles from where the camera is.
   - `testTheMomentsRiseIsItsOwnTablesNotTheEvents` asserted bedtime's move was nil. I replaced it with `testBedtimesRiseIsTheMomentsOwnTable` (the lab's frames on both worlds, and `Moment.frame` every 0.05 s, full and reduced) and `testAnUndoInTheMiddleOfTheRiseSettlesFromWhereTheViewIs`. No other assertion was changed or loosened.
5. `SkyScript.momentIsSpent(age:world:reduced:)` reads the moment's table (`captionIn.upperBound`). The `2.8` constant is gone. Under Reduce Motion the moment is therefore spent at 1.6 s; this is new behaviour.
6. Names: `reduceMotion:` became `reduced:` (the plan's word). `StarChart.Standing` became `StarChart.CastSky`, because `SkyScript.Standing` means something else.
7. One fixture reader: `TwoOfUsTests/SkyCoreFixture.swift`. The eight generated files carried eight copies of reader code and now hold data only. I compared every table with the lanes' originals: the data is identical.
8. Exporters: `night-emit.mjs` renamed `emit.mjs`; every exporter takes `--check`.
9. Two tests across the lanes:
   - NightCountTests ties `HillPalette.starsOut` to the count's turn at the lab's three suns.
   - `StarChartTests.testTonightsSkyByTheAppsOwnCountKeepsEveryPromise` runs `NightCount.night` → `monthNights` → `StarChart.cast` on all three displays: 143 stars, all in view looking up, no star without a place, four-point stars at least 80 pt apart, the first 61 nights at the lab's places, and tomorrow moving none.
10. MomentTests and SkyCameraTests now parse their tables once per class, not once per test instance.

Mutation check of the seams: ten one-line mutations (rise duration, reduced curve, the spent rule twice, `Math.round`, the quintic's clamp, the arrive length, the retarget origin, hypot, starlight). All ten were caught.

NAME CLASHES

- I searched the app, widgets, watch, complication, notification extension and both test targets for every new type name. The only hit is `Moment`: the app has a nested `DayHighlights.Moment`. Every use of it is inside `DayHighlights` or written `DayHighlights.Moment` (HomeView), so the top-level `Moment` does not collide. Kept, because it is the plan's name.
- Between the lanes: `Moment.Sleep` against `SleepKind`, and the two `Standing`s. Both resolved above.
- No duplicate file basename in the app or test target; no test class or fixture enum name is already taken.
- Not reachable from other targets: `project.yml` is untouched, no existing file references a new type, and the widget, watch and notification targets list files one by one.

FIXTURES AND THE LAB'S CHECKS

- As delivered, all eight exporters reproduced the lanes' files byte for byte. After the reader change I regenerated them, then ran `--check` on all eight twice: up to date.
- `node tools/test-math.mjs`: all 80 tests passed (8,417 checks).
- I did not run `measure.mjs` or the signature frame. No lane added an export hook on disk: the probes are added in transit, and `skies/`, `lab/` and `index.html` are byte-identical to cd2b979.

THE READ FOR A MAC

- Core imports Foundation only. It has no `Date()`, `.current`, `public`, force-unwrap or top-level function.
- Core type-checks in Swift 6 mode and with `-strict-concurrency=complete -warnings-as-errors`. No Core expression takes over 80 ms to type-check, and none in the new tests over 150 ms.
- `project.yml` sets Swift 5 and no isolation or concurrency flags.
- The new test classes have no member that shadows an XCTestCase or NSObject member.

NOT DONE

- `SkyBodies` (waits for the lab change), with its two tests `testNoDiscStandsInTheHeaderBand` and `…BesideTheStatusIcons`.
- `SkyTone`, `SkyLegibility`, `SkyLayoutModel` (stage 0b), and `testTheSkyStaysLegible`.
- No Mac build and no `make test`.
- No Home wiring, no `SleepEvent → SleepSpan` mapping, no production function from a date to a palette (SkyCoreLightTests shows the wiring).
- The room's depth has no Glide API yet; GlideTests only shows a Glide can carry the lab's curves. That belongs with `SkyTone`.
- The lab's own README does not mention the exporters; I was not to touch existing files.
- `TwoOfUs/Store/SolarClock.swift` is not extended in place. The extension stays in `Sky/Core/SolarClock+Position.swift`, because `test-math.mjs` compares every number in SolarClock.swift with its NOAA port.
- I read the plan (8.txt), the conventions (5.txt), the brief's night rule and sign-off, and every Core file. I did not re-read maps 1–4 and 7, nor hill-painted.js beyond `lookOf`, `seasonLand` and `onGrid`. I relied on the two lane reviews' differentials for fidelity to the lab.

STILL OPEN FROM THE LANES

- Travel: the sun is the pin's, 18:00 / 04:00 are the phone's (plan risk 11).
- A start hours in the future begins the night now.
- Polar `morning` has no Swift glue.
- `rises` near the polar circles: a dip under the angle shorter than the 10-minute search step reads as "never", which gives the 04:00 fallback.
- Three unpinned StarChart numbers: the spiral's room of 20, `max(4, …)`, and the `u <=` tie.

WHAT MAY DIFFER ON THE MAC

- Darwin's `pow`, `exp`, `cbrt`, `sin`, `cos`, `atan2`, `log` may differ from glibc in the last bit.
  - Tolerances are 1e-12, 2.5e-7 for single-precision values, and 1 s for rise times.
  - `hypot` and `round` no longer depend on the system.
  - A star could move only on an exact tie in the spiral.
- Clock strings asserted to the second ("06:12:14", "06:29:39", "04:34:12").
- Calendar and time-zone data: America/Chicago 2027, Europe/Oslo, Europe/Stockholm, Asia/Tokyo. A policy hour inside a spring-forward gap is untested.
- Bit-exact tests (SkyNoise, Skyline, SkyMath's hypot) would fail first if arm64 fused a multiply-add.
- About 2.1 MB of string literals in the test target. A clean build of everything took 15 s here; Xcode is untested.
- Xcode's Swift 6.4 against 6.2 here. `SkyEvent.Move` has static functions named like the enum's cases (`.bedtime`, `.arrive`, `.settle`, `.dissolve`); it resolves by return type here and I expect the same there.
- NightRuleTests takes about 5 s and StarChartTests 3 s here; a simulator will be slower.

DECISIONS THIS CODE PINS ONE WAY (owner's to confirm)

| # | What is pinned | Test |
|---|---|---|
| 1 | The sky's night starts at 18:00, while the app's wording rule still says 20:00 (plan decision 1) | `NightRuleTests.testANightSleepIsOneBegunBetweenSixAndFour`, `testThePolicyHoldsTheHours` |
| 2 | A 6:05 pm catnap begins the night (decision 2) | `NightRuleTests.testAnEveningCatnapBeginsTheNight` |
| 3 | A 5:50 pm bedtime never begins the night (decision 3) | `NightRuleTests.testABedtimeTenMinutesBeforeSixNeverBeginsTheNight` |
| 4 | "Night N" turns as the sun passes −4°, not at first light | `NightCountTests.testTheCountTurnsOnceTheStarsAreOut` |
| 5 | Month-nights are his real month-birthdays, so from night 62 his sky is not the lab's star for star | `NightCountTests.testMonthNightsAreHisRealMonthBirthdays`, `StarChartTests.testTonightsSkyByTheAppsOwnCountKeepsEveryPromise` |
| 6 | First light found more than 5 minutes late only dissolves | `SkyScriptTests.testAMorningFoundLongAfterFirstLightOnlyDissolves` |
| 7 | The hand token is matched by freshness (5 s), not by sleep id | `SkyScriptTests.testATokenOlderThanFiveSecondsIsNoLongerThisTap` |
| 8 | A start ahead of this phone's clock counts at once | `NightRuleTests.testAFastClockStillBeginsTheNight` |
| 9 | Arrival within 90 s rises; later dissolves. An un-beginning waits 1.5 s | `SkyScriptTests.testALateArrivalDissolves`, `testASplitEditDoesNotSettle` |
| 10 | The moment is spent once the caption is up: 2.8 s, and 1.6 s under Reduce Motion (the second is mine) | `SkyScriptTests.testAMisTapUndoneAtOnceDoesNotSpendTheMoment` |
| 11 | An Undo mid-rise settles from where the view is (mine) | `SkyEventTests.testAnUndoInTheMiddleOfTheRiseSettlesFromWhereTheViewIs` |
| 12 | A touch: cards back in 0.3 s on an ease-out, lights out in 0.2 s on a smoothstep. The lab has no touch; the easings are the builder's | `MomentTests.testATouchEndsTheMomentAtOnce`, `testATouchPutsTheLightsOutWithoutAStep` |
| 13 | The cards fall on the lab's smoothstep, not SwiftUI's `.easeInOut` (up to 2.9 % of a card apart) | `MomentTests.testTheMomentFollowsTheLabsTable` |
| 14 | Under tilt, a move runs between the two rounded offsets, not the lab's unrounded path | `SkyCameraTests.testDuringAMoveALayerTravelsBetweenPixels` |
| 15 | With no pin, the place is 40°N on the time zone's meridian (first light up to 18 min late in Chicago) | `SkyPlaceTests.testTheGuessPutsFirstLightWithinTwentyMinutesOfChicagos` |
| 16 | The pale page's sky floor is 0.876 (the lab's code), not the 0.846 in the lab's comment | `AirTests.testThePalePagesSkyStaysWhereGreyTextCanBeRead` |
| 17 | Tonight's star is always last in the list, lit by the moment's `star` | `StarChartTests.testTonightsStarTakesNobodysPlace` |
