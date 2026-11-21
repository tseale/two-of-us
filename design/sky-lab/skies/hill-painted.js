// Hill, painted — picture book's place, standing in true light's air.
//
// One illustrated place: a river valley, the hills between, a knoll and one
// grown tree against the setting sun — drawn as shapes with intention, and lit
// by the real sky: a twilight with its true layers that leans toward the sun,
// every plane of land taking its colour from the horizon sky behind it (lighter
// and bluer with distance), mist lying level in the valleys, a rim of caught
// light on the shoulders that face the sun and a cool shade on the far side,
// clouds lit from where the sun really is.
//
// It is all 2-D canvas, and built to port to SwiftUI as a handful of planes:
//
//   the air      skies/hill-painted/air.js — true-light's twilight table, printed
//                for the appearance and quietened by presence(); the painter
//                samples it (a coarse grid for the sky, a stop every 30 points
//                for a plane of land)
//   the sky      one TALL plane (the everyday view shows its foot; the night's
//                pose looks up into the rest): the field, dithered — the one
//                per-pixel pass, a 30-line shader or a pre-rendered image in the app
//   his stars    sprites on the tall sky, one per night of his life
//   sun, moon    discs with painted haloes, each at ONE place in the world (a
//                high one is above the everyday view); clouds: a few strokes
//                of a flat brush, lit along the edge that faces the light
//   the land     five planes of authored shapes (crest lines set by hand),
//                each painted once a minute: a fill that follows the sky along
//                x, air gathering at its foot, strokes along the crest (shade,
//                light, frost, the rim), the river, the tree
//                (skies/hill-painted/tree.js — grown once from a fixed seed)
//   mist         level bands between the planes, breathing
//   the camera   two poses, rest and looking up: every plane only TRANSLATES
//                (the far ones with the sky, the near ones faster) — nothing is
//                repainted for the move; a change of tone while an event plays
//                (the bloom, the dimmed room) is one colour adjustment on the layers.
//                Looking up is a STATE, not a moment: the view is up for as long as
//                a night sleep runs (bedtime carries it up, waking brings it down)
//
// World coordinates: points, x = 0 at the anchor window's leading edge
// (`state.phone.x`), y = the display's y in the REST pose. The Duo's cover and
// spread share the world exactly, in both poses (measured: the spread's phone
// page is the cover's picture to within 3 levels at every pixel).
//
// The URL's `look=0…1` holds any pose at any hour (the lab does not pass it on:
// it is read from location.search here). `window.__hillPainted` carries the
// render timings and the count of his stars in each pose.

import { presence as bloomOf } from '../lab/presence.js';
import { smoothstep, lerp } from '../lab/oklab.js';
import { nights, twinkle, ignition, hash } from '../lab/nights.js';
import { season as seasonOf } from '../lab/season.js';
import { hash2 } from '../lab/noise.js';
import { airFor, css, toRgb, lch, mix3 } from './hill-painted/air.js';
import { growTree, treeMasks, crownTop } from './hill-painted/tree.js';

export const meta = {
  id: 'hill-painted',
  name: 'Hill, painted',
  blurb: 'Picture book’s place painted in true light’s air: a river valley, a knoll and one grown tree against the setting sun; when he goes down for the night the view looks up into every night of his life, and stays there while he sleeps.',
};

const TAU = Math.PI * 2;
const DEG = Math.PI / 180;
const clamp01 = (x) => Math.min(1, Math.max(0, x));
const clamp = (x, lo, hi) => Math.min(hi, Math.max(lo, x));

// ──────────────────────────────────────────────────────────────── noise ──

const LATTICE = 256;
const lattice = new Float32Array(LATTICE * LATTICE);
for (let y = 0; y < LATTICE; y += 1) for (let x = 0; x < LATTICE; x += 1) lattice[y * LATTICE + x] = hash2(x, y, 23);
/** Smooth value noise, 0–1. */
function vn(x, y) {
  let xi = Math.floor(x), yi = Math.floor(y);
  const fx = x - xi, fy = y - yi;
  xi &= 255; yi &= 255;
  const x1 = (xi + 1) & 255, y1 = (yi + 1) & 255;
  const u = fx * fx * (3 - 2 * fx), v = fy * fy * (3 - 2 * fy);
  const a = lattice[yi * LATTICE + xi], b = lattice[yi * LATTICE + x1];
  const c = lattice[y1 * LATTICE + xi], d = lattice[y1 * LATTICE + x1];
  return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
}
function fb(x, y, octaves = 3) {
  let sum = 0, amp = 0.5, norm = 0;
  for (let o = 0; o < octaves; o += 1) {
    sum += amp * vn(x + o * 17.3, y + o * 9.1);
    norm += amp;
    x *= 2; y *= 2; amp *= 0.5;
  }
  return sum / norm;
}

// ──────────────────────────────────────────────────────────── the place ──
// Every shape of land is a crest line set by hand ([x, y] in rest-pose points),
// far to near. `haze`: how far it has gone into the air (1 = the horizon sky's
// own colour). `soft`: the edge, in points of blur (far is soft, near is cut).
// `base`: where a spur meets the valley floor (omitted: it runs to the foot).
// A plane is the shapes that move together when the camera does. Its `mists` lie just behind it:
// on the valley side a level band on the valley floor ({ y, h, x0, x1 }); on the hill side POOLS
// ({ pools: [[x, half-length, level, strength]…] }) — mist that has run down into the hollow behind
// this plane's crest and lies there with a level, wispy top: thick where the crest dips, gone
// where it rises, uneven in length, broken. (Its foot is the crest in front of it, never a line.)

const DUO = {
  kind: 'duo',
  H0: 292,                 // the horizon at rest
  D: 312,                  // looking up lowers it this far (→ 604)
  T: 90,                   // …and the turn slides the far world this far left: the tree to x 318, its whole crown behind the cards when they are on (never a few twigs past a card's edge). Not more: the moon is then 90 pt from the baseline's x, and tools/measure.mjs only knows a disc for the moon within a fifth of the window (93 pt)
  table: 292,              // points of sky the twilight's eight stops span
  Emax: 500,               // sun and moon: how high the zenith stands over the horizon, in points of the tall sky
  tree: { x: 408, h: 88 },
  tonight: { x: 379, y: 194 },          // tonight's star at rest: above the tree's left shoulder (rest-pose points)
  tonightUp: { x: 412, y: 270 },        // …and looking up: in the strip's clear window, between the status icons and the tab capsule (display points, the anchor window's x)
  firstUp: { x: 262, y: 43 },           // the first night's star, looking up: in the header's clear gap, between his name and the gear
  sunR: 11.5, moonR: 9.5,
  starScale: 1,
  caption: { x: 30, y: 652, size: 15 },
  planes: [
    { id: 'far', sink: 1, slide: 1, tilt: [1.0, 0.5], shapes: [
      { id: 'range', haze: 0.90, soft: 1.5, wob: 0.8, crest: [[-560, 285], [-430, 281], [-330, 285.5], [-250, 289.5], [-170, 285], [-90, 281.5], [20, 285], [120, 288], [200, 284.5], [300, 287.5], [400, 289.5], [520, 286], [660, 287]] },
      { id: 'ridge', haze: 0.76, soft: 1.0, wob: 1.0, crest: [[-560, 289], [-440, 286.5], [-340, 284], [-270, 291], [-235, 294.5], [-190, 290.5], [-110, 287], [-30, 285.5], [60, 289.5], [160, 292.5], [260, 291.5], [340, 289], [430, 292], [520, 290], [660, 288]] },
      { id: 'floor', haze: 0.74, hazeNear: 0.44, soft: 0.8, wob: 0.5, floor: true, crest: [[-560, 299], [-400, 300], [-250, 301], [-100, 301.5], [100, 302]] },
      { id: 'l1', haze: 0.64, soft: 0.8, wob: 1.0, foot: 7, crest: [[-560, 289], [-460, 290.5], [-380, 294], [-310, 299], [-262, 303.5]], base: [[-256, 306], [-340, 310], [-440, 314], [-560, 318]] },
      { id: 'r1', haze: 0.60, soft: 0.8, wob: 1.0, foot: 7, crest: [[-220, 304.5], [-170, 299], [-110, 293.5], [-40, 290], [40, 289], [150, 292]], base: [[150, 312], [40, 314], [-60, 316], [-150, 314], [-224, 308]] },
      { mist: { y: 300, h: 15, x0: -440, x1: -60, amt: 0.9, seed: 1 } },
      { id: 'l2', haze: 0.50, soft: 0.6, wob: 1.2, foot: 16, crest: [[-560, 296], [-470, 299], [-400, 304], [-330, 311], [-264, 317.5]], base: [[-256, 322], [-350, 330], [-450, 338], [-560, 346]] },
    ] },
    { id: 'mid', sink: 1, slide: 1, tilt: [2.0, 0.9], mists: [{ y: 320, h: 28, x0: -540, x1: -110, amt: 0.9, seed: 2, valley: true }], shapes: [
      { id: 'hill', haze: 0.46, soft: 0.5, wob: 1.6, rim: 0.8, foot: 80, crest: [[-216, 339], [-170, 328], [-120, 316], [-60, 306], [10, 298.5], [90, 290.5], [170, 285], [240, 287], [310, 295], [370, 302], [450, 307], [540, 311], [660, 314]], base: [[660, 760], [60, 760], [-10, 600], [-70, 500], [-125, 430], [-175, 378], [-212, 346]] },
      { id: 'l3', haze: 0.34, soft: 0.4, wob: 1.6, rim: 0.4, foot: 30, crest: [[-560, 316], [-500, 326], [-452, 341], [-418, 357], [-394, 372]], base: [[-384, 380], [-440, 398], [-500, 420], [-560, 446]] },
    ] },
    { id: 'knoll', sink: 1, slide: 1, tilt: [3.0, 1.3], mists: [{ y: 376, h: 36, x0: -580, x1: -90, amt: 0.75, seed: 3, valley: true },
      { pools: [[236, 82, 331, 1], [20, 120, 352, 0.55]], amt: 0.85, seed: 4 }], shapes: [
      { id: 'knoll', haze: 0.25, soft: 0, wob: 1.0, rim: 1, grass: 1, tree: true, foot: 60, crest: [[-150, 452], [-60, 428], [20, 418], [90, 413], [150, 406], [200, 396], [240, 382], [272, 364], [300, 344], [330, 322], [360, 305.5], [385, 298.6], [408, 296.5], [430, 298.2], [456, 305], [486, 318], [520, 335], [570, 356], [660, 384]], base: [[660, 760], [-100, 760], [-150, 455]] },
    ] },
    { id: 'near', sink: 1.12, slide: 1.1, tilt: [5.0, 2.0], mists: [{ pools: [[306, 100, 335, 1], [468, 96, 333, 1], [96, 110, 361, 0.6], [620, 60, 350, 0.7]], amt: 1, seed: 5 }], shapes: [
      { id: 'near', haze: 0.14, soft: 0, wob: 2.0, rim: 0.3, grass: 0.8, foot: 70, crest: [[-194, 441], [-150, 425], [-90, 404], [-20, 388], [60, 377], [140, 372], [230, 366], [320, 359], [400, 356], [470, 361], [540, 375], [660, 398]], base: [[660, 760], [40, 760], [-30, 650], [-95, 560], [-150, 495], [-190, 448]] },
    ] },
    { id: 'fore', sink: 1.3, slide: 1.25, tilt: [8.0, 3.0], mists: [{ pools: [[392, 150, 440, 0.8], [110, 210, 488, 0.6], [-170, 100, 560, 0.45], [640, 70, 470, 0.7]], amt: 0.85, seed: 6 },
      { y: 498, h: 46, x0: -620, x1: -300, amt: 0.7, seed: 7, valley: true }], shapes: [
      { id: 'fore', haze: 0.05, soft: 0, wob: 2.4, rim: 0.2, grass: 1.2, crest: [[-392, 760], [-372, 700], [-338, 662], [-270, 628], [-170, 598], [-70, 574], [30, 548], [130, 520], [230, 496], [320, 478], [390, 470], [460, 474], [540, 488], [660, 512]] },
    ] },
  ],
  // The river, seen from the hill: its centre line in the picture, far to near. Its WIDTH is not
  // drawn — the line is laid on the valley floor (a ground plane whose vanishing line is the
  // horizon, `f` the focal length in points) and a river `width` camera-heights wide is projected
  // back, so a far reach running across the view is a level sliver of light, a bend seen end-on
  // shows its whole width, and the near reach opens to a hundred points. The far meanders are
  // tighter and flatter by the same rule (each bend about 1.3× as far below the horizon as the last).
  // `mist`: pools lying on the far reaches [x, y, half-length, half-height, amount] — the river
  // goes into them and comes out again.
  river: {
    vx: -240, f: 520, width: 0.262, minHalf: 0.42,
    line: [[-240, 301.6], [-229.5, 303.3], [-249, 305.5], [-223, 308.5], [-257, 312.4], [-178, 319.2], [-268, 330], [-231, 346], [-350, 367], [-263, 399],
      [-330, 432], [-400, 462], [-449, 502], [-440, 548], [-417, 598], [-440, 652], [-466, 714]],
    mist: [[-243, 302.4, 22, 1.8, 1], [-217, 306.9, 17, 1.7, 0.85], [-243, 310.4, 15, 1.8, 0.9], [-212, 316.6, 27, 2.6, 1], [-246, 326.2, 19, 2.9, 0.9], [-243, 339.5, 24, 3.6, 0.7], [-300, 358, 32, 4.8, 0.62], [-300, 384, 36, 6, 0.36],
      [-286, 411, 46, 7.5, 0.5], [-372, 444, 50, 9.5, 0.42]],
  },
  // Clouds: a few designed forms, each in a designed place (the middle of the lane it drifts along)
  // and all clear of the header's words. `e`: its flat base, points over the horizon; `rise`: its
  // tallest lobe; `lobes`: [centre as a fraction of its length, half-width and height as fractions
  // of `rise`], back to front — the tall ones behind, the small ones in front and lower, so the top
  // is a run of unequal scallops that falls away to a thin foot at both ends. Four in the everyday
  // view — the bank over the tree, a small one in the header's clear gap, one over the fold gutter
  // (the one clear place on the leading page's frieze), a long bank over the valley — and three
  // higher up, for the evenings the camera looks up before dark.
  clouds: [
    // (each its own silhouette — none is the same hat at another width: the bank leans toward the
    // sunset with a long tail behind it, the gap's is a small two-headed puff, the frieze's is the
    // large one — three unequal masses over the clear stretch between the leading page's title and
    // the fold — and the valley's is a long low bank with two humps)
    { id: 'bank', x: 420, e: 110, len: 104, rise: 13.5, span: 64, period: 2400, phase: 0.42,
      lobes: [[0.17, 1.2, 1], [0.0, 1.1, 0.74], [0.31, 0.8, 0.6], [-0.17, 1.0, 0.5], [-0.31, 0.7, 0.3], [0.4, 0.45, 0.3], [0.09, 0.8, 0.5]] },
    { id: 'gap', x: 262, e: 236, len: 60, rise: 12.5, span: 26, period: 2800, phase: 0.5,
      lobes: [[-0.13, 1.0, 1], [0.1, 0.95, 0.66], [0.28, 0.6, 0.4], [-0.31, 0.55, 0.42], [-0.02, 0.7, 0.5]] },
    { id: 'frieze', x: -68, e: 239, len: 128, rise: 22, span: 14, period: 3000, phase: 0.5,
      lobes: [[-0.19, 0.95, 0.74], [0.04, 1.1, 1], [0.22, 0.9, 0.66], [-0.33, 0.62, 0.44], [0.34, 0.6, 0.4], [0.12, 0.72, 0.52], [-0.09, 0.7, 0.5], [0.43, 0.34, 0.2], [-0.43, 0.34, 0.2]] },
    { id: 'valley', x: -322, e: 124, len: 200, rise: 17, span: 120, period: 2600, phase: 0.48,
      lobes: [[-0.21, 1.3, 1], [-0.08, 1.1, 0.66], [0.15, 1.2, 0.82], [0.29, 0.9, 0.48], [-0.35, 0.8, 0.4], [0.39, 0.6, 0.26], [0.03, 0.9, 0.46]] },
    { id: 'up1', x: 176, e: 372, len: 150, rise: 18, span: 110, period: 3000, phase: 0.45, high: true,
      lobes: [[0.12, 1.25, 1], [-0.06, 1.05, 0.7], [0.27, 0.9, 0.6], [-0.22, 0.95, 0.46], [-0.36, 0.6, 0.26], [0.38, 0.5, 0.3]] },
    { id: 'up2', x: 396, e: 462, len: 100, rise: 13, span: 90, period: 3300, phase: 0.55, high: true,
      lobes: [[-0.14, 1.2, 1], [0.08, 1.0, 0.64], [0.26, 0.7, 0.4], [-0.32, 0.6, 0.36]] },
    { id: 'up3', x: -300, e: 410, len: 184, rise: 20, span: 130, period: 3100, phase: 0.5, high: true,
      lobes: [[-0.24, 1.1, 0.8], [-0.07, 1.25, 1], [0.13, 1.0, 0.62], [0.28, 0.95, 0.5], [-0.37, 0.7, 0.36], [0.4, 0.5, 0.24], [0.02, 0.8, 0.5]] },
  ],
};

const SLAB = {
  kind: 'slab',
  H0: 140,
  D: 630,                  // → 770, just above the floating capsule
  T: 30,
  table: 146,
  Emax: 620,
  tree: { x: 286, h: 62 },
  tonight: { x: 262, y: 66 },
  tonightUp: { x: 270, y: 100 },        // looking up: in the header band, in the gap between his name and the gear
  sunR: 9, moonR: 8,
  starScale: 0.9,
  caption: { x: 26, y: 774, size: 15 },
  planes: [
    { id: 'far', sink: 1, slide: 1, tilt: [1.0, 0.5], shapes: [
      { id: 'range', haze: 0.90, soft: 1.2, wob: 0.7, crest: [[-60, 131], [40, 128.5], [120, 131.5], [200, 133], [280, 130], [350, 132.5], [420, 129.5], [560, 132]] },
      { id: 'ridge', haze: 0.74, soft: 0.8, wob: 0.8, crest: [[-60, 134], [60, 132], [150, 135], [240, 136.5], [330, 133.5], [400, 135.5], [560, 132.5]] },
    ] },
    { id: 'mid', sink: 1, slide: 1, tilt: [2.0, 0.9], shapes: [
      // (its shoulder carries on past the end of the age line before it falls to the knoll: the whole line sits on the hill, the crest never runs through it)
      { id: 'hill', haze: 0.42, hazeLight: 0.86, soft: 0.4, wob: 1.1, rim: 0.8, crest: [[-60, 116], [10, 106], [60, 101], [110, 101], [160, 103.5], [197, 109.5], [229, 120], [258, 130], [290, 137], [330, 142], [400, 147], [560, 152]] },
    ] },
    { id: 'knoll', sink: 1, slide: 1, tilt: [3.0, 1.3], mists: [{ y: 138, h: 15, x0: 150, x1: 560, amt: 0.7, seed: 4 }], shapes: [
      { id: 'knoll', haze: 0.22, soft: 0, wob: 0.8, rim: 1, grass: 0.8, tree: true, crest: [[150, 190], [200, 162], [228, 148], [252, 139], [272, 133.5], [286, 132], [300, 133.5], [318, 138.5], [345, 148], [380, 160], [420, 172], [560, 196]], base: [[560, 900], [140, 900]] },
    ] },
    { id: 'near', sink: 1.1, slide: 1.1, tilt: [5.0, 2.0], mists: [{ y: 150, h: 22, x0: -60, x1: 560, amt: 0.9, seed: 5 }], shapes: [
      { id: 'near', haze: 0.13, soft: 0, wob: 1.6, rim: 0.6, grass: 0.7, crest: [[-60, 178], [40, 169], [120, 166], [200, 171], [280, 181], [360, 186], [440, 181], [560, 174]] },
    ] },
    { id: 'fore', sink: 1.25, slide: 1.2, tilt: [8.0, 3.0], mists: [{ y: 250, h: 50, x0: -60, x1: 560, amt: 0.8, seed: 6 }], shapes: [
      { id: 'near2', haze: 0.07, soft: 0, wob: 2.2, rim: 0.4, crest: [[-60, 334], [60, 303], [160, 292], [260, 301], [340, 322], [420, 350], [560, 384]] },
      { mist: { y: 470, h: 60, x0: -60, x1: 560, amt: 0.7, seed: 7 } },
      { id: 'near3', haze: 0.03, soft: 0, wob: 2.4, rim: 0.3, grass: 1, crest: [[-60, 566], [60, 524], [160, 507], [260, 514], [340, 541], [420, 577], [560, 612]] },
    ] },
  ],
  river: null,
  clouds: [
    // (none in the everyday view: the header's small landscape has no clear place for one — its one gap holds the tree)
    { id: 'up1', x: 150, e: 330, len: 150, rise: 18, span: 110, period: 3000, phase: 0.45, high: true,
      lobes: [[0.12, 1.25, 1], [-0.06, 1.05, 0.7], [0.27, 0.9, 0.6], [-0.22, 0.95, 0.46], [-0.36, 0.6, 0.26], [0.38, 0.5, 0.3]] },
    { id: 'up2', x: 300, e: 500, len: 110, rise: 14, span: 100, period: 3300, phase: 0.55, high: true,
      lobes: [[-0.14, 1.2, 1], [0.08, 1.0, 0.64], [0.26, 0.7, 0.4], [-0.32, 0.6, 0.36]] },
  ],
};

const NIGHT_MIST = 0.198;   // OKLab L of mist in the dark appearance at night (luminance 0.0078; a card is 0.0117)
const NIGHT_WATER = 0.196;  // …and of the river there: the faintest line of reflected sky (luminance 0.0076), whatever the room's depth
const PADL = 34;          // points of world beyond the display's leading edge (tilt, the near planes' slide)
const PADR = 44;

