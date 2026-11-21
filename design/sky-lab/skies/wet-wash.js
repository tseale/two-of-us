// Wet wash — the sky as a watercolour on cold-pressed paper.
//
// One sheet of paper, painted by one hand:
//   · the paper       a height-field (tooth); in the light appearance its white IS the page
//   · the sky wash    a graded wash laid at the top and pulled down — five pigments down the
//                     sheet, standing tall toward the sun and sinking away from it, meeting
//                     wet-in-wet; long cloud bars charged in over the glow; three back-runs
//   · clouds          paper left / lifted out, a shadow dropped in at the base
//   · sun, moon       untouched paper in a wet halo; the moon lifted out, in its phase
//   · the land        four transparent glazes, each with a drying edge along its top and a
//                     dissolve into wet paper below (the valley mist); water (paper left);
//                     a near bank
//   · his stars       flecks of gouache, one per night (a 2-D layer over the wash)
//
// Colour is subtractive: every passage is an ABSORBANCE (−ln of the linear colour over the
// paper), washes add, and the picture is paper × exp(−A). So a wash that thins goes to
// paper, two washes that meet multiply (rose over blue is violet, never chalk), pigment
// that settles into the paper's pits darkens and cools there, and a drying edge is simply
// more of the same pigment. The palettes are written in OKLCH at full strength and
// quietened by lab/presence.js before they become absorbances.
//
// The wash is one fragment shader (WebGL2 here; a Metal shader in the app, rendered into an
// image when its inputs change: nothing in it moves faster than a few points a minute, so
// it is repainted at most every fourth second). The stars are a 2-D canvas above it.

import { presence as presenceOf } from '../lab/presence.js';
import { toOklab, fromOklab, smoothstep, lerp } from '../lab/oklab.js';
import { nights, twinkle, ignition, hash } from '../lab/nights.js';
import { season as seasonOf } from '../lab/season.js';

export const meta = {
  id: 'wet-wash',
  name: 'Wet wash',
  blurb: 'A watercolour on cold-pressed paper: graded washes, granulation, lifted clouds, glazed hills; the bloom is pigment arriving.',
};

const DEG = 180 / Math.PI;
const TAU = Math.PI * 2;
const clamp01 = (x) => Math.min(1, Math.max(0, x));

// ───────────────────────────────────────────────────────────── palette ──
// Everything is [L, C, h°] in OKLCH, at full strength. Rows are keyed by the sun's
// altitude in degrees; between keys colours are mixed in OKLab.

const KEYS = [-14, -10, -6, -2.5, 1, 5, 12];

/** The sky wash, five pigments down the sheet: zenith bead, upper, middle, low, horizon. */
const SKY = {
  light: [
    [[.870, .060, 272], [.882, .052, 273], [.905, .038, 276], [.922, .028, 282], [.926, .026, 290]],   // night
    [[.866, .066, 274], [.876, .058, 282], [.894, .046, 300], [.908, .040, 335], [.910, .042, 25]],    // nautical dusk
    [[.860, .074, 276], [.866, .066, 296], [.872, .066, 345], [.880, .075, 35], [.874, .092, 55]],     // civil
    [[.862, .076, 276], [.868, .062, 300], [.874, .076, 12], [.882, .092, 48], [.866, .120, 62]],      // just set
    [[.864, .072, 272], [.872, .058, 298], [.880, .070, 18], [.890, .090, 55], [.882, .118, 74]],      // low sun
    [[.868, .066, 262], [.880, .048, 285], [.896, .050, 20], [.910, .070, 62], [.906, .095, 82]],      // golden hour
    [[.872, .056, 248], [.895, .040, 246], [.925, .020, 240], [.945, .010, 200], [.940, .015, 90]],    // day
  ],
  dark: [
    [[.250, .078, 270], [.228, .070, 272], [.212, .060, 275], [.218, .052, 280], [.236, .048, 288]],
    [[.225, .066, 274], [.222, .066, 280], [.226, .066, 295], [.244, .066, 325], [.258, .064, 355]],
    [[.215, .072, 278], [.240, .084, 298], [.280, .096, 340], [.335, .106, 15], [.378, .112, 38]],
    [[.228, .080, 279], [.275, .096, 306], [.335, .114, 2], [.420, .130, 30], [.510, .150, 48]],
    [[.245, .082, 277], [.292, .096, 304], [.352, .112, 5], [.448, .130, 36], [.580, .145, 58]],
    [[.250, .070, 270], [.280, .078, 290], [.325, .095, 345], [.400, .118, 22], [.520, .138, 48]],
    [[.250, .050, 262], [.238, .044, 266], [.224, .038, 270], [.216, .034, 275], [.220, .034, 285]],
  ],
};

/** The land's four glazes, far → near. */
const HILLS = {
  light: [
    [[.905, .028, 272], [.885, .034, 273], [.866, .038, 274], [.846, .042, 276]],
    [[.895, .034, 276], [.875, .040, 278], [.855, .044, 280], [.835, .048, 283]],
    [[.870, .048, 280], [.858, .048, 288], [.840, .050, 298], [.815, .054, 310]],
    [[.862, .052, 282], [.850, .050, 294], [.830, .054, 310], [.805, .058, 328]],
    [[.862, .052, 282], [.850, .050, 294], [.830, .054, 310], [.805, .058, 328]],
    [[.874, .046, 278], [.862, .044, 288], [.845, .046, 300], [.822, .050, 320]],
    [[.895, .030, 262], [.875, .034, 266], [.855, .038, 270], [.835, .040, 275]],
  ],
  dark: [
    [[.196, .052, 272], [.176, .048, 273], [.156, .042, 274], [.136, .036, 275]],
    [[.196, .052, 280], [.176, .048, 280], [.156, .042, 280], [.136, .036, 280]],
    [[.205, .055, 300], [.178, .052, 296], [.152, .046, 290], [.126, .040, 284]],
    [[.250, .070, 318], [.212, .064, 310], [.176, .056, 300], [.142, .046, 290]],
    [[.255, .070, 320], [.216, .064, 312], [.180, .056, 302], [.145, .046, 292]],
    [[.255, .060, 316], [.220, .058, 310], [.185, .050, 302], [.150, .042, 294]],
    [[.205, .034, 268], [.186, .030, 270], [.166, .027, 272], [.146, .024, 274]],
  ],
};

/** The sun's wet halo, and the disc (light: untouched paper). */
const HALO = {
  light: [[.92, .03, 290], [.91, .04, 40], [.90, .07, 60], [.885, .125, 68], [.895, .135, 82], [.905, .125, 88], [.93, .075, 95]],
  dark: [[.20, .05, 283], [.26, .06, 350], [.42, .11, 40], [.58, .15, 50], [.68, .145, 62], [.68, .14, 60], [.36, .05, 80]],
};
const DISC_DARK = [[.60, .13, 50], [.60, .13, 50], [.66, .14, 50], [.78, .13, 60], [.90, .09, 82], [.93, .06, 90], [.90, .03, 95]];

/** Cloud shadow, dropped in at the base: cool by day, lit from beneath at the bloom. */
const SHADE = {
  light: [[.865, .040, 275], [.860, .045, 285], [.850, .060, 330], [.852, .085, 20], [.860, .090, 35], [.875, .070, 40], [.885, .030, 265]],
  dark: [[.16, .04, 275], [.17, .045, 285], [.25, .08, 335], [.36, .12, 15], [.40, .125, 28], [.36, .10, 30], [.20, .03, 270]],
};

/** The low cloud bars, charged in wet over the glow. */
const BAR = {
  light: [[.87, .04, 275], [.85, .045, 280], [.815, .055, 292], [.795, .062, 300], [.80, .060, 302], [.83, .05, 295], [.89, .03, 265]],
  dark: [[.15, .04, 275], [.155, .045, 280], [.175, .06, 292], [.20, .07, 302], [.215, .07, 305], [.22, .06, 300], [.20, .03, 268]],
};

const PAGE = { light: { r: 0xf2 / 255, g: 0xf2 / 255, b: 0xf7 / 255 }, dark: { r: 1, g: 1, b: 1 } };
const CREAM = [.935, .035, 88];

const lch = ([L, C, h]) => ({ L, a: C * Math.cos(h / DEG), b: C * Math.sin(h / DEG) });
const mixLab = (A, B, t) => ({ L: lerp(A.L, B.L, t), a: lerp(A.a, B.a, t), b: lerp(A.b, B.b, t) });

/** A keyed row at `alt` degrees → OKLab (each entry of the row may itself be a list). */
function keyed(rows, alt) {
  let i = 0;
  while (i < KEYS.length - 2 && alt > KEYS[i + 1]) i += 1;
  const t = clamp01((alt - KEYS[i]) / (KEYS[i + 1] - KEYS[i]));
  const A = rows[i], B = rows[i + 1];
  if (typeof A[0] === 'number') return mixLab(lch(A), lch(B), t);
  return A.map((entry, k) => mixLab(lch(entry), lch(B[k]), t));
}

const toLin = (c) => (c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4));

