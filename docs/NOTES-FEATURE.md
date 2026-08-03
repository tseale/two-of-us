# Notes on the Timeline — Design Plan

**Status: PLAN — not yet implemented.** Review this before building anything.

A new event type: a timestamped free-text note that lives on the timeline
alongside feeds, diapers, and sleeps, synced to both parents like every other
event.

Use cases:

- "Gave him vitamin D drops"
- "Doctor said to try 4 oz"
- "He was fussy after this feed"
- "Mom visited and helped with bath"

This is deliberately different from the *attached* note that already exists on
`FeedEvent`/`SleepEvent`/`DiaperEvent` (`notes: String?`, rendered as a caption
under the row). A `NoteEvent` is a **standalone** entry — something happened
that isn't a feed, sleep, or diaper, but belongs in the shared record.

---

## 1. Scope

### In scope

- New `NoteEvent` SwiftData `@Model`, synced via CloudKit exactly like
  `FeedEvent` (same record-mapping, sync-registration, and CKShare story).
- Inline "+ Add note" button in the timeline section header on Home.
- A small compose sheet: multi-line text field + editable timestamp.
- Timeline row: 📝, note text (truncated), timestamp, author avatar — same
  visual rhythm as the existing `DayTimelineRow`.
- Tap a note row → read full text, edit, or delete (append-only edit, soft
  delete, undo toast — same semantics as the other events).
- Phase 4: notes surfaced in the History tab with filtering.

### Explicitly out of scope (decided up front)

- **No dedicated card/tile on the home screen.** Notes are far less frequent
  than feeds/diapers; they don't earn a `LogButtons` tile, a "time since"
  status, or a spot on the today ribbon.
- **No widget or Live Activity changes.**
- **No notifications** for new notes — the feature is passive; a note is
  discovered by reading the timeline, never pushed.
- **No Siri intent** (for now). `QuickLogger` and the App Intents stay
  untouched.
- **No tracker toggle.** Feed/sleep/diaper logging can be turned off per
  household (`SharedSettings.isEnabled(kind)`); notes are always available and
  don't participate in that system.
- **No stats.** `StatsEngine`, ribbons, charts, and the daily summary ignore
  notes entirely.

---

## 2. Data model

### 2.1 `NoteEvent` (new file: `TwoOfUs/Models/NoteEvent.swift`)

Mirror [FeedEvent.swift](../TwoOfUs/Models/FeedEvent.swift) field-for-field,
swapping the payload (`amountOz` → `text`):

```swift
import Foundation
import SwiftData

/// A standalone timestamped note on the timeline ("gave vitamin D drops").
/// Distinct from the optional `notes` field attached to feed/sleep/diaper
/// events — this is its own entry, not an annotation on another one.
@Model
final class NoteEvent {
    var id: UUID = UUID()
    var baby: Baby?
    var text: String = ""
    var timestamp: Date = Date()        // when it happened (backdatable)
    var loggedByID: UUID = UUID()
    var loggedByName: String = ""       // denormalized so it renders if participant removed
    var loggedByColorHex: String = ""
    var deletedAt: Date?                // soft delete; nil == live
    var editOfID: UUID?                 // if this replaced an edited record, points to the original
    var ckSystemFields: Data?           // archived CKRecord system fields (see Baby.ckSystemFields)

    init(...)                           // same shape as FeedEvent.init
}
```

**Design decision — denormalized author, not a relationship.** The original
sketch said "participant (relationship to Participant)", but **no event in
this codebase holds a `Participant` relationship**. Every event carries the
denormalized triple `loggedByID` / `loggedByName` / `loggedByColorHex`, and the
sync layer stores relationships as UUID strings resolved locally (see the
header comment in [RecordMapping.swift](../TwoOfUs/Sync/RecordMapping.swift) —
no `CKReference`, no cross-zone integrity problems). The row resolves the
author's *photo* at render time from `loggedByID` (`HomeView.loggerPhoto`),
exactly like the other rows. Deviating for notes would break
`applyCommon`/`AnyEventModel`, the identity backfill in
`EventStore.updateMyProfile`, the ghost sweeps, and the participant merge.
NoteEvent follows the house pattern exactly.

