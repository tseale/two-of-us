# Two of Us — Design Language

> **What this file is.** The portable design system for *Two of Us*, a native iOS baby-tracking
> app for two parents. This file is the shared contract between **Claude Design**
> (claude.ai/design — mockups, explorations, new screens) and **Claude Code** (the SwiftUI
> implementation). Upload it to Claude Design to scaffold a faithful UI kit; hand exported
> designs back to Claude Code with this file as the reference.
>
> **Source of truth.** The values below are extracted directly from the implementation —
> `TwoOfUs/DesignSystem/` (tokens) and `TwoOfUs/Features/` (components) — as of commit
> `c05d891` (June 12, 2026). If this file and the Swift code disagree, the Swift code wins —
> update this file to match (see §10, Agent Guide).
>
> **Companion docs.** [`docs/DESIGN.md`](docs/DESIGN.md) covers iOS screen flows and behavior
> (states, onboarding, roles, accessibility); this file owns the visual language. The PNGs in
> `mockups/` are early concepts kept for history — don't design from them. Precedence when in
> conflict: Swift code → this file → docs/DESIGN.md.

---

## 1. Visual Theme & Atmosphere

**One line:** *calm, not clinical* — readable in 1.5 seconds, at 3am, one-handed, holding a baby.

- **Mood:** warm, soft, reassuring. A nursery at night, not a hospital chart. Rounded numerals,
  pastel accents over near-black or soft-gray grounds, generous breathing room.
- **Density:** low. One idea per card. Big glanceable numbers with quiet labels above them.
- **Tone of voice:** gentle and human. "Miller is sleeping", "next bottle ~10:45",
  "No events yet — tap 🍼 to log Miller's first feed." Emoji are part of the visual language
  (🍼 💤 💩), used as icons, not decoration.
- **Energy:** *quiet until it matters.* Status is calm gray at rest; color appears only when
  something is due (amber) or overdue (red). No badges, no alarms, no red dots at rest.
- **Sound:** none, ever. The baby may be asleep. Haptics + visuals are the only feedback.
- **Appearance:** light **and** dark are first-class; dark is the reference mood
  (the app is used mostly at night).

---

## 2. Color Palette & Roles

All colors are **semantic tokens** — components never reference raw hex. Neutral tokens resolve
per appearance; accents and urgency hues are fixed across both.

```css
:root {
  /* Neutrals — light appearance */
  --bg:        #F2F2F7;  /* app background */
  --card:      #FFFFFF;  /* primary surface (read-only cards, rows) */
  --card2:     #ECECF0;  /* raised surface (buttons inside sheets, toast) */
  --separator: #D1D1D6;  /* hairline dividers, 0.5px strokes */
  --text:      #000000;  /* primary text */
  --text2:     #6C6C70;  /* secondary text, eyebrow labels */
  --text3:     #8E8E93;  /* tertiary text, hints, timestamps */

  /* Event accents — fixed in both appearances */
  --accent-feed:   #5AC8B8;  /* teal — feeds, also the global tint/brand accent */
  --accent-sleep:  #8E8EFF;  /* periwinkle — sleep */
  --accent-diaper: #F5B971;  /* warm amber — diapers */

  /* Urgency scale (time-since indicators) */
  --urgency-green: #5AD17E;  /* recent — drawn as NOTHING extra (calm gray text) */
  --urgency-amber: #F5B971;  /* due soon — 8px dot + tinted since-line */
  --urgency-red:   #FF6B6B;  /* overdue — 8px dot + tinted since-line */
  --urgency-amber-text: #B87B1E;  /* darkened amber, readable as body text */
  --urgency-red-text:   #D94F4F;  /* darkened red, readable as body text */

  /* Night stage (celebration screens, sleep Live Activity) */
  --night-ink:        #130E18;  /* deep warm plum-indigo — "nursery at 3am", not blue-black */
  --nightlight-cream: #FFF4E8;  /* warm cream — text & glow on the night stage */

  /* Indigo gradient — the ONE intentional delight surface
     (Stats record hero, sleep Live Activity background).
     Ratified as AppColor.indigoHi / indigoLo / indigoNight. */
  --indigo-hi: #2A2A4D;
  --indigo-lo: #1C1C2E;  /* Live Activity runs it deeper: indigo-hi → indigo-night */
  --indigo-night: #15151F;
}

@media (prefers-color-scheme: dark) {
  :root {
    --bg:        #000000;
    --card:      #1C1C1E;
    --card2:     #2C2C2E;
    --separator: #38383A;
    --text:      #FFFFFF;
    --text2:     #98989F;
    --text3:     #636366;
    --urgency-amber-text: #F0B05A;  /* brightened for dark surfaces */
    --urgency-red-text:   #FF8A8A;
  }
}
```

