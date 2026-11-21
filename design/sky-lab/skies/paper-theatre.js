// Paper theatre — a little lit stage of cut and torn paper.
//
// The sky is a stack of paper sheets with air between them, and the sun or the
// moon is a lamp BEHIND the stack:
//
//   sheet     the back sheet. The sun is a round hole cut in it, the moon a
//             hole in the shape of tonight's phase, his stars are pin-pricks —
//             one more pricked each night — and the lamp shines through all of
//             them and soaks into the paper around the hole.
//   clouds    three depths of long torn strips, sliding on their tracks.
//   ridges    eight flats, torn (far, soft) to knife-cut (near, crisp). The far
//             ones are thin enough to glow where the lamp is behind them.
//   tree      on the leading page's margin: a cut trunk, leaves as loose scraps.
//   scraps    paper snow, petals, leaves in the air; fireflies as warm pricks.
//
// Two lights. The lamp behind (the real sun or moon, where it really is): it
// glows through the sheet, lights each flat from peach beside it to mauve and
// slate away from it, shows through the far flats, and rims every edge that
// stands in front of it. And the room in front, soft and from below like a
// footlight: it gives each flat its paper colour, the lighter cut face along
// its edge and the soft shadow it throws on the flat behind. By day the room
// wins (white-on-white relief), at the bloom the lamp wins.
//
// How a frame is made (all 2-D canvas; see paper-theatre.md for the SwiftUI port):
//   · every flat is a Path2D in display points, built once per display/season;
//   · its colour is a small OKLab field (a quarter-resolution image computed in
//     JS: its own paper by depth and season, the lamp's falloff, a lift toward
//     its foot) drawn through the path's clip; then the lamp's disc showing
//     through, the rim light (a blurred, clipped stroke), the cut or torn
//     face, the fibre — and under it its shadow (blurred once per shape at
//     half size, tinted per light). Each flat is cached as its own bitmap
//     until the light changes;
//   · a frame is: sheet, stars, clouds, the flats stacked (two cached sheets;
//     translated by tilt — parallax — or sheared about the fold while the Duo
//     opens), scraps; then, where the cards stand, a soft veil so no crisp
//     edge crosses a card border.
//
// Palettes are written at full strength and quietened with the lab's hush
// (lab/oklab.js); presence(state) (lab/presence.js) says how far the sky is
// open; nights() places his stars; season() turns the land.

import { presence as presenceOf } from '../lab/presence.js';
import { toOklab, HUSH, DARK_HUSH, smoothstep, lerp } from '../lab/oklab.js';
import { nights, twinkle, ignition, hash } from '../lab/nights.js';
import { season as seasonOf } from '../lab/season.js';
import { rng, fbm1, fbm2 } from '../lab/noise.js';

export const meta = {
  id: 'paper-theatre',
  name: 'Paper theatre',
  blurb: 'A lit stage of cut and torn paper: the sun or moon is a lamp behind the layers, his stars are pin-pricks in the back sheet.',
};

// ───────────────────────────────────────────────────────────── numbers ──

const TAU = Math.PI * 2;
const DEG = 180 / Math.PI;
const clamp01 = (x) => Math.min(1, Math.max(0, x));
const clamp = (x, lo, hi) => Math.min(hi, Math.max(lo, x));
const easeOut = (x) => 1 - Math.pow(1 - clamp01(x), 3);

/** How far every flat runs past the display, so tilt and the pop-up never show an end. */
const PAD = 40;
/** The field's cell, in points: colour is computed this coarsely and interpolated. */
const CELL = 4;
/** Parallax: how far the nearest flat travels at full tilt, in points. */
const PARALLAX = { x: 15, y: 8 };

// ─────────────────────────────────────────────────────────────── colour ──
// Everything is OKLab { L, a, b }; K(L, C, hue°) writes it as OKLCH.

const K = (L, C, h) => ({ L, a: C * Math.cos(h / DEG), b: C * Math.sin(h / DEG) });
const PAGE_L = toOklab({ r: 0xf2 / 255, g: 0xf2 / 255, b: 0xf7 / 255 }).L;

function labToRgb(L, a, b, out) {
  const l_ = L + 0.3963377774 * a + 0.2158037573 * b;
  const m_ = L - 0.1055613458 * a - 0.0638541728 * b;
  const s_ = L - 0.0894841775 * a - 1.291485548 * b;
  const l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_;
  const r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s;
  const g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s;
  const bb = -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s;
  out[0] = gamma(r); out[1] = gamma(g); out[2] = gamma(bb);
  return out;
}
const gamma = (c) => {
  const v = c <= 0 ? 0 : c >= 1 ? 1 : c <= 0.0031308 ? 12.92 * c : 1.055 * Math.pow(c, 1 / 2.4) - 0.055;
  return v * 255;
};
const scratchRgb = [0, 0, 0];
function cssLab(c, alpha = 1) {
  labToRgb(c.L, c.a, c.b, scratchRgb);
  return `rgba(${Math.round(scratchRgb[0])}, ${Math.round(scratchRgb[1])}, ${Math.round(scratchRgb[2])}, ${alpha})`;
}
const mixLab = (A, B, t) => ({ L: A.L + (B.L - A.L) * t, a: A.a + (B.a - A.a) * t, b: A.b + (B.b - A.b) * t });
/** In place: o moves `w` of the way to c. */
function toward(o, c, w) { o.L += (c.L - o.L) * w; o.a += (c.a - o.a) * w; o.b += (c.b - o.b) * w; }

/** The lab's hush (lab/oklab.js `present` / `presentDark`), on OKLab directly:
 *  the same rule, so a palette can be quietened once and then mixed freely. */
function hush(c, p, dark, lift = 1) {
  if (dark) {
    const k = DARK_HUSH.chroma + (1 - DARK_HUSH.chroma) * p;
    return { L: c.L * (1 - DARK_HUSH.darken * (1 - p)), a: c.a * k, b: c.b * k };
  }
  const k = HUSH.chroma + (1 - HUSH.chroma) * p;
  return { L: c.L + (PAGE_L - c.L) * HUSH.toward * lift * (1 - p), a: c.a * k, b: c.b * k };
}

// The palettes, at full strength, by the sun's altitude. One set per appearance.
//   skyTop/skyLow   the back sheet away from the lamp, zenith and horizon
//   lampNear/Mid/Far  the sheet beside the lamp, a little out, further out
//   disc            the light in the hole
//   rim             the light that wraps the edges in front of the lamp
//   cloud/cloudShade/cloudLit   the torn strips: body, far side, lamp side
//   ridgeFar/Near   the flats' own paper, first to last
//   litFar/litNear  the same paper beside the lamp
//   haze            what a flat fades toward at its foot
//   shadow, shadowA the cast shadow's colour and strength
//   face            the cut face along an edge
const LIGHT = {
  // The light appearance: a dyed back sheet, and WHITE paper in front of it —
  // the land takes its colour from the lamp, never from pigment.
  day: {
    skyTop: K(0.80, 0.075, 248), skyLow: K(0.905, 0.04, 240),
    lampNear: K(0.985, 0.035, 95), lampMid: K(0.94, 0.04, 220), lampFar: K(0.90, 0.045, 240),
    disc: K(0.995, 0.02, 100), rim: K(0.995, 0.02, 95),
    cloud: K(0.975, 0.012, 250), cloudShade: K(0.89, 0.03, 255), cloudLit: K(0.99, 0.02, 95),
    ridgeFar: K(0.955, 0.012, 250), ridgeNear: K(0.90, 0.02, 265), litFar: K(0.975, 0.03, 90), litNear: K(0.94, 0.03, 80),
    haze: K(0.965, 0.01, 250), shadow: K(0.48, 0.06, 262), shadowA: 0.46, face: K(0.995, 0.006, 250),
  },
  gold: {
    skyTop: K(0.852, 0.055, 275), skyLow: K(0.90, 0.04, 350),
    lampNear: K(0.965, 0.085, 84), lampMid: K(0.925, 0.085, 62), lampFar: K(0.885, 0.068, 25),
    disc: K(0.995, 0.035, 95), rim: K(0.995, 0.05, 88),
    cloud: K(0.965, 0.025, 40), cloudShade: K(0.875, 0.045, 310), cloudLit: K(0.985, 0.06, 80),
    ridgeFar: K(0.94, 0.022, 330), ridgeNear: K(0.905, 0.03, 285), litFar: K(0.965, 0.065, 70), litNear: K(0.93, 0.06, 45),
    haze: K(0.95, 0.025, 350), shadow: K(0.50, 0.08, 295), shadowA: 0.44, face: K(0.99, 0.02, 60),
  },
  set: {
    skyTop: K(0.852, 0.056, 275), skyLow: K(0.885, 0.05, 340),
    lampNear: K(0.955, 0.095, 68), lampMid: K(0.90, 0.105, 40), lampFar: K(0.865, 0.08, 10),
    disc: K(0.99, 0.06, 85), rim: K(0.985, 0.08, 70),
    cloud: K(0.945, 0.035, 20), cloudShade: K(0.85, 0.055, 305), cloudLit: K(0.97, 0.08, 60),
    ridgeFar: K(0.93, 0.03, 320), ridgeNear: K(0.895, 0.035, 282), litFar: K(0.95, 0.085, 55), litNear: K(0.915, 0.07, 30),
    haze: K(0.94, 0.035, 335), shadow: K(0.49, 0.08, 290), shadowA: 0.44, face: K(0.98, 0.03, 40),
  },
  dusk: {
    skyTop: K(0.845, 0.055, 270), skyLow: K(0.875, 0.05, 300),
    lampNear: K(0.93, 0.10, 48), lampMid: K(0.885, 0.09, 15), lampFar: K(0.855, 0.07, 322),
    disc: K(0.97, 0.06, 60), rim: K(0.95, 0.06, 30),
    cloud: K(0.915, 0.03, 300), cloudShade: K(0.84, 0.045, 280), cloudLit: K(0.94, 0.055, 20),
    ridgeFar: K(0.915, 0.03, 288), ridgeNear: K(0.885, 0.035, 272), litFar: K(0.94, 0.075, 30), litNear: K(0.90, 0.06, 345),
    haze: K(0.925, 0.03, 290), shadow: K(0.48, 0.07, 275), shadowA: 0.44, face: K(0.96, 0.02, 300),
  },
  night: {
    skyTop: K(0.85, 0.066, 258), skyLow: K(0.885, 0.05, 256),
    lampNear: K(0.885, 0.05, 256), lampMid: K(0.885, 0.05, 256), lampFar: K(0.885, 0.05, 256),
    disc: K(0.97, 0.06, 60), rim: K(0.94, 0.03, 262),
    cloud: K(0.93, 0.02, 270), cloudShade: K(0.86, 0.035, 270), cloudLit: K(0.96, 0.02, 262),
    ridgeFar: K(0.93, 0.03, 262), ridgeNear: K(0.90, 0.04, 260), litFar: K(0.93, 0.03, 262), litNear: K(0.90, 0.04, 260),
    haze: K(0.94, 0.03, 260), shadow: K(0.47, 0.06, 268), shadowA: 0.44, face: K(0.975, 0.012, 260),
  },
};
const DARK = {
  // The dark appearance: black paper in a dark room, and the lamp behind it.
  day: {
    skyTop: K(0.27, 0.035, 262), skyLow: K(0.195, 0.03, 262),
    lampNear: K(0.44, 0.05, 75), lampMid: K(0.33, 0.04, 300), lampFar: K(0.28, 0.035, 270),
    disc: K(0.66, 0.06, 80), rim: K(0.62, 0.05, 80),
    cloud: K(0.31, 0.025, 262), cloudShade: K(0.22, 0.03, 265), cloudLit: K(0.42, 0.04, 80),
    ridgeFar: K(0.185, 0.03, 258), ridgeNear: K(0.125, 0.025, 262), litFar: K(0.27, 0.035, 70), litNear: K(0.17, 0.03, 60),
    haze: K(0.21, 0.03, 260), shadow: K(0.04, 0.02, 265), shadowA: 0.7, face: K(0.36, 0.03, 255),
  },
  gold: {
    skyTop: K(0.235, 0.05, 280), skyLow: K(0.275, 0.06, 335),
    lampNear: K(0.74, 0.14, 68), lampMid: K(0.47, 0.13, 38), lampFar: K(0.30, 0.085, 10),
    disc: K(0.95, 0.08, 88), rim: K(0.84, 0.13, 68),
    cloud: K(0.21, 0.045, 310), cloudShade: K(0.16, 0.04, 290), cloudLit: K(0.70, 0.13, 60),
    ridgeFar: K(0.215, 0.05, 312), ridgeNear: K(0.115, 0.03, 275), litFar: K(0.56, 0.13, 48), litNear: K(0.27, 0.085, 20),
    haze: K(0.25, 0.055, 320), shadow: K(0.03, 0.03, 300), shadowA: 0.7, face: K(0.42, 0.06, 320),
  },
  set: {
    skyTop: K(0.22, 0.055, 278), skyLow: K(0.26, 0.065, 330),
    lampNear: K(0.68, 0.15, 55), lampMid: K(0.42, 0.14, 28), lampFar: K(0.28, 0.09, 355),
    disc: K(0.90, 0.11, 75), rim: K(0.78, 0.15, 55),
    cloud: K(0.20, 0.05, 305), cloudShade: K(0.15, 0.04, 285), cloudLit: K(0.62, 0.14, 45),
    ridgeFar: K(0.20, 0.055, 305), ridgeNear: K(0.105, 0.03, 275), litFar: K(0.50, 0.14, 38), litNear: K(0.24, 0.09, 12),
    haze: K(0.235, 0.06, 315), shadow: K(0.03, 0.03, 290), shadowA: 0.7, face: K(0.38, 0.07, 310),
  },
  dusk: {
    skyTop: K(0.20, 0.055, 272), skyLow: K(0.23, 0.06, 300),
    lampNear: K(0.48, 0.13, 32), lampMid: K(0.35, 0.11, 358), lampFar: K(0.27, 0.08, 322),
    disc: K(0.60, 0.12, 40), rim: K(0.50, 0.11, 25),
    cloud: K(0.18, 0.045, 285), cloudShade: K(0.14, 0.04, 275), cloudLit: K(0.40, 0.10, 15),
    ridgeFar: K(0.18, 0.05, 290), ridgeNear: K(0.10, 0.03, 270), litFar: K(0.36, 0.11, 10), litNear: K(0.18, 0.07, 335),
    haze: K(0.21, 0.05, 290), shadow: K(0.03, 0.03, 275), shadowA: 0.7, face: K(0.31, 0.05, 290),
  },
  night: {
    skyTop: K(0.205, 0.045, 270), skyLow: K(0.19, 0.042, 266),
    lampNear: K(0.19, 0.042, 266), lampMid: K(0.19, 0.042, 266), lampFar: K(0.19, 0.042, 266),
    disc: K(0.60, 0.12, 40), rim: K(0.50, 0.03, 255),
    cloud: K(0.22, 0.03, 268), cloudShade: K(0.15, 0.035, 268), cloudLit: K(0.30, 0.03, 258),
    ridgeFar: K(0.15, 0.04, 266), ridgeNear: K(0.09, 0.03, 266), litFar: K(0.15, 0.04, 266), litNear: K(0.09, 0.03, 266),
    haze: K(0.18, 0.045, 262), shadow: K(0.02, 0.02, 266), shadowA: 0.72, face: K(0.25, 0.035, 260),
  },
};
// What does not turn with the sun: the moon's light, the far side of a
// twilight (the pink belt over the earth's blue shadow), snow, the tree.
const FIXED = {
  light: {
    moonNear: K(0.955, 0.02, 95), moonMid: K(0.90, 0.035, 270), moonLit: K(0.95, 0.02, 262), moonDisc: K(0.995, 0.015, 95),
    moonRim: K(0.99, 0.015, 250), belt: K(0.875, 0.05, 5), earth: K(0.82, 0.045, 262),
    snow: K(0.985, 0.008, 250), trunk: K(0.60, 0.035, 300), star: K(0.999, 0.012, 95), starWarm: K(0.985, 0.07, 80),
    ink: K(0.42, 0.05, 285),
  },
  dark: {
    moonNear: K(0.235, 0.035, 262), moonMid: K(0.205, 0.04, 266), moonLit: K(0.25, 0.035, 258), moonDisc: K(0.965, 0.03, 95),
    moonRim: K(0.60, 0.035, 250), belt: K(0.29, 0.065, 5), earth: K(0.185, 0.05, 255),
    snow: K(0.235, 0.02, 255), trunk: K(0.075, 0.02, 290), star: K(0.985, 0.02, 95), starWarm: K(0.93, 0.09, 78),
    ink: K(0.78, 0.04, 80),
  },
};
// The season's tint for the land (hue and chroma only — the lightness stays the paper's).
const SEASON_TINT = { winter: K(0.9, 0.03, 245), spring: K(0.8, 0.075, 128), summer: K(0.72, 0.068, 126), autumn: K(0.75, 0.066, 78) };