The only relationship kept is `baby: Baby?` — same as the other events, synced
as a `babyID` string and relinked by `relinkOrphanEvents`.

### 2.2 Protocol conformances (all existing, all required)

| Protocol | Where | Why |
|---|---|---|
| `HasSyncID` | RecordMapping.swift extension block | `findByID`/`fetchByID`, sets id + system fields on inbound upsert |
| `AnyEventModel` | RecordMapping.swift extension block | lets `applyCommon` write logger identity / deletedAt / editOfID / baby link |
| `SoftDeletable` | EventStore.swift extension block | swipe-delete, undo restore, clear-all-logs |

### 2.3 Text bounds

`EventBounds` gains a dedicated cap for standalone notes:

```swift
/// Longest standalone NoteEvent text. Roomier than the 280-char attached-note
/// cap (noteMaxLength) — "doctor said…" summaries need a few sentences — but
/// still bounded so a paste-bomb can't bloat the record.
static let noteEventMaxLength = 500
```

Cleaning reuses the `cleanNote` shape: trim whitespace, empty → refuse the
write (a blank note is never saved), cap at 500. The store refuses empty text
the same way `logFeed` refuses 0 oz — Save is also disabled in the UI for
empty text, so the guard is defense in depth.

### 2.4 Schema registration

- Add `NoteEvent.self` to `SchemaV1.models` in
  [Schema.swift](../TwoOfUs/Store/Schema.swift). Adding a whole new model (like
  adding an optional attribute) is a purely additive change — SwiftData's
  lightweight migration handles it; **no** `VersionedSchema` bump (see the
  existing comment in Schema.swift about why a hand-rolled bump is
  counterproductive, and the `swiftdata-cloudkit-constraints` lesson).
- **project.yml:** the `TwoOfUsWidgets` target compiles `Schema.swift` and
  explicitly lists every model file as a source
  ([project.yml](../project.yml) `TwoOfUsWidgets.sources`). `NoteEvent.swift`
  must be added to that list or the widget target stops compiling. The widget
  never *displays* notes — it just needs the type to open the shared store.
- Regenerate the project (`make` / XcodeGen) after the project.yml edit.

---

## 3. CloudKit sync

Follow the `FeedEvent` pattern exactly. Every touchpoint, in one list — miss
one and notes silently don't sync (or worse, sync one-way):

### 3.1 `SyncConstants.RecordType` ([SyncConstants.swift](../TwoOfUs/Sync/SyncConstants.swift))

- `static let note = "NoteEvent"`
- **Add `note` to `RecordType.all`.** This set drives the "did an app update
  teach us new record types?" re-fetch in SyncManager — it's what re-delivers
  NoteEvent records that an older build fetched and dropped (the
  unknown-record-type warning path in `RecordMapping.apply`). This is the
  mixed-version story between the two phones: the parent still on the old
  build ignores inbound notes with a logged warning, then receives them all in
  one re-fetch after updating. No other mixed-version handling is needed.

### 3.2 `RecordMapping` ([RecordMapping.swift](../TwoOfUs/Sync/RecordMapping.swift))

Each of these has an existing per-type block to copy:

1. **Outbound** — `record(forRecordName:)`: new `NoteEvent.fetchByID` branch;
   set `r["text"]`, `r["timestamp"]`, then `setCommon(...)` (logger identity,
   deletedAt, editOfID, babyID).
2. **`modelExists`** — add the NoteEvent fetch-count probe (this is the
   throwing existence check that keeps queued sync work from being dropped on
   transient store errors).
3. **Inbound** — `apply` switch: route `RecordType.note` to a new
   `applyNote`. Follow `applyFeed`'s ghost-hardening exactly: on **insert**,
   require `timestamp`, `text`, and `loggerIdentity(r)` or `skip(...)` — never
   materialize a placeholder note. Then overwrite fields and call
   `applyCommon`.
4. **`delete(recordName:)`** — add the NoteEvent probe (true CloudKit
   deletions; routine removals travel as `deletedAt`).
