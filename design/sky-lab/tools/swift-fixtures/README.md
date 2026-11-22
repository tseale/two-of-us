# Swift fixtures: the lab's numbers, for the app's tests

The painted hill is built in Swift from this lab (`TwoOfUs/Sky/Core/`). Its unit tests do not restate
the Swift: they compare it with what the lab computes. These scripts are where the lab says it. Each one
runs the lab's own code and writes one Swift file of plain data into `TwoOfUsTests/`.

**The `SkyCoreFixtures…swift` files are generated. Never edit one by hand.** Change the lab, run the
exporter, commit both. The code that reads them is written by hand, once:
`TwoOfUsTests/SkyCoreFixture.swift`.

| Script | Writes `TwoOfUsTests/…` | From | Needs |
|---|---|---|---|
| `night.mjs` | `SkyCoreFixturesNight.swift` | `lab/solar.js` (the sun), `lab/core.js` (night hours, the night has begun), `lab/nights.js`, `lab/presence.js` (starlight, room depth) | node |
| `season.mjs` | `SkyCoreFixturesSeason.swift` | `lab/season.js`, every day of a year; the tree's step | node |
| `colour.mjs` | `SkyCoreFixturesColour.swift` | `lab/oklab.js`, the colour half of `air.js`, `heldTo` | node |
| `air.mjs` | `SkyCoreFixturesAir.swift` | `skies/hill-painted/air.js` (`airFor`: colours, sky, haze, mist, the hush) | node |
| `look.mjs` | `SkyCoreFixturesLook.swift` | `lookOf`, read frame by frame from the running page | Chromium |
| `palette.mjs` | `SkyCoreFixturesPalette.swift` | `resolve` (the palette for a minute), run in the lab's page | Chromium |
| `moment.mjs` | `SkyCoreFixturesMoment.swift` | the two worlds, the camera, the bedtime moment's table and curves | Chromium |
| `stars.mjs` | `SkyCoreFixturesStars.swift` | the hash and noise, the skyline, `starsFor` on 52 skies | Chromium |

`emit.mjs` is not an exporter: it is the writer the first six share.

## Running them

From the repository's root (any directory works; paths are taken from the script's own place):

    for s in night season colour air look palette moment stars; do
      node design/sky-lab/tools/swift-fixtures/$s.mjs          # writes the file
    done

Add `--check` to write nothing and exit 1 if the file on disk is not what the lab says today. All eight
take about a minute. A second run must leave every file byte-identical: nothing here is random.

The four that need Chromium use the Playwright already installed for the lab's other tools (never run
`playwright install`). `look.mjs` reads what the page already publishes. The other three serve the sky
module to a headless page with a few read-only probe lines added **in transit, never on disk**, because
the sky keeps its worlds and rules inside its closure. If the sky module changes shape, the script stops
and names the mark it could not find: fix the mark in the script, never a number in the Swift.

## After running

    make test        # on a Mac

A change in the lab shows up as a diff in a fixture and as a failing test beside it. That is the point.
