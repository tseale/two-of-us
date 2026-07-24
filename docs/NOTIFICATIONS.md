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

- **Feed-schedule routing** — when the shared feed schedule assigns the next
  feed's slot to the other parent, this device arms neither the AlarmKit alarm
  nor the gentle feed nudge. Full rules, fail-safe biases, and sync behavior:
  `NOTIFICATION_SYSTEM.md` → "Feed-schedule routing".
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

Both special UserNotifications entitlements are currently **deferred** because
Xcode Cloud's automatic cloud signing couldn't provision them, which failed the
App Store distribution export (Builds 47–48). Neither removal breaks the build
at runtime — the related features simply degrade:

- **Time Sensitive Notifications** (`com.apple.developer.usernotifications.time-sensitive`)
  — *deferred.* `NotificationManager` still sets `interruptionLevel =
  .timeSensitive` on gentle reminders, but without the entitlement iOS downgrades
  them to a normal active level, so they no longer break through Focus/Silent.
  The loud AlarmKit feed alarm still pierces for the critical overnight wake case.
- **Communication Notifications** (`com.apple.developer.usernotifications.communication`)
  — *deferred.* It styled co-parent posts with the sender's avatar
  (`INSendMessageIntent`). `NotificationManager.communicationContent` still
  builds the intent but **falls back to plain content** when the styling can't
  be applied, so co-parent notifications post without an avatar.

Re-enable either by turning the matching capability on for the
`com.taylorseale.twoofus` App ID in the Developer portal, then restoring the
entitlement here and in `project.yml`.
- **Not** using Critical Alerts — AlarmKit already covers the wake-the-parents
  case, and Critical Alerts needs a special request to Apple.

### Notification-content-extension App ID — REQUIRED portal step

The rich card (below) ships as the **`TwoOfUsNotificationContent`** app
extension, bundle id **`com.taylorseale.twoofus.notificationcontent`**. It reads
live data from the shared App Group (`QuickLogger.make()`), so its entitlements
declare `com.apple.security.application-groups` → `group.com.taylorseale.twoofus`.

This is a **new** bundle id (added in #78). Xcode Cloud's automatic *cloud
signing* will register the App ID on the fly, but it does **not** reliably enable
the **App Groups** capability on it or assign the group — and an App Store
*Distribution* profile for an App-Group target can't be minted until that's set.
That is what fails the archive at **"Exporting for App Store Distribution failed
→ Code Signing"** (Builds 47–49), independent of the app-level notification
entitlements removed in #80/#81.

**One-time fix in [developer.apple.com → Identifiers](https://developer.apple.com/account/resources/identifiers/list)** (team `Q58H65DQ64`):

1. **+** → **App IDs** → **App** → Continue.
   - Description: `Two of Us Notification Content`
   - Bundle ID: **Explicit** → `com.taylorseale.twoofus.notificationcontent`
   - Capabilities: check **App Groups**. Register.
2. Edit the new App ID → **App Groups** → **Configure** → select the existing
   `group.com.taylorseale.twoofus` group → Save. (The group already exists; it's
   shared by the app and widgets — do *not* create a new one.)
3. Nothing else to upload — Xcode Cloud's managed certs do the rest. Re-run the
   workflow (push to `main` or **Start Build**); the next archive exports.

No repo change is needed — `project.yml` and the extension's entitlements are
already correct. This is purely the portal registration catching up to the new
target. (If the export *still* fails after this, the App Group capability also
needs confirming on the `…twoofus` and `…twoofus.widgets` App IDs, but those have
signed since the original setup.)

## Rich expanded UI (Notification Content Extension)

Long-pressing / pulling down a notification shows a custom card rendered by the
**`TwoOfUsNotificationContent`** app extension (`NotificationViewController` hosts
the SwiftUI `NotificationCardView`). It's registered for the daily summary,
co-parent, and both reminder categories (`UNNotificationExtensionCategory` in the
extension's Info.plist). The card reads **live** state from `QuickLogger`
(today's counts/sleep for the summary; last-feed/diaper/sleep "time since" for
co-parent/reminders) so it's accurate even if the notification was posted earlier.
Action buttons still render below, supplied by the category. The extension shares
`QuickLogger`, the models, and the design system via `project.yml` sources (like
the widget target).

## Dynamic daily summary

`refreshDailyMilestone()` schedules a **one-shot** notification for the next 9pm
with today's real numbers (e.g. "8 feeds (24 oz) · 6 diapers · 5h 10m sleep")
from `QuickLogger.todayCounts` + `todaySleep`. It's re-armed on app foreground
and on every log so the pending copy stays fresh. (If the app isn't opened on a
given day, that day's summary keeps the last-armed copy.)

## Focus filters

`TwoOfUsFocusFilter` (`SetFocusFilterIntent`, in `Intents/`) lets each iOS Focus
reconfigure the app via two per-Focus toggles — **Mute co-parent activity** and
**Only urgent reminders**. `perform()` persists them to App Group UserDefaults;
`NotificationManager` suppresses passive (co-parent) posts when either is set,
while time-sensitive reminders always get through. Note: deactivation reversion
is the one behavior to confirm on-device, and the pre-scheduled daily summary
can't be focus-gated at fire time.

## Future / deferred

- Per-focus gating of the pre-scheduled daily summary.
- `relevantDate` / scheduled-summary tuning.

## Testing

Requires **two physical iPhones** on different Apple IDs (a simulator shares one
iCloud account and won't exercise co-parent sync). See the verification steps in
the implementation plan: log on device A → device B is notified with an avatar;
fire a reminder → "Log feed" writes + syncs without opening the app; toggle
each type + quiet hours and confirm suppression; confirm no sound and no
self-notification.
