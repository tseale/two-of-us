# Miller Time 🍼

A native iOS baby-tracking app for two parents to track their newborn — feeds,
sleep, and diaper changes — with real-time sync between both of their iPhones.
Built for speed of entry (you're holding a baby) and a calm, dark-mode-first
interface for 3 AM use. Distributed privately via TestFlight.

## Status

**In active development.** Phase 1 (core logging) is implemented in SwiftUI with
local SwiftData persistence; CloudKit sync, widgets, Live Activities, and Siri
intents are in progress. No App Store submission — the app is distributed via
TestFlight to the two parents.

## UI Preview

> The images below are dark-mode UI design mockups that reflect the implemented
> screens. (Real device captures require building in Xcode on macOS.)

**Core screens — Home · Feed · Sleep · Diaper**

![Home, Feed, Sleep, and Diaper screens](mockups/mockup.png)

**Glanceable layer — lock screen Live Activity & home-screen widget**

![Lock screen Live Activity and home-screen widget](mockups/mockup-lock.png)

**Insights — sleep/feed visualizations (Phase 3)**

![Stats and charts exploration](docs/mockups/visualizations.png)

## Features

- **Fast one-tap logging** — as few taps as possible:
  - **Feed** — log a bottle in ounces (configurable presets + custom amount)
  - **Sleep** — start/stop timer (the single running timer); shows live elapsed time
  - **Diaper** — wet / dirty / both, logged with one tap
- **Rolling timeline** — the last 12–24 hours of events (not a midnight "Today" reset)
- **Full edit + backdate** — fix the time, amount, type, or notes on any event
- **Urgency colors** — green → amber → red countdown to the next bottle at your
  target feed interval (default 3h, configurable)
- **Per-parent attribution** — each participant has a colored initial so you can
  see who logged what
- **History & stats** — review past events and emerging sleep/feed patterns
- **Real-time two-parent sync** — both phones see updates within ~10 seconds
- **Dark + Light appearance** — follows the iOS system setting
- **Accessibility** — Dynamic Type, VoiceOver labels, color-plus-label urgency,
  one-handed operation, silent (haptics + visuals, no sound)

## Tech Stack

- **SwiftUI** — declarative UI, iOS 17+
- **SwiftData** — local persistence with automatic CloudKit sync
- **CloudKit** — real-time sync between both parents' iPhones (free for 2 users, no server)
- **WidgetKit** — lock screen and home screen widgets ("time since last feed")
- **ActivityKit / Live Activities** — live Sleep timer on the lock screen and Dynamic Island
- **App Intents / Siri** — "Hey Siri, log a diaper change"
- **Swift Charts** — built-in charting for sleep/feed patterns

## Glanceable layer

- **Home-screen & lock-screen widgets** — time since the last feed/sleep/diaper at a glance
- **Sleep Live Activity** — a running timer on the lock screen and Dynamic Island while
  the baby is asleep (feeds are instantaneous, so there's no feed activity)
- **Siri App Intents** — log a feed or diaper, or toggle sleep, by voice

## Project structure

```
MillerTime/                 # Main iOS app target
├── App/                    # Entry point & routing
├── Models/                 # SwiftData models (Baby, FeedEvent, SleepEvent, DiaperEvent, Participant, …)
├── Store/                  # ModelContainer, EventStore, StatsEngine, seed data
├── DesignSystem/           # Colors, Urgency, Haptics, TimeFormatting, DayRibbon
├── Features/               # Home, Feed, Sleep, Diaper, Edit, History, Stats, Settings, Onboarding
├── Intents/                # Siri App Intents (LogFeed, LogDiaper, ToggleSleep)
├── LiveActivities/         # Sleep Live Activity (ActivityKit)
├── Sync/                   # CloudKit sync, sharing & join flows
└── Support/                # App Group, local prefs

MillerTimeWidgets/          # WidgetKit extension (small/medium/large + ribbon + Live Activity views)
docs/                       # Design & implementation documentation (see below)
mockups/                    # UI mockups (PNG + interactive index.html)
project.yml                 # XcodeGen project specification
```

## Building & running

The Xcode project is generated from `project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen   # if needed
xcodegen generate
open MillerTime.xcodeproj
```

Then build & run on an iOS 17+ simulator or device. CloudKit sync requires a paid
Apple Developer account and being signed in to iCloud on the device.

## Documentation

| Doc | What's in it |
|-----|--------------|
| [`docs/BUILD_PLAN.md`](docs/BUILD_PLAN.md) | Phased build roadmap, v1 scope, effort estimates |
| [`docs/DATA_MODEL.md`](docs/DATA_MODEL.md) | SwiftData schema, CloudKit layout, schema-evolution rules |
| [`docs/DESIGN.md`](docs/DESIGN.md) | Design system, screen states, accessibility |
| [`docs/IOS_VS_WEB_COMPARISON.md`](docs/IOS_VS_WEB_COMPARISON.md) | Why native iOS over a PWA (decision record) |
| [`docs/PRIVACY.md`](docs/PRIVACY.md) | Privacy model, data storage, access & roles |
| [`docs/VISUALIZATIONS.md`](docs/VISUALIZATIONS.md) | Future charts/stats design exploration |

## Roadmap

- **Phase 1 — Core logging** ✅ Feed/Sleep/Diaper, rolling timeline, edit/backdate,
  urgency colors, onboarding
- **Phase 2 — Live features & widgets** — CloudKit sharing, lock-screen widgets,
  Sleep Live Activity, per-user notifications
- **Phase 3 — Insights** — sleep/feed charts and stats (Swift Charts)
- **Phase 4 — Smart features** — Siri intents and quality-of-life polish

See [`docs/BUILD_PLAN.md`](docs/BUILD_PLAN.md) for the full plan.
