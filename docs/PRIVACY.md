# Miller Time — Privacy

**Status**: v1 — June 5, 2026

Miller Time records a baby's feeds, sleep, and diapers and shares them between a small, invited group of family/caregivers. The data is mundane but personal, and it's about a child — so the design is privacy-first by default.

---

## What's stored

- **Baby**: name, date of birth.
- **Events**: feeds (ounces, time), sleep (start/end), diapers (type, time), optional notes, who logged each.
- **People**: display name, color, and role of each invited participant.
- **Settings**: target feed interval and presets (shared); notification preferences and quiet hours (per-device, never leave the device).

No location, no contacts, no health-kit data, no photos in v1.

## Where it's stored

- All shared data lives in **the owner's private iCloud** (Taylor's account), in a CloudKit container (`iCloud.com.taylorseale.millertime`), inside a shared record zone.
- It is **end-to-end within Apple's iCloud** — there is **no Miller Time server**, no third-party backend, and the developers never see the data.
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

- Data persists in the owner's iCloud until deleted. Deleting an event is a soft delete in-app; full removal follows from deleting the iCloud records / container.
- Uninstalling the app does not delete the iCloud data (so a reinstall restores it); the owner can purge it via iCloud settings.
- **Export** is deferred past v1 — when added, it will be a local export (CSV/PDF) the user initiates, with no upload.

## Children's data note

Miller Time is used **by parents to record their own child's care** — it does not collect data *from* a child, has no accounts for children, and is distributed privately via TestFlight to a handful of invited adults. It is not a service directed at children. If the app is ever submitted to the App Store, revisit the privacy nutrition label and applicable children's-privacy requirements before release.

## Distribution

- Distributed via **TestFlight** to invited testers only. No public App Store listing in v1.
- Requires the user to be **signed into iCloud** for sync; the app degrades to local-only logging if not.
