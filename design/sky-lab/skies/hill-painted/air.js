// The air — True light's twilight, as a painter's mixing table.
//
// Round one's `true-light` wrote the sky as a "negative": keyframes by the sun's
// real altitude, each colour a [value, chroma, hue°], printed twice — high-key
// for the light appearance, low-key for the dark one. That table is kept here
// almost stop for stop (it is the one that passed every measured limit); what is
// new is what it is asked for:
//
//   · the sky is TALL. The table's eight stops still span the sky the everyday
//     view shows (e 0…1 — the horizon to the top of the display at rest); above
//     it two more stops carry the sky on to the zenith the looked-up pose reveals;
//   · there is no shader. `airFor()` answers with plain functions — skyAt(dx, e),
//     hazeAt(dx), mistAt(dx) — that the painter samples: a coarse grid for the sky
//     field, a stop every few dozen points for a plane of land;
//   · the hush and the dimmed room are applied here, once, to every colour that
//     leaves the table (`show`), so nothing downstream can forget them.
//
// Pure. OKLab colours are [L, a, b] arrays; `css()` turns one into a canvas colour.

import { smoothstep, lerp } from '../../lab/oklab.js';

const DEG = 180 / Math.PI;
const clamp01 = (x) => Math.min(1, Math.max(0, x));
export const lch = (L, C, hDeg) => [L, C * Math.cos(hDeg / DEG), C * Math.sin(hDeg / DEG)];
export const mix3 = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
const PAGE_L = 0.9612;   // #F2F2F7 in OKLab

// ─────────────────────────────────────────────────────────── the negative ──
// Stops: 0 the horizon … 1 the top of the everyday view; then the sky above it.
export const E_STOPS = [0, 0.04, 0.10, 0.18, 0.29, 0.44, 0.68, 1, 1.5, 2.3];

