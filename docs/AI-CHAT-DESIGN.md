# Natural Language Queries — Research & Design

**Status: proposal, rev 3** — written 2026-08-28. Rev 2: target iOS 27 (Taylor
runs the betas; Girl Taylor stays on iOS 26 until she upgrades, and it's fine
if the new capabilities are his-phone-only until then). Rev 3, per Taylor:
**no in-app chatbot at all — maximize what's exposed to Siri and make the
Siri experience best-in-class.** Nothing here is built.

The question this doc answers: how does "what time did he go to sleep last
night?" get answered from the app's own data — now specifically, how much of
the app can Siri see and answer for?

**TL;DR recommendation:** give Siri three kinds of surface area, which
together cover every tier of question:

1. **Indexed entities** — `AppEntity` + `IndexedEntity` for every event and
   note, so the semantic index answers lookups and notes recall natively.
2. **Indexed daily summaries** — the max-exposure trick: index one derived
   `DaySummaryEntity` per day (totals, counts, longest stretch, night wakes,
   bedtime). The semantic index can't do math, so we do the math nightly and
   index the *results* — "how much did he sleep Tuesday?" becomes a lookup.
3. **A full catalog of parameterized read intents** — `GetStatIntent(metric:,
   period:)` over enums, prediction intents, plus free-text `AskTwoOfUsIntent`
   as the catch-all. Siri's model fills `AppEnum` parameters from natural
   phrasing, which sidesteps the free-text-phrase limitation entirely.

Behind the intents: the shared **AskEngine** (deterministic parser +
Foundation Models tool-calling over the query machinery the app already has) —
still the compute layer, now with Siri as its only front-end. No Ask bar, no
in-app chat; the in-app experience stays what it is today (glanceable cards).
Girl Taylor's iOS 26 phone keeps the existing fixed intents plus any new ones
that don't need the index.

**Hard constraint discovered in rev 2:** the **deployment target must stay
iOS 26**. Bumping it to 27 would stop Girl Taylor's phone from installing new
TestFlight builds at all. Everything iOS 27 is `if #available(iOS 27, *)`-gated
polish on top of a 26 baseline — which the codebase already knows how to do.

---

## 1. What's technically feasible

### 1a. Foundation Models framework (iOS 26 — available now, already in the app)

The on-device ~3B model behind Apple Intelligence, exposed to apps via
`LanguageModelSession`. The app already uses it: `AI/BabyIntelligence.swift`
gates on `SystemLanguageModel.default.availability` and generates the Insights
and Outlook cards on Stats from pre-computed digests, with prompts that forbid
the model from inventing numbers.

What we have **not** used yet, and what makes NL queries feasible:

- **Tool calling** (`Tool` protocol). The model can call typed Swift functions
  mid-generation: it reads the question, decides it needs "total sleep last
  night", calls our tool, gets real numbers back, and narrates them. The
  framework runs the loop. This is the load-bearing capability — it means the
  model never does arithmetic and never sees more data than the question needs.
- **`@Generable` guided generation** — type-safe structured output (e.g. parse a
  question into a typed `ParsedQuery` instead of prose).
- **Hard limits**: 4,096-token context (instructions + prompt + tool outputs +
  answer combined), so tool results must be compact digests, not event dumps.
  No world knowledge or real-time data — fine, every answer comes from our
  tools. Requires an Apple Intelligence-capable device (iPhone 15 Pro+) with
  Apple Intelligence enabled; `availability` can be `.unavailable` at any time,
  so every model path needs a non-model fallback.
- **No Private Cloud Compute on iOS 26.** Third-party PCC access was announced
  at WWDC26 for the OS 27 cycle. On-device only for now — which is also the
  privacy story we want ("nothing about Miller leaves the phone" stays true).

### 1b. App Intents + Siri (iOS 26 — the app already ships this)