5. **`relinkOrphanEvents`** — add the NoteEvent baby-relink loop.
6. **`clearAllSystemFields`** — add `clear(NoteEvent.self)`.
7. **`model(ofType:)` and `anyModel(id:)`** — add the NoteEvent cases.
8. **`absorbConflict`** — no new code: the `SoftDeletable` branch already
   protects a concurrent soft-delete, and notes have no other terminal field
   (nothing like `endedAt`). Last-writer-wins on text is correct for a
   two-person household.
9. **Conformance extensions** — `NoteEvent: HasSyncID` (the standard
   `findByID` fetch-limit-1 block) and `NoteEvent: AnyEventModel` (the
   `babyRef` forwarding).

### 3.3 `SyncManager` ([SyncManager.swift](../TwoOfUs/Sync/SyncManager.swift))

- `sweepGhostsIfNeeded` and `healUnnamedEventsIfNeeded` each keep a local
  `eventTypes` list of `[feed, sleep, diaper]` — add `note` to both, so a
  ghost-signature note (empty logger name, unknown logger id) triggers the
  sweep and an unnamed-but-known-logger note gets healed.
- Nothing else: enqueue/save/fetch plumbing is record-type-agnostic (ids in,
  `RecordMapping` out).

### 3.4 CKShare / zone

**No work.** The share is zone-wide (`TwoOfUsZone` + one `CKShare`), so every
record in the zone — including the new type — is automatically shared with the
co-parent. This is the whole point of the hand-rolled `CKSyncEngine`
architecture.

### 3.5 ⚠️ CloudKit Console schema deploy (release gate)

A new record type exists only in the **Development** environment until the
schema is deployed to **Production** — until then, notes are dead on TestFlight
builds (production container): outbound saves fail, both phones look broken.
`cktool` cannot deploy to production; it's a manual step in CloudKit Console
(Deploy Schema Changes). Same runbook as the PlanSlot deploy (2026-07-28).

**Order of operations:** dev-build locally → NoteEvent record type auto-created
in Development by first save → deploy schema to Production in the Console →
*then* merge to `main` (which ships to TestFlight).

### 3.6 Ghost-event invariants (from the PR #111 postmortem)

All four invariants are honored by construction if the steps above copy the
feed pattern faithfully:

- Creation requires a resolved owner (`requireOwner`) — no random-UUID
  attribution, ever.
- Inbound insert requires the record's own required fields — no placeholder
  materialization.