**Participant palette** — each caregiver gets a fixed identity color for attribution badges,
assigned in order, avoiding collisions:

```css
--participant-1: #5AC8B8;  /* teal */
--participant-2: #8E8EFF;  /* periwinkle */
--participant-3: #F5B971;  /* amber */
--participant-4: #FF8FA3;  /* pink */
--participant-5: #7FB2FF;  /* blue */
--participant-6: #B6E36B;  /* green */
```

**Rules:**
- Urgency is conveyed by **presence of color + a dot + the wording**, never hue alone
  (must work without red-vs-green discrimination; VoiceOver speaks "recent / due soon / overdue").
- The event accents (teal/periwinkle/amber) are the identity of the three event types —
  every surface that represents a feed is teal-tinted, sleep is periwinkle, diaper is amber.
- Contrast meets WCAG AA in both appearances.

---

## 3. Typography Rules

Two families, **split by role, not by size**:

| Role | iOS face | Web fallback | Notes |
|---|---|---|---|
| **Glance numerals** — timers, "time since", counts, records | SF Rounded, bold–heavy, `monospacedDigit` | `"Nunito", "Quicksand", sans-serif` + `font-variant-numeric: tabular-nums` | Anything read in ~1.5s. Mono digits so ticking values never jitter. |
| **Hero titles** — baby's name, celebration titles | SF Rounded bold | `"Nunito"`, 700 | Warm, human. 28–34px. |
| **Everything else** — body, labels, hints | SF Pro | `"Inter", -apple-system, sans-serif` | Legibility first. Body 15–17px, captions 11–13px. |

```css
--font-round: "Nunito", "Quicksand", ui-rounded, sans-serif;  /* SF Rounded stand-in */
--font-text:  "Inter", -apple-system, "SF Pro Text", sans-serif;

/* Type scale (px ≈ pt) */
--display-xl: 48px/800;  /* active sleep timer */
--display-lg: 38px/800;  /* record hero value */
--display-md: 26–30px/700;  /* metric values, widget timers */
--hero:       28–34px/700;  /* baby name, page heroes */
--title:      17–20px/700;  /* tile titles (rounded) */
--body:       15–17px/400–600;
--caption:    11–13px/400–600;
--eyebrow:    11px/600, UPPERCASE, letter-spacing 0.6px, color var(--text2);
```

**The signature unit — `MetricStack`:** an uppercase tracked **eyebrow label** (`--eyebrow`,
quiet, recedes) sitting *above* a **big rounded mono number**, with an optional tertiary caption
below. Reused on Home, the active sleep card, Stats, and widgets. When in doubt, build glance
info as a MetricStack.

Rounded faces are for **numerals and heroes only** — never body text. All text scales with
Dynamic Type (web: rem-based); large values get `min-scale 0.7` / single line.

---

## 4. Component Stylings

### Log tile (the primary action — Feed / Diaper / Sleep)
The most important component in the app. Status display and button in one.
- **Surface:** interactive "liquid glass" tinted with the event accent at 18% —
  web stand-in: `background: color-mix(in srgb, var(--accent-feed) 18%, transparent)` +
  `backdrop-filter: blur(20px)`; radius **20px**; min-height **96px**; padding **18px**.
- **Content (leading column):** emoji 30px → title (17px bold rounded) → *since-line*
  (15px: "2h 40m since last") → hint caption ("next bottle ~10:45", `--text2`).
