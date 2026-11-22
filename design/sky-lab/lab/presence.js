// Presence: how far the sky has opened up, 0 (hushed, as today's sky is all
// day) to 1 (itself, in full colour). The sky is quiet ground for most of the
// day and blooms at the turning points:
//
//   · sunrise and sunset — by the sun's real altitude, not the clock: it starts
//     to open as the sun drops under about 10°, is fully open from a few degrees
//     up to a few degrees under the horizon (golden hour into civil twilight),
//     and has settled again by nautical dusk. Mirrored at dawn.
//   · moonrise near the full moon — a small one.
//   · bedtime — he falls asleep for the night: a breath of bloom as his star is
//     lit, then the sky settles DEEPER than it was (the room dims).
//   · opening the Duo — a short swell as the cover's sky widens into the spread.
//
// And the room's dimming (`depth`), which never jumps: it eases in from 0 when a
// sleep starts (with the bedtime moment, or quietly when the sleep `arrive`s from
// elsewhere) and, when he wakes, eases out from what that sleep had — a night's 1,
// a nap's 0.45 — so the first frame after a change is the frame before it. The
// solar bloom is taken from that eased depth. `arrive`, `settle` (first light) and
// `wake` have no bloom of their own: a wake's tone goes one way, to its resting value.
//
// Everything here is pure. `state` is the lab's state (README); events arrive as
// state.event = { kind: 'bedtime' | 'arrive' | 'settle' | 'wake' | 'open' | 'close', age: seconds since,
// woke: 'night' | 'nap' (a wake's: the sleep that ended) }.
// (Whether the night has begun — the view up, tonight's star lit — is not presence's business: `state.nightBegun`.)

import { smoothstep } from './oklab.js';

const DEG = 180 / Math.PI;

/** The solar bloom alone, from the sun's altitude in degrees. */
export function solarBloom(altitudeDeg) {
  const opening = 1 - smoothstep(2.5, 10, altitudeDeg);   // 0 above 10°, 1 below 2.5°
  const closing = smoothstep(-10.5, -4.5, altitudeDeg);    // 1 above −4.5°, 0 below −10.5°
  return opening * closing;
}

/** A small bloom while a bright moon is low: within ~6° of the horizon, scaled
 *  by how full it is, and only once the sun is well down. */
export function moonBloom(moon, sunAltitudeDeg) {
  if (!moon) return 0;
  const low = 1 - smoothstep(2, 9, moon.altitude * DEG);
  const dark = 1 - smoothstep(-9, -4, sunAltitudeDeg);
  return 0.35 * low * dark * smoothstep(0.55, 0.95, moon.fraction);
}

/** One event's swell at `age` seconds: up over `attack`, held, then down over `release`. */
export function swell(age, { attack, hold, release }) {
  if (age == null || age < 0) return 0;
  if (age < attack) return smoothstep(0, attack, age);
  if (age < attack + hold) return 1;
  return 1 - smoothstep(attack + hold, attack + hold + release, age);
}

// (No `wake`: BRIEF.md, "After the first review" — waking only un-dims the room. It had a bloom of its
// own, peak 0.35 over 1.2 s and 8 s to let go: at every wake the sky swelled past its resting tone and
// fell back — 0.00355 asleep, 0.00424 at 5 s, 0.00409 at rest for a 03:00 feed in the dark appearance.)
export const EVENTS = {
  bedtime: { attack: 1.6, hold: 2.4, release: 14, peak: 0.55 },
  open: { attack: 0.5, hold: 0.9, release: 5, peak: 0.45 },
  close: { attack: 0.3, hold: 0.2, release: 2, peak: 0.15 },
};

// ── the bedtime moment's timeline ────────────────────────────────────────
// BRIEF.md, "After the first review", item 3: the sky keeps its pace, the cards
// give up the time. Seconds since the tap. One table for the sky (the rise, the
// band, the caption) and for the lab's UI (the cards: `momentVeil`), so the two
// cannot drift apart: the caption has gone before a card is back, and the band
// has crossed before that.
//
//   fall      the cards fall back (smoothstep): under 5 % by 0.87 s
//   rise      the view rises (a quintic ease). The slab's sky is twice as tall as
//             the Duo's (630 pt against 312), so its rise is 0.3 s longer: at its
//             peak 492 pt/s, not 563 (the Duo's: 279)
//   band      it leaves tonight's star as the view arrives and crosses the anchor
//             window to its farthest corner in `crosses` seconds (Duo 276 pt/s,
//             slab 410); its own light has gone at nine tenths of the way
//   caption   "✦ Night 143": in, and out
//   back      the cards return over the sky that is already there, with an
//             ease-out (`easeOut`: SwiftUI's .easeOut), starting as the caption
//             has gone
//   reduced   Reduce Motion: no move, no band. The cards go, the looked-up still
//             dissolves in once they are under 10 % (0.6 s), the caption stands
//             for two seconds, the cards return: about 4 s
//   quiet     arrive and settle under Reduce Motion: a 0.6 s dissolve
//
// In the app a touch ends the moment at once: cards back in 0.3 s, band and
// caption out in 0.2 s; the view stays up (skies/hill-painted.md, "Bedtime").
export const MOMENT = Object.freeze({
  fall: Object.freeze([0, 1.0]),
  rise: Object.freeze({ duo: Object.freeze([0.3, 2.4]), slab: Object.freeze([0.3, 2.7]) }),
  band: Object.freeze({ duo: Object.freeze({ leaves: 2.1, crosses: 2.1 }), slab: Object.freeze({ leaves: 2.3, crosses: 2.0 }) }),
  caption: Object.freeze({ in: Object.freeze([2.0, 2.8]), out: Object.freeze([4.15, 4.6]) }),
  back: Object.freeze([4.6, 5.8]),
  reduced: Object.freeze({
    fall: Object.freeze([0, 0.6]),
    dissolve: Object.freeze([0.6, 1.2]),
    caption: Object.freeze({ in: Object.freeze([1.2, 1.6]), out: Object.freeze([3.0, 3.4]) }),
    back: Object.freeze([3.4, 4.0]),
  }),
  quiet: Object.freeze({ dissolve: 0.6 }),
});

