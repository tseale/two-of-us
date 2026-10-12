# iOS 27 best-in-class plan

An audit of the whole app (every target, every screen, all 30+ docs) against
what iOS 27 actually offers, written 2026-09-19 — five days after iOS 27
shipped and one day after build #144 archived green on Xcode 27. The question
this answers: **why doesn't the app *feel* like iOS 27 yet, and what would
make Apple's design-award judges call it the reference baby-tracking app?**

Companion to `docs/IOS-27-UPGRADE-PLAN.md` (the toolchain/API migration, most
of which is done). This doc is about the experience. Standing decisions it
respects: **no in-app chat** (decided 2026-09-18 — Siri covers it), no
third-party LLM providers, no App Schemas, deployment target bumps to 27.0
only with the first 27-only requirement.

## 0. Why you aren't "seeing" iOS 27

The uncomfortable truth first: **most of what shipped in PRs #185/#186 is
invisible by design**, and the one headline feature is switched off.

| What landed | Why you can't see it |
|---|---|
| PCC weekly-patterns card (`AI/BabyIntelligence.swift:144`, `StatsView.swift:340`) | **Dormant.** `TOUPrivateCloudComputeEnabled: NO` (`project.yml:55`) because Apple's managed entitlement `com.apple.developer.private-cloud-compute` hasn't been granted — FoundationModels *traps* without it. The request form is the single highest-leverage unblocking action, and it's an owner task: <https://developer.apple.com/contact/request/private-cloud-compute/> |
| Spotlight care-event entities, `SyncableEntity`, `OwnershipProvidingEntity`, `EntityPropertyQuery` | Plumbing. Visible only when you search Spotlight for "feed", ask Siri about Miller, or build a Find Care Events shortcut — nothing announces it. |
| Live Activity `.small` family + landscape Dynamic Island | Only appears on the Watch Smart Stack / CarPlay **while a sleep is running**, and only on devices running the new build. |
| Token accounting, `@State` macro fix, entity-linked feed alarm | Genuinely invisible (logs, correctness, Siri metadata). |
| AI cards (Insights / Outlook) | They **vanish silently** when the model is unavailable or data is thin (`BabyIntelligence` returns `nil` on every failure) — so on a bad day the app shows *less* intelligence, with no explanation. |

The app's own UI meanwhile hasn't adopted any iOS 27 *interaction* surface —
no reorderable containers, no new toolbar behaviors, no chart interactivity,
haptics still go through UIKit generators. That's the actual gap between
"technically on iOS 27" and "feels like iOS 27," and it's what §2–§6 fix.

## 1. Where the app already is (credit where due)

The foundation is unusually strong — this is a polish-and-surface plan, not a
rebuild:

