# AI Predictions — Plan

**Status: Phase 1 implemented** (statistical predictions for the v1 trio —
next feed time, feed amount, sleep duration/wake — plus the AI Features
toggle and `AIGlow` styling; see `PredictionEngine.swift`). Phases 2–4 remain
planned. Decisions taken 2026-08-27: v1 ships the trio (diaper predictions
held), Home + Live Activity surfaces first, subtle gradient styling,
night-schedule annotations only, age baselines shown from day one, one synced
family-wide toggle that also governs the Stats insights card.

⚠️ Before the next TestFlight build: deploy the new `aiPredictionsEnabled`
field on the Settings record type to CloudKit **Production** (Console only —
cktool can't; see the schema-deploys memory).

Original plan follows. Written 2026-08-27.

## Goal

Use Miller's own logged history (feeds, sleep, diapers) plus his age to predict:

1. **When he will wake up** — from sleep patterns, time of day, age-based duration trends
2. **How long he will sleep** — duration prediction for the current/next nap and night sleep
3. **When he will want to eat next** — from actual feeding patterns, not just the flat interval timer
4. **How much he will eat** — oz by time of day, age, and recent trend
5. **When he'll need a diaper change** — from feed-to-diaper intervals
6. **Wet vs dirty** — predict the next diaper's type from patterns

Everything runs on device. Nothing about Miller ever leaves the phone.

---

## What the app already has (build on this, don't duplicate it)

The codebase is further along than "no predictions" — Phase 1 is partly a
generalization of machinery that already exists:

| Existing piece | Where | What it does |
|---|---|---|
| `WakeWindow` | `TwoOfUs/Store/WakeWindow.swift` | **The template for everything in this plan.** Age-banded wake-window table; prediction = age-band midpoint slid toward the median of observed gaps in proportion to sample count, clamped back into the band. Night wakes excluded. Pure functions, fully unit-tested (`WakeWindowTests`). Drives "next nap ~2:15 PM" on Home, watch, and widgets. |
| `ScheduleAssembly.nextFeedPrediction` | `TwoOfUs/Store/ScheduleAssembly.swift:53` | Next feed = min(schedule's next slot, last feed + `feedInterval(after:)`). Feeds the sleep Live Activity and feed alarm. |
| `SharedSettings.feedInterval(after:)` | `TwoOfUs/Models/SharedSettings.swift` | Canonical day/night feed-interval target (`targetFeedIntervalMinutes`, night spacing). |
| `StatsEngine` | `TwoOfUs/Store/StatsEngine.swift` | Day summaries, feed heatmap by hour, sleep records, week recaps — most of the feature-engineering queries already exist here. |
| `BabyIntelligence` | `TwoOfUs/AI/BabyIntelligence.swift` | Foundation Models (iOS 26) wrapper: availability gate, on-device `LanguageModelSession`, warm-recap generation from a stats digest. Used by `StatsView`. |
| `Urgency` | `TwoOfUs/DesignSystem/Urgency.swift` | Time-since coloring; the visual language predictions must coexist with. |
| Night window & schedule | `SharedSettings.nightStartMinute/nightEndMinute`, `NightSchedule`, `ScheduleEngine` | Wall-clock night definition + tonight's planned feed slots with parent assignment. |

**Implication:** the plan's core is a `PredictionEngine` that generalizes the
`WakeWindow` recipe — *age sets the range, his own data positions him inside
it* — to feeds, feed amounts, sleep durations, and diapers. ML (Core ML) is a
later, optional upgrade, not the foundation.

---

## The six predictions

Common shape for all of them:

```swift
struct Prediction<Value> {
    let value: Value            // Date, TimeInterval, Double (oz), DiaperType odds
    let range: ClosedRange<Value>? // where meaningful (e.g. wake time ±20m)
    let confidence: Confidence  // .low / .medium / .high
    let basis: Basis            // .ageBaseline, .blended(samples: Int), .model
}
```

`confidence` maps from evidence volume (the `minimumSamples` /
`fullConfidenceSamples` pattern `WakeWindow` already uses) and recency of data.
`basis` keeps the UI honest about whether a number is "babies his age" or "your
baby."

### 1. Wake-up time (current sleep → predicted end)

- **Trigger:** a `SleepEvent` with `endedAt == nil` is running.
- **Signal:** is this a nap or night sleep (start time vs night window)? Recent
  nap durations at this time of day; recent night-stretch durations; age-based
  duration bands (newborn naps 30–120m, consolidating by 4–6 months, etc.).
- **Method (Phase 1):** median of comparable recent sleeps (same day-part,
  trailing 14 days), blended with an age-band table exactly like `WakeWindow`,
  → `predicted wake = startedAt + blendedDuration`. Overnight, cross-check
  against the night schedule: he historically wakes for the ~3:00 AM slot.
- **Surfaces:** SleepActiveCard ("predicted wake ~6:15 AM"), sleep Live
  Activity, watch sleep complication.

### 2. Sleep duration (same engine, different framing)

Same computation as #1 presented as duration ("likely a ~45 min nap") before or
during the sleep. Also powers a pre-sleep hint on the sleep tile: "next nap
~2:15 PM · usually ~50m at this hour."

### 3. Next feed time (upgrade the flat interval)

- **Today:** flat `targetFeedIntervalMinutes` (day) / `nightFeedSpacingMinutes`.
- **Phase 1:** replace the flat interval with an *observed* interval: median gap
  between feeds in the same day-part over the trailing 7–14 days, blended with
  the settings interval as prior, clamped to a plausible band around it. Cluster
  feeds (< 30 min apart) collapse into one "feeding" before computing gaps —
  same outlier hygiene as `WakeWindow.plausibleGap`.
- Optionally hour-of-day aware (he goes longer 10 AM–2 PM, shorter in the
  evening cluster) once there's enough data per bucket.
- **Interaction with the night schedule:** during the night the schedule is the
  plan; prediction should defer to it (or annotate it: "scheduled 3:00 AM,
  he usually wakes ~2:40"). This is an open question for Taylor (Q4 below).
- **Surfaces:** feed tile hint, sleep Live Activity trailing column (already
  plumbed via `nextFeedPrediction`), feed alarm pre-arm, widgets/complications.

### 4. Feed amount (oz)

- **Signal:** trailing 7-day oz-per-feed by day-part, total daily oz trend
  (age-driven growth), time since last feed (longer gap → bigger bottle).
- **Method (Phase 1):** median oz for this day-part over trailing 7 days,
  blended with an age-based oz table (roughly: total daily oz ≈ weight-driven,
  approximated by age bands since we don't log weight), nudged by gap length.
  Round to the app's half-ounce steps.
- **Surfaces:** feed tile ("~3.5 oz"), FeedSheet default-amount suggestion
  (distinct from the fixed `defaultFeedOz` — suggestion, not silent override),
  widget one-tap default stays the fixed setting (predictable > clever for
  one-tap logging).

### 5. Next diaper change (time)

- **Signal:** feed→diaper latency distribution, diaper→diaper gaps, time of
  day (fewer changes overnight — that's already how parents behave), age-based
  frequency (newborns 8–10/day trending down).
- **Method (Phase 1):** two candidate clocks — last diaper + median
  diaper-to-diaper gap for this day-part, and last feed + median feed-to-diaper
  latency — take the earlier, with age-band clamp.
- **Surfaces:** diaper tile hint.

### 6. Wet vs dirty (type)

- **Signal:** sequence patterns (dirty diapers cluster after feeds and in the
  morning; long dirty droughts at certain ages are normal), time since last
  dirty, count of wets since last dirty.
- **Method (Phase 1):** empirical conditional frequency: P(next is dirty |
  hours since last dirty, day-part), from his own history with a small
  age-based prior. Presented as a lean ("likely wet" / "dirty likely — it's
  been 2 days"), never as certainty.
- Honest caveat: this is the noisiest of the six and the least actionable
  (you change the diaper either way). Lowest priority; candidate to cut from
  v1 (Q5 below).

---

## Technical approach

### Options assessed

**Statistical (pure Swift, no ML) — Phase 1, and honestly most of the value.**
Medians over filtered windows, day-part bucketing, age-band priors,
evidence-proportional blending. This is `WakeWindow` generalized. With a
single-digit-thousands event history, well-chosen statistics are competitive
with trained models, fully explainable ("median of his last 9 morning naps"),
deterministic, unit-testable, and run in microseconds anywhere (widgets, watch,
Live Activity budget). No model file, no training pipeline, no schema changes.

**Core ML with on-device training — Phase 2, targeted.**
Two realistic routes:
- **Create ML framework on iOS** (`import CreateML`, available on-device since
  iOS 15): train small tabular regressors (boosted trees / linear) directly
  from the event history, periodically (e.g. nightly or after N new events),
  persist the `.mlmodel` locally per device. No bundled model needed; each
  phone trains on its own synced copy of the data, so nothing new syncs.
- **Updatable Core ML models** (`MLUpdateTask`): ship a tiny bundled model and
  fine-tune on device. More machinery, mainly pays off for neural nets — likely
  overkill here.

Candidate first model: **feed-gap regressor** (features: hour sin/cos, day-part,
age-in-days, last 3 gaps, last amount, gap-since-sleep) and **oz regressor**.
Ship behind a comparison harness: the model only replaces the statistical
number if Phase 4's accuracy tracking shows it beating the statistic on a
trailing window. If it doesn't win, it doesn't ship — the statistic stays.

**Apple Intelligence Foundation Models — already integrated; wrong tool for numbers.**
`BabyIntelligence` already uses the on-device `SystemLanguageModel` (iOS 26,
device-gated). LLMs are the wrong instrument for numeric regression (they
confabulate numbers), but the right instrument for **narrative around the
numbers**: a "today's outlook" blurb generated *from* the computed predictions
("Expect a bigger evening bottle — he's been cluster feeding around 7 PM"),
using `@Generable` guided generation for structure. Phase 3. All availability
gating and graceful-nil patterns already exist in `BabyIntelligence`.

**Private Cloud Compute — not applicable.**
There is no third-party developer API that lets an app run its own workloads on
PCC; the Foundation Models framework is the on-device developer surface. If
Apple opens PCC-backed larger models to the framework later, `BabyIntelligence`
is the seam where it would slot in. Nothing to build; noted so the privacy
story stays "on-device, full stop."

### Architecture

```
TwoOfUs/Store/
  PredictionEngine.swift      // pure functions, WakeWindow-style; no SwiftData imports
  AgeBaselines.swift          // published age-band tables: feed interval, oz/day,
                              // nap/night durations, diaper frequency (WakeWindow.bands
                              // migrates here or stays put and is referenced)
  PredictionAccuracy.swift    // Phase 4: predicted-vs-actual capture + scoring
TwoOfUs/AI/
  BabyIntelligence.swift      // Phase 3: outlook narrative from computed predictions
```

- **`PredictionEngine` is pure**: takes `[(Date, Double)]`-shaped inputs, age
  in days, night window minutes, `now`. Callers (`EventStore` /
  `ScheduleAssembly` / `WidgetProvider` / `ComplicationStore`) fetch and map.
  This is exactly how `WakeWindow` stays testable and shareable across the
  seven targets, and it must stay dependency-free so the watch/widget targets
  can compile it in.
- **No schema changes in Phases 1–2.** Predictions are derived, never stored,
  never synced. Each device computes from its own synced event history, so both
  parents see (near-)identical predictions without any CloudKit work. The only
  stored additions: an `aiPredictionsEnabled` toggle, and Phase 4's accuracy
  log (local-only, see below).
- **Settings toggle:** `aiPredictionsEnabled: Bool = true` on `SharedSettings`
  (synced — one family, one policy, matching every other toggle there;
  CloudKit field is additive, and per the schema-deploy rule it must be
  deployed to Production before the TestFlight build ships). Surfaced in
  Settings → Feeding & Tracking as an "AI Features" section with a one-line
  privacy note. Governs predictions AND the existing `BabyIntelligence`
  summary card, which currently has no toggle.
- **Cold start / degraded modes**, in order: (1) no toggle or hardware issue —
  hints fall back to today's behavior (flat interval, `WakeWindow` alone);
  (2) < ~3 relevant samples — show age-baseline predictions labeled as such
  ("typical for 12 weeks"), low confidence; (3) enough data — blended,
  confidence rises with sample count. New-user experience is therefore never
  empty: age baselines work from day one because `Baby.dateOfBirth` exists at
  onboarding (including due-date-before-birth, where `isBorn == false` pins to
  the newborn band — `WakeWindow` already handles this).

### Data requirements (how much history before it's "his data")

Follow `WakeWindow`'s calibration, per-prediction rather than a global "N days":

| Prediction | Min samples before blending | Full confidence | Practical wall-clock |
|---|---|---|---|
| Next feed time | 5 gaps in day-part | 15 | ~2 days |
| Feed amount | 5 feeds in day-part | 15 | ~2 days |
| Nap duration / wake | 3 comparable sleeps | 8 | ~2–4 days |
| Night wake | 3 nights | 7 | ~1 week |
| Diaper timing | 5 gaps | 15 | ~2 days |
| Wet vs dirty | 10 diapers + 3 dirty | 25 | ~1 week |

Trailing windows of 7–14 days keep predictions tracking developmental change
(a growth spurt should move the numbers within days, not weeks) — this matters
more than total history volume.

---

## UI / UX

Visual mockups: `mockups/ai-predictions-mockup.html` (open in a browser) —
seven phone-frame panels covering the tiles, active-sleep card, Live Activity,
tonight-card annotation, confidence wording, settings toggle, and Stats cards.

### AI gradient styling

Apple's Intelligence visual language: multicolor gradient shimmer for
AI-generated content.

- A `DesignSystem` component: `AIGlow` — animated angular gradient border /
  text foreground style (the Siri palette: blue→purple→pink→orange), applied
  to prediction hint text and the Phase 3 outlook card. Static gradient text
  by default; a slow shimmer only on first appearance — this is a calm app
  used at 3 AM, and Home tiles already carry `Urgency` coloring that must
  remain readable next to it. Respect Reduce Motion (no shimmer) and keep
  dark-mode contrast (the app is dark-first at night).
- Prominence is Q3 for Taylor: subtle (gradient tint on the hint line only,
  recommended) vs loud (full gradient card treatment).

### Where predictions appear

| Surface | Prediction | Treatment |
|---|---|---|
| Home feed tile | "next feed ~2:30 AM · ~3.5 oz" | replaces current flat-interval hint when confidence ≥ medium |
| Home sleep tile | existing `WakeWindow` nap hint + "usually ~50m" | extend existing hint |
| SleepActiveCard / Live Activity | "predicted wake ~6:15 AM" | new line; LA already shows next feed |
| Home diaper tile | "next change ~4:15 PM" (+ optional lean) | replaces "last change Xh ago"? No — appended |
| Tonight card / night schedule | annotations only ("usually wakes ~2:40") | schedule remains the source of truth |
| Widgets / watch complications | reuse the tile hint strings | snapshot pipeline already carries hint text |
| Stats screen | Phase 3 outlook card; Phase 4 accuracy view | AI-styled card, mirrors existing summary card |

### Confidence display

Three levels, shown as wording rather than badges (calmer): high = plain
statement ("next feed ~2:30"), medium = hedged ("likely around 2:30"), low /
baseline = attributed ("typical for his age: ~3h"). A small info affordance
(tap the hint) explains the basis: "Median of his last 12 afternoon feeds."
Explainability is the trust feature — `WakeWindow`'s hint already shows its
assumption (`· 1h50m awake`) for exactly this reason; keep that principle.

### Predicted vs actual (Phase 4)

- At event log time, snapshot the then-current prediction into a local-only
  record (`PredictionOutcome`: kind, predictedAt, predictedValue, actualValue).
  Local store (not synced — both devices independently converge on similar
  numbers; syncing outcomes buys nothing and costs a schema deploy).
- Stats screen gets an accuracy card: "Feed-time predictions this week: median
  miss 14 min." Doubles as the gate for Phase 2 model promotion.

### Privacy

- All computation on device; Foundation Models inference on device; no
  third-party services; nothing new synced beyond the settings toggle.
- Settings copy under the AI Features toggle: "Predictions are computed on your
  device from your own logs. Nothing about Miller leaves your phone."
- `docs/PRIVACY.md` + App Store privacy answers reviewed; no new data types
  collected → no nutrition-label changes expected (verify before submission).
- Keep `BabyIntelligence`'s "never medical advice" line: predictions are
  planning aids, phrased as observations about *his patterns*, never guidance
  about what he *should* eat/sleep.

---

## Phases

### Phase 1 — Statistical predictions (no ML)
The whole feature, minus the word "model." Ships all six predictions.
1. `AgeBaselines` tables (feed interval, oz, nap/night durations, diaper
   frequency by age band) with sources noted in comments.
2. `PredictionEngine` pure functions per prediction, `WakeWindow`-style
   blending; unit tests mirroring `WakeWindowTests` (goldens for cold start,
   outliers, night/day routing, cluster-feed collapsing).
3. `aiPredictionsEnabled` on `SharedSettings` (+ CloudKit Production schema
   deploy) and the Settings → Feeding & Tracking "AI Features" section.
4. `AIGlow` design-system component.
5. Wire surfaces: home tiles → Live Activity → widgets/complications (in that
   order; each is independently shippable).

### Phase 2 — Core ML (only where it beats the statistic)
1. Feature-extraction code shared with Phase 1 bucketing.
2. On-device Create ML tabular training for feed-gap and oz; background
   retrain task; local model persistence + versioning.
3. Champion/challenger: model prediction logged alongside statistical in the
   Phase 4 accuracy store; promoted per-prediction only when it wins.

### Phase 3 — Apple Intelligence narrative
1. Extend `BabyIntelligence` with a structured "outlook" generation taking the
   computed predictions + stats digest as input (`@Generable`).
2. Outlook card on Home or Stats (Q2), availability-gated as today.

### Phase 4 — Accuracy tracking
(Can land right after Phase 1 — it gates Phase 2, so schedule it early.)
1. `PredictionOutcome` local store + capture at log time.
2. Stats accuracy card; per-prediction rolling error metrics.
3. Feeds Phase 2 promotion decisions and future re-tuning of blend constants.

Suggested order: **1 → 4 → 2 → 3**, with 2 contingent on 4's evidence.

---

## Risks & honest caveats

- **Tiny data.** One baby, weeks of history. Core ML may never beat the
  medians; the plan treats that as an acceptable (even likely) outcome — hence
  champion/challenger rather than a rewrite. The statistic is the product; ML
  is an optimization experiment.
- **Regime changes.** Growth spurts, sleep regressions, illness, starting
  solids — patterns break abruptly. Trailing windows + age-band clamps bound
  the damage; confidence should drop when recent variance spikes (cheap to
  add: interquartile-range check).
- **SNOO data.** Snoo-sourced sleeps (`sourceRaw`) improve sleep-history
  density but can double-log with manual entries; `SnooReconciler` invariants
  must hold upstream of the engine — the engine itself just consumes live,
  non-deleted events.
- **Prediction fatigue / wrongness cost.** A wrong "wake ~6:15" that a parent
  planned a shower around is worse than no prediction. Confidence gating and
  hedged wording are load-bearing, not polish.
- **Widget/complication staleness.** Predictions embedded in timeline snapshots
  age; hint strings should be phrased to degrade gracefully (clock times, not
  countdowns, where the surface can't re-render).

---

## Questions for Taylor

1. **Prioritization for v1:** all six predictions, or start with the highest-value
   trio — next feed time, feed amount, and wake-up time — and hold diaper
   predictions (especially wet-vs-dirty, the noisiest and least actionable) for
   a later pass?
2. **Surfaces:** Home tiles + Live Activity first, with widgets/watch following —
   or do you want widgets/complications in the first cut? And should the Phase 3
   narrative card live on Home or stay on Stats with the existing summary?
3. **AI styling prominence:** subtle gradient tint on the hint text only
   (recommended — keeps 3 AM calm and coexists with Urgency colors), or the full
   Apple Intelligence shimmer/glow card treatment?
4. **Night schedule interplay:** overnight, should predictions stay annotations
   on the schedule ("usually wakes ~2:40"), or actually adjust the plan — e.g.
   nudge the feed alarm earlier when he consistently beats the slot? The
   schedule's parent-routing invariant makes the second option materially more
   invasive.
5. **Threshold to show anything:** are age-baseline predictions from day one
   (labeled "typical for his age") desirable, or should prediction UI stay
   hidden until his own data reaches medium confidence (~2–4 days per
   prediction)?
6. **Scope of the toggle:** should the new "AI Features" switch also govern the
   existing Stats summary card (currently always-on when hardware supports it),
   and should it be per-family (synced, recommended) or per-device?
