# iOS 27 upgrade plan

iOS 27 and Xcode 27 shipped 2026-09-14. This is the audit of what actually
changed, what Two of Us should adopt (and in what order), and what has to happen
in Xcode Cloud. Researched 2026-09-18 from Apple's release notes, updates pages,
WWDC26 sessions, and the live Xcode Cloud workflow settings in App Store Connect
— links inline. Facts we could not confirm from an Apple source are marked
**[unverified]**.

## Where we start from

Better than expected. The app is already iOS 26-only (deployment target `26.0`
on all seven targets: app, widgets, watch app, watch complications,
notification content, unit tests, UI tests), already ships a Foundation Models
integration (`TwoOfUs/AI/BabyIntelligence.swift` — the Stats summary card and
the "Today's outlook" card), a full statistical prediction stack
(`PredictionEngine`, `AgeBaselines`, the ridge-regression challenger behind
`PredictionArbiter`, walk-forward `PredictionAccuracy`), a full App Intents
surface (log/query intents, Controls, Focus filter, Shortcuts), a sleep Live
Activity, widgets, and a native watchOS app with complications. So this is a
one-version hop with no deprecated-API debt, not a migration.

Design docs that exist and are affected: `docs/AI-PREDICTIONS.md` (all four
phases implemented 2026-08-27) and `docs/PREDICTION-MATH.md` (recency-weighted
blend, Option D, implemented 2026-08-27). `docs/AI-CHAT-DESIGN.md` does **not**
exist in the repo or its history — §5 proposes writing it.

