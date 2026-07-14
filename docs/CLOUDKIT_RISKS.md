# CloudKit risk assessment

What can go wrong with the Two of Us sync architecture, what's already safe, and
the rules to follow while shipping updates to real users. Written against the
codebase as of 2026-07-14 (post sync-overhaul, pre App Store release).

**Architecture recap** (details in `docs/CLOUDKIT_SETUP.md`): SwiftData is the
local store; sync is hand-rolled on `CKSyncEngine` — the owner's `.private`
database holds one custom zone (`TwoOfUsZone`) shared zone-wide via `CKShare`;
the co-parent syncs the same zone through the `.shared` database. Records are
keyed by model UUID, relationships travel as UUID strings, and every model
caches the server change tag in a local-only `ckSystemFields` property. This is
NOT SwiftData's automatic CloudKit mirroring — which means schema evolution has
**two independent layers** that must both be handled on every model change:

1. **The local SwiftData store** — migrated on device by SwiftData.
2. **The CloudKit schema** (record types/fields in the container) plus the
   hand-written mapping in `TwoOfUs/Sync/RecordMapping.swift`.

---

## 1. Rules Taylor must follow

### Schema changes — DO

1. **DO make every new model property optional, or give it a default value.**
   Both is best (`var mood: String? = nil`). This is what lets SwiftData
   lightweight-migrate the on-disk store in place and lets old records decode.
2. **DO treat a new field as optional *in meaning*, not just in type.** The
   other phone may run the old app for weeks and will never write the field.
   Every read must have a sensible fallback (`r["x"] as? T ?? existing`), and
   the feature it powers must degrade gracefully when the field is absent.
3. **DO update every layer when adding a field.** A new synced property touches,
   at minimum: the `@Model`, `RecordMapping.record(forRecordName:)` (outbound),
   the matching `apply…` function (inbound), a round-trip case in
   `TwoOfUsTests/RecordMappingTests.swift`, and the schema table in
   `docs/CLOUDKIT_SETUP.md`.
4. **DO deploy the CloudKit schema to Production BEFORE merging to `main`.**
   Order matters: create the field in the Development environment (run a dev
   build that saves it, or add it by hand in the CloudKit Console), then Console
   → Schema → *Deploy Schema Changes* → verify it's visible under Production,
   and only then merge (a `main` push archives straight to TestFlight). A
   production build that writes a field Production doesn't know fails the save
   — that record then never reaches the co-parent until the schema catches up.
5. **DO keep enum handling non-destructive.** New enum cases (e.g. a fourth
   `DiaperType`) are safe only because raw values are stored as strings and old
   clients fall back for *display* (`DiaperType(rawValue:) ?? .wet`) without
   rewriting `typeRaw`. Keep that pattern: never normalize/rewrite a raw value
   you don't recognize.
6. **DO run `make test` after any model or mapping change** — the record-mapping
   round-trip tests are the guard rail for rules 1–3.

### Schema changes — DON'T

7. **DON'T rename anything that syncs.** Not a property, not a CKRecord field
   key, not a record type, not the zone name, not the container ID. CloudKit
   Production is additive-only — a rename is really "add new + orphan old":
   old clients keep writing the old field, new clients the new one, and the
   data forks. If a name truly must change, change only the Swift-side name and
   keep the CKRecord key the same (the mapping in `RecordMapping` is the only
   place the wire name lives — that indirection exists exactly for this).
8. **DON'T delete or repurpose an existing field.** You can stop *writing* one
   (leave a comment tombstone in `RecordMapping`), but the field stays in the
   Production schema forever and old clients may still write it. Never reuse an
   abandoned field name with different semantics or a different type.
9. **DON'T change a field's type** (e.g. `Int` → `String`, scalar → list).
   CloudKit rejects type changes outright; add a new field instead and read the
   old one as a fallback.
10. **DON'T add a `VersionedSchema` bump or `MigrationStage` for additive
    optional changes.** Counterintuitive but load-bearing (see the comment in
    `TwoOfUs/Store/Schema.swift`): each `VersionedSchema` references the *live*
    model types, so a hand-rolled "v1 snapshot" would also carry the new
    property and fail to match the real on-disk v1 store. Additive changes ride
    `SchemaV1` + automatic lightweight migration. A custom `MigrationStage` is
    only for a genuinely breaking local change — which rule 7/8 says you
    shouldn't be making anyway.
11. **DON'T introduce `@Attribute(.externalStorage)`** or other store options
    that change how a property is persisted — keep assets small and inline
    (the avatar pattern: downscaled JPEG in a `Data?` property, shipped as a
    `CKAsset` by the mapping layer).
12. **DON'T add a `context.delete(baby)` path.** The `.cascade` relationship
    hard-deletes all events locally without touching CloudKit; full deletion
    must go through `SyncManager.deleteEverything()`, which tears down the zone
    server-side first.

### Adding a whole new record type (e.g. a MedicineEvent)

