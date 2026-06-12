# CloudKit setup runbook

Instructions for Claude, running **locally** (computer use + Xcode available), to
finish and verify the CloudKit production setup. Written by a prior cloud session
that fixed the sync layer (PRs #52, #54) but couldn't compile, run, or reach the
CloudKit Console. Work through this top to bottom; each phase has a checkpoint.

**Context you need:**
- Container: `iCloud.com.taylorseale.twoofus` · custom zone: `TwoOfUsZone`
- Sync is hand-rolled on `CKSyncEngine` + a zone-wide `CKShare`
  (`TwoOfUs/Sync/`), NOT SwiftData mirroring. Records are keyed by model UUID;
  relationships travel as UUID strings, not `CKReference`s.
- TestFlight builds use the **Production** CloudKit environment; Xcode dev
  builds use **Development**. Dev creates schema just-in-time; Production is
  locked and additive-only. Shares are visible only within the environment
  that created them.
- Taylor must do every Apple-ID sign-in himself (Console, simulators). Never
  handle his credentials; pause and ask him to sign in when a step needs it.

## Phase 0 — Build and test locally (do this first)

The cloud sessions authored everything blind. Verify it actually compiles and
passes before touching the Console.

1. `make test` (regenerates the .xcodeproj via XcodeGen, runs `TwoOfUsTests`
   on the iPhone simulator). Fix any compile errors or test failures —
   they're expected to be small (API-signature or XcodeGen-scheme nits).
2. If PR #54 ("Fix the invite link hanging forever in Messages") is still
   open, this is the moment to validate it: confirm `make test` is green on
   that branch, mark the PR ready, and tell Taylor.

**Checkpoint:** `make test` green.

## Phase 1 — CloudKit Console: verify the Development schema

Browser work (computer use). Ask Taylor to sign in at
<https://icloud.developer.apple.com>, then open the container
`iCloud.com.taylorseale.twoofus` and select the **Development** environment.

Under Schema → Record Types, all six types below must exist with all listed
fields. Fields are also created just-in-time, so any field that was never
non-nil on a dev build is missing — `cloudUserID` and `notes` almost
certainly are. **Add missing fields manually** (Record Type → Edit → Add
Field) rather than trying to exercise every code path; it's deterministic.

| Record type | Field | CloudKit type |
|---|---|---|
| `Baby` | `name` | String |
| | `dateOfBirth`, `createdAt` | Date/Time |
| | `photoData` | Asset |
| `FeedEvent` | `amountOz` | Double |
| | `timestamp`, `deletedAt` | Date/Time |
| | `notes`, `loggedByID`, `loggedByName`, `loggedByColorHex`, `editOfID`, `babyID` | String |
| `SleepEvent` | `startedAt`, `endedAt`, `deletedAt` | Date/Time |
| | `notes`, `loggedByID`, `loggedByName`, `loggedByColorHex`, `editOfID`, `babyID` | String |
| `DiaperEvent` | `typeRaw` | String |
| | `timestamp`, `deletedAt` | Date/Time |
| | `notes`, `loggedByID`, `loggedByName`, `loggedByColorHex`, `editOfID`, `babyID` | String |
| `Participant` | `displayName`, `colorHex`, `roleRaw`, `cloudUserID` | String |
| | `isActive` | Int64 |
| | `invitedAt` | Date/Time |
| | `photoData` | Asset |
| `SharedSettings` | `targetFeedIntervalMinutes` | Int64 |
| | `ozPresets` | Double (List) |
| | `defaultFeedOz` | Double |

The authoritative source is `TwoOfUs/Sync/RecordMapping.swift` — if it and
this table disagree, trust the code and update this table.

Skip what you don't need: **no indexes** (CKSyncEngine uses zone deltas, never
queries) and **no security-role changes** (the zone-wide CKShare handles
access).

**Checkpoint:** all six record types complete in Development.

## Phase 2 — Deploy schema to Production

1. Still in the Console: Schema → **Deploy Schema Changes**.
2. Review the diff it shows (should be exactly the six record types / added
   fields), then deploy. Remember Production is additive-only — nothing can
   be renamed or removed later, so fix any typos in Development first.
3. Verify by switching the environment picker to **Production** and
   re-checking the record types.

**Checkpoint:** six record types visible in Production.