- **Urgency:** at green the since-line is plain `--text2`, nothing else. At amber/red it takes
  `--urgency-*-text` plus an **8px dot** before the text.
- **⊕ badge** top-right corner (22px, accent color) so the status-bearing tile still reads as a button.
- **Press:** scale 0.96 with a quick spring; medium haptic.
- **Layout:** Feed + Diaper side-by-side (highest-frequency); Sleep full-width below.
  When sleep starts, the Sleep tile **morphs in place** into the active-sleep card —
  Feed and Diaper never move.

### Active sleep card
Full-width periwinkle glass tile (radius 22, padding 20), centered: 💤 34px → eyebrow
"MILLER IS SLEEPING" (periwinkle) → elapsed timer (48px heavy rounded mono) → "since 7:42 PM"
caption → **Wake up ☀️** button (full-width, solid periwinkle fill, white text, radius 16,
14px vertical padding). Success haptic on wake.

### Surface card (read-only data)
Solid `--card` fill, radius **18px** (Today ribbon: 20), **0.5px hairline** border
(`--separator` @ 50%), padding 14–16px. Used for: Today ribbon card, timeline, History/Stats
cards, Settings rows. Card header = eyebrow title left + quiet caption right.

### Day ribbon (signature data-viz)
A 24-hour horizontal strip, reused on Home, History swimlanes, and widgets:
- A 1px baseline at ~66% height. **Above it:** instantaneous marks at their time-of-day x-position —
  🍼 for feeds, 💧/💩 for diapers (near-simultaneous marks nudge apart, never stack).
- **Below it:** sleep spans as pale periwinkle pills (35% opacity) with "z z z" lettering inside
  when they fit.
- A dashed 1px "now" line (55% opacity) spanning both lanes, today only.
- Sizes: 40px tall on Home, 16px in History swimlanes (slim ribbons drop the z z z).
- Monochrome variant for tinted/lock-screen contexts: ● feed · ○ diaper (hollow ring) · — sleep bar.

### Timeline row
Left-to-right: **time gutter** (64px, right-aligned, mono caption, `--text3`) → **rail**
(2px vertical line, `--separator` @ 60%, with an 11px accent node per event; sleep nodes are
capsules whose height scales with duration, 14–30px; nodes carry a 2px `--card` ring so the
rail passes behind) → emoji + title (15px semibold) → **participant badge** right.
Min height 46px. A "NOW" eyebrow cap with a hollow ring sits at the top.
Tap → edit sheet; swipe-left → delete (confirm + warning haptic).

### Participant badge
24px filled circle in the participant's identity color, white bold initial. Larger avatar
variant (36–64px) uses photo or monogram-on-color fallback (initial at 44% of the size).

### Sheets (Feed / Diaper / Edit / quick-log)
Bottom sheets, medium detent (Feed also large), visible drag indicator, title with emoji
("Log a feed 🍼"). Content patterns:
- **Preset chips** (Feed oz: 2/3/4): equal-width, radius 14, stacked value+unit; selected =
  accent stroke 2px + accent fill @ 25%.
- **Choice buttons** (Diaper Wet/Dirty/Both): equal-width `--card2` tiles, radius 16, emoji over
  label, one tap logs-and-dismisses (success haptic).
- **Time control**: every log sheet defaults to "now" with a compact date picker + a teal
  "Now" reset button. Backdating is one tap away, never required.

### Toast (undo)
Bottom-floating `--card2` capsule, padding 18×14, message left + bold teal "Undo" right;
shadow `0 4px 12px rgb(0 0 0 / 0.25)`; slides up + fades; auto-dismisses in 3s.

### Record hero (Stats)
The one gradient surface: linear-gradient `--indigo-hi → --indigo-lo`, radius 18.
Eyebrow "🏆 RECORD — LONGEST SLEEP" → 38px heavy display value → date caption. The same
gradient family backs the sleep Live Activity, so in-app and lock-screen sleep share a language.

### Stat tiles
2-column grid, gap 12. Each: surface card, padding 14 — caption key ("🥛 Total milk") →
28px display value in the event accent → tertiary unit line ("≈ 3 gallons").

