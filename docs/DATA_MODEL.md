# Two of Us — Data Model

**Status**: v1 design — locked June 5, 2026
**Persistence**: SwiftData (`@Model`) · **Sync**: CloudKit · **Min OS**: iOS 17+

This doc is the source of truth for the schema. Because SwiftData + CloudKit makes schema changes painful (see [Schema Evolution Rules](#schema-evolution-rules)), get names and types right here *before* writing Swift.

---

## Storage tiers

Two of Us has three distinct storage tiers. Putting data in the wrong tier is the most expensive mistake to undo later.

| Tier | What lives here | Backed by | Synced? | Shared between people? |
|---|---|---|---|---|
| **Shared app data** | Baby, all events, participants, shared settings | SwiftData + CloudKit **shared zone** | Yes | Yes — all invited participants |
| **Per-user settings** | My notification toggles, my quiet hours, my display name/color | `UserDefaults` (local) | No | No — device-local |
| **Ephemeral / derived** | "time since last X", urgency color, active-timer elapsed | Computed at render time | n/a | n/a |

**Rule of thumb:** if both parents must see it, it's shared app data. If it's a personal preference about *my* phone, it's per-user and never syncs.

---

## Entities (shared app data)

All events are **append-only**. Editing soft-deletes the original (`deletedAt` set) and writes a replacement; queries always filter `deletedAt == nil`. This sidesteps CloudKit merge conflicts — if both parents edit the same event, you get two live records and let a parent delete the loser.

All timestamps are stored as **absolute `Date` (UTC under the hood)** and rendered in the viewer's local time zone. Elapsed time is always computed from the stored timestamp, never tracked with a client-side ticking counter (survives backgrounding, relaunch, and clock changes).

```swift
@Model final class Baby {
    var id: UUID
    var name: String                 // "Miller"
    var dateOfBirth: Date            // drives "12 weeks old" in the header
    var createdAt: Date
    // v1 has exactly one Baby. The model is kept relational so a future
    // sibling needs a baby switcher, not a schema migration.
}

@Model final class FeedEvent {
    var id: UUID
    var baby: Baby?                  // optional for CloudKit (see rules)
    var amountOz: Double             // formula amount — feeds are instantaneous
    var timestamp: Date              // when the bottle was given (backdatable)
    var notes: String?
    var loggedByID: UUID             // → Participant.id
    var loggedByName: String         // denormalized: renders even if participant later removed
    var loggedByColorHex: String     // denormalized for the same reason
    var deletedAt: Date?             // soft delete; nil == live
    var editOfID: UUID?              // if this record replaced an edited one, points to the original
}

@Model final class SleepEvent {
    var id: UUID
    var baby: Baby?
    var startedAt: Date
    var endedAt: Date?               // nil while the timer is running (the ONLY running timer in the app)
    var notes: String?
    var loggedByID: UUID
    var loggedByName: String
    var loggedByColorHex: String
    var deletedAt: Date?
    var editOfID: UUID?
}

@Model final class DiaperEvent {
    var id: UUID
    var baby: Baby?
    var type: DiaperType             // .wet, .dirty, .both
    var timestamp: Date
    var notes: String?
    var loggedByID: UUID
    var loggedByName: String
    var loggedByColorHex: String
    var deletedAt: Date?
    var editOfID: UUID?
}

@Model final class Participant {
    var id: UUID
    var displayName: String          // "Taylor", "Grandma"
    var colorHex: String             // assigned color for the timeline initial
    var roleRaw: String              // ParticipantRole rawValue
    var cloudUserID: String?         // CKShare participant identity, when known
    var isActive: Bool               // false once access is revoked
    var invitedAt: Date
}

@Model final class SharedSettings {
    var id: UUID                     // single record
    var targetFeedIntervalMinutes: Int   // next-feed countdown target; default 180 (3h)
    var ozPresets: [Double]              // default [2, 3, 4]
}

enum DiaperType: String, Codable { case wet, dirty, both }
enum ParticipantRole: String, Codable {
    case full      // co-parent: log, edit, delete, change settings
    case logger    // caregiver: log + edit events, NO settings / baby changes
}
```

### Why `loggedBy*` is denormalized
Attribution is stored as a triple — `loggedByID` + a **copy** of the name and color at log time. If a caregiver is later revoked (`Participant.isActive = false`) or removed, their past events still render correctly with the right colored initial. The `Participant` record is the live source for *current* people; the denormalized copy is the historical truth on each event.

---

## Per-user settings (local, never synced)

Stored in `UserDefaults` (or a small local store), keyed per device/user. These do **not** belong in SwiftData/CloudKit:

- `notify.feed` / `notify.sleep` / `notify.diaper` — per-event-type opt-in toggles
- `notify.feedReminder` — next-feed countdown reminder on/off
- `quietHours.enabled`, `quietHours.start`, `quietHours.end` — personal do-not-disturb window
- `myDisplayName`, `myColorHex` — how *I* appear (mirrored into my `Participant` record on change)

---

## CloudKit layout

- **Container**: `iCloud.com.taylorseale.twoofus`
- **Owner**: Taylor's iCloud account holds the canonical data in a **shared record zone**.
- **Sharing**: a single `CKShare` over the baby's record zone. Each invited person (wife, caregiver) is a `CKShare.Participant`. Both roles (`full`, `logger`) are **read-write at the CloudKit level** — the Full-vs-Logger distinction is enforced *in the app UI* (gate the settings/baby-edit screens), not by CloudKit permissions. No view-only tier means we never need a read-only participant path.
- **Invite / revoke**: invites are CloudKit share links (`UICloudSharingController` or a custom share flow). Revoking removes the participant from the `CKShare`; their already-logged events remain (owned by the owner's zone).
- **Cross-parent awareness**: a `CKDatabaseSubscription` fires a **silent push** when any participant writes an event. The receiving device wakes, syncs, and — *if that user's local notification prefs allow it* — posts a local notification ("Taylor fed Miller · 3 oz"). The push carries no user-facing content itself; the local prefs decide.

> **Technical risk:** SwiftData's high-level sharing API is thinner than `NSPersistentCloudKitContainer`'s. Sharing a SwiftData store across two iCloud accounts must be validated on **two physical devices** early in Phase 1 — simulators share one iCloud account and will falsely "just work." If SwiftData sharing proves too limited, fall back to `NSPersistentCloudKitContainer` with explicit share management. This is the single biggest build risk; spike it first.

---

## Derived values (never stored)

- **Time since last feed/sleep/diaper** — `now − latest(event.timestamp)` per category
- **Urgency color** — green / amber / red from time-since vs `targetFeedIntervalMinutes` (and per-category thresholds)
- **Next-bottle time** — `lastFeed.timestamp + targetFeedInterval`
- **Active sleep elapsed** — `now − sleepEvent.startedAt` while `endedAt == nil`
- **Daily/stat rollups** — computed from fetches (charts are a later phase)

---

## Schema Evolution Rules

SwiftData + CloudKit is unforgiving. Follow these or you'll be forced into a destructive migration:

1. **Every new property must be optional or have a default value.** CloudKit rejects non-optional additions to existing records.
2. **Never rename or delete a property** in place. Add a new one and migrate data; leave the old one tombstoned.
3. **Additive only.** New models and new optional fields are safe; changing a type or relationship cardinality is not.
4. **No unique constraints** beyond the implicit `id` — CloudKit doesn't enforce them and SwiftData uniqueness conflicts with CloudKit sync.
5. **Relationships are optional** (`var baby: Baby?`) — CloudKit requires it.
6. Use a SwiftData `VersionedSchema` + `SchemaMigrationPlan` from v1 so future versions have a migration seam already in place.