/** The hush, on an OKLab colour. Light: toward the page and greyer (a diluted wash).
 *  Dark: dimmer and greyer, never lighter. */
function quiet(lab, p, dark, pageL, night = 0) {
  const k = clamp01(p);
  if (dark) {
    const c = 0.52 + 0.48 * k;
    return { L: lab.L * (1 - 0.10 * (1 - k)), a: lab.a * c, b: lab.b * c };
  }
  const c = lerp(0.50, 0.80, night) + lerp(0.50, 0.20, night) * k;
  return { L: lab.L + (pageL - lab.L) * 0.36 * (1 - k) * (1 - 0.85 * night), a: lab.a * c, b: lab.b * c };
}

/** OKLab → absorbance against the paper (three numbers ≥ 0). */
function absorb(lab, paperLin) {
  const c = fromOklab(lab);
  return [c.r, c.g, c.b].map((v, i) => Math.max(0, -Math.log(Math.max(toLin(v), 1e-5) / paperLin[i])));
}

// ────────────────────────────────────────────────────────────── shader ──

const VERT = `#version 300 es
in vec2 aPos;
void main() { gl_Position = vec4(aPos, 0.0, 1.0); }`;

const FRAG = `#version 300 es
precision highp float;
out vec4 outColor;

uniform vec2 uRes;          // device px
uniform float uDpr;
uniform float uOriginX;     // the anchor window's left edge on the display (pt)
uniform float uWorldW;      // the anchor window's width (pt)
uniform float uH;           // the horizon (pt from the top)
uniform float uDark;        // 0 light, 1 dark
uniform float uMul;         // how far a change of load shows: 1 on thin washes, small on heavy ones
uniform vec3 uPaper;        // linear
uniform vec4 uSky[5];       // absorbance rgb, granulation a — zenith bead … horizon
uniform vec4 uHill[4];
uniform vec4 uGround;       // absorbance, hill opacity (0 = pure glaze … 1 = covers)
uniform vec4 uHalo;         // absorbance, strength
uniform vec4 uDisc;         // absorbance, on
uniform vec4 uSun;          // x (world), y, radius, sun-side weight
uniform vec4 uMoon;         // x, y, radius, on
uniform vec4 uMoonLit;      // lit fraction, rotation, lift, halo
uniform vec3 uMoonA;        // the lifted paper's absorbance
uniform vec4 uShade;        // cloud shadow absorbance, strength
uniform vec4 uCloud;        // lift, amount high, amount low, drift (pt)
uniform vec4 uTex;          // granulation, brush unevenness, tooth shading, dry-brush
uniform vec4 uFlow;         // warp amplitude (pt), curtains, creep, bloom
uniform vec4 uEdge;         // hill edge darkening, dissolve length, mist drift, pool at the horizon
uniform vec4 uLean;         // far-side compression, sun-side lift, feathering
uniform vec4 uCov;          // the wash's cover: middle far, middle sun, low far, low sun
uniform vec4 uBar;          // the low cloud bars: absorbance, strength
uniform vec4 uMist;         // the valley mist toward the sun (dark appearance): absorbance, strength
uniform vec4 uRun[3];       // back-runs: x, y (world), radius, strength
uniform vec4 uCl[3];        // the high clouds: centre x, y, half-widths (world pt)
uniform vec4 uBr[3];        // the low bars, likewise
uniform vec4 uWin[3];       // where the land's edges are found: centre x, half-width
uniform vec4 uSeason;       // frost, blossom, snow, —
uniform vec3 uBlossomA;
uniform vec4 uOpen;         // the second pass crossing the leading page: front x (world), strength
uniform vec4 uLake;         // far shore, near bank (pt below the horizon), reflection, —
uniform vec4 uWater;        // the water: absorbance, opacity
uniform vec4 uBank;         // the near bank: absorbance, stays
uniform vec4 uGlit;         // the light on the water: x, half-width, strength, —
uniform vec3 uGlitA;
uniform float uSpark;
uniform float uDeep;        // he is asleep: the whole sheet a little deeper
uniform vec2 uTilt;

// ── noise ──
uint hashu(uvec2 v) {
  v = v * 1664525u + 1013904223u;
  v.x += v.y * 1664525u; v.y += v.x * 1664525u;
  v ^= v >> 16u;
  v.x += v.y * 1664525u; v.y += v.x * 1664525u;
  v ^= v >> 16u;
  return v.x ^ v.y;
}
float hash(vec2 p) { return float(hashu(uvec2(ivec2(floor(p)) + 65536))) * (1.0 / 4294967295.0); }
vec2 grad(vec2 i) {
  uint h = hashu(uvec2(ivec2(i) + 65536));
  return vec2(float(h & 65535u), float(h >> 16u)) * (2.0 / 65535.0) - 1.0;
}
// gradient noise, about 0…1, centred on 0.5
float gn(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
  float a = dot(grad(i), f), b = dot(grad(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
  float c = dot(grad(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0)), d = dot(grad(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
  return 0.5 + 0.62 * mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
const mat2 ROT = mat2(0.8, -0.6, 0.6, 0.8);
const mat2 ROT0 = mat2(0.9553, -0.2955, 0.2955, 0.9553);
float fbm2(vec2 p) { p = ROT0 * p; return gn(p) * 0.6667 + gn(ROT * p * 2.03 + 11.7) * 0.3333; }
float fbm3(vec2 p) {
  p = ROT0 * p;
  float s = gn(p) * 0.5714; p = ROT * p * 2.03 + 11.7;
  s += gn(p) * 0.2857; p = ROT * p * 2.03 + 11.7;
  return s + gn(p) * 0.1429;
}
float fbm4(vec2 p) {
  p = ROT0 * p;
  float s = gn(p) * 0.5333; p = ROT * p * 2.03 + 11.7;
  s += gn(p) * 0.2667; p = ROT * p * 2.03 + 11.7;
  s += gn(p) * 0.1333; p = ROT * p * 2.03 + 11.7;
  return s + gn(p) * 0.0667;
}
// a ridge line: slow shoulders, a little shorter rhythm on them
float ridgeN(float x, float seed) {
  return 0.62 * gn(vec2(x, seed)) + 0.27 * gn(vec2(x * 2.3 + 5.1, seed + 3.7)) + 0.11 * gn(vec2(x * 5.3 + 1.3, seed + 9.1));
}

// The land's four lines, far → near. Slow shoulders that cross one another, so a narrow
// window never shows four parallel stripes.
float ridgeY(int i, float wx) {
  // tilt: the nearer the glaze, the further it slides
  float k = i == 0 ? 1.5 : (i == 1 ? 3.0 : (i == 2 ? 5.0 : 8.0));
  wx += uTilt.x * k;
  float lift = uTilt.y * k * 0.4;
  if (i == 0) return lift + uH - 6.0 - 52.0 * (ridgeN(wx / 205.0 + 0.3, 1.0) - 0.5) - 26.0 * exp(-pow((wx + 432.0) / 86.0, 2.0))
                   + 0.9 * (gn(vec2(wx / 3.6, 4.0)) - 0.5);
  if (i == 1) return lift + uH + 27.0 - 62.0 * (ridgeN(wx / 168.0 + 13.7, 8.3) - 0.5) + 1.1 * (gn(vec2(wx / 4.3, 5.0)) - 0.5);
  if (i == 2) return lift + uH + 62.0 - 72.0 * (ridgeN(wx / 142.0 + 27.4, 15.6) - 0.5) + 1.3 * (gn(vec2(wx / 5.0, 6.0)) - 0.5);
  return lift + uH + 108.0 - 84.0 * (ridgeN(wx / 124.0 + 41.1, 22.9) - 0.5) + 1.6 * (gn(vec2(wx / 5.6, 7.0)) - 0.5);
}

// A back-run: wetter paint let into a drying wash pushes the pigment out to a crinkled rim.
// The water came in from below, so the fan opens upward and its foot is lost.
// → (how much is lifted inside, how much gathers at the rim)
vec2 backrun(vec2 w, vec2 c, float R, float seed) {
  vec2 d = (w - c) / R;
  d.x *= 0.72;
  float r = length(d);
  if (r > 1.9) return vec2(0.0);
  float f = r + 0.95 * (fbm4(d * 1.25 + seed) - 0.5) + 0.10 * (gn(d * 7.0 + seed + 9.0) - 0.5);
  float inside = 1.0 - smoothstep(0.93, 1.0, f);
  float rim = smoothstep(0.74, 0.97, f) * inside;
  float fan = smoothstep(0.75, -0.35, d.y / max(r, 0.001));
  float deep = 1.0 - smoothstep(0.1, 0.95, f);
  return vec2(inside * (0.35 + 0.65 * deep) * (0.4 + 0.6 * fan), rim * fan);
}

vec4 ramp(in vec4 s[5], float v) {
  vec4 r = mix(s[0], s[1], smoothstep(0.00, 0.24, v));
  r = mix(r, s[2], smoothstep(0.24, 0.45, v));
  r = mix(r, s[3], smoothstep(0.42, 0.76, v));
  return mix(r, s[4], smoothstep(0.72, 1.00, v));
}

vec3 toGamma(vec3 c) { return mix(c * 12.92, 1.055 * pow(max(c, 0.0), vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c)); }

void main() {
  vec2 px = vec2(gl_FragCoord.x, uRes.y - gl_FragCoord.y);
  vec2 p = px / uDpr;
  float wx = p.x - uOriginX;
  float y = p.y;
  vec2 w = vec2(wx, y);

  // ── the paper: cold-pressed tooth, pinned to the sheet ──
  float n1 = gn(ROT0 * w / 1.3), n2 = gn(ROT * w / 3.1 + 31.7), n3 = gn(ROT0 * ROT * w / 7.9 + 7.1);
  float tooth = 0.42 * n1 + 0.36 * n2 + 0.22 * n3;          // 0…1 about 0.5; high = a peak of the felt
  float pit = 0.5 - tooth;
  // Where the wash lay wet for longer the pigment had time to settle: granulation comes and goes.
  float settle = smoothstep(0.36, 0.64, fbm2(w / 70.0 + 40.0));
  float gran = uTex.x * (0.45 + 0.55 * settle) * min(pit * 5.0 + 7.0 * max(pit - 0.06, 0.0) + 1.3 * (0.5 - n3), 1.25);

  // ── the hand: uneven loading along the stroke, and the wet-in-wet warp ──
  float brush = fbm3(vec2(wx / 190.0, y / 40.0) + 3.3) - 0.5;
  float stroke = gn(vec2(wx / 560.0 + 3.0, y / 6.5)) - 0.5;
  vec2 wq = w / 86.0;
  vec2 warp = vec2(fbm4(wq + vec2(1.7, 9.2 + uFlow.z)), fbm4(wq + vec2(8.3 - uFlow.z, 2.8))) - 0.5;
  float feather = fbm4(vec2(wx / 40.0, y / 70.0 + uFlow.z * 2.0) + 21.0) - 0.5;

  // ── the land's top line (the far ridge), needed by the sky ──
  float lf0 = gn(vec2(wx / 80.0, 2.5));
  float r0 = ridgeY(0, wx);
  float land = smoothstep(-0.7, 0.7, y - r0);

  // ── the sky wash ──
  // Toward the sun the colours stand tall; away from it they sink to the horizon.
  float dx = (wx + warp.x * uFlow.x * 3.0 - uSun.x) / (uWorldW * 0.60);
  float side = uSun.w * exp(-dx * dx);
  float v = (y + warp.y * uFlow.x * 2.0) / uH;
  float ve = mix(v * uLean.x, uLean.y + (1.0 - uLean.y) * v, side) + feather * uLean.z;
  vec4 sky = ramp(uSky, ve);
  // how much of the wash is on the paper: it thins below the top band and gathers again at the horizon
  float mid = mix(uCov.x, uCov.y, side), low = mix(uCov.z, uCov.w, side);
  float dens = mix(1.0, mid, smoothstep(0.18, 0.50, v + feather * 0.25));
  dens = mix(dens, low, smoothstep(0.62, 0.96, v));
  dens = clamp(dens + (tooth - 0.5) * 2.2 * dens * (1.0 - dens) * uTex.w, 0.0, 1.0);    // a thinning wash breaks on the tooth
  float load = 1.0 + uMul * (0.34 * brush * uTex.y + 0.16 * stroke * uTex.y + 0.24 * exp(-y / 8.0));   // …and the bead along the top of the first stroke
  // the wash pooled where it met the land
  load += uMul * uEdge.w * exp(-max(r0 - y, 0.0) / 3.0) * smoothstep(0.35, 0.75, gn(vec2(wx / 37.0, 8.0)));

  // clouds, high: paper left, or lifted out; crisp where the wash was cut around them (their tops),
  // soft where it bled (their bases); a shadow dropped in at the base.
  vec2 cq = vec2((wx + uCloud.w) / 230.0, y / 27.0) + warp * 0.5;
  float c0 = fbm4(cq), c1 = fbm4(cq + vec2(0.0, 0.22));
  float eHigh = 0.0, eLow = 0.0, found = 0.0;
  for (int i = 0; i < 3; i++) {
    vec2 e = (vec2(wx + uCloud.w, y) - uCl[i].xy) / uCl[i].zw;
    eHigh += exp(-dot(e, e));
    e = (vec2(wx + uCloud.w * 0.6, y) - uBr[i].xy) / uBr[i].zw;
    eLow += exp(-dot(e, e));
    found = max(found, 1.0 - smoothstep(uWin[i].y, uWin[i].y + 70.0, abs(wx - uWin[i].x)));
  }
  eHigh *= uCloud.y; eLow *= uCloud.z;
  float th = 0.87 - 0.46 * min(eHigh, 1.0);
  float rising = smoothstep(0.0, 0.03, c1 - c0);           // 1 at a cloud's top edge
  float soft = mix(0.085, 0.016, rising);
  float cloud = smoothstep(th - soft, th + soft, c0);
  float base = cloud * (1.0 - smoothstep(th - 0.05, th + 0.06, c1));
  float pooled = smoothstep(th - 0.07, th - 0.012, c0) * (1.0 - cloud) * rising;   // wash pooled against the top edge

  // opening the Duo: the leading page has its first thin pass; the second crosses it from the fold
  float second = smoothstep(uOpen.x - 110.0, uOpen.x + 20.0, wx + 60.0 * feather);
  float pass = 1.0 - uMul * uOpen.y * (1.0 - second);
  load *= pass;

  vec3 A = sky.rgb * dens * load * (1.0 + sky.a * gran);
  A *= 1.0 - uCloud.x * cloud;
  A *= 1.0 + uMul * 0.28 * pooled;
  A += uShade.rgb * uShade.a * base * (1.0 + 1.2 * brush);

  // clouds, low: long bars charged in wet over the glow, lit from beneath
  vec2 sq = vec2((wx + uCloud.w * 0.6) / 380.0, y / 19.0) + warp * 0.6 + 40.0;
  float s0 = fbm3(sq), s1 = fbm3(sq + vec2(0.0, 0.30));
  float ths = 0.87 - 0.42 * min(eLow, 1.0);
  float falling = smoothstep(0.0, 0.03, s0 - s1);          // 1 at a bar's lower edge
  float bsoft = mix(0.075, 0.028, falling);
  float bar = smoothstep(ths - bsoft, ths + bsoft, s0 + feather * 0.05);
  float under = smoothstep(ths - 0.06, ths + 0.01, s0) * (1.0 - smoothstep(ths - 0.03, ths + 0.05, s1)) * falling;
  A = mix(A, uBar.rgb * (1.0 + 0.8 * gran), bar * uBar.a * (0.8 + 0.6 * brush));
  A = mix(A, uHalo.rgb, under * uBar.a * 0.5 * side);

  // back-runs: the few places where something happened
  for (int i = 0; i < 3; i++) {
    vec4 b = uRun[i];
    if (b.w <= 0.0) continue;
    vec2 br = backrun(w, b.xy, b.z, float(i) * 17.0 + 2.0);
    A *= 1.0 - uMul * b.w * 0.34 * br.x;
    A *= 1.0 + uMul * b.w * 0.42 * br.y * (0.5 + 1.0 * gn(w / 4.0 + 50.0));
  }

  // the sun: untouched paper inside a wet halo
  if (uDisc.a > 0.0) {
    vec2 d = w - uSun.xy;
    float r = length(d);
    float wob = (fbm2(d / 7.0 + 3.0) - 0.5) * 1.8;
    float hr = uSun.z * (2.1 + 2.0 * (warp.x + 0.5));
    float halo = uHalo.a * exp(-pow(r / hr, 2.0));
    A = mix(A, uHalo.rgb * (1.0 + 0.5 * sky.a * gran), halo);
    float ring = exp(-pow((r - hr * 1.25) / 4.0, 2.0)) * uHalo.a * uFlow.w;
    A *= 1.0 + uMul * 0.10 * ring;                             // where the wet halo stopped
    A *= 1.0 + uMul * 0.5 * exp(-pow((r + wob - uSun.z - 1.5) / 1.6, 2.0)) * uDisc.a
             * smoothstep(0.25, 0.7, gn(d / 6.0 + 14.0));    // pooled against the reserve, here and there
    float disc = 1.0 - smoothstep(uSun.z - 0.8, uSun.z + 0.8, r + wob);
    A = mix(A, uDisc.rgb, disc * uDisc.a);
  }
  // the moon: lifted out of the wash, in its phase
  if (uMoon.w > 0.0) {
    vec2 d = w - uMoon.xy;
    float r = length(d);
    float cr = cos(uMoonLit.y), sr = sin(uMoonLit.y);
    vec2 m = vec2(cr * d.x + sr * d.y, -sr * d.x + cr * d.y) / uMoon.z;     // lit limb on +x
    float term = 1.0 - 2.0 * uMoonLit.x;                                    // 1 new … −1 full
    float edge = sqrt(max(0.0, 1.0 - m.y * m.y));
    float inside = 1.0 - smoothstep(1.0 - 0.07, 1.0 + 0.07, length(m) + (fbm2(d / 5.0) - 0.5) * 0.10);
    float lit = inside * smoothstep(-0.08, 0.08, m.x - term * edge);
    float stain = 1.0 - 0.035 * smoothstep(0.42, 0.72, fbm2(d / 5.5 + 9.0));
    A *= 1.0 - uMoonLit.w * (0.6 * exp(-pow(r / (uMoon.z * 2.6), 2.0)) + 0.4 * exp(-pow(r / (uMoon.z * 7.0), 2.0)));   // re-wet halo
    A = mix(A, uMoonA, lit * uMoonLit.z * stain * uMoon.w);
    A *= 1.0 - uMul * 0.07 * inside * (1.0 - lit) * uMoon.w;               // earthshine: the faintest lift
    float rim = exp(-pow((r - uMoon.z - 1.6) / 1.3, 2.0)) * lit;
    A += uSky[0].rgb * 0.75 * rim * (1.0 - uDark) * (0.4 + 1.2 * gn(d / 4.0 + 3.0)) * uMoon.w;
  }

  // ── the land: glaze over glaze ──
  vec3 L = mix(uGround.rgb, uMist.rgb, side * uMist.a) * (1.0 + uMul * 0.3 * brush);
  float mistN = fbm3(vec2(wx / 150.0 + uEdge.z, y / 52.0) + 17.0) - 0.5;
  for (int i = 0; i < 4; i++) {
    float fi = float(i);
    float ry;
    float lf;
    if (i == 0) { ry = r0; lf = lf0; }
    else { ry = ridgeY(i, wx); lf = gn(vec2(wx / 80.0 + fi * 5.0, 2.5 + fi)); }
    float s = y - ry;
    float lostEdge = mix(0.6, 4.5, max(smoothstep(0.56, 0.32, lf), 0.55 * (1.0 - found)));
    float top = smoothstep(-lostEdge, lostEdge, s);
    float len = uEdge.y * (34.0 + 11.0 * fi + 8.0 * fi * fi);
    float body = mix(1.0, uGround.a + (i == 0 ? 0.2 : 0.0), smoothstep(0.0, 10.0, s));   // charged along the top, then pulled out with water
    float dis = 1.0 - smoothstep(0.10 * len, len, s * (1.0 + 1.3 * mistN) + 10.0 * warp.y);
    dis = mix(dis, 1.0, uHill[i].a);                                         // (dark: the glaze never quite leaves)
    float dry = exp(-max(s, 0.0) / 1.5) * uEdge.x * smoothstep(0.36, 0.60, lf) * (0.3 + 0.7 * found);
    float d = top * body * dis * pass;
    // frost: the shoulders lifted pale just under the drying edge
    float frost = uSeason.x * exp(-pow((s - 4.5) / 3.2, 2.0)) * smoothstep(0.3, 0.6, gn(vec2(wx / 23.0, 30.0 + fi)));
    vec3 glaze = uHill[i].rgb * (1.0 + uMul * (0.3 * brush + dry - 0.55 * frost)) * (1.0 + 0.9 * gran);
    if (i >= 2 && uSeason.y > 0.0) {
      // blossom: rose dropped into the damp slope, flowering
      // trees in flower along the crest: soft puffs, dropped in wet
      float bl = smoothstep(0.50, 0.66, fbm3(vec2(wx / 26.0, y / 17.0) + 70.0 + fi * 9.0)) * exp(-pow((s - 3.0) / 9.0, 2.0)) * uSeason.y;
      glaze = mix(glaze, uBlossomA * (1.0 + 0.6 * gran), bl);
      d = max(d, bl * 0.9);
    }
    L = L * (1.0 - d * uDark) + glaze * d;
  }

  // the water in the valley: paper left, the far shore let run down into it; then the near bank
  {
    float bankY = uH + uLake.y + uTilt.y * 4.5 - 76.0 * (ridgeN((wx + uTilt.x * 12.0) / 175.0 + 55.0, 33.0) - 0.5)
                + 1.8 * (gn(vec2(wx / 6.0, 9.0)) - 0.5);
    float sb = y - bankY;
    float topb = smoothstep(-0.7, 0.7, sb);
    float shore = uH + uLake.x + uTilt.y * 3.2 + 2.4 * (gn(vec2(wx / 85.0, 61.0)) - 0.5);
    float sw = y - shore;
    float water = smoothstep(-0.7, 1.3, sw) * (1.0 - topb);
    float ripple = gn(vec2(wx / 52.0 + 9.0, y / 2.1));                    // long level strokes
    float refl = exp(-max(sw, 0.0) / 26.0);
    vec3 W = uWater.rgb * (1.0 + uMul * (0.25 * brush + 0.7 * (ripple - 0.5))) * (1.0 + 0.5 * gran);
    W = mix(W, uHill[3].rgb, refl * uLake.z * (0.55 + 0.9 * ripple));   // the far shore, mirrored and pulled down
    float gx = (wx - uGlit.x) / (uGlit.y * (1.0 + sw / 90.0));
    float glit = uGlit.z * exp(-gx * gx) * smoothstep(0.52, 0.70, ripple + 0.12 * feather) * smoothstep(0.0, 8.0, sw);
    W = mix(W, uGlitA, glit);
    L = mix(L, W, water * uWater.a);
    float lfb = gn(vec2(wx / 80.0 + 31.0, 7.5));
    float bodyb = mix(1.0, uLake.w, smoothstep(0.0, 12.0, sb));
    float disb = mix(1.0 - smoothstep(14.0, 120.0, sb * (1.0 + 1.3 * mistN)), 1.0, uBank.a);
    float dryb = exp(-max(sb, 0.0) / 1.6) * uEdge.x * 0.6 * smoothstep(0.36, 0.60, lfb) * (0.3 + 0.7 * found);
    float db = topb * bodyb * disb * pass;
    L = L * (1.0 - db * uDark) + uBank.rgb * db * (1.0 + uMul * (0.3 * brush + dryb)) * (1.0 + 0.9 * gran);
  }

  A = mix(A, L, land) * uDeep;

  // the heaviest washes skip the highest tooth
  A *= 1.0 - uSpark * smoothstep(0.60, 0.70, tooth);

  vec3 col = uPaper * exp(-A);
  col *= 1.0 + uTex.z * (tooth - 0.5);
  col = toGamma(col);
  float n = hash(px + 0.5) + hash(px * 1.7 + 19.0) - 1.0;      // triangular dither
  outColor = vec4(col + n / 255.0, 1.0);
}`;