- 7 targets, all deployment 26.0, archiving green on Xcode 27 (build #144).
- Foundation Models in production since August (on-device Insights + Outlook
  cards, availability-gated, family kill-switch synced via CloudKit).
- Champion/challenger prediction stack with walk-forward accuracy gating
  (`PredictionArbiter` — a model's number only surfaces while it *provably*
  beats the statistic on Miller's own history). This is the most
  award-narrative-worthy thing in the app: **honest AI**.
- 9 App Shortcuts, interactive widgets, Control Center controls, Focus
  filter, communication notifications with the co-parent's face, AlarmKit
  alarms with entity links, an independent watch app with 8 complications,
  hand-rolled CKSyncEngine sync that survived a ghost-entry war.
- A real design system with documented glass discipline ("glass floats,
  surfaces sit"), a night palette, urgency encoded in shape + word (never
  color alone), Reduce Motion respected in 13 places.

## 2. Priority 1 — Turn the intelligence lights on (≈3 days + Apple's clock)

### 2a. PCC entitlement (owner action, 10 minutes + wait)
Submit the request form. The turn-on runbook already exists
(`docs/XCODE_CLOUD.md:126-134`): entitlement granted → App ID capability in
the portal → `TwoOfUs.entitlements` + flag flip in one PR. **This PR also
bumps deployment target to 27.0 on all seven targets** per the standing rule —
PCC is the first true 27-only requirement. Everything below in §2 can ship
before the grant arrives.

### 2b. A visible "intelligence unavailable" state (0.5 day)
Today `BabyIntelligence` failures return `nil` and cards evaporate. Add one
graceful state: when `SystemLanguageModel.default.availability` is
`.unavailable(reason:)` and the AI toggle is on, Stats shows a single quiet
line ("Insights need Apple Intelligence — it's off on this iPhone") instead
of nothing. Map the three `UnavailableReason` cases to copy. Never show it
when the family toggle is off. Also wire the currently-dead
`BabyIntelligence.isCloudAvailable` (`AI/BabyIntelligence.swift:135`) into
`StatsView.loadWeeklyPatterns` as the cheap pre-flight, or delete it.

### 2c. `@Generable` + streaming for the daily cards (1 day)
The two on-device cards still parse free text. Move `summary`/`outlook` to
guided generation (`respond(to:generating:)`) with small `@Generable` structs
— same pattern `WeeklyPatterns` already uses — and stream via
`streamResponse` so the card paints progressively instead of popping in after
~2 s. Reuse one prewarmed `LanguageModelSession` per foreground session
instead of a fresh session per call (`session.prewarm()` after Stats appears;
the current code builds a new session every generation).

### 2d. AFM 3 guardrail QA (0.5 day)
Re-run the summary/outlook QA prompts on the AFM 3 Core model — infant
feeding/sleep content occasionally tripped false-positive safety refusals on
AFM 2. Log refusal rate via `AppLog.ai` for a week of real use.

### 2e. Resolve PR #184 (0.5 day decision + rebase)
The open AskEngine PR predates #186 and overlaps it (semantic indexing).
Salvage the part #186 didn't ship — `GetStatIntent` aggregate answers
("how many ounces this week") as a Siri/Shortcuts surface riding the same
`AskEngine` — and drop the rest. It's the last piece of "ask Siri anything
about Miller" and it's already written and tested.

## 3. Priority 2 — Make it feel like iOS 27 (≈4 days)

### 3a. Swift Charts: from posters to instruments (1.5 days)
All five History charts are static 7-day snapshots (`HistoryView.swift:100,
147, 184, 222, 271`). Adopt, per chart:
- `chartXSelection(value:)` — tap a bar/day to see exact numbers in a small
  annotation (the same numbers VoiceOver will speak, §5).
- `chartScrollableAxes(.horizontal)` + `chartXVisibleDomain(length:)` +
  `chartScrollTargetBehavior(.valueAligned)` — the 7-day window becomes the
  *visible* window over Miller's whole history; scrub back to week one.
- Extract chart content into `@ChartContentBuilder` functions (also dodges
  the Xcode 27 type-check slowdown for deployment targets below 27).
This single item does more for "the app grew up" than anything else in §3 —
the data's been accumulating since June and none of it is reachable.

### 3b. Liquid Glass 27 audit (1 day)
iOS 27 refined glass (darkened edges, brighter speculars, better diffusion)
and **added a user transparency slider** — the app must stay legible at both
extremes. Work: replace the two `.regularMaterial` holdouts
(`RootView.swift:141, 162`) with glass or `surfaceCard`; give the Wake-up
button (`SleepActiveCard.swift:108`) `buttonStyle(.glass)`; adopt
`scrollEdgeEffectStyle` under the Home header; delete the never-called
`glassCard` helper (`Colors.swift:108`) or start using it; re-screenshot
`docs/DEVICE_TEST_MATRIX.md` flows at min/max transparency, both appearances.
The "glass floats, surfaces sit" contract in `docs/DESIGN.md` survives — this
is tuning, not rethinking.

### 3c. Motion + haptics to the SwiftUI idiom (1 day)
- Replace the 47 UIKit `Haptics.tap/success/warning` call sites with
  `.sensoryFeedback(_:trigger:)` — one mechanical sweep; it also makes the
  system honor the user's haptics settings for free. Keep `Haptics` as a thin
  shim for the few non-view call sites.
- `contentTransition(.numericText())` on the glance values that tick (Home
  tile time-since, active-sleep timer label, Stats lifetime tiles).
- One `symbolEffect(.bounce)` on the tile glyph when a log lands — the
  confirmation moment, nowhere else. The brand is calm; resist more.

### 3d. Reorderable Home tiles (0.5 day)
iOS 27's reorderable-container API, applied to the one place parents would
use it: the Feed/Diaper/Sleep tile order on Home (persist in `LocalPrefs`).
Whichever tracker *your* baby uses most sits under your thumb. (The API also
works on watchOS now — same preference syncs to the watch row order later,
via the App Group.)

### 3e. Modernize presentation patterns (0.5 day, opportunistic)
Item-binding `confirmationDialog`/`alert` (new in 27) can replace the six
hand-rolled `Binding(get:set:)` dances in `PeopleSettingsView` /
`ManageDataSections`. Do it when touching those files for §5; don't make it
its own pass.

## 4. Priority 3 — Everywhere Miller's rhythm matters (≈3 days)

### 4a. CarPlay widget (0.5 day + device verification)
iOS 27 opens CarPlay to third-party widgets. `NextFeedGaugeWidget` and
`LastFeedWidget` are exactly what a driving parent wants. Verify family
support and legibility in the CarPlay simulator (widgets render
monochrome-tinted there like lock screen — shape/position already carry the
meaning per `docs/VISUALIZATIONS.md:24`).

### 4b. Smart Stack relevance done properly (0.5 day)
Widgets ship score-only relevance (`WidgetProvider.swift:45-55`). Adopt
`RelevantContext.date(interval:)` from the night schedule: during *your*
assigned slot, the feed widget should be the top of the Smart Stack on phone
and watch. The schedule engine already computes the intervals
(`ScheduleEngine` is compiled into the complication target today).

### 4c. Watch complications: relevance + one interaction (1 day)
All 8 complications are read-only with no relevance hints. Add
`RelevantContext` (same night-slot intervals) and make the sleep complication
interactive with `Button(intent: SetSleepIntent…)` — the wrist is where you
are when you put a baby down. Foundation Models now runs on watchOS 27; a
glanceable AI summary on the wrist is *possible* but adds little over the
phone card — skip it deliberately, note it in the doc.

### 4d. Live Activity: sleep-stretch progress ring (0.5 day)
Idea #8 from `docs/LIVE-ACTIVITY-IDEAS.md` — `ProgressView(timerInterval:)`
against `predictedWakeAt` (already in `ContentState`). Self-ticking, no
pushes, and it puts the prediction stack's output on the lock screen. Respect
the #7 decision: no buttons return; the ring replaces the moon's halo, not
the layout.

### 4e. Live Activity push-to-start — document, don't build
A co-parent's sleep still can't light this phone's lock screen (no push
server, `SleepActivityManager.swift:182-187`). ActivityKit push-to-start
needs real APNs infrastructure; for a two-phone household the foreground
reconcile is the right trade. Keep the limitation written down, revisit only
if Apple ever offers CloudKit-brokered activity starts.

### 4f. Widget configurability (0.5 day)
`AppIntentConfiguration` on the small event widget: let each parent choose
which tracker their lock screen shows. Cheap personalization; the intent
enum already exists (`CareEventKind`).

## 5. Priority 4 — Inclusivity as a first-class feature (≈4 days)

This is the weakest area relative to award standards, and the audit was
blunt: **five charts with zero accessibility representation, 16 view files
with zero accessibility API calls, every box in
`docs/ACCESSIBILITY_CHECKLIST.md` unchecked.**

- **Charts (1.5 days):** `accessibilityChartDescriptor` (`AXChartDescriptor`
  + `AXDataSeriesDescriptor`) on all five History charts → VoiceOver audio
  graphs; per-mark `accessibilityLabel`/`accessibilityValue` as the fallback;
  labels on the two bare `GeometryReader` split bars in Stats
  (`StatsView.swift:534, 674`). The §3a selection annotations and these
  descriptors should read the same numbers — one formatter, two outputs.
- **The 16 silent files (1.5 days):** priority order — `SettingsView` shell
  + `SettingsIconLabel`, `ManageDataSections` (the delete-everything gauntlet
  *must* be navigable), `NotificationSettingsView`, `SnooSettingsSection`,
  `BabyEditSheet`/`ProfileEditSheet`, `SnooLoginSheet`, `WrappedView` (one
  composed summary label for the share card).
- **Dynamic Type (1 day):** the deliberate 1.6× cap (`Typography.swift:44`)
  is defensible for glance values, but AX sizes currently *scale down* via 14
  `minimumScaleFactor` sites instead of reflowing. Add `ViewThatFits`
  fallbacks on Home tiles and Stats tiles (the onboarding bento already
  models the pattern), replace the two 9 pt floors (`HomeView.swift:674`,
  `SleepLaneColumn.swift:106`), adopt `@ScaledMetric` for the hand-tuned
  paddings that break at AX3+.
- **Run the checklist (0.5 day)** — Accessibility Inspector per screen, dark
  AA on amber/red, and *extend it* to the surfaces it currently ignores:
  widgets, complications, Live Activity, Siri snippets.
- **App Store:** fill in the Accessibility Nutrition Label with what's then
  true. iOS 27's system features (VoiceOver Image Explorer, Accessibility
  Reader, auto-captions) need nothing from the app but benefit from the
  labels above.