`Intents/QueryIntents.swift` already answers five questions by voice:
`LastFeedIntent`, `LastDiaperIntent`, `SleepStatusIntent`, `TodaySummaryIntent`,
`UndoLastLogIntent` — fixed phrases, hand-written response sentences, reading
through `QuickLogger` (docs/SIRI_AND_SHORTCUTS.md documents the phrases).

The honest constraint: **on iOS 26 Siri cannot take an arbitrary
natural-language question and route it to an app in one utterance.** App
Shortcut phrases can only interpolate `AppEntity`/`AppEnum` parameters — not
free text (noted in `Intents/TwoOfUsShortcuts.swift`). So "Hey Siri, ask Two of
Us what time he went to sleep last night" is not expressible as a single
phrase. What IS possible:

- More fixed "asking" intents (each covers exactly one question shape, but the
  UX is genuinely one utterance, hands-free).
- One `AskTwoOfUsIntent` with a free-text `@Parameter` — "Hey Siri, ask Two of
  Us" → Siri prompts "What do you want to ask?" → you dictate the question →
  our engine answers and Siri speaks it. Two steps, but fully hands-free and
  covers the entire long tail.
- Constraint to plan around: `TwoOfUsShortcuts.swift` registers 8 of the
  10-shortcut maximum, so only 2 slots are free.

SiriKit (the old framework) is deprecated as of iOS 26; App Intents is the only
path, which is where we already are.

### 1c. iOS 27 (public beta 3 as of Aug 2026, ships ~Sept) — now the target

This is where "ask Siri about Miller" becomes a first-class OS feature:

- **The Siri app.** iOS 27 gives Siri a dedicated app with a chat interface
  and conversation history, powered by Apple Intelligence. This settles the
  chat question: **Apple is shipping the chat UI.** Our job is to make
  Miller's data answerable inside it, not to build a rival chat in-app.
- **`IndexedEntity` semantic indexing**: conforming an `AppEntity` puts it in
  the system semantic index (conformance is close to free —
  `extension FeedEntity: IndexedEntity {}` plus `@Property(indexingKey:)` on
  the searchable fields; the system indexes automatically). Siri can then
  match by meaning and *answer questions over the content* — "when and where
  is my next meeting?"-style. For us that's Tier 1 lookups and, best of all,
  notes recall ("when did we start vitamin D drops?").
- **App Schemas**: entities conformed to a predefined schema
  (`.messages.message` etc.) get Siri's pre-trained understanding with no
  trigger phrases. **There is no baby-tracking schema**, and whether
  non-schema entities get the full question-answering treatment (vs. plain
  semantic retrieval) is genuinely unresolved in the current betas — even
  detailed third-party writeups say so explicitly. Plan: index custom
  entities, test on Taylor's beta phone, and map to a schema only if a
  fitting one appears in the final SDK.
- **What the semantic index will NOT do: math.** It reasons over indexed
  items; nothing suggests it computes aggregates, comparisons, or runs our
  prediction models. "How much sleep this week vs last?" and "when will he
  wake up?" still need our engine — surfaced to Siri as App Intents, which
  the Siri experience can invoke. The index answers "which/when was X";
  AskEngine answers "how much/compared to what/what's next."
- Foundation Models on 27 also gains PCC and third-party model backends
  behind the same API — noted, but on-device remains the right choice here.

**Toolchain reality check (this Mac, 2026-08-28):** Xcode 26.4 with the iOS
26.4 SDK is the only install — `IndexedEntity`/iOS 27 code cannot compile
until the **Xcode 27 beta** is installed. Also, Xcode Cloud workflows must
either move to the beta Xcode or the 27-only code ships after the stable SDK
lands in September. Phase 1 below is deliberately SDK-26-safe so work can
start today.

### 1d. NaturalLanguage framework / Core ML (rule-based parsing)

