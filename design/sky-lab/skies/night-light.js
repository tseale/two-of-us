// Night-light — the sky as a field of soft light.
//
// Almost nothing is drawn. One fragment shader lays down light the way a
// night-light glows on a nursery wall: a vertical ramp of colour built in
// OKLab (the hue travels: ember, apricot, a breath of green-gold, rose, lilac,
// blue), turning from warm to cool with distance from the sun; the sun and the
// moon as soft orbs whose light pools and tints everything; three broad swells
// of tone for land, with mist lying between them; a slow unevenness in the
// light where another sky would have clouds; a fine film grain that is also
// the dither. Over it, on a 2-D canvas, the one sharp thing: his stars — a
// crisp point for every night of his life.
//
//   field  (WebGL2)   everything soft.            → SwiftUI: one small Metal shader
//                                                   (`colorEffect`), or five gradients
//   points (canvas)   his stars, the ordinary     → SwiftUI: one `Canvas` of points
//                     sky, snow / petals /
//                     fireflies / leaves, the
//                     bedtime caption
//
// Layout is in points from the display's top-left, world x = 0 at
// `state.phone.x` (README: one world, two windows). The horizon is put where it
// can be seen: on the Duo in the seam between the Today card and the log tiles
// (y 292), which is also the middle of the system strip's clear window.

import { presence } from '../lab/presence.js';
import { toOklab, hex, smoothstep, lerp, HUSH, DARK_HUSH } from '../lab/oklab.js';
import { nights, twinkle, ignition, hash } from '../lab/nights.js';
import { season } from '../lab/season.js';
import { rng } from '../lab/noise.js';

export const meta = {
  id: 'night-light',
  name: 'Night-light',
  blurb: 'Pure light, almost no drawing: a soft field that follows the sun and the moon, and one sharp thing — a crisp star for every night of his life.',
};

// ───────────────────────────────────────────────────────────── helpers ──

const DEG = Math.PI / 180;
const TAU = Math.PI * 2;
const clamp01 = (x) => Math.min(1, Math.max(0, x));
/** OKLCH (hue in degrees) → OKLab. Every colour in this file is written as [L, C, h]. */
const lch = ([L, C, h]) => ({ L, a: C * Math.cos(h * DEG), b: C * Math.sin(h * DEG) });
const mixLab = (A, B, t) => ({ L: A.L + (B.L - A.L) * t, a: A.a + (B.a - A.a) * t, b: A.b + (B.b - A.b) * t });

function labToRgb({ L, a, b }) {
  const l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3;
  const m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3;
  const s = (L - 0.0894841775 * a - 1.291485548 * b) ** 3;
  const lin = [
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s,
  ];
  return lin.map((c) => {
    const v = clamp01(c);
    return Math.round(255 * (v <= 0.0031308 ? 12.92 * v : 1.055 * Math.pow(v, 1 / 2.4) - 0.055));
  });
}
const cssLab = (lab, alpha = 1) => { const [r, g, b] = labToRgb(lab); return `rgba(${r},${g},${b},${alpha})`; };

/** A value keyed by the sun's altitude in degrees: [[alt, value], …] ascending; values are numbers or arrays of [L,C,h]. */
function keyed(table, alt, mixer) {
  if (alt <= table[0][0]) return mixer(table[0][1], table[0][1], 0);
  for (let i = 0; i < table.length - 1; i++) {
    const [a0, v0] = table[i], [a1, v1] = table[i + 1];
    if (alt <= a1) return mixer(v0, v1, (alt - a0) / (a1 - a0));
  }
  const last = table[table.length - 1][1];
  return mixer(last, last, 0);
}
const mixNumber = (a, b, t) => a + (b - a) * t;
const mixStops = (A, B, t) => A.map((c, i) => mixLab(lch(c), lch(B[i]), t));

/** A colour at position x on [[pos, lab], …]. */
function rampAt(stops, x) {
  if (x <= stops[0][0]) return stops[0][1];
  for (let i = 0; i < stops.length - 1; i++) {
    const [x0, c0] = stops[i], [x1, c1] = stops[i + 1];
    if (x <= x1) return mixLab(c0, c1, (x - x0) / (x1 - x0));
  }
  return stops[stops.length - 1][1];
}

/** A row of OKLab colours, blurred (a Gaussian of `sigma` samples, edges held). */
function smoothRow(row, sigma) {
  const reach = Math.ceil(sigma * 3);
  const kernel = [];
  for (let k = -reach; k <= reach; k++) kernel.push(Math.exp(-(k * k) / (2 * sigma * sigma)));
  const total = kernel.reduce((a, b) => a + b, 0);
  return row.map((_, i) => {
    let L = 0, a = 0, b = 0;
    for (let k = -reach; k <= reach; k++) {
      const c = row[Math.min(row.length - 1, Math.max(0, i + k))];
      const w = kernel[k + reach] / total;
      L += c.L * w; a += c.a * w; b += c.b * w;
    }
    return { L, a, b };
  });
}

// ───────────────────────────────────────────────────────────── palette ──
// All at FULL strength; `quiet()` below hushes them by presence (the lab's rule).

const PAGE = { light: toOklab(hex('#F2F2F7')), dark: lch([0.105, 0.012, 280]) };

/** The air away from the sun, by the sun's altitude: horizon, low, middle, zenith. */
const AIR_AT = [0, 0.15, 0.45, 1];
const AIR = {
  light: [
    [-18, [[0.872, 0.030, 276], [0.858, 0.036, 272], [0.838, 0.044, 268], [0.815, 0.052, 265]]],
    [-10, [[0.868, 0.038, 270], [0.860, 0.042, 270], [0.846, 0.048, 268], [0.826, 0.055, 266]]],
    [-5, [[0.852, 0.046, 258], [0.858, 0.046, 276], [0.850, 0.052, 270], [0.834, 0.060, 266]]],
    [-1, [[0.870, 0.038, 256], [0.886, 0.028, 290], [0.878, 0.036, 276], [0.852, 0.046, 266]]],
    [4, [[0.922, 0.024, 40], [0.914, 0.028, 310], [0.896, 0.038, 274], [0.868, 0.048, 266]]],
    [12, [[0.945, 0.026, 80], [0.928, 0.026, 250], [0.902, 0.046, 256], [0.870, 0.064, 260]]],
    [30, [[0.955, 0.028, 92], [0.936, 0.024, 236], [0.906, 0.046, 250], [0.874, 0.064, 257]]],
  ],
  dark: [
    [-18, [[0.228, 0.030, 266], [0.215, 0.032, 268], [0.196, 0.032, 270], [0.176, 0.030, 274]]],
    [-10, [[0.238, 0.038, 262], [0.228, 0.042, 266], [0.208, 0.042, 268], [0.186, 0.040, 270]]],
    [-5, [[0.250, 0.048, 256], [0.255, 0.052, 272], [0.236, 0.052, 270], [0.212, 0.052, 270]]],
    [-1, [[0.268, 0.048, 252], [0.285, 0.052, 278], [0.268, 0.056, 272], [0.236, 0.058, 270]]],
    [4, [[0.322, 0.046, 330], [0.302, 0.050, 292], [0.274, 0.058, 272], [0.242, 0.062, 268]]],
    [12, [[0.318, 0.046, 250], [0.300, 0.052, 254], [0.275, 0.060, 260], [0.245, 0.066, 265]]],
    [30, [[0.320, 0.046, 242], [0.302, 0.052, 250], [0.278, 0.060, 258], [0.248, 0.066, 264]]],
  ],
};

/** The sun's side: the ladder of warm colour that climbs from the horizon —
 *  s = elevation / reach. Twilight's (sun low) and the day's (a cream haze). */
const LADDER_AT = [0, 0.2, 0.42, 0.6, 0.8, 1];
const LADDER = {
  light: {
    twilight: [[0.868, 0.118, 48], [0.892, 0.104, 64], [0.922, 0.078, 84], [0.934, 0.044, 102], [0.926, 0.018, 140], [0.896, 0.028, 240]],
    day: [[0.968, 0.050, 82], [0.962, 0.044, 86], [0.955, 0.034, 90], [0.948, 0.022, 100], [0.938, 0.014, 200], [0.926, 0.022, 240]],
  },
  dark: {
    twilight: [[0.500, 0.125, 48], [0.455, 0.120, 38], [0.395, 0.108, 22], [0.340, 0.090, 356], [0.300, 0.075, 322], [0.270, 0.062, 290]],
    day: [[0.345, 0.050, 20], [0.335, 0.048, 350], [0.320, 0.048, 320], [0.305, 0.050, 295], [0.290, 0.055, 275], [0.275, 0.058, 266]],
  },
};
/** How strong the ladder is, how high it reaches (in elevation, 0–1), and how much of it is twilight's. */
const LADDER_STRENGTH = [[-18, 0], [-14, 0.22], [-10, 0.55], [-5, 0.92], [-1, 1], [3, 1], [8, 0.8], [20, 0.5], [60, 0.4]];
const LADDER_REACH = [[-18, 0.14], [-14, 0.2], [-10, 0.34], [-5, 0.7], [-1, 0.86], [3, 0.8], [8, 0.56], [20, 0.36], [60, 0.3]];
const LADDER_TWILIGHT = [[-18, 1], [3, 1], [6, 0.8], [14, 0], [60, 0]];