const ALTITUDE_STOPS = [[-15, 'night'], [-8.5, 'dusk'], [-2.5, 'set'], [3.5, 'gold'], [13, 'day']];

/** The palette at a solar altitude (degrees), full strength. */
function paletteAt(altitude, dark) {
  const set = dark ? DARK : LIGHT;
  let A = set.night, B = set.night, t = 0;
  if (altitude >= ALTITUDE_STOPS[ALTITUDE_STOPS.length - 1][0]) { A = B = set.day; }
  else {
    for (let i = 0; i < ALTITUDE_STOPS.length - 1; i += 1) {
      const [a0, k0] = ALTITUDE_STOPS[i], [a1, k1] = ALTITUDE_STOPS[i + 1];
      if (altitude >= a0 && altitude < a1) { A = set[k0]; B = set[k1]; t = smoothstep(a0, a1, altitude); break; }
    }
  }
  const out = {};
  for (const key of Object.keys(A)) out[key] = typeof A[key] === 'number' ? lerp(A[key], B[key], t) : mixLab(A[key], B[key], t);
  return out;
}

// ─────────────────────────────────────────────────────────────── the land ──
// Eight flats, drawn by hand as control points in WORLD points: x = 0 at the
// anchor window's leading edge (the cover's), the leading page running to the
// left (−485 … 0), y as on the Duo. R1 has the far summit over the leading
// page, a near peak in the strip's window and a notch where the sun goes down.

const MEAN = [300, 324, 352, 386, 428, 482, 556, 632];
const RIDGE_POINTS = [
  [[-560, 300], [-500, 296], [-440, 288], [-385, 276], [-330, 262], [-290, 258], [-250, 243], [-215, 252], [-170, 270], [-120, 284], [-60, 293], [-10, 297], [50, 292], [110, 284], [165, 287], [215, 279], [270, 291], [320, 298], [350, 292], [385, 271], [415, 281], [452, 302], [500, 306], [540, 302]],
  [[-560, 308], [-485, 312], [-420, 321], [-360, 329], [-300, 331], [-240, 324], [-180, 314], [-110, 310], [-50, 316], [10, 327], [70, 334], [130, 330], [190, 322], [250, 320], [310, 329], [362, 336], [420, 326], [466, 312], [540, 305]],
  [[-560, 362], [-485, 358], [-420, 346], [-370, 339], [-310, 344], [-250, 356], [-190, 364], [-120, 366], [-60, 360], [0, 349], [60, 343], [120, 348], [180, 358], [240, 364], [300, 356], [350, 346], [400, 350], [466, 364], [540, 370]],
  [[-560, 366], [-470, 372], [-380, 381], [-290, 390], [-200, 397], [-110, 402], [-40, 403], [30, 399], [110, 392], [200, 386], [290, 382], [362, 385], [420, 379], [466, 372], [540, 364]],
  [[-560, 448], [-485, 441], [-420, 428], [-350, 417], [-270, 410], [-200, 411], [-130, 418], [-50, 428], [30, 437], [110, 444], [200, 447], [280, 444], [350, 440], [420, 438], [466, 437], [540, 440]],
  [[-560, 474], [-500, 464], [-440, 459], [-380, 465], [-310, 478], [-230, 492], [-140, 503], [-50, 509], [40, 510], [130, 504], [220, 494], [300, 484], [370, 478], [430, 479], [490, 486], [540, 492]],
  [[-560, 584], [-480, 580], [-400, 570], [-310, 556], [-220, 544], [-130, 537], [-50, 538], [40, 546], [130, 560], [220, 574], [300, 585], [370, 590], [430, 588], [490, 580], [540, 574]],
  [[-560, 612], [-470, 618], [-370, 630], [-270, 642], [-170, 650], [-70, 653], [30, 650], [130, 643], [230, 636], [330, 628], [420, 620], [490, 614], [540, 610]],
];
const RIDGE_COUNT = RIDGE_POINTS.length;
/** Which flats are torn (the far, soft ones); the rest are knife-cut. */
const TORN = [true, true, true, false, false, false, false, false];

/** A smooth curve through control points [[x, y], …] (x ascending): cubic Hermite. */
function spline(points) {
  const n = points.length;
  const xs = points.map((p) => p[0]), ys = points.map((p) => p[1]);
  const m = new Array(n);
  for (let i = 0; i < n; i += 1) {
    const before = i > 0 ? (ys[i] - ys[i - 1]) / (xs[i] - xs[i - 1]) : null;
    const after = i < n - 1 ? (ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]) : null;
    m[i] = before == null ? after : after == null ? before : (before + after) / 2;
  }
  return (x) => {
    if (x <= xs[0]) return ys[0];
    if (x >= xs[n - 1]) return ys[n - 1];
    let i = 0;
    while (x > xs[i + 1]) i += 1;
    const h = xs[i + 1] - xs[i], t = (x - xs[i]) / h, t2 = t * t, t3 = t2 * t;
    return (2 * t3 - 3 * t2 + 1) * ys[i] + (t3 - 2 * t2 + t) * h * m[i] + (-2 * t3 + 3 * t2) * ys[i + 1] + (t3 - t2) * h * m[i + 1];
  };
}
const RIDGE_SPLINES = RIDGE_POINTS.map(spline);
/** The crest of flat k at world x, on the Duo: the drawn curve and a little wander. */
function worldCrest(k, wx) {
  const wander = (fbm1(wx / (58 + k * 12) + k * 13.7, { octaves: 3, seed: 40 + k }) - 0.5) * (5.5 - k * 0.35);
  return RIDGE_SPLINES[k](wx) + wander;
}

// The cloud strips, in world points. `z` is depth (0 the sheet … 1 the nearest
// flat) and decides parallax and drift; `speed` is points per second.
const CLOUDS = [
  { x: 430, y: 177, len: 260, thick: 9, z: 0.10, speed: 0.07, seed: 3, skew: 0.8 },
  { x: -420, y: 130, len: 380, thick: 11, z: 0.10, speed: 0.07, seed: 4, skew: 1.25 },
  { x: 300, y: 232, len: 520, thick: 14, z: 0.17, speed: 0.11, seed: 5, skew: 0.8 },
  { x: -140, y: 196, len: 600, thick: 16, z: 0.17, speed: 0.11, seed: 6, skew: 1.15 },
  { x: 40, y: 253, len: 420, thick: 11, z: 0.24, speed: 0.16, seed: 8, skew: 1.1 },
  { x: 455, y: 245, len: 190, thick: 8, z: 0.24, speed: 0.16, seed: 9, skew: 1.2 },
];
/** The clouds' track: they leave one wing and come back at the other. */
const TRACK = { from: -760, to: 760 };

// ─────────────────────────────────────────────────────────────── layout ──

/** Where the world sits on this display. */
function layoutOf(state) {
  const W = state.width, H = state.height;
  const phone = state.phone ?? { x: 0, width: W };
  if (state.device === 'iphone') {
    // The slab has no tall window: the stage is the header band. The same
    // world, its right-hand 402 points, closed up so the far ridge and the
    // notch the sun sets into stand just above the first card.
    return {
      duo: false, W, H, originX: -64, anchorX: 0, anchorW: W,
      horizon: 128, lane: 61,
      base: [128, 163, 206, 264, 342, 442, 584, 752], amp: [1.3, 1.4, 1.5, 1.5, 1.6, 1.6, 1.7, 1.5],
      starTop: 8, starBottom: 100, sunR: 10.5, moonR: 9.5,
      tonight: { x: 292, y: 80 },
      text: [{ x: 16, y: 70, w: 60, h: 60, r: 30 }, { x: 90, y: 75, w: 100, h: 28, r: 5 }, { x: 90, y: 106, w: 96, h: 22, r: 5 }],
      // Behind the name and the age line the far ridge keeps under the first card; it rises only in the clear part of the header.
      sink: (k, x) => (k === 0 ? 44 * (1 - smoothstep(186, 262, x)) : 0),
    };
  }
  const text = [{ x: phone.x + 20, y: 22, w: 60, h: 60, r: 30 }, { x: phone.x + 92, y: 27, w: 98, h: 28, r: 5 }, { x: phone.x + 92, y: 60, w: 96, h: 22, r: 5 }];
  if (phone.x > 0) text.push({ x: 95, y: 27, w: 240, h: 28, r: 5 }, { x: 95, y: 60, w: 130, h: 22, r: 5 });
  return {
    duo: true, W, H, originX: phone.x, anchorX: phone.x, anchorW: phone.width,
    horizon: 300, lane: 14,
    base: MEAN, amp: [1, 1, 1, 1, 1, 1, 1, 1],
    starTop: 7, starBottom: 262, sunR: 12, moonR: 10,
    tonight: { x: phone.x + 444, y: 210 },
    text,
  };
}

/** The crest of flat k at display x. */
function crestAt(lay, k, x) {
  return lay.base[k] + (worldCrest(k, x - lay.originX) - MEAN[k]) * lay.amp[k] + (lay.sink ? lay.sink(k, x) : 0);
}

