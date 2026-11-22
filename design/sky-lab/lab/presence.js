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
// solar bloom is taken from that eased depth. `arrive` and `settle` (first light)
// have no bloom of their own.
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

export const EVENTS = {
  bedtime: { attack: 1.6, hold: 2.4, release: 14, peak: 0.55 },
  wake: { attack: 1.2, hold: 1.0, release: 8, peak: 0.35 },
  open: { attack: 0.5, hold: 0.9, release: 5, peak: 0.45 },
  close: { attack: 0.3, hold: 0.2, release: 2, peak: 0.15 },
};

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
