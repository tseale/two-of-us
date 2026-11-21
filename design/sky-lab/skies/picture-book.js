// Picture book — a page from the book you will read him.
//
// A gouache-and-pencil picture-book illustration that happens to tell the real
// time: flat shapes with dry-brushed edges, a limited palette re-mixed by the
// hour, rounded hills overlapping like cut-outs, two or three clouds, a sun
// that is a soft disc with a painted halo, the moon in its true phase, a star
// for every night of his life, and one tree on a hill that carries the seasons.
//
// How it is made (and how it would ship): everything is a SHAPE — a path, or
// a mask cut once — filled with one flat colour; a pre-rendered TEXTURE
// (dry-brush speckle, paper tooth, paint mottle, mist); or a small SPRITE
// (clouds, stars, the tree's masks). The "dry brush" is the speckle texture
// stroked along a shape's edge in destination-out: the paint skips over the
// paper's tooth. Shapes never change; only their paint does. Nothing is shaded
// per pixel per frame: the still parts are composed into three planes (the sky
// with the sun and moon; the far hills with the tree; the near hills), which
// are repainted only when the palette or the light moves, and a frame is
// those three, the stars, the clouds, one band of mist and the small life.
//
//   palette    KEYS (by the sun's altitude, light and dark) → `resolve()`:
//              the painter's mix for this minute, quietened by presence()
//   geometry   DUO / SLAB: where the horizon, hills, tree, clouds and stars sit
//   textures   speckle (dry brush), paper, mottle, mist — built once
//   masks      sky bands · each hill's edge and its lit / shaded sides · the
//              tree by season · clouds by the light's direction — cut once
//   planes     back (sky, sun, moon) · far land + tree · near land
//   frame      back, stars, clouds, far land, moving mist, near land, small life
//
// World coordinates are points with x = 0 at the anchor window's leading edge
// (`state.phone.x`), y = the display's y. The Duo's cover and spread share one
// world exactly (the horizon is at the same y on both), so opening the Duo
// only ever widens the picture.

import { presence as bloomOf } from '../lab/presence.js';
import { toOklab, fromOklab, present, presentDark, css, smoothstep, lerp } from '../lab/oklab.js';
import { nights, twinkle, ignition, hash } from '../lab/nights.js';
import { season as seasonOf } from '../lab/season.js';
import { hash2, rng } from '../lab/noise.js';

export const meta = {
  id: 'picture-book',
  name: 'Picture book',
  blurb: 'A gouache picture-book page that tells the real time: cut-out hills, a painted sun and moon, his stars, and one tree that carries the seasons.',
};

const TAU = Math.PI * 2;
const DEG = Math.PI / 180;
const clamp01 = (x) => Math.min(1, Math.max(0, x));
const clamp = (x, lo, hi) => Math.min(hi, Math.max(lo, x));

// ─────────────────────────────────────────────────────────────── colour ──
// Everything is mixed in OKLab. K(L, C, hue°) is a tube colour; nothing is
// used straight from it.

const K = (L, C, h) => ({ L, a: C * Math.cos(h * DEG), b: C * Math.sin(h * DEG) });
const mixLab = (p, q, t) => ({ L: p.L + (q.L - p.L) * t, a: p.a + (q.a - p.a) * t, b: p.b + (q.b - p.b) * t });

function mixAny(a, b, t) {
  if (typeof a === 'number') return a + (b - a) * t;
  if (Array.isArray(a)) return a.map((v, i) => mixAny(v, b[i], t));
  if (a && typeof a === 'object' && 'L' in a) return mixLab(a, b, t);
  const out = {};
  for (const k of Object.keys(a)) out[k] = mixAny(a[k], b[k], t);
  return out;
}

/** Where the sky's five colours sit, zenith (0) to horizon (1). */
const SKY_AT = [0, 0.3, 0.58, 0.82, 1];

function rampLab(stops, f) {
  if (f <= SKY_AT[0]) return stops[0];
  for (let i = 0; i < SKY_AT.length - 1; i += 1) {
    if (f <= SKY_AT[i + 1]) return mixLab(stops[i], stops[i + 1], (f - SKY_AT[i]) / (SKY_AT[i + 1] - SKY_AT[i]));
  }
  return stops[stops.length - 1];
}

const PAGE = { r: 0xf2 / 255, g: 0xf2 / 255, b: 0xf7 / 255 };
/** The hush, shaped for this picture: its full-strength light palette is already
 *  pastel, so it is pulled less far toward the page than today's deep one. */
const LIGHT_HUSH = { chroma: 0.24, toward: 0.5 };
const DARK_HUSH = { chroma: 0.5, darken: 0.12 };

// The painter's keys, by the sun's altitude (degrees). Each is the palette at
// FULL strength; presence() quietens it. `sky` runs zenith → horizon on the
// sun's side, `anti` the same away from it (the Belt of Venus over the earth's
// shadow at twilight). Land: a value for the farthest and nearest hill, how
// much of the season's local colour survives the light (`keep`), the ambient
// it is mixed into (`amb`, `ambAmt`), how far snow or straw lifts it
// (`localGain`), the haze far hills dissolve into, the light's own colour on
// the lit shoulders (`key`, `litGain`). `ink` is the tree.
const KEYS = {
  light: [
    {
      alt: -18,
      sky: [K(0.848, 0.05, 268), K(0.846, 0.05, 270), K(0.824, 0.054, 274), K(0.8, 0.056, 278), K(0.806, 0.052, 288)],
      anti: [K(0.848, 0.05, 267), K(0.846, 0.05, 268), K(0.824, 0.054, 270), K(0.802, 0.056, 272), K(0.8, 0.052, 276)],
      glow: K(0.88, 0.05, 320), glowAmt: 0,
      sun: K(0.97, 0.06, 80), halo: K(0.93, 0.08, 60), haloAmt: 0,
      cloud: [K(0.87, 0.035, 280), K(0.85, 0.04, 275), K(0.82, 0.045, 272)],
      landFar: K(0.8, 0.046, 272), landNear: K(0.752, 0.05, 278), keep: 0.3, localGain: 0.5,
      haze: K(0.85, 0.04, 285), aerial: 0.6, key: K(0.93, 0.02, 250), litGain: 0.035,
      ink: K(0.54, 0.05, 280), mist: K(0.86, 0.035, 280), mistAmt: 0.5,
    },
    {
      alt: -10,
      sky: [K(0.846, 0.05, 270), K(0.844, 0.05, 275), K(0.832, 0.054, 285), K(0.824, 0.058, 310), K(0.846, 0.06, 350)],
      anti: [K(0.846, 0.05, 268), K(0.842, 0.05, 270), K(0.828, 0.052, 272), K(0.812, 0.054, 276), K(0.806, 0.048, 270)],
      glow: K(0.89, 0.07, 10), glowAmt: 0.3,
      sun: K(0.97, 0.06, 80), halo: K(0.93, 0.08, 60), haloAmt: 0,
      cloud: [K(0.87, 0.05, 330), K(0.845, 0.045, 290), K(0.815, 0.048, 275)],
      landFar: K(0.806, 0.048, 285), landNear: K(0.758, 0.052, 285), keep: 0.35, localGain: 0.5,
      haze: K(0.85, 0.045, 300), aerial: 0.6, key: K(0.9, 0.05, 350), litGain: 0.03,
      ink: K(0.53, 0.052, 285), mist: K(0.87, 0.038, 300), mistAmt: 0.5,
    },
    {
      alt: -5,
      sky: [K(0.856, 0.05, 272), K(0.86, 0.052, 285), K(0.868, 0.06, 320), K(0.882, 0.075, 15), K(0.905, 0.082, 55)],
      anti: [K(0.853, 0.05, 268), K(0.856, 0.048, 272), K(0.86, 0.05, 285), K(0.868, 0.056, 335), K(0.842, 0.044, 280)],
      glow: K(0.915, 0.1, 45), glowAmt: 0.6,
      sun: K(0.915, 0.125, 62), halo: K(0.97, 0.05, 80), haloAmt: 0.1,
      cloud: [K(0.89, 0.085, 20), K(0.845, 0.055, 305), K(0.805, 0.052, 280)],
      landFar: K(0.848, 0.052, 312), landNear: K(0.792, 0.055, 300), keep: 0.5, localGain: 0.5,
      haze: K(0.86, 0.055, 330), aerial: 0.62, key: K(0.9, 0.08, 20), litGain: 0.035,
      ink: K(0.53, 0.055, 300), mist: K(0.89, 0.04, 340), mistAmt: 0.5,
    },
    {
      alt: -1,
      sky: [K(0.864, 0.05, 275), K(0.87, 0.052, 300), K(0.88, 0.07, 350), K(0.9, 0.086, 45), K(0.93, 0.09, 75)],
      anti: [K(0.86, 0.05, 268), K(0.864, 0.048, 275), K(0.87, 0.05, 295), K(0.88, 0.06, 350), K(0.854, 0.04, 282)],
      glow: K(0.945, 0.11, 70), glowAmt: 0.85,
      sun: K(0.918, 0.13, 70), halo: K(0.975, 0.05, 88), haloAmt: 0.8,
      cloud: [K(0.935, 0.095, 50), K(0.87, 0.06, 335), K(0.82, 0.052, 292)],
      landFar: K(0.862, 0.052, 328), landNear: K(0.8, 0.055, 12), keep: 0.7, localGain: 0.5,
      haze: K(0.885, 0.065, 20), aerial: 0.65, key: K(0.92, 0.1, 55), litGain: 0.06,
      ink: K(0.47, 0.06, 330), mist: K(0.92, 0.05, 40), mistAmt: 0.55,
    },
    {
      alt: 3,
      sky: [K(0.864, 0.052, 268), K(0.87, 0.052, 290), K(0.882, 0.06, 345), K(0.908, 0.076, 55), K(0.946, 0.08, 86)],
      anti: [K(0.86, 0.052, 262), K(0.864, 0.048, 268), K(0.872, 0.045, 285), K(0.886, 0.046, 340), K(0.876, 0.034, 285)],
      glow: K(0.957, 0.1, 82), glowAmt: 0.75,
      sun: K(0.93, 0.125, 80), halo: K(0.98, 0.045, 94), haloAmt: 0.85,
      cloud: [K(0.962, 0.07, 72), K(0.9, 0.05, 340), K(0.84, 0.05, 295)],
      landFar: K(0.868, 0.05, 322), landNear: K(0.806, 0.055, 35), keep: 0.82, localGain: 0.5,
      haze: K(0.9, 0.06, 40), aerial: 0.65, key: K(0.94, 0.1, 68), litGain: 0.07,
      ink: K(0.48, 0.055, 345), mist: K(0.935, 0.045, 60), mistAmt: 0.55,
    },
    {
      alt: 9,
      sky: [K(0.83, 0.065, 255), K(0.846, 0.058, 255), K(0.878, 0.045, 275), K(0.91, 0.04, 40), K(0.94, 0.05, 82)],
      anti: [K(0.826, 0.065, 252), K(0.842, 0.058, 250), K(0.868, 0.045, 248), K(0.896, 0.032, 240), K(0.91, 0.026, 236)],
      glow: K(0.965, 0.07, 88), glowAmt: 0.5,
      sun: K(0.962, 0.095, 90), halo: K(0.985, 0.035, 96), haloAmt: 0.7,
      cloud: [K(0.978, 0.03, 88), K(0.94, 0.02, 300), K(0.88, 0.036, 280)],
      landFar: K(0.876, 0.035, 262), landNear: K(0.812, 0.05, 80), keep: 0.95, localGain: 0.5,
      haze: K(0.91, 0.03, 250), aerial: 0.6, key: K(0.97, 0.06, 90), litGain: 0.06,
      ink: K(0.5, 0.045, 30), mist: K(0.95, 0.02, 250), mistAmt: 0.45,
    },
    {
      alt: 25,
      sky: [K(0.8, 0.075, 250), K(0.83, 0.065, 246), K(0.866, 0.05, 240), K(0.9, 0.035, 230), K(0.926, 0.026, 215)],
      anti: [K(0.8, 0.075, 250), K(0.83, 0.065, 246), K(0.866, 0.05, 240), K(0.9, 0.035, 230), K(0.926, 0.026, 215)],
      glow: K(0.975, 0.03, 96), glowAmt: 0.35,
      sun: K(0.972, 0.075, 94), halo: K(0.988, 0.025, 98), haloAmt: 0.4,
      cloud: [K(0.988, 0.008, 90), K(0.956, 0.012, 255), K(0.9, 0.028, 260)],
      landFar: K(0.888, 0.028, 240), landNear: K(0.818, 0.05, 90), keep: 1, localGain: 0.5,
      haze: K(0.92, 0.026, 225), aerial: 0.58, key: K(0.98, 0.03, 96), litGain: 0.05,
      ink: K(0.52, 0.04, 50), mist: K(0.96, 0.015, 230), mistAmt: 0.4,
    },
  ],
  dark: [
    {
      alt: -18,
      sky: [K(0.158, 0.07, 270), K(0.168, 0.072, 273), K(0.18, 0.074, 277), K(0.196, 0.072, 282), K(0.21, 0.066, 290)],
      anti: [K(0.158, 0.07, 269), K(0.167, 0.072, 270), K(0.178, 0.073, 272), K(0.192, 0.071, 275), K(0.204, 0.066, 279)],
      glow: K(0.3, 0.07, 320), glowAmt: 0,
      sun: K(0.86, 0.11, 75), halo: K(0.66, 0.14, 55), haloAmt: 0,
      cloud: [K(0.24, 0.05, 280), K(0.215, 0.055, 276), K(0.18, 0.06, 272)],
      landFar: K(0.178, 0.066, 278), landNear: K(0.095, 0.05, 284), keep: 0.2, localGain: 0.25,
      haze: K(0.22, 0.066, 288), aerial: 0.55, key: K(0.36, 0.04, 258), litGain: 0.05,
      ink: K(0.075, 0.03, 285), mist: K(0.25, 0.06, 280), mistAmt: 0.62,
    },
    {
      alt: -10,
      sky: [K(0.162, 0.066, 272), K(0.173, 0.07, 276), K(0.19, 0.076, 285), K(0.218, 0.082, 306), K(0.25, 0.088, 336)],
      anti: [K(0.16, 0.064, 270), K(0.17, 0.066, 271), K(0.181, 0.066, 272), K(0.194, 0.064, 276), K(0.196, 0.06, 272)],
      glow: K(0.36, 0.1, 350), glowAmt: 0.35,
      sun: K(0.86, 0.11, 75), halo: K(0.66, 0.14, 55), haloAmt: 0,
      cloud: [K(0.3, 0.08, 340), K(0.22, 0.06, 295), K(0.185, 0.06, 278)],
      landFar: K(0.19, 0.07, 290), landNear: K(0.1, 0.05, 288), keep: 0.25, localGain: 0.3,
      haze: K(0.25, 0.075, 310), aerial: 0.58, key: K(0.3, 0.08, 340), litGain: 0.03,
      ink: K(0.08, 0.032, 290), mist: K(0.27, 0.07, 310), mistAmt: 0.5,
    },
    {
      alt: -5,
      sky: [K(0.18, 0.06, 275), K(0.2, 0.07, 286), K(0.245, 0.086, 316), K(0.325, 0.106, 0), K(0.425, 0.12, 36)],
      anti: [K(0.176, 0.056, 270), K(0.187, 0.06, 274), K(0.207, 0.06, 282), K(0.238, 0.062, 322), K(0.212, 0.052, 282)],
      glow: K(0.5, 0.13, 30), glowAmt: 0.7,
      sun: K(0.86, 0.11, 75), halo: K(0.64, 0.14, 50), haloAmt: 0.1,
      cloud: [K(0.4, 0.105, 12), K(0.255, 0.07, 312), K(0.2, 0.06, 286)],
      landFar: K(0.245, 0.08, 318), landNear: K(0.115, 0.05, 295), keep: 0.35, localGain: 0.4,
      haze: K(0.31, 0.09, 345), aerial: 0.62, key: K(0.36, 0.1, 20), litGain: 0.06,
      ink: K(0.09, 0.036, 305), mist: K(0.33, 0.085, 350), mistAmt: 0.5,
    },
    {
      alt: -1,
      sky: [K(0.2, 0.06, 278), K(0.232, 0.075, 300), K(0.292, 0.095, 345), K(0.405, 0.12, 22), K(0.555, 0.135, 56)],
      anti: [K(0.196, 0.056, 270), K(0.212, 0.06, 276), K(0.242, 0.066, 292), K(0.288, 0.07, 340), K(0.242, 0.052, 284)],
      glow: K(0.64, 0.15, 52), glowAmt: 0.9,
      sun: K(0.87, 0.125, 74), halo: K(0.75, 0.135, 64), haloAmt: 0.8,
      cloud: [K(0.4, 0.105, 18), K(0.3, 0.08, 336), K(0.25, 0.066, 305)],
      landFar: K(0.31, 0.088, 338), landNear: K(0.125, 0.055, 300), keep: 0.5, localGain: 0.5,
      haze: K(0.38, 0.105, 10), aerial: 0.66, key: K(0.48, 0.13, 38), litGain: 0.12,
      ink: K(0.1, 0.04, 322), mist: K(0.42, 0.1, 20), mistAmt: 0.5,
    },
    {
      alt: 3,
      sky: [K(0.236, 0.066, 275), K(0.262, 0.076, 295), K(0.322, 0.09, 340), K(0.435, 0.116, 30), K(0.585, 0.13, 66)],
      anti: [K(0.23, 0.06, 268), K(0.25, 0.06, 272), K(0.282, 0.06, 285), K(0.322, 0.066, 336), K(0.29, 0.05, 286)],
      glow: K(0.68, 0.14, 62), glowAmt: 0.8,
      sun: K(0.9, 0.11, 84), halo: K(0.79, 0.125, 74), haloAmt: 0.85,
      cloud: [K(0.41, 0.1, 30), K(0.32, 0.07, 332), K(0.27, 0.064, 302)],
      landFar: K(0.33, 0.085, 345), landNear: K(0.14, 0.055, 310), keep: 0.6, localGain: 0.5,
      haze: K(0.41, 0.1, 25), aerial: 0.66, key: K(0.52, 0.12, 46), litGain: 0.12,
      ink: K(0.11, 0.04, 335), mist: K(0.46, 0.09, 35), mistAmt: 0.5,
    },
    {
      alt: 9,
      sky: [K(0.3, 0.07, 265), K(0.32, 0.07, 268), K(0.36, 0.06, 285), K(0.42, 0.07, 20), K(0.5, 0.09, 62)],
      anti: [K(0.3, 0.07, 262), K(0.318, 0.066, 262), K(0.35, 0.056, 260), K(0.38, 0.046, 256), K(0.39, 0.04, 250)],
      glow: K(0.6, 0.11, 66), glowAmt: 0.5,
      sun: K(0.76, 0.1, 86), halo: K(0.64, 0.1, 76), haloAmt: 0.6,
      cloud: [K(0.52, 0.07, 62), K(0.38, 0.05, 300), K(0.31, 0.056, 276)],
      landFar: K(0.34, 0.05, 285), landNear: K(0.17, 0.04, 300), keep: 0.75, localGain: 0.5,
      haze: K(0.4, 0.05, 300), aerial: 0.62, key: K(0.5, 0.08, 66), litGain: 0.08,
      ink: K(0.13, 0.035, 320), mist: K(0.44, 0.04, 290), mistAmt: 0.45,
    },
    {
      alt: 25,
      sky: [K(0.33, 0.07, 262), K(0.35, 0.066, 260), K(0.38, 0.056, 256), K(0.41, 0.046, 250), K(0.43, 0.04, 245)],
      anti: [K(0.33, 0.07, 262), K(0.35, 0.066, 260), K(0.38, 0.056, 256), K(0.41, 0.046, 250), K(0.43, 0.04, 245)],
      glow: K(0.5, 0.04, 90), glowAmt: 0.3,
      sun: K(0.47, 0.05, 86), halo: K(0.44, 0.04, 90), haloAmt: 0.22,
      cloud: [K(0.47, 0.03, 250), K(0.41, 0.04, 262), K(0.35, 0.05, 268)],
      landFar: K(0.37, 0.04, 250), landNear: K(0.2, 0.035, 275), keep: 0.85, localGain: 0.5,
      haze: K(0.42, 0.04, 248), aerial: 0.6, key: K(0.46, 0.035, 90), litGain: 0.05,
      ink: K(0.15, 0.03, 300), mist: K(0.45, 0.03, 245), mistAmt: 0.4,
    },
  ],
};

