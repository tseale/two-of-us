# Visualizations & Stats — Design Exploration

> **Status:** Forward-looking ideation for the deferred charts/stats phase. No code yet.
> See [BUILD_PLAN.md](BUILD_PLAN.md) for where this lands in the roadmap.

Today every surface shows **"time since last X"** — a single number per event
([SmallEventWidget.swift](../TwoOfUsWidgets/SmallEventWidget.swift),
[MediumWidget.swift](../TwoOfUsWidgets/MediumWidget.swift),
[LargeWidget.swift](../TwoOfUsWidgets/LargeWidget.swift)). This doc explores the
next axis: **distribution over time** ("*when* did things happen") and **history / trends**.

## Grounding constraints

- **3 events:** feed (instant + `amountOz`), sleep (duration: `startedAt`/`endedAt`),
  diaper (instant + `type`: wet/dirty/both). **Sleep is the only span event** — it's the
  interesting rendering case in every visualization below.
- **Palette:** feed `#5AC8B8` teal · sleep `#8E8EFF` periwinkle · diaper `#F5B971` amber ·
  urgency green→amber→red ([Colors.swift](../TwoOfUs/DesignSystem/Colors.swift),
  [Urgency.swift](../TwoOfUs/DesignSystem/Urgency.swift)).
- **Attribution is free:** every event carries `loggedByID` / `loggedByName` /
  `loggedByColorHex` → parent-split stats need no new data.
- **Philosophy:** calm not clinical, dark from day 1, silent (haptics only), one-handed,
  readable at 3am.
- **Lock-screen accessory widgets are monochrome-tinted** → encode by **shape/position,
  not color**. Home-screen widgets get full color.
- Reuse `EventStore.timeline(since:)` and `lastEventDate(of:)`
  ([EventStore.swift](../TwoOfUs/Store/EventStore.swift)); reads go through the App Group
  container, no app launch.

---

## 1. Lock screen — "when did things happen today"

Encode by shape/position (monochrome tint). Feeds/diapers = instantaneous ticks;
sleep = a segment spanning its duration.

| Idea | Family | What it shows |
|---|---|---|
| **24h ribbon** *(recommended)* | `.accessoryRectangular` | Horizontal strip = last 24h / since midnight. Feed = filled dot, diaper = hollow dot, sleep = underline bar spanning duration. Whole-day rhythm in one glance. |
| **Radial clock dial** | `.accessoryCircular` | 12/24h dial, marks at each event's clock-angle; sleep arcs as a rim stroke. |
| **Next-feed gauge ring** | `.accessoryCircular` | Progress ring toward target interval, urgency-colored. Complements the "since" number. |
| **Micro 3-event list** | `.accessoryRectangular` | `🍼 2:40 · 💤 1:10 · 💩 0:30` — denser than today's single-event widget. |
| **Inline next-up** | `.accessoryInline` | `Next bottle ~3:40pm` above the clock. |

**Home screen (full color):** the ribbon/dial becomes color-coded; add a "today so far"
strip above the existing time-since rows in the medium/large widgets.

## 2. In-app Home tab — glanceable "today" + log

The Home tab is the most-visited surface, so the lightweight visualization belongs here too
(not only in History). Above the existing time-since status and quick-log:

- **"Today so far" ribbon** — the full-color 24h strip (feed dots, diaper dots, sleep spans)
  with a "now" marker and a one-line total (`🍼 5 · 💤 4h10 · 💩 6`). Same component as the
  home-screen widget ribbon, reused in-app.

Deep multi-day charts stay in History/Stats — Home keeps a single glance + the log buttons.

## 3. In-app history — trends over days/weeks (Swift Charts)

Status: ✅ = implemented in `Features/History/HistoryView.swift` (aggregations in
`Store/StatsEngine.swift`).

- ✅ **Day-in-the-life swimlane (Gantt)** — *the* core chart. 24h axis, one row per day
  (last 7). Sleep = bars, feeds/diapers = marks. Watch the rhythm form: naps
  consolidating, night stretch lengthening.
- ✅ **Sleep consolidation line** — longest continuous night stretch over time. Emotionally
  rewarding: the line climbs as Miller starts sleeping through.
- ✅ **Total sleep per day** — daily total-sleep bars with a weekly-average rule
  (complements the consolidation line: stretch vs. total).
- ✅ **Feed volume** — daily total oz bars + dashed average rule. *(Remaining: avg-interval
  trend line, oz-per-feed distribution.)*
- ✅ **24h feed heatmap** — day × 24h grid (opacity ramps with feeds-per-hour); reveals
  his natural feeding schedule.
- ✅ **Diaper trend** — wet / dirty / both stacked bars per day (monochrome-amber shades;
  doubles as a health signal pediatricians ask about).
- ✅ **Today summary card** — "Today so far" on Stats: today's feeds/oz/sleep/diapers vs the
  trailing 7-day average ("+3 oz vs avg").

Keep calm: soft fills, rounded bars, existing accents, gentle gridlines.

## 4. Fun / delightful stats (the emotional layer)

Status: ✅ = implemented in `Features/Stats/StatsView.swift`.

- ✅ **Records** — "Longest sleep: 6h 12m on May 28."
- ✅ **Lifetime in fun units** — "412 oz ≈ 3.2 gallons 🥛"; "1,130 hours slept";
  "847 diapers changed."
- ✅ **Night-shift split** — "Night MVP this week: Mom, 7 of 9 feeds" (uses `loggedByID`;
  light, not competitive).
- ✅ **Streaks & milestones** — first 4/5/6/8-hour sleep, 50/100/250/500th bottle,
  100/250/500th diaper, current logging streak, and the next bottle milestone.
- ✅ **Both-parents contribution** — "🤝 Teamwork": all-time split of who logged what
  (non-competitive companion to the night-shift card).
- ✅ **"On this day"** — "A week ago, every 2h; now every 3h."
- ✅ **Hungriest hour** — "He's hungriest around 6pm."
- **Weekly/monthly recap card ("Miller Wrapped")** — auto-generated **shareable image**
  to text grandparents. *(Not built — the one remaining delight feature.)*

## Notes for the future build phase

- **Sleep-as-span rendering is the shared hard part** (ribbon segments, Gantt bars,
  consolidation metric) — solve once, reuse everywhere.
- New aggregation helpers (daily totals, longest-stretch, per-hour buckets,
  per-participant counts) belong alongside `EventStore`; all derivable from existing
  fields — **no schema change**.
- Recap card = render a SwiftUI view to image; reuse the same chart components.
