# Two of Us — Design

**Status**: v1 design — locked June 5, 2026 · amended June 12, 2026 to match the implementation (day ribbon replaced the day-arc concept; HTML mockup retired in favor of the design-language spec) · amended November 12, 2026 for iPhone Duo (the ground and the light — see Surfaces & depth)
**Principle**: calm, not clinical. One-thumb operable. Readable at a glance, at 3am, holding a baby.
**Platforms**: iPhone (iPhone Duo included — its layouts are in [`IPHONE_DUO.md`](IPHONE_DUO.md)) + iPad · **Appearance**: light + dark, follows the iOS system setting.

The portable design-language spec — used for Claude Design collaboration and as the visual reference — lives at [`DESIGN.md`](../DESIGN.md) (repo root). It is extracted from the implementation; this document covers iOS screen flows and behavior.

---

## Design system

### Color
Colors are defined as **semantic tokens** that resolve differently in light vs dark. Never hardcode a hex in a view — reference the token. Hex values below are the dark-mode reference; both appearances' values live in `DesignSystem/Colors.swift` and [`DESIGN.md`](../DESIGN.md) §2.

| Token | Role | Dark ref |
|---|---|---|
| `bg` | App background | `#000000` |
| `card` | Card / surface | `#1C1C1E` |
| `card2` | Raised surface (buttons in sheets) | `#2C2C2E` |
| `separator` | Hairline dividers | `#38383A` |
| `text` / `text2` / `text3` | Primary / secondary / tertiary text | `#FFFFFF` / `#98989F` / `#636366` |
| `accentFeed` | Feed (teal) | `#5AC8B8` |
| `accentSleep` | Sleep (periwinkle) | `#8E8EFF` |
| `accentDiaper` | Diaper (warm amber) | `#F5B971` |

**Urgency scale** (applied to the time-since indicators):

| State | Token | Dark ref | Meaning |
|---|---|---|---|
| Fresh | `urgencyGreen` | `#5AD17E` | recently done |
| Approaching | `urgencyAmber` | `#F5B971` | nearing target interval |
| Overdue | `urgencyRed` | `#FF6B6B` | past target |

Thresholds derive from `SharedSettings.targetFeedInterval` for feed; sleep and diaper use sensible per-category defaults. Urgency is conveyed by **both color and the value position** (never color alone — see Accessibility).

### Typography
Two type families, by role (helpers in `DesignSystem/Typography.swift`):
- **Glance numerals → SF Rounded.** Anything you read in ~1.5s at 3am — a timer, a "time since", a record, a lifetime total — uses `AppFont.display(_:)` (rounded + `.monospacedDigit()`). Rounded reads as warm and human ("calm, not clinical"); mono keeps ticking values from jittering. The baby-name hero uses `AppFont.hero()` (also rounded). Tile titles use `.rounded` too.
- **Everything else → SF Pro**, Dynamic Type throughout. Body 15–17, Caption 11–13.
- **Eyebrow labels** are uppercase, tracked, `text2`/`text3` — apply with `.sectionLabelStyle()`. They sit *above* a display value and recede behind it.

`MetricStack` is the reusable "eyebrow + big value + caption" glance unit. Everything scales with Dynamic Type (test at XXL — display values carry `.minimumScaleFactor`).

### Surfaces & depth (hierarchy through glass)
Liquid Glass signals *elevation and interactivity*, not decoration. Reserve it for the floating/tappable layer:
- **Glass** (`glassTile`/`glassCard`, `glassEffect`): the log tiles, the active-sleep card, the tab bar.
- **Solid surface** (`surfaceCard()` — `card` fill + hairline): calm content you read but don't tap — data cards, timeline. This keeps the glass elements visually on top. On iPhone Duo's open pages the timeline is one such card (`JournalCard`).
Don't stack glass on glass. The Stats "record" hero keeps its indigo gradient as the one intentional delight surface.

