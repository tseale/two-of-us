# Changelog

All notable changes to Two of Us are recorded here. The format loosely follows
[Keep a Changelog](https://keepachangelog.com/); versions track
`MARKETING_VERSION` in `project.yml`.

## [Unreleased]

### Fixed — late pick-ups inside the fence
- With arrival detection on, returning to the daycare while he's checked in
  shows the pick-up slider (and fires the "Pick up Miller?" prompt) at any
  hour, closing time included. The "assumed checked out at closing" fallback
  now only applies away from the daycare: standing inside the fence, only a
  logged pick-up ends the day. The Hours footer in Settings → Daycare says so.

### Changed — a plain drop-off prompt; the whiteboard lives on Home
- The morning geofence prompt is back to one line — "Drop off Miller?" /
  "You're at <daycare> — log the drop-off with one tap." — with the single
  **Dropped off** action. The whiteboard-in-the-banner experiment (five
  rows in the body, a custom long-press card) is gone: the long-press card
  rendered blank in the field, and the plain ask reads better from a
  pocket anyway. The content extension no longer claims `GEOFENCE_DROPOFF`,
  and its hosting controller's intrinsic-size change from that experiment is
  reverted so the other expanded cards size as they did before.
- Home's slide-to-drop-off whiteboard card (last bottle, last diaper, wake
  time, overnight sleep, the parents' notes since last night) stays, minus
  the Copy button: it's read off the phone and written on the daycare's
  physical whiteboard, never pasted.

### Changed — geofence-driven sliders (arrival mode)
- With arrival detection on (pin placed, toggle on, "Always" location granted
  on that phone), the drop-off and pick-up sliders never show by default:
  only the phone standing inside the daycare fence gets one — drop-off on a
  morning arrival inside operating hours, pick-up on a return while he's
  checked in. A day no phone visits shows nothing at all: weekends and sick
  days are home days by silence, so the "Staying home" notification action is
  gone too.
- Multi-device: each geofence crossing syncs as a latest-state
  `daycarePresence` value on `SharedSettings` (`{deviceID, timestamp,
  arrival/departure}` — schema generation 6, new field pending CloudKit
  deploy), so the phone that stayed at work shows a quiet "someone's at
  daycare" line instead of a slider.
- Fallback: with location off or no pin, the sliders follow the clock as
  before (drop-off from doors-open, pick-up from "Pick-up from"). The
  settings page now explains both modes and hides the redundant "Pick-up
  from" time while arrival mode is active on that phone.
- The slide-to-confirm shimmer sweeps three times and stops — it's an
  introduction, not an alarm.
- The wake-up slide only shows for manually started sleeps: a SNOO session
  ends itself when the device reports the wake.

### Added — Daycare settings page (Settings → Integrations → Daycare)
- The daycare is now a configured place, not hardcoded assumptions: name
  (used wherever the app said "Daycare"), classroom, phone (with a quick-dial
  row), operating hours, and operating days — all on `SharedSettings`, so one
  parent's setup syncs to the other (schema generation 5; the eleven new
  fields are in the CloudKit **Development** schema, Production deploy
  pending).
- Operating hours replace the hardcoded 7 AM / 5:30 PM: the drop-off button
  appears when the doors open, and with no pick-up logged the daycare day is
  assumed over at the configured close. Operating days replace the weekday
  check — the check-in chips only show on configured days.
- Location: address search (MapKit) or tap-to-place pin on a map, with the
  geofence radius (100/200/500 m) drawn around it.
- Arrival prompts: entering the geofence posts "Drop off Miller?" in the
  morning or "Pick up Miller?" while he's at daycare — with one-tap
  Dropped off / Picked up / Staying home notification actions that log the
  check marker straight from the lock screen. Runs on `CLMonitor`, so it
  works with the app closed; needs per-device "Always" location permission
  (new `NSLocation*` usage strings). One ask per direction per day, silent
  on home days and after checkout.

### Added — smart pick-up button
- The hero's Picked up button no longer sits exposed all day. Before the
  configured "Pick-up from" time (3:00 PM until set, new `SharedSettings`
  field `daycarePickupShowMinute`, clamped inside the operating hours) it is
  hidden entirely; from then it rests as a quiet one-line "Ready to pick up
  Miller?" ask that a tap expands into the real button — two deliberate taps
  between a bounced phone and a logged checkout.
