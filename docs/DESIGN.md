# Two of Us — Design

**Status**: v1 design — locked June 5, 2026
**Principle**: calm, not clinical. One-thumb operable. Readable at a glance, at 3am, holding a baby.
**Platforms**: iPhone + iPad · **Appearance**: light + dark, follows the iOS system setting.

A clickable reference mockup lives at [`mockups/index.html`](../mockups/index.html).

---

## Design system

### Color
Colors are defined as **semantic tokens** that resolve differently in light vs dark. Never hardcode a hex in a view — reference the token. Hex values below are the dark-mode reference (from the mockup); light-mode variants are derived to keep contrast.

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
- **Solid surface** (`surfaceCard()` — `card` fill + hairline): calm content you read but don't tap — data cards, timeline. This keeps the glass elements visually on top.
Don't stack glass on glass. The Stats "record" hero keeps its indigo gradient as the one intentional delight surface.

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
- **Day arc (signature centerpiece)**: today drawn as a sunrise-to-night dome (`DayArcView`). A faint full-day track; a dawn→day gradient fills the elapsed portion, led by a glowing "now" orb that is **warm amber by day, cool periwinkle at night**. Feeds/diapers ride the arc as marks; sleep stretches render as soft periwinkle bands. Below it: the day's three glance numbers (feeds / sleep / changes) and a part-of-day greeting.
- **Actions (with live status)**: Feed and Diaper — the two highest-frequency logs — as large side-by-side targets; Sleep full-width below. Each tile carries its own time-since value, so the tiles double as the status row — no separate pill row. Urgency is *quiet until it matters*: at green the since-line is calm gray with no indicator; at amber/red it takes a darkened readable tint plus an 8pt dot, so the presence of color is the signal (works without red-vs-green discrimination). A per-accent ⊕ badge in each tile's corner keeps the status-bearing tiles reading as buttons. The Feed tile's hint is forward-looking — "next bottle ~10:45" from the target-interval math — instead of a static verb. The wide Sleep row is the slot the timer takes over: when sleep is active it morphs in place into the running timer card with a "Wake up" action (Feed and Diaper never move, and the Wake button sits in easy thumb reach).
- **Timeline**: rolling recent window (~last 12–24h), continuous — *not* a "Today" list that resets at midnight. Each row: type icon, detail (3 oz / 1h 22m / Wet), local time, participant initial. Tap a row → edit. Swipe → delete (confirm).
- **Empty**: "No events yet — tap 🍼 to log Miller's first feed."
- **Loading**: initial CloudKit fetch shows a light skeleton, but local data renders immediately (offline-first).
- **Error**: a non-blocking banner if sync fails ("Not syncing — check iCloud"); logging still works locally.

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
Shown only while a sleep timer runs (feeds are instantaneous — no feed activity). A calm night scene: a haloed moon, an uppercase eyebrow, and a large rounded timer over the brand indigo gradient (the same one as the Stats record hero), so the in-app and lock-screen sleep surfaces share one visual language. Dynamic Island compact: `💤 23:47`; expanded adds a "Wake up" action. Uses ActivityKit's native timer text so it counts without app wake-ups (no continuous animation — ActivityKit doesn't support it).

### Widgets (home + lock screen)
- **Lock-screen accessory / small**: "🍼 2h 40m since feed".
- **Medium (home)**: last bottle / last sleep / last diaper times.
Timeline reloads on a schedule and on relevant updates. Widgets read shared data via an App Group container so they don't launch the app. Live Activities can't be tested in the simulator — budget on-device time.

---

## Motion
Subtle and quick. Sheets use the standard system presentation. Timer digits animate via monospaced text only (no bouncing). Respect **Reduce Motion** — drop non-essential transitions.

---

## Accessibility
- **Dynamic Type** to the largest sizes; layouts reflow, no clipping. Test at XXL.
- **VoiceOver**: every control labeled; timeline rows read as "Feed, 3 ounces, 2:14 PM, logged by Taylor". Urgency announced as a word ("overdue"), not just color.
- **Color is never the only signal** — urgency also shows in the numeric value and an optional label; the participant initial carries a letter, not just a hue.
- **Contrast** meets WCAG AA in both appearances.
- **One-handed**: primary actions in thumb reach; large targets.
- **Silent**: no audio feedback ever; haptics + visuals only.
