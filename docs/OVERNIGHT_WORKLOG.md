# Overnight autonomous session — worklog

Running autonomously while Taylor sleeps (started 2026-07-12 ~22:10). Goal: work
the pre-App-Store backlog — accessibility, CloudKit schema/sync review, edge
cases — testing + fixing + logging. Branch `release-polish-batch-1`. Local
commits only (no push — pushing `main` triggers TestFlight). Gates that must stay
green: `make build`, `make test` (76 unit tests), `make uitest` (UI smoke).

This file is the source of truth for what's done — a continuation reads it first.

## Legend
✅ done & verified · 🔧 in progress · ⏭️ queued · 🔎 finding (noted, not fixed) · ⚠️ needs device/manual

## Backlog (ordered)
- ✅ **A11y-1** Dynamic Type: make `AppFont.display`/`hero` actually scale (Typography.swift)
- ✅ **A11y-2** Urgency non-color cue (dot vs "!" marker). ⚠️ amber/red marker rendering not yet visually confirmed (all-green seed state verified — no marker, correct); confirm on a device with an overdue event. De-alias of `accentDiaper`==`urgencyAmber` left as-is — the shape cue makes the hue overlap non-blocking.
- ✅ **A11y-3** VoiceOver: "Wake up" button now a separate focusable/actionable element (SleepActiveCard). Verified by the passing UI smoke test.
- ✅ **CK-1** CloudKit schema/mapping review — see findings below. Code is correct & complete; no code fix needed.
- ✅ **CK-2** Sync review — **no bugs found**. Reviewed sharing lifecycle (makeShare returns the server copy for the invite URL; stopSharing/removeParticipant/deleteEverything/leaveShare; removeParticipant matches by cloudUserID with a safe sole-non-owner fallback), the park-never-drop pending queue (persisted to UserDefaults, drained on engine-up), and bootstrap reconcile. Well-architected + unit-test-covered (SyncQueueTests, RecordMappingTests). Documented constraint: offline widget/Siri writes sync on next app-open (no background CKSyncEngine in the extension) — acceptable for 2 users, already in RELEASE_POLISH_PLAN §10.
- ✅ **A11y-4** Onboarding secondary button now wraps (2 lines, shrink-to-fit) + flexible bar height instead of clipping at large Dynamic Type. Verified at AX3.
- 🔎 **A11y-5 (noted, not fixed)** The onboarding **tour page (OnboardingTourPage) overflows at AX3+** — content isn't scrollable, so it collides with the bottom bar (Continue overlaps the "without opening the app" mockup). Needs a focused fix (ScrollView or a ViewThatFits that compresses/hides the decorative mockup at large sizes) + cross-size verification. The name-entry pages already scroll. Flagging rather than risking a blind layout rework.
- ✅ **EDGE-1** Active-sleep broken sliver on History swimlane — fixed (DayRibbon: anchor active sleep to `min(now, laneEnd)`, not the lane's midnight). +3 regression tests (DayRibbonTests).
- ✅ **EDGE-2** "Invite my partner" now gated on `canFinish` (OnboardingView) — no share before names exist.
- ✅ **EDGE-3** JoinFlow stuck state — added a "Try again" re-kick on the profile page's slow-connect state (owner profile not synced), matching JoinSyncingView. ⚠️ slow-connect state needs interactive verification (30s wait + name entry).
- 🔧 **OB-1** Keyboard covers Continue — ✅ fixed (scoped `ignoresSafeArea(.keyboard)` to background+pager; bar rides above keyboard). ⚠️ needs interactive keyboard verification. Blank-page-on-swipe still ⏭️.

## More fixes (from the deduped 197-finding audit)
- ✅ **SLEEP-UNDO** Undo of "Started sleep" now ends the Live Activity (new `EventStore.cancelSleep`) — a plain softDelete stranded the lock-screen timer.
- ✅ **CK-AVATAR** Inbound sync no longer erases a good local avatar when a CKAsset is momentarily unreadable (`inboundPhoto` distinguishes cleared vs transiently-unreadable). +2 regression tests.

## CK-1 — CloudKit schema/mapping review (findings)
Reviewed `Schema.swift`, `RecordMapping.swift`, `SyncConstants.swift`. **The mapping code is solid** — this is the trickiest area and it's well-built:
- Every field **round-trips**: outbound `record(forRecordName:)` writes exactly what inbound `apply*` reads, for all 6 record types (Feed/Sleep/Diaper/Baby/Participant/SharedSettings). Verified field-by-field.
- Records keyed by model `UUID` (stable across owner/participant zones); relationships stored as UUID strings, resolved locally — **no `CKReference`**, so no cross-zone ordering/integrity trap.
- `ckSystemFields` (archived server change tag) correctly rebuilt on every outbound save (if-server-record-unchanged semantics) with a newer-wins guard; `absorbConflict` preserves terminal fields (soft-delete, sleep-stop) so a race loser can't resurrect them.
- Orphan events relinked to the baby both in the fetch handler and on first Baby apply (belt-and-suspenders for interrupted fetches).
- CKAsset temp files swept via `cleanUpStaleAssetFiles` (called from `SyncManager` bootstrap) — no leak.

**🔎 Deployment items to verify (not code bugs — CloudKit Dashboard / manual):**
- ⚠️ **CK-DEPLOY-1**: `SharedSettings.ozPresets` is a `[Double]` → CloudKit **Double (List)** field. Auto-created in Development; must be **promoted to Production** with the list type or settings sync fails in prod.
- ⚠️ **CK-DEPLOY-2**: Deploy the full schema (all 6 record types + fields) from Development → **Production** in the CloudKit Dashboard before App Store submit. CKSyncEngine uses zone changes (no queries), so no query indexes are required.
- ⚠️ **CK-DEPLOY-3**: `Schema.swift` migration plan is intentionally empty (additive-optional changes auto-migrate). Any **non-additive** model change post-launch needs a real `MigrationStage` — matches the existing SwiftData/CloudKit constraint note.

## Batch 1 summary (overnight, ~22:10–23:00)
**9 commits, all green** (build ✅, 81 unit tests ✅, UI smoke test ✅). Fixed:
1. Dynamic Type scaling for glance fonts (was fully broken) + ribbon labels
2. Urgency shape cue (dot vs "!") — no longer hue-only
3. VoiceOver reaches the "Wake up" button
4. Active-sleep sliver on History swimlane (+3 tests)
5. Invite gated on names (no empty-zone share)
6. Continue rides above the keyboard in onboarding
7. JoinFlow "Try again" escape hatch (no permanent stuck state)
8. Onboarding secondary CTA wraps at large text
9. Undo-of-started-sleep ends the Live Activity
10. Inbound sync keeps local avatar on transient asset failure (+2 tests)
Plus CloudKit CK-1 + CK-2 reviews (no bugs; deployment items logged).

**Verified on device/sim:** #1 (AX-XL), #2 green-state, #4/#9/#10 by tests, UI smoke.
**Needs interactive verification:** #2 amber/red marker, #6 keyboard, #7 slow-connect. See ⚠️ items.
**Deferred (risk/verification):** A11y-5 tour-page AX3 overflow; onboarding blank-page-on-swipe; StatsEngine "divide by fixed 7 days" newborn-delta inflation (HistoryView:113/StatsEngine:396); ManageDataView export "Preparing…" hang; WidgetProvider overnight-sleep drop; HistoryView whole-screen empty state.

## Change log
_(append newest last)_
- Dynamic Type scaling (A11y-1) + ribbon label shrink-to-fit. Verified at accessibility-extra-large.
- Urgency shape marker dot/"!" (A11y-2). Green state verified; amber/red pending device confirm.
- SleepActiveCard: split accessibility so "Wake up" is reachable in VoiceOver (A11y-3). UI test green.
- CK-1 review: no code change; deployment findings logged above.
