// True light — the real sky, with the light finally true.
//
// One light source (the sun; the moon once the sun is well down) and everything
// answers it: the twilight leans toward the sun's x and wraps along the horizon,
// the cloud bank is lit from where the light really is, ridge behind ridge takes
// its colour from the sky at the horizon, mist lies in the valleys and catches
// the last light, and opposite the sun the Belt of Venus stands over the earth's
// shadow.
//
// How it is put together (and how it ports — see true-light.md):
//
//   JS (per frame, cheap)        the "negative": a table of twilight keyframes by
//                                the sun's real altitude, authored once as value /
//                                chroma / hue, then PRINTED twice — a high-key print
//                                for the light appearance, a low-key one for the dark.
//                                Out come 2 × 32 OKLab ramp samples and ~30 colours.
//   one fragment shader (WebGL2) sky ramps → sun, moon → two cloud families lit by a
//                                short walk toward the light → seven ridges with aerial
//                                perspective, woods and valley mist → the lab's
//                                hush (oklab.present) → sRGB, dithered.
//   a 2-D canvas, as a texture   his stars (lab/nights.js), sharp, each its own
//                                colour; the shader hides them behind cloud and land.
//   a 2-D canvas on top          tonight's star, fireflies, snowflakes, the "Night 143" caption.
//
// World: x = 0…1 across the anchor window (state.phone), running on to −1.04 on
// the spread's leading page; the horizon is a fixed 305 pt from the top on the
// Duo (cover and spread are the same picture to the point), 350 pt on the slab.

import { presence } from '../lab/presence.js';
import { nights, twinkle, ignition, hash } from '../lab/nights.js';
import { season as seasonOf } from '../lab/season.js';
import { GLSL_NOISE } from '../lab/noise.js';
import { smoothstep, lerp } from '../lab/oklab.js';

export const meta = {
  id: 'true-light',
  name: 'True light',
  blurb: 'The real sky with one true light: a leaning twilight, a lit cloud bank, ridge behind ridge, his stars.',
};

const DEG = 180 / Math.PI;
const TAU = Math.PI * 2;
const clamp01 = (x) => Math.min(1, Math.max(0, x));
const lch = (L, C, hDeg) => [L, C * Math.cos(hDeg / DEG), C * Math.sin(hDeg / DEG)];
const mix3 = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
const PAGE_L = 0.9612;   // #F2F2F7 in OKLab

// ───────────────────────────────────────────────────────────── the negative ──
// Twilight by the sun's altitude (degrees). Each colour is [value, chroma, hue°]:
// value 0–1 inside that hour's own range, so the same table prints high-key
// (light appearance) and low-key (dark appearance). S is the column of sky at the
// sun's x, A the column opposite the sun; stops are at E_STOPS (0 the horizon,
// 1 the top of the display).
const E_STOPS = [0, 0.04, 0.10, 0.18, 0.29, 0.44, 0.68, 1];
const N_RAMP = 32;

const KEYS = [
  { alt: 30,
    light: [0.872, 0.968, 1, 0.80], dark: [0.165, 0.250, 1, 0.62],
    S: [[1, .016, 235], [.97, .028, 238], [.90, .048, 242], [.78, .072, 246], [.60, .098, 250], [.40, .114, 254], [.18, .124, 257], [0, .13, 260]],
    A: [[.93, .024, 240], [.90, .034, 242], [.84, .054, 245], [.72, .078, 248], [.55, .10, 252], [.36, .114, 255], [.16, .124, 258], [0, .13, 260]],
    sun: [1.5, .03, 95], glow: [1.12, .03, 92, 0.42],
    lo: { lit: [1.2, .012, 90], shade: [.42, .035, 255], amt: 1 },
    hi: { lit: [1.16, .008, 90], shade: [.74, .03, 250], amt: 1 },
    mist: [1.05, .012, 240],
    land: { light: [0.80, .03, 250], dark: [0.105, .02, 255] }, gain: [0.26, 0.30], rim: [1.1, .03, 90, 0.10] },
  { alt: 8,
    light: [0.862, 0.968, 1, 0.75], dark: [0.150, 0.355, 1.35, 0.80],
    S: [[1, .075, 78], [.98, .065, 84], [.92, .04, 92], [.80, .022, 150], [.62, .06, 245], [.42, .095, 254], [.24, .112, 258], [.10, .12, 262]],
    A: [[.70, .03, 290], [.72, .035, 310], [.70, .04, 285], [.62, .06, 258], [.50, .085, 255], [.36, .102, 257], [.21, .112, 259], [.09, .12, 262]],
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
    sun: [.7, .12, 40], glow: [.8, .1, 45, 0.16],
    lo: { lit: [.4, .05, 20], shade: [.05, .04, 268], amt: 0 },
    hi: { lit: [.4, .05, 300], shade: [.16, .045, 270], amt: 0 },
    mist: [.42, .04, 265],
    land: { light: [0.818, .03, 278], dark: [0.068, .02, 272] }, gain: [0.14, 0.26], rim: [.5, .05, 30, 0] },
  { alt: -18,
    light: [0.84, 0.892, 1, 1.4], dark: [0.148, 0.234, 1.1, 1.0],
    S: [[1, .055, 262], [.92, .06, 264], [.78, .066, 266], [.60, .072, 268], [.40, .078, 270], [.22, .082, 272], [.08, .085, 273], [0, .085, 274]],
    A: [[1, .055, 262], [.92, .06, 264], [.78, .066, 266], [.60, .072, 268], [.40, .078, 270], [.22, .082, 272], [.08, .085, 273], [0, .085, 274]],
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
  if (dark && h > 88 && h < 130) { h = 76 + (h - 88) * 0.15; C *= 1.5; }
  // …and its golds lean to apricot and ember, never mustard.
  if (dark && h > 48 && h <= 88) h = 48 + (h - 48) * 0.6;
  return lch(L, C * r[3] * quiet, h);
}

/** The sun's disc is not printed with the sky: it is the light, and keeps its
 *  own brightness in both appearances. [altitude°, [L, C, h°] dark, light]. */
const SUN_DISC = [
  [30, [0.90, 0.035, 95], [0.992, 0.02, 95]],
  [8, [0.90, 0.05, 92], [0.988, 0.035, 90]],
  [2.5, [0.90, 0.065, 86], [0.982, 0.05, 86]],
  [-0.8, [0.80, 0.13, 60], [0.95, 0.10, 62]],
  [-3, [0.60, 0.17, 40], [0.90, 0.12, 48]],
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

/** Cubic Hermite through non-uniform stops (finite-difference tangents). */
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
    return a * b <= 0 ? 0 : (2 * a * b) / (a + b);   // harmonic: no overshoot
  };
  const m0 = slope(i) * h, m1 = slope(i + 1) * h;
  const t2 = t * t, t3 = t2 * t;
  return (2 * t3 - 3 * t2 + 1) * ys[i] + (t3 - 2 * t2 + t) * m0 + (-2 * t3 + 3 * t2) * ys[i + 1] + (t3 - t2) * m1;
}

/** The whole palette for one instant: the two ramps (N_RAMP samples, denser
 *  toward the horizon: e = (k/31)²) and every other colour, printed. */
function palette(altDeg, dark, morning) {
  let i = 0;
  while (i < KEYS.length - 2 && altDeg < KEYS[i + 1].alt) i += 1;
  const k0 = KEYS[i], k1 = KEYS[i + 1];
  const t = smoothstep(0, 1, clamp01((k0.alt - altDeg) / (k0.alt - k1.alt)));
  const both = (get) => mix3(print(k0, dark, dawnTweak(get(k0), morning)), print(k1, dark, dawnTweak(get(k1), morning)), t);
  const column = (name) => {
    const stops = E_STOPS.map((_, s) => both((k) => k[name][s]));
    const out = new Float32Array(N_RAMP * 3);
    for (let n = 0; n < N_RAMP; n += 1) {
      const e = Math.pow(n / (N_RAMP - 1), 2);
      for (let c = 0; c < 3; c += 1) out[n * 3 + c] = hermite(E_STOPS, stops.map((s) => s[c]), e);
    }
    return out;
  };
  const num = (get) => lerp(get(k0), get(k1), t);
  return {
    solar: column('S'), anti: column('A'),
    sun: both((k) => k.sun), glow: both((k) => k.glow), glowAmt: num((k) => k.glow[3]),
    loLit: both((k) => k.lo.lit), loShade: both((k) => k.lo.shade), loAmt: num((k) => k.lo.amt),
    hiLit: both((k) => k.hi.lit), hiShade: both((k) => k.hi.shade), hiAmt: num((k) => k.hi.amt),
    mist: both((k) => k.mist),
    mistFar: both((k) => [k.mist[0] * 0.72, 0.045, k.alt > 5 ? k.mist[2] : 302]),
    shadow: both(() => [0.20, 0.05, 252]),
    rim: both((k) => k.rim), rimAmt: num((k) => k.rim[3]),
    land: mix3(lch(...(dark ? k0.land.dark : k0.land.light)), lch(...(dark ? k1.land.dark : k1.land.light)), t),
    gain: num((k) => k.gain[dark ? 1 : 0]),
    range: [num((k) => (dark ? k.dark : k.light)[0]), num((k) => (dark ? k.dark : k.light)[1])],
    chroma: num((k) => (dark ? k.dark : k.light)[3]),
  };
}

