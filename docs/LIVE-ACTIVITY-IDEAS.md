# Replacing the "Wake up" button on the Sleep Live Activity

> **Decision (2026-08-04):** the recommendation below was picked and built —
> #7 (no button) combined with #1 (next-feed countdown), upgrading to #2's
> owner label during the nighttime window. See CHANGELOG "sleep Live Activity
> shows the next feed instead of a Wake button".

The lock-screen Live Activity currently spends its right-hand column on a
"Wake up ☀️" button (`TwoOfUsWidgets/SleepLiveActivityView.swift`). It's
redundant — tapping anywhere on the card already deep-links into the app,
where the sleep card has the same button — and it's the single widest element
on a card whose layout is already fighting for horizontal space.

Ideas below for what to put there instead. Constraints that shape all of them:

- **Interactivity is limited.** A Live Activity button can only run an
  `AppIntent` (in the widget process, like our Control Center buttons) or
  deep-link into the app. No sheets, no toggles with UI feedback beyond a
  re-render.
- **We don't push updates.** ContentState today is just `startedAt`; the card
  self-ticks via `Text(timerInterval:)`. Anything new we show is captured when
  the activity starts and refreshed only when the app reconciles (foreground,
  or a widget-process intent fires). Slow-moving facts are fine; fast-moving
  ones need the `timerInterval` trick to tick on their own.
- **Layout is width-sensitive.** The dimmed-screen re-render can spell out the
  timer ("2 hours, 14 minutes"), so whatever fills the slot must stay
  `fixedSize`-narrow, same as the button it replaces.

---

## 1. Next feed countdown ⏳

**What:** "Next feed" over a live countdown ("in 1:47") to the predicted next
feed — last feed + current spacing, the same anchor the nighttime schedule
already computes (PR #131).

**Why at 3am:** It answers the actual question a parent has while the baby
sleeps: *how long do I have?* Do I sleep, shower, or start warming a bottle?

**Feasibility: Easy–Medium.** Add the predicted `Date` to ContentState;
`Text(timerInterval:countsDown:true)` ticks with zero pushes. Goes stale only
if a feed is logged mid-sleep (rare — update on reconcile like everything
else).

## 2. "Who's up next" — nighttime shift position 🌙

**What:** During the nighttime window, the next `PlanSlot`'s owner and time:
"GT · 2:30 AM" in her participant color. Outside the window, falls back to
idea 1 or nothing.

**Why at 3am:** Settles the half-asleep negotiation — *is this one mine?* —
without unlocking a phone or waking the other Taylor.

**Feasibility: Medium.** Slot data is local (SwiftData via App Group);
snapshot the next slot into ContentState at start. Slots change rarely, but a
mid-sleep slot edit by the co-parent won't reach the card until reconcile —
acceptable staleness for a plan that's set before bed.

## 3. Log Diaper quick action 🍃

**What:** Keep a button, but make it non-redundant: "Diaper 🍃" running
`LogDiaperIntent` — the exact intent already behind the Control Center button,
so it logs without opening the app.

**Why at 3am:** The mid-sleep diaper change is the one thing you do *while
sleep continues* — change, re-swaddle, back in the SNOO. Today that's
unlock → app → tile; this makes it one tap with the phone still locked.

**Feasibility: Easy.** The intent already runs in the widget process against
the App Group store. Main risk is pocket-taps logging phantom diapers — worth
a small confirmation affordance (e.g. the button re-renders "Logged ✓" via
ContentState) or accepting that Undo exists.

## 4. Last feed summary 🍼

**What:** A quiet stat where the button was: "Last feed / 4 oz · 8:45 PM".

**Why at 3am:** When the baby stirs, the first triage question is *when did he
last eat and how much?* — that's what decides whether this wake-up is a feed
or a soothe. Having it pre-answered on the lock screen skips the app entirely.

**Feasibility: Easy.** Known at activity start; static text, narrow, no
ticking needed. Stale only if a feed is logged during the sleep, which is
exactly when you're already in the app.

## 5. Total sleep today, ticking 📈

**What:** "Today / 4h 32m" — total sleep across all of today's sessions,
including the running one, counting up live.

**Why at 3am:** Less triage, more reassurance — the "is he getting enough?"
glance, and a satisfying number to watch grow. Also the stat most asked at
the pediatrician.

**Feasibility: Medium (with a trick).** A static total goes stale, but
`Text(timerInterval:)` from a *back-dated* start (`startedAt` minus prior
sleep today) ticks the true running total for free. Needs StatsEngine's
day-total snapshot in ContentState; crossing midnight mid-sleep makes the
number technically "yesterday+today" — probably fine, parents count nights,
not calendar days.

## 6. Attribution + SNOO badge 🛏️

**What:** Small stacked chips: who started the sleep ("GT", participant
color) and a SNOO badge when the session is SNOO-driven/synced.

**Why at 3am:** Tells you at a glance whether the SNOO is doing the soothing
(don't intervene yet) and who put him down — i.e. whose shift this actually
is.

**Feasibility: Easy for attribution** (`SleepEvent.loggedBy*` is right there;
static attribute). **Medium for SNOO** — depends on the `snoo-sleep-sync`
branch landing, and SNOO state is only as fresh as the last poll. Ship
attribution first, add the badge when SNOO sync merges.

## 7. No button — let the night scene breathe 🌌

**What:** Remove the third column entirely. Timer grows a size, "since
6:03 PM" gets promoted from caption to subheadline, moon gets a little more
halo. Pure glance card; the whole surface remains a deep-link.

**Why at 3am:** The card's one job is *he's asleep, this long, since then* —
bigger type is easier on eyes that just woke up, and no button means nothing
to fat-finger while half-asleep. Also the calmest option, which is the brand.

**Feasibility: Trivial.** Deleting the button also deletes the layout
gymnastics it caused (the width-instability comments in
`SleepLiveActivityView.swift` exist largely because of that fixed trailing
column).

## 8. Sleep-stretch progress ring 💍

**What:** Wrap the moon in a thin progress ring filling toward the expected
stretch length (the current feed spacing), with the ring completing — and
maybe the moon swapping to a sunrise tint — as the predicted wake window
approaches.

**Why at 3am:** Ambient, no-numbers answer to "are we early, middle, or late
in this stretch?" A nearly-full ring says "bottle soon"; a quarter ring says
"go back to sleep."

**Feasibility: Medium.** `ProgressView(timerInterval:)` is natively supported
in Live Activities and self-ticks. Needs the predicted interval in
ContentState (same data as idea 1). Purely decorative failure mode if the
prediction is off, which is the right failure mode.

---

## Recommendation

Pair **#7 with one info idea**: drop the button, then use the reclaimed slack
for **#1 (next feed countdown)** at all hours, upgrading to **#2 (who's up
next)** during the nighttime window. That keeps the card calm, answers the
two real 3am questions (how long do I have / whose turn is it), and both ride
on schedule data the app already computes. **#3 (diaper button)** is the best
option if we want to keep an action — it's the only one that's genuinely
one-tap-useful without the app.
