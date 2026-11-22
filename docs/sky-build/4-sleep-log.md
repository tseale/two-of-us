# The sleep log and where sleeps come from: report for the sky port

> A map of the sleep log and of every way a sleep starts or ends.
> Written on 22 Nov 2026 by a read-only agent, against the branch at about commit `cd2b979` (the app as `origin/main` `3583e43` plus the sky lab). Line numbers are from that day and will drift. It is working context for building the painted hill (`docs/SKY_BUILD_PLAN.md`), not a maintained document.


Read-only pass; I changed nothing and ran nothing (no Swift toolchain here). Body citations are `File.swift:line`; absolute paths are indexed at the end. Deployment target is iOS 26.0 (`project.yml:5`), not the "iOS 17+" in CLAUDE.md.

## Headline findings

- **A sleep is one `SleepEvent` row**: start, optional end, no night/nap flag, no creation time, no device id. Running means no end and not deleted.
- **The app has no single night/nap rule.** It has four, and none matches the mockup's. The wording rule calls an 18:00–19:59 bedtime "napping" for its first two hours.
- **"6 pm, or sunset if earlier" taken literally makes a winter late-afternoon catnap the night's start.** The mockup's own sample day has a 17:40–18:25 catnap; Chicago November sunset is about 16:25. The 4 am cut-off exists only in the BRIEF's words, not in `lab/core.js`.
- **"By hand on Home, this phone" has exactly one call site.** A transient in-memory token there is enough: no model change, no CloudKit change. Record contents cannot tell a Home tap from Siri or a widget on the same phone.
- **Views learn of changes only through SwiftData `@Query` on the main actor.** Synced records arrive as whole-record states, so a start and its stop can arrive as one change, and an edit arrives as a new id.
- **The foreground fetch and the SNOO poll land a few seconds after Home appears.** The quiet "arrive" rise will often play just after opening unless the port treats that window as "simply up".
- **Date of birth carries an arbitrary time of day**, and two existing age functions can differ by one day. "Night N" needs its own calendar-day function with a night day that does not roll at midnight.
- **The sun's place is the daycare's map pin**, else the time zone's meridian at 40°N. No first-light (−7°) function exists.

## 1. The sleep model

`@Model final class SleepEvent` (`SleepEvent.swift:6-26`):

| Field | Meaning |
|---|---|
| `id: UUID` | Also the CloudKit record name |
| `startedAt: Date` | Claimed start. Now for a tap; the bassinet's time for SNOO; user-set after an edit |
| `endedAt: Date?` | Nil while running |
| `deletedAt: Date?` | Soft delete |
| `editOfID: UUID?` | Points to the row this one replaced |
| `sourceRaw: String?` | Nil = "by hand"; `"snoo"`; `"brightwheel"` (`Enums.swift:28-44`) |
| `externalID: String?` | Set only by the Brightwheel import; SNOO passes none (`EventStore.swift:463`, `SnooSyncCoordinator.swift:407-410`) |
| `loggedByID/Name/ColorHex` | The parent (a `Participant`), not the device. For imports, the importing phone's parent |
| `ckSystemFields: Data?` | Local only; nil until the record has round-tripped to the server |
| `notes`, `baby` | — |