// ───────────────────────────────────────────────────────────────── the land ──
// Seven ridges, far to near. Points below the horizon (on the Duo; scaled by the
// land's height on the slab), amplitude in points, base wavelength in anchor
// widths, how far it has gone into the haze, edge softness, canopy height.
const RIDGES = [
  { base: -10, amp: 10, freq: 5.2, seed: 11.3, haze: 0.90, soft: 2.8, trees: 0, mist: 6, depth: 1.2 },
  { base: 6, amp: 14, freq: 4.3, seed: 27.9, haze: 0.77, soft: 2.3, trees: 0, mist: 8, depth: 2 },
  { base: 27, amp: 18, freq: 3.5, seed: 43.1, haze: 0.62, soft: 1.9, trees: 0, mist: 11, depth: 3.2 },
  { base: 56, amp: 24, freq: 2.9, seed: 61.7, haze: 0.47, soft: 1.6, trees: 1.5, mist: 15, depth: 5 },
  { base: 98, amp: 30, freq: 2.3, seed: 83.2, haze: 0.32, soft: 1.3, trees: 2.6, mist: 30, depth: 8 },
  { base: 172, amp: 34, freq: 1.8, seed: 97.4, haze: 0.18, soft: 1.15, trees: 4.5, mist: 40, depth: 11 },
  { base: 276, amp: 34, freq: 1.35, seed: 121.9, haze: 0.06, soft: 1.0, trees: 17, mist: 0, depth: 15 },
];
const N_RIDGE = RIDGES.length;

/** The land's own colours for the season, as daylight albedo [L, C, h°]. */
function seasonLand(sn) {
  const mixLch = (a, b, t) => {
    const A = lch(...a), B = lch(...b);
    const m = mix3(A, B, clamp01(t));
    return [m[0], Math.hypot(m[1], m[2]), Math.atan2(m[2], m[1]) * DEG];
  };
  const w = sn.weights;
  const green = mixLch(mixLch([0.50, 0.06, 112], [0.60, 0.085, 128], w.spring / Math.max(1e-6, w.spring + w.autumn + w.winter) || 0),
    [0.44, 0.075, 140], w.summer);
  let ground = mixLch([0.47, 0.034, 72], green, sn.grass);
  // Woods: bare twigs → fresh leaf → deep summer → amber → russet.
  const leaf = sn.leafHue <= 0.5
    ? mixLch([0.66, 0.105, 124], [0.38, 0.078, 142], sn.leafHue / 0.5)
    : sn.leafHue <= 0.8
      ? mixLch([0.38, 0.078, 142], [0.60, 0.115, 78], (sn.leafHue - 0.5) / 0.3)
      : mixLch([0.60, 0.115, 78], [0.47, 0.11, 44], (sn.leafHue - 0.8) / 0.2);
  const woods = mixLch([0.33, 0.022, 45], leaf, sn.foliage);
  const blossom = [0.88, 0.05, 352];
  return { ground, woods, blossom, snow: [0.94, 0.012, 255] };
}

// ─────────────────────────────────────────────────────────────── the shader ──

const VERT = `#version 300 es
in vec2 aPos;
void main() { gl_Position = vec4(aPos, 0.0, 1.0); }`;