Safe for old clients — they ignore record types they don't recognize
(`RecordMapping.apply`'s `default: break`) and the records simply appear after
they update. But the type must be threaded through **all** of these
hand-maintained lists; missing one is silent (see Risk R1):

- `SchemaV1.models` (Schema.swift) — and the widget/notification-extension
  targets pick it up via `project.yml`'s shared-source lists if the file is new
- `SyncConstants.RecordType`
- `RecordMapping`: `record(forRecordName:)`, `modelExists`, `apply`,
  `model(ofType:)`, `anyModel`, `clearAllSystemFields`, plus a `HasSyncID`
  conformance (and `AnyEventModel` if it's an event)
- `SyncManager`: `allLocalIDs()` (bootstrap upload) and `wipeLocalModels()`
- CloudKit Console: create the type in Development, deploy to Production
- `docs/CLOUDKIT_SETUP.md` schema table, and round-trip tests

---

## 2. Current risk assessment

**Checked, no rule violations found.** Every synced property is defaulted or
optional; no renames/typechanges pending; `photoData` was added additively with
no schema bump (correct per rule 10); inbound mapping is tolerant of missing
fields; outbound saves rebuild on archived system fields so only explicitly-set
keys are sent. `aps-environment: development` in the entitlements is fine —
distribution signing flips it to `production` automatically
(`docs/XCODE_CLOUD.md`).

Two properties of the current design are worth calling out because they're what
makes mixed-version operation safe — **don't break them**:

- **Old clients can't wipe new fields.** Outbound records are rebuilt from
  `encodeSystemFields` archives and CKRecord sends only the keys the client
  set, so an old app re-saving a record leaves fields it doesn't know about
  untouched on the server.
- **Old clients ignore unknown inbound data.** Unknown fields fail the `as?`
  cast and keep the local value/default; unknown record types are skipped
  entirely.

Open risks, highest first:

- **R1 (medium) — six hand-maintained type lists.** Adding a model requires
  touching every enumeration site in the "Adding a whole new record type"
  checklist above. Missing
  `allLocalIDs()` means the type never bootstrap-uploads; missing
  `wipeLocalModels()` means "Delete everything" leaves residue; missing
  `clearAllSystemFields` breaks zone-recreation recovery. All failures are
  silent. Mitigation: use the checklist above; consider a shared
  `SyncedModel` registry if a third event type ever lands.
- **R2 (medium) — Production schema state isn't verifiable from the repo.**
  `docs/OVERNIGHT_WORKLOG.md` flags CK-DEPLOY-1/2 (deploy all six types;
  `ozPresets` must be **Double (List)** in Production). TestFlight sync working
  implies the deploy happened, but before the App Store release, confirm in the
  Console that all six record types and every field in the
  `docs/CLOUDKIT_SETUP.md` table exist under **Production** — a field that was
  never non-nil on a dev build (e.g. `notes`, `cloudUserID`, `editOfID`) is the
  classic gap.
- **R3 (medium) — the family's data has a single point of failure: Taylor's
  iCloud account.** The zone lives in the owner's private database; the share
  is not transferable to another owner (CloudKit has no ownership transfer).
  If the owner's account is lost/reset (or its iCloud storage is purged), the
  server copy is gone — and a revoke event *wipes the participant's local copy
  by design* (`detachFromShare`). Mitigations: both phones do hold full local
  replicas until a revoke lands, and CSV export exists — see §4. Export
  periodically.
- **R4 (low) — concurrent edits of the *same record* are whole-record
  last-writer-wins.** Simultaneous logging is conflict-free (new UUIDs never
  collide), and soft-deletes / sleep-stops always stick (`absorbConflict`
  terminal-field rules). But if both parents edit the *same existing event's*
  notes/amount at the same moment, the losing side re-sends its full content
  and the other parent's non-terminal edit is overwritten. Acceptable for two
  users; don't add collaborative-editing features on top of this policy.
- **R5 (low) — pending-write bookkeeping lives in UserDefaults/state files.**
  Hold queues and engine state survive relaunches but not app deletion:
  deleting the app with unsynced local writes loses those writes (the synced
  history is safe server-side). Not fixable without a server-side journal;
  just don't debug by deleting the app off a device that's been offline.
- **R6 (info) — widget/Siri logs made while offline sync only after the app is
  next opened.** Documented constraint (`SyncManager.drainExtensionQueue`,
  RELEASE_POLISH_PLAN §10); not a bug.

---

## 3. Update deployment checklist

For every release that touches a model or `RecordMapping` (skip to step 5 for
pure UI releases):

1. **Design the change additively** (Rules 1–2, 7–9). Ask: "what does the old
   app on the other phone do with this record?" — the answer must be "renders
   fine, just without the new feature."
2. **Update all mapping layers + tests** (Rule 3), `make test` green.
3. **Exercise the field in Development**: `make run`, log data that writes the
   new field, confirm the field appears in Console → Development → Data. For a
   two-device behavior, test owner + participant on two simulators/accounts.
4. **Deploy schema to Production** (Console → Deploy Schema Changes) and verify
   in the Production environment picker. This is the point of no return —
   Production changes cannot be rolled back, so re-read the diff for typos
   before confirming.
5. **Merge to `main`** → Xcode Cloud archives → TestFlight.
6. **Update your own phone first**, confirm sync against your wife's
   still-on-old-version phone (this is the mixed-version test that matters),
   then let her update.
7. **If something breaks**: there is no binary rollback on TestFlight/App
   Store — you can only ship a fix forward. That's why the compat rules are
   strict: the escape hatch for a bad *code* change is a quick forward fix;
   there is no escape hatch for a bad *schema* change. Check Console →
   Production → Logs for per-record server errors before touching code.

**Staging container?** No. A second CKContainer would double the signing/
entitlement surface for a 2-user app. The **Development environment of the
existing container already is the staging tier** — same code path, isolated
data, resettable schema. Use it (steps 3–4); that's what it's for.

**Schema rollback?** Development can be reset to match Production; Production
can never remove types or fields. A mistakenly-deployed *extra* field is
harmless (nothing writes it). A wrongly-*typed* field is permanent — hence
step 4's re-read.

---

## 4. Data safety analysis

**Protected:**

- **Every event both phones have seen** exists in ≥3 places: CloudKit server,
  owner's local store, participant's local store. Local stores are treated as
  caches — a corrupt store is quarantined and rebuilt from a full zone re-fetch
  (`ModelContainer+App.swift`), safe because inbound apply upserts by UUID.
- **Writes park, never drop.** Offline edits queue in the engine state; edits
  made while an engine can't exist (signed out, zone unknown) go to explicit
  hold queues and drain later. Even a fetched batch the store refuses to save
  triggers an engine reset + re-fetch rather than a silent skip.
- **Deletes are soft** (`deletedAt`) and terminal in conflicts — an edit racing
  a delete can't resurrect the event. Undo re-clears `deletedAt` as a new
  write. Hard deletes only happen via the audited full-wipe paths.
- **Long offline periods** are fine: CKSyncEngine change tokens resume the
  delta; if state is lost, a full re-fetch is idempotent. The co-parent's
  device being offline for weeks converges on next launch.

**Not protected / know the edges:**

- **Owner account loss = family data loss** (R3). CSV export
  (`LogExporter`, Settings → export) is the only copy outside the iCloud
  ecosystem — but it covers **live events only**: no photos, no settings, no
  soft-deleted history, and it isn't re-importable today. It's a keepsake, not
  a restore path. Habit worth having: export before any risky operation and
  every month or so.
- **"Delete everything" (owner) is a true kill switch** — it deletes the zone
  server-side, which cascades to the share and, via the revoke path, wipes the
  participant's phone too. The flow is well-guarded (typed confirmation, won't
  pretend success while offline), but there is no server-side undo.
- **Accidental revoke is recoverable but disruptive**: the participant's device
  wipes its copy and returns to onboarding (by design — an ex-member's phone
  shouldn't keep the log). Fix: re-send an invite; full history re-syncs on
  accept. Nothing is lost server-side — except any writes the participant made
  offline that hadn't synced before the revoke landed.
- **Device-local, never synced, lost on app deletion**: sync role +
  `myParticipantID` (LocalPrefs), notification/quiet-hours prefs, engine state,
  hold queues. After a delete-and-reinstall the *data* comes back from CloudKit
  but the device redoes identity setup (owner: onboarding re-links; participant:
  needs the invite link tapped again).

**Conflict policy (for reference):** change-tag (`ckSystemFields`) based.
Concurrent *creates* never conflict (distinct UUIDs). Concurrent *edits of the
same record*: loser adopts the server change tag, keeps its own content, and
re-sends — except `deletedAt`/`endedAt`, which are adopted from the server if
set. Net: last writer wins per record, deletes and sleep-stops always win.

---

## 5. Scaling notes

**Short version: nothing to do for years.**

- **Participants**: a CKShare supports ~100 participants; the design (one zone,
  one baby, role enforcement in UI) is comfortable to ~10 caregivers. Beyond
  that the People UX, not CloudKit, is the limit.
- **Storage**: records in the owner's private DB count against the **owner's
  iCloud quota** (free tier 5 GB shared with everything else). An event record
  is well under 1 KB; heavy newborn tracking (~25 events/day) is ~9k records
  ≈ single-digit MB per year. Avatars are ~50 KB each. Quota is a non-issue.
- **Request limits**: CloudKit private-database traffic isn't metered like the
  public DB; two phones' worth of CKSyncEngine deltas is nowhere near any
  operational limit.
- **Performance**: the first full fetch on a new device grows linearly with
  history (batched, resumable — fine at tens of thousands of records). Local
  fetch paths are indexed by-UUID lookups with fetch limits. The things that
  scan broadly (`StatsEngine`, History) work on date-bounded fetches; revisit
  only if year-two profiling says so.
- **Pruning**: don't. The data is the product (the log of the first years).
  If anything, eventually hard-delete *soft-deleted* records older than ~90
  days (`enqueueDelete` + local delete) to keep the zone tidy — cosmetic, not
  necessary.
- **When to actually worry**: a second baby (schema is ready — `Baby` is
  relational; the app UI is single-baby), a caregiver count past ~10, or any
  feature that wants server-side logic/queries — CKSyncEngine's zone-delta
  model does no queries, and adding them would mean new indexes + a different
  architecture conversation.