- **Running**: `isActive` is `endedAt == nil && deletedAt == nil` (`SleepEvent.swift:57`). One at a time is guarded locally only (`EventStore.swift:469`). Two phones can each open one; a sweep later keeps the earliest start and soft-deletes the rest (`EventStore.swift:842-849`).
- **Edits are append-only.** `editSleep` soft-deletes the original and inserts a new row with a new id, `editOfID` set and `sourceRaw` carried (`EventStore.swift:602-616`). This includes backdating the start of the running sleep (`SleepStartEditSheet.swift:42-47`), so the running sleep's id changes.
- **Deletions are soft**: `softDelete` (`EventStore.swift:680-695`), `cancelSleep` for undo of a start (`:536-539`), `clearAllLogs` (`:711-740`), `QuickLogger.undoLastLog` (`QuickLogger.swift:375-405`). `restore` and `resumeSleep` reverse them on the same row (`EventStore.swift:545-558, 700-707`).
- **Sync conflicts**: a remote stop or soft-delete always wins over a local re-save (`RecordMapping.swift:429-436`).
- **CloudKit fields for SleepEvent** are `babyID, deletedAt, editOfID, endedAt, externalID, loggedBy*, notes, sourceRaw, startedAt` (`docs/cloudkit-schema.ckdb:313-325`). An undeployed field makes saves fail and park (`SyncManager.swift:1206-1219`).
- **Home's view of the log**: `@Query` of live sleeps, newest start first (`HomeView.swift:17-18`); `activeSleep` is the first active one (`:120`). It is the whole history, not a window.

## 2. Every path by which a sleep starts or ends

Nothing is "published". Every path ends in `context.save()` on some `ModelContext`, and views see it through `@Query`. The phone has no Combine publisher or notification for event writes.

| Path | Functions | Written | What a view can tell |
|---|---|---|---|
| **Home Sleep tile** | `LogButtons.swift:88-90`, then `HomeView.startSleep()` (`:2488-2493`), then `EventStore.startSleep()` (`:463-491`) | Main context, `startedAt` = now, `sourceRaw` nil, my participant | The handler gets the event back synchronously. All four layouts share this one handler (`HomeView.swift:410, 1562, 1933`) |
| Undo of that start | Toast Undo calls `cancelSleep` (`HomeView.swift:2492`) | `deletedAt` set | Toast dwells 3 s (6 s under VoiceOver), so it overlaps the 5.8 s moment (`LoggedToast.swift:76-78`) |
| **Home wake slide** | `HomeView.endSleep` (`:2501-2514`) | Under 60 s: soft-deleted. Else `stopSleep` sets `endedAt` (`EventStore.swift:523-531`). Undo calls `resumeSleep` | Same row throughout |
| Edit start of running sleep | `SleepStartEditSheet`, then `editSleep` | New id, old row deleted, one save | Active id and `startedAt` change together |
| Timeline edit or delete | `EditEventSheet.swift:213-214, 229`; swipe on a running sleep (`HomeView.swift:2784-2793`) | As above | — |
| SNOO card accept or edit (a tap on Home) | `SnooSuggestionCard.swift:100-101, 181-196`, then `SnooSyncCoordinator.accept` (`:403-414`) | `startSleep(at: bassinet start, source: .snoo)` or `logCompletedSleep` | `sourceRaw == "snoo"`; start is backdated |
| SNOO auto-log | Home `.task` and `scenePhase` (`HomeView.swift:317-326`), then `sync` (`SnooSyncCoordinator.swift:201-257`). Ends via `autoEndFinishedSnooSleep` (`:358-367`) | Same, with no tap. Start can be up to 14 h old (`SnooReconciler.swift:28`) | Arrives seconds after foreground; poll throttled to 5 min (`:49`) |
| **Siri and Shortcuts** | `StartSleepIntent`, `StopSleepIntent`, `ToggleSleepIntent` (`ToggleSleepIntent.swift:18-133`); phrases at `TwoOfUsShortcuts.swift:40-59` | `QuickLogger.make()` opens a second `ModelContainer` on the same store file, in the app process (`QuickLogger.swift:24-43`); `toggleSleep` (`:415-441`). `startedAt` = now, `sourceRaw` nil, my participant | Record is identical to a Home tap |
| **Widgets and Control Center** | `SetSleepIntent` (`ToggleSleepIntent.swift:140-167`) from `SmallEventWidget.swift:118`, `WidgetActionButton.swift:55`, `LogControls.swift:35-56` | Same `QuickLogger` path | Identical to a Home tap |
| "Undo that" by Siri | `UndoLastLogIntent` (`QueryIntents.swift:96-111`) | Can soft-delete the running or last sleep | — |
| **Live Activity** | None. It has no buttons today (`SleepActivityAttributes.swift:11-12`; only a `widgetURL` at `SleepLiveActivityView.swift:377`) | — | The store drives it via `SleepActivityManager.reconcile` (`:95-119`), never the reverse |
| Apple Watch | `WatchRootView.swift:254-260` writes the watch's own store, then CloudKit | Reaches the phone by sync | My participant id, `ckSystemFields` set |
| **Other parent's phone** | `SyncManager.handleEvent(.fetchedRecordZoneChanges)` (`:1042-1125`), then `RecordMapping.applySleep` (`:621-640`) | Main context, on the main actor, one save per fetched batch | Usually another `loggedByID`; `ckSystemFields` set from first sight |
| Daycare naps | `logCompletedSleep(source: .brightwheel)` (`BrightwheelImporter.swift:347-349, 371-372`) | Always completed, never running | A live daycare nap is not a `SleepEvent` (`HomeView.swift:1885-1887`) |
| Self-heal sweep | `autoPurgeGhostEvents` on foreground (`AppDelegate.swift:71-73`) and after a batch with an open sleep (`SyncManager.swift:1245-1262`) | May soft-delete a second open sleep | Active id can change with no user action |

