# Manual check-in / check-out — plan

Manual "Drop off" / "Pick up" on the Today card, weekdays only, one tap each,
attributed to whoever tapped, synced via CloudKit, driving daycare mode
immediately. Plus a lightweight "Home today" escape hatch. Fully manual — no
auto-detect (geofencing etc.) in this phase.

## What already exists (and what this plan reuses)

- **`CheckEvent`** (SwiftData, synced): `typeRaw` (checkIn/checkOut),
  `timestamp`, `byName`, `loggedByID/Name/ColorHex`, `sourceRaw`, soft delete,
  `ckSystemFields`. Already in the CloudKit mapping and on the timeline —
  **no new record type and no schema deploy needed** for drop-off/pick-up.
- **`DaycareStatus.attendance`** already implements most of the fallback
  hierarchy: today's latest check marker wins (checkout beats check-in),
  else the first daycare-logged event stands in as an implicit check-in,
  and the whole thing force-closes at the assumed 5:30 PM. Crucially,
  `HomeView.daycareAttendance` already passes **all** `CheckEvent`s into it,
  not just Brightwheel ones — a manually inserted check-in flips daycare
  mode today, with zero changes to the engine. A manual 4:00 PM pickup
  already overrides the 5:30 assumption (latest marker wins).
- **Daycare mode** on Home is `attendance != nil`: log tiles sit out, the
  hero shows the open strip zone + "@ daycare since" line. Manual pickup →
  `attendance == nil` → tiles return. Requirement 4 is almost free.

## Model changes

1. **Drop-off / pick-up: none.** Manual markers are `CheckEvent`s with
   `sourceRaw = nil` — the app-wide convention for "logged by hand" (SNOO
   and Brightwheel are the only `EventSource` cases; `isFromDaycare` stays
   false, which is correct: a parent logged it, not staff). Taylor's
   `source = "manual"` requirement is met semantically — nil *means*
   manual everywhere else in the store. (Alternative: add
   `EventSource.manual`; rejected — it would make manual checks the only
   hand-logged events with a non-nil source, and old builds would render
   an unknown-source tag as blank anyway.)
   `byName` is set to the logger's display name so the timeline row reads
   "Checked in by Taylor" with zero row changes.
2. **"Home today": one new enum case** — `CheckType.notAttending`
   (label "Home today", emoji 🏠). Stored in the existing `typeRaw` string
   field, so **no CloudKit schema change** (the field is a string; new
   values are schema-free).
   - ⚠️ **Version-skew caveat**: `CheckEvent.type` falls back to
     `.checkIn` for unknown raw values, so an **old build** syncing a
     `notAttending` record would misread it as a check-in and enter
     daycare mode. Mitigation: change the fallback *in the same release*
     is impossible for already-shipped builds, so the release notes tell
     both parents to update together (2-user app, we control both
     phones). Conservative alternative if that's unacceptable: keep
     "Home today" device-local in `LocalPrefs` (doesn't sync; Paige's
     phone would still show Drop off) — recommended only if we expect
     long version skew.
