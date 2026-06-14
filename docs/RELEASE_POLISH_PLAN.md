# Two of Us — Functional Areas & Release Polish Plan

**Purpose.** A map of every functional area of the app, written so each one can be
worked in its **own Claude Code session** — a self-contained brief (scope, key files,
current state) plus a prioritized checklist of bugs, polish, and enhancements to tighten
before a first release.

**How to use this doc.**
1. Pick an area below. Open a fresh session and paste its section heading + "work through
   the checklist for this area in `docs/RELEASE_POLISH_PLAN.md`."
2. Each session: read the listed files, confirm the findings still hold, fix the
   🔴/🟠 items, then re-check the boxes and commit.
3. The findings here came from a code audit (June 14, 2026); treat line numbers as
   "approximately here," not gospel — verify before editing.

**Priority key:**
🔴 Blocker / correctness (data loss, broken flow, submission gate) ·
🟠 Should-fix before release (UX gap, fragile edge case) ·
🟡 Polish / nice-to-have ·
💡 Enhancement (optional, post-v1 candidate)

> **⚠️ Scope note — read first.** `CLAUDE.md` and several docs still say *"TestFlight only,
> no App Store submission."* The goal has changed to a **real App Store release.** That
> unlocks a set of submission-only requirements (privacy manifest, nutrition label,
> screenshots, age rating, a second CI workflow) that TestFlight never enforced — see
> **§16**. Update `CLAUDE.md`/`README.md`/`docs/BUILD_PLAN.md` to reflect the App Store
> goal as part of this effort.

---

## Progress — automated release-polish pass (2026-06-14)

A pass landed every checklist item that could be fixed **from the codebase
alone** (no device, no App Store Connect, no macOS-only tooling), grouped into
commits by area on one PR. Marker meanings below:

- `- [x]` — done in this pass (or verified already-correct; noted inline).
- `- [ ]` — still open. Each remaining item is tagged with **why**:
  - **(manual)** — needs a device, two iCloud accounts, App Store Connect, the
    Developer portal, or macOS-only tooling. Tracked in the new runbooks
    (`APP_STORE_RELEASE_RUNBOOK.md`, `TESTFLIGHT_MANUAL_CHECKLIST.md`,
    `DEVICE_TEST_MATRIX.md`, `ACCESSIBILITY_CHECKLIST.md`).
  - **(deferred)** — a lower-priority 🟡/💡 polish/refactor left for a later pass.

> Note on line numbers: several findings cited code that had already been fixed
> (e.g. the rhythm-quest OR, the DOB future cap) or had moved; those are checked
> with an inline "already satisfied" note. New shared infra this pass added:
> `Support/AppLog.swift` (os.Logger channels + a user-facing `StoreErrorCenter`).

## Area index

| # | Area | Code health | Release risk |
|---|------|-------------|--------------|
| 1 | App shell, routing & launch | ✅ Solid | 🟠 |
| 2 | Onboarding (owner first-run) | ✅ Solid | 🟡 |
| 3 | Co-parent join flow | ✅ Solid | 🟠 |
| 4 | Setup checklist / quests / spotlights | ✅ Solid | 🟡 |
| 5 | Home & quick-logging (Feed / Diaper / Sleep) | ✅ Strong | 🟠 |
| 6 | Edit & backdate events | ✅ Good | 🟠 |
| 7 | ~~Natural-language quick-log (Foundation Models)~~ | ➖ Removed (superseded by Siri) | — |
| 8 | Timeline & history & stats | ✅ Good | 🟡 |
| 9 | Data model & local store (SwiftData) | ✅ Strong | 🔴 |
| 10 | CloudKit sync engine | ✅ Strong arch | 🔴 |
| 11 | Sharing lifecycle (invite / revoke / leave) | ✅ Good | 🟠 |
| 12 | Widgets & Control Center controls | ✅ Complete | 🟡 |
| 13 | Live Activity (sleep) | ✅ Complete | 🟡 |
| 14 | Siri / App Intents & deep links | ✅ Complete | 🟠 |
| 15 | Feed reminders (AlarmKit) & notifications | ⚠️ Fragile | 🟠 |
| 16 | Settings, data management & export | ✅ Good | 🟠 |
| 17 | Design system & accessibility | ✅ Strong | 🟠 |
| 18 | Build, CI/CD, tests & App Store submission | ⚠️ TestFlight-only | 🔴 |

