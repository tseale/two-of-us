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
//   the sky      one TALL plane (the everyday view shows its foot; the bedtime
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
//                (the bloom, the dimmed room) is one colour adjustment on the layers
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
  blurb: 'Picture book’s place painted in true light’s air: a river valley, a knoll and one grown tree against the setting sun; at bedtime the view looks up into every night of his life.',
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
// A plane is the shapes that move together when the camera does.

const DUO = {
  kind: 'duo',
  H0: 292,                 // the horizon at rest
  D: 312,                  // looking up lowers it this far (→ 604)
  T: 78,                   // …and the turn slides the far world this far left
  table: 292,              // points of sky the twilight's eight stops span
  Emax: 500,               // sun and moon: how high the zenith stands over the horizon, in points of the tall sky
  tree: { x: 408, h: 88 },
  tonight: { x: 379, y: 194 },
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
    { id: 'knoll', sink: 1, slide: 1, tilt: [3.0, 1.3], mists: [{ y: 376, h: 36, x0: -580, x1: -90, amt: 0.75, seed: 3, valley: true }, { y: 309, h: 46, x0: -210, x1: 430, amt: 0.9, seed: 4 }], shapes: [
      { id: 'knoll', haze: 0.25, soft: 0, wob: 1.0, rim: 1, grass: 1, tree: true, foot: 60, crest: [[-150, 452], [-60, 428], [20, 418], [90, 413], [150, 406], [200, 396], [240, 382], [272, 364], [300, 344], [330, 322], [360, 305.5], [385, 298.6], [408, 296.5], [430, 298.2], [456, 305], [486, 318], [520, 335], [570, 356], [660, 384]], base: [[660, 760], [-100, 760], [-150, 455]] },
    ] },
    { id: 'near', sink: 1.12, slide: 1.1, tilt: [5.0, 2.0], mists: [{ y: 326, h: 40, x0: 215, x1: 720, amt: 1, seed: 5 }], shapes: [
      { id: 'near', haze: 0.14, soft: 0, wob: 2.0, rim: 0.3, grass: 0.8, foot: 70, crest: [[-194, 441], [-150, 425], [-90, 404], [-20, 388], [60, 377], [140, 372], [230, 366], [320, 359], [400, 356], [470, 361], [540, 375], [660, 398]], base: [[660, 760], [40, 760], [-30, 650], [-95, 560], [-150, 495], [-190, 448]] },
    ] },
    { id: 'fore', sink: 1.3, slide: 1.25, tilt: [8.0, 3.0], mists: [{ y: 404, h: 76, x0: -280, x1: 720, amt: 0.85, seed: 6 }, { y: 498, h: 46, x0: -620, x1: -300, amt: 0.7, seed: 7, valley: true }], shapes: [
      { id: 'fore', haze: 0.05, soft: 0, wob: 2.4, rim: 0.2, grass: 1.2, crest: [[-392, 760], [-372, 700], [-338, 662], [-270, 628], [-170, 598], [-70, 574], [30, 548], [130, 520], [230, 496], [320, 478], [390, 470], [460, 474], [540, 488], [660, 512]] },
    ] },
  ],
  // The river: its centre line and its width, from the valley's head to the foot of the leading margin.
  river: [[-243, 302.2, 0.8], [-236, 305, 1.5], [-251, 309, 2.6], [-228, 314.5, 4], [-181, 322, 6], [-204, 333, 9], [-296, 347, 12], [-362, 363, 15], [-322, 386, 19], [-258, 410, 23], [-306, 442, 27], [-404, 466, 30], [-452, 502, 33], [-441, 546, 37], [-418, 596, 41], [-440, 650, 46], [-462, 710, 52]],
  // Clouds: designed places (the middle of a lane each drifts along), all clear of the header's words.
  clouds: [
    { id: 'bar', x: 432, e: 113, kind: 'bar', len: 150, thick: 7.5, span: 110, period: 2400, phase: 0.42 },
    { id: 'gap', x: 262, e: 246, kind: 'wisp', len: 86, thick: 6, span: 60, period: 2800, phase: 0.5, high: true },
    { id: 'lead', x: -330, e: 128, kind: 'bar', len: 190, thick: 9, span: 120, period: 2600, phase: 0.48 },
    { id: 'leadhi', x: -84, e: 250, kind: 'wisp', len: 84, thick: 6, span: 44, period: 3000, phase: 0.5, high: true },
    { id: 'up1', x: 190, e: 372, kind: 'wisp', len: 170, thick: 10, span: 120, period: 3000, phase: 0.45, high: true },
    { id: 'up2', x: 400, e: 452, kind: 'wisp', len: 120, thick: 8, span: 100, period: 3300, phase: 0.55, high: true },
    { id: 'up3', x: -300, e: 410, kind: 'wisp', len: 200, thick: 11, span: 130, period: 3100, phase: 0.5, high: true },
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
  sunR: 9, moonR: 8,
  starScale: 0.9,
  caption: { x: 26, y: 774, size: 15 },
  planes: [
    { id: 'far', sink: 1, slide: 1, tilt: [1.0, 0.5], shapes: [
      { id: 'range', haze: 0.90, soft: 1.2, wob: 0.7, crest: [[-60, 131], [40, 128.5], [120, 131.5], [200, 133], [280, 130], [350, 132.5], [420, 129.5], [560, 132]] },
      { id: 'ridge', haze: 0.74, soft: 0.8, wob: 0.8, crest: [[-60, 134], [60, 132], [150, 135], [240, 136.5], [330, 133.5], [400, 135.5], [560, 132.5]] },
    ] },
    { id: 'mid', sink: 1, slide: 1, tilt: [2.0, 0.9], shapes: [
      { id: 'hill', haze: 0.42, hazeLight: 0.86, soft: 0.4, wob: 1.1, rim: 0.8, crest: [[-60, 116], [10, 106], [60, 101], [110, 102], [160, 107], [200, 114], [235, 123], [262, 131], [290, 137], [330, 142], [400, 147], [560, 152]] },
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
    { id: 'bar', x: 352, e: 46, kind: 'bar', len: 96, thick: 4.6, span: 60, period: 2600, phase: 0.45 },
    { id: 'up1', x: 150, e: 330, kind: 'wisp', len: 170, thick: 10, span: 110, period: 3000, phase: 0.45, high: true },
    { id: 'up2', x: 300, e: 500, kind: 'wisp', len: 130, thick: 8, span: 100, period: 3300, phase: 0.55, high: true },
  ],
};

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
    }

    g.clouds = cfg.clouds.map((c) => ({ ...c, key: '', canvas: null }));
    g.moon = { key: '', canvas: null };
    g.stars = { key: '', list: [], far: [] };
    return g;
  }

  // ── the camera ───────────────────────────────────────────────────────

  /** How far the camera has looked up, 0 rest … 1 up: bedtime's own curve, or the URL's `look=`. */
  function lookOf(state) {
    if (urlLook != null) return urlLook;
    const e = state.event;
    if (!e || e.kind !== 'bedtime' || state.asleep !== 'night') return 0;
    const a = e.age;
    const ease = (t) => t * t * t * (t * (t * 6 - 15) + 10);
    if (a <= 0.3) return 0;
    if (a < 2.4) return ease((a - 0.3) / 2.1);
    if (a <= 5.3) return 1;
    if (a < 7.5) return 1 - ease((a - 5.3) / 2.2);
    return 0;
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

  function leafLocal(hue) {
    const stops = [[0, [0.70, 0.12, 128]], [0.5, [0.50, 0.10, 141]], [0.8, [0.70, 0.13, 78]], [1, [0.56, 0.12, 46]]];
    for (let i = 0; i < stops.length - 1; i += 1) {
      if (hue <= stops[i + 1][0]) {
        const t = (hue - stops[i][0]) / (stops[i + 1][0] - stops[i][0]);
        const a = stops[i][1], b = stops[i + 1][1];
        return [lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t)];
      }
    }
    return stops[stops.length - 1][1];
  }

  function resolve(state, look) {
    const c = G.cfg;
    const dark = state.scheme !== 'light';
    const B = bloomOf(state);
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
    const snowLit = litLand(sl.snow);
    const frostLit = litLand(sl.frost);
    ground = mix3(ground, frostLit, 0.34 * sea.frost);
    const snowShade = [snowLit[0] - (dark ? 0.035 : 0.05), snowLit[1] + 0.012 * Math.cos(262 * DEG), snowLit[2] + 0.02 * Math.sin(262 * DEG)];
    ground = mix3(ground, snowShade, sea.snow * 0.92);
    if (dark) ground = [ground[0] + 0.035 * sea.snow * (0.3 + 0.7 * dusk), ground[1], ground[2]];

    const mistAmt = (0.55 + 0.25 * (morning ? 1 : 0) + 0.15 * sea.frost + 0.2 * nightness + 0.25 * moonlight) * (1 - 0.35 * smoothstep(8, 30, altDeg)) * (dark ? 1 : 0.72);

    // The tree: ink, and the season's paints re-lit by the hour.
    const inkL = dark ? Math.max(0.045, air.land[0] * 0.62) : air.land[0] - 0.36;
    const ink = [inkL, air.land[1] * 0.9 + 0.012 * Math.cos(330 * DEG) * (dark ? 0.6 : 1), air.land[2] * 0.9 + 0.012 * Math.sin(330 * DEG) * (dark ? 0.6 : 1)];
    const paint = (alb, lift = 0) => {
      const own = 0.5 + 0.5 * air.day;
      const L = (dark ? air.land[0] + 0.035 : air.land[0] - 0.20) + (alb[0] - 0.47) * (dark ? air.gain * 0.9 : 0.62) + lift;
      const base = lch(L, alb[1] * (dark ? 0.62 : 0.8) * (0.35 + 0.65 * own), alb[2]);
      return [base[0], base[1] + air.land[1] * 0.5, base[2] + air.land[2] * 0.5];
    };
    const leaf = leafLocal(sea.leafHue);

    return {
      dark, B, air, sea, altDeg, morning, nightness, moonlight, look, shown, deepNight,
      sunX, sunRest, moonRest, lamp, byMoon,
      C, dxSun, dxLamp,
      ground, snowLit, snowShade, frostLit, mistAmt,
      ink, inkLit: mix3([ink[0] + (dark ? 0.16 : 0.10), ink[1], ink[2]], byMoon ? air.silver : air.rim, 0.5),
      leafShade: paint(leaf, dark ? -0.02 : -0.07), leafMid: paint(leaf), leafLit: mix3(paint(leaf, dark ? 0.06 : 0.06), air.rim, 0.25 * air.rimAmt),
      // a low sun behind the crown shines through its edge: the leaf's own colour, lit
      leafGlow: lch(dark ? 0.50 : 0.86, dark ? 0.12 : 0.09, lerp(leaf[2], 70, 0.45)), backlit: smoothstep(-6, -1, altDeg) * (1 - smoothstep(8, 18, altDeg)),
      blossom: paint([0.93, 0.06, 355], dark ? 0.10 : 0.05), blossomShade: paint([0.84, 0.09, 350], dark ? 0.04 : 0),
      snow: paint([0.96, 0.012, 250], dark ? 0.10 : 0.06), frost: paint([0.88, 0.02, 235]),
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
        // The hand: long drags of the brush, following the bands.
        const drag = fb(x / 120 + 3.1, y / 9 + (x - sunX) * 0.004 + 1.7, 3) - 0.5;
        const shown = air.show([lab[0] + drag * strokes * (0.5 + 0.5 * smoothstep(-0.1, 0.5, e)), lab[1], lab[2]]);
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

  /** A cloud is a few long strokes of a flat brush: laid one over another, tapering at both
   *  ends. Its three masks — the body, the edge toward the light, the edge away — are cut
   *  once per light direction; only their paint changes. */
  function buildCloud(cloud, lx, ly) {
    const s = G.s;
    const L = cloud.len, T = cloud.thick;
    const w = Math.ceil((L + 40) * s), h = Math.ceil((T * 5.5 + 26 + (cloud.kind === 'bar' ? 0 : L * 0.2)) * s);
    const cx = w / 2, cy = h / 2;
    const body = scratch('a', w, h);
    body.fillStyle = '#fff';
    // each stroke: [offset along (of len), offset across (of thick), length, thickness, bow]
    const seedOf = (i, k) => hash(i * 7 + k, 311 + Math.round(cloud.len * 3 + cloud.e));
    const strokes = cloud.kind === 'bar'
      ? [[0, 0, 1, 1, 0.04], [0.20, 1.02, 0.50, 0.42, 0.02], [-0.27, 0.82, 0.34, 0.30, 0], [-0.10, -0.92, 0.46, 0.36, 0.05], [0.32, -0.66, 0.24, 0.26, 0.02]]
      : [[0, 0, 1, 0.50, 0.30], [0.10, -1.05, 0.72, 0.36, 0.34], [-0.16, 1.00, 0.60, 0.34, 0.24], [0.26, 1.9, 0.42, 0.24, 0.2], [-0.04, -2.05, 0.46, 0.22, 0.4]];
    const slant = cloud.kind === 'bar' ? 0 : -0.07;      // high cloud slants a little, and bows
    strokes.forEach(([oa, oc, kl, kt, bow], i) => {
      const len = L * kl * s, th = T * kt * s;
      body.save();
      body.translate(cx + oa * L * s * 0.5, cy + oc * T * s * 0.60);
      body.rotate(slant + (seedOf(i, 1) - 0.5) * 0.03);
      body.beginPath();
      const n = 48;
      const top = [], bot = [];
      for (let k = 0; k <= n; k += 1) {
        const u = k / n;
        // a brush stroke: it lands, runs, and lifts — fuller a little past where it began
        const taper = Math.pow(Math.sin(Math.PI * Math.pow(u, 0.86)), cloud.kind === 'bar' ? 0.62 : 0.9);
        const billow = 0.82 + 0.36 * vn(u * (cloud.kind === 'bar' ? 5 : 3) + i * 3.7 + cloud.x * 0.013, 2.2 + i);
        const mid = -bow * th * 4 * Math.sin(Math.PI * u) * (u - 0.2);
        const x = -len / 2 + u * len;
        top.push([x, mid - th * 0.60 * taper * billow]);
        bot.push([x, mid + th * 0.40 * taper * (0.92 + 0.16 * vn(u * 4 + i * 1.9, 5.5))]);
      }
      top.forEach((q, k) => { if (k === 0) body.moveTo(q[0], q[1]); else body.lineTo(q[0], q[1]); });
      for (let k = n; k >= 0; k -= 1) body.lineTo(bot[k][0], bot[k][1]);
      body.closePath();
      body.fill();
      body.restore();
    });
    // soften: gouache laid wet, not cut paper
    const soft = mk(w, h);
    const sc = soft.getContext('2d');
    sc.filter = `blur(${(cloud.kind === 'bar' ? 0.7 : 1.1) * s}px)`;
    sc.drawImage(body.canvas, 0, 0, w, h, 0, 0, w, h);
    sc.filter = 'none';
    // the ends dry out
    sc.globalCompositeOperation = 'destination-out';
    const ends = sc.createLinearGradient(0, 0, w, 0);
    ends.addColorStop(0, 'rgba(0,0,0,1)'); ends.addColorStop(0.10, 'rgba(0,0,0,0)');
    ends.addColorStop(0.90, 'rgba(0,0,0,0)'); ends.addColorStop(1, 'rgba(0,0,0,1)');
    sc.fillStyle = ends;
    sc.fillRect(0, 0, w, h);
    sc.globalCompositeOperation = 'source-over';
    const facing = (dx, dy, reach, blur) => {
      const m = mk(w, h);
      const mc = m.getContext('2d');
      mc.drawImage(soft, 0, 0);
      mc.globalCompositeOperation = 'destination-out';
      mc.filter = `blur(${blur * s}px)`;
      mc.drawImage(soft, -dx * reach * s, -dy * reach * s);
      mc.filter = 'none';
      return m;
    };
    return { w, h, cx, cy, body: soft, lit: facing(lx, ly, T * 0.42, 0.5), shade: facing(-lx, -ly, T * 0.5, 1.2) };
  }

  function paintCloud(cloud, pal, x, y, lightKey) {
    if (!cloud.masks || cloud.maskKey !== lightKey) {
      let dx = pal.lamp.x - x, dy = pal.lamp.y - y;
      const dist = Math.hypot(dx, dy) || 1;
      dx /= dist; dy /= dist;
      // a brush cloud is lit along an edge: lean the light to above or below, whichever it is nearer
      const ly = dy > 0.12 ? Math.max(dy, 0.75) : dy < -0.12 ? Math.min(dy, -0.75) : dy;
      const n = Math.hypot(dx * 0.6, ly) || 1;
      cloud.masks = buildCloud(cloud, (dx * 0.6) / n, ly / n);
      cloud.maskKey = lightKey;
      cloud.canvas = mk(cloud.masks.w, cloud.masks.h);
    }
    const { w, h, body, lit, shade } = cloud.masks;
    const air = pal.air, cl = air.cloud;
    const hi = Boolean(cloud.high);
    const far = smoothstep(0.1, 1.35, Math.abs(pal.dxSun(x)));
    const litAmt = pal.byMoon ? (hi ? 0.8 : 0.95) * pal.moonlight : hi ? cl.hiAmt : cl.loAmt;
    let litLab = pal.byMoon ? air.silver : hi ? cl.hiLit : cl.loLit;
    if (air.dark && !pal.byMoon) {
      // the low key's lit cloud keeps its fire: apricot under a low sun, rose after it
      const warm = smoothstep(14, 6, pal.altDeg) * smoothstep(-9, -4, pal.altDeg);
      const tgt = lch(litLab[0] + 0.02, 0.12, pal.altDeg > 0 ? 58 : 30);
      litLab = mix3(litLab, tgt, 0.6 * warm);
    }
    const shadeLab = hi ? cl.hiShade : cl.loShade;
    // Away from the sun the lit side goes to the Belt's pink, and quieter.
    if (!pal.byMoon) litLab = mix3(litLab, mix3(shadeLab, lch(litLab[0] - 0.03, 0.05, 350), 0.6), 0.75 * far);
    const skyHere = air.skyAt(pal.dxSun(x), (G.cfg.H0 - y) / G.cfg.table);
    const bodyLab = mix3(mix3(shadeLab, litLab, 0.42 * litAmt), skyHere, hi ? 0.34 : 0.22);
    const ctx = cloud.canvas.getContext('2d');
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.globalCompositeOperation = 'source-over';
    ctx.globalAlpha = 1;
    ctx.clearRect(0, 0, w, h);
    ctx.drawImage(tinted(body, pal.C(bodyLab)), 0, 0, w, h, 0, 0, w, h);
    ctx.globalAlpha = 0.75;
    ctx.drawImage(tinted(shade, pal.C(mix3(shadeLab, skyHere, 0.15))), 0, 0, w, h, 0, 0, w, h);
    ctx.globalAlpha = clamp01(0.25 + 0.75 * litAmt);
    ctx.drawImage(tinted(lit, pal.C(litLab)), 0, 0, w, h, 0, 0, w, h);
    ctx.globalAlpha = 1;
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
  function facing(sh, x, lampX) {
    const a = sh.at(x - 5), b = sh.at(x + 5);
    if (!Number.isFinite(a) || !Number.isFinite(b)) return 0.5;
    const slope = (b - a) / 10;                          // + falls to the right
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
        const g = [pal.ground[0] + side, pal.ground[1], pal.ground[2]];
        return mix3(g, air.hazeAt(pal.dxSun(x)), air.dark ? hz : sh.hazeLight ?? hz * 0.78);
      };
      a.fillStyle = hGrad(a, (x) => pal.C(own(x)));
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
        const amt = (1 - hz) * (air.dark ? 0.44 : 0.26) + 0.06;
        fall.addColorStop(0, 'rgba(0,0,0,0)'); fall.addColorStop(0.5, `rgba(0,0,0,${amt * 0.55})`); fall.addColorStop(1, `rgba(0,0,0,${amt})`);
        lo.fillStyle = fall;
        lo.fillRect(0, 0, w + 8, h + 8);
        lo.globalCompositeOperation = 'source-over';
      }
      // Three strokes along the crest. Shade first: a broad cool one on the side turned away…
      lo.lineJoin = 'round';
      if (power > 0.03 && hz < 0.8) {
        const coolLab = mix3(own(sh.x0 + 40), air.skyAt(pal.dxSun(sh.x0), 0.9), 0.5);
        const shadeLab = [coolLab[0] - (air.dark ? 0.03 : 0.05), coolLab[1], coolLab[2]];
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
      if (sh.floor && G.river) paintRiver(a, pal, plane.y0);

      // 4. The rim: one thin, loaded line where the crest catches the light, the brush skipping.
      if (sh.rim && rimAmt > 0.02 && power > 0.03 && hz < 0.8 && !pal.byMoon) {
        const rimLab = pal.byMoon ? air.silver : air.rim;
        let yMin = Infinity, yMax = -Infinity;
        for (const p of sh.crest) { if (p[0] < G.xL || p[0] > G.xR) continue; yMin = Math.min(yMin, p[1]); yMax = Math.max(yMax, p[1]); }
        const y0 = Math.max(0, Math.floor(py(yMin) - 6 * s)), y1 = Math.min(h, Math.ceil(py(Math.min(yMax, G.bottom)) + 6 * s));
        if (y1 > y0) {
          const b2 = scratch('b', w, y1 - y0);
          b2.translate(0, -y0);
          b2.lineJoin = 'round'; b2.lineCap = 'round';
          b2.lineWidth = (1.5 + 1.7 * (1 - hz)) * s;
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

  function buildRiver() {
    const def = G.cfg.river;
    if (!def) return null;
    const pts = line(def, 3, 0, 0);
    const left = [], right = [];
    for (let i = 0; i < pts.length; i += 1) {
      const a = pts[Math.max(0, i - 1)], b = pts[Math.min(pts.length - 1, i + 1)];
      let tx = b[0] - a[0], ty = b[1] - a[1];
      const len = Math.hypot(tx, ty) || 1;
      tx /= len; ty /= len;
      // the river's width is across the ground: seen from the hill it is mostly a width in x
      const wdt = pts[i][2] * (0.55 + 0.45 * Math.abs(ty));
      const nx = -ty, ny = tx * 0.35;
      left.push([pts[i][0] + nx * wdt, pts[i][1] + ny * wdt]);
      right.push([pts[i][0] - nx * wdt, pts[i][1] - ny * wdt]);
    }
    return { pts, left, right };
  }

  /** The river: the lightest thing in the land. Each reach mirrors the sky above it — the far
   *  ones the bright low sky, the near ones the sky higher up — and carries the light's own path. */
  function paintRiver(a, pal, y0) {
    const s = G.s, air = pal.air, c = G.cfg;
    const r = G.river;
    const px = (x) => (x - G.xL) * s, py = (y) => (y - y0) * s;
    const path = new Path2D();
    path.moveTo(px(r.left[0][0]), py(r.left[0][1]));
    for (const p of r.left) path.lineTo(px(p[0]), py(p[1]));
    for (let i = r.right.length - 1; i >= 0; i -= 1) path.lineTo(px(r.right[i][0]), py(r.right[i][1]));
    path.closePath();
    const yTop = r.pts[0][1], yBot = r.pts[r.pts.length - 1][1];
    const grad = a.createLinearGradient(0, py(yTop), 0, py(yBot));
    const n = 14;
    for (let i = 0; i <= n; i += 1) {
      const f = i / n;
      const y = yTop + (yBot - yTop) * f;
      // which reach is this: its x, from the centre line
      let x = r.pts[0][0];
      for (const p of r.pts) { if (p[1] >= y) { x = p[0]; break; } }
      const eRef = 0.02 + 0.30 * Math.pow(f, 0.9);       // what it mirrors: low sky far away, higher sky near
      const sky = air.skyAt(pal.dxSun(x), eRef);
      const lift = air.dark ? 0.03 : 0.025;
      const water = mix3([sky[0] + lift, sky[1] * 0.92, sky[2] * 0.92], pal.ground, 0.10 + 0.10 * f);
      grad.addColorStop(f, pal.C(water));
    }
    a.fillStyle = grad;
    a.fill(path);
    // the near bank's shade on the water, and the light's broken path
    const save = a.globalCompositeOperation;
    a.save();
    a.clip(path);
    a.lineCap = 'round';
    const glint = pal.byMoon ? air.silver : air.glow;
    const amt = pal.byMoon ? 0.5 * pal.moonlight : clamp01(air.glowAmt * 1.2) * smoothstep(-9, -2, pal.altDeg) * (1 - 0.6 * smoothstep(6, 25, pal.altDeg));
    // long soft streaks: the sky lying on moving water
    for (let i = 0; i < 46; i += 1) {
      const k = 3 + Math.floor(hash(i, 511) * (r.pts.length - 4));
      const p = r.pts[k];
      const wdt = p[2];
      if (wdt < 3) continue;
      const x = p[0] + (hash(i, 512) - 0.5) * wdt * 0.9, y = p[1] + (hash(i, 513) - 0.5) * 4;
      const len = wdt * (0.35 + 0.5 * hash(i, 514));
      const lightStreak = hash(i, 515) < 0.6;
      const sky = air.skyAt(pal.dxSun(x), lightStreak ? 0.02 : 0.6);
      a.strokeStyle = css(pal.shown([sky[0] + (lightStreak ? 0.03 : -0.02), sky[1], sky[2]]), 0.16 + 0.14 * hash(i, 516));
      a.lineWidth = (0.6 + 1.1 * hash(i, 517)) * s * Math.min(1.6, 0.4 + wdt / 30);
      a.beginPath();
      a.moveTo(px(x - len), py(y));
      a.quadraticCurveTo(px(x), py(y + (hash(i, 518) - 0.5) * 1.2), px(x + len), py(y));
      a.stroke();
    }
    if (amt > 0.03) {
      for (let i = 0; i < 110; i += 1) {
        const k = Math.floor(hash(i, 501) * (r.pts.length - 1));
        const p = r.pts[k];
        const wdt = p[2];
        const x = p[0] + (hash(i, 502) - 0.5) * wdt * 1.1, y = p[1] + (hash(i, 503) - 0.5) * 3;
        const len = (0.4 + 1.3 * hash(i, 504)) * Math.min(1.4, 0.3 + wdt / 18);
        // only on the reaches under the light's own x: its broken path
        const near = Math.exp(-Math.pow(Math.abs(x - pal.lamp.x) / (G.Wa * (pal.byMoon ? 1.05 : 0.55)), 2));
        const al = amt * near * (0.3 + 0.7 * hash(i, 505));
        if (al < 0.03) continue;
        // (the moon's path is points of light, not an area: it may outshine the land around it)
        a.strokeStyle = pal.byMoon
          ? css(air.show([air.dark ? 0.6 : glint[0] + 0.03, glint[1], glint[2]]), clamp01(al * 1.5))
          : css(pal.shown([glint[0] + 0.02, glint[1], glint[2]]), clamp01(al));
        a.lineWidth = (0.35 + 0.35 * hash(i, 506)) * s * Math.min(1.4, 0.5 + wdt / 30);
        a.beginPath();
        a.moveTo(px(x - len), py(y));
        a.lineTo(px(x + len), py(y));
        a.stroke();
      }
    }
    a.restore();
    a.globalCompositeOperation = save;
    // the banks: a thin darker line on the near side of each reach
    a.strokeStyle = pal.C([pal.ground[0] - (air.dark ? 0.02 : 0.06), pal.ground[1], pal.ground[2]]);
    a.globalAlpha = 0.5;
    a.lineWidth = 0.7 * s;
    a.beginPath();
    r.left.forEach((p, i) => { if (i === 0) a.moveTo(px(p[0]), py(p[1])); else a.lineTo(px(p[0]), py(p[1])); });
    a.stroke();
    a.beginPath();
    r.right.forEach((p, i) => { if (i === 0) a.moveTo(px(p[0]), py(p[1])); else a.lineTo(px(p[0]), py(p[1])); });
    a.stroke();
    a.globalAlpha = 1;
  }

  // ── mist ─────────────────────────────────────────────────────────────

  /** A level band of mist, tinted along x by the light it catches. Drawn straight into `ctx`
   *  (plane pixels when y0 is a plane's, display pixels with an offset otherwise). */
  function mistCanvas(band, pal) {
    const s = G.s, air = pal.air;
    const x0 = Math.max(band.x0, G.xL), x1 = Math.min(band.x1, G.xR);
    if (x1 - x0 < 8) return null;
    const w = Math.ceil((x1 - x0) * s), h = Math.ceil(band.h * s);
    const c = mk(w, h);
    const ctx = c.getContext('2d');
    ctx.fillStyle = (() => {
      const grad = ctx.createLinearGradient(0, 0, w, 0);
      const tint = (x) => css(pal.shown(air.mistAt(pal.dxLamp(x), pal.dxSun(x))), 0.62 + 0.38 * Math.exp(-Math.abs(pal.dxLamp(x)) / 0.55));
      grad.addColorStop(0, tint(x0));
      for (let x = Math.ceil((x0 + 0.01) / 30) * 30; x < x1; x += 30) grad.addColorStop((x - x0) / (x1 - x0), tint(x));
      grad.addColorStop(1, tint(x1));
      return grad;
    })();
    ctx.fillRect(0, 0, w, h);
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
    return { canvas: c, x0, w, h };
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
    const C = pal.C;
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
    lay(m.leafBack, C(pal.leafShade));
    lay(burnt(m.twigs, 0), C(pal.ink), pal.dark ? 0.92 : 0.8);
    lay(burnt(m.wood, 0.5), C(pal.ink));
    if (power > 0.05) lay(facingMask(m.wood, 1.1 * s), C(pal.inkLit), power * (pal.dark ? 0.55 : 0.8));
    if (m.leafMid) {
      lay(m.leafMid, C(pal.leafMid));
      lay(m.leafFront, C(mix3(pal.leafMid, pal.leafLit, 0.5)));
      if (power > 0.05) {
        lay(facingMask(m.leafBack, 3.0 * s), C(pal.leafGlow), power * pal.backlit * 0.55 * (1 - 0.7 * pal.sea.blossom));
        lay(facingMask(m.leafMid, 2.6 * s), C(pal.leafLit), power * 0.8);
        lay(facingMask(m.leafFront, 2.0 * s), C(pal.leafLit), power);
      }
    }
    lay(m.lastLeaves, C(pal.lastLeaf));
    lay(m.blossomB, C(pal.blossomShade));
    lay(m.blossomA, C(pal.blossom));
    lay(m.frost, C(pal.frost), pal.dark ? 0.28 : 0.7);
    lay(m.snow, C(pal.snow));
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
    out.firefly = soft(lch(0.93, 0.13, 104), 2.4);
    out.flake = soft(lch(0.985, 0.006, 250), 1.2);
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
      header.push(pad({ x: x0, y: y0, width: x1 - x0, height: y1 - y0 }, 7));
    } else if (L.avatar) header.push(pad(L.avatar, 2));
    if (L.gear) header.push(pad(L.gear, 3));
    for (const r of header) {
      outs.push(r);                                                    // looking up
      outs.push({ x0: r.x0 - c.T, x1: r.x1 - c.T, y0: r.y0 + c.D, y1: r.y1 + c.D });   // at rest
    }
    if (c.kind === 'duo') {
      const sx = (L.stripClear?.x ?? 362) + 20 - G.ox;                 // the strip's own column
      outs.push({ x0: sx - 2, x1: G.Wa + 4, y0: -10, y1: 192 });       // clock, island, status icons
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
    const tonightLook = { x: c.tonight.x - c.T, y: c.tonight.y + c.D };
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
    // rows of the looked-up sky: [y0, y1, share of his stars, columns [x0, x1, weight]…]
    const rows = c.kind === 'duo'
      ? [[yMin, c.D + 2, 0.42, [[xMin, xMax, 1]]],
        [c.D + 2, c.D + 90, 0.24, [[xMin, G.Wa - c.T, 1], [G.Wa - c.T, xMax, 0.45]]],
        [c.D + 90, hLook - 10, 0.34, [[xMin, 284, 0.8], [284, G.Wa - c.T, 2.1], [G.Wa - c.T, xMax, 0.45]]]]
      : [[yMin, c.D + 60, 0.80, [[xMin, xMax, 1]]],
        [c.D + 60, hLook - 8, 0.20, [[xMin, 160, 0.5], [160, G.Wa - c.T, 1.6], [G.Wa - c.T, xMax, 0.5]]]];
    const place = (star) => {
      let acc = 0, row = rows[rows.length - 1], v = star.v;
      for (const r of rows) { if (star.v < acc + r[2]) { row = r; v = (star.v - acc) / r[2]; break; } acc += r[2]; }
      const cols = row[3];
      let total = 0;
      for (const [x0, x1, w] of cols) total += (x1 - x0) * w;
      let x = xMax, a2 = 0;
      for (const [x0, x1, w] of cols) {
        const part = ((x1 - x0) * w) / total;
        if (star.u <= a2 + part) { x = x0 + ((star.u - a2) / part) * (x1 - x0); break; }
        a2 += part;
      }
      const y1 = Math.min(row[1], floor(x));
      return { x, y: row[0] + v * Math.max(4, y1 - row[0]) };
    };
    const apart = 5.6 * c.starScale;
    const list = [];
    const free = (x, y, big) => {
      if (x < xMin || x > xMax || y < yMin || y > floor(x)) return false;
      for (const r of outs) if (x > r.x0 && x < r.x1 && y > r.y0 && y < r.y1) return false;
      if (Math.hypot(x - tonightLook.x, y - tonightLook.y) < 17) return false;
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
      const at = place(star);
      const big = star.kind !== 'night';
      let { x, y } = at;
      // One star per night has to be countable: a place that is taken, hidden or behind the
      // words gives way to the nearest free one — judged only against the nights before it.
      if (!free(x, y, big)) {
        let found = false;
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
    // world coordinates (rest pose): the looked-up place, turned back and lowered
    for (const st of list) { st.x = st.lx + c.T; st.y = st.ly - c.D; }
    // The ordinary, fainter sky of the leading page (nobody's stars), on the whole tall sky.
    const far = [];
    if (G.ox > 0) {
      const count = Math.round((G.ox * (c.H0 + c.D)) / 1500);
      for (let n = 0; n < count; n += 1) {
        const x = -G.ox + hash(n, 41) * (G.ox + c.T - 4);
        const yl = 6 + Math.pow(hash(n, 42), 0.92) * (G.skyline(x) + c.D - 16);
        far.push({ x, y: yl - c.D, r: 0.46 + 0.5 * hash(n, 43), a: 0.3 + 0.45 * Math.pow(hash(n, 44), 1.6), phase: hash(n, 45), period: 3 + 4 * hash(n, 46) });
      }
    }
    G.stars = { key, list, far, tonightLook };
    return G.stars;
  }

  /** The ring that leaves tonight's star at bedtime: its radius now (points) and its strength. */
  function ringOf(state) {
    const e = state.event;
    if (!e || e.kind !== 'bedtime' || state.asleep !== 'night' || state.reduceMotion) return null;
    const age = e.age - 1.9;
    if (age <= 0) return null;
    const far = Math.hypot(G.W, G.H) * 1.02;
    const radius = 250 * age + 20 * (1 - Math.exp(-age * 3));
    const strength = smoothstep(0, 0.4, age) * (1 - smoothstep(far * 0.72, far * 1.05, radius));
    if (strength <= 0.003) return null;
    return { radius, strength };
  }

  function drawStars(ctx, state, pal, time, off, ring, tonightAt) {
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
    const answer = (x, y) => {
      if (!ring) return 0;
      const since = ring.radius - Math.hypot(x - tonightAt.x, y - tonightAt.y);
      if (since < -26) return 0;
      const pulse = since < 0 ? Math.exp(-((since / 10) ** 2)) : Math.exp(-((since / 95) ** 2));
      return pulse * Math.sqrt(ring.strength);
    };
    const passed = (x, y) => (ring ? smoothstep(-10, 30, ring.radius - Math.hypot(x - tonightAt.x, y - tonightAt.y)) : bed != null && bed > 2 ? 1 : 0);

    // the ordinary sky of the leading page
    if (stars.far.length) {
      const sprite = sprites[`dot-${light ? 'ink' : 'cool'}`];
      for (const f of stars.far) {
        const x = G.ox + f.x + off.x, y = f.y + off.y;
        if (y < -4 || y > G.H + 4 || x < -4) continue;
        const tw = time == null ? 1 : 0.8 + 0.2 * Math.cos(TAU * (time / f.period + f.phase));
        const wave = answer(x, y);
        let a = f.a * Math.max(out, wave * 0.8) * tw * (light ? 0.5 : 0.8) * (1 + 0.8 * wave);
        if (f.x > -3) a *= smoothstep(0.55, 1, pal.look);     // the anchor window's sky is his alone, until the camera has turned past it
        // none behind the leading page's title when it is there
        const T1 = state.layout?.title;
        if (T1 && lead > 0 && x > T1.x - 8 && x < T1.x + T1.width + 8 && y > T1.y - 8 && y < (state.layout.subtitle?.y ?? T1.y) + 26) a *= 1 - lead;
        if (a < 0.006) continue;
        ctx.globalAlpha = clamp01(a);
        const r = f.r * s * scale * (light ? 0.85 : 1);
        ctx.drawImage(sprite, x * s - r * 2.33, y * s - r * 2.33, r * 4.66, r * 4.66);
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
      let alpha = (light ? 0.8 + 0.2 * star.magnitude : 0.56 + 0.44 * star.magnitude) * tw * shown * settle;
      alpha *= 1 + 0.22 * passed(x, y) * (bed != null && bed < 9 ? 1 : 0);
      alpha = Math.max(alpha, wave * (0.6 + 0.4 * star.magnitude)) + 0.4 * wave * shown;
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
          ctx.globalAlpha = clamp01(alpha * 0.5);
          ctx.drawImage(sprites.dusk, px - half * 1.1, py - half * 1.1, half * 2.2, half * 2.2);
        } else {
          ctx.globalAlpha = clamp01(alpha * 0.16);
          const g = star.warmth > 0 ? sprites.glowWarm : sprites.glowCool;
          ctx.drawImage(g, px - half * 0.7, py - half * 0.7, half * 1.4, half * 1.4);
        }
        ctx.globalAlpha = clamp01(alpha);
        ctx.drawImage(sprites[`glint-${tint}`], px - half, py - half, half * 2, half * 2);
      } else {
        const r = (0.5 + 0.86 * star.magnitude) * s * scale * grow * (light ? 1.1 : 1);
        if (light) {
          // on a pale page a light needs a little deeper sky around it
          ctx.globalAlpha = clamp01(alpha * 0.55);
          ctx.drawImage(sprites.dusk, px - r * 4.2, py - r * 4.2, r * 8.4, r * 8.4);
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
    const scale = c.starScale;
    ctx.globalCompositeOperation = 'source-over';
    if (pal.dark) {
      // a tight warm glow: the room stays dark
      const quiet = 0.5 + 0.5 * (1 - pal.nightness);     // a little more of it while there is still light in the sky
      for (const [radius, a] of [[12, 0.07 * quiet], [5, 0.16]]) {
        const r = radius * s * scale * (0.7 + 0.3 * k) * breath;
        ctx.globalAlpha = clamp01(a * k);
        ctx.drawImage(sprites.glowWarm, px - r, py - r, r * 2, r * 2);
      }
    } else {
      // on a light page: a little dusk gathered round it, so the cream star shows
      const r = 17 * s * scale * (0.7 + 0.3 * k) * breath;
      ctx.globalAlpha = clamp01(0.5 * k);
      ctx.drawImage(sprites.dusk, px - r, py - r, r * 2, r * 2);
    }
    ctx.globalAlpha = clamp01(k) * (0.9 + 0.1 * breath);
    const half = 14 * s * scale * (0.62 + 0.38 * k);
    ctx.drawImage(sprites[`spark-${pal.dark ? 'tonight' : 'white'}`], px - half, py - half, half * 2, half * 2);
    if (spark > 1) {                                     // past full: the spark
      ctx.globalAlpha = clamp01((spark - 1) * 2);
      const r = 2.4 * s;
      ctx.drawImage(sprites['dot-white'], px - r * 2.33, py - r * 2.33, r * 4.66, r * 4.66);
    }
    // The ring: one thin line of light going out across the whole sky, once.
    if (ring) {
      const tint = pal.dark ? lch(0.9, 0.05, 84) : lch(0.99, 0.02, 90);
      const dim = pal.dark ? lch(0.6, 0.06, 80) : lch(0.6, 0.06, 285);
      ctx.save();
      ctx.globalAlpha = 1;
      const core = pal.dark ? tint : dim;
      const k = ring.strength * (pal.dark ? 1 : 0.8);
      // a soft band, widening as it goes, and a hair of brighter light inside it
      for (const [wdt, a, back] of [[22 + ring.radius * 0.04, 0.035, 8], [11, 0.06, 4], [4.5, 0.08, 1.5], [1.6, 0.15, 0]]) {
        ctx.lineWidth = wdt * s;
        ctx.strokeStyle = css(core, clamp01(a * k));
        ctx.beginPath();
        ctx.arc(px, py, Math.max(0, ring.radius - back) * s, 0, TAU);
        ctx.stroke();
      }
      ctx.restore();
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
    const count = Math.round((G.W * G.H) / 2600 * amount);
    const sunny = 0.55 + 0.45 * smoothstep(-12, 6, pal.altDeg);
    ctx.globalCompositeOperation = 'source-over';
    for (let i = 0; i < count; i += 1) {
      const depth = hash(i, 111);
      const span = G.H + 40;
      const y = ((hash(i, 112) * span + t * (7 + 16 * depth)) % span) - 20;
      let x = hash(i, 113) * (G.W + 60) - 30 + (5 + 9 * depth) * Math.sin(t * (0.22 + 0.2 * hash(i, 114)) + hash(i, 115) * TAU) + t * 1.6 * depth;
      x = ((x % (G.W + 60)) + G.W + 60) % (G.W + 60) - 30;
      const r = 1.0 + 2.1 * depth * depth;
      ctx.globalAlpha = clamp01((pal.dark ? 0.2 + 0.42 * depth : 0.6 + 0.4 * depth) * sunny);
      ctx.drawImage(sprites.flake, (x - r) * s, (y - r) * s, r * 2 * s, r * 2 * s);
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
    const arrive = bed == null ? 1 : smoothstep(2.2, 3.1, bed) * (1 - smoothstep(4.9, 5.6, bed));
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
        const px = (m.x0 + G.ox + off.x + breath(band)) * s, py = (band.y + off.y) * s;
        ctx.globalAlpha = clamp01(pal.mistAmt * band.amt * 1.5);
        ctx.drawImage(m.canvas, px, py);
        // Opening the Duo: the light reaches the river's mist from the fold outward.
        if (open != null && band.valley) {
          const front = -(open - 0.1) * 400;             // world x the light has reached
          const settle = Math.exp(-Math.max(0, open - 1.4) / 2.2);
          const b = scratch('b', m.w, m.h);
          b.drawImage(m.canvas, 0, 0);
          b.globalCompositeOperation = 'destination-in';
          const g = b.createLinearGradient(0, 0, m.w, 0);
          const stops = 12;
          for (let k = 0; k <= stops; k += 1) {
            const x = m.x0 + ((m.w / s) * k) / stops;
            g.addColorStop(k / stops, `rgba(0,0,0,${smoothstep(front - 70, front + 30, x) * settle})`);
          }
          b.fillStyle = g;
          b.fillRect(0, 0, m.w, m.h);
          ctx.globalCompositeOperation = pal.dark ? 'lighter' : 'source-over';
          ctx.globalAlpha = clamp01(pal.mistAmt * band.amt * (pal.dark ? 0.9 : 0.8));
          ctx.drawImage(b.canvas, 0, 0, m.w, m.h, px, py, m.w, m.h);
          ctx.globalCompositeOperation = 'source-over';
        }
        ctx.globalAlpha = 1;
      });
      ctx.drawImage(plane.canvas, Math.round((G.xL + G.ox + off.x) * s), Math.round((plane.y0 + off.y) * s));
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
    const tonightAt = { x: G.ox + c.tonight.x + knollOff.x, y: c.tonight.y + knollOff.y };
    const ring = ringOf(state);

    drawStars(ctx, state, pal, time, skyOff, ring, tonightAt);
    drawShootingStar(ctx, pal, time, skyOff);

    // the moon: a quiet halo, then the disc
    if (pal.moonNow) {
      const m = state.moon;
      const clear = pal.dark ? clearOfText(state, moonNow.x, moonNow.y, c.moonR) : 1;
      const mk2 = [pal.dark, Math.round(m.fraction * 200), Math.round(m.rotation * 60), m.inDaylight, Math.round(pal.altDeg * 4), Math.round(clear * 20), Math.round(m.altitude / DEG)].join('|');
      if (G.moon.key !== mk2) { paintMoon(state, pal, clear); G.moon.key = mk2; }
      const up = smoothstep(-1.5, 0.5, m.altitude / DEG);
      const night = 1 - smoothstep(-8, 3, pal.altDeg);
      const vis = (0.42 + 0.58 * night) * up * lerp(smoothstep(0.04, 0.2, m.fraction), 1, pal.nightness) * moonNow.seen;
      const haloAmt = pal.nightness * (0.3 + 0.7 * m.fraction) * clear * up * moonNow.seen;
      if (haloAmt > 0.02) {
        // two painted rings of light, barely there: the room stays dark
        for (const [k, a] of [[5.2, pal.dark ? 0.05 : 0.5], [2.6, pal.dark ? 0.09 : 0.7]]) {
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
      ctx.globalAlpha = clamp01(sunVis);
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
        const a = cloudAlpha * fade * clearOfText(state, sx, sy, cloud.len * 0.35);
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
    const breath = (band) => (time == null ? 0 : Math.round(16 * Math.sin(TAU * (time / (240 + 37 * band.seed) + band.seed * 0.37)) * 4) / 4);
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
      G = buildGeometry(state);
      G.key = geoKey;
      G.river = buildRiver();
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
    const tone = { p: Math.round(pal.B.presence * 60) / 60, d: Math.round(pal.B.depth * 30) / 30 };
    // While an event PLAYS (the bloom swelling, the room dimming) the planes are not repainted: the
    // change of tone is laid over what is already painted as one colour adjustment — as the app would,
    // with .brightness / .saturation on the layers — and the planes are painted afresh once it settles.
    // A still (a frozen frame, the first frame) is always painted exactly.
    const nowMs = performance.now();
    const playing = time != null && Boolean(state.event) && lastRenderMs > 0 && nowMs - lastRenderMs < 600;
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
      G.tree.masks = treeMasks(TREE, mk, G.tree.h * s, s, sea);
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
        plane.mistCanvases = (plane.mists ?? []).map((band) => mistCanvas(band, pal));
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