- Arriving inside the daycare geofence (arrival prompts on, after the show
  time) expands the ask to the full button on its own — walking in to get him
  is the confirmation. An early sick-day pickup still gets the existing
  arrival-prompt notification at any hour.
- After checkout the slot shows a quiet "picked up at 4:12" receipt for the
  rest of the day instead of vanishing.

### Changed — photo polish
- The viewer's post-save checkmark (which read as a tappable button) is now
  a quiet "Saved" text that fades after two seconds; the Save button doesn't
  re-offer itself for an already-saved photo.
- Photo bursts render as a little pile of polaroids — card-framed thumbnails
  fanned with rotation and offset, deeper photos leaning further out, the
  count badge riding the top corner — instead of a flat side-by-side strip.

### Fixed — simultaneous Brightwheel photos no longer dedupe each other
- Two photos posted at the same minute (the 9:23 AM pair) imported as one:
  the importer's ±90s same-type fallback treated the second as a re-issue.
  Media now dedupes on Brightwheel's own object id alone — the time window
  only backstops an id-less activity, which hasn't been seen in the wild.
- Photo bursts render as one timeline row — "Photos (2)" with thumbnails
  side by side (+N past three) — instead of identical stacked rows.
  Tapping opens a swipeable pager with per-photo Save; swipe-delete removes
  the burst as one gesture with one Undo.

### Added — save daycare photos to the camera roll
- The photo viewer has a **Save** button (add-only Photos access, requested
  on first save; `NSPhotoLibraryAddUsageDescription` added) — works for
  standalone photo posts and photos attached to feeds/changes alike, since
  attachments import as their own photo events.
- The daycare card (hero and finished forms) gains **"Save all N photos to
  camera roll"**, batch-saving the day in one tap. Honest reporting: a full
  save toasts the count, expired CDN links toast a partial ("Saved 3 of 4 —
  some links expired"), and denied access points at Settings. Exposed to
  VoiceOver as a custom action on the card.

### Added — attached photos and live naps on the timeline
- **Photos attached to any Brightwheel activity** (a diaper change or feed
  can carry one, not just standalone photo posts) now import as their own
  photo events on the timeline, deduped independently of their host event.
  Photos on either half of a nap import immediately, even while the nap is
  still open.
- **Naps in progress show on the timeline**: an active sleep renders as a
  growing purple capsule with a live "Napping · 23 min" label — manual
  timers, SNOO sessions, and Brightwheel daycare naps alike (the daycare one
  is synthesized from the live-nap signal, since its SleepEvent only lands at
  wake). Tapping a running sleep doesn't open the edit sheet (nothing to
  end-date yet), and swipe-deleting one tears down its Live Activity and
  alarm properly, with Undo resuming the timer.

### Changed — daycare hero polish, round two
- Home/daycare are side-by-side columns again, each a vertical emoji list.
- Diapers break down wet vs dirty ("💧1 💩1" — a `.both` counts toward each).
- Circle numbers wear their circle's own darker ink (lighter in dark mode)
  instead of stark black; sleep reads "4h 50m" everywhere; circle labels
  drop to quiet lowercase captions.

### Changed — daycare hero polish
- The circles sit straight on the card (the gradient band behind them is
  gone), the top-right corner reads just "daycare since 7:51 AM", and the
  home/daycare split is now two vertical emoji lists — 🍼 oz (feeds),
  💩 changes, 💤 sleep per section, with photos/activities (and medication,
  in red) living under DAYCARE instead of floating at the card's foot.