/** Opposite the sun: the Belt of Venus (rose) over the earth's shadow (slate), around sunset. */
const BELT = {
  light: { rose: [0.888, 0.044, 12], shadow: [0.856, 0.038, 254] },
  dark: { rose: [0.310, 0.068, 4], shadow: [0.232, 0.046, 254] },
};
const BELT_STRENGTH = [[-8, 0], [-5, 0.7], [-2, 1], [1, 0.75], [4, 0]];

/** The sun's pool of light, by distance from it in points: [radius, [L,C,h], alpha]. */
const POOL = {
  light: {
    twilight: [[0, [0.985, 0.035, 90], 0.95], [16, [0.972, 0.055, 86], 0.82], [38, [0.948, 0.080, 76], 0.58], [86, [0.925, 0.092, 62], 0.36], [180, [0.900, 0.085, 44], 0.19], [330, [0.885, 0.060, 18], 0.08], [620, [0.870, 0.050, 330], 0]],
    day: [[0, [0.998, 0.020, 95], 0.95], [16, [0.994, 0.030, 92], 0.8], [38, [0.986, 0.040, 88], 0.56], [86, [0.976, 0.044, 84], 0.36], [180, [0.966, 0.038, 80], 0.2], [330, [0.956, 0.026, 76], 0.08], [620, [0.95, 0.02, 70], 0]],
  },
  dark: {
    twilight: [[0, [0.780, 0.125, 76], 0.95], [16, [0.650, 0.145, 60], 0.8], [38, [0.520, 0.145, 48], 0.55], [86, [0.420, 0.130, 34], 0.34], [180, [0.340, 0.110, 15], 0.18], [330, [0.280, 0.085, 345], 0.07], [620, [0.25, 0.07, 320], 0]],
    day: [[0, [0.620, 0.100, 72], 0.9], [16, [0.520, 0.100, 62], 0.7], [38, [0.430, 0.090, 50], 0.42], [86, [0.370, 0.075, 30], 0.22], [180, [0.330, 0.060, 340], 0.1], [330, [0.300, 0.055, 290], 0.04], [620, [0.28, 0.05, 270], 0]],
  },
};
const POOL_MAX = 620;
const SUN_DISC = {
  light: { twilight: [0.992, 0.030, 92], day: [0.995, 0.010, 95] },
  dark: { twilight: [0.860, 0.105, 80], day: [0.700, 0.090, 80] },
};

const MOON = {
  light: { disc: [0.998, 0.006, 95], glow: [0.955, 0.012, 280], near: [0.985, 0.012, 95] },
  dark: { disc: [0.945, 0.028, 90], glow: [0.330, 0.034, 262], near: [0.560, 0.040, 85] },
};

/** The land's own tone, by season: [far, middle, near] swells. Mixed with the
 *  air at the horizon (far most of all), so distance reads as light. */
const LAND = {
  light: {
    winter: [[0.930, 0.018, 250], [0.945, 0.016, 255], [0.955, 0.012, 262]],
    spring: [[0.895, 0.040, 128], [0.876, 0.050, 126], [0.858, 0.056, 124]],
    summer: [[0.886, 0.040, 138], [0.864, 0.050, 134], [0.846, 0.056, 130]],
    autumn: [[0.884, 0.028, 44], [0.862, 0.034, 48], [0.842, 0.038, 52]],
  },
  dark: {
    winter: [[0.250, 0.022, 250], [0.240, 0.022, 252], [0.228, 0.020, 256]],
    spring: [[0.225, 0.034, 140], [0.195, 0.038, 136], [0.165, 0.038, 132]],
    summer: [[0.215, 0.034, 150], [0.185, 0.038, 146], [0.158, 0.038, 142]],
    autumn: [[0.230, 0.036, 22], [0.198, 0.040, 28], [0.168, 0.040, 34]],
  },
};
/** How much of the land's own tone each swell keeps (the rest is the air's). */
const LAND_OWN = [0.42, 0.66, 0.84];

/** Season as temperature: what it does to warm colours and to cool ones — [hue turn, chroma ×, lightness +]. */
const TEMPERATURE = {
  winter: { warm: [-16, 0.72, 0.008], cool: [-12, 1.12, 0.008] },
  spring: { warm: [16, 0.95, 0.004], cool: [-6, 0.95, 0.004] },
  summer: { warm: [5, 1.16, 0], cool: [6, 0.95, -0.004] },
  autumn: { warm: [-9, 1.08, -0.008], cool: [10, 0.9, -0.004] },
};

/** Season temperature on one OKLab colour. Warm hues (reds to golds) and cool
 *  ones (blues to violets) turn separately; in between is left alone. */
function temper(lab, weights) {
  const C = Math.hypot(lab.a, lab.b);
  if (C < 1e-5) return lab;
  let h = Math.atan2(lab.b, lab.a) / DEG;
  if (h < 0) h += 360;
  const isWarm = h <= 105 || h >= 350 ? 1 : h < 135 ? 1 - (h - 105) / 30 : h > 330 ? (h - 330) / 20 : 0;
  const isCool = h >= 225 && h <= 300 ? 1 : h > 195 && h < 225 ? (h - 195) / 30 : h > 300 && h < 330 ? 1 - (h - 300) / 30 : 0;
  let turn = 0, gain = 1, lift = 0;
  for (const name of Object.keys(TEMPERATURE)) {
    const w = weights[name] ?? 0;
    if (!w) continue;
    const { warm: wm, cool: cl } = TEMPERATURE[name];
    turn += w * (isWarm * wm[0] + isCool * cl[0]);
    gain *= 1 + w * (isWarm * (wm[1] - 1) + isCool * (cl[1] - 1));
    lift += w * (isWarm * wm[2] + isCool * cl[2]);
  }
  const hh = (h + turn) * DEG;
  return { L: lab.L + lift, a: C * gain * Math.cos(hh), b: C * gain * Math.sin(hh) };
}

/** The lab's hush (oklab.js `present` / `presentDark`), on OKLab directly:
 *  the hue is kept, the chroma falls to a fraction, and the lightness goes
 *  toward the page (light) or a little toward black (dark). `night` (0–1)
 *  pulls the light appearance less toward the page, as today's sky does. */
function quiet(lab, p, scheme, night = 0) {
  const k = clamp01(p);
  if (scheme === 'light') {
    const toward = lerp(HUSH.toward, 0.34, night) * (1 - k);
    const chroma = lerp(HUSH.chroma + 0.12, 0.42, night);
    const c = chroma + (1 - chroma) * k;
    return { L: lab.L + (PAGE.light.L - lab.L) * toward, a: lab.a * c, b: lab.b * c };
  }
  const c = DARK_HUSH.chroma + 0.1 + (1 - DARK_HUSH.chroma - 0.1) * k;
  return { L: lab.L * (1 - DARK_HUSH.darken * (1 - k)), a: lab.a * c, b: lab.b * c };
}

// ────────────────────────────────────────────────────────────── layout ──

/** Where things are on this display, in points. */
function layoutFor(state) {
  const W = state.phone.width;
  const H = state.height;
  const slab = state.device === 'iphone';
  return {
    W, H, slab,
    ox: state.phone.x,
    // The seam between the Today card and the log tiles.
    hy: slab ? 340 : 292,
    // The top of the sun's and the moon's arc: just under the top edge on the Duo
    // (above the header's text), between the status bar and the header on the slab.
    orbTop: slab ? 61 : 12,
    // How the sky's layers are spread over the height: 1 is even; more keeps the
    // low, colourful layers for longer (the slab's only window is its top band).
    ePow: slab ? 2.3 : 1,
    landScale: slab ? 1.7 : 1,
    // Tonight's star, before it joins the others: the evening star, low in the
    // strip's clear window (Duo), or right of his name in the header (slab).
    tonight: slab ? { x: 286, y: 100 } : { x: 450, y: 211 },
  };
}

/** Rectangles (points, display coordinates) where words sit on the sky — his
 *  name and age in the header: an orb passes over them, never behind, and goes
 *  soft if it must come near. Fixed numbers (the header's layout), not
 *  `state.cards`, so the sky is the same with the chrome drawn or not. */
function quietRects(state, L) {
  return L.slab ? [[L.ox + 88, 73, L.ox + 186, 131]] : [[L.ox + 92, 25, L.ox + 190, 84]];
}

/** An orb's height, lifted clear of any words it would otherwise sit behind
 *  (it passes over his name, it does not cross it). */
function clearOfWords(x, y, radius, rects) {
  let out = y;
  for (const [x0, y0, x1, y1] of rects) {
    if (out + radius < y0 - 2 || out - radius > y1 + 2) continue;
    const inside = smoothstep(x0 - radius - 16, x0 - radius + 4, x) * (1 - smoothstep(x1 + radius - 4, x1 + radius + 16, x));
    out = lerp(out, Math.min(out, y0 - radius - 3), inside);
  }
  return out;
}

// ─────────────────────────────────────────────────────── his stars' places ──

/** How much of the starfield wants to be at (x, y) in the anchor window — more
 *  where the sky shows (the top band, the strip, the margins), none where
 *  something opaque or a word sits. Fixed numbers, not `state.cards`: a star's
 *  place must not depend on whether the chrome is drawn. */
