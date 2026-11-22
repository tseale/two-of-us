# Stage 0a on the Mac, and the stage 1 spikes: the report

> Written on 22 Nov 2026 by the session that ran them on the owner's Mac mini (Xcode 27.0, build
> 27A266a; iPhone 17 simulator, iOS 27.0). Working context for `docs/SKY_BUILD_PLAN.md`, not a
> maintained document. **Everything below was seen on a simulator. Nothing here has been on a
> phone**, and three answers need one (marked).

## Stage 0a on the Mac

- `make test` from a clean derived-data folder: **1,045 tests, 0 failures**. The 275 sky tests (19
  suites) take about 4.3 s on the simulator; the slowest are StarChart 1.6 s and NightRule 1.5 s.
- The sky code needed no change: no compile error, no name clash, no Darwin/glibc difference, no
  tolerance touched, no warning. The 2 MB of fixtures build without trouble.
- Widgets, watch app, complication and notification extension build and compile no sky file. A
  Release build succeeds.
- **`main` did not compile** (not the sky's doing): PR #300 calls the main-actor
  `BrightwheelImporter.messagePhotoPrefix` from a non-isolated function, and Xcode Cloud's archive
  of `3583e43` failed on 21 Nov. Fixed on this branch only (`4b8db94`, one word: `nonisolated`).

## How to try the bench

Settings → Data → "Painted sky" (off by default, this phone only). While on:

- **Sky bench** (the link under the switch): "1 · Sky field and tone" and "2 · Land in Core
  Graphics". Tap the picture to hide the controls.
- **Home** (a slab iPhone or the closed Duo) gets a stand-in sky under the list and a small pill
  above the tab bar: **Look** (the camera up or down, then what it measured), **Cards** (each
  card away or back), **Rects** (the header's measured frames).
- DEBUG builds also take launch arguments, for captures: `-skyBench field|land`,
  `-skyBenchHour 16.1667`, `-skyBenchPanel 0`, `-skyBenchLook 1`, `-skyBenchCards 0.5`,
  `-skyBenchRects 1`, `-skyBenchPlay 1`, and `-ui.paintedSky "<true/>"`.

The stand-in is the sky field and, on a slab, every hill but the knoll. No tree, sun, moon,
stars, mist, clouds or river: those are stage 2.

## The six answers

### 1. The sky field as a shader, and its tone (risk 3)

- **Tried:** `SkyFieldTexture` (the air on the lab's 2 pt grid, in OKLab, before the room's tone,
  as one 16-bit image) printed by `SkyField.metal` through `colorEffect`, with the hush and the
  room's depth as uniforms ahead of one dither.
- **Measured:** the 16-bit image reaches the shader as half floats (lightness keeps 12 bits at
  0.25–0.5, more below) and unchanged by colour management; the shader's output is taken as sRGB.
  Against the lab's frames (21 Nov, dark, slab): 4:10 pm at rest and 9 pm looking up agree to
  within 2 levels wherever the lab paints nothing else. Stepping the room's depth by 0.02 at
  9 pm moves the mean of a sky patch by 0.055 of a level: the tone is continuous, no whole-level
  step. The texture (224 × 416 samples) is made off the main thread.
- **Found on the way:** Xcode 27 does not ship the Metal compiler. The build fails with "cannot
  execute tool 'metal' due to missing Metal Toolchain" until
  `xcodebuild -downloadComponent MetalToolchain` (839 MB) has been run. It is now installed on
  this Mac. **Whether Xcode Cloud's image has it is not known**; if not, `ci_post_clone.sh` needs
  that line or the archive of `main` breaks at the merge.
- **Decision:** the shader stands; no CPU fallback needed. Before any merge to `main`, prove the
  Metal toolchain on Xcode Cloud (a throwaway workflow on the branch, or the line in
  `ci_post_clone.sh`).
- **Needs a phone:** whether a moving tone is clean on the OLED in a dark room. Bench 1 →
  "Breathe" at Hour 21:00 runs the hush and the depth together every six seconds.

### 2. One land plane in Core Graphics (risk 1)

- **Tried:** `SkyLandPainter`, the lab's `paintPlane` stroke for stroke for the shapes that need
  only themselves (the slab's far range and ridge, hill, near, and both fore hills): the fill
  along x, the quarter-size wash, each blurred stroke on its own layer under three vImage box
  passes, the dry-brushed rim, the mottle, and deep night's bright-and-dithered plane.
- **Measured** (simulator, Debug, 3×): mean difference from the lab's 4:10 pm frame about 2 levels
  a channel in four clean regions (the lab's own grain is about that), larger only along crests
  where the dry brush falls differently. At 9 pm looking up the land's values agree (about
  10, 13, 23). Painting: far 308 ms, mid 151, near 83, fore 120, off the main thread. Four
  uncropped plates are 52 MB at 3×.
- **Decision:** the land painter ports to Core Graphics as planned; the fallback (masks exported
  from the lab) is not needed. The plan's cropping is needed: uncropped, the planes alone pass
  the 40 MB budget. 8-bit layers were enough to match the lab; whether deep night bands on an
  OLED is the phone's to say (Bench 2 at Hour 21:00, Look 1).
- **Not ported yet:** the knoll (a spur with a melting foot), the valley floor and river, mist
  bands, the shade under his name in snow.

### 3. The sky hoisted out of the list, under the glass (risk 5)

- **Tried:** with the switch on, `SkyBenchStage` is the first child of Home's ZStack and the
  list's own `SkyBackground` is left out.
- **Saw:** the list scrolls over it, the glass tiles take the sky and the land through them, and
  the frame reads like the lab's signature frame (`cmp-home2`, judged side by side at phone
  size). With the switch off Home is pixel for pixel as before, as far as two stills can show.
- **Decision:** hoisting works. Two things for stage 2: (a) in demo mode the banner row pushes
  Home down, so the sky must be anchored to the window, not to Home's frame (the bench's is
  not, and starts under the banner); (b) the open Duo's two skies were not tried: this Xcode
  has no Duo simulator.

### 4. Cards, glass included, fading one by one (risk 2)

- **Tried:** `.opacity` on each card on its own (Today, the tile row, the sleep card, the
  checklist, the timeline section); the header untouched. Stills at 1, 0.5, 0.15 and 0, and a
  recording of the fade out (1.0 s ease-in-out) and back (1.2 s ease-out).
- **Saw:** the glass keeps the sky through the whole fade and does not jump; in the recording no
  frame differs from the one before by more than the fade itself, at the start or the end.
- **Found:** at zero the timeline card's background is still there. Its rows' backgrounds are
  `listRowBackground`s, which the section's opacity does not reach. They need the veil too, as
  the plan says.
- **Decision:** a fade per card is right, and the tile row can fade as one (its glass container
  did not lose the sky). Give `CardVeil` to the row backgrounds as well.
- **Needs a phone:** the one-frame step the lab's films met; a simulator recording drops frames.

### 5. The camera at 60 with Home ticking (risk 4)

- **Tried:** each layer on a SwiftUI `.offset` from `SkyCamera`, driven by a `Glide` read in a
  `TimelineView(.animation)` that runs only during the move, with Home's one-second timeline
  running; a `CADisplayLink` counts frames across the move.
- **Measured** (simulator, Debug): 158 frames in 2.6 s, 60 fps, longest 33 ms, one long frame.
- **Decision:** nothing here asks for the `CALayer` fallback. This is the weakest answer of the
  six: a simulator on a Mac mini says little about a phone.
- **Needs a phone:** press Look on Home and read the pill, a few times, once with a sleep running.

### 6. The real rects (risk 6)

Measured on the iPhone 17 simulator (points, in the window), against the lab's table:

| | App | Lab |
|---|---|---|
| Avatar | 16, 70, 60 × 60 | the same |
| Gear | 342, 70, 44 × 44 | the same |
| First card's top | 136.6 (off a still) | 136.59 |
| Name (text frame, "Charlie") | 90, 70, 113 × 40.7 | 92, 77, 92 × 26 (the ink of "Miller") |
| Age (text frame) | 90, 112.7, 89.7 × 18 | 90, 115.59, 90.6 × 12 (ink) |
| Clock | x 57–91.7, y 25.7–39 | |
| Wi-Fi | x 313.3–332, y 25.7–39.3 | icons' foot at y 39 |
| Battery | x 340.7–369.7, y 25.3–39 | right edge at 366 |
| Top safe area | 62 | |

- **Decision:** on the slab the lab's guesses hold; `SkyLayoutModel` can take the avatar, gear and
  first card from constants, and the icons' foot of 39.
- **Not measured:** the island (a simulator still does not draw it); the name's width for
  "Miller" in SF Rounded (the sample baby is "Charlie"); anything on the Duo.

## What I would change in the plan

1. Add "the Metal toolchain on Xcode Cloud" as a gate before the first merge to `main`.
2. Stage 2 anchors the sky to the window (demo mode's banner).
3. `CardVeil` covers `listRowBackground`s; the tile row fades as one.
4. Keep the bench (`TwoOfUs/Sky/Bench/`) through stage 2 as the place to compare with the lab,
   then delete it with the switch at stage 9. `SkyLandPainter` and `SkyFieldTexture` are the
   starting points for `SkyPrinter`; `SkyBenchMinute` gives way to `SkyBodies` and `SkyInputs`.
5. Fix `main` (the `nonisolated` word) on its own, soon: no build has reached the phones since
   PR #300.

## What I need from the owner

1. On your iPhone 17, from Xcode or a TestFlight build of this branch: the three "needs a phone"
   checks above (tone in a dark room, the Look meter, the cards' fade).
2. A way to see the Duo: Xcode 27.1's simulator on this Mac, or the phone itself. Nothing about
   the Duo is answered here.
3. A word on `main`: whether to send the one-word fix there as its own pull request.
4. A photo or the numbers for the island's rect, if the lab's 126 × 37 at y 14 is to be checked.

## Left on this Mac

- Apple's Metal Toolchain component for Xcode (839 MB), installed by `xcodebuild
  -downloadComponent MetalToolchain`.
- A simulator named "Sky 17" (delete with `xcrun simctl delete "Sky 17"`), and derived data at
  `~/Library/Developer/Xcode/DerivedData/TwoOfUs-sky`.
- A git worktree at `.claude/worktrees/sky`. The checkout on `fix-today-card-sleep` was not touched.