### Charts (History)
Swift Charts style: 120px tall, accent-colored. Line charts: 2.5px, round caps, smoothed
(catmull-rom), area fill fading from accent @ 35% → 2%. Bar charts: accent gradient bars,
radius 6, ~58% width, optional dashed average rule. Axes whisper: narrow weekday labels,
3 y-ticks, `--text3`.

### Empty states
Centered: a gently bobbing emoji (46px, ±5px, 1.9s ease loop, disabled under reduced motion) →
headline (rounded) → one supportive sentence (`--text2`). Always name the next action:
"tap 🍼 to log Miller's first feed."

### Settings
Standard grouped iOS form. Custom row icons: 20×20 rounded-square (radius 7) accent fill with
white SF Symbol. Role pills: capsule, caption semibold, tint fill @ 16%.

### Brand mark — "CradleMark"
Two overlapping glowing circles (periwinkle + teal — the two parents) screen-blended over
black into a bright shared lens, with a warm cream point of light (the baby) cradled low in
the overlap. **Dark backdrops only.** Used on launch, the join flow, and celebrations.

---

## 5. Layout Principles

- **8-point rhythm.** Common steps: 4 / 8 / 12 / 16 / 20 / 24 / 28. Screen gutter 16px;
  vertical card gap 12–14px.
- **One column.** Phone-first single column of cards; the only grid is the 2-column stat tiles.
- **Thumb-reach hierarchy:** glance info (ribbon, metrics) up top; **actions in the lower half**;
  the Wake button at the very bottom of its card. Primary actions are never at the top of the screen.
- **Three tabs:** Home (log + glance) · History (7-day trends) · Stats (records & patterns).
  Settings is a sheet from Home, not a tab. Navigation is 1–2 levels deep, never more.
- **Tap targets:** 44×44px minimum everywhere; the log tiles are ≥96px tall on purpose.
- **Fixed-height CTA bars** in flows (onboarding): page dots + 52px primary button +
  44px secondary slot — heights never jump between steps.

---

## 6. Depth & Elevation

Hierarchy through **material, not shadow**. Two layers:

| Layer | Treatment | Used for |
|---|---|---|
| **Glass** (floats, interactive) | translucent blur + accent tint 18%, touch-responsive | log tiles, active sleep card, tab bar, onboarding input fields |
| **Surface** (sits, read-only) | solid `--card` + 0.5px hairline | data cards, timeline, charts, settings |

- **Never stack glass on glass.** Glass elements sit directly on `--bg`.
- Shadows are nearly absent — the only real shadow is under the floating toast.
  Web previews should resist the urge to add elevation shadows to cards.
- The **indigo record gradient** is the single intentional "delight" surface; don't add more.

---

## 7. Motion & Feedback

Subtle and quick. Nothing bounces for attention.

| Event | Motion |
|---|---|
| Tile press | scale → 0.96, spring (response 0.3, damping 0.6) |
| Sleep tile ⇄ active card | in-place morph, spring (0.45, 0.8), fade + scale 0.96 |
| Toast | slide-up + fade, spring 0.3s; auto-out at 3s |
| Screen/route changes | 0.35s ease-in-out cross-fade |
| Empty-state emoji | ±5px bob, 1.9s ease loop |
| Onboarding entrances | fade + 16px rise, spring (0.5, 0.7), staggered 0.08s |
| Timers | **digits change with no animation** — tabular numerals only, no flip/bounce |

- **Reduce Motion:** every non-essential animation drops to an opacity fade or nothing.
- **Haptics are the confirmation channel** (the app is silent): medium impact on tap,
  success on log/wake, warning on delete.

---

## 8. Do's and Don'ts

**Do**
- Build glance info as MetricStack: quiet uppercase eyebrow above a big rounded mono number.
- Keep green-state UI completely quiet — color appears only at amber/red, always with a dot + words.
- Tint every feed/sleep/diaper surface with its event accent; keep the mapping absolute.
- Use emoji (🍼 💤 💩 💧) as the iconography for event types.
- Keep both appearances in mind; design dark first (3am is the real use case).
- Name the user's next action in every empty state.
- Keep Feed and Diaper stationary when Sleep state changes.