---

## 1. App shell, routing & launch

**Scope.** Top-level routing between co-parent join → owner onboarding → main tabs;
demo-mode store swaps; CloudKit share-acceptance (cold + warm launch); celebration
overlay; deep-link entry.

**Key files:** `App/TwoOfUsApp.swift`, `App/RootView.swift`, `App/AppDelegate.swift`,
`App/DeepLinkRouter.swift`.

**Current state.** Well-architected; smooth crossfades, isolated demo container, both
scene- and app-delegate share-acceptance paths.

**Checklist**
- [x] 🔴 `RootView.swift:29–35` — `joinSyncing` route can wait **forever** if the owner's
      baby never syncs (owner offline / deleted baby). Add a ~30s timeout + escape hatch
      ("taking longer than expected… try later / contact").
- [x] 🟠 `RootView.swift:73–80` — Share-acceptance failure alert is generic. Distinguish
      *offline* vs *already-used link* vs *access revoked* and suggest the right next step.
- [x] 🟠 `AppDelegate.swift:48–49` — Silent-push fetch in `applicationDidBecomeActive`
      can race the UI querying the store mid-sync; consider awaiting/retry.
- [x] 🟡 `RootView.swift:113–124` — Demo banner uses `.thinMaterial`; verify dark-mode
      contrast and give the exit button a clear label ("Exit demo mode").
- [x] 🟡 `TwoOfUsApp.swift:80–86` — `-autoFinish` dev flag hardcodes names; gate behind
      `#if DEBUG` and confirm it can't ship enabled.

---

## 2. Onboarding (owner first-run)

**Scope.** Four-page first-run: welcome tour → baby setup → owner profile → invite.
Local-until-commit; per-page gating; share created at invite step; celebration finale.

**Key files:** `Features/Onboarding/*` (`OnboardingView`, `OnboardingPages`,
`OnboardingSetupSteps`, `CelebrationView`, `OnboardingComponents`, `OnboardingAmbient`,
`OnboardingMockups`).

**Current state.** Complete, polished, accessible (Reduce-Motion aware, ViewThatFits for
Dynamic Type, ambient re-tint).

**Checklist**
- [x] 🟠 `OnboardingSetupSteps.swift:38–42` — Baby DOB `DatePicker` allows **future dates**.
      Cap with `in: ...Date()`.
- [ ] 🟡 `OnboardingSetupSteps.swift:31` — Baby-name field has no max length; long names
      can break layout. Add `lineLimit`/truncation on display.
- [ ] 🟡 `OnboardingPages.swift:137–138` — "Invited by your partner? Open the link…"
      escape hatch is buried at the bottom; raise its prominence.
- [x] 🟡 `OnboardingPages.swift:182–197` — Page dots are `accessibilityHidden`; announce
      "page X of 4" to VoiceOver instead.
- [x] 🟡 `OnboardingSetupSteps.swift:142` — Interval stepper readability ("1h" vs
      "1 hour"); fix pluralization.
- [ ] 💡 `OnboardingSetupSteps.swift:165–227` — `RhythmStep`/`RemindersStep` reused in
      quests via a clunky `barClearance` param; move to an `@Environment` value.

---

## 3. Co-parent join flow

**Scope.** Invited parent's path: hello (live sync status) → profile (name/color/photo).
Finish gates on owner's profile syncing; first joiner = full, later = guest.

**Key files:** `Sync/JoinFlowView.swift`, `Sync/ShareAcceptance.swift`.

**Current state.** Clever live-updating copy as records land; correct role gating.

**Checklist**
- [x] 🟠 `JoinFlowView.swift:195–200` — Finish button disabled until `owner != nil` with
      **no timeout**; if owner is offline it hangs on a spinner. Add ~30s → help message.
- [x] 🟠 `ShareAcceptance.swift:74–96` — Inspect the `CKError` code and show specific copy
      for `.notAuthenticated` (access revoked) vs transient network errors; add Retry.
- [ ] 🟡 `JoinFlowView.swift:175–178` — Color suggestion re-runs on every
      `participants.count` change (thrashes while many sync); debounce or stop once the
      user manually picks.
- [ ] 🟡 `JoinFlowView.swift:147–156` — Swiping hello↔profile loses the "connecting"
      shimmer while the Finish button stays disabled; reconcile the state.