// ───────────────────────────────────────────────────────────── geometry ──

/** Where things are on this display, in points. World x = 0 at the anchor window's left. */
function layoutFor(state) {
  const phone = state.phone ?? { x: 0, width: state.width };
  const duo = state.device !== 'iphone';
  const H = duo ? 300 : 352;
  return {
    duo, H, originX: phone.x, worldW: phone.width, width: state.width, height: state.height,
    // where the land may be found crisp: the strip; the leading margin; the fold gutter
    windows: duo ? [[414, 44], [-436, 46], [-10, 22]] : [[-9999, 0], [-9999, 0], [-9999, 0]],
    bandBottom: duo ? 88 : 136,
    gap: duo ? [203, 303] : [206, 322],
    tonight: duo ? { x: 386, y: 210 } : { x: 262, y: 96 },
    caption: duo ? [296, 376, 200, 220] : [220, 304, 105, 124],
    clouds: duo ? [[270, 44, 150, 26], [-110, 48, 170, 28], [-430, 36, 110, 24]] : [[262, 100, 120, 26], [60, 40, 90, 20], [-999, 0, 1, 1]],
    bars: duo ? [[400, 232, 190, 26], [-30, 226, 220, 24], [-420, 214, 170, 24]] : [[330, 290, 150, 26], [40, 280, 150, 24], [-999, 0, 1, 1]],
    // back-runs, in clear sky: between his name and the gear; the leading margin; the strip
    runs: duo ? [[262, 60, 34, 1], [-436, 160, 46, 1], [430, 214, 30, 0.9]] : [[262, 112, 30, 1], [-999, 0, 1, 0], [-999, 0, 1, 0]],
  };
}

