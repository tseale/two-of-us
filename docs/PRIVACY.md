# Two of Us — Privacy

**Status**: v2 — July 13, 2026 (avatars, export, and App Store distribution
reflected; v1 was June 5, 2026)

Two of Us records a baby's feeds, sleep, and diapers and shares them between a small, invited group of family/caregivers. The data is mundane but personal, and it's about a child — so the design is privacy-first by default.

---

## What's stored

- **Baby**: name, date of birth, optional profile photo (chosen by a parent,
  downscaled on-device before storage).
- **Events**: feeds (ounces, time), sleep (start/end), diapers (type, time), optional notes, who logged each.
- **People**: display name, color, role, and optional avatar photo of each invited participant.
- **Settings**: target feed interval and presets (shared); notification preferences and quiet hours (per-device, never leave the device).

No location, no contacts, no HealthKit data. Photos are limited to the optional
baby/participant avatars above — chosen through the system photo picker, so the
app never gets access to the photo library itself.

## Where it's stored

- All shared data lives in **the owner's private iCloud** (Taylor's account), in a CloudKit container (`iCloud.com.taylorseale.twoofus`), inside a shared record zone.
- It is **end-to-end within Apple's iCloud** — there is **no Two of Us server**, no third-party backend, and the developers never see the data.
- Per-user settings stay in local device storage and never sync.

## Who can access it

- The **owner** and anyone they explicitly **invite by link**. Nobody can join without an invite.
- Two roles: **Full** (co-parent — full access) and **Logger** (caregiver — can log and edit events, cannot change settings or baby info). No public or view-only access tier.
- Access is **revocable** at any time from Manage People. A revoked person immediately loses access; their previously logged entries remain in the record (attributed to their name at the time).

## No tracking

- **No analytics, telemetry, ads, or tracking SDKs.**
- **No third-party dependencies** — the app uses only first-party Apple frameworks (SwiftUI, SwiftData, CloudKit, WidgetKit, ActivityKit, UserNotifications).
- Notifications are generated **locally on each device**; cross-parent alerts use Apple's CloudKit push to wake the app, which then posts a local notification only if that user opted in. No notification content is routed through any external service.

## Data lifetime & control

- Data persists in the owner's iCloud until deleted. Deleting an event is a soft delete in-app; **Settings → Manage data → Delete everything** permanently removes the CloudKit zone (and with it every record and the share) after a multi-step confirmation.
- Uninstalling the app does not delete the iCloud data (so a reinstall restores it); the owner can purge it in-app via Delete everything or via iCloud settings.
- **Export** is built in and local-only: a CSV backup and a pediatrician PDF report, both generated on-device and shared only where the user chooses to send them. No upload, ever.

## Children's data note

Two of Us is used **by parents to record their own child's care** — it does not collect data *from* a child, has no accounts for children, and has no child-facing features. It is not a service directed at children and is not enrolled in the Kids Category. The App Store privacy nutrition label answers derived from this document live in `docs/appstore/PRIVACY_NUTRITION_LABEL.md`.

## Distribution

- Distributed via **TestFlight** today; a public **App Store** release is in preparation with the same privacy posture (the listing's nutrition label is "Data Not Collected" — no data ever reaches the developer).
- Requires the user to be **signed into iCloud** for sync; the app degrades to local-only logging if not.