function starWeight(x, y, L) {
  const box = (x0, y0, x1, y1, soft = 3) => smoothstep(x0 - soft, x0 + soft, x) * (1 - smoothstep(x1 - soft, x1 + soft, x))
    * smoothstep(y0 - soft, y0 + soft, y) * (1 - smoothstep(y1 - soft, y1 + soft, y));
  const disc = (cx, cy, r) => 1 - smoothstep(r - 2, r + 3, Math.hypot(x - cx, y - cy));
  let w;
  let hole = 0;
  if (!L.slab) {
    w = 0.3;
    w = Math.max(w, 1.0 * (1 - smoothstep(80, 94, y)));                      // the top band
    w = Math.max(w, 1.5 * smoothstep(362, 374, x));                           // the strip
    w = Math.max(w, 1.1 * (1 - smoothstep(14, 20, x)));                       // the leading margin
    w = Math.max(w, 1.25 * box(200, 6, 314, 84, 6));                          // the header's clear window
    hole = Math.max(hole, disc(50, 52.3, 34));                                // avatar
    hole = Math.max(hole, box(84, 18, 198, 90, 4));                           // name and age
    hole = Math.max(hole, disc(340, 52.3, 26));                               // gear
    hole = Math.max(hole, box(396, 44, 453, 192, 4));                         // the island (as long as a sleep makes it) and wifi / battery
    hole = Math.max(hole, box(388, 8, 460, 42, 4));                           // the clock
  } else {
    w = 0.3;
    w = Math.max(w, 1.0 * (1 - smoothstep(126, 140, y)));
    w = Math.max(w, 1.2 * Math.max(1 - smoothstep(11, 16, x), smoothstep(386, 391, x)));
    hole = Math.max(hole, box(22, 10, 92, 46, 4));                            // clock
    hole = Math.max(hole, box(132, 6, 270, 52, 4));                           // island
    hole = Math.max(hole, box(296, 12, 384, 44, 4));                          // status icons
    hole = Math.max(hole, disc(46, 100.3, 34));                               // avatar
    hole = Math.max(hole, box(80, 66, 206, 136, 4));                          // name and age
    hole = Math.max(hole, disc(364, 100.3, 26));                              // gear
  }
  // Thinner in the haze just over the horizon.
  w *= 0.25 + 0.75 * (1 - smoothstep(L.hy - 46, L.hy - 6, y));
  return w * (1 - hole);
}

/** (u, v) in 0–1 → a place in the anchor window, by the weight above: v picks a
 *  row, u a column in it (two inverse CDFs), so the lab's evenly-filling
 *  sequence stays even while most stars land where they can be seen. */
function makeStarMap(L) {
  const COLS = 120, ROWS = 76;
  const top = 2, bottom = L.hy - 4;
  const cellW = L.W / COLS, cellH = (bottom - top) / ROWS;
  const rows = new Float64Array(ROWS + 1);
  const cols = [];
  for (let j = 0; j < ROWS; j++) {
    const cdf = new Float64Array(COLS + 1);
    for (let i = 0; i < COLS; i++) cdf[i + 1] = cdf[i] + starWeight((i + 0.5) * cellW, top + (j + 0.5) * cellH, L) + 1e-6;
    rows[j + 1] = rows[j] + cdf[COLS];
    cols.push(cdf);
  }
  const pick = (cdf, n, value) => {
    const target = value * cdf[n];
    let lo = 0, hi = n;
    while (hi - lo > 1) { const mid = (lo + hi) >> 1; if (cdf[mid] <= target) lo = mid; else hi = mid; }
    return lo + (target - cdf[lo]) / (cdf[lo + 1] - cdf[lo]);
  };
  return (u, v) => {
    const r = pick(rows, ROWS, v);
    const j = Math.min(ROWS - 1, Math.floor(r));
    const c = pick(cols[j], COLS, u);
    return { x: c * cellW, y: top + r * cellH };
  };
}

// ────────────────────────────────────────────────────────────── shader ──

const VERT = `#version 300 es
in vec2 aPos;
void main() { gl_Position = vec4(aPos, 0.0, 1.0); }`;