/** A body's height on the sheet from its real altitude: opened out near the horizon,
 *  and held under the header — unless it is high while it crosses the gap between his
 *  name and the gear, where it comes up into the top band. */
function bodyPoint(G, progress, altitude, radius) {
  const x = (0.04 + 0.92 * clamp01(progress)) * G.worldW;
  const alt = altitude * DEG;
  const span = G.H - (G.bandBottom + radius + 3);
  let y;
  if (alt >= 0) y = G.H - 14 - (span - 14) * Math.pow(Math.min(alt, 90) / 90, 0.55);
  else y = G.H - 14 - alt * 9;
  const inGap = smoothstep(G.gap[0] - 2, G.gap[0] + 12, x) * (1 - smoothstep(G.gap[1] - 12, G.gap[1] + 2, x));
  const high = smoothstep(38, 46, alt);
  const up = inGap * high;
  if (up > 0) {
    const top = G.duo ? 30 : 84;
    const low = G.bandBottom - radius - 5;
    const yBand = low - (low - top) * clamp01((alt - 40) / 40);
    y = lerp(y, yBand, up);
  }
  return { x, y };
}

/** Piecewise-linear: [[t, value], …], t ascending. */
function pw(stops, t) {
  if (t <= stops[0][0]) return stops[0][1];
  for (let i = 0; i < stops.length - 1; i += 1) {
    const [t0, v0] = stops[i], [t1, v1] = stops[i + 1];
    if (t <= t1) return v0 + (v1 - v0) * ((t - t0) / (t1 - t0));
  }
  return stops[stops.length - 1][1];
}