- [ ] 🟡 Photo picker shows no avatar preview (suggested color monogram) until save.
- [ ] 💡 `JoinFlowView.swift:228` — Re-joiner is re-promoted to co-parent (count-based,
      not identity-based). Acceptable for v1; document the choice or track first-joiner ID.

---

## 4. Setup checklist / quests / spotlights

**Scope.** Deferred post-onboarding setup (rhythm tuning, reminders opt-in) surfaced as a
Home card + Settings rows + just-in-time spotlights. Rhythm is shared; reminders per-device.

**Key files:** `Features/Setup/*` (`SetupChecklistCard`, `QuestSheets`, `SpotlightSheet`),
`Support/SetupProgress.swift`.

**Current state.** Smart completion detection; one-prompt-per-session; quests auto-retire.

**Checklist**
- [x] 🟠 `SetupProgress.swift:96` — Rhythm quest only completes when **both** interval
      **and** presets differ from defaults `(180, [2,3,4])`. Should be **OR** (changing
      either counts).
- [x] 🟠 `SetupProgress.swift:116–118` — Spotlight marks "shown" on **appear**, so a user
      who swipes it away before reading never sees it again. Mark shown on **dismiss**.
- [ ] 🟡 `SetupChecklistCard.swift:84–91` — "All set" card auto-dismisses after 2s; fade
      gently or keep until the user leaves the screen.
- [x] 🟡 `SpotlightSheet.swift:102–111` — "Tune rhythm" button still shows when the rhythm
      quest is already complete; hide/disable it.
- [ ] 🟡 `QuestSheets.swift:101–102` — Reminders quest "not now" is a silent no-op; add a
      light confirmation toast.

---

## 5. Home & quick-logging (Feed / Diaper / Sleep)

**Scope.** Primary screen: header, Today ribbon + daily metrics, three log tiles with
"time since," active-sleep card morph, 24h timeline.

**Key files:** `Features/Home/*` (`HomeView`, `LogButtons`, `TodayRibbonCard`,
`LoggedToast`), `Features/Feed/FeedSheet.swift`, `Features/Diaper/DiaperSheet.swift`,
`Features/Sleep/SleepActiveCard.swift`, `Features/Shared/*`.

**Current state.** The strongest part of the app — periodic time updates without jank,
spring morphs, haptics, toasts+undo, Reduce-Motion + dark mode throughout.

**Checklist**
- [x] 🟠 `DiaperSheet.swift` — Diaper type buttons have **no selected state** and the sheet
      has no confirm label; rapid taps feel accidental. Add a selected highlight (parity
      with Feed preset chips) and/or a "Log Wet" button label.
- [x] 🟡 `LoggedToast.swift:30` — Undo button is always teal (feed accent) even for diaper
      (amber) and sleep (periwinkle) logs. Pass the event accent through.
- [x] 🟡 `TodayRibbonCard.swift:59–65` — Sleep duration renders "2h45" (no space);
      align to `TimeFormatting.duration()` → "2h 45m".
- [x] 🟡 `FeedSheet.swift:36–47` — Custom oz `TextField` should trim whitespace before
      parsing and block autofill (`.textContentType(.none)`); paste of "5 oz" is rejected
      but silently.
- [ ] 🟡 `FeedSheet.swift` / `DiaperSheet.swift` — Sheet snaps shut on log; a brief
      "Logged ✓" before dismiss would feel less abrupt.
- [ ] 💡 `SleepActiveCard.swift` — No indicator that the sleep is synced / Live-Activity
      running; consider a subtle "shared" affordance.
- [x] 💡 `Features/Shared/TimeControl.swift:25` — "Now" reset button is always teal;
      pass a tint so it matches the hosting sheet's accent.

---

## 6. Edit & backdate events

**Scope.** Unified editor (Feed oz / Diaper type / Sleep start+end) reached from a
timeline row; append-only (soft-delete original, insert replacement linked by `editOfID`).

**Key files:** `Features/Edit/EditEventSheet.swift`, `Store/EventStore.swift` (edit paths).

**Current state.** Correct append-only history; sleep end constrained ≥ start.

**Checklist**
- [x] 🟠 `EditEventSheet.swift:48` — Feed stepper hardcodes `0.5...12`; a 0.25 oz value
      (older data / Siri or widget input) gets clamped on edit. Widen or derive from settings.