const FRAG = `#version 300 es
precision highp float;
out vec4 outColor;

uniform vec2 uRes;            // device pixels
uniform float uDpr;
uniform float uOx, uW, uH;    // the anchor window's left edge and width, the display's height (points)
uniform float uHy, uEpow, uLandScale;
uniform sampler2D uLut;       // 256 x 3, OKLab: the sun's side by elevation, the far side, the sun's pool by distance (a = strength)
uniform float uPoolMax;
uniform vec3 uSun;            // x (display), y, disc radius
uniform vec4 uSunDisc;        // OKLab, strength
uniform float uSunSoft;       // how out of focus the disc is, 0 crisp-soft … 1 dissolved
uniform vec2 uWarm;           // how far the warm side spreads: at the horizon, high up (fractions of uW)
uniform vec4 uMoon;           // x, y, radius, strength
uniform vec3 uMoonPhase;      // terminator (1 new … -1 full), cos, sin of its turn
uniform vec3 uMoonDisc, uMoonGlow, uMoonNear;
uniform vec3 uMoonAmt;        // near glow, wide glow, light on the land
uniform vec3 uLandTone[3];    // OKLab, far → near
uniform vec3 uLandOwn;
uniform float uLandWarm;       // how much of the sun's side the land takes at the horizon
uniform float uHaze;           // how much of the pool hangs in front of the land
uniform vec3 uMist;           // how far each swell lightens toward its foot
uniform vec3 uRim;            // OKLab of the light that catches a crest
uniform float uRimAmt;
uniform vec4 uFrost;           // OKLab, amount
uniform vec3 uPage;           // OKLab the ground settles into under the cards
uniform float uPageAmt;
uniform vec2 uSettle;          // where the settling starts and ends, points below the horizon
uniform float uT;
uniform float uVary;          // the slow unevenness of the light
uniform vec4 uRing;           // x, y, radius, strength — bedtime's ring of light
uniform vec3 uRingTint;
uniform vec4 uOpen;           // the fold's x, how far the light has reached (points), softness, how dim the unlit side is
uniform vec2 uTilt;
uniform float uGrain;
uniform float uDim;           // the room dimmed (asleep): lightness ×
uniform vec4 uQuiet[3];       // rectangles where words sit
uniform int uQuietCount;

// ---- noise: integer hashes, so there is no pattern at any zoom and no drift between GPUs
uint pcg(uint v) {
  uint s = v * 747796405u + 2891336453u;
  uint w = ((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u;
  return (w >> 22u) ^ w;
}
float ihash(ivec2 q, uint seed) {
  return float(pcg(uint(q.x) + pcg(uint(q.y) + pcg(seed)))) * (1.0 / 4294967296.0);
}
float vnoise(vec2 p, uint seed) {
  vec2 i = floor(p), f = fract(p);
  vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
  ivec2 c = ivec2(i);
  float a = ihash(c, seed), b = ihash(c + ivec2(1, 0), seed);
  float d = ihash(c + ivec2(0, 1), seed), e = ihash(c + ivec2(1, 1), seed);
  return mix(mix(a, b, u.x), mix(d, e, u.x), u.y);
}
float soft2(vec2 p, uint seed) {
  // each octave turned off the screen's axes, so no cell edge ever lines up with the horizon
  return 0.62 * vnoise(mat2(0.891, -0.454, 0.454, 0.891) * p, seed) + 0.38 * vnoise(mat2(0.809, 0.588, -0.588, 0.809) * p * 2.07 + 31.7, seed + 7u);
}

vec3 unoklab(vec3 lab) {
  float l = lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z;
  float m = lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z;
  float s = lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z;
  l = l * l * l; m = m * m * m; s = s * s * s;
  vec3 c = vec3(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s);
  c = clamp(c, 0.0, 1.0);
  return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
}

vec4 lut(float x, float row) { return texture(uLut, vec2((clamp(x, 0.0, 1.0) * 255.0 + 0.5) / 256.0, (row + 0.5) / 3.0)); }

float crest(int i, float xw) {
  if (i == 0) return uHy + uLandScale * (3.0 + 5.0 * sin(xw * 0.0052 + 1.3) + 2.6 * sin(xw * 0.0121 + 4.1));
  if (i == 1) return uHy + uLandScale * (31.0 + 11.0 * sin(xw * 0.0068 + 2.6) + 4.5 * sin(xw * 0.0163 + 0.7));
  return uHy + uLandScale * (76.0 + 16.0 * sin(xw * 0.0047 + 5.2) + 6.0 * sin(xw * 0.0109 + 3.3));
}

void main() {
  vec2 p = vec2(gl_FragCoord.x, uRes.y - gl_FragCoord.y) / uDpr;     // points, y down
  float xw = p.x - uOx;

  // The slow unevenness of the light: two broad fields, drifting.
  float drift = uT * 0.9;
  float n1 = soft2(vec2((xw + drift) / 520.0 + 40.0, p.y / 210.0 + 3.1), 1u);
  float n2 = vnoise(mat2(0.966, -0.259, 0.259, 0.966) * vec2((xw + drift * 1.7) / 700.0 + 49.3, p.y / 80.0), 2u);    // long bands, low
  float vary = uVary;

  // Elevation: 0 at the horizon, 1 at the top edge.
  float eLin = clamp((uHy - p.y) / uHy, 0.0, 1.0);
  float e = pow(eLin, uEpow);
  float eW = clamp(e + vary * ((n1 - 0.5) * 0.16 + (n2 - 0.5) * 0.10 * (1.0 - e)), 0.0, 1.0);

  // Warm toward the sun, cool away from it — wider along the horizon than overhead.
  float d = (p.x - uSun.x) / uW;
  float sigma = mix(uWarm.y, uWarm.x, exp(-e * 3.2));
  float warm = exp(-pow(abs(d) / sigma, 1.7));
  warm = clamp(warm * (1.0 + vary * (n2 - 0.5) * 0.5), 0.0, 1.0);

  vec3 sunSide = lut(eW, 0.0).rgb;
  vec3 farSide = lut(eW, 1.0).rgb;
  vec3 col = mix(farSide, sunSide, warm);
  vec3 horizonCol = mix(lut(0.0, 1.0).rgb, lut(0.0, 0.0).rgb, warm * uLandWarm);

  // Words on the sky: an orb behind them goes soft.
  float hushed = 0.0;
  for (int i = 0; i < 3; i++) {
    if (i >= uQuietCount) break;
    vec4 r = uQuiet[i];
    vec2 q = max(max(r.xy - p, p - r.zw), 0.0);
    hushed = max(hushed, 1.0 - smoothstep(0.0, 9.0, length(q)));
  }

  // The sun's pool: wide and elliptical, hue travelling outward.
  vec2 ds = p - uSun.xy;
  float rs = length(ds * vec2(0.74, 1.0));
  vec4 pool = lut(sqrt(clamp(rs / uPoolMax, 0.0, 1.0)), 2.0);
  float poolA = pool.a * (1.0 + vary * (n1 - 0.5) * 0.5);
  col = mix(col, pool.rgb, clamp(poolA * (1.0 - 0.45 * hushed), 0.0, 1.0));

  // The moon's quiet light.
  vec2 dm = p - uMoon.xy;
  float rm = length(dm);
  col = mix(col, uMoonGlow, clamp(uMoon.w * uMoonAmt.y * exp(-rm / 150.0), 0.0, 1.0));
  col = mix(col, uMoonNear, clamp(uMoon.w * uMoonAmt.x * exp(-max(rm - uMoon.z, 0.0) / (uMoon.z * 1.25)) * (1.0 - 0.7 * hushed), 0.0, 1.0));

  col.x *= uDim;

  // The discs. Soft orbs: no edge, only a falling-off.
  float rd = length(ds);
  float soften = mix(uSunSoft, 1.0, hushed * 0.8);
  float disc = 1.0 - smoothstep(uSun.z * mix(0.62, 0.05, soften), uSun.z * mix(1.12, 2.3, soften), rd);
  disc *= mix(1.0, 0.42, soften);
  col = mix(col, uSunDisc.rgb, disc * uSunDisc.a);

  vec2 mq = vec2(dm.x * uMoonPhase.y + dm.y * uMoonPhase.z, -dm.x * uMoonPhase.z + dm.y * uMoonPhase.y) / uMoon.z;
  float mr = length(mq);
  float moonDisc = 1.0 - smoothstep(0.7, 1.1, mr);
  float limb = uMoonPhase.x * sqrt(max(0.0, 1.0 - mq.y * mq.y));
  float lit = smoothstep(limb - 0.2, limb + 0.2, mq.x);
  float moonA = moonDisc * mix(0.05, 1.0, lit) * uMoon.w * (1.0 - 0.75 * hushed);
  col = mix(col, vec3(uMoonDisc.x * (1.0 - 0.07 * mr * mr), uMoonDisc.yz), moonA);

  // Land: three swells of tone. Each takes the air's colour by its distance,
  // is darkest along its crest and lightens toward its foot, where mist lies.
  float under = 0.0;
  for (int i = 0; i < 3; i++) {
    float par = (i == 0) ? 2.0 : (i == 1) ? 4.5 : 8.0;
    float c = crest(i, xw + uTilt.x * par) - uTilt.y * par * 0.4;
    float softness = (i == 0) ? 7.0 : (i == 1) ? 6.0 : 5.5;
    softness *= uLandScale;
    float cover = smoothstep(-softness, softness, p.y - c);
    float depth = max(0.0, p.y - c);
    float tau = ((i == 0) ? 16.0 : (i == 1) ? 26.0 : 60.0) * uLandScale;
    float mist = 1.0 - exp(-depth / tau);
    mist *= 1.0 + (n2 - 0.5) * 0.6;
    float breathe = 0.5 + 0.5 * sin(uT * (6.2832 / (41.0 + float(i) * 13.0)) + float(i) * 2.1);
    vec3 own = uLandTone[i];
    vec3 tone = mix(horizonCol, own, uLandOwn[i]);
    vec3 foot = mix(tone, horizonCol, uMist[i] * (0.86 + 0.14 * breathe));
    vec3 body = mix(tone, foot, clamp(mist, 0.0, 1.0));
    body = mix(body, uFrost.rgb, uFrost.a * exp(-depth / (11.0 * uLandScale)) * (0.6 + 0.8 * n1));
    // Light skimming the crest, on the sun's side; and the moon's.
    float skim = exp(-depth / (5.0 * uLandScale)) * exp(-pow(abs(d) / (uWarm.x * 0.8), 1.6));
    body = mix(body, uRim, clamp(uRimAmt * skim * (1.0 - 0.22 * float(i)), 0.0, 1.0));
    float mskim = exp(-depth / (9.0 * uLandScale)) * exp(-abs(p.x - uMoon.x) / 170.0);
    body = mix(body, uMoonGlow, clamp(uMoon.w * uMoonAmt.z * mskim, 0.0, 1.0));
    body.x *= uDim;
    col = mix(col, body, cover);
    under = max(under, cover);
  }
  // Haze in front of the land carries a little of the pools.
  col = mix(col, pool.rgb, clamp(poolA * uHaze * under, 0.0, 1.0));

  // Under the cards the ground settles into the page.
  float settle = smoothstep(uHy + uSettle.x * uLandScale, uHy + uSettle.y * uLandScale, p.y);
  col = mix(col, vec3(uPage.x * uDim, uPage.yz), uPageAmt * settle);

  // Bedtime: a ring of light travels outward from his star.
  if (uRing.w > 0.0) {
    float rr = length(p - uRing.xy);
    float width = 9.0 + uRing.z * 0.03;
    float band = exp(-pow((rr - uRing.z) / width, 2.0));
    float wake = exp(-max(0.0, uRing.z - rr) / (width * 4.0)) * step(rr, uRing.z) * 0.22;
    float a = uRing.w * (band + wake);
    col = mix(col, uRingTint, clamp(a, 0.0, 0.6));
  }

  // Opening the Duo: the light crosses the leading page from the fold.
  if (uOpen.w > 0.0) {
    float reach = (uOpen.x - p.x) - uOpen.y;                 // > 0: the light has not reached here yet
    float unlit = smoothstep(0.0, uOpen.z, reach) * step(p.x, uOpen.x + 40.0);
    col.x *= 1.0 - uOpen.w * unlit;
    col.yz *= 1.0 - 0.6 * uOpen.w * unlit;
  }


  vec3 rgb = unoklab(col);
  // Film grain (which is also the dither): the same on all three channels, so it never tints.
  ivec2 px = ivec2(gl_FragCoord.xy);
  float tri = ihash(px, 11u) + ihash(px, 23u) - 1.0;           // triangular, -1..1: the dither
  float clump = vnoise(gl_FragCoord.xy / 1.9, 37u) + vnoise(gl_FragCoord.xy / 3.7 + 9.0, 41u) - 1.0;   // grain is not quite white
  rgb += (tri * 0.75 + (tri * 0.55 + clump * 1.5) * uGrain) / 255.0;
  outColor = vec4(rgb, 1.0);
}`;

function compile(gl, type, source) {
  const shader = gl.createShader(type);
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    const log = gl.getShaderInfoLog(shader);
    gl.deleteShader(shader);
    throw new Error(`skies/night-light: shader: ${log}`);
  }
  return shader;
}

// ───────────────────────────────────────────────────────────── the sky ──