**Source, from the record alone:** only SNOO and daycare are marked. A Home tap, Siri, a widget, the watch and the other phone all have `sourceRaw == nil`. `loggedByID` separates parents, not devices or surfaces. `ckSystemFields == nil` means "written on this phone, not yet uploaded", which still cannot separate Home from Siri or a widget.

**Time it happened:** there is no "logged at" field. `startedAt` is the claimed start and can be minutes or hours before the record appears. A view knows only when it first saw the row.

**Delay to the other phone:** intent writes queue their ids in App Group defaults and upload only at the next app-active or engine start (`QuickLogger.swift:443-457`, `SyncManager.swift:943-977`). A Siri or widget start can reach the other phone much later.

## 3. How the app tells night from nap today

| Rule | Where | Night means |
|---|---|---|
| Wording, on every surface | `SleepLanguage.isNap` (`SleepLanguage.swift:16-30`) | Start hour 20:00–05:59, fixed. A daytime sleep becomes "sleep" once it has run 2 h. Tested at `SleepLanguageTests.swift:26-38` |
| Household night window | `WakeWindow.isNight` (`WakeWindow.swift:112-119`) with `SharedSettings.nightStartMinute/nightEndMinute`, default 20:00–08:00, adjustable and synced (`SharedSettings.swift:78-79`) | Used by `PredictionEngine.sleepDuration` (by start time, `:336`), `TodayOutlook` "down for the night" (`:117-120`), and wake gaps |
| "Went down for the night" | `PredictionEngine.bedtime` (`PredictionEngine.swift:367-410`) | Earliest sleep start per night between night start − 90 min and night start + 4 h: 18:30–24:00 by default. Prediction only |
| Night-feed stats | `StatsEngine.nightShift` (`StatsEngine.swift:264-272`) | Feeds 19:00–07:00, fixed |

- **"Last night"** is `NightReport.night(containing:startMinute:endMinute:)` (`NightReport.swift:67-78`): the household window containing now, else the most recent one. Called from `HomeView.nightReports` (`:773-796`). It counts any sleep touching the window with no classification (`NightReport.swift:104-112`).
- The drop-off board's "overnight" is yesterday's night start to today's night end (`DropoffBoard.swift:45-63`).
- The spread's leading page picks its "Tonight" and "Last night" pages from the household window too (`HomeView.swift:683-691, 1201-1206`).
- Nights are keyed elsewhere by the local calendar day of the night's start (`ScheduleEngine.swift:145-148`, `NightSchedule.swift:235`).

## 4. Answering (a), (b), (c), (d)