- [x] 🟠 `EditEventSheet.swift:63–64` — Editor allows `endedAt == startedAt` (0-duration
      sleep) with no guard. Validate a minimum duration or warn.
- [x] 🟡 `EditEventSheet.swift:78` — Generic "Save" label; make it contextual ("Save feed").
- [ ] 💡 `EditEventSheet.swift:5` — Notes UI intentionally deferred; models already carry
      `notes`. Decide if v1 ships notes editing.

---

## 7. Natural-language quick-log — REMOVED (2026-06-14)

The on-device ✨ NL quick-log sheet was **removed**: hands-free logging is fully covered by
Siri / App Intents (§13 / runbook below), so the feature was redundant. Deleted
`Features/Home/NLLogSheet.swift`, the Home top-left ✨ button + `HomeView.applyParsed`, and the
`parseLog` / `ParsedLog` / `outOfRangeMessage` / `Bounds` members of `BabyIntelligence`. The
on-device **Insights summary** (`BabyIntelligence.summary`, Stats tab) is retained — see §8.

---

## 8. Timeline, history & stats

**Scope.** Home vertical timeline (rail nodes, sleep capsules scaled by duration,
participant badges); History (7-day swimlane + sleep/feed charts); Stats (AI insights,
record hero, lifetime tiles, night-shift chart, cadence patterns).

**Key files:** `Features/Timeline/*`, `Features/History/HistoryView.swift`,
`Features/Stats/StatsView.swift`, `Store/StatsEngine.swift`.

**Current state.** Complete and tasteful; soft chart styling; good empty states.

**Checklist**
- [x] 🟠 `StatsView.swift:72–76` — `loadSummary` triggers on `feeds.count`; a widget batch
      of N feeds regenerates the AI summary N times. Debounce.
- [x] 🟠 `DayTimelineView.swift:62–73` — Sleep capsule height maxes at 30pt around ~2h40,
      so a 4h sleep looks identical to a 2.5h one. Widen range or use log scaling.
- [ ] 🟡 `StatsView.swift:277–280` / `HistoryView.swift:142–149` — Hour/weekday axis
      formatting is hardcoded (12h assumption, fixed stride); use locale-aware
      `.dateTime` and scale stride to width (for a future 30-day option).
- [ ] 🟡 Single-data-point charts (1 day / 1 sleep) render lopsided against a full
      7-day axis; add a "more data coming" treatment.
- [ ] 🟡 `StatsView.swift:141–172` — Lifetime 2×2 grid + `minimumScaleFactor(0.7)`:
      verify legibility on iPhone SE and in dark mode.
- [ ] 💡 `HistoryView.swift:38–59` — 7-day window is hardcoded; add a 7/30-day picker.

---

## 9. Data model & local store (SwiftData)

**Scope.** `@Model` types (Baby, Feed/Sleep/Diaper, Participant, SharedSettings);
append-only soft-delete + replacement; denormalized logger identity; App Group store
shared with widget; StatsEngine aggregations; seed/demo data.

**Key files:** `Models/*`, `Store/*` (`EventStore`, `Schema`, `ModelContainer+App`,
`SeedData`, `DemoData`, `TimelineEntry`, `StatsEngine`), `docs/DATA_MODEL.md`.

**Current state.** Schema is locked and well-designed; soft-delete/terminal-field strategy
is sound. The main risk is **silent failure** in the write path.

**Checklist**
- [x] 🔴 `EventStore.swift:346` — `save()` catches and `print`s on failure. A user logs a
      feed, sees optimistic UI, the save throws, app dies → **feed lost, no signal.**
      Surface a failure banner / propagate the error.
- [x] 🟠 `EventStore.swift:58,75,92` — `logFeed/logDiaper/startSleep` don't validate
      inputs (negative/huge oz, future/ancient timestamps, `baby == nil`). Add guards.
- [ ] 🟠 `StatsEngine.swift:69–100` — Every fetch is `try? … ?? []`, so a fetch failure
      reads as "0 oz today" rather than an error. Return a result type or render an error
      state.
- [x] 🟡 `EventStore.swift:305–306` — `lastEventDate(of:)` returns an active sleep's
      `startedAt` (hours old); document or return `endedAt ?? .now`.
