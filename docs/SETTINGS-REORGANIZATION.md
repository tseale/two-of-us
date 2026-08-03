# Settings Reorganization Plan

## Why

`SettingsView.swift` has grown into a single ~750-line `Form` with 13 sections
stacked on top of each other. A sleep-deprived parent scrolling for "quiet
hours" or "invite someone" has to scan past feeding intervals, tracker
toggles, three separate notification sections, and SNOO before finding it.
This plan proposes splitting the flat list into a landing page of ≤6 category
rows, each pushing to a focused subpage — the standard iOS Settings.app
pattern.

No behavior changes are proposed here — same toggles, same copy, same
underlying `@AppStorage`/`LocalPrefs`/`SharedSettings` bindings. This is a
navigation/grouping change only.

## Current structure (audit)

Everything below lives in [`SettingsView.swift`](../TwoOfUs/Features/Settings/SettingsView.swift),
rendered top-to-bottom in one `Form`, in this order:

| # | Section (as coded) | Contents | Gated by |
|---|---|---|---|
| 1 | `babySection` | Baby header row (avatar, name, age/DOB) → taps into `BabyEditSheet` | `canEditShared` for edit access; always visible read-only otherwise |
| 2 | `youSection` ("You") | Your avatar + name row → taps into `ProfileEditSheet` | always |
| 3 | `setupSection` ("Finish setting up") | Dynamic list of incomplete onboarding quests (`.rhythm`, `.reminders`) → sheets | only if quests pending & not demo mode |
| 4 | "Feeding" | `Stepper` "Feed every Xh Ym" (60–360 min) + 4 quick-preset chips (2h/2.5h/3h/4h) | `canEditShared` |
| 5 | "What to track" | 3 toggles: Feed, Sleep, Diaper (`trackerToggle`) — last-enabled-tracker locks | `canEditShared` |
| 6 | "Appearance" | `Picker` "Theme" (Appearance: system/light/dark) | always |
| 7 | `coParentSection` ("People") | Participant rows (avatar, name, role pill, segmented Full/Logger picker), swipe actions (Remove, Resend link, Merge), "Invite someone" / "Leave shared baby" / "Stop sharing" buttons + 4 confirmation dialogs | always |
| 8 | "Reminders" | Toggle "Feed reminder", Toggle "My slot alarm", Picker "Alarm sound" (AlarmTone) | always |
| 9 | "When your co-parent logs" | 3 toggles: Feeds, Sleep, Diapers (co-parent activity notifications) | always |
| 10 | (untitled, footer only) | Toggle "Gentle reminders", Toggle "Daily summary" | always |
| 11 | "Quiet hours" | Toggle "Quiet hours" + From/To `DatePicker`s (shown when enabled) | always |
| 12 | `SnooSettingsSection` ("Integrations") | Connect/manage SNOO row, Toggle "Auto-log SNOO sleep", "Sync now" button, "Sign out" (+ confirm) | `SnooFeature.isEnabled && !demoModeEnabled` |
| 13 | (untitled) | NavigationLink "Manage data" → `ManageDataView` | always |
| 14 | `demoSection` ("Demo mode") | Toggle "Demo mode", Button "Reset demo data" (shown when enabled) | always |
| 15 | `aboutSection` (untitled) | App icon, "Two of Us", version string, "Made with love for {baby}" | always |

`ManageDataView` (already a subpage) contains: "Export log (CSV)", "Clear all
logs" (+ confirm), "Remove unknown entries" / ghost-entry cleanup (+ confirm),
and "Delete everything" — a 3-stage destructive confirm flow with a
type-to-confirm phrase.

Sheets/dialogs presented from `SettingsView` itself: `BabyEditSheet`,
`ProfileEditSheet`, quest sheets (`RhythmQuestSheet`, `RemindersQuestSheet`),
`CloudShareView` (invite), `SnooLoginSheet`, resend-link `ActivityShareSheet`,
plus 4 confirmation dialogs for the People section (leave / stop sharing /
remove / merge) and a reinvite alert.

**Notably absent today:** nighttime-schedule config is not in Settings at
all — it's `NightScheduleSettingsSheet`, presented from the Schedule tab
(`ScheduleView.swift`). The plan below keeps it there and just links to it,
per the existing pattern.

## Problems with the current layout

- 15 sections, no grouping above the section level — everything is one long
  scroll.
- Notifications alone are spread across 4 separate sections (Reminders /
  co-parent logs / gentle+summary / quiet hours) with no shared heading.
- "Feeding" and "What to track" are both feeding-adjacent but split by an
  unrelated "Appearance" section in between.
- SNOO (an integration) sits between notifications and data management with
  no header signaling what it is until you're already in it.
- Demo mode and About are both low-frequency but presented as full peer
  sections, same visual weight as "People".

## Proposed structure

Top-level `SettingsView` becomes a short list of rows, each a
`NavigationLink` into a focused subpage `View`. Baby header, You card, and
"Finish setting up" stay inline at the top (they're already compact,
high-frequency, and card-like rather than list-like — matching how
Settings.app keeps its own profile header outside the grouped list).

```
Settings
├─ [Baby header card]         (unchanged, inline)
├─ [You card]                 (unchanged, inline)
├─ [Finish setting up]        (unchanged, inline, conditional)
│
├─ Feeding & Tracking      →  Feed interval, presets, What to track toggles
├─ Notifications & Alarms  →  Reminders, co-parent activity, gentle+summary, quiet hours
├─ People & Sharing        →  Participant list, invite/leave/stop sharing
├─ Integrations            →  SNOO (conditional on SnooFeature.isEnabled)
├─ Data                    →  Appearance, Manage data (export/clear/delete), Demo mode
└─ About                   →  App icon, version, credit line
```