/** SwiftUI's `.easeOut` (the CSS `ease-out`): the cubic Bézier (0, 0, 0.58, 1), y at x = `u`.
 *  Quick away and soft to rest: half way at a third of the time (0.34), 95 % by 0.83. */
export function easeOut(u) {
  if (!(u > 0)) return 0;
  if (u >= 1) return 1;
  // x(s) = 3·0.58·(1 − s)·s² + s³ is monotonic on 0–1: solve x(s) = u by bisection
  let lo = 0, hi = 1;
  for (let i = 0; i < 40; i += 1) {
    const s = (lo + hi) / 2;
    if (1.74 * (1 - s) * s * s + s * s * s < u) lo = s; else hi = s;
  }
  const s = (lo + hi) / 2;
  return 3 * (1 - s) * s * s + s * s * s;
}

/** How far the phone page's cards have fallen back at `age` seconds into the bedtime moment, 0–1
 *  (`state.veil`; a card's opacity is 1 − veil): the lab's UI curve — tools/film.mjs and
 *  tools/review.mjs play this one. They fall back with a smoothstep and return with an ease-out. */
export function momentVeil(age, reduceMotion = false) {
  const m = reduceMotion ? MOMENT.reduced : MOMENT;
  if (!(age > m.fall[0])) return 0;
  if (age >= m.back[1]) return 0;
  if (age >= m.back[0]) return 1 - easeOut((age - m.back[0]) / (m.back[1] - m.back[0]));
  return smoothstep(m.fall[0], m.fall[1], age);
}

/** How lit the caption is at `age` seconds into the moment, 0–1 (the sky multiplies it by the veil). */
export function momentCaption(age, reduceMotion = false) {
  const c = (reduceMotion ? MOMENT.reduced : MOMENT).caption;
  return smoothstep(c.in[0], c.in[1], age) * (1 - smoothstep(c.out[0], c.out[1], age));
}

/** How lit tonight's star is in the bedtime moment, given whether it was lit before (the night had
 *  already begun) and the spark's own curve now (lab/nights.js, `ignition`): a star is lit ONCE, from
 *  what it was — a lit star is left alone, it is never put out to be lit again, and never flares. */
export function litFrom(wasLit, sparkNow) {
  return wasLit ? 1 : sparkNow;
}

/** How far a sleep dims the room. */
export const SLEEP_DEPTH = { night: 1, nap: 0.45 };

/** The room's dimming, 0–1: the running sleep's own depth, eased across a sleep's start and end. */
export function roomDepth(state) {
  const target = SLEEP_DEPTH[state.asleep] ?? 0;
  const e = state.event;
  if (!e) return target;                                    // with no event in the URL it has already dimmed
  // A sleep starts: the room dims over the first seconds — with the moment, after the cards have gone;
  // quietly, at once, when the sleep arrives from elsewhere.
  if (e.kind === 'bedtime') return target * smoothstep(1.2, 9, e.age);
  if (e.kind === 'arrive') return target * smoothstep(0, 4, e.age);
  // He wakes: the room is still as dim as that sleep had it, and un-dims over about five seconds.
  if (e.kind === 'wake') return Math.max(target, (SLEEP_DEPTH[e.woke] ?? SLEEP_DEPTH.night) * (1 - smoothstep(0.3, 5, e.age)));
  return target;
}

/**
 * → { presence, solar, moon, event, depth, stars }
 *   presence  0–1, what a sky feeds to oklab.present()/presentDark()
 *   depth     0–1, how far the room has dimmed because he sleeps (night sleep 1,
 *             nap 0.45; eased across a sleep's start and end: roomDepth) — a sky
 *             gets deeper and stiller with it, never brighter
 *   stars     0–1, how much of the starfield is out (by the sun's altitude:
 *             none above −4°, all of it below −12°)
 */
export function presence(state) {
  const sunDeg = state.sun.altitude * DEG;
  const solar = solarBloom(sunDeg);
  const moon = moonBloom(state.moon, sunDeg);
  let event = 0;
  if (state.event && EVENTS[state.event.kind]) {
    const e = EVENTS[state.event.kind];
    event = e.peak * swell(state.event.age, e);
  }
  const depth = roomDepth(state);
  // Asleep takes a third off the solar bloom: a sunset behind a sleeping baby is still a sunset, just quieter.
  // (By the eased depth: at a dawn wake that third comes back over the same seconds, not in one frame.)
  const open = Math.max(solar * (1 - 0.35 * depth), moon);
  const total = Math.min(1, open + event * (1 - open));
  const stars = 1 - smoothstep(-12, -4, sunDeg);
  return { presence: total, solar, moon, event, depth, stars };
}