function keyAt(keys, alt) {
  if (alt <= keys[0].alt) return keys[0];
  for (let i = 0; i < keys.length - 1; i += 1) {
    if (alt <= keys[i + 1].alt) return mixAny(keys[i], keys[i + 1], (alt - keys[i].alt) / (keys[i + 1].alt - keys[i].alt));
  }
  return keys[keys.length - 1];
}

// ───────────────────────────────────────────────────────────── geometry ──
// Points. Hills: `base` below the horizon, then rounded bumps [x, height, width].

// Clouds: a few soft blobs [x, y, rx, ry, weight] that melt into one shape, cut flat below.
const CLOUD_LONG = [[-4, 3, 44, 11, 1], [-28, -5, 18, 12, 0.95], [20, -10, 21, 15, 1.05], [-6, -13, 14, 10, 0.85], [52, 6, 20, 6, 0.7], [-54, 7, 16, 5, 0.6]];
const CLOUD_SMALL = [[0, 2, 25, 9, 1], [-9, -7, 13, 11, 1], [11, -3, 12, 9, 0.85], [-26, 4, 11, 5, 0.6], [28, 5, 10, 4.5, 0.6]];
const CLOUD_MID = [[0, 2, 31, 10, 1], [12, -9, 15, 12, 1], [-14, -5, 15, 10, 0.9], [37, 4, 12, 5.5, 0.65], [-38, 5, 12, 5, 0.6]];

const DUO = {
  lead: 485,                        // how far the world runs on to the left of the anchor window
  horizon: 292, sunTop: 14, sunR: 14, moonR: 10.5, moonMid: 98, moonTop: 12.5,
  tree: { x: 399, h: 88, hill: 2 },
  tonight: { x: 441, y: 211 },
  // x0, x1, how densely his stars fall there, and the share of them in the top band
  starCols: [[0, 20, 1.25, 0.34], [20, 362, 0.9, 0.46], [362, 466, 1.45, 0.33]],
  topBand: 89, starTop: 5, starScale: 1,
  text: [88, 29, 220, 85],          // his name and age (anchor points): nothing bright goes behind them
  hills: [
    { base: 4, depth: 0, bumps: [[-300, 26, 260], [330, 16, 200]] },
    { base: 30, depth: 0.22, bumps: [[-120, 46, 170], [560, 30, 160]] },
    { base: 58, depth: 0.45, bumps: [[399, 56, 86, 2.6], [-440, 52, 140, 2.4]] },
    { base: 128, depth: 0.66, bumps: [[150, 62, 230, 2.3], [-330, 30, 200]] },
    { base: 244, depth: 0.84, bumps: [[-250, 58, 280, 2.3], [470, 40, 180]] },
    { base: 352, depth: 1, bumps: [[200, 46, 300, 2.3]] },
  ],
  clouds: [
    { x: 260, y: 47, speed: 0.1, scale: 0.94, base: 12, blobs: CLOUD_LONG },
    { x: -8, y: 166, speed: 0.14, scale: 0.92, base: 10, blobs: CLOUD_SMALL },
    { x: -438, y: 150, speed: 0.08, scale: 1, base: 11, blobs: CLOUD_MID },
  ],
  caption: { x: 30, y: 632, size: 16 },
};

const SLAB = {
  lead: 0,
  horizon: 140, sunTop: 59, sunR: 9.5, moonR: 8.5, moonMid: 104, moonTop: 59,
  tree: { x: 286, h: 62, hill: 2 },
  tonight: { x: 318, y: 74 },
  starCols: [[0, 402, 1, 1]],
  topBand: 132, starTop: 4, starScale: 0.82,
  text: [86, 76, 214, 131],
  // On the slab his name sits right on the horizon, where a twilight is brightest. A long
  // bank of cloud lies along the horizon on that side, so the bright band is never under the words.
  bank: { x0: -12, x1: 274, top: 92, foot: 150 },
  hills: [
    { base: 4, depth: 0, bumps: [[262, 20, 80], [430, 26, 90], [40, 6, 90]] },
    { base: 9, depth: 0.2, bumps: [[380, 14, 70], [200, 6, 80]] },
    { base: 12, depth: 0.42, bumps: [[286, 25, 66, 2.6]] },
    { base: 96, depth: 0.6, bumps: [[90, 40, 180, 2.3], [400, 30, 150]] },
    { base: 300, depth: 0.76, bumps: [[300, 46, 210, 2.3], [-40, 30, 160]] },
    { base: 500, depth: 0.9, bumps: [[80, 44, 230, 2.3], [420, 30, 160]] },
    { base: 676, depth: 1, bumps: [[280, 40, 230, 2.3]] },
  ],
  clouds: [
    { x: 224, y: 72, speed: 0.1, scale: 0.7, base: 11, blobs: CLOUD_MID },
    { x: 96, y: 58, speed: 0.13, scale: 0.6, base: 10, blobs: CLOUD_SMALL },
  ],
  caption: { x: 34, y: 452, size: 25 },     // the tall land under the picture is the page's text side
};

const PAD = 14;   // points of overscan on each side of the hill layers, for parallax

// ──────────────────────────────────────────────────────────────── noise ──

const LATTICE = 256;
const lattice = new Float32Array(LATTICE * LATTICE);
for (let y = 0; y < LATTICE; y += 1) for (let x = 0; x < LATTICE; x += 1) lattice[y * LATTICE + x] = hash2(x, y, 11);

/** Smooth value noise, 0–1, wrapping every `px`, `py` lattice cells (≤ 256). */
function vn(x, y, px = LATTICE, py = LATTICE) {
  let xi = Math.floor(x), yi = Math.floor(y);
  const fx = x - xi, fy = y - yi;
  xi = ((xi % px) + px) % px; yi = ((yi % py) + py) % py;
  const x1 = (xi + 1) % px, y1 = (yi + 1) % py;
  const u = fx * fx * (3 - 2 * fx), v = fy * fy * (3 - 2 * fy);
  const a = lattice[yi * LATTICE + xi], b = lattice[yi * LATTICE + x1];
  const c = lattice[y1 * LATTICE + xi], d = lattice[y1 * LATTICE + x1];
  return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
}

function fb(x, y, octaves = 3, px = LATTICE, py = LATTICE) {
  let sum = 0, amp = 0.5, norm = 0;
  for (let o = 0; o < octaves; o += 1) {
    sum += amp * vn(x + o * 17.3, y + o * 9.1, px, py);
    norm += amp;
    x *= 2; y *= 2; px = Math.min(LATTICE, px * 2); py = Math.min(LATTICE, py * 2);
    amp *= 0.5;
  }
  return sum / norm;
}

// ────────────────────────────────────────────────────────────── module ──