const FRAG = `#version 300 es
precision highp float;
out vec4 outColor;

uniform vec2 uPx;          // canvas size, device px
uniform float uDpr;
uniform vec4 uGeo;         // phoneX, phoneW, horizon, land scale        (points)
uniform vec2 uBand;        // the text band's foot (points); the limit's L
uniform vec3 uSolar[${N_RAMP}];
uniform vec3 uAnti[${N_RAMP}];
uniform vec4 uSun;         // x, y (points), radius, disc visibility
uniform vec3 uSunCol;
uniform vec4 uGlow;        // OKLab, amount
uniform vec4 uArch;        // glow width (anchor widths), far height, anti from, anti to
uniform vec4 uMoon;        // x, y (points), radius, visibility
uniform vec4 uMoonB;       // lit fraction, rotation, glow, earthshine
uniform vec3 uMoonCol;
uniform vec4 uLight;       // the light on the clouds: x, y (points), low amount, high amount
uniform vec3 uLoLit, uLoShade, uLoFar, uHiLit, uHiShade, uHiFar;
uniform vec4 uCloud;       // low cover, high cover, low drift, high drift
uniform vec4 uRidgeA[${N_RIDGE}];   // base, amp, freq, seed
uniform vec4 uRidgeB[${N_RIDGE}];   // haze, soft, trees, mist height
uniform vec4 uRidgeC[${N_RIDGE}];   // parallax x, parallax y, -, -
uniform vec3 uLand;        // the near ground, printed
uniform vec3 uWoods;       // canopy
uniform vec4 uWoodsLit;    // canopy in the last light, and how much of that light there is
uniform vec3 uBloom;       // blossom
uniform vec4 uSeason;      // snow, frost, leaf opacity, blossom
uniform vec3 uSnowLit, uSnowShade;
uniform vec4 uMist;        // OKLab, amount
uniform vec3 uMistFar;     // the mist away from the light
uniform vec4 uShadow;      // the earth's shadow: OKLab, amount
uniform float uShadowH;    // …and how high it has risen
uniform vec4 uRim;         // OKLab, amount
uniform vec3 uAmbient;     // the sky's ambient (far haze leans to it)
uniform vec4 uHush;        // presence, dark (0/1), depth, page L
uniform vec4 uTime;        // mist drift, tilt x, tilt y, grain seed
uniform sampler2D uStars;
uniform float uStarGain;

${GLSL_NOISE}

float hash11(float n) { return fract(sin(n * 127.1 + 311.7) * 43758.5453123); }
float n1(float x) {
  float i = floor(x), f = fract(x);
  float u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
  return mix(hash11(i), hash11(i + 1.0), u);
}
float fbm1(float x) { return (n1(x) * 0.56 + n1(x * 2.13 + 5.2) * 0.29 + n1(x * 4.37 + 1.7) * 0.15); }
float fbm3(vec2 p) {
  float s = 0.0, a = 0.5;
  mat2 r = mat2(0.8, -0.6, 0.6, 0.8);
  for (int i = 0; i < 3; i++) { s += a * vnoise(p); p = r * p * 2.03 + 11.7; a *= 0.5; }
  return s / 0.875;
}
float smin(float a, float b, float k) { float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0); return mix(b, a, h) - k * h * (1.0 - h); }
float smax(float a, float b, float k) { return -smin(-a, -b, k); }

vec3 ramp(vec3 stops[${N_RAMP}], float e) {
  float f = sqrt(clamp(e, 0.0, 1.0)) * ${N_RAMP - 1}.0;
  int i = int(min(floor(f), ${N_RAMP - 2}.0));
  return mix(stops[i], stops[i + 1], f - float(i));
}

// The sky at anchor-x X, elevation e: the sun's column, its bands sinking toward
// the horizon away from the sun (an arch), going over to the column opposite.
vec3 skyAt(float X, float e) {
  float dx = X - (uSun.x - uGeo.x) / uGeo.y;
  float wS = exp(-dx * dx / (uArch.x * uArch.x));
  float arch = mix(uArch.y, 1.0, wS);
  float eg = 1.0 - pow(1.0 - e, 1.0 / arch);
  float wA = smoothstep(uArch.z, uArch.w, abs(dx));
  return mix(ramp(uSolar, eg), ramp(uAnti, e), wA);
}

// The low bank: a few long bars of stratus stacked along the horizon — flat
// underneath, softer and a little billowed on top, tapering to nothing at
// their ends. The main bar is composed: one mass over the strip, where the sun
// sets, and one over the leading page's margin, 2.6 horizon-heights apart.
float bar(vec2 n, float x, float pres, float c, float thMax, float seed) {
  if (pres <= 0.0) return 0.0;
  float th = thMax * (0.22 + 0.78 * pres) * (0.72 + 0.56 * n1(x * 3.1 + seed * 2.0));
  float dy = n.y - c;
  float wob = (vnoise(vec2(x * 3.6 + seed, n.y * 17.0)) - 0.5) * th * 1.2;
  float u = dy > 0.0 ? (dy + wob) / (th * 1.35) : -dy / (th * 0.6);
  return (1.0 - smoothstep(0.25, 1.0, u)) * smoothstep(0.0, 0.35, pres);
}
float loDensity(vec2 n) {
  float x = n.x + uCloud.z;
  float pa = smoothstep(0.46, 0.86, n1(x * 0.95 + 2.3));
  float pc = smoothstep(0.50, 0.88, n1(x * 1.10 + 13.4));
  float pb = smoothstep(0.30, 0.95, 0.5 + 0.5 * cos((x - 1.36) * 2.4166)) * (0.72 + 0.28 * n1(x * 2.2 + 7.9));
  float a = bar(n, x, pa, 0.104 + 0.030 * (n1(x * 0.57 + 3.0) - 0.5), 0.030, 2.3);
  float b = bar(n, x, pb, 0.178 + 0.026 * (n1(x * 0.42 + 10.3) - 0.5), 0.056, 7.9);
  float c = bar(n, x, pc, 0.236 + 0.024 * (n1(x * 0.66 + 17.4) - 0.5), 0.022, 13.4);
  return (1.0 - (1.0 - a) * (1.0 - b) * (1.0 - c)) * smoothstep(0.03, 0.07, n.y);
}

// The high cloud: one long, soft swath slanting across the upper sky, and a
// few finer streaks above it.
float hiDensity(vec2 n) {
  float env = smoothstep(0.42, 0.66, n.y);
  vec2 q = vec2(n.x * 0.30 + uCloud.w, (n.y + 0.085 * n.x + 0.03 * sin(n.x * 1.3)) * 3.6 + 3.1);
  float f = fbm3(q);
  float fibre = vnoise(vec2(q.x * 2.2 + 1.0, q.y * 4.5)) - 0.5;
  float swath = smoothstep(0.48, 0.68, f + 0.05 * fibre);
  vec2 q2 = vec2(n.x * 0.42 + uCloud.w * 1.4 + 7.0, (n.y + 0.06 * n.x) * 8.5 + 1.7);
  float f2 = 0.62 * vnoise(q2) + 0.38 * vnoise(q2 * vec2(2.1, 2.3) + 5.0);
  float streaks = 0.42 * smoothstep(0.58, 0.82, f2) * smoothstep(0.62, 0.86, n.y);
  return env * max(swath, streaks);
}

// A ridge's crest (points from the top, y down) at anchor-x X; and the height of
// the woods standing on it.
float crestOf(int i, float X, out float canopy, out float patchOut) {
  vec4 a = uRidgeA[i];
  vec4 b = uRidgeB[i];
  float x = X + uRidgeC[i].x;
  float c = uGeo.z + (a.x + a.y * (2.0 * fbm1(x * a.z + a.w) - 1.0)) * uGeo.w + uRidgeC[i].y;
  // The near hill shoulders up at the far left of the world: the leading page's margin.
  if (i == ${N_RIDGE - 1}) c -= uGeo.w * (150.0 * exp(-pow((x + 1.12) / 0.27, 2.0)) + 16.0 * exp(-pow((x - 1.05) / 0.30, 2.0)));
  canopy = 0.0;
  patchOut = 0.0;
  if (b.z > 0.0) {
    // Woods: crowns of several sizes, in patches that thin out at their ends.
    float patchy = smoothstep(0.24, 0.52, n1(x * a.z * 2.6 + a.w * 1.7));
    if (i == ${N_RIDGE - 1}) patchy = max(patchy, smoothstep(-0.60, -0.84, x));
    patchOut = patchy;
    if (patchy > 0.0) {
      float xs = x * uGeo.y / (b.z * 1.9);
      float h = 0.0;
      for (int o = 0; o < 2; o++) {
        float cell = floor(xs);
        for (int k = -1; k <= 1; k++) {
          float cc = cell + float(k);
          float seed = cc * (1.0 + float(o) * 0.37) + a.w + float(o) * 19.0;
          float cx = cc + 0.5 + (hash11(seed) - 0.5) * 0.8;
          float r = 0.55 + 0.45 * hash11(seed * 1.7 + 3.0);
          float hh = (0.45 + 0.55 * hash11(seed * 2.3 + 7.0)) * (o == 0 ? 1.0 : 0.62);
          float t = (xs - cx) / r;
          h = max(h, hh * sqrt(max(0.0, 1.0 - t * t)));
        }
        xs = xs * 1.83 + 4.7;
      }
      canopy = b.z * uGeo.w * patchy * (0.18 + 0.82 * h);
    }
  }
  return c;
}

vec3 labToLinear(vec3 lab) {
  vec3 lms = mat3(1.0, 1.0, 1.0,
                  0.3963377774, -0.1055613458, -0.0894841775,
                  0.2158037573, -0.0638541728, -1.2914855480) * lab;
  lms = lms * lms * lms;
  return mat3(4.0767416621, -1.2684380046, -0.0041960863,
              -3.3077115913, 2.6097574011, -0.7034186147,
              0.2309699292, -0.3413193965, 1.7076147010) * lms;
}
// Into gamut by giving up chroma, never hue (continuous, so it cannot band).
vec3 display(vec3 lab) {
  lab.x = clamp(lab.x, 0.0, 1.0);
  vec3 lin = labToLinear(lab);
  float g = lab.x * lab.x * lab.x;
  for (int i = 0; i < 3; i++) {
    vec3 d = lin - g;
    vec3 kHi = (1.0 - g) / max(d, vec3(1e-5));
    vec3 kLo = (0.0 - g) / min(d, vec3(-1e-5));
    vec3 k3 = mix(kLo, kHi, step(vec3(0.0), d));
    float k = min(k3.x, min(k3.y, k3.z));
    if (k >= 1.0) break;
    lab.yz *= clamp(k, 0.0, 1.0);
    lin = labToLinear(lab);
  }
  return toGamma(clamp(lin, 0.0, 1.0));
}

void main() {
  vec2 pt = vec2(gl_FragCoord.x, uPx.y - gl_FragCoord.y) / uDpr;
  float hor = uGeo.z;
  float X = (pt.x - uGeo.x) / uGeo.y;
  float E = (hor - pt.y) / hor;
  float e = clamp(E, 0.0, 1.0);
  float aspect = uGeo.y / hor;
  float dxSun = X - (uSun.x - uGeo.x) / uGeo.y;
  float wS = exp(-dxSun * dxSun / (uArch.x * uArch.x));
  float wA = smoothstep(uArch.z, uArch.w, abs(dxSun));
  // Opposite the sun the earth's shadow rises out of the horizon, under the Belt.
  float wShadow = uShadow.w * smoothstep(0.95, 1.9, abs(dxSun));

  // ── land, front to back: the near hill hides the rest, and the sky ──
  vec3 landCol = vec3(0.0);
  float T = 1.0;                       // how much of what is behind still shows
  float yTop = hor - 48.0 * uGeo.w;
  if (pt.y > yTop - 150.0 * uGeo.w * step(X, -0.5)) {
    vec3 horizonCol = mix(skyAt(X, 0.012), uShadow.xyz, wShadow);
    // The air between the ridges is lit by the whole low sky, not only its rim.
    vec3 hazeCol = mix(mix(horizonCol, skyAt(X, 0.27), 0.55), uAmbient, 0.25 + 0.15 * wA);
    hazeCol.yz *= 0.85;
    float dxLight = X - (uLight.x - uGeo.x) / uGeo.y;
    vec3 mistCol = mix(mix(uMist.xyz, uMistFar, smoothstep(0.12, 1.1, abs(dxLight))), hazeCol, 0.35);
    for (int k = 0; k < ${N_RIDGE}; k++) {
      int i = ${N_RIDGE - 1} - k;
      vec4 b = uRidgeB[i];
      float fi = float(i);
      float cn, cp;
      float cr = crestOf(i, X, cn, cp);
      float ground = smoothstep(-b.y, b.y, pt.y - cr);
      // Mist in the valley in front of this ridge: a level pool that the next
      // ridge's crests stand out of.
      if (i < ${N_RIDGE - 1} && b.w > 0.0 && uMist.w > 0.0 && ground > 0.0) {
        float level = uGeo.z + (uRidgeA[i + 1].x - 0.30 * uRidgeA[i + 1].y) * uGeo.w + uRidgeC[i].y;
        float mn = vnoise(vec2(X * uGeo.y / (90.0 + 40.0 * fi) + uTime.x * (1.0 + 0.3 * fi) + fi * 5.3, pt.y / (10.0 + 4.0 * fi) + fi));
        float mw = vnoise(vec2(X * uGeo.y / (260.0 + 60.0 * fi) - uTime.x * 0.5 + fi * 9.1, 0.5));
        float depth = (pt.y - level + (mn - 0.5) * b.w * 1.1) / (b.w * uGeo.w);
        float m = uMist.w * smoothstep(-0.9, 1.6, depth) * smoothstep(0.25, 0.75, mw + 0.25);
        m = clamp(m, 0.0, 0.8) * ground * (1.0 - 0.5 * wA * (1.0 - uHush.y));
        landCol += T * m * mistCol;
        T *= 1.0 - m;
      }
      float top = cr - cn;
      float wood = cn > 0.0 ? smoothstep(-b.y * 1.8, b.y * 1.8, pt.y - top) * uSeason.z : 0.0;
      float a = max(ground, wood);
      if (a > 0.001) {
        float below = max(pt.y - cr, 0.0);
        // Texture of the slope: broad, slow.
        float tex = vnoise(vec2(X * uGeo.y / (34.0 + 24.0 * fi) + fi * 7.1, pt.y / (15.0 + 9.0 * fi)));
        vec3 g = uLand;
        // Which way the slope under the crest faces: toward the light, or away.
        float fx = (X + uRidgeC[i].x) * uRidgeA[i].z + uRidgeA[i].w;
        float slope = (fbm1(fx + 0.04) - fbm1(fx - 0.04)) * 12.0;         // + falls to the right
        float side = clamp(0.5 - clamp(dxSun * 6.0, -1.0, 1.0) * slope, 0.0, 1.0);
        // Frost silvers the open ground; snow lies on it with blue shadows.
        g = mix(g, mix(g, uSnowLit, 0.5), uSeason.y * (0.30 + 0.55 * tex));
        // Snow: bright on the shoulders where the sky reaches it, blue down in
        // the hollows; the slopes that face the low sun take a little of its colour.
        float hollow = smoothstep(0.0, 30.0 + 16.0 * fi, below + (tex - 0.5) * (24.0 + 8.0 * fi));
        vec3 snow = mix(uSnowLit, uSnowShade, hollow * (0.55 + 0.45 * wA));
        g = mix(g, snow, uSeason.x * (0.86 + 0.14 * tex));
        // Woods on the crest, thinning down the slope; their tops catch the
        // light, and that is where the season shows: russet, blossom, new leaf.
        float inWood = cp * uSeason.z * (1.0 - smoothstep(0.0, b.z * uGeo.w * 2.2 + 8.0 + 6.0 * fi, below + (tex - 0.5) * 10.0));
        float wmask = max(inWood, wood * (1.0 - ground));
        if (wmask > 0.001) {
          float topLit = exp(-max(pt.y - top, 0.0) / (4.0 + b.z * uGeo.w * 1.4)) * (0.42 + 0.58 * wS) * uWoodsLit.w * (i == ${N_RIDGE - 1} ? 0.7 : 1.0);
          vec3 w = mix(uWoods, uWoodsLit.xyz, clamp(topLit, 0.0, 1.0));
          // Blossom: a pale haze drifting through the woods, strongest along their tops.
          float fx2 = X * uGeo.y;
          float drift = 0.62 * vnoise(vec2(fx2 / (46.0 + 12.0 * fi) + fi * 3.0, pt.y / (34.0 + 8.0 * fi)))
                      + 0.38 * vnoise(vec2(fx2 / (19.0 + 5.0 * fi) + fi * 7.0, pt.y / (15.0 + 4.0 * fi) + 3.0));
          float flower = uSeason.w * smoothstep(0.34, 0.72, drift) * (0.45 + 0.55 * exp(-max(pt.y - top, 0.0) / (b.z * uGeo.w * 1.6 + 6.0)));
          w = mix(w, uBloom, 0.8 * flower);
          w = mix(w, uSnowLit, 0.30 * uSeason.x);
          g = mix(g, w, wmask);
        }
        // The slope that faces the light catches it under the crest.
        float rim = uRim.w * side * exp(-below / (7.0 + 4.0 * fi)) * (0.30 + 0.70 * wS);
        g = mix(g, uRim.xyz, rim * 0.55);
        // Aerial perspective: into the sky's own colour at the horizon; and
        // down the slope it sinks into the valley's air.
        float hz = b.x + (1.0 - b.x) * 0.36 * smoothstep(0.0, 60.0 + 50.0 * fi, below);
        landCol += T * a * mix(g, hazeCol, hz);
        T *= 1.0 - a;
      }
      if (T < 0.004) break;
    }
  }
  float landA = 1.0 - T;

  // ── sky (only where the land lets it through) ──
  vec3 lab = vec3(0.0);
  float cloudA = 0.0;
  float moonLight = 0.0;
  float sunDisc = 0.0;
  if (T >= 0.004) {
    lab = skyAt(X, e);
    lab = mix(lab, uShadow.xyz, wShadow * (1.0 - smoothstep(uShadowH * 0.35, uShadowH, e)));

    // The sun's own light in the air around it, hugging the horizon.
    vec2 ds = (pt - uSun.xy) / hor;
    float rs = length(ds * vec2(0.8, 1.2));
    float glow = uGlow.w * (0.55 * exp(-rs / 0.22) + 0.45 * exp(-rs / 0.06));
    lab = mix(lab, uGlow.xyz, clamp(glow, 0.0, 0.92));
    sunDisc = uSun.w * (1.0 - smoothstep(uSun.z - 0.9, uSun.z + 0.9, length(pt - uSun.xy)));

    // The moon: a quiet glow, the lit part of the disc turned to its real angle.
    if (uMoon.w > 0.0) {
      vec2 dm = pt - uMoon.xy;
      float rm = length(dm);
      float mg = uMoonB.z * (0.5 * exp(-rm / (hor * 0.20)) + 0.5 * exp(-rm / (uMoon.z * 1.7)));
      lab = mix(lab, uMoonCol, clamp(mg, 0.0, 0.8) * uMoon.w);
      if (rm < uMoon.z + 2.0) {
        float cr = cos(-uMoonB.y), sr = sin(-uMoonB.y);
        vec2 q = vec2(cr * dm.x - sr * dm.y, sr * dm.x + cr * dm.y);
        float limb = 1.0 - smoothstep(uMoon.z - 0.8, uMoon.z + 0.8, rm);
        float term = (1.0 - 2.0 * uMoonB.x) * sqrt(max(uMoon.z * uMoon.z - q.y * q.y, 0.0));
        float lit = smoothstep(term - 0.8, term + 0.8, q.x);
        moonLight = limb * (lit + (1.0 - lit) * uMoonB.w) * uMoon.w;
      }
    }

    // ── clouds ──
    // Lit by walking a little way toward the light through the cloud: thin and
    // sunward is bright, thick and behind is shade.
    vec2 n = vec2(X * aspect, E);
    float lightE = (hor - uLight.y) / hor;
    vec2 toLight = normalize(vec2(clamp((uLight.x - pt.x) / hor * 1.2, -0.55, 0.55), clamp((lightE - E) * 7.0, -1.0, 1.0) + 1e-3));
    float bodies = max(sunDisc, moonLight);
    if (E > 0.40 && uCloud.y > 0.0) {
      float d0 = hiDensity(n);
      if (d0 > 0.002) {
        float through = hiDensity(n + toLight * 0.03) + hiDensity(n + toLight * 0.075);
        float lit = exp(-0.4 * through) * uLight.w;
        vec3 c = mix(uHiShade, mix(uHiLit, uHiFar, wA), lit);
        float a = d0 * uCloud.y * (1.0 - 0.8 * bodies);
        lab = mix(lab, c, a);
        cloudA = a;
      }
    }
    if (E > 0.03 && E < 0.36 && uCloud.x > 0.0) {
      float d0 = loDensity(n);
      if (d0 > 0.002) {
        float through = loDensity(n + toLight * 0.016) + loDensity(n + toLight * 0.04) + loDensity(n + toLight * 0.075);
        float lit = exp(-1.25 * through) * uLight.z;
        vec3 shade = mix(uLoShade, lab, 0.20);
        vec3 c = mix(shade, mix(uLoLit, uLoFar, wA), lit);
        float a = d0 * uCloud.x * (1.0 - 0.8 * bodies);
        lab = mix(lab, c, a);
        cloudA = cloudA + (1.0 - cloudA) * a;
      }
    }
  }
  lab = landCol + T * lab;

  // ── the hush, the room, the text band ──
  float p = uHush.x;
  float band = 1.0 - smoothstep(uBand.x, uBand.x + 26.0, pt.y);
  vec3 sunCol = uSunCol;
  if (uHush.y > 0.5) {
    lab.x *= 1.0 - 0.12 * (1.0 - p);
    lab.yz *= 0.4 + 0.6 * p;
    lab.x *= 1.0 - 0.14 * uHush.z;
    lab.yz *= 1.0 - 0.12 * uHush.z;
    lab.x = mix(lab.x, smin(lab.x, uBand.y, 0.05), band);
    sunCol.x = mix(sunCol.x, min(sunCol.x, uBand.y), band);
  } else {
    lab.x += (uHush.w - lab.x) * 0.55 * (1.0 - p);
    lab.yz *= 0.2 + 0.8 * p;
    lab.x -= 0.012 * uHush.z;
    lab.yz *= 1.0 - 0.25 * uHush.z;
    lab.x = mix(lab.x, smax(lab.x, uBand.y, 0.03), band);
  }
  // The sun and the moon are never hushed: they are the light. (The land and
  // thick cloud still hide them; in the text band they are held to its limit.)
  vec3 moonCol = uMoonCol;
  if (uHush.y > 0.5) moonCol.x = mix(moonCol.x, min(moonCol.x, uBand.y), band);
  lab = mix(lab, moonCol, moonLight * T * (1.0 - 0.5 * cloudA));
  float sd = sunDisc * T * (1.0 - 0.55 * cloudA);
  lab = mix(lab, sunCol, sd);
  lab.x += 0.04 * sd * (1.0 - smoothstep(0.0, uSun.z, length(pt - uSun.xy)));

  vec3 rgb = display(lab);

  // His stars: behind the cloud, behind the land, thinned by the air at the horizon.
  vec3 st = texture(uStars, gl_FragCoord.xy / uPx).rgb;
  rgb += st * uStarGain * T * (1.0 - 0.9 * cloudA) * (1.0 - moonLight) * (1.0 - sunDisc) * (0.3 + 0.7 * smoothstep(0.0, 0.12, E));

  // Dither (triangular, one level) and a breath of grain.
  uvec2 q2 = uvec2(gl_FragCoord.xy);
  uint hA = q2.x * 1597334677u ^ q2.y * 3812015801u;
  hA = hA * (hA ^ (hA >> 15u));
  uint hB = (q2.x + 71u) * 2654435761u ^ (q2.y + 13u) * 2246822519u;
  hB = hB * (hB ^ (hB >> 13u));
  rgb += (float(hA >> 8u) + float(hB >> 8u) - 16777216.0) / 16777216.0 * (1.25 / 255.0);
  outColor = vec4(clamp(rgb, 0.0, 1.0), 1.0);
}`;