- [x] 🟡 `Baby.swift:28–30` — `.cascade` delete rule vs never-hard-deleting invariant is
      implicit; add an assertion/comment in the wipe path so a refactor can't silently
      orphan CloudKit records.
- [x] 🟡 `RecordMapping.swift` (UUID parse sites) — bad UUID strings drop relationships
      silently; log the offending string.

---

## 10. CloudKit sync engine

**Scope.** Hand-rolled dual `CKSyncEngine` (private + shared), zone-wide `CKShare`,
change-tag persistence, conflict resolution (local wins except terminal `deletedAt`/
`endedAt`), hold queues, bootstrap, zone-recovery.

**Key files:** `Sync/SyncManager.swift`, `Sync/RecordMapping.swift`, `Sync/SyncConstants.swift`,
`Sync/CloudAccount.swift`, `docs/CLOUDKIT_SETUP.md`, `docs/cloudkit-schema.ckdb`.

**Current state.** Thoughtful architecture with real conflict handling; recently
overhauled. Gaps are around **surfacing failure to the user** and a few edge cases.

**Checklist**
- [x] 🔴 Errors are Console-only across the sync layer (`SyncManager.swift:219,452,512,
      517,522`; `ShareAcceptance.swift:94`). A participant can sit on "Bringing everything
      over…" forever. Route errors to the UI (extend the existing `ShareAcceptance.failed`
      pattern) with retry.
- [x] 🔴 Widget/extension write queue (`SyncManager.swift:354–361`) only drains when the
      app launches. Feeds logged via the widget while offline, with the app never opened,
      never sync. Document the constraint and/or nudge the user to open the app.
- [x] 🟠 `RecordMapping.swift:210–217` — Orphaned events (event syncs before its Baby) are
      only relinked on `fetchedRecordZoneChanges`; an interrupted fetch can leave
      `baby == nil` forever. Relink whenever a Baby is fetched/inserted too.
- [ ] 🟠 `SyncManager.swift:832–841` — `captureCloudUserID` is fire-and-forget; if it
      fails, `removeParticipant` falls back to "sole non-owner," which can remove the
      **wrong** person with 2+ caregivers. Add retry or make it blocking with a spinner.
- [x] 🟠 `RecordMapping.swift` asset writes (`:298–302`, `:70`) — temp files for
      Baby/Participant photos leak if a save fails before upload. Add a cleanup queue.
- [ ] 🟡 `SyncManager.swift:546–559` — Private-zone-deletion recovery re-uploads
      everything but logs nothing if the re-upload fails (catastrophic-but-rare). Log it.
- [ ] 🟡 `SyncManager.swift:849–892` — Document the `leaveShare()` partial-rollback
      recovery ("tap Leave again if it throws").

---

## 11. Sharing lifecycle (invite / revoke / leave)

**Scope.** Owner creates zone-wide share + invites; participant accepts (replace-or-merge);
manage People (change role, revoke); leave share; household switch.

**Key files:** `Sync/CloudShareView.swift`, `Sync/ShareAcceptance.swift`,
`Sync/JoinFlowView.swift`, sharing rows in `Features/Settings/SettingsView.swift`.

**Current state.** Mechanically complete with good safeguards (replace confirmation, role
gating). Gaps are in error messaging and a couple of multi-account edge cases.

**Checklist**
- [x] 🟠 `CloudShareView.swift:48–52` — If the system share sheet fails to save participant
      edits, the error is only logged and the sheet is gone — no retry. Surface + retry.
- [x] 🟠 `SettingsView.swift:223–224` — People list can show a left/orphaned participant
      with no name/role (sync lag). Filter inactive or show a "left the log" state.
- [ ] 🟡 `ShareAcceptance.swift:27–41` — Replace-vs-merge logic reads like a fragile
      boolean short-circuit; refactor to an explicit `LinkAction` enum.
- [ ] 🟡 `SyncManager.swift:663–672` — Share invite card can show a stale title if the
      baby is named after the share is created; refresh share metadata on baby-name change.
- [ ] 🟡 Document the invariant: a device syncs to **one** zone owner at a time; switching
      requires `deleteEverything()` first (guards the "two owners in one store" edge).

---

## 12. Widgets & Control Center controls

**Scope.** 8 widget surfaces (small Feed/Sleep/Diaper + accessories, medium ribbon, large
timeline, "when" ribbon + next-feed gauge); Control Center / Lock Screen / Action Button
log controls + stateful sleep toggle. Reads SwiftData via App Group; no SwiftData objects
cross the boundary (`WidgetEntry` snapshot).