## 6. Priority 5 — Platform hygiene (background, no deadline pressure)

- **SwiftData 27:** `HistoryObserver` (filtered by model type + transaction
  author) can replace the hand-wired "reindex Spotlight + reconcile Live
  Activity after every applied sync batch" calls in `SyncManager`/`EventStore`
  with one observation point; `@Query(sectionBy:)` simplifies the timeline's
  day sectioning. Cleanup-grade, do when touching those files.
- **Swift 6 language mode:** all seven targets still declare
  `SWIFT_VERSION: "5.0"` while the code is already actor/`@MainActor`/
  `Sendable`-disciplined. Flip target-by-target (tests first) — likely days,
  not weeks, and it hardens the sync layer.
- **Dead branches:** the iOS 18 availability gates in the widget target
  (`LogControls.swift`, `TwoOfUsWidgets.swift:18`) are unreachable at
  deployment 26.0 — removed in this PR.
- **AppIntentsTesting:** re-evaluate once there's a worked sample; the
  shipped framework is introspection-shaped and the intents remain untested
  (`IOS-27-UPGRADE-PLAN.md` §4).
- **Xcode Cloud: no changes required.** Both workflows already resolve to
  Xcode 27; the April 2027 SDK rule is satisfied since build #143. The only
  future change is the PCC entitlement runbook (§2a), which touches the App
  ID, `project.yml`, and entitlements in one PR. Keep `MARKETING_VERSION` in
  sync when the App Store tag rides one of these builds.