const KEYS = [
  { alt: 30,
    // (The low key's hushed day is not a night: a dusky slate-blue with its hue kept — pale along the
    // horizon, deeper overhead, still under the limits behind the header's words — so the tree is a
    // true silhouette on it and the planes of land can be told apart at one in the afternoon.)
    light: [0.872, 0.968, 1, 0.80], dark: [0.325, 0.495, 1.1, 1.3],
    S: [[1, .016, 235], [.97, .028, 238], [.90, .048, 242], [.78, .072, 246], [.60, .098, 250], [.40, .114, 254], [.18, .124, 257], [0, .13, 260]],
    A: [[.93, .024, 240], [.90, .034, 242], [.84, .054, 245], [.72, .078, 248], [.55, .10, 252], [.36, .114, 255], [.16, .124, 258], [0, .13, 260]],
    Sd: [[1, .045, 236], [.97, .052, 239], [.90, .066, 243], [.78, .082, 247], [.60, .10, 251], [.40, .114, 254], [.18, .124, 257], [0, .13, 260]],
    Ad: [[.92, .05, 242], [.89, .058, 244], [.83, .07, 247], [.71, .086, 250], [.55, .10, 252], [.36, .114, 255], [.16, .124, 258], [0, .13, 260]],
    sun: [1.5, .03, 95], glow: [1.12, .03, 92, 0.42],
    lo: { lit: [1.2, .012, 90], shade: [.42, .035, 255], amt: 1 },
    hi: { lit: [1.16, .008, 90], shade: [.74, .03, 250], amt: 1 },
    mist: [1.05, .012, 240],
    land: { light: [0.80, .03, 250], dark: [0.165, .034, 258] }, gain: [0.26, 0.30], rim: [1.1, .03, 90, 0.10] },
  { alt: 8,
    light: [0.862, 0.968, 1, 0.75], dark: [0.25, 0.46, 1.25, 1.15],
    S: [[1, .075, 78], [.98, .065, 84], [.92, .04, 92], [.80, .022, 150], [.62, .06, 245], [.42, .095, 254], [.24, .112, 258], [.10, .12, 262]],
    // (away from a low sun the far side is already cool rose over blue: the first of the Belt)
    A: [[.70, .05, 322], [.73, .058, 338], [.71, .055, 318], [.62, .062, 276], [.50, .085, 255], [.36, .102, 257], [.21, .112, 259], [.09, .12, 262]],
    Sd: [[1, .12, 66], [.99, .115, 72], [.94, .09, 80], [.84, .055, 60], [.66, .06, 350], [.44, .085, 285], [.24, .108, 262], [.10, .12, 262]],
    sun: [1.45, .06, 92], glow: [1.1, .09, 80, 0.55],
    lo: { lit: [1.14, .06, 82], shade: [.36, .04, 272], amt: 1 },
    hi: { lit: [1.1, .04, 80], shade: [.62, .034, 266], amt: 1 },
    mist: [1.0, .04, 80],
    land: { light: [0.80, .03, 275], dark: [0.085, .02, 275] }, gain: [0.26, 0.30], rim: [1.1, .06, 80, 0.2] },
  { alt: 2.5,
    light: [0.852, 0.965, 1, 0.64], dark: [0.135, 0.52, 1.3, 0.95],
    S: [[.96, .13, 62], [1, .12, 72], [.97, .08, 86], [.90, .04, 100], [.78, .07, 15], [.58, .085, 318], [.36, .105, 280], [.17, .115, 268]],
    A: [[.72, .04, 320], [.75, .055, 342], [.76, .065, 352], [.70, .06, 325], [.58, .075, 290], [.42, .092, 270], [.27, .105, 266], [.14, .115, 266]],
    sun: [1.9, .085, 84], glow: [1.12, .13, 68, 0.55],
    lo: { lit: [1.12, .13, 62], shade: [.36, .05, 292], amt: 1 },
    hi: { lit: [1.1, .10, 52], shade: [.62, .045, 300], amt: 1 },
    mist: [1.0, .07, 62],
    land: { light: [0.818, .026, 318], dark: [0.066, .018, 300] }, gain: [0.22, 0.40], rim: [1.08, .11, 66, 0.5] },
  { alt: -0.8,
    light: [0.846, 0.962, 1, 0.68], dark: [0.128, 0.575, 1.4, 1.0],
    S: [[.84, .18, 42], [.95, .16, 58], [1, .11, 80], [.93, .04, 100], [.80, .09, 12], [.60, .10, 318], [.38, .105, 284], [.17, .11, 270]],
    A: [[.60, .05, 320], [.64, .07, 345], [.68, .085, 352], [.64, .08, 336], [.52, .08, 302], [.38, .09, 280], [.25, .10, 272], [.14, .11, 270]],
    sun: [1.5, .16, 52], glow: [1.04, .17, 52, 0.58],
    lo: { lit: [1.08, .18, 44], shade: [.27, .05, 286], amt: 1 },
    hi: { lit: [1.08, .12, 40], shade: [.54, .05, 300], amt: 1 },
    mist: [.92, .10, 40],
    land: { light: [0.815, .028, 310], dark: [0.060, .02, 300] }, gain: [0.20, 0.40], rim: [1.0, .15, 44, 0.7] },
  { alt: -4,
    light: [0.842, 0.955, 1, 0.68], dark: [0.112, 0.53, 1.45, 1.0],
    S: [[.62, .175, 36], [.84, .165, 52], [1, .12, 78], [.92, .04, 102], [.76, .10, 8], [.54, .10, 318], [.32, .105, 286], [.13, .105, 272]],
    A: [[.40, .055, 300], [.44, .065, 325], [.48, .075, 345], [.48, .08, 335], [.40, .08, 306], [.29, .09, 282], [.18, .10, 274], [.10, .105, 272]],
    sun: [1.0, .19, 40], glow: [.95, .17, 44, 0.5],
    lo: { lit: [.82, .17, 24], shade: [.17, .05, 276], amt: 0.42 },
    hi: { lit: [.98, .13, 8], shade: [.42, .05, 292], amt: 1 },
    mist: [.62, .08, 350],
    land: { light: [0.815, .03, 296], dark: [0.052, .02, 290] }, gain: [0.18, 0.34], rim: [.8, .14, 30, 0.2] },
  { alt: -7.5,
    light: [0.84, 0.935, 1, 0.6], dark: [0.092, 0.42, 1.55, 0.95],
    S: [[.60, .16, 38], [.80, .14, 58], [.85, .08, 90], [.68, .04, 150], [.48, .06, 250], [.32, .08, 265], [.16, .085, 268], [.03, .085, 268]],
    A: [[.15, .045, 255], [.17, .05, 258], [.20, .055, 262], [.20, .06, 265], [.17, .07, 266], [.12, .075, 268], [.06, .08, 268], [0, .085, 268]],
    sun: [.8, .17, 36], glow: [.82, .16, 42, 0.34],
    lo: { lit: [.5, .1, 20], shade: [.10, .04, 268], amt: 0 },
    hi: { lit: [.62, .09, 350], shade: [.22, .045, 276], amt: 0.3 },
    mist: [.34, .04, 280],
    land: { light: [0.815, .032, 285], dark: [0.05, .018, 280] }, gain: [0.16, 0.28], rim: [.6, .1, 30, 0] },
  { alt: -11,
    light: [0.84, 0.905, 1, 1.1], dark: [0.125, 0.28, 1.5, 0.9],
    S: [[.75, .12, 42], [.85, .09, 65], [.70, .045, 120], [.50, .05, 235], [.36, .065, 258], [.22, .075, 266], [.10, .08, 268], [0, .08, 270]],
    A: [[.24, .05, 258], [.24, .055, 260], [.21, .06, 264], [.17, .065, 266], [.12, .07, 268], [.07, .075, 269], [.03, .08, 270], [0, .08, 270]],
    // (The low key's last light is not the high key's: its gold and its green-gold breath, hushed,
    // print as a brown band behind the tree. There the dying glow is one thin ember line that goes
    // up through wine and plum into the indigo — and it is written strong enough to stay a colour.)
    Sd: [[.66, .20, 34], [.70, .17, 41], [.52, .09, 20], [.42, .06, 332], [.36, .065, 275], [.22, .075, 266], [.10, .08, 268], [0, .08, 270]],
    sun: [.7, .12, 40], glow: [.8, .1, 45, 0.16],
    lo: { lit: [.4, .05, 20], shade: [.05, .04, 268], amt: 0 },
    hi: { lit: [.4, .05, 300], shade: [.16, .045, 270], amt: 0 },
    mist: [.42, .04, 265],
    land: { light: [0.818, .03, 278], dark: [0.068, .02, 272] }, gain: [0.14, 0.26], rim: [.5, .05, 30, 0] },
  { alt: -18,
    light: [0.84, 0.892, 1, 1.4], dark: [0.148, 0.234, 1.1, 1.0],
    // (The night's horizon light is a BAND, not a line: it stands as high as the tree's crown before
    // it lets go — so at night the tree is a silhouette against it, a shade lighter than the land.)
    S: [[1, .055, 262], [.97, .058, 263], [.93, .062, 265], [.87, .068, 267], [.76, .075, 269], [.50, .081, 271], [.16, .085, 273], [0, .085, 274]],
    A: [[1, .055, 262], [.97, .058, 263], [.93, .062, 265], [.87, .068, 267], [.76, .075, 269], [.50, .081, 271], [.16, .085, 273], [0, .085, 274]],
    sun: [1, .03, 262], glow: [1, .03, 262, 0],
    lo: { lit: [1, .03, 262], shade: [-.1, .05, 268], amt: 0 },
    hi: { lit: [1, .03, 262], shade: [.45, .05, 268], amt: 0 },
    mist: [1.2, .055, 258],
    land: { light: [0.82, .03, 274], dark: [0.092, .026, 268] }, gain: [0.12, 0.30], rim: [.5, .02, 260, 0] },
];
// The long hushed day is one palette: nothing begins to turn until the sun is under 15°.
KEYS.splice(1, 0, { ...KEYS[0], alt: 15 });