**Key files:** `TwoOfUsWidgets/*`.

**Current state.** Complete and well-isolated. Cosmetic edges only.

**Checklist**
- [x] 🟡 `WidgetProvider.swift:64–69` — Store/container access failures are swallowed by
      `try?` → silent `.empty`. Add debug logging for missing App Group / corrupt store.
- [ ] 🟡 `SmallEventWidget.swift:130–131` — Active-sleep state is a snapshot; the widget
      can show "Sleeping" for minutes after a wake from Siri/Control Center until the
      timeline reloads. Ensure a reload fires on sleep end (mostly handled).
- [ ] 🟡 `WidgetActionButton.swift:22` — `minimumScaleFactor(0.7)` may collide emoji+text
      on narrow lock-screen widths; test across device sizes, consider dropping emoji on
      the lock-screen variant.
- [ ] 🟠 **Device-only:** widgets can't be unit-tested. Validate on hardware that home/lock
      widgets render, update, and deep-link (see §18 manual checklist).

---

## 13. Live Activity (sleep)

**Scope.** Lock Screen + Dynamic Island running sleep timer; self-updating `.timer` text;
foreground reconciliation (`endAll()` then restart) for crash recovery.

**Key files:** `LiveActivities/SleepActivityManager.swift`,
`LiveActivities/SleepActivityAttributes.swift`,
`TwoOfUsWidgets/SleepLiveActivityView.swift`.

**Current state.** Complete; reconciliation handles the common crash case.

**Checklist**
- [x] 🟡 `SleepActivityManager.swift:50–59` — `endAll()` fires async `Task`s without
      awaiting; a slow end could flicker against a new start. Collect/await them.
- [x] 🟡 `SleepActivityManager.swift:18–27` — `.request()` failure is logged only; the
      user starts sleep and no activity appears with no feedback. Consider a retry on next
      sync tick.
- [x] 🟡 `SleepActivityManager.swift:16` — `staleDate: nil` keeps the Island bright all
      night; set ~1h so long sleeps dim (cosmetic).
- [ ] 🟠 **Device-only:** ActivityKit can't run in the simulator — validate start/lock/
      Dynamic Island/wake/dismiss on hardware (iPhone + iPad).

---

## 14. Siri / App Intents & deep links

**Scope.** Log intents (feed/diaper/sleep toggle), 5 read-only query intents, 8 registered
App Shortcuts, confirmation snippets; widget/Siri write path (`QuickLogger`); `twoofus://`
deep-link routing into log sheets.

**Key files:** `Intents/*`, `App/DeepLinkRouter.swift`, `docs/SIRI_AND_SHORTCUTS.md`.

**Current state.** Complete and well-guarded (every intent handles `QuickLogger.make()`
failure). `QuickLogger.logFeed` clamps ounces at the write boundary.

**Checklist**
- [x] 🟠 `LogFeedIntent.swift:22` — `amountOz` accepts 0 / negative / absurd values from
      Shortcuts with no bounds check. Guard `oz ∈ (0, 32]`.
- [x] 🟡 `DeepLinkRouter.swift:28` — Unrecognized host/kind fails silently; log a warning.
- [ ] 🟡 `DeepLinkRouter.swift:13` — Two fast widget taps overwrite `pendingLog` (second is
      lost); queue or de-dupe. Low real-world risk.
- [ ] 🟡 `QuickLogger.swift:45–56` — Owner-ID fallback to "first participant" can stamp the
      wrong parent if the stored ID is stale; log when the fallback fires.
- [ ] 🟡 App Shortcuts are at 8/10; note the ceiling before adding more.

---

## 15. Feed reminders (AlarmKit) & notifications

**Scope.** Device-local, opt-in AlarmKit "next feed due" countdown that pierces Silent/
Focus; re-armed after every feed and on foreground; stable per-device alarm ID.

**Key files:** `Alarms/FeedAlarmManager.swift`, `Support/LocalPrefs.swift`,
`EventStore` reschedule calls.

**Current state.** Works on the happy path but **fails silently** in several spots — the
weakest production area.

**Checklist**
- [x] 🟠 `FeedAlarmManager.swift:59` — `try?` discards scheduling errors; a failed
      reschedule leaves the parent with no reminder and no signal. Log + consider a
      `UNUserNotificationCenter` fallback.