One correction to a premise this audit started from: **Live Activities on
Watch, Mac, and CarPlay is not new in iOS 27.** Smart Stack forwarding shipped
with iOS 18/watchOS 11; Mac menu bar and CarPlay Dashboard forwarding shipped
with iOS 26
([ActivityKit updates](https://developer.apple.com/documentation/updates/activitykit)).
Our sleep activity has been eligible all along — we just never opted into the
small layout, so whatever those surfaces show today is an auto-shrunk
lock-screen view. iOS 27's actual ActivityKit news is landscape Dynamic
Island/StandBy. Either way, the work in §2 is real and cheap.

## 1. What shipped in iOS 27 / Xcode 27 (the parts that touch us)

| Area | What's new | Relevance |
|---|---|---|
| Foundation Models | `LanguageModel` protocol (any provider can back a session), `PrivateCloudComputeLanguageModel` (32K context, free under 2M downloads), AFM 3 Core on-device model (3B, image understanding), Dynamic Profiles for agentic sessions, `SpotlightSearchTool` local RAG, token accounting APIs — [session 241](https://developer.apple.com/videos/play/wwdc2026/241/), [session 242](https://developer.apple.com/videos/play/wwdc2026/242/), [AFM 3](https://machinelearning.apple.com/research/introducing-third-generation-of-apple-foundation-models) | High — upgrades both AI cards, unlocks real weekly pattern analysis |
| Siri / App Intents | LLM-backed Siri (App Intents is the only integration path; SiriKit deprecated **[unverified — secondary sources only]**), App Schemas, `IndexedEntity`/`IndexedEntityQuery`, `SyncableEntity`, `OwnershipProvidingEntity`, `ShowsSnippetView`, AppIntentsTesting framework — [session 343](https://developer.apple.com/videos/play/wwdc2026/343/), [session 345](https://developer.apple.com/videos/play/wwdc2026/345/) | High — our intents get smarter Siri handling mostly for free; entity APIs map directly onto our synced events |
| ActivityKit | Landscape Dynamic Island + `\.isDynamicIslandLimitedInWidth`; `.supplementalActivityFamilies([.small])` (pre-27, unadopted by us) — [session 223](https://developer.apple.com/videos/play/wwdc2026/223/) | Medium — small-family layout is the missing piece for Smart Stack/CarPlay |
| SwiftUI | `@State` is a macro (once-per-lifetime init, back-deploys to iOS 17, **source-compat breaks**), reorderable containers, swipe actions outside `List`, `@ContentBuilder`, toolbar additions, `Tab(role: .prominent)` — [SwiftUI updates](https://developer.apple.com/documentation/updates/swiftui), [iOS 27 release notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes) | Medium — mostly free wins plus a required compile audit (done, §6) |
| SwiftData | `@Query(sectionBy:)`, `.codable` attribute option, `ResultsObserver`, `HistoryObserver` (observe remote changes) — [SwiftData updates](https://developer.apple.com/documentation/updates/swiftdata) | Medium — `HistoryObserver` is interesting for sync-driven UI refresh |
| CloudKit | Effectively nothing: no WWDC26 session, no new `CKSyncEngine`/`CKShare` API found; one 27.0 bugfix (self-demoting share administrator now works) | None — hand-rolled sync is unaffected |
| Xcode 27 | Swift 6.4, macOS Tahoe 26.6+ / Apple silicon only, min deployment target iOS 15 (so 26.0 stays fine), `-ld64` now errors — [Xcode 27 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes) | Required — see §6 |
| App Store | **Uploads must use the iOS 27 SDK starting April 2027** — [Apple news](https://developer.apple.com/news/?id=k1mtkt1k) | Hard deadline for the whole plan |

Not relevant to us: Core AI framework (custom-model deployment — the pure-Swift
ridge regressor already covers our "personal model" need), the new Document
APIs (`FileDocument` deprecation doesn't apply; we have no document types),
iPhone Duo hinge APIs, Metal/visionOS Xcode Cloud support.

## 2. Priority 1 — Live Activity small family (Smart Stack + CarPlay)

The sleep Live Activity (`TwoOfUsWidgets/SleepLiveActivityView.swift`) declares
only the standard lock-screen and Dynamic Island presentations — no
`supplementalActivityFamilies` anywhere in the tree. The watch app already
gives us complications (`SleepComplication`, `NextFeedComplication`, …), so
this isn't "sleep on the wrist for the first time"; it's the *live, pinned*
sleep timer at the top of the Smart Stack while a sleep is running, plus the
CarPlay Dashboard card, both rendered on purpose instead of auto-shrunk. Work:

1. Add `.supplementalActivityFamilies([.small])` to the `ActivityConfiguration`.
2. Branch on `@Environment(\.activityFamily)` and build a dedicated `.small`
   layout: moon glyph + `Text(startedAt, style: .timer)` + baby name, and the
   predicted-wake line if it fits. The Wake button (`Button(intent:)` with
   `SetSleepIntent`) works on Watch — keep it if it fits, drop it if cramped.
3. Handle `\.isDynamicIslandLimitedInWidth` in the compact/minimal Dynamic
   Island views for landscape (iOS 27).
4. Verify in Xcode 27's Preview Snapshot tooling (it renders Live Activity
   states) plus a paired Watch simulator.

No Info.plist or entitlement changes — `NSSupportsLiveActivities: YES` already
covers it. Mac menu bar and CarPlay forwarding are automatic. ~Half a day.

## 3. Priority 1 — Foundation Models upgrades

`BabyIntelligence` today: availability-gated `SystemLanguageModel.default`
sessions; `summary(digest:)` for the Stats recap and `outlook(digest:)` for the
"Today's outlook" narrative over the computed predictions, both governed by the
synced `aiPredictionsEnabled` toggle. iOS 27 changes worth taking, in order:

- **Keep the on-device default.** AFM 3 Core is a straight quality upgrade to
  both existing cards — zero code change. The 8,192-token context is ample for
  the digest approach.
- **Adopt token accounting** (`model.contextSize`, `tokenCount(for:)`,
  `response.usage`) to size the digest defensively instead of hoping, and log
  usage via `AppLog.ai`.
- **Weekly pattern analysis via Private Cloud Compute — approved 2026-09-18.**
  `docs/AI-PREDICTIONS.md` wrote PCC off as "not applicable… if Apple opens
  PCC-backed larger models to the framework later, `BabyIntelligence` is the
  seam where it would slot in." That is exactly what iOS 27 did.
  `PrivateCloudComputeLanguageModel` (32K context + reasoning levels, free at
  our scale, also on watchOS 27) fits weeks of raw event history, enabling real
  trend analysis ("night stretches lengthening ~20 min/week") the 8K digest
  can't. Build as a new opt-in weekly card, keeping on-device as the default
  for the daily cards. It changes the privacy story, so the same PR must update
  every "nothing leaves the device" statement: `BabyIntelligence.swift`'s doc
  comment, the AI Features toggle copy in
  `TwoOfUs/Features/Settings/FeedingSettingsView.swift` ("Everything is
  computed on your iPhone — nothing about … leaves your device"), the
  "Generated on-device" caption in `StatsView`, `docs/AI-PREDICTIONS.md`'s
  Privacy and PCC sections, `docs/PRIVACY.md`, and
  `docs/APP_PRIVACY_ANSWERS.md`. Testing note: iOS 27.0 fixed PCC not working
  in the simulator (iOS 27 release notes, 177684296), so this is testable
  without a device.
- **Skip third-party providers.** The `LanguageModel` protocol makes Claude or
  Gemini drop-in, but they need API keys, billing, and a privacy story; Apple's
  free models cover our needs. Revisit only if a chat feature (§5) outgrows AFM.
- **Guardrail check:** re-run the existing summary/outlook QA — session 241
  notes refined guardrails; infant feeding/sleep content occasionally trips
  false-positive safety refusals today, worth re-testing on AFM 3.

No new entitlements or Info.plist keys surfaced for any of this (none found in
release notes — the adapter entitlement only applies to custom LoRA adapters,
which we don't use).

## 4. Priority 2 — Siri and App Intents

The new Siri resolves our existing intents conversationally without work on our
side, but three iOS 27 APIs fit this app unusually well. **Done 2026-09-18
(`ios27-features`):** `CareEventEntity` in `TwoOfUs/Intents/CareEventEntity.swift`
covers the first three, `SpotlightIndexer` keeps the last 30 days indexed,
`LastFeedIntent`/`LastDiaperIntent` return the entity, `CareEventQuery` is
also an `EntityPropertyQuery` (Shortcuts "Find Care Events" with
kind/time/amount/logger filters), and the timeline rows carry
`.appEntityIdentifier` for Siri's onscreen awareness.

- **`IndexedEntity` + `IndexedEntityQuery`** on Feed/Sleep/Diaper/Note events:
  makes them Spotlight-semantically searchable and lets Siri resolve "when did
  Miller last have a dirty diaper" against the real store instead of our
  hand-rolled query intents. Our `QueryIntents.swift` answers stay as the
  dialog layer. *(Done — one `CareEventEntity` with a `kind`, reindexed
  after every local write and every applied sync batch, coalesced.)*
- **`SyncableEntity`** — stable cross-device entity identity for CloudKit-synced
  records. Our events already have stable IDs synced via CKSyncEngine; adopting
  this tells the system two phones (and the watch) are seeing the same entity.
  Low effort, future-proofs Siri/Shortcuts references to events. *(Done — it
  is a marker protocol in the shipped SDK, no requirements.)*
- **`OwnershipProvidingEntity`** — declares shared ownership so Siri's
  confirmation language is right for two people editing the same data. Directly
  matches our model. *(Done — `.shared`.)*
- **AppIntentsTesting framework** — our intents currently have zero automated
  coverage (they're excluded from `TwoOfUsTests`). This exercises real
  Siri/Shortcuts pathways headlessly; add a small suite to `make test`.
  *(Open — the shipped framework is definition/introspection-shaped
  (`IntentDefinitions`, `AppEntityDefinition`, `AnyEntityQuery`); needs a
  session with the WWDC26 295 sample before it's worth adopting.)*
- **`ShowsSnippetView`** — port `ConfirmationSnippet` to snippet-view results so
  Siri confirmations show the app-styled card. *(Already the case — the log
  intents have returned `ShowsSnippetView` since iOS 26; nothing to do.)*

Skip: App Schemas (`@AppEntity(schema:)`) — the system schema catalog (messages,
photos, etc.) has no baby-tracking domain; our custom entities are the right
shape already. `LongRunningIntent`/`CancellableIntent` — nothing we do takes 30s.

Update `docs/SIRI_AND_SHORTCUTS.md` once this lands: the "things you can say"
list loosens considerably under LLM Siri (natural phrasing, no more rigid
"…in Two of Us" suffixes in many cases) — re-test and re-document actual behavior.

## 5. Priority 2 — Update the AI docs, decide on chat

- **`docs/AI-PREDICTIONS.md`** — the deterministic math stays primary (fast,
  explainable, offline; `PREDICTION-MATH.md`'s recency-weighted blend is the
  right foundation and nothing in iOS 27 replaces it — there is still no
  dedicated Apple time-series/forecasting API; guided generation over
  structured digests plus tool calling is Apple's recommended shape, session
  242). Edits needed: replace the "Private Cloud Compute — not applicable"
  section with the §3 design, revise the Privacy section and Settings copy,
  and add the `PredictionAccuracy`-style validation idea for narrative
  quality (does the PCC weekly card say anything the accuracy card
  contradicts?).
- **`docs/PREDICTION-MATH.md`** — no iOS 27 impact. Its open item (the
  on-real-data half-life sweep) is unrelated to this plan.
- **`docs/AI-CHAT-DESIGN.md` — written and shipped as "Ask about Miller"
  (2026-09-18, `ios27-features`).** Decision: Siri covers one-fact questions;
  the chat exists for questions with a *range* in them ("how were the nights
  this week"). Deliberately narrow: on-device only, one tool
  (`CareEventsTool`, kind + days → event lines), no streaming, no writes.
  `SpotlightSearchTool` and PCC escalation for long spans are listed there
  as follow-ups, not v1.

## 6. Xcode Cloud and toolchain migration

### Where Xcode Cloud actually stands (read from App Store Connect, 2026-09-18)

- **Xcode 27 is already live on Xcode Cloud, and both workflows resolve to
  it.** Apple's
  [Xcode Cloud release notes](https://developer.apple.com/xcode-cloud/release-notes)
  still have no Xcode 27 entry (newest toolchain entry: Xcode 26.2), but the
  workflow editor is the ground truth: "Default" and "App Store Release" are
  both on **Xcode Version: Latest Release — Currently Xcode 27 (27A266a)** and
  **macOS Version: Latest Release — Currently macOS 27 (26A428)**. The picker
  offers: *Latest Beta or Release* (currently Xcode 27.2 beta, 27B5019j),
  *Latest Release* (Xcode 27, 27A266a), and released versions Xcode 27
  (27A266a), 26.6 (17F113), 26.5 (17F42), 26.4.1 (17E202).
- **No build has run on 27 yet.** The last Default build is #142 on 2026-08-27
  (the PR #183 merge); `main` hasn't been pushed since. So **the next merge to
  `main` is the first Xcode 27 archive**, which is why this PR carries the
  `@State` fix (below) rather than deferring it.
- **Pinning:** not needed right now — "Latest Release" already equals the
  version we'd pin to. Apple only flips it to *releases* (27.1 is due late
  September for iPhone Duo). Leave it; if a 27.x point release ever breaks
  the archive, select "Xcode 27 (27A266a)" from the picker (it stays listed)
  and unpin once fixed. The earlier idea of pinning ahead of time is
  withdrawn.
- **Both workflows have "Clean" enabled** (no derived-data cache restore).
  Every build is a clean build anyway, so there's no cache-invalidation risk
  from the toolchain change — just the usual ~15–20 min.
- **Local Mac readiness:** the Mac mini is on macOS 27.0 (Xcode 27 needs
  26.6+ ✓, Apple silicon ✓), has Xcode 26.4 installed (4.8 GB) and 63 GB free,
  no `xcodes`/`mas` helper. Installing Xcode 27 side-by-side is ~15 GB with
  the iOS 27 + watchOS 27 simulator runtimes. `xcrun simctl` currently hangs
  on this machine (CoreSimulator wedged) — restart the service or reboot
  before running `make test` on 27.

### Checklist

1. **`@State` macro compile audit — done, fix in this PR.** Apple's rule
   (iOS 27 release notes, 78212597): a `@State` with a declaration-site
   initial value that `init` also assigns no longer compiles (and the init
   value would be discarded). On `main` there are 35 `_x = State(initialValue:)`
   sites in six files (`EditEventSheet` 25, `OnboardingView` 5,
   `SnooSuggestionCard` 2, `TwoOfUsApp`, `SnooLoginSheet`,
   `SleepStartEditSheet` 1 each); 32 are on un-initialized declarations and
   are fine. The three that matched the break were all in
   `OnboardingView.swift` (`page = .tour`, `babyName = ""`, `ownerName = ""`)
   — the `page` one would have failed the Release archive, the other two only
   Debug (`-autoFinish` path). Fixed by dropping the declaration-site values
   and assigning once in `init`; verified building on Xcode 26.4, and
   **build #143 (Xcode 27, 2026-09-18) archived green**, which settles the
   first open question: `_x = State(initialValue:)` in `init` is accepted by
   the macro, no mechanical rewrite needed. Still to eyeball on device:
   `TwoOfUsApp.demoContainer` (`ModelContainer?` assigned conditionally in
   `init`) — an implicit-nil optional may count as "has an initial value", in
   which case the assignment is silently discarded. Degrades gracefully
   (`configure()` rebuilds the demo store one frame later), but check demo
   mode's cold launch for a flash of real data.
2. **27-SDK behavior gates to test, not fix:** three `TabView(selection:)`
   sites (`RootView`, `OnboardingView`, `JoinFlowView`) — the 27 SDK crashes
   if selection points at a hidden tab; none hide tabs today, so this is a
   smoke-test item. No `textSelection(.enabled)`, `-ld64`, or `-ld_classic`
   usage in the project; no `ToolbarContentBuilder`/`CommandsBuilder`.
3. **Build #143 — done.** PR #185 merged 2026-09-18 21:25 CDT and the Default
   workflow archived it on Xcode 27 (27A266a) successfully. What's left is
   the TestFlight soak on both phones and the watch: sync, widgets, Live
   Activity, Siri phrases, notification content extension, complications.
   Fallback if a later 27.x build breaks: pin Default to Xcode 26.6 (17F113)
   from the picker and fix forward.
4. **Local toolchain — Xcode 27.0 installed 2026-09-18** via the Mac App
   Store update (replaces 26.4 in place; `mas upgrade` needs `sudo`, so the
   click happens in the App Store app). Still owed: the iOS 27 and watchOS 27
   simulator runtimes (`xcodebuild -downloadPlatform iOS` / `watchOS`), then
   `make test` with `SIMULATOR` pointed at an iOS 27 device and the
   `docs/DEVICE_TEST_MATRIX.md` screenshot flows. Blocker found on the way:
   every `simctl` invocation on the mini hangs indefinitely (even `simctl
   help`, even invoked directly and after killing CoreSimulatorService —
   `xcrun` itself is fine), which means no simulator tests until the Mac is
   rebooted. Builds against `generic/platform=iOS Simulator` still work.
5. **`ci_scripts/ci_post_clone.sh`** — no changes needed. XcodeGen via brew and
   the `CURRENT_PROJECT_VERSION` stamping are toolchain-independent. Only risk
   is an XcodeGen release lagging a project-format change; pin the brew formula
   only if a failure actually shows up.
6. **No new build settings, entitlements, or capabilities** are required for
   Foundation Models, the new Siri, or the Live Activity family work — verified
   against the Xcode 27 / iOS 27 release notes (nothing surfaced). The existing
   App ID capability rule from `docs/XCODE_CLOUD.md` (register capabilities
   before archiving when adding a target) still applies to any new target.
7. **Deployment target: hold at 26.0, bump to 27.0 deliberately.** Two users,
   both on Apple-Intelligence-capable phones; bump `project.yml`'s
   `deploymentTarget` on all seven targets (iOS *and* watchOS) to `27.0` in
   the same PR as the first feature that actually requires a 27-only API
   (§3's PCC model or §4's entity protocols), after confirming both phones
   and the watch run 27. The `@State` macro and most SwiftUI additions don't
   force the bump (macro back-deploys to 17). No SwiftData/CloudKit migration
   implications — schema stays additive-only per the standing rule.
8. **App Store lane.** Tag `v1.x` for the App Store Release workflow only
   after the TestFlight soak, per the existing release convention; that
   workflow is on the same "Latest Release" → 27 resolution, so the tagged
   build will be 27-SDK and satisfies the April 2027 rule.

## 7. Sequencing and estimates

| Order | Work | Estimate |
|---|---|---|
| 1 | Merge this PR → build #143 on Xcode 27 → TestFlight soak (§6.1–3) | 0.5 day + soak |
| 2 | Xcode 27 local install + sim runtimes (§6.4) | 0.5 day |
| 3 | Live Activity small family + landscape DI (§2) | 0.5 day |
| 4 | Foundation Models: token accounting + AFM 3 QA re-run (§3) | 0.5 day |
| 5 | PCC weekly-pattern card + all privacy copy/doc updates (§3, approved) | 1–2 days |
| 6 | App Intents: Indexed/Syncable/Ownership entities + snippet views + AppIntentsTesting (§4) | 2–3 days |
| 7 | Update AI-PREDICTIONS.md; write AI-CHAT-DESIGN.md; prototype chat only if Siri leaves a gap (§5) | 1 day docs; chat TBD |
| 8 | Deployment target bump to 27.0 riding whichever feature needs it first (§6.7) | folded in |

Total: roughly **6–9 working days** spread over the fall, with the only hard
date being iOS 27 SDK uploads by **April 2027** — which build #143 already
satisfies. Items 1–3 are a comfortable single week.

## Doc updates this plan implies

- `docs/XCODE_CLOUD.md` — Xcode 27 note (done in this PR)
- `docs/AI-PREDICTIONS.md` — PCC section, Privacy section, Settings copy (§3/§5)
- `docs/SIRI_AND_SHORTCUTS.md` — re-test phrases under LLM Siri, rewrite list
- `docs/PRIVACY.md` + `docs/APP_PRIVACY_ANSWERS.md` — with the PCC card
- New: `docs/AI-CHAT-DESIGN.md` (§5)