export function create(host) {
  const doc = host.ownerDocument ?? document;
  const mk = (w, h) => {
    const c = doc.createElement('canvas');
    c.width = Math.max(1, Math.ceil(w));
    c.height = Math.max(1, Math.ceil(h));
    return c;
  };
  const canvas = mk(1, 1);
  canvas.setAttribute('aria-hidden', 'true');
  canvas.style.cssText = 'position:absolute;left:0;top:0;display:block;pointer-events:none;';
  host.appendChild(canvas);
  const main = canvas.getContext('2d');

  let destroyed = false;
  let G = null;            // geometry + layers for the current display
  let T = null;            // textures at the current dpr
  let keys = {};           // what each cached layer was painted for

  // ── textures (once per dpr) ──────────────────────────────────────────

  function imageCanvas(w, h, fill) {
    const c = mk(w, h);
    const ctx = c.getContext('2d');
    const img = ctx.createImageData(w, h);
    fill(img.data, w, h);
    ctx.putImageData(img, 0, 0);
    return c;
  }

  function buildTextures(s) {
    // Dry brush: where the paint skipped. Streaks along x (the way the brush
    // was dragged), broken by the paper's tooth. Two densities.
    const S = 384;
    const speck = (lo, hi, ox, oy) => imageCanvas(S, S, (d) => {
      for (let y = 0; y < S; y += 1) {
        for (let x = 0; x < S; x += 1) {
          const X = x + ox, Y = y + oy;
          const wx = (vn(X / 24, Y / 24, 16, 16) - 0.5) * 22, wy = (vn(X / 16 + 5.5, Y / 16 + 2.5, 24, 24) - 0.5) * 9;
          const streak = fb((X + wx) / 32, (Y + wy) / 6, 3, 12, 64);
          const tooth = vn((X + wy) / 2.6, (Y + wx * 0.3) / 2.6, 128, 128) * 0.6 + hash2(x, y, 5) * 0.4;
          const v = 0.66 * streak + 0.34 * tooth;
          const i = (y * S + x) * 4;
          d[i] = 255; d[i + 1] = 255; d[i + 2] = 255;
          d[i + 3] = Math.round(255 * smoothstep(lo, hi, v));
        }
      }
    });
    const sparse = speck(0.555, 0.63, 0, 0);
    const dense = speck(0.47, 0.56, 131, 57);

    // Paper tooth: fine grain around mid grey, for soft-light.
    const P = 512;
    const paper = imageCanvas(P, P, (d) => {
      for (let y = 0; y < P; y += 1) {
        for (let x = 0; x < P; x += 1) {
          const white = (hash2(x, y, 3) + hash2(x + 1, y, 3) + hash2(x, y + 1, 3)) / 3;
          const fibre = vn(x / 9, y / 1.6, 56, 256) * 0.5 + vn(x / 1.9, y / 7, 256, 73) * 0.5;
          const tooth = vn(x / 2.2, y / 2.2, 232, 232);
          const v = 0.5 + (white - 0.5) * 0.5 + (tooth - 0.5) * 0.3 + (fibre - 0.5) * 0.14;
          const g = Math.round(255 * clamp01(v));
          const i = (y * P + x) * 4;
          d[i] = g; d[i + 1] = g; d[i + 2] = g; d[i + 3] = 255;
        }
      }
    });

    // Valley mist: a soft band, wrapping in x.
    const MW = 1024, MH = Math.ceil(60 * s);
    const mist = imageCanvas(MW, MH, (d) => {
      for (let y = 0; y < MH; y += 1) {
        const f = y / (MH - 1);
        const bell = smoothstep(0, 0.55, f) * (1 - smoothstep(0.75, 1, f));
        for (let x = 0; x < MW; x += 1) {
          const n = fb(x / 128, y / 44 + 3.7, 3, 8, 256);
          const top = smoothstep(0.25, 0.7, n + f * 0.55 - 0.2);
          const i = (y * MW + x) * 4;
          d[i] = 255; d[i + 1] = 255; d[i + 2] = 255;
          d[i + 3] = Math.round(255 * bell * top);
        }
      }
    });

    return { s, sparse, dense, paper, mist,
      sparsePattern: main.createPattern(sparse, 'repeat'),
      densePattern: main.createPattern(dense, 'repeat'),
      paperPattern: main.createPattern(paper, 'repeat') };
  }

  /** The dry-brush edge: the speckle stroked along `path` in destination-out —
   *  a wide sparse pass, then narrower denser ones. Widths in device px. */
  function dryEdge(ctx, path, passes, ox = 0, oy = 0) {
    ctx.save();
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.globalCompositeOperation = 'destination-out';
    ctx.lineJoin = 'round';
    ctx.lineCap = 'round';
    for (const [width, alpha, kind] of passes) {
      const pattern = kind === 'dense' ? T.densePattern : T.sparsePattern;
      pattern.setTransform(new DOMMatrix().translate(ox, oy));
      ctx.strokeStyle = pattern;
      ctx.globalAlpha = alpha;
      ctx.lineWidth = width;
      ctx.stroke(path);
    }
    ctx.restore();
  }

  let scratchA = null, scratchB = null;
  function scratch(which, w, h) {
    let c = which === 'a' ? scratchA : scratchB;
    if (!c || c.width < w || c.height < h) {
      c = mk(Math.max(w, c ? c.width : 0), Math.max(h, c ? c.height : 0));
      if (which === 'a') scratchA = c; else scratchB = c;
    }
    const ctx = c.getContext('2d');
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.globalCompositeOperation = 'source-over';
    ctx.globalAlpha = 1;
    ctx.filter = 'none';
    ctx.clearRect(0, 0, w, h);          // callers use (and copy out) only this corner
    return ctx;
  }

  /** A white alpha mask, tinted: → the scratch canvas holding it (use at once). */
  function tinted(mask, colour) {
    const ctx = scratch('b', mask.width, mask.height);
    ctx.drawImage(mask, 0, 0);
    ctx.globalCompositeOperation = 'source-in';
    ctx.fillStyle = colour;
    ctx.fillRect(0, 0, mask.width, mask.height);
    return ctx.canvas;
  }

  // ── geometry (once per display) ──────────────────────────────────────

  function crestAt(cfg, layer, index, x) {
    let y = cfg.horizon + layer.base;
    for (const [bx, bh, bw, power = 2] of layer.bumps) {
      const d = Math.abs(x - bx) / bw;
      y -= bh * Math.exp(-Math.pow(d, power));
    }
    // the hand's wobble
    y += (fb(x / 90 + index * 13.7, index * 3.1 + 0.5, 2) - 0.5) * 3.2 + (vn(x / 13 + index * 5.3, 7.7) - 0.5) * 0.7;
    return y;
  }

  function buildGeometry(state) {
    const s = state.dpr;
    const cfg = state.strip ? DUO : SLAB;
    const ox = state.phone.x;
    const Wa = state.phone.width;
    const pxW = Math.ceil(state.width * s - 1e-6), pxH = Math.ceil(state.height * s - 1e-6);
    const padPx = Math.round(PAD * s);
    const layerW = pxW + 2 * padPx;
    const g = { cfg, s, ox, Wa, pxW, pxH, padPx, layerW, width: state.width, height: state.height };

    // Hills: the crest per device-pixel column of the padded layer, and the
    // strip of rows its edge (and its lit and shaded sides) can occupy — below
    // the strip a hill is one flat fill.
    g.hills = cfg.hills.map((layer, index) => {
      const crest = new Float32Array(layerW);
      let top = Infinity, low = -Infinity, sum = 0;
      for (let j = 0; j < layerW; j += 1) {
        const xw = (j - padPx) / s - ox;
        const y = crestAt(cfg, layer, index, xw) * s;
        crest[j] = y; sum += y;
        if (y < top) top = y;
        if (y > low) low = y;
      }
      const reach = (16 + 30 * layer.depth) * s;
      const y0 = Math.max(0, Math.floor(top - 8 * s));
      const stripH = Math.max(8, Math.min(pxH + padPx, Math.ceil(low + reach * 0.75 + 10 * s)) - y0);
      const body = new Path2D();                       // layer pixels: x from the padded edge, y absolute
      body.moveTo(-4, crest[0]);
      for (let j = 0; j < layerW; j += 2) body.lineTo(j, crest[j]);
      body.lineTo(layerW + 4, crest[layerW - 1]);
      body.lineTo(layerW + 4, pxH + padPx + 4); body.lineTo(-4, pxH + padPx + 4); body.closePath();
      return { ...layer, index, crest, y0, stripH, reach, mean: sum / layerW, body, edgeMask: null, sides: { key: '', lit: null, shade: null } };
    });
    g.crestPt = (index, xw) => crestAt(cfg, cfg.hills[index], index, xw);
    g.skyBottom = (xw) => {
      let y = Infinity;
      for (let i = 0; i < cfg.hills.length; i += 1) y = Math.min(y, crestAt(cfg, cfg.hills[i], i, xw));
      return y;
    };

    // The tree stands on its hill.
    const tr = cfg.tree;
    g.tree = { x: tr.x, baseY: g.crestPt(tr.hill, tr.x) + 1.5, h: tr.h, masksKey: '', canvas: null };

    // Two planes of land: the far hills with the tree's hill and the tree, and the near hills.
    g.fronts = [g.hills.slice(0, tr.hill + 1), g.hills.slice(tr.hill + 1)].map((hills, i) => {
      let y0 = Math.min(...hills.map((h) => h.y0));
      if (i === 0) y0 = Math.max(0, Math.min(y0, Math.floor((g.tree.baseY - tr.h * 1.12) * s)));     // room for the tree
      const layer = mk(layerW, pxH + padPx - y0);
      return { hills, y0, canvas: layer, ctx: layer.getContext('2d'), depth: hills.reduce((a, h) => a + h.depth, 0) / hills.length };
    });

    // His stars: the places never move (for a display).
    /** The lowest a star may sit at x: clear of the hills and of the tree's crown. */
    g.starFloor = (x) => {
      let bottom = g.skyBottom(x) - 9;
      const dx = x - tr.x, rx = tr.h * 0.42;
      if (Math.abs(dx) < rx) {
        const crownTop = g.tree.baseY - tr.h * 0.6 - tr.h * 0.46 * Math.sqrt(1 - (dx * dx) / (rx * rx));
        bottom = Math.min(bottom, crownTop - 4);
      }
      return bottom;
    };
    g.starPlace = (star) => {
      const { u, v } = star;
      // across: the columns by weight
      let total = 0;
      for (const [x0, x1, w] of cfg.starCols) total += (x1 - x0) * w;
      let acc = 0, x = 0, share = 0.5;
      for (const [x0, x1, w, sh] of cfg.starCols) {
        const part = ((x1 - x0) * w) / total;
        if (u <= acc + part || x1 === cfg.starCols[cfg.starCols.length - 1][1]) {
          x = x0 + ((u - acc) / part) * (x1 - x0);
          share = sh;
          if (u <= acc + part) break;
        }
        acc += part;
      }
      x = clamp(x, 2, Wa - 2);
      const bottom = g.starFloor(x);
      const top = cfg.starTop;
      const band = Math.min(cfg.topBand, bottom);
      let y;
      if (share >= 1 || v < share) y = top + (share >= 1 ? v : v / share) * (band - top);
      else y = band + ((v - share) / (1 - share)) * (bottom - band);
      // never behind his name: such a star goes to the lane above it, or below the band
      const [tx0, ty0, tx1, ty1] = cfg.text;
      if (x > tx0 - 2 && x < tx1 + 2 && y > ty0 - 4 && y < ty1 + 2) {
        if (cfg === DUO) {
          y = hash(star.night, 21) < 0.42
            ? top + hash(star.night, 22) * (ty0 - 7 - top)
            : ty1 + 6 + hash(star.night, 22) * (bottom - ty1 - 6);
        } else {
          x = tx1 + 5 + hash(star.night, 22) * (Wa - tx1 - 64);
          y = top + v * (g.starFloor(x) - top);
        }
      }
      return { x, y };
    };

    // The ordinary, fainter sky of the leading page (not his stars).
    g.farStars = [];
    if (ox > 0) {
      const count = Math.round(ox / 4.2);
      for (let n = 0; n < count; n += 1) {
        const x = -ox + hash(n, 41) * (ox - 6);
        const bottom = g.skyBottom(x) - 8;
        const y = 4 + Math.pow(hash(n, 42), 0.9) * (bottom - 4);
        const titled = x + ox > 90 && x + ox < 350 && y > 18 && y < 90;     // where the leading page's title sits
        g.farStars.push({ x, y, titled, r: 0.5 + 0.55 * hash(n, 43), a: 0.3 + 0.45 * hash(n, 44), phase: hash(n, 45), period: 3 + 4 * hash(n, 46) });
      }
    }

    // Layers.
    g.sky = mk(pxW, pxH);                // the sky as painted
    g.skyCtx = g.sky.getContext('2d');
    g.back = mk(pxW, pxH);               // …with the moon and the paper, as composed each frame
    g.backCtx = g.back.getContext('2d');
    g.mottle = buildMottle(g);
    g.bands = {};
    g.clouds = cfg.clouds.map((cloud) => ({ ...cloud, key: '', masks: null, canvas: null }));
    g.moon = { key: '', canvas: null };
    g.mist = mk(1024, Math.ceil(60 * s));
    return g;
  }

  /** Paint mottle, unique to the display (quarter size, stretched): long
   *  horizontal drags in the sky, broader blots on the land. For soft-light. */
  function buildMottle(g) {
    const w = Math.ceil(g.pxW / 4), h = Math.ceil(g.pxH / 4);
    const hz = (g.cfg.horizon * g.s) / 4;
    return imageCanvas(w, h, (d) => {
      for (let y = 0; y < h; y += 1) {
        const land = smoothstep(hz - 6, hz + 14, y);
        for (let x = 0; x < w; x += 1) {
          const drag = fb(x / 80 + 9.2, y / 7 + 1.3, 3);
          const blot = fb(x / 70 + 3.1, y / 20 + 8.4, 2);
          const v = 0.5 + (drag - 0.5) * (1 - land) * 0.5 + (blot - 0.5) * land * 0.32;
          const q = Math.round(255 * clamp01(v));
          const i = (y * w + x) * 4;
          d[i] = q; d[i + 1] = q; d[i + 2] = q; d[i + 3] = 255;
        }
      }
    });
  }

  // ── where the lights are ─────────────────────────────────────────────

  function sunAt(state) {
    const c = G.cfg;
    const p = state.sun.progress;
    const alt = state.sun.altitude / DEG;
    if (!state.sun.isNight) {
      const lift = Math.pow(Math.max(0, Math.sin(Math.PI * p)), 0.88);
      return { x: (0.04 + 0.92 * p) * G.Wa, y: c.horizon - (c.horizon - c.sunTop) * lift, alt };
    }
    const west = p < 0.5;
    return { x: (west ? 0.96 : 0.04) * G.Wa, y: c.horizon + (-alt - 0.8) * 9, alt };
  }

  function moonAt(state) {
    const m = state.moon;
    if (!m) return null;
    const c = G.cfg;
    const a = m.altitude / DEG;
    const y = a <= 30
      ? c.horizon - (c.horizon - c.moonMid) * Math.pow(Math.max(0, a) / 30, 0.9)
      : lerp(c.moonMid, c.moonTop, smoothstep(35.5, 41, a));
    return { x: m.x * G.Wa, y, alt: a, fraction: m.fraction, rotation: m.rotation, inDaylight: m.inDaylight };
  }

  /** 0 on his name and age, 1 once a disc of radius `r` at (x, y) is clear of them. */
  function clearOfText(x, y, r) {
    const [x0, y0, x1, y1] = G.cfg.text;
    const dx = Math.max(x0 - x, 0, x - x1), dy = Math.max(y0 - y, 0, y - y1);
    return smoothstep(r - 3, r + 7, Math.hypot(dx, dy));
  }

  // ── the palette for this minute ──────────────────────────────────────

  /** The land the keys were mixed for: dormant straw. A season's local colour
   *  shows as its difference from this. */
  const STRAW = K(0.75, 0.05, 88);

  function landLocals(sea) {
    const straw = STRAW;
    const summer = K(0.69, 0.105, 140);
    const spring = K(0.775, 0.12, 127);
    const ochre = K(0.775, 0.095, 82);
    let base = mixLab(straw, summer, sea.grass);
    base = mixLab(base, spring, 0.7 * sea.weights.spring * sea.grass);
    base = mixLab(base, ochre, 0.8 * sea.weights.autumn);
    base = mixLab(base, K(0.88, 0.018, 235), 0.5 * sea.frost);
    base = mixLab(base, K(0.955, 0.012, 250), sea.snow);
    return base;
  }

  function leafLocal(hue) {
    const stops = [[0, K(0.78, 0.13, 128)], [0.5, K(0.61, 0.115, 141)], [0.8, K(0.76, 0.13, 78)], [1, K(0.6, 0.12, 46)]];
    for (let i = 0; i < stops.length - 1; i += 1) {
      if (hue <= stops[i + 1][0]) return mixLab(stops[i][1], stops[i + 1][1], (hue - stops[i][0]) / (stops[i + 1][0] - stops[i][0]));
    }
    return stops[stops.length - 1][1];
  }

  function resolve(state) {
    const scheme = state.scheme === 'light' ? 'light' : 'dark';
    const light = scheme === 'light';
    const B = bloomOf(state);
    const sun = sunAt(state);
    const moon = moonAt(state);
    const key = keyAt(KEYS[scheme], sun.alt);
    const sea = seasonOf(state.dayOfYear, state.latitude);
    const p = B.presence;
    const depth = B.depth;

    // By day the hush pulls the light palette toward the page; by night it only
    // greys it, so that the light appearance still has a night to show.
    const lightHush = { chroma: LIGHT_HUSH.chroma, toward: lerp(0.14, LIGHT_HUSH.toward, smoothstep(-10, 0, sun.alt)) };
    /** A full-strength colour as it shows now: presence, then the dimmed room. */
    const show = (lab, opts = {}) => {
      let rgb = fromOklab(lab);
      const pp = opts.presence ?? p;
      rgb = light ? present(rgb, pp, PAGE, lightHush) : presentDark(rgb, pp, DARK_HUSH);
      if (depth > 0 && !opts.noDepth) {
        const q = toOklab(rgb);
        const k = light ? 1 - 0.035 * depth : 1 - 0.1 * depth;
        rgb = fromOklab({ L: q.L * k, a: q.a * (1 - 0.12 * depth), b: q.b * (1 - 0.12 * depth) });
      }
      return rgb;
    };
    const C = (lab, opts) => css(show(lab, opts));

    // Which light the land answers: the sun until it is well down, then the moon.
    const sunPower = smoothstep(-7, -1.5, sun.alt);
    const moonPower = moon ? (1 - smoothstep(-8, -3, sun.alt)) * (0.3 + 0.7 * moon.fraction) : 0;
    const lamp = sunPower >= moonPower
      ? { x: sun.x, y: Math.min(sun.y, G.cfg.horizon - 2), power: sunPower, kind: 'sun' }
      : { x: moon.x, y: moon.y, power: moonPower, kind: 'moon' };

    // Land.
    const local = landLocals(sea);
    const n = G.cfg.hills.length;
    const land = (index, lit) => {
      const d = G.cfg.hills[index].depth;
      const wob = [0, -0.012, 0.014, -0.014, 0.01, -0.016, 0][index] ?? 0;
      const chromaK = [0.85, 0.92, 1.06, 1, 1.1, 1.05, 1][index] ?? 1;
      const ground = mixLab(key.landFar, key.landNear, Math.pow(d, 0.8));
      const near = 0.35 + 0.65 * d;                    // far hills keep less of their own colour
      let c = {
        L: ground.L + (local.L - STRAW.L) * key.localGain + wob,
        a: ground.a + (local.a - STRAW.a) * key.keep * near * chromaK,
        b: ground.b + (local.b - STRAW.b) * key.keep * near * chromaK,
      };
      if (lit === true) c = { L: c.L + key.litGain, a: lerp(c.a, key.key.a, 0.34), b: lerp(c.b, key.key.b, 0.34) };
      // the side turned away: a cooler, darker mix of the same paint
      if (lit === 'shade') c = { L: c.L - key.litGain * (light ? 0.55 : 0.3), a: lerp(c.a, key.sky[0].a, 0.3), b: lerp(c.b, key.sky[0].b, 0.3) };
      return c;
    };

    const pal = {
      scheme, light, presence: p, depth, starsOut: B.stars, event: B.event, sea, sun, moon, lamp,
      sky: key.sky.map((c) => show(c)).map(toOklab),
      anti: key.anti.map((c) => show(c)).map(toOklab),
      glow: show(key.glow), glowAmt: key.glowAmt,
      rose: show({ L: key.sky[2].L + (light ? 0.01 : 0.05), a: key.sky[2].a * 1.35 + 0.01, b: key.sky[2].b * 1.2 }),
      sunDisc: C(key.sun), halo: show(key.halo), haloAmt: key.haloAmt, sunClear: 1,
      cloud: key.cloud.map((c) => C(c)),
      bank: C(light
        ? { L: Math.max(key.cloud[1].L, 0.9), a: key.cloud[1].a * 0.8, b: key.cloud[1].b * 0.8 }
        : { L: Math.min(key.cloud[2].L, 0.28), a: key.cloud[2].a, b: key.cloud[2].b }),
      bankLit: C(light
        ? { L: Math.max(key.cloud[0].L, 0.925), a: key.cloud[0].a * 0.7, b: key.cloud[0].b * 0.7 }
        : { L: Math.min(key.cloud[0].L, 0.33), a: key.cloud[0].a * 0.8, b: key.cloud[0].b * 0.8 }),
      hills: G.cfg.hills.map((_, i) => ({ base: C(land(i, false)), lit: C(land(i, true)), shade: C(land(i, 'shade')) })),
      haze: show(key.haze),
      mist: show(key.mist), mistAmt: key.mistAmt,
      ink: C(key.ink),
      inkLit: C({ L: key.ink.L + key.litGain * 1.6, a: lerp(key.ink.a, key.key.a, 0.6), b: lerp(key.ink.b, key.key.b, 0.6) }),
      litAmt: lamp.power,
      n,
    };

    // In the dark appearance nothing bright passes behind his name: the sun
    // dims to an ember while it is there (it only is in the hushed hours).
    if (!light) {
      const clear = clearOfText(sun.x, sun.y, G.cfg.sunR);
      const disc = toOklab(show(key.sun));
      const cap = lerp(0.375, 1, clear);
      if (disc.L > cap) pal.sunDisc = cssLab({ L: cap, a: disc.a * 0.8, b: disc.b * 0.8 });
      pal.haloAmt *= 0.25 + 0.75 * clear;
      pal.sunClear = clear;
    }

    // The tree's seasonal paints, re-mixed by the same light as the land.
    // (A mid-green leaf sits a step under the near land in the light appearance and a step
    // over it in the dark one, where the tree is otherwise a silhouette; paler paints —
    // blossom, snow, frost — rise from there.)
    const paint = (loc, dL = 0) => {
      const own = 0.55 + 0.35 * key.keep;               // how much of its own colour the light leaves it
      const gain = light ? 0.85 : 0.25 + 0.7 * key.keep;
      return {
        L: key.landNear.L + (light ? -0.14 : 0.075) + (loc.L - 0.61) * gain + dL,
        a: loc.a * own + key.landNear.a * 0.5,
        b: loc.b * own + key.landNear.b * 0.5,
      };
    };
    const leaf = leafLocal(sea.leafHue);
    pal.leaf = C(paint(leaf));
    pal.leafShade = C(paint(leaf, light ? -0.06 : -0.035));
    pal.leafLit = C(mixLab(paint(leaf, light ? 0.05 : 0.07), { ...key.key, L: paint(leaf).L + 0.08 }, 0.35));
    pal.blossom = C(paint(K(0.95, 0.05, 355), light ? 0.02 : 0.0));
    pal.blossomShade = C(paint(K(0.86, 0.07, 350)));
    pal.snow = C(paint(K(0.985, 0.008, 250), light ? 0.03 : 0.0));
    pal.frost = C(paint(K(0.93, 0.02, 235)));
    pal.lastLeaf = C(paint(K(0.66, 0.13, 50), light ? 0.02 : 0.13));
    return pal;
  }

  const cssLab = (lab, alpha = 1) => css(fromOklab(lab), alpha);

  // ── the sky ──────────────────────────────────────────────────────────

  /** The sky is laid in bands: each a stroke dragged across with a dry top
   *  edge, melting away below. Their shapes never change — only their paint. */
  function bandMasks(seed) {
    if (G.bands[seed]) return G.bands[seed];
    const s = G.s, w = G.pxW, hz = G.cfg.horizon * s;
    const cuts = [0.15, 0.34, 0.52, 0.68, 0.81, 0.91];
    G.bands[seed] = cuts.map((cut, k) => {
      const y0 = cut * hz;
      const y1 = (k + 1 < cuts.length ? cuts[k + 1] : 1.02) * hz;
      const bandH = Math.ceil(y1 - y0 + 26 * s);
      const c = mk(w, bandH + 20);
      const b = c.getContext('2d');
      b.fillStyle = '#fff';
      b.fillRect(0, 10, w, bandH);
      const edge = new Path2D();
      for (let x = -8; x <= w + 8; x += 8) {
        const y = 10 + (vn(x / (150 * s) + k * 7.3 + seed, k * 2.1 + seed) - 0.5) * 9 * s;
        if (x === -8) edge.moveTo(x, y); else edge.lineTo(x, y);
      }
      dryEdge(b, edge, [[15 * s, 0.75, 'sparse'], [8 * s, 0.8, 'sparse'], [3.5 * s, 0.9, 'dense']], k * 97 + seed * 31, k * 53);
      b.globalCompositeOperation = 'destination-in';
      const fade = b.createLinearGradient(0, 10, 0, 10 + bandH);
      fade.addColorStop(0, 'rgba(0,0,0,1)');
      fade.addColorStop(0.45, 'rgba(0,0,0,0.8)');
      fade.addColorStop(1, 'rgba(0,0,0,0)');
      b.fillStyle = fade;
      b.fillRect(0, 0, w, bandH + 20);
      return { canvas: c, y: y0 - 10, at: Math.min(1, cut + 0.085) };
    });
    return G.bands[seed];
  }

  function paintSkyRamp(ctx, stops, w, h, hz, seed, strength) {
    const s = G.s;
    const yEnd = hz + 40 * s;
    const grad = ctx.createLinearGradient(0, 0, 0, hz);
    for (let i = 0; i <= 24; i += 1) grad.addColorStop(i / 24, cssLab(rampLab(stops, i / 24)));
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, w, Math.max(yEnd, h));
    for (const band of bandMasks(seed)) {
      const bw = band.canvas.width, bh = band.canvas.height;
      const paint = tinted(band.canvas, cssLab(rampLab(stops, band.at)));
      ctx.globalAlpha = 0.62 * strength;
      ctx.drawImage(paint, 0, 0, bw, bh, 0, band.y, bw, bh);
    }
    ctx.globalAlpha = 1;
  }

  function discPath(cx, cy, r, wobble, seed) {
    const path = new Path2D();
    const steps = 72;
    for (let i = 0; i <= steps; i += 1) {
      const a = (i / steps) * TAU;
      const rr = r * (1 + wobble * (Math.sin(2 * a + seed) * 0.6 + Math.sin(3 * a + seed * 2.3) * 0.4 + Math.sin(5 * a + seed * 4.1) * 0.25));
      const x = cx + rr * Math.cos(a), y = cy + rr * Math.sin(a);
      if (i === 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    path.closePath();
    return path;
  }

  function paintSky(pal) {
    const ctx = G.skyCtx;
    const s = G.s, w = G.pxW, h = G.pxH;
    const hz = G.cfg.horizon * s;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.globalCompositeOperation = 'source-over';
    ctx.globalAlpha = 1;
    ctx.clearRect(0, 0, w, h);

    // Away from the sun…
    const strokes = 0.5 + 0.5 * pal.presence;      // the brushwork quietens with the colour
    paintSkyRamp(ctx, pal.anti, w, h, hz, 1, strokes);
    // …and toward it, laid over through a wide soft mask.
    const sunX = (G.ox + pal.sun.x) * s;
    const a = scratch('a', w, h);
    paintSkyRamp(a, pal.sky, w, h, hz, 5, strokes);
    a.globalCompositeOperation = 'destination-in';
    const reach = 640 * s;
    const mask = a.createLinearGradient(sunX - reach, 0, sunX + reach, 0);
    const shape = [[0, 0], [0.2, 0.06], [0.42, 0.4], [0.62, 0.8], [0.8, 0.97], [1, 1]];
    for (const [t, v] of shape) mask.addColorStop(t / 2, `rgba(0,0,0,${v})`);
    for (const [t, v] of shape.slice().reverse()) mask.addColorStop(1 - t / 2, `rgba(0,0,0,${v})`);
    a.fillStyle = mask;
    a.fillRect(0, 0, w, h);
    ctx.drawImage(a.canvas, 0, 0, w, h, 0, 0, w, h);

    // The pool of light at the sun's foot.
    const glowAmt = pal.glowAmt * (pal.light ? 1 : 1);
    if (glowAmt > 0.01) {
      const gy = Math.min(pal.sun.y * s, hz + 4 * s);
      ctx.save();
      ctx.translate(sunX, gy);
      ctx.scale(1, 0.5);
      // widest, the rose that lies beside and above the gold; then the gold itself
      for (const [radius, strength, tint] of [[640 * s, 0.5, pal.rose], [380 * s, 0.55, pal.glow], [150 * s, 0.6, pal.glow]]) {
        const pool = ctx.createRadialGradient(0, 0, 0, 0, 0, radius);
        pool.addColorStop(0, css(tint, glowAmt * strength));
        pool.addColorStop(0.3, css(tint, glowAmt * strength * 0.55));
        pool.addColorStop(0.65, css(tint, glowAmt * strength * 0.16));
        pool.addColorStop(1, css(tint, 0));
        ctx.fillStyle = pool;
        ctx.beginPath();
        ctx.arc(0, 0, radius, 0, TAU);
        ctx.fill();
      }
      ctx.restore();
    }

    // The sun: a painted halo (two dry rings), then the disc.
    const R = G.cfg.sunR * s;
    const sy = pal.sun.y * s;
    if (sy - R < hz + 16 * s) {
      const stamp = (radius, wobble, seed, colour, alpha, passes) => {
        const size = Math.ceil(radius * 2.12 + 24 * s);
        const b = scratch('b', size, size);
        const shape = discPath(size / 2, size / 2, radius, wobble, seed);
        b.fillStyle = colour;
        b.fill(shape);
        dryEdge(b, shape, passes, seed * 40, seed * 71);
        ctx.globalAlpha = alpha;
        ctx.drawImage(b.canvas, 0, 0, size, size, sunX - size / 2, sy - size / 2, size, size);
        ctx.globalAlpha = 1;
      };
      if (pal.haloAmt > 0.01) {
        const dry = [[9 * s, 0.7, 'sparse'], [4.5 * s, 0.85, 'sparse'], [2 * s, 0.9, 'dense']];
        stamp(R * 3.7, 0.022, 2.1, css(pal.halo), 0.3 * pal.haloAmt, dry);
        stamp(R * 2.15, 0.022, 0.7, css(pal.halo), 0.5 * pal.haloAmt, dry);
      }
      stamp(R, 0.016, 4.2, pal.sunDisc, 1, [[1.7 * s, 0.5, 'dense']]);
    }
  }

  /** The slab's bank of cloud along the horizon, behind his name. In front of
   *  the sun and the moon: they rise out of it and sink into it. */
  function drawBank(ctx, pal) {
    const bank = G.cfg.bank;
    if (!bank) return;
    const s = G.s;
    const bw = Math.ceil((bank.x1 - bank.x0 + 20) * s), bh = Math.ceil((bank.foot - bank.top + 24) * s);
    const ox = (G.ox + bank.x0 - 10) * s, oy = (bank.top - 14) * s;
    const shape = (lift, shorten) => {
      const path = new Path2D();
      const edge = new Path2D();
      const x0 = 10 * s, x1 = bw - (10 + shorten) * s;
      path.moveTo(x0 - 30 * s, bh + 10);
      for (let x = x0 - 30 * s; x <= x1; x += 3) {
        const u = clamp01((x - x0) / (x1 - x0));
        // a long low bank: a few soft swells, sinking to the horizon at its far end
        const swell = 4 * Math.sin(u * 6.4 + 0.6) + 2.5 * Math.sin(u * 14 + 2.1) + (vn(x / (22 * s) + 3.3, 9.1) - 0.5) * 3;
        const sink = Math.pow(smoothstep(0.8, 1, u), 1.4) * (bank.foot - bank.top);
        const y = (14 + lift + 4 - swell + sink) * s;
        path.lineTo(x, y);
        if (x === x0 - 30 * s) edge.moveTo(x, y); else edge.lineTo(x, y);
      }
      path.lineTo(x1, bh + 10);
      path.closePath();
      return { path, edge };
    };
    const lay = (lift, shorten, colour, alpha, seed) => {
      const b = scratch('b', bw, bh);
      const { path, edge } = shape(lift, shorten);
      b.fillStyle = colour;
      b.fill(path);
      dryEdge(b, edge, [[7 * s, 0.7, 'sparse'], [3.6 * s, 0.8, 'sparse'], [1.8 * s, 0.9, 'dense']], seed, seed * 3);
      ctx.globalAlpha = alpha;
      ctx.drawImage(b.canvas, 0, 0, bw, bh, ox, oy, bw, bh);
      ctx.globalAlpha = 1;
    };
    lay(0, 0, pal.bankLit, 0.97, 41);       // its top, catching what light there is
    lay(4, 5, pal.bank, 0.97, 67);          // its body
  }

  /** The back plane as the frame uses it: the sky, the moon on it, paint and paper over both. */
  function composeBack(pal, skyTx, skyTy) {
    const ctx = G.backCtx;
    const s = G.s;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.globalCompositeOperation = 'source-over';
    ctx.globalAlpha = 1;
    ctx.drawImage(G.sky, 0, 0);
    if (pal.moon) {
      const size = G.moon.canvas.width;
      ctx.drawImage(G.moon.canvas, (G.ox + pal.moon.x + skyTx) * s - size / 2, (pal.moon.y + skyTy) * s - size / 2);
    }
    drawBank(ctx, pal);
    bakeTexture(ctx, G.pxW, G.pxH, 0, 0, pal, true);
  }

  /** Paint mottle and paper tooth, soft-light, baked into a layer. A layer with
   *  holes in it gets its own alpha back afterwards. (dx, dy: where the display's
   *  top-left is on the layer.) */
  function bakeTexture(ctx, w, h, dx, dy, pal, opaque) {
    let keep = null;
    if (!opaque) {
      const a = scratch('a', w, h);
      a.drawImage(ctx.canvas, 0, 0, w, h, 0, 0, w, h);
      keep = a.canvas;
    }
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.globalCompositeOperation = 'soft-light';
    ctx.globalAlpha = pal.light ? 0.5 : 0.4;
    ctx.drawImage(G.mottle, dx - G.padPx, dy, G.pxW + 2 * G.padPx, G.pxH + G.padPx);
    ctx.globalAlpha = pal.light ? 0.4 : 0.32;
    T.paperPattern.setTransform(new DOMMatrix().translate(dx, dy));
    ctx.fillStyle = T.paperPattern;
    ctx.fillRect(0, 0, w, h);
    if (keep) {
      ctx.globalCompositeOperation = 'destination-in';
      ctx.globalAlpha = 1;
      ctx.drawImage(keep, 0, 0, w, h, 0, 0, w, h);
    }
    ctx.globalCompositeOperation = 'source-over';
    ctx.globalAlpha = 1;
  }

  // ── the moon ─────────────────────────────────────────────────────────

  function moonPhasePath(lit, r) {
    const terminator = 1 - 2 * clamp01(lit);
    const steps = 48;
    const path = new Path2D();
    for (let i = 0; i <= steps; i += 1) {
      const t = (Math.PI * i) / steps;
      const x = r * Math.sin(t), y = -r * Math.cos(t);
      if (i === 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    for (let i = steps; i >= 0; i -= 1) {
      const t = (Math.PI * i) / steps;
      path.lineTo(terminator * r * Math.sin(t), -r * Math.cos(t));
    }
    path.closePath();
    return path;
  }

  function paintMoon(pal) {
    const m = pal.moon;
    const s = G.s;
    const R = G.cfg.moonR * s;
    const size = Math.ceil(R * 9);
    if (!G.moon.canvas || G.moon.canvas.width !== size) G.moon.canvas = mk(size, size);
    const ctx = G.moon.canvas.getContext('2d');
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.globalAlpha = 1;
    ctx.globalCompositeOperation = 'source-over';
    ctx.clearRect(0, 0, size, size);
    const c = size / 2;
    const night = 1 - smoothstep(-6, -1, pal.sun.alt);
    const clear = pal.light ? 1 : clearOfText(m.x, m.y, G.cfg.moonR);
    const cream = pal.light ? K(0.985, 0.022, 92) : mixLab(K(0.4, 0.03, 300), K(0.93, 0.045, 88), clear);
    const haloTint = pal.light ? K(0.955, 0.025, 95) : K(0.5, 0.05, 270);
    // The painted halo: quiet, and only at night.
    const haloAmt = night * clear * (0.35 + 0.65 * m.fraction) * (pal.light ? 0.5 : 0.16);
    if (haloAmt > 0.01) {
      for (const [k, alpha, seed] of [[3.9, 0.5, 1.3], [2.3, 0.8, 3.9]]) {
        const b = scratch('b', size, size);
        const ring = discPath(c, c, R * k, 0.02, seed);
        b.fillStyle = cssLab(haloTint);
        b.fill(ring);
        dryEdge(b, ring, [[8 * s, 0.7, 'sparse'], [4 * s, 0.85, 'sparse'], [2 * s, 0.9, 'dense']], seed * 33, seed * 61);
        ctx.globalAlpha = alpha * haloAmt;
        ctx.drawImage(b.canvas, 0, 0, size, size, 0, 0, size, size);
        ctx.globalAlpha = 1;
      }
    }
    // The whole disc, barely: the unlit part of a picture-book moon is still there.
    const whole = discPath(c, c, R, 0.014, 2.2);
    const shine = smoothstep(0.03, 0.3, m.fraction);
    ctx.fillStyle = cssLab(pal.light ? K(0.9, 0.03, 275) : K(0.27, 0.05, 272), (pal.light ? 0.3 : 0.4) * night * shine);
    ctx.fill(whole);
    // The lit part, turned to the bright limb's real angle.
    const b = scratch('b', size, size);
    b.save();
    b.translate(c, c);
    b.rotate(m.rotation);
    b.fillStyle = cssLab(cream);
    b.fill(moonPhasePath(m.fraction, R));
    b.restore();
    // a few thin washes of a cooler cream, so it is not a sticker
    b.globalCompositeOperation = 'source-atop';
    b.fillStyle = cssLab(pal.light ? K(0.93, 0.03, 80) : mixLab(K(0.37, 0.03, 300), K(0.84, 0.045, 78), clear), 0.5);
    b.globalAlpha = 0.5;
    b.beginPath();
    b.ellipse(c - 0.5 * R, c + 0.42 * R, 0.95 * R, 0.6 * R, -0.7, 0, TAU);   // one thin wash, off to one side
    b.fill();
    b.globalAlpha = 1;
    b.globalCompositeOperation = 'source-over';
    dryEdge(b, whole, [[2.2 * s, 0.55, 'dense']], 5, 9);
    const day = m.inDaylight ? lerp(0.62, 1, night) : 1;
    ctx.globalAlpha = day;
    ctx.drawImage(b.canvas, 0, 0, size, size, 0, 0, size, size);
    ctx.globalAlpha = 1;
  }

  // ── clouds ───────────────────────────────────────────────────────────

  /** A cloud's three masks (body, the side toward the light, the side away),
   *  from its blobs: a soft implicit shape with a streaky, dry edge. */
  function buildCloudMasks(cloud, lx, ly) {
    const s = G.s, k = cloud.scale;
    let ex = 0, top = 0, bot = 0;
    for (const [bx, by, rx, ry] of cloud.blobs) {
      ex = Math.max(ex, Math.abs(bx) + rx * 1.9);
      top = Math.min(top, by - ry * 1.9);
      bot = Math.max(bot, by + ry * 1.9);
    }
    bot = Math.min(bot, cloud.base + 5);
    const w = Math.ceil(ex * 2 * k * s) + 8, h = Math.ceil((bot - top) * k * s) + 8;
    const cx = w / 2, cy = 4 - top * k * s;
    const field = (px, py) => {
      const x = (px - cx) / (k * s), y = (py - cy) / (k * s);
      let f = 0;
      for (const [bx, by, rx, ry, wt] of cloud.blobs) {
        const dx = (x - bx) / rx, dy = (y - by) / ry;
        f += wt * Math.exp(-(dx * dx + dy * dy));
      }
      return f * (1 - smoothstep(cloud.base - 3.5, cloud.base + 1, y));
    };
    const TH = 0.42;
    const dLit = 8.5 * k * s, dShade = 7 * k * s;
    const body = new Uint8ClampedArray(w * h), lit = new Uint8ClampedArray(w * h), shade = new Uint8ClampedArray(w * h);
    for (let py = 0; py < h; py += 1) {
      for (let px = 0; px < w; px += 1) {
        const f0 = field(px, py);
        if (f0 < TH - 0.3) continue;                    // clear sky: the edge's wobble cannot reach it
        const n = fb(px / (15 * s) + cloud.x, py / (2.6 * s) + cloud.y, 3);
        const tooth = vn(px / 1.7 + 31, py / 1.7 + 77);
        const endness = smoothstep(0.55, 1, Math.abs(px - cx) / (w / 2));
        const amp = 0.16 + 0.3 * endness;
        const f = f0 + (n - 0.5) * amp + (tooth - 0.5) * 0.07;
        const a = smoothstep(TH - 0.035, TH + 0.035, f);
        if (a <= 0) continue;
        const i = py * w + px;
        body[i] = 255 * a;
        const fl = field(px + lx * dLit, py + ly * dLit) + (n - 0.5) * 0.3 + (tooth - 0.5) * 0.16;
        lit[i] = 255 * a * (1 - smoothstep(TH - 0.05, TH + 0.05, fl));
        const fs = field(px - lx * dShade, py - ly * dShade) + (n - 0.5) * 0.3 + (tooth - 0.5) * 0.16;
        shade[i] = 255 * a * (1 - smoothstep(TH - 0.05, TH + 0.05, fs));
      }
    }
    const toCanvas = (alpha) => imageCanvas(w, h, (d) => {
      for (let i = 0; i < w * h; i += 1) { d[i * 4] = 255; d[i * 4 + 1] = 255; d[i * 4 + 2] = 255; d[i * 4 + 3] = alpha[i]; }
    });
    return { w, h, cx, cy, body: toCanvas(body), lit: toCanvas(lit), shade: toCanvas(shade) };
  }

  function paintCloud(cloud, pal, lightKey, x) {
    if (!cloud.masks || cloud.maskKey !== lightKey) {
      // lit from the lamp's side; from below only a little, or the flat base becomes a line
      let dx = pal.lamp.x - x, dy = pal.lamp.y - cloud.y;
      let dist = Math.hypot(dx, dy) || 1;
      dx /= dist; dy = Math.min(dy / dist, 0.45);
      dist = Math.hypot(dx, dy) || 1;
      cloud.masks = buildCloudMasks(cloud, dx / dist, dy / dist);
      cloud.maskKey = lightKey;
      cloud.canvas = mk(cloud.masks.w, cloud.masks.h);
    }
    const { w, h, body, lit, shade } = cloud.masks;
    const ctx = cloud.canvas.getContext('2d');
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.globalAlpha = 1;
    ctx.clearRect(0, 0, w, h);
    ctx.drawImage(tinted(body, pal.cloud[1]), 0, 0, w, h, 0, 0, w, h);
    ctx.globalAlpha = 0.55;
    ctx.drawImage(tinted(shade, pal.cloud[2]), 0, 0, w, h, 0, 0, w, h);
    ctx.globalAlpha = 0.3 + 0.6 * pal.litAmt;
    ctx.drawImage(tinted(lit, pal.cloud[0]), 0, 0, w, h, 0, 0, w, h);
    // the paper shows through the cloud's paint too
    ctx.globalCompositeOperation = 'soft-light';
    ctx.globalAlpha = pal.light ? 0.4 : 0.32;
    T.paperPattern.setTransform(new DOMMatrix().translate(cloud.x * 3, cloud.y * 5));
    ctx.fillStyle = T.paperPattern;
    ctx.fillRect(0, 0, w, h);
    ctx.globalCompositeOperation = 'destination-in';
    ctx.globalAlpha = 1;
    ctx.drawImage(body, 0, 0);
    ctx.globalCompositeOperation = 'source-over';
  }

  // ── hills ────────────────────────────────────────────────────────────

  function lampDirection(pal) {
    // From the middle of the land to the light: low sun → along the ground, noon → from above.
    const rx = G.Wa * 0.42, ry = G.cfg.horizon + 46;
    const dx = pal.lamp.x - rx, dy = pal.lamp.y - ry;
    const dist = Math.hypot(dx, dy) || 1;
    return { x: dx / dist, y: dy / dist };
  }

  /** A hill's cut-out edge, dragged dry: the strip of rows the crest crosses. */
  function hillEdgeMask(hill) {
    if (hill.edgeMask) return hill.edgeMask;
    const s = G.s, w = G.layerW;
    const c = mk(w, hill.stripH);
    const ctx = c.getContext('2d');
    ctx.translate(0, -hill.y0);
    ctx.fillStyle = '#fff';
    ctx.fill(hill.body);
    const edge = new Path2D();
    edge.moveTo(-4, hill.crest[0] - hill.y0);
    for (let j = 0; j < w; j += 2) edge.lineTo(j, hill.crest[j] - hill.y0);
    edge.lineTo(w + 4, hill.crest[w - 1] - hill.y0);
    const passes = hill.index < 2
      ? [[5 * s, 0.6, 'sparse'], [2.2 * s, 0.75, 'dense']]
      : [[7 * s, 0.7, 'sparse'], [3.6 * s, 0.8, 'sparse'], [1.8 * s, 0.9, 'dense']];
    dryEdge(ctx, edge, passes, hill.index * 83, hill.index * 29);
    hill.edgeMask = c;
    return c;
  }

  /** The lit shoulder and the shaded one: the crest's own shape slid away from
   *  the light (or toward it); the strip between the two, dragged dry along its
   *  lower edge. Repainted only when the light has moved. */
  function hillSideMasks(hill, dir, lightKey) {
    if (hill.sides.key === lightKey) return hill.sides;
    const s = G.s, w = G.layerW, h = hill.stripH;
    const { crest, y0, index } = hill;
    const edge = hillEdgeMask(hill);
    const make = (toward, seed, into) => {
      const reach = hill.reach * (toward ? 1 : 1.5);
      const shiftX = dir.x * reach * (toward ? 1 : -1), shiftY = toward ? Math.max(0, -dir.y) * reach * 0.3 : 0;
      const c = into ?? mk(w, h);
      const ctx = c.getContext('2d');
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.globalCompositeOperation = 'source-over';
      ctx.globalAlpha = 1;
      ctx.clearRect(0, 0, w, h);
      const under = new Path2D();
      const line = new Path2D();
      under.moveTo(-4, -4);
      for (let j = 0; j < w; j += 2) {
        const widen = 0.5 + 1.0 * vn(j / (120 * s) + index * 3.1 + seed, 5.5 + index);
        const src = clamp(Math.round(j + shiftX * widen), 0, w - 1);
        const y = crest[src] - y0 + shiftY * widen - 0.3 * s;
        under.lineTo(j, y);
        if (j === 0) line.moveTo(j, y); else line.lineTo(j, y);
      }
      under.lineTo(w + 4, -4);
      under.closePath();
      ctx.fillStyle = '#fff';
      ctx.fill(under);
      dryEdge(ctx, line, [[12 * s, 0.85, 'sparse'], [7 * s, 0.85, 'sparse'], [3 * s, 0.9, 'dense']], index * 61 + seed * 13, index * 37);
      ctx.globalCompositeOperation = 'destination-in';        // only where the hill is
      ctx.drawImage(edge, 0, 0);
      ctx.globalCompositeOperation = 'source-over';
      return c;
    };
    hill.sides.shade = make(false, 7, hill.sides.shade);
    hill.sides.lit = make(true, 0, hill.sides.lit);
    hill.sides.key = lightKey;
    return hill.sides;
  }

  /** One plane of land: its hills back to front, each a flat fill with its dry
   *  edge, its two sides, the haze at its foot; the tree on its hill; the mist
   *  lying in the valleys; then paint and paper. */
  function paintFront(front, pal, dir, lightKey) {
    const s = G.s, w = G.layerW;
    const { ctx, y0 } = front;
    const h = front.canvas.height;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.globalCompositeOperation = 'source-over';
    ctx.globalAlpha = 1;
    ctx.clearRect(0, 0, w, h);
    const low = 1 - Math.abs(dir.y);                      // a high light leaves no shaded side
    const amt = Math.min(1, pal.litAmt);
    for (const hill of front.hills) {
      const { index, stripH } = hill;
      const top = hill.y0 - y0;
      const colours = pal.hills[index];
      ctx.drawImage(tinted(hillEdgeMask(hill), colours.base), 0, 0, w, stripH, 0, top, w, stripH);
      ctx.fillStyle = colours.base;
      ctx.fillRect(0, top + stripH - 1, w, h - (top + stripH) + 1);
      if (pal.litAmt > 0.03) {
        const sides = hillSideMasks(hill, dir, lightKey);
        if (low > 0.05) {
          ctx.globalAlpha = amt * Math.min(1, low * 1.4);
          ctx.drawImage(tinted(sides.shade, colours.shade), 0, 0, w, stripH, 0, top, w, stripH);
        }
        ctx.globalAlpha = amt;
        ctx.drawImage(tinted(sides.lit, colours.lit), 0, 0, w, stripH, 0, top, w, stripH);
        ctx.globalAlpha = 1;
      }
      // Haze gathering at the foot, where the next hill's crest will cut across it.
      const next = G.hills[index + 1];
      if (next) {
        const from = hill.mean + 6 * s, to = next.mean + 12 * s;
        ctx.save();
        ctx.translate(0, -y0);
        ctx.clip(hill.body);
        const haze = ctx.createLinearGradient(0, from, 0, to);
        haze.addColorStop(0, css(pal.haze, 0));
        haze.addColorStop(1, css(pal.haze, 0.3 * (1 - 0.5 * hill.depth)));
        ctx.fillStyle = haze;
        ctx.fillRect(0, from, w, G.pxH + G.padPx - from);
        ctx.restore();
      }
      if (index === G.cfg.tree.hill) {
        const t = G.tree;
        ctx.drawImage(t.canvas, G.padPx + (G.ox + t.x) * s - t.masks.cx, t.baseY * s - t.masks.cy - y0);
      }
      // Mist lying in the valley behind the next hill of this plane. (The valley
      // between the two planes has the mist that moves; the frame draws that.)
      const last = hill === front.hills[front.hills.length - 1];
      if (next && !last && pal.mistAmt > 0.01) {
        const mw = G.mist.width, mh = G.mist.height;
        ctx.globalAlpha = pal.mistAmt * (0.6 - 0.35 * hill.depth);
        for (let x = -((index * 317) % mw); x < w; x += mw) ctx.drawImage(G.mist, x, next.mean - mh * 0.78 - y0);
        ctx.globalAlpha = 1;
      }
    }
    bakeTexture(ctx, w, h, G.padPx, -y0, pal, false);
  }

  function paintMist(pal) {
    const ctx = G.mist.getContext('2d');
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.globalCompositeOperation = 'source-over';
    ctx.clearRect(0, 0, G.mist.width, G.mist.height);
    ctx.drawImage(T.mist, 0, 0);
    ctx.globalCompositeOperation = 'source-in';
    ctx.fillStyle = css(pal.mist);
    ctx.fillRect(0, 0, G.mist.width, G.mist.height);
    ctx.globalCompositeOperation = 'source-over';
  }

  // ── the tree ─────────────────────────────────────────────────────────

  /** Grows the tree once, the way a tree fills its crown: twigs reach for the
   *  open places in an egg-shaped crown until it is full (space colonisation),
   *  and every limb is as thick as the twigs it carries.
   *  Unit space: the trunk's foot at (0, 0), up is −y, the whole about 1 tall. */
  function growTree() {
    const rnd = rng(20260621);
    const nodes = [];
    const add = (x, y, parent) => {
      nodes.push({ x, y, parent, kids: 0, w: 0 });
      if (parent >= 0) nodes[parent].kids += 1;
      return nodes.length - 1;
    };
    const STEP = 0.012;
    let last = add(0, 0, -1);
    for (let h = STEP; h <= 0.3; h += STEP) last = add(Math.sin(h * 8) * 0.014 + h * 0.05, -h, last);
    const crown = { cx: 0.03, cy: -0.635, rx: 0.32, ry: 0.37 };
    const points = [];
    while (points.length < 700) {
      const u = rnd() * 2 - 1, v = rnd() * 2 - 1;
      const widen = 1 + 0.14 * v;                       // an egg, fuller below the middle
      if ((u / widen) ** 2 + v ** 2 > 1 || v > 0.78) continue;
      points.push({ x: crown.cx + u * crown.rx, y: crown.cy + v * crown.ry, alive: true });
    }
    const REACH = 0.3, KILL = 0.02;
    for (const p of points) { p.near = -1; p.d = Infinity; }
    let fresh = 0;                                     // nodes not yet measured against the points
    for (let round = 0; round < 260; round += 1) {
      // each point remembers its nearest node; only the new nodes need measuring
      for (const p of points) {
        if (!p.alive) continue;
        for (let i = fresh; i < nodes.length; i += 1) {
          const d = Math.hypot(p.x - nodes[i].x, p.y - nodes[i].y);
          if (d < p.d) { p.d = d; p.near = i; }
        }
        if (round > 0 && p.d < KILL) p.alive = false;  // reached
      }
      fresh = nodes.length;
      const pull = new Map();
      for (const p of points) {
        if (!p.alive || p.d >= REACH) continue;
        const e = pull.get(p.near) ?? { x: 0, y: 0 };
        e.x += (p.x - nodes[p.near].x) / p.d;
        e.y += (p.y - nodes[p.near].y) / p.d;
        pull.set(p.near, e);
      }
      if (pull.size === 0) break;
      let grew = false;
      for (const [i, e] of pull) {
        const n = nodes[i];
        const len = Math.hypot(e.x, e.y) || 1;
        const nx = n.x + (e.x / len) * STEP + (rnd() - 0.5) * STEP * 0.4;
        const ny = n.y + (e.y / len) * STEP - 0.002 + (rnd() - 0.5) * STEP * 0.4;
        let crowded = false;
        for (const m of nodes) if (Math.hypot(m.x - nx, m.y - ny) < STEP * 0.6) { crowded = true; break; }
        if (crowded) continue;
        add(nx, ny, i);
        grew = true;
      }
      if (!grew) break;
    }
    // Every limb as thick as what it carries.
    const POWER = 1.45;
    for (let i = nodes.length - 1; i >= 0; i -= 1) {
      const n = nodes[i];
      if (n.kids === 0) n.w = 1;
      if (n.parent >= 0) nodes[n.parent].w += n.w;
    }
    const foot = Math.pow(nodes[0].w, 1 / POWER);
    for (const n of nodes) n.w = (Math.pow(n.w, 1 / POWER) / foot) * 0.064;
    return { nodes, tips: nodes.filter((n) => n.kids === 0), crown };
  }
  const TREE = growTree();

  function buildTreeMasks(sea) {
    const s = G.s;
    const H = G.tree.h * s;
    const size = Math.ceil(H * 1.3);
    const cx = size / 2, cy = size - Math.ceil(H * 0.1);
    const X = (u) => cx + u * H, Y = (v) => cy + v * H;
    const mask = () => {
      const ctx = mk(size, size).getContext('2d');
      ctx.fillStyle = '#fff'; ctx.strokeStyle = '#fff'; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
      return ctx;
    };
    const { nodes, tips, crown } = TREE;

    // Limbs.
    const wood = mask();
    for (const n of nodes) {
      if (n.parent < 0) continue;
      const q = nodes[n.parent];
      wood.lineWidth = Math.max(0.6 * s, n.w * H);
      wood.beginPath();
      wood.moveTo(X(q.x), Y(q.y));
      wood.lineTo(X(n.x), Y(n.y));
      wood.stroke();
    }
    // the foot, flaring into the ground
    wood.beginPath();
    wood.moveTo(X(-0.07), Y(0.014));
    wood.quadraticCurveTo(X(-0.04), Y(-0.02), X(nodes[7].x - nodes[7].w / 2), Y(nodes[7].y));
    wood.lineTo(X(nodes[7].x + nodes[7].w / 2), Y(nodes[7].y));
    wood.quadraticCurveTo(X(0.046), Y(-0.02), X(0.078), Y(0.014));
    wood.closePath();
    wood.fill();
    // the paint skips here and there on the trunk
    wood.globalCompositeOperation = 'destination-out';
    wood.globalAlpha = 0.3;
    T.sparsePattern.setTransform(new DOMMatrix().rotateSelf(80));
    wood.fillStyle = T.sparsePattern;
    wood.fillRect(X(-0.09), Y(-0.36), 0.2 * H, 0.38 * H);
    T.sparsePattern.setTransform(new DOMMatrix());

    const out = { size, cx, cy, wood: wood.canvas };

    // Leaf masses: a few rounded clumps that together make the crown.
    const foliage = sea.foliage;
    if (foliage > 0.04) {
      const back = mask(), front = mask();
      const clumps = [[0.02, -0.62, 0.5], [-0.62, -0.22, 0.46], [0.62, -0.3, 0.46], [-0.32, 0.3, 0.46], [0.4, 0.32, 0.44],
        [0.02, -0.08, 0.5], [-0.78, 0.36, 0.34], [0.8, 0.34, 0.33], [-0.3, -0.5, 0.4], [0.36, -0.56, 0.38]];
      clumps.forEach(([u, v, r], i) => {
        const ctx = i % 3 === 1 || i >= 8 ? back : front;
        const big = r * crown.rx * (0.4 + 0.6 * foliage) * (1 - 0.3 * sea.leafFall);
        for (let b = 0; b < 5; b += 1) {
          const a = hash(i * 9 + b, 63) * TAU, d = hash(i * 9 + b, 64) * big * 0.55;
          const rr = big * (0.62 + 0.4 * hash(i * 9 + b, 65));
          ctx.beginPath();
          ctx.ellipse(X(crown.cx + u * crown.rx + Math.cos(a) * d), Y(crown.cy + v * crown.ry + Math.sin(a) * d * 0.8), rr * H, rr * H * 0.88, 0, 0, TAU);
          ctx.fill();
        }
      });
      for (const ctx of [back, front]) {
        ctx.globalCompositeOperation = 'destination-out';
        ctx.globalAlpha = 0.16;
        ctx.fillStyle = T.sparsePattern;
        ctx.fillRect(0, 0, size, size);
        ctx.globalAlpha = 1;
        ctx.globalCompositeOperation = 'source-over';
      }
      out.leafBack = back.canvas;
      out.leafFront = front.canvas;
    }

    // Blossom: small dabs gathered at the twig ends, two tones.
    if (sea.blossom > 0.04) {
      const a = mask(), b = mask();
      const fine = nodes.filter((n) => n.w < 0.009);
      fine.forEach((n, i) => {
        const dabs = n.kids === 0 ? 3 : 1;
        for (let k = 0; k < dabs; k += 1) {
          if (hash(i * 7 + k, 72) > sea.blossom * (n.kids === 0 ? 1 : 0.42)) continue;
          const ctx = hash(i * 7 + k, 73) < 0.6 ? a : b;
          const r = (0.017 + 0.017 * hash(i * 7 + k, 74)) * H;
          ctx.beginPath();
          ctx.arc(X(n.x + (hash(i * 7 + k, 76) - 0.5) * 0.06), Y(n.y + (hash(i * 7 + k, 77) - 0.5) * 0.06), r, 0, TAU);
          ctx.fill();
        }
      });
      out.blossomA = a.canvas;
      out.blossomB = b.canvas;
    }

    // Snow lying along the limbs; frost, a thinner line of the same.
    const lying = (amount, thickness, minW) => {
      const ctx = mask();
      for (const n of nodes) {
        if (n.parent < 0 || n.w < minW) continue;
        const q = nodes[n.parent];
        const len = Math.hypot(n.x - q.x, n.y - q.y) || 1;
        const flat = Math.abs(n.x - q.x) / len;             // 0 for a limb going straight up
        if (flat < 0.34) continue;
        const lift = n.w * H * 0.5 + thickness * s * 0.3;
        ctx.lineWidth = Math.max(0.7 * s, thickness * s * (0.45 + 0.55 * flat) * amount);
        ctx.beginPath();
        ctx.moveTo(X(q.x), Y(q.y) - lift);
        ctx.lineTo(X(n.x), Y(n.y) - lift);
        ctx.stroke();
      }
      return ctx.canvas;
    };
    if (sea.snow > 0.04) out.snow = lying(sea.snow, 2.4, 0.0085);
    if (sea.frost > 0.04) out.frost = lying(sea.frost, 0.9, 0.006);

    // The last leaves of autumn, clinging.
    const clinging = sea.leafFall * (1 - sea.foliage);
    if (clinging > 0.02) {
      const ctx = mask();
      tips.forEach((t, i) => {
        if (hash(i, 81) > clinging * 0.3) return;
        ctx.beginPath();
        ctx.ellipse(X(t.x) + (hash(i, 83) - 0.5) * 2 * s, Y(t.y) + 1.3 * s, 0.8 * s, 1.35 * s, (hash(i, 82) - 0.5) * 1.2, 0, TAU);
        ctx.fill();
      });
      out.lastLeaves = ctx.canvas;
    }
    return out;
  }

  function paintTree(pal, dir) {
    const t = G.tree;
    const m = t.masks;
    if (!t.canvas || t.canvas.width !== m.size) t.canvas = mk(m.size, m.size);
    const ctx = t.canvas.getContext('2d');
    const s = G.s, size = m.size;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.globalCompositeOperation = 'source-over';
    ctx.globalAlpha = 1;
    ctx.clearRect(0, 0, size, size);
    const lay = (mask, colour, alpha = 1) => {
      if (!mask) return;
      ctx.globalAlpha = alpha;
      ctx.drawImage(tinted(mask, colour), 0, 0, size, size, 0, 0, size, size);
      ctx.globalAlpha = 1;
    };
    /** The part of `mask` that faces the light: itself, less itself slid away from it. */
    const facing = (mask, reach) => {
      const a = scratch('a', size, size);
      a.drawImage(mask, 0, 0);
      a.globalCompositeOperation = 'destination-out';
      a.drawImage(mask, -dir.x * reach, -dir.y * reach);
      const c = mk(size, size);
      c.getContext('2d').drawImage(a.canvas, 0, 0, size, size, 0, 0, size, size);
      return c;
    };
    lay(m.leafBack, pal.leafShade);
    lay(m.wood, pal.ink);
    if (pal.litAmt > 0.05) lay(facing(m.wood, 1.1 * s), pal.inkLit, Math.min(1, pal.litAmt));
    if (m.leafFront) {
      lay(m.leafFront, pal.leaf);
      if (pal.litAmt > 0.05) lay(facing(m.leafFront, 3.2 * s), pal.leafLit, Math.min(1, pal.litAmt));
    }
    lay(m.lastLeaves, pal.lastLeaf);
    lay(m.blossomB, pal.blossomShade);
    lay(m.blossomA, pal.blossom);
    lay(m.frost, pal.frost, 0.8);
    lay(m.snow, pal.snow);
  }

  // ── stars ────────────────────────────────────────────────────────────

  let starSprites = null;
  function buildStarSprites(s) {
    const tints = { cool: K(0.93, 0.035, 255), plain: K(0.99, 0.008, 95), warm: K(0.95, 0.055, 82), tonight: K(0.955, 0.075, 82), ink: K(0.42, 0.05, 285), under: K(0.7, 0.055, 276) };
    const out = { s };
    const size = Math.ceil(26 * s);
    for (const [name, lab] of Object.entries(tints)) {
      const colour = cssLab(lab);
      // hand-set dots: three slightly different dabs, drawn at radius 6 pt
      out[`dot-${name}`] = [0, 1, 2].map((v) => {
        const c = mk(size, size);
        const ctx = c.getContext('2d');
        if (name === 'under') {                 // a soft patch of deeper sky, for stars on a light page
          const g = ctx.createRadialGradient(size / 2, size / 2, 0, size / 2, size / 2, 6 * s);
          g.addColorStop(0, cssLab(lab, 1));
          g.addColorStop(0.45, cssLab(lab, 0.75));
          g.addColorStop(1, cssLab(lab, 0));
          ctx.fillStyle = g;
          ctx.fillRect(0, 0, size, size);
          return c;
        }
        ctx.fillStyle = colour;
        ctx.fill(discPath(size / 2, size / 2, 6 * s, 0.07, v * 2.7 + 1));
        return c;
      });
      // four-point: cut by hand, the arms not quite equal; drawn at arm length 10 pt
      const c = mk(size, size);
      const ctx = c.getContext('2d');
      ctx.translate(size / 2, size / 2);
      ctx.rotate(0.07);
      ctx.fillStyle = colour;
      const arms = [10, 7.4, 9.4, 7.0];
      const waist = 1.25;
      ctx.beginPath();
      for (let i = 0; i < 4; i += 1) {
        const a = -Math.PI / 2 + (i * Math.PI) / 2;
        const b = a + Math.PI / 4;
        ctx.lineTo(Math.cos(a) * arms[i] * s, Math.sin(a) * arms[i] * s);
        ctx.lineTo(Math.cos(b) * waist * s, Math.sin(b) * waist * s);
      }
      ctx.closePath();
      ctx.fill();
      ctx.beginPath();
      ctx.arc(0, 0, 2.1 * s, 0, TAU);
      ctx.fill();
      out[`glint-${name}`] = c;
    }
    // the small things: a soft-edged dab each
    out.life = {};
    const dabs = { leaf: K(0.66, 0.13, 52), petal: K(0.95, 0.045, 355), snow: K(0.98, 0.008, 250), firefly: K(0.95, 0.12, 104), fireflyGlow: K(0.9, 0.13, 100) };
    for (const [name, lab] of Object.entries(dabs)) {
      const c = mk(size, size);
      const ctx = c.getContext('2d');
      if (name === 'fireflyGlow') {
        const g = ctx.createRadialGradient(size / 2, size / 2, 0, size / 2, size / 2, 6 * s);
        g.addColorStop(0, cssLab(lab, 1));
        g.addColorStop(0.5, cssLab(lab, 0.4));
        g.addColorStop(1, cssLab(lab, 0));
        ctx.fillStyle = g;
        ctx.fillRect(0, 0, size, size);
      } else {
        ctx.fillStyle = cssLab(lab);
        ctx.fill(discPath(size / 2, size / 2, 6 * s, name === 'leaf' ? 0.16 : 0.08, 1.9));
      }
      out.life[name] = c;
    }
    return out;
  }

  let starList = { key: '', stars: [] };
  function starsFor(state) {
    const lit = state.asleep === 'night';
    const key = `${state.ageDays}|${lit}|${G.cfg === DUO ? 'duo' : 'slab'}|${G.Wa}`;
    if (starList.key === key) return starList.stars;
    const stars = nights(state.ageDays, { tonightLit: lit }).map((star) => {
      const at = star.kind === 'tonight' ? { x: G.cfg.tonight.x, y: G.cfg.tonight.y } : G.starPlace(star);
      return { ...star, x: at.x, y: at.y };
    });
    // One star per night has to be countable: none on top of another, none in
    // tonight's place. A star that would be takes the nearest free spot — judged
    // only against the nights before it, so its place never depends on a later one.
    const home = G.cfg.tonight;
    const [tx0, ty0, tx1, ty1] = G.cfg.text;
    const apart = 5.2 * G.cfg.starScale + 0.6;
    const free = (x, y, upto) => {
      if (x < 2 || x > G.Wa - 2 || y < G.cfg.starTop || y > G.starFloor(x)) return false;
      if (x > tx0 - 2 && x < tx1 + 2 && y > ty0 - 4 && y < ty1 + 2) return false;
      if (Math.hypot(x - home.x, y - home.y) < 15) return false;
      for (let i = 0; i < upto; i += 1) {
        const gap = stars[i].kind === 'night' ? apart : apart + 4;       // a little more room round a glint
        if (Math.hypot(x - stars[i].x, y - stars[i].y) < gap) return false;
      }
      return true;
    };
    stars.forEach((star, index) => {
      if (star.kind === 'tonight' || free(star.x, star.y, index)) return;
      for (let ring = 1; ring <= 16; ring += 1) {
        for (let k = 0; k < 10; k += 1) {
          const a = (k / 10 + hash(star.night, 31)) * TAU, r = ring * apart * 0.55;
          const x = star.x + Math.cos(a) * r, y = star.y + Math.sin(a) * r * 0.8;
          if (free(x, y, index)) { star.x = x; star.y = y; return; }
        }
      }
    });
    starList = { key, stars };
    return stars;
  }

  function drawStars(state, pal, time, tiltX, tiltY) {
    const s = G.s;
    const out = pal.starsOut;
    const bed = state.event && state.event.kind === 'bedtime' ? state.event.age : null;
    const spark = bed == null ? 1 : ignition(bed);
    const answering = bed != null && bed < 9;
    if (!(out > 0.004) && !(state.asleep === 'night')) return;
    if (!starSprites || starSprites.s !== s) starSprites = buildStarSprites(s);
    const stars = starsFor(state);
    const scale = G.cfg.starScale;
    const still = time == null ? 1 : 1 - 0.6 * pal.depth;       // asleep: the twinkle calms
    const moon = pal.moon;
    const mR = G.cfg.moonR + 5;
    const home = G.cfg.tonight;
    const strength = pal.light ? 0.95 : 1;
    const lead = state.lead == null ? 1 : clamp01(state.lead);
    main.globalCompositeOperation = 'source-over';

    // The ordinary sky of the leading page.
    if (out > 0.01 && G.farStars.length) {
      const sprite = starSprites[`dot-${pal.light ? 'plain' : 'cool'}`][1];
      for (const f of G.farStars) {
        const tw = time == null ? 1 : 0.8 + 0.2 * Math.cos(TAU * (time / f.period + f.phase));
        main.globalAlpha = clamp01(f.a * out * tw * (pal.light ? 0.8 : 0.72) * (f.titled ? 1 - lead : 1));
        if (main.globalAlpha < 0.004) continue;
        const r = f.r * s * scale;
        main.drawImage(sprite, (G.ox + f.x + tiltX) * s - r * 2.17, (f.y + tiltY) * s - r * 2.17, r * 4.34, r * 4.34);
      }
    }

    for (const star of stars) {
      let x = star.x, y = star.y;
      const tonight = star.kind === 'tonight';
      if (moon && !tonight) {
        const dx = x - moon.x, dy = y - moon.y;
        const d = Math.hypot(dx, dy);
        if (d < mR) {
          const a = d < 0.01 ? hash(star.night, 9) * TAU : Math.atan2(dy, dx);
          x = moon.x + Math.cos(a) * mR; y = moon.y + Math.sin(a) * mR;
          if (y < 3) {                                   // not off the top of the page: out to the side instead
            y = Math.max(3, star.y);
            x = moon.x + (dx < 0 ? -1 : 1) * Math.sqrt(Math.max(0, mR * mR - (y - moon.y) * (y - moon.y)));
          }
        }
      }
      const tw = time == null ? 1 : 1 - (1 - twinkle(star, time)) * still;
      let alpha, grow = 1;
      if (tonight) {
        alpha = Math.min(1, spark) * (0.9 + 0.1 * tw);
        grow = bed == null ? 1 : 0.55 + 0.45 * spark;
      } else {
        alpha = (pal.light ? 0.72 + 0.28 * star.magnitude : 0.34 + 0.66 * star.magnitude) * tw * out * strength;
        if (answering) {
          // the others answer: a slow ring of brightness going out from his star
          const dist = Math.hypot(x - home.x, y - home.y);
          const wave = Math.exp(-Math.pow((bed - 1.7 - dist / 210) / 0.5, 2));
          alpha = Math.min(1, alpha * (1 + 0.6 * wave) + 0.5 * wave * (0.4 + 0.6 * star.magnitude) * Math.max(out, 0.55));
          grow = 1 + 0.35 * wave;
        }
      }
      if (!(alpha > 0.004)) continue;
      const tint = pal.light ? 'plain' : tonight ? 'tonight' : star.warmth > 0.3 ? 'warm' : star.warmth < -0.25 ? 'cool' : 'plain';
      const px = (G.ox + x + tiltX) * s, py = (y + tiltY) * s;
      main.globalAlpha = clamp01(alpha);
      if (tonight) {
        // its own small painted halo, then the star
        const breath = time == null ? 1 : 0.9 + 0.1 * Math.cos((TAU * time) / 5.2);
        const flare = spark > 1 ? 1 + (spark - 1) * 1.6 : 1;
        if (pal.light) {
          // on a light page: a little dusk gathered round it, so the cream star shows
          const dusk = starSprites['dot-under'][0];
          const r = 15 * s * scale * grow * breath * flare;
          main.globalAlpha = clamp01(alpha * 0.62);
          main.drawImage(dusk, px - r * 2.17, py - r * 2.17, r * 4.34, r * 4.34);
        } else {
          const halo = starSprites['dot-tonight'][0];
          for (const [radius, a] of [[9.5, 0.1], [5.6, 0.16]]) {
            const r = radius * s * scale * grow * breath * flare;
            main.globalAlpha = clamp01(alpha * a);
            main.drawImage(halo, px - r * 2.17, py - r * 2.17, r * 4.34, r * 4.34);
          }
        }
        main.globalAlpha = clamp01(alpha);
        const g = starSprites[`glint-${pal.light ? 'plain' : 'tonight'}`];
        const half = 13 * s * scale * 1.05 * grow;
        main.drawImage(g, px - half, py - half, half * 2, half * 2);
      } else if (star.kind === 'first' || star.kind === 'month') {
        const g = starSprites[`glint-${tint}`];
        const half = 13 * s * scale * (star.kind === 'first' ? 0.8 : 0.56) * grow;
        main.drawImage(g, px - half, py - half, half * 2, half * 2);
      } else {
        const sprite = starSprites[`dot-${tint}`][star.night % 3];
        const r = (0.62 + 0.95 * star.magnitude) * s * scale * grow * (pal.light ? 1.12 : 1);
        if (pal.light) {
          const under = starSprites['dot-under'][0];
          main.globalAlpha = clamp01(alpha * alpha * 0.5);
          main.drawImage(under, px - r * 5, py - r * 5, r * 10, r * 10);
          main.globalAlpha = clamp01(alpha);
        }
        main.drawImage(sprite, px - r * 2.17, py - r * 2.17, r * 4.34, r * 4.34);
      }
    }
    main.globalAlpha = 1;
  }

  // ── small life: fireflies, a few leaves or petals, snow, a shooting star ──

  const lifeTints = { key: '', canvas: null };

  function drawLife(state, pal, time, px, py) {
    const s = G.s;
    const sea = pal.sea;
    const tr = G.tree;
    const hillIndex = G.cfg.tree.hill;
    const dot = starSprites.life;
    // leaves, petals and snow take the hour's light like everything else
    const relit = { leaf: pal.lastLeaf, petal: pal.blossom, snow: pal.snow };
    const put = (colour, x, y, r, alpha) => {
      if (!(alpha > 0.01)) return;
      let sprite = dot[colour];
      if (relit[colour]) {
        const key = `${colour}|${relit[colour]}`;
        if (lifeTints.key !== key || !lifeTints.canvas) {
          const c = lifeTints.canvas ?? mk(sprite.width, sprite.height);
          const ctx = c.getContext('2d');
          ctx.globalCompositeOperation = 'source-over';
          ctx.clearRect(0, 0, c.width, c.height);
          ctx.drawImage(sprite, 0, 0);
          ctx.globalCompositeOperation = 'source-in';
          ctx.fillStyle = relit[colour];
          ctx.fillRect(0, 0, c.width, c.height);
          lifeTints.canvas = c;
          lifeTints.key = key;
        }
        sprite = lifeTints.canvas;
      }
      main.globalAlpha = clamp01(alpha);
      main.drawImage(sprite, (G.ox + x) * s + px - r * s * 2.17, y * s + py - r * s * 2.17, r * s * 4.34, r * s * 4.34);
    };
    main.globalCompositeOperation = 'source-over';

    // Leaves lying under the tree, and a few on their way down (petals in spring).
    const falling = Math.max(sea.leafFall * (0.35 + 0.65 * sea.foliage), sea.petals * 0.8);
    if (falling > 0.03) {
      const petals = sea.petals * 0.8 > sea.leafFall;
      const colour = petals ? 'petal' : 'leaf';
      const lying = Math.max(4, Math.round(18 * falling));
      for (let i = 0; i < lying; i += 1) {
        const x = tr.x + (hash(i, 101) - 0.42) * tr.h * 1.0;
        const y = G.crestPt(hillIndex, x) + 2 + Math.pow(hash(i, 102), 1.5) * 15;
        put(colour, x, y, 0.55 + 0.6 * hash(i, 103), 0.8);
      }
      const adrift = Math.round(6 * falling);
      for (let i = 0; i < adrift; i += 1) {
        const period = 30 + 16 * hash(i, 104);
        const f = time == null ? hash(i, 105) : (((time / period + hash(i, 105)) % 1) + 1) % 1;
        const x = tr.x + (hash(i, 106) - 0.5) * tr.h * 0.6 + Math.sin(f * 9 + i) * 6 + f * 9;
        const y = tr.baseY - tr.h * 0.62 + f * tr.h * 0.66;
        put(colour, x, y, 1.05, Math.sin(Math.PI * f) * 0.9);
      }
    }

    // Snow in the air, on the days it snows.
    if (sea.snowfall > 0.02) {
      const count = Math.round(70 * sea.snowfall * (G.width / 466));
      for (let i = 0; i < count; i += 1) {
        const period = 70 + 50 * hash(i, 111);
        const f = time == null ? hash(i, 112) : (((time / period + hash(i, 112)) % 1) + 1) % 1;
        const x = -G.ox + hash(i, 113) * G.width + Math.sin(f * 7 + i) * 9;
        put('snow', x, f * (G.height + 10) - 5, 0.7 + 0.8 * hash(i, 114), 0.35 + 0.4 * hash(i, 115));
      }
    }

    // Fireflies beneath the tree on summer evenings, from the last of the sun on.
    const dusk = sea.fireflies * (1 - smoothstep(-2.5, 3.5, pal.sun.alt));
    if (dusk > 0.02) {
      const count = Math.round(14 + 16 * (G.width / 466));
      for (let i = 0; i < count; i += 1) {
        let x, y;
        if (i < 12) {                                    // gathered by the tree
          x = clamp(tr.x - 36 + hash(i, 121) * 100, -G.ox + 4, G.Wa - 5);
          y = i < 3 ? tr.baseY - 6 - hash(i, 122) * 20 : G.crestPt(hillIndex, x) + 4 + hash(i, 122) * 70;
        } else {                                         // and thinly over the land
          x = -G.ox + hash(i, 121) * G.width;
          y = G.skyBottom(x) + 14 + hash(i, 122) * (G.height - G.cfg.horizon) * 0.5;
        }
        const period = 3.6 + 3.2 * hash(i, 123);
        let glow;
        if (time == null) glow = hash(i, 124) < 0.55 ? 0.85 : 0;
        else {
          glow = Math.pow(Math.max(0, Math.sin(TAU * (time / period + hash(i, 124)))), 2.2);
          x += 5 * Math.sin(TAU * (time / 23 + hash(i, 125)));
          y += 3 * Math.sin(TAU * (time / 17 + hash(i, 126)));
        }
        glow *= 1 - 0.4 * pal.depth;
        put('fireflyGlow', x, y, 4.6, glow * dusk * (pal.light ? 0.5 : 0.24));
        put('firefly', x, y, 1.05, glow * dusk);
      }
    }
    main.globalAlpha = 1;
  }

  /** Rarely, and never under Reduce Motion: one shooting star, about a second long. */
  function drawShootingStar(pal, time) {
    if (time == null || pal.starsOut < 0.9 || pal.light) return;
    const cycle = 140;
    const k = Math.floor(time / cycle);
    const tt = time - k * cycle - 61;
    if (tt < 0 || tt > 1.1) return;
    const s = G.s;
    const f = tt / 1.1;
    const x0 = 40 + hash(k, 91) * G.Wa * 0.55, y0 = 26 + hash(k, 92) * (G.cfg.horizon * 0.3);
    const angle = (18 + 16 * hash(k, 93)) * DEG;
    const hx = x0 + Math.cos(angle) * 90 * f, hy = y0 + Math.sin(angle) * 90 * f;
    const tail = 30 * Math.sin(Math.PI * f);
    const tx = hx - Math.cos(angle) * tail, ty = hy - Math.sin(angle) * tail;
    const grad = main.createLinearGradient((G.ox + tx) * s, ty * s, (G.ox + hx) * s, hy * s);
    grad.addColorStop(0, 'rgba(255, 246, 228, 0)');
    grad.addColorStop(1, `rgba(255, 246, 228, ${0.75 * Math.sin(Math.PI * f)})`);
    main.save();
    main.strokeStyle = grad;
    main.lineWidth = 1.1 * s;
    main.lineCap = 'round';
    main.beginPath();
    main.moveTo((G.ox + tx) * s, ty * s);
    main.lineTo((G.ox + hx) * s, hy * s);
    main.stroke();
    main.restore();
  }

  // ── the page's one line of text ──────────────────────────────────────

  /** "Night 143", set like the line at the foot of a picture-book page, while
   *  the cards are away at bedtime. (In the app: a SwiftUI Text, not the sky's.) */
  function drawCaption(state, pal) {
    if (state.asleep !== 'night' || !(state.veil > 0.01)) return;
    const bed = state.event && state.event.kind === 'bedtime' ? state.event.age : null;
    const arrive = bed == null ? 1 : smoothstep(1.3, 2.8, bed);
    const alpha = clamp01(state.veil) * clamp01(state.veil) * arrive;
    if (!(alpha > 0.01)) return;
    const s = G.s;
    const at = G.cfg.caption;
    const x = (G.ox + at.x) * s, y = at.y * s;
    const ink = pal.light ? K(0.42, 0.05, 285) : K(0.86, 0.035, 85);
    main.save();
    main.globalAlpha = alpha * (pal.light ? 0.8 : 0.78);
    main.fillStyle = cssLab(ink);
    // a small four-point star, his, before the words
    if (!starSprites || starSprites.s !== s) starSprites = buildStarSprites(s);
    const g = starSprites[`glint-${pal.light ? 'ink' : 'tonight'}`];
    const k = at.size / 16;
    const half = 13 * s * 0.62 * k;
    main.drawImage(g, x + 6 * s * k - half, y - 5.6 * s * k - half, half * 2, half * 2);
    main.font = `600 ${at.size * s}px Nunito, ui-rounded, system-ui, sans-serif`;
    main.textBaseline = 'alphabetic';
    if ('letterSpacing' in main) main.letterSpacing = `${0.2 * s * k}px`;
    main.fillText(`Night ${Math.max(1, Math.floor(state.ageDays) + 1)}`, x + 18 * s * k, y);
    main.restore();
  }

  // ── a frame ──────────────────────────────────────────────────────────

  let lastState = null;
  function render(state) {
    if (destroyed || !state || !state.sun) return;
    lastState = state;
    const s = Number.isFinite(state.dpr) && state.dpr > 0 ? state.dpr : 1;
    if (!T || T.s !== s) { T = buildTextures(s); keys = {}; G = null; }
    const geoKey = [state.device, state.width, state.height, s, state.phone.x, state.phone.width, Boolean(state.strip)].join('|');
    if (!G || G.key !== geoKey) {
      G = buildGeometry(state);
      G.key = geoKey;
      keys = {};
      canvas.width = G.pxW;
      canvas.height = G.pxH;
      canvas.style.width = `${G.pxW / s}px`;
      canvas.style.height = `${G.pxH / s}px`;
    }
    const pal = resolve(state);
    const time = state.reduceMotion || !Number.isFinite(state.t) ? null : state.t;
    const dir = lampDirection(pal);

    const tilt = state.tilt ?? { x: 0, y: 0 };
    const tx = clamp(tilt.x || 0, -1, 1), ty = clamp(tilt.y || 0, -1, 1);
    const skyTx = -tx * 1.5, skyTy = -ty * 0.8;
    if (!starSprites || starSprites.s !== s) starSprites = buildStarSprites(s);

    // Repaint what changed. (Presence is stepped finely, so a slow settling
    // repaints a few times a second, not every frame.)
    const skyKey = JSON.stringify([pal.sky, pal.anti, pal.glow, pal.rose, pal.glowAmt, pal.sunDisc, pal.halo, pal.haloAmt, pal.bank, pal.bankLit, Math.round(pal.presence * 50),
      Math.round(pal.sun.x * 4), Math.round(pal.sun.y * 4)]);
    let backDirty = false;
    if (keys.sky !== skyKey) { paintSky(pal); keys.sky = skyKey; backDirty = true; }
    let moonKey = 'down';
    if (pal.moon) {
      moonKey = JSON.stringify([pal.light, Math.round(pal.moon.fraction * 200), Math.round(pal.moon.rotation * 60), pal.moon.inDaylight, Math.round(pal.sun.alt * 4),
        pal.light ? 1 : Math.round(clearOfText(pal.moon.x, pal.moon.y, G.cfg.moonR) * 25)]);
      if (G.moon.key !== moonKey) { paintMoon(pal); G.moon.key = moonKey; }
      moonKey += `|${Math.round((pal.moon.x + skyTx) * 8)}|${Math.round((pal.moon.y + skyTy) * 8)}`;
    }
    moonKey += `|${pal.bank}|${pal.bankLit}`;
    if (backDirty || keys.moon !== moonKey) { composeBack(pal, skyTx, skyTy); keys.moon = moonKey; }

    const lightKey = `${Math.round(Math.atan2(dir.y, dir.x) / (2.5 * DEG))}|${pal.lamp.kind}`;
    const sea = pal.sea;
    const seaKey = [sea.foliage, sea.blossom, sea.snow, sea.frost, sea.leafFall].map((v) => Math.round(v * 50)).join('|');
    if (G.tree.masksKey !== seaKey) { G.tree.masks = buildTreeMasks(sea); G.tree.masksKey = seaKey; keys.tree = ''; }
    const treeKey = JSON.stringify([pal.ink, pal.inkLit, pal.leaf, pal.leafShade, pal.leafLit, pal.blossom, pal.blossomShade, pal.snow, pal.frost, pal.lastLeaf,
      lightKey, Math.round(pal.litAmt * 40)]);
    let landDirty = false;
    if (keys.tree !== treeKey) { paintTree(pal, dir); keys.tree = treeKey; landDirty = true; }
    const mistKey = css(pal.mist);
    if (keys.mist !== mistKey) { paintMist(pal); keys.mist = mistKey; landDirty = true; }
    const landKey = JSON.stringify([pal.hills, pal.haze, pal.mistAmt, lightKey, Math.round(pal.litAmt * 40)]);
    if (landDirty || keys.land !== landKey) {
      for (const front of G.fronts) paintFront(front, pal, dir, lightKey);
      keys.land = landKey;
    }
    const cloudAlpha = 1 - 0.92 * pal.starsOut;
    // Clouds drift across the whole WORLD (the spread's, even on the cover), so both windows see the same sky.
    const west = -G.cfg.lead - 100, span = G.cfg.lead + G.Wa + 200;
    const cloudsNow = [];
    if (cloudAlpha > 0.02) {
      for (const cloud of G.clouds) {
        const drift = time == null ? 0 : time * cloud.speed;
        const x = (((cloud.x + drift - west) % span) + span) % span + west;
        if (x + G.ox < -110 || x + G.ox > G.width + 110) continue;       // not in this window now
        const cdx = pal.lamp.x - x, cdy = pal.lamp.y - cloud.y;
        const cLight = `${Math.round(Math.atan2(cdy, cdx) / (5 * DEG))}`;
        const cKey = JSON.stringify([pal.cloud, cLight, Math.round(pal.litAmt * 30)]);
        if (cloud.key !== cKey) { paintCloud(cloud, pal, cLight, x); cloud.key = cKey; }
        cloudsNow.push([cloud, x]);
      }
    }

    // Compose: the back plane, the stars, the clouds, the two planes of land
    // with the moving mist between them, then the small life.
    main.setTransform(1, 0, 0, 1, 0, 0);
    main.globalCompositeOperation = 'source-over';
    main.globalAlpha = 1;
    main.drawImage(G.back, 0, 0);
    drawStars(state, pal, time, skyTx, skyTy);
    drawShootingStar(pal, time);
    for (const [cloud, x] of cloudsNow) {
      main.globalAlpha = cloudAlpha;
      main.drawImage(cloud.canvas, (x + G.ox + skyTx * 0.6) * s - cloud.masks.cx, (cloud.y + skyTy * 0.6) * s - cloud.masks.cy);
    }
    main.globalAlpha = 1;
    G.fronts.forEach((front, i) => {
      const dx = tx * front.depth * 7 * s, dy = ty * front.depth * 3 * s;
      if (i === 1 && pal.mistAmt > 0.01) {
        const mw = G.mist.width, mh = G.mist.height;
        const drift = (time == null ? 0 : time * 0.24) * s + 951;
        main.globalAlpha = pal.mistAmt * 0.45;
        for (let x = -(((drift % mw) + mw) % mw); x < G.pxW; x += mw) main.drawImage(G.mist, x, front.hills[0].mean - mh * 0.78 + dy);
        main.globalAlpha = 1;
      }
      main.drawImage(front.canvas, -G.padPx + dx, front.y0 + dy);
    });
    {
      const d = G.fronts[0].depth;
      drawLife(state, pal, time, tx * d * 7 * s, ty * d * 3 * s);
    }
    drawCaption(state, pal);
  }

  function destroy() {
    destroyed = true;
    G = null; T = null;
    scratchA = null; scratchB = null;
    canvas.remove();
  }

  // The caption's face (the lab's stand-in for SF Rounded) may still be on its way.
  const ready = doc.fonts && doc.fonts.load
    ? doc.fonts.load('600 16px Nunito').then(() => { if (!destroyed && lastState) render(lastState); }, () => {})
    : Promise.resolve();

  return { render, destroy, ready };
}
