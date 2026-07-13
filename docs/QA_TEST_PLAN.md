# QA & UI Polish Plan — pre-App-Store

_Author: hands-on simulator pass (iPhone 17, iOS 26.4) + multi-agent code audit._
_Date: 2026-07-12. Companion to `RELEASE_POLISH_PLAN.md` and `APP_STORE_RELEASE_RUNBOOK.md` — this doc adds the results of an actual device walkthrough plus a runnable test matrix. Only items **not already** tracked in the polish plan are called out as "new"._

---

## 0. What was done this session

- Built + ran the app on the **iPhone 17 / iOS 26.4** simulator (`make run`).
- Walked every screen reachable without live tapping, capturing screenshots for critique: Home (light + dark, sleeping + awake, demo + real data), History, Stats (loading + resolved), Feed sheet, Diaper sheet, Settings, Onboarding p1, Join flow.
- Added a **DEBUG-only screenshot/QA hook** (`-uiScreen feed|diaper|settings|history|stats`) mirroring the existing `-forceSpotlight` / `-seedSampleData` pattern, so any screen can be launched directly for deterministic captures (compiled out of Release).
- **Fixed and verified 3 bugs** (below).

### Testing-harness note
Interactive tap approval was unavailable in this run, so navigation used `simctl` + the launch-arg hooks rather than pixel taps. That covers launch-into-screen states but **not** multi-step interactions (advancing onboarding, editing an event, tapping into Wrapped/BabyEdit/ProfileEdit, swipe-to-delete, scrolling to the last row). Those are enumerated in the test matrix as **needs-interaction** and are the strongest argument for the XCUITest smoke suite in §5.

---

## 1. Bugs fixed this session (verified on simulator)

| # | Bug | File | Fix | Status |
|---|-----|------|-----|--------|
| B1 | Feed sheet Custom amount row rendered **"oz  oz"** — the `TextField` placeholder was `"oz"` and there is also a trailing `Text("oz")` unit label, so an empty custom field showed the unit twice. | `FeedSheet.swift:37` | Placeholder → `"0"` (a value hint, not the unit). | ✅ verified |
| B2 | The **"Time" label appeared twice** on Feed/Diaper/Edit sheets — `TimeControl`'s `DatePicker("Time", …)` label duplicated the host's `Section("Time")` header. | `TimeControl.swift` | `.labelsHidden()` on the DatePicker + a `Spacer` so "Now" trails; the section header is the single label. Fixes all 3 reuse sites. | ✅ verified (Feed + Diaper) |
| B3 | Stats **Insights showed "Log a few feeds and sleeps to see patterns here."** over a full week of data whenever the on-device model was available but generation produced nothing (Simulator, unsupported device, or a transient failure). Misleading empty-state over real data. | `StatsView.swift` | Added `showInsights` gate: the card shows only while generating, once a summary exists, or as a genuine no-data teaser — otherwise it hides (matching the "callers can simply hide the UI" contract in `BabyIntelligence`). Moved the generation `.task` to the always-present container so it still runs when the card is conditionally hidden. | ✅ verified (card now hides on sim) |

None of these three were in `RELEASE_POLISH_PLAN.md` — they surfaced from actually running the app.

---

## 2. New findings from the hands-on pass (not yet in the polish plan)

Ranked by severity. "Owner" = who can act: **code** (fixable in-repo now), **device** (needs hardware), **decision** (product call).

| # | Sev | Finding | Where | Owner |
|---|-----|---------|-------|-------|
| N1 | High | **Urgency is signalled by hue alone.** The Feed/Diaper/Sleep tiles show an amber vs red dot + colored "…ago" text for "due soon" vs "overdue". A colorblind parent gets no non-color cue. Add a shape/glyph or a word ("overdue"). | `LogButtons.swift`, urgency tokens | code |
| N2 | High | **`accentDiaper` == `urgencyAmber` (both `#F5B971`).** An amber "due soon" dot on the Diaper tile is the exact color of the diaper accent → the urgency state is invisible there. Give urgency its own hue or a shape cue. | `DesignSystem/Colors.swift:42,45` | code |
| N3 | Med | **History "Day in the life" 24h grid has no time axis.** Rows are sequential emoji, not positioned on a real timeline, yet the card is labelled "24h". You can read counts/order but not _when_ things happened. Add hour ticks or relabel. | `HistoryView.swift` | decision/code |
| N4 | Med | **Large dead space above the "History"/"Stats" titles** — the demo pill row plus the large-title inset stack into a big empty band. Tighten the top spacing (esp. with the demo pill present). | `RootView` demo strip + tab views | code |
| N5 | Med | **Join flow "Continue" looks enabled while "…is syncing".** Confirm a user can't advance past data landing (or that `joinSyncing` cleanly holds). Verify against the real CloudKit accept path. | `JoinFlowView.swift` | device/code |
| N6 | Low | **Join hero blob reads as a dark smudge** on a light background (the vignette behind the two glows). Lighten the center or reduce the dark ring in light mode. | `OnboardingAmbient` / Join | decision |
| N7 | Info | The **system iCloud "Apple Account Verification" prompt** interrupted the app on the simulator. That's the sim's account, not an app bug — but it confirms the app must degrade gracefully when iCloud isn't signed in / needs re-auth. Validate on a signed-out device. | — | device |

