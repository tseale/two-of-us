# Two of Us 🍼

A native iOS baby-tracking app for two parents to log their newborn's **feeds,
sleep, and diaper changes** — with real-time sync between both of their iPhones.
Built for speed of entry (you're holding a baby), a calm dark-mode-first
interface for 3 AM use, and a glanceable layer so the answer to "when did he last
eat?" is already on your lock screen. Distributed privately via TestFlight to the
two parents — no App Store submission.

## Status

**In active development**, targeting **iOS 26**. Core logging, the glanceable
layer (widgets + Sleep Live Activity), Siri / Shortcuts / Control Center
controls, stats, and CloudKit two-parent sharing are all implemented in SwiftUI
with local SwiftData persistence. The app adopts iOS 26's headline frameworks —
Liquid Glass, AlarmKit feed reminders, on-device Foundation Models, and Control
Center controls (see [iOS 26 features](#ios-26-features)). Each degrades
gracefully where the OS or hardware doesn't support it.

## UI preview

> The images below are dark-mode UI mockups that reflect the implemented screens
> (Liquid Glass cards, on-device AI). Live device captures require building in
> Xcode on macOS.

**Core screens — Home · Feed · Sleep · Diaper**
*Liquid Glass cards, an on-device insight strip, one-tap log tiles, and the ✨ quick-log entry point.*

![Home, Feed, Sleep, and Diaper screens](mockups/mockup.png)

**Glanceable layer — lock-screen Live Activity & widgets · Control Center controls**
*A running Sleep timer and "next feed due" reminder on the lock screen; one-tap Log Feed / Log Diaper / Sleep toggle from Control Center, the Lock Screen, and the Action Button.*

![Lock screen Live Activity, widgets, and Control Center controls](mockups/mockup-lock.png)

**On-device AI — natural-language quick log & Foundation Models insights**
*Type "4 oz bottle, 20 minutes ago" and it's parsed on-device; the Stats tab opens with a warm plain-English recap of the week.*

![Natural-language quick log and Stats insights](mockups/mockup-ai.png)

**Insights — richer chart exploration (design direction)**
*Future Swift Charts work explored in [`docs/VISUALIZATIONS.md`](docs/VISUALIZATIONS.md).*

![Stats and charts exploration](docs/mockups/visualizations.png)

## Features

### Logging — as few taps as possible
- **Feed** — log a bottle in ounces from configurable presets or a custom amount
- **Sleep** — start/stop the single running timer; shows live elapsed time
- **Diaper** — wet / dirty / both, logged with one tap
- **Natural-language quick log** — tap ✨ and type "4 oz, 20 min ago" or "wet
  diaper"; parsed entirely on-device by Foundation Models (nothing leaves the phone)
- **Full edit + backdate** — fix the time, amount, type, or notes on any event

### At a glance
- **Rolling timeline** — the last 12–24 hours of events on a timeline rail (not a
  midnight "Today" reset)
- **Urgency colors** — a green → amber → red countdown to the next bottle at your
  target feed interval (default 3h, configurable)
- **Home- & lock-screen widgets** — time since the last feed / sleep / diaper
- **Sleep Live Activity** — a running timer on the lock screen and Dynamic Island
  while the baby is asleep (feeds are instantaneous, so there's no feed activity)
- **Feed reminders** — an AlarmKit "next feed due" countdown that breaks through
  Silent and Focus, re-armed on every feed (device-local, opt-in)
- **Control Center / Action Button controls** — Log Feed, Log Diaper, and a
  stateful Sleep toggle, also surfaced on the Lock Screen
- **Siri** — "Hey Siri, log a diaper change" via App Intents and Shortcuts

### Insights
- **On-device insights** — a short, warm recap of feeding cadence, longest sleep
  stretch, and busiest hour, generated locally on the Stats tab
- **Stats & history** — daily summaries, lifetime totals, night-shift split
  between caregivers, hungriest hour, and longest sleep (Swift Charts)
- **CSV export** — back up the full log from Settings → Manage Data

### Sharing & sync
- **Real-time two-parent sync** — both phones see updates within ~10 seconds via
  CloudKit, with an invite/join flow to add the second parent
- **Per-parent attribution** — each participant has a colored initial so you can
  see who logged what
- **Roles** — Co-parent (full access) and Guest (log + edit, no settings changes)

### Design & accessibility
- **Liquid Glass UI** — translucent cards and log tiles with a tab bar that
  minimizes on scroll (iOS 26)
- **Dark + Light appearance** — follows the iOS system setting
- **Accessibility** — Dynamic Type, VoiceOver labels, color-plus-label urgency,
  one-handed operation, and silent feedback (haptics + visuals, no sound)

## Tech stack

- **SwiftUI** — declarative UI, iOS 26
- **SwiftData** — local persistence and source of truth
- **CloudKit (CKSyncEngine + CKShare)** — real-time sync and the invite/join flow
  between both parents' iPhones (free for 2 users, no server)
- **WidgetKit** — lock-screen and home-screen widgets ("time since last feed")
- **ActivityKit / Live Activities** — live Sleep timer on the lock screen and Dynamic Island
- **App Intents / Siri & Controls** — voice logging plus Control Center / Action Button controls
- **AlarmKit** — "next feed due" reminder that breaks through Silent / Focus (iOS 26)
- **Foundation Models** — on-device natural-language logging and insights (iOS 26)
- **Swift Charts** — built-in charting for sleep/feed patterns

## iOS 26 features

The app targets iOS 26 and adopts four of its frameworks; each degrades
gracefully where unsupported:

- **Liquid Glass** — `glassCard()` / `glassTile()` modifiers in
  `DesignSystem/Colors.swift` back the status pills, insight strip, log tiles, and
  Stats/History cards; the tab bar minimizes on scroll.
- **AlarmKit feed reminders** — `Alarms/FeedAlarmManager.swift` schedules a single
  "next feed due" countdown that pierces Silent / Focus. Device-local and opt-in
  (`LocalPrefs.feedReminderEnabled`), re-armed on each feed and on app foreground.
- **Foundation Models** — `AI/MillerIntelligence.swift` runs everything on-device:
  a warm Insights summary over `StatsEngine`, and `@Generable` natural-language
  parsing behind the ✨ quick-log sheet. Gated on model availability; the UI hides
  when unavailable.
- **Controls** — `TwoOfUsWidgets/LogControls.swift` exposes Log Feed, Log Diaper,
  and a stateful Sleep toggle to Control Center, the Lock Screen, and the Action
  Button, reusing the existing App Intents.

## Project structure

```
TwoOfUs/                    # Main iOS app target
├── App/                    # Entry point & routing (TwoOfUsApp, RootView, AppDelegate)
├── Models/                 # SwiftData models (Baby, FeedEvent, SleepEvent, DiaperEvent, Participant, …)
├── Store/                  # ModelContainer, EventStore, StatsEngine, seed & demo data
├── DesignSystem/           # Colors + Liquid Glass, Urgency, Haptics, Typography, TimeFormatting, DayRibbon
├── Features/               # Home, Feed, Sleep, Diaper, Edit, History, Stats, Settings, Onboarding, Timeline
├── Intents/                # Siri App Intents (LogFeed, LogDiaper, ToggleSleep) + QuickLogger + Shortcuts
├── AI/                     # MillerIntelligence — on-device Foundation Models (insights + NL logging)
├── Alarms/                 # FeedAlarmManager — AlarmKit "next feed due" reminder
├── LiveActivities/         # Sleep Live Activity (ActivityKit)
├── Sync/                   # CloudKit sync engine, sharing & join flows
└── Support/                # App Group, local prefs, CSV export, image downscale

TwoOfUsWidgets/             # WidgetKit extension (small/medium/large widgets + ribbon,
                            #   Live Activity views, and Control Center controls)
docs/                       # Design & implementation documentation (see below)
mockups/                    # UI mockups (PNG + interactive index.html)
project.yml                 # XcodeGen project specification
Makefile                    # Common build/run tasks
.githooks/                  # Auto-regenerate the .xcodeproj when project.yml changes
```

## Building & running

The `.xcodeproj` is generated from `project.yml` by
[XcodeGen](https://github.com/yonaskolb/XcodeGen) and is gitignored, so generation
is the canonical first step. The `Makefile` wraps the common tasks:

```sh
brew install xcodegen        # if needed
make bootstrap               # enable git hooks + generate TwoOfUs.xcodeproj
open TwoOfUs.xcodeproj        # or: make run  (build + launch on the simulator)
```

| Target | What it does |
|--------|--------------|
| `make project` | Regenerate `TwoOfUs.xcodeproj` from `project.yml` (and enable hooks) |
| `make build` | Regenerate, then build for the simulator |
| `make run` | Build, install, and launch on the iPhone simulator |
| `make clean` | Remove the generated project and build output |

Build & run on an iOS 26 simulator or device (Xcode 26 / iOS 26 SDK). CloudKit
sync requires a paid Apple Developer account and being signed in to iCloud on the
device. Foundation Models features (NL quick-log, Insights) require Apple
Intelligence–capable hardware and hide themselves where unavailable.

## Documentation

| Doc | What's in it |
|-----|--------------|
| [`docs/BUILD_PLAN.md`](docs/BUILD_PLAN.md) | Phased build roadmap, v1 scope, effort estimates |
| [`docs/DATA_MODEL.md`](docs/DATA_MODEL.md) | SwiftData schema, CloudKit layout, schema-evolution rules |
| [`docs/DESIGN.md`](docs/DESIGN.md) | Design system, screen states, accessibility |
| [`docs/IOS_VS_WEB_COMPARISON.md`](docs/IOS_VS_WEB_COMPARISON.md) | Why native iOS over a PWA (decision record) |
| [`docs/SIRI_AND_SHORTCUTS.md`](docs/SIRI_AND_SHORTCUTS.md) | Siri phrases, App Intents, Shortcuts & Control Center controls |
| [`docs/PRIVACY.md`](docs/PRIVACY.md) | Privacy model, data storage, access & roles |
| [`docs/VISUALIZATIONS.md`](docs/VISUALIZATIONS.md) | Future charts/stats design exploration |

## Roadmap

- **Phase 1 — Core logging** ✅ Feed/Sleep/Diaper, rolling timeline, edit/backdate,
  urgency colors, onboarding
- **Phase 2 — Live features & widgets** ✅ CloudKit sharing, home/lock-screen widgets,
  Sleep Live Activity
- **Phase 3 — Insights** ✅ sleep/feed charts and stats (Swift Charts)
- **Phase 4 — Smart features** ✅ Siri intents, Shortcuts, Control Center controls
- **iOS 26 adoption** ✅ Liquid Glass, AlarmKit feed reminders, on-device Foundation
  Models (NL logging + insights)
- **Next** — per-user push notifications; widget accented-rendering polish; an
  AlarmKit "Log feed" alert action

See [`docs/BUILD_PLAN.md`](docs/BUILD_PLAN.md) for the full plan.
