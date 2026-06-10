# Increment 1 — Foundation & Core Loop

**Status**: design — June 5, 2026 · **Type**: build-ready blueprint
**Depends on**: [DATA_MODEL.md](../DATA_MODEL.md), [DESIGN.md](../DESIGN.md)
**Maps to**: most of BUILD_PLAN.md "Phase 1" (sharing, glance layer, and notifications are later increments)

---

## Goal & milestone

A tappable Two of Us app, running on device, where one person can log feeds, sleep, and diapers, see them in a rolling timeline with time-since/urgency, and edit/backdate any entry — **all stored locally**. CloudKit is *configured in the model layer but not relied on* this increment. The **CloudKit sharing spike** is part of this increment's plan but **deferred until a second device/Apple ID is available** (see Task, below) — it must complete before Increment 2, and it does not block the local core.

**Done when**: you can install on your iPhone, complete first-run setup, log all three event types (with backdating), edit and delete entries, undo a just-logged event, and watch the home screen update. (The sharing spike is a separate gate before Increment 2.)

### Review decisions (locked 2026-06-05)
1. **Local-first** — Increment 1 stores locally; real sync is Increment 2.
2. **Execution** — Claude scaffolds all Swift source **and** the XcodeGen `project.yml`; Taylor runs `xcodegen generate`, opens, and runs on the Simulator. No hand-built Xcode project. No Apple account/signing for Increment 1 (local-first → Simulator).
3. **Spike timing** — only one device available now, so the spike is deferred (not Task 0); runs before Increment 2.
4. **Identifiers** — `com.taylorseale.twoofus` / `iCloud.com.taylorseale.twoofus` confirmed.
5. **Backdate control** — "Now / Pick" only (default Now; tap opens a full date-time picker).
6. **Age string** — adaptive: days → weeks → months.
7. **Notes** — model keeps the field, but **no notes UI this increment** (deferred).
8. **Oz precision** — half-ounce steps (2, 2.5, 3, …) in custom entry and display.
9. **Timeline** — flat list, newest first (no day separators).
10. **Undo** — brief "Logged · Undo" toast after a log.

---

## In scope

- Xcode project, capabilities, folder structure, identifiers
- SwiftData models (full schema from DATA_MODEL.md) + `ModelContainer` (CloudKit-ready config)
- First-run onboarding (baby name, DOB, my display name/color) + seed `Participant` (owner) and `SharedSettings`
- Home: header, time-since pills with urgency colors, three log targets, rolling timeline
- Feed sheet (oz presets + custom + backdate), Sleep (start/stop timer + active card), Diaper sheet (one tap)
- Edit entry sheet (time/amount/type), soft-delete + replacement, swipe-to-delete
- "Logged · Undo" toast after each log
- Light + dark via semantic color tokens; Dynamic Type; haptics; silent operation
- **CloudKit sharing spike** (throwaway, two real devices) — *planned but deferred until a second device/Apple ID is available; before Increment 2*

## Out of scope (later increments)

- Real sync UX, invite/revoke, multi-participant attribution → Increment 2
- Sleep Live Activity, widgets → Increment 3
- Next-feed reminder, per-user notification prefs, quiet hours, TestFlight hardening → Increment 4
- Charts/stats, growth, Siri, photos, export → deferred phases

> Single-device, single-participant for now: every event is attributed to the owner `Participant`. The `Participant` model and the denormalized `loggedBy*` fields are built now so Increment 2 slots in without a migration.

---

## Prerequisites