## Phase 3 — End-to-end verification

Dev-environment loop (fast, on this Mac):
1. `make run`, sign the simulator into an iCloud account (Taylor does the
   sign-in), complete onboarding, log a feed.
2. Console → Development → Data: query `FeedEvent` records in zone
   `TwoOfUsZone` of that account's private database. The record appearing
   proves the full outbound path (EventStore → SyncManager → CKSyncEngine).
3. Tap the invite step → the share sheet must appear, and the share must
   carry a URL (the #54 fix). If anything fails here, the "couldn't prepare
   the invite" notice — not a hang — is the correct failure mode now.

Production loop (the real one, needs both phones — coordinate with Taylor):
4. Wait for a TestFlight build containing #54 (Xcode Cloud archives every
   push to `main`).
5. Taylor creates a fresh invite **from the TestFlight build** and sends it
   via Messages: the bubble must resolve to a "Two of Us" card within a few
   seconds (no spinner).
6. His wife taps it: the app must open into the join flow (this is the
   `CKSharingSupported` fix), and after she finishes her profile, events
   logged on either phone must appear on the other within ~10s.
7. If anything fails, check Console → Production → Logs (live server-side
   request log, including per-record errors) before touching code.

**Checkpoint / done:** both phones syncing on TestFlight builds.

## Sync-layer invariants (June 2026 overhaul)

The sync layer was overhauled after a comprehensive audit (every finding
verified against Apple's CKSyncEngine sample + WWDC23 10188). The invariants
below are load-bearing; the troubleshooting map assumes them.

1. **Change tags are persisted.** Every synced model carries `ckSystemFields`
   (archived CKRecord system fields, local-only — NOT a CloudKit schema field).
   Outbound saves rebuild on top of it; without it CloudKit rejects every
   update as `serverRecordChanged` and edits silently revert. Tags are captured
   from successful saves, fetched records, and conflict errors
   (`RecordMapping.persistSystemFields` / `absorbConflict`).
2. **Conflicts re-enqueue, local content wins, terminal fields stick.** A
   concurrent `deletedAt` / sleep `endedAt` from the other parent is adopted;
   everything else keeps the local value and re-uploads.
3. **The shared zone ID is persisted** (`sync.sharedZone.*`), captured from the
   share metadata at accept. The engine never re-announces an already-fetched
   zone, so without this every participant write after a relaunch parks forever.
4. **Writes park, never drop.** Hold queues exist for both scopes
   (`sync.pendingShared*`, `sync.pendingPrivate*`) and drain when the engine
   and zone are available.
5. **SyncManager exists from `didFinishLaunching`** (background pushes work
   without a scene), observes `CKAccountChanged`, and restarts engines after
   role transitions (leave/revoke/delete-everything).

## Troubleshooting map

| Symptom | Likely cause | Where |
|---|---|---|
| Messages bubble spins forever | Share has no `.url` (pre-#54 bug) or share save silently failed | `SyncManager.makeShare()` |
| Invite link opens browser / does nothing on the joiner's phone | `CKSharingSupported` missing from Info.plist (pre-#54) | `project.yml` info properties |
| Sync works in dev builds, dead on TestFlight | Schema never deployed to Production | Phase 1–2 above |
| "Unknown field" / "Did not find record type" in Console logs | A JIT-created field missed the deploy | Phase 1 table |
| Owner's TestFlight build can't find a share created from Xcode | Shares don't cross environments | Recreate from TestFlight build |
| Joiner stuck on "Bringing everything over…" | Owner's records not in the shared zone — check owner upload first | Phase 3 step 2 |
| Edits/deletes/sleep-stops revert or never reach the other phone | `ckSystemFields` not being captured (invariant 1 broken) | `RecordMapping`, `SyncManager.handleSentRecordZoneChanges` |
| Participant's logs stop syncing after they relaunch the app | Persisted shared zone missing (invariant 3) — check `sync.sharedZone.*` defaults | `SyncManager.markShareAccepted(zoneID:)` |
| Joiner's Finish button stays disabled | Owner's Participant record hasn't synced down yet (by design — it decides the joiner's role); check owner upload | `JoinFlowView.primaryConfig` |
| Invite accepted on a phone that already had its own log | Expected: a "Join the shared log?" replace confirmation appears first | `ShareAcceptance` / `RootView` |
