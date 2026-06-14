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
| 4 | **Home & status** | `Features/Home/HomeView.swift`, `Features/Home/LogButtons.swift`, `Features/Home/LoggedToast.swift` | Home shows current status + log tiles; logging shows a confirmation toast. | ☐ | |
| 5 | **Urgency colors** | `DesignSystem/Urgency.swift`, `DesignSystem/DayRibbon.swift`, `Features/Home/TodayRibbonCard.swift` | Green→amber→red countdown to next feed at the configured interval (default 3h). | ☐ | |
| 6 | **Timeline & history** | `Features/Timeline/`, `Features/History/HistoryView.swift`, `Store/TimelineEntry.swift` | Rolling 12–24h timeline (no midnight reset); history of past events; per-parent attribution. | ☐ | |
| 7 | **Edit & backdate** | `Features/Edit/EditEventSheet.swift`, `Features/Shared/TimeControl.swift` | Edit time/amount/type/notes on any event; backdate; delete. | ☐ | |
| 8 | **Stats & charts** | `Features/Stats/StatsView.swift`, `Store/StatsEngine.swift` | Sleep/feed patterns rendered via Swift Charts; numbers match logged data. | ☐ | |
| 9 | **On-device AI insights** | `AI/BabyIntelligence.swift` | Warm plain-English recap (cadence, longest sleep, busiest hour); hides when model unavailable. | ☐ | |
| 10 | **Natural-language quick log** | `Features/Home/NLLogSheet.swift`, `AI/BabyIntelligence.swift` | ✨ sheet parses "4 oz, 20 min ago" / "wet diaper" on-device; nothing leaves the phone. | ☐ | |
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
