# Adversarial review: port plan for the painted hill

> The adversarial review of the first draft of the build plan. The plan of record already answers it.
> Written on 22 Nov 2026 by a read-only agent, against the branch at about commit `cd2b979` (the app as `origin/main` `3583e43` plus the sky lab). Line numbers are from that day and will drift. It is working context for building the painted hill (`docs/SKY_BUILD_PLAN.md`), not a maintained document.


Nothing was built or run. Two blockers: the cards' fade is on the wrong view, and the disc rules are mis-sorted.

**Paths.** APP = `the repository root`; HV = `APP/TwoOfUs/Features/Home/HomeView.swift`; LAB = `design/sky-lab`; HP = `LAB/skies/hill-painted.js`; MD = `LAB/skies/hill-painted.md`; PRES = `LAB/lab/presence.js`; BRIEF = `APP/design/sky-lab/BRIEF.md`.

## BLOCKERS

**B1. "Cards step back" as one `.opacity` on the list.**
- **Claim (§4):** `CardsVeil` goes on the list, before `.loggedToast`.
- **Evidence:**
  - The header is the list's first row (HV:382-385), so name, age, avatar and gear fade too.
  - The design keeps them: the lab's header sits outside the veil (`LAB/lab/chrome.js:748-749`; HP:3770-3771).
  - The lab's author already rejected fading the wrapper: the glass tiles' "blur no longer sees the sky, and they would jump" (`LAB/lab/chrome.css:1140-1143`). BRIEF:226 says "fading list rows one by one".
  - Platform: Apple's guidance for `UIVisualEffectView` is that alpha below 1 on it or a superview breaks the effect. Liquid Glass is likely the same; untested.
