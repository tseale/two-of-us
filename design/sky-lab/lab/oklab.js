// Colour in OKLab / OKLCH, for palettes that mix without going muddy and for the
// "hush": the rule today's sky was quietened by (SkyBackground.swift — each
// colour keeps its hue at a fifth of its chroma and sits 55 % of the way to the
// page's lightness), made continuous so a sky can open up and settle back.
//
// Colours are { r, g, b } in 0–1 sRGB, as in lab/palette.js.

const toLinear = (c) => (c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4));
const toGamma = (c) => (c <= 0.0031308 ? 12.92 * c : 1.055 * Math.pow(c, 1 / 2.4) - 0.055);
const clamp01 = (x) => Math.min(1, Math.max(0, x));

export function hex(value) {
  if (typeof value === 'string') value = parseInt(value.replace('#', ''), 16);
  return { r: ((value >> 16) & 255) / 255, g: ((value >> 8) & 255) / 255, b: (value & 255) / 255 };
}

export function toOklab({ r, g, b }) {
  const lr = toLinear(r), lg = toLinear(g), lb = toLinear(b);
  const l = Math.cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb);
  const m = Math.cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb);
  const s = Math.cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb);
  return {
    L: 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
    a: 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
    b: 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s,
  };
}

function oklabToLinear({ L, a, b }) {
  const l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3;
  const m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3;
  const s = (L - 0.0894841775 * a - 1.291485548 * b) ** 3;
  return [
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s,
  ];
}

/** Back to sRGB. Out-of-gamut colours give up chroma (never hue) until they fit. */
export function fromOklab(lab) {
  let lin = oklabToLinear(lab);
  const inGamut = (v) => v.every((c) => c >= -1e-4 && c <= 1 + 1e-4);
  if (!inGamut(lin)) {
    let lo = 0, hi = 1;
    for (let i = 0; i < 18; i++) {
      const k = (lo + hi) / 2;
      if (inGamut(oklabToLinear({ L: lab.L, a: lab.a * k, b: lab.b * k }))) lo = k; else hi = k;
    }
    lin = oklabToLinear({ L: lab.L, a: lab.a * lo, b: lab.b * lo });
  }
  return { r: clamp01(toGamma(clamp01(lin[0]))), g: clamp01(toGamma(clamp01(lin[1]))), b: clamp01(toGamma(clamp01(lin[2]))) };
}

export function toOklch(c) {
  const { L, a, b } = toOklab(c);
  return { L, C: Math.hypot(a, b), h: Math.atan2(b, a) };
}

export function fromOklch({ L, C, h }) {
  return fromOklab({ L, a: C * Math.cos(h), b: C * Math.sin(h) });
}

/** Perceptual mix: straight through OKLab, so blue → orange passes through
 *  rose and lilac, not grey-green. */
export function mixOk(c1, c2, t) {
  const k = clamp01(t);
  const A = toOklab(c1), B = toOklab(c2);
  return fromOklab({ L: A.L + (B.L - A.L) * k, a: A.a + (B.a - A.a) * k, b: A.b + (B.b - A.b) * k });
}

/** A colour at `stops` [[position, colour], …] (positions ascending), mixed in OKLab. */
export function rampOk(stops, x) {
  if (x <= stops[0][0]) return stops[0][1];
  for (let i = 0; i < stops.length - 1; i++) {
    const [x0, c0] = stops[i], [x1, c1] = stops[i + 1];
    if (x <= x1) return mixOk(c0, c1, x1 > x0 ? (x - x0) / (x1 - x0) : 0);
  }
  return stops[stops.length - 1][1];
}

/** Today's hush, exactly: `chroma` of the colour's own chroma, `toward` of the
 *  way to the page's lightness. (Night in today's sky is pulled less: 0.4.) */
export const HUSH = { chroma: 0.2, toward: 0.55 };
/** The dark appearance's: two fifths of the chroma, 12 % nearer black. */
export const DARK_HUSH = { chroma: 0.4, darken: 0.12 };

/** A full-strength colour as it shows at `presence` (0 = hushed as today,
 *  1 = itself), on a light `page`. */
export function present(c, presence, page = { r: 0xf2 / 255, g: 0xf2 / 255, b: 0xf7 / 255 }, hush = HUSH) {
  const p = clamp01(presence);
  const lch = toOklch(c);
  const pageL = toOklab(page).L;
  const toward = hush.toward * (1 - p);
  return fromOklch({ L: lch.L + (pageL - lch.L) * toward, C: lch.C * (hush.chroma + (1 - hush.chroma) * p), h: lch.h });
}

/** …and in the dark appearance, where hushed means dimmer and greyer, never lighter. */
export function presentDark(c, presence, hush = DARK_HUSH) {
  const p = clamp01(presence);
  const lch = toOklch(c);
  return fromOklch({ L: lch.L * (1 - hush.darken * (1 - p)), C: lch.C * (hush.chroma + (1 - hush.chroma) * p), h: lch.h });
}

export function css(c, alpha = 1) {
  const q = (v) => Math.round(clamp01(v) * 255);
  return `rgba(${q(c.r)}, ${q(c.g)}, ${q(c.b)}, ${alpha})`;
}

export const smoothstep = (a, b, x) => {
  const t = clamp01((x - a) / (b - a));
  return t * t * (3 - 2 * t);
};
export const lerp = (a, b, t) => a + (b - a) * t;