## 7. Phased rollout

| Phase | Contents | Effort | Ships as |
|---|---|---|---|
| 0 — now | This doc + quick wins (pronoun fixes, slot-reminder rich cards, dead gates, doc drift) | done in this PR | next `main` merge |
| 1 — "Feel" | §3a charts, §3b glass audit, §3c motion/haptics, §3d reorderable tiles | ~4 days | one TestFlight build, soak on both phones |
| 2 — "Intelligence" | §2b unavailable state, §2c Generable+streaming, §2d QA, §2e PR #184; **§2a flag-flip PR the day the entitlement lands** (+ deployment bump to 27.0) | ~3 days | independent of the grant except the flip |
| 3 — "Everywhere" | §4a CarPlay, §4b/§4c relevance + watch interaction, §4d LA ring, §4f configurability | ~3 days | needs device/CarPlay verification |
| 4 — "Inclusive" | §5 in full, checklist run, nutrition label | ~4 days | gates the next App Store tag |
| ongoing | §6 hygiene | background | opportunistic |

Total ≈ 14 working days of focused work to a genuinely reference-quality iOS
27 app. Phases 1–2 are the perceived transformation; phase 4 is what makes
the award narrative honest.

## 8. The award pitch, for orientation

If Apple wrote the citation, it should be able to say: *predictions that
audit themselves and step aside when they lose; the household's rhythm on
lock screen, wrist, car, and Siri without a single account or server; Private
Cloud Compute analysis with a provable privacy boundary; and a 3 a.m.-calm
design that one-handed, VoiceOver, and AX5 parents can all actually use.*
Everything in this plan serves one of those four clauses — anything that
doesn't (in-app chat, third-party models, more Live Activity buttons) stays
cut.