/** A [value, chroma, hue] of the negative, printed for a scheme → OKLab. */
function print(key, dark, vch) {
  const r = dark ? key.dark : key.light;
  const v = vch[0];
  const vv = v <= 0 ? v : v >= 1 ? 1 + (v - 1) : Math.pow(v, r[2]);
  // A saturated colour prints a little deeper in the high key, so pastels keep their chroma.
  const L = r[0] + (r[1] - r[0]) * vv - (dark ? 0 : 0.30 * vch[1]);
  // In both prints the luminous passages carry the colour; the deep ones go quiet.
  const quiet = dark ? 0.62 + 0.38 * clamp01(v) : 0.60 + 0.40 * clamp01(v);
  // A dim green-gold is khaki: in the low key that breath is plain gold.
  let h = vch[2], C = vch[1];
  if (dark && h > 88 && h < 130) { h = 72 + (h - 88) * 0.15; C *= 2.3; }
  // …and its golds lean to apricot and ember, never mustard.
  if (dark && h > 48 && h <= 88) h = 48 + (h - 48) * 0.6;
  return lch(L, C * r[3] * quiet, h);
}

/** The sun's disc is not printed with the sky: it is the light. [altitude°, [L, C, h°] dark, light]. */
const SUN_DISC = [
  [30, [0.90, 0.035, 95], [0.992, 0.02, 95]],
  [8, [0.895, 0.125, 78], [0.955, 0.12, 88]],
  [2.5, [0.90, 0.105, 76], [0.885, 0.165, 70]],
  [-0.8, [0.85, 0.13, 62], [0.86, 0.17, 56]],
  [-3, [0.62, 0.17, 40], [0.84, 0.15, 44]],
];
function sunDisc(altDeg, dark) {
  let i = 0;
  while (i < SUN_DISC.length - 2 && altDeg < SUN_DISC[i + 1][0]) i += 1;
  const a = SUN_DISC[i], b = SUN_DISC[i + 1];
  const t = clamp01((a[0] - altDeg) / (a[0] - b[0]));
  return mix3(lch(...a[dark ? 1 : 2]), lch(...b[dark ? 1 : 2]), t);
}

