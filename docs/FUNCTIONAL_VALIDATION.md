# Functional Validation Checklist

A walkthrough of every functional area of **Two of Us**, used to validate
behavior and track enhancements. Work through one area at a time: confirm the
expected behavior holds on device/simulator, set **Status**, and capture any
**Notes / enhancements** to follow up on.

**Status legend:** ☐ Not yet validated · ✅ Validated · ⚠️ Issue found · 🔧 Enhancement queued

| # | Area | Key code | Expected behavior | Status | Notes / enhancements |
|---|------|----------|-------------------|--------|----------------------|
| 1 | **Feed logging** | `Features/Feed/FeedSheet.swift`, `Models/FeedEvent.swift`, `Store/EventStore.swift` | Log a bottle in oz from presets or a custom amount; saved with timestamp + parent attribution. | ✅ | Code review: `logFeed` clamps oz to 0–32 (`EventBounds`) + timestamp to the past, stamps logger identity, then save→sync→reload widgets→re-arm feed reminder→donate intent. Custom field tolerates pasted "5 oz". Undo via `softDelete`. |
| 2 | **Sleep logging** | `Features/Sleep/SleepActiveCard.swift`, `Models/SleepEvent.swift` | Start/stop the single running sleep timer; live elapsed time; only one sleep open at a time. | ✅ | Code review: single-timer guard (`guard activeSleep == nil`) in `startSleep`; elapsed computed from `startedAt` so it survives backgrounding; start/stop drives the Live Activity. |
| 3 | **Diaper logging** | `Features/Diaper/DiaperSheet.swift`, `Models/DiaperEvent.swift` | Wet / dirty / both in one tap; saved with timestamp + attribution. | ✅ | Code review: select-then-confirm guards against a stray mislog; `logDiaper` stamps identity + clamps timestamp. Undo via `softDelete`. |
| 4 | **Home & status** | `Features/Home/HomeView.swift`, `Features/Home/LogButtons.swift`, `Features/Home/LoggedToast.swift` | Home shows current status + log tiles; logging shows a confirmation toast. | ✅ | Code review: live 1s `TimelineView`; active-sleep card animates in place keyed on sleep state (CloudKit/Siri starts animate too); widget deep-links consumed on warm + cold launch; toast auto-dismisses (3s) with tinted Undo. Minor: NL `sleepEnd` toast has no undo (`{}`) — acceptable. |
| 5 | **Urgency colors** | `DesignSystem/Urgency.swift`, `DesignSystem/DayRibbon.swift`, `Features/Home/TodayRibbonCard.swift` | Green→amber→red countdown to next feed at the configured interval (default 3h). | ✅ | Code review: ratio model green<0.66 / amber≤1.0 / red>1.0; safe fallbacks (green when target≤0 or no date); never color-only — `accessibilityWord` + `sinceTextColor` carry the signal. Feed target from `SharedSettings`; sleep/diaper from `UrgencyDefaults`. |
| 6 | **Timeline & history** | `Features/Timeline/`, `Features/History/HistoryView.swift`, `Store/TimelineEntry.swift` | Rolling 12–24h timeline (no midnight reset); history of past events; per-parent attribution. | ✅ | Code review: Home timeline filters live events to a rolling −24h window, sorts newest-first; `TimelineEntry` unifies the 3 types with `sortDate`/`detail`/attribution. History tab = 7-day swimlane + sleep-consolidation + daily-volume charts with empty states. |
| 7 | **Edit & backdate** | `Features/Edit/EditEventSheet.swift`, `Features/Shared/TimeControl.swift` | Edit time/amount/type/notes on any event; backdate; delete. | ✅ | Code review: append-only edit (soft-delete original + insert replacement preserving identity/notes/`editOfID`); sleep edit enforces ≥60s duration & end≥start; `TimeControl` caps at `...Date()` (no future). 🔧 Fixed: diaper edit now uses the diaper accent tint for the "Now" button (was feed-teal). Notes editing still not surfaced in UI (documented as out of scope this increment). |
| 8 | **Stats & charts** | `Features/Stats/StatsView.swift`, `Store/StatsEngine.swift` | Sleep/feed patterns rendered via Swift Charts; numbers match logged data. | ✅ | Code review: `StatsEngine` is pure aggregation, consistently filters `deletedAt == nil`, credits a sleep stretch to its start day, and splits cross-midnight sleep by day-overlap. Stats tab (records/lifetime/night-shift/cadence) + History charts all have empty states. |
| 9 | **On-device AI insights** | `AI/BabyIntelligence.swift`, `Features/Stats/StatsView.swift` | Warm plain-English recap (cadence, longest sleep, busiest hour); hides when model unavailable. | ✅ | Code review: card gated on `isAvailable`; generation debounced (0.8s) + cancellable; digest built from `StatsEngine`. 🔧 Fixed: insight now regenerates on sleep/diaper changes too (was keyed on `feeds.count` only, leaving sleep-stretch text stale after a new sleep). |
| 10 | **Natural-language quick log** | `Features/Home/NLLogSheet.swift`, `AI/BabyIntelligence.swift` | ✨ sheet parses "4 oz, 20 min ago" / "wet diaper" on-device; nothing leaves the phone. | ✅ | Code review: `@Generable ParsedLog` + on-device `parseLog`; `outOfRangeMessage` blocks hallucinated oz/time and keeps the sheet open with a friendly message; entry point hidden when model unavailable. Writes go through the same toast+undo store paths as taps. |
| 11 | **CloudKit sync** | `Sync/SyncManager.swift`, `Sync/RecordMapping.swift`, `Sync/SyncConstants.swift` | Both phones see updates within ~10s; record round-trips are lossless. | ☐ | |
| 12 | **Sharing & join flow** | `Sync/CloudShareView.swift`, `Sync/JoinFlowView.swift`, `Sync/ShareAcceptance.swift`, `Sync/CloudAccount.swift` | Second parent can be invited and accept; iCloud account state handled gracefully. | ☐ | |
| 13 | **Siri / App Intents** | `Intents/LogFeedIntent.swift`, `Intents/LogDiaperIntent.swift`, `Intents/ToggleSleepIntent.swift`, `Intents/QueryIntents.swift`, `Intents/TwoOfUsShortcuts.swift` | Voice log feed/diaper, toggle sleep, and query state; Shortcuts donations work. | ☐ | |
| 14 | **Control Center / Action Button** | `TwoOfUsWidgets/LogControls.swift` | Log Feed, Log Diaper, and stateful Sleep toggle from Control Center / Lock Screen / Action Button. | ☐ | |
| 15 | **Widgets** | `TwoOfUsWidgets/` (Small/Medium/Large/Ribbon), `TwoOfUsWidgets/WidgetActionButton.swift`, `App/DeepLinkRouter.swift` | Time-since-last feed/sleep/diaper at a glance; action buttons deep-link into the app. | ☐ | |
| 16 | **Sleep Live Activity** | `LiveActivities/`, `TwoOfUsWidgets/SleepLiveActivityView.swift` | Running sleep timer on Lock Screen + Dynamic Island; starts/stops with the sleep timer. | ☐ | |
| 17 | **Feed reminders (AlarmKit)** | `Alarms/FeedAlarmManager.swift`, `Support/LocalPrefs.swift` | Opt-in "next feed due" alarm pierces Silent/Focus; re-armed on each feed and on foreground. | ☐ | |
| 18 | **Onboarding** | `Features/Onboarding/` | First-run flow: pages, setup steps, celebration; completes once and persists. | ☐ | |
| 19 | **Setup checklist** | `Features/Setup/`, `Support/SetupProgress.swift` | Setup quests / Spotlight checklist track and advance correctly. | ☐ | |
| 20 | **Settings & profiles** | `Features/Settings/SettingsView.swift`, `BabyEditSheet.swift`, `ProfileEditSheet.swift`, `ParticipantColorPicker.swift`, `Models/Baby.swift`, `Models/Participant.swift` | Edit baby profile, parent profiles + colors; settings persist and sync where shared. | ☐ | |
| 21 | **Manage data & export** | `Features/Settings/ManageDataView.swift`, `Support/LogExporter.swift` | Export/clear data behaves correctly; export contents are accurate. | ☐ | |
| 22 | **Settings scope** | `Models/SharedSettings.swift`, `Support/LocalPrefs.swift` | Shared settings sync across parents; local prefs stay device-local. | ☐ | |
| 23 | **Design system & appearance** | `DesignSystem/Colors.swift`, `Typography.swift`, `Haptics.swift`, `TimeFormatting.swift` | Liquid Glass cards/tiles; dark + light follow system; haptics + time formatting consistent. | ☐ | |
| 24 | **Accessibility** | `docs/ACCESSIBILITY_CHECKLIST.md` (cross-cutting) | Dynamic Type, VoiceOver labels, color-plus-label urgency, one-handed, silent operation. | ☐ | |
| 25 | **App lifecycle & routing** | `App/TwoOfUsApp.swift`, `App/RootView.swift`, `App/DeepLinkRouter.swift`, `App/AppDelegate.swift` | App launches to the right state; deep links from widgets/intents route correctly. | ☐ | |
| 26 | **Data foundation** | `Store/Schema.swift`, `Store/ModelContainer+App.swift`, `Store/SeedData.swift`, `Store/DemoData.swift`, `docs/DATA_MODEL.md` | SwiftData schema/migrations load cleanly; seed/demo data sane. | ☐ | |

## Cross-cutting / infrastructure (optional scope)

| Area | Reference | Notes |
|------|-----------|-------|
| CI/CD (Xcode Cloud) | `docs/XCODE_CLOUD.md`, `ci_scripts/` | Push to `main` → archive → TestFlight. |
| TestFlight feedback automation | `docs/TESTFLIGHT_AUTOMATION.md`, `.github/` | Hourly poll files feedback/crashes as issues. |
| App Store release prep | `docs/APP_STORE_RELEASE_RUNBOOK.md`, `docs/RELEASE_POLISH_PLAN.md` | Privacy manifest, nutrition label, screenshots, second archive workflow. |
| Test suite | `TwoOfUsTests/` | `make test` — record mapping, sync queues, store semantics, stats, deep links. |