- Xcode 16+ on macOS, iOS 17+ deployment target
- Apple Developer account (Taylor's) for the CloudKit container + on-device runs
- A second physical iPhone signed into a *different* Apple ID for the sharing spike (simulators share one iCloud account and will give a false positive)

---

## Project setup

The project is **generated from an XcodeGen spec** (`project.yml`), not hand-built in Xcode's wizard. Claude writes the spec + all source; you run one command and open the result. Toolchain on this Mac is already present: XcodeGen 2.44.1, Xcode 26.4, Swift 6.3.

- **Project**: `TwoOfUs`, SwiftUI lifecycle, SwiftData enabled
- **Bundle ID**: `com.taylorseale.twoofus`
- **Deployment target**: iOS 17.0
- **Capabilities — deferred, added per increment** (kept OFF in Increment 1 so it runs with **no Apple account and no signing, on the Simulator**):
  - iCloud → CloudKit (container `iCloud.com.taylorseale.twoofus`) → **Increment 2**
  - App Group `group.com.taylorseale.twoofus` (widget store sharing) → **Increment 3**
  - Background Modes → Remote notifications → **Increment 2/4**
- **Apple account**: not needed for Increment 1 (Simulator). A free personal team enables on-device runs; a paid Developer Program ($99/yr) is needed at Increment 4 (TestFlight) and for the CloudKit container.

### Bootstrapping runbook (one-time)
1. Claude commits `project.yml`, entitlements/Info.plist, and all Swift source.
2. You run: `xcodegen generate` (in the repo root) → produces `TwoOfUs.xcodeproj`.
3. `open TwoOfUs.xcodeproj`, pick an iPhone Simulator, press Run. No signing needed.
4. (Optional) To run on your own iPhone: select your device, set Signing → your personal Apple ID team. Still no paid account.

> `project.yml` is the source of truth and is committed; `TwoOfUs.xcodeproj` is generated and git-ignored (regenerate with `xcodegen generate`).

### Folder structure
```
TwoOfUs/
  App/
    TwoOfUsApp.swift          # @main, ModelContainer, root routing
    RootView.swift               # onboarding gate → HomeView
  Models/
    Baby.swift
    FeedEvent.swift
    SleepEvent.swift
    DiaperEvent.swift
    Participant.swift
    SharedSettings.swift
    Enums.swift                  # DiaperType, ParticipantRole
  Store/
    ModelContainer+App.swift     # container config (local + CloudKit-ready)
    EventStore.swift             # log/edit/delete helpers, query predicates
    SeedData.swift               # first-run seeding
  Features/
    Home/        HomeView.swift, StatusPill.swift, LogButtons.swift
    Feed/        FeedSheet.swift
    Sleep/       SleepActiveCard.swift, SleepController.swift
    Diaper/      DiaperSheet.swift
    Timeline/    TimelineList.swift, TimelineRow.swift, ParticipantBadge.swift
    Edit/        EditEventSheet.swift
    Onboarding/  OnboardingView.swift
    Settings/    SettingsView.swift            # shell only this increment
  DesignSystem/
    Colors.swift                 # semantic tokens (Asset catalog backed)
    Haptics.swift
    TimeFormatting.swift         # "2h 40m", relative + absolute
  Support/
    LocalPrefs.swift             # UserDefaults wrapper (per-user settings)
Spike/                            # throwaway, not shipped
  CloudKitShareSpike/
```

---

## Task — CloudKit sharing spike (deferred: needs a 2nd device; gate before Increment 2)

The single biggest risk (flagged in DATA_MODEL.md). Build a *throwaway* mini-app, not the real models. Originally planned as Task 0, but only one device is available now — so the **local core is built first** and this spike runs as soon as a second iPhone on a different Apple ID is available. It is a hard gate before Increment 2.

**Validate:** a record written by Apple ID A appears for Apple ID B after B accepts a share, in both directions, on two physical devices.

**Approach:**
1. Minimal SwiftData store with one model (`Memo { text, createdAt }`).
2. Attempt sharing via SwiftData's CloudKit sharing path; share a record/zone and generate a `CKShare` link (`UICloudSharingController`).
3. Accept on device B (different Apple ID). Write on A → confirm on B; write on B → confirm on A.

**Success criteria:** bidirectional sync within ~10s on two Apple IDs.

**Decision gate:**
- ✅ Works → real models use SwiftData + CloudKit sharing as designed.
- ❌ Too limited → fall back to `NSPersistentCloudKitContainer` with explicit share management (still backs SwiftUI). Record the decision in DATA_MODEL.md before Increment 2.

This spike does not block Increment 1 (local UI) at all; its outcome simply must be known before Increment 2 begins.

---

## Data layer

### Models
Implement exactly as specified in [DATA_MODEL.md](../DATA_MODEL.md): `Baby`, `FeedEvent`, `SleepEvent`, `DiaperEvent`, `Participant`, `SharedSettings`, `DiaperType`, `ParticipantRole`. Honor the schema-evolution rules (all new props optional/defaulted; relationships optional). Wrap the schema in a `VersionedSchema` (`SchemaV1`) + `SchemaMigrationPlan` now, so future versions have a seam.

### ModelContainer (`ModelContainer+App.swift`)
- Increment 1: **local store at the default app-support location**, no CloudKit. Keep the store URL behind a single constant so Increment 3 can redirect it to the App Group container (one-time migration) and Increment 2 can flip on CloudKit.
- Expose a `.preview` in-memory container for SwiftUI previews/tests.

### EventStore (`EventStore.swift`)
Thin layer over `ModelContext` so views never hand-roll predicates:
```swift
func log(feed amountOz: Double, at: Date, by: Participant, notes: String?)
func log(diaper: DiaperType, at: Date, by: Participant, notes: String?)
func startSleep(at: Date, by: Participant) -> SleepEvent     // guards single active timer
func stopSleep(_ event: SleepEvent, at: Date)
func edit<E>(_ original: E, mutate: (E) -> Void)             // soft-delete + replacement w/ editOfID
func softDelete<E>(_ event: E)
func undoLast()                                             // soft-delete the most recent log (powers the toast)
func liveEvents(since: Date) -> [any TimelineItem]          // deletedAt == nil, sorted desc
var activeSleep: SleepEvent? { get }                        // endedAt == nil
func lastEvent(of: EventKind) -> Date?
```
- `startSleep` refuses if `activeSleep != nil` (single-timer guard).
- All writes stamp `loggedByID` + denormalized `loggedByName`/`loggedByColorHex` from the owner participant.
- `notes` stays on the models (per schema) but log helpers default it to `nil` — no notes UI this increment.
- `amountOz` accepts half-ounce values; the store does no rounding.

### Seeding (`SeedData.swift`)
On first launch only: create `Baby`, owner `Participant`, and `SharedSettings(targetFeedIntervalMinutes: 180, ozPresets: [2,3,4])`.

---

## Design system (`DesignSystem/`)
- **Colors.swift** — semantic tokens from DESIGN.md, backed by an asset catalog with light + dark variants: `bg, card, card2, separator, text/2/3, accentFeed/Sleep/Diaper, urgencyGreen/Amber/Red`. Views reference tokens only.
- **TimeFormatting.swift** — `since(_ date: Date) -> String` ("2h 40m"), absolute local time formatter, duration formatter ("1h 22m"), and `age(from dob: Date) -> String` (**adaptive: days → weeks → months**, e.g. "5 days old" → "3 weeks old" → "4 months old"). All from stored absolute `Date`, rendered in local TZ.
- **Haptics.swift** — `Haptics.tap()`, `.success()`, `.warning()`. No sounds anywhere.

### Urgency logic
```swift
enum Urgency { case green, amber, red }
func feedUrgency(sinceLastFeed: TimeInterval, target: TimeInterval) -> Urgency
// green < 0.66·target ; amber 0.66–1.0·target ; red > target
```
Sleep/diaper use fixed default thresholds (documented constants). Urgency is reflected in color **and** an accessibility label word ("overdue").

---

## Screens & components (build-ready)

### App entry + routing
- `TwoOfUsApp` installs the container. `RootView` shows `OnboardingView` if no `Baby` exists, else `HomeView`.

### OnboardingView
TextField (name) → DatePicker (DOB) → name + color picker for the owner. On finish: seed data, route to Home.

### HomeView
- Header: `baby.name`, computed age string, settings gear.
- `StatusPill` × up to 3: icon, time-since value with urgency dot, label. When `activeSleep != nil`, swap the sleep pill for `SleepActiveCard`.
- `LogButtons`: Feed + Sleep (half-width), Diaper (full-width). Sleep button → starts timer; while active, region is the running card.
- `TimelineList`: `EventStore.liveEvents(since: now-24h)`, rolling. Empty state per DESIGN.md.
- Tap row → `EditEventSheet`; swipe → confirm soft-delete.

### FeedSheet
- Oz preset chips from `SharedSettings.ozPresets` + custom field; custom supports **half-ounce** values (2, 2.5, 3, …).
- **Backdate control** (`TimeControl`): "Now / Pick" — defaults to Now; "Pick" opens a full date-time picker → `Date`. Reused by Diaper + Edit.
- Log button shows resulting next-bottle time (display only this increment). Saves via `EventStore.log(feed:)`, success haptic, dismiss, then the "Logged · Undo" toast.
- No notes field this increment.

### SleepActiveCard + SleepController
- Tap Sleep → `EventStore.startSleep`. Card shows elapsed = `now − startedAt` via a `TimelineView(.periodic)` (no stored ticking). "Wake up" → `stopSleep`.

### DiaperSheet
- Three buttons; one tap → `EventStore.log(diaper:)` with `TimeControl` (defaults Now), success haptic, dismiss, then the "Logged · Undo" toast.

### TimelineRow + ParticipantBadge
- Row: type icon, detail string, absolute local time, `ParticipantBadge` (colored circle + initial from denormalized fields). VoiceOver label combines all.

### EditEventSheet
- Edit time (`TimeControl`) and amount/type (no notes UI this increment). Save → `EventStore.edit` (replacement + `editOfID`, original soft-deleted). Delete → soft-delete with confirm.

### Toast (`LoggedToast`)
- A transient banner ("Logged · Undo") shown ~3s after any log. Undo → `EventStore.undoLast()`. Auto-dismisses; respects Reduce Motion. Used by Feed, Diaper, and Sleep-start.

### SettingsView (shell)
- Render the *shared* settings (interval, oz presets, baby/DOB) editable, and a placeholder per-user section. Manage People / notifications are stubs this increment. Gate shared settings behind owner role (only role present now).

---

## Acceptance criteria

- [ ] App launches; first run creates Baby + owner Participant + SharedSettings; relaunch skips onboarding.
- [ ] Feed logs with a chosen oz amount and a backdated time; appears in timeline.
- [ ] Diaper logs (W/D/Both) in one tap; appears in timeline.
- [ ] Sleep starts a timer, only one active at a time, elapsed updates live, "Wake up" sets end and logs duration.
- [ ] Timeline shows a rolling ~24h window, newest first, with correct local times and the owner's colored initial.
- [ ] Time-since pills compute correctly and show green/amber/red per thresholds.
- [ ] Header age string reads naturally across days → weeks → months.
- [ ] Custom feed amount accepts and displays half-ounce values (e.g. 2.5 oz).
- [ ] After any log, a "Logged · Undo" toast appears and Undo removes the just-logged event.
- [ ] Any entry can be edited (time, amount/type) and deleted; edits preserve history via soft-delete + `editOfID`.
- [ ] Light and dark both render correctly; layout holds at XXL Dynamic Type; VoiceOver reads rows and urgency.
- [ ] No audio output on any interaction; haptics fire on log/save/delete.

**Gate before Increment 2 (not an Increment 1 criterion):**
- [ ] **Spike**: bidirectional CloudKit sync confirmed on two devices/Apple IDs (or fallback decision recorded in DATA_MODEL.md).

---

## Test plan

**Unit (SwiftData in-memory container):**
- `EventStore`: log/edit/delete each type; `editOfID` linkage; `softDelete` excluded from `liveEvents`.
- `startSleep` single-active-timer guard; `stopSleep` sets `endedAt`.
- `TimeFormatting.since` and urgency thresholds at boundaries (0.65/0.66/1.0/1.1 · target).
- `liveEvents` ordering and 24h window edges (incl. an event crossing midnight).

**Manual (device):**
- First-run onboarding; relaunch persistence.
- Backdate a feed to "yesterday 11pm" → correct placement, no crash on day boundary.
- Background the app mid-sleep, relaunch → elapsed still correct (computed from `startedAt`).
- Toggle system Light/Dark → live recolor.
- Spike: two physical devices / two Apple IDs, bidirectional within ~10s.

---

## Risks & open questions

- **SwiftData sharing limits** — resolved by the spike; gates Increment 2 (now deferred until a 2nd device is available).
- **Sleep crossing into the timeline** — an in-progress sleep shows as the active card, not a timeline row, until stopped. Confirm that reads well on device.

*Resolved in review (2026-06-05): time control (Now/Pick), age string (adaptive), notes (deferred), oz precision (half-ounce), timeline (flat), undo (toast). See "Review decisions" near the top.*