**The ground.** In the light appearance Home sits on **the sky** (`SkyBackground`): a gradient that fades into `bg` a little past halfway down and into a pale haze behind the hills, the sun on an arc from low-left at sunrise to just over the top edge at its noon to low-right at sunset (a crescent moon and fixed stars on the same arc through the night), a few soft cumulus clouds and wisps by day, and four ridges of hills along the bottom edge. Nothing in it has a hard edge: the sun is a soft disc in a bloom; the clouds are painted textures (`Assets.xcassets/Sky`, lit for dawn, day and dusk and crossfaded between them; regenerate with `scripts/make_sky_textures.py`), placed where the screen's own sky shows; each ridge is darkest at its crest, dissolves into valley mist below and is blurred a little — the far ones more — so the layers read by tone, not outline; and a fine soft-light grain keeps the gradients from banding. Colours and positions follow the real sunrise and sunset (`SolarClock`, the NOAA approximation) at the daycare's coordinate, or the time zone's meridian at 40°N without one; keyframes (dawn, morning, noon, dusk, night) in `SkyPalette`. It is ground like the light below: no surface wears it, it is hidden from VoiceOver, and it turns off under Reduce Transparency and Increase Contrast. The dark appearance keeps flat `bg`. The other screens sit on flat `bg`. The one exception is iPhone Duo, where the ground carries **the light** (`CradleField`) — the `CradleMark` at the size of the phone: a faint pool of each parent's accent behind each leaf of the open display (periwinkle leading, teal trailing) and, while he sleeps, a cream glow in the hinge between them. Falling asleep dims the pools; it never brightens the room. Closed, the phone keeps flat `bg`. The light is ground, not a surface: no card or control wears it, glass and solid surfaces sit on it exactly as they sit on `bg`, it is hidden from VoiceOver and never takes a touch. It turns off (plain `bg`) under Reduce Transparency, Increase Contrast and Low Power Mode, and no slab iPhone or iPad ever draws it. It is behind the spread of every tab. Numbers and rules: [`IPHONE_DUO.md`](IPHONE_DUO.md) → "The light".

### Spacing & shape
8-pt rhythm. Corner radii: cards/sheets 16–26, big tap targets 20, pills 16. Generous padding around tap targets — minimum 44×44pt hit area, the primary log buttons are far larger.

### Participant initial (attribution)
Each participant has a `colorHex`. The timeline renders a filled circle with their initial. Colors are assigned from a fixed, high-contrast palette on invite, avoiding collisions. Supports N people, not a fixed T/W.

### Haptics
- Log button tap → `UIImpactFeedbackGenerator(.medium)`
- Event saved → `UINotificationFeedbackGenerator.success`
- Stop/Wake timer → `.success`
- Destructive (delete) → `.warning`
Haptics are the primary confirmation — **the app makes no sound** (baby may be asleep).

---

## Screens & states

Every screen specifies its **empty**, **loading**, and **error** states — not just the happy path.

### 1. Home
- **Header**: baby name + age ("12 weeks old"), settings gear.
- **Today ribbon (signature centerpiece)**: today drawn as a 24-hour horizontal strip (`TodayRibbonCard` wrapping `DayRibbonView`), on a solid surface card titled "TODAY" with a part-of-day word on the right ("morning ☀️ … night 🌙"). Feed/diaper marks ride above a hairline baseline at their time-of-day position (🍼 · 💧 · 💩, near-simultaneous marks nudge apart); sleep renders below it as pale periwinkle pills with "z z z" resting inside; a dashed "now" line spans both lanes (today only). Below the ribbon: the day's three glance numbers (feeds / sleep / changes) in accent-colored metrics. The ribbon is reused on the History swimlanes and the widgets — a monochrome `tinted` variant (● feed · ○ diaper · — sleep) survives lock-screen desaturation.
- **Actions (with live status)**: Feed and Diaper — the two highest-frequency logs — as large side-by-side targets; Sleep full-width below. Each tile carries its own time-since value, so the tiles double as the status row — no separate pill row. Urgency is *quiet until it matters*: at green the since-line is calm gray with no indicator; at amber/red it takes a darkened readable tint plus an 8pt dot, so the presence of color is the signal (works without red-vs-green discrimination). A per-accent ⊕ badge in each tile's corner keeps the status-bearing tiles reading as buttons. The Feed tile's hint is forward-looking — "next bottle ~10:45" from the target-interval math — instead of a static verb. The wide Sleep row is the slot the timer takes over: when sleep is active it morphs in place into the running timer card with a "Wake up" action (Feed and Diaper never move, and the Wake button sits in easy thumb reach).
- **Timeline**: rolling recent window (~last 12–24h), continuous — *not* a "Today" list that resets at midnight. Each row: type icon, detail (3 oz / 1h 22m / Wet), local time, participant initial. Tap a row → edit. Swipe → delete (confirm).
- **Empty**: "No events yet — tap 🍼 to log Miller's first feed."
- **Loading**: initial CloudKit fetch shows a light skeleton, but local data renders immediately (offline-first).
- **Error**: a non-blocking banner if sync fails ("Not syncing — check iCloud"); logging still works locally.
- **iPhone Duo**: the same pieces in two more arrangements. Closed: this screen, unchanged. Open in landscape, *the spread*: this screen as the right page, and a details page on the left — the other parent's side of today, or tonight for the two of you — over the light. See [`IPHONE_DUO.md`](IPHONE_DUO.md).