### Changed — the daycare hero card absorbs TODAY
- During daycare hours the TODAY card and the daycare card — the same three
  numbers in two formats — merge into one storybook page: "🏫 Miller's Day ·
  since 7:51 AM · 1h 9m" over the 24-hour ribbon, whole-day totals as three
  beads on a soft gradient string (the sleep bead counts and pulses mid-nap),
  and a home/daycare split underneath ("🏠 5 oz · 2 changes · 3h 10m |
  🏫 2 oz · 1 change · 40m", daycare side in the check-in teal). Warm
  peach-to-lavender wash; pops on new events; Reduce Motion respected.
- Checkout dissolves it back into the plain TODAY card, the log tiles, and
  the quiet finished-day daycare card.

### Changed — one daycare card, now a window into his day
- The daycare report paragraph and the "at daycare" strip merged into one
  card: "Miller is at daycare · since 7:51 AM · 3h 12m" over three stat
  circles that carry the whole summary — total oz in the feed circle, change
  count in the diaper circle, total sleep in the sleep circle. Activities and
  photos get one gentle line; medication keeps its red one.
- **Live nap**: Brightwheel sends naps as separate fell-asleep/woke-up
  activities, so an unpaired start means he's napping *right now* — the sleep
  circle pulses with a counting timer and settles into the day's total once
  the wake lands. Surfaced ephemerally from the importer; nothing is
  persisted until the pair completes.
- A circle pops briefly when its number grows (a new bottle just landed from
  the daycare feed), the card wears a soft two-accent gradient wash, and the
  same card renders the finished day quietly after pickup. All motion
  respects Reduce Motion.

### Changed — Home adapts to where Miller actually is
- **Tonight's Schedule leaves when it's done**: once every overnight slot is
  fulfilled, missed, or skipped, the card hides instead of showing a
  completed checklist all morning. It returns with the next evening's run-up.
- **Daycare mode**: between check-in and check-out (CheckEvent markers,
  Brightwheel-imported or hand-logged) the big Feed/Diaper/Sleep tiles
  collapse into a compact "at daycare" strip — the three log actions stay
  reachable — and the Daycare Report card moves to the top of the screen as
  the hero. Fallbacks keep a missed tap from wedging the mode: with no
  check-in recorded, the first daycare-logged event of the day stands in
  ("daycare's been logging since 9:02 AM"); with no check-out, the day is
  assumed over at 5:30 PM; and midnight clears everything.

### Changed — Today's outlook rebuilt: computed, not generated
- **Today's outlook** (Stats) is now assembled directly from the prediction
  engine as structured rows — next bottle (time + size), next nap or wake-up,
  and bedtime — each with the basis it rests on ("usually ~3h10m between
  feeds · last fed 5:40 PM"). The Foundation Models generation step is gone:
  the on-device model kept parroting its own prompt example ("the 2:15 nap")
  into every output, and the card's content was always numbers the engine had
  already computed. As a side effect the card no longer needs Apple
  Intelligence hardware.
- **Bedtime prediction**: the engine now learns when Miller goes down for the
  night (earliest qualifying bed-down per night, recency-weighted, overnight
  re-settles excluded) and shows it with the observed range.
- **Time-of-day bottle sizes**: amount suggestions now read the matching
  clock bucket (morning / midday / evening) when it has enough evidence of
  its own, so a big-dinner pattern stops being averaged into breakfast.
  Thin buckets fall back to the whole-day pattern as before.
- **Wake-window recency weighting**: the "next nap" projection now weights
  the past week's wake gaps by freshness (3-day half-life) with
  effective-sample-size gating — the same Option D math the feed and sleep
  predictions already use (docs/PREDICTION-MATH.md).

### Added — AI predictions, phases 2–4
- **Prediction accuracy card** (Stats): the trailing month of predictions
  scored against what actually happened — median miss for feed timing, bottle
  size, and sleep length. Computed by replaying history ("what would we have
  predicted just before this event"), so it covers every logging path and
  needed no new storage.
- **Personal models**: tiny regression models trained on-device from Miller's
  own history (time-of-day shape, age trend, previous gap) now run as
  challengers behind every feed-time and bottle-size prediction. A model's
  number is shown only while the accuracy scoring proves it beating the
  statistical baseline by a real margin; otherwise the baseline stays. The
  accuracy card says which is in use.
- **Today's outlook** (Stats): 1–2 forward-looking sentences generated
  on-device by Apple's Foundation Models FROM the computed predictions (the
  model narrates the numbers, never invents them). Same hardware gating as
  the existing insights card; both sit behind the AI Features toggle.

### Added — on-device AI predictions (Phase 1)
- The app now predicts from Miller's own history: the Feed tile projects the
  next bottle from his observed cadence with the expected size ("✦ next bottle
  ~2:30 PM · ~3.5 oz"), the Sleep tile adds his usual nap length, the
  active-sleep card and the sleep Live Activity show the predicted wake time,
  the feed sheet suggests what he's been taking at that hour, and the Tonight
  card notes the usual overnight amount. All statistics (age-banded medians,
  `WakeWindow`-style blending — see `PredictionEngine`), computed on device,
  never stored or synced. Predictions render in a gradient with a ✦ mark;
  confidence shows as wording ("next" vs "likely around"), and thin history
  falls back to the existing plain hints. Alarms and the night schedule are
  deliberately untouched — the bell is a contract, the hint is a forecast.
- New Settings → Feeding & Tracking → AI Features toggle (synced, family-wide;
  default on) governing the prediction hints AND the Stats insights summary.
  Adds `aiPredictionsEnabled` to the Settings record — **needs a CloudKit
  Production schema deploy before the next TestFlight build.**

### Changed — night bottles slide into a get-up gap instead of waking someone
- A bottle whose rhythm time would land while BOTH parents are planned-asleep
  now slides to the nearest minute one of them is already up — at most 45
  minutes, and never more than half the night's spacing, so slid bottles can't
  crowd or overtake their neighbors. A 3:27am bottle against a 2:30–3:00
  get-up gap becomes 2:59: the parent who's up anyway takes it on her way to
  bed, and nobody's sleep is broken. Ties slide earlier (a bottle slightly
  early beats waking someone).
- The night's FIRST bottle never moves — it's a logged feed, an explicit
  "move tonight", or the window opening. Every slide measures off the rhythm
  grid, never off the previous slide, so one nudge can't cascade through the
  night or change how many bottles there are (per-night overrides stay
  attached to their slot).
- When no reachable minute has anyone up, the time stands and the existing
  soonest-wake-up rule picks who gets woken — the plan never invents a gap.
  A slid row says so on the timeline ("Moved off 3:27 AM — both asleep").

### Fixed — sleep bands no longer break apart between rows
- The schedule rows put their 46pt height floor on the OUTSIDE of the row's
  stack, which padded the row without telling its children: the sleep bands
  (and the rail) stretched only to the text's natural height, leaving a gap at
  every row boundary — a different gap per row, since captions and weekday
  labels change that height. The floor now lives on a full-height child, so a
  window that spans six rows draws as one unbroken bar. Same fix on the NOW
  cap, whose fixed height had the same shape.
- Bands no longer dim above the NOW line. A sleep block is one object; fading
  half of it read as a break in the sleep rather than a break in the past.

### Fixed — sleep bands are one flat color, and the night gets an end
- A band no longer darkens where it crosses a row. The bars are drawn per row
  and deliberately bleed a couple of points past each boundary so neighbors
  fuse, but the fill was translucent, so every overlap composited with itself
  and striped the bar with a dark line every row or two. The softening alpha
  is now flattened into the color itself — same shade, no seam.
- A fall-asleep or wake landing a minute from a row boundary left a 2pt stub
  in one row carrying the rounded cap and the `zzz`, with the real block
  starting square-topped in the next: an 8pt corner radius squashed flat, and
  a marker floating off a thing too small to be a block. Such a transition is
  now drawn by the neighboring row, which has room for it — one clean cap at
  the boundary, at the cost of a few points of drift on a rail that was never
  to scale.
- Sleep that outlasts the last bottle used to run off the bottom of the
  schedule, open-ended — the parent sleeping latest never saw their night
  finish. The rail now ends in a hollow "awake" node at the night's last
  wake, so every window has two real ends and windows that fell entirely past
  the last bottle (an early-morning nap) are on the timeline at all.

### Changed — sleep bands got wide enough to read
- The lanes went from 6pt hairlines to 16pt bars, and the fall-asleep marker
  from a 10pt 💤 (which spilled outside the lane and vanished into blue and
  violet bands) to a `zzz` glyph knocked out of the band in the page color —
  legible on any parent's tint in either appearance. The legend strip labels
  the column "asleep" once, under the avatar chips.

### Changed — sleep windows paint as lanes beside the nighttime timeline
- The Nighttime tab's "Next 24 hours" rail is bottles-only now. Each parent
  gets a slim vertical lane between the clock gutter and the rail — avatar
  chip on top, a solid line in their color while they're planned-asleep, the
  Home timeline's sleep-capsule language stretched down the rail — so any
  bottle row reads at a glance who's down, who's up, and why it's assigned
  the way it is (the both-asleep overlap is two filled lanes side by side).
- A block's real fall-asleep end is rounded and carries a small 💤; its real
  wake end is rounded; everywhere a block merely continues into the next row
  the line is cut square and bled past the row boundary, so one window reads
  as one unbroken band however many rows it crosses (row spacing pinned to
  zero for the same reason). Bands run through the NOW cap and clamp to the
  rail's range; same-parent windows that touch merge into
  one block, and a get-up gap between two bottles is a visible break between
  two rounded ends. No clock labels ride the lanes — exact times live in
  "Your sleep, planned", in the sheet a band tap opens, and in VoiceOver, so
  the gutter belongs to the bottle times alone.
- Tapping a band opens the same per-night actions the old "GT sleeps" rows
  offered (VoiceOver gets them as named row actions, plus a "Both asleep" /
  "GT asleep" summary per row). Windows themselves still live in "Your
  sleep, planned" below. Geometry is a pure, unit-tested layout
  (`SleepLaneLayout`); no engine, model, or sync changes.

### Changed — overlapping sleep windows route feeds to the soonest wake-up
- A night bottle that lands while BOTH parents are inside planned sleep
  windows now goes to the parent whose planned wake-up comes soonest — their
  block was ending anyway, and the other parent's long stretch stays whole —
  instead of falling back to the blind alternation (which could assign a
  bottle mid-window and needed a manual swap). Back-to-back and overlapping
  windows chain into one block for the wake-up walk; an exact tie still
  falls to the rotation, and a per-night override still beats everything.
  The "exactly one parent asleep → the other takes it" rule is unchanged.
  The schedule footer documents the new rule.

### Added — Apple Watch companion app
- New **TwoOfUsWatch** target: a minimal watchOS app installed with the
  iPhone app. One screen, three rows — Feed (one tap logs the default
  amount), Diaper (wet/dirty/both dialog), Sleep (start/wake toggle) — each
  showing time since the last event, plus a **Last Feed complication**
  (circular/corner/rectangular/inline) that ticks by itself.
- The watch syncs with CloudKit directly (`WatchSyncManager`, a trimmed
  sibling of the phone's `SyncManager` on its own `CKSyncEngine`), so it
  works with the phone out of reach. It discovers whether this iCloud
  account owns the family zone or joined it as a share participant, applies
  fetches through the same `RecordMapping` dialect, and attributes watch
  logs to the right parent by matching the account's `cloudUserID`. The
  watch never creates zones or shares and never bulk-uploads — it is a
  cache device; the phones own the household lifecycle.
- Writes reuse `QuickLogger` (the widget/Siri write path) unchanged; its
  per-key outbound queue is drained into the watch's engine in-process.
- The UI speaks the app's design language: emoji iconography, the absolute
  kind-accent mapping (feed teal · diaper amber · sleep periwinkle) as
  18%-tinted cards over the card surface, the full green/amber/red urgency
  model on all three rows (feed target night-aware from SharedSettings),
  phone-verbatim status copy ("2h 31m ago", "next bottle ~6:15 PM",
  "changed at 2:44 PM", "MILLER IS SLEEPING"), rounded mono numerals, and
  the CradleMark on the pre-sync waiting screen. Scene backdrop is the
  sleep Live Activity's indigo-night gradient. `WatchDesign.swift` provides
  watch-native `AppColor`/`AppFont` tokens (same semantic names, no UIKit)
  so `Urgency.swift` and `CradleMark.swift` compile into the watch targets
  unchanged. The complication mirrors the phone's next-feed gauge: a
  self-advancing `ProgressView(timerInterval:)` ring with urgency-staged
  tint flips at 66%/100% of target.
- Freshness model: every app activation fetches; there is no background
  push on the watch, so remote changes land when the app is opened (the
  complication re-reads the local store after every fetch/log).

### Changed — sleep Live Activity shows the next feed instead of a Wake button
- The lock-screen sleep card's trailing column is now a self-ticking
  **next-feed countdown** — "NEXT FEED / 1:47:23 / at 2:30 AM", or the
  assigned parent's turn ("GT IS UP") in their color while the nighttime
  schedule is speaking. The old Wake up ☀️ button was redundant: tapping the
  activity already opens the app, where the active-sleep card keeps its Wake
  button (widget and Siri wake paths are unchanged).
- The prediction is the earlier of tonight's next scheduled slot and the
  canonical last-feed + interval maths the feed alarm uses, and it refreshes
  whenever a feed is logged, edited, or deleted mid-sleep on this phone —
  or arrives from the co-parent via sync/foreground reconcile.
- The expanded Dynamic Island adds a quiet "next feed 2:30 AM · GT" caption
  under the sleeping line; compact and minimal Island are unchanged.

### Changed — sleep is no longer attributed to a person in the UI
- Sleep rows on the Home timeline (and the legacy timeline row) no longer
  show the logger's avatar, and VoiceOver no longer reads "logged by …"
  for them — sleep is the baby's doing, not a caregiver task.
- The sleep edit sheet no longer offers the "Logged by" reassignment picker.
- A fulfilled sleep slot on the Nighttime schedule reads "Done ✓" instead of
  "Covered by ⟨name⟩ ✓".
- The Stats "Teamwork" split (and Wrapped's caregiver credit) now counts
  feeds and diapers only; its caption says so.
- UI-only: events still record `loggedBy` internally (sync, ghost-event
  detection, and the CSV export are unchanged).

### Fixed — ghost "?" events, duplicates, and 0 oz feeds
- Timeline rows with a grey "?" avatar, batches of identical events stamped
  the same minute, and impossible "Feed · 0 oz" entries are eliminated at
  every source:
  - **Creation requires attribution.** Every write path (app, widget, Siri,
    Control Center, notification action buttons) refuses to log when the
    local participant can't be resolved — the old fallback stamped a random
    logger UUID with an empty name, which rendered as "?" and synced to both
    phones. Widget/Siri now answer "Couldn't log — open Two of Us and try
    again" instead of persisting an unattributed event.
  - **0 oz feeds are rejected** at creation everywhere (a bottle of nothing is
    never a real feed).
  - **Inbound sync can no longer mint placeholders.** Applying a fetched
    CloudKit record used to swallow store errors and blind-insert a
    placeholder row (0 oz / wet / "now" / random logger — exactly the ghost
    shape), duplicating events under one id. Upserts now propagate store
    errors (the engine re-fetches the batch, same recovery as a failed save),
    and a record missing its required fields is skipped, never materialized.
  - **Self-healing sweep.** On every app foreground (and after any sync batch
    that carries a ghost-shaped record), ghost events — empty logger name AND
    a logger no participant matches — are soft-deleted and synced so both
    phones and the CloudKit zone clean up; duplicate rows sharing one id are
    collapsed locally to the attributed copy.
  - If a nameless event ever slips through again, the timeline shows a neutral
    person silhouette instead of an alarming "?".

### Changed — the schedule is fully manual now
- Predicted rows are gone from the Schedule tab (and Home's up-next line).
  The schedule shows exactly the slots you defined — parent-authored, nothing
  derived from the log — and every row is editable.
- New per-night **Move tonight…** in the slot sheet: slide tonight's slot to a
  different time without touching the standing plan. Times near midnight snap
  to the sensible night (11:30pm "moved to 12:15" means 45 minutes later).
  Moves combine with swaps (assigning after moving keeps the moved time),
  sync like any override, and reminders/alarms follow the moved time.

### Fixed
- "Resend link" now verifies the person is actually a member of the iCloud
  share before offering the URL. A non-member tapping the bare link hits
  Apple's "Item Unavailable" dead end — the flow now explains they need
  re-adding and opens the sharing sheet instead.

### Added
- Resend an invite link to someone who already has access (lost link, new
  phone): swipe their row in Settings → People → **Resend link**. Shares the
  standing zone-wide invite URL through the plain share sheet — never creates
  a new person or touches the participant list.

### Fixed
- ITMS-90473 upload warning (build 76): the notification-content extension's
  Info.plist hardcoded version 1.0/1 instead of wiring `$(MARKETING_VERSION)` /
  `$(CURRENT_PROJECT_VERSION)` like the app and widget targets — every version
  bump would trip the mismatch warning. Now wired; future bumps carry through.
- The unremovable "?" person in Settings → People. A ghost participant record
  (leaked by the same pre-SyncGate dev runs as the ghost logs) was never a
  member of the iCloud share, so Remove threw "Couldn't match this person" and
  stranded the row. Removal now purges record-only participants — synced, so
  the row disappears on both phones — and only touches the CKShare when the
  member's identity is certain. This also defuses the old fallback that could
  have removed the *real* co-parent from the share when removing a ghost, and
  stops `nil == nil` from ever matching a pending invitee.

### Fixed — ghost logs from dev/test runs syncing into the family zone
- Sync is now refused outright in simulator builds and in any launch carrying
  a store-mutating fixture argument (`-seedSampleData`, `-wipeStore`, …).
  Previously a UI-test or App Store screenshot run seeded a week of fake
  "Mom"/"Dad" feeds/sleeps/diapers into the real store, and the sync layer's
  one-shot bootstrap uploaded all of it to the family's CloudKit zone — both
  parents then pulled them as ghost logs nobody had tapped for (`SyncGate`).
- Manage data gains a one-tap **Remove unknown entries** cleanup: soft-deletes
  every event whose logger was never a household participant (the signature
  of leaked sample data), synced to both parents like any normal deletion.
  The section only appears when such entries exist.

### Fixed — reminder routing & phantom sleeps
- The loud interval feed alarm now stays dark on the off-duty parent's phone
  when the schedule pins that feed to their co-parent. Previously only the
  gentle nudge consulted the schedule; the AlarmKit "feed due" alarm checked
  only this device's own armed slot alarm, so a parent with the classic feed
  reminder enabled was still woken during the other parent's assigned slot.
  Fail-safe unchanged: unassigned slots, skipped nights, unknown identity, or
  no schedule all keep the alarm armed for everyone.
- Phantom sleep sessions from stale widget taps. The widget Sleep/Wake buttons
  (quick-log row and the small sleep tile) ran a blind toggle rendered from a
  timeline snapshot — tapping "Wake" after the co-parent had already stopped
  the sleep started a brand-new session. They now drive sleep to the state
  the button showed (same idempotent intent as the Control Center toggle and
  Live Activity Wake button), so a stale tap is a no-op, never a phantom log.
- "Hey Siri, start sleep" no longer *stops* a running sleep: the start/stop
  phrases now map to separate idempotent intents instead of sharing the toggle.

### Release-polish pass (toward the first App Store release)

#### Reliability — silent failures now surface
- Failed SwiftData saves raise a transient banner instead of being swallowed by
  a `print`, so an optimistic log can't quietly disappear.
- Feed-reminder (AlarmKit) scheduling failures are logged and fall back to a
  local notification; a denied alarm permission prompts once to enable it.
- CloudKit sync, share-acceptance, and the system share sheet route failures to
  the unified log (and a banner where a parent needs to know).
- The join/sync screens no longer spin forever — a ~30s escape hatch re-kicks
  the fetch, and the co-parent Finish step explains itself if the owner's
  profile is slow to sync.

#### Correctness — input bounds & validation
- Siri/Shortcuts and widget inputs are bounds-checked (feed ounces, backdated
  times) before they're written.
- The edit sheet blocks 0-duration sleeps and no longer clamps 0.25 oz values.
- Baby/profile edits can't be saved with an empty name.

#### Polish
- Diaper logging uses select-then-confirm with a selected highlight (parity
  with feeds); toast Undo and the "Now" control tint to the event's accent.
- Timeline sleep capsules scale so longer sleeps look longer; the Dynamic Island
  sleep timer dims overnight.
- CSV export carries a logger-color column and a readable sleep duration.

#### Submission scaffolding
- Added `TwoOfUs/PrivacyInfo.xcprivacy` (no tracking; required-reason APIs
  declared) for App Store submission.
- New runbooks: App Store release, manual/device QA, device matrix, and
  accessibility checklist (`docs/`).

> Device- and account-dependent work (widgets, Live Activities, two-account
> CloudKit sharing, push, App Store Connect listing/nutrition label, the second
> Xcode Cloud workflow) is tracked in `docs/RELEASE_POLISH_PLAN.md` §18 and the
> new runbooks — it can't be completed from the codebase alone.

## [1.0] — TestFlight
- Initial TestFlight build: core logging (feed/diaper/sleep), CloudKit sync,
  widgets, Live Activities, Siri/App Intents, and stats.