### (b) Night sleep versus nap: the rules disagree

What the mockup has: `nightHours(sun, minutes)` (`lab/core.js:314-318`) is true from 18:00 while the sun is still up, from sunset through the first half of the night, then until the sun reaches −7°. It is a time gate, not a classifier; the lab is told `asleep=night|nap` by URL.

Against the BRIEF's rule (start between 18:00, or sunset if earlier, and 04:00):

| Start | BRIEF rule | Wording rule (card, hero, widgets, Live Activity) | Household window |
|---|---|---|---|
| 18:00–19:59 (the 19:40 bedtime) | Night | "Napping" for 2 h, then "sleeping" | Not night |
| Sunset to 17:59 in winter | Night, if "sunset if earlier" is kept | Nap | Not night |
| 20:00–03:59 | Night | Sleeping | Night |
| 04:00–05:59 | Not night | Sleeping | Night |
| 06:00–07:59 | Not night | Nap | Night |

Consequences:
- Under a sky that has just shown "Night N", the sleep card reads "MILLER IS NAPPING" for two hours after an 18:00–19:59 bedtime (`SleepActiveCard.swift:56-58, 175`).
- The co-parent's notification always says "Started a nap" (`SyncManager.swift:739`).
- A catnap begun after 18:00 (or after winter sunset) begins the night and, if started by hand, takes the full moment. The real bedtime an hour later then gets none.
- A sleep begun before the evening and still running at midnight never begins the night under a start-time rule.

**Decision for you:** either keep the BRIEF rule as signed off, or use the app's own "went down for the night" ground (18:30–24:00 by default, following the household setting). The second has precedent in the code but changes a signed-off number. Either way, the port should have one pure function, for example `isNightSleep(start:evening:)`, and should not reuse `SleepLanguage`.

### (a) "The night has begun"

It can be derived from what exists plus two small pure additions. With `EV(d)` the evening start on day d, `FL(d)` first light on day d:

1. If now < `FL(today)`: the frame is `EV(yesterday)` to `FL(today)`, night day = yesterday.
2. Else if now ≥ `EV(today)`: the frame is `EV(today)` to `FL(tomorrow)`, night day = today.
3. Else it is day: false.
4. `begunAt` = the earliest `startedAt` among live sleeps with `EV ≤ startedAt < min(04:00, FL)` and `startedAt ≤ now`. The night has begun when it exists.

Completed sleeps stay in the log, so a night feed changes nothing.

- **Exists:** the `sleeps` query; `SolarClock.day` for sunset (`SolarClock.swift:19-43`); `NightReport.night(containing:)` as the pattern; the newest-first `prefix(while:)` idiom (`HomeView.swift:781`).
- **Missing:** a first-light time. `SolarClock.day` is fixed at zenith 90.833° (`:35`). The smallest addition is the same formula with a zenith parameter (97° for −7°), with a fallback where the sun never gets that low. `MoonClock` has a sun position series, but it is private (`MoonClock.swift:179-205`).
- **Missing:** the frame and classifier functions above. Nothing needs storing.

Cases the pure function forces, none of them designed yet:
- **Undo of the start** (inside the moment), a sub-minute wake, or deleting the sleep makes the night un-begin, and the view has to come down.
- **Editing the start across the evening boundary** flips night to nap or back.
- **Sleep tracking switched off** (`SharedSettings.swift:72`, `EventStore.swift:464`) means the night never begins.
- **Clock skew:** another phone's `startedAt` can be a few seconds ahead of this phone's clock (`clampPast` runs on the writer only, `EventStore.swift:1609-1611`). Allow a small tolerance.
- **Awake after an early sleep:** down at 18:30, up at 19:00 and awake until 21:00 means Home looks up from 18:30 while he is awake, in summer daylight.

### (c) Started by hand from Home on this phone, just now

