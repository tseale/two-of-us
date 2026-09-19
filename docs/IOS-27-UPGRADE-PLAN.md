# iOS 27 upgrade plan

iOS 27 and Xcode 27 shipped 2026-09-14. This is the audit of what actually
changed, what Two of Us should adopt (and in what order), and what has to happen
in Xcode Cloud. Researched 2026-09-18 from Apple's release notes, updates pages,
and WWDC26 sessions — links inline. Facts we could not confirm from an Apple
source are marked **[unverified]**.

## Where we start from

Better than expected. The app is already iOS 26-only (deployment target `26.0`
on every target), already ships a Foundation Models integration
(`TwoOfUs/AI/BabyIntelligence.swift` powering the Stats summary card), a full
App Intents surface (log/query intents, Controls, Focus filter, Shortcuts), a
sleep Live Activity, and widgets. So this is a one-version hop with no
deprecated-API debt, not a migration.

One correction to the premise this audit started from: the repo has **no**
`docs/AI-PREDICTIONS.md`, `docs/AI-CHAT-DESIGN.md`, or `docs/PREDICTION-MATH.md`
— not in the tree, not in git history. The real prediction/AI artifacts are
`BabyIntelligence.swift`, the feed-interval prediction in
`SharedSettings.feedInterval` / `NightScheduleGenerator` / `Urgency.swift`, and
`docs/SIRI_AND_SHORTCUTS.md`. §5 proposes writing the missing design docs as
part of this work rather than "updating" docs that don't exist.