/** Signed distance from a point to a rounded box (negative inside). */
function boxDistance(box, x, y) {
  const cx = box.x + box.w / 2, cy = box.y + box.h / 2;
  const qx = Math.abs(x - cx) - (box.w / 2 - box.r), qy = Math.abs(y - cy) - (box.h / 2 - box.r);
  return Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0) - box.r;
}

// ─────────────────────────────────────────────────────────────── the light ──

/** Where the lamp is and what the paper looks like now. Pure. */
function lightOf(state, lay) {
  const dark = state.scheme === 'dark';
  const pr = presenceOf(state);
  const altitude = state.sun.altitude * DEG;
  const p = pr.presence;
  const morning = state.sun.isNight ? state.sun.progress >= 0.5 : state.sun.progress < 0.5;

  // The palette: by altitude, a little pinker at dawn, the season in the
  // land, then quietened by the lab's hush and deepened by sleep.
  const full = paletteAt(altitude, dark);
  if (morning) {
    for (const key of ['lampNear', 'lampMid', 'lampFar', 'litFar', 'litNear', 'cloudLit', 'rim']) {
      const c = full[key], turn = -10 / DEG, cos = Math.cos(turn), sin = Math.sin(turn);
      full[key] = { L: c.L, a: (c.a * cos - c.b * sin) * 0.92, b: (c.a * sin + c.b * cos) * 0.92 };
    }
  }
  const se = seasonOf(state.dayOfYear, state.latitude);
  const tint = { a: 0, b: 0 };
  for (const name of Object.keys(SEASON_TINT)) { tint.a += SEASON_TINT[name].a * se.weights[name]; tint.b += SEASON_TINT[name].b * se.weights[name]; }
  const land = (c, w) => ({ L: c.L, a: c.a + (tint.a * (dark ? 0.55 : 1) - c.a) * w, b: c.b + (tint.b * (dark ? 0.55 : 1) - c.b) * w });
  // The land is the season's paper: green in spring and summer, straw in autumn, white under snow.
  // (The lamp still colours it: beside the sun everything goes to peach whatever the season.)
  const dayness = smoothstep(-8, 5, altitude);
  const seasonal = (0.3 + 0.62 * dayness) * (1 - 0.8 * se.snow);
  full.ridgeNear = land(full.ridgeNear, seasonal);
  full.ridgeFar = land(full.ridgeFar, seasonal * 0.5);
  full.litNear = land(full.litNear, seasonal * 0.5);
  full.litFar = land(full.litFar, seasonal * 0.3);
  full.haze = land(full.haze, seasonal * 0.35);
  Object.assign(full, FIXED[dark ? 'dark' : 'light']);

  const depth = pr.depth;
  // By night the light appearance sits where its palette says (no lift toward the page): a night, not a pale day.
  const pageLift = smoothstep(-13, -5, altitude);
  const pal = {};
  for (const key of Object.keys(full)) {
    if (typeof full[key] === 'number') { pal[key] = full[key]; continue; }
    const c = hush(full[key], p, dark, pageLift);
    const keepLight = key === 'disc' || key === 'moonDisc' || key === 'star' || key === 'starWarm';
    if (!keepLight) {
      if (dark) { c.L *= 1 - 0.17 * depth; c.a *= 1 - 0.2 * depth; c.b *= 1 - 0.2 * depth; }
      else { c.L *= 1 - 0.022 * depth; c.a *= 1 - 0.12 * depth; c.b *= 1 - 0.12 * depth; }
    }
    pal[key] = c;
  }

  // The sun: across by the baseline's clock, up by an arc onto this horizon;
  // after it sets it goes on down behind the flats, so its light comes up
  // through them.
  const sp = state.sun.progress;
  let sunX, sunY;
  if (!state.sun.isNight) {
    sunX = 0.04 + 0.92 * sp;
    sunY = lay.horizon - (lay.horizon - lay.lane) * Math.pow(Math.sin(Math.PI * sp), 0.9);
  } else {
    sunX = sp < 0.5 ? 0.96 : 0.04;
    sunY = lay.horizon + Math.min(64, (-altitude - 0.83) * 4.2);
  }
  const sun = {
    x: lay.anchorX + sunX * lay.anchorW, y: sunY, r: lay.sunR,
    power: smoothstep(-15, -7, altitude),              // how much of a lamp it still is
    up: !state.sun.isNight,
  };

  // The moon: across by its own pass, up by its real altitude.
  let moon = null;
  if (state.moon) {
    const m = state.moon;
    const t = clamp01((m.altitude * DEG) / 52);
    const lift = 1 - Math.pow(1 - t, 1.6);
    const night = 1 - smoothstep(-9, -2, altitude);
    moon = {
      x: lay.anchorX + m.x * lay.anchorW, y: lay.horizon - (lay.horizon - lay.lane) * lift, r: lay.moonR,
      fraction: m.fraction, rotation: m.rotation,
      power: night * (0.3 + 0.7 * m.fraction),          // as a lamp
      shown: 0.5 + 0.5 * night,                         // the hole itself: pale by day
    };
  }

  // A lamp never sits bright behind the header's text: it dims as it passes.
  for (const body of [sun, moon]) {
    if (!body) continue;
    let near = Infinity;
    for (const box of lay.text) near = Math.min(near, boxDistance(box, body.x, body.y));
    body.veiled = 1 - smoothstep(body.r - 1, body.r + 4, near);
  }

  return { dark, pr, p, altitude, pal, sun, moon, season: se, depth, morning };
}

// ────────────────────────────────────────────────────────────── geometry ──

function closedPath(points) {
  const path = new Path2D();
  path.moveTo(points[0][0], points[0][1]);
  for (let i = 1; i < points.length; i += 1) path.lineTo(points[i][0], points[i][1]);
  path.closePath();
  return path;
}

/** A crest as hand-cut paper: the curve, re-cut in long slightly flat strokes
 *  (knife) or with a fibrous wobble (torn). → { top: [[x, y]…], deckle: [[x, y]…] | null } */
function cutCrest(lay, k, torn) {
  const from = -PAD, to = lay.W + PAD;
  const top = [], deckle = torn ? [] : null;
  if (!torn) {
    // Knife: knots every 9–24 pt; between them the cut runs a little straighter than the curve.
    const rand = rng(900 + k * 17);
    const knots = [];
    for (let x = from - 30; x < to + 30;) { knots.push(x); x += 9 + rand() * 15; }
    let j = 0;
    for (let x = from; x <= to; x += 1.5) {
      while (knots[j + 1] < x) j += 1;
      const x0 = knots[j], x1 = knots[j + 1];
      const chord = lerp(crestAt(lay, k, x0), crestAt(lay, k, x1), (x - x0) / (x1 - x0));
      top.push([x, lerp(crestAt(lay, k, x), chord, 0.6)]);
    }
  } else {
    for (let x = from; x <= to; x += 0.75) {
      const wx = x - lay.originX;
      const tear = (fbm1(wx / 13 + k * 7.1, { octaves: 2, seed: 60 + k }) - 0.5) * 2.6
        + (fbm1(wx / 3.4 + k * 3.3, { octaves: 2, seed: 70 + k }) - 0.5) * 1.5
        + (fbm1(wx / 1.1, { octaves: 1, seed: 80 + k }) - 0.5) * 0.7;
      const y = crestAt(lay, k, x) + tear;
      top.push([x, y]);
      // The torn face: the paper's core shows for a point or three before the surface begins.
      const core = 1.1 + 2.6 * fbm1(wx / 8 + 50 + k, { octaves: 2, seed: 90 + k }) + 0.9 * fbm1(wx / 1.9 + 9, { octaves: 1, seed: 95 + k });
      deckle.push([x, y + core]);
    }
  }
  return { top, deckle };
}

function ridgeLayer(lay, k) {
  const { top, deckle } = cutCrest(lay, k, TORN[k]);
  const floor = lay.H + PAD;
  const outline = [[-PAD, floor], ...top, [lay.W + PAD, floor]];
  let minY = Infinity;
  for (const point of top) minY = Math.min(minY, point[1]);
  const layer = {
    id: `ridge${k}`, kind: 'ridge', k, depth: k / (RIDGE_COUNT - 1), z: 0.3 + 0.7 * (k / (RIDGE_COUNT - 1)),
    path: closedPath(outline), band: null,
    box: { x0: -PAD, y0: Math.floor(minY) - 56, x1: lay.W + PAD, y1: floor },
    top,
  };
  if (deckle) {
    // The band between the torn edge and where the surface begins.
    layer.band = closedPath([...top, ...deckle.slice().reverse()]);
  }
  return layer;
}

/** Snow (or hoar frost) lying along a crest: a torn white strip. */
function snowPath(lay, layer, amount, frost) {
  const k = layer.k;
  const lower = [];
  for (const [x, y] of layer.top) {
    const wx = x - lay.originX;
    const lie = frost
      ? (0.6 + 2.2 * fbm1(wx / 23 + k * 5, { octaves: 2, seed: 120 + k })) * amount
      : (2.5 + (6 + k * 2) * fbm1(wx / 52 + k * 5, { octaves: 2, seed: 120 + k }) + 1.6 * fbm1(wx / 7 + 3, { octaves: 2, seed: 130 + k })) * amount;
    lower.push([x, y + Math.max(0.2, lie)]);
  }
  return closedPath([...layer.top, ...lower.reverse()]);
}

function cloudLayer(lay, cloud, index) {
  const len = cloud.len * (lay.duo ? 1 : 0.6), thick = cloud.thick * (lay.duo ? 1 : 0.5);
  // On the slab the strips keep to one lane, between the status bar and the name.
  const y0 = lay.duo ? cloud.y : lay.lane + 3 + ((index % 3) - 1) * 3;
  const top = [], bottom = [], topIn = [], bottomIn = [];
  const steps = Math.ceil(len / 0.8);
  let minY = 0, maxY = 0;
  for (let i = 0; i <= steps; i += 1) {
    const u = i / steps, x = (u - 0.5) * len;
    // A torn strip: one long tail, one blunter end, a few low swells along the top, a nearly straight underside.
    const body = Math.pow(Math.sin(Math.PI * Math.pow(u, cloud.skew)), 0.62);
    const swell = 0.35 + 1.1 * Math.pow(fbm1(u * 2.6 + cloud.seed * 11, { octaves: 2, seed: 200 + cloud.seed }), 1.3);
    const sag = (fbm1(u * 1.4 + 5, { octaves: 2, seed: 220 + cloud.seed }) - 0.5) * thick * 0.5;
    const tearT = (fbm1(x / 5.5, { octaves: 2, seed: 230 + cloud.seed }) - 0.5) * 1.5 + (fbm1(x / 1.3, { octaves: 1, seed: 235 + cloud.seed }) - 0.5) * 0.55;
    const tearB = (fbm1(x / 7 + 40, { octaves: 2, seed: 240 + cloud.seed }) - 0.5) * 1.1 + (fbm1(x / 1.4 + 7, { octaves: 1, seed: 245 + cloud.seed }) - 0.5) * 0.45;
    const edge = Math.min(1, body * 2.2);
    const yt = sag - thick * body * swell + tearT * edge;
    const yb = Math.max(sag + thick * 0.3 * body * (0.75 + 0.5 * fbm1(u * 3 + 9, { octaves: 2, seed: 250 + cloud.seed })) + tearB * edge, yt + 0.3);
    top.push([x, yt]); bottom.push([x, yb]);
    minY = Math.min(minY, yt); maxY = Math.max(maxY, yb);
    const core = (0.7 + 1.9 * fbm1(x / 7 + 3, { octaves: 2, seed: 260 + cloud.seed })) * Math.min(1, body * 1.6);
    const mid = (yt + yb) / 2;
    topIn.push([x, Math.min(mid, yt + core)]); bottomIn.push([x, Math.max(mid, yb - core * 0.7)]);
  }
  const outline = [...top, ...bottom.slice().reverse()];
  const inner = [...topIn, ...bottomIn.slice().reverse()];
  const band = new Path2D();
  band.addPath(closedPath(outline));
  band.addPath(closedPath(inner));
  return {
    id: `cloud${index}`, kind: 'cloud', cloud, index, depth: 0, z: cloud.z,
    path: closedPath(outline), band, bandRule: 'evenodd',
    box: { x0: -len / 2 - 22, y0: Math.floor(minY) - 22, x1: len / 2 + 22, y1: Math.ceil(maxY) + 22 },   // local: about its own centre
    homeX: cloud.x, homeY: y0, thick,
  };
}