// ─────────────────────────────────────────────────────────────── geometry ──

function geometry(state) {
  const slab = state.device === 'iphone';
  const phone = state.phone ?? { x: 0, width: state.width };
  const horizon = slab ? 350 : 305;
  const landScale = slab ? (state.height - horizon) / 373 : 1;
  // The text band's foot: the header on the phone page; the titles on the spread.
  const band = slab ? 134 : 90;
  // The sun and moon never climb into the text band: their highest is just under the first card's top edge.
  const ceiling = slab ? 0.57 : 0.63;
  return { slab, phone, horizon, landScale, band, ceiling };
}

/** A body's height above the horizon, as a fraction of the horizon's height:
 *  the real altitude, opened out near the horizon and held under the text band. */
function bodyE(altitude, ceiling = 0.63) {
  const a = altitude * DEG;
  if (a <= 0) return (a / 90) * 1.4;
  const f = Math.pow(a / 90, 0.72);
  return ceiling * (1 - Math.pow(1 - f, 2.6 * 0.63 / ceiling));
}

/** Where tonight's star is lit: low in the strip's clear window on the Duo —
 *  an evening star over the hills — and beside his name on the slab. */
function tonightSpot(G) {
  return G.slab ? { x: G.phone.x + 266, y: 99 } : { x: G.phone.x + 389, y: 203 };
}

