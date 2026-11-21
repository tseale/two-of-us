// Hill, lit — picture book's place, standing in true light's air.
//
// One place: a knoll with one grown tree on it, the hills falling away behind,
// and on the far side (the Duo's leading page) a river valley. One light: the
// sun, then the moon, and everything answers it — the twilight leans toward the
// sun's x, the few clouds are lit on its side and shadowed beneath, each plane of
// land takes its colour from the sky at the horizon and sinks into the valley's
// air, mist lies level between the planes, the river carries what light is left.
// One camera: at rest the horizon crosses the middle of the Duo's strip; at
// bedtime it looks up — the land sinks to the foot of the display, the tree with
// it, and the sky that was above the top edge comes down with every night of his
// life on it.
//
// How it is put together (and how it ports — see hill-lit.md):
//
//   JS, per frame, cheap        the palette: true light's table of twilight keyframes by
//                               the sun's altitude, PRINTED twice (high-key for the light
//                               appearance, low-key for the dark); the camera; ~60 uniforms.
//   one fragment shader         sky ramps → sun, moon → designed clouds → eight planes of
//   (WebGL2)                    land drawn from tables (hill-lit/place.js), the valley floor
//                               with its river, mist → the hush → sRGB, dithered. Every
//                               plane is the same picture slid by the camera, so the app
//                               can cache each as a layer and translate it.
//   a 2-D canvas over it        his stars (lab/nights.js) on the tall sky, the ring, the
//                               tree (hill-lit/tree.js), tonight's star, the caption, the
//                               small life of the season.
//
// World: points, x = 0 at the anchor window's leading edge, y the display's y at
// rest (hill-lit/place.js). The camera is two numbers, (dx, dy) = (−turn, rise) · look.

import { presence } from '../lab/presence.js';
import { nights, twinkle, ignition, hash } from '../lab/nights.js';
import { season as seasonOf } from '../lab/season.js';
import { GLSL_NOISE } from '../lab/noise.js';
import { smoothstep, lerp } from '../lab/oklab.js';
import { DUO, SLAB, N_HILL, N_BUMP, N_RIVER, N_CLOUD, N_BLOB, crestAt, skyline, riverTable, riverAt, cloudNow, cloudCover } from './hill-lit/place.js';
import { paintTree, crownSpan } from './hill-lit/tree.js';

export const meta = {
  id: 'hill-lit',
  name: 'Hill, lit',
  blurb: 'The knoll and its one tree against the real sun, in true air: mist between the hills, a river valley on the far page, and a camera that looks up at bedtime.',
};

const DEG = 180 / Math.PI;
const TAU = Math.PI * 2;
const clamp01 = (x) => Math.min(1, Math.max(0, x));
const clamp = (x, lo, hi) => Math.min(hi, Math.max(lo, x));
const lch = (L, C, hDeg) => [L, C * Math.cos(hDeg / DEG), C * Math.sin(hDeg / DEG)];
const mix3 = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
const PAGE_L = 0.9612;   // #F2F2F7 in OKLab

// ───────────────────────────────────────────────────────────── the negative ──
// Twilight by the sun's altitude (degrees) — true light's table. Each colour is
// [value, chroma, hue°]: value 0–1 inside that hour's own range, so the same table
// prints high-key (light appearance) and low-key (dark). S is the column of sky at
// the sun's x, A the column opposite the sun; stops are at E_STOPS (0 the horizon,
// 1 the top of the display at rest).
const E_STOPS = [0, 0.04, 0.10, 0.18, 0.29, 0.44, 0.68, 1];
const N_RAMP = 32;

const KEYS = [
  { alt: 30,
    light: [0.872, 0.968, 1, 0.80], dark: [0.205, 0.335, 1, 0.66],
    S: [[1, .016, 235], [.97, .028, 238], [.90, .048, 242], [.78, .072, 246], [.60, .098, 250], [.40, .114, 254], [.18, .124, 257], [0, .13, 260]],
    A: [[.93, .024, 240], [.90, .034, 242], [.84, .054, 245], [.72, .078, 248], [.55, .10, 252], [.36, .114, 255], [.16, .124, 258], [0, .13, 260]],
    sun: [1.5, .03, 95], glow: [1.12, .03, 92, 0.42],
    lo: { lit: [1.2, .012, 90], shade: [.42, .035, 255], amt: 1 },
    mist: [1.05, .012, 240],
    land: { light: [0.80, .03, 250], dark: [0.165, .028, 258] }, gain: [0.26, 0.30], rim: [1.1, .03, 90, 0.10] },
  { alt: 8,
    light: [0.862, 0.968, 1, 0.75], dark: [0.165, 0.40, 1.3, 0.84],
    S: [[1, .10, 74], [.98, .10, 76], [.93, .09, 72], [.82, .075, 52], [.64, .06, 338], [.43, .085, 272], [.24, .112, 260], [.10, .12, 262]],
    A: [[.70, .03, 290], [.72, .035, 310], [.70, .04, 285], [.62, .06, 258], [.50, .085, 255], [.36, .102, 257], [.21, .112, 259], [.09, .12, 262]],
    sun: [1.45, .06, 92], glow: [1.5, .12, 70, 0.9],
    lo: { lit: [1.14, .06, 82], shade: [.36, .04, 272], amt: 1 },
    mist: [1.0, .04, 80],
    land: { light: [0.80, .03, 275], dark: [0.115, .024, 275] }, gain: [0.26, 0.30], rim: [1.1, .06, 80, 0.2] },
  { alt: 2.5,
    light: [0.852, 0.965, 1, 0.64], dark: [0.135, 0.52, 1.3, 0.95],
    S: [[.96, .13, 62], [1, .12, 72], [.97, .08, 86], [.90, .04, 100], [.78, .07, 15], [.58, .085, 318], [.36, .105, 280], [.17, .115, 268]],
    A: [[.72, .04, 320], [.75, .055, 342], [.76, .065, 352], [.70, .06, 325], [.58, .075, 290], [.42, .092, 270], [.27, .105, 266], [.14, .115, 266]],
    sun: [1.9, .085, 84], glow: [1.12, .13, 68, 0.72],
    lo: { lit: [1.12, .13, 62], shade: [.36, .05, 292], amt: 1 },
    mist: [1.0, .07, 62],
    land: { light: [0.818, .026, 318], dark: [0.066, .018, 300] }, gain: [0.22, 0.40], rim: [1.08, .11, 66, 0.5] },
  { alt: -0.8,
    light: [0.846, 0.962, 1, 0.68], dark: [0.128, 0.575, 1.4, 1.0],
    S: [[.84, .18, 42], [.95, .16, 58], [1, .11, 80], [.93, .04, 100], [.80, .09, 12], [.60, .10, 318], [.38, .105, 284], [.17, .11, 270]],
    A: [[.60, .05, 320], [.64, .07, 345], [.68, .085, 352], [.64, .08, 336], [.52, .08, 302], [.38, .09, 280], [.25, .10, 272], [.14, .11, 270]],
    sun: [1.5, .16, 52], glow: [1.04, .17, 52, 0.58],
    lo: { lit: [1.08, .18, 44], shade: [.27, .05, 286], amt: 1 },
    mist: [.92, .10, 40],
    land: { light: [0.815, .028, 310], dark: [0.060, .02, 300] }, gain: [0.20, 0.40], rim: [1.0, .15, 44, 0.7] },
  { alt: -4,
    light: [0.842, 0.955, 1, 0.68], dark: [0.112, 0.53, 1.45, 1.0],
    S: [[.62, .175, 36], [.84, .165, 52], [1, .12, 78], [.92, .04, 102], [.76, .10, 8], [.54, .10, 318], [.32, .105, 286], [.13, .105, 272]],
    A: [[.40, .055, 300], [.44, .065, 325], [.48, .075, 345], [.48, .08, 335], [.40, .08, 306], [.29, .09, 282], [.18, .10, 274], [.10, .105, 272]],
    sun: [1.0, .19, 40], glow: [.95, .17, 44, 0.5],
    lo: { lit: [.82, .17, 24], shade: [.17, .05, 276], amt: 0.42 },
    mist: [.62, .08, 350],
    land: { light: [0.815, .03, 296], dark: [0.052, .02, 290] }, gain: [0.18, 0.34], rim: [.8, .14, 30, 0.2] },
  { alt: -7.5,
    light: [0.856, 0.935, 1, 0.6], dark: [0.092, 0.42, 1.55, 0.95],
    S: [[.60, .16, 38], [.80, .14, 58], [.85, .08, 90], [.68, .04, 150], [.48, .06, 250], [.32, .08, 265], [.16, .085, 268], [.03, .085, 268]],
    A: [[.15, .045, 255], [.17, .05, 258], [.20, .055, 262], [.20, .06, 265], [.17, .07, 266], [.12, .075, 268], [.06, .08, 268], [0, .085, 268]],
    sun: [.8, .17, 36], glow: [.82, .16, 42, 0.34],
    lo: { lit: [.5, .1, 20], shade: [.10, .04, 268], amt: 0 },
    mist: [.34, .04, 280],
    land: { light: [0.815, .032, 285], dark: [0.05, .018, 280] }, gain: [0.16, 0.28], rim: [.6, .1, 30, 0] },
  { alt: -11,
    light: [0.866, 0.912, 1, 1.1], dark: [0.125, 0.28, 1.5, 0.9],
    S: [[.75, .12, 42], [.85, .09, 65], [.70, .045, 120], [.50, .05, 235], [.36, .065, 258], [.22, .075, 266], [.10, .08, 268], [0, .08, 270]],
    A: [[.24, .05, 258], [.24, .055, 260], [.21, .06, 264], [.17, .065, 266], [.12, .07, 268], [.07, .075, 269], [.03, .08, 270], [0, .08, 270]],
    sun: [.7, .12, 40], glow: [.8, .1, 45, 0.16],
    lo: { lit: [.4, .05, 20], shade: [.05, .04, 268], amt: 0 },
    mist: [.42, .04, 265],
    land: { light: [0.80, .034, 278], dark: [0.068, .02, 272] }, gain: [0.14, 0.26], rim: [.5, .05, 30, 0] },
  { alt: -18,
    light: [0.872, 0.905, 1, 1.4], dark: [0.148, 0.234, 1.1, 1.0],
    S: [[1, .055, 262], [.92, .06, 264], [.78, .066, 266], [.60, .072, 268], [.40, .078, 270], [.22, .082, 272], [.08, .085, 273], [0, .085, 274]],
    A: [[1, .055, 262], [.92, .06, 264], [.78, .066, 266], [.60, .072, 268], [.40, .078, 270], [.22, .082, 272], [.08, .085, 273], [0, .085, 274]],
    sun: [1, .03, 262], glow: [1, .03, 262, 0],
    lo: { lit: [1, .03, 262], shade: [-.1, .05, 268], amt: 0 },
    mist: [1.2, .055, 258],
    land: { light: [0.782, .04, 276], dark: [0.092, .026, 268] }, gain: [0.12, 0.30], rim: [.5, .02, 260, 0] },
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
  if (dark && h > 88 && h < 130) { h = 72 + (h - 88) * 0.15; C *= 2.4; }
  // …and its golds lean to apricot and ember, never mustard.
  if (dark && h > 48 && h <= 88) h = 48 + (h - 48) * 0.6;
  return lch(L, C * r[3] * quiet, h);
}

/** The sun's disc is not printed with the sky: it is the light, and keeps its
 *  own brightness in both appearances. [altitude°, [L, C, h°] dark, light]. */