- **Change:** fade each card inside its row (hero, each tile, sleep card, SNOO and schedule rows, checklist, the timeline's row backgrounds at HV:2907-2941). Leave the header alone. Glass leaves by its own transition, chosen in spike 1. Spike that, not list opacity.

**B2. The disc rules are mis-sorted.**
- **Claim (§4, decision 3):** "draws a disc where it stands"; drops `clearOfButtons`, `clearOfText` and the strip-column rule.
- **Evidence:**
  - `bodyAt().seen` (HP:785-796) is never mentioned. It is a header rule, not a card rule: on the Duo no disc is drawn in the header band, on the slab none behind the status bar. The sign-off withdrew only the card clause (BRIEF:362-370). Dropping it puts the midday sun behind his name, a frame no review saw.
  - `clearOfText` hides nothing. In dark it removes the halo and dims the disc to L 0.33 behind words (HP:4052, 4071). Without it the 7:1 limit (BRIEF:397-400) rests on the text guards (HP:3713-3756), which are in no rendering row and no stage.
  - The strip-column width serves sign-off item 5, which stands (BRIEF:347-348; HP:3953-3959: a disc beside the glyphs "is a weather symbol").
  - The gate tests run on plates. Discs, halos, glare and guards are composited outside them.
- **Change:**
  - Port `seen` and `clearOfText` unchanged, and put the text guards in stage 2.
  - Hide across the icons' row of the strip, not in glyph rects.
  - Run the gates on the composite (`ImageRenderer` of `HillSky` with fixed inputs, 2× and 3×).
  - Ask the owner only about `clearOfButtons`.

## SERIOUS

**S1. Tone during the moment has no workable first answer.**
- **Claim (§3):** repaint and cross-fade; "a spike decides".
- **Evidence:** the bloom peaks 1.6 s after an unpredictable tap (PRES:58); a repaint took 0.5–1.2 s in the lab (MD:980-989). The path is not monotone: bloom up then down while depth runs 1.2–9 s (PRES:146-157). Two paintings cannot carry it, and three sets would slide at once.
- **Change:** decide before stage 0. Simplest: the land holds its tone for 5.8 s, then one cross-fade to the dimmed set; the bloom lives in the sky field only. Fade new over old at full opacity: a symmetric fade shows 25 % sky through the hills.

**S2. `arrive` will play on ordinary evening opens.**
- **Claim:** risk 6, with no rule.
- **Evidence:** sync and the SNOO poll land after Home draws (HV:317-326). Sign-off: "simply up when it appears" (BRIEF:331).
- **Change:** play `arrive` only when the beginning sleep's `startedAt` is within about 90 s of now; otherwise the 0.6 s dissolve. Clamp a future start to now and drop "≤ now + 2 min": a fast clock on the other phone leaves the sky down beside a running sleep card.

**S3. Un-beginning needs a hold.**
- **Evidence:** an edit is a delete plus an insert (`APP/TwoOfUs/Store/EventStore.swift:602-616`). Split across two fetch batches (`APP/TwoOfUs/Sync/SyncManager.swift:1042-1095`), the other phone sees no night sleep for an instant: `settle`, then `arrive`.
- **Change:** settle for a non-clock cause only after about 1.5 s still un-begun. Undo inside the moment must also cancel cards, caption and band; the toast sits above the touch catcher.

**S4. The 18:00 cliff is not among the decisions.** A 5:50 pm bedtime never begins the night. Moving a running sleep's start from 6:05 to 5:55 brings the sky down. Add a decision 5, for example: a sleep begun 16:00–18:00 and still running at 19:30 counts, quietly.

**S5. The camera runs on the main thread.**
- **Evidence:** every plate offset is sampled in SwiftUI per frame. Home recomputes its summaries every second (HV:386-397), and `startSleep` saves, starts the Live Activity and reloads widgets synchronously (`EventStore.swift:463-491`).
- **Change:** make it a spike item. Fallback: plates as `CALayer`s running the same sampled curve as a keyframe animation. Start the moment's clock at the first frame after reconcile, not at the tap.

**S6. Memory has no budget.**
- **Evidence (my arithmetic from the lab's sizes):** sky 1147 × 660 pt at 3× is about 27 MB; five land planes about 60–70 MB; one spread set about 110 MB, two while cross-fading, kept even with the Duo closed.
- **Change:** set a budget. Flatten far, mid and knoll, which travel identically (HP:128-141), if tilt is not ported. Reuse buffers.

**S7. "Tree masks shipped as images" is unsized.** Masks are keyed on seven season values in 1/40 steps (HP:4304; `LAB/skies/hill-painted/tree.js:421`). Those change most days in spring and autumn (`LAB/lab/season.js:78-87`): likely thousands of images per size. Port `tree.js` (pure, seeded) or ship weekly states.

**S8. Stages.**
- Stage 1 is "never merged", so it cannot reach a phone by TestFlight; it needs Taylor's Mac (BRIEF:242). Name who runs it.
- Run the spikes before stage 0's `SkyTone`, `StarChart` and `SkyLayoutModel`.
- Stage 7 mixes sign-off rules (clouds at card edges, item 5) with extras and has no "done when". Split it.
- "No Mac needed" is not credible: the tests are app-hosted and there is no `Package.swift`.

## MINOR

- **Tests restate tables** (quintic, spark, room dim, seasons, pixel grid). Compare with lab-exported samples instead. §2 lists no `SkyScript` test: hand token with the night already begun, an id swap, a late or already-ended arrival, undo then re-tap, a DST night.
- **Night N turning at first light** pops last night's star in mid-settle, with about a third of the stars still out (PRES:182). Turn the count once the sun is above −4°.
- **Island.** "Asleep" does not mean a long island: Live Activities can be off (`APP/TwoOfUs/LiveActivities/SleepActivityManager.swift:154`), and demo mode starts none. Always assume the long island; port note 16 then needs nothing.
- **120 Hz.** `CADisableMinimumFrameDurationOnPhone` is in neither `APP/TwoOfUs/Info.plist` nor `project.yml`, so display-link work is probably held to 60.
- **"Call for call" is overstated.** HP has 11 `filter: blur()` sites, plus patterns. Paint in a 16-bit context, dither once, tag sRGB.
- **§2 and §5 disagree.** §2 says star places ignore on-screen layout; §5 uses measured name width. Compute the width from the font.
- **Missing entirely:**
  - what is drawn before the first plates exist, or after an appearance flip;
  - tilt (BRIEF:33), dropped without a word;
  - iPad compact windows (give them flat ground);
  - which iPhones the parents carry: one question, before the slab world is ported;
  - `.onChange(of: grid != nil)` also fires when an open Duo is rotated.

## What the plan gets right

1. One hoisted sky with one driver removes the seam, the second clock and the feather.
2. The night as a pure function, with an in-memory hand token and no schema change; HV:2488-2493 is the only by-hand path.
3. Dropping the lab's "sunset if earlier" and keeping 4 am, as BRIEF:238-241 says.
4. Looking up as offsets of kept images, rounded to device pixels.
5. A visible `LocalPrefs` switch with a scrubber, and putting the wording clash to the owner.

## Not read

- `air.js`, `noise.js`, `palette.js`, `solar.js`; `tree.js` beyond a grep.
- HP outside 628–800, 1036–1150, 3706–3785, 3940–4100, 4296–4360 and greps.
- MD outside 975–1000 and 1044–1227.
- `SkyBackground.swift`, `MoonClock.swift` above line 170, `SleepEvent`, `RecordMapping`, `AppDelegate`, `LaunchOverlay`, `TodayHeroCard`.
- No still or film.