**Don't**
- Don't use rounded faces for body text, or proportional digits for anything that ticks.
- Don't add shadows, borders, or gradients to cards beyond the hairline — the indigo record
  hero is the only gradient.
- Don't put glass on glass, or make read-only cards look tappable (no glass on data).
- Don't use red/amber as decoration — urgency colors are earned by elapsed time only.
- Don't add sounds, confetti, badges, or attention-seeking motion. Calm is the product.
- Don't hardcode hex values in components — everything routes through the tokens in §2.
- Don't bury actions above the fold or outside thumb reach.

---

## 9. Platform & Responsive Behavior

- **Native iOS (SwiftUI), iPhone-first**, iPad supported via the same single-column layouts
  with wider gutters. Web artifacts from Claude Design are *previews/specs*, not the product —
  frame mockups at iPhone widths (390–430pt) by default.
- **Dynamic Type to XXL:** layouts reflow, display values shrink to 0.7 before truncating,
  nothing clips. On web, use rem units and test at 1.4× root size.
- **Dark/light follow the system**; both must hold AA contrast.
- **Glanceable companions** share the language at tiny sizes: lock-screen widgets use the
  monochrome ribbon variant; the Dynamic Island sleep timer is `💤 23:47` compact /
  moon + timer + an interactive **Wake up ☀️** button expanded, over the deep indigo
  gradient. The lock-screen Live Activity carries the same Wake button (solid periwinkle,
  radius 16), mirroring the in-app active-sleep card.
- Touch targets ≥44px; no hover-dependent affordances (it's a touch product).

---

## 10. Agent Guide — collaborating across Claude Design & Claude Code

**Round-trip contract.** This file is the interchange. The Swift implementation is canonical;
this spec mirrors it. Keep them in sync in both directions:

| This file (§) | Swift source of truth |
|---|---|
| §2 Colors | `TwoOfUs/DesignSystem/Colors.swift` (`AppColor`, `ParticipantColors`) |
| §3 Typography | `TwoOfUs/DesignSystem/Typography.swift` (`AppFont`, `MetricStack`, `.sectionLabelStyle()`) |
| §4 Urgency behavior | `TwoOfUs/DesignSystem/Urgency.swift` (green <0.66 · amber ≤1.0 · red >1.0 of target interval) |
| §4 Day ribbon | `TwoOfUs/DesignSystem/DayRibbon.swift` |
| §4 Brand mark | `TwoOfUs/DesignSystem/CradleMark.swift` |
| §6 Glass/surface | `Colors.swift` extensions: `.glassTile()`, `.glassCard()`, `.surfaceCard()` |
| §7 Haptics | `TwoOfUs/DesignSystem/Haptics.swift` |
| Screens & flows | `TwoOfUs/Features/*`, spec in `docs/DESIGN.md` |

**Prompts for Claude Design** (paste with this file):
- *"Using this DESIGN.md, scaffold the design system: token swatches (light + dark), the type
  ramp, and component cards for the log tile (all three urgency states), active sleep card,
  timeline, day ribbon, toast, and feed sheet."*
- *"Design a new ‹screen/feature› for Two of Us in this system. Dark mode first, iPhone 390pt
  frame, single column, actions in the bottom half, MetricStack for any glance value."*

**Prompts for Claude Code** (when bringing a design back):
- *"Implement this Claude Design export in SwiftUI. Map every color to an `AppColor` token and
  every numeral to `AppFont.display`; use `.glassTile`/`.surfaceCard` per §6 — flag anything
  in the design that has no existing token instead of hardcoding it."*
- *"I changed ‹token/component› in the app — update DESIGN.md §‹n› to match."*

**Change protocol:** new tokens are *proposed* in a design, *ratified* by adding them to
`Colors.swift`/`Typography.swift`, then recorded here — in that order. A design that needs a
seventh participant color, a fourth accent, or a second gradient is a flag to pause and discuss.