- **Smallest addition:** in `HomeView.startSleep()` (`:2488-2493`), after the store returns the event, set a transient value such as `(sleepID, tappedAt)` on view state or on the shared sky driver. It is not persisted and not synced, so there is no SwiftData migration and no CloudKit schema change.
- The sky plays the full moment only if that sleep is a night sleep and the night had not begun without it. Otherwise it is the quiet path.
- This excludes SNOO card accepts (also taps on Home), which go through other functions.
- **"Once a night":** undo then start again, or a sub-minute discard then Undo, would begin the night twice. If the moment must not replay, keep a device-local "played for night yyyymmdd" value in `UserDefaults`, following the `LocalPrefs` pattern (`LocalPrefs.swift:36-37`). This is not camera state.
- **Not recommended:** writing a new `sourceRaw` value such as `"home"`. The field already exists in CloudKit so it needs no schema change, but it breaks the documented "nil means by hand" rule (`Enums.swift:28-31`, `EventStoreTests.swift:275-279`) and still cannot say "this phone".

For the quiet "arrive" rise and the first-light settle, the view needs only its own previous value of the pure function while it is on screen: false then true animates; the first evaluation does not.

### (d) Nights of his life

- **Exists:** `Baby.dateOfBirth` (`Baby.swift:10`), synced. Home has it as `baby?.dateOfBirth` (`HomeView.swift:113`).
- **Missing:** a "Night N" function. Proposed: `born = startOfDay(dateOfBirth)`; `nightDay` from the frame in (a), or today during the day; `N = days(born, nightDay) + 1`. This matches the mockup's "night `ageDays + 1`" (`lab/nights.js:3`) and does not roll at midnight.
- Stars drawn: N − 1 past nights, plus tonight's once the night has begun.
- A future date of birth is a due date (`Baby.swift:53`); the mockup clamps to 1 and the port must choose.
- Month-birthday stars should use calendar months as `AgeMarks` does (`AgeMarks.swift:25-26`), not the lab's 30.44 days.

## 5. How a view learns of changes