/** A night's star on the sheet (world points): its (u, v) weighted toward the sky that can
 *  be seen — the top band, the strip — and moved clear of the text and the things drawn
 *  on the sky. A function of the night and the display alone. */
function starPlace(star, G) {
  const n = star.night;
  let x, y;
  if (G.duo) {
    x = pw([[0, 3], [0.035, 17], [0.035, 20], [0.76, 360], [0.76, 366], [1, 463]], star.u);
    y = pw([[0, 4], [0.46, 86], [1, 266]], star.v);
    const inside = (x0, x1, y0, y1) => x >= x0 && x <= x1 && y >= y0 && y <= y1;
    if (inside(16, 86, 18, 88)) y = 3 + hash(n, 12) * 15;                                // the avatar → the lane above
    else if (inside(86, 198, 20, 88)) {                                                  // his name and age
      if (hash(n, 11) < 0.45) y = 3 + hash(n, 12) * 15; else x += 114;
    } else if (inside(314, 364, 24, 84)) x = 200 + hash(n, 13) * 112;                    // the gear → the gap
    else if (inside(376, 450, 18, 162)) {                                                // clock, island
      if (hash(n, 14) < 0.38) y = 168 + ((y - 18) / 144) * 96; else x = 22 + hash(n, 13) * 336;
    }
  } else {
    x = 5 + 392 * star.u;
    y = pw([[0, 5], [0.52, 134], [1, 322]], star.v);
    const inside = (x0, x1, y0, y1) => x >= x0 && x <= x1 && y >= y0 && y <= y1;
    if (inside(126, 276, 4, 54)) y = 55 + hash(n, 12) * 11;                              // the island
    else if (inside(16, 126, 10, 44) || inside(276, 392, 10, 44)) y = 46 + hash(n, 12) * 18;   // clock, battery
    if (inside(10, 82, 64, 136)) y = 46 + hash(n, 12) * 18;                              // the avatar
    else if (inside(82, 202, 64, 136)) y += 96;                                          // his name and age
    else if (inside(332, 394, 72, 130)) x = 206 + hash(n, 13) * 120;                     // the gear
  }
  if (Math.hypot(x - G.tonight.x, y - G.tonight.y) < 20) y -= 26;                        // room for tonight's
  const cap = G.caption;                                                                  // …and for its name
  if (x > cap[0] && x < cap[1] && y > cap[2] && y < cap[3]) y = y < (cap[2] + cap[3]) / 2 ? cap[2] - 3 : cap[3] + 3;
  return { x, y };
}

// ─────────────────────────────────────────────────────────────── module ──