A second correction: **Live Activities on Watch, Mac, and CarPlay is not new in
iOS 27.** Smart Stack forwarding shipped with iOS 18/watchOS 11; Mac menu bar
and CarPlay Dashboard forwarding shipped with iOS 26
([ActivityKit updates](https://developer.apple.com/documentation/updates/activitykit)).
Our sleep activity has been eligible all along — we just never opted into the
small layout, so whatever those surfaces show today is an auto-shrunk lock-screen
view. iOS 27's actual ActivityKit news is landscape Dynamic Island/StandBy.
Either way, the work in §2 is real and cheap.

## 1. What shipped in iOS 27 / Xcode 27 (the parts that touch us)

| Area | What's new | Relevance |
|---|---|---|
| Foundation Models | `LanguageModel` protocol (any provider can back a session), `PrivateCloudComputeLanguageModel` (32K context, free under 2M downloads), AFM 3 Core on-device model (3B, image understanding), Dynamic Profiles for agentic sessions, `SpotlightSearchTool` local RAG, token accounting APIs — [session 241](https://developer.apple.com/videos/play/wwdc2026/241/), [session 242](https://developer.apple.com/videos/play/wwdc2026/242/), [AFM 3](https://machinelearning.apple.com/research/introducing-third-generation-of-apple-foundation-models) | High — upgrades the summary card, unlocks pattern analysis and chat |
| Siri / App Intents | LLM-backed Siri (App Intents is the only integration path; SiriKit deprecated **[unverified — secondary sources only]**), App Schemas, `IndexedEntity`/`IndexedEntityQuery`, `SyncableEntity`, `OwnershipProvidingEntity`, `ShowsSnippetView`, AppIntentsTesting framework — [session 343](https://developer.apple.com/videos/play/wwdc2026/343/), [session 345](https://developer.apple.com/videos/play/wwdc2026/345/) | High — our intents get smarter Siri handling mostly for free; entity APIs map directly onto our synced events |
| ActivityKit | Landscape Dynamic Island + `\.isDynamicIslandLimitedInWidth`; `.supplementalActivityFamilies([.small])` (pre-27, unadopted by us) — [session 223](https://developer.apple.com/videos/play/wwdc2026/223/) | Medium — small-family layout is the missing piece for Watch/CarPlay |
| SwiftUI | `@State` is a macro (once-per-lifetime init, back-deploys to iOS 17, **source-compat breaks**), reorderable containers, swipe actions outside `List`, `@ContentBuilder`, toolbar additions, `Tab(role: .prominent)` — [SwiftUI updates](https://developer.apple.com/documentation/updates/swiftui), [iOS 27 release notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes) | Medium — mostly free wins plus a required compile audit |
| SwiftData | `@Query(sectionBy:)`, `.codable` attribute option, `ResultsObserver`, `HistoryObserver` (observe remote changes) — [SwiftData updates](https://developer.apple.com/documentation/updates/swiftdata) | Medium — `HistoryObserver` is interesting for sync-driven UI refresh |
| CloudKit | Effectively nothing: no WWDC26 session, no new `CKSyncEngine`/`CKShare` API found; one 27.0 bugfix (self-demoting share administrator now works) | None — hand-rolled sync is unaffected |
| Xcode 27 | Swift 6.4, macOS Tahoe 26.6+ / Apple silicon only, min deployment target iOS 15 (so 26.0 stays fine), `-ld64` now errors — [Xcode 27 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes) | Required — see §6 |
| App Store | **Uploads must use the iOS 27 SDK starting April 2027** — [Apple news](https://developer.apple.com/news/?id=k1mtkt1k) | Hard deadline for the whole plan |

Not relevant to us: Core AI framework (custom-model deployment — overkill), the
new Document APIs (`FileDocument` deprecation doesn't apply; we have no document
types), iPhone Duo hinge APIs, Metal/visionOS Xcode Cloud support.

## 2. Priority 1 — Live Activity small family (Watch Smart Stack + CarPlay)

The sleep Live Activity (`TwoOfUsWidgets/SleepLiveActivityView.swift`) declares
only the standard lock-screen and Dynamic Island presentations. Work:

1. Add `.supplementalActivityFamilies([.small])` to the `ActivityConfiguration`.
2. Branch on `@Environment(\.activityFamily)` and build a dedicated `.small`
   layout: moon glyph + `Text(startedAt, style: .timer)` + baby name, nothing
   else. The Wake button (`Button(intent:)` with `SetSleepIntent`) works on
   Watch — keep it if it fits, drop it if cramped.
3. Handle `\.isDynamicIslandLimitedInWidth` in the compact/minimal Dynamic
   Island views for landscape (iOS 27).
4. Verify in Xcode 27's Preview Snapshot tooling (it renders Live Activity
   states) plus a paired Watch simulator.

No Info.plist or entitlement changes — `NSSupportsLiveActivities: YES` already
covers it. Mac menu bar and CarPlay forwarding are automatic. Estimated ~half a
day including testing. This is the single best effort-to-value item in the
plan: sleep timer on the wrist while holding the baby is exactly this app's
use case.

## 3. Priority 1 — Foundation Models upgrades

`BabyIntelligence` today: availability-gated `SystemLanguageModel.default`
session, pre-computed stats digest in, 2–3 sentence summary out. iOS 27 changes
worth taking, in order:

- **Keep the on-device default.** AFM 3 Core is a straight quality upgrade to
  the existing summary card — zero code change. The 8,192-token context is
  ample for the digest approach.
- **Adopt token accounting** (`model.contextSize`, `tokenCount(for:)`,
  `response.usage`) to size the digest defensively instead of hoping, and log
  usage via `AppLog.ai`.
- **Weekly pattern analysis as a new, opt-in card** using
  `PrivateCloudComputeLanguageModel` (32K context + reasoning levels, free at
  our scale, watchOS 27 too). 32K comfortably fits weeks of raw event history,
  enabling real trend analysis ("night stretches lengthening ~20 min/week")
  the 8K digest can't. **Decided 2026-09-18: PCC is approved.** It still
  changes `BabyIntelligence`'s documented "nothing about your baby ever leaves
  the device" promise, so the build must: keep on-device as the default for the
  daily summary, label the weekly card as using Apple's Private Cloud Compute,
  update the doc comment, `docs/PRIVACY.md`, and the App Store privacy answers
  (`docs/APP_PRIVACY_ANSWERS.md`). Testing note: iOS 27.0 fixed PCC not working
  in the simulator (iOS 27 release notes, 177684296), so this is testable
  without a device.
- **Skip third-party providers.** The `LanguageModel` protocol makes Claude or
  Gemini drop-in, but they need API keys, billing, and a privacy story; Apple's
  free models cover our needs. Revisit only if a chat feature (§5) outgrows AFM.
- **Guardrail check:** re-run the existing summary QA — session 241 notes
  refined guardrails; infant feeding/sleep content occasionally trips
  false-positive safety refusals today, worth re-testing on AFM 3.

No new entitlements or Info.plist keys surfaced for any of this (none found in
release notes — the adapter entitlement only applies to custom LoRA adapters,
which we don't use).

## 4. Priority 2 — Siri and App Intents

The new Siri resolves our existing intents conversationally without work on our
side, but three iOS 27 APIs fit this app unusually well:

- **`IndexedEntity` + `IndexedEntityQuery`** on Feed/Sleep/Diaper/Note events:
  makes them Spotlight-semantically searchable and lets Siri resolve "when did
  Miller last have a dirty diaper" against the real store instead of our
  hand-rolled query intents. Our `QueryIntents.swift` answers stay as the
  dialog layer.
- **`SyncableEntity`** — stable cross-device entity identity for CloudKit-synced
  records. Our events already have stable IDs synced via CKSyncEngine; adopting
  this tells the system two phones are seeing the same entity. Low effort,
  future-proofs Siri/Shortcuts references to events.
- **`OwnershipProvidingEntity`** — declares shared ownership so Siri's
  confirmation language is right for two people editing the same data. Directly
  matches our model.
- **AppIntentsTesting framework** — our intents currently have zero automated
  coverage (they're excluded from `TwoOfUsTests`). This exercises real
  Siri/Shortcuts pathways headlessly; add a small suite to `make test`.
- **`ShowsSnippetView`** — port `ConfirmationSnippet` to snippet-view results so
  Siri confirmations show the app-styled card.

Skip: App Schemas (`@AppEntity(schema:)`) — the system schema catalog (messages,
photos, etc.) has no baby-tracking domain; our custom entities are the right
shape already. `LongRunningIntent`/`CancellableIntent` — nothing we do takes 30s.

Update `docs/SIRI_AND_SHORTCUTS.md` once this lands: the "things you can say"
list loosens considerably under LLM Siri (natural phrasing, no more rigid
"…in Two of Us" suffixes in many cases) — re-test and re-document actual behavior.

## 5. Priority 2 — Write the missing AI design docs (predictions + chat)

Since `AI-PREDICTIONS.md` / `AI-CHAT-DESIGN.md` / `PREDICTION-MATH.md` don't
exist, write them now against the iOS 27 reality rather than retrofitting:

- **`docs/AI-PREDICTIONS.md`** — deterministic math stays primary (the
  current recency-weighted interval logic in `SharedSettings.feedInterval` +
  `NightScheduleGenerator` is fast, explainable, offline). Foundation Models'
  role is *narrating* predictions and spotting multi-signal patterns, not
  replacing the math: on-device AFM 3 for the daily digest, PCC (if the §3
  privacy decision allows) for weekly trends. There is no dedicated Apple
  time-series/forecasting API in iOS 27 — guided generation over structured
  digests plus tool calling is Apple's recommended shape (session 242).
- **`docs/AI-CHAT-DESIGN.md`** — decide whether an in-app chat is worth building
  at all now that LLM Siri + our intents cover "ask about Miller" hands-free.
  If yes: `LanguageModelSession` with Dynamic Profiles, tool calling into the
  SwiftData store (a `FetchEventsTool`), `SpotlightSearchTool` for local RAG
  over indexed entities, rolling-window transcript management. Recommendation:
  prototype after §4 lands, because better Siri may make chat redundant for a
  two-person user base.

## 6. Xcode Cloud and toolchain migration

### Where Xcode Cloud actually stands (checked 2026-09-18)

- **Xcode 27 is not on Xcode Cloud yet.** Apple's
  [Xcode Cloud release notes](https://developer.apple.com/xcode-cloud/release-notes)
  have no Xcode 27 / macOS 27 entry; the newest toolchain entry is Xcode 26.2
  (2025-12-19). Historically the GA Xcode lands on Xcode Cloud the same day
  as release — Xcode 16 on 2024-09-16, Xcode 26 on 2025-09-15 — so 27 being
  absent four days after its 2026-09-14 release is a real lag, not the norm.
  There is precedent for the RC being late too
  ([Xcode 26 RC thread](https://developer.apple.com/forums/thread/799883),
  resolved by Apple within days). Expect 27 to appear any day.
- **Both workflows ride "latest released Xcode."** Apple's workflow reference
  says Xcode Cloud "may update available macOS and Xcode versions and
  subsequently ask you to update your workflows." In practice, "latest
  released" flips to 27 on Apple's schedule, not ours — so the first Xcode 27
  archive of this app will happen on whatever `main` push follows that flip.
  That makes the compile audit below a *prerequisite*, not a follow-up.
- **Ground truth is the workflow picker** (ASC → Apps → Two of Us → Xcode Cloud
  → Manage Workflows → Environment) or the API:
  `GET https://api.appstoreconnect.apple.com/v1/ciXcodeVersions` with the
  same key the TestFlight-feedback action uses (`ASC_KEY_ID`/`ASC_ISSUER_ID`/
  `ASC_PRIVATE_KEY`, JWT built like `scripts/testflight_feedback_to_issues.py`).
  Neither was reachable from this session (ASC needs an attended sign-in;
  the key lives only in GitHub secrets) — a 2-minute manual check.
- **Local Mac readiness:** the Mac mini is on macOS 27.0 (Xcode 27 needs
  26.6+ ✓, Apple silicon ✓), has Xcode 26.4 installed (4.8 GB) and 63 GB free,
  no `xcodes`/`mas` helper. Installing Xcode 27 side-by-side is ~15 GB with
  the iOS 27 simulator runtime. `xcrun simctl` currently hangs on this
  machine (CoreSimulator wedged) — restart the service or reboot before
  running `make test` on 27.

### Checklist

Ordered; nothing else in this plan ships to TestFlight before steps 1–4 are
green.

1. **`@State` macro compile audit — done, fix in this PR.** Apple's rule
   (iOS 27 release notes, 78212597): a `@State` with a declaration-site
   initial value that `init` also assigns no longer compiles (and the init
   value would be discarded). The codebase has 36 `_x = State(initialValue:)`
   sites in seven files; 33 are on un-initialized declarations and are fine.
   The three that matched the break were all in `OnboardingView.swift`
   (`page = .tour`, `babyName = ""`, `ownerName = ""`) — the `page` one would
   have failed the Release archive, the other two only Debug (`-autoFinish`
   path). Fixed by dropping the declaration-site values and assigning once in
   `init`; verified building on Xcode 26.4. Two things to confirm on the
   first Xcode 27 build: (a) that `_x = State(initialValue:)` in `init` is
   still accepted by the macro — Apple's own workaround uses plain
   `self.x = …`, and if the underscore form breaks it's a mechanical
   replacement across the 36 sites; (b) `TwoOfUsApp.demoContainer`
   (`ModelContainer?` assigned conditionally in `init`) — an implicit-nil
   optional may count as "has an initial value", in which case the assignment
   is silently discarded. Degrades gracefully (`configure()` rebuilds the
   demo store one frame later), but check demo mode's cold launch for a
   flash of real data.
2. **27-SDK behavior gates to test, not fix:** three `TabView(selection:)`
   sites (`RootView`, `OnboardingView`, `JoinFlowView`) — the 27 SDK crashes
   if selection points at a hidden tab; none hide tabs today, so this is a
   smoke-test item. No `textSelection(.enabled)`, `-ld64`, or `-ld_classic`
   usage in the project; no `ToolbarContentBuilder`/`CommandsBuilder`.
3. **Local toolchain.** Install Xcode 27 alongside 26.4 (keep 26.4 until
   Xcode Cloud has flipped, so local builds match CI). Build, then `make
   test` with `SIMULATOR` pointed at an iOS 27 runtime; re-run the
   `docs/DEVICE_TEST_MATRIX.md` screenshot flows on 27.
4. **Xcode Cloud workflow environment.** Once the picker offers Xcode 27,
   **pin both workflows to that specific 27.x** for the migration build
   rather than riding "latest released" through the 27.0 → 27.1 (iPhone Duo,
   late September) churn; return to "latest released" once a 27 build has
   soaked on TestFlight. If the flip happens before we pin, step 1 is what
   keeps the archive green. Optional hardening: a `workflow_dispatch` GitHub
   Action that hits `ciXcodeVersions` with the existing ASC secrets and
   prints what Xcode Cloud offers, so this check never needs an ASC login.
5. **`ci_scripts/ci_post_clone.sh`** — no changes needed. XcodeGen via brew and
   the `CURRENT_PROJECT_VERSION` stamping are toolchain-independent. Only risk
   is an XcodeGen release lagging a project-format change; pin the brew formula
   only if a failure actually shows up.
6. **No new build settings, entitlements, or capabilities** are required for
   Foundation Models, the new Siri, or the Live Activity family work — verified
   against the Xcode 27 / iOS 27 release notes (nothing surfaced). The existing
   App ID capability rule from `docs/XCODE_CLOUD.md` (register capabilities
   before archiving when adding a target) still applies if we ever add a Watch
   *app* target — not needed for Smart Stack forwarding.
7. **Deployment target: hold at 26.0 for now, bump to 27.0 deliberately.**
   Two users, both on Apple-Intelligence-capable phones; bump `project.yml`'s
   `deploymentTarget` (all five targets) to `27.0` in the same PR as the first
   feature that actually requires a 27-only API (likely §4's entity protocols
   or §3's PCC model), after confirming both phones run iOS 27. `@State` macro
   and most SwiftUI additions don't force the bump (macro back-deploys to 17).
   No SwiftData/CloudKit migration implications — schema stays additive-only
   per the standing rule.
8. **First 27-SDK TestFlight build** — normal `main` merge, then the standard
   soak: sync between both phones, widgets, Live Activity, Siri phrases,
   notification content extension. Tag `v1.x` for the App Store lane only after
   the soak, per the existing release convention.

## 7. Sequencing and estimates

| Order | Work | Estimate |
|---|---|---|
| 1 | `@State` audit (done here) + Xcode 27 local install + sim runtimes (§6.1–3) | 0.5 day |
| 2 | Xcode Cloud environment check/pin + first 27-SDK TestFlight build (§6.4–8) | 0.5 day + soak |
| 3 | Live Activity small family + landscape DI (§2) | 0.5 day |
| 4 | Foundation Models: token accounting + AFM 3 QA re-run (§3) | 0.5 day |
| 5 | PCC weekly-pattern card + privacy doc updates (§3, approved) | 1–2 days |
| 6 | App Intents: Indexed/Syncable/Ownership entities + snippet views + AppIntentsTesting (§4) | 2–3 days |
| 7 | Write AI-PREDICTIONS.md + AI-CHAT-DESIGN.md; prototype chat only if Siri leaves a gap (§5) | 1 day docs; chat TBD |
| 8 | Deployment target bump to 27.0 riding whichever feature needs it first (§6.7) | folded in |

Total: roughly **6–9 working days** spread over the fall, with the only hard
date being iOS 27 SDK uploads by **April 2027**. Items 1–3 are a comfortable
single week and deliver the most visible win (sleep timer on the Watch).

## Doc updates this plan implies

- `docs/XCODE_CLOUD.md` — environment-pinning note and the April 2027 SDK rule
- `docs/SIRI_AND_SHORTCUTS.md` — re-test phrases under LLM Siri, rewrite list
- `docs/PRIVACY.md` + App Store privacy answers — only if PCC is adopted
- New: `docs/AI-PREDICTIONS.md`, `docs/AI-CHAT-DESIGN.md` (§5)
