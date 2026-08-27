# Prediction Math — Current State & Recency-Weighting Analysis

**Status: Option D implemented on this branch (2026-08-27).** What shipped,
relative to the analysis below:
- `PredictionEngine.blend` now takes recency-weighted `(value, weight)`
  pairs: weights are `2^(−age/halfLife)` (`decayWeight`), the statistic is a
  **weighted quantile**, and confidence gates run on the **Kish effective
  sample size** (`effectiveCount`). Half-lives: feed gaps 3 d, bottle
  amounts 2 d, sleep durations 4 d. Evidence gates: 4/12 effective samples
  for feeds and amounts (was 5/15 raw), 3/8 for sleep (unchanged
  numerically, now effective).
- Feed timing reads the **40th percentile** (`feedGapQuantile`), not the
  median — the deliberately-slightly-early forecast from §5 Q3. Amounts and
  sleep stay at the median.
- `HomeView.sleepTarget` is windowed to the trailing 7 days (§1.5's bug).
- `NightScheduleGenerator.predictedNextFeed` (dead simple-mean code) is
  deleted.
- Not done: `WakeWindow` itself stays unweighted (phase 2 per §3's table),
  and the on-real-data half-life sweep (§4 step 3) still needs a run of
  `PredictionAccuracy` against Miller's live history on-device — the
  constants are the analysis's priors, and the accuracy card on Stats is
  the thing to watch after this ships.

The analysis below describes the state *before* this branch; §1's formulas
are the "current state" it replaced.

---

Written 2026-08-27, Miller ~4 weeks old. This is the answer to "should the
predictions weigh recent data more heavily?" — an inventory of every formula
the app uses today, an analysis of where equal weighting actually hurts, four
candidate designs with worked examples, and a recommendation.

**TL;DR:** the app does *not* average all-time history — every prediction
already uses a sliding window (7–14 days), a robust median, and an
age/config prior. But *inside* those windows every event counts equally, so a
windowed median lags a real change by roughly **half the window's span**
(~3–4 days for feed gaps, ~2–3 days for bottle sizes). For a baby whose
patterns shift week to week, that lag is the whole game. The recommended fix
is not EMA and not a smaller window: it's an **exponentially time-decayed
weighted median** dropped into the existing blend — keeps the outlier
robustness and the prior, cuts adaptation lag from ~3.5 days to ~1.5, and can
be validated against Miller's own history with the walk-forward accuracy
harness that already exists (`PredictionAccuracy`).

---

## 1. Current state — every prediction in the app

### 1.1 "next ~7:15" on the Feed tile (AI path)

- **Where:** `PredictionEngine.nextFeed` (`TwoOfUs/Store/PredictionEngine.swift:117`),
  called from `HomeView.feedHint` (`TwoOfUs/Features/Home/HomeView.swift:371`).
- **Math:** `prediction = lastFeed + blend(prior, observed)` where
  - *prior* = the configured target interval
    (`SharedSettings.feedInterval(after:)` — day target or night spacing,
    whichever applies to the last feed's clock time);
  - *observed* = gaps between **distinct feedings** — bottles < 30 min apart
    collapse into one feeding (`feedClusterGap`); the gap runs from the last
    bottle of one feeding to the first of the next;
  - *blend* = `prior + w · (median(observed) − prior)` with
    `w = min(n, 15) / 15`, then clamped to `0.6×…1.5×` the target.
- **Data:** trailing **14 days** (`feedHistoryWindow`), same day-part only —
  a night-time last feed is predicted only from night gaps, a daytime one
  only from day gaps (`WakeWindow.isNight` against the household night
  window).
- **Edge cases:** gaps outside 1–6 h are discarded as mis-logs
  (`plausibleFeedGap`); < 5 usable gaps → confidence `.low` and the caller
  falls back to the plain config hint; ≥ 15 → `.high` ("next ~" wording
  instead of "likely ~"). **Median, not mean** — one outlier that slips the
  filter can't move the answer.

### 1.2 The Phase-2 challenger model

- **Where:** `PredictionModel.trainGapModel` / `predictGap`
  (`TwoOfUs/AI/PredictionModel.swift`), refereed by `PredictionArbiter`,
  gated by `PredictionAccuracy` (walk-forward, trailing 30 days).
- **Math:** closed-form ridge regression (λ = 1) over 7 features:
  bias, sin/cos of clock time, isNight, **age/100 days**, previous gap,
  has-previous-gap. Trained on the trailing **45 days**, ≥ 24 samples.
  Output clamped by the *same* policy as the statistic.
- **Recency behavior:** no sample weighting — every training row counts
  equally — but the **age feature lets it model a trend** the median can't
  (it can learn "gaps grow ~X min/day" and extrapolate to today). It only
  ever surfaces while `AccuracyReport.modelWins` holds: median absolute
  error ≥ 5% better than the statistic over ≥ 20 walk-forward-scored events.

### 1.3 "next bottle ~X" (AI off, and the Live Activity / feed alarm)

- **Where:** `HomeView.feedHint` fallback (`HomeView.swift:406`),
  `QuickLogger.nextFeedPrediction` (`TwoOfUs/Store/ScheduleAssembly.swift:53`),
  `FeedAlarmManager`.
- **Math:** `lastFeed + feedInterval(after:)` — **pure configuration**, zero
  history. Deliberate: the bell is a contract the parents set, the hint is a
  forecast; the alarm never follows the forecast.

### 1.4 "~3.5 oz" bottle-size hint and FeedSheet prefill

- **Where:** `PredictionEngine.feedAmount` (`PredictionEngine.swift:153`),
  called from `HomeView.predictedOz` and `FeedSheet`. Ridge challenger:
  `PredictionModel.trainAmountModel` (9 features, adds gap-since-last-feed
  and last bottle's oz).
- **Math:** same blend shape — *prior* = `AgeBaselines.ozPerFeed` band
  midpoint for his age (2–4 weeks: 2.0–4.0 oz → 3.0), slid toward the
  **median** of same-day-part bottles, `w = min(n, 15)/15`, clamped to the
  band stretched 1.5 oz each side, rounded to quarter ounces.
- **Data:** trailing **7 days** (`amountHistoryWindow`); 0.5–12 oz
  plausibility filter; < 5 samples → `.low` → hint hidden.

### 1.5 "next nap ~2:15" — the wake window

- **Where:** `WakeWindow.predicted` (`TwoOfUs/Store/WakeWindow.swift:122`) —
  the template the whole engine generalized. Drives the sleep tile hint, the
  tile's urgency dot, widgets, and the watch.
- **Math:** age-band midpoint (0–4 weeks: 45–60 min → 52.5 min) slid toward
  the median of observed **daytime** wake gaps (sleep-end → next
  sleep-start, 15 min–6 h plausible, night wakes excluded),
  `w = min(n, 8)/8`, **clamped back into the age band** — his data can
  position him inside the published range but never outside it.
- **Data — inconsistent (real finding):**
  - `QuickLogger.sleepTarget` and `WidgetProvider` pass sleeps from the
    trailing **7 days**;
  - `HomeView.sleepTarget` (`HomeView.swift:495`) passes its unwindowed
    `@Query` — **all-time history**. At 4 weeks that's already a 4-week
    equal-weight average; at 6 months the Home tile would be averaging
    newborn wake gaps into a half-year-old's projection, and Home would
    quietly disagree with the widget. This is the one place the "averages
    all data equally" concern is literally true today.

### 1.6 Nap-length / night-stretch / predicted-wake

- **Where:** `PredictionEngine.sleepDuration` (`PredictionEngine.swift:196`),
  used by the sleep hint's "usually ~1h20m" suffix, the active-sleep card's
  "wake ~2:55", and the Live Activity footer (`ScheduleAssembly.predictedWakeAt`).
- **Math:** same blend — prior = `AgeBaselines.napDuration` /
  `nightStretch` band midpoint by age, median of same-class completed sleeps
  (nap vs night by start time), `w = min(n, 8)/8`, clamped *into* the band.
- **Data:** trailing **14 days**; naps 15 min–4 h plausible, night stretches
  30 min–13 h.

### 1.7 The nighttime schedule's anchor math

- **Where:** `NightSchedule` (`TwoOfUs/Store/NightSchedule.swift`),
  `NightScheduleGenerator`.
- **Math:** **no statistics at all, by design.** The anchor is the last
  logged feed + the configured *night spacing*; later slots are
  anchor + k·spacing until the window closes, with slots slid to awake
  parents (never more than half the spacing). The schedule is a
  parent-authored contract; log-based prediction was deliberately removed
  from it 2026-07-25.
- **Dead code:** `NightScheduleGenerator.predictedNextFeed` — a plain
  **mean of the last 6 gaps** — is no longer called from app code (tests
  only). It's the only surviving simple-average predictor, and it predicts
  nothing anymore.

### 1.8 Stats displays (not predictions, for completeness)

`StatsEngine.averageFeedInterval` is a plain mean over an explicit day range
— it powers "vs typical day" comparisons, where equal weighting inside the
chosen range is the *point*. `BabyIntelligence.outlook` (Foundation Models)
narrates numbers the engine computed and is forbidden from inventing any.

### Summary table

| Prediction | Estimator | Window | Prior | Min/full samples | Clamp |
|---|---|---|---|---|---|
| Next feed time (AI) | median of day-part gaps, blended | 14 d | config interval | 5 / 15 | 0.6–1.5× target |
| Next feed time (plain) | none — config only | — | config interval | — | — |
| Bottle size | median of day-part oz, blended | 7 d | age band midpoint | 5 / 15 | band ± 1.5 oz |
| Wake window | median of day wake gaps, blended | 7 d (widgets) / **∞ (Home!)** | age band midpoint | 3 / 8 | inside band |
| Nap / night-stretch length | median of same-class durations, blended | 14 d | age band midpoint | 3 / 8 | inside band |
| Night schedule slots | none — config spacing | — | config | — | — |
| Ridge challengers | equal-weight regression, age feature | 45 d | (clamped like champion) | 24 train / 20 score | same as champion |

---

## 2. The problem — how equal weighting fails here

The failure is not "week-1 data dilutes week-4 data" in the all-time sense —
the windows already cut that off. It's subtler and still real:

**A windowed, unweighted median lags a step change by half the window's
occupied span.** The median flips only when the new regime holds more than
half the samples in the window. Feed gaps look back 14 days, so a genuine
shift — a growth spurt, dropping a night feed, stretching from 2.5 h to
3.5 h — takes **several days** to move the number, and until it flips the
prediction is *exactly* the old value (medians don't glide, they jump).

Concretely, with the 14-day gap window at newborn cadence (~5 usable daytime
gaps/day, so the window holds ~70 gaps): the day-gap median doesn't reflect
a new rhythm until it has persisted ~7 days at full window occupancy. In
practice Miller is 4 weeks old so the window isn't yet full — the effective
lag is half of *whatever span the window holds* — but it grows toward that
worst case every day.

Secondary issues found along the way:

1. **`HomeView.sleepTarget` has no window at all** (§1.5) — genuinely
   all-time equal weighting, and inconsistent with widgets/watch/QuickLogger.
2. **The confidence ramp saturates instantly.** `w = min(n, 15)/15` hits 1.0
   with just 15 samples — about two days of feeds. After that the prior
   contributes nothing and the prediction is purely the (laggy) median. So
   in steady state the *entire* behavior is the median's behavior.
3. **Night gaps are sparse.** ~2–3 usable night gaps per night means the
   night-side median rests on ~10–20 samples over two weeks — any window
   shrink must not push these below the 5-sample minimum or the AI hint
   silently disappears every night.

Why the current design is still mostly right: the plausibility filters,
day-part split, cluster collapsing, median, prior, and clamp are all
protecting against real failure modes (mis-logs, forgotten timers, one
chaotic day). Whatever adds recency must not give any of that back.

---

## 3. Options

Throughout, the worked amount example uses the sample data plus a realistic
multi-day ramp, because recency weighting is invisible at hour scale:

- **Sample A (from today):** bottles of 3.0 oz (6 h ago), 3.5 oz (4 h ago),
  4.0 oz (2 h ago), 3.75 oz (now). Age 28 days → band 2.0–4.0 oz, prior 3.0.
- **Sample B (growth-spurt week):** 6 bottles/day for 7 days; days −6…−3 at
  3.0 oz (24 bottles), days −2…0 at 4.0 oz (18 bottles) — a spurt that
  started two days ago.

**Current engine on Sample A:** 4 samples < 5 minimum → returns the prior
3.0 oz at `.low` confidence → **the hint is hidden**. (If a 5th sample
existed, median 3.625, w = 5/15 → 3.0 + 0.33·0.625 ≈ **3.25 oz** — the
prior deliberately dominates when evidence is thin.) An equal-weight mean
would say 3.56 oz; time-decayed weights with a 48 h half-life say 3.57 oz —
**within a single day, recency weighting changes nothing**. The divergence
lives at day scale, which is what Sample B shows.

**Current engine on Sample B:** 42 samples, w = 1.0 → prediction = median.
24 of 42 samples are 3.0 → **median = 3.0 oz**. Two full days into the
spurt, every surface still suggests 3.0. The median flips to 4.0 only when
the 4.0s hold a majority — about **3.5 days after the spurt began**.

### Option A — Exponential Moving Average (EMA)

Replace the median with `EMA_n = α·x_n + (1−α)·EMA_{n−1}` (count-based,
newest last), keeping the prior blend and clamps around it.

- **Sample B, α = 0.15:** starting near 3.0, after 18 spurt bottles:
  `3.0 + (1 − 0.85¹⁸)·1.0 ≈ 3.95 oz`. After just one day (6 bottles) it's
  already at 3.62. Responds in ~1 day.
- **Pros:** O(1), no window needed, glides smoothly instead of jumping,
  trivially explainable.
- **Cons — why it's wrong for this app:**
  - **Loses robustness.** The engine chose medians specifically because a
    plausible-looking outlier (a 6 h car-nap gap at 5.9 h, inside the
    filter) shouldn't move the answer. EMA is a mean; one such gap at
    α = 0.15 yanks the next-feed projection ~20 min all by itself.
  - **Count-based, not time-based.** Ten cluster feeds in one rough evening
    consume ten decay steps and erase yesterday; a quiet day decays nothing.
    The decay should follow the calendar, not the log rate.
  - Needs a seed and an ordering pass anyway once the day-part split is
    applied, so the O(1) elegance mostly evaporates.

### Option B — Smaller sliding window

Keep everything, shrink `feedHistoryWindow` 14 d → 4–5 d and
`amountHistoryWindow` 7 d → 3 d.

- **Sample B, 3-day amount window:** window holds days −2…0 = all 4.0s →
  **median 4.0 oz** immediately. Lag becomes ~1.5 days.
- **Pros:** a two-line constant change; zero new math.
- **Cons:**
  - **Variance up, sample counts down.** A 3-day amount window at 6
    bottles/day holds ~18 day-part-split samples — fine — but the *night*
    side of a 4-day gap window holds ~8–10 gaps, and one unsettled night
    (all gaps < 1 h or clustered) can push it under the 5-sample minimum:
    the AI hint would flicker off exactly on the hard nights.
  - Still a cliff: events are 100%-weight until they fall off the edge, then
    0% — a 4-day-old chaotic day counts fully, a 5-day-old normal day not
    at all.
  - Hurts the challenger too if applied naively — the ridge model *wants*
    long history (its age feature de-stales it); its 45-day window should
    not shrink.

### Option C — Age-adjusted baseline + deviation

Use published age norms as the prior and the baby's deviation from them as
the signal. **This is essentially already the architecture**: `AgeBaselines`
/ `WakeWindow.bands` are the prior, the blend is the deviation, the clamp
keeps the result age-plausible, and the ridge challenger's age/100d feature
explicitly models the trend. Two genuine refinements remain:

1. **Interpolate the prior within/between bands** instead of stepping at
   band edges — midpoint-of-band means the prior jumps (e.g. 3.0 → 4.0 oz
   overnight on day 28). A linear ramp by age removes the discontinuity the
   parents can currently watch happen on a band birthday.
2. **Model the deviation, not the level:** predict
   `his_value = age_baseline(today) × ratio`, where *ratio* is the median of
   `observed / age_baseline(at that event's date)`. Then week-old samples
   are automatically "inflated" to today's age before averaging — old data
   stops dragging *because it's re-expressed in today's terms*, without any
   decay parameter at all.
- **Sample B with ratio-of-baseline:** if the baseline itself ramps
  3.0 → 3.3 oz over the week, the old 3.0-oz bottles become ratios ≈ 1.0
  and the new 4.0s ≈ 1.25; median ratio still needs a majority to flip —
  so **this fixes trend-following only as far as the published curve bends,
  not Miller's personal spurts**. It complements recency weighting; it
  doesn't replace it.

### Option D — Hybrid: time-decayed weighted median inside the existing blend (recommended)

Keep every existing stage — windows, plausibility filters, day-part split,
cluster collapse, prior, blend, clamp, confidence tiers — and change exactly
one primitive: **the median becomes a weighted median with exponential
time-decay**, and the confidence count becomes the effective sample size.

- Weight per event: `w_i = 2^(−Δt_i / h)` where `Δt_i` is the event's age
  and `h` is the half-life (today ≈ 1.0, `h` days ago 0.5, `2h` days ago
  0.25).
- **Weighted median:** sort values; take the smallest value whose cumulative
  weight reaches half the total weight. Still order-statistic robust — an
  outlier contributes its weight, never its magnitude.
- **Effective sample size** (Kish): `n_eff = (Σw)² / Σw²`. Use `n_eff` in
  place of `n` for both the minimum-samples gate and the blend weight
  `w = min(n_eff, full)/full`, so confidence wording stays honest when the
  evidence is mostly-old.
- **Sample B, h = 2 days:** decayed mass of the 18 spurt bottles ≈ 13.3 vs
  ≈ 5.4 for the 24 old ones → **weighted median = 4.0 oz today**, and
  re-running the flip condition shows it crosses on **day 2 of the spurt
  instead of day ~3.5**. Same shape for feed gaps: with h = 3 d over the
  14-day window, a 2.75 h → 3.5 h stretch that began 5 days ago gives the
  recent regime ~16.6 mass vs ~6.7 → the projection reads **3.5 h**, where
  the unweighted median still says 2.75 h (a 45-minute miss — the
  bottle-warmed-too-early kind).
- **Why this beats A and B:** it is time-based (a chaotic evening of
  cluster feeds decays as one evening, not ten steps), it never cliffs (old
  events fade, they don't vanish), it keeps the median's outlier immunity,
  and the night-side sparsity problem is handled by `n_eff` — thin recent
  nights *lower confidence* toward the prior instead of flickering the
  feature off.
- **Cost:** ~15 lines in `blend` plus a weighted-median helper; all pure,
  all unit-testable next to the existing `WakeWindowTests`.

#### Proposed parameters

| Prediction | Window (keep) | Half-life *h* | Gate/full (on n_eff) |
|---|---|---|---|
| Feed gaps | 14 d | **3 d** | 4 / 12 |
| Bottle size | 7 d | **2 d** | 4 / 12 |
| Nap & night-stretch length | 14 d | **4 d** | 3 / 8 |
| Wake window | **7 d everywhere** (fix Home) | 3 d (optional, phase 2) | 3 / 8 |

Rationale: half-life ≈ the timescale on which a newborn's pattern genuinely
shifts (2–4 days), windows kept as the hard mis-log horizon. Gates drop
slightly because `n_eff` runs below raw *n* (with h = 2 d over a full 7-day
window, `n_eff` ≈ 0.4–0.5 × n).

#### Validation for free

`PredictionAccuracy` already replays the trailing 30 days walk-forward and
scores median absolute error per predictor — the exact harness needed to
prove (or disprove) the half-life choice **on Miller's real history before
anything ships**. Concretely: implement the weighted median behind a
parameter, run the accuracy report for h ∈ {1.5, 2, 3, 4, ∞} days
(∞ = today's behavior) in a unit test against exported real data, and keep
the winner. The champion/challenger machinery means even after shipping,
the ridge model keeps auditing the statistic — and if recency weighting is
wrong, `modelWins` will say so. Optionally, the same decay weights can later
be applied as row weights in `RidgeRegression.fit` (weighted least squares —
a two-line change) so the challenger gets recency too.

---

## 4. Recommendation

**Adopt Option D**, in this order:

1. **Bug-fix first (no behavior debate needed):** window
   `HomeView.sleepTarget` to 7 days to match `QuickLogger`/widgets — today
   it equal-weights all-time history and diverges from every other surface.
2. Add `weightedMedian` + Kish `n_eff` to the blend; thread a half-life
   through `PredictionEngine`'s constants (feed gaps 3 d, amounts 2 d,
   sleep 4 d). Keep windows, filters, clamps, and priors exactly as they
   are.
3. Tune the half-lives with `PredictionAccuracy` walk-forward on real
   exported history before merging; keep h = ∞ if it genuinely scores best
   (the harness outranks this document).
4. Leave alone: the night schedule (contract, not forecast), the feed
   alarm, the plain-hint fallback, and the ridge challenger's 45-day
   window. Delete or comment-mark `NightScheduleGenerator.predictedNextFeed`
   (dead simple-mean code).
5. Skip Option C's ratio-of-baseline for now — most of its value arrives
   automatically via the ridge challenger's age feature; revisit if the
   accuracy card shows the statistic losing systematically around band
   birthdays.

---

## 5. Questions for Taylor

**On what's actually wrong today**
1. What triggered this — a specific miss? E.g. "the tile said next ~2:30
   and he was screaming at 1:45," and had his rhythm changed in the days
   before? (That distinguishes *lag* — this doc's target — from *bias* or
   *variance*, which want different fixes.)
2. Which surface matters most when it's off — the Feed tile time, the oz
   suggestion, the nap hint, or the predicted-wake on the Live Activity?
   Tuning order should follow real use.

**On error direction**
3. Should feed-time predictions deliberately run *early* (bottle warm
   before the cry) rather than symmetric? An asymmetric nudge — e.g.
   predict the 40th percentile gap instead of the 50th — is a one-line
   change on top of the weighted median, but it should be a product
   decision, not a math accident.
4. Same for oz: is over-preparing (predicting high, pouring a little extra)
   cheaper than under-preparing? Formula down the drain vs a second warm-up
   mid-feed.

**On how much "last night" should count**
5. Should last night's pattern strongly shape *tonight's* predictions
   (h ≈ 1–2 days for the night side specifically), or is night-to-night
   variance so high that the weekly rhythm is the better anchor (h ≈ 4 d)?
   One rough night steering tonight's expectations is exactly what a short
   half-life buys — and exactly what it risks.
6. The night *schedule* stays config-driven on purpose. Confirm: recency
   math should never move the planned slots or alarms, only the ✦ hints?

**On thresholds**
7. With `n_eff` gating, thin-data nights degrade toward the age/config
   prior at `.low` confidence instead of hiding the hint. Is showing a
   clearly-hedged prior-based hint ("likely ~") better than showing
   nothing? Current behavior hides it.
