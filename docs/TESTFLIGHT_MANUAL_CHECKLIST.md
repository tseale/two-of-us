# Manual / Device QA Checklist

Things `make test` can't cover — they need real hardware, real iCloud accounts,
or both. Run before promoting a build to the App Store. Pair with
`DEVICE_TEST_MATRIX.md` (which devices) and `ACCESSIBILITY_CHECKLIST.md`.

## Onboarding & join (two iCloud accounts)
- [ ] Owner first-run: baby → profile → invite → celebration → Home.
- [ ] DOB picker can't pick a future date; empty baby/owner name blocks Finish.
- [ ] Co-parent taps the invite link (cold launch and warm) → join flow → lands
      on the shared log within ~10s.
- [ ] Join screen escape hatch appears after ~30s if the owner is offline, and
      "Try again" re-kicks the fetch.
- [ ] Accept failures show the right copy: signed out vs offline vs revoked link.

## Logging core
- [ ] Feed/diaper/sleep quick-log; backdate via the time control; toast + Undo.
- [ ] Diaper select-then-confirm logs the highlighted type, not a stray tap.
- [ ] Active-sleep card morph; stop sleep; edit/backdate an event.
- [ ] Add a note on a feed/diaper (log + edit); it shows on the timeline row.

## Sync (two devices)
- [ ] A log on phone A appears on phone B within ~10s (foreground and via push
      while backgrounded).
- [ ] Offline edits reconcile on reconnect; concurrent edits resolve (terminal
      delete / sleep-stop win).
- [ ] **Known limitation**: a widget/Control-Center log made offline with the app
      never opened does NOT sync until the app is next opened (by design — see
      `RELEASE_POLISH_PLAN.md` §10).

## Sharing lifecycle
- [ ] Change a co-parent's role; remove a participant; the right person leaves.
- [ ] Leave share from the participant side; revoke from the owner side.
- [ ] A failed sharing edit surfaces a banner and is retryable on reopen.

## Widgets & controls (device-only)
- [ ] Home + lock-screen widgets render, update, and deep-link into log sheets.
- [ ] Control Center / Action Button log controls; stateful sleep toggle.
- [ ] Widget reflects a Siri/Control-Center sleep end promptly.

## Live Activity (device-only — not in the simulator)
- [ ] Start sleep → Lock Screen + Dynamic Island timer; survives lock/wake.
- [ ] Force-quit mid-sleep → next foreground reconciles the activity.
- [ ] End sleep dismisses it; no flicker when starting right after a stop.

## Reminders & notifications (device-only)
- [ ] Feed reminder fires (pierces Silent/Focus); re-arms after each feed.
- [ ] Denying alarm permission shows the one-time prompt; the notification
      fallback fires if AlarmKit scheduling fails.

## Siri / Shortcuts
- [ ] "Hey Siri, log a diaper / feed"; query intents; 8 app shortcuts.
- [ ] An absurd Shortcuts feed amount is clamped, not persisted as-is.

## Data management
- [ ] CSV export opens and contains the logger-color column + readable sleep
      durations.
- [ ] Delete-everything gauntlet; if the delete stalls, the retry/"Go back"
      path works (no stranded spinner).