### 2. Feed sheet
Bottom sheet. Oz presets (from `ozPresets`, default 2/3/4) + custom amount field. A **time control** defaults to "now" with quick "15 min ago / pick time" backdating. The Log button shows the resulting next-bottle reminder time. One tap on a preset can log-and-dismiss.

### 3. Sleep
Tap Sleep → timer starts immediately (writes `SleepEvent` with `endedAt = nil`). Active state shows elapsed time (computed from `startedAt`) and a "Wake up" action that sets `endedAt`. Only one sleep timer can be active; guard against a second start.

### 4. Diaper sheet
Three buttons (Wet / Dirty / Both). One tap logs with `timestamp = now` (backdatable via the same time control) and dismisses with a success haptic.

### 5. Edit entry
Reached by tapping any timeline row. Edit time, amount/type, notes. Save creates a replacement record (`editOfID` → original) and soft-deletes the original. Delete is a soft delete with confirmation. Available to Full and Logger roles.

### 6. Settings
- **Shared** (Full role only — gated/hidden for Loggers): baby name/DOB, target feed interval, oz presets, **Manage People**.
- **Per-user** (everyone): notification toggles per event type, feed-reminder on/off, quiet hours, my display name/color.

### 7. Manage People
List of participants with name, colored initial, role. Actions: invite (share link), change role (Full ↔ Logger), revoke. Revoking marks `isActive = false` and removes from the `CKShare`; their past events stay. Owner cannot be removed.

### 8. Onboarding (first launch, owner)
Deliberately small: a one-page tour that doubles as the welcome (log tiles, widgets/Dynamic Island/Siri/Control Center collage, sync teaser, plus the "Explore with sample data" demo entry) → baby (name/DOB/photo) → you (name/color/photo) → invite your co-parent. Then straight to Home. Tuning is deferred:
- **"Getting set up" quests** — a dismissible checklist card on Home (feeding rhythm, feed reminders), each a self-contained 30-second sheet; sensible defaults apply until tuned. Dismissed or not, unfinished quests live on under Settings → "Finish setting up". The reminders quest is also offered once, just-in-time, right after a feed log (the calm moment for the AlarmKit permission ask).
- **Spotlight** — "it learns your rhythm" plays once, contextually, after the first logged feed (when there's real data to show).

Second/third person joins by accepting an invite link — hello → name/color, then Home (their quest list is reminders only). The first joiner is assumed to be the co-parent and gets Full access; later joiners start as Loggers (the owner changes roles in Settings → People).

### 9. iCloud gate
If not signed into iCloud: a full-screen explainer ("Sign into iCloud to sync with your partner") with a button to Settings. The app still logs locally; data back-fills to CloudKit once signed in.

---

## Glanceable surfaces

### Sleep Live Activity (lock screen + Dynamic Island)
Shown only while a sleep timer runs (feeds are instantaneous — no feed activity). A calm night scene: a haloed moon, an uppercase eyebrow, and a large rounded timer over the brand indigo gradient (the same one as the Stats record hero), so the in-app and lock-screen sleep surfaces share one visual language. Dynamic Island compact: `💤 23:47`; the expanded view stays action-free by design (see docs/LIVE-ACTIVITY-IDEAS.md #7 — nothing to fat-finger at 3am). Uses ActivityKit's native timer text so it counts without app wake-ups (no continuous animation — ActivityKit doesn't support it).

### Widgets (home + lock screen)
Seven widgets ship (see TwoOfUsWidgets.swift): per-event small/accessory
widgets ("🍼 2h 40m since feed"), the Today Ribbon, the Next Feed gauge, and
medium/large quick-log widgets with interactive App-Intent buttons — plus
three Control Center controls.
Timeline reloads on a schedule and on relevant updates. Widgets read shared data via an App Group container so they don't launch the app. Live Activities can't be tested in the simulator — budget on-device time.

---

## Motion
Subtle and quick. Sheets use the standard system presentation. Timer digits animate via monospaced text only (no bouncing). Respect **Reduce Motion** — drop non-essential transitions.

iPhone Duo's light is slow on purpose: a 1.2 s cross-fade when he falls asleep or wakes, and a hinge light that breathes with the day strip's live-sleep glow (2.6 s). Under Reduce Motion the change cuts and the light holds still.

---

## Accessibility
- **Dynamic Type** to the largest sizes; layouts reflow, no clipping. Test at XXL.
- **VoiceOver**: every control labeled; timeline rows read as "Feed, 3 ounces, 2:14 PM, logged by Taylor". Urgency announced as a word ("overdue"), not just color.
- **Color is never the only signal** — urgency also shows in the numeric value and an optional label; the participant initial carries a letter, not just a hue.
- **Contrast** meets WCAG AA in both appearances.
- **One-handed**: primary actions in thumb reach; large targets.
- **Silent**: no audio feedback ever; haptics + visuals only.