- [x] 🟠 `FeedAlarmManager.swift:25–26` — If the user denies AlarmKit auth, every future
      feed silently no-ops. Detect denial once and prompt to enable in Settings.
- [x] 🟠 `FeedAlarmManager.swift:41` — No guard on `interval > 0`; a 0/garbage
      `targetFeedIntervalMinutes` silently no-ops. Validate a sane minimum.
- [ ] 🟡 No "reminder armed" affordance anywhere; the user can't tell a reminder is set.
      Add a small badge on the Feed tile / Today card.
- [ ] 🟡 Revoking a share doesn't cancel a device's pending alarm (low severity).

---

## 16. Settings, data management & export

**Scope.** Settings shell (baby header, identity, feeding rhythm [shared, full-role],
appearance, sharing, reminders, manage data, demo, about); Baby/Profile edit sheets;
ManageData (CSV export, clear logs, multi-step delete-everything); role pills + pickers.

**Key files:** `Features/Settings/*`, `Support/LogExporter.swift`,
`Support/ImageDownscale.swift`, `Support/AppInfo.swift`.

**Current state.** Production-ready RBAC and a serious delete gauntlet. A few empty-input
and recovery gaps.

**Checklist**
- [x] 🟠 `ManageDataView.swift:87–175` — Delete-everything is a 3-step flow with **no
      recovery if step 2 fails/times out** — the user is stranded. Add back/retry.
- [x] 🟠 `BabyEditSheet.swift:70–75` / `ProfileEditSheet.swift:70–75` — Clearing the name
      field **silently reverts/dismisses** instead of blocking. Disable Save on empty or
      show an error.
- [x] 🟡 `ManageDataView.swift:69` — Export shows a bare `ProgressView` then pops a
      `ShareLink`; add "Preparing…" copy for the transition.
- [x] 🟡 `LogExporter.swift:48–52` — Temp CSV files accumulate in `temporaryDirectory`
      across exports; clean up old ones or reuse a stable name.
- [x] 🟡 `LogExporter.swift:32–33` — Sleep "detail" shows a raw ISO `endedAt`; format as a
      readable time / duration.
- [ ] 🟡 `SettingsView.swift:51–57` — Feed-interval stepper is granular (15-min) and verbose
      ("every 3h 0m"); add common presets (2h/3h/4h).
- [ ] 🟡 `SettingsView.swift:267–272` — People section lacks a heading/count for VoiceOver.
- [x] 💡 `LogExporter.swift` — CSV doesn't carry participant identity/color; add a column.

---

## 17. Design system & accessibility

**Scope.** Semantic color tokens (light/dark), Liquid Glass vs surface materials,
typography (`MetricStack`), urgency model, DayRibbon canvas viz, CradleMark, haptics,
time formatting. The shared contract lives in `DESIGN.md`.

**Key files:** `DesignSystem/*`, `DESIGN.md`, `docs/DESIGN.md`.

**Current state.** Cohesive and semantic. Accessibility is good but **never audited
end-to-end** — a release gate (see §18).

**Checklist**
- [ ] 🟠 **Accessibility audit pass** (its own session): VoiceOver across every screen,
      Dynamic Type to XXL with no clipping, urgency conveyed by dot+words not hue alone,
      haptic-only confirmation (no sound). Capture Accessibility Inspector output.
- [x] 🟡 `CradleMark.swift` — Decorative `.screen`-blend mark isn't
      `accessibilityHidden(true)`; hide it from VoiceOver.
- [ ] 🟡 Verify urgency amber/red and role-pill `opacity(0.16)` fills hold AA contrast in
      **dark** mode specifically (`Colors.swift:48–50`, `SettingsView.swift:313–321`).
- [ ] 🟡 `CradleMark.swift:46–62` — Hardcoded radial-gradient stops break at extreme sizes;
      scale with size.
- [ ] 💡 `TimeFormatting.duration()` — Offer a no-seconds variant; `AppFont.display/hero`
      lack named scales (magic numbers at call sites).

---

## 18. Build, CI/CD, tests & App Store submission

**Scope.** XcodeGen project generation + git hooks; Xcode Cloud → TestFlight; TestFlight
feedback→issues automation; unit tests; entitlements/Info.plist; icon/launch; **the
TestFlight→App Store gap.**