const SUN_DISC = [
  [30, [0.90, 0.035, 95], [0.99, 0.03, 95]],
  [8, [0.905, 0.085, 84], [0.975, 0.07, 88]],
  [2.5, [0.90, 0.105, 76], [0.958, 0.105, 80]],
  [-0.8, [0.80, 0.13, 60], [0.93, 0.125, 62]],
  [-3, [0.60, 0.17, 40], [0.89, 0.13, 48]],
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
  const ground = mixLch([0.47, 0.034, 72], green, sn.grass);
  // Leaves: fresh → deep summer → amber → russet.
  const leaf = sn.leafHue <= 0.5
    ? mixLch([0.66, 0.105, 124], [0.40, 0.08, 142], sn.leafHue / 0.5)
    : sn.leafHue <= 0.8
      ? mixLch([0.40, 0.08, 142], [0.62, 0.12, 78], (sn.leafHue - 0.5) / 0.3)
      : mixLch([0.62, 0.12, 78], [0.5, 0.115, 46], (sn.leafHue - 0.8) / 0.2);
  const woods = mixLch([0.33, 0.022, 45], leaf, sn.foliage);
  return { ground, woods, leaf, blossom: [0.88, 0.05, 352], snow: [0.94, 0.012, 255] };
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
uniform vec4 uGeo;         // phoneX, phoneW, horizon (world y), the tall sky's top (E)
uniform vec2 uCam;         // the sky's plane: screen − world (points), the phone's x left out
uniform vec3 uSolar[${N_RAMP}];
uniform vec3 uAnti[${N_RAMP}];
uniform vec2 uZen;         // above the rest view the sky deepens: L, chroma
uniform vec4 uSun;         // world x, y (points), radius, disc visibility
uniform vec3 uSunCol;
uniform vec4 uGlow;        // OKLab, amount
uniform vec4 uArch;        // glow width (anchor widths), far height, anti from, anti to
uniform vec4 uMoon;        // world x, y (points), radius, visibility
uniform vec4 uMoonB;       // lit fraction, rotation, glow, earthshine
uniform vec3 uMoonCol;
uniform vec4 uLight;       // the light on cloud and water: world x, y, amount on cloud, amount on water
uniform vec3 uLightCol;
uniform float uLightV;      // on a cloud the light comes from above (−) or below (+): its real altitude
uniform vec3 uCLit, uCShade, uCFar;
uniform vec4 uBlob[${N_CLOUD * N_BLOB}];   // world x, y, rx, ry
uniform vec4 uCloud[${N_CLOUD}];           // box: centre x, y, half width, half height
uniform vec4 uCloudQ[${N_CLOUD}];          // foot y (world), amount, seed, -
uniform vec4 uHillA[${N_HILL}];   // base, haze, soft, depth
uniform vec4 uHillB[${N_HILL}];   // side x0, x1, fall, floor (0/1)
uniform vec4 uHillC[${N_HILL}];   // screen − world x, y (points), wobble amplitude, phase
uniform vec4 uHillM[${N_HILL}];   // mist level, thickness, amount; downslope fade
uniform vec4 uHillW[${N_HILL}];   // woods x0, x1, height; the foot of a hill that stands on the floor
uniform vec4 uBump[${N_HILL * N_BUMP}];    // x, height, half-width, roundness
uniform vec2 uRiver[${N_RIVER}];  // x, half-width along its course
uniform vec4 uRiverQ;      // Y0, Y1 (below the horizon), on, shimmer time
uniform float uRoom;       // how much lighter than the land the water and its mist may go: 0 on a dark night
uniform vec4 uOpen;        // the Duo opening: the light's front (world x), its softness, how unlit the rest is, -
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
uniform vec2 uHushK;       // how the hush is shaped this hour: toward the page (light) or toward black (dark); the chroma kept
uniform vec4 uTime;        // mist drift, grain, -, -
uniform vec4 uText[3];     // where words sit on the sky (screen points): x0, y0, x1, y1
uniform vec2 uLimit;       // the L the sky is held to behind them, the feather

${GLSL_NOISE}

float sstep(float a, float b, float x) { float t = clamp((x - a) / (b - a), 0.0, 1.0); return t * t * (3.0 - 2.0 * t); }
float hash11(float n) { return fract(sin(n * 127.1 + 311.7) * 43758.5453123); }
float smin(float a, float b, float k) { float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0); return mix(b, a, h) - k * h * (1.0 - h); }
float smax(float a, float b, float k) { return -smin(-a, -b, k); }

vec3 ramp(vec3 stops[${N_RAMP}], float e) {
  float f = sqrt(clamp(e, 0.0, 1.0)) * ${N_RAMP - 1}.0;
  int i = int(min(floor(f), ${N_RAMP - 2}.0));
  return mix(stops[i], stops[i + 1], f - float(i));
}

// The sky at anchor-x X, elevation e (1 = the top of the display at rest; it goes on
// above that): the sun's column, its bands sinking toward the horizon away from the
// sun (an arch), going over to the column opposite.
vec3 skyAt(float X, float e) {
  float e1 = clamp(e, 0.0, 1.0);
  float dx = X - uSun.x / uGeo.y;
  float wS = exp(-dx * dx / (uArch.x * uArch.x));
  float arch = mix(uArch.y, 1.0, wS);
  float eg = 1.0 - pow(1.0 - e1, 1.0 / arch);
  float wA = smoothstep(uArch.z, uArch.w, abs(dx));
  vec3 c = mix(ramp(uSolar, eg), ramp(uAnti, e1), wA);
  float z = sstep(0.85, uGeo.w, e);
  c.x *= 1.0 - uZen.x * z;
  c.yz *= 1.0 - uZen.y * z;
  return c;
}

// A plane's crest (world y) at world x, and which way it falls there (+ to the right).
float crestOf(int i, float wx, out float slope) {
  vec4 B = uHillB[i];
  vec4 C = uHillC[i];
  float c = uGeo.z + uHillA[i].x;
  slope = 0.0;
  for (int j = 0; j < ${N_BUMP}; j++) {
    vec4 b = uBump[i * ${N_BUMP} + j];
    if (b.y == 0.0) continue;
    float d = (wx - b.x) / b.z;
    float ad = abs(d) + 1e-4;
    float e = b.y * exp(-pow(ad, b.w));
    c -= e;
    slope += e * b.w * pow(ad, b.w - 1.0) * sign(d) / b.z;
  }
  if (B.z != 0.0) {
    float t = clamp((wx - B.x) / (B.y - B.x), 0.0, 1.0);
    c += B.z * t * t * (3.0 - 2.0 * t);
    slope += B.z * 6.0 * t * (1.0 - t) / (B.y - B.x);
  }
  c += C.z * (sin(wx * 0.0231 + C.w) * 0.9 + sin(wx * 0.0517 + C.w * 1.7) * 0.55 + sin(wx * 0.113 + C.w * 2.3) * 0.28);
  return c;
}