// ─────────────────────────────────────────────────────────────── module ──

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

  const TREE = growTree();
  let destroyed = false;
  let G = null;            // geometry + planes for the current display
  let X = null;            // textures for the current dpr
  let keys = {};
  const timing = { first: null, last: 0, repaint: 0, frames: 0 };

  const timingFlush = /[?&]hpTiming=1/.test(globalThis.location?.search ?? '');
  // The URL's own overrides (the lab does not pass these on): look=0…1.
  const urlLook = (() => {
    try {
      const v = new URLSearchParams(globalThis.location?.search ?? '').get('look');
      if (v == null || v === '') return null;
      const n = Number(v);
      return Number.isFinite(n) ? clamp01(n) : null;
    } catch { return null; }
  })();

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
    // Grain: fine, at the device pixel — white or black at a few levels of alpha.
    const GS = 512;
    const grain = imageCanvas(GS, GS, (d) => {
      for (let y = 0; y < GS; y += 1) {
        for (let x = 0; x < GS; x += 1) {
          const n = (hash2(x, y, 3) + hash2(x + 7, y + 3, 5) + hash2(x, y, 9)) / 3 - 0.5;
          const i = (y * GS + x) * 4;
          const v = n > 0 ? 255 : 0;
          d[i] = v; d[i + 1] = v; d[i + 2] = v;
          d[i + 3] = Math.min(255, Math.abs(n) * 2 * 26);
        }
      }
    });
    // Mottle: the paint's own unevenness, broad and low — for the land.
    const MS = 512;
    const mottle = imageCanvas(MS, MS, (d) => {
      for (let y = 0; y < MS; y += 1) {
        for (let x = 0; x < MS; x += 1) {
          const n = fb(x / 46, y / 17, 3) * 0.7 + vn(x / 5.5, y / 2.6) * 0.3 - 0.5;
          const i = (y * MS + x) * 4;
          const v = n > 0 ? 255 : 0;
          d[i] = v; d[i + 1] = v; d[i + 2] = v;
          d[i + 3] = Math.min(255, Math.abs(n) * 2 * 60);
        }
      }
    });
    // Mist: a level band — a soft foot, a top edge that feathers into wisps.
    const TW = 2048, TH = Math.ceil(48 * s);
    const mist = imageCanvas(TW, TH, (d) => {
      for (let y = 0; y < TH; y += 1) {
        const f = y / (TH - 1);                           // 0 top … 1 foot
        const foot = Math.pow(1 - smoothstep(0.42, 1, f), 1.3);
        for (let x = 0; x < TW; x += 1) {
          const n = fb(x / 170, f * 0.9 + 2.3, 3);
          const fine = vn(x / 37, f * 3 + 9.1);
          const top = 0.06 + 0.46 * n + 0.09 * (fine - 0.5);     // where the band begins, in f
          const rise = smoothstep(top - 0.10, top + 0.30, f);
          const i = (y * TW + x) * 4;
          d[i] = 255; d[i + 1] = 255; d[i + 2] = 255;
          d[i + 3] = Math.round(255 * rise * foot * (0.42 + 0.58 * smoothstep(0.2, 0.75, fb(x / 210 + 7, 0.5, 2))));
        }
      }
    });
    // Dry brush: where a loaded brush skips — only the rim light uses it.
    const DS = 256;
    const dry = imageCanvas(DS, DS, (d) => {
      for (let y = 0; y < DS; y += 1) {
        for (let x = 0; x < DS; x += 1) {
          const streak = fb(x / 26, y / 3.2, 3);
          const tooth = vn(x / 2.1, y / 2.1) * 0.6 + hash2(x, y, 5) * 0.4;
          const v = 0.7 * streak + 0.3 * tooth;
          const i = (y * DS + x) * 4;
          d[i] = 255; d[i + 1] = 255; d[i + 2] = 255;
          d[i + 3] = Math.round(255 * smoothstep(0.50, 0.60, v));
        }
      }
    });
    // TPDF dither, one level wide.
    const DN = 1 << 16;
    const dither = new Float32Array(DN);
    for (let i = 0; i < DN; i += 1) dither[i] = (hash2(i, 1, 41) + hash2(i, 2, 43) - 1) * (0.92 / 255);
    return { s, grain, mottle, mist, dry, dither,
      grainPattern: main.createPattern(grain, 'repeat'),
      mottlePattern: main.createPattern(mottle, 'repeat'),
      dryPattern: main.createPattern(dry, 'repeat') };
  }

  const scratches = new Map();
  function scratch(which, w, h) {
    let c = scratches.get(which);
    if (!c || c.width < w || c.height < h) {
      c = mk(Math.max(w, c ? c.width : 0), Math.max(h, c ? c.height : 0));
      scratches.set(which, c);
    }
    const ctx = c.getContext('2d');
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.globalCompositeOperation = 'source-over';
    ctx.globalAlpha = 1;
    ctx.filter = 'none';
    ctx.setLineDash([]);
    ctx.clearRect(0, 0, w, h);
    return ctx;
  }
  /** A white alpha mask, tinted: → scratch B (use at once). */
  function tinted(mask, colour) {
    const ctx = scratch('b', mask.width, mask.height);
    ctx.drawImage(mask, 0, 0);
    ctx.globalCompositeOperation = 'source-in';
    ctx.fillStyle = colour;
    ctx.fillRect(0, 0, mask.width, mask.height);
    return ctx.canvas;
  }

  // ── geometry (once per display) ──────────────────────────────────────

  /** Catmull-Rom through hand-set points, a sample every `step` points of x; the hand's wobble added. */
  function line(points, step, wob, seed) {
    const out = [];
    const P = (i) => points[clamp(i, 0, points.length - 1)];
    for (let k = 0; k < points.length - 1; k += 1) {
      const p0 = P(k - 1), p1 = P(k), p2 = P(k + 1), p3 = P(k + 2);
      const len = Math.hypot(p2[0] - p1[0], p2[1] - p1[1]);
      const n = Math.max(2, Math.ceil(len / step));
      for (let j = k === 0 ? 0 : 1; j <= n; j += 1) {
        const t = j / n, t2 = t * t, t3 = t2 * t;
        const cr = (a, b, c, d) => 0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3);
        const x = cr(p0[0], p1[0], p2[0], p3[0]);
        let y = cr(p0[1], p1[1], p2[1], p3[1]);
        if (wob) y += (fb(x / 70 + seed * 13.7, seed * 3.1 + 0.5, 2) - 0.5) * 2.6 * wob + (vn(x / 11 + seed * 5.3, 7.7) - 0.5) * 0.6 * wob;
        const extra = points[0].length > 2 ? cr(p0[2], p1[2], p2[2], p3[2]) : 0;
        out.push([x, y, extra]);
      }
    }
    return out;
  }

  /** Pooled mist behind a crest: an alpha mask at one sample a point (mist has no detail finer),
   *  → { canvas, x0, y0, w, h } in points, or null where this display sees none of it. */
  function poolMask(sh, band, g) {
    let x0 = Infinity, x1 = -Infinity, top = Infinity;
    for (const [cx, hl, level] of band.pools) { x0 = Math.min(x0, cx - hl); x1 = Math.max(x1, cx + hl); top = Math.min(top, level); }
    x0 = Math.max(Math.floor(x0), Math.ceil(g.xL)); x1 = Math.min(Math.ceil(x1), Math.floor(g.xR));
    if (x1 - x0 < 8) return null;
    let bottom = -Infinity;
    for (let x = x0; x <= x1; x += 4) { const y = sh.at(x); if (Number.isFinite(y)) bottom = Math.max(bottom, y); }
    if (!Number.isFinite(bottom)) return null;
    const y0 = Math.floor(top - 30), y1 = Math.min(Math.ceil(bottom + 8), g.bottom);
    const w = x1 - x0, h = y1 - y0;
    if (h < 4) return null;
    const seed = band.seed;
    const canvas = imageCanvas(w, h, (d) => {
      for (let px = 0; px < w; px += 1) {
        const x = x0 + px + 0.5;
        const crest = sh.at(x);
        if (!Number.isFinite(crest)) continue;
        // uneven along its length, and broken in places
        const uneven = 0.42 + 0.58 * smoothstep(0.28, 0.62, fb(x / 64 + seed * 3.3, 5.5 + seed, 2));
        const slow = (fb(x / 150 + seed * 1.9, seed * 0.7, 2) - 0.5) * 18;
        // (its ends are not ends: they thin out raggedly, a long way)
        const ragged = 0.55 + 0.9 * fb(x / 37 + seed * 5.1, 2.2 + seed, 2);
        // every pool that reaches this far: its own level, and how much of it there is this far along it
        for (const [cx, hl, level, strength] of band.pools) {
          const u = (x - cx) / hl;
          if (Math.abs(u) >= 1) continue;
          const amount = strength * Math.min(1, Math.pow(1 - Math.pow(Math.abs(u), 1.5), 1.7) * lerp(1, ragged, smoothstep(0.25, 0.75, Math.abs(u)))) * uneven;
          const depth = crest - level;                     // how deep the hollow is here, under the pool's top
          if (amount <= 0.004 || depth < -6) continue;
          const shallow = smoothstep(-6, 9, depth);        // it thins out where the land comes up through it
          for (let py = Math.max(0, Math.floor(level - 28 - y0)); py < h; py += 1) {
            const y = y0 + py + 0.5;
            if (y > crest + 7) break;
            const wisp = (fb(x / 40 + seed * 2.2, y / 6.5 + seed, 3) - 0.5) * 14;
            const below = y - (level + slow + wisp);       // points under its top
            if (below < -9) continue;
            // a level top that is soft, not cut; and it is thickest — brightest — low down, where it meets the dark crest in front
            const edge = smoothstep(-9, 15 + 0.22 * Math.max(0, depth), below);
            const body = 0.38 + 0.62 * smoothstep(0, 30, below);
            const grain = 0.72 + 0.28 * fb(x / 90 + seed, y / 18 + seed * 4.1, 2);
            const a = clamp01(amount * shallow * edge * body * grain * 1.42);
            const i = (py * w + px) * 4;
            d[i] = 255; d[i + 1] = 255; d[i + 2] = 255;
            d[i + 3] = Math.round(255 * (1 - (1 - d[i + 3] / 255) * (1 - a)));
          }
        }
      }
    });
    return { canvas, x0, y0, w, h };
  }

  function buildGeometry(state) {
    const s = state.dpr;
    const cfg = state.strip ? DUO : SLAB;
    const ox = state.phone.x;
    const Wa = state.phone.width;
    const W = state.width, H = state.height;
    const xL = -4 * Math.ceil((ox + PADL) / 4);          // the world's left edge on the planes (a multiple of 4: cover and spread sample the same points)
    const xR = W - ox + cfg.T * 1.3 + PADR;
    const g = { cfg, s, ox, Wa, W, H, xL, xR, pxW: Math.ceil(W * s - 1e-6), pxH: Math.ceil(H * s - 1e-6) };
    g.planeW = Math.ceil((xR - xL) * s);
    g.bottom = H + 20;                                   // the planes are painted this far down (rest pose)

    // Shapes: dense crest lines, clipped to the world this display can see.
    let index = 0;
    g.planes = cfg.planes.map((plane) => {
      const shapes = plane.shapes.map((def) => {
        if (def.mist) return { mist: def.mist };
        index += 1;
        const crest = line(def.crest, 2, def.wob ?? 1, index);
        const base = def.base ? line(def.base, 4, 0, index) : null;
        // crest height at any x (for stars, the tree, mist): a lookup per point of x
        const x0 = crest[0][0], x1 = crest[crest.length - 1][0];
        const lut = new Float32Array(Math.max(2, Math.ceil(x1 - x0) + 1)).fill(NaN);
        for (let i = 0; i < crest.length - 1; i += 1) {
          const [ax, ay] = crest[i], [bx, by] = crest[i + 1];
          for (let x = Math.ceil(ax); x <= bx; x += 1) {
            const k = x - Math.round(x0);
            if (k >= 0 && k < lut.length && bx > ax) lut[k] = ay + ((by - ay) * (x - ax)) / (bx - ax);
          }
        }
        const at = (x) => {
          const k = Math.round(x - Math.round(x0));
          return k >= 0 && k < lut.length && !Number.isNaN(lut[k]) ? lut[k] : Infinity;
        };
        // its highest point: in the world (what its washes hang from — the same on every display)
        // and in what this display can see of it (how tall its plane must be)
        let top = Infinity, seenTop = Infinity;
        for (const p of crest) {
          if (p[1] < top) top = p[1];
          if (p[0] >= xL && p[0] <= xR && p[1] < seenTop) seenTop = p[1];
        }
        return { ...def, index, crest, base, at, top, seenTop, x0, x1 };
      }).filter((sh) => sh.mist || Number.isFinite(sh.seenTop));   // not the shapes this display never sees
      let top = Infinity;
      for (const sh of shapes) if (!sh.mist && sh.seenTop < top) top = sh.seenTop;
      const out = { ...plane, shapes, top };
      return out;
    });
    const find = (id) => { for (const p of g.planes) for (const sh of p.shapes) if (sh.id === id) return sh; return null; };
    g.shape = find;
    /** The land's skyline at world x (rest pose): the highest crest of the planes that move with the sky. */
    g.skyline = (x) => {
      let y = Infinity;
      for (const p of g.planes) {
        if (p.sink !== 1) continue;
        for (const sh of p.shapes) if (!sh.mist && !sh.floor) y = Math.min(y, sh.at(x));
      }
      return y;
    };

    // The tree stands on the knoll.
    const knoll = find('knoll');
    g.tree = { x: cfg.tree.x, h: cfg.tree.h, baseY: knoll.at(cfg.tree.x) + 1.2, masks: null, masksKey: '', canvas: null };

    // The tall sky: from under the horizon up to the top of the looked-up view.
    g.skyTop = -(cfg.D + 26);                            // rest-pose y of the sky plane's top edge
    g.skyBot = cfg.H0 + 30;
    g.sky = mk(g.planeW, Math.ceil((g.skyBot - g.skyTop) * s));
    g.skyCtx = g.sky.getContext('2d');

    // The planes' canvases.
    for (const plane of g.planes) {
      // (a multiple of 4 points: the washes are laid at a quarter of the size, and must fall on the same pixels on every display)
      plane.y0 = 4 * Math.floor((plane.top - (plane.id === 'knoll' ? cfg.tree.h * 1.06 : 6)) / 4);
      plane.canvas = mk(g.planeW, Math.ceil((g.bottom - plane.y0) * s));
      plane.ctx = plane.canvas.getContext('2d');
      plane.mistCanvases = (plane.mists ?? []).map(() => null);
      const crestOf = plane.shapes.find((sh) => !sh.mist);
      plane.mistMasks = (plane.mists ?? []).map((band) => (band.pools ? poolMask(crestOf, band, g) : null));
    }

    g.clouds = cfg.clouds.map((c) => ({ ...c, key: '', canvas: null }));
    g.moon = { key: '', canvas: null };
    g.stars = { key: '', list: [], far: [] };
    return g;
  }

  // ── the camera ───────────────────────────────────────────────────────

  /** How far the camera has looked up, 0 rest … 1 up. Looking up is a STATE: while a night sleep runs
   *  the view is up, and still. Events only carry it there and back — bedtime (0 until 0.3 s, up by
   *  2.4 s, and it stays), a re-settle the same night (up over 2.5 s, quietly), waking (down over
   *  about 3 s, behind the cards). Naps keep the rest pose. The URL's `look=` holds any pose. */
  function lookOf(state) {
    if (urlLook != null) return urlLook;
    const e = state.event;
    const a = e ? e.age : 0;
    const ease = (t) => t * t * t * (t * (t * 6 - 15) + 10);
    if (state.asleep === 'night') {
      if (e && e.kind === 'bedtime') return a <= 0.3 ? 0 : a < 2.4 ? ease((a - 0.3) / 2.1) : 1;
      if (e && e.kind === 'resettle') return a < 2.5 ? ease(a / 2.5) : 1;
      return 1;
    }
    // Waking: only a night's sleep leaves the view up. (The lab does not say which sleep ended; its
    // `wake` is the sample day's morning one, so a wake in the nap hours of the day is taken for a nap's.)
    if (e && e.kind === 'wake' && !state.asleep && !(state.localHour >= 9 && state.localHour < 18)) {
      return a <= 0.2 ? 1 : a < 3.2 ? 1 - ease((a - 0.2) / 3.0) : 0;
    }
    return 0;
  }

  /** Tonight's star has two homes on the display — above the tree's shoulder at rest, in the clear
   *  window looking up — and goes from one to the other with the camera, so it is still wherever the
   *  view comes to rest. Display points. */
  function tonightHome(look, tilt) {
    const c = G.cfg;
    const knoll = G.planes.find((p) => p.id === 'knoll');
    const rest = planeOffset(knoll, 0, tilt);
    const rx = G.ox + c.tonight.x + rest.x, ry = c.tonight.y + rest.y;
    const ux = G.ox + c.tonightUp.x + tilt.x * SKYPLANE.tilt[0], uy = c.tonightUp.y + tilt.y * SKYPLANE.tilt[1];
    return { x: rx + (ux - rx) * look, y: ry + (uy - ry) * look };
  }

  /** Where a plane's rest-pose picture sits on the display for this pose: an offset in points. */
  function planeOffset(plane, look, tilt) {
    const c = G.cfg;
    return {
      x: -c.T * plane.slide * look + tilt.x * plane.tilt[0],
      y: c.D * plane.sink * look + tilt.y * plane.tilt[1],
    };
  }
  const SKYPLANE = { slide: 1, sink: 1, tilt: [-1.2, -0.6] };

  // ── where the lights are ─────────────────────────────────────────────

  /** A body's height over the horizon in points of the TALL sky: its real altitude, opened out near
   *  the horizon (the last degrees of a sunset are the ones worth seeing) and easing toward the zenith. */
  function bodyE(altDeg) {
    if (altDeg < 0) return 8.5 * altDeg;
    return G.cfg.Emax * (1 - Math.exp(-altDeg / 45)) + 12 * (1 - Math.exp(-altDeg / 2.5));
  }

  /** Where a body is on the display (points, before tilt). The sun and the moon have ONE place in the
   *  world — a high one is above the top of the everyday view and comes down into view with the sky
   *  when the camera looks up. `seen`: they are never drawn behind the header (Duo: the whole band;
   *  slab: the status bar), so a body crossing it is out of sight until it is clear. */
  function bodyAt(state, xFrac, altDeg, R, look) {
    const c = G.cfg;
    const E = bodyE(altDeg);
    const y = c.H0 - E + c.D * look;
    const foot = c.kind === 'duo' ? (state.layout?.firstCardTop ?? 88.6) + R - 3 : 58;
    return { x: xFrac * G.Wa - c.T * look, y, E, seen: smoothstep(foot, foot + 15, y) };
  }

  // ── the palette for this minute ──────────────────────────────────────

  /** The land's own colours for the season, as daylight albedo [L, C, h°] (true-light's). */
  function seasonLand(sn) {
    const mixLch = (a, b, t) => {
      const m = mix3(lch(...a), lch(...b), clamp01(t));
      return [m[0], Math.hypot(m[1], m[2]), Math.atan2(m[2], m[1]) / DEG];
    };
    const w = sn.weights;
    const green = mixLch(mixLch([0.50, 0.06, 112], [0.60, 0.085, 128], w.spring / Math.max(1e-6, w.spring + w.autumn + w.winter) || 0), [0.44, 0.075, 140], w.summer);
    let ground = mixLch([0.47, 0.036, 76], green, sn.grass);
    ground = mixLch(ground, [0.50, 0.06, 70], 0.5 * w.autumn * (1 - sn.grass * 0.5));
    return { ground, snow: [0.94, 0.012, 255], frost: [0.80, 0.014, 240] };
  }

  /** The leaf's own colour for the season, as daylight albedo [L, C, h°]. A crown is not one paint:
   *  `variant` 0 is its body, 1 the lighter, yellower leaf (gold, in autumn), 2 the deeper one (russet),
   *  3 the far side of the crown — cooler and darker. */
  function leafLocal(hue, variant = 0) {
    const stops = [[0, [0.70, 0.12, 128]], [0.5, [0.50, 0.10, 141]], [0.8, [0.70, 0.13, 78]], [1, [0.56, 0.12, 46]]];
    let base = stops[stops.length - 1][1];
    for (let i = 0; i < stops.length - 1; i += 1) {
      if (hue <= stops[i + 1][0]) {
        const t = (hue - stops[i][0]) / (stops[i + 1][0] - stops[i][0]);
        const a = stops[i][1], b = stops[i + 1][1];
        base = [lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t)];
        break;
      }
    }
    if (!variant) return base;
    const green = smoothstep(92, 116, base[2]);          // 1 a green leaf … 0 a turned one
    if (variant === 1) return [base[0] + 0.04, base[1] * 1.06, base[2] + lerp(9, -10, green)];
    if (variant === 2) return [base[0] - 0.04, base[1] * 0.97, base[2] + lerp(-12, 9, green)];
    return [base[0] - 0.15, base[1] * 0.72, base[2] + lerp(-24, 17, green)];
  }

  function resolve(state, look) {
    const c = G.cfg;
    const dark = state.scheme !== 'light';
    let B = bloomOf(state);
    // Waking reverses bedtime: at the instant he wakes the room is still as it was while he slept —
    // dimmed — and it un-dims over the next five seconds, as tonight's star cools and goes out.
    if (state.event && state.event.kind === 'wake' && state.asleep !== 'night') {
      const still = 1 - smoothstep(0.3, 5.0, state.event.age);
      if (still > B.depth) B = { ...B, depth: still };
    }
    const altDeg = state.sun.altitude / DEG;
    const morning = state.sun.isNight ? state.sun.progress > 0.5 : state.sun.progress < 0.5;
    const sea = seasonOf(state);
    const moon = state.moon;
    const nightness = 1 - smoothstep(-13, -8, altDeg);
    const moonUp = moon ? smoothstep(-1.5, 2.5, moon.altitude / DEG) : 0;
    const moonlight = moon ? moonUp * (0.2 + 0.8 * moon.fraction) * nightness : 0;
    const air = airFor({ altDeg, dark, morning, presence: B.presence, depth: B.depth, moonlight });

    // The sun: the lab's own x (continuous through the night), its real altitude.
    const sunX = state.sun.x * G.Wa;
    const sunRest = bodyAt(state, state.sun.x, altDeg, c.sunR, 0);
    const moonRest = moon ? bodyAt(state, moon.x, moon.altitude / DEG, c.moonR, 0) : null;

    // Which light the land and the clouds answer: the sun until it is well down, then the moon.
    const byMoon = altDeg < -9.5 && moonlight > 0.02;
    const lamp = byMoon
      ? { kind: 'moon', x: moon.x * G.Wa, y: moonRest.y, power: moonlight }
      : { kind: 'sun', x: sunX, y: Math.min(sunRest.y, c.H0 + 30), power: smoothstep(-8, -1, altDeg) };

    const sl = seasonLand(sea);
    // Dark appearance at night stays dark: once the twilight has gone, nothing in the land
    // (mist, water, snow, a moonlit shoulder) is painted lighter than a card.
    const deepNight = dark ? 1 - smoothstep(-10.6, -9.6, altDeg) : 0;
    const NIGHT_CAP = 0.214;
    const shown = (lab, opts) => {
      const q = air.show(lab, opts);
      if (deepNight > 0 && q[0] > NIGHT_CAP) q[0] = lerp(q[0], NIGHT_CAP, deepNight);
      return q;
    };
    const C = (lab, opts) => css(shown(lab, opts));
    const dxSun = (x) => (x - sunX) / G.Wa;
    const dxLamp = (x) => (x - lamp.x) / G.Wa;

    /** An albedo in this hour's light, in this print (true-light's `litLand`). */
    const litLand = (alb, keep = 0.2) => {
      const L = air.land[0] + (alb[0] - 0.47) * air.gain;
      const base = lch(L, alb[1] * (dark ? 0.6 : 0.62) * (keep + (1 - keep) * air.day), alb[2]);
      return [base[0], base[1] + air.land[1] * 0.8, base[2] + air.land[2] * 0.8];
    };
    let ground = litLand(sl.ground, 0.42 + 0.3 * sea.grass);
    // An illustrated place keeps colour in its shadows: through the golden hour and the
    // twilight the dark appearance's land is aubergine, not black. (At night it goes back down.)
    const dusk = smoothstep(-12, -5, altDeg) * (1 - smoothstep(9, 24, altDeg));
    if (dark) ground = [ground[0] + 0.045 * dusk, ground[1] + 0.034 * dusk * Math.cos(318 * DEG), ground[2] + 0.034 * dusk * Math.sin(318 * DEG)];
    else ground = [ground[0] - 0.035 * nightness - 0.02 * dusk, ground[1] + 0.012 * nightness * Math.cos(275 * DEG), ground[2] + 0.012 * nightness * Math.sin(275 * DEG)];
    // Snow in the low key is not the land's own dark with a little white in it: it is the palest
    // thing on the ground, blue-white by the sky's light (and it takes the sky's colour) — from a clear
    // pale by day and at sunset down to the night's own cap. Winter has to be read from the strip.
    const snowDay = smoothstep(-11, 1, altDeg);
    const snowLit = dark
      ? mix3(lch(lerp(0.20, 0.52, snowDay), 0.03, 262), [lerp(0.20, 0.52, snowDay), air.ambient[1], air.ambient[2]], 0.38)
      : litLand(sl.snow);
    const frostLit = litLand(sl.frost);
    ground = mix3(ground, frostLit, 0.34 * sea.frost);
    const snowShade = dark
      ? [snowLit[0] - lerp(0.02, 0.105, snowDay), snowLit[1] + 0.022 * Math.cos(266 * DEG), snowLit[2] + 0.022 * Math.sin(266 * DEG)]
      : [snowLit[0] - 0.05, snowLit[1] + 0.012 * Math.cos(262 * DEG), snowLit[2] + 0.02 * Math.sin(262 * DEG)];
    ground = mix3(ground, snowShade, sea.snow * 0.92);

    const mistAmt = (0.55 + 0.25 * (morning ? 1 : 0) + 0.15 * sea.frost + 0.2 * nightness + 0.25 * moonlight) * (1 - 0.35 * smoothstep(8, 30, altDeg)) * (dark ? 1 : 0.72);

    // The tree: ink, and the season's paints re-lit by the hour.
    // (The light print's tree is not text and not land: a confident warm-dark wood — umber by day,
    // warmer in the low sun, plum-brown at night — and it may be the darkest thing in the picture.)
    const inkL = Math.max(0.045, air.land[0] * 0.62);
    const lowSun = smoothstep(-6, 0, altDeg) * (1 - smoothstep(6, 16, altDeg));
    const ink = dark
      ? [inkL, air.land[1] * 0.9 + 0.012 * Math.cos(330 * DEG) * 0.6, air.land[2] * 0.9 + 0.012 * Math.sin(330 * DEG) * 0.6]
      : mix3(mix3(lch(0.375, 0.040, 58), lch(0.345, 0.055, 42), lowSun), lch(0.37, 0.042, 322), nightness);
    const paint = (alb, lift = 0) => {
      const own = 0.5 + 0.5 * air.day;
      const L = (dark ? air.land[0] + 0.035 : air.land[0] - 0.225) + (alb[0] - 0.47) * (dark ? air.gain * 0.9 : 0.62) + lift;
      const base = lch(L, alb[1] * (dark ? 0.62 : 1.1) * (dark ? 0.35 + 0.65 * own : 0.55 + 0.45 * own), alb[2]);
      const tint = dark ? 0.5 : 0.36;
      return [base[0], base[1] + air.land[1] * tint, base[2] + air.land[2] * tint];
    };
    const leaf = leafLocal(sea.leafHue);

    return {
      dark, B, air, sea, altDeg, morning, nightness, moonlight, look, shown, deepNight,
      sunX, sunRest, moonRest, lamp, byMoon,
      C, dxSun, dxLamp,
      ground, snowLit, snowShade, frostLit, mistAmt,
      ink, inkLit: dark ? mix3([ink[0] + 0.16, ink[1], ink[2]], byMoon ? air.silver : air.rim, 0.5)
        : mix3([ink[0] + 0.15, ink[1] * 1.25, ink[2] * 1.25], byMoon ? air.silver : air.rim, 0.24),
      // (the crown in leaf: the far side cool and dark; the near masses in three paints; their shadowed core; the leaves that catch the lamp)
      leafShade: paint(leafLocal(sea.leafHue, 3), dark ? 0.02 : -0.02),
      leafBody: [paint(leaf, dark ? 0.03 : 0), paint(leafLocal(sea.leafHue, 1), dark ? 0.03 : 0), paint(leafLocal(sea.leafHue, 2), dark ? 0.03 : 0)],
      leafCore: mix3(paint(leafLocal(sea.leafHue, 2), dark ? 0.03 : 0), paint(leafLocal(sea.leafHue, 3), dark ? 0.02 : -0.02), 0.62),
      leafLit: mix3(paint(leafLocal(sea.leafHue, 1), dark ? 0.08 : 0.10), air.rim, 0.25 * air.rimAmt),
      // the leaves that face the open sky take a little of its colour
      leafSky: mix3(paint(leafLocal(sea.leafHue, 1), dark ? 0.085 : 0.07), [air.land[0] + (dark ? 0.12 : 0.02), air.ambient[1], air.ambient[2]], dark ? 0.32 : 0.16),
      // a low sun behind the crown shines through its thin places: the leaf's own colour, lit from within (a turned leaf burns amber, never pale)
      leafGlow: lch(dark ? 0.50 : lerp(0.73, 0.82, smoothstep(92, 116, leaf[2])), dark ? 0.12 : lerp(0.155, 0.125, smoothstep(92, 116, leaf[2])), lerp(leaf[2], 70, 0.45)), backlit: smoothstep(-6, -1, altDeg) * (1 - smoothstep(8, 18, altDeg)),
      blossom: paint([0.93, dark ? 0.10 : 0.06, 357], dark ? 0.15 : 0.05), blossomShade: paint([0.84, dark ? 0.11 : 0.09, 350], dark ? 0.07 : 0),
      blossomLit: mix3(paint([0.95, dark ? 0.07 : 0.075, 28], dark ? 0.20 : 0.045), air.rim, 0.3 * air.rimAmt),
      // (snow on the limbs is a line, not an area: in the low key it keeps a clear pale all evening and a quiet one at night)
      snow: dark ? mix3(lch(lerp(0.30, 0.70, snowDay), 0.022, 258), [lerp(0.30, 0.70, snowDay), air.ambient[1], air.ambient[2]], 0.3) : paint([0.96, 0.012, 250], 0.06),
      frost: paint([0.88, 0.02, 235]),
      lastLeaf: paint([0.64, 0.13, 55], dark ? 0.03 : 0.0),
      starsOut: B.stars,
    };
  }

  // ── the sky ──────────────────────────────────────────────────────────

  /** The sky field: the air sampled on a 2-point grid in OKLab, then laid at the device pixel with dither.
   *  (The one per-pixel pass; in the app, a small shader.) */
  function paintSky(pal) {
    const s = G.s, c = G.cfg, air = pal.air;
    const w = G.sky.width, h = G.sky.height;
    const step = 2;                                      // points between samples
    const gw = Math.ceil(w / (step * s)) + 2, gh = Math.ceil(h / (step * s)) + 2;
    const grid = new Float32Array(gw * gh * 3);
    const lab = new Float32Array(3);
    const sunX = pal.sunX, sunY = pal.sunSkyY;           // rest-pose points
    const glow = air.glow, glowAmt = air.glowAmt;
    const strokes = (air.dark ? 0.011 : 0.007) * (0.45 + 0.55 * air.presence);
    const keepBand = air.dark ? air.night * (1 / (1 - 0.14 * air.depth) - 1) * 0.9 : 0;
    // A sun still a hand above the horizon (a July bedtime, a November mid-afternoon) stands in a wide
    // warm column of its own light: without it the low key's pale disc in a blue sky is a moon.
    // (Nothing of it below 2.5°: the last of the sunset is the table's own, and is left alone.)
    const column = (air.dark ? 0.62 : 0.3) * glowAmt * smoothstep(2.5, 6, pal.altDeg) * (1 - smoothstep(11, 17, pal.altDeg));
    // At night, in the dark appearance: the horizon's light stands a touch higher just behind the
    // tree's crown, and lets go within the strip — the tree has something to be a silhouette against.
    const crownLift = air.dark ? 0.013 * air.night * (1 - 0.8 * air.moonlight) : 0;
    const treeX = c.tree.x, crownE = (c.tree.h * 0.62) / c.table;
    for (let gy = 0; gy < gh; gy += 1) {
      const y = G.skyTop + gy * step;
      const e = (c.H0 - y) / c.table;
      for (let gx = 0; gx < gw; gx += 1) {
        const x = G.xL + gx * step;
        air.skyRaw((x - sunX) / G.Wa, e, lab, 0);
        // The sun's own light in the air around it, hugging the horizon.
        if (glowAmt > 0.004) {
          const rs = Math.hypot(((x - sunX) / c.table) * 0.8, ((y - sunY) / c.table) * 1.2);
          const gl = Math.min(0.92, glowAmt * (0.60 * Math.exp(-rs / 0.27) + 0.45 * Math.exp(-rs / 0.07)));
          lab[0] += (glow[0] - lab[0]) * gl; lab[1] += (glow[1] - lab[1]) * gl; lab[2] += (glow[2] - lab[2]) * gl;
        }
        if (column > 0.004) {
          const rw = Math.hypot(((x - sunX) / c.table) * 0.62, ((y - sunY) / c.table) * 0.5);
          const gl = Math.min(0.8, column * Math.exp(-rw * rw / 0.36) * (0.55 + 0.45 * smoothstep(-0.05, 0.5, e)));
          lab[0] += (glow[0] + 0.02 - lab[0]) * gl; lab[1] += (glow[1] - lab[1]) * gl; lab[2] += (glow[2] - lab[2]) * gl;
        }
        // The hand: long drags of the brush, following the bands.
        const drag = fb(x / 120 + 3.1, y / 9 + (x - sunX) * 0.004 + 1.7, 3) - 0.5;
        const shown = air.show([lab[0] + drag * strokes * (0.5 + 0.5 * smoothstep(-0.1, 0.5, e)), lab[1], lab[2]]);
        // The dimmed room deepens the sky overhead, not the last light along the horizon: at night
        // that band keeps what it had (it is still under a card's own value), so the land and the
        // tree have something to stand against while he sleeps.
        if (keepBand > 0.001) shown[0] += shown[0] * keepBand * Math.exp(-Math.max(0, e) / 0.3);
        if (crownLift > 0) {
          const ux = (x - treeX) / (c.tree.h * 0.95), ue = (Math.max(0, e) - crownE * 0.72) / (crownE * 0.55);
          shown[0] += crownLift * Math.exp(-ux * ux - ue * ue);
        }
        const rgb = toRgb(shown);
        const i = (gy * gw + gx) * 3;
        grid[i] = rgb[0]; grid[i + 1] = rgb[1]; grid[i + 2] = rgb[2];
      }
    }
    // Bilinear up to the device pixel, a triangular dither of one level.
    const img = G.skyCtx.createImageData(w, h);
    const d = img.data;
    const dn = X.dither, dnMask = dn.length - 1;
    const row = new Float32Array(gw * 3);
    const inv = 1 / (step * s);
    for (let py = 0; py < h; py += 1) {
      const fy = py * inv;
      const gy = Math.min(gh - 2, Math.floor(fy));
      const ky = fy - gy;
      const a = gy * gw * 3, b = (gy + 1) * gw * 3;
      for (let k = 0; k < gw * 3; k += 1) row[k] = grid[a + k] + (grid[b + k] - grid[a + k]) * ky;
      let o = py * w * 4;
      let seed = ((Math.imul(py, 0x9e3779b1) >>> 7) + Math.round(G.xL * s)) & dnMask;
      for (let px = 0; px < w; px += 1) {
        const fx = px * inv;
        const gx = Math.floor(fx);
        const kx = fx - gx;
        const i = gx * 3;
        seed = (seed + 1) & dnMask;
        const n = dn[seed];
        d[o] = (row[i] + (row[i + 3] - row[i]) * kx + n) * 255 + 0.5;
        d[o + 1] = (row[i + 1] + (row[i + 4] - row[i + 1]) * kx + dn[(seed + 21013) & dnMask]) * 255 + 0.5;
        d[o + 2] = (row[i + 2] + (row[i + 5] - row[i + 2]) * kx + dn[(seed + 40507) & dnMask]) * 255 + 0.5;
        d[o + 3] = 255;
        o += 4;
      }
    }
    G.skyCtx.putImageData(img, 0, 0);
  }

  function discPath(cx, cy, r, wobble, seed) {
    const path = new Path2D();
    const steps = 64;
    for (let i = 0; i <= steps; i += 1) {
      const a = (i / steps) * TAU;
      const rr = r * (1 + wobble * (Math.sin(2 * a + seed) * 0.6 + Math.sin(3 * a + seed * 2.3) * 0.4 + Math.sin(5 * a + seed * 4.1) * 0.25));
      const x = cx + rr * Math.cos(a), y = cy + rr * Math.sin(a);
      if (i === 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    path.closePath();
    return path;
  }

  /** 0 on the header's words, 1 once a disc of radius `r` at display (x, y) is clear of them. */
  function clearOfText(state, x, y, r) {
    const L = state.layout;
    if (!L) return 1;
    let clear = 1;
    for (const box of [L.name, L.age, L.title, L.subtitle]) {
      if (!box) continue;
      const dx = Math.max(box.x - x, 0, x - (box.x + box.width)), dy = Math.max(box.y - y, 0, y - (box.y + box.height));
      clear = Math.min(clear, smoothstep(r - 2, r + 9, Math.hypot(dx, dy)));
    }
    return clear;
  }

  /** 0 while any of a disc of radius `r` at display (x, y) lies behind the avatar or the gear button,
   *  1 once it is clear of both: a disc is never shown bitten by a button's rim (its glow stays). */
  function clearOfButtons(state, x, y, r) {
    const L = state.layout;
    if (!L) return 1;
    let clear = 1;
    for (const box of [L.avatar, L.gear]) {
      if (!box) continue;
      const d = Math.hypot(x - (box.x + box.width / 2), y - (box.y + box.height / 2)) - box.width / 2 - r;
      clear = Math.min(clear, smoothstep(-0.5, 3.5, d));
    }
    return clear;
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

  /** The moon, painted: the whole disc barely there, the lit part in cream with one thin wash. */
  function paintMoon(state, pal, clear) {
    const m = state.moon;
    const s = G.s;
    const R = G.cfg.moonR * s;
    const size = Math.ceil(R * 3) * 2;
    if (!G.moon.canvas || G.moon.canvas.width !== size) G.moon.canvas = mk(size, size);
    const ctx = G.moon.canvas.getContext('2d');
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.globalAlpha = 1;
    ctx.globalCompositeOperation = 'source-over';
    ctx.clearRect(0, 0, size, size);
    const c = size / 2;
    const night = 1 - smoothstep(-6, -1, pal.altDeg);
    const low = 1 - smoothstep(2, 14, m.altitude / DEG);   // a low moon is warmer and a little dimmer
    const full = pal.dark ? lch(0.925 - 0.05 * low, 0.03 + 0.03 * low, 86 - 10 * low) : lch(0.992 - 0.015 * low, 0.014 + 0.03 * low, 88 - 14 * low);
    const cream = pal.dark ? mix3(lch(0.34, 0.03, 290), full, clear) : full;
    const whole = discPath(c, c, R, 0.012, 2.2);
    const shine = smoothstep(0.03, 0.3, m.fraction);
    ctx.fillStyle = css(pal.dark ? lch(0.27, 0.045, 272) : lch(0.90, 0.03, 275), (pal.dark ? 0.42 : 0.35) * night * shine);
    ctx.fill(whole);
    const b = scratch('b', size, size);
    b.save();
    b.translate(c, c);
    b.rotate(m.rotation);
    b.fillStyle = css(cream);
    b.fill(moonPhasePath(m.fraction, R));
    b.restore();
    b.globalCompositeOperation = 'source-atop';
    b.fillStyle = css(pal.dark ? mix3(lch(0.32, 0.03, 290), lch(0.84, 0.04, 80), clear) : lch(0.945, 0.028, 82), 0.5);
    b.beginPath();
    b.ellipse(c - 0.42 * R, c + 0.36 * R, 0.8 * R, 0.5 * R, -0.7, 0, TAU);       // one thin wash: the seas, as a painter hints them
    b.fill();
    b.beginPath();
    b.ellipse(c + 0.3 * R, c - 0.45 * R, 0.34 * R, 0.24 * R, 0.4, 0, TAU);
    b.fill();
    const day = m.inDaylight ? lerp(0.6, 1, night) : 1;
    ctx.globalAlpha = day;
    ctx.drawImage(b.canvas, 0, 0, size, size, 0, 0, size, size);
    ctx.globalAlpha = 1;
  }

  // ── clouds ───────────────────────────────────────────────────────────

  /** A cloud is a designed form, cut in gouache: a flat base, a long thin foot that tapers to
   *  nothing at both ends, and two to four soft lobes standing on it, the tallest off-centre. Each
   *  lobe is modelled on its own — a lit side toward the light, a shadowed side away — and the
   *  front ones overlap the back ones, so the form reads as a thing and not as a sticker. Its masks
   *  (the body, the lit sides, the shadowed sides, the underside) are cut once per light direction;
   *  only their paint changes. */
  function buildCloud(cloud, lx, ly) {
    const s = G.s;
    const L = cloud.len, R = cloud.rise;
    const pad = 12;
    const w = Math.ceil((L + 2 * pad) * s), h = Math.ceil((R * 1.2 + 2 * pad) * s);
    const cx = w / 2, cy = h - (pad + 2) * s;             // the middle of its base
    const seed = Math.round(L * 3 + cloud.e);
    const blank = () => { const c = mk(w, h); const x = c.getContext('2d'); x.fillStyle = '#fff'; return x; };
    const body = blank(), lit = blank(), shade = blank();
    // the base: flat, a hair of belly, drying to a point at each end
    const footT = Math.max(1.5, R * 0.17);
    const baseY = (u) => 0.9 * Math.pow(Math.max(0, 1 - 4 * u * u), 0.4) + 0.35 * (vn(u * 7 + seed, 1.3) - 0.5);
    const above = new Path2D();                           // everything over the base line
    above.moveTo(-10, -10); above.lineTo(w + 10, -10);
    for (let k = 40; k >= 0; k -= 1) { const u = k / 40 - 0.5; above.lineTo(cx + u * L * s, cy + baseY(u) * s); }
    above.closePath();
    /** One form: a lobe [centre, half-width, height] or the foot (null). */
    const form = (lobe, i) => {
      const path = new Path2D();
      if (!lobe) {
        const n = 48;
        for (let k = 0; k <= n; k += 1) {
          const u = k / n - 0.5;
          const taper = Math.pow(Math.max(0, 1 - 4 * u * u), 1.15);
          const y = -footT * taper * (0.86 + 0.3 * vn(u * 6 + seed * 0.7, 4.4));
          if (k === 0) path.moveTo(cx + u * L * s, cy + y * s); else path.lineTo(cx + u * L * s, cy + y * s);
        }
        for (let k = n; k >= 0; k -= 1) { const u = k / n - 0.5; path.lineTo(cx + u * L * s, cy + (baseY(u) + 0.4) * s); }
        path.closePath();
        return { path, r: footT * 0.8 };
      }
      const [c, hw, hf] = lobe;
      const rx = hw * R * (0.9 + 0.2 * hf), top = hf * R, ry = top * 0.66, oy = -top * 0.34;
      const n = 56;
      for (let k = 0; k <= n; k += 1) {
        const a = (k / n) * TAU;
        // cut by hand: never a true ellipse
        const wob = 1 + 0.06 * Math.sin(2 * a + seed + i * 2.1) + 0.045 * Math.sin(3 * a + seed * 1.7 + i) + 0.03 * Math.sin(5 * a + i * 3.3);
        const x = cx + (c * L + Math.cos(a) * rx * wob) * s, y = cy + (oy + Math.sin(a) * ry * wob) * s;
        if (k === 0) path.moveTo(x, y); else path.lineTo(x, y);
      }
      path.closePath();
      return { path, r: Math.min(rx, top) };
    };
    const forms = [form(null, 0), ...cloud.lobes.map((lobe, i) => form(lobe, i + 1))];
    const one = scratch('a', w, h);
    forms.forEach(({ path, r }, i) => {
      // this form alone, cut off at the base
      one.setTransform(1, 0, 0, 1, 0, 0);
      one.globalCompositeOperation = 'source-over';
      one.clearRect(0, 0, w, h);
      one.save(); one.clip(above); one.fillStyle = '#fff'; one.fill(path); one.restore();
      body.drawImage(one.canvas, 0, 0, w, h, 0, 0, w, h);
      // it stands in front of what was drawn before it: their modelling stops at its edge
      for (const m of [lit, shade]) {
        m.globalCompositeOperation = 'destination-out';
        m.globalAlpha = i === 0 ? 0 : 0.8;
        m.drawImage(one.canvas, 0, 0, w, h, 0, 0, w, h);
        m.globalAlpha = 1;
        m.globalCompositeOperation = 'source-over';
      }
      // its lit side: itself, less itself slid away from the light — and, fainter and broader, its shadow
      // (cut in two steps, the second slid half as far and laid half as strong, so the side fades
      // inward without a blur per form — the masks are softened once, at the end)
      const side = (target, dx, dy, reach, alpha) => {
        for (const [k, a] of [[1, 0.55], [0.5, 0.45]]) {
          const t = scratch('lo', w, h);
          t.drawImage(one.canvas, 0, 0, w, h, 0, 0, w, h);
          t.globalCompositeOperation = 'destination-out';
          t.drawImage(one.canvas, 0, 0, w, h, -dx * reach * k * s, -dy * reach * k * s, w, h);
          target.globalAlpha = alpha * a;
          target.drawImage(t.canvas, 0, 0, w, h, 0, 0, w, h);
        }
        target.globalAlpha = 1;
      };
      // (lit from below, a lobe's own lit side is its foot — which the underside already is: no notches between the lobes)
      side(lit, lx, ly, r * (i === 0 ? 0.5 : 0.34), i === 0 ? 1 : 1 - 0.85 * Math.max(0, ly));
      side(shade, -lx, -ly, r * 0.62, i === 0 ? 0.7 : 0.5);
    });
    // The whole of it is turned, too: toward the light on one side, away on the other.
    {
      const ext = Math.abs(lx) * L * 0.34 + Math.abs(ly) * R * 0.6;
      const mx = cx, my = cy - R * 0.42 * s;
      const turn = (ctx, sign, amount) => {
        const g = ctx.createLinearGradient(mx - sign * lx * ext * s, my - sign * ly * ext * s, mx + sign * lx * ext * s, my + sign * ly * ext * s);
        g.addColorStop(0, 'rgba(255,255,255,0)'); g.addColorStop(0.45, `rgba(255,255,255,${amount * 0.25})`); g.addColorStop(1, `rgba(255,255,255,${amount})`);
        ctx.fillStyle = g;
        ctx.fillRect(0, 0, w, h);
        ctx.fillStyle = '#fff';
      };
      turn(lit, 1, 0.42);
      turn(shade, -1, 0.5);
    }
    // soften: gouache laid wet, not cut paper — and the ends dry out
    const finish = (ctx, blur) => {
      const c = mk(w, h);
      const x = c.getContext('2d');
      x.filter = `blur(${blur * s}px)`;
      x.drawImage(ctx.canvas, 0, 0);
      x.filter = 'none';
      x.globalCompositeOperation = 'destination-out';
      const ends = x.createLinearGradient(pad * s, 0, w - pad * s, 0);
      ends.addColorStop(0, 'rgba(0,0,0,1)'); ends.addColorStop(0.09, 'rgba(0,0,0,0)');
      ends.addColorStop(0.91, 'rgba(0,0,0,0)'); ends.addColorStop(1, 'rgba(0,0,0,1)');
      x.fillStyle = ends;
      x.fillRect(0, 0, w, h);
      x.globalCompositeOperation = 'source-over';
      return c;
    };
    // (firm against the sky — the softness is kept for the inside)
    const soft = finish(body, 0.3);
    const within = (c) => { const x = c.getContext('2d'); x.globalCompositeOperation = 'destination-in'; x.drawImage(soft, 0, 0); x.globalCompositeOperation = 'source-over'; return c; };
    // The whole silhouette, too, has a side: a crisp edge of light where it faces the sun (the form
    // less itself slid a point and a half away from the light), and a broad shadowed far side (the
    // form less itself slid toward the light) — the two things that say which way the light comes.
    const slid = (dx, dy, blur) => {
      const c = mk(w, h);
      const x = c.getContext('2d');
      x.drawImage(soft, 0, 0);
      x.globalCompositeOperation = 'destination-out';
      x.drawImage(soft, Math.round(dx * s), Math.round(dy * s));
      x.globalCompositeOperation = 'source-over';
      if (!blur) return c;
      const c2 = mk(w, h);
      const x2 = c2.getContext('2d');
      x2.filter = `blur(${blur * s}px)`;
      x2.drawImage(c, 0, 0);
      x2.filter = 'none';
      return within(c2);
    };
    const edge = slid(-lx * 1.5, -ly * 1.5, 0);
    const farSide = slid(lx * R * 0.42, ly * R * 0.3, 0.9);
    // the underside: the lowest of it, along the flat base
    const under = mk(w, h);
    {
      const x = under.getContext('2d');
      x.drawImage(soft, 0, 0);
      x.globalCompositeOperation = 'destination-in';
      const band = Math.max(2.2, R * 0.3);
      const g = x.createLinearGradient(0, cy - band * s, 0, cy + 1.2 * s);
      g.addColorStop(0, 'rgba(0,0,0,0)'); g.addColorStop(0.55, 'rgba(0,0,0,0.45)'); g.addColorStop(1, 'rgba(0,0,0,1)');
      x.fillStyle = g;
      x.fillRect(0, 0, w, h);
    }
    return { w, h, cx, cy, body: soft, lit: within(finish(lit, 0.2 + R * 0.05)), shade: within(finish(shade, 0.5 + R * 0.1)), under, edge, farSide };
  }

  function paintCloud(cloud, pal, x, y, lightKey) {
    if (!cloud.masks || cloud.maskKey !== lightKey) {
      let dx = pal.lamp.x - x, dy = pal.lamp.y - (y - cloud.rise * 0.5);
      const dist = Math.hypot(dx, dy) || 1;
      dx /= dist; dy /= dist;
      // a form is lit on a side: the light's own side of the page, leaning up or down as the light stands
      const lyy = clamp(dy * 1.6, -0.85, 0.85);
      const lxx = Math.sign(dx || 1) * Math.max(0.5, Math.abs(dx));
      const n = Math.hypot(lxx, lyy) || 1;
      const tb = performance.now();
      cloud.masks = buildCloud(cloud, lxx / n, lyy / n);
      timing.clouds = (timing.clouds ?? 0) + performance.now() - tb;
      cloud.maskKey = lightKey;
      cloud.canvas = mk(cloud.masks.w, cloud.masks.h);
    }
    const { w, h, body, lit, shade, under, edge, farSide } = cloud.masks;
    const air = pal.air, cl = air.cloud;
    const hi = Boolean(cloud.high);
    const far = smoothstep(0.1, 1.35, Math.abs(pal.dxSun(x)));
    const litAmt = pal.byMoon ? (hi ? 0.8 : 0.95) * pal.moonlight : hi ? cl.hiAmt : cl.loAmt;
    let litLab = pal.byMoon ? air.silver : hi ? cl.hiLit : cl.loLit;
    // While the sun is well up, a cloud in the low key is a pale cool thing in a dusky sky — the
    // table's warm white prints as tan there, and a tan cloud at one in the afternoon is a smudge.
    // (Under 2.5° nothing here changes: the sunset's clouds are the table's.)
    const high = air.dark && !pal.byMoon ? smoothstep(2.5, 6, pal.altDeg) : 0;
    if (air.dark && !pal.byMoon) {
      // the low key's lit cloud keeps its fire: apricot under a low sun, rose after it
      const warm = smoothstep(14, 6, pal.altDeg) * smoothstep(-9, -4, pal.altDeg);
      const tgt = lch(litLab[0] + 0.02, 0.12, pal.altDeg > 0 ? 58 : 30);
      litLab = mix3(litLab, tgt, 0.6 * warm);
      litLab = mix3(litLab, lch(litLab[0] + 0.05, 0.02, 250), smoothstep(7, 15, pal.altDeg));
    }
    const shadeLab = hi ? cl.hiShade : cl.loShade;
    // Away from the sun the lit side goes to the Belt's pink, and quieter.
    if (!pal.byMoon) litLab = mix3(litLab, mix3(shadeLab, lch(litLab[0] - 0.03, 0.05, 350), 0.6), 0.75 * far);
    const skyHere = air.skyAt(pal.dxSun(x), (G.cfg.H0 - y) / G.cfg.table);
    // (its body does not take the fire — only its lit side does: orange mixed into violet is brown)
    const bodyLit = high > 0 ? mix3(litLab, [Math.max(litLab[0], skyHere[0] + 0.13), skyHere[1] * 0.5, skyHere[2] * 0.5], high) : litLab;
    let bodyLab = mix3(mix3(shadeLab, bodyLit, 0.36 * litAmt), skyHere, hi ? 0.34 : 0.22);
    if (high > 0) bodyLab = [Math.max(bodyLab[0], skyHere[0] + 0.035 * high), bodyLab[1], bodyLab[2]];
    // The underside catches the afterglow: from the last of the sun until the twilight has gone, the
    // flat base is the warmest thing on the cloud (ember near the sun, rose away from it).
    const after = pal.byMoon ? 0 : smoothstep(7, 1.5, pal.altDeg) * smoothstep(-6.5, -2.5, pal.altDeg);
    const underLab = mix3(lch(air.dark ? 0.60 : 0.86, air.dark ? 0.13 : 0.10, pal.altDeg > 0 ? 52 : 28), lch(air.dark ? 0.50 : 0.84, air.dark ? 0.085 : 0.07, 5), far);
    const ctx = cloud.canvas.getContext('2d');
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.globalCompositeOperation = 'source-over';
    ctx.globalAlpha = 1;
    ctx.clearRect(0, 0, w, h);
    ctx.drawImage(tinted(body, pal.C(bodyLab)), 0, 0, w, h, 0, 0, w, h);
    // the far side: cooler and a step deeper (a little of the sky's own blue in it)
    const coolLab = mix3([shadeLab[0] - (air.dark ? 0.012 : 0.02), shadeLab[1], shadeLab[2]], skyHere, 0.12);
    ctx.globalAlpha = (air.dark ? 0.55 : 0.5) * (0.4 + 0.6 * clamp01(litAmt));
    ctx.drawImage(tinted(farSide, pal.C(coolLab)), 0, 0, w, h, 0, 0, w, h);
    ctx.globalAlpha = 0.8;
    ctx.drawImage(tinted(shade, pal.C(mix3(shadeLab, skyHere, 0.12))), 0, 0, w, h, 0, 0, w, h);
    ctx.globalAlpha = clamp01(0.22 + 0.78 * litAmt);
    ctx.drawImage(tinted(lit, pal.C(litLab)), 0, 0, w, h, 0, 0, w, h);
    if (after > 0.03) {
      ctx.globalAlpha = clamp01(0.85 * after * (1 - 0.35 * far));
      ctx.drawImage(tinted(under, pal.C(underLab)), 0, 0, w, h, 0, 0, w, h);
    }
    // the edge of light on the sun's side: crisp, the brightest thing on the cloud
    const edgeAmt = clamp01(litAmt) * (pal.byMoon ? 0.6 : 0.5 + 0.5 * smoothstep(-6, 0, pal.altDeg)) * (1 - 0.4 * far);
    if (edgeAmt > 0.03) {
      ctx.globalAlpha = clamp01(0.9 * edgeAmt);
      ctx.drawImage(tinted(edge, pal.C([litLab[0] + (air.dark ? 0.06 : 0.02), litLab[1], litLab[2]])), 0, 0, w, h, 0, 0, w, h);
    }
    ctx.globalAlpha = 1;
  }

  /** 0 where a cloud would lie across the header's words, 1 once its whole form is clear of them. */
  function cloudClear(state, sx, sy, cloud) {
    const L = state.layout;
    if (!L) return 1;
    let clear = 1;
    const x0 = sx - cloud.len / 2, x1 = sx + cloud.len / 2, y0 = sy - cloud.rise, y1 = sy + 2;
    for (const box of [L.name, L.age, L.title, L.subtitle]) {
      if (!box) continue;
      const dx = Math.max(box.x - x1, 0, x0 - (box.x + box.width)), dy = Math.max(box.y - y1, 0, y0 - (box.y + box.height));
      clear = Math.min(clear, smoothstep(3, 14, Math.hypot(dx, dy)));
    }
    return clear;
  }

  // ── the land ─────────────────────────────────────────────────────────

  /** A horizontal gradient across the plane: a stop at every multiple of `step` points of WORLD x
   *  (so the cover and the spread mix the same colours at the same places). `fn(x)` → a css colour. */
  function hGrad(ctx, fn, step = 30, x0 = G.xL, x1 = G.xR) {
    const s = G.s;
    const grad = ctx.createLinearGradient((x0 - G.xL) * s, 0, (x1 - G.xL) * s, 0);
    grad.addColorStop(0, fn(x0));
    for (let x = Math.ceil((x0 + 0.01) / step) * step; x < x1; x += step) grad.addColorStop((x - x0) / (x1 - x0), fn(x));
    grad.addColorStop(1, fn(x1));
    return grad;
  }

  function shapePaths(sh, y0) {
    const s = G.s;
    const px = (x) => (x - G.xL) * s, py = (y) => (y - y0) * s;
    const body = new Path2D();
    const crestLine = new Path2D();
    const first = sh.crest[0], last = sh.crest[sh.crest.length - 1];
    body.moveTo(px(first[0]), py(first[1]));
    crestLine.moveTo(px(first[0]), py(first[1]));
    for (const p of sh.crest) { body.lineTo(px(p[0]), py(p[1])); crestLine.lineTo(px(p[0]), py(p[1])); }
    if (sh.base) {
      for (const p of sh.base) body.lineTo(px(p[0]), py(p[1]));
    } else {
      body.lineTo(px(last[0]), py(G.bottom + 40));
      body.lineTo(px(first[0]), py(G.bottom + 40));
    }
    body.closePath();
    // for a spur: everything under its crest line, and its body with the crest lifted out of the way
    let under = null, raised = null;
    if (sh.base) {
      under = new Path2D();
      under.moveTo(px(first[0]) - 200, py(first[1]));
      for (const p of sh.crest) under.lineTo(px(p[0]), py(p[1]));
      under.lineTo(px(last[0]) + 200, py(last[1]));
      under.lineTo(px(last[0]) + 200, py(G.bottom + 400));
      under.lineTo(px(first[0]) - 200, py(G.bottom + 400));
      under.closePath();
      const lift = (sh.foot ?? 0) * 2 + 20;
      raised = new Path2D();
      raised.moveTo(px(first[0]), py(first[1] - lift));
      for (const p of sh.crest) raised.lineTo(px(p[0]), py(p[1] - lift));
      for (const p of sh.base) raised.lineTo(px(p[0]), py(p[1]));
      raised.closePath();
    }
    return { body, crestLine, under, raised, px, py };
  }

  /** How squarely the slope under the crest at x faces the light: 0 turned away … 1 facing. */
  function facing(sh, x, lampX, reach = 5) {
    const a = sh.at(x - reach), b = sh.at(x + reach);
    if (!Number.isFinite(a) || !Number.isFinite(b)) return 0.5;
    const slope = (b - a) / (2 * reach);                 // + falls to the right
    return clamp01(0.5 + clamp((lampX - x) / 60, -1, 1) * slope * 2.2);
  }

  /** One plane of land. Each shape: a fill that follows the sky along x, then — laid as a WASH at a
   *  quarter of the size and enlarged, because a wash has no edges to lose — the air at its foot and
   *  the broad strokes of shade, light and frost along its crest; then, at full size, the things with
   *  an edge: grass, the river, the rim of caught light. */
  function paintPlane(plane, pal) {
    const s = G.s, air = pal.air;
    const ctx = plane.ctx;
    const w = plane.canvas.width, h = plane.canvas.height;
    const Q = 0.25;
    const wq = Math.ceil(w * Q) + 1, hq = Math.ceil(h * Q) + 1;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.globalCompositeOperation = 'source-over';
    ctx.globalAlpha = 1;
    ctx.clearRect(0, 0, w, h);
    const sea = pal.sea;
    const lampX = pal.lamp.x;
    const power = pal.lamp.power;
    const rimAmt = pal.byMoon ? 0.5 * pal.moonlight : Math.max(air.rimAmt, 0.12 * air.day);
    for (const sh of plane.shapes) {
      if (sh.mist) { drawMistBand(ctx, sh.mist, pal, plane.y0, 0, 1); continue; }
      const { body, crestLine, under, raised, px, py } = shapePaths(sh, plane.y0);
      const a = scratch('a', w, h);
      const hz = sh.haze;
      // 1. The fill: its own colour gone `haze` of the way into the horizon sky behind it, at every x.
      const own = (x) => {
        const f = facing(sh, x, lampX);
        // the side turned to the light is a breath lighter and warmer, the far side cooler
        const side = (f - 0.5) * power * (1 - hz) * (air.dark ? 0.035 : 0.03);
        // (the light print: a near plane is a step deeper and warmer at its crest than the plane behind
        // it is at its foot — depth by overlap, without darkening the page under the cards)
        const near = air.dark || sh.hazeLight != null ? 0 : Math.pow(1 - hz, 1.2);
        const g = [pal.ground[0] + side - 0.058 * near, pal.ground[1] + 0.007 * near, pal.ground[2] + 0.006 * near];
        return mix3(g, air.hazeAt(pal.dxSun(x)), air.dark ? hz : sh.hazeLight ?? hz * 0.78);
      };
      // Dark, at night: the land is not one black band. Each plane keeps a value of its own — far
      // ones a shade under the horizon's light, near ones deeper — and its blue; all of it under a card's.
      const nightL = 0.106 + 0.098 * Math.pow(hz, 0.8);
      const fillAt = (x) => {
        const q = pal.shown(own(x));
        if (pal.deepNight > 0) {
          const k = pal.deepNight;
          const L = Math.max(q[0], nightL);
          q[0] = lerp(q[0], L, k);
          q[1] = lerp(q[1], 0.030 * Math.cos(266 * DEG), 0.7 * k); q[2] = lerp(q[2], 0.030 * Math.sin(266 * DEG), 0.7 * k);
        }
        return css(q);
      };
      a.fillStyle = hGrad(a, fillAt);
      const melts = Boolean(sh.base && sh.foot);
      if (sh.soft > 0 || melts) {
        // A far ridge has a soft edge; a spur meets the valley floor softly, its foot melting away.
        // Both are cut small and enlarged: the enlarging is the softness.
        const q = sh.soft >= 1 ? 0.25 : sh.soft > 0 ? 0.5 : 0.25;
        const mw = Math.ceil(w * q) + 1, mh = Math.ceil(h * q) + 1;
        const m = scratch('m', mw, mh);
        m.setTransform(q, 0, 0, q, 0, 0);
        m.fillStyle = '#fff';
        if (melts) {
          m.filter = `blur(${sh.foot * 0.42 * s * q}px)`;
          m.fill(raised);
          m.filter = 'none';
          if (sh.soft > 0) { m.globalCompositeOperation = 'destination-in'; m.fill(under); }
        } else {
          m.fill(body);
        }
        if (sh.soft > 0) a.fillRect(0, 0, w, h); else a.fill(under);
        a.globalCompositeOperation = 'destination-in';
        a.drawImage(m.canvas, 0, 0, mw, mh, 0, 0, mw / q, mh / q);
        a.globalCompositeOperation = 'source-over';
      } else {
        a.fill(body);
      }
      // grass along a near crest: blades of the same paint, so the edge is drawn, not cut
      if (sh.grass) {
        for (let n = Math.ceil((Math.max(sh.x0, G.xL) + 1) / 0.55); n * 0.55 < Math.min(sh.x1, G.xR); n += 1) {
          const x = n * 0.55;                              // blades stand at fixed places in the world
          const k = n;
          // grass grows in clumps: thick here, thin there
          const clump = smoothstep(0.35, 0.7, vn(x / 9 + sh.index * 3.3, 4.4)) * 0.85 + 0.15;
          if (hash(k, 401 + sh.index) > 0.8 * sh.grass * clump) continue;
          const y = sh.at(x);
          if (!Number.isFinite(y) || y > G.bottom) continue;
          const len = (0.9 + 2.9 * Math.pow(hash(k, 402), 2.2) * clump) * Math.min(1.2, sh.grass);
          const lean = (hash(k, 403) - 0.42) * 1.5;
          // a blade: a sliver that tapers to nothing
          const wdt = (0.28 + 0.26 * hash(k, 404));
          a.beginPath();
          a.moveTo(px(x - wdt), py(y + 0.8));
          a.quadraticCurveTo(px(x + lean * 0.2 - wdt * 0.4), py(y - len * 0.6), px(x + lean), py(y - len));
          a.quadraticCurveTo(px(x + lean * 0.2 + wdt * 0.6), py(y - len * 0.55), px(x + wdt), py(y + 0.8));
          a.closePath();
          a.fill();
        }
      }

      // 2. The wash, a quarter of the size.
      const lo = scratch('lo', wq, hq);
      lo.setTransform(Q, 0, 0, Q, 0, 0);
      if (sh.floor) {
        // the valley floor recedes: near is its own colour, far is air
        lo.fillStyle = hGrad(lo, (x) => pal.C(mix3(pal.ground, air.hazeAt(pal.dxSun(x)), sh.hazeNear)));
        lo.fillRect(0, 0, w + 8, h + 8);
        lo.globalCompositeOperation = 'destination-in';
        const fall = lo.createLinearGradient(0, py(sh.top), 0, py(sh.top + 190));
        fall.addColorStop(0, 'rgba(0,0,0,0)'); fall.addColorStop(0.3, 'rgba(0,0,0,0.5)'); fall.addColorStop(1, 'rgba(0,0,0,1)');
        lo.fillStyle = fall;
        lo.fillRect(0, 0, w + 8, h + 8);
        lo.globalCompositeOperation = 'source-over';
      } else if (hz < 0.95) {
        // air gathers at its foot: toward the valley's own haze, level
        lo.fillStyle = hGrad(lo, (x) => pal.C(air.hazeAt(pal.dxSun(x))));
        lo.fillRect(0, 0, w + 8, h + 8);
        lo.globalCompositeOperation = 'destination-in';
        const depth = 60 + 130 * (1 - hz);
        const fall = lo.createLinearGradient(0, py(sh.top + 4), 0, py(sh.top + 4 + depth));
        const amt = (1 - hz) * (air.dark ? 0.44 : 0.50) + 0.06;
        fall.addColorStop(0, 'rgba(0,0,0,0)'); fall.addColorStop(0.5, `rgba(0,0,0,${amt * 0.55})`); fall.addColorStop(1, `rgba(0,0,0,${amt})`);
        lo.fillStyle = fall;
        lo.fillRect(0, 0, w + 8, h + 8);
        lo.globalCompositeOperation = 'source-over';
      }
      // The pale page at night: the land is slate only where it meets the sky — down the page, under
      // the cards, it gives way to the paper (the same level wash on every plane, so no plane begins again).
      if (!air.dark && pal.nightness > 0.02) {
        const H0 = G.cfg.H0;
        const paper = pal.shown(lch(0.948, 0.014, 285));
        const g2 = lo.createLinearGradient(0, py(H0 + 14), 0, py(H0 + (G.cfg.kind === 'duo' ? 250 : 190)));
        g2.addColorStop(0, css(paper, 0)); g2.addColorStop(0.4, css(paper, 0.3 * pal.nightness)); g2.addColorStop(1, css(paper, 0.62 * pal.nightness));
        lo.fillStyle = g2;
        lo.fillRect(0, 0, w + 8, h + 8);
      }
      // Three strokes along the crest. Shade first: a broad cool one on the side turned away…
      lo.lineJoin = 'round';
      if (power > 0.03 && hz < 0.8) {
        const coolLab = mix3(own(sh.x0 + 40), air.skyAt(pal.dxSun(sh.x0), 0.9), 0.5);
        const shadeLab = [coolLab[0] - (air.dark ? 0.03 : 0.05), coolLab[1], coolLab[2]];
        // (A near hill is a round thing: before the strokes that hug its crest, its whole flank turns —
        // a very broad, very soft pass that reaches a hundred points down the slope, shade where the
        // slope looks away from the light and a breath of the light's own colour where it looks toward it.)
        if (hz < 0.5 && !sh.base) {
          const turn = (x) => 0.5 + (facing(sh, x, lampX, 90) - 0.5) * 0.62;
          // (where a hill's crest ends inside the picture — the valley side of the Duo — the pass comes in
          // gradually: a broad stroke must not begin with an edge)
          const ends = (x) => (G.cfg.kind === 'duo' ? smoothstep(sh.x0 - 10, sh.x0 + 100, x) : 1);
          const k = power * (1 - hz);
          lo.filter = `blur(${30 * s * Q}px)`;
          lo.lineWidth = 210 * s;
          lo.strokeStyle = hGrad(lo, (x) => css(pal.shown([shadeLab[0] - (air.dark ? 0.012 : 0.01), shadeLab[1], shadeLab[2]]), clamp01((0.5 - turn(x)) * 2.4) * ends(x) * k * (air.dark ? 0.62 : 0.5)), 24);
          lo.stroke(crestLine);
          const warm = mix3(own(lampX), pal.byMoon ? air.silver : air.rim, 0.45);
          lo.strokeStyle = hGrad(lo, (x) => css(pal.shown([warm[0] + (air.dark ? 0.045 : 0.03), warm[1], warm[2]]), clamp01((turn(x) - 0.5) * 2.4) * ends(x) * k * (0.25 + 0.75 * Math.max(air.rimAmt, 0.3 * air.day)) * (air.dark ? 0.5 : 0.42)), 24);
          lo.stroke(crestLine);
        }
        lo.filter = `blur(${(5 + 9 * (1 - hz)) * s * Q}px)`;
        lo.lineWidth = (16 + 40 * (1 - hz)) * s;
        lo.strokeStyle = hGrad(lo, (x) => css(pal.shown(shadeLab), clamp01((1 - facing(sh, x, lampX)) * 1.5 - 0.35) * power * (1 - hz) * 0.75), 14);
        lo.stroke(crestLine);
        // …then the light: a broad soft glaze on the shoulder that faces it.
        const litLab = mix3(own(lampX), pal.byMoon ? air.silver : air.rim, 0.62);
        const lit = [litLab[0] + (air.dark ? 0.06 : 0.035), litLab[1], litLab[2]];
        lo.filter = `blur(${(3 + 6 * (1 - hz)) * s * Q}px)`;
        lo.lineWidth = (10 + 26 * (1 - hz)) * s;
        lo.strokeStyle = hGrad(lo, (x) => css(pal.shown(lit), clamp01(clamp01(facing(sh, x, lampX) * 2.2 - 0.9) * rimAmt * (1 - hz * 0.7) * 1.5 * (0.35 + 0.65 * (sh.rim ?? 0.5)) * Math.exp(-Math.abs(x - lampX) / (G.Wa * 0.8)))), 14);
        lo.stroke(crestLine);
      }
      // Frost and snow on the shoulders: where the sky reaches them.
      const white = Math.max(sea.snow, sea.frost * 0.55);
      if (white > 0.03 && hz < 0.7) {
        const lab = sea.snow > 0.03 ? pal.snowLit : pal.frostLit;
        lo.filter = `blur(${(2 + 3 * (1 - hz)) * s * Q}px)`;
        lo.lineWidth = (5 + 16 * (1 - hz)) * s * (sea.snow > 0.03 ? 1.5 : 1);
        lo.strokeStyle = hGrad(lo, (x) => css(pal.shown(mix3(lab, air.hazeAt(pal.dxSun(x)), hz * 0.8)), white * (sea.snow > 0.03 ? 0.9 : 0.5)), 40);
        lo.stroke(crestLine);
      }
      lo.filter = 'none';
      a.globalCompositeOperation = 'source-atop';
      a.drawImage(lo.canvas, 0, 0, wq, hq, 0, 0, wq / Q, hq / Q);

      // 3. The river lies on the valley floor.
      if (sh.floor && G.river) { const tr = performance.now(); paintRiver(a, pal, plane.y0, w, h); timing.river = performance.now() - tr; }

      // 4. The rim: one thin, loaded line where the crest catches the light, the brush skipping.
      // (under a moon: a thin cool rim on the knoll alone, where the tree stands)
      if (sh.rim && rimAmt > 0.02 && power > 0.03 && hz < 0.8 && (!pal.byMoon || sh.tree)) {
        const rimLab = pal.byMoon ? air.silver : air.rim;
        let yMin = Infinity, yMax = -Infinity;
        for (const p of sh.crest) { if (p[0] < G.xL || p[0] > G.xR) continue; yMin = Math.min(yMin, p[1]); yMax = Math.max(yMax, p[1]); }
        const y0 = Math.max(0, Math.floor(py(yMin) - 6 * s)), y1 = Math.min(h, Math.ceil(py(Math.min(yMax, G.bottom)) + 6 * s));
        if (y1 > y0) {
          const b2 = scratch('b', w, y1 - y0);
          b2.translate(0, -y0);
          b2.lineJoin = 'round'; b2.lineCap = 'round';
          b2.lineWidth = (pal.byMoon ? 1.3 : 1.5 + 1.7 * (1 - hz)) * s;
          b2.strokeStyle = hGrad(b2, (x) => css(pal.shown([rimLab[0] + 0.04, rimLab[1], rimLab[2]]), clamp01((0.14 + 0.86 * facing(sh, x, lampX)) * rimAmt * sh.rim * (air.dark ? 2.6 : 1.3) * Math.exp(-Math.abs(x - lampX) / (G.Wa * 0.5)))), 10);
          b2.translate(0, 0.3 * s);
          b2.stroke(crestLine);
          b2.setTransform(1, 0, 0, 1, 0, 0);
          b2.globalCompositeOperation = 'destination-out';
          X.dryPattern.setTransform(new DOMMatrix().translate(sh.index * 37 - G.xL * s, sh.index * 91 - y0));
          b2.fillStyle = X.dryPattern;
          b2.globalAlpha = 0.62;
          b2.fillRect(0, 0, w, y1 - y0);
          b2.globalAlpha = 1;
          a.drawImage(b2.canvas, 0, 0, w, y1 - y0, 0, y0, w, y1 - y0);
        }
      }
      a.globalCompositeOperation = 'source-over';
      const top = Math.max(0, Math.floor(py(sh.top) - 14 * s));
      ctx.drawImage(a.canvas, 0, top, w, h - top, 0, top, w, h - top);
      // The tree stands on its knoll.
      if (sh.tree) {
        const t = G.tree;
        ctx.drawImage(t.canvas, Math.round((t.x - G.xL) * s - t.masks.cx), Math.round((t.baseY - plane.y0) * s - t.masks.cy));
      }
    }
    // The paint's own unevenness, over the whole plane (not the tree: it is ink).
    ctx.globalCompositeOperation = 'source-atop';
    ctx.globalAlpha = air.dark ? 0.04 : 0.036;
    X.mottlePattern.setTransform(new DOMMatrix().translate(-G.xL * s, -plane.y0 * s).scale(s / 2 * 1.5));
    ctx.fillStyle = X.mottlePattern;
    ctx.fillRect(0, 0, w, h);
    ctx.globalAlpha = 1;
    ctx.globalCompositeOperation = 'source-over';
  }

  // ── the river ────────────────────────────────────────────────────────

  /** The river's two banks, by projection: the centre line is laid on the valley floor (a ground
   *  plane under a camera one unit up; its vanishing line is the horizon), offset there by half the
   *  river's width, and brought back to the picture. */
  function buildRiver() {
    const def = G.cfg.river;
    if (!def) return null;
    const H0 = G.cfg.H0, { vx, f, width, minHalf } = def;
    const pts = line(def.line, 1.5, 0, 0);
    const ground = pts.map((p) => { const d = Math.max(1.5, p[1] - H0); return [(p[0] - vx) / d, f / d]; });
    const back = (g) => { const d = f / Math.max(0.6, g[1]); return [vx + g[0] * d, H0 + d]; };
    const left = [], right = [], half = [];
    for (let i = 0; i < pts.length; i += 1) {
      const a = ground[Math.max(0, i - 1)], b = ground[Math.min(pts.length - 1, i + 1)];
      let tx = b[0] - a[0], tz = b[1] - a[1];
      const len = Math.hypot(tx, tz) || 1;
      tx /= len; tz /= len;
      const g = ground[i];
      const edge = (side) => {
        // (a river is not a road: each bank wanders on its own, so the water widens and narrows)
        const waver = 1 + 0.5 * (fb(i / 34 + side * 9.3 + 2.1, 3.3 + side, 2) - 0.5) * 2 * smoothstep(20, 90, i);
        const q = back([g[0] - tz * side * width * waver / 2, g[1] + tx * side * width * waver / 2]);
        let ox = q[0] - pts[i][0], oy = q[1] - pts[i][1];
        const o = Math.hypot(ox, oy);
        // a far reach is never thinner than a line the eye can follow
        if (o < minHalf) { if (o < 1e-4) { ox = 0; oy = side; } const k = minHalf / Math.max(o, 1e-4); ox *= k; oy *= k; }
        return [pts[i][0] + ox, pts[i][1] + oy];
      };
      const L = edge(1), R = edge(-1);
      left.push(L); right.push(R);
      half.push([Math.abs(L[0] - R[0]) / 2, Math.abs(L[1] - R[1]) / 2]);     // half its extent in x and in y, on the picture
    }
    let minX = Infinity, maxX = -Infinity, maxY = -Infinity;
    for (const p of left.concat(right)) { minX = Math.min(minX, p[0]); maxX = Math.max(maxX, p[0]); maxY = Math.max(maxY, p[1]); }
    return { pts, left, right, half, minX, maxX, maxY, def };
  }

  /** The river: water, not a ribbon and not a channel. There is no line along either bank. Its
   *  width wavers (buildRiver); each reach is a pale mirror of the sky above it — the low bright sky
   *  far away, a little more of the sky's own colour near — and the lightest passage of the land;
   *  where a reach runs across the view the far bank lies in it as a short dark reflection, broken;
   *  level streaks of sheen and a few glints lie across the near reach; a sandbar sits inside one
   *  bend and reeds stand at the water's edge in a few places; mist lies on the far and the middle
   *  reaches, so the far bank is lost in it. One soft upright smear of the low sky's light stands in
   *  the bend in the leading margin column; under a moon, its broken path. */
  function paintRiver(a, pal, y0, w, h) {
    const s = G.s, air = pal.air, c = G.cfg;
    const r = G.river;
    G.riverLight = null;
    if (r.maxX < G.xL - 4 || r.minX > G.xR + 4) return;   // this display never sees it (the cover)
    const px = (x) => (x - G.xL) * s, py = (y) => (y - y0) * s;
    // everything below happens inside the river's own box
    const bx = Math.max(0, Math.floor(px(r.minX - 22))), by = Math.max(0, Math.floor(py(r.pts[0][1] - 8)));
    const bw = Math.min(w, Math.ceil(px(r.maxX + 22))) - bx, bh = h - by;
    if (bw < 2 || bh < 2) return;
    const path = new Path2D();
    path.moveTo(px(r.left[0][0]), py(r.left[0][1]));
    for (const p of r.left) path.lineTo(px(p[0]), py(p[1]));
    for (let i = r.right.length - 1; i >= 0; i -= 1) path.lineTo(px(r.right[i][0]), py(r.right[i][1]));
    path.closePath();
    const vx = px(r.def.vx), vy = py(c.H0);
    // the picture, scaled about the river's vanishing point: a shift that is small far away and large near
    const about = (ctx, kx, ky = kx, skew = 0) => ctx.setTransform(kx, 0, skew, ky, vx * (1 - kx) - skew * vy, vy * (1 - ky));
    const plain = (ctx) => { ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.globalAlpha = 1; ctx.filter = 'none'; };
    const yTop = r.pts[0][1], yBot = Math.min(r.maxY, G.bottom + 40);
    const xAt = (y) => { for (const p of r.pts) if (p[1] >= y) return p[0]; return r.pts[r.pts.length - 1][0]; };
    const depthOf = (y) => clamp01((y - c.H0) / 380);     // 0 at the horizon … 1 at the foot of the picture
    const dusk = pal.deepNight;
    const lightNight = air.dark ? 0 : pal.nightness;      // the pale page at night: the river is all but lost in mist
    const mistK = 1 + 0.9 * lightNight;
    // (On the pale page the hush takes every colour toward the paper — and pale water on pale land is
    // gone. Like the tree, the water keeps most of its own: the sky's blue, a breath deeper than the land's grey.)
    const shownW = (lab) => (air.dark ? pal.shown(lab) : pal.shown(lab, { presence: Math.max(air.presence, 0.56) }));
    /** A level stroke on the water: a lens of paint, soft at both ends. */
    const lens = (ctx, x, y, halfLen, halfTh, lab, alpha) => {
      if (!(alpha > 0.012)) return;
      ctx.save();
      ctx.translate(px(x), py(y));
      ctx.scale(halfLen * s, halfTh * s);
      const g = ctx.createRadialGradient(0, 0, 0, 0, 0, 1);
      g.addColorStop(0, css(lab, alpha)); g.addColorStop(0.5, css(lab, alpha * 0.7)); g.addColorStop(1, css(lab, 0));
      ctx.fillStyle = g;
      ctx.fillRect(-1, -1, 2, 2);
      ctx.restore();
    };

    // 1. The water's shape. Its edges are feathered in proportion to how near they are, and far
    //    more on the far side than the near: the far bank is not a line, it is where the water stops showing.
    const W = scratch('rv', w, h);
    W.fillStyle = '#fff';
    W.globalCompositeOperation = 'lighter';
    const feather = [-0.034, -0.026, -0.019, -0.013, -0.008, -0.004, 0, 0.004];
    W.globalAlpha = 1 / feather.length + 0.002;
    for (const k of feather) { about(W, 1 + k * 0.3, 1 + k); W.fill(path); }
    plain(W);
    // …and lost altogether where mist lies on it
    W.globalCompositeOperation = 'destination-out';
    for (const [mx, my, rx, ry, amt] of r.def.mist) {
      W.save();
      W.translate(px(mx), py(my));
      W.scale(rx * s, ry * 1.25 * s);
      const g = W.createRadialGradient(0, 0, 0, 0, 0, 1);
      const al = clamp01(amt * (0.7 + 0.6 * pal.mistAmt) * mistK);
      g.addColorStop(0, `rgba(0,0,0,${al})`); g.addColorStop(0.55, `rgba(0,0,0,${al * 0.85})`); g.addColorStop(0.85, `rgba(0,0,0,${al * 0.3})`); g.addColorStop(1, 'rgba(0,0,0,0)');
      W.fillStyle = g;
      W.fillRect(-1, -1, 2, 2);
      W.restore();
    }

    // …and where a bar of sand and grass lies along the inside of the near bend, the bank comes out
    // into the river (the land itself shows there: nothing is painted)
    {
      let at = Math.round(0.705 * (r.pts.length - 1));
      for (let i = Math.round(0.6 * (r.pts.length - 1)); i < Math.round(0.8 * (r.pts.length - 1)); i += 1) if (r.pts[i][0] < r.pts[at][0]) at = i;
      const e = r.right[at], hw = r.half[at][0];
      W.save();
      W.translate(px(e[0] + hw * 0.16), py(e[1] + 6));
      W.rotate(0.14);
      W.scale(hw * 0.78 * s, hw * 1.7 * s);
      const g = W.createRadialGradient(0.3, 0, 0, 0.3, 0, 1);
      g.addColorStop(0, 'rgba(0,0,0,1)'); g.addColorStop(0.7, 'rgba(0,0,0,1)'); g.addColorStop(0.86, 'rgba(0,0,0,0.5)'); g.addColorStop(1, 'rgba(0,0,0,0)');
      W.fillStyle = g;
      W.fillRect(-1, -1, 2, 2);
      W.restore();
    }

    // 2. What it mirrors: a stop every few points down the picture. Water seen from a hill gives back
    //    the sky a little above the horizon — pale; the near reach takes a little more of the sky's own
    //    colour, never its depth: the river is the lightest passage of the land.
    W.globalCompositeOperation = 'source-in';
    const mirrorE = (f) => 0.012 + lerp(0.30, 0.13, pal.nightness) * Math.pow(f, 0.7);
    const waterAt = (x, y) => {
      const f = depthOf(y);
      const dx = pal.dxSun(x);
      const sky = air.skyAt(dx, mirrorE(f));
      const low = air.skyAt(dx, 0.012);
      const lift = (air.dark ? 0.05 : 0.016) + (air.dark ? 0.012 : 0.0) * pal.nightness;
      const k = 1 - 0.18 * f;                             // the mirror loses a little colour as it steepens
      // never deeper than the low sky by more than a step: a pale mirror
      const L = Math.max(sky[0], low[0] - (air.dark ? 0.035 : 0.02)) + lift;
      const water = [L, sky[1] * k, sky[2] * k];
      // far away the water is all the horizon's light
      return mix3(water, [low[0] + lift, low[1], low[2]], 0.6 * (1 - smoothstep(0, 0.07, f)));
    };
    const grad = W.createLinearGradient(0, py(yTop), 0, py(yBot));
    const n = 22;
    for (let i = 0; i <= n; i += 1) {
      const fy = (i / n) ** 2;                            // closer together far away, where the sky turns fastest
      const y = yTop + (yBot - yTop) * fy;
      // (dark, at night: the faintest line of reflected sky — held a step under the land's own cap)
      const q = shownW(waterAt(xAt(y), y));
      if (pal.deepNight > 0) q[0] = lerp(q[0], NIGHT_WATER * (1 - 0.08 * depthOf(y)), pal.deepNight);
      grad.addColorStop(fy, css(q));
    }
    W.fillStyle = grad;
    W.fillRect(bx, by, bw, bh);
    W.globalCompositeOperation = 'source-atop';

    // 3. The far bank lies in the water where a reach runs ACROSS the view — a short, soft, darker
    //    reflection under its far edge, here and there. Never along a reach that runs toward you
    //    (a dark edge down one side and a light one down the other is a moulded channel, not water).
    {
      const bank = (x) => pal.shown(mix3([pal.ground[0] - (air.dark ? 0.0 : 0.03), pal.ground[1], pal.ground[2]], air.hazeAt(pal.dxSun(x)), 0.4));
      for (let i = 6; i < r.pts.length - 6; i += 5) {
        const p = r.pts[i], q2 = r.pts[i + 5];
        const tx = q2[0] - p[0], ty = q2[1] - p[1];
        const across = Math.abs(tx) / (Math.hypot(tx, ty) || 1);
        const hy = r.half[i][1];
        if (across < 0.86 || hy < 0.7) continue;
        const broken = smoothstep(0.34, 0.6, fb(i / 23 + 4.4, 1.7, 2));
        const al = (air.dark ? 0.5 : 0.3) * broken * (1 - 0.6 * dusk) * (1 - 0.7 * lightNight);
        lens(W, (p[0] + q2[0]) / 2, (p[1] + q2[1]) / 2 - hy * 0.62, Math.abs(tx) * 0.9 + 2, Math.max(0.6, hy * 0.6), bank(p[0]), al);
      }
    }

    // 4. The light. The low sky's brightest passage lies on the water, strongest on the reaches
    //    nearest the light's own x (at dawn the sun comes up out of the fold gutter and the far reaches
    //    burn); under a moon it is silver and faint.
    const lampAmt = pal.byMoon ? 0.45 * pal.moonlight : clamp01(air.glowAmt * 1.5) * smoothstep(-9, -2, pal.altDeg) * (1 - 0.55 * smoothstep(6, 25, pal.altDeg));
    const glowLab = pal.byMoon ? air.silver : mix3(air.glow, air.sun, 0.25);
    const reach = G.Wa * (pal.byMoon ? 0.9 : 0.8);
    const nearLamp = (x) => Math.exp(-Math.abs(x - pal.lamp.x) / reach);
    if (lampAmt > 0.02) {
      const M = scratch('rw', w, h);
      M.fillStyle = hGrad(M, (x) => css(pal.shown([glowLab[0] + 0.05, glowLab[1], glowLab[2]]), clamp01(lampAmt * 1.7 * nearLamp(x))), 20);
      M.fillRect(bx, by, bw, bh);
      M.globalCompositeOperation = 'destination-in';
      const fall = M.createLinearGradient(0, py(c.H0), 0, py(c.H0 + 380));
      fall.addColorStop(0, 'rgba(0,0,0,1)'); fall.addColorStop(0.1, 'rgba(0,0,0,0.9)'); fall.addColorStop(0.35, 'rgba(0,0,0,0.45)'); fall.addColorStop(1, 'rgba(0,0,0,0.16)');
      M.fillStyle = fall;
      M.fillRect(bx, by, bw, bh);
      W.drawImage(M.canvas, bx, by, bw, bh, bx, by, bw, bh);
    }
    // The smear: where a far reach lies under the light — in line with it, or nearly — the brightest
    // of the low sky stands in the water below as a soft upright smear.
    const toward = Math.sign(pal.lamp.x - r.def.vx) || 1;
    const bends = [];                                     // the bends on the light's side: where the centre line turns back
    for (let i = 8; i < r.pts.length - 8; i += 1) {
      const p = r.pts[i];
      if ((p[0] - r.pts[i - 8][0]) * toward <= 0 || (p[0] - r.pts[i + 8][0]) * toward <= 0) continue;
      if ((p[0] - r.pts[i - 1][0]) * toward < 0 || (p[0] - r.pts[i + 1][0]) * toward <= 0) continue;
      bends.push(i);
    }
    if (lampAmt > 0.03) {
      for (const i of bends) {
        const p = r.pts[i];
        const hw = r.half[i][0], d = p[1] - c.H0;
        const k = lampAmt * nearLamp(p[0]) * (1 - smoothstep(0.12, 0.5, depthOf(p[1])));
        if (k < 0.04 || hw < 1.5) continue;
        const x = p[0] + toward * hw * 0.2;
        const rx = Math.max(2.2, hw * 0.55), ry = Math.max(3, Math.min(46, d * 0.34));
        W.save();
        W.translate(px(x), py(p[1] + ry * 0.35));
        W.scale(rx * s, ry * s);
        const g = W.createRadialGradient(0, -0.35, 0, 0, 0, 1);
        const col = pal.shown([glowLab[0] + 0.04, glowLab[1], glowLab[2]]);
        const al = clamp01(1.5 * k);
        g.addColorStop(0, css(col, al)); g.addColorStop(0.4, css(col, al * 0.5)); g.addColorStop(1, css(col, 0));
        W.fillStyle = g;
        W.fillRect(-1, -1, 2, 2);
        W.restore();
      }
    }
    // The near reach: the one bend that sits in the leading margin column is the brightest water in
    // the picture — the palest of the low sky above it lies in it as one soft upright smear (under a
    // moon: silver), hanging from the bend and letting go toward you.
    {
      let best = -1;
      for (const i of bends) if (depthOf(r.pts[i][1]) > 0.62 && (best < 0 || r.pts[i][1] < r.pts[best][1])) best = i;
      if (best < 0) best = Math.round(0.86 * (r.pts.length - 1));
      const p = r.pts[best], hw = r.half[best][0];
      const dx = pal.dxSun(p[0]);
      let top = air.skyAt(dx, 0.03);
      for (const e of [0.012, 0.07, 0.12]) { const q2 = air.skyAt(dx, e); if (q2[0] > top[0]) top = q2; }
      const warm = pal.byMoon ? air.silver : mix3(top, glowLab, 0.3 * clamp01(lampAmt * 1.4));
      const col = pal.shown([Math.max(top[0], waterAt(p[0], p[1])[0]) + (air.dark ? 0.085 : 0.03), warm[1], warm[2]]);
      if (pal.deepNight > 0) col[0] = lerp(col[0], NIGHT_WATER + 0.012, pal.deepNight);
      const al = (air.dark ? 0.8 : 0.9) * (1 - 0.5 * lightNight);
      W.save();
      W.translate(px(p[0] - toward * hw * 0.12), py(p[1] + 26));
      W.scale(hw * 0.86 * s, 82 * s);
      const g = W.createRadialGradient(0, -0.3, 0, 0, 0, 1);
      g.addColorStop(0, css(col, al)); g.addColorStop(0.35, css(col, al * 0.62)); g.addColorStop(0.7, css(col, al * 0.2)); g.addColorStop(1, css(col, 0));
      W.fillStyle = g;
      W.fillRect(-1, -1, 2, 2);
      W.restore();
    }
    // Level streaks across the near and the middle reach, bank to bank, a tone apart: the sheen is
    // broken by the wind in lanes. (Level strokes on a receding plane are what say "water".)
    for (let k = 0; k < 15; k += 1) {
      const t = 0.36 + 0.62 * ((k + 0.25 + 0.5 * hash(k, 541)) / 15);
      const i = Math.min(r.pts.length - 1, Math.round(t * (r.pts.length - 1)));
      const p = r.pts[i], hw = r.half[i][0];
      if (hw < 4) continue;
      const d = p[1] - c.H0;
      const here = waterAt(p[0], p[1]);
      const x = p[0] + (hash(k, 543) - 0.5) * hw * 0.7;
      const lightOne = k % 3 === 1;
      const lab = lightOne
        ? shownW([here[0] + (air.dark ? 0.05 : 0.02), here[1] * 0.8, here[2] * 0.8])
        : shownW(mix3([here[0] - (air.dark ? 0.04 : 0.04), here[1], here[2]], pal.ground, 0.3));
      if (pal.deepNight > 0) lab[0] = lerp(lab[0], NIGHT_WATER + (lightOne ? 0.01 : -0.012), pal.deepNight);
      lens(W, x, p[1], hw * (0.5 + 0.4 * hash(k, 545)), Math.max(0.8, (0.006 + 0.010 * hash(k, 546)) * d),
        lab, (lightOne ? 0.5 : 0.3 + 0.16 * hash(k, 547)) * (1 - 0.5 * lightNight));
    }
    // A few short level glints, where the sheen is brightest. Sparse; never sparkle.
    {
      const amt = (pal.byMoon ? 0.6 * pal.moonlight : 0.3 + 0.7 * smoothstep(-8, 2, pal.altDeg)) * (1 - 0.65 * dusk);
      const glints = [[0.325, 0.1, 2.2], [0.455, -0.15, 2.0], [0.545, 0.2, 3.0], [0.625, 0.0, 2.4], [0.70, 0.25, 4.0], [0.79, 0.05, 3.0], [0.885, 0.2, 4.6]];
      for (const [t, side, halfLen] of glints) {
        const i = Math.round(t * (r.pts.length - 1));
        const p = r.pts[i], hw = r.half[i][0];
        const lean = 0.2 * clamp((pal.lamp.x - p[0]) / G.Wa, -1, 1);
        const x = p[0] + (side + lean) * hw, y = p[1];
        const low = air.skyAt(pal.dxSun(x), 0.02);
        const near = nearLamp(x);
        const lab = mix3([low[0] + 0.07, low[1] * 0.9, low[2] * 0.9], [glowLab[0] + 0.05, glowLab[1], glowLab[2]], 0.6 * near * clamp01(lampAmt * 1.5));
        lens(W, x, y, Math.min(halfLen, Math.max(1.2, hw * 0.4)), Math.max(0.42, Math.min(0.75, 0.3 + (y - c.H0) * 0.0013)), pal.shown(lab), clamp01(amt * (0.55 + 0.4 * near)));
      }
    }
    // The moon's broken path: while the moon lights the night, a ladder of short level dashes of its
    // silver down the near reach, on the side the moon is — thin lines of light, not an area (in the
    // dark appearance each is a hair over a card's value and half a point deep).
    if (pal.byMoon && pal.moonlight > 0.05) {
      const silver = air.show([air.dark ? lerp(0.30, 0.26, pal.B.depth) : 0.985, air.silver[1] * 0.7, air.silver[2] * 0.7]);
      for (let k = 0; k < 13; k += 1) {
        const t = 0.50 + 0.47 * ((k + 0.5 * hash(k, 571)) / 13);
        const i = Math.min(r.pts.length - 1, Math.round(t * (r.pts.length - 1)));
        const p = r.pts[i], hw = r.half[i][0];
        if (hw < 3) continue;
        const d = p[1] - c.H0;
        const x = p[0] + toward * hw * (0.18 + 0.2 * (hash(k, 572) - 0.5));
        lens(W, x, p[1], Math.max(1.6, hw * (0.16 + 0.2 * hash(k, 573)) * (0.6 + 0.4 * Math.sin(k * 1.7) ** 2)), Math.max(0.4, Math.min(0.9, d * 0.0026)),
          silver, clamp01((air.dark ? 0.55 : 0.8) * pal.moonlight * (0.6 + 0.4 * hash(k, 574))));
      }
    }
    plain(W);
    W.globalCompositeOperation = 'source-over';
    a.globalAlpha = 1 - 0.42 * lightNight;
    a.drawImage(W.canvas, bx, by, bw, bh, bx, by, bw, bh);
    a.globalAlpha = 1;

    // What the opening of the Duo lights (drawLand): the water itself and the mist that lies along
    // the river's own course — kept as one small layer, in the far plane's pixels.
    {
      const ex = Math.round(70 * s);
      const lx = Math.max(0, bx - ex), lw = Math.min(w, bx + bw + ex) - lx;
      const cv = mk(lw, bh);
      const L = cv.getContext('2d');
      L.translate(-lx, -by);
      // the water: its own shape, at half strength
      L.globalAlpha = 0.6;
      L.drawImage(W.canvas, bx, by, bw, bh, bx, by, bw, bh);
      L.globalAlpha = 1;
      L.globalCompositeOperation = 'source-in';
      L.fillStyle = '#fff';
      L.fillRect(lx, by, lw, bh);
      L.globalCompositeOperation = 'source-over';
      // the mist: a run of level puffs along the river, far to near — thin and close far away, broad near
      for (let i = 0, k = 0; i < r.pts.length; k += 1) {
        const p = r.pts[i], hw = r.half[i][0];
        const d = Math.max(2, p[1] - c.H0);
        const rx = 9 + hw * 1.9 + d * 0.10, ry = Math.max(1.6, d * 0.052);
        const al = (0.30 + 0.32 * hash(k, 581)) * (0.55 + 0.45 * smoothstep(0.3, 0.6, fb(k / 3.1 + 2.2, 8.8, 2)));
        L.save();
        L.translate(px(p[0] + (hash(k, 582) - 0.5) * hw * 1.2), py(p[1] - ry * 0.25));
        L.scale(rx * s, ry * s);
        const g = L.createRadialGradient(0, 0.2, 0, 0, 0, 1);
        g.addColorStop(0, `rgba(255,255,255,${al})`); g.addColorStop(0.5, `rgba(255,255,255,${al * 0.6})`); g.addColorStop(1, 'rgba(255,255,255,0)');
        L.fillStyle = g;
        L.fillRect(-1, -1, 2, 2);
        L.restore();
        // the next one: a little under a puff's own depth further down the river
        let j = i + 1;
        while (j < r.pts.length && Math.abs(r.pts[j][1] - p[1]) < ry * 0.9 && Math.abs(r.pts[j][0] - p[0]) < rx * 0.8) j += 1;
        i = j;
      }
      G.riverLight = { canvas: cv, x: lx, y: by, y0 };
    }

    // 5. A sandbar inside the near bend, and reeds at the water's edge in a few places: the bank is
    //    not a line, it is things standing in front of the water.
    {
      const land = (x) => mix3(pal.ground, air.hazeAt(pal.dxSun(x)), 0.3);
      // reeds: [how far down the river, which bank, how many]
      const inkL = pal.shown(mix3([pal.ground[0] - (air.dark ? 0.05 : 0.14), pal.ground[1] * 1.2, pal.ground[2] * 1.2], pal.ink, 0.45));
      a.lineCap = 'round';
      for (const [t, side, count, spread] of [[0.585, 1, 9, 0.5], [0.69, -1, 12, 0.6], [0.775, 1, 15, 0.7], [0.845, -1, 18, 0.8], [0.93, 1, 16, 0.8], [0.50, -1, 7, 0.4]]) {
        const i = Math.round(t * (r.pts.length - 1));
        for (let k = 0; k < count; k += 1) {
          const j = clamp(i + Math.round((hash(k * 7 + i, 591) - 0.5) * 26 * spread), 1, r.pts.length - 2);
          const e = side > 0 ? r.right[j] : r.left[j];
          const d = e[1] - c.H0;
          const hgt = d * (0.020 + 0.022 * hash(k + i, 592));
          const x = e[0] + (hash(k + i, 593) - 0.5) * 3 - side * 0.02 * d * hash(k + i, 596), y = e[1] + (hash(k + i, 594) - 0.5) * 0.012 * d;
          const lean = (hash(k + i, 595) - 0.4) * 0.28 * hgt;
          a.strokeStyle = css(inkL, air.dark ? 0.9 : 0.62);
          a.lineWidth = Math.max(0.5, d * 0.0028) * s;
          a.beginPath();
          a.moveTo(px(x), py(y));
          a.quadraticCurveTo(px(x + lean * 0.2), py(y - hgt * 0.6), px(x + lean), py(y - hgt));
          a.stroke();
          // …and its reflection, shorter and fainter, in the water beneath it
          a.strokeStyle = css(inkL, air.dark ? 0.32 : 0.2);
          a.beginPath();
          a.moveTo(px(x), py(y));
          a.lineTo(px(x - lean * 0.4), py(y + hgt * 0.55));
          a.stroke();
        }
      }
    }

    // 6. Mist lies on the far and the middle reaches: the river goes into it and comes out again.
    for (const [mx, my, rx, ry, amt] of r.def.mist) {
      const lit = clamp01(lampAmt * 1.2 * nearLamp(mx));
      const col = pal.shown(mix3(air.mistAt(pal.dxLamp(mx), pal.dxSun(mx)), [glowLab[0], glowLab[1], glowLab[2]], 0.5 * lit));
      if (pal.deepNight > 0) col[0] = lerp(col[0], NIGHT_MIST, pal.deepNight);
      const al = clamp01(amt * (0.35 + 0.75 * pal.mistAmt) * mistK);
      a.save();
      a.translate(px(mx), py(my));
      a.scale(rx * s, ry * s);
      const g = a.createRadialGradient(0, 0.25, 0, 0, 0, 1);
      g.addColorStop(0, css(col, al)); g.addColorStop(0.45, css(col, al * 0.8)); g.addColorStop(0.8, css(col, al * 0.25)); g.addColorStop(1, css(col, 0));
      a.fillStyle = g;
      a.fillRect(-1, -1, 2, 2);
      a.restore();
    }
  }

  // ── mist ─────────────────────────────────────────────────────────────

  /** A level band of mist, tinted along x by the light it catches. Drawn straight into `ctx`
   *  (plane pixels when y0 is a plane's, display pixels with an offset otherwise). */
  function mistCanvas(band, pal, mask) {
    const s = G.s, air = pal.air;
    if (band.pools && !mask) return null;
    const x0 = mask ? mask.x0 : Math.max(band.x0, G.xL), x1 = mask ? mask.x0 + mask.w : Math.min(band.x1, G.xR);
    if (x1 - x0 < 8) return null;
    const w = Math.ceil((x1 - x0) * s), h = Math.ceil((mask ? mask.h : band.h) * s);
    const c = mk(w, h);
    const ctx = c.getContext('2d');
    ctx.fillStyle = (() => {
      const grad = ctx.createLinearGradient(0, 0, w, 0);
      const tint = (x) => {
        let raw = air.mistAt(pal.dxLamp(x), pal.dxSun(x));
        // under the low sun the mist in a hollow is the most luminous thing in the land: it takes the glow
        const nearSun = pal.byMoon ? 0 : Math.exp(-Math.abs(pal.dxSun(x)) / 0.32) * air.lastLight * (1 - smoothstep(5, 12, pal.altDeg));
        if (nearSun > 0.01) raw = mix3(raw, [Math.max(raw[0], air.glow[0]) + 0.03, air.glow[1], air.glow[2]], 0.5 * nearSun);
        const q = pal.shown(raw);
        // dark, at night: a breath of mist — held at one quiet value (under a card's), whatever the room's depth
        if (pal.deepNight > 0) q[0] = lerp(q[0], NIGHT_MIST, pal.deepNight);
        // the pale page at night: paler than the land and nearly its colour — never blue puddles
        if (!air.dark) { const k = 1 - 0.62 * pal.nightness; q[1] *= k; q[2] *= k; }
        return css(q, lerp(0.62 + 0.38 * Math.exp(-Math.abs(pal.dxLamp(x)) / 0.55), 1, pal.deepNight) * (air.dark ? 1 : 1 - 0.3 * pal.nightness));
      };
      grad.addColorStop(0, tint(x0));
      for (let x = Math.ceil((x0 + 0.01) / 30) * 30; x < x1; x += 30) grad.addColorStop((x - x0) / (x1 - x0), tint(x));
      grad.addColorStop(1, tint(x1));
      return grad;
    })();
    ctx.fillRect(0, 0, w, h);
    if (mask) {
      // a pool: its own mask, enlarged (the enlarging is its softness)
      ctx.globalCompositeOperation = 'destination-in';
      ctx.imageSmoothingEnabled = true;
      ctx.imageSmoothingQuality = 'high';
      ctx.drawImage(mask.canvas, 0, 0, mask.w, mask.h, 0, 0, mask.w * s, mask.h * s);
      return { canvas: c, x0, w, h, y: mask.y0 };
    }
    // its own stretch of the mist texture (never the same stretch twice), its ends thinning out
    const m = scratch('b', w, h);
    if (w <= X.mist.width) {
      const full = Math.ceil((band.x1 - band.x0) * s);
      const tx = (band.seed * 397) % Math.max(1, X.mist.width - full) + Math.round((x0 - band.x0) * s);
      m.drawImage(X.mist, Math.min(tx, X.mist.width - w), 0, w, X.mist.height, 0, 0, w, h);
    } else {
      m.drawImage(X.mist, 0, 0, X.mist.width, X.mist.height, 0, 0, w, h);
    }
    m.globalCompositeOperation = 'destination-in';
    const ends = m.createLinearGradient(0, 0, w, 0);
    const fadeL = band.x0 >= G.xL ? Math.min(0.3, 90 / (x1 - x0)) : 0, fadeR = band.x1 <= G.xR ? Math.min(0.3, 90 / (x1 - x0)) : 0;
    ends.addColorStop(0, `rgba(0,0,0,${fadeL > 0 ? 0 : 1})`);
    if (fadeL > 0) ends.addColorStop(fadeL, 'rgba(0,0,0,1)');
    if (fadeR > 0) ends.addColorStop(1 - fadeR, 'rgba(0,0,0,1)');
    ends.addColorStop(1, `rgba(0,0,0,${fadeR > 0 ? 0 : 1})`);
    m.fillStyle = ends;
    m.fillRect(0, 0, w, h);
    ctx.globalCompositeOperation = 'destination-in';
    ctx.drawImage(m.canvas, 0, 0, w, h, 0, 0, w, h);
    return { canvas: c, x0, w, h, y: band.y };
  }

  function drawMistBand(ctx, band, pal, y0, offX, alphaK, cached) {
    const m = cached ?? mistCanvas(band, pal);
    if (!m) return;
    const s = G.s;
    ctx.globalAlpha = clamp01(pal.mistAmt * band.amt * alphaK);
    ctx.drawImage(m.canvas, (m.x0 - G.xL) * s + offX, (band.y - y0) * s);
    ctx.globalAlpha = 1;
  }

  // ── the tree ─────────────────────────────────────────────────────────

  function paintTree(pal, burns) {
    const t = G.tree;
    const m = t.masks;
    if (!t.canvas || t.canvas.width !== m.w || t.canvas.height !== m.h) t.canvas = mk(m.w, m.h);
    const ctx = t.canvas.getContext('2d');
    const s = G.s;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.globalCompositeOperation = 'source-over';
    ctx.globalAlpha = 1;
    ctx.clearRect(0, 0, m.w, m.h);
    // In the light print the hush pulls every colour toward the page; the tree keeps most of its own
    // (a ghost-grey tree on a pale page is the one thing the hush must not make).
    const C = pal.dark ? pal.C : (lab) => css(pal.shown(lab, { presence: Math.max(pal.air.presence, 0.82) }));
    const lay = (mask, colour, alpha = 1) => {
      if (!mask) return;
      ctx.globalAlpha = alpha;
      ctx.drawImage(tinted(mask, colour), 0, 0, m.w, m.h, 0, 0, m.w, m.h);
      ctx.globalAlpha = 1;
    };
    // the direction of the light, from the tree
    let dx = pal.lamp.x - t.x, dy = pal.lamp.y - (t.baseY - t.h * 0.55);
    const dist = Math.hypot(dx, dy) || 1;
    dx /= dist; dy /= dist;
    /** The part of `mask` that faces the light: itself, less itself slid away from it. */
    const facingMask = (mask, reach) => {
      const a = scratch('a', m.w, m.h);
      a.drawImage(mask, 0, 0);
      a.globalCompositeOperation = 'destination-out';
      a.drawImage(mask, -dx * reach, -dy * reach);
      const c = mk(m.w, m.h);
      c.getContext('2d').drawImage(a.canvas, 0, 0, m.w, m.h, 0, 0, m.w, m.h);
      return c;
    };
    const power = Math.min(1, pal.lamp.power * (pal.byMoon ? 0.6 : 1));
    /** A disc of light behind the tree burns out the twigs in front of it and eats into the limbs:
     *  `mask` with those places thinned (twigs: gone; wood: `keep` of it left). */
    const burnt = (mask, keep) => {
      if (!burns.length) return mask;
      const c = mk(m.w, m.h);
      const x = c.getContext('2d');
      x.drawImage(mask, 0, 0);
      x.globalCompositeOperation = 'destination-out';
      for (const b of burns) {
        const bx = m.cx + (b.x - t.x) * s, by = m.cy + (b.y - t.baseY) * s;
        const r0 = b.r * s, r1 = (b.r + 2.2) * s;
        const g = x.createRadialGradient(bx, by, 0, bx, by, r1);
        g.addColorStop(0, `rgba(0,0,0,${(1 - keep) * b.power})`);
        g.addColorStop(r0 / r1, `rgba(0,0,0,${(1 - keep) * b.power})`);
        g.addColorStop(1, 'rgba(0,0,0,0)');
        x.fillStyle = g;
        x.fillRect(bx - r1, by - r1, 2 * r1, 2 * r1);
      }
      return c;
    };
    /** Leaves and flowers are composed apart — `build(add)` lays its masks with add(mask, colour, alpha) —
     *  and then opened where a disc of light stands behind them, so the sun is seen THROUGH the crown:
     *  thinned a little all over the disc (`keep` of them left), and, given `gaps` (masks of single
     *  leaves), those leaves taken out whole — the disc comes through leaf-shaped holes, not through
     *  a ghost of the crown. Then set down on the tree. */
    const foliage = (keep, build, gaps, feather = 4.5) => {
      const g = scratch('tl', m.w, m.h);
      build((mask, colour, alpha = 1) => {
        if (!mask || !(alpha > 0.012)) return;
        g.globalAlpha = Math.min(1, alpha);
        g.drawImage(tinted(mask, colour), 0, 0, m.w, m.h, 0, 0, m.w, m.h);
        g.globalAlpha = 1;
      }, g);
      for (const b of burns) {
        const bx = m.cx + (b.x - t.x) * s, by = m.cy + (b.y - t.baseY) * s;
        const r0 = b.r * s, r1 = (b.r + feather) * s;
        const disc = (c, amount) => {
          const gr = c.createRadialGradient(bx, by, 0, bx, by, r1);
          gr.addColorStop(0, `rgba(0,0,0,${amount})`);
          gr.addColorStop((r0 * 0.8) / r1, `rgba(0,0,0,${amount})`);
          gr.addColorStop(1, 'rgba(0,0,0,0)');
          c.fillStyle = gr;
          c.fillRect(bx - r1, by - r1, 2 * r1, 2 * r1);
        };
        if (gaps) {
          const a = scratch('a', m.w, m.h);
          for (const gap of gaps) a.drawImage(gap, 0, 0);
          a.globalCompositeOperation = 'destination-in';
          disc(a, b.power);
          g.globalCompositeOperation = 'destination-out';
          g.drawImage(a.canvas, 0, 0, m.w, m.h, 0, 0, m.w, m.h);
        }
        g.globalCompositeOperation = 'destination-out';
        disc(g, (1 - keep) * b.power);
        g.globalCompositeOperation = 'source-over';
      }
      ctx.drawImage(g.canvas, 0, 0, m.w, m.h, 0, 0, m.w, m.h);
    };
    const leaf = m.leaf;
    const snowC = pal.dark ? css(pal.air.show(pal.snow)) : C(pal.snow);
    // (the twigs lie under the leaf. In leaf the tree hands over only the twigs that are in sight — in a full crown
    // the ones that lead to leaves, across the holes and along the bare arm; more as it thins. Bare — the default
    // day — they are the whole crown.)
    lay(burnt(leaf ? leaf.twigs : m.twigs, 0), C(pal.ink), pal.dark ? 0.92 : 0.9);
    // the far side of the crown, behind the limbs: cooler, darker, softer — and the crown's whole silhouette
    if (leaf) foliage(0.88, (add) => add(leaf.back, C(pal.leafShade)), [leaf.gaps]);
    lay(burnt(m.wood, 0.5), C(pal.ink));
    if (power > 0.05) lay(facingMask(m.wood, 1.1 * s), C(pal.inkLit), power * (pal.dark ? 0.55 : 0.5));
    // snow on the level twigs: a hair of it (in the low key snow is a line of light, not an area — it does not take the night's cap)
    lay(m.snowFine, snowC, (pal.dark ? 0.62 : 0.8) * pal.sea.snow);
    // (the lamp's direction as the crown takes it: a sun going down beside the tree lights it from the side, not from underneath)
    const lampN = Math.hypot(dx, Math.min(dy, 0.3)) || 1;
    const lampX = dx / lampN, lampY = Math.min(dy, 0.3) / lampN;
    /** `mask` in `colour`, let through `wash` (a gradient made on the context it is handed): → scratch A, use at once. */
    const washed = (mask, colour, wash) => {
      const a = scratch('a', m.w, m.h);
      a.drawImage(tinted(mask, colour), 0, 0, m.w, m.h, 0, 0, m.w, m.h);
      a.globalCompositeOperation = 'destination-in';
      a.fillStyle = wash(a);
      a.fillRect(0, 0, m.w, m.h);
      return a.canvas;
    };
    /** Light that comes THROUGH the crown where a low sun stands behind it: most beside the disc, dying away across the crown. */
    const through = power * pal.backlit * (pal.byMoon ? 0 : 1);
    const aura = (amount) => (a) => {
      const sx = m.cx + (pal.lamp.x - t.x) * s, sy = m.cy + (pal.lamp.y - t.baseY) * s;
      const r0 = G.cfg.sunR * s, r1 = r0 + t.h * 0.62 * s;
      const gr = a.createRadialGradient(sx, sy, r0 * 0.5, sx, sy, r1);
      gr.addColorStop(0, `rgba(0,0,0,${Math.min(1, amount)})`);
      gr.addColorStop(0.28, `rgba(0,0,0,${Math.min(1, 0.6 * amount)})`);
      gr.addColorStop(0.62, `rgba(0,0,0,${Math.min(1, 0.2 * amount)})`);
      gr.addColorStop(1, 'rgba(0,0,0,0)');
      return gr;
    };
    /** …and light that falls ACROSS the crown: nothing on its far side, `amount` on the side toward the lamp. */
    const across = (amount) => (a) => {
      const mx = m.cx, my = m.cy - t.h * 0.60 * s, R = t.h * 0.50 * s;
      const gr = a.createLinearGradient(mx - lampX * R, my - lampY * R, mx + lampX * R, my + lampY * R);
      gr.addColorStop(0, 'rgba(0,0,0,0)');
      gr.addColorStop(0.3, 'rgba(0,0,0,0)');
      gr.addColorStop(1, `rgba(0,0,0,${Math.min(1, amount)})`);
      return gr;
    };
    if (leaf) {
      // how open the crown is (spring's first leaves, autumn's last): an open crown is never a dark mass against the sun
      const open = clamp01(0.9 * pal.sea.leafFall + 1.2 * (1 - pal.sea.foliage));
      foliage(0.9, (add, g) => {
        // the near masses, in the leaf's own paints
        // (against a low sun a full crown is in its own shade: only its edge and its thin places are lit)
        const contre = (pal.dark ? 0.45 : 0.30) * pal.backlit * power * (1 - 0.8 * open);
        leaf.body.forEach((mask, k) => add(mask, C(mix3(pal.leafBody[k], pal.leafCore, contre))));
        // every leaf is turned some way: those turned from the lamp are the mass's shadowed core, those
        // turned to it catch it — and by day the ones that face the sky take a little of its light
        const skyLight = pal.dark ? 0.55 * (0.3 + 0.7 * pal.air.day) * (1 - 0.75 * pal.nightness) : 0.6 * (0.4 + 0.6 * pal.air.day);
        const rimOnly = lerp(0.02, 0.42, pal.backlit);          // a low sun behind the crown lights only its edge
        for (let i = 0; i < 8; i += 1) {
          const ax = Math.cos((i * TAU) / 8), ay = Math.sin((i * TAU) / 8);
          const f = ax * lampX + ay * lampY;
          const lit = clamp01(power * (1 - 0.45 * pal.backlit) * smoothstep(rimOnly, 0.95, f));
          const sky = skyLight * smoothstep(0.25, 1, -ay) * (1 - lit);
          // (the underside of every bough is in its own shade, whatever the lamp)
          const shade = clamp01(Math.max((0.30 + 0.60 * power) * smoothstep(0.05, 0.95, -f), 0.5 * smoothstep(0.15, 0.95, ay))) * (1 - lit) * (1 - 0.4 * open);
          add(leaf.turned[i], C(pal.leafCore), shade);
          add(leaf.turned[i], C(pal.leafSky), sky);
          add(leaf.turned[i], C(pal.leafLit), lit);
        }
        if (through > 0.03) {
          g.drawImage(washed(leaf.thin, C(pal.leafGlow), aura(through * (1 + 0.6 * open))), 0, 0, m.w, m.h, 0, 0, m.w, m.h);
          // …and a full crown's own edge catches it where it faces the disc and stands near it: a rim of
          // lit leaves beside the sun, gone a little way along the crown (never an outline all round)
          const rim = scratch('rim', m.w, m.h);
          rim.drawImage(leaf.back, 0, 0);
          rim.globalCompositeOperation = 'destination-out';
          rim.drawImage(leaf.back, -lampX * 1.1 * s, -lampY * 1.1 * s);
          const edge = mk(m.w, m.h);
          edge.getContext('2d').drawImage(rim.canvas, 0, 0, m.w, m.h, 0, 0, m.w, m.h);
          g.drawImage(washed(edge, C(mix3(pal.leafGlow, pal.air.rim, 0.35)), aura(1.5 * through * (1 - open) * (1 - open))), 0, 0, m.w, m.h, 0, 0, m.w, m.h);
        }
      }, [leaf.gaps]);
    }
    lay(m.lastLeaves, C(pal.lastLeaf));
    if (m.blossomA) {
      foliage(0.12, (add, g) => {
        add(m.blossomB, C(pal.blossomShade));
        add(m.blossomA, C(pal.blossom));
        // the flowers on the lamp's side of the crown are lit
        if (power > 0.05) g.drawImage(washed(m.blossomA, C(pal.blossomLit), across(0.85 * power)), 0, 0, m.w, m.h, 0, 0, m.w, m.h);
      }, null, 1.2);
    }
    lay(m.frost, C(pal.frost), pal.dark ? 0.28 : 0.34);
    // snow: a cap along the limbs, and the foot of the cap — the half point of it next the wood — in its own blue shade
    lay(m.snow, snowC);
    if (m.snow) {
      const a = scratch('a', m.w, m.h);
      a.drawImage(m.snow, 0, 0);
      a.globalCompositeOperation = 'destination-out';
      a.drawImage(m.snow, 0, -Math.max(1, Math.round(0.5 * s)));
      const foot = [pal.snow[0] - (pal.dark ? 0.11 : 0.085), pal.snow[1] - 0.004, pal.snow[2] - 0.024];
      const footC = pal.dark ? css(pal.air.show(foot)) : C(foot);
      const c = mk(m.w, m.h);
      c.getContext('2d').drawImage(a.canvas, 0, 0, m.w, m.h, 0, 0, m.w, m.h);
      lay(c, footC, 0.7);
    }
  }

  // ── his stars ────────────────────────────────────────────────────────

  let sprites = null;
  function buildSprites(s) {
    const out = { s };
    const size = Math.ceil(28 * s);
    const tints = { cool: lch(0.94, 0.04, 255), plain: lch(0.985, 0.008, 95), warm: lch(0.955, 0.055, 82), rose: lch(0.93, 0.05, 20), tonight: lch(0.965, 0.07, 84), ink: lch(0.40, 0.05, 285), white: lch(1, 0, 0) };
    for (const [name, lab] of Object.entries(tints)) {
      // a dot: a clean small light, the faintest breath around it (drawn at radius 6 pt)
      const d = mk(size, size);
      let ctx = d.getContext('2d');
      const g = ctx.createRadialGradient(size / 2, size / 2, 0, size / 2, size / 2, 14 * s);
      g.addColorStop(0, css(lab, 1)); g.addColorStop(0.36, css(lab, 1)); g.addColorStop(0.43, css(lab, 0.55)); g.addColorStop(0.5, css(lab, 0.15)); g.addColorStop(0.7, css(lab, 0.05)); g.addColorStop(1, css(lab, 0));
      ctx.fillStyle = g;
      ctx.fillRect(0, 0, size, size);
      out[`dot-${name}`] = d;
      // four-point: cut by hand, the arms not quite equal (arm length 10 pt)
      const c = mk(size, size);
      ctx = c.getContext('2d');
      ctx.translate(size / 2, size / 2);
      ctx.rotate(0.06);
      ctx.fillStyle = css(lab);
      const arms = [10, 7.2, 9.3, 6.9];
      ctx.beginPath();
      for (let i = 0; i < 4; i += 1) {
        const a = -Math.PI / 2 + (i * Math.PI) / 2, b = a + Math.PI / 4;
        ctx.lineTo(Math.cos(a) * arms[i] * s, Math.sin(a) * arms[i] * s);
        ctx.lineTo(Math.cos(b) * 1.05 * s, Math.sin(b) * 1.05 * s);
      }
      ctx.closePath();
      ctx.fill();
      ctx.beginPath();
      ctx.arc(0, 0, 1.9 * s, 0, TAU);
      ctx.fill();
      out[`glint-${name}`] = c;
    }
    // tonight's star: hair-thin flares and a small clean core — a point of light, never a disc
    for (const [name, lab] of [['tonight', tints.tonight], ['white', tints.white]]) {
      const c = mk(size, size);
      const ctx = c.getContext('2d');
      ctx.translate(size / 2, size / 2);
      ctx.rotate(0.05);
      ctx.fillStyle = css(lab);
      const arms = [12.5, 8.6, 11.4, 8.2];
      for (let i = 0; i < 4; i += 1) {
        const a = -Math.PI / 2 + (i * Math.PI) / 2;
        const ux = Math.cos(a), uy = Math.sin(a), vx = -uy, vy = ux;
        const L = arms[i] * s, wdt = 0.5 * s;
        ctx.beginPath();
        ctx.moveTo(vx * wdt, vy * wdt);
        ctx.quadraticCurveTo(ux * L * 0.3 + vx * wdt * 0.35, uy * L * 0.3 + vy * wdt * 0.35, ux * L, uy * L);
        ctx.quadraticCurveTo(ux * L * 0.3 - vx * wdt * 0.35, uy * L * 0.3 - vy * wdt * 0.35, -vx * wdt, -vy * wdt);
        ctx.closePath();
        ctx.fill();
      }
      ctx.beginPath();
      ctx.arc(0, 0, 1.55 * s, 0, TAU);
      ctx.fill();
      out[`spark-${name}`] = c;
    }
    // a soft round glow, and its dark twin for the light page (radius = half the sprite)
    const soft = (lab, falloff) => {
      const c = mk(size, size);
      const ctx = c.getContext('2d');
      const g = ctx.createRadialGradient(size / 2, size / 2, 0, size / 2, size / 2, size / 2);
      for (let i = 0; i <= 10; i += 1) g.addColorStop(i / 10, css(lab, Math.pow(1 - i / 10, falloff)));
      ctx.fillStyle = g;
      ctx.fillRect(0, 0, size, size);
      return c;
    };
    out.glowWarm = soft(lch(0.93, 0.08, 80), 2.2);
    out.glowCool = soft(lch(0.9, 0.04, 255), 2.2);
    out.dusk = soft(lch(0.62, 0.07, 280), 1.6);
    // the light page's star stands on a soft patch of slightly deeper sky: no edge, so never a ring round a dot
    out.deep = soft(lch(0.56, 0.085, 283), 3.2);
    out.firefly = soft(lch(0.93, 0.13, 104), 2.4);
    // a snowflake: a small clean light (a core two thirds of its radius, then gone) — and a softer, nearer one
    out.flake = (() => {
      const c = mk(size, size);
      const ctx = c.getContext('2d');
      const lab = lch(0.985, 0.006, 250);
      const g = ctx.createRadialGradient(size / 2, size / 2, 0, size / 2, size / 2, size / 2);
      g.addColorStop(0, css(lab, 1)); g.addColorStop(0.40, css(lab, 0.96)); g.addColorStop(0.62, css(lab, 0.3)); g.addColorStop(0.8, css(lab, 0.06)); g.addColorStop(1, css(lab, 0));
      ctx.fillStyle = g;
      ctx.fillRect(0, 0, size, size);
      return c;
    })();
    out.flakeNear = soft(lch(0.985, 0.006, 250), 1.5);
    out.size = size;
    return out;
  }

  /** Rects no star may sit behind, in LOOKED-UP display points (anchor window's own x). */
  function starKeepOuts(state) {
    const c = G.cfg, L = state.layout ?? {};
    const outs = [];
    const pad = (b, p) => ({ x0: b.x - G.ox - p, y0: b.y - p, x1: b.x - G.ox + b.width + p, y1: b.y + b.height + p });
    const header = [];
    if (L.name && L.age) {
      // avatar, name and age are one block: no star squeezes between them
      const x0 = Math.min(L.name.x, L.age.x, L.avatar ? L.avatar.x : Infinity), x1 = Math.max(L.name.x + L.name.width, L.age.x + L.age.width);
      const y0 = Math.min(L.name.y, L.avatar ? L.avatar.y : Infinity), y1 = Math.max(L.age.y + L.age.height + 10, L.avatar ? L.avatar.y + L.avatar.height : 0);
      // (one em of clear sky past the last glyph: a star on the baseline after "old" reads as punctuation)
      header.push(pad({ x: x0, y: y0, width: x1 - x0 + 13, height: y1 - y0 }, 7));
    } else if (L.avatar) header.push(pad(L.avatar, 2));
    if (L.gear) header.push(pad(L.gear, 3));
    for (const r of header) {
      outs.push(r);                                                    // looking up
      outs.push({ x0: r.x0 - c.T, x1: r.x1 - c.T, y0: r.y0 + c.D, y1: r.y1 + c.D });   // at rest
    }
    if (c.kind === 'duo') {
      const sx = (L.stripClear?.x ?? 362) + 20 - G.ox;                 // the strip's own column
      outs.push({ x0: sx - 2, x1: G.Wa + 4, y0: -10, y1: 192 });       // clock, island, status icons
      outs.push({ x0: sx + 8 - c.T, x1: G.Wa + 4 - c.T, y0: 14 + c.D, y1: 44 + c.D });   // …and, at rest, the clock
      outs.push({ x0: sx + 4, x1: G.Wa + 4, y0: 388, y1: 652 });       // the tab capsule
    } else {
      outs.push({ x0: -10, x1: G.Wa + 10, y0: -10, y1: 64 });          // the status bar and the island
    }
    return outs;
  }

  function starsFor(state) {
    const c = G.cfg;
    const L = state.layout ?? {};
    const key = [state.ageDays, state.tonightLit, c.kind, G.Wa, L.name?.x, L.name?.width, L.age?.width, L.gear?.x].join('|');
    if (G.stars.key === key) return G.stars;
    const outs = starKeepOuts(state);
    const hLook = c.H0 + c.D;
    const t = G.tree;
    const treeLook = { x: t.x - c.T, y: t.baseY + c.D };
    // tonight's star: its place looking up (the clear window), and where it is at rest, in looked-up points
    const tonightLook = { x: c.tonightUp.x, y: c.tonightUp.y };
    const tonightRest = { x: c.tonight.x - c.T, y: c.tonight.y + c.D };
    /** The lowest a star may sit at looked-up x: clear of the land's skyline and of the tree's crown. */
    const floor = (x) => {
      let bottom = G.skyline(x + c.T) + c.D - 8;
      const u = (x - treeLook.x) / t.h;
      const top = crownTop(u);
      if (top != null) bottom = Math.min(bottom, treeLook.y + top * t.h - 5);
      return Math.min(bottom, hLook - 12);
    };
    const xMin = 5, xMax = G.Wa - 5;
    const yMin = c.kind === 'duo' ? 7 : 66;
    // The looked-up sky is the night's picture now, so it is laid out for THAT view, in boxes, top to
    // bottom: [x0, x1, y0, y1, density, columns [x0, x1, weight]…]. A box's share of his stars is its
    // area × density. Thickest overhead and thinning toward the land, as a sky is; a few more in the
    // header's clear gap; fewer in the strip's clear window, where tonight's star is to be the one
    // bright thing with a little company; and, low down, the part of the sky the REST pose shows in
    // the header band and the strip (the night he is awake) is never empty.
    const SW = c.kind === 'duo' ? (state.layout?.stripClear?.x ?? state.phone.x + 362) - G.ox : G.Wa;   // where the strip's window begins
    const boxes = c.kind === 'duo'
      ? [[207, 313, yMin, 97, 0.85, null],
        [xMin, SW + 16, 99, 187, 0.80, null],
        [xMin, xMax, 187, c.D, 0.70, [[xMin, SW, 1], [SW, xMax, 0.85]]],
        // (at rest this band is the header: its words and buttons stand at x < 116 here, its clear gap at 116–232)
        [xMin, xMax, c.D, c.D + 88, 0.95, [[xMin, 116, 0.12], [116, 232, 1.7], [232, SW, 0.9], [SW, xMax, 0.55]]],
        [xMin, SW + 22, c.D + 88, hLook - 10, 0.70, [[xMin, SW - c.T, 0.7], [SW - c.T, SW + 14, 2.3], [SW + 14, SW + 22, 0.5]]]]   // (at rest: the strip, beside the tree)
      : [[206, 337, yMin, 138, 0.75, null],
        [xMin, xMax, 146, c.D + 60, 0.50, null],
        [xMin, xMax, c.D + 60, hLook - 8, 1.05, [[xMin, 160, 0.5], [160, G.Wa - c.T, 1.5], [G.Wa - c.T, xMax, 0.5]]]];   // (at rest: the header's small landscape)
    let boxTotal = 0;
    for (const bx of boxes) { bx.push((bx[1] - bx[0]) * (bx[3] - bx[2]) * bx[4]); boxTotal += bx[6]; }
    const place = (star) => {
      let acc = 0, box = boxes[boxes.length - 1], v = star.v;
      for (const bx of boxes) { const share = bx[6] / boxTotal; if (star.v < acc + share) { box = bx; v = (star.v - acc) / share; break; } acc += share; }
      const cols = box[5] ?? [[box[0], box[1], 1]];
      let total = 0;
      for (const [x0, x1, w] of cols) total += (x1 - x0) * w;
      let x = box[1], a2 = 0;
      for (const [x0, x1, w] of cols) {
        const part = ((x1 - x0) * w) / total;
        if (star.u <= a2 + part) { x = x0 + ((star.u - a2) / part) * (x1 - x0); break; }
        a2 += part;
      }
      const y1 = Math.min(box[3], floor(x));
      const y = box[2] + v * Math.max(4, y1 - box[2]);
      // (an even sprinkle is a pattern: the sky is gathered a little, slowly, into loose knots with
      // open sky between them — a smooth drift of every place, the same for every night)
      const wx = (fb(x / 150 + 3.7, y / 150 + 1.3, 2) - 0.5) * 2, wy = (fb(x / 150 + 9.1, y / 150 + 6.6, 2) - 0.5) * 2;
      const amt = c.kind === 'duo' ? 30 : 26;
      return { x: clamp(x + wx * amt, xMin + 1, xMax - 1), y: Math.max(yMin + 1, Math.min(y + wy * amt, floor(x) - 1)) };
    };
    const apart = Math.max(5.6 * c.starScale, 5.6);     // (never closer: on the light page two stars' soft patches would run together)
    const list = [];
    const free = (x, y, big) => {
      if (x < xMin || x > xMax || y < yMin || y > floor(x)) return false;
      const wide = big ? 9 : 0;                           // (a four-point star keeps further from the words and the buttons: beside a line of text it is an asterisk)
      for (const r of outs) if (x > r.x0 - wide && x < r.x1 + wide && y > r.y0 - wide && y < r.y1 + wide) return false;
      // tonight's star has dark sky of its own round it in the clear window (and no four-point star
      // near enough to be taken for it); beside the tree, at rest, a smaller clearing
      if (Math.hypot(x - tonightLook.x, y - tonightLook.y) < (big ? 70 : 30 * c.starScale)) return false;
      if (Math.hypot(x - tonightRest.x, y - tonightRest.y) < 17) return false;
      for (const o of list) {
        const gap = (o.kind === 'night' ? apart : apart + 5) + (big ? 5 : 0);
        if (Math.abs(x - o.lx) < gap && Math.hypot(x - o.lx, y - o.ly) < gap) return false;
      }
      return true;
    };
    for (const star of nights(state.ageDays, { tonightLit: state.tonightLit })) {
      if (star.kind === 'tonight') {
        list.push({ ...star, lx: tonightLook.x, ly: tonightLook.y });
        continue;
      }
      // the first night — the brightest star in his sky — has a place of its own where the night's
      // view shows it with the cards on (if that place is free on this display)
      const at = star.kind === 'first' && c.firstUp && free(c.firstUp.x, c.firstUp.y, false) ? { ...c.firstUp } : place(star);
      const big = star.kind !== 'night';
      let { x, y } = at;
      // One star per night has to be countable: a place that is taken, hidden or behind the
      // words gives way to the nearest free one — judged only against the nights before it.
      if (!free(x, y, big)) {
        let found = false;
        // first, cast again: the night's own second, third… place, anywhere in the sky (the nearest
        // free place would line the stars up along the edge of whatever they could not sit behind)
        for (let k = 1; k <= 30 && !found; k += 1) {
          const fr = (v2) => v2 - Math.floor(v2);
          const again = place({ ...star, u: fr(star.u + k * 0.6180339887), v: fr(star.v + k * 0.7548776662) });
          if (free(again.x, again.y, big)) { x = again.x; y = again.y; found = true; }
        }
        for (let ring = 1; ring <= 40 && !found; ring += 1) {
          for (let k = 0; k < 12; k += 1) {
            const a = (k / 12 + hash(star.night, 31) + ring * 0.07) * TAU, r = ring * apart * 0.6;
            const nx = at.x + Math.cos(a) * r, ny = at.y + Math.sin(a) * r * 0.9;
            if (free(nx, ny, big)) { x = nx; y = ny; found = true; break; }
          }
        }
      }
      list.push({ ...star, lx: x, ly: y });
    }
    // world coordinates (rest pose): the looked-up place, turned back and lowered (tonight's: its place beside the tree)
    for (const st of list) { st.x = st.lx + c.T; st.y = st.ly - c.D; if (st.kind === 'tonight') { st.x = c.tonight.x; st.y = c.tonight.y; } }
    // The ordinary sky of the leading page (nobody's stars), on the whole tall sky: fainter than
    // his, as thick as his at the fold — so that, looking up, there is no boundary where the anchor
    // window begins — and thinning and dimming to the far left. It fills as his does (a newborn's
    // sky is not upstaged by the page beside it).
    const far = [];
    if (G.ox > 0) {
      const span = G.ox + c.T - 2;                         // from the fold (looking up) to the leading edge
      const count = clamp(Math.round(1.12 * list.length * (span / G.Wa) * 0.84), 80, 460);
      const expShare = 0.36, fall = 190;
      const title = L.title ? { x0: L.title.x - G.ox - 8, x1: L.title.x - G.ox + Math.max(L.title.width, L.subtitle ? L.subtitle.width : 0) + 22, y0: L.title.y - 8, y1: (L.subtitle ? L.subtitle.y + L.subtitle.height : L.title.y + L.title.height) + 8 } : null;
      for (let n = 0; n < count; n += 1) {
        // how far left of the fold: a third of them crowd toward it, the rest lie evenly
        const u = hash(n, 41);
        const left = hash(n, 47) < expShare ? -fall * Math.log(1 - u * (1 - Math.exp(-span / fall))) : u * span;
        const x = c.T - 2 - left;                          // world x (the fold, looking up, is at T)
        const sky = G.skyline(x) + c.D - 14;               // the looked-up sky's foot there
        // a few more low in the sky, where the everyday view shows them (its top band, the margin, the gutter)
        const v = hash(n, 42);
        const yl = hash(n, 48) < 0.09 ? c.D + 5 + v * 96 : 6 + Math.pow(v, 0.95) * (sky - 6);
        if (title && x > title.x0 && x < title.x1 && yl - c.D > title.y0 && yl - c.D < title.y1) continue;   // (at rest: not behind the page's title)
        const near = Math.exp(-left / 300);                // 1 at the fold … 0.15 at the far edge
        const m = Math.pow(hash(n, 43), 2.2);              // most are faint, a few are bright
        far.push({ x, y: yl - c.D, m, r: (0.5 + 0.72 * m) * (0.86 + 0.14 * near), a: (0.46 + 0.5 * m) * (0.6 + 0.4 * near),
          tint: hash(n, 49) < 0.42 ? 'cool' : hash(n, 49) < 0.9 ? 'plain' : 'warm', phase: hash(n, 45), period: 3 + 4 * hash(n, 46), steady: hash(n, 44) > 0.6 });
      }
    }
    G.stars = { key, list, far, tonightLook };
    return G.stars;
  }

  /** The band of light that leaves tonight's star at bedtime: where it leaves from, its radius now
   *  (points), its pace and its strength. It leaves once the view is all but up (2.1 s: the star is
   *  then within a few points of its place in the clear window) and from THAT place, fixed on the
   *  display — so it never wobbles with the camera — and it crosses the anchor window to its
   *  farthest corner in 2.4 s: his last star has answered by 4.5 s and settled before the cards begin
   *  to come back (4.8 s). The pace is the anchor window's, so the spread's phone page is the cover's
   *  picture at every instant of it; over the leading page it goes on, and dies away. */
  function ringOf(state, tilt) {
    const e = state.event;
    if (!e || e.kind !== 'bedtime' || state.asleep !== 'night' || state.reduceMotion) return null;
    const age = e.age - 2.1;
    if (age <= 0) return null;
    const c = G.cfg;
    const at = tonightHome(1, tilt);
    const foot = c.H0 + c.D + (c.kind === 'duo' ? 74 : 104);     // the display's foot, looking up (the cover's: the spread is 9 pt shorter)
    const far = Math.hypot(Math.max(c.tonightUp.x, G.Wa - c.tonightUp.x), Math.max(c.tonightUp.y, foot - c.tonightUp.y));
    const speed = far / 2.4;
    const radius = speed * age;
    const strength = smoothstep(0, 0.4, age) * (1 - smoothstep(far * 1.04, far * 1.3, radius));
    if (strength <= 0.003) return null;
    return { radius, strength, age, at, far, speed };
  }

  function drawStars(ctx, state, pal, time, off, ring) {
    const s = G.s, c = G.cfg;
    const out = pal.starsOut;
    const asleepNight = state.asleep === 'night';
    const bed = state.event && state.event.kind === 'bedtime' && asleepNight ? state.event.age : null;
    if (!(out > 0.004) && !ring) return;
    const stars = starsFor(state);
    const scale = c.starScale;
    const still = time == null ? 1 : 1 - 0.6 * pal.B.depth;
    const lead = state.lead == null ? 1 : clamp01(state.lead);
    const light = !pal.dark;
    const moonAt = pal.moonNow;
    const mR = c.moonR + 5;
    // A little brighter once he is down; the sky has gone deeper.
    const settle = 1 + 0.1 * pal.B.depth * (bed == null ? 1 : smoothstep(4, 8, bed));
    ctx.globalCompositeOperation = 'source-over';
    /** As the ring passes: [swell — a breath that rises fast and lets go; kept — what stays with a star that is out]. */
    const paceK = ring ? ring.speed / 250 : 1;           // (the swell's lengths were set for a band going 250 pt/s: the same breath in time at any pace)
    const answer = (x, y) => {
      if (!ring) return 0;
      const since = (ring.radius - Math.hypot(x - ring.at.x, y - ring.at.y)) / paceK;
      if (since < -26) return 0;
      const pulse = since < 0 ? Math.exp(-((since / 10) ** 2)) : Math.exp(-((since / 95) ** 2));
      return pulse * Math.sqrt(ring.strength);
    };
    const passed = (x, y) => (ring ? smoothstep(-10, 30, (ring.radius - Math.hypot(x - ring.at.x, y - ring.at.y)) / paceK) : bed != null && bed > 2.1 ? 1 : 0);
    // In a sky still too light for stars (a July bedtime) the band shows them one by one — and they keep
    // a faint presence behind it while the cards are away, so the held frame is a sky of stars, not a
    // crescent of them; they are let go as the cards come back over the sky.
    const kept = bed == null ? 0 : 0.34 * smoothstep(2.1, 2.8, bed) * (1 - smoothstep(4.8, 6.8, bed));

    // the ordinary sky of the leading page
    if (stars.far.length) {
      const horizonY = c.H0 + c.D * pal.look + off.tiltY;
      // Opening the Duo at night: the valley's light is starlight. In the bare second the page's stars
      // come out from the fold outward — once, slowly: dim until the front reaches them, a small
      // swell as it passes, then themselves. (By day there are none; under Reduce Motion nothing moves.)
      const openAge = state.event && state.event.kind === 'open' && !state.reduceMotion ? state.event.age : null;
      const foldX = G.ox - 10, frontAt = openAge == null ? Infinity : 560 * Math.max(0, openAge - 0.12);
      const T1 = lead > 0 ? state.layout?.title : null;
      const T2 = T1 ? state.layout.subtitle : null;
      for (const f of stars.far) {
        const x = G.ox + f.x + off.x, y = f.y + off.y;
        if (y < -4 || y > G.H + 4 || x < -4) continue;
        const tw = time == null || f.steady ? 0.94 : 1 - 0.3 * (0.5 - 0.5 * Math.cos(TAU * (time / f.period + f.phase))) * still;
        let wave = answer(x, y);
        let arrived = 1;
        if (openAge != null) {
          const since = frontAt - (foldX - x);
          arrived = 0.4 + 0.6 * smoothstep(-30, 60, since);
          if (since > -30) wave = Math.max(wave, out * 0.75 * Math.exp(-(((since - 20) / 110) ** 2)) * smoothstep(-30, 10, since));
        }
        let a = f.a * Math.max(out, wave * 0.8, kept * 0.5 * passed(x, y)) * tw * (light ? 0.8 : 0.9) * (1 + 0.6 * wave) * settle * arrived;
        if (f.x > -3) a *= smoothstep(0.55, 1, pal.look);     // the anchor window's sky is his alone, until the camera has turned past it
        a *= 0.35 + 0.65 * smoothstep(4, 46, horizonY - y);   // thinned by the air near the horizon
        // none behind the leading page's title when it is there
        if (T1 && x > T1.x - 8 && x < T1.x + T1.width + 8 && y > T1.y - 8 && y < (T2 ? T2.y + T2.height : T1.y + T1.height) + 8) a *= 1 - lead;
        if (a < 0.006) continue;
        const r = f.r * s * scale * (1 + 0.3 * wave);
        if (light) {
          // (as his are drawn on the pale page — small crisp points, the few bright ones as small glints — and fainter)
          if (f.m > 0.62) {
            const half = (2.8 + 2.4 * (f.m - 0.62) / 0.38) * s * scale * (1 + 0.3 * wave);
            ctx.globalAlpha = clamp01(a * 0.4);
            ctx.drawImage(sprites.deep, x * s - half * 1.7, y * s - half * 1.7, half * 3.4, half * 3.4);
            ctx.globalAlpha = clamp01(a);
            ctx.drawImage(sprites['glint-white'], x * s - half, y * s - half, half * 2, half * 2);
            continue;
          }
          ctx.globalAlpha = clamp01(a * 0.26 * (0.5 + 0.5 * f.m));
          ctx.drawImage(sprites.deep, x * s - r * 5.2, y * s - r * 5.2, r * 10.4, r * 10.4);
        }
        ctx.globalAlpha = clamp01(a);
        const sprite = sprites[`dot-${light ? 'white' : f.tint}`];
        const rr = light ? r * 0.82 : r;
        ctx.drawImage(sprite, x * s - rr * 2.33, y * s - rr * 2.33, rr * 4.66, rr * 4.66);
      }
    }

    for (const star of stars.list) {
      if (star.kind === 'tonight') continue;               // lit over everything: see drawTonight
      let x = G.ox + star.x + off.x, y = star.y + off.y;
      if (y < -8 || y > G.H + 8) continue;
      if (moonAt) {
        const dx = x - moonAt.x, dy = y - moonAt.y;
        const d = Math.hypot(dx, dy);
        if (d < mR) {
          const a = d < 0.01 ? hash(star.night, 9) * TAU : Math.atan2(dy, dx);
          x = moonAt.x + Math.cos(a) * mR; y = moonAt.y + Math.sin(a) * mR;
        }
      }
      const tw = time == null ? 0.92 : 1 - (1 - twinkle(star, time)) * still;
      const wave = answer(x, y);
      // out in the order of brightness as the sky darkens; the ring shows any of them for a breath
      const threshold = (1 - star.magnitude) * 0.8;
      const shown = smoothstep(threshold - 0.05, threshold + 0.2, out);
      // a real range: most nights are small faint lights, a few are bright (m: 0 the faintest … 1)
      const m = clamp01((star.magnitude - 0.22) / 0.5);
      let alpha = (light ? 0.74 + 0.26 * m : 0.50 + 0.50 * Math.pow(m, 0.6)) * tw * shown * settle;
      if (bed != null) alpha *= 1 + 0.22 * passed(x, y) * (1 - smoothstep(5.5, 12, bed));   // (it keeps a fifth more light, and lets it go slowly into the settled night's own)
      alpha = Math.max(alpha, wave * (0.6 + 0.4 * star.magnitude), kept * passed(x, y) * (0.6 + 0.4 * m)) + 0.4 * wave * shown;
      // thinned by the air near the horizon
      const horizonY = c.H0 + (c.D * pal.look) + off.tiltY;
      alpha *= 0.4 + 0.6 * smoothstep(4, 46, horizonY - y);
      if (!(alpha > 0.006)) continue;
      const grow = 1 + 0.45 * wave;
      const px = x * s, py = y * s;
      const tint = light ? 'white' : star.warmth > 0.3 ? 'warm' : star.warmth < -0.25 ? 'cool' : hash(star.night, 8) > 0.9 ? 'rose' : 'plain';
      if (star.kind === 'first' || star.kind === 'month') {
        const half = 14 * s * scale * (star.kind === 'first' ? 0.78 : 0.52) * grow;
        if (light) {
          ctx.globalAlpha = clamp01(alpha * 0.55);
          ctx.drawImage(sprites.deep, px - half * 1.5, py - half * 1.5, half * 3, half * 3);
        } else {
          ctx.globalAlpha = clamp01(alpha * 0.16);
          const g = star.warmth > 0 ? sprites.glowWarm : sprites.glowCool;
          ctx.drawImage(g, px - half * 0.7, py - half * 0.7, half * 1.4, half * 1.4);
        }
        ctx.globalAlpha = clamp01(alpha);
        ctx.drawImage(sprites[`glint-${tint}`], px - half, py - half, half * 2, half * 2);
      } else {
        const r = (0.52 + 0.95 * Math.pow(m, 0.85)) * s * scale * grow;
        if (light) {
          // On a pale page a light needs a little deeper sky around it — a soft patch, never a disc.
          // And a field of soft round white dots is falling snow: so here the faint nights are small
          // crisp points with hardly any patch, and the brighter fifth are drawn as stars are drawn on
          // paper — small four-point glints, each on its own bit of dusk.
          if (m > 0.6) {
            const half = (3.4 + 3.0 * (m - 0.6) / 0.4) * s * scale * grow;
            ctx.globalAlpha = clamp01(alpha * 0.5);
            ctx.drawImage(sprites.deep, px - half * 1.7, py - half * 1.7, half * 3.4, half * 3.4);
            ctx.globalAlpha = clamp01(alpha);
            ctx.drawImage(sprites['glint-white'], px - half, py - half, half * 2, half * 2);
            continue;
          }
          const rl = (0.56 + 0.62 * m) * s * scale * grow;
          ctx.globalAlpha = clamp01(alpha * (0.22 + 0.4 * m));
          ctx.drawImage(sprites.deep, px - rl * 5.2, py - rl * 5.2, rl * 10.4, rl * 10.4);
          ctx.globalAlpha = clamp01(alpha);
          ctx.drawImage(sprites['dot-white'], px - rl * 2.33, py - rl * 2.33, rl * 4.66, rl * 4.66);
          continue;
        } else if (m > 0.5) {
          // the few bright ones carry a small soft glow
          ctx.globalAlpha = clamp01(alpha * 0.13 * (m - 0.5) * 2);
          const gs = star.warmth > 0 ? sprites.glowWarm : sprites.glowCool;
          ctx.drawImage(gs, px - r * 4, py - r * 4, r * 8, r * 8);
        }
        ctx.globalAlpha = clamp01(alpha);
        ctx.drawImage(sprites[`dot-${tint}`], px - r * 2.33, py - r * 2.33, r * 4.66, r * 4.66);
      }
    }
    ctx.globalAlpha = 1;
  }

  /** Tonight's star: the evening star above the tree's shoulder. Drawn over the land, so
   *  nothing ever hides it; it travels with the tree. */
  function drawTonight(ctx, state, pal, time, at, ring) {
    const lit = state.tonightLit;
    const wake = state.event && state.event.kind === 'wake' ? state.event.age : null;
    if (!lit && wake == null) return;
    const s = G.s, c = G.cfg;
    const bed = state.event && state.event.kind === 'bedtime' && state.asleep === 'night' ? state.event.age : null;
    let spark = bed == null ? 1 : ignition(bed);
    if (!lit && wake != null) spark = 1 - smoothstep(0.4, 4.5, wake);       // morning: it cools and joins the rest
    if (!(spark > 0.004)) return;
    const breath = time == null ? 0.94 : 0.86 + 0.14 * Math.cos((TAU * time) / 5.2);
    const k = Math.min(spark, 1.35);
    const px = at.x * s, py = at.y * s;
    // (while the sun is still up — a July bedtime — it is a small evening star beside the sun, not a second light)
    const sunUp = smoothstep(-4, 3, pal.altDeg);
    // Beside the tree it is an accent to the tree, and small. In the clear window, looking up, it is the
    // night's one bright star and the subject of what the cards leave open: larger, with a fuller glow
    // and four short rays between the long ones. It grows into that on the way up.
    const up = clamp01(pal.look ?? 0);
    const dim = sunUp * (1 - 0.45 * up);                 // (…but in the clear window it is the one thing there, and is kept findable)
    const scale = c.starScale * (1 - 0.4 * dim) * (1 + 0.42 * up);
    ctx.globalCompositeOperation = 'source-over';
    if (pal.dark) {
      // a tight warm glow: the room stays dark
      const quiet = 0.5 + 0.5 * (1 - pal.nightness);     // a little more of it while there is still light in the sky
      for (const [radius, a] of [[12 + 3 * up, (0.07 + 0.02 * up) * quiet], [6 - 0.6 * up, 0.25 + 0.02 * up]]) {
        const r = radius * s * scale * (0.7 + 0.3 * k) * breath;
        ctx.globalAlpha = clamp01(a * k * (1 - 0.55 * dim));
        ctx.drawImage(sprites.glowWarm, px - r, py - r, r * 2, r * 2);
      }
    } else {
      // on a light page: a little dusk gathered round it, so the cream star shows
      const r = 26 * s * scale * (0.7 + 0.3 * k) * breath;
      ctx.globalAlpha = clamp01(0.62 * k);
      ctx.drawImage(sprites.deep, px - r, py - r, r * 2, r * 2);
    }
    const half = 14 * s * scale * (0.62 + 0.38 * k);
    const sprite = sprites[`spark-${pal.dark ? 'tonight' : 'white'}`];
    if (up > 0.02) {
      const h2 = half * 0.44;
      ctx.save();
      ctx.translate(px, py);
      ctx.rotate(Math.PI / 4);
      ctx.globalAlpha = clamp01(k) * 0.62 * up * (0.9 + 0.1 * breath);
      ctx.drawImage(sprite, -h2, -h2, h2 * 2, h2 * 2);
      ctx.restore();
    }
    ctx.globalAlpha = clamp01(k) * (0.9 + 0.1 * breath);
    ctx.drawImage(sprite, px - half, py - half, half * 2, half * 2);
    if (spark > 1) {                                     // past full: the spark
      ctx.globalAlpha = clamp01((spark - 1) * 2);
      const r = 2.4 * s;
      ctx.drawImage(sprites['dot-white'], px - r * 2.33, py - r * 2.33, r * 4.66, r * 4.66);
    }
    // The ring is not a line: one soft band of light going out across the sky, once — feathered
    // on both sides, brightest just behind its leading edge, a long soft trail inside it, and
    // fading as it grows so that it has all but gone before it reaches the far corner. It only
    // tells the eye where to look; the stars answering as it passes carry the gesture (they answer
    // to `ring.strength`, which lasts the whole way — the band's own light does not).
    if (ring) {
      const R = ring.radius;
      const farC = ring.far;
      // (it is never a small tight circle round the star — that is sonar: it comes up out of nothing as
      // it leaves, broad and soft, is fullest a third of the way across, and has gone by nine tenths)
      const band = smoothstep(farC * 0.03, farC * 0.34, R) * (1 - smoothstep(farC * 0.36, farC * 0.9, R));
      if (band > 0.004) {
        // (it leaves from the star's place in the clear window, which does not move: `ring.at`)
        const bx = ring.at.x * s, by = ring.at.y * s;
        const Wd = 54 + R * 0.14;                         // it widens as it goes
        const r0 = Math.max(0, R - Wd * 0.6), r1 = R + Wd * 0.5;
        const tint = pal.dark ? lch(0.88, 0.05, 84) : lch(0.995, 0.012, 95);
        const peak = (pal.dark ? 0.085 : 0.22) * band;
        // (distance from the crest, in band-widths → how much of the peak: a soft swell with no edge on
        // either side — a drawn arc is what a hard leading edge makes — and a short trail, so the sky
        // inside is not left lighter than the sky outside it: no dome)
        const profile = [[-0.6, 0], [-0.48, 0.05], [-0.36, 0.16], [-0.25, 0.36], [-0.15, 0.62], [-0.07, 0.86], [0, 1], [0.07, 0.9], [0.15, 0.68], [0.24, 0.4], [0.33, 0.18], [0.42, 0.05], [0.5, 0]];
        // It is light in the SKY: drawn small (it has no detail), let go well above the horizon — its
        // foot never stands on the land — and laid over the picture once.
        const q = 0.25;
        const bw2 = Math.ceil(G.pxW * q) + 1, bh2 = Math.ceil(G.pxH * q) + 1;
        const b = scratch('band', bw2, bh2);
        b.setTransform(q, 0, 0, q, 0, 0);
        const g = b.createRadialGradient(bx, by, r0 * s, bx, by, r1 * s);
        for (const [u, a] of profile) g.addColorStop(clamp01((R + u * Wd - r0) / (r1 - r0)), css(tint, peak * a));
        b.fillStyle = g;
        const x0 = Math.max(0, (ring.at.x - r1) * s), y0 = Math.max(0, (ring.at.y - r1) * s);
        const x1 = Math.min(G.pxW, (ring.at.x + r1) * s), y1 = Math.min(G.pxH, (ring.at.y + r1) * s);
        b.fillRect(x0, y0, x1 - x0, y1 - y0);
        b.globalCompositeOperation = 'destination-in';
        const hy = (c.H0 + c.D * pal.look) * s;
        const fall = b.createLinearGradient(0, hy - 150 * s, 0, hy - 22 * s);
        fall.addColorStop(0, 'rgba(0,0,0,1)'); fall.addColorStop(0.45, 'rgba(0,0,0,0.62)'); fall.addColorStop(1, 'rgba(0,0,0,0)');
        b.fillStyle = fall;
        b.fillRect(0, 0, G.pxW, G.pxH);
        ctx.save();
        ctx.globalAlpha = 1;
        ctx.globalCompositeOperation = pal.dark ? 'lighter' : 'source-over';
        ctx.imageSmoothingEnabled = true;
        ctx.drawImage(b.canvas, 0, 0, bw2, bh2, 0, 0, bw2 / q, bh2 / q);
        ctx.restore();
      }
    }
    ctx.globalAlpha = 1;
  }

  // ── small life: fireflies, leaves, petals, snow, a shooting star ─────

  function drawLife(ctx, state, pal, time, offKnoll, look) {
    const s = G.s, c = G.cfg;
    const sea = pal.sea;
    const tr = G.tree;
    const knoll = G.shape('knoll');
    const dab = (sprite, x, y, r, alpha) => {
      if (!(alpha > 0.01)) return;
      ctx.globalAlpha = clamp01(alpha);
      ctx.drawImage(sprite, (G.ox + x + offKnoll.x) * s - r * s, (y + offKnoll.y) * s - r * s, r * 2 * s, r * 2 * s);
    };
    ctx.globalCompositeOperation = 'source-over';

    // Leaves lying under the tree, and a few on their way down (petals in spring).
    const falling = Math.max(sea.leafFall * (0.3 + 0.7 * sea.foliage), sea.petals * 0.8);
    if (falling > 0.03) {
      const petals = sea.petals * 0.8 > sea.leafFall;
      const key = `${petals}|${pal.C(petals ? pal.blossom : pal.lastLeaf)}`;
      if (!G.leafSprite || G.leafSprite.key !== key) {
        const size = Math.ceil(8 * s);
        const cv = mk(size, size);
        const x = cv.getContext('2d');
        x.fillStyle = pal.C(petals ? pal.blossom : pal.lastLeaf);
        x.beginPath();
        x.ellipse(size / 2, size / 2, size * 0.42, size * 0.27, 0.5, 0, TAU);
        x.fill();
        G.leafSprite = { key, canvas: cv };
      }
      const sp = G.leafSprite.canvas;
      const lying = Math.max(4, Math.round(22 * falling));
      for (let i = 0; i < lying; i += 1) {
        const x = tr.x + (hash(i, 101) - 0.5) * tr.h * 1.0;
        const y = knoll.at(x) + 1.5 + Math.pow(hash(i, 102), 1.5) * 12;
        dab(sp, x, y, 0.7 + 0.5 * hash(i, 103), 0.75);
      }
      const adrift = Math.round(7 * falling);
      for (let i = 0; i < adrift; i += 1) {
        const period = 30 + 16 * hash(i, 104);
        const f = time == null ? hash(i, 105) : (((time / period + hash(i, 105)) % 1) + 1) % 1;
        const x = tr.x + (hash(i, 106) - 0.5) * tr.h * 0.7 + Math.sin(f * 9 + i) * 6 + f * 9;
        const y = tr.baseY - tr.h * 0.7 + f * tr.h * 0.74;
        dab(sp, x, y, 1.0, Math.sin(Math.PI * f) * 0.9);
      }
    }

    // Fireflies beneath the tree on summer evenings, from the last of the sun on.
    const dusk = sea.fireflies * (1 - smoothstep(-2.5, 3.5, pal.altDeg)) * (1 - 0.5 * smoothstep(-14, -30, -pal.altDeg));
    if (dusk > 0.02) {
      const count = Math.round(12 + 14 * (G.W / 466));
      for (let i = 0; i < count; i += 1) {
        let x, y;
        if (i < 12) {
          x = tr.x - tr.h * 0.6 + hash(i, 121) * tr.h * 1.2;
          y = i < 4 ? tr.baseY - 5 - hash(i, 122) * tr.h * 0.3 : knoll.at(x) + 3 + hash(i, 122) * tr.h * 0.5;
        } else {
          x = -G.ox + hash(i, 121) * (G.W + c.T);
          y = Math.max(G.skyline(x), c.H0) + 16 + hash(i, 122) * 120;
        }
        if (!Number.isFinite(y)) continue;
        const period = 3.6 + 3.2 * hash(i, 123);
        let glow;
        if (time == null) glow = hash(i, 124) < 0.55 ? 0.85 : 0;
        else {
          glow = Math.pow(Math.max(0, Math.sin(TAU * (time / period + hash(i, 124)))), 2.2);
          x += 5 * Math.sin(TAU * (time / 23 + hash(i, 125)));
          y += 3 * Math.sin(TAU * (time / 17 + hash(i, 126)));
        }
        glow *= 1 - 0.4 * pal.B.depth;
        dab(sprites.firefly, x, y, 5.5, glow * dusk * (pal.dark ? 0.26 : 0.5));
        dab(sprites.firefly, x, y, 1.5, glow * dusk);
      }
    }
    ctx.globalAlpha = 1;
  }

  /** Snow in the air, on the days it snows: three depths, slow. Fixed to the display, not the world. */
  function drawSnowfall(ctx, state, pal, time) {
    const amount = pal.sea.snowfall;
    if (!(amount > 0.02)) return;
    const s = G.s;
    const t = time ?? 0;
    // many and small: most are far (a fine dust of them, slow), a few are near (larger, a little
    // soft, quicker) — depth, not dots
    const count = Math.round((G.W * G.H) / 620 * amount);
    const sunny = 0.55 + 0.45 * smoothstep(-12, 6, pal.altDeg);
    ctx.globalCompositeOperation = 'source-over';
    for (let i = 0; i < count; i += 1) {
      const depth = Math.pow(hash(i, 111), 2.4);
      const span = G.H + 40;
      const y = ((hash(i, 112) * span + t * (6 + 20 * depth)) % span) - 20;
      let x = hash(i, 113) * (G.W + 60) - 30 + (3 + 10 * depth) * Math.sin(t * (0.22 + 0.2 * hash(i, 114)) + hash(i, 115) * TAU) + t * (0.6 + 1.6 * depth);
      x = ((x % (G.W + 60)) + G.W + 60) % (G.W + 60) - 30;
      const r = 0.55 + 1.0 * depth;
      ctx.globalAlpha = clamp01((pal.dark ? 0.30 + 0.5 * depth : 0.62 + 0.38 * depth) * sunny * (0.75 + 0.25 * hash(i, 116)));
      const sp = depth > 0.55 ? sprites.flakeNear : sprites.flake;
      ctx.drawImage(sp, (x - r * 1.5) * s, (y - r * 1.5) * s, r * 3 * s, r * 3 * s);
    }
    ctx.globalAlpha = 1;
  }

  /** Rarely, and never under Reduce Motion: one shooting star, about a second long. */
  function drawShootingStar(ctx, pal, time, off) {
    if (time == null || pal.starsOut < 0.9 || !pal.dark) return;
    const cycle = 140;
    const k = Math.floor(time / cycle);
    const tt = time - k * cycle - 61;
    if (tt < 0 || tt > 1.1) return;
    const s = G.s;
    const f = tt / 1.1;
    const x0 = G.ox + 60 + hash(k, 91) * G.Wa * 0.5 + off.x, y0 = G.cfg.H0 * (0.12 + 0.3 * hash(k, 92)) + off.y;
    const angle = (18 + 16 * hash(k, 93)) * DEG;
    const hx = x0 + Math.cos(angle) * 90 * f, hy = y0 + Math.sin(angle) * 90 * f;
    const tail = 30 * Math.sin(Math.PI * f);
    const tx = hx - Math.cos(angle) * tail, ty = hy - Math.sin(angle) * tail;
    const grad = ctx.createLinearGradient(tx * s, ty * s, hx * s, hy * s);
    grad.addColorStop(0, 'rgba(255, 246, 228, 0)');
    grad.addColorStop(1, `rgba(255, 246, 228, ${0.7 * Math.sin(Math.PI * f)})`);
    ctx.save();
    ctx.strokeStyle = grad;
    ctx.lineWidth = 1.0 * s;
    ctx.lineCap = 'round';
    ctx.beginPath();
    ctx.moveTo(tx * s, ty * s);
    ctx.lineTo(hx * s, hy * s);
    ctx.stroke();
    ctx.restore();
  }

  /** "✦ Night 143": the page's one line, at the foot on the side away from the tree, while the
   *  cards are away at bedtime. (In the app: a SwiftUI Text, not the sky's.) */
  function drawCaption(ctx, state, pal, look) {
    if (state.asleep !== 'night' || !(state.veil > 0.01)) return;
    const bed = state.event && state.event.kind === 'bedtime' ? state.event.age : null;
    // It arrives as the view comes to rest and has gone as the cards begin to come back (4.8 s): the
    // page's title gives way to the page — it is never seen through a returning card.
    const arrive = bed == null ? 1 : smoothstep(2.2, 3.0, bed) * (1 - smoothstep(4.5, 5.1, bed));
    const alpha = clamp01(state.veil) ** 2 * arrive * smoothstep(0.6, 1, look);
    if (!(alpha > 0.01)) return;
    const s = G.s;
    const at = G.cfg.caption;
    const x = (G.ox + at.x) * s, y = at.y * s;
    ctx.save();
    ctx.globalCompositeOperation = 'source-over';
    ctx.globalAlpha = alpha * (pal.dark ? 0.8 : 0.82);
    const k = at.size / 16;
    const half = 14 * s * 0.5 * k;
    ctx.drawImage(sprites[`glint-${pal.dark ? 'tonight' : 'ink'}`], x + 6 * s * k - half, y - 5.4 * s * k - half, half * 2, half * 2);
    ctx.fillStyle = css(pal.dark ? lch(0.88, 0.03, 85) : lch(0.40, 0.05, 285));
    ctx.font = `600 ${at.size * s}px Nunito, ui-rounded, system-ui, sans-serif`;
    ctx.textBaseline = 'alphabetic';
    if ('letterSpacing' in ctx) ctx.letterSpacing = `${0.25 * s * k}px`;
    ctx.fillText(`Night ${Math.max(1, Math.floor(state.ageDays) + 1)}`, x + 18 * s * k, y);
    ctx.restore();
  }

  /** Nothing bright behind the words: a feathered limiter under each line of the header. It does
   *  nothing unless the sky there is past the limit (darken / lighten blending). */
  const guardSprites = new Map();
  function drawTextGuards(ctx, state, pal) {
    const L = state.layout;
    if (!L) return;
    const s = G.s;
    const lead = state.lead == null ? 1 : clamp01(state.lead);
    const pad = 7, feather = 9;
    const guard = (box, capL, opacity) => {
      if (!box || !(opacity > 0.01)) return;
      const w = Math.ceil((box.width + 2 * (pad + feather)) * s), h = Math.ceil((box.height + 2 * (pad + feather)) * s);
      // the cap takes the sky's own hue there, so it is never a grey patch
      const sky = pal.air.show(pal.air.skyAt(pal.dxSun(box.x + box.width / 2 - G.ox), 0.8));
      const cap = css(pal.dark ? [capL, sky[1] * 0.8, sky[2] * 0.8] : [capL, sky[1] * 0.6, sky[2] * 0.6]);
      const key = `${w}|${h}|${cap}`;
      let sprite = guardSprites.get(key);
      if (!sprite) {
        if (guardSprites.size > 24) guardSprites.clear();
        sprite = mk(w, h);
        const b = sprite.getContext('2d');
        b.filter = `blur(${feather * 0.5 * s}px)`;
        b.fillStyle = cap;
        b.beginPath();
        b.roundRect(feather * s, feather * s, w - 2 * feather * s, h - 2 * feather * s, 10 * s);
        b.fill();
        guardSprites.set(key, sprite);
      }
      ctx.globalCompositeOperation = pal.dark ? 'darken' : 'lighten';
      ctx.globalAlpha = opacity;
      ctx.drawImage(sprite, Math.round((box.x - pad - feather) * s), Math.round((box.y - pad - feather) * s));
      ctx.globalAlpha = 1;
      ctx.globalCompositeOperation = 'source-over';
    };
    if (pal.dark) {
      guard(L.name, 0.43, 1); guard(L.age, 0.36, 1);
      guard(L.title, 0.43, lead); guard(L.subtitle, 0.36, lead);
    } else {
      guard(L.age, 0.868, 1); guard(L.subtitle, 0.868, lead);
    }
  }

  // ── a frame ──────────────────────────────────────────────────────────

  /** The planes of land for one pose, far to near, with the mist between them and the sun's bloom
   *  lying over the far ones. `open`: seconds since the Duo opened, or null. */
  function drawLand(ctx, pal, look, tilt, breath, open, sunNow, bloomAmt) {
    const s = G.s, c = G.cfg;
    for (const plane of G.planes) {
      const off = planeOffset(plane, look, tilt);
      (plane.mists ?? []).forEach((band, i) => {
        const m = plane.mistCanvases[i];
        if (!m) return;
        const px = (m.x0 + G.ox + off.x + breath(band)) * s, py = (m.y + off.y) * s;
        ctx.globalAlpha = clamp01(pal.mistAmt * band.amt * 1.5);
        ctx.drawImage(m.canvas, px, py);
        ctx.globalAlpha = 1;
      });
      ctx.drawImage(plane.canvas, Math.round((G.xL + G.ox + off.x) * s), Math.round((plane.y0 + off.y) * s));
      // Opening the Duo — the one thing that happens in the bare second: light runs down the river
      // toward you. A crest leaves the furthest bend at 0.1 s and is at the foot of the page by 0.9 s,
      // slow among the far bends and quick through the near reach, as anything coming up a valley is.
      // The water and the mist lying along the river's own course take it as it passes, keep half of
      // it while the cards land, and let it go over the next seconds. In the dark appearance it is
      // light added; on the pale page, a warm pass over pale mist. (At night it is held to a breath.)
      const RL = plane.id === 'far' && open != null ? G.riverLight : null;
      if (RL) {
        const run = clamp01((open - 0.1) / 0.8);
        const reach = G.H - c.H0 - off.y + 40;            // points from the horizon to past the foot of the page, in this pose (looking up, only the far bends are in view)
        const crestAt = 3 + (reach - 3) * Math.pow(run, 2.2);   // where the crest is, points below the horizon
        const crestW = 6 + 0.2 * crestAt;                 // it is broader the nearer it is
        const hold = smoothstep(0.1, 0.25, open) * (1 - smoothstep(1.4, 4.4, open));
        const amount = hold * (pal.dark ? 1 - 0.86 * pal.deepNight : 1 - 0.5 * pal.nightness);
        if (amount > 0.01) {
          const cw = RL.canvas.width, ch = RL.canvas.height;
          const b = scratch('b', cw, ch);
          b.drawImage(RL.canvas, 0, 0);
          b.globalCompositeOperation = 'source-in';
          const warm = pal.byMoon ? pal.air.silver : mix3(pal.air.mist, mix3(pal.air.glow, pal.air.sun, 0.3), 0.5 * clamp01(pal.air.glowAmt * 1.6) * smoothstep(-9, -2, pal.altDeg));
          const tint = pal.dark
            ? pal.air.show([Math.max(0.5, warm[0]), warm[1], warm[2]], { presence: Math.max(pal.air.presence, 0.6) })
            : pal.air.show(lch(0.985, 0.03 + 0.03 * smoothstep(-9, 3, pal.altDeg) * (1 - smoothstep(8, 25, pal.altDeg)), 72), { presence: 1 });
          // down the page, far to near; the stops crowd toward the horizon, where the crest is thin
          const g = b.createLinearGradient(0, 0, 0, ch);
          const stops = 64;
          for (let k = 0; k <= stops; k += 1) {
            const at = (k / stops) ** 2;
            const d = RL.y0 + (RL.y + ch * at) / s - c.H0;      // this row, points below the horizon
            const crest = Math.exp(-(((d - crestAt) / crestW) ** 2));
            const passed = 0.5 * (1 - smoothstep(crestAt - crestW, crestAt + 0.5 * crestW, d));
            g.addColorStop(at, css(tint, clamp01(passed + crest * (1 - passed))));
          }
          b.fillStyle = g;
          b.fillRect(0, 0, cw, ch);
          ctx.globalCompositeOperation = pal.dark ? 'lighter' : 'source-over';
          ctx.globalAlpha = clamp01(amount * (pal.dark ? 0.6 : 0.85));
          ctx.drawImage(b.canvas, 0, 0, cw, ch, Math.round((G.xL + G.ox + off.x) * s) + RL.x, Math.round((RL.y0 + off.y) * s) + RL.y, cw, ch);
          ctx.globalCompositeOperation = 'source-over';
          ctx.globalAlpha = 1;
        }
      }
      if (plane.id === 'mid' && bloomAmt > 0.02) {
        // haze thickens under the sun: its light lies over the far land, in front of the knoll's own shade
        const hy = (c.H0 + off.y) * s, r = 150 * s;
        const g = ctx.createRadialGradient(sunNow.x * s, hy, 0, sunNow.x * s, hy, r);
        const tint = pal.air.show(pal.air.glow);
        g.addColorStop(0, css(tint, 0.42 * bloomAmt)); g.addColorStop(0.3, css(tint, 0.2 * bloomAmt)); g.addColorStop(0.65, css(tint, 0.06 * bloomAmt)); g.addColorStop(1, css(tint, 0));
        ctx.save();
        ctx.beginPath();
        ctx.rect(0, hy - 14 * s, G.pxW, 70 * s);
        ctx.clip();
        ctx.translate(sunNow.x * s, hy);
        ctx.scale(1.7, 0.3);
        ctx.translate(-sunNow.x * s, -hy);
        ctx.fillStyle = g;
        ctx.fillRect(sunNow.x * s - r, hy - r, 2 * r, 2 * r);
        ctx.restore();
      }
    }
  }

  /** Compose one pose of the picture into `ctx` (display pixels). */
  function compose(ctx, state, pal, look, time) {
    const s = G.s, c = G.cfg;
    const tiltIn = state.tilt ?? { x: 0, y: 0 };
    const tilt = { x: clamp(tiltIn.x || 0, -1, 1), y: clamp(tiltIn.y || 0, -1, 1) };
    pal.look = look;
    const skyOff = planeOffset(SKYPLANE, look, tilt);
    skyOff.tiltY = tilt.y * SKYPLANE.tilt[1];
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.globalCompositeOperation = 'source-over';
    ctx.globalAlpha = 1;
    // the tall sky
    const adj = pal.adjust ?? 'none';
    ctx.filter = adj;
    ctx.drawImage(G.sky, Math.round((G.xL + G.ox + skyOff.x) * s), Math.round((G.skyTop + skyOff.y) * s));
    ctx.filter = 'none';

    // where the bodies are in this pose
    const sunNow = bodyAt(state, state.sun.x, pal.altDeg, c.sunR, look);
    sunNow.x += G.ox + tilt.x * SKYPLANE.tilt[0]; sunNow.y += skyOff.tiltY;
    let moonNow = null;
    if (state.moon) {
      moonNow = bodyAt(state, state.moon.x, state.moon.altitude / DEG, c.moonR, look);
      moonNow.x += G.ox + tilt.x * SKYPLANE.tilt[0]; moonNow.y += skyOff.tiltY;
    }
    pal.moonNow = moonNow && state.moon.altitude > -0.02 ? moonNow : null;

    const knollPlane = G.planes.find((p) => p.id === 'knoll');
    const knollOff = planeOffset(knollPlane, look, tilt);
    const tonightAt = tonightHome(look, tilt);
    const ring = ringOf(state, tilt);

    drawStars(ctx, state, pal, time, skyOff, ring);
    drawShootingStar(ctx, pal, time, skyOff);

    // the moon: a quiet halo, then the disc
    if (pal.moonNow) {
      const m = state.moon;
      const clear = pal.dark ? clearOfText(state, moonNow.x, moonNow.y, c.moonR) : 1;
      const mk2 = [pal.dark, Math.round(m.fraction * 200), Math.round(m.rotation * 60), m.inDaylight, Math.round(pal.altDeg * 4), Math.round(clear * 20), Math.round(m.altitude / DEG)].join('|');
      if (G.moon.key !== mk2) { paintMoon(state, pal, clear); G.moon.key = mk2; }
      const up = smoothstep(-1.5, 0.5, m.altitude / DEG);
      const night = 1 - smoothstep(-8, 3, pal.altDeg);
      const vis = (0.42 + 0.58 * night) * up * lerp(smoothstep(0.04, 0.2, m.fraction), 1, pal.nightness) * moonNow.seen * clearOfButtons(state, moonNow.x, moonNow.y, c.moonR);
      const haloAmt = pal.nightness * (0.3 + 0.7 * m.fraction) * clear * up * moonNow.seen;
      if (haloAmt > 0.02) {
        // two painted rings of light, barely there: the room stays dark. (Looking up, the moon has the
        // sky to itself and nothing under it but sky: its halo is a little fuller there.)
        const fuller = pal.dark ? 1 + 1.3 * look * smoothstep(70, 190, moonNow.E) : 1;
        for (const [k, a] of [[5.2, (pal.dark ? 0.05 : 0.5) * fuller], [2.6, (pal.dark ? 0.09 : 0.7) * fuller]]) {
          const r = c.moonR * k * s;
          ctx.globalAlpha = clamp01(a * haloAmt);
          ctx.drawImage(pal.dark ? sprites.glowCool : sprites['dot-white'], moonNow.x * s - r, moonNow.y * s - r, r * 2, r * 2);
        }
      }
      ctx.globalAlpha = clamp01(vis);
      const size = G.moon.canvas.width;
      ctx.drawImage(G.moon.canvas, moonNow.x * s - size / 2, moonNow.y * s - size / 2);
      ctx.globalAlpha = 1;
    }

    // the sun: a painted halo of two rings, then the disc
    const sunVis = smoothstep(-2.4, -0.3, pal.altDeg) * sunNow.seen;
    if (sunVis > 0.01 && sunNow.y < G.H + 40) {
      const clear = pal.dark ? clearOfText(state, sunNow.x, sunNow.y, c.sunR) : 1;
      const air = pal.air;
      const R = c.sunR * s;
      const low = 1 - smoothstep(3, 14, pal.altDeg);
      const haloAmt = (pal.dark ? 0.16 + 0.34 * low : 0.5 + 0.3 * low) * clear * sunVis * (pal.dark ? 0.35 + 0.65 * air.presence : 1);
      const haloLab = mix3(air.sun, air.glow, 0.5);
      for (const [k, a, seed] of [[3.3, 0.22, 2.1], [1.95, 0.34, 0.7]]) {
        ctx.globalAlpha = clamp01(a * haloAmt);
        ctx.fillStyle = css(air.show(haloLab, { presence: Math.max(air.presence, 0.6) }));
        ctx.filter = `blur(${1.4 * s}px)`;
        ctx.fill(discPath(sunNow.x * s, sunNow.y * s, R * k, 0.02, seed));
      }
      ctx.filter = 'none';
      let disc = air.sun;
      if (pal.dark && clear < 1) disc = mix3([0.33, disc[1] * 0.7, disc[2] * 0.7], disc, clear);
      // (never a disc bitten by a button's rim: behind the gear or the avatar there is only its glow)
      ctx.globalAlpha = clamp01(sunVis * clearOfButtons(state, sunNow.x, sunNow.y, c.sunR));
      ctx.fillStyle = css(disc);
      ctx.fill(discPath(sunNow.x * s, sunNow.y * s, R, 0.012, 4.2));
      ctx.globalAlpha = 1;
    }

    // clouds, on the sky's own plane; gone at night
    const cloudAlpha = 1 - 0.94 * pal.starsOut;
    if (cloudAlpha > 0.02) {
      for (const cloud of G.clouds) {
        const f = (((cloud.phase + (time ?? 0) / cloud.period) % 1) + 1) % 1;
        const x = cloud.x + cloud.span * (0.5 - f);            // drifting from the sunset side
        const y = c.H0 - cloud.e;
        const sx = G.ox + x + skyOff.x, sy = y + skyOff.y;
        if (sx < -cloud.len || sx > G.W + cloud.len || sy < -40 || sy > G.H + 40) continue;
        const fade = smoothstep(0, 0.18, f) * (1 - smoothstep(0.82, 1, f));
        let a = cloudAlpha * fade * cloudClear(state, sx, sy, cloud);
        // …nor behind the strip's own furniture: while a sleep runs the island is longer and the status
        // icons sit lower — a cloud they would sit on is not drawn
        const SC = state.layout?.stripClear;
        if (SC && sx + cloud.len / 2 > SC.x + 20) a *= smoothstep(SC.yMin - 8, SC.yMin, sy - cloud.rise * 0.8);
        // …nor across the sun's disc: a flat base cutting the disc in two is a bitten sun
        if (sunVis > 0.05) {
          const ddx = Math.max(sx - cloud.len / 2 - sunNow.x, 0, sunNow.x - (sx + cloud.len / 2)), ddy = Math.max(sy - cloud.rise - sunNow.y, 0, sunNow.y - (sy + 2));
          a *= lerp(1, smoothstep(c.sunR + 1, c.sunR + 16, Math.hypot(ddx, ddy)), clamp01(sunVis));
        }
        if (a < 0.02) continue;
        const lightKey = `${Math.round(Math.atan2(pal.lamp.y - y, pal.lamp.x - x) / (6 * DEG))}|${pal.lamp.kind}`;
        const ck = `${keys.air}|${lightKey}`;
        if (cloud.key !== ck) { paintCloud(cloud, pal, x, y, lightKey); cloud.key = ck; }
        ctx.globalAlpha = clamp01(a * (cloud.high ? 0.86 : 0.95));
        ctx.drawImage(cloud.canvas, sx * s - cloud.masks.cx, sy * s - cloud.masks.cy);
      }
      ctx.globalAlpha = 1;
    }

    // the land, far to near, with the mist that lies between the planes — composed once and kept
    // while nothing moves (the camera and the mist's slow breathing are what move it)
    const bloomAmt = pal.byMoon ? 0 : clamp01(pal.air.glowAmt * 1.3) * smoothstep(-7, -1, pal.altDeg) * (1 - 0.7 * smoothstep(6, 20, pal.altDeg)) * (pal.dark ? 1 : 0.5);
    const open = state.event && state.event.kind === 'open' && !state.reduceMotion ? state.event.age : null;
    const breath = (band) => (time == null ? 0 : Math.round((band.pools ? 7 : 16) * Math.sin(TAU * (time / (240 + 37 * band.seed) + band.seed * 0.37)) * 4) / 4);
    if (open == null) {
      const key = [keys.land, look.toFixed(5), tilt.x, tilt.y, Math.round(sunNow.x * 4), Math.round(bloomAmt * 50),
        G.planes.map((p) => (p.mists ?? []).map(breath).join(',')).join(';')].join('|');
      if (!G.landCache) G.landCache = { key: '', canvas: mk(G.pxW, G.pxH) };
      if (G.landCache.key !== key) {
        const lc = G.landCache.canvas.getContext('2d');
        lc.setTransform(1, 0, 0, 1, 0, 0);
        lc.globalCompositeOperation = 'source-over';
        lc.globalAlpha = 1;
        lc.clearRect(0, 0, G.pxW, G.pxH);
        drawLand(lc, pal, look, tilt, breath, null, sunNow, bloomAmt);
        G.landCache.key = key;
      }
      ctx.filter = adj;
      ctx.drawImage(G.landCache.canvas, 0, 0);
      ctx.filter = 'none';
    } else {
      ctx.filter = adj;
      drawLand(ctx, pal, look, tilt, breath, open, sunNow, bloomAmt);
      ctx.filter = 'none';
    }
    // the sun's glare: light spills round what stands in front of it
    if (bloomAmt > 0.02 && sunVis > 0.02) {
      const r = c.sunR * (pal.dark ? 4.6 : 3.4) * s;
      const tint = pal.air.show(mix3(pal.air.sun, pal.air.glow, 0.6), { presence: Math.max(pal.air.presence, 0.6) });
      const g = ctx.createRadialGradient(sunNow.x * s, sunNow.y * s, c.sunR * 0.7 * s, sunNow.x * s, sunNow.y * s, r);
      const k = bloomAmt * sunVis * (pal.dark ? 0.55 : 0.1);
      g.addColorStop(0, css(tint, 0.9 * k)); g.addColorStop(0.25, css(tint, 0.42 * k)); g.addColorStop(0.6, css(tint, 0.12 * k)); g.addColorStop(1, css(tint, 0));
      ctx.globalCompositeOperation = pal.dark ? 'lighter' : 'source-over';
      ctx.fillStyle = g;
      ctx.fillRect(sunNow.x * s - r, sunNow.y * s - r, 2 * r, 2 * r);
      ctx.globalCompositeOperation = 'source-over';
    }
    drawLife(ctx, state, pal, time, knollOff, look);

    drawTonight(ctx, state, pal, time, tonightAt, ring);
    drawSnowfall(ctx, state, pal, time);
    drawCaption(ctx, state, pal, look);
  }

  let lastState = null;
  let lookBuffer = null;
  let painted = null, lastTone = null, lastRenderMs = 0, lastMovedMs = -1e9;
  function render(state) {
    if (destroyed || !state || !state.sun) return;
    lastState = state;
    const started = performance.now();
    const s = Number.isFinite(state.dpr) && state.dpr > 0 ? state.dpr : 1;
    if (!X || X.s !== s) { X = buildTextures(s); sprites = buildSprites(s); keys = {}; G = null; }
    const geoKey = [state.device, state.width, state.height, s, state.phone.x, state.phone.width, Boolean(state.strip)].join('|');
    if (!G || G.key !== geoKey) {
      const tg = performance.now();
      G = buildGeometry(state);
      G.key = geoKey;
      G.river = buildRiver();
      timing.geometry = performance.now() - tg;
      keys = {};
      canvas.width = G.pxW;
      canvas.height = G.pxH;
      canvas.style.width = `${G.pxW / s}px`;
      canvas.style.height = `${G.pxH / s}px`;
    }
    const time = state.reduceMotion || !Number.isFinite(state.t) ? null : state.t;
    const look = lookOf(state);
    const pal = resolve(state, look);
    const c = G.cfg;

    let repainted = false;
    // What the planes were painted for. (Presence and the dimmed room are stepped finely, so a
    // slow settling repaints a few times a second, not every frame; the camera never repaints.)
    const sea = pal.sea;
    const seaKey = [sea.foliage, sea.blossom, sea.snow, sea.frost, sea.leafFall, sea.grass, sea.leafHue].map((v) => Math.round(v * 40)).join(',');
    // the sun's glow is laid into the sky where the sun is in the world
    pal.sunSkyY = c.H0 - pal.sunRest.E;
    const baseKey = [state.scheme, Math.round(pal.altDeg * 8), pal.morning, Math.round(pal.moonlight * 30),
      Math.round(pal.sunX * 2), Math.round(pal.sunSkyY), pal.lamp.kind, Math.round(pal.lamp.x), Math.round(pal.lamp.y / 3)].join('|');
    const tone = { p: Math.round(pal.B.presence * 120) / 120, d: Math.round(pal.B.depth * 60) / 60 };   // (fine steps: a held frame of a slow settling is within a third of a level of the true tone)
    // While an event PLAYS (the bloom swelling, the room dimming) the planes are not repainted: the
    // change of tone is laid over what is already painted as one colour adjustment — as the app would,
    // with .brightness / .saturation on the layers — and the planes are painted afresh once it settles.
    // A still (a frozen frame, the first frame) is always painted exactly.
    const nowMs = performance.now();
    const playing = !state.frozen && time != null && Boolean(state.event) && lastRenderMs > 0 && nowMs - lastRenderMs < 600;
    if (lastTone && Math.abs(tone.p - lastTone.p) + Math.abs(tone.d - lastTone.d) > 0.0005) lastMovedMs = nowMs;
    const moving = nowMs - lastMovedMs < 350 ? 1 : 0;
    let adjust = null;
    if (playing && keys.base === baseKey && painted && moving > 0.0005 && Math.abs(tone.p - painted.p) <= 0.62) {
      if (tone.p !== painted.p || tone.d !== painted.d) {
        if (pal.dark) {
          const f = (t) => (1 - 0.12 * (1 - t.p)) * (1 - 0.14 * t.d), g = (t) => (0.4 + 0.6 * t.p) * (1 - 0.12 * t.d);
          const Lk = f(tone) / f(painted), Ck = g(tone) / g(painted);
          adjust = `brightness(${Math.pow(Lk, 1.25).toFixed(4)}) saturate(${(Ck / Lk).toFixed(4)})`;
        } else {
          const c0 = lerp(0.2, 0.62, pal.air.night);
          const g = (t) => (c0 + (1 - c0) * t.p) * (1 - 0.25 * t.d);
          adjust = `brightness(${(1 - 0.013 * (tone.d - painted.d)).toFixed(4)}) saturate(${(g(tone) / g(painted)).toFixed(4)})`;
        }
      }
    } else {
      const airKey = `${baseKey}|${tone.p}|${tone.d}`;
      if (keys.air !== airKey) {
        keys.air = airKey;
        keys.base = baseKey;
        painted = tone;
        const t0 = performance.now();
        paintSky(pal);
        timing.sky = performance.now() - t0;
        keys.land = '';
        repainted = true;
      }
    }
    lastTone = tone;
    pal.adjust = adjust;
    if (G.tree.masksKey !== seaKey) {
      const tm = performance.now();
      G.tree.masks = treeMasks(TREE, mk, G.tree.h * s, s, sea);
      timing.treeMasks = performance.now() - tm;
      G.tree.masksKey = seaKey;
      keys.land = '';
    }
    // the sun or the moon behind the tree: where its light burns through (rest pose; a low body moves with the tree)
    const burns = [];
    {
      const t = G.tree;
      const near = (b, r) => b && Math.abs(b.x - t.x) < t.h * 0.62 + r && b.y > t.baseY - t.h * 1.05 - r && b.y < t.baseY + r;
      const sunPower = smoothstep(-2.4, -0.3, pal.altDeg);
      if (sunPower > 0.05 && near(pal.sunRest, c.sunR)) burns.push({ x: pal.sunRest.x, y: pal.sunRest.y, r: c.sunR, power: sunPower });
      if (pal.moonRest && state.moon.altitude > -0.01 && near(pal.moonRest, c.moonR)) burns.push({ x: pal.moonRest.x, y: pal.moonRest.y, r: c.moonR, power: (0.4 + 0.6 * pal.nightness) * smoothstep(0.1, 0.4, state.moon.fraction) });
    }
    const landKey = `${keys.air}|${seaKey}|${burns.map((b) => `${Math.round(b.x * 2)},${Math.round(b.y * 2)},${Math.round(b.power * 10)}`).join(';')}`;
    if (keys.land !== landKey) {
      keys.land = landKey;
      const t0 = performance.now();
      paintTree(pal, burns);
      timing.tree = performance.now() - t0;
      for (const plane of G.planes) {
        paintPlane(plane, pal);
        plane.mistCanvases = (plane.mists ?? []).map((band, i) => mistCanvas(band, pal, plane.mistMasks[i]));
      }
      timing.land = performance.now() - t0 - timing.tree;
      repainted = true;
    }

    const tCompose = performance.now();
    // Reduce Motion: there is no move — the looked-up still cross-fades in and out.
    if (state.reduceMotion && look > 0.001 && look < 0.999) {
      compose(main, state, pal, 0, time);
      if (!lookBuffer || lookBuffer.width !== G.pxW || lookBuffer.height !== G.pxH) lookBuffer = mk(G.pxW, G.pxH);
      compose(lookBuffer.getContext('2d'), state, pal, 1, time);
      main.globalAlpha = look;
      main.drawImage(lookBuffer, 0, 0);
      main.globalAlpha = 1;
    } else {
      compose(main, state, pal, state.reduceMotion ? Math.round(look) : look, time);
    }
    const tc = performance.now();
    timing.compose = tc - tCompose;
    drawTextGuards(main, state, pal);
    // grain, at the device pixel, fixed to the paper
    if (!G.grain) {
      G.grain = mk(G.pxW, G.pxH);
      const g = G.grain.getContext('2d');
      X.grainPattern.setTransform(new DOMMatrix().translate(Math.round(G.ox * s) % 512, 0));
      g.fillStyle = X.grainPattern;
      g.fillRect(0, 0, G.pxW, G.pxH);
    }
    main.globalAlpha = pal.dark ? 0.5 : 0.42;
    main.drawImage(G.grain, 0, 0);
    main.globalAlpha = 1;

    if (timingFlush) main.getImageData(0, 0, 1, 1);
    timing.finish = performance.now() - tc;
    const took = performance.now() - started;
    lastRenderMs = performance.now();
    timing.took = took; timing.repainted = repainted;
    timing.maxTook = Math.max(timing.maxTook ?? 0, took); timing.repaints = (timing.repaints ?? 0) + (repainted ? 1 : 0);
    if (timing.first == null) timing.first = took;
    if (repainted) timing.repaint = took; else timing.last = took;
    timing.frames += 1;
    if (typeof window !== 'undefined') {
      const st = G.stars.list;
      window.__hillPainted = { timing, look, stars: st.length ? {
        total: st.length,
        places: st.map((q) => [Math.round(q.lx * 10) / 10, Math.round(q.ly * 10) / 10, q.kind]),   // looked-up display points (anchor window's x)
        rest: st.filter((q) => q.y > 2 && q.x < G.Wa - 2 && q.x > 2).length,
        up: st.filter((q) => q.ly > 2 && q.ly < G.H && q.lx > 2 && q.lx < G.Wa - 2).length,
        restOpen: st.filter((q) => q.y > 2 && q.x < G.Wa - 2 && q.x > 2 && !(state.cards ?? []).some((cd) => cd.kind !== 'header' && cd.kind !== 'strip'
          && q.x + G.ox > cd.x && q.x + G.ox < cd.x + cd.width && q.y > cd.y && q.y < cd.y + cd.height)).length,
      } : null };
    }
  }

  function destroy() {
    destroyed = true;
    G = null; X = null;
    scratches.clear(); lookBuffer = null;
    canvas.remove();
  }

  // The caption's face (the lab's stand-in for SF Rounded) may still be on its way.
  const ready = doc.fonts && doc.fonts.load
    ? doc.fonts.load('600 16px Nunito').then(() => { if (!destroyed && lastState) render(lastState); }, () => {})
    : Promise.resolve();

  return { render, destroy, ready };
}