/** The tree: a cut trunk and boughs (one path), and leaf scraps in three depths. */
function buildTree(lay, se) {
  if (!lay.duo || lay.originX <= 0) return null;
  const rand = rng(1907);
  const baseX = lay.originX - 443, baseY = crestAt(lay, 5, lay.originX - 443) + 8;
  const boughs = new Path2D();
  const tips = [];
  let minX = baseX, maxX = baseX, minY = baseY;
  // A bough: a tapering ribbon that bends as it goes, then forks.
  const grow = (x, y, angle, length, width, level) => {
    const parts = 5;
    const curl = (rand() - 0.5) * 0.5 - angle * 0.12;        // wanders, and leans back toward the light
    const left = [], right = [];
    let cx = x, cy = y, a = angle;
    for (let i = 0; i <= parts; i += 1) {
      const w = width * (1 - 0.36 * i / parts) / 2;
      left.push([cx - Math.cos(a) * w, cy - Math.sin(a) * w]);
      right.push([cx + Math.cos(a) * w, cy + Math.sin(a) * w]);
      if (i < parts) { a += curl / parts; cx += Math.sin(a) * length / parts; cy -= Math.cos(a) * length / parts; }
    }
    boughs.moveTo(left[0][0], left[0][1]);
    for (let i = 1; i < left.length; i += 1) boughs.lineTo(left[i][0], left[i][1]);
    for (let i = right.length - 1; i >= 0; i -= 1) boughs.lineTo(right[i][0], right[i][1]);
    boughs.closePath();
    minX = Math.min(minX, cx); maxX = Math.max(maxX, cx); minY = Math.min(minY, cy);
    if (level <= 2) tips.push({ x: cx, y: cy, angle: a, level });
    if (level === 0) return;
    const next = width * 0.64;
    const fork = 0.33 + rand() * 0.18;
    const lead = rand() < 0.5 ? -1 : 1;
    grow(cx, cy, a + lead * fork * 0.75, length * (0.7 + rand() * 0.14), Math.max(0.85, next), level - 1);
    grow(cx, cy, a - lead * fork * 1.25, length * (0.62 + rand() * 0.14), Math.max(0.85, next * 0.9), level - 1);
    if (level <= 3 && rand() < 0.55) grow(cx, cy, a + (rand() - 0.5) * 0.3, length * 0.55, Math.max(0.8, next * 0.7), level - 1);
  };
  // The foot flares where it is glued behind the hill.
  boughs.moveTo(baseX - 7, baseY + 6); boughs.lineTo(baseX - 3.6, baseY - 12); boughs.lineTo(baseX + 3.6, baseY - 12); boughs.lineTo(baseX + 7, baseY + 6); boughs.closePath();
  grow(baseX, baseY, 0.04, 47, 6.2, 5);

  // Leaves: scraps about the tips. Each has a rank; the season shows the first so many.
  const scraps = [];
  tips.forEach((tip, ti) => {
    const count = tip.level === 0 ? 5 : tip.level === 1 ? 4 : 2;
    for (let i = 0; i < count; i += 1) {
      const a = rand() * TAU, d = Math.sqrt(rand()) * (tip.level === 0 ? 11 : 9);
      scraps.push({
        x: tip.x + Math.cos(a) * d, y: tip.y + Math.sin(a) * d * 0.85 - 2, turn: rand() * TAU,
        size: 3.8 + rand() * 2.8, rank: hash(ti * 16 + i, 31), tier: Math.floor(rand() * 3), shade: rand(),
      });
    }
  });
  for (const scrap of scraps) { minX = Math.min(minX, scrap.x - 6); maxX = Math.max(maxX, scrap.x + 6); minY = Math.min(minY, scrap.y - 6); }

  const leafPath = (list, round) => {
    const path = new Path2D();
    for (const s of list) {
      const cos = Math.cos(s.turn), sin = Math.sin(s.turn);
      const half = s.size * (round ? 0.55 : 1), wide = s.size * (round ? 0.5 : 0.36);
      const P = (u, v) => [s.x + u * cos - v * sin, s.y + u * sin + v * cos];
      const [ax, ay] = P(-half, 0), [bx, by] = P(half, 0), [c1x, c1y] = P(0, -wide * 1.5), [c2x, c2y] = P(0, wide * 1.5);
      path.moveTo(ax, ay); path.quadraticCurveTo(c1x, c1y, bx, by); path.quadraticCurveTo(c2x, c2y, ax, ay); path.closePath();
    }
    return path;
  };
  const leafShare = se.foliage * (1 - 0.45 * smoothstep(0.82, 1, se.leafHue));
  const leaves = scraps.filter((s) => s.rank < leafShare);
  const blossoms = scraps.filter((s) => hash(Math.round(s.x * 7 + s.y * 13), 5) < se.blossom * 0.75);
  const box = { x0: Math.floor(minX) - 26, y0: Math.floor(minY) - 30, x1: Math.ceil(maxX) + 26, y1: Math.ceil(baseY) + 12 };
  const z = 0.3 + 0.7 * (5 / 7);
  const layers = [{ id: 'trunk', kind: 'trunk', path: boughs, box, z: z - 0.02, depth: 0.8 }];
  for (let tier = 0; tier < 3; tier += 1) {
    const list = leaves.filter((s) => s.tier === tier);
    if (list.length) layers.push({ id: `leaf${tier}`, kind: 'leaf', tier, path: leafPath(list, false), box, z: z + tier * 0.015, depth: 0.6 });
  }
  if (blossoms.length) layers.push({ id: 'blossom', kind: 'blossom', tier: 3, path: leafPath(blossoms, true), box, z: z + 0.05, depth: 0.5 });
  return { layers, baseX, baseY, box };
}

// ───────────────────────────────────────────────────────────── the paper ──

/** Two tiling tiles of fibre and tooth: one of dark marks, one of light. */
function paperTiles(doc, s) {
  const size = Math.round(320 * s);
  const tiles = ['dark', 'light'].map(() => { const c = doc.createElement('canvas'); c.width = size; c.height = size; return c; });
  const rand = rng(4242);
  tiles.forEach((tile, which) => {
    const ctx = tile.getContext('2d');
    const image = ctx.createImageData(size, size);
    const data = image.data;
    const value = which === 0 ? 0 : 255;
    for (let y = 0; y < size; y += 1) {
      for (let x = 0; x < size; x += 1) {
        const n = (rand() - rand()) * 0.8;
        const a = Math.max(0, which === 0 ? n : -n);
        const o = (y * size + x) * 4;
        data[o] = value; data[o + 1] = value; data[o + 2] = value; data[o + 3] = a * 28;
      }
    }
    ctx.putImageData(image, 0, 0);
    // Fibres: short, faint, slightly curved hairs, wrapped so the tile repeats without a seam.
    const count = which === 0 ? 190 : 210;
    ctx.lineCap = 'round';
    for (let i = 0; i < count; i += 1) {
      const x = rand() * size, y = rand() * size, angle = rand() * TAU, length = (4 + rand() * 11) * s, curl = (rand() - 0.5) * 1.1;
      ctx.strokeStyle = which === 0 ? `rgba(0,0,0,${0.02 + rand() * 0.035})` : `rgba(255,255,255,${0.025 + rand() * 0.045})`;
      ctx.lineWidth = (0.3 + rand() * 0.35) * s;
      for (const ox of [-size, 0, size]) {
        for (const oy of [-size, 0, size]) {
          const x1 = x + ox, y1 = y + oy;
          if (x1 < -length || x1 > size + length || y1 < -length || y1 > size + length) continue;
          ctx.beginPath();
          ctx.moveTo(x1, y1);
          ctx.quadraticCurveTo(x1 + Math.cos(angle + curl) * length * 0.5, y1 + Math.sin(angle + curl) * length * 0.5,
            x1 + Math.cos(angle) * length, y1 + Math.sin(angle) * length);
          ctx.stroke();
        }
      }
    }
  });
  return { dark: tiles[0], light: tiles[1], size };
}

/** `MoonPhaseShape`: the lit part of a moon of radius r about the origin, bright limb on the right. */
function moonPhasePath(lit, r) {
  const terminator = 1 - 2 * clamp01(lit);
  const steps = 48;
  const path = new Path2D();
  for (let i = 0; i <= steps; i += 1) {
    const t = Math.PI * i / steps;
    if (i === 0) path.moveTo(r * Math.sin(t), -r * Math.cos(t)); else path.lineTo(r * Math.sin(t), -r * Math.cos(t));
  }
  for (let i = steps; i >= 0; i -= 1) {
    const t = Math.PI * i / steps;
    path.lineTo(terminator * r * Math.sin(t), -r * Math.cos(t));
  }
  path.closePath();
  return path;
}

// ─────────────────────────────────────────────────────────────── module ──

