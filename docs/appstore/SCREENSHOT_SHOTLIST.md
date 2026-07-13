# App Store Screenshot Shot-List

A repeatable plan for capturing App Store screenshots with realistic data, so
the listing looks lived-in instead of empty. Keyed to the `-seedSampleData`
launch argument (`TwoOfUsApp.swift:21`), which populates ~a week of events.

---

## Required sizes (App Store Connect)

ASC requires at least one set; the **6.9" iPhone** set is the modern baseline
and ASC down-scales it to smaller iPhones if you don't supply them. iPad is
required **only if the app is offered on iPad** (it is — portrait is enabled).

| Display class | Example device | Portrait points | Required? |
|---|---|---|---|
| iPhone 6.9" | iPhone 16 Pro Max / 17 Pro Max | 1320 × 2868 px | ✅ Baseline |
| iPhone 6.5" | iPhone 11 Pro Max / XS Max sim | 1242 × 2688 px | Recommended fallback |
| iPad 13" | iPad Pro 13" (M4) | 2064 × 2752 px | ✅ (app runs on iPad) |

Capture **both light and dark** for each — the brief sells dark mode from day 1,
so show it. Up to **10 screenshots per size**; aim for **5–6 strong ones**.

---

> **Automated:** `scripts/capture_appstore_screenshots.sh` runs
> `AppStoreScreenshotTests` (shots 1–5 below) on the 6.9" iPhone and 13" iPad,
> light + dark, with the clean status bar, and exports PNGs to
> `docs/appstore/screenshots/` (gitignored). The widget and Live Activity shots
> below still need the manual capture. The manual steps that follow remain the
> reference for one-off captures.

## Setup (do this once per simulator)

1. Boot the target simulator (e.g. iPhone 16 Pro Max), set **Appearance** for
   the pass: `xcrun simctl ui booted appearance light` (or `dark`).
2. Launch the app with seed data — in the Xcode scheme add `-seedSampleData`
   under *Run → Arguments Passed On Launch*, **or**:
   `xcrun simctl launch --console booted com.taylorseale.twoofus -seedSampleData`
3. Set a clean status-bar (optional but nicer):
   `xcrun simctl status_bar booted override --time 9:41 --batteryLevel 100 --cellularBars 4 --wifiBars 3`
4. Capture: `⌘S` in the Simulator, or
   `xcrun simctl io booted screenshot ~/Desktop/shots/<name>.png`
5. Repeat the whole pass for the other appearance and each device size.

> Tip: drive it with the same `-seedSampleData` build for every size so the
> data is identical across screenshots — consistency reads as polish.

---

## The shots (in listing order)

Order matters: the **first 1–2 are what users see without scrolling** in search
results, so lead with the strongest story (shared timeline + quick logging).

| # | Screen | Source | What it should show | Caption idea |
|---|---|---|---|---|
| 1 | **Home** | `Features/Home` | Time-since-last-feed front and center, today's quick-log buttons, calm hero state | "Everything at a glance" |
| 2 | **Timeline** | `Features/Timeline` | A full, realistic day of feeds/sleep/diapers with who-logged attribution | "One shared timeline, both parents" |
| 3 | **Log sheet** | `Features/Feed` (or Diaper/Sleep) | A logging sheet mid-interaction — show how few taps it takes | "Log in a tap or two" |
| 4 | **Stats** | `Features/Stats` | Swift Charts feeding/sleep rhythm with a week of data | "See the patterns emerge" |
| 5 | **Widgets** | Home Screen | Lock Screen + Home Screen widgets ("time since last feed") — see widget note | "Always a glance away" |
| 6 | **Settings / People** | `Features/Settings` | The co-parent sharing / invite + roles section (avatars filled in) | "Invite your co-parent with a link" |

Optional extras if you want all 10 slots filled:
- **Live Activity / Dynamic Island** during an active feed or sleep timer
  (`TwoOfUsWidgets/SleepLiveActivityView.swift`) — Lock Screen shot.
- **History** detail (`Features/History`) for a per-day deep dive.
- **Onboarding** hero (`Features/Onboarding`) — only if it's visually strong.

---

## Widget & Live Activity shots (can't use plain simulator screenshot alone)

- **Home/Lock Screen widgets:** add the widget to a simulator Home/Lock Screen,
  then screenshot. Seed data drives the widget's "time since last feed" via the
  shared App Group, so launch the app with `-seedSampleData` first so the widget
  timeline has content.
- **Live Activity / Dynamic Island:** start a feed or sleep timer in-app to make
  the Live Activity appear, then capture the Lock Screen / Dynamic Island.
- Widget previews (`SmallEventWidget`, `MediumWidget`, `LargeWidget`,
  `RibbonWidget`) render in Xcode canvas too, but **ship real on-device captures**
  — canvas chrome looks fake in a listing.

---

## Polish checklist before upload

- [ ] Same seeded data across every size (consistency).
- [ ] Baby name is intentional (the seed uses a placeholder — confirm it reads
      well publicly; "Miller" is fine, or set a neutral demo name).
- [ ] No half-finished states, error banners, or debug toggles visible
      (watch for **Demo mode** / **Reset setup** rows in Settings).
- [ ] Status bar clean (9:41, full battery/signal) if you overrode it.
- [ ] Both **light and dark** captured for each size.
- [ ] First screenshot reads clearly as a *thumbnail* in search results.
- [ ] Avatars/photos in People + Home look filled-in, not empty initials.
- [ ] Optional: add text/device-frame overlays (caption ideas above) — keep them
      legible at thumbnail scale.

> If you frame screenshots with marketing captions, keep the captions free of
> medical claims for the same reason the listing copy does (age rating 4+).