That's 6 rows (5 if SNOO's feature flag is off and the row is hidden
entirely, which is already how it's gated today).

### Row-by-row mapping

**1. Feeding & Tracking** (new subpage `FeedingSettingsView`)
- "Feeding" section as-is: Stepper + preset chips (`canEditShared`)
- "What to track" section as-is: Feed/Sleep/Diaper toggles (`canEditShared`)
- Rationale: both are about *what gets logged and how often*; today they're
  only separated by "Appearance," which has nothing to do with either.

**2. Notifications & Alarms** (new subpage `NotificationSettingsView`)
- "Reminders" (Feed reminder, My slot alarm, Alarm sound)
- "When your co-parent logs" (Feeds/Sleep/Diapers toggles)
- Gentle reminders / Daily summary (currently untitled — give it a header,
  e.g. "Nudges")
- "Quiet hours" (toggle + From/To pickers)
- Rationale: today these are 4 separate top-level sections a parent has to
  scroll past individually; consolidating under one entry point makes "turn
  off notifications overnight" a single tap-in instead of hunting across the
  whole page. Sub-headers preserve the existing grouping/footers.

**3. People & Sharing** (new subpage `PeopleSettingsView`, or promote existing
`coParentSection` wholesale)
- Everything in `coParentSection` unchanged: participant rows, role picker,
  swipe actions, invite/leave/stop-sharing buttons, all 4 confirmation
  dialogs.
- Rationale: this section is already the single largest and most
  self-contained block (participant rows + their own swipe menus). Moving it
  off the main page removes the biggest chunk of main-page scroll length
  with zero internal restructuring needed.

**4. Integrations** (existing `SnooSettingsSection`, becomes its own pushed
page instead of an inline section)
- SNOO connect/manage row, Auto-log toggle, Sync now, Sign out.
- Still gated by `SnooFeature.isEnabled && !prefs.demoModeEnabled` — if SNOO
  is off, this row doesn't appear on the main page at all.
- Rationale: named as "Integrations" (plural) so a future integration (e.g.
  another smart-crib brand) has a home without inventing a new top-level row.

**5. Data** (new subpage `DataSettingsView`)
- "Appearance" (Theme picker) — moved here rather than kept top-level; it's
  a device display preference, same shelf as demo mode.
- "Manage data" — currently a `NavigationLink` row; becomes the first
  section of this subpage instead of a link-to-a-link.
- "Demo mode" section as-is (toggle + Reset demo data button).
- Rationale: these are all "how the app behaves/what data it holds"
  settings a parent touches rarely. Grouping avoids 3 separate low-frequency
  top-level rows.
- Alternative considered: keep "Appearance" top-level since it's arguably
  higher-frequency than demo mode or data export. Open question below.

**6. About** (new subpage `AboutSettingsView`, or keep inline as a footer —
open question below)
- App icon, "Two of Us", version string, credit line.
- Rationale: matches iOS Settings.app's own "About" pattern. Low-frequency,
  fine as a single tap-in.

### What doesn't move
- Baby header, You card, and "Finish setting up" stay inline on the main
  page — they're the highest-frequency taps (edit baby / edit your profile)
  and are already card-shaped rather than row-shaped, so they don't add to
  the "row count" the ≤6 budget is about.
- Nighttime schedule config stays in the Schedule tab
  (`NightScheduleSettingsSheet`), not duplicated into Settings. If desired,
  a single row/link could be added under "Notifications & Alarms" or
  "Data" pointing at it, but that's additive scope beyond a pure
  reorganization — flagged as an open question, not included in the row
  count above.

## Open questions

1. **Appearance placement** — top-level next to the 6 categories (making it
   7), or folded into "Data" as proposed? Leaning toward folding in, since
   it's a single Picker and the ≤6 budget matters more for scannability.
2. **About as its own row vs. inline footer** — About sections are commonly
   left inline at the very bottom of Settings.app-style forms rather than
   pushed to a subpage, since there's nothing to interact with. Could stay
   inline below "Data" instead of counting as row 6, bringing the top row
   count to 5.
3. **Cross-link to Nighttime Schedule** — worth adding a "Nighttime
   schedule" row under Notifications & Alarms (or its own row) that jumps to
   the Schedule tab's existing sheet, so parents don't have to know it lives
   elsewhere? Deferred to a follow-up if wanted.
4. **Section titles** — "Feeding & Tracking" and "Notifications & Alarms"
   are working names; final copy should stay consistent with existing
   in-app tone (short, sentence case, no jargon).

## Non-goals for this pass

- No changes to `LocalPrefs`, `SharedSettings`, or any underlying state/sync
  model.
- No changes to `ManageDataView`'s internal structure (export/clear/delete
  flows stay as they are, just reached via the new "Data" subpage instead of
  a bare link on the main page).
- No new settings or toggles — purely reorganizing what exists today.

## Suggested implementation order (for a future PR, not this one)

1. Extract each proposed subpage as its own `View` file under
   `TwoOfUs/Features/Settings/` (e.g. `FeedingSettingsView.swift`,
   `NotificationSettingsView.swift`, `PeopleSettingsView.swift`,
   `DataSettingsView.swift`), moving section bodies verbatim — no logic
   changes.
2. Replace the main `Form` in `SettingsView.swift` with the 6 (or 5)
   `NavigationLink` rows + the unchanged inline baby/you/setup content.
3. Verify `@State` currently living on `SettingsView` (e.g. `showShareSheet`,
   `snooLogin`, confirmation-dialog flags) moves with its owning section to
   the new subpage rather than staying on the parent.
4. Manual pass on device/simulator: every toggle, picker, and destructive
   confirm still round-trips correctly from its new subpage.