**Key files:** `project.yml`, `Makefile`, `ci_scripts/ci_post_clone.sh`, `.githooks/*`,
`.github/workflows/testflight-feedback.yml`, `scripts/testflight_feedback_to_issues.py`,
`TwoOfUsTests/*`, `TwoOfUs/Info.plist`, `TwoOfUs/TwoOfUs.entitlements`,
`TwoOfUs/Assets.xcassets/AppIcon.appiconset`, `TwoOfUs/TwoOfUs.icon`,
`docs/XCODE_CLOUD.md`, `docs/TESTFLIGHT_AUTOMATION.md`, `docs/PRIVACY.md`.

**Current state.** Build/CI/tests for **TestFlight** are solid (XcodeGen, hooks, auto
build-numbering, 9 test files covering store/sync/stats/NL/export/deeplink/urgency/config).
App-Store-specific requirements are **not yet in place**, and the device/manual test
surface (widgets, Live Activities, sharing, push) is untested.

**Submission blockers & gates**
- [x] 🔴 **Privacy manifest** — add `TwoOfUs/PrivacyInfo.xcprivacy` (`NSPrivacyTracking
      = false`, no tracking domains, declare any required-reason APIs). Required by App
      Store, not by TestFlight.
- [ ] 🔴 **Privacy nutrition label** — complete in App Store Connect (map from
      `docs/PRIVACY.md`: user-provided baby/event data, no tracking, no third-party share).
- [ ] 🔴 **App Store CI workflow** — add a **second** Xcode Cloud workflow that archives
      for App Store distribution; **do not modify** the existing TestFlight workflow.
- [ ] 🔴 **Device + manual QA** — widgets, Live Activities, CloudKit sharing across two
      real iCloud accounts, offline→reconnect sync, push. None are simulator-testable.
- [ ] 🟠 **Accessibility audit** (see §17) — Apple may request; do it regardless.
- [ ] 🟠 **App Store listing** — screenshots (light+dark, iPhone+iPad), description,
      keywords, age rating, category, support URL.
- [ ] 🟠 Verify the **iCloud container capability** is enabled on the bundle ID in the
      developer portal and the ASC app record matches; confirm archived `aps-environment`
      flips to `production`.
- [ ] 🟠 Decide & document the **iOS 26-only** deployment target (vs backporting) —
      `project.yml:5`. Bump `MARKETING_VERSION` (`project.yml:13`) for 1.0.

**Polish / infra**
- [ ] 🟡 Finish the **Liquid Glass app icon** in Icon Composer (macOS) — `TwoOfUs.icon` is
      a headless scaffold; PNG fallback is an acceptable v1 backstop
      (`docs/ICON_AND_SPLASH_MAC_STEPS.md`).
- [x] 🟡 Add a `CHANGELOG.md` and wire release notes; automate `MARKETING_VERSION`.
- [ ] 🟡 Extend tests: Participant/SharedSettings round-trips; deep-link malformed URLs;
      NL bounds validation; consider SwiftUI snapshot tests.
- [x] 🟡 New runbooks under `docs/`: `APP_STORE_RELEASE_RUNBOOK.md`,
      `TESTFLIGHT_MANUAL_CHECKLIST.md`, `DEVICE_TEST_MATRIX.md`, `ACCESSIBILITY_CHECKLIST.md`.
- [x] 🟡 Update `CLAUDE.md`/`README.md` so the "TestFlight only" language reflects the
      App Store goal.

---

## Suggested session ordering

A sensible path to a clean 1.0:

1. **§9 + §10 + §15** (data integrity & reliability) — fix the 🔴 silent-failure paths
   first; everything else rides on writes/sync being trustworthy.
2. **§5 + §6 + §14** (logging surfaces & validation) — the daily-use core.
3. **§1 + §3 + §11** (routing & sharing edges) — the timeout/escape-hatch gaps.
4. **§2 + §4 + §8 + §16** (onboarding, setup, stats, settings polish).
5. **§12 + §13** (glanceable layer — pair with on-device QA).
6. **§17** (accessibility audit) — one focused pass.
7. **§18** (submission mechanics) — privacy manifest, CI workflow, listing, device QA.

> Total rough effort to App-Store-ready: the audit estimate is **~6–10 focused days**,
> dominated by device/manual QA and the submission paperwork, not new code.
