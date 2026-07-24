# Changelog

All notable changes to Two of Us are recorded here. The format loosely follows
[Keep a Changelog](https://keepachangelog.com/); versions track
`MARKETING_VERSION` in `project.yml`.

## [Unreleased]

### Feed schedule — per-slot reminder routing
- New shared **Feed schedule** (Settings → Feed schedule, Full role): recurring
  overnight slots, each assigned to one parent or Both. When the next feed
  lands in a slot, only the assigned parent's phone arms the AlarmKit alarm,
  its fallback notification, and the gentle feed nudge — the other parent
  sleeps through. Unassigned slots and uncovered times alert everyone.
- Routing is fail-safe by design: an unknown local identity, a slot assigned
  to a revoked participant, or corrupt schedule data all degrade to "remind
  everyone" — a silently skipped overnight feed is the one unacceptable outcome.
- The schedule syncs on the existing settings record (`feedSlotsData`);
  records from older app versions leave a local schedule untouched, and a
  synced-in assignment change immediately re-arms (or disarms) this device's
  alarm via the existing post-fetch re-arm path.
- Changing the target feed interval or the schedule in Settings now re-arms
  the pending alarm immediately (previously waited for the next foreground).

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