Viable as a **deterministic fast path and fallback**, not as the whole feature:
a small parser (keyword matching + date phrase resolution) can handle the top
question shapes ("when did he last ___", "how many ___ today/yesterday/this
week") with zero latency and zero device requirements. Full NL understanding by
hand-rolled NLP is a research project we should not attempt — that's what the
Foundation Models layer is for. Core ML custom models: overkill, nothing to
train on.

### 1e. Shortcuts

Parameterized shortcuts already cover custom logging (docs/SIRI_AND_SHORTCUTS.md).
For *queries* they add nothing beyond what App Intents give us directly.

---

## 2. UX comparison — what actually works at 3am

The test case is real: one hand holding a sleeping baby, phone in the other,
dark room, you want one number.

| Surface | Honest assessment |
|---|---|
| **In-app chat bubble** | ❌ **Recommend against — doubly so on iOS 27.** Typing is the worst input mode for this app's core scenario — the whole design is "as few taps as possible" — and the top 10 questions already have zero-tap answers (Home, widgets). On iOS 27 the argument gets terminal: **the Siri app is a system-wide chat with history**; a private in-app clone of it would be strictly worse. Feed the system chat instead of building one. |
| **Siri (voice + the iOS 27 Siri app)** | ✅ **Best for the 3am case and now the primary surface.** Hands-free system Siri for the head of the distribution; the Siri app's chat for typed/threaded questions with history. Indexed entities give lookup answers for free; `AskTwoOfUsIntent` + fixed intents carry the aggregate/predictive questions into the same surfaces. On iOS 26 (Girl Taylor until she upgrades) the existing five fixed intents plus any new ones still work — one-utterance phrase limitations and all. |
| **Ask bar (smart search on History)** | ➖ **Dropped in rev 3.** It was the daytime/analytical answer, but Taylor's call is to route all questioning through Siri — and the Siri app's typed chat covers the "quietly type a question" case the Ask bar existed for. If a gap shows up in practice on iOS 26 (Girl Taylor), the AskEngine is surface-agnostic and an Ask bar can be added later without rework. |
| **Proactive insights** | ✅ **Already the app's direction** — Insights card, Today's outlook, weekly Wrapped, milestones. Best passive UX: the question you didn't have to ask. Extend, don't invent: the same engine's comparative answers ("20% longer than his weekly average") can upgrade existing cards. Never a replacement for on-demand questions, though. |
| **Widget intelligence** | ➖ **Lowest incremental value.** Widgets already answer the top glance questions (time since last feed, countdown, sleep state). "Smart" rotating insight widgets are cute but compete with the countdown for very limited widget real estate. Skip for now. |

The honest overall answer: **most of the value of "ask the app anything" is
already shipped** as glanceable UI, widgets, and five Siri intents. The real
gaps are (a) voice coverage of more question shapes, (b) the analytical tail
that currently requires chart-reading, (c) notes recall ("when did we start
the new formula?"). The design targets those gaps instead of adding a chat
front-end to data that's one glance away.

---

## 3. Recommended approach (rev 3 — everything into Siri)

The design goal restated: **Siri should be able to answer any question the
app itself could answer.** Three exposure mechanisms, because each covers a
question class the others can't:

**A. Indexed raw entities** (`AppEntity` + `IndexedEntity`, iOS 27) —
Feed/Sleep/Diaper/Note entities with `indexingKey` on timestamps, amounts,
type, and note text. Covers Tier 1 lookups ("what time did he go to sleep
last night?", "who did the 3am feed?" — `loggedByName` goes in the display
representation) and Tier 4 notes recall, natively in the Siri app and system
Siri, no intent invocation needed.

**B. Indexed derived summaries** — the semantic index reasons over *items*
but does no arithmetic. So make the arithmetic into items: a
`DaySummaryEntity` per day (total sleep, night sleep, wake count, feed
count/oz, diaper breakdown, longest stretch, bedtime, computed by
`StatsEngine`) and a `WeekSummaryEntity` per week, re-derived whenever the
day's events change (events are append-only soft-delete, so recompute is
cheap and deterministic). This converts a big slice of Tier 2 from "needs an
engine" to "it's in the index": "how much did he sleep Tuesday night?",
"what was his biggest bottle this week?". Cross-summary comparisons
("more than last week?") may work in the index since both items are indexed —
to verify on the beta; the intent catalog backstops it either way.

**C. The intent catalog** (works on iOS 26 too, minus Siri-app polish) —
- `GetStatIntent(metric: StatMetric, period: StatPeriod)` — two `AppEnum`s
  (metric: totalSleep, nightWakes, feedTotal, avgBottle, longestStretch,
  bedtime…; period: today, yesterday, lastNight, thisWeek, lastWeek) give
  Siri's model a structured way to express dozens of questions — enum
  parameters are exactly what it fills well, sidestepping free-text phrase
  limits.
- `CompareStatIntent(metric:, period:, vs:)` — "is he sleeping more this
  week than last?"
- `NextUpIntent(kind: .feed/.nap/.wake)` — routes to
  `PredictionEngine`/`PredictionArbiter`/`WakeWindow`; predictions can never
  live in an index.
- `AskTwoOfUsIntent(question: String)` — free-text catch-all → AskEngine.
- The existing five fixed intents stay (they're Girl Taylor's iOS 26 voice
  surface and true one-utterance shortcuts).

**Plus the trimmings that make it best-in-class:** on-screen awareness
(`NSUserActivity` + view annotations tied to entity identifiers, so "what's
this?" works while browsing), interactive snippet views on intent results
(reuse `ConfirmationSnippet` patterns), and `Transferable` representations so
entities can leave Siri as text/summaries.

**What's deliberately absent:** any in-app chat or Ask UI. AskEngine remains
(it's what `GetStatIntent`/`AskTwoOfUsIntent` execute), and stays
surface-agnostic in case an in-app surface is ever wanted.

**Privacy note worth stating in-app and in the App Store nutrition label
review:** indexing puts Miller's data in the on-device semantic index —
still on-device, but now queryable outside the app. That's the point, but it
should be a visible, synced toggle (like `aiPredictionsEnabled`), and
`deletedAt` eviction has to be airtight so edited/deleted events never
linger in Siri answers.

---

## 4. Top 20 questions, by complexity

Drawn from the app's actual scenario (formula-fed newborn, two parents trading
night shifts). ✅ = answerable today without this feature.

**Tier 1 — simple lookups** (one event or one day's tally; deterministic parser
territory; `QuickLogger` mostly has these already)

1. "When did he last eat?" ✅ Siri + Home + widget
2. "How much did he take at the last feed?" ✅ folded into LastFeedIntent
3. "What time did he go to sleep last night?" ← the motivating question; **no
   surface answers this today** (Home timeline shows it, but you scroll + read)
4. "How long has he been asleep?" ✅ SleepStatusIntent + Live Activity
5. "When was his last dirty diaper?" ✅ LastDiaperIntent (wet/dirty split needs work)
6. "How many ounces today?" ✅ TodaySummaryIntent
7. "How many feeds/diapers today?" ✅ TodaySummaryIntent
8. "Who did the 3am feed?" — `loggedByName` is on every event; nothing surfaces it
9. "How long was his last nap?" — computable, not surfaced
10. "Did he poop today?" — tally exists; needs type filter

**Tier 2 — analytical** (aggregation + comparison; `StatsEngine` has ~all the
raw material: `dailySummaries`, `todayVsTypical`, `longestSleep`,
`averageFeedInterval`, heatmaps)

11. "How much did he sleep last night?" (night window is defined in
    `SharedSettings.nightStartMinute/nightEndMinute` — use it)
12. "How many times did he wake up last night?"
13. "Is he sleeping more this week than last week?"
14. "Is he eating more than usual?"
15. "What's his longest sleep stretch ever? This week?" (`StatsEngine.longestSleep`)
16. "What's his average per-feed amount lately?"
17. "What time does he usually go down for the night?"
18. "How does today compare to a typical day?" (`StatsEngine.todayVsTypical` exists)

**Tier 3 — predictive** (already built — `PredictionEngine` + `PredictionArbiter`
+ `WakeWindow`; the query layer just needs to route to them)

19. "When will he wake up?" / "When's his next nap?" ✅ Home shows it; not askable
20. "When will he want to eat next, and how much?" ✅ Home + alarm; not askable

**Tier 4 — notes recall** (free text; the one genuinely *searchy* case)

- "When did we start vitamin D drops?" / "What did the pediatrician say about
  spit-up?" — `NoteEvent.text` search. Substring search now; `IndexedEntity`
  semantic search is the iOS 27 upgrade path.

Distribution guess worth validating with Taylor: Tier 1 dominates at night
(voice/glance), Tier 2 is a daytime/curiosity activity (the Siri app's typed
chat, indexed summaries), Tier 3 is
already served passively.

---

## 5. Architecture

Principle carried over from `BabyIntelligence`: **the app computes every
number; the model only parses and narrates.** No LLM arithmetic, ever.

```
                 question (text or dictation)
                            │
                     ┌──── AskEngine ────┐
                     │ 1. QueryParser     │  deterministic: keywords + date
                     │    (rule-based)    │  phrases → ParsedQuery. Hit → skip
                     │                    │  the model entirely (instant, works
                     │                    │  on every device)
                     │ 2. FM session      │  miss + model available → tool-
                     │    with Tools      │  calling LanguageModelSession
                     └────────┬───────────┘
                              │ Tool calls (typed, read-only)
        ┌──────────────┬──────┴───────┬───────────────┬────────────┐
   EventLookupTool  StatsTool   PredictionTool   NotesSearchTool  ClockTool
   (QuickLogger:    (StatsEngine: (PredictionEngine (NoteEvent     ("today",
   last X, events   totals, avgs, /Arbiter/       substring       "last night"
   in range)        comparisons)  WakeWindow)      search)         resolution)
                              │
                     AskAnswer { sentence, facts: [label: value],
                                 sourceEvents: [TimelineEntry],
                                 deepLink: ChartDestination? }
                              │
              ┌───────────────┼────────────────┐
        Siri dialog +   (future in-app     Insights cards
        snippet views    surface, none      (existing)
        (ProvidesDialog) planned)
```

Key decisions:

- **New target-agnostic module** (files under `TwoOfUs/Ask/`), same pattern as
  `QuickLogger`: constructible against the App Group store so intents can run
  it headless without the full app.
- **Deterministic parser first, always.** Tier 1 shapes and common Tier 2
  shapes resolve without the model: lower latency, works when Apple
  Intelligence is off/unavailable (Siri fixed intents route straight to it),
  and unit-testable in CI where Foundation Models doesn't exist. The model is
  the long-tail fallback, not the front door.
- **Tools are thin adapters** over `QuickLogger` / `StatsEngine` /
  `PredictionEngine` / `NoteEvent` — no new query logic in the tools, and each
  returns a compact digest (the 4K context budget rules out raw event dumps;
  `StatsEngine`'s digest pattern from `StatsView.buildDigest()` is the
  template). All reads filter `deletedAt == nil` — they inherit this by going
  through the existing layers rather than raw `#Predicate`s.
- **`AskAnswer` carries its receipts**: the sentence plus the actual
  label/value facts used, so the Ask card can show "Slept 7:42 PM – 6:05 AM ·
  2 wakes" under the prose, and a wrong answer is diagnosable. Facts come from
  tool results, never parsed back out of model prose.
- **The iOS 27 entity layer is parallel plumbing, not part of AskEngine.**
  `Entities/` gets lightweight `AppEntity` structs mirroring the SwiftData
  models (id, display representation incl. `loggedByName`,
  `@Property(indexingKey:)` on timestamps/type/amounts/note text),
  `IndexedEntity` conformance, and `EntityQuery`s reading through
  `QuickLogger`. The semantic index answers lookup questions on its own;
  anything computed still routes through AskEngine via intents.
- **Derived summary entities are re-derived, never stored.** `DaySummaryEntity`
  / `WeekSummaryEntity` are pure functions of the event log via `StatsEngine`
  (same philosophy as the walk-forward accuracy evaluation): an
  `IndexMaintainer` recomputes and re-indexes the affected day/week whenever
  its events change, locally or via sync. Nothing new is persisted in
  SwiftData or CloudKit — no schema change, no new sync surface.
  **Index hygiene rules:** soft-deleted events (`deletedAt != nil`) must be
  evicted on delete/edit (the append-only edit model means every edit is a
  delete + insert), synced events from the other parent must index on
  arrival — the CKSyncEngine ingest path needs an indexing hook, same place
  the feed alarm re-arms today — and each event change also dirties its
  containing day/week summary.
- **Time is injected** (`now: Date` parameter throughout, like
  `PredictionEngine`) — "last night" and "yesterday" are testable, and the
  night window comes from `SharedSettings`, not hardcoded hours.
- **Failure posture**: parser miss + model unavailable → the intent replies
  with what it *can* answer ("Try asking about feeds, sleep, or diapers —
  e.g. 'how much did he sleep last night?'"); model answers are never cached
  as data; nothing about the feature writes to the SwiftData store.

Testing mirrors the prediction work: `AskEngineTests` (parser → query → answer
over fixture events, fully deterministic), tool adapters tested against
`StatsEngineTests`-style fixtures; the FM session itself is availability-gated
and exercised manually on device, exactly like `BabyIntelligence` today.

---

## 6. Phased implementation (rev 2)

**Phase 0 — toolchain.** Install the Xcode 27 beta alongside 26.4 (iOS 27 SDK
is required to compile any of Phase 2; this Mac currently has only 26.4).
Deployment target stays iOS 26 in project.yml — **never bump it while Girl
Taylor's phone is on 26**, or her TestFlight updates stop installing.

**Phase 1 — AskEngine + deterministic parser** (~the prediction-engine
playbook). `Ask/AskEngine.swift`, `Ask/QueryParser.swift`,
`Ask/AskAnswer.swift`, tool adapters, `TwoOfUsTests/AskEngineTests.swift`.
Covers Tier 1 + the 5 biggest Tier 2 questions + Tier 3 routing. No UI, no new
SDK needed — **can start today**, mergeable without user-visible risk.

**Phase 2 — entities + index** (`#available(iOS 27)` throughout):
- `Entities/` — `AppEntity` structs for feed/sleep/diaper/note +
  `IndexedEntity` conformance + `EntityQuery` via `QuickLogger`; index
  hygiene hooks in EventStore (edit/delete) and the sync ingest path; the
  synced "Siri can see Miller's data" toggle.
- Acceptance test, on Taylor's beta phone: the motivating question asked in
  the Siri app returns Miller's actual bedtime; "when did we start vitamin D
  drops" hits the indexed note.

**Phase 3 — the intent catalog.** `GetStatIntent` + `CompareStatIntent` +
`NextUpIntent` + free-text `AskTwoOfUsIntent`, all executing through
AskEngine, all with snippet views. The enum-parameterized ones work on iOS 26
too (Girl Taylor gets them). The FM tool-calling session (first
`Tool`/`@Generable` use in the app) backs `AskTwoOfUsIntent`; when Apple
Intelligence is unavailable the deterministic parser still covers the common
shapes.

**Phase 4 — summaries + polish.** `DaySummaryEntity`/`WeekSummaryEntity` +
`IndexMaintainer`; on-screen awareness (`NSUserActivity` + view annotations);
`Transferable` on entities; test which Tier 2 questions the index now answers
without an intent.

**Phase 5 — GM fast-follow (Sept–Oct).** Re-test the semantic index on
release Siri; adopt an App Schema if one fits; move Xcode Cloud back to a
stable toolchain; revisit the shortcut-slot budget with real usage; check
whether summary indexing made any intents redundant.

Phases 1–3 are the commitment; 4–5 sharpen it.

---

## 7. Questions for Taylor

Rev 2 resolved ~~ship now or ride iOS 27~~ (target 27) and half the device
question; rev 3 resolved ~~which surface~~ (all-in on Siri, no in-app chat or
Ask bar). Still open:

1. **Girl Taylor's phone** — when she does upgrade to iOS 27, is the hardware
   Apple Intelligence-capable (iPhone 15 Pro or newer)? If not, her phone
   never gets the semantic-index answers or the model-backed tail even on
   27 — the enum-parameterized intents and fixed intents are permanently her
   whole voice feature. Doesn't change the plan; sets expectations.
2. **Does anyone actually use the existing Siri asking intents?** ("When did
   Miller last eat…" shipped months ago.) Signal for how much to invest in
   the fixed-intent catalog vs. leaning entirely on the Siri app + index.
3. **What's the real question list?** Section 4 is my guess. A week of noting
   "things we wished the app could tell us" beats my ranking — especially
   whether notes recall matters, since it's the semantic index's best trick.
4. **Shortcut budget:** adding Ask + "last night's sleep" as App Shortcuts
   needs 2+ of the 10 slots and 8 are taken. Demote two logging variants
   (e.g. the wet/dirty/both diaper trio → one), or ship the new query intents
   without phrases (still usable via Shortcuts app and, on 27, discoverable
   by Siri through the intent metadata anyway)?
5. **Beta toolchain tolerance:** OK installing the Xcode 27 beta on the Mac
   (Phase 2 can't compile without it)? And should 27-gated code merge to
   `main`/TestFlight while built against a beta SDK, or live on a branch
   until the GM in September? (TestFlight accepts beta-SDK builds during the
   beta cycle, but `main` = auto-TestFlight here, so the answer decides when
   Girl Taylor's phone receives builds containing the gated code.)

---

## References

- [Apple: Foundation Models framework (newsroom, Sept 2025)](https://www.apple.com/newsroom/2025/09/apples-foundation-models-framework-unlocks-new-intelligent-app-experiences/)
- [WWDC26 241: What's new in the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2026/241/)
- [WWDC26 240: Build intelligent Siri experiences with App Schemas](https://developer.apple.com/videos/play/wwdc2026/240/)
- [WWDC26 343: Explore advanced App Intents features](https://developer.apple.com/videos/play/wwdc2026/343/)
- [WWDC26 319: Build with the new Apple Foundation Model on Private Cloud Compute](https://developer.apple.com/videos/play/wwdc2026/319/)
- [WWDC26 Apple Intelligence guide](https://developer.apple.com/wwdc26/guides/apple-intelligence/)
- Guided generation / tool calling walkthroughs: [AppCoda — Foundation Models](https://www.appcoda.com/foundation-models/), [AppCoda — Tool Calling](https://www.appcoda.com/tool-calling/)
- iOS 27 Siri app / Siri AI: [MacRumors — Siri AI in iOS 27](https://www.macrumors.com/guide/ios-27-siri/), [MacRumors — Siri redesign with chat interface and dedicated app](https://www.macrumors.com/2026/05/12/ios-27-siri-redesign/), [9to5Mac — iOS 27 public beta 3](https://9to5mac.com/2026/08/11/ios-27-public-beta-3/)
- Developer integration detail (incl. the open non-schema question): [Swiftjective-C — iOS 27, Your App, and Siri](https://www.swiftjectivec.com/siri-ai-for-ios027/)
- In-repo prior art: `docs/AI-PREDICTIONS.md`, `docs/SIRI_AND_SHORTCUTS.md`,
  `AI/BabyIntelligence.swift`, `Intents/QueryIntents.swift`, `Store/StatsEngine.swift`