export function create(host) {
  const doc = host.ownerDocument ?? document;
  const make = () => {
    const c = doc.createElement('canvas');
    c.setAttribute('aria-hidden', 'true');
    c.style.cssText = 'position:absolute;left:0;top:0;display:block;pointer-events:none;';
    return c;
  };
  const glCanvas = make();
  const overCanvas = make();      // later in the host, so above the wash
  host.append(glCanvas, overCanvas);
  const over = overCanvas.getContext('2d');
  const gl = glCanvas.getContext('webgl2', { antialias: false, alpha: false, depth: false, stencil: false,
    preserveDrawingBuffer: true, powerPreference: 'high-performance' });
  if (!gl) throw new Error('wet-wash: this browser has no WebGL2');

  const compile = (type, src) => {
    const sh = gl.createShader(type);
    gl.shaderSource(sh, src);
    gl.compileShader(sh);
    if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) throw new Error(`wet-wash shader: ${gl.getShaderInfoLog(sh)}`);
    return sh;
  };
  const program = gl.createProgram();
  gl.attachShader(program, compile(gl.VERTEX_SHADER, VERT));
  gl.attachShader(program, compile(gl.FRAGMENT_SHADER, FRAG));
  gl.linkProgram(program);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error(`wet-wash link: ${gl.getProgramInfoLog(program)}`);
  gl.useProgram(program);
  const U = {};
  for (let i = 0, n = gl.getProgramParameter(program, gl.ACTIVE_UNIFORMS); i < n; i += 1) {
    const info = gl.getActiveUniform(program, i);
    U[info.name.replace(/\[0\]$/, '')] = gl.getUniformLocation(program, info.name);
  }
  const buf = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, buf);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
  const loc = gl.getAttribLocation(program, 'aPos');
  gl.enableVertexAttribArray(loc);
  gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);

  let destroyed = false;
  let lastState = null;
  let washKey = '';
  // The caption's face (the lab bundles Nunito); a frame drawn before it arrives is drawn again.
  const ready = (doc.fonts && doc.fonts.load ? doc.fonts.load('700 9.5px Nunito').catch(() => {}) : Promise.resolve())
    .then(() => { if (!destroyed && lastState) render(lastState); });
  const timing = { first: null, wash: 0, washes: 0, over: 0, frames: 0 };   // ms: first frame; a frame that repaints the wash; one that only moves the stars

  /** Everything the wash needs for this state: uniforms, as plain numbers. */
  function compose(state) {
    const G = layoutFor(state);
    const dark = state.scheme === 'dark';
    const scheme = dark ? 'dark' : 'light';
    const P = presenceOf(state);
    const alt = state.sun.altitude * DEG;
    const p = P.presence;
    const paper = PAGE[scheme];
    const paperLin = [toLin(paper.r), toLin(paper.g), toLin(paper.b)];
    const pageL = toOklab(PAGE.light).L;
    const nightness = 1 - smoothstep(-12, -5, alt);
    const q = (lab) => quiet(lab, p, dark, pageL, nightness);
    const A = (lab) => absorb(lab, paperLin);

    // Dawn is not dusk played backwards: the warm end turns to rose and lemon, a little thinner.
    const morning = state.sun.isNight ? state.localHour < 12 : state.sun.progress < 0.5;
    const dawn = (lab) => {
      if (!morning) return lab;
      const C0 = Math.hypot(lab.a, lab.b);
      let h = Math.atan2(lab.b, lab.a) * DEG;
      const warm = smoothstep(-30, 0, h) * (1 - smoothstep(95, 120, h));       // rose … gold
      h += warm * (h < 42 ? -14 : 9);
      const c = C0 * (1 - 0.10 * warm);
      return { L: lab.L + (dark ? 0 : 0.004 * warm), a: c * Math.cos(h / DEG), b: c * Math.sin(h / DEG) };
    };
    const sky = keyed(SKY[scheme], alt).map(dawn).map(q);
    const twilight = smoothstep(-11, -5, alt) * (1 - smoothstep(4, 10, alt));
    const night = 1 - smoothstep(-12, -5, alt);
    // How much of the wash is on the paper. Light: at hush it dies away below the top band;
    // at the bloom it floods down to the horizon on the sun's side. Dark: it covers the sheet.
    const cov = dark ? [1, 1, 1, 1] : [
      Math.max(lerp(0.05, 0.40, p), night * 0.55), Math.max(lerp(0.05, 0.92, p), night * 0.55),
      Math.max(lerp(0.03, 0.80, p), night * 0.50), Math.max(lerp(0.04, 1.00, p), night * 0.50),
    ];
    const gSky = dark ? [0.9, 0.9, 0.8, 0.55, 0.4] : [1, 0.95, 0.7, 0.4, 0.3];

    // The land turns with the season: the nearer the glaze, the more of its own colour.
    const se = seasonOf(state.dayOfYear, state.latitude);
    const dayness = smoothstep(-9, 3, alt);
    const turned = smoothstep(0.55, 0.85, se.leafHue);
    const wGreen = se.grass * (0.35 + 0.65 * se.foliage) * (1 - turned) * (1 - se.snow);
    const wRusset = se.foliage * turned * (1 - se.snow);
    const wBare = (1 - Math.max(se.foliage, se.grass * 0.6)) * (1 - se.snow);
    const local = (C, h) => [C * Math.cos(h / DEG), C * Math.sin(h / DEG)];
    const tints = [[wGreen, local(dark ? 0.062 : 0.078, 140 - 14 * se.leafHue)], [wRusset, local(dark ? 0.080 : 0.085, 50)],
      [wBare, local(dark ? 0.036 : 0.034, 38)], [se.snow, local(dark ? 0.034 : 0.028, 258)]];
    const wSum = tints.reduce((sum, [wt]) => sum + wt, 0) || 1;
    const ta = tints.reduce((sum, [wt, ab]) => sum + wt * ab[0], 0) / wSum;
    const tb = tints.reduce((sum, [wt, ab]) => sum + wt * ab[1], 0) / wSum;
    const seasoned = (lab, i) => {
      // far glazes are the air's colour; the near ones their own (never the two halved into grey)
      const k = [0.22, 0.52, 0.82, 0.94][i] * (0.40 + 0.60 * dayness) * Math.min(1, wSum);
      const snowLift = se.snow * (dark ? 0.085 : 0.040) * k;
      return { L: lab.L + snowLift, a: lab.a * (1 - k) * (1 - k) + ta * k * 1.15, b: lab.b * (1 - k) * (1 - k) + tb * k * 1.15 };
    };
    const hush = (lab) => (dark ? lab : { L: lab.L, a: lab.a * (0.72 + 0.28 * p), b: lab.b * (0.72 + 0.28 * p) });   // the land's own colour stays under the accents
    const hills = keyed(HILLS[scheme], alt).map(seasoned).map(q).map(hush);
    const groundLab = { L: hills[0].L + 0.022, a: hills[0].a * 1.1, b: hills[0].b * 1.1 };

    // Sun and moon.
    const sunR = 16;
    const sunAt = bodyPoint(G, state.sun.isNight ? (state.localHour > 12 ? 1 : 0) : state.sun.progress, state.sun.altitude, sunR);
    const sunUp = smoothstep(-5, -1.2, alt);
    const haloLab = dawn(keyed(HALO[scheme], alt));
    const discLab = dark ? keyed(DISC_DARK, alt) : null;
    const sunSide = smoothstep(-13, -6, alt);

    let moon = null;
    if (state.moon) {
      const r = 12.5;
      const at = bodyPoint(G, state.moon.passProgress, state.moon.altitude, r);
      moon = { ...at, r, fraction: state.moon.fraction, rotation: state.moon.rotation, day: state.moon.inDaylight };
    }

    const cloudsOut = smoothstep(-13, -7, alt);      // by full night the sky has cleared
    // The water takes the sky's low colours; the bank is the nearest, darkest glaze.
    const waterLab = dark ? mixLab(hills[1], sky[3], 0.42) : mixLab(sky[3], sky[4], 0.5);
    const bankLab = dark ? { L: hills[3].L - 0.022, a: hills[3].a * 0.9, b: hills[3].b * 0.9 }
      : { L: hills[3].L - 0.012, a: hills[3].a * 1.05, b: hills[3].b * 1.05 };
    const mistLab = mixLab(groundLab, q(haloLab), 0.38);

    return { G, dark, P, alt, p, paperLin, A, q, twilight, night, cov, gSky, cloudsOut, se, dayness,
      blossom: A(q(lch(dark ? [.44, .10, 2] : [.85, .085, 2]))),
      water: A(waterLab), bank: A(bankLab),
      sky: sky.flatMap((lab, i) => [...A(lab), gSky[i]]),
      hills: hills.map((lab) => A(lab)),
      ground: dark ? A(groundLab) : [0, 0, 0],
      mist: dark ? A(mistLab) : [0, 0, 0],
      shade: A(q(keyed(SHADE[scheme], alt))),
      bar: A(q(keyed(BAR[scheme], alt))),
      sun: { ...sunAt, r: sunR, up: sunUp, side: sunSide, halo: A(haloLab), disc: discLab ? A(discLab) : [0, 0, 0] },
      moon };
  }

  function drawWash(state, C, time) {
    const { G, dark, p } = C;
    const s = state.dpr;
    const set4 = (name, a, b, c, d) => gl.uniform4f(U[name], a, b, c, d);
    const set3a = (name, v, a) => gl.uniform4f(U[name], v[0], v[1], v[2], a);
    gl.viewport(0, 0, glCanvas.width, glCanvas.height);
    gl.uniform2f(U.uRes, glCanvas.width, glCanvas.height);
    gl.uniform1f(U.uDpr, s);
    gl.uniform1f(U.uOriginX, G.originX);
    gl.uniform1f(U.uWorldW, G.worldW);
    gl.uniform1f(U.uH, G.H);
    gl.uniform1f(U.uDark, dark ? 1 : 0);
    gl.uniform1f(U.uMul, dark ? 0.12 : 1);
    gl.uniform1f(U.uDeep, dark ? 1 + 0.07 * C.P.depth : 1 + 0.14 * C.P.depth * C.night);
    gl.uniform3f(U.uPaper, C.paperLin[0], C.paperLin[1], C.paperLin[2]);
    gl.uniform4fv(U.uSky, new Float32Array(C.sky));
    const stays = dark ? [0.22, 0.30, 0.40, 1] : [0, 0, 0, 0];
    gl.uniform4fv(U.uHill, new Float32Array(C.hills.flatMap((v, i) => [...v, stays[i]])));
    set3a('uGround', C.ground, dark ? 0.66 : 0.42 * (1 - 0.45 * C.se.snow));
    set4('uSeason', C.se.frost * (dark ? 0.5 : 0.9), C.se.blossom * (0.35 + 0.65 * C.dayness) * (dark ? 0.7 : 0.9), C.se.snow, 0);
    gl.uniform3f(U.uBlossomA, C.blossom[0], C.blossom[1], C.blossom[2]);
    // opening the Duo: a second pass of the wash crosses the leading page from the fold
    const opening = state.event && state.event.kind === 'open' ? state.event.age : null;
    set4('uOpen', opening == null ? -9999 : lerp(40, -G.originX - 160, smoothstep(0, 1.5, opening)), opening == null ? 0 : 0.3, 0, 0);
    set3a('uMist', C.mist, 0.75 * C.twilight);
    set3a('uHalo', C.sun.halo, C.sun.up * (dark ? 0.92 : 0.85));
    set3a('uDisc', C.sun.disc, C.sun.up);
    set4('uSun', C.sun.x, C.sun.y, C.sun.r, C.sun.side);
    if (C.moon) {
      const m = C.moon;
      const strength = m.day ? (dark ? 0.35 : 0.8) : 1;
      set4('uMoon', m.x, m.y, m.r, strength);
      set4('uMoonLit', m.fraction, m.rotation, dark ? 0.995 : 0.97, (dark ? 0.055 : 0.30) * (0.35 + 0.65 * m.fraction) * (m.day ? 0.3 : 1));
      const moonA = dark ? C.A(lch(CREAM)) : [0, 0, 0];
      gl.uniform3f(U.uMoonA, moonA[0], moonA[1], moonA[2]);
    } else {
      set4('uMoon', 0, 0, 1, 0);
      set4('uMoonLit', 0, 0, 0, 0);
      gl.uniform3f(U.uMoonA, 0, 0, 0);
    }
    set3a('uShade', C.shade, (dark ? 0.20 : 0.5) * C.cloudsOut);
    const sway = 13 * Math.sin(time / 97) + 6 * Math.sin(time / 41 + 1);     // clouds drift, and come back
    set4('uCloud', (dark ? lerp(0.05, 0.13, p) : 0.94) * C.cloudsOut, 1.0, 1.0, sway);
    set3a('uBar', C.bar, C.cloudsOut * lerp(0.25, 0.85, p));
    set4('uTex', dark ? 0.08 : 0.28, dark ? 2.0 : 1.0, dark ? 0 : 0.014, dark ? 0 : 1);
    gl.uniform1f(U.uSpark, dark ? 0.05 : 0);
    const runs = G.runs.flatMap(([x, y, r, k]) => [x, y, r * (0.7 + 0.3 * p), k * (0.35 + 0.65 * p)]);
    gl.uniform4fv(U.uRun, new Float32Array(runs));
    gl.uniform4fv(U.uCl, new Float32Array(G.clouds.flat()));
    gl.uniform4fv(U.uBr, new Float32Array(G.bars.flat()));
    gl.uniform4fv(U.uWin, new Float32Array(G.windows.flatMap(([x, hw]) => [x, hw, 0, 0])));
    set4('uFlow', lerp(14, 24, p), 0, time * 0.0012 * (0.3 + 0.7 * p), p);
    set4('uEdge', dark ? 2.4 : 1.3, dark ? 1.5 : 1.0, time * 0.0008, 0.6 * p);
    set4('uLean', 1 - 0.40 * C.twilight, 0.30 * C.twilight, lerp(0.03, 0.10, p), 0);
    set4('uLake', G.duo ? 172 : 205, G.duo ? 262 : 345, dark ? 0.62 : 0.30, dark ? 1 : 0.42);
    set3a('uWater', dark ? C.water : C.water.map((v) => v * 0.16 * (0.4 + 0.6 * p)), 1);
    set3a('uBank', dark ? C.bank : C.bank.map((v) => v * 0.8), dark ? 1 : 0);
    // the light on the water: under the low sun; at night under the moon
    const moonNight = C.moon && !C.moon.day ? C.night * (0.35 + 0.65 * C.moon.fraction) : 0;
    const sunLow = C.sun.up * (1 - smoothstep(6, 16, C.alt));
    const useMoon = moonNight > sunLow;
    set4('uGlit', useMoon ? C.moon.x : C.sun.x, useMoon ? 15 : 22, useMoon ? (dark ? 0.26 : 0) * moonNight : (dark ? 0.30 : 0.55) * sunLow, 0);
    const glitA = useMoon ? C.A(lch(CREAM)) : C.sun.halo;
    gl.uniform3f(U.uGlitA, glitA[0], glitA[1], glitA[2]);
    set4('uCov', C.cov[0], C.cov[1], C.cov[2], C.cov[3]);
    gl.uniform2f(U.uTilt, state.tilt?.x ?? 0, state.tilt?.y ?? 0);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
  }

  // ── his stars: flecks of gouache, one per night ──

  let starCache = { key: '', list: [] };
  function starList(state, G, lit) {
    const key = `${state.ageDays}|${lit}|${state.device}`;
    if (starCache.key !== key) {
      const list = nights(state.ageDays, { tonightLit: lit }).map((star) => {
        const at = star.kind === 'tonight' ? G.tonight : starPlace(star, G);
        return { ...star, x: at.x, y: at.y, tilt: hash(star.night, 31) * Math.PI, squash: 0.04 + 0.13 * hash(star.night, 32) };
      });
      // The leading page carries the ordinary sky: spatter off the brush, nobody's nights.
      const spatter = [];
      if (G.originX > 0) {
        for (let i = 0; i < 64; i += 1) {
          const cx = -G.originX + 8 + hash(i, 41) * (G.originX - 20);
          const cy = 5 + Math.pow(hash(i, 42), 1.5) * 226;
          spatter.push({ x: cx, y: cy, r: 0.35 + 0.55 * Math.pow(hash(i, 43), 2), a: 0.22 + 0.33 * hash(i, 44), phase: hash(i, 45), period: 3 + 4 * hash(i, 46) });
        }
        // …and the river of it: one flick of the brush across the page, thickest in the middle
        for (let i = 0; i < 300; i += 1) {
          const along = hash(i, 51);
          const gauss = (hash(i, 52) + hash(i, 53) + hash(i, 54) - 1.5) / 1.5;          // about −1…1, bunched at 0
          const width = 26 + 22 * Math.sin(Math.PI * along);
          const cx = -G.originX + 20 + along * (G.originX - 60) + gauss * width * 0.35;
          const cy = 232 - along * 236 + gauss * width;
          if (cy < 3 || cy > 238) continue;
          spatter.push({ x: cx, y: cy, r: 0.28 + 0.62 * Math.pow(hash(i, 55), 3), a: 0.16 + 0.44 * hash(i, 56) * (1 - 0.6 * Math.abs(gauss)), phase: hash(i, 57), period: 0 });
        }
      }
      starCache = { key, list, spatter };
    }
    return starCache;
  }

  /** A four-point glint, drawn by hand: two tapered strokes. */
  function glint(ctx, x, y, long, short, turn, width) {
    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(turn);
    for (const [len, ang] of [[long, 0], [short, Math.PI / 2]]) {
      ctx.rotate(ang);
      ctx.beginPath();
      ctx.moveTo(-len, 0);
      ctx.quadraticCurveTo(0, -width, len, 0);
      ctx.quadraticCurveTo(0, width, -len, 0);
      ctx.fill();
    }
    ctx.restore();
  }

  function paintOver(state, C, time) {
    const { G, dark, P } = C;
    const s = state.dpr;
    over.setTransform(1, 0, 0, 1, 0, 0);
    over.clearRect(0, 0, overCanvas.width, overCanvas.height);
    over.setTransform(s, 0, 0, s, G.originX * s, 0);

    const lit = state.asleep === 'night';
    const bedtime = state.event && state.event.kind === 'bedtime' ? state.event.age : null;
    const { list, spatter } = starList(state, G, lit);
    const dusk = 1 - smoothstep(-2, 9, C.alt);
    const out = clamp01(P.stars + 0.22 * P.depth * dusk);          // how much of the starfield is out
    const still = time == null;
    const tonight = list.find((star) => star.kind === 'tonight');
    const ignite = tonight ? (bedtime == null ? 1 : ignition(bedtime)) : 0;
    const paperCss = dark ? null : 'rgba(246, 246, 250,';

    const cool = [226, 232, 255], white = [250, 248, 244], warm = [255, 240, 214];
    const tint = (wm) => {
      const a = wm < 0 ? cool : warm, k = Math.min(1, Math.abs(wm) * 1.5);
      return [0, 1, 2].map((i) => Math.round(white[i] + (a[i] - white[i]) * k));
    };

    if (out > 0.003) {
      if (dark && G.originX > 0) {
        for (let k = 0; k < 5; k += 1) {
          const along = 0.12 + 0.19 * k;
          const cx = -G.originX + 20 + along * (G.originX - 60), cy = 232 - along * 236;
          const R = 70 + 30 * Math.sin(Math.PI * along);
          const g = over.createRadialGradient(cx, cy, 0, cx, cy, R);
          g.addColorStop(0, `rgba(150, 160, 230, ${0.035 * out})`);
          g.addColorStop(1, 'rgba(150, 160, 230, 0)');
          over.fillStyle = g;
          over.beginPath(); over.arc(cx, cy, R, 0, TAU); over.fill();
        }
      }
      // spatter on the leading page
      for (const sp of spatter) {
        const tw = still || !sp.period ? 1 : 0.75 + 0.25 * Math.cos(TAU * (time / sp.period + sp.phase));
        const a = sp.a * out * tw * (dark ? 1 : 0.8);
        if (dark) {
          over.fillStyle = `rgba(236, 238, 250, ${a})`;
          over.beginPath(); over.arc(sp.x, sp.y, sp.r, 0, TAU); over.fill();
        } else {
          over.fillStyle = `rgba(104, 98, 160, ${a * 0.55})`;
          over.beginPath(); over.arc(sp.x, sp.y, sp.r * 1.1, 0, TAU); over.fill();
        }
      }
    }

    const moonAt = C.moon;
    for (const star of list) {
      if (star.kind === 'tonight') continue;
      if (moonAt && Math.hypot(star.x - moonAt.x, star.y - moonAt.y) < moonAt.r + 2.5) continue;    // behind the moon
      const th = 0.95 - 0.9 * star.magnitude;
      let vis = smoothstep(th - 0.12, th + 0.12, out * 1.12) * smoothstep(0, 0.06, out);
      // the others answer: a ripple leaves his star and crosses the sky
      let answer = 0;
      if (bedtime != null && tonight) {
        const d = Math.hypot(star.x - tonight.x, star.y - tonight.y);
        const front = (bedtime - 1.5) * 190;
        answer = bedtime > 1.5 ? Math.exp(-Math.pow((d - front) / 46, 2)) * Math.exp(-(bedtime - 1.5) / 4) : 0;
        vis = Math.max(vis, 0.35 * answer * (star.magnitude > 0.5 ? 1 : 0.4));
      }
      if (vis < 0.004) continue;
      const tw = still ? 1 : twinkle(star, time);
      const a = clamp01((0.50 + 0.50 * star.magnitude) * vis * (0.86 + 0.14 * tw) * (1 + 0.6 * answer));
      const r = (0.55 + 1.35 * star.magnitude) * (1 + 0.25 * answer) * (0.94 + 0.06 * tw);
      const special = star.kind === 'first' || star.kind === 'month';
      if (dark) {
        const c = tint(star.warmth);
        if (star.magnitude > 0.55) {
          const g = over.createRadialGradient(star.x, star.y, 0, star.x, star.y, r * 3.4);
          g.addColorStop(0, `rgba(${c[0]},${c[1]},${c[2]},${0.13 * a})`);
          g.addColorStop(1, `rgba(${c[0]},${c[1]},${c[2]},0)`);
          over.fillStyle = g;
          over.beginPath(); over.arc(star.x, star.y, r * 3.4, 0, TAU); over.fill();
        }
        over.fillStyle = `rgba(${c[0]},${c[1]},${c[2]},${a})`;
        over.beginPath();
        over.ellipse(star.x, star.y, r * (1 + star.squash), r * (1 - star.squash), star.tilt, 0, TAU);
        over.fill();
        if (special) {
          over.fillStyle = `rgba(${c[0]},${c[1]},${c[2]},${0.78 * a})`;
          const long = star.kind === 'first' ? 8.5 : 5.6;
          glint(over, star.x, star.y, long * (0.9 + 0.1 * tw), long * 0.72, 0.12 + (star.tilt - 1.5) * 0.12, 0.55);
        }
      } else {
        // light: flecks of the night's own pigment, spattered on the pale wash
        over.fillStyle = `rgba(86, 80, 156, ${0.82 * a})`;
        over.beginPath();
        over.ellipse(star.x, star.y, r * 0.86 * (1 + star.squash), r * 0.86 * (1 - star.squash), star.tilt, 0, TAU);
        over.fill();
        if (special) {
          over.fillStyle = `rgba(86, 80, 156, ${0.62 * a})`;
          const long = star.kind === 'first' ? 8.5 : 5.6;
          glint(over, star.x, star.y, long, long * 0.72, 0.12 + (star.tilt - 1.5) * 0.12, 0.5);
        }
      }
    }

    // summer dusk: fireflies over the water meadow — points of warm gouache that come and go
    const flies = C.se.fireflies * (1 - smoothstep(-1, 7, C.alt)) * smoothstep(-16, -9, C.alt + 6 * P.depth);
    if (flies > 0.01) {
      for (let i = 0; i < 26; i += 1) {
        const span = G.originX + G.worldW;
        const bx = -G.originX + hash(i, 61) * span, by = G.H + 26 + hash(i, 62) * 150;
        const ph = hash(i, 63), per = 5 + 6 * hash(i, 64);
        const tt = still ? ph * per : time + ph * per;
        const blink = still ? (hash(i, 65) > 0.45 ? 0.85 : 0) : Math.pow(Math.max(0, Math.sin(TAU * tt / per)), 3);
        if (blink < 0.02) continue;
        const x = bx + (still ? 0 : 7 * Math.sin(tt / 3.1 + i)), y = by + (still ? 0 : 4 * Math.sin(tt / 2.3 + 2 * i));
        const a = flies * blink * (dark ? 0.9 : 0.8);
        const g = over.createRadialGradient(x, y, 0, x, y, 6);
        g.addColorStop(0, dark ? `rgba(236, 232, 150, ${0.42 * a})` : `rgba(226, 190, 70, ${0.34 * a})`);
        g.addColorStop(1, dark ? 'rgba(236, 232, 150, 0)' : 'rgba(226, 190, 70, 0)');
        over.fillStyle = g;
        over.beginPath(); over.arc(x, y, 6, 0, TAU); over.fill();
        over.fillStyle = dark ? `rgba(250, 246, 190, ${a})` : `rgba(214, 168, 40, ${a})`;
        over.beginPath(); over.arc(x, y, 0.95, 0, TAU); over.fill();
      }
    }

    // snow in the air: slow flecks of white, three depths
    if (C.se.snowfall > 0) {
      const count = Math.round(70 * C.se.snowfall);
      const span = G.originX + G.worldW + 40;
      for (let i = 0; i < count; i += 1) {
        const depth = i % 3;
        const fall = (still ? 0 : time) * (5 + 3.5 * depth) + hash(i, 71) * (G.height + 20);
        const y = (fall % (G.height + 20)) - 10;
        const x = -G.originX - 20 + ((hash(i, 72) * span + (still ? 0 : 5 * Math.sin(time / 4 + i)) + y * 0.12) % span);
        const r = 0.7 + 0.5 * depth + 0.4 * hash(i, 73);
        const a = (0.30 + 0.16 * depth) * (dark ? 0.75 : 1);
        over.fillStyle = dark ? `rgba(226, 230, 246, ${a})` : `rgba(255, 255, 255, ${Math.min(1, a * 1.9)})`;
        over.beginPath(); over.arc(x, y, r, 0, TAU); over.fill();
        if (!dark) {
          over.strokeStyle = `rgba(128, 132, 176, ${a * 0.5})`;
          over.lineWidth = 0.4;
          over.beginPath(); over.arc(x, y, r + 0.2, 0, TAU); over.stroke();
        }
      }
    }

    // tonight's: a touch of warm gouache, still wet
    if (tonight && ignite > 0.002) {
      const tw = still ? 1 : twinkle(tonight, time);
      const k = Math.min(ignite, 1.35);
      const x = tonight.x, y = tonight.y;
      const r = 2.5 * (0.55 + 0.45 * k) * (0.95 + 0.05 * tw);
      const glow = (dark ? 0.34 : 0.55) * Math.min(k, 1.2) * (0.8 + 0.2 * tw);
      const R = (dark ? 15 : 11) * (0.7 + 0.3 * k);
      const g = over.createRadialGradient(x, y, 0, x, y, R);
      const hc = dark ? '255, 196, 128' : '236, 142, 76';
      g.addColorStop(0, `rgba(${hc}, ${glow})`);
      g.addColorStop(0.35, `rgba(${hc}, ${glow * (dark ? 0.35 : 0.6)})`);
      g.addColorStop(1, `rgba(${hc}, 0)`);
      over.fillStyle = g;
      over.beginPath(); over.arc(x, y, R, 0, TAU); over.fill();
      if (bedtime != null && bedtime > 0.2 && bedtime < 7) {
        // the bloom itself: a wet ring opening in the wash
        const age = bedtime - 0.2;
        const rr = 8 + 34 * (1 - Math.exp(-age / 1.6));
        const ra = (dark ? 0.30 : 0.42) * Math.exp(-age / 1.9) * smoothstep(0, 0.4, age);
        const band = 5 + 0.22 * rr;
        const ring = over.createRadialGradient(x, y, Math.max(0, rr - band), x, y, rr + band * 0.55);
        ring.addColorStop(0, `rgba(${hc}, 0)`);
        ring.addColorStop(0.72, `rgba(${hc}, ${ra * 0.55})`);
        ring.addColorStop(0.86, `rgba(${hc}, ${ra * 0.2})`);
        ring.addColorStop(1, `rgba(${hc}, 0)`);
        over.fillStyle = ring;
        over.beginPath(); over.arc(x, y, rr + band, 0, TAU); over.fill();
      }
      const kk = clamp01(k);
      over.fillStyle = dark ? `rgba(255, 226, 178, ${0.7 * kk})` : `rgba(226, 128, 62, ${0.75 * kk})`;
      glint(over, x, y, 7.5 * k, 5.2 * k, 0.1, 0.55);
      over.fillStyle = dark ? `rgba(255, 226, 178, ${kk})` : `rgba(232, 136, 66, ${kk})`;
      over.beginPath();
      over.ellipse(x, y, r * 1.1, r * 0.94, 0.5, 0, TAU);
      over.fill();
      over.fillStyle = dark ? `rgba(255, 244, 222, ${kk * 0.9})` : `rgba(255, 244, 226, ${kk})`;
      over.beginPath(); over.arc(x - r * 0.12, y - r * 0.14, r * (dark ? 0.5 : 0.62), 0, TAU); over.fill();

      // …and its name, while the cards are back
      const veil = state.veil ?? 0;
      const said = bedtime == null ? 0 : veil * smoothstep(1.5, 2.6, bedtime) * (1 - smoothstep(5.2, 6.4, bedtime));
      if (said > 0.01) {
        const label = `night ${Math.floor(state.ageDays) + 1}`.toUpperCase();
        over.font = '700 9.5px Nunito, ui-rounded, system-ui, sans-serif';
        try { over.letterSpacing = '1.6px'; } catch { /* older canvas */ }
        over.textBaseline = 'middle';
        const left = G.duo;                               // on the Duo the sky to the star's left is open
        over.textAlign = left ? 'right' : 'center';
        over.fillStyle = dark ? `rgba(255, 232, 200, ${0.78 * said})` : `rgba(150, 86, 50, ${0.85 * said})`;
        over.fillText(label, left ? x - 15 : x, left ? y + 0.5 : y + 18);
        try { over.letterSpacing = '0px'; } catch { /* */ }
      }
    }
    return out > 0.003 || (tonight && ignite > 0.002);
  }

  function render(state) {
    if (destroyed || !state) return;
    lastState = state;
    const started = performance.now();
    const s = Number.isFinite(state.dpr) && state.dpr > 0 ? state.dpr : 1;
    const pxW = Math.round(state.width * s), pxH = Math.round(state.height * s);
    for (const c of [glCanvas, overCanvas]) {
      if (c.width !== pxW || c.height !== pxH) {
        c.width = pxW; c.height = pxH;
        c.style.width = `${state.width}px`; c.style.height = `${state.height}px`;
        washKey = '';
      }
    }
    const still = state.reduceMotion || !Number.isFinite(state.t);
    // Nothing in the wash moves faster than a few points a minute, so it is repainted every
    // fourth second at most (a step is under half a point); the stars above it move freely.
    const time = still ? 0 : Math.floor(state.t / 4) * 4;
    const C = compose(state);
    const key = JSON.stringify([state.device, state.scheme, +state.date, state.asleep, state.ageDays, time,
      state.event, state.tilt, s, state.latitude, state.longitude]);
    const washed = key !== washKey;
    if (washed) {
      drawWash(state, C, time);
      washKey = key;
      if (globalThis.__wetWashMeasure) gl.readPixels(0, 0, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array(4));   // block until it is drawn (timing only)
    }
    paintOver(state, C, still ? null : state.t);
    const ms = performance.now() - started;
    if (timing.first == null) timing.first = ms;
    else if (washed) { timing.wash = ms; timing.washes += 1; }
    else { timing.over = Math.max(timing.over * 0.9, ms); timing.frames += 1; }
    if (typeof window !== 'undefined') window.__wetWash = timing;
  }

  function destroy() {
    destroyed = true;
    glCanvas.remove();
    overCanvas.remove();
    const ext = gl.getExtension('WEBGL_lose_context');
    if (ext) ext.loseContext();
  }

  return { render, destroy, ready };
}