- Inbound is an upsert keyed by `id`, and the existence check **throws** on
  store errors (that's `findByID`, not `fetchByID`) — no blind INSERT dupes.
- The render-level dedupe (`seen.insert($0.id).inserted`) covers notes for
  free once they flow through `TimelineEntry`.

---

## 4. `EventStore` ([EventStore.swift](../TwoOfUs/Store/EventStore.swift))

New methods, copying the feed shapes:

```swift
@discardableResult
func logNote(_ text: String, at date: Date = .now) -> NoteEvent?
```
- `requireOwner()` (banner on failure), **no** `requireTracking` (notes have
  no tracker toggle).
- Refuse empty/whitespace text (like `isLoggableOz` refuses 0 oz); trim + cap
  at `noteEventMaxLength`; `clampPast` the date.
- Insert → `save()` with rollback on failure → `sync(save: [event.id])`.
- **No** `reloadWidgets()`, **no** `refreshLocalReminders()`, **no** intent
  donation — notes touch none of those surfaces. (This is the one deliberate
  difference from `logFeed`'s tail.)

```swift
@discardableResult
func editNote(_ original: NoteEvent, text: String, timestamp: Date,
              loggedBy: Participant? = nil) -> NoteEvent
```
- Append-only, same as `editFeed`: build replacement with
  `editOfID: original.id`, soft-delete the original, sync both ids. Refuse
  empty text by returning the original (mirror of the 0-oz edit refusal).

Delete/undo reuse `softDelete`/`restore` unchanged (NoteEvent is
`SoftDeletable`). The `reloadWidgets`/`refreshLocalReminders` calls inside
them are harmless no-ops for notes — not worth special-casing.

Sweeps and maintenance — add `NoteEvent.self` to each generic call site:

- `clearAllLogs()` — purge notes too ("Clear all logs" means everything).
- `ghostEvents()` / `autoPurgeGhostEvents()` — collect/sweep notes. The
  duplicate-id collapse and ghost-signature soft-delete generics already
  handle any `PersistentModel & SoftDeletable & AnyEventModel`.
- `backfillIdentity` (inside `updateMyProfile`) — rewrite notes on
  rename/recolor so old note rows relabel.
- `ParticipantMerger` ([ParticipantMerger.swift](../TwoOfUs/Sync/ParticipantMerger.swift))
  — wherever it rewrites event `loggedByID`s on merge, include NoteEvent
  (verify at implementation time; it iterates event types like the store
  sweeps do).
- `LogExporter` ([LogExporter.swift](../TwoOfUs/Support/LogExporter.swift)) —
  include notes in the export if it enumerates event types (verify at
  implementation time).

---

## 5. Timeline plumbing (`TimelineEntry`)

[TimelineEntry.swift](../TwoOfUs/Store/TimelineEntry.swift) gets a fourth
case: `case note(NoteEvent)`.

**Design decision — do *not* extend `EventKind`.** `EventKind` means "loggable
tracker kind": it drives the tracker toggles, the `LogButtons` tiles,
"time since" lookups, `RibbonMark`, `PlanSlot.kind`, and Siri enums. Notes
belong in none of those. Instead:

- `TimelineEntry.kind: EventKind` becomes `EventKind?` (nil for `.note`), **or**
  the two call sites that switch on `kind` for display (emoji + accent in
  `DayTimelineRow`/`TimelineRow`) switch on the entry case directly.
  Recommendation: switch on the entry directly — `kind` keeps its current
  non-optional type and simply isn't consulted for notes (compiler will force
  every `switch entry` to handle `.note`, which is exactly the audit we want).
- `id`, `sortDate` (→ `timestamp`), `loggedByID/Name/ColorHex` — trivial new
  arms.
- `notes` property returns nil for `.note` (the row body *is* the text; the
  caption-under-title slot stays empty).
- `title`/`detail`: `title` returns the note text single-line-truncated;
  see the row design below for why the note text takes the title slot.

Display constants:

- Emoji: **📝** (hardcoded in the `.note` arms, since it's not an `EventKind`).
- Accent color: new `AppColor.accentNote` in
  [Colors.swift](../TwoOfUs/DesignSystem/Colors.swift) — a muted neutral
  (e.g. a soft warm gray/lavender) chosen to *recede* next to the feed/sleep/
  diaper accents; notes are context, not activity. Dark-mode variant from day
  one like every other `AppColor`.

Surfaces that enumerate the three event types and **must not** pick up notes
(no change needed, just verification): `RibbonMark.forDay`, `StatsEngine`,
`LogButtons`/tile status, `NightSchedule`/`ScheduleEngine`, widgets,
notifications.

---

## 6. UI design

### 6.1 "+ Add note" button (Home, timeline header)

The timeline section header in [HomeView.swift](../TwoOfUs/Features/Home/HomeView.swift)
(`timelineSection`) currently renders one line:

> `Recent · last 24 hours`

It becomes a two-ended header row:

```
Recent · last 24 hours                    + Add note
```

- Left: existing header text, untouched (`AppColor.text3`, section style).
- Right: an **inline text button** — `+ Add note` in `.caption`/`.footnote`
  weight-medium, tinted `AppColor.accentNote` (or `text2`) — deliberately
  quiet. No card, no icon-only mystery button, no background. It reads like a
  header affordance, the same visual weight as the header text itself.
- Tap → present the note compose sheet. Also fires when the timeline is in
  its empty state (the button lives in the header, which renders either way —
  note-first households exist; the empty-state copy stays feed-focused).
- Accessibility: label "Add note", hint "Writes a timestamped note on the
  timeline".

**Mockup — header state:**
> A thin header line above the NOW cap. Left-aligned muted caption "Recent ·
> last 24 hours"; right-aligned, same baseline, slightly-less-muted "+ Add
> note". Nothing else changes on Home — the log tiles, ribbon, and cards
> above are untouched.

### 6.2 Compose sheet (`NoteSheet`, new file `TwoOfUs/Features/Notes/NoteSheet.swift`)

Follow the sheet pattern of `FeedSheet`/`EditEventSheet`: `NavigationStack` +
`Form`, Cancel / Save toolbar items, presented via `.sheet` from HomeView with
an `onLogged` callback that fires the toast.

Layout (top to bottom):

1. **Note** section — `TextField("What happened?", text:, axis: .vertical)`
   `.lineLimit(3...8)`, autofocused on present (`@FocusState`), sentence
   capitalization. A quiet character counter appears only past ~400 chars
   ("487/500").
2. **Time** section — the existing `TimeControl(date:)` component (same one
   the edit sheet uses), defaulting to `.now`, clamped to past (`clampPast`
   at the store; the picker's `in: ...Date()` in the UI).
3. Toolbar: `Cancel` (dismiss, no save) / **`Save`** — disabled while the
   trimmed text is empty.

Behavior on Save: `store.logNote(text, at: date)` → dismiss → toast
`"Note added"` (accent `accentNote`) with **Undo** → `store.softDelete(event)`.
Exactly the log-feed toast contract.

**Mockup — compose state:**
> A medium-detent sheet titled "New note" (inline). A roomy multi-line text
> field with the keyboard up and cursor blinking, placeholder "What
> happened?". Below it a compact time row showing "Today 2:47 PM" that
> expands to the wheel/tap-to-edit control the edit sheet already uses. Save
> sits top-right, grayed until a character is typed.

### 6.3 Timeline row

Notes render through the same `DayTimelineRow`
([DayTimelineView.swift](../TwoOfUs/Features/Timeline/DayTimelineView.swift))
— same time gutter, same rail, same avatar — so the timeline keeps one visual
rhythm:

- **Time gutter**: clock time, unchanged.
- **Rail node**: standard 11pt circle filled `accentNote` (notes are
  instantaneous — no capsule).
- **Content**: `📝` in the emoji slot; then the **note text** in the title
  slot (`.subheadline.semibold`, `lineLimit(2)`, tail-truncated). No
  "Note ·" prefix — the emoji and muted node already say what it is, and the
  text is the payload. No caption line beneath.
- **Trailing**: author avatar, unchanged.
- Accessibility label: `"Note: <text>, <time>, logged by <name>"`.

`TimelineRow` (the plain non-rail variant kept for other callers) gets the
same treatment via its `entry.kind.emoji`/`title` call sites.

**Mockup — timeline state:**
> Between a 🍼 "Feed · 3 oz" row and a 💧 "Diaper · Wet" row sits: `2:47 PM`
> in the gutter, a small soft-gray node on the rail, `📝  Doctor said to try
> 4oz next week, sizes look…` truncated at two lines, Katie's avatar on the
> right. Same height rhythm; scanning the rail, notes read as quiet gray
> punctuation between the colored activity dots.

### 6.4 Read / edit / delete

Tapping a timeline row already routes to `EditEventSheet` via
`editing = entry` + `.sheet(item: $editing)`. Notes join that flow — the
tap-to-open *is* the read view:

- `EditEventSheet` gets a `.note` arm in its `switch entry`:
  - **Note** section: the same multi-line `TextField` as compose, prefilled,
    `lineLimit(3...8)` — full text visible and editable in one place.
  - **Time** section: `TimeControl(date:)`.
  - The existing **Logged by** reassignment section and **Delete entry**
    button/confirmation apply as-is.
  - Save → `store.editNote(original, text:, timestamp:, loggedBy:)`
    (append-only replacement), disabled when trimmed text is empty.
- Swipe-to-delete on the timeline row works once `HomeView.delete(entry)`
  handles the `.note` case (soft delete + undo toast, unchanged pattern).

**Mockup — read/edit state:**
> The familiar Edit sheet, title "Edit". First section shows the full note
> text in an editable field ("Doctor said to try 4oz next week, sizes look
> good, next appt in 2 weeks"), then the time row, then the two parent
> avatars under "Logged by", then the red "Delete entry" row.

### 6.5 Timeline assembly

Two assembly points build the 24-hour window; both add a notes source:

- `HomeView.timelineEntries` — add a `@Query` for live `NoteEvent`s (deletedAt
  == nil, sorted by timestamp desc) and append
  `notes.filter { $0.timestamp >= since }.map(TimelineEntry.note)`.
- `EventStore.timeline(since:)` — add the matching fetch.

The existing sort + id-dedupe handles the rest.

---

## 7. History tab (Phase 4)

[HistoryView.swift](../TwoOfUs/Features/History/HistoryView.swift) is
charts-only today; notes are text, so they get their own card rather than a
chart:

- **"Notes" card** (the same `Card` container), placed last, shown only when
  notes exist in the window.
- Contents: the last 7 days of notes, newest first, grouped by day
  ("Yesterday", "Tuesday"). Each row: 📝, first ~2 lines of text, time,
  small author avatar. Tap → the same `EditEventSheet` read/edit flow.
- **Filtering**: a compact chip row at the top of the card — `All` ·
  `<Parent 1>` · `<Parent 2>` (built from active participants) — filters by
  author. With more than ~15 notes in the window, a "Show all" link expands
  the card (or pushes a simple full-list screen — decide at build time; start
  with in-card expansion).
- Notes stay **out** of the swimlane, heatmap, and every chart.

**Mockup — history state:**
> Below "Diapers per day": a card titled "Notes" with trailing "7 days".
> Inside, three thin chips (All / Taylor / Katie), then day-grouped rows —
> "Yesterday — 📝 Vitamin D drops ✓ 9:12 AM (avatar)". Tapping a row opens
> the standard edit sheet.

---

## 8. Implementation phases

Each phase is a mergeable unit; tests green (`make test`) at every boundary.

### Phase 1 — Data model + CloudKit + CRUD (no UI)
1. `TwoOfUs/Models/NoteEvent.swift` (mirror FeedEvent).
2. `SchemaV1.models` + project.yml widget-target source + regenerate project.
3. `SyncConstants.RecordType.note` + membership in `RecordType.all`.
4. All nine `RecordMapping` touchpoints (§3.2) + conformances.
5. `SyncManager` eventTypes lists (§3.3).
6. `EventStore`: `logNote`, `editNote`, `EventBounds.noteEventMaxLength`,
   and the sweep/backfill/clear-all/merger/exporter inclusions (§4).
7. Tests: `RecordMappingTests` round-trip (model → CKRecord → model, plus the
   skip-on-missing-fields ghost guard), `EventStoreTests` (log/edit/soft
   delete/restore, empty-text refusal, cap), `SyncQueueTests` if it enumerates
   types.
8. Dev-build once so the record type exists in the CloudKit **Development**
   environment.

### Phase 2 — Timeline UI (display + add)
1. `TimelineEntry.note` case + display arms; `AppColor.accentNote`.
2. `DayTimelineRow`/`TimelineRow` `.note` rendering.
3. Home header "+ Add note" button; `NoteSheet` compose; toast + undo.
4. `timelineEntries` / `timeline(since:)` assembly.
5. Verify non-surfaces: ribbon, stats, tiles, widgets unaffected.

### Phase 3 — Edit/delete on tap
1. `EditEventSheet` `.note` arm (text + time + logged-by + delete).
2. `HomeView.delete(entry)` `.note` case (swipe-delete + undo).

### Phase 4 — History tab
1. Notes card with day grouping + author filter chips.
2. Tap-through to the edit sheet.

### Release gate (before merging to `main`)
- **Deploy the NoteEvent schema to Production in CloudKit Console** (§3.5).
  TestFlight users on the current build simply ignore inbound notes until
  they update, then the known-record-types re-fetch backfills them.

---

## 9. Test plan summary

- **Round-trip**: NoteEvent → CKRecord → NoteEvent preserves every field;
  system-fields archive survives; conflict absorb keeps a server-side
  soft-delete.
- **Ghost guards**: inbound note record missing `text`/`timestamp`/logger →
  skipped, never a placeholder row; duplicate-id rows collapse; ghost
  signature swept.
- **Store semantics**: empty text refused (create + edit); 500-char cap;
  append-only edit chains `editOfID`; clear-all covers notes; identity
  backfill relabels notes.
- **Timeline**: note in window renders once, sorted by timestamp, deduped;
  deleted note disappears; undo restores.