/** A night's fixed place in the anchor window (points). Weighted toward the top
 *  band and the strip, where they can be seen. */
function starPlace(star, G) {
  const u = Math.pow(star.u, 0.80);
  const v = Math.pow(star.v, 1.38);
  return { x: G.phone.x + (0.012 + 0.976 * u) * G.phone.width, y: 5 + v * (G.horizon - 22) };
}

function starColour(star) {
  // Cool blue-white … white … warm cream, and now and then a rose or an orange one.
  const w = star.warmth;
  const odd = hash(star.night, 8);
  let h = w < 0 ? 250 : 74;
  let C = 0.018 + 0.15 * Math.abs(w);
  if (odd > 0.88) { h = 42; C = 0.10; } else if (odd < 0.08) { h = 8; C = 0.07; }
  if (star.kind === 'tonight') { h = 72; C = 0.06; }
  if (star.kind === 'first') { h = 80; C = 0.035; }
  return oklchCss(0.955, C, h);
}

function oklchCss(L, C, hDeg) {
  // Tiny OKLab → sRGB for the 2-D canvases (no gamut work needed up here).
  const a = C * Math.cos(hDeg / DEG), b = C * Math.sin(hDeg / DEG);
  const l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3;
  const m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3;
  const s = (L - 0.0894841775 * a - 1.291485548 * b) ** 3;
  const g = (c) => Math.round(255 * clamp01(c <= 0.0031308 ? 12.92 * c : 1.055 * Math.pow(c, 1 / 2.4) - 0.055));
  return [g(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
    g(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
    g(-0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s)];
}
const rgba = (c, a) => `rgba(${c[0]},${c[1]},${c[2]},${a})`;

// ───────────────────────────────────────────────────────────────── module ──

export function create(host) {
  const doc = host.ownerDocument ?? document;
  const make = (z) => {
    const c = doc.createElement('canvas');
    c.setAttribute('aria-hidden', 'true');
    c.style.cssText = `position:absolute;left:0;top:0;display:block;pointer-events:none;z-index:${z};`;
    return c;
  };
  const glCanvas = make(0);
  const overCanvas = make(1);
  host.append(glCanvas, overCanvas);
  const starCanvas = doc.createElement('canvas');
  const starCtx = starCanvas.getContext('2d');
  const over = overCanvas.getContext('2d');

  const gl = glCanvas.getContext('webgl2', { antialias: false, alpha: false, depth: false, stencil: false,
    preserveDrawingBuffer: true, powerPreference: 'high-performance' });
  let program = null;
  const U = {};
  let starTex = null;
  if (gl) {
    const compile = (type, src) => {
      const sh = gl.createShader(type);
      gl.shaderSource(sh, src);
      gl.compileShader(sh);
      if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) throw new Error(`true-light shader: ${gl.getShaderInfoLog(sh)}`);
      return sh;
    };
    program = gl.createProgram();
    gl.attachShader(program, compile(gl.VERTEX_SHADER, VERT));
    gl.attachShader(program, compile(gl.FRAGMENT_SHADER, FRAG));
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error(`true-light link: ${gl.getProgramInfoLog(program)}`);
    gl.useProgram(program);
    const count = gl.getProgramParameter(program, gl.ACTIVE_UNIFORMS);
    for (let i = 0; i < count; i += 1) {
      const info = gl.getActiveUniform(program, i);
      const name = info.name.replace(/\[0\]$/, '');
      U[name] = gl.getUniformLocation(program, info.name);
    }
    const buf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buf);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
    const loc = gl.getAttribLocation(program, 'aPos');
    gl.enableVertexAttribArray(loc);
    gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
    starTex = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, starTex);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true);
  }

  let destroyed = false;
  let lastKey = '';
  let starKey = '';
  let starCache = { key: '', list: [] };
  const timing = { first: null, last: 0, frames: 0 };

  const set3 = (name, v) => gl.uniform3f(U[name], v[0], v[1], v[2]);
  const set4 = (name, a, b, c, d) => gl.uniform4f(U[name], a, b, c, d);

  // ── his stars ──

  function starList(state, lit) {
    const key = `${state.ageDays}|${lit}`;
    if (starCache.key !== key) starCache = { key, list: nights(state.ageDays, { tonightLit: lit }) };
    return starCache.list;
  }

  /** Draws the stars (light to ADD, on black) for this instant. → true if anything shows. */
  function paintStars(state, G, P, t, s, dark, tonightLit) {
    const w = starCanvas.width, h = starCanvas.height;
    starCtx.setTransform(1, 0, 0, 1, 0, 0);
    starCtx.globalCompositeOperation = 'source-over';
    starCtx.globalAlpha = 1;
    starCtx.fillStyle = '#000';
    starCtx.fillRect(0, 0, w, h);
    // How dark it is, for stars: the sun's depth, and a little more once he is down.
    const sunDeg = state.sun.altitude * DEG;
    const dusk = 1 - smoothstep(-2, 9, sunDeg);
    const darkness = Math.min(1, P.stars + 0.24 * P.depth * (0.35 + 0.65 * dusk) + 0.10 * P.event * dusk);
    if (!(darkness > 0.004) && !tonightLit) return false;
    starCtx.setTransform(s, 0, 0, s, 0, 0);
    starCtx.globalCompositeOperation = 'lighter';
    const bedtime = state.event && state.event.kind === 'bedtime' ? state.event.age : null;
    const spot = tonightSpot(G);
    const swell = 1 + 0.25 * P.event;
    const tilt = state.tilt ?? { x: 0, y: 0 };
    for (const star of starList(state, tonightLit)) {
      const tonight = star.kind === 'tonight';
      const at = tonight ? spot : starPlace(star, G);
      const x = at.x - tilt.x * 1.0, y = at.y - tilt.y * 0.6;
      if (tonight) continue;                     // lit over everything: see paintOver
      const threshold = (1 - star.magnitude) * 0.86;
      let a = smoothstep(threshold - 0.06, threshold + 0.16, darkness);
      if (!(a > 0)) continue;
      a *= (0.30 + 0.70 * star.magnitude) * (t == null ? 0.9 : twinkle(star, t)) * swell;
      // The others answer: a ripple out from tonight's star as it is lit.
      if (bedtime != null) {
        const d = Math.hypot(x - spot.x, y - spot.y);
        const wave = Math.exp(-Math.pow((bedtime - 1.5 - d / 210) / 0.42, 2));
        a *= 1 + 1.1 * wave;
      }
      if (!(a > 0.004)) continue;
      const c = starColour(star);
      const big = star.kind !== 'night';
      const r = (tonight ? 1.6 : 0.5 + 1.05 * star.magnitude) * (dark ? 1 : 1.12);
      const halo = tonight ? 15 : big ? 8.5 : star.magnitude > 0.5 ? r * 3.4 : 0;
      if (halo > 0) {
        const g = starCtx.createRadialGradient(x, y, 0, x, y, halo * (tonight ? 0.75 + 0.25 * Math.min(a, 1.4) : 1));
        const k = (tonight ? 0.34 : big ? 0.20 : 0.12) * Math.min(a, 1.35);
        g.addColorStop(0, rgba(c, k));
        g.addColorStop(0.25, rgba(c, k * 0.32));
        g.addColorStop(1, rgba(c, 0));
        starCtx.fillStyle = g;
        starCtx.beginPath();
        starCtx.arc(x, y, halo * 1.4, 0, TAU);
        starCtx.fill();
      }
      if (big) {
        // A four-point glint, fine and short: the month stars, the first night, tonight.
        const len = (tonight ? 9.5 : star.kind === 'first' ? 7.5 : 5.5) * (0.55 + 0.45 * Math.min(a, 1.35));
        starCtx.fillStyle = rgba(c, Math.min(1, 0.85 * a));
        for (let q = 0; q < 2; q += 1) {
          const dx = q === 0 ? len : 0.55, dy = q === 0 ? 0.55 : len;
          starCtx.beginPath();
          starCtx.moveTo(x - dx, y);
          starCtx.quadraticCurveTo(x, y, x, y - dy);
          starCtx.quadraticCurveTo(x, y, x + dx, y);
          starCtx.quadraticCurveTo(x, y, x, y + dy);
          starCtx.quadraticCurveTo(x, y, x - dx, y);
          starCtx.fill();
        }
      }
      starCtx.fillStyle = rgba(c, Math.min(1, a));
      starCtx.beginPath();
      starCtx.arc(x, y, r, 0, TAU);
      starCtx.fill();
      if (a > 1) {   // past full: the spark
        starCtx.fillStyle = rgba([255, 255, 255], Math.min(1, a - 1));
        starCtx.beginPath();
        starCtx.arc(x, y, r * 0.8, 0, TAU);
        starCtx.fill();
      }
    }
    // The leading page carries the ordinary sky: fainter, uncounted, no glints.
    if (G.phone.x > 0 && darkness > 0.05) {
      const count = Math.round(G.phone.x * G.horizon / 1250);
      for (let i = 0; i < count; i += 1) {
        const mag = Math.pow(hash(i, 63), 2.2);
        const threshold = (1 - (0.25 + 0.5 * mag)) * 0.86;
        let a = smoothstep(threshold - 0.06, threshold + 0.16, darkness);
        if (!(a > 0)) continue;
        const x = hash(i, 61) * (G.phone.x - 6) - tilt.x, y = 5 + Math.pow(hash(i, 62), 1.25) * (G.horizon - 24) - tilt.y * 0.6;
        const period = 2.6 + 3 * hash(i, 64);
        const tw = t == null || hash(i, 65) > 0.6 ? 0.9 : 0.7 + 0.3 * Math.cos(TAU * (t / period + hash(i, 66)));
        a *= (0.20 + 0.42 * mag) * tw * swell;
        const c = oklchCss(0.95, 0.02 + 0.07 * hash(i, 67), hash(i, 68) < 0.6 ? 250 : 75);
        starCtx.fillStyle = rgba(c, Math.min(1, a));
        starCtx.beginPath();
        starCtx.arc(x, y, (0.42 + 0.5 * mag) * (dark ? 1 : 1.12), 0, TAU);
        starCtx.fill();
      }
    }
    // A rare shooting star: one window in three, for a second, high in the anchor sky.
    if (t != null && darkness > 0.6) {
      const windowLen = 53;
      const index = Math.floor(t / windowLen);
      const age = t - index * windowLen - 20;
      if (hash(index, 31) < 0.34 && age > 0 && age < 1.1) {
        const x0 = G.phone.x + (0.15 + 0.55 * hash(index, 32)) * G.phone.width;
        const y0 = 14 + 60 * hash(index, 33);
        const k = age / 1.1;
        const hx = x0 + 120 * k, hy = y0 + 46 * k;
        const g = starCtx.createLinearGradient(hx - 46, hy - 17.6, hx, hy);
        const fade = Math.sin(Math.PI * k) * darkness;
        g.addColorStop(0, 'rgba(255,255,255,0)');
        g.addColorStop(1, `rgba(255,250,240,${0.8 * fade})`);
        starCtx.strokeStyle = g;
        starCtx.lineWidth = 1.1;
        starCtx.lineCap = 'round';
        starCtx.beginPath();
        starCtx.moveTo(hx - 46, hy - 17.6);
        starCtx.lineTo(hx, hy);
        starCtx.stroke();
      }
    }
    return true;
  }

  // ── what lies over the land: fireflies, snowflakes, the caption ──

  function paintOver(state, G, P, t, s, dark, sn, snowfall, tonightLit) {
    const w = overCanvas.width, h = overCanvas.height;
    over.setTransform(1, 0, 0, 1, 0, 0);
    over.clearRect(0, 0, w, h);
    over.setTransform(s, 0, 0, s, 0, 0);
    const sunDeg = state.sun.altitude * DEG;
    const time = t ?? 0;

    // Fireflies over the near valley, from dusk into the night.
    const dusk = smoothstep(4, -3, sunDeg) * (1 - 0.55 * smoothstep(-14, -30, sunDeg));
    const flies = sn.fireflies * dusk;
    if (flies > 0.02) {
      const worldLeft = -G.phone.x / G.phone.width;
      const count = Math.round(34 * (1 - worldLeft));
      over.globalCompositeOperation = dark ? 'lighter' : 'source-over';
      for (let i = 0; i < count; i += 1) {
        const X = worldLeft + (1 - worldLeft) * hash(i, 41);
        const depth = hash(i, 42);
        const x0 = G.phone.x + X * G.phone.width;
        const y0 = G.horizon + (96 + 250 * Math.pow(depth, 1.2)) * G.landScale;
        const wander = 5 + 9 * depth;
        const ph = hash(i, 43) * TAU;
        const x = x0 + wander * Math.sin(time * (0.11 + 0.1 * hash(i, 44)) + ph);
        const y = y0 + wander * 0.6 * Math.sin(time * (0.09 + 0.08 * hash(i, 45)) + ph * 1.7);
        const period = 3.2 + 3.6 * hash(i, 46);
        const blink = t == null ? 0.55 : Math.pow(0.5 + 0.5 * Math.sin((time / period) * TAU + ph * 2.3), 3);
        const a = flies * blink * (0.5 + 0.5 * depth);
        if (!(a > 0.03)) continue;
        const r = 0.7 + 0.8 * depth;
        const c = dark ? [226, 240, 150] : [250, 255, 205];
        const g = over.createRadialGradient(x, y, 0, x, y, r * 6);
        g.addColorStop(0, rgba(c, 0.55 * a));
        g.addColorStop(0.3, rgba(c, 0.16 * a));
        g.addColorStop(1, rgba(c, 0));
        over.fillStyle = g;
        over.beginPath();
        over.arc(x, y, r * 6, 0, TAU);
        over.fill();
        over.fillStyle = rgba(dark ? [244, 250, 190] : [255, 255, 236], Math.min(1, 1.1 * a));
        over.beginPath();
        over.arc(x, y, r, 0, TAU);
        over.fill();
      }
    }

    // Snow in the air: a few slow flakes, three depths.
    if (snowfall > 0) {
      over.globalCompositeOperation = 'source-over';
      const count = Math.round(state.width * state.height / 7600 * snowfall);
      for (let i = 0; i < count; i += 1) {
        const depth = hash(i, 51);                       // 0 far … 1 near
        const speed = 7 + 16 * depth;
        const span = state.height + 40;
        const x0 = hash(i, 52) * (state.width + 60) - 30;
        const y = ((hash(i, 53) * span + time * speed) % span) - 20;
        const x = x0 + (5 + 9 * depth) * Math.sin(time * (0.22 + 0.2 * hash(i, 54)) + hash(i, 55) * TAU) + time * 1.6 * depth;
        const r = 0.7 + 1.5 * depth * depth;
        const a = (dark ? 0.16 + 0.34 * depth : 0.45 + 0.4 * depth) * (0.55 + 0.45 * smoothstep(-12, 6, sunDeg));
        const xx = ((x % (state.width + 60)) + state.width + 60) % (state.width + 60) - 30;
        const g = over.createRadialGradient(xx, y, 0, xx, y, r * 1.8);
        const c = dark ? [214, 222, 240] : [255, 255, 255];
        g.addColorStop(0, rgba(c, a));
        g.addColorStop(0.55, rgba(c, a * 0.6));
        g.addColorStop(1, rgba(c, 0));
        over.fillStyle = g;
        over.beginPath();
        over.arc(xx, y, r * 1.8, 0, TAU);
        over.fill();
      }
    }

    // Tonight's star: warm, lit when he goes down, findable all night — so it is
    // drawn over cloud and all. It breathes on the app's sleeping rhythm.
    if (tonightLit) {
      const bedtime = state.event && state.event.kind === 'bedtime' ? state.event.age : null;
      const spot = tonightSpot(G);
      const tilt = state.tilt ?? { x: 0, y: 0 };
      const x = spot.x - tilt.x, y = spot.y - tilt.y * 0.6;
      const a = ignition(bedtime) * (t == null ? 0.92 : 0.8 + 0.2 * Math.cos((TAU * t) / 5.2));
      if (a > 0.004) {
        const cream = dark ? [255, 236, 208] : [255, 250, 240];
        const k = Math.min(a, 1.35);
        over.globalCompositeOperation = dark ? 'lighter' : 'source-over';
        const halo = over.createRadialGradient(x, y, 0, x, y, 19 * (0.7 + 0.3 * k));
        halo.addColorStop(0, rgba(cream, (dark ? 0.42 : 0.9) * k));
        halo.addColorStop(0.16, rgba(cream, (dark ? 0.17 : 0.5) * k));
        halo.addColorStop(0.5, rgba(cream, (dark ? 0.045 : 0.14) * k));
        halo.addColorStop(1, rgba(cream, 0));
        over.fillStyle = halo;
        over.beginPath();
        over.arc(x, y, 27, 0, TAU);
        over.fill();
        // A fine four-point glint.
        over.fillStyle = rgba(dark ? [255, 244, 226] : [255, 255, 255], Math.min(1, 0.9 * k));
        const len = 10.5 * (0.5 + 0.5 * k);
        for (let q = 0; q < 2; q += 1) {
          const dx = q === 0 ? len : 0.7, dy = q === 0 ? 0.7 : len * 1.15;
          over.beginPath();
          over.moveTo(x - dx, y);
          over.quadraticCurveTo(x, y, x, y - dy);
          over.quadraticCurveTo(x, y, x + dx, y);
          over.quadraticCurveTo(x, y, x, y + dy);
          over.quadraticCurveTo(x, y, x - dx, y);
          over.fill();
        }
        over.fillStyle = rgba(dark ? [255, 248, 236] : [255, 255, 255], Math.min(1, k));
        over.beginPath();
        over.arc(x, y, 1.9 + 0.5 * Math.max(0, k - 1), 0, TAU);
        over.fill();
        if (!dark) {
          // On a light page a white star needs a breath of its own dusk behind it.
          over.globalCompositeOperation = 'destination-over';
          const shade = over.createRadialGradient(x, y, 0, x, y, 22);
          shade.addColorStop(0, `rgba(96,92,140,${0.16 * Math.min(k, 1)})`);
          shade.addColorStop(1, 'rgba(96,92,140,0)');
          over.fillStyle = shade;
          over.beginPath();
          over.arc(x, y, 22, 0, TAU);
          over.fill();
          over.globalCompositeOperation = 'source-over';
        }
      }
    }

    // "Night 143", for the seconds the sky has the display at bedtime.
    if (state.event && state.event.kind === 'bedtime' && tonightLit) {
      const age = state.event.age;
      const veil = state.veil == null ? 1 : state.veil;
      const a = smoothstep(1.7, 2.7, age) * (1 - smoothstep(4.7, 5.6, age)) * smoothstep(0.6, 1, veil);
      if (a > 0.01) {
        const spot = tonightSpot(G);
        const label = `NIGHT ${Math.floor(state.ageDays) + 1}`;
        over.globalCompositeOperation = 'source-over';
        over.font = '700 10.5px "Nunito", ui-rounded, system-ui, sans-serif';
        try { over.letterSpacing = '1.6px'; } catch { /* older canvases */ }
        over.textBaseline = 'middle';
        over.fillStyle = dark ? `rgba(255,244,232,${0.82 * a})` : `rgba(60,60,67,${0.72 * a})`;
        if (G.slab) {
          over.textAlign = 'center';
          over.fillText(label, spot.x + 0.8, spot.y + 19);
        } else {
          over.textAlign = 'right';
          over.fillText(label, spot.x - 17, spot.y + 0.5);
        }
      }
    }
  }

  // ── a frame ──

  function render(state) {
    if (destroyed || !state || !state.sun) return;
    const s = Number.isFinite(state.dpr) && state.dpr > 0 ? state.dpr : 1;
    const pxW = Math.ceil(state.width * s - 1e-6), pxH = Math.ceil(state.height * s - 1e-6);
    const G = geometry(state);
    const dark = state.scheme === 'dark';
    const P = presence(state);
    const still = state.reduceMotion || !Number.isFinite(state.t);
    // Slow motion needs no more than twelve frames a second.
    const t = still ? null : Math.round(state.t * 12) / 12;
    const tilt = state.tilt ?? { x: 0, y: 0 };

    const key = [state.device, pxW, pxH, s, G.phone.x, G.phone.width, state.scheme, +state.date, state.tzOffsetHours,
      state.latitude, state.longitude, state.asleep, state.ageDays, t, tilt.x, tilt.y,
      state.event ? `${state.event.kind}:${state.event.age}` : '', state.veil ?? '', forcedSnow()].join('|');
    if (key === lastKey) return;
    const started = performance.now();

    for (const c of [glCanvas, overCanvas]) {
      if (c.width !== pxW || c.height !== pxH) { c.width = pxW; c.height = pxH; }
      const cw = `${pxW / s}px`, ch = `${pxH / s}px`;
      if (c.style.width !== cw) c.style.width = cw;
      if (c.style.height !== ch) c.style.height = ch;
    }
    if (starCanvas.width !== pxW || starCanvas.height !== pxH) { starCanvas.width = pxW; starCanvas.height = pxH; starKey = ''; }

    const sunDeg = state.sun.altitude * DEG;
    const morning = state.sun.isNight ? state.sun.progress > 0.5 : state.sun.progress < 0.5;
    const pal = palette(sunDeg, dark, morning);
    const sn = seasonOf(state.dayOfYear, state.latitude);
    const snowfall = Math.max(sn.snowfall, forcedSnow());
    const tonightLit = state.asleep === 'night';

    // The sun, by the clock across the anchor window and by its real altitude above the horizon.
    let sunU;
    if (!state.sun.isNight) sunU = 0.04 + 0.92 * state.sun.progress;
    else if (!morning) sunU = 0.96 + 0.08 * Math.min(1, state.sun.progress / 0.2);
    else sunU = 0.04 - 0.08 * Math.min(1, (1 - state.sun.progress) / 0.2);
    const sunX = G.phone.x + sunU * G.phone.width;
    const sunY = G.horizon * (1 - bodyE(state.sun.altitude, G.ceiling));
    const sunVis = smoothstep(-2.2, -0.2, sunDeg);

    // The moon, the same way.
    const moon = state.moon;
    const moonUp = moon ? smoothstep(-1.5, 2.5, moon.altitude * DEG) : 0;
    const moonX = moon ? G.phone.x + moon.x * G.phone.width : 0;
    const moonY = moon ? G.horizon * (1 - bodyE(moon.altitude, G.ceiling)) : 0;
    const nightness = 1 - smoothstep(-13, -8, sunDeg);
    const moonlight = moon ? moonUp * (0.2 + 0.8 * moon.fraction) * nightness : 0;
    const moonVis = moon ? (0.42 + 0.58 * (1 - smoothstep(-8, 3, sunDeg))) * smoothstep(-1.5, 0.5, moon.altitude * DEG)
      * lerp(smoothstep(0.04, 0.2, moon.fraction), 1, nightness) : 0;

    // ── stars: redrawn only when they change ──
    const sKey = [pxW, pxH, state.ageDays, tonightLit, t, P.stars.toFixed(4), P.depth.toFixed(4), P.event.toFixed(4),
      state.event ? state.event.age : '', dark, tilt.x, tilt.y, G.phone.x].join('|');
    let starsOn = true;
    if (gl && sKey !== starKey) {
      starsOn = paintStars(state, G, P, t, s, dark, tonightLit);
      gl.activeTexture(gl.TEXTURE0);
      gl.bindTexture(gl.TEXTURE_2D, starTex);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, starCanvas);
      starKey = sKey;
    }

    if (gl) {
      gl.viewport(0, 0, pxW, pxH);
      gl.useProgram(program);
      gl.uniform2f(U.uPx, pxW, pxH);
      gl.uniform1f(U.uDpr, s);
      set4('uGeo', G.phone.x, G.phone.width, G.horizon, G.landScale);
      gl.uniform2f(U.uBand, G.band, dark ? 0.385 : 0.848);
      gl.uniform3fv(U.uSolar, pal.solar);
      gl.uniform3fv(U.uAnti, pal.anti);
      set4('uSun', sunX, sunY, 10.5, sunVis);
      set3('uSunCol', sunDisc(sunDeg, dark));
      // By day the dark appearance keeps the sun's aureole close: nothing but the disc outshines a card.
      set4('uGlow', pal.glow[0], pal.glow[1], pal.glow[2], pal.glowAmt * (dark ? 0.4 + 0.6 * smoothstep(11, 3, sunDeg) : 1));
      set4('uArch', 0.60, 0.44, 0.10, 1.35);
      set4('uMoon', moonX, moonY, 8.5, moonVis);
      const moonLow = moon ? 1 - smoothstep(2, 14, moon.altitude * DEG) : 0;
      const moonCol = dark ? lch(0.92 - 0.06 * moonLow, 0.028 + 0.028 * moonLow, 85 - 8 * moonLow) : lch(0.992 - 0.02 * moonLow, 0.014 + 0.03 * moonLow, 85 - 15 * moonLow);
      set4('uMoonB', moon ? moon.fraction : 0, moon ? moon.rotation : 0, 0.42 * moonlight * (dark ? 0.30 : 0.8), dark ? 0.07 : 0.2);
      set3('uMoonCol', moonCol);

      // Clouds: lit by the sun until it is well down, then by the moon.
      const byMoon = sunDeg < -9.5;
      const loAmt = byMoon ? 0.95 * moonlight : pal.loAmt;
      const hiAmt = byMoon ? 0.8 * moonlight : pal.hiAmt;
      set4('uLight', byMoon ? moonX : sunX, byMoon ? moonY : sunY, loAmt, hiAmt);
      const silver = print(KEYS[KEYS.length - 1], dark, [dark ? 1.55 : 1.9, 0.045, 255]);
      set3('uLoLit', byMoon ? silver : pal.loLit);
      set3('uLoShade', pal.loShade);
      // Away from the sun the bank's lit side goes to the Belt's pink, and quieter.
      set3('uLoFar', byMoon ? silver : mix3(pal.loLit, mix3(pal.loShade, lch(pal.loLit[0] - 0.03, 0.05, 350), 0.6), 0.75));
      set3('uHiLit', byMoon ? silver : pal.hiLit);
      set3('uHiShade', pal.hiShade);
      const golden = smoothstep(9, 1, sunDeg);
      const farPink = lch(pal.hiLit[0] - 0.035, 0.07 * (dark ? 0.9 : 0.62), 352);
      set3('uHiFar', byMoon ? silver : mix3(pal.hiLit, farPink, 0.7 * golden));
      const drift = t ?? 0;
      set4('uCloud', 0.92, 0.80, 0.0004 * drift, 0.00018 * drift);

      // The land.
      const sl = seasonLand(sn);
      const day = smoothstep(-2, 16, sunDeg);
      const litLand = (alb, keep = 0.2) => {
        // An albedo in this hour's light, in this print.
        const L = pal.land[0] + (alb[0] - 0.47) * pal.gain;
        const base = lch(L, alb[1] * (dark ? 0.6 : 0.62) * (keep + (1 - keep) * day), alb[2]);
        return [base[0], base[1] + pal.land[1] * 0.8, base[2] + pal.land[2] * 0.8];
      };
      set3('uLand', litLand(sl.ground, 0.2 + 0.25 * sn.grass));
      set3('uWoods', litLand(sl.woods, 0.4));
      // The canopy's top in the last light: the season's colour at full strength, lifted.
      const lastLight = smoothstep(-7, -1, sunDeg);
      const lift = dark ? 0.03 + 0.15 * lastLight * (1 - 0.5 * day) : -0.02;
      const wl = lch(pal.land[0] + (sl.woods[0] - 0.47) * pal.gain + lift, sl.woods[1] * (dark ? 0.8 : 0.80), sl.woods[2]);
      set4('uWoodsLit', wl[0], wl[1], wl[2], 0.25 + 0.75 * lastLight);
      set3('uBloom', litLand(sl.blossom, 0.6));
      const snowLit = litLand(sl.snow);
      set3('uSnowLit', mix3(snowLit, pal.rim, 0.25 * pal.rimAmt));
      set3('uSnowShade', [snowLit[0] - (dark ? 0.035 : 0.05), snowLit[1] + 0.012 * Math.cos(262 / DEG), snowLit[2] + 0.02 * Math.sin(262 / DEG)]);
      set4('uSeason', sn.snow, sn.frost, 0.6 + 0.4 * sn.foliage, sn.blossom);
      for (let i = 0; i < N_RIDGE; i += 1) {
        const r = RIDGES[i];
        gl.uniform4f(gl.getUniformLocation(program, `uRidgeA[${i}]`), r.base, r.amp, r.freq, r.seed);
        gl.uniform4f(gl.getUniformLocation(program, `uRidgeB[${i}]`), r.haze, r.soft, r.trees, r.mist);
        gl.uniform4f(gl.getUniformLocation(program, `uRidgeC[${i}]`), (tilt.x * r.depth) / G.phone.width, -tilt.y * r.depth * 0.4, 0, 0);
      }
      const mistCol = byMoon ? mix3(pal.mist, silver, 0.5 * moonlight) : pal.mist;
      const mistAmt = (0.55 + 0.25 * (morning ? 1 : 0) + 0.15 * sn.frost + 0.2 * nightness) * (1 - 0.35 * smoothstep(8, 30, sunDeg));
      set4('uMist', mistCol[0], mistCol[1], mistCol[2], mistAmt);
      set3('uMistFar', byMoon ? mix3(pal.mistFar, silver, 0.5 * moonlight) : pal.mistFar);
      const shadowAmt = smoothstep(1.5, -2.5, sunDeg) * (1 - smoothstep(-6, -9.5, sunDeg));
      set4('uShadow', pal.shadow[0], pal.shadow[1], pal.shadow[2], 0.85 * shadowAmt);
      gl.uniform1f(U.uShadowH, lerp(0.06, 0.2, smoothstep(0, -5, sunDeg)));
      set4('uRim', pal.rim[0], pal.rim[1], pal.rim[2], pal.rimAmt);
      set3('uAmbient', [pal.solar[(N_RAMP - 10) * 3], pal.solar[(N_RAMP - 10) * 3 + 1], pal.solar[(N_RAMP - 10) * 3 + 2]]);
      set4('uHush', P.presence, dark ? 1 : 0, P.depth, PAGE_L);
      set4('uTime', 0.004 * drift, tilt.x, tilt.y, 0);
      gl.uniform1i(U.uStars, 0);
      gl.uniform1f(U.uStarGain, starsOn ? 1 : 0);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
    } else {
      fallback(state, pal, s, pxW, pxH);
    }

    paintOver(state, G, P, t, s, dark, sn, snowfall, tonightLit);

    lastKey = key;
    if (gl && timing.frames < 3) gl.finish();
    const took = performance.now() - started;
    if (timing.first == null) timing.first = took;
    timing.last = took;
    timing.frames += 1;
    if (typeof window !== 'undefined') window.__trueLight = timing;
  }

  /** Without WebGL2: the two ramps as a plain gradient, so the lab never goes blank. */
  function fallback(state, pal, s, pxW, pxH) {
    over.setTransform(1, 0, 0, 1, 0, 0);
    const g = over.createLinearGradient(0, 0, 0, pxH * 0.46);
    for (let n = 0; n < N_RAMP; n += 4) {
      const e = Math.pow(n / (N_RAMP - 1), 2);
      const L = pal.solar[n * 3], a = pal.solar[n * 3 + 1], b = pal.solar[n * 3 + 2];
      const c = oklchCss(L, Math.hypot(a, b), Math.atan2(b, a) * DEG);
      g.addColorStop(1 - e, rgba(c, 1));
    }
    glCanvas.style.background = '#000';
    over.fillStyle = g;
    over.fillRect(0, 0, pxW, pxH);
  }

  function destroy() {
    destroyed = true;
    if (gl) {
      const lose = gl.getExtension('WEBGL_lose_context');
      if (lose) lose.loseContext();
    }
    glCanvas.remove();
    overCanvas.remove();
  }

  return { render, destroy };
}

/** The lab's season.js promises `snowfall=1` to force snow in the air, but the
 *  viewer does not pass it on; read here so the snowfall can be shot. */
function forcedSnow() {
  try {
    const v = new URLSearchParams(globalThis.location?.search ?? '').get('snowfall');
    return v == null ? 0 : clamp01(Number(v) || 0);
  } catch { return 0; }
}
