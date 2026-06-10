# Siri & Shortcuts — Two of Us

Two of Us exposes its logging and a few "ask the app" actions to Siri, Spotlight,
the Shortcuts app, and (on iOS 18) Control Center / the Action button — no extra
setup required. This doc is for the two of us using the app: what you can say, and
a few automations worth building.

## Things you can say to Siri

You don't have to open the app. Just say "Hey Siri, …":

### Logging
- **"Log a feed in Two of Us"** — logs a bottle at your default amount.
  (Siri can't capture a spoken ounce number directly; to log a specific amount,
  build a "Log 3 oz" shortcut in the Shortcuts app — the Log Feed action has an
  **Amount** field.)
- **"Log a diaper in Two of Us"** — logs a wet diaper.
- **"Log a dirty diaper in Two of Us"** / **"…wet diaper…"** / **"…both…"** — logs that type.
- **"Start sleep in Two of Us"** / **"Stop sleep in Two of Us"** — starts/stops the sleep timer.
- **"Undo that in Two of Us"** — removes the most recent thing you logged.

Each one speaks a confirmation back ("Logged 3 oz for Miller.").

### Asking
- **"When did Miller last eat in Two of Us"** — "Miller last ate 4 oz 1h 50m ago…"
- **"When was Miller's last diaper in Two of Us"**
- **"Is Miller asleep in Two of Us"** / **"How long has Miller been sleeping…"**
- **"How is Miller doing today in Two of Us"** — today's feeds, ounces, and diapers.

> Tip: in the Shortcuts app you can rename any of these to a shorter phrase you
> like better (e.g. just "Miller ate") under the shortcut's settings.

## Automations worth building (Shortcuts app → Automation tab)

These use the same actions; build them once and they run hands-free.

### NFC tags (fastest one-tap logging)
Stick a cheap NFC sticker where you do the thing, then: **Automation → New → NFC →
Scan** the tag → add the matching action.
- **On the changing table** → run **Log Diaper**.
- **On the crib / bassinet** → run **Start sleep** (and a second tag, or the same
  one toggling, for **Stop sleep**).
- **On the bottle warmer** → run **Log Feed**.

Tap the tag with your phone while holding the baby — no screen, no taps.

### "Goodnight" routine
**Automation → Time of Day** (or hook into your existing Goodnight Focus/scene) →
run **Start sleep**. Pairs nicely with turning the lights off.

### Feed reminder
**Automation → Time of Day** isn't ideal for "X hours since last feed," so instead:
build a **Personal Automation** that, on a schedule, asks Two of Us *"How is
Miller doing today"* — or simpler, set a manual reminder keyed to the app's
**next-feed countdown** (Settings → target interval, default 3h). The app's widget
gauge already shows the countdown; the automation is just a nudge.

## iOS 18: Control Center, Lock Screen & the Action button

Three controls ship with the app: **Log Feed**, **Log Diaper**, and **Start/Stop
Sleep**.

- **Control Center:** swipe down → **＋** (top-left) → **Add a Control** → find them
  under *Two of Us*.
- **Lock Screen:** customize the Lock Screen → tap a control slot → pick a Miller
  Time control.
- **Action button** (iPhone 15 Pro and later): **Settings → Action Button →
  Controls →** pick a Two of Us control. One press logs without unlocking.

All of these write through the same shared store as the app and sync to the other
parent on the app's next launch.
