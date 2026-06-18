# Notifications

Two of Us uses three layers of iOS notification tech, each for a distinct job.
All of it is **silent** (no sound — haptics + visuals only, per `DESIGN.md`),
per-device (prefs live in `LocalPrefs`, never synced), and honors per-user
**quiet hours**.

| Layer | Framework | Job | Code |
|---|---|---|---|
| Loud feed alarm | **AlarmKit** | The one reminder that must pierce Silent/Focus to wake a parent overnight: "next feed due". | `Alarms/FeedAlarmManager.swift` |
| User-facing local notifications | **UserNotifications** | Co-parent activity, gentle feed/diaper reminders, daily summary. | `Notifications/NotificationManager.swift` |
| Silent sync push | **CloudKit / APNs** | Background `CKSyncEngine` fetch; never shown to the user. | `App/AppDelegate.swift`, `Sync/SyncManager.swift` |

## What gets posted

- **Co-parent activity** — when the *other* parent's feed/sleep/diaper syncs in,
  `SyncManager.notifyCoParentActivity` posts a calm, informational notification
  ("Taylor · Fed Miller 3 oz"). Styled as a **Communication Notification**
  (`INSendMessageIntent` + the co-parent's `Participant.photoData`) so it shows
  their avatar. Per-kind opt-in via `notifyFeed` / `notifySleep` / `notifyDiaper`.
  Interruption level `.passive`.
- **Gentle reminders** — soft, snoozable "feed due / diaper check" nudges
  (`gentleRemindersEnabled`), re-armed by `EventStore` on every log and on
  foreground. Interruption level `.timeSensitive`. The feed nudge **stands down
  while the AlarmKit feed alarm is on** so you're never reminded twice.
- **Daily summary** — a `.passive` end-of-day recap (`notifyMilestones`).

## Actionable (background logging)

Reminder notifications carry action buttons (`registerCategories`):

- Feed reminder → **Log feed**, **Snooze 30m**
- Diaper reminder → **Wet**, **Dirty**, **Snooze 30m**

Logging actions run **without opening the app**: `AppDelegate`'s
`UNUserNotificationCenterDelegate` routes the response to
`NotificationManager.handle`, which writes through **`QuickLogger`** (the App
Group store) exactly like the widget/Siri path, then drains the write to
CloudKit. Snooze reschedules the reminder. The default tap just opens the app.

## Safeguards

- **Never notify yourself** — co-parent posts skip events whose `loggedByID`
  is the local participant.
- **Dedupe** — posted keys are tracked in App Group `UserDefaults`
  (`notify.posted`) so a re-delivered record never double-fires.
- **Recency window** — co-parent posts ignore events older than 15 min, so a
  participant joining (which pulls full history) doesn't flood.
- **Quiet hours** — suppress `.passive` posts; reminders aren't scheduled to
  fire inside the window. AlarmKit still breaks through.
- **Demo mode** — everything no-ops against the throwaway in-memory store.

## Capabilities / entitlements

`TwoOfUs.entitlements` (mirrored in `project.yml`):

- `com.apple.developer.usernotifications.time-sensitive` — for `.timeSensitive`
  reminders (no Apple approval needed).
- `com.apple.developer.usernotifications.communication` — for the avatar styling.
- **Not** using Critical Alerts — AlarmKit already covers the wake-the-parents
  case, and Critical Alerts needs a special request to Apple.

## Future / deferred

- Dynamic daily-summary copy (today's real counts).
- Focus Filter intent (`SetFocusFilterIntent`).
- Notification Content Extension for fully custom rich UI.

## Testing

Requires **two physical iPhones** on different Apple IDs (a simulator shares one
iCloud account and won't exercise co-parent sync). See the verification steps in
the implementation plan: log on device A → device B is notified with an avatar;
fire a reminder → "Log feed" writes + syncs without opening the app; toggle
each type + quiet hours and confirm suppression; confirm no sound and no
self-notification.