/** Dawn is the same table a breath cooler and rosier, with less ember. */
function dawnTweak(vch, morning) {
  if (!morning) return vch;
  const [v, C, h] = vch;
  const warm = h < 125 || h > 345 ? 1 : 0;
  return [v, C * (warm ? 0.88 : 1), warm ? (h < 125 ? h - 7 : h) : h];
}

/** Cubic Hermite through non-uniform stops (harmonic tangents: no overshoot). */
function hermite(xs, ys, x) {
  const n = xs.length;
  if (x <= xs[0]) return ys[0];
  if (x >= xs[n - 1]) return ys[n - 1];
  let i = 0;
  while (x > xs[i + 1]) i += 1;
  const h = xs[i + 1] - xs[i];
  const t = (x - xs[i]) / h;
  const slope = (j) => {
    if (j === 0) return (ys[1] - ys[0]) / (xs[1] - xs[0]);
    if (j === n - 1) return (ys[n - 1] - ys[n - 2]) / (xs[n - 1] - xs[n - 2]);
    const a = (ys[j] - ys[j - 1]) / (xs[j] - xs[j - 1]);
    const b = (ys[j + 1] - ys[j]) / (xs[j + 1] - xs[j]);
    return a * b <= 0 ? 0 : (2 * a * b) / (a + b);
  };
  const m0 = slope(i) * h, m1 = slope(i + 1) * h;
  const t2 = t * t, t3 = t2 * t;
  return (2 * t3 - 3 * t2 + 1) * ys[i] + (t3 - 2 * t2 + t) * m0 + (-2 * t3 + 3 * t2) * ys[i + 1] + (t3 - t2) * m1;
}

// ─────────────────────────────────────────────────────────────── colour ──

function labToLinear(L, a, b) {
  const l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3;
  const m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3;
  const s = (L - 0.0894841775 * a - 1.291485548 * b) ** 3;
  return [4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s];
}
const toGamma = (c) => (c <= 0.0031308 ? 12.92 * c : 1.055 * Math.pow(c, 1 / 2.4) - 0.055);