export function create(host) {
  const doc = host.ownerDocument ?? document;
  const newCanvas = (w = 1, h = 1) => { const c = doc.createElement('canvas'); c.width = w; c.height = h; return c; };
  const canvas = newCanvas();
  canvas.setAttribute('aria-hidden', 'true');
  canvas.style.cssText = 'position:absolute;left:0;top:0;display:block;pointer-events:none;';
  host.appendChild(canvas);
  const main = canvas.getContext('2d');

  let destroyed = false;
  let s = 1;                         // device pixels per point
  let lay = null, layKey = '';
  let geomKey = '';
  let ridges = [], clouds = [], tree = null;
  let tiles = null, tilesFor = 0;
  let patterns = null;
  const bitmaps = new Map();         // layer id → { canvas, key, x, y } (its lit bitmap, with its shadow)
  const sheet = { canvas: newCanvas(), key: '' };
  const stacks = { canvases: [newCanvas(), newCanvas()], key: '' };
  const soft = { canvas: newCanvas(), mask: newCanvas(), maskKey: '', key: '' };
  const rim = { canvas: newCanvas() };
  const shade = { canvas: newCanvas() };
  const fieldCanvas = newCanvas();
  const fieldCtx = fieldCanvas.getContext('2d');
  let lastFrame = '';
  const stats = { first: null, relight: null, steady: null, frames: 0 };

  // ── a colour field through a clip ──
  function drawField(ctx, box, shader) {
    const fw = Math.max(2, Math.ceil((box.x1 - box.x0) / CELL) + 1);
    const fh = Math.max(2, Math.ceil((box.y1 - box.y0) / CELL) + 1);
    if (fieldCanvas.width !== fw || fieldCanvas.height !== fh) { fieldCanvas.width = fw; fieldCanvas.height = fh; }
    const image = fieldCtx.createImageData(fw, fh);
    const data = image.data;
    const o = { L: 0, a: 0, b: 0 }, rgb = [0, 0, 0];
    for (let j = 0; j < fh; j += 1) {
      const y = box.y0 + j * CELL;
      for (let i = 0; i < fw; i += 1) {
        shader(box.x0 + i * CELL, y, o);
        labToRgb(o.L, o.a, o.b, rgb);
        const q = (j * fw + i) * 4;
        data[q] = rgb[0] + 0.5; data[q + 1] = rgb[1] + 0.5; data[q + 2] = rgb[2] + 0.5; data[q + 3] = 255;
      }
    }
    fieldCtx.putImageData(image, 0, 0);
    ctx.imageSmoothingEnabled = true;
    ctx.imageSmoothingQuality = 'high';
    ctx.drawImage(fieldCanvas, box.x0 - CELL / 2, box.y0 - CELL / 2, fw * CELL, fh * CELL);
  }

  /** The fibre, over whatever the clip lets through. */
  function drawFibre(ctx, box, light, offset, strength = 1) {
    if (!patterns) return;
    const matrix = new DOMMatrix().translate(Math.round(offset * 37.3 * s) / s, Math.round(offset * 91.7 * s) / s).scale(1 / s);
    patterns.dark.setTransform(matrix);
    patterns.light.setTransform(matrix);
    ctx.globalAlpha = (light.dark ? 0.85 : 0.55) * strength;
    ctx.fillStyle = patterns.dark;
    ctx.fillRect(box.x0, box.y0, box.x1 - box.x0, box.y1 - box.y0);
    ctx.globalAlpha = (light.dark ? 0.32 : 0.9) * strength;
    ctx.fillStyle = patterns.light;
    ctx.fillRect(box.x0, box.y0, box.x1 - box.x0, box.y1 - box.y0);
    ctx.globalAlpha = 1;
  }

  /** A radial gradient about a point: alpha(d) sampled at `stops` distances out to `reach`. */
  function radial(ctx, x, y, reach, colour, alphaAt, stops = 10) {
    const g = ctx.createRadialGradient(x, y, 0, x, y, reach);
    for (let i = 0; i <= stops; i += 1) g.addColorStop(i / stops, cssLab(colour, clamp01(alphaAt(reach * i / stops))));
    return g;
  }

  // ── the lamp's reach, shared by every shader ──
  // d is measured a little squashed, so a low lamp's glow lies along the horizon.
  function lampTerms(light) {
    const { sun, moon, dark, pal, pr } = light;
    const veilS = sun.veiled ?? 0, veilM = moon ? moon.veiled ?? 0 : 0;
    const low = 1 - smoothstep(4, 16, light.altitude);     // the glow spreads along the horizon when the sun is low
    return {
      sx: sun.x, sy: sun.y, sp: sun.power * (1 - 0.75 * veilS * (dark ? 1 : 0)),
      squash: lerp(1, dark ? 0.5 : 0.62, low),
      r1: (dark ? 26 : 46) * (lay.duo ? 1 : 0.8), r2: (dark ? 66 : 124) * (lay.duo ? 1 : 0.8), r3: (dark ? 215 : 310) * (lay.duo ? 1 : 0.8),
      mx: moon ? moon.x : 0, my: moon ? moon.y : 0, mp: moon ? moon.power * (1 - 0.7 * veilM * (dark ? 1 : 0)) : 0,
      m1: (dark ? 22 : 34) * (lay.duo ? 1 : 0.8), m2: (dark ? 70 : 110) * (lay.duo ? 1 : 0.8),
      anti: pr.solar * (1 - light.depth * 0.3),
      pal,
    };
  }

  function sheetShader(light) {
    const T = lampTerms(light), pal = light.pal, hy = lay.horizon;
    const sunSide = light.sun.x;
    return (x, y, o) => {
      const v = clamp01(y / hy);
      const e = v * v * (3 - 2 * v);
      o.L = pal.skyTop.L + (pal.skyLow.L - pal.skyTop.L) * e;
      o.a = pal.skyTop.a + (pal.skyLow.a - pal.skyTop.a) * e;
      o.b = pal.skyTop.b + (pal.skyLow.b - pal.skyTop.b) * e;
      if (T.anti > 0.01) {
        // Away from the sun: the pink belt, and under it the earth's blue shadow.
        const away = T.anti * smoothstep(150, 600, Math.abs(x - sunSide));
        if (away > 0.004) {
          const h = hy - y;
          const belt = Math.exp(-Math.pow((h - 62) / 40, 2));
          const shade = Math.exp(-Math.pow(Math.max(0, h - 2) / 26, 2));
          toward(o, pal.belt, away * 0.8 * belt);
          toward(o, pal.earth, away * 0.7 * shade);
        }
      }
      if (T.sp > 0.003) {
        const dx = (x - T.sx) * T.squash, dy = (y - T.sy) * (y > T.sy ? 1.25 : 1);
        const d = Math.sqrt(dx * dx + dy * dy);
        toward(o, pal.lampFar, T.sp * 0.88 * Math.exp(-Math.pow(d / T.r3, 1.3)));
        toward(o, pal.lampMid, T.sp * 0.92 * Math.exp(-Math.pow(d / T.r2, 1.6)));
        toward(o, pal.lampNear, T.sp * 0.95 * Math.exp(-Math.pow(d / T.r1, 2)));
      }
      if (T.mp > 0.003) {
        const d = Math.hypot(x - T.mx, y - T.my);
        toward(o, pal.moonMid, T.mp * 0.7 * Math.exp(-Math.pow(d / T.m2, 1.3)));
        toward(o, pal.moonNear, T.mp * 0.85 * Math.exp(-Math.pow(d / T.m1, 2)));
      }
      o.L += (fbm2(x / 90, y / 90, { octaves: 3, seed: 11 }) - 0.5) * (light.dark ? 0.012 : 0.01);
    };
  }

  function ridgeShader(layer, light) {
    const T = lampTerms(light), pal = light.pal, k = layer.k, t = layer.depth;
    const cover = layer.snowCover ?? 0;
    const base = mixLab(mixLab(pal.ridgeFar, pal.ridgeNear, Math.pow(t, 0.9)), pal.snow, cover * (light.dark ? 0.8 : 0.9));
    const lit = mixLab(mixLab(pal.litFar, pal.litNear, t), mixLab(pal.snow, pal.litFar, 0.7), cover * 0.6);
    const moonLit = mixLab(base, pal.moonLit, 0.6 - 0.3 * t);
    const lift = light.dark ? 0.065 * (1 - 0.4 * t) : 0.022;
    const hazeTint = mixLab(base, pal.haze, 0.6 - 0.3 * t);
    const hazeMix = { L: base.L + lift, a: hazeTint.a, b: hazeTint.b };
    const hazeAmount = 1;
    const span = (k < RIDGE_COUNT - 1 ? (lay.base[k + 1] - lay.base[k]) : 50) * 1.5 + 14;
    const reach = (light.dark ? 215 - 85 * t : 350 - 120 * t) * (lay.duo ? 1 : 0.8);
    const gain = 0.95 - 0.5 * t;
    const mottle = light.dark ? 0.012 : 0.009;
    // The crest, sampled once per column of the field.
    const crests = new Map();
    const crest = (x) => { let c = crests.get(x); if (c === undefined) { c = crestAt(lay, k, x); crests.set(x, c); } return c; };
    return (x, y, o) => {
      o.L = base.L; o.a = base.a; o.b = base.b;
      const below = y - crest(x);
      toward(o, hazeMix, hazeAmount * smoothstep(0, span, below));
      if (T.sp > 0.003) {
        const dx = (x - T.sx) * lerp(1, T.squash, 0.6), dy = y - T.sy;
        const d = Math.sqrt(dx * dx + dy * dy);
        toward(o, lit, T.sp * gain * Math.exp(-Math.pow(d / reach, 1.5)));
      }
      if (T.mp > 0.003) {
        const d = Math.hypot(x - T.mx, y - T.my);
        toward(o, moonLit, T.mp * (0.85 - 0.4 * t) * Math.exp(-Math.pow(d / (reach * 0.9), 1.4)));
      }
      o.L += (fbm2(x / 80 + k * 31, y / 80, { octaves: 3, seed: 300 + k }) - 0.5) * mottle;
    };
  }

  function cloudShader(layer, light, cx, cy) {
    const T = lampTerms(light), pal = light.pal;
    const lampY = T.sp > 0.05 ? T.sy : T.mp > 0.05 ? T.my : cy + 400;   // by day with a high sun the room lights them from below
    const side = lampY > cy ? 1 : -1;
    const reach = (light.dark ? 170 : 330) * (lay.duo ? 1 : 0.8);
    return (lx, ly, o) => {
      const x = lx + cx, y = ly + cy;
      const across = clamp01(0.5 + 0.5 * side * (ly / (layer.thick * 0.9)));
      o.L = pal.cloudShade.L + (pal.cloud.L - pal.cloudShade.L) * across;
      o.a = pal.cloudShade.a + (pal.cloud.a - pal.cloudShade.a) * across;
      o.b = pal.cloudShade.b + (pal.cloud.b - pal.cloudShade.b) * across;
      if (T.sp > 0.003) {
        const dx = (x - T.sx) * lerp(1, T.squash, 0.6), dy = y - T.sy;
        const d = Math.sqrt(dx * dx + dy * dy);
        toward(o, pal.cloudLit, T.sp * (0.35 + 0.6 * across) * Math.exp(-Math.pow(d / reach, 1.4)));
      }
      if (T.mp > 0.003) {
        const d = Math.hypot(x - T.mx, y - T.my);
        toward(o, pal.moonLit, T.mp * 0.7 * Math.exp(-Math.pow(d / (reach * 0.7), 1.4)));
      }
      o.L += (fbm2(x / 60, y / 60, { octaves: 2, seed: 400 + layer.index }) - 0.5) * 0.01;
    };
  }

  function flatShader(colour, litColour, light, gain) {
    const T = lampTerms(light);
    const reach = (light.dark ? 120 : 240);
    return (x, y, o) => {
      o.L = colour.L; o.a = colour.a; o.b = colour.b;
      if (T.sp > 0.003) {
        const d = Math.hypot((x - T.sx) * lerp(1, T.squash, 0.6), y - T.sy);
        toward(o, litColour, T.sp * gain * Math.exp(-Math.pow(d / reach, 1.5)));
      }
      o.L += (fbm2(x / 23, y / 23, { octaves: 2, seed: 500 }) - 0.5) * 0.02;
    };
  }

  // ── one flat: lit, then its shadow underneath ──
  // `ox, oy`: where the path's own origin sits on the display (clouds are built about their centre).
  function paintLayer(layer, light, ox = 0, oy = 0) {
    let entry = bitmaps.get(layer.id);
    if (!entry) { entry = { canvas: newCanvas(), key: '' }; bitmaps.set(layer.id, entry); }
    const box = layer.box;
    const pw = Math.ceil((box.x1 - box.x0) * s), ph = Math.ceil((box.y1 - box.y0) * s);
    if (entry.canvas.width !== pw || entry.canvas.height !== ph) { entry.canvas.width = pw; entry.canvas.height = ph; }
    const ctx = entry.canvas.getContext('2d');
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.globalAlpha = 1; ctx.globalCompositeOperation = 'source-over'; ctx.filter = 'none';
    ctx.clearRect(0, 0, pw, ph);
    ctx.setTransform(s, 0, 0, s, -box.x0 * s, -box.y0 * s);
    const { pal, sun, moon, dark } = light;
    const T = lampTerms(light);
    // The lamp, in this layer's own coordinates.
    const lsx = sun.x - ox, lsy = sun.y - oy, lmx = moon ? moon.x - ox : 0, lmy = moon ? moon.y - oy : 0;

    ctx.save();
    ctx.clip(layer.path);

    // 1 · the paper, by the light
    let shader, flatness = 1;
    if (layer.kind === 'ridge') shader = ridgeShader(layer, light);
    else if (layer.kind === 'cloud') shader = cloudShader(layer, light, ox, oy);
    else if (layer.kind === 'trunk') { shader = flatShader(pal.trunk, mixLab(pal.trunk, pal.litNear, 0.5), light, 0.6); flatness = 0.7; }
    else {
      const se = light.season;
      let own;
      if (layer.kind === 'blossom') own = dark ? K(0.34, 0.06, 5) : K(0.90, 0.07, 5);
      else {
        // 0 fresh green · 0.5 deep green · 0.8 amber · 1 russet
        const hue = se.leafHue < 0.5 ? lerp(128, 146, se.leafHue / 0.5) : lerp(146, 52, smoothstep(0.5, 0.95, se.leafHue));
        const chroma = se.leafHue < 0.5 ? lerp(0.105, 0.09, se.leafHue / 0.5) : lerp(0.09, 0.12, smoothstep(0.5, 0.9, se.leafHue));
        const tone = (dark ? 0.2 : 0.74) + (dark ? 0.035 : 0.05) * (layer.tier - 1);
        own = K(tone, chroma * (dark ? 0.6 : 1), hue);
      }
      own = hush(own, light.p, dark);
      if (dark) own.L *= 1 - 0.17 * light.depth;
      shader = flatShader(own, mixLab(own, pal.litFar, 0.55), light, 0.7);
    }
    drawField(ctx, box, shader);

    // 2 · the torn face: the paper's lighter core along the tear
    if (layer.band) {
      ctx.fillStyle = cssLab(pal.face, dark ? 0.3 : 0.5);
      ctx.fill(layer.band, layer.bandRule ?? 'nonzero');
    }

    // 3 · the lamp showing THROUGH the paper where it stands behind it
    const through = layer.kind === 'ridge' ? Math.pow(0.5, layer.k + 1) * 1.7 : layer.kind === 'cloud' ? 0.8 : 0;
    if (through > 0.02) {
      if (T.sp > 0.02) {
        const r = sun.r;
        ctx.fillStyle = radial(ctx, lsx, lsy, r * 3.4, mixLab(pal.disc, pal.lampMid, layer.kind === 'ridge' ? 0.25 + 0.2 * layer.k : 0.1),
          (d) => through * T.sp * (0.95 * Math.exp(-Math.pow(d / (r * 1.02), 4)) + 0.42 * Math.exp(-Math.pow(d / (r * 1.9), 2))), 16);
        ctx.fillRect(lsx - r * 3.4, lsy - r * 3.4, r * 6.8, r * 6.8);
      }
      if (moon && T.mp > 0.02) {
        const r = moon.r;
        ctx.fillStyle = radial(ctx, lmx, lmy, r * 3, pal.moonDisc,
          (d) => through * 0.5 * T.mp * Math.exp(-Math.pow(d / (r * 1.3), 2)) * (dark ? 0.5 : 1), 12);
        ctx.fillRect(lmx - r * 3, lmy - r * 3, r * 6, r * 6);
      }
    }

    // 4 · the rim: lamp light wrapping the edges that stand in front of it
    const rimReach = (dark ? 210 : 260) * (lay.duo ? 1 : 0.8);
    const rimGain = layer.kind === 'ridge' ? 1 - 0.45 * layer.depth : layer.kind === 'cloud' ? 1 : 0.8;
    const lamps = [];
    if (T.sp > 0.02) lamps.push({ x: lsx, y: lsy, colour: pal.rim, power: T.sp * (0.25 + 0.75 * clamp01(light.p * 1.2 + (dark ? 0.25 : 0))), reach: rimReach });
    if (moon && T.mp > 0.02) lamps.push({ x: lmx, y: lmy, colour: pal.moonRim, power: T.mp * (dark ? 1.15 : 0.6), reach: rimReach * 0.8 });
    for (const lamp of lamps) {
      const fall = (d) => lamp.power * rimGain * Math.exp(-Math.pow(d / (lamp.reach * 0.55), 1.5)) * (1 - smoothstep(lamp.reach * 0.7, lamp.reach, d));
      if (layer.kind === 'ridge') {
        // A flat's only edge is its crest: a soft band of light inside it, and a bright hair on the cut.
        // (Only as far as the lamp reaches: the blur is paid for by area.)
        ctx.save();
        ctx.beginPath();
        ctx.rect(lamp.x - lamp.reach, lamp.y - lamp.reach, lamp.reach * 2, lamp.reach * 2);
        ctx.clip();
        ctx.filter = `blur(${2.6 * s}px)`;
        ctx.strokeStyle = radial(ctx, lamp.x, lamp.y, lamp.reach, lamp.colour, (d) => 0.6 * fall(d), 12);
        ctx.lineWidth = 7;
        ctx.stroke(layer.path);
        ctx.restore();
        ctx.strokeStyle = radial(ctx, lamp.x, lamp.y, lamp.reach, lamp.colour, (d) => 0.8 * fall(d), 12);
        ctx.lineWidth = 1.8;
        ctx.stroke(layer.path);
      } else {
        // A strip or a bough has edges all round: only the side that faces the lamp catches it.
        // (The shape, less itself moved away from the lamp.)
        const cxm = (box.x0 + box.x1) / 2, cym = layer.kind === 'cloud' ? 0 : (box.y0 + box.y1) / 2;
        const ux = lamp.x - cxm, uy = lamp.y - cym, un = Math.hypot(ux, uy) || 1;
        const reach = layer.kind === 'cloud' ? 3.4 : 1.6;
        if (rim.canvas.width !== pw || rim.canvas.height !== ph) { rim.canvas.width = pw; rim.canvas.height = ph; }
        const r = rim.canvas.getContext('2d');
        r.setTransform(1, 0, 0, 1, 0, 0);
        r.globalCompositeOperation = 'source-over'; r.filter = 'none';
        r.clearRect(0, 0, pw, ph);
        r.setTransform(s, 0, 0, s, -box.x0 * s, -box.y0 * s);
        r.fillStyle = radial(r, lamp.x, lamp.y, lamp.reach * 1.6, lamp.colour, (d) => 0.95 * lamp.power * rimGain * Math.exp(-Math.pow(d / (lamp.reach * 0.7), 1.6)), 12);
        r.fill(layer.path);
        r.globalCompositeOperation = 'destination-out';
        r.filter = `blur(${0.9 * s}px)`;
        r.translate(-ux / un * reach, -uy / un * reach);
        r.fillStyle = '#000';
        r.fill(layer.path);
        r.filter = 'none';
        ctx.save();
        ctx.setTransform(1, 0, 0, 1, 0, 0);
        ctx.drawImage(rim.canvas, 0, 0);
        ctx.restore();
      }
    }

    // By night the whole sheet glows a little (it is what the pin-pricks let through): the far crests catch it.
    if (dark && layer.kind === 'ridge' && light.pr.stars > 0.03 && layer.k < 6) {
      ctx.strokeStyle = cssLab(pal.moonRim, light.pr.stars * (0.13 - 0.02 * layer.k) * (moon ? 0.6 + 0.4 * moon.power : 0.6));
      ctx.lineWidth = 1.6;
      ctx.stroke(layer.path);
    }

    // 5 · the cut face, by the room's light
    if (layer.kind === 'ridge' && !layer.band) {
      ctx.strokeStyle = cssLab(pal.face, dark ? 0.1 : 0.42);
      ctx.lineWidth = 1.3;
      ctx.stroke(layer.path);
    }

    // 6 · snow or frost along the crest, a torn strip of its own
    if (layer.snow) {
      ctx.save();
      ctx.filter = `blur(${1.1 * s}px)`;
      ctx.translate(0, 1.3);
      ctx.fillStyle = cssLab(pal.shadow, pal.shadowA * 0.8 * layer.snowAlpha);
      ctx.fill(layer.snow);
      ctx.restore();
      ctx.save();
      ctx.clip(layer.snow);
      ctx.globalAlpha = layer.snowAlpha * (dark ? 0.6 : 1);
      drawField(ctx, box, flatShader(pal.snow, mixLab(pal.snow, pal.litFar, 0.7), light, 0.9));
      ctx.restore();
    }

    // 7 · fibre
    drawFibre(ctx, box, light, layer.kind === 'ridge' ? layer.k + 1 : layer.kind === 'cloud' ? 11 + layer.index : 20, flatness);
    ctx.restore();

    // 8 · under it all, the shadow it throws on the flat behind: the room's
    // light comes from below and a little from the lamp's side, and the lamp
    // itself washes the shadow out where it is close.
    const lean = clamp(((box.x0 + box.x1) / 2 + ox - (T.sp > 0.05 ? sun.x : moon ? moon.x : sun.x)) / 200, -1, 1);
    let sdx, sdy, wide, tight, strength;
    if (layer.kind === 'ridge') { sdx = lean * 2; sdy = -(4.5 + 3.5 * layer.depth); wide = 8 + 5 * layer.depth; tight = 1.3; strength = 1; }
    else if (layer.kind === 'cloud') {
      const lampY = T.sp > 0.05 ? sun.y : moon && T.mp > 0.05 ? moon.y : oy + 300;
      sdx = lean * 1.5; sdy = lampY > oy ? -2.4 : 2.4; wide = 3.4; tight = 0.9; strength = dark ? 0.4 : 0.6;
    } else { sdx = lean * 2 + 1.5; sdy = -2; wide = 3.5; tight = 0.8; strength = 0.75; }
    const wash = (d) => 1 - 0.7 * T.sp * Math.exp(-Math.pow(d / (dark ? 90 : 150), 2));
    const shadowReach = Math.hypot(box.x1 - box.x0, box.y1 - box.y0) + 600;
    // The shadow's shape never changes (a tight one under the edge, a wide soft one): it is blurred once,
    // at half size, and only tinted when the light changes.
    const h = s / 2;
    const mw = Math.ceil((box.x1 - box.x0) * h), mh = Math.ceil((box.y1 - box.y0) * h);
    const maskKey = `${sdy}|${mw}|${mh}`;
    if (!layer.shadowMask || layer.shadowMaskKey !== maskKey) {
      layer.shadowMask = newCanvas(mw, mh);
      layer.shadowMaskKey = maskKey;
      const m = layer.shadowMask.getContext('2d');
      for (const [blur, alpha, scale] of [[tight, 0.55, 0.3], [wide, 0.9, 1]]) {
        m.setTransform(h, 0, 0, h, -box.x0 * h, (-box.y0 + sdy * scale) * h);
        m.filter = `blur(${blur * h}px)`;
        m.fillStyle = `rgba(0,0,0,${alpha})`;
        m.fill(layer.path);
      }
      m.filter = 'none';
    }
    if (shade.canvas.width !== mw || shade.canvas.height !== mh) { shade.canvas.width = mw; shade.canvas.height = mh; }
    const sc = shade.canvas.getContext('2d');
    sc.setTransform(h, 0, 0, h, -box.x0 * h, -box.y0 * h);
    sc.globalCompositeOperation = 'copy';
    sc.fillStyle = radial(sc, lsx, lsy, shadowReach, pal.shadow, (d) => pal.shadowA * strength * wash(d), 24);
    sc.fillRect(box.x0, box.y0, box.x1 - box.x0, box.y1 - box.y0);
    sc.setTransform(1, 0, 0, 1, 0, 0);
    sc.globalCompositeOperation = 'destination-in';
    sc.drawImage(layer.shadowMask, 0, 0);
    ctx.globalCompositeOperation = 'destination-over';
    ctx.imageSmoothingEnabled = true;
    ctx.imageSmoothingQuality = 'high';
    ctx.drawImage(shade.canvas, box.x0 + sdx, box.y0, mw / h, mh / h);
    ctx.globalCompositeOperation = 'source-over';
    return entry;
  }

  // ── the back sheet: paper, the lamp's glow in it, and the holes ──
  function paintSheet(light) {
    const ctx = sheet.canvas.getContext('2d');
    ctx.setTransform(s, 0, 0, s, 0, 0);
    ctx.globalAlpha = 1; ctx.globalCompositeOperation = 'source-over'; ctx.filter = 'none';
    const box = { x0: 0, y0: 0, x1: lay.W, y1: lay.H };
    drawField(ctx, box, sheetShader(light));
    drawFibre(ctx, box, light, 0);
    const { pal, sun, moon, dark } = light;

    // The sun: a round hole, the lamp behind it.
    if (sun.power > 0.01) {
      const veiled = dark ? sun.veiled : 0;
      const core = mixLab(pal.disc, pal.lampMid, 0.75 * veiled);
      const edge = mixLab(core, pal.lampNear, 0.55);
      ctx.save();
      ctx.globalAlpha = Math.min(1, sun.power * 1.4);
      const g = ctx.createRadialGradient(sun.x, sun.y, 0, sun.x, sun.y, sun.r);
      g.addColorStop(0, cssLab(core)); g.addColorStop(0.55, cssLab(core)); g.addColorStop(1, cssLab(edge));
      ctx.fillStyle = g;
      ctx.beginPath(); ctx.arc(sun.x, sun.y, sun.r, 0, TAU); ctx.fill();
      // The hole's cut edge: a hair of the sheet's thickness all round, a little heavier below where the room's light catches it.
      ctx.lineWidth = 0.8;
      ctx.strokeStyle = cssLab(mixLab(pal.lampMid, pal.shadow, dark ? 0.15 : 0.3), dark ? 0.5 : 0.42);
      ctx.beginPath(); ctx.arc(sun.x, sun.y, sun.r + 0.3, 0, TAU); ctx.stroke();
      ctx.strokeStyle = cssLab(pal.face, dark ? 0.2 : 0.8);
      ctx.beginPath(); ctx.arc(sun.x, sun.y, sun.r - 0.5, Math.PI * 0.15, Math.PI * 0.85); ctx.stroke();
      ctx.restore();
    }

    // The moon: the lit part is cut out; the rest of the disc is only thinned. Up in the
    // top band its light soaks a little way into the paper; low over the land it keeps quiet.
    if (moon) {
      const veiled = dark ? moon.veiled : 0;
      const night = smoothstep(0.5, 1, moon.shown);
      const high = 1 - smoothstep(64, 130, moon.y) * (lay.duo ? 1 : 0);
      ctx.save();
      ctx.translate(moon.x, moon.y);
      if (night > 0.02) {
        const reach = moon.r * 3.1;
        const soak = ctx.createRadialGradient(0, 0, moon.r * 0.8, 0, 0, reach);
        const a0 = (dark ? 0.02 + 0.44 * high : 0.55) * night * (1 - veiled) * (0.4 + 0.6 * moon.fraction);
        soak.addColorStop(0, cssLab(pal.moonDisc, a0));
        soak.addColorStop(0.3, cssLab(pal.moonDisc, a0 * 0.34));
        soak.addColorStop(1, cssLab(pal.moonDisc, 0));
        ctx.fillStyle = soak;
        ctx.beginPath(); ctx.arc(0, 0, reach, 0, TAU); ctx.fill();
      }
      ctx.fillStyle = cssLab(mixLab(pal.moonNear, pal.moonDisc, dark ? 0.42 : 0.5), (dark ? 0.8 : 0.5) * (0.4 + 0.6 * night) * (1 - 0.8 * veiled));
      ctx.beginPath(); ctx.arc(0, 0, moon.r - 0.3, 0, TAU); ctx.fill();
      ctx.strokeStyle = cssLab(dark ? pal.face : pal.shadow, (dark ? 0.3 : 0.2) * moon.shown);
      ctx.lineWidth = 0.6;
      ctx.beginPath(); ctx.arc(0, 0, moon.r - 0.3, 0, TAU); ctx.stroke();
      ctx.rotate(moon.rotation);
      const lit = mixLab(mixLab(pal.lampNear, pal.moonDisc, 0.35 + 0.65 * night), pal.moonMid, 0.8 * veiled);
      const warm = mixLab(lit, dark ? K(0.90, 0.05, 80) : pal.moonNear, 0.5 * (1 - veiled));
      const shape = moonPhasePath(moon.fraction, moon.r);
      const face = ctx.createRadialGradient(moon.r * 0.25, -moon.r * 0.1, 0, 0, 0, moon.r * 1.05);
      face.addColorStop(0, cssLab(lit, 0.55 + 0.45 * night));
      face.addColorStop(0.6, cssLab(lit, 0.55 + 0.45 * night));
      face.addColorStop(1, cssLab(warm, 0.55 + 0.45 * night));
      ctx.fillStyle = face;
      ctx.fill(shape);
      ctx.restore();
    }
  }

  // ── his stars ──
  let starKey = '', starList = [], wideList = [];
  function starsFor(state) {
    const lit = state.asleep === 'night' && !(state.event && state.event.kind === 'bedtime' && state.event.age <= 0);
    const key = `${layKey}|${state.ageDays}|${lit}`;
    if (key === starKey) return;
    starKey = key;
    const list = nights(state.ageDays, { tonightLit: lit });
    starList = list.map((star) => {
      let x, y;
      if (star.kind === 'tonight') { x = lay.tonight.x; y = lay.tonight.y; }
      else {
        // Each night's own place — gathered a little toward the top band and the strip, where they can be seen.
        x = lay.anchorX + lay.anchorW * (1 - Math.pow(1 - star.u, 1.22));
        y = lay.starTop + (lay.starBottom - lay.starTop) * Math.pow(star.v, 1.3);
      }
      let dim = 1;
      for (const box of lay.text) dim = Math.min(dim, 0.4 + 0.6 * smoothstep(-2, 5, boxDistance(box, x, y)));
      return { ...star, x, y, dim };
    });
    // The leading page's ordinary sky: fainter, uncounted.
    wideList = [];
    if (lay.anchorX > 0) {
      const count = 84;
      for (let i = 0; i < count; i += 1) {
        const x = hash(i, 801) * (lay.anchorX - 10), y = lay.starTop + (lay.starBottom - lay.starTop) * Math.pow(hash(i, 802), 1.15);
        let dim = 1;
        for (const box of lay.text) dim = Math.min(dim, 0.4 + 0.6 * smoothstep(-2, 5, boxDistance(box, x, y)));
        wideList.push({ x, y, magnitude: 0.1 + 0.26 * hash(i, 803), period: 3 + hash(i, 804) * 4, phase: hash(i, 805), dim });
      }
    }
  }

  const GLINT = [[0.5, 0], [0.56, 0.44], [1, 0.5], [0.56, 0.56], [0.5, 1], [0.44, 0.56], [0, 0.5], [0.44, 0.44]];
  function paintStars(ctx, state, light, time) {
    const { pal, dark, pr } = light;
    const out = pr.stars;
    const bedtime = state.event && state.event.kind === 'bedtime' ? state.event.age : null;
    const spark = bedtime == null ? 1 : ignition(bedtime);
    // The answer: when tonight's star is lit, the others swell in a ring that travels out from it.
    const ring = (x, y) => {
      if (bedtime == null) return 0;
      const d = Math.hypot(x - lay.tonight.x, y - lay.tonight.y);
      return Math.exp(-Math.pow((bedtime - 1.5 - d / 210) / 0.7, 2));
    };
    const prick = (x, y, radius, glow, alpha, colour, glint) => {
      if (alpha <= 0.004) return;
      if (!dark) {
        // On pale paper a prick is a dimple first: a breath of shadow under the hole.
        ctx.fillStyle = cssLab(pal.shadow, Math.min(0.5, 0.34 * alpha));
        ctx.beginPath(); ctx.arc(x + 0.25, y + 0.45, radius + 0.75, 0, TAU); ctx.fill();
      }
      // The light it lets into the paper round it…
      const g = ctx.createRadialGradient(x, y, 0, x, y, glow);
      g.addColorStop(0, cssLab(colour, (dark ? 0.5 : 0.9) * alpha));
      g.addColorStop(0.28, cssLab(colour, (dark ? 0.15 : 0.4) * alpha));
      g.addColorStop(1, cssLab(colour, 0));
      ctx.fillStyle = g;
      ctx.beginPath(); ctx.arc(x, y, glow, 0, TAU); ctx.fill();
      // …and the hole itself, crisp.
      ctx.fillStyle = cssLab(colour, Math.min(1, 0.45 + alpha));
      if (glint) {
        const size = radius * 5.2;
        ctx.beginPath();
        GLINT.forEach(([u, v], i) => { const px = x + (u - 0.5) * size, py = y + (v - 0.5) * size; if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py); });
        ctx.closePath(); ctx.fill();
      }
      ctx.beginPath(); ctx.arc(x, y, radius, 0, TAU); ctx.fill();
    };
    const cool = mixLab(pal.star, K(0.95, 0.03, 250), 0.6);
    for (const star of wideList) {
      const tw = time == null ? 1 : 0.7 + 0.3 * Math.cos(TAU * (time / star.period + star.phase));
      prick(star.x, star.y, 0.5 + star.magnitude, 2.2 + 3 * star.magnitude, out * tw * (0.3 + star.magnitude) * star.dim, cool, false);
    }
    for (const star of starList) {
      const tw = time == null ? (star.kind === 'tonight' ? 0.9 : 1) : twinkle(star, time);
      if (star.kind === 'tonight') {
        // Tonight's: a larger, warmer hole, its light soaking into the paper around it. Lit by day too.
        const a = Math.min(1.35, spark) * tw;
        if (a <= 0.004) continue;
        const reach = (dark ? 30 : 27) * (0.8 + 0.3 * Math.min(1.35, spark));
        const warm = dark ? pal.starWarm : K(0.905, 0.13, 78);
        const halo = ctx.createRadialGradient(star.x, star.y, 0, star.x, star.y, reach);
        halo.addColorStop(0, cssLab(warm, (dark ? 0.42 : 0.9) * Math.min(1, a)));
        halo.addColorStop(0.3, cssLab(warm, (dark ? 0.15 : 0.45) * Math.min(1, a)));
        halo.addColorStop(1, cssLab(warm, 0));
        ctx.fillStyle = halo;
        ctx.beginPath(); ctx.arc(star.x, star.y, reach, 0, TAU); ctx.fill();
        if (!dark) {
          ctx.strokeStyle = cssLab(pal.shadow, 0.62 * Math.min(1, a));
          ctx.lineWidth = 0.9;
          ctx.beginPath(); ctx.arc(star.x, star.y, 3.2, 0, TAU); ctx.stroke();
        }
        prick(star.x, star.y, (dark ? 2.1 : 2.5) * (0.85 + 0.15 * Math.min(1.35, spark)), 8, Math.min(1, a), mixLab(pal.starWarm, pal.star, 0.35), false);
        continue;
      }
      const bright = star.kind === 'first' || star.kind === 'month';
      // By day the sheet hides them; at the bedtime moment the brightest answer even so.
      const answer = ring(star.x, star.y);
      const seen = Math.max(out, bright ? 0.5 * pr.event : 0) * (0.2 + 0.8 * Math.pow(star.magnitude, 1.25)) * tw * star.dim;
      const alpha = Math.min(1, seen * (1 + 0.9 * answer) + (dark ? 0.12 : 0.08) * answer * Math.max(out, bright ? pr.event : 0));
      const colour = star.warmth > 0 ? mixLab(pal.star, pal.starWarm, star.warmth * 0.6) : mixLab(pal.star, cool, -star.warmth);
      const radius = (star.kind === 'first' ? 1.8 : star.kind === 'month' ? 1.15 : 0.3 + 1.15 * Math.pow(star.magnitude, 1.5)) * (1 + 0.25 * answer) * Math.min(1, 0.5 + out);
      prick(star.x, star.y, radius, (bright ? 6 : 1.8 + 6 * Math.pow(star.magnitude, 1.5)) * (1 + 0.4 * answer), alpha, colour, star.kind === 'month');
    }
  }

  // ── scraps in the air ──
  function paintScraps(ctx, state, light, time, nearGroup) {
    const se = light.season, { pal, dark } = light;
    const t = time ?? 0;
    const kinds = [];
    const flurry = se.snowfall > 0 ? se.snowfall : se.snow > 0.5 ? 0.3 : 0;      // no snowfall today: still a few flakes off the ridges
    if (flurry > 0) kinds.push({ kind: 'snow', count: Math.round(74 * flurry), colour: pal.snow, fall: 6.5, size: 1.7 });
    if (se.petals > 0.02) kinds.push({ kind: 'petal', count: Math.round(46 * se.petals), colour: hush(dark ? K(0.36, 0.06, 5) : K(0.91, 0.065, 5), light.p, dark), fall: 7.5, size: 3 });
    if (se.leafFall > 0.02) kinds.push({ kind: 'leaf', count: Math.round(40 * se.leafFall), colour: hush(dark ? K(0.3, 0.07, 62) : K(0.80, 0.10, 65), light.p, dark), fall: 9, size: 3.6 });
    const area = lay.W / 466;
    for (const spec of kinds) {
      const count = Math.round(spec.count * area);
      for (let i = 0; i < count; i += 1) {
        const near = hash(i, 611) < 0.5;
        if (near !== nearGroup) continue;
        const depth = near ? 1 : 0.62;
        const span = lay.H + 60;
        const speed = spec.fall * (0.7 + 0.6 * hash(i, 612)) * depth;
        const y = ((hash(i, 613) * span + speed * t) % span) - 30;
        const sway = (8 + 10 * hash(i, 614)) * Math.sin(TAU * (t / (6 + 5 * hash(i, 615)) + hash(i, 616)));
        const x = ((hash(i, 617) * (lay.W + 80) + sway + t * 1.2 * depth) % (lay.W + 80)) - 40;
        const turn = TAU * (hash(i, 618) + t / (9 + 8 * hash(i, 619)));
        const size = spec.size * (0.75 + 0.5 * hash(i, 620)) * depth;
        const lit = lampTint(light, x, y, spec.colour);
        const clear = smoothstep(lay.duo ? 84 : 124, lay.duo ? 140 : 170, y);
        if (clear <= 0.01) continue;
        ctx.save();
        ctx.translate(x, y);
        ctx.rotate(turn);
        // Its shadow on the flat behind, then the scrap.
        for (const pass of [0, 1]) {
          ctx.fillStyle = pass === 0 ? cssLab(pal.shadow, pal.shadowA * 0.5 * clear) : cssLab(lit, (near ? 1 : 0.9) * clear);
          ctx.beginPath();
          const off = pass === 0 ? 1.4 : 0;
          if (spec.kind === 'snow') ctx.ellipse(off, -off, size, size * 0.86, 0, 0, TAU);
          else { ctx.moveTo(-size + off, -off); ctx.quadraticCurveTo(off, -size * 0.75 - off, size + off, -off); ctx.quadraticCurveTo(off, size * 0.75 - off, -size + off, -off); }
          ctx.fill();
        }
        ctx.restore();
      }
    }
  }
  /** A small thing's colour where it is: its own, warmed by the lamp. */
  function lampTint(light, x, y, colour) {
    const T = lampTerms(light);
    const d = Math.hypot(x - T.sx, y - T.sy);
    return mixLab(colour, light.pal.litFar, 0.6 * T.sp * Math.exp(-Math.pow(d / (light.dark ? 130 : 260), 1.5)));
  }

  function paintFireflies(ctx, state, light, time) {
    const se = light.season;
    const glow = se.fireflies * light.pr.stars;
    if (glow <= 0.02) return;
    const t = time ?? 0;
    const count = Math.round(15 * lay.W / 466);
    const colour = light.dark ? K(0.93, 0.13, 105) : K(0.97, 0.12, 102);
    for (let i = 0; i < count; i += 1) {
      const homeX = hash(i, 701) * lay.W, homeY = lay.horizon + 26 + hash(i, 702) * (lay.H - lay.horizon - 90);
      const x = homeX + 9 * Math.sin(TAU * (t / (23 + 14 * hash(i, 703)) + hash(i, 704)));
      const y = homeY + 6 * Math.sin(TAU * (t / (17 + 12 * hash(i, 705)) + hash(i, 706)));
      const breath = Math.pow(0.5 + 0.5 * Math.sin(TAU * (t / (3.4 + 2.6 * hash(i, 707)) + hash(i, 708))), 2);
      const a = glow * (0.25 + 0.75 * breath);
      const reach = light.dark ? 9 : 7;
      if (!light.dark) { ctx.fillStyle = cssLab(light.pal.shadow, 0.3 * a); ctx.beginPath(); ctx.arc(x + 0.3, y + 0.5, 1.9, 0, TAU); ctx.fill(); }
      const g = ctx.createRadialGradient(x, y, 0, x, y, reach);
      g.addColorStop(0, cssLab(colour, 0.7 * a)); g.addColorStop(0.3, cssLab(colour, 0.22 * a)); g.addColorStop(1, cssLab(colour, 0));
      ctx.fillStyle = g; ctx.beginPath(); ctx.arc(x, y, reach, 0, TAU); ctx.fill();
      ctx.fillStyle = cssLab(colour, a); ctx.beginPath(); ctx.arc(x, y, 1.1, 0, TAU); ctx.fill();
    }
  }

  // ── where the cards stand, the stage goes soft ──
  function soften(state, light, pictureKey) {
    const cards = state.cards ?? [];
    const veil = state.veil ?? 0, lead = state.lead ?? 1;
    const phoneX = state.phone ? state.phone.x : 0;
    const list = cards.filter((card) => !['header', 'strip'].includes(card.kind));
    if (!list.length) return;
    const q = 3;                          // the soft copy is a third of the size
    const w = Math.ceil(canvas.width / q), h = Math.ceil(canvas.height / q);
    if (soft.canvas.width !== w || soft.canvas.height !== h) { soft.canvas.width = w; soft.canvas.height = h; soft.mask.width = w; soft.mask.height = h; soft.maskKey = ''; soft.key = ''; }
    const key = list.map((card) => `${card.x},${card.y},${card.width},${card.height}`).join(';') + `|${veil}|${lead}|${s}`;
    const k = s / q;
    if (soft.maskKey !== key) {
      const m = soft.mask.getContext('2d');
      m.setTransform(1, 0, 0, 1, 0, 0);
      m.clearRect(0, 0, w, h);
      m.filter = `blur(${4 * k}px)`;
      for (const card of list) {
        const present = card.x < phoneX - 1 ? lead : 1 - veil;
        if (present <= 0.01) continue;
        m.fillStyle = `rgba(0,0,0,${present})`;
        const grow = 2;
        m.beginPath();
        m.roundRect((card.x - grow) * k, (card.y - grow) * k, (card.width + 2 * grow) * k, (card.height + 2 * grow) * k, 24 * k);
        m.fill();
      }
      m.filter = 'none';
      soft.maskKey = key;
    }
    // The soft copy is only remade when the picture under it has really changed (the flats, the
    // light, a cloud gone a point or two): what drifts under a card can wait a moment.
    const softKey = `${pictureKey}|${soft.maskKey}`;
    if (soft.key !== softKey) {
      soft.key = softKey;
      const c = soft.canvas.getContext('2d');
      c.setTransform(1, 0, 0, 1, 0, 0);
      c.globalCompositeOperation = 'copy';
      c.filter = `blur(${3.2 * k}px)`;
      c.drawImage(canvas, 0, 0, w, h);
      c.filter = 'none';
      // A sheet of vellum in front of it: values close up.
      c.globalCompositeOperation = 'source-over';
      c.fillStyle = cssLab(mixLab(light.pal.haze, light.pal.ridgeNear, 0.5), 0.14 + 0.2 * light.p);
      c.fillRect(0, 0, w, h);
      c.globalCompositeOperation = 'destination-in';
      c.drawImage(soft.mask, 0, 0);
      c.globalCompositeOperation = 'source-over';
    }
    main.setTransform(1, 0, 0, 1, 0, 0);
    main.imageSmoothingEnabled = true;
    main.imageSmoothingQuality = 'high';
    main.drawImage(soft.canvas, 0, 0, canvas.width, canvas.height);
  }

  // ── geometry, when the display or the season changes ──
  function buildGeometry(state, se) {
    ridges = [];
    for (let k = 0; k < RIDGE_COUNT; k += 1) {
      const layer = ridgeLayer(lay, k);
      const frost = se.frost * (1 - se.snow);
      if (se.snow > 0.04) {
        if (k < 3) { layer.snow = snowPath(lay, layer, se.snow, false); layer.snowAlpha = Math.min(1, se.snow * 1.6); }
        else layer.snowCover = Math.min(1, se.snow * 1.3);
      } else if (frost > 0.04 && k < 5) { layer.snow = snowPath(lay, layer, frost, true); layer.snowAlpha = 0.55 * frost; }
      ridges.push(layer);
    }
    clouds = CLOUDS.map((cloud, index) => cloudLayer(lay, cloud, index));
    tree = buildTree(lay, se);
    bitmaps.clear();
    sheet.key = ''; stacks.key = '';
  }

  const round = (v, q) => Math.round(v / q) * q;
  function lightKeyOf(light) {
    const parts = [light.dark ? 'd' : 'l', round(light.sun.x, 0.5), round(light.sun.y, 0.5), light.sun.power.toFixed(3), (light.sun.veiled ?? 0).toFixed(2)];
    if (light.moon) parts.push(round(light.moon.x, 0.5), round(light.moon.y, 0.5), light.moon.power.toFixed(3), light.moon.fraction.toFixed(3), light.moon.rotation.toFixed(2), (light.moon.veiled ?? 0).toFixed(2), light.moon.shown.toFixed(2));
    parts.push(light.p.toFixed(2), light.depth.toFixed(2), light.altitude.toFixed(1), light.pr.solar.toFixed(2), light.morning ? 'm' : 'e');
    return parts.join(',');
  }

  function render(state) {
    if (destroyed || !state) return;
    const started = performance.now();
    s = Number.isFinite(state.dpr) && state.dpr > 0 ? state.dpr : 1;
    const pw = Math.ceil(state.width * s - 1e-6), ph = Math.ceil(state.height * s - 1e-6);
    if (canvas.width !== pw || canvas.height !== ph) {
      canvas.width = pw; canvas.height = ph;
      canvas.style.width = `${pw / s}px`; canvas.style.height = `${ph / s}px`;
      lastFrame = '';
    }
    const phone = state.phone ?? { x: 0, width: state.width };
    const nextLayKey = [state.device, state.width, state.height, s, phone.x, phone.width].join('|');
    if (nextLayKey !== layKey) { layKey = nextLayKey; lay = layoutOf(state); geomKey = ''; starKey = ''; }
    if (tilesFor !== s) { tiles = paperTiles(doc, s); tilesFor = s; patterns = { dark: main.createPattern(tiles.dark, 'repeat'), light: main.createPattern(tiles.light, 'repeat') }; geomKey = ''; }
    if (sheet.canvas.width !== pw || sheet.canvas.height !== ph) { sheet.canvas.width = pw; sheet.canvas.height = ph; sheet.key = ''; stacks.key = ''; }

    const light = lightOf(state, lay);
    const se = light.season;
    const nextGeomKey = [layKey, se.snow.toFixed(2), se.frost.toFixed(2), se.foliage.toFixed(2), se.leafHue.toFixed(2), se.blossom.toFixed(2)].join('|');
    if (nextGeomKey !== geomKey) { geomKey = nextGeomKey; buildGeometry(state, se); }
    starsFor(state);

    const time = state.reduceMotion || !Number.isFinite(state.t) ? null : state.t;
    const tilt = state.tilt ?? { x: 0, y: 0 };
    const opening = state.event && state.event.kind === 'open' && state.fold ? state.event.age : null;
    const lightKey = lightKeyOf(light);
    const frameKey = [geomKey, lightKey, time, tilt.x, tilt.y, opening, state.event ? `${state.event.kind}${state.event.age}` : '', state.asleep, state.ageDays,
      state.veil ?? '', state.lead ?? '', (state.cards ?? []).length].join('|');
    if (frameKey === lastFrame) return;
    let relit = false;

    // The back sheet.
    if (sheet.key !== lightKey) { paintSheet(light); sheet.key = lightKey; relit = true; }

    // Each flat's own bitmap, when the light on it has changed.
    const cloudsOut = lay.duo ? clamp01(1 - light.pr.stars * 1.15) : 0;      // the slab's header is too small a sky for strips
    const drift = (cloud) => {
      const span = TRACK.to - TRACK.from;
      const x = cloud.homeX + (time ?? 0) * cloud.cloud.speed * (1 - 0.4 * light.depth);
      return ((x - TRACK.from) % span + span) % span + TRACK.from;
    };
    for (const layer of ridges) {
      const entry = bitmaps.get(layer.id);
      if (!entry || entry.key !== lightKey) { paintLayer(layer, light).key = lightKey; relit = true; }
    }
    if (tree) for (const layer of tree.layers) {
      const entry = bitmaps.get(layer.id);
      if (!entry || entry.key !== lightKey) { paintLayer(layer, light).key = lightKey; relit = true; }
    }
    const cloudPlaces = [];
    if (cloudsOut > 0.01) {
      for (const layer of clouds) {
        const x = lay.originX + (lay.duo ? drift(layer) : drift(layer) * 0.7 + 60), y = layer.homeY;
        if (x + layer.box.x1 < -PAD || x + layer.box.x0 > lay.W + PAD) continue;
        const key = `${lightKey}|${round(x, 3)}`;
        const entry = bitmaps.get(layer.id);
        if (!entry || entry.key !== key) { paintLayer(layer, light, round(x, 3), y).key = key; relit = true; }
        cloudPlaces.push({ layer, x, y });
      }
    }

    // ── the frame ──
    const ctx = main;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.globalAlpha = 1; ctx.globalCompositeOperation = 'source-over'; ctx.filter = 'none';
    ctx.drawImage(sheet.canvas, 0, 0);
    ctx.setTransform(s, 0, 0, s, 0, 0);
    paintStars(ctx, state, light, time);

    const shift = (z) => ({ x: tilt.x * PARALLAX.x * z, y: tilt.y * PARALLAX.y * z });
    // Opening the Duo: the leading page's flats swing up about the fold, far ones first.
    const foldX = state.fold ? state.fold.x : 0;
    const rise = (order) => (opening == null ? 1 : easeOut((opening - 0.08 * order) / 0.95));
    const place = (to, layer, order, drop) => {
      const entry = bitmaps.get(layer.id);
      if (!entry) return;
      const off = shift(layer.z);
      const px = (layer.box.x0 + off.x) * s, py = (layer.box.y0 + off.y) * s;
      const q = rise(order);
      to.setTransform(1, 0, 0, 1, 0, 0);
      if (q >= 0.999 || !state.fold) { to.drawImage(entry.canvas, px, py); return; }
      const slope = (1 - q) * drop / foldX;         // the far end of the page hangs `drop` points low
      to.save();
      to.beginPath(); to.rect(foldX * s, 0, canvas.width - foldX * s, canvas.height); to.clip();
      to.drawImage(entry.canvas, px, py);
      to.restore();
      to.save();
      to.beginPath(); to.rect(0, 0, foldX * s, canvas.height); to.clip();
      to.setTransform(1, -slope, 0, 1, 0, slope * foldX * s);
      to.drawImage(entry.canvas, px, py);
      to.restore();
    };

    ctx.globalAlpha = cloudsOut;
    for (const { layer, x, y } of cloudPlaces) {
      // A strip on the leading page slides in from the wing as the Duo opens.
      const q = opening != null && x < foldX ? rise(2 + layer.index * 0.6) : 1;
      const off = shift(layer.z);
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.drawImage(bitmaps.get(layer.id).canvas, (x + layer.box.x0 + off.x - (1 - q) * 150) * s, (y + layer.box.y0 + off.y) * s);
    }
    ctx.globalAlpha = 1;

    // The flats, stacked once into two sheets (the far four; the tree and the near four) and kept
    // until the light, the tilt or the pop-up moves: a still frame is then two drawImages.
    const stackKey = `${geomKey}|${lightKey}|${tilt.x},${tilt.y}|${opening}`;
    if (stacks.key !== stackKey) {
      stacks.key = stackKey;
      for (const [index, stack] of stacks.canvases.entries()) {
        if (stack.width !== pw || stack.height !== ph) { stack.width = pw; stack.height = ph; }
        const to = stack.getContext('2d');
        to.setTransform(1, 0, 0, 1, 0, 0);
        to.globalAlpha = 1; to.globalCompositeOperation = 'source-over';
        to.clearRect(0, 0, pw, ph);
        ridges.forEach((layer, k) => {
          if ((k < 4) !== (index === 0)) return;
          if (k === 5 && tree) {
            // The tree unfolds last, standing up from its foot behind its hill.
            const up = opening == null ? 1 : easeOut((opening - 0.75) / 0.85);
            const hill = rise(5), drop = 70 + 5 * 22;
            const sink = state.fold ? (1 - hill) * drop * (foldX - tree.baseX) / foldX : 0;
            for (const part of tree.layers) {
              const entry = bitmaps.get(part.id);
              if (!entry || up < 0.04) continue;
              const off = shift(part.z);
              to.setTransform(s, 0, 0, s, 0, 0);
              to.translate(tree.baseX + off.x, tree.baseY + off.y + sink);
              to.scale(1, Math.max(0.02, up));
              to.translate(-tree.baseX, -tree.baseY);
              to.drawImage(entry.canvas, part.box.x0, part.box.y0, entry.canvas.width / s, entry.canvas.height / s);
            }
          }
          place(to, layer, k, 70 + k * 22);
        });
      }
    }
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.drawImage(stacks.canvases[0], 0, 0);
    ctx.setTransform(s, 0, 0, s, 0, 0);
    paintScraps(ctx, state, light, time, false);
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.drawImage(stacks.canvases[1], 0, 0);
    ctx.setTransform(s, 0, 0, s, 0, 0);
    paintScraps(ctx, state, light, time, true);
    paintFireflies(ctx, state, light, time);

    soften(state, light, `${stackKey}|${cloudsOut.toFixed(2)}|${cloudPlaces.map((c) => round(c.x, 1.5)).join(',')}|${time == null ? '' : Math.floor(time / 2)}|${state.event ? state.event.age : ''}`);

    // The bedtime moment's caption, by tonight's star.
    const veil = state.veil ?? 0;
    if (veil > 0.01 && state.asleep === 'night' && state.event && state.event.kind === 'bedtime') {
      ctx.setTransform(s, 0, 0, s, 0, 0);
      ctx.globalAlpha = veil * clamp01((state.event.age - 0.9) / 0.9) * 0.8;
      ctx.fillStyle = cssLab(light.pal.ink);
      ctx.font = '700 9.5px "Nunito", ui-rounded, system-ui, sans-serif';
      ctx.textAlign = 'right';
      ctx.textBaseline = 'middle';
      if ('letterSpacing' in ctx) ctx.letterSpacing = '1.3px';
      ctx.fillText(`NIGHT ${Math.floor(state.ageDays) + 1}`, lay.tonight.x - 9, lay.tonight.y + 0.5);
      if ('letterSpacing' in ctx) ctx.letterSpacing = '0px';
      ctx.globalAlpha = 1;
    }

    lastFrame = frameKey;
    const took = performance.now() - started;
    stats.frames += 1;
    if (stats.first == null) stats.first = took; else if (relit) stats.relight = took; else stats.steady = took;
    host.dataset.paperTheatre = JSON.stringify(stats);
  }

  function destroy() {
    destroyed = true;
    bitmaps.clear();
    canvas.remove();
  }

  return { render, destroy };
}
