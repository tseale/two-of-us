// A star for every night of his life.
//
// Night 1 is the night he was born; tonight is night `ageDays + 1`. Every night
// has one star and it never moves: the place is a function of the night's number
// alone (a low-discrepancy sequence, so each new star lands in the widest gap
// the earlier ones left, and the sky fills evenly from the first night to the
// thousandth). Brightness and warmth are seeded by the number too.
//
//   · the first night is the brightest star in his sky
//   · each month-birthday night is a brighter star with a four-point glint
//   · tonight's star is warm (nightlight cream) and is only lit once he is down
//     for the night; in the morning it cools and joins the rest. The lab says
//     when with `state.tonightLit` (README): nights(state.ageDays, { tonightLit: state.tonightLit })
//
// Pure. Positions are (u, v) in 0–1: u across the sky's width (the WORLD's, see
// the README: a sky decides how wide its world is — the same star is in the same
// place on the cover and on the spread only if the sky maps u onto the anchor
// window consistently), v from the zenith (0) down to the horizon (1).

const PLASTIC = 1.32471795724474602596;
const A1 = 1 / PLASTIC;
const A2 = 1 / (PLASTIC * PLASTIC);
const frac = (x) => x - Math.floor(x);

/** A stable 0–1 hash of an integer and a salt. */
export function hash(n, salt = 0) {
  let h = (Math.imul(n | 0, 0x9e3779b1) ^ Math.imul((salt | 0) + 0x85ebca6b, 0xc2b2ae35)) >>> 0;
  h ^= h >>> 15; h = Math.imul(h, 0x2c1b3c6d) >>> 0;
  h ^= h >>> 12; h = Math.imul(h, 0x297a2d39) >>> 0;
  h ^= h >>> 15;
  return (h >>> 0) / 4294967296;
}

/** How many month-birthdays have passed by night `n` (30.44-day months; the lab
 *  has no calendar for him, the app would use his real date of birth). */
const monthsBy = (n) => Math.floor((n - 1) / 30.4375);

/**
 * The stars of his sky on night `ageDays + 1`.
 *   ageDays     whole days since he was born (0 on his birthday)
 *   tonightLit  his star for tonight has been lit (he is down for the night) — `state.tonightLit`
 * → [{ night, u, v, magnitude, warmth, kind, twinkle: { period, phase } }]
 *   magnitude 0–1 (1 brightest), warmth −1 cool blue-white … +1 warm cream
 *   kind: 'first' | 'month' | 'tonight' | 'night'
 */
export function nights(ageDays, { tonightLit = false } = {}) {
  const count = Math.max(1, Math.floor(ageDays) + 1);
  const stars = [];
  for (let n = 1; n <= count; n++) {
    const isTonight = n === count;
    if (isTonight && !tonightLit) continue;
    const jitter = 0.018;
    const u = frac(0.5 + n * A1 + (hash(n, 1) - 0.5) * jitter);
    const v = frac(0.5 + n * A2 + (hash(n, 2) - 0.5) * jitter);
    const isFirst = n === 1;
    const isMonth = !isFirst && monthsBy(n) > monthsBy(n - 1);
    // Most stars are faint, a few are bright — as in a real sky.
    const roll = hash(n, 3);
    let magnitude = 0.22 + 0.5 * Math.pow(roll, 2.6);
    if (isMonth) magnitude = 0.78;
    if (isFirst) magnitude = 1;
    if (isTonight) magnitude = 0.92;
    const warmth = isTonight ? 1 : isFirst ? 0.55 : (hash(n, 4) - 0.5) * 1.1;
    stars.push({
      night: n, u, v, magnitude, warmth,
      kind: isTonight ? 'tonight' : isFirst ? 'first' : isMonth ? 'month' : 'night',
      twinkle: { period: 2.4 + hash(n, 5) * 3.2, phase: hash(n, 6), steady: hash(n, 7) > 0.65 },
    });
  }
  return stars;
}

/** A star's brightness at `t` seconds, as a fraction of its own: a slow swell.
 *  Tonight's star breathes on the app's own sleeping rhythm (2.6 s, 0.6–1). */
export function twinkle(star, t) {
  if (star.kind === 'tonight') return 0.8 + 0.2 * Math.cos((2 * Math.PI * t) / 5.2);
  if (star.twinkle.steady) return 1;
  return 0.66 + 0.34 * Math.cos(2 * Math.PI * (t / star.twinkle.period + star.twinkle.phase));
}

/** How lit tonight's star is, `age` seconds after he went down: a spark that
 *  swells past full and settles (0 → 1.35 → 1 over about four seconds). */
export function ignition(age) {
  if (age == null) return 1;
  if (age <= 0) return 0;
  const rise = 1 - Math.exp(-age / 0.55);
  const flare = 0.35 * Math.exp(-Math.pow((age - 1.5) / 0.9, 2));
  return rise + flare;
}