/** OKLab → sRGB 0–1 (gamma). Out of gamut gives up chroma, never hue. */
export function toRgb(lab) {
  const L = clamp01(lab[0]);
  let a = lab[1], b = lab[2];
  let lin = labToLinear(L, a, b);
  const ok = (v) => v[0] >= -1e-4 && v[0] <= 1.0001 && v[1] >= -1e-4 && v[1] <= 1.0001 && v[2] >= -1e-4 && v[2] <= 1.0001;
  if (!ok(lin)) {
    let lo = 0, hi = 1;
    for (let i = 0; i < 14; i += 1) {
      const k = (lo + hi) / 2;
      if (ok(labToLinear(L, a * k, b * k))) lo = k; else hi = k;
    }
    a *= lo; b *= lo;
    lin = labToLinear(L, a, b);
  }
  return [toGamma(clamp01(lin[0])), toGamma(clamp01(lin[1])), toGamma(clamp01(lin[2]))];
}

export function css(lab, alpha = 1) {
  const c = toRgb(lab);
  return `rgba(${Math.round(c[0] * 255)},${Math.round(c[1] * 255)},${Math.round(c[2] * 255)},${alpha})`;
}

/** WCAG relative luminance of an OKLab colour (for the limits). */
export function luminance(lab) {
  const lin = labToLinear(clamp01(lab[0]), lab[1], lab[2]);
  return 0.2126 * clamp01(lin[0]) + 0.7152 * clamp01(lin[1]) + 0.0722 * clamp01(lin[2]);
}

// ──────────────────────────────────────────────────────────────── the air ──

/**
 * Everything the painter needs to know about the light at one instant.
 *
 *   altDeg     the sun's altitude, degrees
 *   dark       the appearance
 *   morning    the sun is on its way up
 *   presence   0 hushed … 1 itself (lab/presence.js)
 *   depth      0–1, the room dimmed because he sleeps
 *   moonlight  0–1, how much the moon lights the night (0 when it is down or the sun is up)
 *   sunDx(x)   is not needed here: every function takes `dx`, the distance from the
 *              sun's x in ANCHOR WIDTHS (negative: left of the sun)
 */