// A wood standing on a crest between W.x and W.y: crowns of several sizes, thinning at its ends.
float woodsAt(int i, float wx, vec4 W) {
  float patchy = sstep(W.x, W.x + 26.0, wx) * (1.0 - sstep(W.y - 26.0, W.y, wx));
  if (patchy <= 0.0) return 0.0;
  float xs = wx / (W.z * 1.9);
  float h = 0.0;
  float seed0 = float(i) * 37.0;
  for (int o = 0; o < 2; o++) {
    float cell = floor(xs);
    for (int k = -1; k <= 1; k++) {
      float cc = cell + float(k);
      float seed = cc * (1.0 + float(o) * 0.37) + seed0 + float(o) * 19.0;
      float cx = cc + 0.5 + (hash11(seed) - 0.5) * 0.8;
      float r = 0.55 + 0.45 * hash11(seed * 1.7 + 3.0);
      float hh = (0.45 + 0.55 * hash11(seed * 2.3 + 7.0)) * (o == 0 ? 1.0 : 0.62);
      float t = (xs - cx) / r;
      h = max(h, hh * sqrt(max(0.0, 1.0 - t * t)));
    }
    xs = xs * 1.83 + 4.7;
  }
  return W.z * patchy * (0.2 + 0.8 * h);
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
  // The sky's plane.
  vec2 ws = pt - vec2(uGeo.x, 0.0) - uCam;
  float X = ws.x / uGeo.y;
  float E = (hor - ws.y) / hor;
  float sunX = uSun.x / uGeo.y;
  float dxSun = X - sunX;
  float wS = exp(-dxSun * dxSun / (uArch.x * uArch.x));
  float wA = smoothstep(uArch.z, uArch.w, abs(dxSun));
  float dxLight = X - uLight.x / uGeo.y;
  // Opposite the sun the earth's shadow rises out of the horizon, under the Belt.
  float wShadow = uShadow.w * smoothstep(0.95, 1.9, abs(dxSun));

  // ── land, front to back: the near hill hides the rest, and the sky ──
  vec3 landCol = vec3(0.0);
  float T = 1.0;                       // how much of what is behind still shows
  if (ws.y > hor - 44.0) {
    vec3 horizonCol = mix(skyAt(X, 0.012), uShadow.xyz, wShadow);
    // The air between the planes is lit by the whole low sky, not only its rim.
    vec3 hazeCol = mix(mix(horizonCol, skyAt(X, 0.27), 0.55), uAmbient, 0.36 + 0.12 * wA);
    hazeCol.yz *= 0.85;
    // …and it is the cool of the evening: what yellow the low sun gave it goes to rose.
    hazeCol.z = min(hazeCol.z, hazeCol.z * 0.22 + 0.002);
    vec3 mistCol = mix(mix(uMist.xyz, uMistFar, smoothstep(0.10, 0.9, abs(dxLight))), hazeCol, 0.30);
    // where the low sun is behind it, the mist is full of its light
    mistCol = mix(mistCol, uGlow.xyz, uGlow.w * 0.6 * exp(-dxSun * dxSun / 0.09));
    // (rose-gold, never mustard: the low key has no use for yellow in a dim colour)
    mistCol.z = mix(mistCol.z, min(mistCol.z, mistCol.z * 0.5 + 0.004), uHush.y);
    for (int k = 0; k < ${N_HILL}; k++) {
      int i = ${N_HILL - 1} - k;
      vec4 A = uHillA[i];
      if (A.x > 5000.0) continue;
      vec4 C = uHillC[i];
      vec4 M = uHillM[i];
      vec2 w = pt - C.xy;
      float fi = A.w;
      float slope;
      float cr = crestOf(i, w.x, slope);
      float soft = max(A.z, 0.6 / uDpr);
      vec4 W = uHillW[i];
      float cn = 0.0;
      if (W.z > 0.0 && w.x > W.x && w.x < W.y && w.y > cr - W.z * 1.6 - 2.0) cn = woodsAt(i, w.x, W);
      float ground = sstep(-soft, soft, w.y - cr);
      float top = cr - cn;
      float wood = cn > 0.0 ? sstep(-soft * 1.6, soft * 1.6, w.y - top) * uSeason.z : 0.0;
      float a = max(ground, wood);
      // A hill that stands on the valley floor ends there, its foot lost in the mist.
      float footed = 1.0;
      if (W.w > 0.0) {
        float fy = hor + W.w + (vnoise(vec2(w.x / 38.0 + fi * 3.0, 1.5)) - 0.5) * 9.0;
        footed = 1.0 - sstep(fy - 16.0, fy + 3.0, w.y);
        a *= footed;
      }
      if (a <= 0.0) continue;
      float Xp = w.x / uGeo.y;
      // Mist in the valley in front of this plane: a level pool the next plane stands out of.
      if (M.z > 0.0 && uMist.w > 0.0) {
        float level = hor + M.x;
        float mn = vnoise(vec2(w.x / (64.0 + 70.0 * fi) + uTime.x * (1.0 + 0.4 * fi) + fi * 5.3, w.y / (8.0 + 7.0 * fi) + fi));
        float mw = vnoise(vec2(w.x / (210.0 + 90.0 * fi) - uTime.x * 0.5 + fi * 9.1, 0.5));
        float d = (w.y - level + (mn - 0.5) * M.y * 1.1) / M.y;
        float m = uMist.w * M.z * sstep(-0.9, 1.6, d) * (0.62 + 0.38 * sstep(0.18, 0.7, mw + 0.2));
        m = clamp(m, 0.0, 0.85) * a * (1.0 - 0.5 * wA * (1.0 - uHush.y));
        landCol += T * m * mistCol;
        T *= 1.0 - m;
      }
      float below = max(w.y - cr, 0.0);
      // The slope's texture: broad and slow, a brush's drag rather than a grain.
      float tex = vnoise(vec2(w.x / (30.0 + 34.0 * fi) + fi * 7.1, w.y / (11.0 + 13.0 * fi)));
      vec3 g = uLand;
      if (uHillB[i].w > 0.5) {
        // ── the valley floor, and the river on it ──
        float Yr = w.y - hor;
        float farness = 1.0 - sstep(6.0, 190.0, Yr);
        g = mix(g, mix(g, uSnowLit, 0.5), uSeason.y * (0.35 + 0.5 * tex));
        g = mix(g, mix(uSnowLit, uSnowShade, 0.35 + 0.3 * tex), uSeason.x * 0.92);
        g = mix(g, hazeCol, 0.24 + 0.6 * farness);
        // long thin bands of mist lie level across it, nearer the far end
        float lie = vnoise(vec2(w.x / 260.0 + uTime.x * 1.3, Yr / (5.0 + 0.05 * Yr))) * 0.65 + vnoise(vec2(w.x / 90.0 - uTime.x, Yr / (3.0 + 0.03 * Yr) + 7.0)) * 0.35;
        float bandM = uMist.w * (0.16 + 0.44 * farness) * sstep(0.3, 0.86, lie);
        g = mix(g, mistCol, clamp(bandM, 0.0, 0.6));
        if (uRiverQ.z > 0.5 && Yr > uRiverQ.x - 2.0 && Yr < uRiverQ.y) {
          float u = sqrt(clamp((Yr - uRiverQ.x) / (uRiverQ.y - uRiverQ.x), 0.0, 1.0)) * ${N_RIVER - 1}.0;
          int j = int(min(floor(u), ${N_RIVER - 2}.0));
          vec2 r0 = uRiver[j], r1 = uRiver[j + 1];
          vec2 r = mix(r0, r1, u - float(j));
          float dY = (uRiverQ.y - uRiverQ.x) * (2.0 * float(j) + 1.0) / ${(N_RIVER - 1) * (N_RIVER - 1)}.0;
          float lean = abs(r1.x - r0.x) / max(dY, 0.02);
          float aa = 0.55 + 0.45 * min(lean, 7.0);
          float d = abs(w.x - r.x) - r.y;
          float water = (1.0 - sstep(-aa, aa, d)) * sstep(uRiverQ.x - 1.5, uRiverQ.x + 2.5, Yr);
          // The water carries the sky above it, and whatever light is low in it.
          vec3 wc = skyAt(Xp, clamp(0.02 + 0.16 * Yr / hor, 0.0, 1.0));
          wc.x = wc.x * (1.0 + 0.03 * uRoom) + 0.012 * uRoom;
          wc = mix(wc, uShadow.xyz, wShadow * 0.5);
          float nearSun = exp(-dxSun * dxSun / 0.36);
          wc = mix(wc, uGlow.xyz, clamp(uGlow.w * 0.75 * nearSun, 0.0, 0.8));
          float nearLight = exp(-dxLight * dxLight / 0.5);
          wc = mix(wc, uLightCol, uLight.w * 0.28 * nearLight * uRoom);
          // a broken path of light on it
          float gl = vnoise(vec2(w.x * 0.55 + uRiverQ.w, Yr * 1.9 + uRiverQ.w * 0.6));
          float spark = sstep(0.70, 0.9, gl) * uLight.w * nearLight * nearLight;
          wc = mix(wc, uLightCol, clamp(spark * 0.85, 0.0, 0.9));
          // the brush dragged along it, lighter down its middle
          wc.x += 0.022 * (vnoise(vec2(w.x / 26.0 + uRiverQ.w * 0.4, Yr / 1.3)) - 0.5) + 0.014 * (1.0 - sstep(0.0, r.y, abs(w.x - r.x)));
          g = mix(g, wc, water);
          // …and mist lies on it and beside it, lit from where the light is.
          float md = exp(-pow(max(d, 0.0) / (r.y * 1.5 + 9.0), 2.0));
          float mn = vnoise(vec2(w.x / 44.0 + uTime.x * 1.7, Yr / 6.5 + 3.0));
          float reach = 1.0 - uOpen.z * (1.0 - sstep(uOpen.x - uOpen.y, uOpen.x + uOpen.y, w.x));
          float crest = uOpen.z * exp(-pow((w.x - uOpen.x) / (uOpen.y * 1.2), 2.0));
          float rm = uMist.w * (0.6 + 0.5 * farness) * md * sstep(0.2, 0.75, mn + 0.3 * farness) * (reach + 0.7 * crest);
          vec3 riverMist = mix(mistCol, wc, 0.55);
          riverMist.x += 0.03 * uRoom;
          riverMist.x = mix(min(riverMist.x, wc.x), riverMist.x, uRoom);
          g = mix(g, riverMist, clamp(rm, 0.0, 0.8));
        }
      } else {
        // Which way the slope under the crest faces: toward the light, or away.
        float side = clamp(0.5 - clamp(dxLight * 6.0, -1.0, 1.0) * slope * 1.7, 0.0, 1.0);
        // Frost silvers the open ground; snow lies on it with blue shadows.
        g = mix(g, mix(g, uSnowLit, 0.5), uSeason.y * (0.30 + 0.55 * tex));
        float hollow = sstep(0.0, 26.0 + 22.0 * fi, below + (tex - 0.5) * (20.0 + 12.0 * fi));
        vec3 snow = mix(uSnowLit, uSnowShade, hollow * (0.55 + 0.45 * wA));
        g = mix(g, snow, uSeason.x * (0.86 + 0.14 * tex));
        // A wood on the crest: its tops catch the light, and that is where the season shows.
        if (cn > 0.0 || (W.z > 0.0 && w.x > W.x && w.x < W.y)) {
          float inWood = sstep(W.x, W.x + 26.0, w.x) * (1.0 - sstep(W.y - 26.0, W.y, w.x)) * uSeason.z
            * (1.0 - sstep(0.0, W.z * 2.4 + 6.0, below + (tex - 0.5) * 8.0));
          float wmask = max(inWood, wood * (1.0 - ground));
          if (wmask > 0.001) {
            float topLit = exp(-max(w.y - top, 0.0) / (3.0 + W.z * 1.4)) * (0.42 + 0.58 * wS) * uWoodsLit.w;
            vec3 wd = mix(uWoods, uWoodsLit.xyz, clamp(topLit, 0.0, 1.0));
            float drift = 0.62 * vnoise(vec2(w.x / 40.0 + fi * 3.0, w.y / 30.0)) + 0.38 * vnoise(vec2(w.x / 17.0 + fi * 7.0, w.y / 13.0 + 3.0));
            float flower = uSeason.w * smoothstep(0.34, 0.72, drift) * (0.45 + 0.55 * exp(-max(w.y - top, 0.0) / (W.z * 1.6 + 6.0)));
            wd = mix(wd, uBloom, 0.8 * flower);
            wd = mix(wd, uSnowLit, 0.30 * uSeason.x);
            g = mix(g, wd, wmask);
          }
        }
        // The slope that faces the light catches it under the crest; the other is a shade deeper.
        float dry = vnoise(vec2(w.x / 11.0 + fi * 13.0, below / 1.7 + fi * 3.0));
        float rim = uRim.w * side * exp(-below / (5.0 + 9.0 * fi)) * (0.25 + 0.75 * wS) * (0.62 + 0.38 * sstep(0.25, 0.7, dry));
        g = mix(g, uRim.xyz, clamp(rim * 0.85, 0.0, 0.9));
        // the crest itself is drawn: a darker line where the light does not find it
        g.x *= 1.0 - 0.13 * exp(-below / 1.4) * (1.0 - side * uRim.w) * (1.0 - A.y);
        g.x *= 1.0 - 0.12 * (1.0 - side) * exp(-below / (36.0 + 50.0 * fi)) * (0.35 + 0.65 * uRim.w);
        g.x += 0.010 * (tex - 0.5) * (1.0 - A.y);
        // Aerial perspective: into the sky's own colour at the horizon; and
        // down the slope it sinks into the valley's air.
        float hz = A.y + (1.0 - A.y) * 0.44 * sstep(0.0, M.w, below);
        g = mix(g, hazeCol, hz);
      }
      landCol += T * a * g;
      T *= 1.0 - a;
      if (T < 0.004) break;
    }
  }

  // ── sky (only where the land lets it through) ──
  vec3 lab = vec3(0.0);
  float cloudA = 0.0;
  float moonLight = 0.0;
  float moonSea = 0.0;
  float sunDisc = 0.0;
  if (T >= 0.004) {
    lab = skyAt(X, E);
    lab = mix(lab, uShadow.xyz, wShadow * (1.0 - smoothstep(uShadowH * 0.35, uShadowH, E)));

    // The sun's own light in the air around it, hugging the horizon.
    vec2 ds = (ws - uSun.xy) / 292.0;
    float rs = length(ds * vec2(0.8, 1.2));
    float glow = uGlow.w * (0.5 * exp(-rs / 0.32) + 0.5 * exp(-rs / 0.075));
    lab = mix(lab, uGlow.xyz, clamp(glow, 0.0, 0.92));
    sunDisc = uSun.w * (1.0 - smoothstep(uSun.z - 0.9, uSun.z + 0.9, length(ws - uSun.xy)));

    // The moon: a quiet glow, the lit part of the disc turned to its real angle.
    if (uMoon.w > 0.0) {
      vec2 dm = ws - uMoon.xy;
      float rm = length(dm);
      float mg = uMoonB.z * (0.5 * exp(-rm / 58.0) + 0.5 * exp(-rm / (uMoon.z * 1.7)));
      lab = mix(lab, uMoonCol, clamp(mg, 0.0, 0.8) * uMoon.w);
      if (rm < uMoon.z + 2.0) {
        float cr = cos(-uMoonB.y), sr = sin(-uMoonB.y);
        vec2 q = vec2(cr * dm.x - sr * dm.y, sr * dm.x + cr * dm.y);
        float limb = 1.0 - smoothstep(uMoon.z - 0.8, uMoon.z + 0.8, rm);
        float term = (1.0 - 2.0 * uMoonB.x) * sqrt(max(uMoon.z * uMoon.z - q.y * q.y, 0.0));
        float lit = smoothstep(term - 0.8, term + 0.8, q.x);
        moonLight = limb * (lit + (1.0 - lit) * uMoonB.w) * uMoon.w;
        // its seas, faintly: three soft shadows that turn with it
        vec2 qn = q / uMoon.z;
        moonSea = clamp(exp(-dot(qn - vec2(-0.22, -0.28), qn - vec2(-0.22, -0.28)) / 0.13) + 0.8 * exp(-dot(qn - vec2(0.24, 0.06), qn - vec2(0.24, 0.06)) / 0.08)
          + 0.7 * exp(-dot(qn - vec2(-0.08, 0.44), qn - vec2(-0.08, 0.44)) / 0.06), 0.0, 1.0);
      }
    }

    // ── clouds: a few designed forms, each lit on the side the light is and shadowed beneath ──
    float bodies = max(sunDisc, moonLight);
    for (int c = 0; c < ${N_CLOUD}; c++) {
      vec4 box = uCloud[c];
      vec4 Q = uCloudQ[c];
      if (Q.y <= 0.0 || abs(ws.x - box.x) > box.z || abs(ws.y - box.y) > box.w) continue;
      float f = 0.0;
      vec2 grad = vec2(0.0);
      for (int k = 0; k < ${N_BLOB}; k++) {
        vec4 b = uBlob[c * ${N_BLOB} + k];
        if (b.z <= 0.0) continue;
        vec2 d = (ws - b.xy) / b.zw;
        float e = exp(-dot(d, d));
        f += e;
        grad += -2.0 * d / b.zw * e;
      }
      // A drawn edge with the brush's tooth, and a flatter foot: the one thing every cloud has.
      float tooth = (vnoise(ws * vec2(0.3, 0.6) + Q.z) - 0.5) * 0.14 + (vnoise(ws * vec2(0.09, 0.22) + Q.z * 2.0) - 0.5) * 0.2;
      float body = sstep(0.38, 0.56, f + tooth);
      float footY = Q.x + (vnoise(vec2(ws.x * 0.05 + Q.z, 3.0)) - 0.5) * 2.0;
      body *= 1.0 - sstep(footY - 1.6, footY + 1.0, ws.y);
      if (body <= 0.002) continue;
      // Its form: the whole of it turned toward the light on one side and away on the other,
      // each hump a little on its own — modelled like a thing, not edged like a sticker.
      vec2 nf = (ws - box.xy) / (box.zw * 0.55);
      vec2 n = normalize(nf * 0.7 - grad * 2.4 + vec2(1e-5));
      // (the light's side by where it is on the page; above or below by its real height in the sky)
      vec2 l = normalize(vec2(clamp((uLight.x - ws.x) / 150.0, -1.0, 1.0), uLightV));
      float lam = dot(n, l) * min(1.0, length(nf) * 1.3);
      float lit = sstep(-0.3, 0.8, lam) * uLight.z;
      vec3 base = mix(uCShade, lab, 0.18);
      vec3 cc = mix(base, mix(uCLit, uCFar, wA), lit);
      float aC = body * Q.y * (1.0 - 0.8 * bodies);
      lab = mix(lab, cc, aC);
      cloudA = cloudA + (1.0 - cloudA) * aC;
    }
  }
  lab = landCol + T * lab;

  // ── the hush, the room, the words ──
  float p = uHush.x;
  float words = 0.0;
  for (int r = 0; r < 3; r++) {
    vec4 R = uText[r];
    if (R.z <= R.x) continue;
    float mx = sstep(R.x - uLimit.y, R.x, pt.x) * (1.0 - sstep(R.z, R.z + uLimit.y, pt.x));
    float my = sstep(R.y - uLimit.y * 0.4, R.y, pt.y) * (1.0 - sstep(R.w, R.w + uLimit.y * 0.4, pt.y));
    words = max(words, mx * my);
  }
  if (uHush.y > 0.5) {
    lab.x *= 1.0 - uHushK.x * (1.0 - p);
    lab.yz *= uHushK.y + (1.0 - uHushK.y) * p;
    lab.x *= 1.0 - 0.14 * uHush.z;
    lab.yz *= 1.0 - 0.12 * uHush.z;
    lab.x = mix(lab.x, smin(lab.x, uLimit.x, 0.05), words);
  } else {
    lab.x += (uHush.w - lab.x) * uHushK.x * (1.0 - p);
    lab.yz *= uHushK.y + (1.0 - uHushK.y) * p;
    lab.x -= 0.012 * uHush.z;
    lab.yz *= 1.0 - 0.25 * uHush.z;
    lab.x = mix(lab.x, smax(lab.x, uLimit.x, 0.03), words);
    lab.yz *= 1.0 - 0.3 * words * smoothstep(0.05, 0.12, length(lab.yz));
  }
  // The sun and the moon are never hushed: they are the light. (The land and
  // thick cloud still hide them.)
  vec3 moonC = uMoonCol;
  moonC.x *= 1.0 - 0.085 * moonSea;
  lab = mix(lab, moonC, moonLight * T * (1.0 - 0.5 * cloudA));
  float sd = sunDisc * T * (1.0 - 0.55 * cloudA);
  lab = mix(lab, uSunCol, sd);
  lab.x += 0.04 * sd * (1.0 - smoothstep(0.0, uSun.z, length(ws - uSun.xy)));

  // A breath of grain, in lightness, before the print.
  // (counted from the anchor window's corner, so the cover and the spread's phone page are one print)
  uvec2 q2 = uvec2(ivec2(int(gl_FragCoord.x) + 4096 - int(uGeo.x * uDpr), int(uPx.y - gl_FragCoord.y)));
  uint hA = q2.x * 1597334677u ^ q2.y * 3812015801u;
  hA = hA * (hA ^ (hA >> 15u));
  uint hB = (q2.x + 71u) * 2654435761u ^ (q2.y + 13u) * 2246822519u;
  hB = hB * (hB ^ (hB >> 13u));
  float tri = (float(hA >> 8u) + float(hB >> 8u) - 16777216.0) / 16777216.0;
  lab.x += tri * uTime.y;

  vec3 rgb = display(lab);
  // Dither (triangular, one level).
  rgb += tri * (1.25 / 255.0);
  outColor = vec4(clamp(rgb, 0.0, 1.0), 1.0);
}`;

// ─────────────────────────────────────────────────────────────── geometry ──

// The header as the lab lays it out (points, in the phone page) — used when a state carries
// no measured layout, and, always, for where a star may stand: a night's place must not
// move because his age line grew a letter.
const DUO_LAYOUT = { name: { x: 96, y: 29, width: 92, height: 26 }, age: { x: 94, y: 67.6, width: 91, height: 12 }, avatar: { x: 20, y: 22, width: 60, height: 60 },
  gear: { x: 318, y: 22, width: 44, height: 44 }, firstCardTop: 88.6, stripClear: { x: 362, width: 104, yMin: 151, yMax: 396 }, title: null, subtitle: null };
const SLAB_LAYOUT = { name: { x: 92, y: 77, width: 92, height: 26 }, age: { x: 90, y: 115.6, width: 91, height: 12 }, avatar: { x: 16, y: 70, width: 60, height: 60 },
  gear: { x: 342, y: 70, width: 44, height: 44 }, firstCardTop: 136.6, stripClear: null, title: null, subtitle: null };
// What his stars keep clear of (phone-page points): the words (with room for a longer age),
// the avatar, the gear, the status column or bar, the tab capsule (cover's and spread's together).
const KEEP = {
  duo: { words: { x0: 88, y0: 24, x1: 208, y1: 85 }, avatar: { x0: 17, y0: 19, x1: 83, y1: 85 }, gear: { x0: 315, y0: 19, x1: 365, y1: 69 },
    status: { x0: 382, y0: 0, x1: 466, y1: 190 }, capsule: { x0: 386, y0: 381, x1: 462, y1: 650 } },
  slab: { words: { x0: 84, y0: 72, x1: 204, y1: 132 }, avatar: { x0: 13, y0: 67, x1: 79, y1: 133 }, gear: { x0: 339, y0: 67, x1: 389, y1: 117 },
    status: { x0: 0, y0: 0, x1: 402, y1: 64 }, capsule: { x0: 20, y0: 786, x1: 382, y1: 858 } },
};

const grow = (r, dx, dy = dx) => ({ x0: r.x - dx, y0: r.y - dy, x1: r.x + r.width + dx, y1: r.y + r.height + dy });
const union = (a, b) => (!a ? b : !b ? a : { x0: Math.min(a.x0, b.x0), y0: Math.min(a.y0, b.y0), x1: Math.max(a.x1, b.x1), y1: Math.max(a.y1, b.y1) });

function geometry(state) {
  const slab = state.device === 'iphone';
  const cfg = slab ? SLAB : DUO;
  const phone = state.phone ?? { x: 0, width: state.width };
  const given = state.layout && state.layout.name && state.layout.age ? state.layout : null;
  // The header's own rects, in the phone page's points (so the cover's and the spread's are one set).
  let L;
  if (given) {
    const shift = (r) => (r ? { x: r.x - phone.x, y: r.y, width: r.width, height: r.height } : null);
    L = { name: shift(given.name), age: shift(given.age), avatar: shift(given.avatar), gear: shift(given.gear), firstCardTop: given.firstCardTop,
      stripClear: given.stripClear ? { ...given.stripClear, x: given.stripClear.x - phone.x } : null,
      title: given.title ? { ...given.title } : null, subtitle: given.subtitle ? { ...given.subtitle } : null };
  } else {
    L = slab ? SLAB_LAYOUT : DUO_LAYOUT;
  }
  const treeFoot = crestAt(cfg, cfg.tree.hill, cfg.tree.x) + 1.2;
  return { slab, cfg, phone, L, keep: slab ? KEEP.slab : KEEP.duo, treeFoot, width: state.width, height: state.height };
}

/** How far the camera has looked up, 0 (rest) … 1: the sky's own function of the bedtime
 *  event — or the URL's look=. `move` false under Reduce Motion: the poses cross-fade. */
function lookOf(state) {
  let k = 0;
  if (state.event && state.event.kind === 'bedtime' && state.asleep === 'night') {
    const age = state.event.age;
    const ease = (u) => u * u * u * (u * (u * 6 - 15) + 10);
    k = ease(clamp01((age - 0.3) / 2.1)) * (1 - ease(clamp01((age - 5.3) / 2.2)));
  }
  const forced = urlNumber('look');
  if (forced != null) k = clamp01(forced);
  return { k, move: !state.reduceMotion };
}

function urlNumber(name) {
  try {
    const v = new URLSearchParams(globalThis.location?.search ?? '').get(name);
    if (v == null || v === '') return null;
    const n = Number(v);
    return Number.isFinite(n) ? n : null;
  } catch { return null; }
}

/** A body's height above the horizon (points) from its real altitude: the low sky is
 *  opened out (1.7° is 30 pt on the Duo), it never stands in the header at rest — from
 *  30° it is above the frame, to be seen when the camera looks up — and `show` fades the
 *  disc across that step. */
function bodyAt(cfg, altDeg) {
  const b = cfg.body;
  if (altDeg <= 0) return { h: altDeg * 9 * (b.low / 22.85), show: 1 };
  const lowTop = b.low * Math.pow(12, 0.513);
  let h;
  if (altDeg <= 12) h = b.low * Math.pow(altDeg, 0.513);
  else if (altDeg <= 30) h = lerp(lowTop, b.cap, (altDeg - 12) / 18);
  else h = lerp(b.above[0], b.above[1], (altDeg - 30) / 60);
  const show = altDeg <= 30 ? 1 - smoothstep(29.2, 30, altDeg) : smoothstep(30, 30.8, altDeg);
  return { h, show };
}

/** 1 once a disc of radius r at screen (x, y) is clear of every rect, 0 behind one. */
function clearOf(rects, x, y, r) {
  let f = 1;
  for (const q of rects) {
    if (!q) continue;
    const dx = Math.max(q.x0 - x, 0, x - q.x1), dy = Math.max(q.y0 - y, 0, y - q.y1);
    f *= smoothstep(r - 1, r + 9, Math.hypot(dx, dy));
  }
  return f;
}

function oklchCss(L, C, hDeg) {
  return labRgb([L, C * Math.cos(hDeg / DEG), C * Math.sin(hDeg / DEG)]);
}
/** OKLab → sRGB bytes, giving up chroma to fit. */
function labRgb(lab) {
  const lin = (L, a, b) => {
    const l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3;
    const m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3;
    const s = (L - 0.0894841775 * a - 1.291485548 * b) ** 3;
    return [4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
      -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
      -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s];
  };
  const L = clamp01(lab[0]);
  let k = 1, v = lin(L, lab[1], lab[2]);
  const ok = (q) => q.every((c) => c >= -1e-4 && c <= 1 + 1e-4);
  if (!ok(v)) {
    let lo = 0, hi = 1;
    for (let i = 0; i < 14; i += 1) { k = (lo + hi) / 2; if (ok(lin(L, lab[1] * k, lab[2] * k))) lo = k; else hi = k; }
    v = lin(L, lab[1] * lo, lab[2] * lo);
  }
  const g = (c) => Math.round(255 * clamp01(c <= 0.0031308 ? 12.92 * c : 1.055 * Math.pow(clamp01(c), 1 / 2.4) - 0.055));
  return [g(v[0]), g(v[1]), g(v[2])];
}
const rgba = (c, a) => `rgba(${c[0]},${c[1]},${c[2]},${a})`;
const rgb = (c) => `rgb(${c[0]},${c[1]},${c[2]})`;

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
  const over = overCanvas.getContext('2d');

  const gl = glCanvas.getContext('webgl2', { antialias: false, alpha: false, depth: false, stencil: false,
    preserveDrawingBuffer: true, powerPreference: 'high-performance' });
  let program = null;
  const U = {};
  if (gl) {
    const compile = (type, src) => {
      const sh = gl.createShader(type);
      gl.shaderSource(sh, src);
      gl.compileShader(sh);
      if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) throw new Error(`hill-lit shader: ${gl.getShaderInfoLog(sh)}`);
      return sh;
    };
    program = gl.createProgram();
    gl.attachShader(program, compile(gl.VERTEX_SHADER, VERT));
    gl.attachShader(program, compile(gl.FRAGMENT_SHADER, FRAG));
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error(`hill-lit link: ${gl.getProgramInfoLog(program)}`);
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
  }

  let destroyed = false;
  let lastKey = '';
  let lastState = null;
  const timing = { first: null, last: 0, frames: 0 };
  const set3 = (name, v) => gl.uniform3f(U[name], v[0], v[1], v[2]);
  const set4 = (name, a, b, c, d) => gl.uniform4f(U[name], a, b, c, d);

  // ── the camera ──

  /** Where each plane is on the display at pose `k`: screen = world + offset. */
  function camera(state, G, k) {
    const cfg = G.cfg;
    const tilt = state.tilt ?? { x: 0, y: 0 };
    const cx = -cfg.turn * k, cy = cfg.rise * k;
    const plane = (depthPt, drop) => ({ x: G.phone.x + cx - tilt.x * depthPt, y: cy + drop * k - tilt.y * depthPt * 0.4 });
    const sky = { x: G.phone.x + cx - tilt.x * 1.0, y: cy - tilt.y * 0.6 };
    const hills = cfg.hills.map((h) => plane(1.4 + 12 * h.depth, h.drop));
    return { k, sky, hills, tree: hills[cfg.tree.hill] };
  }

  // ── his stars, on the tall sky ──

  let starCache = { key: '', stars: [], ordinary: [] };

  /** Every night's fixed place in the world (points), on the whole sky the looked-up pose
   *  shows: none behind the header's words or the island or the capsule when the camera
   *  is up, none behind his name at rest, none in the tree, none on another. */
  function starsFor(state, G, lit) {
    const cfg = G.cfg;
    const W = G.phone.width;
    const K = G.keep;
    const key = [cfg.name, W, state.ageDays, lit].join('|');
    if (starCache.key === key) return starCache;
    const up = { x: -cfg.turn, y: cfg.rise };              // screen − world when the camera is up
    // Rects in WORLD points that a star may not sit in: everything on the header, the status
    // column and the capsule when the camera is up; his name and age at rest.
    const worldOf = (q, cam) => ({ x0: q.x0 - cam.x, y0: q.y0 - cam.y, x1: q.x1 - cam.x, y1: q.y1 - cam.y });
    const caption = { x0: 22, y0: (G.slab ? 874 : 678) - cfg.captionFoot - 17, x1: 138, y1: (G.slab ? 874 : 678) - cfg.captionFoot + 7 };
    const no = [K.words, K.avatar, K.gear, K.status, K.capsule, caption].map((q) => worldOf(q, up));
    no.push(worldOf(K.words, { x: 0, y: 0 }));
    const tree = cfg.tree;
    const tonight = { x: tree.x + cfg.tonight.dx, y: G.treeFoot + cfg.tonight.dy };
    const inTree = (x, y) => {
      const v = (G.treeFoot - y) / tree.h;
      if (v < -0.05 || v > 1.16) return false;
      if (v < 0.2) return Math.abs(x - tree.x) < 6;
      const span = crownSpan(Math.min(0.93, v));
      const pad = 7 / tree.h;
      return span ? x > tree.x - (span.left + pad) * tree.h && x < tree.x + (span.right + pad) * tree.h : Math.abs(x - tree.x) < 8;
    };
    const top = -cfg.rise + 6;
    const floorAt = (x) => skyline(cfg, x) - 8;
    // Across: a little denser over the strip's column. Down: denser in the band the header shows at rest.
    const x0 = cfg.turn + 4, x1 = W + cfg.turn - 4;
    const cols = G.slab ? [[x0, x1, 1]] : [[x0, 362, 1], [362, W, 1.4], [W, x1, 1]];
    const colTotal = cols.reduce((a, c) => a + (c[1] - c[0]) * c[2], 0);
    const xOf = (u) => {
      let acc = 0;
      for (const [a, b, wgt] of cols) {
        const part = ((b - a) * wgt) / colTotal;
        if (u <= acc + part) return a + ((u - acc) / part) * (b - a);
        acc += part;
      }
      return x1;
    };
    const bandFoot = (G.slab ? SLAB_LAYOUT : DUO_LAYOUT).firstCardTop - 2;
    const rows = G.slab ? [[top, 0, 1], [0, cfg.horizon, 2.6]] : [[top, 2, 1], [2, bandFoot, 1.9], [bandFoot, cfg.horizon, 0.85]];
    const rowTotal = rows.reduce((a, r) => a + (r[1] - r[0]) * r[2], 0);
    const yOf = (v, floor) => {
      let acc = 0;
      for (const [a, b, wgt] of rows) {
        const part = ((b - a) * wgt) / rowTotal;
        if (v <= acc + part) return Math.min(a + ((v - acc) / part) * (b - a), floor);
        acc += part;
      }
      return floor;
    };
    const stars = nights(state.ageDays, { tonightLit: lit }).map((star) => {
      if (star.kind === 'tonight') return { ...star, x: tonight.x, y: tonight.y };
      const x = xOf(star.u);
      const floor = floorAt(x);
      // the lowest rows are squeezed above the skyline rather than cut off by it
      const y = top + (yOf(star.v, 1e9) - top) * ((floor - top) / (cfg.horizon - top));
      return { ...star, x, y };
    });
    const apart = G.slab ? 5 : 5.6;
    const free = (x, y, upto) => {
      if (x < x0 || x > x1 || y < top || y > floorAt(x)) return false;
      for (const q of no) if (x > q.x0 && x < q.x1 && y > q.y0 && y < q.y1) return false;
      if (inTree(x, y) || Math.hypot(x - tonight.x, y - tonight.y) < 17) return false;
      for (let i = 0; i < upto; i += 1) {
        if (stars[i].kind === 'tonight') continue;
        const gap = stars[i].kind === 'night' ? apart : apart + 4;
        if (Math.abs(x - stars[i].x) < gap && Math.hypot(x - stars[i].x, y - stars[i].y) < gap) return false;
      }
      return true;
    };
    stars.forEach((star, index) => {
      if (star.kind === 'tonight' || free(star.x, star.y, index)) return;
      for (let ring = 1; ring <= 26; ring += 1) {
        for (let k = 0; k < 12; k += 1) {
          const a = (k / 12 + hash(star.night, 31)) * TAU, r = ring * apart * 0.6;
          const x = star.x + Math.cos(a) * r, y = star.y + Math.sin(a) * r * 0.85;
          if (free(x, y, index)) { star.x = x; star.y = y; return; }
        }
      }
    });
    // The ordinary sky, nobody's: the leading page, and the strip of world the turn leaves behind.
    const ordinary = [];
    const ox0 = -cfg.lead - 20, ox1 = cfg.turn;
    const count = Math.round(((ox1 - ox0) * (cfg.horizon + cfg.rise)) / 1500);
    for (let i = 0; i < count; i += 1) {
      const x = ox0 + hash(i, 61) * (ox1 - ox0);
      const y = top + Math.pow(hash(i, 62), 1.1) * (floorAt(x) - 4 - top);
      const mag = Math.pow(hash(i, 63), 2.2);
      ordinary.push({ x, y, mag, period: 2.6 + 3 * hash(i, 64), phase: hash(i, 66), steady: hash(i, 65) > 0.6, cool: hash(i, 68) < 0.6, c: 0.02 + 0.07 * hash(i, 67) });
    }
    starCache = { key, stars, ordinary, tonight };
    return starCache;
  }

  function starColour(star, dark) {
    const w = star.warmth;
    const odd = hash(star.night, 8);
    let h = w < 0 ? 250 : 74;
    let C = 0.018 + 0.15 * Math.abs(w);
    if (odd > 0.88) { h = 42; C = 0.10; } else if (odd < 0.08) { h = 8; C = 0.07; }
    if (star.kind === 'first') { h = 80; C = 0.035; }
    return dark ? oklchCss(0.955, C, h) : oklchCss(0.995, C * 0.25, h);
  }

  /** The ring that leaves tonight's star at bedtime: its radius (points) and strength. */
  function ringOf(state, G) {
    if (!state.event || state.event.kind !== 'bedtime' || state.asleep !== 'night' || state.reduceMotion) return null;
    const age = state.event.age - 1.9;
    if (age <= 0) return null;
    const far = Math.hypot(G.width, G.height) * (G.slab ? 0.98 : 0.92);
    const u = clamp01(age / 3.3);
    const radius = far * (1 - Math.pow(1 - u, 2.1));
    const strength = smoothstep(0, 0.4, age) * (1 - smoothstep(0.62, 1, u));
    return { radius, strength, age, far };
  }

  /** How much cloud lies over a world point. */
  function cloudOver(cfg, t, wx, wy) {
    let cover = 0;
    for (const cloud of cfg.clouds) {
      const at = cloudNow(cloud, t);
      if (Math.abs(wx - at.x) > 110 || Math.abs(wy - at.y) > 26) continue;
      cover = Math.max(cover, cloudCover(cloud, at, wx, wy));
    }
    return cover;
  }

  function drawStars(state, G, P, cam, t, s, dark, lit, env, alpha) {
    const cfg = G.cfg;
    const sunDeg = state.sun.altitude * DEG;
    const dusk = 1 - smoothstep(-2, 9, sunDeg);
    const darkness = Math.min(1, P.stars + 0.24 * P.depth * (0.35 + 0.65 * dusk) + 0.10 * P.event * dusk);
    const ring = ringOf(state, G);
    const bedtime = state.event && state.event.kind === 'bedtime' && state.asleep === 'night' ? state.event.age : null;
    if (!(darkness > 0.004) && !ring && !(state.reduceMotion && bedtime != null)) return;
    const { stars, ordinary, tonight } = starsFor(state, G, lit);
    const ox = cam.sky.x, oy = cam.sky.y;
    const settled = bedtime == null ? (state.asleep === 'night' ? 1 : 0) : smoothstep(2.2, 5.2, bedtime);
    const cloudy = env.cloudAmt;
    over.globalCompositeOperation = 'source-over';
    const moon = env.moon;

    const put = (x, y, r, a, c, big, first) => {
      if (!dark) {
        // On a pale page a light needs a little deeper sky gathered round it.
        const R = big ? 7.5 : Math.max(3.2, r * 3.3);
        const g = over.createRadialGradient(x, y, 0, x, y, R);
        const k = Math.min(1, a) * (big ? 0.42 : 0.3);
        g.addColorStop(0, `rgba(104,98,168,${k})`);
        g.addColorStop(0.35, `rgba(104,98,168,${k * 0.55})`);
        g.addColorStop(1, 'rgba(104,98,168,0)');
        over.fillStyle = g;
        over.beginPath(); over.arc(x, y, R, 0, TAU); over.fill();
      } else if (big || r > 1.05) {
        const R = big ? 8.5 : r * 3.4;
        const g = over.createRadialGradient(x, y, 0, x, y, R);
        const k = (big ? 0.2 : 0.12) * Math.min(a, 1.35);
        g.addColorStop(0, rgba(c, k));
        g.addColorStop(0.25, rgba(c, k * 0.32));
        g.addColorStop(1, rgba(c, 0));
        over.fillStyle = g;
        over.beginPath(); over.arc(x, y, R, 0, TAU); over.fill();
      }
      if (big) {
        // A four-point glint, fine and short: the month-nights, the first night.
        const len = (first ? 7.5 : 5.5) * (0.55 + 0.45 * Math.min(a, 1.35));
        over.fillStyle = rgba(c, Math.min(1, 0.85 * a));
        for (let q = 0; q < 2; q += 1) {
          const dx = q === 0 ? len : 0.55, dy = q === 0 ? 0.55 : len;
          over.beginPath();
          over.moveTo(x - dx, y);
          over.quadraticCurveTo(x, y, x, y - dy);
          over.quadraticCurveTo(x, y, x + dx, y);
          over.quadraticCurveTo(x, y, x, y + dy);
          over.quadraticCurveTo(x, y, x - dx, y);
          over.fill();
        }
      }
      over.fillStyle = rgba(c, Math.min(1, a));
      over.beginPath(); over.arc(x, y, r, 0, TAU); over.fill();
      if (a > 1) {
        over.fillStyle = rgba([255, 255, 255], Math.min(1, a - 1));
        over.beginPath(); over.arc(x, y, r * 0.8, 0, TAU); over.fill();
      }
    };
    const dimmed = (wx, wy, a) => {
      // thinned by the air at the horizon, by cloud, by the moon's own light
      const sky = skyline(cfg, wx);
      a *= 0.35 + 0.65 * smoothstep(0, 34, sky - wy);
      if (cloudy > 0.03) a *= 1 - 0.9 * cloudy * cloudOver(cfg, t, wx, wy);
      if (moon) a *= smoothstep(moon.r + 2, moon.r + 16, Math.hypot(wx - moon.x, wy - moon.y));
      if (env.sun) a *= smoothstep(env.sun.r + 2, env.sun.r + 22, Math.hypot(wx - env.sun.x, wy - env.sun.y));
      return a;
    };
    // Under Reduce Motion there is no ring: in the looked-up still his stars are simply shown.
    const shown = state.reduceMotion && bedtime != null ? 0.6 * cam.k : 0;
    const answering = (wx, wy) => {
      if (shown > 0) return shown;
      if (!ring) return 0;
      const since = ring.radius - Math.hypot(wx - tonight.x, wy - tonight.y);
      return since > -34 ? Math.exp(-(((since - 8) / 40) ** 2)) * Math.sqrt(ring.strength) : 0;
    };

    over.globalAlpha = alpha;
    if (darkness > 0.05) {
      for (const o of ordinary) {
        const x = o.x + ox, y = o.y + oy;
        if (x < -4 || x > G.width + 4 || y < -4 || y > G.height + 4) continue;
        const threshold = (1 - (0.25 + 0.5 * o.mag)) * 0.86;
        let a = smoothstep(threshold - 0.06, threshold + 0.16, darkness);
        if (!(a > 0)) continue;
        const tw = t == null || o.steady ? 0.9 : 0.7 + 0.3 * Math.cos(TAU * (t / o.period + o.phase));
        a = dimmed(o.x, o.y, a * (0.20 + 0.42 * o.mag) * tw * (1 + 0.8 * answering(o.x, o.y)));
        if (!(a > 0.01)) continue;
        put(x, y, (0.42 + 0.5 * o.mag) * (dark ? 1 : 1.1), dark ? a : a * 1.5, dark ? oklchCss(0.95, o.c, o.cool ? 250 : 75) : [255, 255, 255], false, false);
      }
    }
    for (const star of stars) {
      if (star.kind === 'tonight') continue;                     // lit over everything: see drawTonight
      const x = star.x + ox, y = star.y + oy;
      if (x < -10 || x > G.width + 10 || y < -10 || y > G.height + 10) continue;
      const threshold = (1 - star.magnitude) * 0.86;
      let a = smoothstep(threshold - 0.06, threshold + 0.16, darkness);
      const pulse = answering(star.x, star.y);
      a *= (0.30 + 0.70 * star.magnitude) * (t == null ? 0.9 : twinkle(star, t)) * (1 + 0.16 * settled + 0.25 * P.event);
      // The others answer as the ring passes — and in a sky still light, that is the only time they show.
      a = a * (1 + 1.2 * pulse) + pulse * (0.5 + 0.5 * star.magnitude) * 0.9 * (1 - darkness);
      a = dimmed(star.x, star.y, a);
      if (!(a > 0.006)) continue;
      const big = star.kind !== 'night';
      const r = (0.5 + 1.05 * star.magnitude) * (dark ? 1 : 1.12) * (1 + 0.3 * pulse);
      put(x, y, r, dark ? a : Math.min(1.2, a * 1.35), starColour(star, dark), big, star.kind === 'first');
    }
    // A rare shooting star: one window in three, for a second, high in the anchor sky.
    if (t != null && darkness > 0.6 && dark) {
      const windowLen = 53;
      const index = Math.floor(t / windowLen);
      const age = t - index * windowLen - 20;
      if (hash(index, 31) < 0.34 && age > 0 && age < 1.1) {
        const x0 = ox + (0.25 + 0.5 * hash(index, 32)) * G.phone.width;
        const y0 = oy + 14 + 60 * hash(index, 33) - cfg.rise * 0.4 * cam.k;
        const k = age / 1.1;
        const hx = x0 + 120 * k, hy = y0 + 46 * k;
        const g = over.createLinearGradient(hx - 46, hy - 17.6, hx, hy);
        const fade = Math.sin(Math.PI * k) * darkness;
        g.addColorStop(0, 'rgba(255,255,255,0)');
        g.addColorStop(1, `rgba(255,250,240,${0.8 * fade})`);
        over.strokeStyle = g;
        over.lineWidth = 1.1;
        over.lineCap = 'round';
        over.beginPath();
        over.moveTo(hx - 46, hy - 17.6);
        over.lineTo(hx, hy);
        over.stroke();
      }
    }
    // The ring itself: thin, soft, once.
    if (ring && ring.strength > 0.01) {
      const cx = tonight.x + cam.tree.x, cy = tonight.y + cam.tree.y;
      const c = dark ? [255, 232, 200] : [255, 255, 255];
      const k = ring.strength * (dark ? 1 : 1.6) * (1 - 0.55 * ring.radius / ring.far);
      for (const [width, a] of [[56, 0.012], [24, 0.016]]) {
        over.strokeStyle = rgba(c, Math.min(1, a * k));
        over.lineWidth = width * (0.7 + 0.5 * ring.radius / ring.far);
        over.beginPath();
        over.arc(cx, cy, ring.radius, 0, TAU);
        over.stroke();
      }
    }
    over.globalAlpha = 1;
  }

  // ── the tree ──

  let treeCache = { key: '', sprite: null };

  /** The hush, as the shader applies it, for what the canvas draws on the land. */
  function hushed(lab, P, dark, K, keep = 0) {
    const p = P.presence;
    const c = K[1] + (1 - K[1]) * p;
    if (dark) {
      return [lab[0] * (1 - K[0] * (1 - p)) * (1 - 0.14 * P.depth), lab[1] * c * (1 - 0.12 * P.depth), lab[2] * c * (1 - 0.12 * P.depth)];
    }
    const toward = K[0] * (1 - p) * (1 - keep);
    return [lab[0] + (PAGE_L - lab[0]) * toward - 0.012 * P.depth, lab[1] * c * (1 - 0.25 * P.depth), lab[2] * c * (1 - 0.25 * P.depth)];
  }

  /** The tree's colours for this hour, in OKLab, before the hush: the knoll's own dark a shade
   *  deeper for the wood, the light's colour on its lit side, the season's on its leaves. */
  function treeInks(G, dark, env) {
    const pal = env.pal;
    const hueOf = (lab) => Math.atan2(lab[2], lab[1]) * DEG;
    const landHue = hueOf(pal.land);
    const day = smoothstep(-2, 16, env.sunDeg);
    const night = 1 - smoothstep(-13, -6, env.sunDeg);
    const wood = dark
      ? lch(Math.max(0.034, pal.land[0] * (0.58 - 0.1 * night)), 0.014 + 0.008 * day, landHue)
      : lch(0.5 - 0.03 * (1 - day) * (1 - night) - 0.07 * night, 0.045, lerp(landHue, 20, 0.25 * (1 - night)));
    const rimLab = env.lightLab;
    const woodLit = mix3(wood, rimLab, dark ? 0.62 : 0.5);
    const leafAlb = env.land.leaf;
    // against a low sun the crown is a dark mass with a lit rim; under a high one it is its own colour
    const lowSun = 1 - smoothstep(4, 22, env.sunDeg);
    const leafCol = (lift, sat) => (dark
      ? lch(wood[0] + lift * (0.05 + 0.09 * day + 0.05 * env.lastLight) * (1 - 0.3 * lowSun * (lift < 1.5 ? 1 : 0.3)), leafAlb[1] * sat * (0.5 + 0.35 * day + 0.3 * env.lastLight), leafAlb[2])
      : lch(lerp(0.52, 0.82, (leafAlb[0] - 0.3) / 0.5) + 0.07 * (lift - 1) - 0.06 * night, leafAlb[1] * sat * (0.6 + 0.3 * day), leafAlb[2]));
    const leafShade = leafCol(0.35, 0.7), leaf = leafCol(1, 1);
    // …and where the low sun comes through the leaves they glow with their own colour
    const through = dark ? lowSun * env.lastLight : 0;
    const leafLit = mix3(mix3(leafCol(1.9, 1.15), lch(wood[0] + 0.36, Math.min(0.15, leafAlb[1] * 1.5), leafAlb[2] - (leafAlb[2] > 100 ? 14 : 0)), 0.75 * through), rimLab, dark ? 0.2 * env.lastLight : 0.16);
    const snowLit = env.snowLit;
    const blossom = dark ? mix3(lch(wood[0] + 0.3 + 0.2 * day + 0.2 * env.lastLight, 0.035, 356), rimLab, 0.2 * env.lastLight) : lch(0.975 - 0.05 * night, 0.022, 352);
    const blossomShade = dark ? lch(wood[0] + 0.15 + 0.12 * day + 0.08 * env.lastLight, 0.045, 342) : lch(0.9 - 0.06 * night, 0.05, 345);
    const frost = dark ? mix3(wood, snowLit, 0.6) : mix3(wood, [0.97, 0, 0], 0.72);
    const lastLeaf = dark ? lch(wood[0] + 0.12 + 0.1 * day + 0.14 * env.lastLight, 0.09 * (0.5 + 0.5 * Math.max(day, env.lastLight)), 52) : lch(0.7, 0.11, 58);
    return { wood, woodLit, leafShade, leaf, leafLit, blossom, blossomShade, frost, lastLeaf, snow: dark ? snowLit : [0.992, 0, 0.004], day };
  }

  function drawTree(state, G, P, cam, s, dark, env, alpha) {
    const cfg = G.cfg;
    const tree = cfg.tree;
    const sn = env.sn;
    const H = Math.round(tree.h * s);
    const lab = env.inks;
    const day = lab.day;
    const css = (c, keep) => rgb(labRgb(hushed(c, P, dark, env.hushK, keep)));
    const ink = {
      wood: css(lab.wood, 0.45), woodLit: css(lab.woodLit, 0.3), leafShade: css(lab.leafShade, 0.35), leaf: css(lab.leaf, 0.25), leafLit: css(lab.leafLit, 0.15),
      blossom: css(lab.blossom, 0), blossomShade: css(lab.blossomShade, 0.1), snow: css(lab.snow, 0), frost: css(lab.frost, 0.2), lastLeaf: css(lab.lastLeaf, 0.2),
    };
    // Where the light is, seen from the crown.
    const crownX = tree.x, crownY = G.treeFoot - tree.h * 0.6;
    const lv = { x: env.light.x - crownX, y: env.light.y - crownY };
    const ll = Math.hypot(lv.x, lv.y) || 1;
    const light = { x: lv.x / ll, y: lv.y / ll, amt: env.lightAmt, top: 0.15 + 0.45 * day };
    // The sun's disc behind it.
    let glare = null;
    if (env.sunShow > 0.03) {
      const gx = env.sun.x - tree.x, gy = env.sun.y - G.treeFoot;
      if (Math.abs(gx) < tree.h * 0.9 && gy > -tree.h * 1.3 && gy < tree.h * 0.3) {
        glare = { x: Math.round(gx * s * 2) / 2, y: Math.round(gy * s * 2) / 2, r: cfg.sunR * s, amt: env.sunShow * (dark ? 0.9 : 0.5), colour: labRgb(env.sunLab),
          eat: (dark ? 0.34 : 0.12) * (1 - 0.92 * sn.foliage), warm: (dark ? 0.85 : 0.3) * (1 - 0.5 * sn.foliage) };
      }
    }
    const seaKey = [sn.foliage, sn.blossom, sn.snow, sn.frost, sn.leafFall].map((v) => Math.round(v * 40)).join(',');
    const key = [H, s, seaKey, JSON.stringify(ink), Math.round(Math.atan2(light.y, light.x) * 24), Math.round(light.amt * 20), Math.round(light.top * 20),
      glare ? `${glare.x},${glare.y},${glare.amt.toFixed(2)},${glare.colour}` : ''].join('|');
    if (treeCache.key !== key) treeCache = { key, sprite: paintTree(doc, { H, px: s, sea: sn, ink, light, glare }) };
    const sp = treeCache.sprite;
    const fx = (tree.x + cam.tree.x) * s, fy = (G.treeFoot + cam.tree.y) * s;
    over.save();
    over.setTransform(1, 0, 0, 1, 0, 0);
    over.globalAlpha = alpha;
    over.drawImage(sp.canvas, Math.round(fx - sp.ox), Math.round(fy - sp.oy));
    over.restore();
  }

  // ── the trees along the river ──

  /** The sky's colour at anchor-x X, elevation e — the shader's skyAt, for what the canvas tints. */
  function skyLab(env, cfg, X, e) {
    const ramp = (arr, q) => {
      const f = Math.sqrt(clamp01(q)) * (N_RAMP - 1);
      const i = Math.min(Math.floor(f), N_RAMP - 2), k = f - i;
      return [0, 1, 2].map((c) => arr[i * 3 + c] + (arr[(i + 1) * 3 + c] - arr[i * 3 + c]) * k);
    };
    const dx = X - env.sunXn;
    const wS = Math.exp(-dx * dx / (cfg.arch[0] * cfg.arch[0]));
    const eg = 1 - Math.pow(1 - clamp01(e), 1 / lerp(cfg.arch[1], 1, wS));
    return mix3(ramp(env.pal.solar, eg), ramp(env.pal.anti, e), smoothstep(cfg.arch[2], cfg.arch[3], Math.abs(dx)));
  }

  function drawBankTrees(state, G, P, cam, dark, env, alpha) {
    const cfg = G.cfg;
    if (!cfg.bankTrees.length) return;
    const fi = cfg.hills.findIndex((h) => h.floor);
    const plane = cam.hills[fi];
    const sn = env.sn, lab = env.inks;
    const css = (c, a) => rgba(labRgb(hushed(c, P, dark, env.hushK, 0.3)), a);
    over.globalAlpha = alpha;
    over.lineCap = 'round';
    cfg.bankTrees.forEach(([Y, bank, clear, size], i) => {
      const r = riverAt(cfg, Y);
      if (!r) return;
      const wx = r.x + bank * (r.hw + clear), wy = cfg.horizon + Y;
      const x = wx + plane.x, y = wy + plane.y;
      if (x < -20 || x > G.width + 20 || y < -10 || y > G.height + 30) return;
      // hidden by nearer land?
      for (let j = fi + 1; j < cfg.hills.length; j += 1) {
        const top = crestAt(cfg, j, wx - (cam.hills[j].x - plane.x)) + (cam.hills[j].y - plane.y);
        const foot = cfg.hills[j].foot ? cfg.horizon + cfg.hills[j].foot + (cam.hills[j].y - plane.y) : Infinity;
        if (wy > top + 1 && wy < foot - 6) return;
      }
      const h = (2.6 + 0.074 * Y) * size;
      // how far it has gone into the valley's air
      const X = wx / G.phone.width;
      const air = mix3(skyLab(env, cfg, X, 0.012), skyLab(env, cfg, X, 0.27), 0.55);
      const haze = [air[0], air[1] * 0.8, Math.min(air[2] * 0.8, air[2] * 0.2 + 0.002)];
      const far = clamp01(0.94 - Y / 430);
      const inAir = (c) => mix3(c, haze, far);
      const tall = hash(i, 201) < 0.42;                         // a poplar; the others are round-headed
      const rx = h * (tall ? 0.2 : 0.36), ry = h * (tall ? 0.42 : 0.33), cy = y - h * (tall ? 0.56 : 0.62);
      over.strokeStyle = css(inAir(lab.wood), 1);
      over.lineWidth = Math.max(0.5, h * 0.07);
      over.beginPath(); over.moveTo(x, y + 0.4); over.lineTo(x + h * 0.03, y - h * 0.5); over.stroke();
      const leafy = sn.foliage > 0.25, flower = sn.blossom > 0.25;
      if (leafy || flower) {
        const shade = flower && !leafy ? lab.blossomShade : lab.leafShade, body = flower && sn.blossom > sn.foliage ? lab.blossom : lab.leaf;
        over.fillStyle = css(inAir(shade), 1);
        over.beginPath(); over.ellipse(x, cy, rx, ry, 0, 0, TAU); over.fill();
        over.fillStyle = css(inAir(body), 0.9);
        const side = env.light.x > wx ? 1 : -1;
        over.beginPath(); over.ellipse(x + side * rx * 0.22, cy - ry * 0.14, rx * 0.72, ry * 0.76, 0, 0, TAU); over.fill();
        if (h > 9) {
          over.fillStyle = css(inAir(lab.leafLit), 0.75);
          over.beginPath(); over.ellipse(x + side * rx * 0.46, cy - ry * 0.3, rx * 0.34, ry * 0.4, 0, 0, TAU); over.fill();
        }
      } else {
        // bare: a few limbs, and the haze of its twigs
        over.fillStyle = css(inAir(lab.wood), 0.13);
        over.beginPath(); over.ellipse(x, cy - ry * 0.1, rx * 1.1, ry, 0, 0, TAU); over.fill();
        over.lineWidth = Math.max(0.4, h * 0.035);
        const limbs = h > 10 ? 7 : h > 5 ? 5 : 3;
        for (let k = 0; k < limbs; k += 1) {
          const a = -Math.PI / 2 + ((k + 0.5) / limbs - 0.5) * (tall ? 1.0 : 1.9) + (hash(i * 9 + k, 202) - 0.5) * 0.3;
          const len = h * (0.36 + 0.2 * hash(i * 9 + k, 203));
          const bx = x + h * 0.02, by = y - h * (0.34 + 0.16 * hash(i * 9 + k, 204));
          over.beginPath(); over.moveTo(bx, by);
          over.quadraticCurveTo(bx + Math.cos(a) * len * 0.5, by + Math.sin(a) * len * 0.35, bx + Math.cos(a) * len * 0.9, by + Math.sin(a) * len);
          over.stroke();
        }
        if (sn.snow > 0.3 && h > 6) {
          over.strokeStyle = css(inAir(lab.snow), 0.85);
          over.lineWidth = Math.max(0.5, h * 0.05);
          over.beginPath(); over.ellipse(x, cy, rx * 0.8, ry * 0.8, 0, Math.PI * 1.15, Math.PI * 1.85); over.stroke();
        }
      }
    });
    over.globalAlpha = 1;
  }

  // ── tonight's star ──

  function drawTonight(state, G, cam, t, dark, alpha) {
    const cfg = G.cfg;
    const bedtime = state.event && state.event.kind === 'bedtime' ? state.event.age : null;
    const x = cfg.tree.x + cfg.tonight.dx + cam.tree.x, y = G.treeFoot + cfg.tonight.dy + cam.tree.y;
    const a = ignition(bedtime) * (t == null ? 0.92 : 0.8 + 0.2 * Math.cos((TAU * t) / 5.2));
    if (!(a > 0.004)) return;
    const k = Math.min(a, 1.35);
    const scale = G.slab ? 0.86 : 1;
    over.globalAlpha = alpha;
    if (!dark) {
      // On a light page a star needs a breath of its own dusk behind it.
      const shade = over.createRadialGradient(x, y, 0, x, y, 20 * scale);
      shade.addColorStop(0, `rgba(96,90,146,${0.34 * Math.min(k, 1)})`);
      shade.addColorStop(0.45, `rgba(96,90,146,${0.15 * Math.min(k, 1)})`);
      shade.addColorStop(1, 'rgba(96,90,146,0)');
      over.fillStyle = shade;
      over.beginPath(); over.arc(x, y, 20 * scale, 0, TAU); over.fill();
    }
    const cream = dark ? [255, 234, 204] : [255, 251, 240];
    const R = 16 * scale * (0.7 + 0.3 * k);
    const halo = over.createRadialGradient(x, y, 0, x, y, R);
    halo.addColorStop(0, rgba(cream, (dark ? 0.4 : 0.85) * Math.min(1, k)));
    halo.addColorStop(0.16, rgba(cream, (dark ? 0.15 : 0.42) * Math.min(1, k)));
    halo.addColorStop(0.5, rgba(cream, (dark ? 0.035 : 0.1) * Math.min(1, k)));
    halo.addColorStop(1, rgba(cream, 0));
    over.fillStyle = halo;
    over.beginPath(); over.arc(x, y, R, 0, TAU); over.fill();
    // A fine four-point glint.
    over.fillStyle = rgba(dark ? [255, 243, 224] : [255, 255, 255], Math.min(1, 0.9 * k));
    const len = 10 * scale * (0.5 + 0.5 * k);
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
    over.beginPath(); over.arc(x, y, (1.8 + 0.5 * Math.max(0, k - 1)) * scale, 0, TAU); over.fill();
    over.globalAlpha = 1;
  }

  // ── the small life of the season ──

  function drawLife(state, G, cam, t, dark, env, snowfall, alpha) {
    const cfg = G.cfg, sn = env.sn;
    const time = t ?? 0;
    const sunDeg = env.sunDeg;
    const tree = cfg.tree;
    const tx = cam.tree.x, ty = cam.tree.y;
    over.globalAlpha = alpha;

    // Leaves letting go in autumn, petals in spring: a few, slowly, and some lying under the tree.
    const falling = Math.max(sn.leafFall * (0.3 + 0.7 * sn.foliage), sn.petals * 0.8);
    if (falling > 0.03) {
      const petals = sn.petals * 0.8 > sn.leafFall * (0.3 + 0.7 * sn.foliage);
      const c = petals ? env.petalRgb : env.leafRgb;
      const lying = Math.max(3, Math.round(16 * falling));
      over.fillStyle = rgba(c, dark ? 0.75 : 0.9);
      for (let i = 0; i < lying; i += 1) {
        const x = tree.x + (hash(i, 101) - 0.45) * tree.h * 1.1;
        const y = crestAt(cfg, tree.hill, x) + 1.5 + Math.pow(hash(i, 102), 1.5) * 11;
        over.beginPath();
        over.ellipse(x + tx, y + ty, 0.9 + 0.5 * hash(i, 103), 0.55, hash(i, 104) * 3, 0, TAU);
        over.fill();
      }
      const adrift = Math.round(5 * falling);
      for (let i = 0; i < adrift; i += 1) {
        const period = 30 + 16 * hash(i, 105);
        const f = t == null ? hash(i, 106) : (((time / period + hash(i, 106)) % 1) + 1) % 1;
        const x = tree.x + (hash(i, 107) - 0.5) * tree.h * 0.7 + Math.sin(f * 9 + i) * 5 + f * 8;
        const y = G.treeFoot - tree.h * 0.66 + f * tree.h * 0.7;
        over.fillStyle = rgba(c, Math.sin(Math.PI * f) * (dark ? 0.8 : 0.95));
        over.beginPath();
        over.ellipse(x + tx, y + ty, 1.15, 0.7, f * 7 + i, 0, TAU);
        over.fill();
      }
    }

    // Fireflies beneath the tree and over the near land, from dusk into the night.
    const dusk = smoothstep(4, -3, sunDeg) * (1 - 0.55 * smoothstep(-14, -30, sunDeg));
    const flies = sn.fireflies * dusk;
    if (flies > 0.02) {
      const worldLeft = -G.phone.x;
      const count = Math.round(16 + 20 * (G.width / 466));
      for (let i = 0; i < count; i += 1) {
        let x0, y0, depth = hash(i, 42), plane = cam.tree;
        if (i < 11) {
          x0 = tree.x - 34 + hash(i, 41) * 86;
          y0 = i < 4 ? G.treeFoot - 4 - hash(i, 47) * tree.h * 0.3 : crestAt(cfg, tree.hill, x0) + 3 + hash(i, 47) * 38;
          depth = 0.6;
        } else {
          x0 = worldLeft + hash(i, 41) * G.width;
          const hi = cfg.hills.length - 1 - (i % 3);
          y0 = crestAt(cfg, hi, x0) + 8 + 60 * Math.pow(depth, 1.2);
          plane = cam.hills[hi];
        }
        const wander = 4 + 7 * depth;
        const ph = hash(i, 43) * TAU;
        const x = x0 + plane.x + wander * Math.sin(time * (0.11 + 0.1 * hash(i, 44)) + ph);
        const y = y0 + plane.y + wander * 0.6 * Math.sin(time * (0.09 + 0.08 * hash(i, 45)) + ph * 1.7);
        const period = 3.2 + 3.6 * hash(i, 46);
        const blink = t == null ? (hash(i, 48) < 0.6 ? 0.6 : 0) : Math.pow(0.5 + 0.5 * Math.sin((time / period) * TAU + ph * 2.3), 3);
        const a = flies * blink * (0.5 + 0.5 * depth);
        if (!(a > 0.03)) continue;
        const r = 0.7 + 0.7 * depth;
        const c = dark ? [226, 240, 150] : [248, 252, 190];
        const g = over.createRadialGradient(x, y, 0, x, y, r * 5.5);
        g.addColorStop(0, rgba(c, (dark ? 0.5 : 0.7) * a));
        g.addColorStop(0.3, rgba(c, (dark ? 0.14 : 0.3) * a));
        g.addColorStop(1, rgba(c, 0));
        over.fillStyle = g;
        over.beginPath(); over.arc(x, y, r * 5.5, 0, TAU); over.fill();
        over.fillStyle = rgba(dark ? [244, 250, 190] : [255, 255, 226], Math.min(1, 1.1 * a));
        over.beginPath(); over.arc(x, y, r, 0, TAU); over.fill();
      }
    }

    // Snow in the air: a few slow flakes, three depths.
    if (snowfall > 0) {
      const count = Math.round(state.width * state.height / 7600 * snowfall);
      for (let i = 0; i < count; i += 1) {
        const depth = hash(i, 51);
        const speed = 7 + 16 * depth;
        const span = state.height + 40;
        const x0 = hash(i, 52) * (state.width + 60) - 30;
        const y = ((hash(i, 53) * span + time * speed + cam.sky.y * (0.3 + 0.7 * depth)) % span + span) % span - 20;
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
        over.beginPath(); over.arc(xx, y, r * 1.8, 0, TAU); over.fill();
      }
    }
    over.globalAlpha = 1;
  }

  // ── the page's one line: "✦ Night 143", while the sky has the display ──

  function drawCaption(state, G, look, dark) {
    if (state.asleep !== 'night' || !(state.veil > 0.01)) return;
    const bed = state.event && state.event.kind === 'bedtime' ? state.event.age : null;
    const arrive = bed == null ? 1 : smoothstep(1.9, 3.0, bed) * (1 - smoothstep(5.0, 5.7, bed));
    const a = clamp01(state.veil) * clamp01(state.veil) * arrive * smoothstep(0.5, 1, look);
    if (!(a > 0.01)) return;
    const size = G.slab ? 15 : 15.5;
    const x = G.phone.x + (G.slab ? 30 : 30), y = G.height - G.cfg.captionFoot;
    const c = dark ? [246, 232, 210] : [70, 66, 96];
    over.save();
    over.globalAlpha = a * (dark ? 0.8 : 0.82);
    over.fillStyle = rgb(c);
    // his four-point star, before the words
    const gx = x + 5, gy = y - size * 0.34, len = size * 0.46;
    for (let q = 0; q < 2; q += 1) {
      const dx = q === 0 ? len : 0.8, dy = q === 0 ? 0.8 : len * 1.1;
      over.beginPath();
      over.moveTo(gx - dx, gy);
      over.quadraticCurveTo(gx, gy, gx, gy - dy);
      over.quadraticCurveTo(gx, gy, gx + dx, gy);
      over.quadraticCurveTo(gx, gy, gx, gy + dy);
      over.quadraticCurveTo(gx, gy, gx - dx, gy);
      over.fill();
    }
    over.font = `600 ${size}px "Nunito", ui-rounded, system-ui, sans-serif`;
    try { over.letterSpacing = '0.2px'; } catch { /* older canvases */ }
    over.textBaseline = 'alphabetic';
    over.textAlign = 'left';
    over.fillText(`Night ${Math.max(1, Math.floor(state.ageDays) + 1)}`, x + 17, y);
    over.restore();
  }

  // ── a frame ──

  function render(state) {
    if (destroyed || !state || !state.sun) return;
    lastState = state;
    const s = Number.isFinite(state.dpr) && state.dpr > 0 ? state.dpr : 1;
    const pxW = Math.ceil(state.width * s - 1e-6), pxH = Math.ceil(state.height * s - 1e-6);
    const G = geometry(state);
    const cfg = G.cfg;
    const dark = state.scheme === 'dark';
    const P = presence(state);
    const still = state.reduceMotion || !Number.isFinite(state.t);
    // Slow motion needs no more than twelve frames a second.
    const t = still ? null : Math.round(state.t * 12) / 12;
    const tilt = state.tilt ?? { x: 0, y: 0 };
    const look = lookOf(state);
    const lit = state.tonightLit ?? state.asleep === 'night';

    const key = [state.device, pxW, pxH, s, G.phone.x, G.phone.width, state.scheme, +state.date, state.tzOffsetHours,
      state.latitude, state.longitude, state.asleep, state.ageDays, t, tilt.x, tilt.y, lit, look.k, look.move,
      state.event ? `${state.event.kind}:${state.event.age}` : '', state.veil ?? '', state.snowfall ?? '',
      JSON.stringify(G.L)].join('|');
    if (key === lastKey) return;
    const started = performance.now();

    for (const c of [glCanvas, overCanvas]) {
      if (c.width !== pxW || c.height !== pxH) { c.width = pxW; c.height = pxH; }
      const cw = `${pxW / s}px`, ch = `${pxH / s}px`;
      if (c.style.width !== cw) c.style.width = cw;
      if (c.style.height !== ch) c.style.height = ch;
    }

    const sunDeg = state.sun.altitude * DEG;
    const morning = state.sun.isNight ? state.sun.progress > 0.5 : state.sun.progress < 0.5;
    const pal = palette(sunDeg, dark, morning);
    const sn = seasonOf(state);
    const snowfall = sn.snowfall ?? 0;
    const W = G.phone.width;
    const hor = cfg.horizon;

    // The sun: by the clock across the anchor window, by its real altitude above the horizon.
    const sunU = clamp(state.sun.x ?? (0.04 + 0.92 * state.sun.progress), -0.25, 1.25);
    const sunB = bodyAt(cfg, sunDeg);
    const sun = { x: sunU * W, y: hor - sunB.h, r: cfg.sunR };
    const sunUp = smoothstep(-2.2, -0.2, sunDeg);

    // The moon, the same way.
    const m = state.moon;
    const moonDeg = m ? m.altitude * DEG : -90;
    const moonB = m ? bodyAt(cfg, moonDeg) : null;
    const moon = m ? { x: m.x * W, y: hor - moonB.h, r: cfg.moonR } : null;
    const moonUp = m ? smoothstep(-1.5, 2.5, moonDeg) : 0;
    const nightness = 1 - smoothstep(-13, -8, sunDeg);
    const moonlight = m ? moonUp * (0.2 + 0.8 * m.fraction) * nightness : 0;
    const moonVisBase = m ? (0.42 + 0.58 * (1 - smoothstep(-8, 3, sunDeg))) * smoothstep(-1.5, 0.5, moonDeg) * lerp(smoothstep(0.04, 0.2, m.fraction), 1, nightness) : 0;

    // Clouds are lit by the sun until it is well down, then by the moon.
    const byMoon = sunDeg < -9.5;
    const light = byMoon && moon ? { x: moon.x, y: moon.y } : { x: sun.x, y: Math.min(sun.y, hor + 40) };
    const silver = print(KEYS[KEYS.length - 1], dark, [dark ? 1.55 : 1.9, 0.045, 255]);
    const lastLight = smoothstep(-7, -1, sunDeg);
    const day = smoothstep(-2, 16, sunDeg);
    const land = seasonLand(sn);
    const litLand = (alb, keep = 0.2) => {
      // An albedo in this hour's light, in this print.
      const L = pal.land[0] + (alb[0] - 0.47) * pal.gain;
      const base = lch(L, alb[1] * (dark ? 0.6 : 0.62) * (keep + (1 - keep) * day), alb[2]);
      return [base[0], base[1] + pal.land[1] * 0.8, base[2] + pal.land[2] * 0.8];
    };
    const snowLitBase = (() => { const q = litLand(land.snow); return [q[0] + (dark ? 0.07 * smoothstep(-12, 0, sunDeg) : 0.02), q[1], q[2]]; })();
    const snowLit = mix3(snowLitBase, pal.rim, 0.25 * pal.rimAmt);
    const lightLab = byMoon ? silver : pal.rim;
    const lightAmt = byMoon ? 0.5 * moonlight : clamp01(pal.rimAmt * 1.3 + 0.25 * day);
    const cloudNight = 1 - 0.86 * (1 - smoothstep(-12, -5, sunDeg));
    const sunCol = sunDisc(sunDeg, dark);

    // The words the sky must stay quiet behind (screen points).
    const words = [];
    const na = union(grow(G.L.name, 12, 7), grow(G.L.age, 12, 6));
    words.push({ x0: na.x0 + G.phone.x, y0: na.y0, x1: na.x1 + G.phone.x, y1: na.y1 });
    if (G.L.title) words.push(union(grow(G.L.title, 12, 7), G.L.subtitle ? grow(G.L.subtitle, 12, 6) : null));

    // The hush, shaped by the hour: by day today's rule (a fifth of the colour, most of the way to
    // the page); at night the light appearance keeps its lilac and its depth — a night on pale paper.
    const deepNight = 1 - smoothstep(-15, -7, sunDeg);
    const hushK = dark ? [0.12, 0.4] : [0.55 * (1 - 0.72 * deepNight), 0.2 + 0.5 * deepNight];
    const env = { pal, sn, land, sunDeg, lastLight, light, lightLab, lightAmt, snowLit, cloudAmt: cloudNight, sunLab: sunCol, hushK, sunXn: sunU,
      petalRgb: labRgb(hushed(dark ? lch(pal.land[0] + 0.3 + 0.2 * day, 0.03, 352) : lch(0.97, 0.03, 352), P, dark, hushK)),
      leafRgb: labRgb(hushed(dark ? lch(pal.land[0] + 0.16 + 0.12 * day + 0.12 * lastLight, 0.08, 55) : lch(0.7, 0.11, 58), P, dark, hushK, 0.3)) };
    env.inks = treeInks(G, dark, env);

    /** One pose of the camera, drawn at `alpha` over whatever is there. */
    const drawPose = (k, alpha, first) => {
      const cam = camera(state, G, k);
      // Sun and moon: the discs fade where they would stand behind the header's words.
      const chrome = [grow(G.L.name, 2), grow(G.L.age, 2)].map((q) => ({ x0: q.x0 + G.phone.x, y0: q.y0, x1: q.x1 + G.phone.x, y1: q.y1 }));
      if (G.L.title) chrome.push(grow(G.L.title, 2));
      if (G.L.subtitle) chrome.push(grow(G.L.subtitle, 2));
      if (G.slab) chrome.push({ x0: 0, y0: 0, x1: G.width, y1: 60 });
      const sunShow = sunUp * sunB.show * clearOf(chrome, sun.x + cam.sky.x, sun.y + cam.sky.y, sun.r);
      const moonShow = moon ? moonVisBase * moonB.show * clearOf(chrome, moon.x + cam.sky.x, moon.y + cam.sky.y, moon.r) : 0;

      if (gl) {
        gl.viewport(0, 0, pxW, pxH);
        gl.useProgram(program);
        if (first) gl.disable(gl.BLEND);
        else { gl.enable(gl.BLEND); gl.blendColor(0, 0, 0, alpha); gl.blendFunc(gl.CONSTANT_ALPHA, gl.ONE_MINUS_CONSTANT_ALPHA); }
        gl.uniform2f(U.uPx, pxW, pxH);
        gl.uniform1f(U.uDpr, s);
        set4('uGeo', G.phone.x, W, hor, (hor + cfg.rise) / hor);
        gl.uniform2f(U.uCam, cam.sky.x - G.phone.x, cam.sky.y);
        gl.uniform3fv(U.uSolar, pal.solar);
        gl.uniform3fv(U.uAnti, pal.anti);
        gl.uniform2f(U.uZen, dark ? 0.2 : 0, dark ? 0.1 : -0.18);
        set4('uSun', sun.x, sun.y, sun.r, sunShow);
        set3('uSunCol', sunCol);
        // By day the dark appearance keeps the sun's aureole close: nothing but the disc outshines a card.
        set4('uGlow', pal.glow[0], pal.glow[1], pal.glow[2], pal.glowAmt * (dark ? 0.4 + 0.6 * smoothstep(15, 5, sunDeg) : 1));
        set4('uArch', ...cfg.arch);
        set4('uMoon', moon ? moon.x : 0, moon ? moon.y : 0, cfg.moonR, moonShow);
        const moonLow = m ? 1 - smoothstep(2, 14, moonDeg) : 0;
        const moonCol = dark ? lch(0.92 - 0.06 * moonLow, 0.028 + 0.028 * moonLow, 85 - 8 * moonLow) : lch(0.992 - 0.02 * moonLow, 0.014 + 0.03 * moonLow, 85 - 15 * moonLow);
        set4('uMoonB', m ? m.fraction : 0, m ? m.rotation : 0, 0.42 * moonlight * (dark ? 0.26 - 0.06 * moonLow : 0.8), dark ? 0.07 : 0.2);
        set3('uMoonCol', moonCol);

        const cloudLit = byMoon ? 0.9 * moonlight : lerp(pal.loAmt, 1, 0.35 * smoothstep(-6, 2, sunDeg));
        set4('uLight', light.x, light.y, cloudLit, byMoon ? 0.8 * moonlight * moonUp : smoothstep(-3, 2, sunDeg) * (1 - 0.6 * day));
        set3('uLightCol', byMoon ? mix3(silver, moonCol, 0.35) : mix3(pal.glow, sunCol, 0.35));
        gl.uniform1f(U.uLightV, -Math.sin(((byMoon ? moonDeg : sunDeg) - 9) / DEG) * 1.6);
        set3('uCLit', byMoon ? silver : pal.loLit);
        set3('uCShade', dark ? pal.loShade : mix3(pal.loShade, byMoon ? silver : pal.loLit, 0.4));
        // Away from the sun the lit side goes to the Belt's pink, and quieter.
        set3('uCFar', byMoon ? silver : mix3(pal.loLit, mix3(pal.loShade, lch(pal.loLit[0] - 0.03, 0.05, 350), 0.6), 0.75));
        const blobs = new Float32Array(N_CLOUD * N_BLOB * 4);
        for (let c = 0; c < N_CLOUD; c += 1) {
          const cloud = cfg.clouds[c];
          if (!cloud) { gl.uniform4f(gl.getUniformLocation(program, `uCloudQ[${c}]`), 0, 0, 0, 0); continue; }
          const at = cloudNow(cloud, t);
          let hw = 0, hh = 0;
          cloud.blobs.forEach(([dx, dy, rx, ry], b) => {
            blobs.set([at.x + dx, at.y + dy, rx, ry], (c * N_BLOB + b) * 4);
            hw = Math.max(hw, Math.abs(dx) + rx * 1.7);
            hh = Math.max(hh, Math.abs(dy) + ry * 1.7);
          });
          gl.uniform4f(gl.getUniformLocation(program, `uCloud[${c}]`), at.x, at.y, hw + 3, hh + 3);
          gl.uniform4f(gl.getUniformLocation(program, `uCloudQ[${c}]`), at.y + cloud.foot, 0.94 * at.alpha * cloudNight, 3.7 + c * 11.3, 0);
        }
        gl.uniform4fv(U.uBlob, blobs);

        // The land.
        const bumps = new Float32Array(N_HILL * N_BUMP * 4);
        for (let i = 0; i < N_HILL; i += 1) {
          const h = cfg.hills[i];
          const at = (name) => gl.getUniformLocation(program, `${name}[${i}]`);
          if (!h) { gl.uniform4f(at('uHillA'), 9999, 0, 1, 0); continue; }
          gl.uniform4f(at('uHillA'), h.base, h.haze, h.soft, h.depth);
          gl.uniform4f(at('uHillB'), h.side ? h.side[0] : 0, h.side ? h.side[1] : 1, h.side ? h.side[2] : 0, h.floor ? 1 : 0);
          gl.uniform4f(at('uHillC'), cam.hills[i].x, cam.hills[i].y, h.wob[0], h.wob[1]);
          gl.uniform4f(at('uHillM'), h.mist ? h.mist[0] : 0, h.mist ? h.mist[1] : 1, h.mist ? h.mist[2] : 0, h.fade);
          gl.uniform4f(at('uHillW'), h.woods ? h.woods[0] : 0, h.woods ? h.woods[1] : 0, h.woods ? h.woods[2] : 0, h.foot);
          h.bumps.forEach((b, j) => bumps.set(b, (i * N_BUMP + j) * 4));
        }
        gl.uniform4fv(U.uBump, bumps);
        const river = riverCache ?? (riverCache = { cfg, ...riverTable(cfg) });
        if (river.cfg !== cfg) riverCache = { cfg, ...riverTable(cfg) };
        gl.uniform2fv(U.uRiver, riverCache.table);
        set4('uRiverQ', riverCache.y0, riverCache.y1, riverCache.on, (t ?? 0) * 0.35);
        // Opening the Duo: the light reaches the valley's mist from the fold outward.
        let openAmt = 0, openFront = -1e4;
        if (state.event && state.event.kind === 'open' && !state.reduceMotion) {
          const age = state.event.age;
          openAmt = 0.62 * (1 - smoothstep(1.0, 1.7, age));
          openFront = 10 - 520 * smoothstep(0, 1.25, age);
        }
        set4('uOpen', openFront, 70, openAmt, 0);
        gl.uniform1f(U.uRoom, dark ? 0.25 + 0.75 * smoothstep(-11.5, -5, sunDeg) : 1);

        set3('uLand', litLand(land.ground, 0.2 + 0.25 * sn.grass));
        set3('uWoods', litLand(land.woods, 0.4));
        // The canopy's top in the last light: the season's colour at full strength, lifted.
        const lift = dark ? 0.03 + 0.15 * lastLight * (1 - 0.5 * day) : -0.02;
        const wl = lch(pal.land[0] + (land.woods[0] - 0.47) * pal.gain + lift, land.woods[1] * 0.8, land.woods[2]);
        set4('uWoodsLit', wl[0], wl[1], wl[2], 0.25 + 0.75 * lastLight);
        set3('uBloom', litLand(land.blossom, 0.6));
        set3('uSnowLit', snowLit);
        set3('uSnowShade', [snowLitBase[0] - (dark ? 0.035 : 0.05), snowLitBase[1] + 0.012 * Math.cos(262 / DEG), snowLitBase[2] + 0.02 * Math.sin(262 / DEG)]);
        set4('uSeason', sn.snow, sn.frost, 0.6 + 0.4 * sn.foliage, sn.blossom);
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
        gl.uniform2f(U.uHushK, hushK[0], hushK[1]);
        set4('uTime', 0.004 * (t ?? 0), dark ? 0.0052 : 0.004, 0, 0);
        for (let r = 0; r < 3; r += 1) {
          const q = words[r];
          gl.uniform4f(gl.getUniformLocation(program, `uText[${r}]`), q ? q.x0 : 0, q ? q.y0 : 0, q ? q.x1 : 0, q ? q.y1 : 0);
        }
        gl.uniform2f(U.uLimit, dark ? 0.385 : 0.845, 70);
        gl.drawArrays(gl.TRIANGLES, 0, 3);
      }

      // What the canvas draws, in the same camera.
      over.setTransform(s, 0, 0, s, 0, 0);
      const poseEnv = { ...env, sun: sunShow > 0.02 ? sun : null, sunShow, moon: moonShow > 0.05 ? moon : null };
      drawStars(state, G, P, cam, t, s, dark, lit, poseEnv, alpha);
      drawBankTrees(state, G, P, cam, dark, poseEnv, alpha);
      drawTree(state, G, P, cam, s, dark, { ...poseEnv, sun }, alpha);
      drawLife(state, G, cam, t, dark, poseEnv, snowfall, alpha);
      if (lit) drawTonight(state, G, cam, t, dark, alpha);
    };

    over.setTransform(1, 0, 0, 1, 0, 0);
    over.clearRect(0, 0, pxW, pxH);
    if (look.move || look.k <= 0.001 || look.k >= 0.999) {
      drawPose(look.k, 1, true);
    } else {
      // Reduce Motion: no move — the looked-up still fades in over the rest view, and out again.
      drawPose(0, 1 - look.k, true);
      drawPose(1, look.k, false);
      if (gl) gl.disable(gl.BLEND);
    }
    over.setTransform(s, 0, 0, s, 0, 0);
    drawCaption(state, G, look.k, dark);

    lastKey = key;
    // (for timing only: a read-back makes the GL work finish before the clock is read)
    if (gl && globalThis.__hillLitFinish) gl.readPixels(0, 0, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array(4));
    const took = performance.now() - started;
    if (timing.first == null) timing.first = took;
    timing.last = took;
    timing.frames += 1;
    if (typeof window !== 'undefined') window.__hillLit = timing;
  }
  let riverCache = null;

  function destroy() {
    destroyed = true;
    if (gl) {
      const lose = gl.getExtension('WEBGL_lose_context');
      if (lose) lose.loseContext();
    }
    glCanvas.remove();
    overCanvas.remove();
  }

  // The caption's face (the lab's stand-in for SF Rounded) may still be on its way.
  const ready = doc.fonts && doc.fonts.load
    ? doc.fonts.load('600 16px Nunito').then(() => { if (!destroyed && lastState) { lastKey = ''; render(lastState); } }, () => {})
    : Promise.resolve();

  return { render, destroy, ready };
}