- **Mechanism:** `@Query` arrays in `HomeView` (`:12-46`) on the environment's main context. `EventStore` is a `@MainActor struct` that publishes nothing (`EventStore.swift:11-13`). Save and sync enqueue are inline with the tap; only widget and reminder refresh is deferred 50 ms (`:1537-1583`).
- **Sync:** `SyncManager` is `@MainActor` and applies into `modelContainer.mainContext`, the same context the UI reads (`SyncManager.swift:22-23, 90`; `TwoOfUsApp.swift:161`). One fetched batch is applied, relinked and saved in one synchronous turn (`:1060-1109`). Sweeps follow and may save again.
- **Demo mode:** the UI runs on an in-memory container and sees no synced changes (`TwoOfUsApp.swift:172-176`).
- **Intents:** `perform()` is `@MainActor` but writes through a second container. No code bridges that to the UI context. The comments assume `@Query` picks it up (`HomeView.swift:428-429`), and I could not verify it. A Siri or widget start while Home is visible may show late.
- **Clocks:** cards tick in `TimelineView(.periodic(by: 1))` (`HomeView.swift:386`); the sky in `TimelineView(.everyMinute)` with `max(ctx.date, .now)` (`SkyBackground.swift:93-94`). `ctx.date` can be up to 59 s stale when a query change re-runs the closure (`HomeView.swift:540-543`).
- **The sky does not see the sleep log today.** `SkyBackground` takes only `location`. Pass it small values (for example `nightBegunAt`, the running sleep's start, N) from `HomeView`.
- **Two skies on the open Duo** each have their own timeline (`HomeView.swift:462, 610`); they need one shared driver.

What can make a moment fire twice or late:
- **Edit of the running sleep**: new id. On the other phone the delete and the insert are two records with no ordering guarantee (`SyncManager.swift:1092-1093`), so it can briefly see zero or two running sleeps. Key on the derived fact, never on "a new active id appeared".
- **Collapsed history**: a late fetch can deliver a sleep already ended. The view never sees it running.
- **Concurrent starts on both phones**: each plays its own moment; then one row is soft-deleted by the sweep.
- **Undo paths**: see (c).
- **Arrival just after opening**: the foreground fetch (`AppDelegate.swift:88-92`) and the SNOO poll both land after Home is drawn. Silent pushes are throttled (`AppDelegate.swift:74-76`).
- **Cold launch**: Home may be under the launch curtain (`RootView.swift:26-30, 163`).
- **Tree rebuild**: entering or leaving demo mode rebuilds every view (`TwoOfUsApp.swift:166`), which resets view-local state.

## 6. Date of birth, location, time zones

- **Date of birth:** entered with a date-only picker, but the stored `Date` keeps whatever time of day it had and is never normalised (`OnboardingView.swift:50`, `OnboardingSetupSteps.swift:48-52`, `BabyEditSheet.swift:51-55, 103`). Edits sync (`EventStore.swift:870-877`).
- **Age functions:**
  - `TimeFormatting.age(from:now:)` uses calendar days between starts of day; it is the header text (`TimeFormatting.swift:80-83`, `HomeView.swift:1696-1697`).
  - `WakeWindow.ageInDays` uses whole 24 h periods from the raw instant, so it can differ by one (`WakeWindow.swift:224-227`).
  - `AgeMarks.next` returns only the next month or round-day mark within 31 days (`AgeMarks.swift:18-42`).
- **Location for the sun:** `SharedSettings.daycareCoordinate`, the daycare's pin (`HomeView.swift:462, 1821-1823`; `SharedSettings.swift:290-298`). Fallback is 40°N on the time zone's standard meridian (`SolarClock.swift:47-52`), and a fixed 06:45–18:15 day where the sun does not rise or set (`SkyBackground.swift:818-822`). The device's own location is used only for the daycare geofence.
- **Time zones:** dates are absolute; every rule uses `Calendar.current` at evaluation time, with the calendar injectable for tests. The household night window is wall-clock minutes (`SharedSettings.swift:73-79`). `SolarClock.day` returns absolute dates for the local calendar day.

## 7. Surprising or fragile

- The sun is computed for the daycare's coordinates while 18:00 and 04:00 follow the device's clock. When travelling, the two part company. A sleep's night/nap class by local hour also changes if the phone changes time zone.
- `startOfDay(dateOfBirth)` can land on a different calendar day in another time zone, shifting N by one. The header age has the same weakness.
- The leading page and the sky will disagree at the edges. At 07:00 with a co-parent the page still shows "Tonight" (window open until 08:00) while the sky has come down at first light. At a 19:00 bedtime the sky is up while the page still shows the evening book.
- `PlanSlot` with kind `.sleep` is a parent's planned sleep, not the baby's (`NightSchedule.swift:126-130`; `SleepWindowTests`, `SleepLaneLayoutTests`). Do not read it as baby sleep.
- `HomeView` reads `settingsList.first` in several places (`:118, 131, 776`) and the canonical row in others (`:1821-1823`). They can differ if duplicate settings rows exist.
- Possible existing race, unverified: if the other phone moves a running sleep's start later, and the replacement arrives before the original's deletion, the sweep would delete the replacement (it keeps the earliest start). Both records are normally sent together.
- SNOO-sourced sleeps have no wake slide and end on a later poll with a backdated end (`SleepActiveCard.swift:241-243`, `SnooSyncCoordinator.swift:358-367`).

## Not read, or not verified

- **Not verified at runtime:** anything; in particular whether `@Query` reflects writes from the intents' second container.
- **Read in part only:** `SyncManager` outside lines 1–240, 636–1400; `RecordMapping` outside sleep, common fields and conflicts; `NightSchedule` outside `State`; `PredictionEngine` outside sleep duration and bedtime; `StatsEngine`; `TodayHeroCard`; the widget views; `SleepLiveActivityView` (searched for buttons only); the watch app beyond its toggle and sync header; Brightwheel beyond nap import.
- **Not read:** `DayRhythm`, `DayHighlights`, `ScheduleEngine` beyond `dayKey`, the SNOO API client, DTOs, login, token store and settings.
- **Tests:** `NightReportTests` in full; `EventStoreTests` 240–400 and 536–560; `SleepLanguageTests` 10–45; test names only for `SleepWindowTests`, `SleepLaneLayoutTests`, `SnooReconcilerTests`, `QuickLoggerTests`, `AgeMarksTests`.
- **Docs and mockup:** `docs/DATA_MODEL.md` entity and derived-value sections; `lab/core.js` 255–530; `hill-painted.md` events (724–775) and port notes 11–15; BRIEF "Round three" onward. Not `hill-painted.js`, `presence.js`, `air.js` or `tree.js`.
- The main checkout already had uncommitted changes in `design/sky-lab` before my run.

## File index

App root ``:
- `TwoOfUs/Models/`: `SleepEvent.swift`, `Enums.swift`, `Baby.swift`, `SharedSettings.swift`
- `TwoOfUs/Store/`: `EventStore.swift`, `SleepLanguage.swift`, `WakeWindow.swift`, `NightReport.swift`, `NightSchedule.swift`, `PredictionEngine.swift`, `TodayOutlook.swift`, `StatsEngine.swift`, `ScheduleEngine.swift`, `AgeMarks.swift`, `SolarClock.swift`, `MoonClock.swift`, `QuickLogger+AppReads.swift`
- `TwoOfUs/Intents/`: `QuickLogger.swift`, `ToggleSleepIntent.swift`, `QueryIntents.swift`, `TwoOfUsShortcuts.swift`
- `TwoOfUs/LiveActivities/`: `SleepActivityManager.swift`, `SleepActivityAttributes.swift`
- `TwoOfUs/SNOO/`: `SnooSyncCoordinator.swift`, `SnooReconciler.swift`, `SnooSuggestionCard.swift`
- `TwoOfUs/Sync/`: `SyncManager.swift`, `RecordMapping.swift`, `SyncConstants.swift`
- `TwoOfUs/Features/Home/`: `HomeView.swift`, `LogButtons.swift`, `LoggedToast.swift`
- `TwoOfUs/Features/Sleep/`: `SleepActiveCard.swift`, `SleepStartEditSheet.swift`
- `TwoOfUs/Features/Edit/EditEventSheet.swift`, `TwoOfUs/Features/Onboarding/OnboardingView.swift`, `OnboardingSetupSteps.swift`, `TwoOfUs/Features/Settings/BabyEditSheet.swift`
- `TwoOfUs/App/`: `AppDelegate.swift`, `TwoOfUsApp.swift`, `RootView.swift`
- `TwoOfUs/DesignSystem/`: `SkyBackground.swift`, `TimeFormatting.swift`
- `TwoOfUs/Daycare/DropoffBoard.swift`, `TwoOfUs/Brightwheel/BrightwheelImporter.swift`, `TwoOfUs/Support/LocalPrefs.swift`
- `TwoOfUsWidgets/`: `SmallEventWidget.swift`, `WidgetActionButton.swift`, `LogControls.swift`, `SleepLiveActivityView.swift`
- `TwoOfUsWatch/WatchRootView.swift`, `TwoOfUsWatch/WatchSyncManager.swift`
- `TwoOfUsTests/`: `EventStoreTests.swift`, `SleepLanguageTests.swift`, `NightReportTests.swift`
- `docs/DATA_MODEL.md`, `docs/cloudkit-schema.ckdb`, `project.yml`, `design/sky-lab/BRIEF.md`

Mockup root `design/sky-lab/`: `lab/core.js`, `lab/nights.js`, `lab/chrome.js`, `skies/hill-painted.md`