export function airFor({ altDeg, dark, morning, presence, depth, moonlight = 0 }) {
  let i = 0;
  while (i < KEYS.length - 2 && altDeg < KEYS[i + 1].alt) i += 1;
  const k0 = KEYS[i], k1 = KEYS[i + 1];
  const t = smoothstep(0, 1, clamp01((k0.alt - altDeg) / (k0.alt - k1.alt)));
  const both = (get) => mix3(print(k0, dark, dawnTweak(get(k0), morning)), print(k1, dark, dawnTweak(get(k1), morning)), t);
  const num = (get) => lerp(get(k0), get(k1), t);
  const range = [num((k) => (dark ? k.dark : k.light)[0]), num((k) => (dark ? k.dark : k.light)[1])];
  const night = 1 - smoothstep(-13, -7, altDeg);

  // ── the hush and the dimmed room: every colour leaves through here ──
  // By day the light appearance's hush pulls toward the page; at night it only
  // greys (a pastel night pulled toward the page would be paler than its bloom).
  const toward = lerp(0.10, 0.55, smoothstep(-10, 0, altDeg));
  const p = clamp01(presence);
  const show = (lab, opts) => {
    const pp = opts && opts.presence != null ? opts.presence : p;
    let [L, a, b] = lab;
    if (dark) {
      L *= 1 - 0.12 * (1 - pp);
      const c = 0.4 + 0.6 * pp;
      a *= c; b *= c;
      L *= 1 - 0.14 * depth;
      a *= 1 - 0.12 * depth; b *= 1 - 0.12 * depth;
    } else {
      L += (PAGE_L - L) * toward * (1 - pp);
      // a storybook night on pale paper keeps its lilac: the hush greys the day, not the night
      const c = lerp(0.2, 0.62, night) + (1 - lerp(0.2, 0.62, night)) * pp;
      a *= c; b *= c;
      L -= 0.012 * depth;
      a *= 1 - 0.25 * depth; b *= 1 - 0.25 * depth;
    }
    return [L, a, b];
  };

  // ── the two columns: over the sun (S) and away from it (A) ──
  // Above the everyday view the sky runs on to the zenith: a little deeper, a
  // little quieter. The light appearance's upper sky is held where grey text
  // can still be read on it (L ≥ 0.846): in the looked-up pose the header sits there.
  const column = (name) => {
    const pick = (k) => (dark && k[`${name}d`] ? k[`${name}d`] : k[name]);
    const stops = k0[name].map((_, s) => both((k) => pick(k)[s]));
    const top = stops[stops.length - 1];
    // (While there is still light in the low key's sky — a summer bedtime, the sun a hand above the
    // hill — the sky the camera looks up into goes a clear shade deeper toward the zenith, as an
    // evening sky does: his stars are shown against it. Nothing of the everyday view changes.)
    const zen = dark ? 0.016 + 0.012 * night + 0.064 * (1 - night) : 0.0;
    stops.push([top[0] - zen * 0.62, top[1] * 0.96, top[2] * 0.96]);
    stops.push([top[0] - zen, top[1] * 0.9, top[2] * 0.9]);
    if (!dark) {
      for (let s = 0; s < stops.length; s += 1) {
        const floor = 0.876;
        const L = stops[s][0];
        // soft max
        const h = clamp01(0.5 + 0.5 * (L - floor) / 0.02);
        stops[s] = [lerp(floor, L, h) + 0.02 * h * (1 - h), stops[s][1], stops[s][2]];
      }
    }
    return stops;
  };
  const S = column('S'), A = column('A');
  const N = 96;                                   // samples per column, denser toward the horizon
  const EMAX = E_STOPS[E_STOPS.length - 1];
  const table = (stops) => {
    const out = new Float32Array(N * 3);
    for (let n = 0; n < N; n += 1) {
      const e = EMAX * Math.pow(n / (N - 1), 2);
      for (let c = 0; c < 3; c += 1) out[n * 3 + c] = hermite(E_STOPS, stops.map((s) => s[c]), e);
    }
    return out;
  };
  const tS = table(S), tA = table(A);
  const ramp = (tab, e, out, o) => {
    const f = Math.sqrt(Math.min(1, Math.max(0, e / EMAX))) * (N - 1);
    const n = Math.min(N - 2, Math.floor(f));
    const k = f - n;
    out[o] = tab[n * 3] + (tab[n * 3 + 3] - tab[n * 3]) * k;
    out[o + 1] = tab[n * 3 + 1] + (tab[n * 3 + 4] - tab[n * 3 + 1]) * k;
    out[o + 2] = tab[n * 3 + 2] + (tab[n * 3 + 5] - tab[n * 3 + 2]) * k;
  };

  // The arch: over the sun the bands stand at their full height; away from it
  // they sink toward the horizon, and a page away the far column takes over —
  // the Belt of Venus over the earth's shadow.
  const ARCH_W = 0.60, ARCH_FAR = 0.44, ANTI_FROM = 0.10, ANTI_TO = 1.35;
  // (the earth's shadow is slate-blue, a little toward violet: at 252° it printed as a teal stripe — the app's own accent)
  const shadowLab = print(k0, dark, [0.20, 0.05, 268]).map((v, c) => lerp(v, print(k1, dark, [0.20, 0.05, 268])[c], t));
  const shadowAmt = 0.85 * smoothstep(-1.5, 2.5, -altDeg) * (1 - smoothstep(6, 9.5, -altDeg));
  const shadowH = lerp(0.06, 0.2, smoothstep(0, 5, -altDeg));
  const sA = new Float32Array(3), sB = new Float32Array(3);
  /** The sky at `dx` anchor-widths from the sun, elevation `e` (table units) → raw OKLab (before `show`). */
  const skyRaw = (dx, e, out, o = 0) => {
    const wS = Math.exp(-(dx * dx) / (ARCH_W * ARCH_W));
    const arch = ARCH_FAR + (1 - ARCH_FAR) * wS;
    const ee = Math.max(0, e);
    // Only the table's own span leans; the sky above the everyday view is one sky.
    const eg = ee >= 1 ? ee : 1 - Math.pow(1 - ee, 1 / arch);
    const wA = smoothstep(ANTI_FROM, ANTI_TO, Math.abs(dx));
    ramp(tS, eg, sA, 0);
    ramp(tA, ee, sB, 0);
    let L = sA[0] + (sB[0] - sA[0]) * wA, a = sA[1] + (sB[1] - sA[1]) * wA, b = sA[2] + (sB[2] - sA[2]) * wA;
    const wShadow = shadowAmt * smoothstep(0.95, 1.9, Math.abs(dx)) * (1 - smoothstep(shadowH * 0.35, shadowH, ee));
    if (wShadow > 0) { L += (shadowLab[0] - L) * wShadow; a += (shadowLab[1] - a) * wShadow; b += (shadowLab[2] - b) * wShadow; }
    out[o] = L; out[o + 1] = a; out[o + 2] = b;
  };

  const glow = both((k) => k.glow);
  const glowAmt = num((k) => k.glow[3]) * (dark ? 0.4 + 0.6 * smoothstep(-15, -6, -altDeg) : 1);
  const rim = both((k) => k.rim);
  const land = mix3(lch(...(dark ? k0.land.dark : k0.land.light)), lch(...(dark ? k1.land.dark : k1.land.light)), t);
  const mist = both((k) => k.mist);
  const mistFar = both((k) => [k.mist[0] * 0.72, 0.045, k.alt > 5 ? k.mist[2] : 302]);
  const ambient = [0, 0, 0];
  { const tmp = new Float32Array(3); ramp(tS, 0.55, tmp, 0); ambient[0] = tmp[0]; ambient[1] = tmp[1]; ambient[2] = tmp[2]; }
  // Moonlight is silver: the night key's lightest value, cooled.
  const silver = print(KEYS[KEYS.length - 1], dark, [dark ? 1.55 : 1.9, 0.045, 255]);

  const tmp = new Float32Array(3);
  const skyAt = (dx, e) => { skyRaw(dx, e, tmp, 0); return [tmp[0], tmp[1], tmp[2]]; };
  /** The air between the ridges at dx: the low sky, not only its rim. */
  const hazeAt = (dx) => {
    const h = skyAt(dx, 0.012), up = skyAt(dx, 0.27);
    const wA = smoothstep(ANTI_FROM, ANTI_TO, Math.abs(dx));
    const m = mix3(mix3(h, up, 0.55), ambient, 0.25 + 0.15 * wA);
    return [m[0], m[1] * 0.85, m[2] * 0.85];
  };
  /** Mist at `dxLight` anchor-widths from the light: it catches the light near it, and goes to the far tint away. */
  const mistAt = (dxLight, dxSun) => {
    const lit = moonlight > 0 ? mix3(mist, silver, 0.5 * moonlight) : mist;
    const far = moonlight > 0 ? mix3(mistFar, silver, 0.5 * moonlight) : mistFar;
    const m = mix3(lit, far, smoothstep(0.12, 1.1, Math.abs(dxLight)));
    return mix3(m, hazeAt(dxSun), 0.18 + 0.2 * smoothstep(0.1, 0.9, Math.abs(dxLight)));
  };

  return {
    dark, altDeg, morning, presence: p, depth, night, range, moonlight,
    show, skyRaw, skyAt, hazeAt, mistAt,
    sun: sunDisc(altDeg, dark),
    glow, glowAmt,
    rim, rimAmt: num((k) => k.rim[3]),
    land, gain: num((k) => k.gain[dark ? 1 : 0]),
    mist, mistFar, ambient, silver,
    cloud: {
      loLit: both((k) => k.lo.lit), loShade: both((k) => k.lo.shade), loAmt: num((k) => k.lo.amt),
      hiLit: both((k) => k.hi.lit), hiShade: both((k) => k.hi.shade), hiAmt: num((k) => k.hi.amt),
    },
    // how much of the day's own colour the land keeps (none of it at night)
    day: smoothstep(-2, 16, altDeg),
    lastLight: smoothstep(-7, -1, altDeg),
    print: (vch) => both(() => vch),
  };
}
