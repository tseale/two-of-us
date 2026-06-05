# Miller Time — Build Plan

**Baby**: Miller  
**Users**: Taylor + wife  
**Goal**: Track feeds, sleep, and diapers in real-time across both parents' devices  
**Platform**: Native iOS — iPhone + iPad (SwiftUI + CloudKit)  
**Distribution**: TestFlight  
**Last Updated**: June 2026

### Document set
- **BUILD_PLAN.md** (this doc) — scope, phases, timeline, risks
- [DATA_MODEL.md](DATA_MODEL.md) — SwiftData schema, storage tiers, CloudKit layout, schema-evolution rules
- [DESIGN.md](DESIGN.md) — design system, screen states, glanceable surfaces, accessibility
- [PRIVACY.md](PRIVACY.md) — what's stored, where, who can access
- [IOS_VS_WEB_COMPARISON.md](IOS_VS_WEB_COMPARISON.md) — why native iOS (decision record)
- **phases/** — a build-ready design doc per increment, written before that increment is built:
  - [01-foundation.md](phases/01-foundation.md) — Foundation & Core Loop (+ CloudKit sharing spike)
  - 02 — Sync & Sharing · 03 — Glance Layer · 04 — Notifications & TestFlight *(to be written before each)*

> **Note:** the locked v1 scope is broader than the original "Phase 1" below (sharing, glance layer, edit/backdate, notifications were pulled into v1). v1 is delivered as the four increments in `phases/`; the Phase 1–5 sections below remain useful background but the `phases/` docs are the build-time source of truth.

---

## v1 Scope (locked June 5, 2026)

A scoping pass narrowed v1. **These decisions supersede anything below that conflicts:**

- **Formula-only feeding** (Baby Brezza Pro Advanced). There is **no nursing/breast timer.** A feed = **amount in ounces** + timestamp, an instantaneous event (~2 taps, like a diaper).
- **Three core events only**: Feed (oz), Sleep (start/stop timer), Diaper (wet/dirty/both). Nothing else in v1 — no spit-up, meds, or mood logs.
- **Sleep is the only running timer** in the app.
- **Glanceable layer ships in v1** (not deferred): home/lock-screen **widget** ("Last bottle: 2h 40m ago") + **Sleep Live Activity**. Feeds are instantaneous, so there is no feed Live Activity.
- **Feed reminders = next-feed countdown**: each logged bottle schedules a reminder at +target interval (default ~3h, single value, editable in Settings; no day/night split yet). Logging a feed cancels the pending reminder and schedules the next.
- **Devices: iPhone + iPad** (adaptive SwiftUI). No Apple Watch in v1.
- **Units: ounces (oz)** throughout.
- **Full edit + backdate in v1**: logging lets you set a custom time ("now / 15 min ago / pick time"); any past entry can be edited or deleted. (Pulled forward from Phase 2 — parents log late.)
- **Urgency colors in v1**: green → amber → red on the time-since indicators (all three events) as the next bottle approaches. (Pulled forward from Phase 4.)
- **Rolling timeline**: home shows a continuous recent window (~last 12–24h), not a "Today" list that resets at midnight. Day-grouping is a stats-only concern, deferred.
- **Sharing via invite links (caregiver sharing pulled into v1)**: Taylor is the owner and sends CloudKit share invites to multiple participants — starting with his wife, also caregivers. Two roles: **Full** (log/edit/settings — co-parent) and **Logger** (log + edit events, no settings/baby changes — caregiver). No view-only tier. Both are read-write CloudKit participants; the role difference is enforced in-app, not by CloudKit. Rules out the shared-iCloud-login approach.
- **Attribution = colored initial** per participant on each timeline row (scales to N people, not a fixed T/W).
- **Per-user notifications**: push for any event type the *other* participants log is allowed, but each type is an opt-in toggle and prefs are **per-user/local (not synced)**. Requires CloudKit subscriptions / silent push. Includes a per-user **quiet-hours** window so reminders/alerts don't fire overnight.
- **Settings split**: *Shared* (synced) = baby info/DOB, target feed interval, oz presets. *Per-user* (local) = my notification toggles, my quiet hours, my display name/initial.
- **Appearance**: dark + light, **follows the iOS system setting**. (No dedicated 3am night mode in v1.)
- **Manage People**: full sharing lifecycle in v1 — invite + a screen to view participants, change role, and **revoke** access. Revoked person's logged events remain.
- **Cross-cutting constraints**: iCloud required (clear sign-in gate; still logs locally and back-fills on reconnect) · notifications are best-effort, never safety-critical · schema-migration discipline (SwiftData+CloudKit: all new properties optional/defaulted, resist rename/delete — name the model right now) · store absolute timestamps render local, handle DST/time-zone/midnight-crossing · accessibility: Dynamic Type, VoiceOver, haptics, **silent operation** · no analytics/tracking SDKs, no third-party deps.
- **Deferred**: nursing timer (n/a), growth charts/percentiles, Siri/App Intents, photo milestones, PDF export, Apple Watch, caregiver sharing.

---

## Tech Stack

| Layer | Choice | Rationale |
|---|---|---|
| **UI** | SwiftUI | Declarative, modern, haptics for free, 120fps on Pro models |
| **Local persistence** | SwiftData | First-class CloudKit sync, replaces Core Data boilerplate |
| **Sync** | CloudKit (private + shared database) | Free for 2 users, no server, conflict resolution built-in |
| **Live lock screen** | Live Activities + ActivityKit | Real-time feed/sleep timer on lock screen and Dynamic Island |
| **Widgets** | WidgetKit | "Last feed: 2h 15m ago" on lock screen and home screen |
| **Voice** | App Intents + Siri | "Hey Siri, log a diaper change" |
| **Charts** | Swift Charts (iOS 16+) | Built-in, no dependency needed |
| **Notifications** | APNs + UserNotifications | Reliable cross-parent push, no server needed |
| **Distribution** | TestFlight | Send link, they install — indistinguishable from App Store |

---

## Data Model

```swift
// SwiftData models — CloudKit sync is automatic when using @Model
// All models stored in a shared CloudKit container so both parents see the same data

@Model class Baby {
    var id: UUID
    var name: String
    var dateOfBirth: Date
    var createdAt: Date
}

@Model class FeedEvent {
    var id: UUID
    var baby: Baby
    var amountOz: Double         // formula amount in ounces
    var timestamp: Date          // feeds are instantaneous — no start/end
    var notes: String?
    var loggedBy: String         // "Taylor" or "Wife" — display name
}

@Model class SleepEvent {
    var id: UUID
    var baby: Baby
    var startedAt: Date
    var endedAt: Date?
    var notes: String?
    var loggedBy: String
}

@Model class DiaperEvent {
    var id: UUID
    var baby: Baby
    var type: DiaperType        // .wet, .dirty, .both
    var timestamp: Date
    var notes: String?
    var loggedBy: String
}

@Model class GrowthRecord {
    var id: UUID
    var baby: Baby
    var date: Date
    var weightKg: Double?
    var heightCm: Double?
    var headCircumferenceCm: Double?
}
```

Events are append-only in the MVP. Edits soft-delete the original and create a replacement. This avoids CloudKit merge conflicts.

> **Note (v1 scope):** `loggedBy: String` is a placeholder. With multiple invited participants (wife + caregivers), attribution should store a stable participant identity (display name + assigned color/initial), not a hardcoded "Taylor"/"Wife". Each timeline row renders that participant's colored initial. A lightweight `Participant` concept (name, color, role: `.full` / `.logger`) backs this; role gates the settings/baby-edit UI in-app.

---

## Phase 1: MVP Core

**Goal**: Both parents can log feeds, diapers, and sleep on their iPhones. Events sync between phones within seconds. App works end-to-end before any polish.

**Effort**: 8–10 days  
**Milestone**: Both parents' phones show the same timeline in real-time via TestFlight

### Features

#### Xcode Project Setup (Day 1, ~4 hrs)
- New Xcode project: SwiftUI, SwiftData enabled, CloudKit container (`iCloud.com.taylorseale.millertime`)
- Target: iOS 17+ (Live Activities, Swift Charts, SwiftData all require it)
- SwiftData stack wired up: `ModelContainer` with CloudKit sync enabled
- Basic folder structure:
  ```
  MillerTime/
    Models/          # SwiftData @Model classes
    Views/
      Main/          # HomeView, TimelineView
      Feed/          # FeedSheet, FeedTimerView
      Sleep/         # SleepSheet, SleepTimerView
      Diaper/        # DiaperSheet
    ViewModels/      # ObservableObject state
    Widgets/         # WidgetKit extension
    LiveActivities/  # ActivityKit extension
  ```
- TestFlight build: provisioning profile + entitlements configured, first build pushed to TestFlight

#### SwiftData Models (Day 1, ~3 hrs)
- All four models defined (`Baby`, `FeedEvent`, `SleepEvent`, `DiaperEvent`)
- Seed a default `Baby` named "Miller" on first launch
- CloudKit container shared between both parents via CloudKit Dashboard: enable sharing on the private database record zone
- Verify sync: log an event on one simulator, see it appear on another

#### Main Screen — Quick-Log UI (Day 2–3, ~8 hrs)
One-thumb operable. No nav bar clutter on this screen.

```
┌──────────────────────────────┐
│  Miller  ·  Wednesday        │
│  Feed: 2h 13m ago            │
│  Sleep: 45m ago              │
│  Diaper: 1h ago              │
├──────────────────────────────┤
│                              │
│  ┌──────────┐  ┌──────────┐  │
│  │  Feed    │  │  Sleep   │  │
│  │  🍼      │  │  💤      │  │
│  └──────────┘  └──────────┘  │
│                              │
│       ┌──────────┐           │
│       │  Diaper  │           │
│       │  💩      │           │
│       └──────────┘           │
│                              │
│  ── Today ──────────────     │
│  2:14p  Feed · 3 oz         │
│  1:10p  Sleep · 1h 22m      │
│  11:40a Diaper · Wet        │
└──────────────────────────────┘
```

- Three large tap targets using SwiftUI `Button` with `.buttonStyle(.borderedProminent)` sized to fill half-screen width
- "Time since last X" computed from latest event in each category, updates every minute
- Bottom sheet (`sheet(isPresented:)`) appears on each button tap
- Today's timeline: last 5 events in a `List`, "See All" link to full timeline
- Dark mode from day 1 via `@Environment(\.colorScheme)`

#### Feed Logging Flow (Day 4, ~2 hrs)
Formula-only — a feed is just an amount. Tap Feed → sheet slides up:

```
  [ 2 oz ]  [ 3 oz ]  [ 4 oz ]  [ ___ oz ]
  [          Log Feed          ]
```

- Quick-select oz amounts (2/3/4 oz) + `TextField` for custom. Single tap on a preset can log-and-dismiss immediately (≈2 taps total), or tap custom for a precise amount.
- Saves a `FeedEvent(amountOz:, timestamp: .now)` — no timer, no method.
- On save: cancel any pending feed reminder and schedule the next at +target interval (default 3h, see Phase 2). Haptic confirmation.
- Adjust amount presets in Settings if Miller's typical bottle size changes.

#### Diaper Logging Flow (Day 4, ~1.5 hrs)
Tap Diaper → sheet:

```
  [ Wet ]   [ Dirty ]   [ Both ]
```

Tapping any option immediately saves the event and dismisses the sheet with a haptic confirmation (`.notificationOccurred(.success)`). Two taps total from main screen.

#### Sleep Logging Flow (Day 4, ~2 hrs)
Tap Sleep → timer starts immediately, sheet shows:

```
  Sleeping...
  ● 23 minutes
  [      Wake Up      ]
```

Active sleep replaces the Sleep button on the main screen with a live timer card. "Wake Up" sets `endedAt` and saves.

#### Today's Full Timeline (Day 5, ~4 hrs)
- `List` with all events for today sorted by time descending
- Section headers by hour
- Each row: event type icon, time, duration/details, "T" or "W" initial for who logged
- Swipe-to-delete: soft delete (sets a `deletedAt` field) with confirmation
- Tap row to show edit sheet (notes only in MVP; time editing in Phase 2)

#### CloudKit Sync Verification (Day 6, ~3 hrs)
- Configure CloudKit container in Apple Developer portal
- Both phones share the same zone via CloudKit sharing or by using a single iCloud account owner's private database (simpler for 2 users: one account owns the container, the other is added as a shared user)
- Test: log event on phone A, confirm it appears on phone B within 10 seconds
- Handle sync errors gracefully: `ModelContext` error handling, CloudKit error types
- Offline: SwiftData writes locally; CloudKit syncs when network returns automatically

#### TestFlight Distribution (Day 7, ~2 hrs)
- Archive build in Xcode, upload to App Store Connect
- Add both parents as TestFlight internal testers
- Distribute build, both install via TestFlight link
- Smoke test all three log flows on real hardware

#### Integration + Polish Day (Days 8–10)
- Fix edge cases: single active timer guard (only one sleep timer can be active at once)
- Timer display when app is backgrounded and relaunched
- "No events yet" empty states
- App icon design (simple "M" in a clock or milk bottle motif)
- Pull-to-refresh on timeline (CloudKit sync is automatic but pull-to-refresh is good UX)

### Definition of Done — Phase 1
- [ ] Both parents have the app on their iPhones via TestFlight
- [ ] Feed (oz amount), diaper (W/D/both), sleep (start/stop timer) all log correctly
- [ ] Events sync from phone A to phone B within ~10 seconds
- [ ] Active timers survive app backgrounding and relaunching
- [ ] Today's timeline shows all events in chronological order
- [ ] Dark mode works on all screens
- [ ] Swipe-to-delete works in timeline

### Key Risks — Phase 1

| Risk | Mitigation |
|---|---|
| CloudKit sharing setup complexity | Use a single iCloud account's private database with CloudKit record sharing for the second parent. Simpler than two independent accounts |
| SwiftData + CloudKit sync edge cases | SwiftData + CloudKit is production-quality in iOS 17. Test both online and offline write → sync. Apple's `NSPersistentCloudKitContainer` docs cover conflict resolution |
| TestFlight entitlement mismatch | Provision both devices in Apple Developer portal before archiving |

---

## Phase 2: Live Features

**Goal**: Real-time lock screen timer during active feeds and sleep. Widgets on home and lock screen. Push notifications for "it's been 3 hours since the last feed."

**Effort**: 5–6 days  
**Milestone**: Parents can glance at the lock screen to see how long Miller has been sleeping

### Features

#### Live Activities — Feed & Sleep Timers (Days 1–3, ~10 hrs)
When a feed or sleep timer is running, a Live Activity appears on the lock screen and Dynamic Island.

```
Lock screen:                    Dynamic Island (compact):
┌─────────────────────────┐     [🍼 Feeding · 4:23]
│ 🍼 Miller is feeding    │
│ Started 2:14 PM         │     Dynamic Island (expanded):
│ ● 4 min 23 sec          │     ┌────────────────────────────┐
└─────────────────────────┘     │ 🍼 Miller feeding · 4:23   │
                                │ [       Stop Feed       ]   │
                                └────────────────────────────┘
```

Technical approach:
- Add `WidgetKit` + `ActivityKit` extension targets to Xcode project
- Define `FeedActivityAttributes` conforming to `ActivityAttributes` with `ContentState` holding elapsed time
- Start activity on feed/sleep start: `Activity<FeedActivityAttributes>.request(...)`
- Update activity state every second via `Task` + `Timer.publish`
- End activity on stop: `activity.end(dismissalPolicy: .immediate)`
- Deep link from Dynamic Island tap → app opens to active timer screen

#### WidgetKit Widgets (Days 3–4, ~6 hrs)
Three widget sizes (small, medium, large) for lock screen and home screen:

**Small (lock screen accessory):**
```
🍼 2h 15m
since last feed
```

**Medium (home screen):**
```
🍼 Last feed: 2h 15m ago
💤 Last sleep: 45m ago
💩 Last diaper: 1h 10m ago
```

**Large (home screen):**
```
Miller · Today
🍼 Last feed: 2h 15m ago
💤 Last sleep: 45m ago
💩 Last diaper: 1h 10m ago

Recent:
2:14p  Bottle · 90ml
1:10p  Sleep · 1h 22m
```

Technical approach:
- `WidgetConfiguration` with `TimelineProvider`
- `TimelineEntry` holds last event timestamps for each category
- Timeline reloads every 15 minutes (or on relevant `URLSession` background task)
- Widget reads from an App Group shared `ModelContainer` so it can access SwiftData without launching the main app

#### Push Notifications — Feed Reminders (Day 5, ~4 hrs)
- Request `UNUserNotificationAuthorization` on first launch
- `UNCalendarNotificationTrigger` for feed reminders: if no feed logged in N hours, schedule a local notification ("Miller hasn't eaten in 3 hours")
- Default threshold: 3 hours, configurable in Settings
- Clear pending notifications when a feed is logged
- No server needed — local notifications only for MVP

#### Edit/Delete Past Entries (Day 6, ~3 hrs)
- Tap event in timeline → edit sheet
- Editable fields: start time, end time, notes, method/type
- Edit creates a new record and soft-deletes the old one (append-only pattern)
- Swipe-to-delete on timeline rows (already wired up in Phase 1)
- Changes sync to CloudKit automatically via SwiftData

### Definition of Done — Phase 2
- [ ] Live Activity appears on lock screen and Dynamic Island when the sleep timer is running (feeds are instantaneous — no feed activity)
- [ ] Live Activity dismisses automatically when timer is stopped
- [ ] Lock screen widget shows "Last feed: Xh Xm ago" and updates
- [ ] Home screen widget (medium) shows all three last-event times
- [ ] Local notifications fire when no feed logged in configured threshold
- [ ] Edit and delete work and sync to partner's phone

### Key Risks — Phase 2

| Risk | Mitigation |
|---|---|
| Live Activities API complexity | Apple's documentation + WWDC sessions are thorough. ActivityKit is stable in iOS 16.2+. Budget an extra day for debugging UI layout in Dynamic Island |
| Widget reads from shared SwiftData store | App Group container setup in Xcode entitlements required. Test widget reads before styling |
| Local notifications cleared on app reinstall | Reschedule notifications on `applicationDidBecomeActive` if no feed logged recently |

---

## Phase 3: Insights

**Goal**: Give parents a clear picture of Miller's patterns — daily totals, weekly trends, sleep duration chart, feed frequency heatmap.

**Effort**: 4–5 days  
**Milestone**: "Stats" tab shows today's summary, weekly charts, and growth percentile

### Features

#### Daily Summary (Day 1, ~3 hrs)
A summary card on the main screen (or dedicated Stats tab):

```
Today
🍼  5 feeds · 2h 10m nursing · 1 bottle (90ml)
💤  3h 45m total sleep · longest stretch 1h 30m
💩  4 diapers (3 wet, 1 dirty)
```

Technical approach:
- Computed properties on a `StatsViewModel: ObservableObject`
- Query SwiftData for all events where `startedAt >= startOfToday`
- Group by event type, compute totals
- Update on `onChange(of: modelContext)` or scheduled refresh

#### Weekly Trends — Swift Charts (Days 2–3, ~8 hrs)
Using the built-in Swift Charts framework (no dependencies):

- **Sleep bar chart**: daily total sleep hours, last 7 days
- **Feed frequency heatmap**: 7-day × 24-hour grid, color intensity = feeds per hour
- **Feed type breakdown**: pie chart of breast vs bottle over last 7 days
- **Diaper count**: simple bar chart, wet vs dirty per day

Technical approach:
- `Chart` view with `BarMark`, `PointMark`, `SectorMark`
- Data aggregated from SwiftData fetch with date predicates
- Charts wrapped in `ScrollView` for mobile scrollability
- Touch targets sized appropriately; charts are display-only in MVP

#### Sleep Pattern Visualization (Day 3, ~4 hrs)
Gantt-style sleep blocks:

```
Mon  ████       ██████
Tue  ███    ████████
Wed  █████       ██████
Thu  ██   ████████
Fri  ████     █████
```

- Each block represents a sleep event, x-axis is 24 hours
- Helps parents spot when Miller sleeps longest
- "Longest stretch this week: 4h 12m (Wednesday 2–6am)"

#### Growth Tracking (Days 4–5, ~6 hrs)
- New `GrowthRecord` model (weight, height, head circumference, date)
- "Add measurement" button in Stats tab
- Line charts for each measurement over time using Swift Charts
- WHO growth chart percentile lookup (static data table embedded in app, no network call)
- Display: "Miller is in the 45th percentile for weight at 2 months"

### Definition of Done — Phase 3
- [ ] Daily summary visible on main screen or Stats tab
- [ ] Weekly sleep, feed, and diaper charts render correctly on iPhone
- [ ] Growth log accepts entries and shows line charts
- [ ] Growth percentile displayed for weight and height
- [ ] All charts handle empty state gracefully

### Key Risks — Phase 3

| Risk | Mitigation |
|---|---|
| Swift Charts layout on small screens | Use `chartXAxis` modifier to limit label density; test on iPhone SE |
| WHO growth chart data accuracy | Use CDC/WHO published lookup tables verbatim; cite the source in the app |
| Performance with many events | SwiftData predicates push filtering to SQLite; for date-range queries this is fast |

---

## Phase 4: Smart Features

**Goal**: Reduce cognitive load for exhausted parents. Urgency indicators on main screen, Siri shortcuts for hands-free logging, pediatrician export.

**Effort**: 5–6 days  
**Milestone**: Taylor can say "Hey Siri, Miller just had a wet diaper" while holding Miller

### Features

#### Urgency Indicators on Main Screen (Day 1, ~3 hrs)
Upgrade the "time since last X" indicators with color coding:

| State | Color | Meaning |
|---|---|---|
| 0–2h since feed | Green | All good |
| 2–3h since feed | Amber | Getting hungry |
| 3h+ since feed | Red | Likely hungry |

- `TimeInterval` thresholds configurable in Settings
- Similar green/amber/red for sleep and diapers (customizable thresholds)
- "Next feed likely around X" prediction: average interval from last 7 days, added to last feed time

#### Siri Integration via App Intents (Days 2–4, ~8 hrs)
Using the `AppIntents` framework (iOS 16+):

Define these intents:
- `LogFeedIntent` — "Hey Siri, Miller just ate" → logs bottle or prompts for breast/bottle
- `LogDiaperIntent` — "Hey Siri, log a wet diaper" → logs diaper event immediately
- `StartSleepIntent` — "Hey Siri, Miller is asleep" → starts sleep timer
- `StopSleepIntent` — "Hey Siri, Miller woke up" → stops active sleep timer
- `LastFeedIntent` — "Hey Siri, when did Miller last eat?" → returns time since last feed

Technical approach:
- `struct LogFiaperIntent: AppIntent` with `@Parameter` for diaper type
- `perform()` creates SwiftData event and returns a spoken response string
- Register intents in `AppIntentsPackage`
- Test with Shortcuts app before testing with Siri (faster iteration)
- Add `AppShortcutsProvider` so intents show up in Spotlight without setup

#### Notes on Any Event (Day 4, ~2 hrs)
- `TextField` for notes already in model from Phase 1
- Wire up notes field in all three log sheets
- Notes visible in timeline row (truncated to one line, full text on tap)
- Free text only; no search in MVP

#### Photo Milestones (Day 5, ~4 hrs)
- New `Milestone` model: date, photo (stored as `Data` in CloudKit, max 10MB), caption
- "Add milestone" button in a Milestones tab (gallery view)
- `PhotosPicker` (SwiftUI native, iOS 16+) for photo selection
- Photos stored as binary in CloudKit — CloudKit private database asset support handles the upload automatically
- Thumbnail grid layout in Milestones tab

#### Pediatrician PDF Export (Day 6, ~4 hrs)
- `UIGraphicsPDFRenderer` to generate a 2-week summary PDF
- Content: feeds (total count, breast/bottle breakdown, average interval), sleep (total hours, longest stretch), diapers (count, wet vs dirty), growth if logged
- Share sheet via `ShareLink` — AirDrop, email, or save to Files
- Formatted for print (not a data dump)

### Definition of Done — Phase 4
- [ ] Main screen urgency colors change at configured thresholds
- [ ] "Log a wet diaper" via Siri creates a diaper event and confirms audibly
- [ ] "When did Miller last eat?" via Siri returns the correct time
- [ ] Notes can be added to any event
- [ ] Photo milestones can be added and viewed in gallery
- [ ] PDF export covers last 2 weeks and is legible at print scale

### Key Risks — Phase 4

| Risk | Mitigation |
|---|---|
| Siri intent parameter disambiguation | Use `@Parameter` enums with display representations; Siri will prompt for clarification if input is ambiguous |
| CloudKit photo storage limits | Free tier: 5GB asset storage. For 2 users' baby photos this won't be reached. CloudKit private database asset quota is shared with iCloud Photos |
| PDF layout on different paper sizes | Use points not pixels; A4 and US Letter are both handled by `UIGraphicsPDFRenderer` with appropriate page rect |

---

## Phase 5: Polish & Extras

**Goal**: Apple Watch logging, caregiver sharing, multiple baby profiles, haptic polish throughout. Build after Phase 1–4 are solid.

**Effort**: Variable / ongoing (3–8 days depending on features chosen)

### Features (priority order)

#### 1. Apple Watch App (3–4 days)
- WatchKit extension with simplified UI: three large buttons (Feed, Diaper, Sleep)
- Tap Feed → choose method on watch → timer starts on both watch and iPhone
- Watch complication: "🍼 2h 15m" on active watch face
- Deep integration: stopping a feed timer on the watch stops it on the iPhone and vice versa
- Why: quick logging from the wrist when one hand is occupied with Miller

#### 2. Haptic Feedback Polish (0.5 days)
- `UIImpactFeedbackGenerator.impactOccurred()` on every log tap
- `UINotificationFeedbackGenerator.notificationOccurred(.success)` on event save
- Subtle haptic on active timer tick (optional, configurable)
- Review every interaction for missing haptic confirmation

#### 3. Caregiver Sharing (2–3 days)
- CloudKit record sharing: owner creates a share, grandparent/nanny receives an invitation URL
- Shared users get read-only access to the timeline and stats (cannot log events)
- "View only" role enforced by CloudKit permissions
- Good for grandparents who want to stay informed

#### 4. Multiple Baby Profiles (1–2 days)
- `Baby` model already exists; add baby switcher in Settings
- Profile picker in nav bar: "Miller ▾" → tap to switch
- All events scoped to selected `baby.id`
- Useful for future siblings; future-proofed from day 1 (schema already supports it)

#### 5. Feeding Reminders Based on Pattern (1 day)
- Upgrade Phase 2 local notifications with personalized threshold
- Analyze last 7 days: compute average feed interval per time-of-day bucket (morning/afternoon/evening/night)
- Threshold adapts: "usually eats every 2h in the morning" → reminder fires at 2h, not the hardcoded 3h
- Shown in Settings: "Miller's average interval: 2h 30m (daytime), 3h 15m (nighttime)"

#### 6. Custom App Icon (0.5 days)
- Design a calm, simple icon: milk bottle with a moon, or "M" lettermark in a soft color
- Export at all required sizes via Xcode's asset catalog
- Alternate app icons (light/dark/tinted) for iOS 18+ customization

### Definition of Done — Phase 5 (per feature)
- Apple Watch: log all three event types from the watch, sync to iPhone, complication showing time since last feed
- Haptics: every tap target has appropriate haptic response
- Caregiver sharing: grandparent can install app and view live timeline, cannot log events
- Multiple babies: switching profiles shows correct events and stats for each baby
- Pattern reminders: notification threshold adapts to Miller's observed intervals

---

## Build Timeline

```
Week 1   ████████████  Phase 1: Xcode setup, SwiftData models, all 3 log flows, TestFlight
Week 2   ████████████  Phase 1 cont: Timeline, CloudKit sync, integration, bug fixes
Week 3   ████████████  Phase 2: Live Activities, Widgets, push notifications, edit/delete
Week 4   ████████████  Phase 3: Daily summary, weekly charts, growth tracking
Week 5   ████████████  Phase 4: Urgency indicators, Siri intents, photos, PDF export
Week 6+  ░░░░░░░░░░░░  Phase 5: Apple Watch, caregiver sharing, polish (as desired)
```

**Milestone 1** (End of Week 2): Both phones running TestFlight build. All three log types working. Events sync between phones.  
**Milestone 2** (Mid Week 3): Feed/sleep timer shows live on lock screen. Widgets installed on home screen.  
**Milestone 3** (End of Week 4): Stats tab with weekly charts. Growth log with percentile.  
**Milestone 4** (End of Week 5): Siri logging works hands-free. PDF export ready for pediatrician.

---

## Key Technical Decisions

| Decision | Choice | Revisit If |
|---|---|---|
| SwiftData vs Core Data | SwiftData | iOS 16 support needed (SwiftData is iOS 17+); use Core Data if targeting iOS 16 |
| CloudKit private vs shared | Private database with record sharing | Need non-iCloud login or web access |
| Single CloudKit container owner | Taylor's Apple ID owns, wife is shared user | Wife needs full write access independently — then use shared database zone |
| Local notifications only | Yes (Phase 2–3) | Need cross-device push ("partner just logged something") — then need APNs server key + server-side scheduling |
| Swift Charts | Yes | Need chart types not in Swift Charts (rare) — then DGCharts |

---

## Risks

**CloudKit sharing between two accounts**: Sharing a private database zone with a second iCloud account is well-documented but requires testing on real hardware, not simulators. Simulators share the same iCloud account and will appear to "just work" — test on two physical iPhones before claiming sync works.

**Live Activities simulator gap**: Live Activities cannot be tested in the iOS Simulator. Requires real devices with iOS 16.2+. Budget time for on-device debugging.

**SwiftData + CloudKit conflict resolution**: SwiftData uses last-write-wins by default. If both parents log the same event simultaneously, both events will appear in the timeline — treat this as "both are correct" and let parents delete the duplicate. True conflict resolution adds significant complexity and isn't worth it for 2 users.

**App Store Review**: Not needed for TestFlight internal testing (up to 100 testers, no review required). If ever submitted to the App Store, CloudKit entitlements and usage descriptions for notifications/photos will be reviewed.
