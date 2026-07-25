# Changelog

All notable changes to Two of Us are recorded here. The format loosely follows
[Keep a Changelog](https://keepachangelog.com/); versions track
`MARKETING_VERSION` in `project.yml`.

## [Unreleased]

### Fixed
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
