# Changelog

All notable changes to Two of Us are recorded here. The format loosely follows
[Keep a Changelog](https://keepachangelog.com/); versions track
`MARKETING_VERSION` in `project.yml`.

## [Unreleased]

### Added — Apple Watch companion app
- New **TwoOfUsWatch** target: a minimal watchOS app installed with the
  iPhone app. One screen, three rows — Feed (one tap logs the default
  amount), Diaper (wet/dirty/both dialog), Sleep (start/wake toggle) — each
  showing time since the last event, plus a **Last Feed complication**
  (circular/corner/rectangular/inline) that ticks by itself.
- The watch syncs with CloudKit directly (`WatchSyncManager`, a trimmed
  sibling of the phone's `SyncManager` on its own `CKSyncEngine`), so it
  works with the phone out of reach. It discovers whether this iCloud
  account owns the family zone or joined it as a share participant, applies
  fetches through the same `RecordMapping` dialect, and attributes watch
  logs to the right parent by matching the account's `cloudUserID`. The
  watch never creates zones or shares and never bulk-uploads — it is a
  cache device; the phones own the household lifecycle.
- Writes reuse `QuickLogger` (the widget/Siri write path) unchanged; its
  per-key outbound queue is drained into the watch's engine in-process.
- Freshness model: every app activation fetches; there is no background
  push on the watch, so remote changes land when the app is opened (the
  complication re-reads the local store after every fetch/log).

### Changed — sleep Live Activity shows the next feed instead of a Wake button
- The lock-screen sleep card's trailing column is now a self-ticking
  **next-feed countdown** — "NEXT FEED / 1:47:23 / at 2:30 AM", or the
  assigned parent's turn ("GT IS UP") in their color while the nighttime
  schedule is speaking. The old Wake up ☀️ button was redundant: tapping the
  activity already opens the app, where the active-sleep card keeps its Wake
  button (widget and Siri wake paths are unchanged).
- The prediction is the earlier of tonight's next scheduled slot and the
  canonical last-feed + interval maths the feed alarm uses, and it refreshes
  whenever a feed is logged, edited, or deleted mid-sleep on this phone —
  or arrives from the co-parent via sync/foreground reconcile.
- The expanded Dynamic Island adds a quiet "next feed 2:30 AM · GT" caption
  under the sleeping line; compact and minimal Island are unchanged.

### Changed — sleep is no longer attributed to a person in the UI
- Sleep rows on the Home timeline (and the legacy timeline row) no longer
  show the logger's avatar, and VoiceOver no longer reads "logged by …"
  for them — sleep is the baby's doing, not a caregiver task.
- The sleep edit sheet no longer offers the "Logged by" reassignment picker.
- A fulfilled sleep slot on the Nighttime schedule reads "Done ✓" instead of
  "Covered by ⟨name⟩ ✓".
- The Stats "Teamwork" split (and Wrapped's caregiver credit) now counts
  feeds and diapers only; its caption says so.
- UI-only: events still record `loggedBy` internally (sync, ghost-event
  detection, and the CSV export are unchanged).

### Fixed — ghost "?" events, duplicates, and 0 oz feeds
- Timeline rows with a grey "?" avatar, batches of identical events stamped
  the same minute, and impossible "Feed · 0 oz" entries are eliminated at
  every source:
  - **Creation requires attribution.** Every write path (app, widget, Siri,
    Control Center, notification action buttons) refuses to log when the
    local participant can't be resolved — the old fallback stamped a random
    logger UUID with an empty name, which rendered as "?" and synced to both
    phones. Widget/Siri now answer "Couldn't log — open Two of Us and try
    again" instead of persisting an unattributed event.
  - **0 oz feeds are rejected** at creation everywhere (a bottle of nothing is
    never a real feed).
  - **Inbound sync can no longer mint placeholders.** Applying a fetched
    CloudKit record used to swallow store errors and blind-insert a
    placeholder row (0 oz / wet / "now" / random logger — exactly the ghost
    shape), duplicating events under one id. Upserts now propagate store
    errors (the engine re-fetches the batch, same recovery as a failed save),
    and a record missing its required fields is skipped, never materialized.
  - **Self-healing sweep.** On every app foreground (and after any sync batch
    that carries a ghost-shaped record), ghost events — empty logger name AND
    a logger no participant matches — are soft-deleted and synced so both
    phones and the CloudKit zone clean up; duplicate rows sharing one id are
    collapsed locally to the attributed copy.
  - If a nameless event ever slips through again, the timeline shows a neutral
    person silhouette instead of an alarming "?".

### Changed — the schedule is fully manual now
- Predicted rows are gone from the Schedule tab (and Home's up-next line).
  The schedule shows exactly the slots you defined — parent-authored, nothing
  derived from the log — and every row is editable.
- New per-night **Move tonight…** in the slot sheet: slide tonight's slot to a
  different time without touching the standing plan. Times near midnight snap
  to the sensible night (11:30pm "moved to 12:15" means 45 minutes later).
  Moves combine with swaps (assigning after moving keeps the moved time),
  sync like any override, and reminders/alarms follow the moved time.

### Fixed
- "Resend link" now verifies the person is actually a member of the iCloud
  share before offering the URL. A non-member tapping the bare link hits
  Apple's "Item Unavailable" dead end — the flow now explains they need
  re-adding and opens the sharing sheet instead.

### Added
- Resend an invite link to someone who already has access (lost link, new
  phone): swipe their row in Settings → People → **Resend link**. Shares the
  standing zone-wide invite URL through the plain share sheet — never creates
  a new person or touches the participant list.

### Fixed
- ITMS-90473 upload warning (build 76): the notification-content extension's
  Info.plist hardcoded version 1.0/1 instead of wiring `$(MARKETING_VERSION)` /
  `$(CURRENT_PROJECT_VERSION)` like the app and widget targets — every version
  bump would trip the mismatch warning. Now wired; future bumps carry through.
- The unremovable "?" person in Settings → People. A ghost participant record
  (leaked by the same pre-SyncGate dev runs as the ghost logs) was never a
  member of the iCloud share, so Remove threw "Couldn't match this person" and
  stranded the row. Removal now purges record-only participants — synced, so
  the row disappears on both phones — and only touches the CKShare when the
  member's identity is certain. This also defuses the old fallback that could
  have removed the *real* co-parent from the share when removing a ghost, and
  stops `nil == nil` from ever matching a pending invitee.

### Fixed — ghost logs from dev/test runs syncing into the family zone
- Sync is now refused outright in simulator builds and in any launch carrying
  a store-mutating fixture argument (`-seedSampleData`, `-wipeStore`, …).
  Previously a UI-test or App Store screenshot run seeded a week of fake
  "Mom"/"Dad" feeds/sleeps/diapers into the real store, and the sync layer's
  one-shot bootstrap uploaded all of it to the family's CloudKit zone — both
  parents then pulled them as ghost logs nobody had tapped for (`SyncGate`).
- Manage data gains a one-tap **Remove unknown entries** cleanup: soft-deletes
  every event whose logger was never a household participant (the signature
  of leaked sample data), synced to both parents like any normal deletion.
  The section only appears when such entries exist.

### Fixed — reminder routing & phantom sleeps
- The loud interval feed alarm now stays dark on the off-duty parent's phone
  when the schedule pins that feed to their co-parent. Previously only the
  gentle nudge consulted the schedule; the AlarmKit "feed due" alarm checked
  only this device's own armed slot alarm, so a parent with the classic feed
  reminder enabled was still woken during the other parent's assigned slot.
  Fail-safe unchanged: unassigned slots, skipped nights, unknown identity, or
  no schedule all keep the alarm armed for everyone.
- Phantom sleep sessions from stale widget taps. The widget Sleep/Wake buttons
  (quick-log row and the small sleep tile) ran a blind toggle rendered from a
  timeline snapshot — tapping "Wake" after the co-parent had already stopped
  the sleep started a brand-new session. They now drive sleep to the state
  the button showed (same idempotent intent as the Control Center toggle and
  Live Activity Wake button), so a stale tap is a no-op, never a phantom log.
- "Hey Siri, start sleep" no longer *stops* a running sleep: the start/stop
  phrases now map to separate idempotent intents instead of sharing the toggle.

### Release-polish pass (toward the first App Store release)

#### Reliability — silent failures now surface
- Failed SwiftData saves raise a transient banner instead of being swallowed by
  a `print`, so an optimistic log can't quietly disappear.
- Feed-reminder (AlarmKit) scheduling failures are logged and fall back to a
  local notification; a denied alarm permission prompts once to enable it.
- CloudKit sync, share-acceptance, and the system share sheet route failures to
  the unified log (and a banner where a parent needs to know).
- The join/sync screens no longer spin forever — a ~30s escape hatch re-kicks
  the fetch, and the co-parent Finish step explains itself if the owner's
  profile is slow to sync.

#### Correctness — input bounds & validation
- Siri/Shortcuts and widget inputs are bounds-checked (feed ounces, backdated
  times) before they're written.
- The edit sheet blocks 0-duration sleeps and no longer clamps 0.25 oz values.
- Baby/profile edits can't be saved with an empty name.

#### Polish
- Diaper logging uses select-then-confirm with a selected highlight (parity
  with feeds); toast Undo and the "Now" control tint to the event's accent.
- Timeline sleep capsules scale so longer sleeps look longer; the Dynamic Island
  sleep timer dims overnight.
- CSV export carries a logger-color column and a readable sleep duration.

#### Submission scaffolding
- Added `TwoOfUs/PrivacyInfo.xcprivacy` (no tracking; required-reason APIs
  declared) for App Store submission.
- New runbooks: App Store release, manual/device QA, device matrix, and
  accessibility checklist (`docs/`).

> Device- and account-dependent work (widgets, Live Activities, two-account
> CloudKit sharing, push, App Store Connect listing/nutrition label, the second
> Xcode Cloud workflow) is tracked in `docs/RELEASE_POLISH_PLAN.md` §18 and the
> new runbooks — it can't be completed from the codebase alone.

## [1.0] — TestFlight
- Initial TestFlight build: core logging (feed/diaper/sleep), CloudKit sync,
  widgets, Live Activities, Siri/App Intents, and stats.