export function create(host) {
  const doc = host.ownerDocument ?? document;
  const field = doc.createElement('canvas');
  const points = doc.createElement('canvas');
  for (const canvas of [field, points]) {
    canvas.setAttribute('aria-hidden', 'true');
    canvas.style.cssText = 'position:absolute;left:0;top:0;display:block;pointer-events:none;';
    host.appendChild(canvas);
  }
  const gl = field.getContext('webgl2', { alpha: false, antialias: false, depth: false, stencil: false, preserveDrawingBuffer: true, powerPreference: 'low-power' });
  if (!gl) throw new Error('skies/night-light needs WebGL2');
  const ctx = points.getContext('2d');

  const program = gl.createProgram();
  gl.attachShader(program, compile(gl, gl.VERTEX_SHADER, VERT));
  gl.attachShader(program, compile(gl, gl.FRAGMENT_SHADER, FRAG));
  gl.linkProgram(program);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error(`skies/night-light: link: ${gl.getProgramInfoLog(program)}`);
  gl.useProgram(program);
  const quad = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, quad);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
  const aPos = gl.getAttribLocation(program, 'aPos');
  gl.enableVertexAttribArray(aPos);
  gl.vertexAttribPointer(aPos, 2, gl.FLOAT, false, 0, 0);
  const U = new Proxy({}, { get: (cache, name) => (cache[name] ??= gl.getUniformLocation(program, name)) });

  const lutTexture = gl.createTexture();
  gl.activeTexture(gl.TEXTURE0);
  gl.bindTexture(gl.TEXTURE_2D, lutTexture);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  gl.uniform1i(U.uLut, 0);
  const lutData = new Float32Array(256 * 3 * 4);

  let sizeKey = '';
  let starMap = null, starMapKey = '';
  let starCache = null, starCacheKey = '';
  let ordinary = null, ordinaryKey = '';
  const sprites = new Map();

  // ── the look, for one state ──

  let lookKey = '', lookCache = null, lutOwner = null;

  /** Everything about the look that does not move with `t`: cached until the
   *  clock, the appearance, the sleep or an event's age changes. */
  function look(state) {
    const key = [state.device, state.width, state.height, state.phone.x, state.scheme, state.date.getTime(), state.latitude, state.longitude,
      state.asleep, state.ageDays, state.event?.kind, state.event?.age].join('|');
    if (key === lookKey) return lookCache;
    lookKey = key;
    lookCache = computeLook(state);
    return lookCache;
  }

  function computeLook(state) {
    const L = layoutFor(state);
    const scheme = state.scheme === 'light' ? 'light' : 'dark';
    const pr = presence(state);
    const alt = state.sun.altitude / DEG;
    const sea = season(state.dayOfYear, state.latitude);
    const night = 1 - smoothstep(-13, -5, alt);
    const p = pr.presence;
    const q = (c) => quiet(temper(c, sea.weights), p, scheme, night);

    // ── the two ramps ──
    const air = keyed(AIR[scheme], alt, mixStops).map((c, i) => [AIR_AT[i], c]);
    const twilight = keyed(LADDER_TWILIGHT, alt, mixNumber);
    const ladder = LADDER[scheme].twilight.map((c, i) => [LADDER_AT[i], mixLab(lch(LADDER[scheme].day[i]), lch(c), twilight)]);
    const strength = keyed(LADDER_STRENGTH, alt, mixNumber);
    const reach = keyed(LADDER_REACH, alt, mixNumber);
    const belt = keyed(BELT_STRENGTH, alt, mixNumber);
    const rose = lch(BELT[scheme].rose), shadow = lch(BELT[scheme].shadow);

    const sunRow = [], farRow = [];
    for (let i = 0; i < 256; i++) {
      const e = i / 255;
      const a = rampAt(air, e);
      const s = e / reach;
      let sunny = a;
      if (s < 1) {
        const k = strength * (1 - smoothstep(0.3, 1, s));
        sunny = mixLab(a, rampAt(ladder, s), k);
      }
      let far = a;
      if (belt > 0) {
        const band = Math.exp(-(((e - 0.24) / 0.17) ** 2));
        const low = 1 - smoothstep(0.02, 0.2, e);
        far = mixLab(far, shadow, belt * 0.65 * low);
        far = mixLab(far, rose, belt * 0.72 * band);
      }
      sunRow.push(q(sunny));
      farRow.push(q(far));
    }

    // ── the sun ──
    const duskSide = state.sun.azimuth / DEG > 180;
    let sunX, sunY;
    if (!state.sun.isNight) {
      const body = state.scene.body;
      sunX = body.x * L.W;
      sunY = L.hy - (1 - body.y / 0.30) * (L.hy - L.orbTop);
    } else {
      const below = Math.max(0, -alt - 0.8);
      sunX = (duskSide ? 0.96 * L.W + below * 1.1 : 0.04 * L.W - below * 1.1);
      sunY = L.hy + below * 5.2;
    }
    const words = quietRects(state, L).map(([x0, y0, x1, y1]) => [x0 - L.ox, y0, x1 - L.ox, y1]);
    if (!state.sun.isNight) sunY = clearOfWords(sunX, sunY, 13, words);
    const sunUp = smoothstep(-16, -3, alt);                  // the pool lingers well after the disc has gone
    const poolTwilight = 1 - smoothstep(5, 16, alt);
    const poolStops = POOL[scheme].twilight.map(([r, c, a], i) => {
      const day = POOL[scheme].day[i];
      return [r, mixLab(lch(day[1]), lch(c), poolTwilight), lerp(day[2], a, poolTwilight)];
    });
    // After sunset the pool reddens and widens as it sinks.
    const sunk = smoothstep(0, -9, alt);
    const poolRow = [];
    for (let i = 0; i < 256; i++) {
      const r = POOL_MAX * (i / 255) ** 2;
      const rr = r / (1 + 0.55 * sunk);
      let c = poolStops[poolStops.length - 1][1], a = 0;
      for (let k = 0; k < poolStops.length - 1; k++) {
        if (rr <= poolStops[k + 1][0]) {
          const t = (rr - poolStops[k][0]) / (poolStops[k + 1][0] - poolStops[k][0]);
          c = mixLab(poolStops[k][1], poolStops[k + 1][1], t);
          a = lerp(poolStops[k][2], poolStops[k + 1][2], t);
          break;
        }
      }
      const hushedA = a * sunUp * (0.55 + 0.45 * p) * (1 - 0.5 * sunk);
      poolRow.push([q(c), hushedA]);
    }
    const discTwilight = poolTwilight;
    const sunDisc = q(mixLab(lch(SUN_DISC[scheme].day), lch(SUN_DISC[scheme].twilight), discTwilight));

    // ── the moon ──
    let moon = null;
    if (state.moon) {
      const m = state.moon;
      const up = 1 - (1 - Math.min(1, Math.max(0, m.altitude / DEG) / 62)) ** 2.4;
      const rising = smoothstep(-0.5, 2.5, m.altitude / DEG);
      moon = {
        x: m.x * L.W, y: clearOfWords(m.x * L.W, L.hy - up * (L.hy - L.orbTop) + 1, 9, words),
        radius: 8.6,
        strength: rising * lerp(scheme === 'light' ? 0.5 : 0.86, 1, 1 - smoothstep(-7, 1, alt)) * smoothstep(0.02, 0.1, m.fraction),
        dusk: 1 - smoothstep(-6, 8, alt),
        terminator: 1 - 2 * clamp01(m.fraction),
        rotation: m.rotation,
        byPhase: 0.3 + 0.7 * m.fraction,
        night,
      };
    }

    // ── the land ──
    const landTone = [0, 1, 2].map((i) => {
      let tone = { L: 0, a: 0, b: 0 };
      for (const name of ['winter', 'spring', 'summer', 'autumn']) {
        const c = lch(LAND[scheme][name][i]);
        const w = sea.weights[name];
        tone = { L: tone.L + c.L * w, a: tone.a + c.a * w, b: tone.b + c.b * w };
      }
      // Snow lying, and frost: lighter and bluer; night: toward the air.
      const snowy = lch(LAND[scheme].winter[i]);
      tone = mixLab(tone, snowy, sea.snow * 0.9);
      const airLow = rampAt(air, 0.05);
      const dusk = scheme === 'light' ? night * 0.55 : night * 0.45;
      tone = mixLab(tone, { L: airLow.L - (scheme === 'light' ? 0.03 + 0.012 * i : 0.034 + 0.022 * i), a: airLow.a, b: airLow.b }, dusk);
      return quiet(tone, p, scheme, night);
    });

    // Hoar frost: a pale, cool line of light along the crests.
    const frost = quiet(lch(scheme === 'light' ? [0.945, 0.016, 250] : [0.33, 0.026, 250]), p, scheme, night);
    return { L, scheme, pr, p, alt, sea, night, sunRow, farRow, poolRow, sunX, sunY, sunDisc, sunUp, moon, landTone, frost };
  }

  // ── the field ──

  function drawField(state, K) {
    const { L, scheme, p, alt, night } = K;
    const dpr = state.dpr;
    // The LUT (only when the look changed). Each row is smoothed, so no stop leaves a crease in the light.
    if (lutOwner !== K) {
      const sunRow = smoothRow(K.sunRow, 7), farRow = smoothRow(K.farRow, 7);
      for (let i = 0; i < 256; i++) {
        const a = sunRow[i], b = farRow[i], [c, alpha] = K.poolRow[i];
        lutData.set([a.L, a.a, a.b, 1], i * 4);
        lutData.set([b.L, b.a, b.b, 1], (256 + i) * 4);
        lutData.set([c.L, c.a, c.b, alpha], (512 + i) * 4);
      }
      gl.bindTexture(gl.TEXTURE_2D, lutTexture);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA16F, 256, 3, 0, gl.RGBA, gl.FLOAT, lutData);
      lutOwner = K;
    }

    const t = state.reduceMotion ? 0 : state.t;
    const stillness = 1 - 0.5 * K.pr.depth;
    gl.viewport(0, 0, field.width, field.height);
    gl.uniform2f(U.uRes, field.width, field.height);
    gl.uniform1f(U.uDpr, dpr);
    gl.uniform1f(U.uOx, L.ox);
    gl.uniform1f(U.uW, L.W);
    gl.uniform1f(U.uH, L.H);
    gl.uniform1f(U.uHy, L.hy);
    gl.uniform1f(U.uEpow, L.ePow);
    gl.uniform1f(U.uLandScale, L.landScale);
    gl.uniform1f(U.uPoolMax, POOL_MAX);
    gl.uniform3f(U.uSun, L.ox + K.sunX + state.tilt.x * 1.5, K.sunY + state.tilt.y * 1.0, 13);
    const discUp = smoothstep(-2.2, 0.2, alt);
    gl.uniform4f(U.uSunDisc, K.sunDisc.L, K.sunDisc.a, K.sunDisc.b, discUp * (0.5 + 0.5 * p));
    gl.uniform1f(U.uSunSoft, Math.max(1 - smoothstep(0.05, 0.8, p), L.slab ? 0.85 * smoothstep(110, 170, K.sunY) : 0));
    gl.uniform2f(U.uWarm, 0.86, 0.46);

    const m = K.moon;
    if (m) {
      gl.uniform4f(U.uMoon, L.ox + m.x + state.tilt.x * 1.5, m.y + state.tilt.y, m.radius, m.strength);
      gl.uniform3f(U.uMoonPhase, m.terminator, Math.cos(m.rotation), Math.sin(m.rotation));
      const disc = quiet(lch(MOON[scheme].disc), 1, scheme, night);
      const glow = quiet(lch(MOON[scheme].glow), Math.max(p, 0.5), scheme, night);
      const near = quiet(lch(MOON[scheme].near), Math.max(p, 0.7), scheme, night);
      gl.uniform3f(U.uMoonDisc, disc.L, disc.a, disc.b);
      gl.uniform3f(U.uMoonGlow, glow.L, glow.a, glow.b);
      gl.uniform3f(U.uMoonNear, near.L, near.a, near.b);
      const k = m.byPhase * (scheme === 'light' ? m.night : lerp(0.25, 1, m.dusk));
      if (scheme === 'light') gl.uniform3f(U.uMoonAmt, 0.7 * k, 0.16 * k, 0.2 * k);
      else gl.uniform3f(U.uMoonAmt, 0.5 * k, 0.12 * k, 0.2 * k);
    } else {
      gl.uniform4f(U.uMoon, -9999, -9999, 8.6, 0);
      gl.uniform3f(U.uMoonPhase, 0, 1, 0);
      gl.uniform3f(U.uMoonDisc, 1, 0, 0);
      gl.uniform3f(U.uMoonGlow, 1, 0, 0);
      gl.uniform3f(U.uMoonNear, 1, 0, 0);
      gl.uniform3f(U.uMoonAmt, 0, 0, 0);
    }

    const tones = new Float32Array(9);
    K.landTone.forEach((c, i) => tones.set([c.L, c.a, c.b], i * 3));
    gl.uniform3fv(U.uLandTone, tones);
    gl.uniform3f(U.uLandOwn, LAND_OWN[0], LAND_OWN[1], LAND_OWN[2]);
    gl.uniform3f(U.uMist, 0.5, 0.56, 0.62);
    if (scheme === 'dark') gl.uniform3f(U.uMist, lerp(0.5, 0.36, night), lerp(0.56, 0.4, night), lerp(0.62, 0.44, night));
    gl.uniform1f(U.uLandWarm, scheme === 'light' ? 0.34 : 0.5);
    gl.uniform1f(U.uHaze, (scheme === 'light' ? 0.09 : 0.16) * smoothstep(-4, 1, alt));
    const rim = K.poolRow[96][0];
    gl.uniform3f(U.uRim, rim.L, rim.a, rim.b);
    gl.uniform4f(U.uFrost, K.frost.L, K.frost.a, K.frost.b, Math.max(K.sea.frost * 0.34, 0) * (1 - K.sea.snow));
    gl.uniform1f(U.uRimAmt, 0.5 * K.sunUp * smoothstep(12, 3, alt) * (0.35 + 0.65 * p));
    const page = PAGE[scheme];
    gl.uniform3f(U.uPage, page.L, page.a, page.b);
    gl.uniform1f(U.uPageAmt, scheme === 'light' ? 0.86 : 0.72);
    gl.uniform2f(U.uSettle, scheme === 'light' ? 10 : 70, scheme === 'light' ? 300 : 400);
    gl.uniform1f(U.uT, t * stillness);
    gl.uniform1f(U.uVary, 2.2);

    // Bedtime's ring.
    const ring = bedtimeRing(state, L);
    if (ring) {
      gl.uniform4f(U.uRing, L.ox + L.tonight.x, L.tonight.y, ring.radius, ring.strength * (scheme === 'light' ? 0.5 : 0.2));
      const tint = scheme === 'light' ? lch([0.99, 0.025, 85]) : lch([0.62, 0.05, 80]);
      gl.uniform3f(U.uRingTint, tint.L, tint.a, tint.b);
    } else {
      gl.uniform4f(U.uRing, 0, 0, 0, 0);
      gl.uniform3f(U.uRingTint, 1, 0, 0);
    }

    // Opening the Duo.
    if (state.event?.kind === 'open' && state.fold && !state.reduceMotion) {
      const age = state.event.age;
      const reachPt = -60 + (state.fold.x + 320) * smoothstep(-0.1, 1.2, age);
      const amount = (1 - smoothstep(0.8, 1.4, age)) * (scheme === 'light' ? 0.03 : 0.17);
      gl.uniform4f(U.uOpen, state.fold.x, reachPt, 300, amount);
    } else {
      gl.uniform4f(U.uOpen, 0, 0, 1, 0);
    }

    gl.uniform2f(U.uTilt, state.tilt.x, state.tilt.y);
    gl.uniform1f(U.uGrain, scheme === 'light' ? 1.05 : 0.9);
    gl.uniform1f(U.uDim, scheme === 'light' ? 1 - 0.022 * K.pr.depth : 1 - 0.13 * K.pr.depth);

    const rects = quietRects(state, L);
    const flat = new Float32Array(12);
    rects.slice(0, 3).forEach((r, i) => flat.set(r, i * 4));
    gl.uniform4fv(U.uQuiet, flat);
    gl.uniform1i(U.uQuietCount, Math.min(3, rects.length));

    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
  }

  /** The ring that leaves tonight's star at bedtime: { radius (points), strength }. */
  function bedtimeRing(state, L) {
    if (state.event?.kind !== 'bedtime' || state.asleep !== 'night' || state.reduceMotion) return null;
    const age = state.event.age - 1.25;
    if (age <= 0) return null;
    const far = Math.hypot(L.ox + L.tonight.x, Math.max(L.tonight.y, L.H - L.tonight.y)) + 80;
    const travel = far * (1 - Math.exp(-age / 2.1));
    const strength = (1 - smoothstep(far * 0.55, far * 0.98, travel)) * smoothstep(0, 0.35, age);
    if (strength <= 0.002) return null;
    return { radius: travel, strength, far };
  }

  // ── the points ──

  function sprite(key, size, paint) {
    let s = sprites.get(key);
    if (!s) {
      s = doc.createElement('canvas');
      s.width = s.height = size;
      paint(s.getContext('2d'), size);
      sprites.set(key, s);
    }
    return s;
  }
  /** A soft round glow in a colour, 0 at the rim. */
  function glow(rgb, falloff = 2.2) {
    const key = `glow:${rgb.join(',')}:${falloff}`;
    return sprite(key, 96, (c, size) => {
      const g = c.createRadialGradient(size / 2, size / 2, 0, size / 2, size / 2, size / 2);
      for (let i = 0; i <= 12; i++) {
        const r = i / 12;
        g.addColorStop(r, `rgba(${rgb[0]},${rgb[1]},${rgb[2]},${Math.pow(1 - r, falloff).toFixed(4)})`);
      }
      c.fillStyle = g;
      c.fillRect(0, 0, size, size);
    });
  }

  function starsFor(state, L) {
    const lit = state.asleep === 'night';
    const key = `${state.ageDays}|${lit}|${L.slab}|${L.W}`;
    if (starCacheKey === key) return starCache;
    const mapKey = `${L.slab}|${L.W}|${L.hy}`;
    if (starMapKey !== mapKey) { starMap = makeStarMap(L); starMapKey = mapKey; }
    const list = nights(state.ageDays, { tonightLit: true }).map((star) => {
      const place = star.kind === 'tonight' ? { ...L.tonight } : starMap(star.u, star.v);
      return { ...star, ...place };
    });
    starCache = { list, count: list.length };
    starCacheKey = key;
    return starCache;
  }

  /** The ordinary sky of the leading page: faint, soft, nobody's. */
  function ordinaryFor(state, L) {
    const key = `${state.width}|${L.ox}|${L.hy}`;
    if (ordinaryKey === key) return ordinary;
    const random = rng(7741);
    const list = [];
    if (L.ox > 40) {
      let guard = 0;
      while (list.length < 84 && guard++ < 4000) {
        const x = random() * (L.ox - 14);
        const v = random() ** 1.5;
        const y = 3 + v * (L.hy - 14);
        const m = random();
        const tw = random();
        if (x > 86 && x < 352 && y > 14 && y < 92) continue;     // the page's title
        list.push({ x, y, magnitude: 0.25 + 0.75 * m ** 3, phase: tw, period: 3 + 4 * random() });
      }
    }
    ordinary = list;
    ordinaryKey = key;
    return ordinary;
  }

  function drawPoints(state, K) {
    const { L, scheme } = K;
    const dpr = state.dpr;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, points.width, points.height);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.globalCompositeOperation = 'source-over';
    const t = state.reduceMotion ? null : state.t;
    const light = scheme === 'light';
    const out = K.pr.stars;                                   // how much of the starfield is out
    const tiltX = state.tilt.x * 3.2, tiltY = state.tilt.y * 2.2;

    const bedtime = state.event?.kind === 'bedtime' && state.asleep === 'night' ? state.event.age : null;
    const ring = bedtimeRing(state, L);
    const veil = clamp01(state.veil ?? 0);

    // ── the ordinary sky (leading page) ──
    if (out > 0.02) {
      const openAge = state.event?.kind === 'open' ? state.event.age : null;
      for (const s of ordinaryFor(state, L)) {
        let a = out * (0.16 + 0.34 * s.magnitude) * (light ? 0.55 : 1);
        if (t != null) a *= 0.78 + 0.22 * Math.cos(TAU * (t / s.period + s.phase));
        if (openAge != null && !state.reduceMotion) a *= smoothstep(0, 0.5, openAge - (L.ox - s.x) / 720);
        a *= 0.35 + 0.65 * (1 - smoothstep(L.hy - 60, L.hy - 4, s.y));
        if (ring) {
          const since = ring.radius - Math.hypot(s.x - L.ox - L.tonight.x, s.y - L.tonight.y);
          if (since > -30) a *= 1 + 1.1 * Math.exp(-(((since - 14) / 46) ** 2)) * ring.strength ** 0.5;
        }
        const r = 1.5 + 1.6 * s.magnitude;
        ctx.globalAlpha = clamp01(a);
        // Soft, never crisp: nobody's stars are out of focus beside his. (Light: a faint grey-violet, as his are ink.)
        ctx.drawImage(glow(light ? [128, 126, 176] : [205, 214, 240], light ? 2.2 : 1.6), s.x + tiltX * 0.6 - r, s.y + tiltY * 0.6 - r, r * 2, r * 2);
      }
    }

    // ── his stars ──
    const { list, count } = starsFor(state, L);
    const tonightLit = state.asleep === 'night';
    const quietBoxes = quietRects(state, L);
    for (const star of list) {
      const isTonight = star.kind === 'tonight';
      const x = L.ox + star.x + tiltX, y = star.y + tiltY;
      // Out in the order of his nights: the first night first.
      let a = isTonight ? 1 : smoothstep(0, 1, (out * 1.16 - (star.night - 1) / count) / 0.16);
      let flare = 0;
      if (ring && !isTonight) {
        // The ring passing: each star answers as the light reaches it.
        const dist = Math.hypot(star.x - L.tonight.x, star.y - L.tonight.y);
        const since = ring.radius - dist;
        if (since > -30) {
          const pulse = Math.exp(-(((since - 14) / 46) ** 2)) * ring.strength ** 0.5;
          flare = pulse;
        }
      }
      if (bedtime != null && !isTonight) a = Math.max(a, flare * 0.9);
      if (a <= 0.003 && !isTonight) continue;
      const tw = t == null ? 0.86 : twinkle(star, t);
      const core = 0.7 + 0.3 * tw;
      // Dimmer in the haze near the horizon.
      const haze = 0.3 + 0.7 * (1 - smoothstep(L.hy - 54, L.hy - 2, y));
      let size = 0.4 + 1.3 * star.magnitude ** 1.35;
      let bright = (0.3 + 0.7 * star.magnitude) * haze * a;
      if (star.kind === 'month') size *= 1.18;
      if (star.kind === 'first') size *= 1.25;
      bright *= 1 + 1.3 * flare;
      size *= 1 + (light ? 0.12 : 0.5) * flare;
      // Behind words: gone soft.
      for (const r of quietBoxes) {
        if (x > r[0] && x < r[2] && y > r[1] && y < r[3]) bright *= 0.25;
      }

      if (isTonight) {
        drawTonight(state, K, x, y, tonightLit, bedtime, out);
        continue;
      }
      const warmth = star.warmth;
      const rgb = light
        ? [255, 255, 255]
        : [Math.round(232 + 23 * clamp01(0.5 + warmth)), Math.round(232 + 8 * (1 - Math.abs(warmth))), Math.round(255 - 62 * clamp01(warmth) - 0 * warmth)];
      if (light) {
        // On a light page nothing can be brighter than the ground, so a star is
        // drawn as its trace: a crisp ink point in a small pool of light.
        const halo = size * (star.kind === 'night' ? 5 : 6.4) * (1 + 0.8 * flare);
        ctx.globalAlpha = clamp01(bright * 0.85 * tw);
        ctx.drawImage(glow([255, 255, 255], 1.6), x - halo, y - halo, halo * 2, halo * 2);
        const w = clamp01(0.5 + warmth);
        ctx.globalAlpha = clamp01(bright * 1.05 * core);
        ctx.fillStyle = `rgb(${Math.round(100 + 44 * w)},${Math.round(106 - 6 * w)},${Math.round(168 - 22 * w)})`;
        ctx.beginPath(); ctx.arc(x, y, size * 0.82, 0, TAU); ctx.fill();
      } else {
        const halo = size * (star.kind === 'night' ? 4.4 : 6.2);
        ctx.globalAlpha = clamp01(bright * tw * (star.kind === 'night' ? 0.3 : 0.42));
        ctx.drawImage(glow(rgb, 2.4), x - halo, y - halo, halo * 2, halo * 2);
        ctx.globalAlpha = clamp01(bright * core * (star.kind === 'night' ? 1.15 : 1.5));
        ctx.fillStyle = `rgb(${rgb[0]},${rgb[1]},${rgb[2]})`;
        ctx.beginPath(); ctx.arc(x, y, size, 0, TAU); ctx.fill();
      }
    }
    ctx.globalAlpha = 1;

    // ── a rare shooting star: one soft stroke of light, about every hundred seconds of a clear night ──
    if (t != null && out > 0.9 && bedtime == null) {
      const every = 97, lasts = 1.1;
      const turn = Math.floor((t - 41) / every);
      const age = (t - 41) - turn * every;
      if (turn >= 0 && age < lasts) {
        const k = age / lasts;
        const x0 = L.ox + (0.12 + 0.6 * hash(turn, 51)) * L.W, y0 = 14 + hash(turn, 52) * (L.hy * 0.42);
        const angle = (18 + 26 * hash(turn, 53)) * DEG * (hash(turn, 54) > 0.5 ? 1 : -1) + (hash(turn, 54) > 0.5 ? 0 : Math.PI);
        const reach = 70 + 50 * hash(turn, 55);
        const head = smoothstep(0, 1, k) * reach, tail = Math.max(0, head - 34);
        const hx = x0 + Math.cos(angle) * head, hy2 = y0 + Math.abs(Math.sin(angle)) * head;
        const tx = x0 + Math.cos(angle) * tail, ty = y0 + Math.abs(Math.sin(angle)) * tail;
        const stroke = ctx.createLinearGradient(tx, ty, hx, hy2);
        const tone = light ? '110,108,168' : '236,240,255';
        stroke.addColorStop(0, `rgba(${tone},0)`);
        stroke.addColorStop(1, `rgba(${tone},${(0.7 * Math.sin(Math.PI * k) ** 0.7).toFixed(3)})`);
        ctx.strokeStyle = stroke;
        ctx.lineWidth = 0.9;
        ctx.lineCap = 'round';
        ctx.beginPath(); ctx.moveTo(tx, ty); ctx.lineTo(hx, hy2); ctx.stroke();
      }
    }

    drawParticles(state, K);

    // ── bedtime's caption ──
    if (bedtime != null && !state.reduceMotion) {
      const a = smoothstep(1.9, 2.9, bedtime) * (1 - smoothstep(5.6, 6.6, bedtime)) * veil;
      if (a > 0.01) {
        ctx.globalAlpha = a * 0.92;
        ctx.fillStyle = light ? 'rgba(60,60,67,0.75)' : 'rgba(235,235,245,0.7)';
        ctx.font = '600 11px Nunito, ui-rounded, system-ui, sans-serif';
        ctx.textAlign = 'right';
        ctx.textBaseline = 'middle';
        if ('letterSpacing' in ctx) ctx.letterSpacing = '1.4px';
        ctx.fillText(`NIGHT ${count}`, L.ox + L.tonight.x - 13, L.tonight.y + 0.5);
        if ('letterSpacing' in ctx) ctx.letterSpacing = '0px';
        ctx.globalAlpha = 1;
      }
    }
  }

  /** Tonight's star: a small ring waiting from dusk; lit when he goes down. */
  function drawTonight(state, K, x, y, lit, bedtime, out) {
    const light = K.scheme === 'light';
    const t = state.reduceMotion ? null : state.t;
    if (!lit) {
      const a = Math.max(out, 0) * 0.5;
      if (a < 0.01) return;
      ctx.globalAlpha = a;
      ctx.strokeStyle = light ? 'rgba(120,112,150,0.9)' : 'rgba(255,236,208,0.9)';
      ctx.lineWidth = 0.7;
      ctx.beginPath(); ctx.arc(x, y, 2.6, 0, TAU); ctx.stroke();
      ctx.globalAlpha = 1;
      return;
    }
    const ign = bedtime != null && !state.reduceMotion ? ignition(bedtime) : 1;
    if (ign <= 0.001) {
      ctx.globalAlpha = 0.5;
      ctx.strokeStyle = light ? 'rgba(120,112,150,0.9)' : 'rgba(255,236,208,0.9)';
      ctx.lineWidth = 0.7;
      ctx.beginPath(); ctx.arc(x, y, 2.6, 0, TAU); ctx.stroke();
      ctx.globalAlpha = 1;
      return;
    }
    const breath = t == null ? 0.9 : 0.8 + 0.2 * Math.cos((TAU * t) / 5.2);
    const k = ign * breath;
    if (light) {
      const wide = 30 * (0.8 + 0.3 * ign);
      ctx.globalAlpha = clamp01(0.8 * k);
      ctx.drawImage(glow([255, 248, 236], 1.5), x - wide, y - wide, wide * 2, wide * 2);
      const near = 15 * (0.8 + 0.3 * ign);
      ctx.globalAlpha = clamp01(0.6 * k);
      ctx.drawImage(glow([255, 176, 112], 1.7), x - near, y - near, near * 2, near * 2);
      ctx.globalAlpha = clamp01(k * 1.1);
      ctx.fillStyle = 'rgb(224,116,58)';
      ctx.beginPath(); ctx.arc(x, y, 2.3 * (0.85 + 0.15 * ign), 0, TAU); ctx.fill();
    } else {
      const wide = 42 * (0.8 + 0.3 * ign);
      ctx.globalAlpha = clamp01(0.34 * k);
      ctx.drawImage(glow([255, 200, 132], 2.6), x - wide, y - wide, wide * 2, wide * 2);
      const near = 12 * (0.8 + 0.3 * ign);
      ctx.globalAlpha = clamp01(0.85 * k);
      ctx.drawImage(glow([255, 222, 168], 1.9), x - near, y - near, near * 2, near * 2);
      ctx.globalAlpha = clamp01(k * 1.15);
      ctx.fillStyle = 'rgb(255,240,210)';
      ctx.beginPath(); ctx.arc(x, y, 2.4 * (0.85 + 0.15 * ign), 0, TAU); ctx.fill();
    }
    ctx.globalAlpha = 1;
  }

  /** Snow, petals, leaves, fireflies: the season as a few slow points of light.
   *  Far ones are small and clear, near ones large and out of focus. */
  function drawParticles(state, K) {
    const { L, scheme, sea, alt, night } = K;
    const light = scheme === 'light';
    const t = state.reduceMotion ? 0 : state.t;
    const width = state.width, height = state.height;
    const calm = 1 - 0.5 * K.pr.depth;
    const area = (width * height) / (466 * 678);
    const lit = light ? 1 : lerp(1, 0.55, night);            // they are lit by the sky
    const wrap = (v, size, pad) => (((v % (size + 2 * pad)) + size + 2 * pad) % (size + 2 * pad)) - pad;
    const each = (count, seed, fn) => {
      for (let i = 0; i < count; i++) fn((salt) => hash(i + 1, seed + salt), i);
    };

    // Snow: always a little in the winter air, more on a snow day.
    const snow = sea.snow > 0.3 ? sea.snow * (0.5 + 0.5 * Math.min(1, sea.snowfall * 1.2)) : 0;
    if (snow > 0.02) {
      each(Math.round(120 * snow * area), 100, (h) => {
        const depth = h(1) ** 1.6;
        const sway = Math.sin(t * (0.16 + 0.2 * h(2)) + h(3) * TAU) * (4 + 9 * depth);
        const x = wrap(h(4) * (width + 60) + sway + t * (1 + 2.4 * depth) * calm, width, 30);
        const y = wrap(h(5) * (height + 60) + t * (5 + 11 * depth) * calm, height, 30);
        const near = depth > 0.78;
        const r = near ? 2.6 + 3.2 * (depth - 0.78) / 0.22 : 0.65 + 1.25 * depth;
        const a = near ? 0.16 : 0.34 + 0.5 * depth;
        if (light) {
          ctx.globalAlpha = a * 0.5;
          ctx.drawImage(glow([150, 162, 206], 1.3), x - r * 2.1, y - r * 2.1 + 0.4, r * 4.2, r * 4.2);
          ctx.globalAlpha = Math.min(1, a * 1.5);
          ctx.drawImage(glow([255, 255, 255], near ? 1.0 : 0.6), x - r * 1.5, y - r * 1.5, r * 3, r * 3);
        } else {
          // By night snow is a soft grey drift, never as sharp or as bright as a star.
          ctx.globalAlpha = a * lerp(1.05, 0.42, night);
          ctx.drawImage(glow([226, 232, 250], near ? 1.1 : lerp(0.7, 1.5, night)), x - r * 1.8, y - r * 1.8, r * 3.6, r * 3.6);
        }
      });
    }

    // Petals: pale, slow, carried sideways.
    if (sea.petals > 0.02) {
      each(Math.round(30 * sea.petals * area), 200, (h) => {
        const depth = h(1);
        const x = wrap(h(2) * (width + 80) + t * (7 + 10 * depth) * calm + Math.sin(t * 0.21 + h(3) * TAU) * 14, width, 40);
        const y = wrap(h(4) * (height + 80) + t * (3.5 + 5 * depth) * calm + Math.sin(t * 0.33 + h(5) * TAU) * 9, height, 40);
        const rx = 1.7 + 1.9 * depth;
        const turn = h(6) * TAU + t * (0.3 + 0.3 * h(7)) * calm;
        const flip = 0.42 + 0.3 * Math.abs(Math.sin(t * 0.5 * calm + h(8) * TAU));
        ctx.save();
        ctx.translate(x, y); ctx.rotate(turn); ctx.scale(1, flip);
        if (light) {
          ctx.globalAlpha = 0.34;
          ctx.drawImage(glow([226, 138, 170], 1.5), -rx * 1.9, -rx * 1.9, rx * 3.8, rx * 3.8);
          ctx.globalAlpha = 0.95;
          ctx.fillStyle = 'rgb(255,238,243)';
        } else {
          ctx.globalAlpha = 0.22 * lit;
          ctx.drawImage(glow([246, 196, 214], 1.6), -rx * 2.2, -rx * 2.2, rx * 4.4, rx * 4.4);
          ctx.globalAlpha = (0.5 + 0.3 * depth) * lit;
          ctx.fillStyle = 'rgb(248,214,226)';
        }
        ctx.beginPath(); ctx.ellipse(0, 0, rx, rx * 0.86, 0, 0, TAU); ctx.fill();
        ctx.restore();
      });
    }

    // Leaves: a few rust flecks, turning as they fall.
    const leaves = Math.max(0, sea.leafFall - 0.3) / 0.7;
    if (leaves > 0.02) {
      const tones = light ? [[198, 112, 70], [214, 144, 76], [178, 98, 82]] : [[206, 122, 72], [222, 156, 84], [184, 100, 78]];
      each(Math.round(20 * leaves * area), 300, (h) => {
        const depth = h(1);
        const x = wrap(h(2) * (width + 80) + t * (4 + 7 * depth) * calm + Math.sin(t * 0.27 + h(3) * TAU) * 18, width, 40);
        const y = wrap(h(4) * (height + 80) + t * (6 + 9 * depth) * calm, height, 40);
        const len = 2.4 + 2.4 * depth;
        const turn = h(6) * TAU + Math.sin(t * 0.4 * calm + h(7) * TAU) * 1.2;
        const flip = 0.3 + 0.25 * Math.abs(Math.sin(t * 0.6 * calm + h(9) * TAU));
        const rgb = tones[Math.floor(h(8) * 3) % 3];
        ctx.save();
        ctx.translate(x, y); ctx.rotate(turn);
        ctx.globalAlpha = (light ? 0.2 : 0.16 * lit);
        ctx.drawImage(glow(rgb, 1.6), -len * 1.8, -len * 1.8, len * 3.6, len * 3.6);
        ctx.globalAlpha = (0.62 + 0.26 * depth) * (light ? 1 : lit);
        ctx.fillStyle = `rgb(${rgb[0]},${rgb[1]},${rgb[2]})`;
        ctx.beginPath();
        ctx.moveTo(-len, 0); ctx.quadraticCurveTo(0, -len * flip * 1.5, len, 0); ctx.quadraticCurveTo(0, len * flip * 1.5, -len, 0);
        ctx.fill();
        ctx.restore();
      });
    }

    // Fireflies: tiny warm points low over the land, from dusk.
    const dusk = sea.fireflies * (1 - smoothstep(-1, 5, alt)) * (0.4 + 0.6 * smoothstep(-18, -6, alt));
    if (dusk > 0.02) {
      each(Math.round(34 * sea.fireflies * area), 400, (h) => {
        const cycle = 5 + 6 * h(1);
        const phase = ((t / cycle) + h(2)) % 1;
        const on = state.reduceMotion ? (h(2) > 0.45 ? 0.8 : 0) : smoothstep(0, 0.12, phase) * (1 - smoothstep(0.22, 0.5, phase));
        if (on < 0.02) return;
        const x = h(3) * width + Math.sin(t * 0.13 + h(4) * TAU) * 16 + Math.sin(t * 0.31 + h(5) * TAU) * 6;
        const y = L.hy - 12 + h(6) ** 1.3 * 150 * L.landScale + Math.sin(t * 0.17 + h(7) * TAU) * 7;
        const r = 5.5;
        ctx.globalAlpha = on * dusk * (light ? 0.75 : 0.6);
        ctx.drawImage(glow(light ? [255, 222, 120] : [240, 226, 130], 2.6), x - r, y - r, r * 2, r * 2);
        ctx.globalAlpha = on * dusk;
        ctx.fillStyle = light ? 'rgb(236,190,70)' : 'rgb(250,240,170)';
        ctx.beginPath(); ctx.arc(x, y, 0.85, 0, TAU); ctx.fill();
      });
    }
    ctx.globalAlpha = 1;
  }

  // ── frame ──

  function resize(state) {
    const key = `${state.width}|${state.height}|${state.dpr}`;
    if (key === sizeKey) return;
    sizeKey = key;
    for (const canvas of [field, points]) {
      canvas.width = Math.round(state.width * state.dpr);
      canvas.height = Math.round(state.height * state.dpr);
      canvas.style.width = `${state.width}px`;
      canvas.style.height = `${state.height}px`;
    }
  }

  function render(state) {
    resize(state);
    const K = look(state);
    drawField(state, K);
    drawPoints(state, K);
  }

  return {
    render,
    destroy() {
      gl.getExtension('WEBGL_lose_context')?.loseContext();
      field.remove();
      points.remove();
      sprites.clear();
    },
  };
}