Not-a-bug, confirmed intentional: the **"DEMO — tap to exit" pill ships in Release** (it's the "Explore with sample data" path from onboarding, not debug scaffolding). Worth a deliberate product ✔, but working as designed.

---

## 3. Per-screen UI critique (harsh)

**Home** — Strong. Clear glance layer, good urgency system, nice glass tiles. Nits: content flows under the floating glass tab bar at rest (expected for iOS 26, but the last timeline row's clearance is unverified — see T-HOME-04); urgency is color-only (N1/N2).

**Feed / Diaper sheets** — Clean and consistent after B1/B2. The primary CTA reflects the selection ("Log 3 oz" / "Log Wet"). Amount presets 2/3/4 oz may be low for older babies but Custom covers it (decision). Sheet dismisses instantly on log with no "Logged ✓" beat (already tracked in the polish plan §5).

**History** — Beautiful, dense analytics (day-in-the-life grid, longest-sleep line, total-sleep bars, daily formula). Weakened by the missing time axis (N3) and the top dead space (N4). Verify chart axes/locale (polish plan §8).

**Stats** — Excellent: shareable weekly recap, comparative "vs avg" deltas, records, milestones/streaks, lifetime counters, night-shift & teamwork splits. Insights card now behaves (B3). Milestones/lifetime tiles are the main content that flows under the tab bar — verify last-tile clearance.

**Settings** — Polished. Feed-interval stepper + preset chips (2h/2h30m/3h/4h) and the "Feed every 3h" label both render correctly (prior session's work). Good grouping (Baby / You / Feeding / Appearance / People). Co-parent role toggle is inline and clear.

**Onboarding (p1)** — A genuinely great first impression: value prop + a widget/Live-Activity/Siri showcase + "Explore with sample data" escape hatch. Pages 2–4 not visually verified (needs-interaction).

**Join flow** — Warm "two of us" motif (merging purple/green glows). See N5/N6.

---

## 4. Test matrix

Priority: **P0** = must pass to ship, **P1** = should pass, **P2** = nice.
Mode: **sim** = testable in simulator, **device** = hardware-only, **needs-interaction** = requires taps (do manually or via the XCUITest suite in §5).

### Core logging (P0)
| ID | Flow | Steps | Expected | Mode |
|----|------|-------|----------|------|
| T-LOG-01 | Log a feed (preset) | Open Feed → tap 3 oz → Log | Toast "Logged feed · 3 oz" + Undo; feed appears in timeline; "since feed" resets | needs-interaction |
| T-LOG-02 | Log a feed (custom, half-oz) | Feed → Custom → "3.5" → Log | Accepts 3.5; timeline shows 3.5 oz | needs-interaction |
| T-LOG-03 | Custom paste tolerance | Feed → Custom → paste "5 oz" | Parses to 5 (strips unit) | needs-interaction |
| T-LOG-04 | Log diaper (each type) | Diaper → Wet/Dirty/Both → Log | Correct type logged; CTA label matches selection | needs-interaction |
| T-LOG-05 | Backdate | Feed → change Time picker to earlier → Log | Event stored at chosen time; ordering correct | needs-interaction |
| T-LOG-06 | Start/stop sleep | Home → Sleep + → later Wake up | Active card + timer; on wake, duration recorded; "last nap" updates | needs-interaction |
| T-LOG-07 | Undo | Log anything → tap Undo on toast | Event removed; counts revert | needs-interaction |
| T-LOG-08 | Edit event | Tap a timeline row → change amount/time → Save | Replacement record; original soft-deleted; history consistent | needs-interaction |
| T-LOG-09 | Delete event | Swipe a timeline row → Delete | Row removed; warning haptic; counts update | needs-interaction |
| T-LOG-10 | Widget deep-link | Tap Feed/Diaper widget (or `twoofus://log/feed`) | App opens straight to that sheet; two fast taps queue both (unit-tested) | device |

### Glance / Home (P0/P1)
| ID | Flow | Steps | Expected | Mode |
|----|------|-------|----------|------|
| T-HOME-01 | Urgency states | Age a feed past target | Dot goes none→amber→red; text tint tracks | sim (seed + wait) |
| T-HOME-02 | Empty state | Fresh baby, no events | "No events yet" empty state; tiles show no "…ago" | needs-interaction |
| T-HOME-03 | Long baby name | Baby name = 40 chars | Header truncates cleanly, no layout break (maxLength enforced) | needs-interaction |
| T-HOME-04 | Tab-bar clearance | Scroll timeline to the last row | **Last row fully clears the glass tab bar** (not permanently obscured) | needs-interaction ⚠ verify |
| T-HOME-05 | Dark mode | Toggle Theme = Dark | All surfaces/contrast correct (spot-checked ✓) | sim |
| T-HOME-06 | Dynamic Type XXL | Settings → largest accessibility text | No clipping/overlap on Home tiles & ribbon | needs-interaction ⚠ |

### Analytics (P1)
| ID | Flow | Expected | Mode |
|----|------|----------|------|
| T-STAT-01 | Stats with a week of data | All cards populate; deltas sane | sim (seed) ✓ |
| T-STAT-02 | Insights unavailable | Card hides (not misleading copy) — B3 | sim ✓ |
| T-STAT-03 | Insights available | On an Apple-Intelligence device, a warm 2–3 sentence summary appears | device |
| T-STAT-04 | Wrapped/share | Open "…'s week" → share sheet renders recap image | needs-interaction |
| T-STAT-05 | Single data point | 1 feed / 1 sleep total | Charts don't render lopsided/broken (polish plan §8) | needs-interaction |
| T-HIST-01 | History charts | Axes labelled, locale-correct units | needs-interaction ⚠ |

### Onboarding & sharing (P0)
| ID | Flow | Expected | Mode |
|----|------|----------|------|
| T-OB-01 | Full owner onboarding | Create baby → land on Home; demo NOT left on | needs-interaction |
| T-OB-02 | Explore sample data | Onboarding → "Explore with sample data" → demo home; pill exits cleanly | needs-interaction |
| T-JOIN-01 | Accept a share | Second iCloud account opens invite link → JoinFlow → co-parent's data syncs | device (2 accounts) |
| T-JOIN-02 | Join replaces local | Device with own log accepts invite → "Replace & Join" warning → merges/replaces | device |
| T-SYNC-01 | Two-way sync | Parent A logs → appears on Parent B within ~10s | device (2 accounts) |
| T-SYNC-02 | Offline→reconnect | Log offline → go online → syncs without dupes | device |
| T-SYNC-03 | Not signed into iCloud | Launch signed out | Graceful degradation, no crash/hang (N7) | device |

### Extensions (P0, device-only)
| ID | Flow | Expected | Mode |
|----|------|----------|------|
| T-WID-01 | Home/lock widgets | "Time since last feed" renders + updates | device |
| T-WID-02 | Sleep Live Activity | Start sleep → DI + lock-screen timer; stop ends it | device |
| T-SIRI-01 | "Log a bottle" | Siri intent logs a feed via QuickLogger | device |

### Robustness / edge (P1)
| ID | Flow | Expected | Mode |
|----|------|----------|------|
| T-EDGE-01 | Sleep across midnight | Start before, stop after 00:00 | Duration correct; day attribution sane | needs-interaction |
| T-EDGE-02 | Hundreds of events | Seed large dataset | Home/History/Stats scroll smoothly | sim (seed) |
| T-EDGE-03 | Future/old timestamps | Backdate far past; check clamps | No negative durations / broken "…ago" | needs-interaction |
| T-EDGE-04 | Rapid double-tap log | Double-tap a log CTA | One event, not two | needs-interaction |
| T-A11Y-01 | VoiceOver sweep | Navigate every screen with VO | Every control labelled; urgency not color-only (N1) | needs-interaction ⚠ |

---

## 5. XCUITest smoke suite — ✅ BUILT & PASSING

`TwoOfUsUITests/SmokeWalkthroughTests.swift` (own target + scheme; run with `make uitest`). One walkthrough drives the app against a seeded real store and asserts each landing, capturing a screenshot per screen into the `.xcresult`:

Home → **Feed sheet + log** → **Diaper sheet + log** → **start/stop Sleep** → **swipe-delete → Undo toast** → History → Stats → Settings → **Edit → Delete confirmation dialog**.

Result: **1 test, 0 failures, ~45s, 9 screenshots.** Crucially it green-lights the two interaction fixes from the notifications/confirmations pass that couldn't be tapped manually — the **Undo toast** and the **delete confirmation dialog** are asserted and captured.

Stable selectors were added as `accessibilityIdentifier`s (no VoiceOver impact): `logTile.feed|diaper|sleep`, `feedSheet.confirm`, `diaperSheet.confirm`, `timelineRow`. Kept in a **separate scheme** so `make test` / the Xcode Cloud unit workflow stay fast.

**Next extensions** (not yet done): owner-onboarding path (with a UI-interruption monitor for the notification prompt), Dynamic-Type run at AX3+, and wiring `make uitest` into a pre-archive Xcode Cloud step. Screenshots also give a light visual-regression baseline.

---

## 6. Priority ordering to ship

**Do next (code — I can take these on):**
1. N1 + N2 — urgency non-color cue + de-alias diaper/amber (accessibility, quick).
2. N4 — tighten large-title / demo-pill top spacing.
3. XCUITest smoke suite (§5).
4. Sheet "Logged ✓" confirmation beat (polish plan §5).
5. Chart axis/locale formatting (polish plan §8) + N3 time-axis decision.

**Blockers I cannot do (yours):**
- Privacy nutrition label (App Store Connect).
- Second Xcode Cloud **App Store** archive workflow.
- Device + two-iCloud-account QA (widgets, Live Activity, sharing, offline, signed-out).
- CloudKit schema → Production; iCloud container capability on the bundle ID.
- App Store listing (screenshots light+dark iPhone+iPad, copy, age rating, category, support URL).

---

## 7. Appendix — exhaustive code audit backlog

A 30-agent audit (one harsh reviewer per feature area, each adversarially verified, plus cross-cutting a11y / design-consistency / copy / edge-case / App-Store passes) ran to completion (0 errors) and deduped to **197 findings**. Distribution:

- **Severity:** 9 high · 69 medium · 93 low · 26 nit (no blockers).
- **Ownership:** 163 code-fixable · 24 design-decision · 9 device-test · 1 App-Store.
- **Verdicts:** 124 confirmed · 28 adjusted (severity/reasoning corrected) · 45 cross-cutting (not per-area re-verified).

The **9 high-severity** items: destructive-sharing-no-confirm (×2), record-hero light-mode contrast (✅ fixed), background-sync-doesn't-re-arm-AlarmKit, co-parent-notifications-never-fire, glance-fonts-ignore-Dynamic-Type, wake-up-button-a11y-absorption, uncontextualized-AlarmKit-prompt, stale-alarm-after-delete. They cluster into five themes:

### A. Notifications & AlarmKit are effectively off / misfiring by default ⚠ — ✅ FIXED this session (build + 76 tests green; interaction paths need a device/tap pass)
- **Co-parent / milestone / gentle notifications never delivered on a default install.** `NotificationManager.requestAuthorization()` is called from *exactly one place* — the Settings notifications toggle (`SettingsView.swift:456`). A user who never opens that toggle is never asked, so those notifications silently never fire. **(verified)**
- **Uncontextualized AlarmKit permission prompt on the first feed.** `feedReminderEnabled` defaults `true` (`LocalPrefs.swift:121`); the first `logFeed` schedules the loud alarm, which requests AlarmKit auth with no priming. Apple reviewers routinely flag this. **(verified)** → default to `false` and let the reminders primer turn it on.
- **Background-synced co-parent feed doesn't re-arm the AlarmKit alarm** → device fires a false overnight alarm (`SyncManager.swift:~542`).
- **Delete / clear-logs leaves a stale "feed due" alarm armed** (`EventStore.swift:198,208` — `softDelete`/`clearAllLogs` don't re-arm).
- **"Snooze 30m" is silently dropped inside quiet hours** (`NotificationManager.swift:149`) — a user-initiated snooze should bypass the quiet-hours guard.
- **Reminders-quest "complete" is derived from `feedReminderEnabled` (defaults true)** (`SetupProgress.swift:93`) — fragile invariant propped up by an onboarding side-write.
- _Recommendation: fix this whole cluster in one focused pass; it's the #1 functional + App-Store-review risk._

### B. Destructive actions lack confirmation / undo — ✅ FIXED this session (needs a tap pass to confirm dialogs present)
- **Swipe-delete and Edit "Delete entry" soft-delete immediately** with no undo/confirm — while (reversible) logging *does* offer Undo (`HomeView.swift:288`, `EditEventSheet.swift:136`). Route deletes through the existing `showToast(undo:)`.
- **"Stop sharing" / "Leave shared baby" / swipe-Remove run irreversible CloudKit teardown on a single tap** (`SettingsView.swift:292,322,366`). Wrap in `.confirmationDialog` with a clear consequence string.

### C. Accessibility
- **Glance type ignores Dynamic Type.** `AppFont.display/hero` return fixed-point `.system(size:)`; the `relativeTo:` parameter is accepted but never used (`Typography.swift:17`). The entire headline ramp won't scale — a real accessibility gap. Use `UIFontMetrics…scaledValue`.
- **Urgency by hue alone** + **`accentDiaper` == `urgencyAmber`** (my N1/N2).
- **Record-hero adaptive-on-dark contrast** — ✅ fixed this session.

### D. Sharing / Join robustness
- **Joining parent can get permanently stuck** — Finish is hard-gated on `owner != nil` with no retry/abandon escape if the owner's records never sync (`JoinFlowView.swift:213`). Add a "Leave and set up my own log" escape after a patience window (relates to N5).
- **Active sleep renders as a broken sliver on the History swimlane** — in-progress sleep end is anchored to the row's midnight instead of `now` (`DayRibbon.swift:50` via `StatsEngine.swimlane`).

### E. App Store copy / first-run
- **Feed sheet opens at a hardcoded 3 oz** not derived from the user's presets (`FeedSheet.swift:14`) — if presets don't include 3, no chip is highlighted and the default is wrong.
- **"Invite my partner" is tappable with empty baby/owner names** while Finish is not (`OnboardingView.swift:187`). A user can send a real zone-wide CKShare before any baby record is committed; a co-parent who accepts first joins an empty zone — the exact hazard the join routing exists to avoid. Add `enabled: canFinish` to the invite CTA.
- **"Install first" invite copy** (`OnboardingSetupSteps.swift:382`) — _correction from an earlier read:_ the user-facing sentence is **still accurate** on the App Store (a CKShare link does require the app installed before joining). Only the internal comment's TestFlight rationale is stale. Optional soften, **not** a blocker or misinformation.

### F. Onboarding interaction polish (from the completed audit)
- **Manual swipe shows a blank page until the swipe settles** — the entrance animation is gated on page-settle, not on the drag (`OnboardingView.swift:130`). Swiping (a first-class gesture here) looks like a render glitch; tapping Continue is fine.
- **Keyboard covers the primary CTA** — `.ignoresSafeArea(.keyboard)` on the whole ZStack pins "Continue" behind the keyboard while typing a name (`OnboardingView.swift:129`). Scope the ignore to the background only.
- **Wake-up button unreachable in VoiceOver** — the active-sleep card's "Wake up" button is absorbed into the card's combined accessibility element (`SleepActiveCard.swift:46`).

### Systemic patterns worth a sweep
- **Dynamic Type** is unsupported at the display/hero tier app-wide (theme C).
- **Adaptive tokens on fixed-dark surfaces** (record hero was one instance — audit the Live Activity and any other indigo-gradient surfaces for the same).
- **Auth/permission requests fire from side-effects rather than deliberate primers** (theme A).
- **Irreversible operations without a confirm/undo affordance** (theme B).

### Completeness-critic gaps (things even this audit didn't cover)
- No hardware pass: widgets, Live Activity, Siri intents, real two-account CloudKit sharing, offline→reconnect (device-only).
- No performance profiling with hundreds/thousands of events.
- No localization/RTL/`.xcstrings` review (app appears English-only hardcoded).
- Privacy-manifest ↔ actual-data-use cross-check is a manual App-Store-Connect task.

