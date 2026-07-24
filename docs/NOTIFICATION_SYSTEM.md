# Notification System — Routing Audit

> Companion to [NOTIFICATIONS.md](NOTIFICATIONS.md) (which covers entitlements,
> categories, and the content extension). This doc maps **every notification the
> app can produce, what triggers it, and which device it fires on** — written to
> answer the question "who gets woken up, and why?"
>
> **Audit finding (2026-07-24):** there is **no feed-schedule / slot-assignment
> feature** in the app. Nothing in the data model, sync layer, or notification
> code routes a reminder to a specific parent. See
> [No assignment routing exists](#no-assignment-routing-exists) for what the
> current behavior actually is and what building assignments would take.

## Every notification, end to end

All reminder *scheduling* is **device-local**: each iPhone arms its own alarms
and notifications off the shared event log. Nothing ever "sends" a reminder to
the other device — the only cross-device push is CloudKit's **silent** sync
push, which is never user-visible.

| # | Notification | Mechanism | Scheduled by | Trigger / fire time | Who receives it |
|---|---|---|---|---|---|
| 1 | **Loud feed alarm** ("feed due") | AlarmKit timer (pierces Silent/Focus) | `FeedAlarmManager.reschedule` | `lastFeed + SharedSettings.targetFeedInterval` | Every device with `LocalPrefs.feedReminderEnabled == true` |
| 2 | **AlarmKit fallback** | Local notification (with sound) | `FeedAlarmManager.scheduleFallbackNotification` | Same fire time as #1, only when AlarmKit scheduling *throws* | The device whose AlarmKit call failed |
| 3 | **Gentle feed nudge** | Local notification, `.timeSensitive`, silent | `NotificationManager.refreshScheduledReminders` | `lastFeed + targetFeedInterval` | Every device with `gentleRemindersEnabled == true` **and** `feedReminderEnabled == false` (stands down when the loud alarm is armed) |
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

1. **Does scheduling check a slot assignment?** No. There are no slots and no
   assignments anywhere in the codebase. Fire time is purely
   `lastFeed + targetFeedInterval`; the only routing input is each device's own
   local toggles.
2. **If one parent "isn't assigned" the 2am feed, does their device skip it?**
   No such concept. If both parents have `feedReminderEnabled` on, **both
   phones alarm at the same moment** — the fire time derives from shared state
   (last feed + shared interval), so the two devices' alarms coincide within
   sync lag. The only way today for one parent to sleep through is to toggle
   the loud alarm off on their device entirely (all nights, not per-slot).
3. **Does AlarmKit bypass any assignment logic?** There is none to bypass, but
   note AlarmKit *does* deliberately bypass quiet hours and Focus — that is its
   role. It respects only the local `feedReminderEnabled` toggle.
4. **Cross-device pushes when the co-parent logs a feed?** The only push is the
   silent sync push. The visible "co-parent activity" banner is generated
   *locally* on the receiving device and is gated by that device's `notifyFeed`
   toggle (default **on**), quiet hours (default **off**), and Focus. So with
   defaults, yes: a 2am feed logged by one parent posts a passive, silent
   banner on the other's phone — it won't light through Silent/Focus, but it
   exists. Enabling quiet hours suppresses it. Separately (and desirably), the
   synced feed re-arms the receiving device's own alarm to the new time.
5. **Are quiet hours per-user?** Yes — `LocalPrefs`, never synced. They don't
   interact with assignments (none exist). Their one sharp edge: they do *not*
   apply to the AlarmKit alarm or a manual snooze, by design.
6. **Does the next-feed countdown consider who's assigned?** No. The countdown
   (home tile urgency, widgets, alarm, gentle nudge) is the same
   `lastFeed + targetFeedInterval` for everyone; `SharedSettings` carries only
   the interval, oz presets, and default oz.

## No assignment routing exists

The v1 scope (locked 2026-06-05) deliberately shipped a **single shared
next-feed countdown** with per-device opt-in reminders — "no day/night split
yet." The de-facto model for "you take the 2am, I take the 5am" today is:
one parent leaves `feedReminderEnabled` on, the other turns it off (or relies
on quiet hours for the passive stuff). Blunt, but it does keep the opted-out
phone dark all night.

Per-slot assignment ("Taylor owns 2am, wife owns 5am, unassigned → both")
would be a **new feature**, not a bug fix. It needs, at minimum:

- A synced schedule model (slots with time windows + optional
  `assignedParticipantID`) — in `SharedSettings` or a new record type, plus
  `RecordMapping` + `CKSyncEngine` plumbing and hold-queue handling.
- Routing: every re-arm point above filters by
  `slot.assignedParticipantID == nil || == LocalPrefs.myParticipantID` before
  arming #1/#2/#3 — the device-local scheduling architecture makes this the
  easy part, since each phone already decides only for itself.
- A race guard for "assignment changed but hasn't synced to the other phone
  yet" (stale device keeps its alarm armed until the change lands + re-arm runs).
- UI to define slots/assignments, widget/countdown semantics for "not your
  slot", and tests.
