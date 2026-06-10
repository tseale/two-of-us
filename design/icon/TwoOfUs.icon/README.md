# TwoOfUs.icon — Liquid Glass app-icon scaffold

This is a **scaffold** for the iOS 26 Liquid Glass app icon, generated headlessly
by `design/icon/generate_icons.py`. It lives under `design/` (not in the compiled
`TwoOfUs/` sources) on purpose, so an unfinished bundle can never affect a build.
The app currently ships its icon from `TwoOfUs/Assets.xcassets/AppIcon.appiconset`
(the same "two of us" mark, flat PNG). Finish this `.icon` on a Mac, then switch
the build over — see `docs/ICON_AND_SPLASH_MAC_STEPS.md`.

## The mark

"Two of Us" — two overlapping circles (the two parents) with a warm point of light
(Miller) at the heart, where they meet:

- **parent-left.png** — periwinkle `#8E8EFF` circle (left parent)
- **parent-right.png** — teal `#5AC8B8` circle (right parent)
- **baby.png** — warm near-white `#FFF4E8` dot (deliberately **not** amber — amber
  is the diaper color in the app)
- **background.png** — soft near-black radial gradient for depth

## Layer stack (bottom → top)

1. `background.png` — full-bleed background
2. `parent-left.png` + `parent-right.png` — the two parents (translucent + specular;
   the overlap screen-blends to a bright shared glow on device)
3. `baby.png` — the baby, a bright specular point at the heart

## `icon.json` is provisional

The `icon.json` here is a **best-effort starter** — Icon Composer's manifest schema
isn't publicly documented, so the material/translucency keys are a starting point to
tune in the GUI, not a guaranteed-final artifact. If Icon Composer doesn't open this
bundle cleanly, just create a new icon in Icon Composer and **re-import the four PNGs
from `Assets/` in the stack order above** — the artwork is the durable part.

## Regenerating

Edit the geometry/colors at the top of `design/icon/generate_icons.py`
(`CIRC_R`, `CIRC_SHIFT`, `DOT_RADIUS`, `BABY`, palette) and run:

```sh
python3 design/icon/generate_icons.py
```

This rewrites `Assets/*.png` here, the `AppIcon.appiconset` PNG fallback, and the
`LaunchLogo` used by the launch screen — all from the same geometry.