3. **`EventStore` additions** (mirroring `logFeed`'s shape):
   `logCheck(_ type: CheckType, at: Date = .now) -> CheckEvent?` — fills
   logger identity, `byName`, saves, returns the event for Undo.
   Soft-delete/restore already work for CheckEvent (swipe-delete exists).

## UI — the Today card

A new **check row** at the bottom of `TodayHeroCard` (below the totals,
above the daycare recap), driven by a single state enum computed in
`HomeView` and passed in:

```
enum CheckinSlot { case dropOff, pickUp, hidden }
```

- **`dropOff`** — weekday, no attendance, no check markers today, not
  marked home, and before the 5:30 close. Renders:
  - Primary: a full-width-ish capsule button "🏫 Drop off" in the
    check-teal (`accentCheck`) family — glass tile idiom (it's tappable),
    ~44pt tall, clearly secondary to the log tiles in weight.
  - Secondary: trailing caption-size text link **"home today"** in
    `text3` — deliberately featherweight (requirement: not equal weight).
- **`pickUp`** — attendance is live (manual *or* Brightwheel-implicit).
  Same slot, same geometry: "🚗 Pick up". This also gives Brightwheel
  days a real checkout when staff never log one.
- **`hidden`** — weekends, after pickup/5:30, or "home today" active.
  The slot collapses (animated with the existing tiles↔strip easeInOut).
- **"Home today" active state**: the slot shows one caption line
  "🏠 home today · *undo*" — tapping undo soft-deletes the
  `notAttending` record and the Drop off button returns. ("Actually,
  taking him in.")
- Every tap: `Haptics.tap()`, logged toast with **Undo** (the app-wide
  pattern — Undo soft-deletes the just-created marker and restores the
  previous state, including re-entering daycare mode if a pickup is
  undone).
- One tap, no sheets, no confirmation (requirement 6). Time = `.now`;
  backdating happens via the timeline row's existing edit path if ever
  needed.

### Weekend detection

`Calendar.current.isDateInWeekend(now)` on the ticking `ctx.date` (so the
slot appears/disappears at midnight without a relaunch, riding the
existing midnight-rollover machinery). Mon–Fri = show; Sat/Sun = never.
(Holidays are out of scope — "home today" covers them.)

## Daycare-mode trigger logic (final hierarchy)

Resolved inside `DaycareStatus.attendance`, in priority order:

1. **Today's latest manual or imported check marker** — checkOut (or a
   manual pickup) ends the day *immediately*; checkIn starts it. A
   `notAttending` marker suppresses attendance **unless** rule 2 fires
   later (if staff start logging bottles, he's obviously there — the
   implicit check-in overrides "home today", and the slot flips to
   Pick up).
2. **First Brightwheel event of the day** — implicit check-in (existing
   behavior, unchanged).
3. **5:30 PM assumed close** — unchanged. A manual check-in *after* 5:30
   is still honored until midnight (existing rule, kept).

`DaycareStatus` changes: accept the `notAttending` case (today: unknown
raws collapse to `.checkIn` — the new case must be filtered before the
"latest marker" scan, not treated as a check-in), and add the
"Brightwheel-overrides-home-today" rule. All pure-function changes —
covered by extending `DaycareStatusTests`.

### Summary/capsule plumbing

`DaycareDaySummary.checkIn/checkOut` and `HomeView.daycareToday` currently
only read **Brightwheel** checks. Widen to any-source check markers so:
- the hero capsule shows "@ daycare from 7:48 – 4:02" from manual markers,
- the strip zone closes at the manual pickup time,
- the recap row appears on a manual-only day (drop-off counts as
  `hasAnythingElse`), reading just "Daycare / since 7:48" until staff
  data arrives.

## CloudKit sync

- CheckEvent already round-trips (record mapping + hold queues); manual
  ones ride the same path. **No schema work, no `cktool` deploy.**
- Both parents see the flip within the usual ~10s; daycare mode is
  derived state, so it follows automatically on the other phone.
- **Race**: both parents tap Drop off within a sync window → two checkIn
  records. Harmless to attendance (latest wins, same type); timeline
  shows two rows, either can be swipe-deleted. The button also disables
  itself the moment a same-type marker for today exists locally, which
  closes the common case. No dedupe machinery warranted for 2 users.

## Edge cases

| Case | Behavior |
| --- | --- |
| Drop off → Pick up → needs to go back (sick-day false alarm) | Spec says buttons disappear after pickup. Escape hatch: undo the pickup from its toast, or swipe-delete the checkout row on the timeline → mode and Pick up button return. No third button state. |
| "Home today" → plans change | Tap *undo* on the slot line (soft-deletes the marker) → Drop off returns. |
| "Home today" but Brightwheel events arrive | Implicit check-in wins; mode ON; slot shows Pick up. The stale marker is ignored for the rest of the day. |
| No pickup by 5:30 | Assumed close (existing). Capsule reads "from 7:48" (honest — end unknown) per current inferred-window rules. |
| Manual pickup at 4:00 | Mode ends 4:00, capsule "7:48 – 4:00" (requirement 5's override — latest-marker-wins already does this). |
| Marker logged, then edited to a weekend date / backdated | Attendance is day-scoped (existing `isLive` guard); nothing leaks across midnight. |
| Second check-in after a checkout (evening re-entry) | Engine supports it (latest marker = checkIn → mode on), but no button offers it per spec; possible only via timeline edits. Accepted. |
| Old app version receives `notAttending` | Misreads as check-in (see caveat above). Ship both phones together; conservative fallback documented. |

## Test plan

- `DaycareStatusTests`: notAttending suppression, Brightwheel-overrides-
  home-today, manual pickup ends before 5:30, post-5:30 manual check-in
  honored, weekend slot logic (pure date fn).
- `EventStoreTests`: `logCheck` attribution + soft-delete/restore.
- Simulator passes: weekday morning (Drop off visible), tap → daycare
  mode + toast, Pick up → tiles return, "home today" → slot collapses →
  undo; Saturday launch (no slot); `-seedDaycareSampleDay` interplay
  (implicit check-in shows Pick up). Screenshots light + dark before
  merge, per the usual loop.

## Out of scope (explicitly)

Auto-detect (geofence/Wi-Fi), holiday calendars, schedules per weekday,
multi-daycare, notifications on check-in (worth a follow-up: ping the
other parent), Watch/widget drop-off buttons.
