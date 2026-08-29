# Natural Language Queries — Research & Design

**Status: proposal** — written 2026-08-28. Nothing here is built.

The question this doc answers: should Two of Us get a natural language
interface — "what time did he go to sleep last night?" answered from the app's
own data — and if so, what shape should it take?

**TL;DR recommendation:** not a chat. Build a shared **AskEngine** (Foundation
Models tool-calling over the query machinery the app already has), surface it
three ways in this order: (1) an **Ask bar** on History with tappable suggestion
chips, (2) a **dictation-friendly Siri intent** plus a few more fixed "asking"
intents, (3) fold the same engine into the existing proactive-insights cards.
Re-evaluate against iOS 27's App Schemas / semantic Spotlight index this fall.

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

### 1c. iOS 27 (WWDC26, ships ~Sept 2026) — the reason not to over-build now

Two announcements directly overlap this feature:

- **App Schemas**: conform entities/intents to predefined schemas and Siri
  understands natural phrasing with no trigger phrases at all. Schemas are
  predefined concepts (messages, contacts, documents…) — there is no
  baby-tracking schema, so applicability is unclear until the final schema list
  ships.
- **`IndexedEntity` semantic Spotlight indexing**: indexed app content becomes
  something Siri can *reason over and answer questions about* system-wide.
  This is almost exactly the feature Taylor is asking for, provided by the OS —
  but iOS 27-only, entity-lookup-shaped (good for "when did we start vitamin D
  drops?", unproven for aggregations like "how much sleep this week?"), and we
  have zero `AppEntity` conformances today (the explorer confirmed none exist).
- Foundation Models also gains PCC and third-party model backends (Claude,
  Gemini) behind the same API.

Implication: build the query *engine* now (it's needed regardless — something
must compute the answers), keep the *Siri plumbing* thin, and adopt
schemas/indexing when iOS 27 is real. Don't hand-roll in August what the OS
does in September — but also don't wait on unshipped promises for the parts we
can ship today.

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
| **In-app chat bubble** | ❌ **Recommend against.** Typing is the worst input mode for this app's core scenario — the whole design is "as few taps as possible." A chat thread also implies conversation history, follow-ups, and a persistent UI surface, all heavyweight for what are single-shot lookups. And the top 10 questions already have zero-tap answers: Home shows time-since-last-everything, the widget shows the feed countdown. A chat bubble would mostly be a slower way to reach data that's already on screen. |
| **Siri (voice)** | ✅ **Best for the 3am case** — hands-free, no unlock, works from across the room. Already partially shipped. The gap is coverage (5 fixed questions) and the iOS 26 one-utterance limitation for arbitrary questions. Strategy: fixed intents for the head of the distribution (true one-utterance), dictated `AskTwoOfUsIntent` for the tail. |
| **Ask bar (smart search on History)** | ✅ **Best for the daytime/analytical case.** History today is six chart cards with no search at all — the analytical long tail ("is he sleeping more this week?") currently means reading charts and doing mental math. A single Ask field with **tappable suggestion chips** (so common questions are one tap, not typed) fits here. This is also the natural debug/trust surface: the answer card can show its supporting numbers. |
| **Proactive insights** | ✅ **Already the app's direction** — Insights card, Today's outlook, weekly Wrapped, milestones. Best passive UX: the question you didn't have to ask. Extend, don't invent: the same engine's comparative answers ("20% longer than his weekly average") can upgrade existing cards. Never a replacement for on-demand questions, though. |
| **Widget intelligence** | ➖ **Lowest incremental value.** Widgets already answer the top glance questions (time since last feed, countdown, sleep state). "Smart" rotating insight widgets are cute but compete with the countdown for very limited widget real estate. Skip for now. |

The honest overall answer: **most of the value of "ask the app anything" is
already shipped** as glanceable UI, widgets, and five Siri intents. The real
gaps are (a) voice coverage of more question shapes, (b) the analytical tail
that currently requires chart-reading, (c) notes recall ("when did we start
the new formula?"). The design targets those gaps instead of adding a chat
front-end to data that's one glance away.

---

## 3. Recommended approach

One engine, three surfaces, in this order:

1. **AskEngine** (no UI) — shared query core in the app target, reusable from
   intents. Deterministic parser for the head, Foundation Models tool-calling
   for the tail. Ships with unit tests only.
2. **Ask bar on History** — first visible surface, chips + free text, answer
   card with supporting numbers and a deep link to the relevant chart.
3. **Siri expansion** — 2–4 new fixed asking intents (last night's sleep,
   totals for a period) + dictated `AskTwoOfUsIntent` backed by the same
   engine. Requires deciding what to do about the 8/10 shortcut slots.
4. **Insights upgrade** — route existing Insights/Outlook cards through the
   engine's comparative queries where it makes them better.
5. **iOS 27 checkpoint (Sept–Oct 2026)** — evaluate App Schemas + `IndexedEntity`
   against the shipped feature; adopt for notes/event *lookup* if the final
   API fits; consider PCC for nothing (on-device is a feature here, not a
   limitation).

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
(voice/glance), Tier 2 is a daytime/curiosity activity (Ask bar), Tier 3 is
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
         Ask bar card    Siri dialog      Insights cards
         (History)       (ProvidesDialog)  (existing)
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
- **Time is injected** (`now: Date` parameter throughout, like
  `PredictionEngine`) — "last night" and "yesterday" are testable, and the
  night window comes from `SharedSettings`, not hardcoded hours.
- **Failure posture**: parser miss + model unavailable → the Ask bar shows the
  chip list ("Here's what I can answer…"); model answers are never cached as
  data; nothing about the feature writes to the store.

Testing mirrors the prediction work: `AskEngineTests` (parser → query → answer
over fixture events, fully deterministic), tool adapters tested against
`StatsEngineTests`-style fixtures; the FM session itself is availability-gated
and exercised manually on device, exactly like `BabyIntelligence` today.

---

## 6. Phased implementation

**Phase 1 — AskEngine + deterministic parser** (~the prediction-engine playbook)
`Ask/AskEngine.swift`, `Ask/QueryParser.swift`, `Ask/AskAnswer.swift`, tool
adapters, `TwoOfUsTests/AskEngineTests.swift`. Covers Tier 1 + the 5 biggest
Tier 2 questions + Tier 3 routing. No UI. Mergeable without user-visible risk.

**Phase 2 — Ask bar on History.** Field + chips above the existing cards
(`HistoryView` is a ScrollView of cards; the Ask card becomes the top card when
active). Chips are the primary interaction; typing is the escape hatch. Answer
card shows sentence + facts + "show me" deep link to the relevant chart card.
FM tool-calling session lands here (first `Tool`/`@Generable` use in the app),
gated on `BabyIntelligence.isAvailable`-style checks, hidden when unavailable
(chips + parser still work).

**Phase 3 — Siri.** `AskTwoOfUsIntent` (dictated question → AskEngine →
`ProvidesDialog`) + 2–3 new fixed intents chosen from Tier 1 gaps ("last
night's sleep" first — it's the motivating question). Resolve the shortcut-slot
budget (see Questions).

**Phase 4 — Insights integration.** Swap hand-built digest lines in
Insights/Outlook for engine-computed comparisons where they're better; add 1–2
new proactive lines ("longest night stretch this week").

**Phase 5 — iOS 27 checkpoint (fall 2026).** Prototype `IndexedEntity` on
`NoteEvent` + the event types; test whether semantic Siri answers Tier 1
questions without our intents; adopt schemas if a fitting one ships. Decide
with real APIs, not announcements.

Phases 1–2 are the commitment; 3–5 are each independently skippable.

---

## 7. Questions for Taylor

1. **Do both phones run Apple Intelligence?** Foundation Models needs iPhone
   15 Pro+ with Apple Intelligence enabled. If Girl Taylor's phone doesn't
   qualify, the model-backed long tail is a one-parent feature and the
   deterministic parser's coverage becomes the real product — worth knowing
   before investing in Phase 2's FM layer.
2. **Does anyone actually use the existing Siri asking intents?** ("When did
   Miller last eat…" etc. shipped months ago.) If voice querying hasn't stuck
   in practice, Phase 3 drops to the bottom and the Ask bar is the feature.
   If it's used nightly, Phase 3 might belong before Phase 2.
3. **What's the real question list?** Section 4 is my guess. A week of noting
   "things we wished the app could tell us" beats my ranking — especially
   whether notes recall (Tier 4) matters, since it's the one case needing
   genuinely different machinery.
4. **Shortcut budget:** to add Ask + "last night's sleep" we need 2+ of the 10
   App Shortcut slots and 8 are taken. OK to demote two logging variants
   (e.g. the wet/dirty/both diaper trio → one), or should new query intents
   ship without App Shortcut phrases (still usable via Shortcuts app, worse
   Siri discovery)?
5. **Ship now or ride iOS 27?** Phases 1–2 are pure iOS 26 and useful
   regardless. But if the appetite is mainly for the *Siri* experience, the
   honest advice is: do Phase 1 now, hold Phase 3 until we've tested iOS 27's
   semantic Siri in September — Apple may ship most of that UX for free.

---

## References

- [Apple: Foundation Models framework (newsroom, Sept 2025)](https://www.apple.com/newsroom/2025/09/apples-foundation-models-framework-unlocks-new-intelligent-app-experiences/)
- [WWDC26 241: What's new in the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2026/241/)
- [WWDC26 240: Build intelligent Siri experiences with App Schemas](https://developer.apple.com/videos/play/wwdc2026/240/)
- [WWDC26 343: Explore advanced App Intents features](https://developer.apple.com/videos/play/wwdc2026/343/)
- [WWDC26 319: Build with the new Apple Foundation Model on Private Cloud Compute](https://developer.apple.com/videos/play/wwdc2026/319/)
- [WWDC26 Apple Intelligence guide](https://developer.apple.com/wwdc26/guides/apple-intelligence/)
- Guided generation / tool calling walkthroughs: [AppCoda — Foundation Models](https://www.appcoda.com/foundation-models/), [AppCoda — Tool Calling](https://www.appcoda.com/tool-calling/)
- In-repo prior art: `docs/AI-PREDICTIONS.md`, `docs/SIRI_AND_SHORTCUTS.md`,
  `AI/BabyIntelligence.swift`, `Intents/QueryIntents.swift`, `Store/StatsEngine.swift`
