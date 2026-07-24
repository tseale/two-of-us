# Notification System — Routing Audit

> Companion to [NOTIFICATIONS.md](NOTIFICATIONS.md) (which covers entitlements,
> categories, and the content extension). This doc maps **every notification the
> app can produce, what triggers it, and which device it fires on** — written to
> answer the question "who gets woken up, and why?"
>
> **Audit finding (2026-07-24):** the app originally had **no feed-schedule /
> slot-assignment feature** — nothing routed a reminder to a specific parent,
> and both phones alarmed simultaneously. Per-slot routing was built the same
> day; see [Feed-schedule routing](#feed-schedule-routing) for how it works.

## Every notification, end to end

All reminder *scheduling* is **device-local**: each iPhone arms its own alarms
and notifications off the shared event log. Nothing ever "sends" a reminder to
the other device — the only cross-device push is CloudKit's **silent** sync
push, which is never user-visible.

| # | Notification | Mechanism | Scheduled by | Trigger / fire time | Who receives it |
|---|---|---|---|---|---|
| 1 | **Loud feed alarm** ("feed due") | AlarmKit timer (pierces Silent/Focus) | `FeedAlarmManager.reschedule` | `lastFeed + SharedSettings.targetFeedInterval` | Every device with `LocalPrefs.feedReminderEnabled == true` **whose turn it is** per [feed-schedule routing](#feed-schedule-routing) |
| 2 | **AlarmKit fallback** | Local notification (with sound) | `FeedAlarmManager.scheduleFallbackNotification` | Same fire time as #1, only when AlarmKit scheduling *throws* | The device whose AlarmKit call failed (sits below the routing gate, so it inherits it) |
| 3 | **Gentle feed nudge** | Local notification, `.timeSensitive`, silent | `NotificationManager.refreshScheduledReminders` | `lastFeed + targetFeedInterval` | Every device with `gentleRemindersEnabled == true` **and** `feedReminderEnabled == false` (stands down when the loud alarm is armed), subject to the same feed-schedule routing |
| 4 | **Diaper nudge** | Local notification, `.timeSensitive`, silent | same | `lastDiaper + 3h` | Every device with `gentleRemindersEnabled == true` |
| 5 | **Snoozed reminder** | Local notification | `NotificationManager.snooze` | +30 min from the snooze tap; ignores quiet hours (user asked) | Only the device that tapped Snooze |
| 6 | **Co-parent activity** ("Fed Miller 3 oz") | Local notification, `.passive`, posted immediately on sync-in | `SyncManager.notifyCoParentActivity` → `NotificationManager.postCoParentActivity` | Another participant's feed/sleep/diaper record arriving via `CKSyncEngine` | The device whose `myParticipantID ≠ record.loggedByID`, if its per-kind toggle (`notifyFeed`/`notifySleep`/`notifyDiaper`) is on |
| 7 | **Daily summary** | Local notification, `.passive` | `NotificationManager.refreshDailyMilestone` | Next 21:00 local | Every device with `notifyMilestones == true` |
| 8 | **Silent sync push** | CloudKit/APNs `content-available` | CloudKit server (zone subscription owned by `CKSyncEngine`) | Any record change in the shared zone | Both devices — invisible; wakes the app to fetch + reload widgets |

Re-arm points (each device recomputes #1/#3/#4/#7 from current store state):

- `EventStore` after every in-app log/edit/delete
- `AppDelegate.applicationDidBecomeActive` (foreground)
- `SyncManager` after a sync batch lands (so a feed logged by the co-parent
  pushes *your* next alarm out)
- `NotificationManager.flushAndRearm` after a background notification-action log
- `SettingsView` when the reminder toggles/interval change

## Gates applied before anything fires

Per-device, in `LocalPrefs` (never synced): `feedReminderEnabled` (loud alarm),
`gentleRemindersEnabled`, `notifyFeed`/`notifySleep`/`notifyDiaper` (co-parent
activity), `notifyMilestones`, quiet hours. Plus, globally: demo mode no-ops
everything; Focus filters can mute `.passive` posts; the dedupe ledger
(`notify.posted`) stops re-delivered records from double-firing; the 15-min
recency window stops a joining participant's history pull from flooding; and
`loggedByID == myParticipantID` guarantees you are never notified about your
own logs.

**Quiet hours** (per-user, default 22:00–07:00 when enabled): suppress
co-parent posts at post time; stop gentle nudges / daily summary from being
*scheduled* to fire inside the window (skipped, not deferred). The **AlarmKit
alarm and its fallback intentionally ignore quiet hours** — the overnight feed
wake-up is their whole job. A user-initiated snooze also ignores them.

## Routing Q&A (the audit questions)

1. **Does scheduling check a slot assignment?** Yes (as of 2026-07-24). Fire
   time is still `lastFeed + targetFeedInterval`, but before arming, both
   `FeedAlarmManager.reschedule` and the gentle-nudge scheduler run the fire
   time through `FeedSchedule.shouldRemind` against the synced schedule and
   this device's `myParticipantID`.
2. **If one parent isn't assigned the 2am slot, does their device skip it?**
   Yes. A fire time covered only by the other parent's slot leaves this device
   dark — no AlarmKit alarm, no fallback, no gentle nudge. Slots set to Both,
   and times outside any slot, alarm both phones as before.
3. **Does AlarmKit bypass the assignment logic?** No — the gate sits inside
   `reschedule`, above the AlarmKit call and its notification fallback, so
   every caller inherits it. AlarmKit still deliberately bypasses quiet hours
   and Focus (that is its job) when it *is* your slot.
4. **Cross-device pushes when the co-parent logs a feed?** The only push is the
   silent sync push. The visible "co-parent activity" banner is generated
   *locally* on the receiving device and is gated by that device's `notifyFeed`
   toggle (default **on**), quiet hours (default **off**), and Focus. So with
   defaults, yes: a 2am feed logged by one parent posts a passive, silent
   banner on the other's phone — it won't light through Silent/Focus, but it
   exists. Enabling quiet hours suppresses it. Separately (and desirably), the
   synced feed re-arms the receiving device's own alarm to the new time.
5. **Are quiet hours per-user?** Yes — `LocalPrefs`, never synced. They apply
   independently of (and in addition to) schedule routing. Their one sharp
   edge: they do *not* apply to the AlarmKit alarm or a manual snooze, by design.
6. **Does the next-feed countdown consider who's assigned?** The *display*
   (home tile urgency, widgets) intentionally does not — both parents can
   glance at when the next bottle is due. Only the reminders route.

## Feed-schedule routing

Added 2026-07-24. The schedule is a list of recurring daily windows
(`FeedSlot`: start/end minutes-from-midnight, wrap-aware, plus an optional
`assignedParticipantID`), stored JSON-encoded in
`SharedSettings.feedSlotsData` and synced on the existing settings record.
Editing lives in **Settings → Feed schedule** (Full role only, like the rest
of Feeding).

**The rule** (`FeedSchedule.shouldRemind`, in `Models/SharedSettings.swift`):
a device arms a feed reminder firing at time T unless every slot covering T is
assigned to somebody else. Concretely:

- Slot assigned to me, or covering slot set to **Both** (`nil` assignee) → arm.
- T covered only by the other parent's slot(s) → **stay dark** (skip alarm #1,
  fallback #2, and gentle nudge #3 alike — the gate sits inside
  `FeedAlarmManager.reschedule` and `refreshScheduledReminders`, so every
  re-arm call site inherits it).
- T outside every slot, or no schedule at all → arm (everyone).

**Fail-safe biases** — ambiguity always resolves to "remind", because a
silently skipped feed is worse than a woken parent: unknown local identity
(`myParticipantID` nil) → remind; assignee no longer an active participant
(revoked caregiver) → treat as Both; corrupt/unreadable `feedSlotsData` →
no schedule → remind everyone.

**Propagation & the stale-device race.** Editing the schedule calls
`EventStore.updateSettings(feedSlots:)`, which saves, syncs, and re-arms this
device immediately. The other phone re-arms when the settings record syncs in
(`SyncManager.rearmFeedRemindersFromStore` after the fetch batch — the silent
push typically lands within seconds). Until that sync lands, the other device
keeps its previous decision — the same staleness window every synced datum
has here. Worst case is bounded and safe-ish in both directions: a *newly
assigned* parent's phone arms on sync/foreground; a *newly excused* parent's
phone disarms the same way (`reschedule` always `cancel()`s first, so a slot
that changed hands can't leave a stale alarm armed).

**Not covered (deliberately):** co-parent activity banners (#6) ignore the
schedule — they're informational, per-kind opt-in, and quiet-hours-gated
already. The widget/home "next feed" countdown still shows for both parents
regardless of assignment (glanceability is shared; only *reminders* route).
Diaper nudges (#4) don't route — slots are a feed concept.

**Tests:** `FeedScheduleTests` (containment incl. midnight wrap, the routing
matrix, fail-safe branches, encoding semantics), `RecordMappingTests`
(schedule round-trip; legacy record without the field preserves a local
schedule; a cleared schedule travels as `[]`, not absence),
`EventStoreTests.testUpdateSettingsPersistsFeedSchedule`. The AlarmKit gate
itself can't run under XCTest (no alarm entitlement in the test host) — it
defers entirely to the tested `FeedSchedule.shouldRemind`.
