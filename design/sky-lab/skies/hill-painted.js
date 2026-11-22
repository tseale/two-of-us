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
//                Looking up is a STATE, not a moment: the view is up while THE NIGHT
//                HAS BEGUN — from the start of tonight's night sleep until first
//                light, asleep or awake (bedtime carries it up; first light brings
//                it down; waking and a night feed move nothing)
//
// World coordinates: points, x = 0 at the anchor window's leading edge
// (`state.phone.x`), y = the display's y in the REST pose. The Duo's cover and
// spread share the world exactly, in both poses (measured: the spread's phone
// page is the cover's picture to within 3 levels at every pixel).
//
// The URL's `look=0…1` holds any pose at any hour (the lab does not pass it on:
// it is read from location.search here). `window.__hillPainted` carries the
// render timings and the count of his stars in each pose.

import { presence as bloomOf, MOMENT, momentCaption, litFrom, easeOut } from '../lab/presence.js';
import { smoothstep, lerp } from '../lab/oklab.js';
import { nights, twinkle, ignition, hash } from '../lab/nights.js';
import { season as seasonOf } from '../lab/season.js';
import { hash2 } from '../lab/noise.js';
import { airFor, css, toRgb, lch, mix3, luminance } from './hill-painted/air.js';
import { growTree, treeMasks, crownTop } from './hill-painted/tree.js';

export const meta = {
  id: 'hill-painted',
  name: 'Hill, painted',
  blurb: 'Picture book’s place painted in true light’s air: a river valley, a knoll and one grown tree against the setting sun; when he goes down for the night the view looks up into every night of his life, and stays there until first light.',
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
  T: 90,                   // …and the turn slides the far world this far left: the tree to x 318, clear of the tab capsule (x 392–456) with the cards away — the bare poster of the bedtime moment. (With the cards on, looking up, the tree is not drawn: treeShown.)
  table: 292,              // points of sky the twilight's eight stops span
  Emax: 500,               // sun and moon: how high the zenith stands over the horizon, in points of the tall sky
  tree: { x: 408, h: 88 },
  tonight: { x: 379, y: 194 },          // tonight's star at rest: above the tree's left shoulder (rest-pose points)
  tonightUp: { x: 412, y: 270 },        // …and looking up: in the strip's clear window, between the status icons and the tab capsule (display points, the anchor window's x)
  firstUp: { x: 262, y: 43 },           // the first night's star, looking up: in the header's clear gap, between his name and the gear
  sunR: 11.5, moonR: 9.5,
  starScale: 1,
  // The phone page's cards in the standing layouts, looked-up display points (the anchor window's x),
  // as the lab lays them out (lab/chrome.js; `state.cards`, measured): the three that are there asleep
  // and awake (Today, the Feed and Diaper tiles), then the night's own — asleep: the sleep card and the
  // card under it; awake in the night (a feed): the Sleep tile and the timeline. What a four-point
  // star keeps clear of (starsFor, `free`): the table is fixed, so a star's place does not change when
  // he wakes. (The first is the Today card: at rest its edges are the header band's foot and the strip's side.)
  cards: [[20, 88.6, 362, 286.2], [20, 298.2, 185, 438.1], [197, 298.2, 362, 438.1],
    [20, 450.1, 362, 647.5], [20, 659.5, 362, 678], [20, 450.1, 362, 590], [20, 602, 362, 678]],
  glass: [1, 2, 3, 5],     // …of which these are GLASS (lab/chrome.js: `tile`, `sleep`): only the lab switch glass=place asks (starsFor) — the sky's own rule is drawn, not placed (underGlass)
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
  // Clouds: quiet banks, each drawn the way this picture draws a hill — ONE top contour set by hand,
  // crisp, run through the crests' own wobble; a flat fill that is lightest along that edge and has
  // gone to the body's tone by 45 % of the rise; and no base at all: the lowest third lets go into
  // the air, as a plane of land does into the mist at its foot. Nothing is modelled in relief (nothing
  // else in the picture is). `e`: its foot, points over the horizon; `len` × `rise`: its box.
  // `top`: the contour's masses, [centre, half-width (both along −1 … 1), height 0 … 1 of `rise`] —
  // a few of unequal size (one large, one of about half that, a small outlier, their shoulders, and
  // the long lens they stand on), never a run of like scallops; where two meet the join is rounded.
  // `wob`: the hand. Each has a designed place (the middle of the lane it drifts along), and none
  // stands whole and compact in a slot of the UI: a closed small cloud under the status glyphs is a
  // weather symbol.
  //   strip   a thin bank that comes in over the tree from the trailing edge and is always cut by it
  //           (a third of it is off the display at every moment of its drift) — weather passing
  //   gap     a small low bank in the header's clear gap, off the line of the name and the gear
  //   bank    the large one: over the clear stretch of the leading page's frieze, between the page's
  //           title and the fold (its right end stays off the cover's picture)
  //   bar     a long low bar over the valley, wholly behind the leading page's cards when they are
  //           on: it belongs to the bare panorama, the second the Duo opens
  // `rest`: it belongs to the everyday view (it leaves as the camera looks up); `up`: to the
  // looked-up one — one broken bar, low, left of the tree: nothing among his stars.
  clouds: [
    { id: 'strip', x: 453, e: 96, len: 98, rise: 10, span: 10, period: 2400, phase: 0.42, rest: true, wob: 0.7,
      top: [[0, 1, 0.46], [-0.30, 0.33, 1.0], [-0.60, 0.22, 0.56], [0.30, 0.30, 0.80], [0.66, 0.2, 0.5]] },
    // (the second family — a taller mass at one end, tailing off to a thin bar: the gap's stands at its
    // left end, the bank's at its right, toward the fold. The strip's, the valley's and the looked-up
    // one are the first: a long low bank.)
    { id: 'gap', x: 254, e: 254, len: 62, rise: 9, span: 8, period: 2800, phase: 0.5, rest: true, high: true, wob: 0.6,
      top: [[0.08, 0.92, 0.3], [-0.5, 0.36, 1.0], [-0.14, 0.3, 0.66], [0.3, 0.24, 0.4], [-0.8, 0.18, 0.45]] },   // (the last: a foot left of the head, so its left end tapers — it was a near-plumb end at 3×)
    // (the bank: 100 pt, from two ems after the leading page's longest daytime title to just short of the
    // fold, and ABOVE the title's line — its foot at y 44, over the x-height — so it is weather over the
    // page, not a mark appended to the heading. It stood on the title's own line, 22 pt after its last glyph.)
    { id: 'bank', x: -56, e: 248, len: 100, rise: 20, span: 6, period: 3000, phase: 0.5, wob: 1.0,
      top: [[0.1, 0.9, 0.3], [0.46, 0.4, 1.0], [0.1, 0.27, 0.68], [0.82, 0.15, 0.5], [-0.36, 0.3, 0.42], [-0.74, 0.2, 0.26]] },
    { id: 'bar', x: -212, e: 82, len: 250, rise: 13, span: 36, period: 2600, phase: 0.48, wob: 0.9,
      top: [[0.1, 0.9, 0.4], [0.04, 0.3, 1.0], [0.34, 0.2, 0.74], [-0.24, 0.16, 0.62], [0.62, 0.16, 0.5], [-0.66, 0.2, 0.52], [-0.86, 0.1, 0.3]] },
    { id: 'low', x: 212, e: 50, len: 176, rise: 11, span: 36, period: 3000, phase: 0.5, up: true, wob: 0.8,
      top: [[-0.22, 0.76, 0.42], [-0.36, 0.3, 1.0], [-0.02, 0.2, 0.7], [-0.7, 0.18, 0.52], [0.72, 0.24, 0.44], [0.66, 0.12, 0.6]] },
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
  // Where the sun and the moon SET on a slab: the baseline's x there is 386, behind the gear button in
  // every season. In its last hour a body is brought left by this many points (bodyX): the sun then
  // comes down behind the crown's right shoulder, limbs across it, and sets at x 324; the moon by less
  // (it sets at x 340, clear of the gear and of the crown: looking up, with the turn's 30 pt, it must
  // stay within a fifth of the window of the baseline's x — tools/measure.mjs knows its disc by that).
  sets: { sun: 62, moon: 46 },
  starScale: 0.9,
  cards: [[16, 136.6, 386, 334.2], [16, 346.2, 195, 486.1], [207, 346.2, 386, 486.1],      // (as the Duo's: Today, the two tiles; asleep; awake)
    [16, 498.1, 386, 773.7], [16, 785.7, 386, 874], [16, 498.1, 386, 638], [16, 650, 386, 843.3]],
  glass: [1, 2, 3, 5],
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
    // (none in the everyday view: the header's small landscape has no clear place for one — its one gap holds the tree.
    // Looking up: one broken bar, low, left of the tree — its whole length behind the sleep card when the cards are on.)
    { id: 'low', x: 150, e: 62, len: 176, rise: 11, span: 30, period: 3000, phase: 0.5, up: true, wob: 0.8,
      top: [[-0.22, 0.76, 0.42], [-0.36, 0.3, 1.0], [-0.02, 0.2, 0.7], [-0.7, 0.18, 0.52], [0.72, 0.24, 0.44], [0.66, 0.12, 0.6]] },
  ],
};

// The snow under a glass tile, dark appearance (cardShade): `most` — the luminance the ground there may
// have (a card is 0.0117); `reads` — what the snow's own paint comes to under a tile, as a share of its
// shaded value (the planes there are part snow, part air and mist); `floor` — never less than this share
// of its light is left (it is still snow).
const SNOW_UNDER_GLASS = { most: 0.029, reads: 1.0, floor: 0.4 };
const WORDS_SHADE_L = 0.345;   // OKLab L of the slab's snow hill behind his age line (the grey line's guard caps at 0.36)
const NIGHT_MIST = 0.198;   // OKLab L of mist in the dark appearance at night (luminance 0.0078; a card is 0.0117)
const NIGHT_WATER = 0.196;  // …and of the river there: the faintest line of reflected sky (luminance 0.0076), whatever the room's depth
// The moon's halo in the dark appearance's deep night (compose): `most` — the luminance the sky under
// the moon's lower limb may come to with the rings on it (a card is 0.0117; the gate's "at the limit"
// begins at 0.0111); `adds` — what the two rings add round the limb at their full strength (measured:
// +0.0024 at 0.93 of it); `least` — the share of themselves they keep whatever the sky.
const MOON_GLOW = { most: 0.0100, adds: 0.0027, least: 0.4 };
const STAR_PEAK = 0.85;     // the peak luminance of an ordinary night's star, as it stands (drawStars: the order of rank)
const PADL = 34;          // points of world beyond the display's leading edge (tilt, the near planes' slide)
const PADR = 44;

// ── small pure rules (exported for tools/test-math.mjs) ─────────────────────

/** `lab` held within a contrast of `sky`: not lighter than `up` : 1 against it, not darker than
 *  `down` : 1 (the limits' own ratio, on luminance + 0.05, with luminance taken as L³). A colour past
 *  the limit is brought back TOWARD THE SKY'S OWN — value, and with it chroma and hue — never only
 *  darkened (an ember held down in value alone is a dark red). `own` 0 … 1: how much of its own
 *  colour it keeps as it comes back (0: it goes the sky's way; 1: only its value is held). What keeps
 *  a cloud quiet at every hour. */
export function heldTo(lab, sky, up, down = up, own = 0) {
  const y = Math.max(0, lab[0]) ** 3, ys = Math.max(0, sky[0]) ** 3;
  const most = up * (ys + 0.05) - 0.05, least = Math.max(0, (ys + 0.05) / down - 0.05);
  const limit = y > most ? Math.cbrt(Math.max(0, most)) : y < least ? Math.cbrt(least) : null;
  if (limit == null || lab[0] === sky[0]) return lab;
  const t = Math.min(1, Math.max(0, (limit - sky[0]) / (lab[0] - sky[0])));
  const k = t + (1 - t) * Math.min(1, Math.max(0, own));
  return [limit, sky[1] + (lab[1] - sky[1]) * k, sky[2] + (lab[2] - sky[2]) * k];
}

/** How far a box [x0, y0, x1, y1] lies ACROSS the edge of a rect { x, y, width, height }: 0 while it is
 *  wholly inside it, or wholly clear of it, by `soft` points or more; 1 where an edge cuts through it. */
export function acrossEdge(box, rect, soft = 6) {
  const clear = Math.max(rect.x - box[2], box[0] - (rect.x + rect.width), rect.y - box[3], box[1] - (rect.y + rect.height));
  const inside = Math.min(box[0] - rect.x, rect.x + rect.width - box[2], box[1] - rect.y, rect.y + rect.height - box[3]);
  return 1 - Math.max(smoothstep(0, soft, clear), smoothstep(0, soft, inside));
}

/** The Duo's status icons sit this much lower while a sleep runs (the island is longer): the lab's
 *  layout table, stripClear.yMinAsleep 185 less yMin 151 (lab/core.js). */
export const ISLAND_GROWS = 34;

/** The Duo's Wi-Fi and battery glyphs: the box the two stand in (17 + 6 + 27 pt wide, 13 tall),
 *  centred in the strip's column, its foot the head of the strip's clear window (lab/chrome.js,
 *  duoStrip; cover: x 399–449, y 138–151 awake and 172–185 while a sleep runs). The one place a
 *  disc is not drawn for the chrome's sake (compose, clearOfGlyphs). */
export const GLYPHS = { width: 50, height: 13 };

/** A sleep that has just begun or ended changes the strip's clear window at once; what the sky
 *  shows there (a cloud) follows over the event's first 0.6 s: 0 as it was before … 1 as it is now.
 *  The events that start or end a sleep: bedtime, arrive, wake. Any other, or none: 1. */
export function sleepJoin(event) {
  if (!event || !['bedtime', 'arrive', 'wake'].includes(event.kind)) return 1;
  return smoothstep(0, 0.6, Math.max(0, event.age ?? 0));
}

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

  // (lab switches read from the URL, to shoot a choice both ways: see hill-painted.md, "Lab notes")
  const urlOpt = (name) => { try { return new URLSearchParams(globalThis.location?.search ?? '').get(name); } catch { return null; } };
  const urlSun = urlOpt('sun'), urlGlare = urlOpt('glare'), urlSets = urlOpt('sets'), urlGlass = urlOpt('glass'), urlMoonStar = urlOpt('moonstar'), urlField = urlOpt('field'), urlSunRamp = urlOpt('sunramp');

  // band=answers: the bedtime band without its own light — only the stars' answers (a lab switch, to
  // compare the two; the sky's own is the band held back until it is wider than the strip).
  const urlBand = (() => {
    try { return new URLSearchParams(globalThis.location?.search ?? '').get('band'); } catch { return null; }
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
  /** A white alpha mask, tinted: → a scratch of the mask's OWN size (use at once). (It was scratch B,
   *  which grows to the largest thing ever drawn through it: the tree's first paint in a page went
   *  through a scratch of exactly its size, every later one through a corner of one as wide as a plane,
   *  and the canvas rounds a semi-transparent pixel differently when it copies a part of a larger
   *  canvas — up to 4 levels along every limb and leaf edge between a fresh page and a long-lived one.
   *  The sizes are a small fixed set: the tree's masks, a cloud's, the sun's rings.) */
  function tinted(mask, colour) {
    const ctx = scratch(`t${mask.width}x${mask.height}`, mask.width, mask.height);
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
        // every pool that reaches this far, and how much of it there is this far along it. It LIES ON
        // the land, it does not fill it to a level: a thin layer along the crest in front, deeper where
        // that crest dips under the pool's own level and a breath where the land comes up through it —
        // so its top follows the form, and is ragged: long level threads, torn.
        for (const [cx, hl, level, strength] of band.pools) {
          const u = (x - cx) / hl;
          if (Math.abs(u) >= 1) continue;
          const amount = strength * Math.min(1, Math.pow(1 - Math.pow(Math.abs(u), 1.5), 1.7) * lerp(1, ragged, smoothstep(0.25, 0.75, Math.abs(u)))) * uneven;
          const depth = crest - level;                     // how deep the hollow is here, under the pool's level
          if (amount <= 0.004 || depth < -14) continue;
          const thick = lerp(4, 23, smoothstep(-10, 30, depth)) * (0.62 + 0.76 * fb(x / 83 + seed * 1.3, 7.7 + seed, 2)) + slow * 0.25;
          for (let py = Math.max(0, Math.floor(crest - thick * 1.7 - 6 - y0)); py < h; py += 1) {
            const y = y0 + py + 0.5;
            if (y > crest + 7) break;
            const lift = crest - y;                        // points above the crest it lies behind
            const thread = fb(x / 78 + seed * 2.2, y / 4.2 + seed, 3) - 0.5;
            const top = Math.max(1.5, thick * (1 + 0.95 * thread));
            // soft into the air above; thickest — brightest — low down, where it meets the dark crest in front
            const edge = smoothstep(top + 2.5, top * 0.3, lift);
            const body = 0.42 + 0.58 * smoothstep(top, 0, lift);
            const grain = 0.7 + 0.3 * fb(x / 90 + seed, y / 9 + seed * 4.1, 2);
            const a = clamp01(amount * edge * body * grain * 1.5);
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

  /** The night has begun (README, `state.nightBegun`): from the start of tonight's night sleep until
   *  first light, asleep or awake. (A lab without the field: while a night sleep runs.) */
  const nightBegunOf = (state) => state.nightBegun ?? state.tonightLit ?? state.asleep === 'night';

  /** How far the camera has looked up, 0 rest … 1 up. Looking up is a STATE: the view is up while the
   *  night has begun, and still — 1 then, 0 otherwise, whichever sleep is running or has ended. Three
   *  events carry it between the two: bedtime (0 until 0.3 s, up by 2.4 s on the Duo and by 2.7 s on
   *  the slab, whose sky is twice as tall — lab/presence.js, MOMENT.rise — and it stays), a night
   *  sleep that arrives from elsewhere (`arrive`: up over 2.5 s, quietly, behind the cards) — both
   *  only where the night begins with them (`event.begunBefore` false) — and first light (`settle`:
   *  down over 2.6 s, behind the cards). Waking moves nothing, at any hour, after any sleep; nor does
   *  a night feed. Under Reduce Motion there is no move: this is then the weight of the looked-up
   *  still in a short dissolve (0.6 s: at bedtime once the cards are away, at once for the other two).
   *  The URL's `look=` holds any pose. */
  function lookOf(state) {
    if (urlLook != null) return urlLook;
    const e = state.event;
    const a = e ? e.age : 0;
    const ease = (t) => t * t * t * (t * (t * 6 - 15) + 10);
    const still = state.reduceMotion;
    const fade = MOMENT.quiet.dissolve;
    if (e && e.kind === 'settle') {
      if (still) return 1 - smoothstep(0, fade, a);
      return a <= 0.1 ? 1 : a < 2.7 ? 1 - ease((a - 0.1) / 2.6) : 0;
    }
    if (!nightBegunOf(state)) return 0;
    if (e && !e.begunBefore && state.asleep === 'night') {
      if (e.kind === 'bedtime') {
        if (still) return smoothstep(MOMENT.reduced.dissolve[0], MOMENT.reduced.dissolve[1], a);
        const [t0, t1] = MOMENT.rise[G.cfg.kind];
        return a <= t0 ? 0 : a < t1 ? ease((a - t0) / (t1 - t0)) : 1;
      }
      if (e.kind === 'arrive') return still ? smoothstep(0, fade, a) : a < 2.5 ? ease(a / 2.5) : 1;
    }
    return 1;
  }

  /** Is the view on its way between the poses (an event is carrying it)? 0 at rest and up, 1 between:
   *  a smooth gate for what belongs only to the move. */
  const onTheWay = (look) => smoothstep(0, 0.08, look) * (1 - smoothstep(0.92, 1, look));

  /** How lit tonight's star is, 0 … 1 (… 1.35 at the spark's flare). Lit exactly while the night has
   *  begun. It comes on only where the night begins — with the moment's spark, or quietly over the
   *  first 0.8 s when the night's sleep arrives from elsewhere — and goes out only at first light, as
   *  the view settles. It is lit once, from what it was (`litFrom`): nothing lights or cools it at a
   *  wake, and a star that is already lit is never put out to be lit again. Under Reduce Motion it
   *  has no spark: it belongs to the looked-up still and dissolves in and out with it. */
  function sparkOf(state) {
    const e = state.event;
    if (e && e.kind === 'settle') return state.reduceMotion ? 1 : 1 - smoothstep(0.1, 2.3, e.age);   // first light: it goes out with the other stars
    if (!nightBegunOf(state)) return 0;
    if (!e || state.asleep !== 'night' || state.reduceMotion) return 1;
    if (e.kind === 'bedtime') return litFrom(e.begunBefore, ignition(e.age));
    if (e.kind === 'arrive') return litFrom(e.begunBefore, smoothstep(0, 0.8, e.age));
    return 1;
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

  /** Where a plane's rest-pose picture sits on the display for this pose: an offset in points.
   *  (A plane's whole travel between the poses is a whole number of device pixels, so it comes to
   *  rest ON the pixel grid: the last frame of a move is the standing frame, not a soft one.) */
  function planeOffset(plane, look, tilt) {
    const c = G.cfg, s = G.s;
    return {
      x: -(Math.round(c.T * plane.slide * s) / s) * look + tilt.x * plane.tilt[0],
      y: (Math.round(c.D * plane.sink * s) / s) * look + tilt.y * plane.tilt[1],
    };
  }
  /** A layer's place in device pixels. At rest it is on the grid (a resampled layer is a soft one).
   *  While the camera moves (0 < look < 1) it is left where it is, between pixels, and the layer is
   *  drawn smoothed: a move rounded to whole pixels holds for a frame and then nudges at its slow ends. */
  const onGrid = (v, look) => (look > 0 && look < 1 ? v : Math.round(v));
  /** …and a plane between pixels is drawn with the canvas's better resampler: its plain bilinear one
   *  truncates, which takes a near-black layer down half a level — the whole picture a shade darker
   *  for the length of the move, and a step at each end. Only the planes: everything else (the mist,
   *  which breathes between pixels at rest too; the star sprites) is drawn the one way, moving or still. */
  const drawPlane = (ctx, image, x, y, look) => {
    const moving = look > 0 && look < 1;
    if (moving) { ctx.imageSmoothingEnabled = true; ctx.imageSmoothingQuality = 'high'; }
    ctx.drawImage(image, onGrid(x, look), onGrid(y, look));
    if (moving) ctx.imageSmoothingQuality = 'low';
  };
  const SKYPLANE = { slide: 1, sink: 1, tilt: [-1.2, -0.6] };
  /** The land's skyline on the DISPLAY at display x, in this pose and tilt (points): the highest
   *  crest of the planes that move with the sky, each where its plane now is. */
  function skylineNow(x, look, tilt) {
    let y = Infinity;
    for (const p of G.planes) {
      if (p.sink !== 1) continue;
      const off = planeOffset(p, look, tilt);
      for (const sh of p.shapes) if (!sh.mist && !sh.floor) y = Math.min(y, sh.at(x - G.ox - off.x) + off.y);
    }
    return y;
  }

  // ── where the lights are ─────────────────────────────────────────────

  /** A body's height over the horizon in points of the TALL sky: its real altitude, opened out near
   *  the horizon (the last degrees of a sunset are the ones worth seeing) and easing toward the zenith. */
  function bodyE(altDeg) {
    if (altDeg < 0) return 8.5 * altDeg;
    return G.cfg.Emax * (1 - Math.exp(-altDeg / 45)) + 12 * (1 - Math.exp(-altDeg / 2.5));
  }

  /** A body's x as a fraction of the anchor window. It is the baseline's (`state.sun.x`,
   *  `state.moon.x`: the lab's clock) everywhere but in ONE place, by the director's leave: the
   *  ordinary iPhone's last hour. There the baseline sets the sun at x 386 — behind the gear button in
   *  every season, so the picture this sky is for, the tree against the low sun, did not exist on a
   *  slab. On the slab, on the SETTING side, a body under 12° of altitude is brought left, by 6° the
   *  whole way (`SLAB.sets`). The easing in (12° … 6°) happens above the header, where a body is not
   *  drawn (`bodyAt().seen`): in sight it only ever goes down and to the right, at the baseline's own
   *  pace, as the real one does. The rising side, the Duo, and a body high in the sky are the
   *  baseline's. A pure function of the baseline's x and the altitude: the sky's glow, the lamp and
   *  the burn through the crown all follow the same x, in both poses. */
  function bodyX(xFrac, altDeg, which) {
    const sets = urlSets === 'old' ? null : G.cfg.sets;
    if (!sets) return xFrac;
    const w = smoothstep(0.5, 0.62, xFrac) * (1 - smoothstep(6, 12, altDeg));
    return xFrac - (w * sets[which]) / G.Wa;
  }

  /** Where a body is on the display (points, before tilt). The sun and the moon have ONE place in the
   *  world — a high one is above the top of the everyday view and comes down into view with the sky
   *  when the camera looks up. `seen`: they are never drawn behind the header (Duo: the whole band;
   *  slab: the status bar), so a body crossing it is out of sight until it is clear.
   *  Once the view has left the rest pose a body comes out from under the header slowly, over 90 pt
   *  of sky and not 15 — and on the slab from under the whole header (his name and age stand in it),
   *  not only the status bar: during the rise a moon coming down with the sky does not roll through
   *  his name or blink on under the header; it arrives in open sky as the view settles. (Looking up,
   *  no body ever rests that close under the header — the Duo's highest moon stands at y ≈ 183, the
   *  slab's at y ≈ 250 — so the standing frames are as they were; and at rest nothing changes.)
   *  `head`: where the header lets it go and the points of its descent over which it comes out (HEAD:
   *  15) — 6 for the slab's SUN on the setting side (sunHead): a sun at half strength is a dim tan ball, and over 15 pt the slab's
   *  stood above the tree as one for four to five minutes of every afternoon (15:48–15:52 on
   *  21 November) — behind the gear, where it used to set, nobody saw it. Over 6 it is under two
   *  minutes: nothing of it until its top is 10 pt under the status icons, which are what it comes
   *  out from under here, all of it at 16 (the icons' foot is y 39; the disc is whole from y 64 —
   *  the slab's status bar is a whole row of glyphs, so the bar hides a disc, not a glyph's box as on
   *  the Duo: compose, clearOfGlyphs). The 6 pt are the HEAD of the
   *  old 15, not their tail: at the tail (whole at y 73, where it always had been) the sun was out
   *  of sight for four minutes longer than it ever was, and the minute the tools shoot a July
   *  evening (19:55: y 68) was one of them — a bedtime that opened on no sun and blinked one on as
   *  the view began to rise. On the RISING side the slab's sun keeps the 15 pt, and its disc is not
   *  drawn above the avatar: sunHead, risingDisc. (sunramp=old: the lab switch, the 15 pt on both
   *  sides and the rising disc as it was.) */
  function bodyAt(state, xFrac, altDeg, R, look, head = HEAD) {
    const c = G.cfg;
    const E = bodyE(altDeg);
    const y = c.H0 - E + c.D * look;
    const foot = c.kind === 'duo' ? (state.layout?.firstCardTop ?? 88.6) + R - 3 : head.foot;
    let seen = smoothstep(foot, foot + head.ramp, y);
    if (look > 0) {
      const under = c.kind === 'duo' ? foot : (state.layout?.firstCardTop ?? 136.6) - 6 + R;
      // (…but a body the rest pose already shows stays in sight as the view leaves it: the 90 pt are for
      // what comes down from above the header. Without this a sun standing in the slab's header at a
      // July bedtime — whole at y 68 — went out at 0.93 s of the rise and was back at 1.2 s, and one
      // beside the Duo's island dipped to half as the view began to move.)
      const atRest = smoothstep(foot, foot + head.ramp, y - c.D * look);
      seen = lerp(seen, Math.max(atRest, smoothstep(under, under + 90, y)), smoothstep(0, 0.12, look));
    }
    return { x: xFrac * G.Wa - c.T * look, y, E, seen };
  }

  /** Where the header lets a body go (bodyAt): `foot` — the slab's status bar (the Duo's is its first
   *  card's top, bodyAt) — and `ramp`, the points of descent over which the body comes out. */
  const HEAD = { foot: 58, ramp: 15 };
  /** …and the slab's SUN: on the SETTING side the 6 pt head (above) — whole 16 pt under the status
   *  icons, a dim disc for under two minutes; on the RISING side the header's own 15, as it always
   *  was. Which side: by where the sun stands across the display (eased over the middle tenth, where
   *  it is far above the header on any day). */
  const sunHead = (xFrac) => (G.cfg.kind === 'slab' && urlSunRamp !== 'old'
    ? { foot: HEAD.foot, ramp: lerp(15, 6, smoothstep(0.45, 0.55, xFrac)) } : HEAD);

  /** THE SLAB'S RISING SUN IS NOT DRAWN ABOVE THE AVATAR. In the morning the sun climbs the leading
   *  edge, goes behind the avatar some eight minutes after sunrise (the buttons' rule: clearOfButtons) and
   *  comes clear of its rim only at y 64–61, six points under the status bar. Over the header's 15 pt
   *  that was a ghost of a disc for a minute (a tenth of its strength on 4 July, less in November and
   *  January); while the 6 pt head served both sides it was a tan ball above the avatar's shoulder,
   *  under the clock, for two or three minutes (4 Jul 05:57–05:59, at up to 0.45 of itself; 21 Nov
   *  07:25–07:26; 15 Jan 07:55–07:56). So on the rising side the DISC has gone by the time it stands
   *  above the avatar's top (all of it 15 pt lower, where the avatar hides it anyway): once behind
   *  the avatar it does not come out again. Its halo keeps the header's own 15 pt, as before — behind
   *  a button there is only its glow. What is seen of a slab's sunrise is the disc on the horizon for
   *  its first eight minutes or so, then its glow round the avatar.
   *  → 0 … 1 for the sun's disc at display height `y`. */
  const risingDisc = (state, xFrac, y) => {
    const box = G.cfg.kind === 'slab' && urlSunRamp !== 'old' ? state.layout?.avatar : null;
    if (!box) return 1;
    return 1 - (1 - smoothstep(0.45, 0.55, xFrac)) * (1 - smoothstep(box.y + 3, box.y + 18, y));
  };

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
    // (The room's dimming across a sleep's start and end is the lab's — lab/presence.js, roomDepth: at a
    // wake it starts from what that sleep had and eases out, and the bloom is taken from that eased depth.)
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
    const sunXf = bodyX(state.sun.x, altDeg, 'sun'), moonXf = moon ? bodyX(moon.x, moon.altitude / DEG, 'moon') : 0;
    const sunX = sunXf * G.Wa;
    const sunRest = bodyAt(state, sunXf, altDeg, c.sunR, 0, sunHead(sunXf));
    const moonRest = moon ? bodyAt(state, moonXf, moon.altitude / DEG, c.moonR, 0) : null;

    // Which light the land and the clouds answer: the sun until it is well down, then the moon.
    const byMoon = altDeg < -9.5 && moonlight > 0.02;
    const lamp = byMoon
      ? { kind: 'moon', x: moonXf * G.Wa, y: moonRest.y, power: moonlight }
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
      sunX, sunXf, moonXf, sunRest, moonRest, lamp, byMoon,
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

  /** THE DRAWING-IN HAS A FLOOR IN TIME. A four-point star's rays are in by the time an arriving glass
   *  card is at a fifth of its opacity (underGlass). In the bedtime moment that is 0.15 s of the cards'
   *  1.2 s return — eight or nine frames, a quick fade. Reduce Motion's cards return in half the time,
   *  and there a fifth of a card came in three frames: a cut. So under Reduce Motion a card on its way
   *  back draws a star in no faster than the full moment's cards would, by the time since the return
   *  began (lab/presence.js, MOMENT). 1 everywhere else: the full moment and every standing frame are
   *  as they were. (The app's touch that ends the moment brings the cards back in 0.3 s: the same
   *  floor is wanted there — port note 3. It was the discs' floor too, while a returning card took a
   *  disc away: it takes none now — compose.) */
  function leavingPace(state) {
    if (!state.reduceMotion || !state.event || state.event.kind !== 'bedtime' || state.asleep !== 'night') return 1;
    const since = state.event.age - MOMENT.reduced.back[0];
    if (!(since >= 0)) return 1;
    return smoothstep(0, 0.2, easeOut(since / (MOMENT.back[1] - MOMENT.back[0])));
  }

  /** How far a four-point star at display (x, y) stands UNDER GLASS: 0 in the open or behind an opaque
   *  card … 1 inside a glass one (`tile`, `sleep`, the tab capsule, the toast — lab/chrome.js), by
   *  that card's opacity — all of it by the time the card is at a FIFTH of its opacity (and under
   *  Reduce Motion no faster than leavingPace): one for one, the mark was still a small sparkle straight after "7:34 PM"
   *  until a returning tile was half there (4.7–5.0 s of the bedtime moment). Eased over the 7 pt its
   *  rays reach, for a star the moving camera carries across an edge; in a standing layout a
   *  four-point star keeps 10 pt from every edge (starsFor), so there it is 0 or 1. It asks the cards
   *  where they ARE (state.cards), not a table: in the app the rule follows the rows when the list
   *  scrolls. */
  function underGlass(state, x, y) {
    let g = 0;
    const pace = leavingPace(state);
    for (const card of state.cards ?? []) {
      if (card.kind !== 'tile' && card.kind !== 'sleep' && card.kind !== 'tabbar' && card.kind !== 'toast') continue;
      const o = clamp01(card.opacity ?? 1);
      if (!(o > 0)) continue;
      const inside = Math.min(x - card.x, card.x + card.width - x, y - card.y, card.y + card.height - y);
      g = Math.max(g, (o < 1 ? Math.min(smoothstep(0, 0.2, o), pace) : 1) * smoothstep(-7, 7, inside));
    }
    return g;
  }

  /** The sun's halo: two painted rings of light, soft-edged. They were filled through a blur filter on
   *  EVERY frame, which made any frame with the sun in view cost nine times one without (35 ms against
   *  4). Now they are painted once into sprites and kept (G.sun), keyed like the moon's:
   *   · a held frame (a still, a film's frame, a gate's) keeps the two rings exactly as they were
   *     painted — the same fill through the same blur, at the sun's own sub-pixel place, in its colour
   *     and at its alpha — so the picture is the old one to the level, and the sprites are painted
   *     again only when one of those changes (not while only `t` moves);
   *   · while the animation runs, colour and alpha change with every frame of an event and the place
   *     with the camera, so there the rings are two white masks blurred once per display, tinted and
   *     laid each frame (a bilinear copy: within two levels of the exact one, inside the halo only).
   *  → draws them into `ctx`. `alphas`: the two rings' own (0.22 and 0.34) times the halo's amount. */
  const SUN_RINGS = [[3.3, 0.22, 2.1, 1.4], [1.95, 0.34, 0.7, 1.4]];     // [radii, alpha, the hand's seed, the edge's softness in points]
  // (the pale page's: the same two rings, DEEPER than the sky — there the colour is in them, not in the
  // disc: an inner one from the disc's edge to 1.9 radii, about a half with the outer one under it, and
  // an outer one to 3.3 radii at a fifth — and softer-edged: shot with the dark print's crisp edges, two
  // deeper rings round an edged disc are a target)
  const SUN_RINGS_LIGHT = [[3.3, 0.2, 2.1, 6.5], [1.95, 0.375, 0.7, 3.2]];
  function drawSunHalo(ctx, state, x, y, colour, amount, rings = SUN_RINGS) {
    const s = G.s, R = G.cfg.sunR * s;
    const soft = Math.max(...rings.map((r) => r[3]));
    const half = Math.ceil(R * 3.3 * 1.03 + soft * s * 3) + 2;
    if (!G.sun) G.sun = { key: '', sprites: null, masks: null, masksFor: null };
    if (state.frozen) {
      const ix = Math.floor(x), iy = Math.floor(y);
      const alphas = rings.map(([, a]) => clamp01(a * amount));
      const key = [colour, alphas.map((a) => a.toFixed(5)).join(','), (x - ix).toFixed(4), (y - iy).toFixed(4), half, soft].join('|');
      if (G.sun.key !== key || !G.sun.sprites) {
        G.sun.sprites = rings.map(([k, , seed, blur], i) => {
          const sprite = G.sun.sprites && G.sun.sprites[i] && G.sun.sprites[i].width === half * 2 ? G.sun.sprites[i] : mk(half * 2, half * 2);
          const b = sprite.getContext('2d');
          b.setTransform(1, 0, 0, 1, 0, 0);
          b.filter = 'none';
          b.globalAlpha = 1;
          b.clearRect(0, 0, half * 2, half * 2);
          b.globalAlpha = alphas[i];
          b.fillStyle = colour;
          b.filter = `blur(${blur * s}px)`;
          b.fill(discPath(half + (x - ix), half + (y - iy), R * k, 0.02, seed));
          b.filter = 'none';
          return sprite;
        });
        G.sun.key = key;
      }
      ctx.globalAlpha = 1;
      for (const sprite of G.sun.sprites) ctx.drawImage(sprite, ix - half, iy - half);
      return;
    }
    if (!G.sun.masks || G.sun.masks[0].width !== half * 2 || G.sun.masksFor !== rings) {
      G.sun.masksFor = rings;
      G.sun.masks = rings.map(([k, , seed, blur]) => {
        const mask = mk(half * 2, half * 2);
        const b = mask.getContext('2d');
        b.filter = `blur(${blur * s}px)`;
        b.fillStyle = '#fff';
        b.fill(discPath(half, half, R * k, 0.02, seed));
        b.filter = 'none';
        return mask;
      });
    }
    rings.forEach(([, a], i) => {
      ctx.globalAlpha = clamp01(a * amount);
      ctx.drawImage(tinted(G.sun.masks[i], colour), 0, 0, half * 2, half * 2, x - half, y - half, half * 2, half * 2);
    });
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

  /** How much the moon is the DAY's moon, 0 … 1: the night's cream moon until the sun is 3° under the
   *  horizon, wholly the day's once it stands 7° over it — through a dawn or a dusk it goes from one to
   *  the other by its colour, whole (it used to thin to a quarter of itself: a flat grey ghost). */
  const urlDayMoon = urlOpt('daymoon');
  const dayMoonOf = (pal) => (urlDayMoon === 'old' ? 0 : smoothstep(-3, 7, pal.altDeg));

  /** The sky as it is painted behind the moon (the moon has one place in the world, so this is the
   *  same in both poses): what a day moon is held to. */
  const skyBehindMoon = (pal, lower = 0) => {
    const mr = pal.moonRest;
    return mr ? pal.air.show(pal.air.skyAt((mr.x - pal.sunX) / G.Wa, Math.max(0, mr.E - lower) / G.cfg.table)) : null;
  };

  /** The moon, painted: the whole disc barely there, the lit part in cream with one thin wash.
   *  BY DAY it is a real pale day moon, not a flat ghost of the night's: only its lit part, in the
   *  sky's own colour gone a little toward white — held within 1.15 : 1 of the sky behind it — with a
   *  soft limb and the seas as the sky showing through. It does not glow, and burns nothing. */
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
    const dayAmt = dayMoonOf(pal);
    const sky = dayAmt > 0 ? skyBehindMoon(pal) : null;
    const pale = sky ? heldTo(lch(pal.dark ? 0.86 : 0.992, 0.012, 245), sky, 1.15, 1.15, 0.3) : null;
    let cream = pal.dark ? mix3(lch(0.34, 0.03, 290), full, clear) : full;
    if (pale) cream = mix3(cream, pale, dayAmt);
    const whole = discPath(c, c, R, 0.012, 2.2);
    const shine = smoothstep(0.03, 0.3, m.fraction);
    ctx.fillStyle = css(pal.dark ? lch(0.27, 0.045, 272) : lch(0.90, 0.03, 275), (pal.dark ? 0.42 : 0.35) * night * shine);
    ctx.fill(whole);
    const b = scratch('b', size, size);
    b.save();
    b.translate(c, c);
    b.rotate(m.rotation);
    b.fillStyle = css(cream);
    if (dayAmt > 0.02) b.filter = `blur(${(0.85 * dayAmt * s).toFixed(2)}px)`;     // a soft limb by day
    b.fill(moonPhasePath(m.fraction, R));
    b.filter = 'none';
    b.restore();
    b.globalCompositeOperation = 'source-atop';
    const seas = pal.dark ? mix3(lch(0.32, 0.03, 290), lch(0.84, 0.04, 80), clear) : lch(0.945, 0.028, 82);
    b.fillStyle = css(sky ? mix3(seas, sky, dayAmt) : seas, lerp(0.5, 0.16, dayAmt));     // (by day a breath of them: two clear patches on a pale disc are a face)
    b.beginPath();
    b.ellipse(c - 0.42 * R, c + 0.36 * R, 0.8 * R, 0.5 * R, -0.7, 0, TAU);       // one thin wash: the seas, as a painter hints them
    b.fill();
    b.beginPath();
    b.ellipse(c + 0.3 * R, c - 0.45 * R, 0.34 * R, 0.24 * R, 0.4, 0, TAU);
    b.fill();
    const day = lerp(m.inDaylight ? lerp(0.6, 1, night) : 1, 1, dayAmt);      // (the day moon is its own colour, whole: it is not the night's seen through)
    ctx.globalAlpha = urlDayMoon === 'none' ? 1 - dayAmt : day;
    ctx.drawImage(b.canvas, 0, 0, size, size, 0, 0, size, size);
    ctx.globalAlpha = 1;
  }

  // ── clouds ───────────────────────────────────────────────────────────

  /** A cloud is drawn the way this picture draws a hill: ONE top contour set by hand (the table's
   *  `top`), crisp against the sky, and paint laid flat under it — no relief, no outline of circles,
   *  no ruled base. Its masks:
   *    body   everything under the contour, let go into the air below. THE UNDERSIDE IS NOT A LEVEL
   *           LINE: each stretch of the bank lets go at its own height (`foot`: two or three slow
   *           swells along it, 3–25 % of the rise) and as softly as it will (`fade`: over 18–42 % of
   *           the rise), and both ends thin UPWARD — a shallow uneven curve. (It ended on one
   *           level foot: three flat-bottomed cut-outs of one shape, nearer floating islands than weather.)
   *    lit    the same, fullest at the top edge and gone by 45 % of the rise: the light on its top
   *    litSide  that light only where the bank is TURNED TO THE LAMP: the third of its length on the
   *           lamp's side, and the flanks of its masses that face that way; the far side goes without.
   *           What a low sun, or the moon, puts on it (a high sun lights the whole top: `lit`)
   *    under  the low part of it: what the afterglow warms, and a high sun leaves a breath deeper.
   *           (At sunset the body between a lit top and a warm underside reads as a darker lens inside
   *           the cloud. Warming the cloud all the way up instead was tried: it is then the sunset sky's
   *           own orange, and at 1× it is gone. The plum body is what makes it a cloud there; what was
   *           changed is that the light on its top is no longer a line round the whole of it.)
   *    rim    one dry line, a point wide, along the parts of the contour that face the lamp, broken
   *           where the brush skips (under a low sun, or the moon: the knoll's rim is the model)
   *  The rim and `litSide` know where the lamp is, and only which side of the cloud: `light.side`. */
  function buildCloud(cloud, light) {
    const s = G.s;
    const L = cloud.len, R = cloud.rise;
    const pad = 4;
    const w = Math.ceil((L + 2 * pad) * s), h = Math.ceil((R + 3 + 2 * pad) * s);
    const cx = w / 2, cy = h - (pad + 1) * s;             // the middle of its foot
    const seed = Math.round(L * 3 + cloud.e) % 251;
    const wob = cloud.wob ?? 1;
    // the contour: its masses run together (a soft maximum: where two meet the join is rounded, never a
    // cusp), then the hand's wobble, as a crest has — none of it at the two ends
    const top = new Float32Array(w).fill(-9);             // the contour's height over the foot at each device column, points
    for (let px = 0; px < w; px += 1) {
      const x = (px + 0.5 - cx) / s, u = x / (L / 2);
      if (Math.abs(u) >= 1) continue;
      let sum = 0;
      for (const [c0, hw, ht] of cloud.top) {
        const t = Math.abs((u - c0) / hw);
        if (t < 1) sum += Math.pow(ht * Math.pow(1 - Math.pow(t, 2.2), 0.55), 6);
      }
      if (!(sum > 0)) continue;
      const ends = smoothstep(0, 0.16, 1 - Math.abs(u));
      const hand = ((fb(x / 70 + seed * 13.7, seed * 3.1 + 0.5, 2) - 0.5) * 2.6 + (vn(x / 11 + seed * 5.3, 7.7) - 0.5) * 0.6) * wob * ends;
      top[px] = Math.pow(sum, 1 / 6) * R + hand;
    }
    // (rounded once more by the brush's own width — a point and a half, two on the large one: no join between two masses is a cusp)
    {
      const raw = top.slice(), r = Math.max(1, Math.round((1.3 + 0.035 * R) * s));
      for (let px = 0; px < w; px += 1) {
        if (!(raw[px] > -9)) continue;
        let sum = 0, wt = 0;
        for (let k = -2 * r; k <= 2 * r; k += 1) {
          const q = px + k;
          if (q < 0 || q >= w) continue;
          const g = Math.exp(-(k * k) / (2 * r * r));
          sum += Math.max(0, raw[q]) * g; wt += g;
        }
        top[px] = sum / wt;
      }
    }
    const litDepth = 0.45 * R, rimW = 1.0;
    const reach = Math.max(1, Math.round(2.5 * s));
    const n = w * h;
    const aBody = new Uint8ClampedArray(n), aLit = new Uint8ClampedArray(n), aSide = new Uint8ClampedArray(n), aUnder = new Uint8ClampedArray(n), aRim = new Uint8ClampedArray(n);
    const sided = Math.abs(light.side);
    for (let px = 0; px < w; px += 1) {
      const t = top[px];
      if (!(t > 0)) continue;
      const x = (px + 0.5 - cx) / s, u = x / (L / 2);
      // where this stretch lets go, points over the bank's lowest: its own slow swell, and the ends thinning upward
      const lift = 0.42 * Math.pow(1 - smoothstep(0, 0.2, 1 - Math.abs(u)), 1.3);          // (the last tenth of its length at each end)
      // (the swell never takes more than half of what stands there: a thin tail stays a thin bar, it is not eaten)
      const foot = Math.max(R * lift, Math.min(0.5 * t, R * (0.03 + 0.22 * fb(x / (L * 0.23) + seed * 0.71, seed * 1.9 + 3.3, 2)) + 0.7 * (vn(x / 27 + seed * 0.37, 2.2) - 0.5)));
      const fade = Math.max(0.3, Math.min(0.85 * (t - foot), Math.max(2, R * (0.18 + 0.24 * vn(x / (L * 0.31) + seed * 2.3, 5.5)))));   // …and how softly
      const dry = smoothstep(0, 0.07, 1 - Math.abs(u));               // the two ends dry out
      // how squarely the contour here faces the lamp's side (its top faces the sky: a little, always)
      const slope = (top[Math.min(w - 1, px + reach)] - top[Math.max(0, px - reach)]) / ((2 * reach) / s);   // + it rises to the right
      const face = clamp01(0.4 - light.side * slope * 1.5);
      // …and how far this stretch of the bank is turned to the lamp: the third of its length on that side, wholly
      // (a lamp that stands under or over the bank — neither side — lights its whole top a little less)
      const turned = lerp(0.72, smoothstep(-0.5, 0.3, Math.sign(light.side) * u) * (0.45 + 0.55 * clamp01(0.6 - Math.sign(light.side) * slope * 1.5)), sided);
      const skip = smoothstep(0.36, 0.5, fb(x / 9 + seed * 1.3, 4.4, 2));   // the brush skipping: runs of line, and gaps
      for (let py = 0; py < h; py += 1) {
        const yUp = (cy - (py + 0.5)) / s;
        const d = t - yUp;                                 // points under the contour
        if (d < -0.5 / s) continue;
        const hgt = yUp - foot;
        if (hgt <= 0) break;
        const edge = clamp01(d * s + 0.5);                // crisp at the contour: one device pixel
        const a = edge * smoothstep(0, fade, hgt) * dry;
        const k = py * w + px;
        aBody[k] = 255 * a;
        aLit[k] = 255 * a * (1 - smoothstep(0, litDepth, d));
        aSide[k] = aLit[k] * turned;
        aUnder[k] = 255 * a * (1 - smoothstep(0.12 * R, 0.62 * R, hgt));
        aRim[k] = 255 * edge * dry * skip * face * (1 - smoothstep(rimW * 0.5, rimW, d)) * smoothstep(0, fade * 0.5, hgt);
      }
    }
    const cut = (alpha) => imageCanvas(w, h, (d) => {
      for (let k = 0; k < n; k += 1) { d[k * 4] = 255; d[k * 4 + 1] = 255; d[k * 4 + 2] = 255; d[k * 4 + 3] = alpha[k]; }
    });
    return { w, h, cx, cy, body: cut(aBody), lit: cut(aLit), litSide: cut(aSide), under: cut(aUnder), rim: cut(aRim) };
  }

  /** Where a cloud's light comes from: which side of it the lamp stands on (−1 left … 1 right, in
   *  halves — all its rim needs), how far across the sky from the sun it lies (`far`) and how low the
   *  sun is (`low`). `key` names what its masks were cut for. */
  function cloudLight(cloud, pal, x, y) {
    const side = Math.round(clamp((pal.lamp.x - x) / 60, -1, 1) * 2) / 2;
    const far = smoothstep(0.1, 1.35, Math.abs(pal.dxSun(x)));
    const low = pal.lamp.kind === 'sun' ? 1 - smoothstep(5, 14, pal.altDeg) : 0;
    return { side, far, low, key: `${side}` };
  }

  function paintCloud(cloud, pal, x, y, light) {
    if (!cloud.masks || cloud.maskKey !== light.key) {
      const tb = performance.now();
      cloud.masks = buildCloud(cloud, light);
      timing.clouds = (timing.clouds ?? 0) + performance.now() - tb;
      cloud.maskKey = light.key;
      cloud.canvas = mk(cloud.masks.w, cloud.masks.h);
    }
    const { w, h, body, lit, litSide, under, rim } = cloud.masks;
    const air = pal.air, cl = air.cloud;
    const hi = Boolean(cloud.high);
    const far = light.far;
    const litAmt = pal.byMoon ? (hi ? 0.8 : 0.95) * pal.moonlight : hi ? cl.hiAmt : cl.loAmt;
    let litLab = pal.byMoon ? air.silver : hi ? cl.hiLit : cl.loLit;
    const shadeLab = hi ? cl.hiShade : cl.loShade;
    const skyHere = air.skyAt(pal.dxSun(x), (G.cfg.H0 - y + cloud.rise * 0.5) / G.cfg.table);
    // The underside catches the afterglow: from the last of the sun until the twilight has gone, the
    // low part of it is the warmest thing on the cloud (ember near the sun, rose away from it).
    const after = pal.byMoon ? 0 : smoothstep(7, 1.5, pal.altDeg) * smoothstep(-6.5, -2.5, pal.altDeg);
    const underLab = mix3(lch(air.dark ? 0.60 : 0.86, air.dark ? 0.13 : 0.10, pal.altDeg > 0 ? 52 : 28), lch(air.dark ? 0.50 : 0.84, air.dark ? 0.085 : 0.07, 5), far);
    // Three paints: the light on its top, the body, the deeper low part.
    let bodyLab, deepLab;
    // While the sun is well up, a cloud is a pale thing — in the low key a pale cool one in a dusky
    // sky, a few steps over it and no more (the table's warm white prints as tan there, and a tan cloud
    // at one in the afternoon is a smudge); on the pale page a white one whose low part is a breath
    // deeper than the sky. Under 2.5° nothing of this is left: the sunset's clouds are the table's.
    const day = pal.byMoon ? 0 : smoothstep(4.5, 11, pal.altDeg);
    if (air.dark && !pal.byMoon) {
      // the low key's lit cloud keeps its fire: apricot under a low sun, rose after it
      const warm = smoothstep(14, 6, pal.altDeg) * smoothstep(-9, -4, pal.altDeg);
      litLab = mix3(litLab, lch(litLab[0] + 0.02, 0.12, pal.altDeg > 0 ? 58 : 30), 0.6 * warm);
    }
    // A low sun lights the clouds across the sky from the front: their whole face takes its colour,
    // gone to rose by the long way the light has come (the Belt's pink).
    const front = light.low * far;
    if (!pal.byMoon) litLab = mix3(litLab, air.dark ? lch(litLab[0] - 0.02, 0.072, 14) : lch(litLab[0] - 0.03, Math.hypot(litLab[1], litLab[2]) * 0.75 + 0.015, 14), (air.dark ? 0.88 : 0.7) * front);
    // (its body does not take the fire — only its lit top does: orange mixed into violet is brown)
    bodyLab = mix3(mix3(shadeLab, litLab, (air.dark ? 0.2 + 0.3 * front : 0.34 + 0.22 * front) * litAmt), skyHere, hi ? 0.34 : 0.22);
    deepLab = mix3(shadeLab, skyHere, 0.14);
    // (the low key's shadowed part under a low sun is plum, and its body mauve — never brown)
    if (air.dark && !pal.byMoon) {
      deepLab = mix3(deepLab, lch(deepLab[0] + 0.02, 0.05, 305), 0.6 * light.low);
      bodyLab = mix3(bodyLab, lch(bodyLab[0] + 0.01, 0.055, 345), 0.45 * light.low * far);
    }
    if (day > 0) {
      const tame = Math.min(1, 0.012 / (Math.hypot(skyHere[1], skyHere[2]) || 1));
      const dayLit = air.dark ? [skyHere[0] + 0.11, skyHere[1] * 0.5, skyHere[2] * 0.5] : lch(1.0, 0.006, 90);
      const dayBody = air.dark ? [skyHere[0] + 0.08, skyHere[1] * 0.8, skyHere[2] * 0.8] : [Math.max(0.985, skyHere[0] + 0.05), skyHere[1] * 0.25, skyHere[2] * 0.25];
      const dayDeep = air.dark ? [skyHere[0] + 0.015, skyHere[1], skyHere[2]] : [skyHere[0] - 0.02, skyHere[1] * tame, skyHere[2] * tame];
      litLab = mix3(litLab, dayLit, day); bodyLab = mix3(bodyLab, dayBody, day); deepLab = mix3(deepLab, dayDeep, day);
    }
    // QUIET, at every hour: a cloud belongs to the sky it is in. Each paint is held within a contrast of
    // the sky behind it — the body about a quarter over it at most, the light on its top a little
    // more, the afterglow under it and the one thin rim line the most — and never much under it.
    const Q = air.dark ? { body: [1.3, 1.1, 0.15], lit: [1.46, 1.05, 0.5], under: [1.5, 1.1, 0.6], rim: [1.9, 1, 0.7] }
      : { body: [1.3, 1.07, 0.5], lit: [1.3, 1.04, 0.7], under: [1.3, 1.1, 0.7], rim: [1.3, 1.02, 0.8] };
    const quiet = (lab, [up, down, own]) => heldTo(lab, skyHere, up, down, own);
    bodyLab = quiet(bodyLab, Q.body); litLab = quiet(litLab, Q.lit); deepLab = quiet(deepLab, Q.body);
    // By night it is barely there: every paint goes to the sky's own, a breath apart (the moon's side
    // a breath lighter) — a shape that is felt where it softly hides the stars behind it.
    const nk = pal.starsOut;
    const nightBody = [skyHere[0] + (air.dark ? 0.010 : 0.012), skyHere[1] * 0.9, skyHere[2] * 0.9];
    const toNight = (lab, dL = 0) => (nk > 0 ? mix3(lab, [nightBody[0] + dL, nightBody[1], nightBody[2]], nk) : lab);
    // (the pale page's cloud keeps more of itself than the hush leaves the sky, as the tree does)
    const C = air.dark ? pal.C : (lab) => css(pal.shown(lab, { presence: Math.max(air.presence, 0.6) }));
    const ctx = cloud.canvas.getContext('2d');
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.globalCompositeOperation = 'source-over';
    ctx.globalAlpha = 1;
    ctx.clearRect(0, 0, w, h);
    ctx.drawImage(tinted(body, C(toNight(bodyLab))), 0, 0, w, h, 0, 0, w, h);
    // its low part: by day a breath deeper than the body; in the afterglow, the warmest of it
    if (nk < 0.97) {
      ctx.globalAlpha = (0.6 * day + 0.5 * (1 - day) * (1 - after)) * (1 - nk);
      ctx.drawImage(tinted(under, C(deepLab)), 0, 0, w, h, 0, 0, w, h);
    }
    if (after > 0.03) {
      ctx.globalAlpha = clamp01(0.85 * after * (1 - 0.35 * far));
      ctx.drawImage(tinted(under, C(quiet(underLab, Q.under))), 0, 0, w, h, 0, 0, w, h);
    }
    // the light on its top: the whole top under a high sun; under a low one (below about 12°), or the
    // moon, only where the bank is turned to it — the far side goes without, to the body's own tone
    const oneSide = pal.byMoon ? 0.85 : 1 - smoothstep(6, 12, pal.altDeg);
    const litA = clamp01(Math.max(day, 0.2 + 0.8 * litAmt)) * (1 - 0.6 * nk);
    const litCss = C(toNight(litLab, 0.008 + 0.012 * pal.moonlight));
    if (oneSide < 0.99) {
      ctx.globalAlpha = litA * (1 - oneSide);
      ctx.drawImage(tinted(lit, litCss), 0, 0, w, h, 0, 0, w, h);
    }
    if (oneSide > 0.01) {
      ctx.globalAlpha = litA * oneSide;
      ctx.drawImage(tinted(litSide, litCss), 0, 0, w, h, 0, 0, w, h);
    }
    // the rim: one dry line where the contour faces a low sun, or the moon — nothing of it by day
    const rimAmt = (pal.byMoon ? 0.6 * pal.moonlight : litAmt * smoothstep(12, 5, pal.altDeg) * smoothstep(-7, -1, pal.altDeg)) * (1 - 0.4 * far) * (1 - nk * (1 - 0.5 * pal.moonlight));
    if (rimAmt > 0.03) {
      ctx.globalAlpha = clamp01(0.9 * rimAmt);
      ctx.drawImage(tinted(rim, C(toNight(quiet([litLab[0] + (air.dark ? 0.08 : 0.02), litLab[1], litLab[2]], Q.rim), 0.02 * pal.moonlight))), 0, 0, w, h, 0, 0, w, h);
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
      clear = Math.min(clear, smoothstep(2, 11, Math.hypot(dx, dy)));
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

  /** Dark, at night, the land's whole range is a couple of dozen levels of the display — and washes
   *  laid one over another in so few levels round to steps: a level line down every slope, an edge
   *  along every broad stroke and every gradient's stop (the faint straight edges in the night land;
   *  they were never the bounds of a canvas). So there a plane is PAINTED BRIGHT — every colour
   *  `NIGHT_K` times its value, where a wash has levels to spare — and brought down to its true value
   *  once, at the end, through a fine noise: a dither. The steps go into the paper's grain. */
  const NIGHT_K = 4;
  const plainCss = css;
  /** The colour-maker for a plane painted `k` times too bright. */
  function brightCss(k) {
    // (a little under: the dither adds a step and a half back on average, and the bringing-down rounds up)
    const v = (x) => Math.min(255, Math.max(0, Math.round(x * 255 * k - (k - 0.5))));
    return (lab, alpha = 1) => { const c = toRgb(lab); return `rgba(${v(c[0])},${v(c[1])},${v(c[2])},${alpha})`; };
  }
  let ditherTile = null, ditherThrows = null;
  /** The world's own noise: a throw, 0 … 1, for every device pixel of a 256 × 256 tile. */
  function ditherNoise() {
    if (!ditherThrows) {
      ditherThrows = new Float32Array(65536);
      for (let i = 0; i < 65536; i += 1) ditherThrows[i] = hash2(i & 255, i >> 8, 77);
    }
    return ditherThrows;
  }
  /** The dither: white at an alpha of a few levels, a fresh throw at every device pixel (laid over
   *  paint of about a quarter of full value it adds 0 … k − 1 levels, evenly). */
  function ditherPattern(k) {
    if (!ditherTile || ditherTile.k !== k) {
      const N = 256, throws = ditherNoise();
      const tile = imageCanvas(N, N, (d) => {
        for (let i = 0; i < N * N; i += 1) {
          const a = Math.min(k - 1, Math.floor(throws[i] * k));
          d[i * 4] = 255; d[i * 4 + 1] = 255; d[i * 4 + 2] = 255; d[i * 4 + 3] = Math.round(a * 1.36);
        }
      });
      ditherTile = { k, pattern: main.createPattern(tile, 'repeat') };
    }
    return ditherTile.pattern;
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
    // (dark, at night: painted bright and dithered down — see NIGHT_K)
    const K = air.dark && pal.deepNight >= 1 ? NIGHT_K : 1;
    const css = K === 1 ? plainCss : brightCss(K);
    for (const sh of plane.shapes) {
      if (sh.mist) { drawMistBand(ctx, sh.mist, pal, plane.y0, 0, 1, null, K); continue; }
      const { body, crestLine, under, raised, px, py } = shapePaths(sh, plane.y0);
      const a = scratch('a', w, h);
      const hz = sh.haze;
      // THE SLAB'S HILL STANDS IN SHADE WHERE HIS NAME AND AGE STAND ON IT, in snow, in the low key. The
      // whole age line sits on this hill by design, and pale snow behind grey words is past the limit:
      // the limiter under the line then cut a dark lozenge into a pale hill, with an end you could see.
      // So the hill itself is the dark thing there — its flank away from the sunset, as deep as the
      // words need — and comes back to its snow over 60 pt, past the last glyph. (0 … 1 at world x.)
      const wordsShade = (x) => (air.dark && G.cfg.kind === 'slab' && plane.id === 'mid' ? smoothstep(0.03, 0.3, sea.snow) * (1 - smoothstep(196, 256, x)) : 0);
      // 1. The fill: its own colour gone `haze` of the way into the horizon sky behind it, at every x.
      const own = (x) => {
        const f = facing(sh, x, lampX);
        // the side turned to the light is a breath lighter and warmer, the far side cooler
        const side = (f - 0.5) * power * (1 - hz) * (air.dark ? 0.035 : 0.03);
        // (the light print: a near plane is a step deeper and warmer at its crest than the plane behind
        // it is at its foot — depth by overlap, without darkening the page under the cards)
        const near = air.dark || sh.hazeLight != null ? 0 : Math.pow(1 - hz, 1.2);
        // (…and by day, when no low light models the land, the planes themselves must read: each a
        // clear step deeper and warmer than the one behind it, the far ones lighter and bluer)
        const step = air.dark ? 0 : air.day * Math.pow(1 - hz, 3);
        // (the low key's snow is the palest thing on the land, and the strip has to say "winter" — the knoll
        // says it. The two nearest planes, and the hill behind the knoll, lie under the cards and the tab
        // capsule, where a pale ground turns the glass milky: there the snow is a step deeper)
        const snowDeep = air.dark ? sea.snow * (0.085 * smoothstep(0.2, 0.04, hz) + (plane.id === 'mid' ? 0.045 : 0)) * smoothstep(0.22, 0.4, pal.ground[0]) : 0;
        const g = [pal.ground[0] + side - 0.058 * near - 0.125 * step - snowDeep, pal.ground[1] + 0.007 * near + 0.007 * step, pal.ground[2] + 0.006 * near + 0.016 * step];
        const m = mix3(g, air.hazeAt(pal.dxSun(x)), air.dark ? hz : sh.hazeLight ?? hz * 0.78);
        // (the slab's hill under his name and age, in snow: see `wordsShade`)
        const ws = wordsShade(x);
        if (ws > 0) { const cap = WORDS_SHADE_L; if (m[0] > cap) m[0] = lerp(m[0], cap, ws); }
        if (air.dark || sh.hazeLight != null) return m;
        const farK = air.day * smoothstep(0.35, 0.9, hz);
        return [m[0] + 0.014 * farK, m[1] - 0.003 * farK, m[2] - 0.016 * farK];
      };
      // Dark, at night: the land is not one black band. Each plane keeps a value of its own — far
      // ones a shade under the horizon's light, near ones deeper — and its blue; all of it under a card's.
      const nightL = 0.106 + 0.098 * Math.pow(hz, 0.8);
      // (The pale page by day is hushed to a fifth of its colour, and three planes of land a few levels
      // apart are one grey mass. There they are told apart by TEMPERATURE, which costs the page nothing
      // in value: the far land cool, the knoll neutral, each nearer plane a little warmer — laid after
      // the hush, and let go as the sky opens up, when the land has colour of its own.)
      const temper = air.dark || sh.hazeLight != null ? 0 : air.day * (1 - air.presence) * lerp(-0.0075, 0.0085, smoothstep(0.50, 0.04, hz));
      const fillAt = (x) => {
        const q = pal.shown(own(x));
        if (temper) { q[1] += 0.3 * temper; q[2] += temper; }
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
        lo.fillStyle = hGrad(lo, (x) => css(pal.shown(mix3(pal.ground, air.hazeAt(pal.dxSun(x)), sh.hazeNear))));
        lo.fillRect(0, 0, w + 8, h + 8);
        lo.globalCompositeOperation = 'destination-in';
        const fall = lo.createLinearGradient(0, py(sh.top), 0, py(sh.top + 190));
        fall.addColorStop(0, 'rgba(0,0,0,0)'); fall.addColorStop(0.3, 'rgba(0,0,0,0.5)'); fall.addColorStop(1, 'rgba(0,0,0,1)');
        lo.fillStyle = fall;
        lo.fillRect(0, 0, w + 8, h + 8);
        lo.globalCompositeOperation = 'source-over';
      } else if (hz < 0.95) {
        // air gathers at its foot: toward the valley's own haze, level (on the pale page by day, all the
        // way to the low sky's own value: each plane lets go into air, and the next one begins against it)
        const footAir = (x) => (air.dark ? air.hazeAt(pal.dxSun(x)) : mix3(air.hazeAt(pal.dxSun(x)), air.skyAt(pal.dxSun(x), 0.03), 0.7 * air.day));
        lo.fillStyle = hGrad(lo, (x) => css(pal.shown(footAir(x))));
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
        lo.strokeStyle = hGrad(lo, (x) => css(pal.shown(mix3(lab, air.hazeAt(pal.dxSun(x)), hz * 0.8)), white * (sea.snow > 0.03 ? 0.9 * (air.dark ? 1 - 0.45 * smoothstep(0.2, 0.04, hz) : 1) : 0.5) * (1 - 0.92 * wordsShade(x))), 20);
        lo.stroke(crestLine);
      }
      lo.filter = 'none';
      a.globalCompositeOperation = 'source-atop';
      a.drawImage(lo.canvas, 0, 0, wq, hq, 0, 0, wq / Q, hq / Q);

      // 3. The river lies on the valley floor.
      if (sh.floor && G.river) { const tr = performance.now(); paintRiver(a, pal, plane.y0, w, h, K); timing.river = performance.now() - tr; }

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
          // (the pale page under a moon: the same dry line as at dawn — broad, broken, quiet — never one clean white hairline, the only crisp mark in the night's land)
          const moonPale = pal.byMoon && !air.dark;
          b2.lineWidth = (pal.byMoon ? (air.dark ? 1.3 : 2.3) : 1.5 + 1.7 * (1 - hz)) * s;
          b2.strokeStyle = hGrad(b2, (x) => css(pal.shown([rimLab[0] + 0.04, rimLab[1], rimLab[2]]), clamp01((0.14 + 0.86 * facing(sh, x, lampX)) * rimAmt * sh.rim * (air.dark ? 2.6 : moonPale ? 0.8 : 1.3) * Math.exp(-Math.abs(x - lampX) / (G.Wa * 0.5)))), 10);
          b2.translate(0, 0.3 * s);
          b2.stroke(crestLine);
          b2.setTransform(1, 0, 0, 1, 0, 0);
          b2.globalCompositeOperation = 'destination-out';
          X.dryPattern.setTransform(new DOMMatrix().translate(sh.index * 37 - G.xL * s, sh.index * 91 - y0));
          b2.fillStyle = X.dryPattern;
          b2.globalAlpha = moonPale ? 0.9 : 0.62;
          b2.fillRect(0, 0, w, y1 - y0);
          b2.globalAlpha = 1;
          a.drawImage(b2.canvas, 0, 0, w, y1 - y0, 0, y0, w, y1 - y0);
        }
      }
      a.globalCompositeOperation = 'source-over';
      const top = Math.max(0, Math.floor(py(sh.top) - 14 * s));
      ctx.drawImage(a.canvas, 0, top, w, h - top, 0, top, w, h - top);
    }
    // The paint's own unevenness, over the whole plane. (The tree is not in the plane: it is ink, a
    // layer of its own that stands on the knoll — drawLand, `treeShown`.)
    ctx.globalCompositeOperation = 'source-atop';
    ctx.globalAlpha = K > 1 ? 0.085 : air.dark ? 0.04 : 0.036;
    X.mottlePattern.setTransform(new DOMMatrix().translate(-G.xL * s, -plane.y0 * s).scale(s / 2 * 1.5));
    ctx.fillStyle = X.mottlePattern;
    ctx.fillRect(0, 0, w, h);
    ctx.globalAlpha = 1;
    if (K > 1) {
      // …the dither (thrown on the world's own grid: the cover and the spread get the same throw),
      // and down to its true value — the one rounding the whole plane ever gets
      const noise = ditherPattern(K);
      noise.setTransform(new DOMMatrix().translate(-G.xL * s, -plane.y0 * s));
      ctx.fillStyle = noise;
      ctx.fillRect(0, 0, w, h);
      // (black laid atop at 1 − 1/K: the paint keeps a K-th of its value, and every edge its softness)
      ctx.fillStyle = `rgba(0,0,0,${1 - 1 / K})`;
      ctx.fillRect(0, 0, w, h);
    }
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
      // (a river is not a road: each bank wanders on its own, so the water widens and narrows —
      // but it leans to one bank or the other, it is never squeezed from both at once: no waist)
      const wander = (side) => 1 + 0.5 * (fb(i / 34 + side * 9.3 + 2.1, 3.3 + side, 2) - 0.5) * 2 * smoothstep(20, 90, i);
      const lift = Math.max(0, 0.94 - (wander(1) + wander(-1)) / 2);
      const edge = (side) => {
        const waver = wander(side) + lift;
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
  function paintRiver(a, pal, y0, w, h, K = 1) {
    const s = G.s, air = pal.air, c = G.cfg;
    const css = K === 1 ? plainCss : brightCss(K);       // (dark, at night, its plane is painted bright: see NIGHT_K)
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
    // into the river: a slender crescent that follows the bank's own curve and tapers to nothing at
    // both ends — a swelling of the shore, not a bite out of the water (the land itself shows there:
    // nothing is painted)
    let barEdge = null;
    {
      let at = Math.round(0.705 * (r.pts.length - 1));
      for (let i = Math.round(0.6 * (r.pts.length - 1)); i < Math.round(0.8 * (r.pts.length - 1)); i += 1) if (r.pts[i][0] < r.pts[at][0]) at = i;
      const span = 30, j0 = Math.max(1, at - span), j1 = Math.min(r.pts.length - 2, at + span);
      const shore = [], lip = [];
      for (let j = j0; j <= j1; j += 1) {
        const e = r.right[j], m = r.pts[j];
        const u = (j - j0) / (j1 - j0);
        let ix = m[0] - e[0], iy = m[1] - e[1];
        const half = Math.hypot(ix, iy) || 1;
        ix /= half; iy /= half;
        // (fuller toward its upstream end, a long thin tail downstream — and uneven, as sand is laid)
        const out = half * 0.36 * Math.pow(Math.sin(Math.PI * Math.pow(u, 0.8)), 1.3) * (0.85 + 0.3 * vn(j / 7 + 3.3, 9.1));
        shore.push([e[0] - ix * 3, e[1] - iy * 3]);
        lip.push([e[0] + ix * out, e[1] + iy * out]);
      }
      const bar = new Path2D();
      shore.forEach((q, k) => (k === 0 ? bar.moveTo(px(q[0]), py(q[1])) : bar.lineTo(px(q[0]), py(q[1]))));
      for (let k = lip.length - 1; k >= 0; k -= 1) bar.lineTo(px(lip[k][0]), py(lip[k][1]));
      bar.closePath();
      // (its lip is soft — two thin passes of the same erasing, each a little further out; a blur
      // here would be a filter over the whole plane)
      W.save();
      W.fillStyle = '#000';
      W.fill(bar);
      W.lineJoin = 'round';
      W.strokeStyle = 'rgba(0,0,0,0.45)';
      W.lineWidth = 1.3 * s;
      W.stroke(bar);
      W.lineWidth = 2.6 * s;
      W.stroke(bar);
      W.restore();
      barEdge = lip;
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

    // 3. The far bank lies in the water where a reach runs ACROSS the view — a soft, darker reflection
    //    close under its far edge, in a few long runs of unequal length with open water between them:
    //    each run one ribbon that follows the bank and thins to nothing at both ends (a run of like
    //    dashes down the middle of the water is a road's marking). Never along a reach that runs toward
    //    you (a dark edge down one side and a light one down the other is a moulded channel, not water).
    {
      const bank = (x) => pal.shown(mix3([pal.ground[0] - (air.dark ? 0.0 : 0.03), pal.ground[1], pal.ground[2]], air.hazeAt(pal.dxSun(x)), 0.4));
      const al = (air.dark ? 0.42 : 0.24) * (1 - 0.6 * dusk) * (1 - 0.7 * lightNight);
      const last = r.pts.length - 7;
      const lies = (i) => {
        const p = r.pts[i], q2 = r.pts[i + 5];
        const tx = q2[0] - p[0], ty = q2[1] - p[1];
        return Math.abs(tx) / (Math.hypot(tx, ty) || 1) >= 0.86 && r.half[i][1] >= 0.9 && fb(i / 58 + 4.4, 1.7, 2) > 0.5;
      };
      const ribbon = (i0, i1) => {
        if (i1 - i0 < 8 || !(al > 0.012)) return;
        W.fillStyle = css(bank(r.pts[(i0 + i1) >> 1][0]), al / 2);
        // (two of them, one inside the other: its edge is soft)
        for (const [far, near] of [[0.98, 0.36], [0.86, 0.52]]) {
          const top = [], foot = [];
          for (let i = i0; i <= i1; i += 1) {
            const p = r.pts[i], bankFar = r.left[i][1] < r.right[i][1] ? r.left[i] : r.right[i];   // (the far bank: the higher of the two on the page)
            const taper = Math.min(1, Math.min(i - i0, i1 - i) / 9);
            const mid = (far + near) / 2, half = ((far - near) / 2) * taper;
            top.push([lerp(p[0], bankFar[0], mid + half), lerp(p[1], bankFar[1], mid + half)]);
            foot.push([lerp(p[0], bankFar[0], mid - half), lerp(p[1], bankFar[1], mid - half)]);
          }
          W.beginPath();
          top.forEach((q, k) => (k === 0 ? W.moveTo(px(q[0]), py(q[1])) : W.lineTo(px(q[0]), py(q[1]))));
          for (let k = foot.length - 1; k >= 0; k -= 1) W.lineTo(px(foot[k][0]), py(foot[k][1]));
          W.closePath();
          W.fill();
        }
      };
      let from = -1;
      for (let i = 6; i <= last; i += 1) {
        const on = i < last && lies(i);
        if (on && from < 0) from = i;
        if (!on && from >= 0) { ribbon(from, i - 1); from = -1; }
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
      // (a breath of it: the sun that lights it is on the other page, and at full strength it was a lamp's reflection)
      const al = (air.dark ? 0.4 : 0.6) * (1 - 0.5 * lightNight);
      W.save();
      W.translate(px(p[0] - toward * hw * 0.12), py(p[1] + 26));
      W.scale(hw * 0.86 * s, 82 * s);
      const g = W.createRadialGradient(0, -0.3, 0, 0, 0, 1);
      g.addColorStop(0, css(col, al)); g.addColorStop(0.35, css(col, al * 0.62)); g.addColorStop(0.7, css(col, al * 0.2)); g.addColorStop(1, css(col, 0));
      W.fillStyle = g;
      W.fillRect(-1, -1, 2, 2);
      W.restore();
    }
    // Level streaks across the NEAR reach, bank to bank, a tone apart: the sheen is broken by the wind
    // in lanes. (Level strokes on a receding plane are what say "water".)
    for (let k = 0; k < 7; k += 1) {
      const t = 0.70 + 0.28 * ((k + 0.25 + 0.5 * hash(k, 541)) / 7);
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
    // The MIDDLE reach, where the river comes round its bends toward you: no streak lies on its centre
    // line (a run of like dashes down the middle of it is a road's marking). Four strokes of sheen, of
    // unequal length and unevenly spaced, each lying along the OUTER bank of a bend — where the
    // current runs — and following that bank's own turn. [how far down the river, its length in points]
    for (const [t, length] of [[0.385, 5], [0.45, 13], [0.555, 8], [0.655, 18]]) {
      const i = clamp(Math.round(t * (r.pts.length - 1)), 9, r.pts.length - 10);
      const p = r.pts[i], a0 = r.pts[i - 8], a1 = r.pts[i + 8];
      const hx = r.half[i][0], hy = r.half[i][1];
      if (Math.hypot(hx, hy) < 1.6) continue;
      // the outer bank: the one further from the chord the bend is strung on
      const mx = (a0[0] + a1[0]) / 2, my = (a0[1] + a1[1]) / 2;
      const outer = Math.hypot(r.left[i][0] - mx, r.left[i][1] - my) > Math.hypot(r.right[i][0] - mx, r.right[i][1] - my) ? r.left[i] : r.right[i];
      const x = lerp(p[0], outer[0], 0.56), y = lerp(p[1], outer[1], 0.56);
      const here = waterAt(x, y);
      const lab = shownW([here[0] + (air.dark ? 0.085 : 0.03), here[1] * 0.75, here[2] * 0.75]);
      if (pal.deepNight > 0) lab[0] = lerp(lab[0], NIGHT_WATER + 0.01, pal.deepNight);
      const alpha = 0.66 * (1 - 0.5 * lightNight);
      if (!(alpha > 0.012)) continue;
      W.save();
      W.translate(px(x), py(y));
      W.rotate(Math.atan2(a1[1] - a0[1], a1[0] - a0[0]));
      W.scale((length / 2) * s, Math.max(0.45, Math.min(1.1, Math.hypot(hx, hy) * 0.16)) * s);
      const g = W.createRadialGradient(0, 0, 0, 0, 0, 1);
      g.addColorStop(0, css(lab, alpha)); g.addColorStop(0.5, css(lab, alpha * 0.7)); g.addColorStop(1, css(lab, 0));
      W.fillStyle = g;
      W.fillRect(-1, -1, 2, 2);
      W.restore();
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
    // The water's edge along the bar: a breath of wet sand, paler than the water, broken.
    if (barEdge) {
      const mid = barEdge[Math.floor(barEdge.length / 2)];
      const here = waterAt(mid[0], mid[1]);
      const lab = shownW([here[0] + (air.dark ? 0.045 : 0.02), here[1] * 0.6, here[2] * 0.6]);
      if (pal.deepNight > 0) lab[0] = lerp(lab[0], NIGHT_WATER + 0.008, pal.deepNight);
      for (let k = 3; k < barEdge.length - 4; k += 4) {
        if (vn(k / 5 + 1.7, 3.3) < 0.36) continue;
        const q = barEdge[k], q2 = barEdge[k + 3];
        lens(W, (q[0] + q2[0]) / 2, (q[1] + q2[1]) / 2, 2.6, 1.1, lab, (air.dark ? 0.34 : 0.4) * (1 - 0.5 * lightNight));
      }
    }
    // The moon's broken path: while the moon lights the night, a column of short level glints of its
    // silver stands in the near reach, on the side the moon is — close and bright far off, under the
    // moon, scattering wider and thinner toward you; no two alike, no rung evenly placed. Thin lines
    // of light, not an area (in the dark appearance each is a hair over a card's value and half a point deep).
    if (pal.byMoon && pal.moonlight > 0.05) {
      const silver = air.show([air.dark ? lerp(0.40, 0.34, pal.B.depth) : 0.99, air.silver[1] * 0.7, air.silver[2] * 0.7]);
      const i0p = Math.round(0.5 * (r.pts.length - 1)), i1p = r.pts.length - 1;
      for (let k = 0; k < 46; k += 1) {
        // (more of them far away, where the path is tight; they thin out as it comes near)
        const f = Math.pow(hash(k, 571), 1.45);
        const i = Math.min(i1p, Math.round(lerp(i0p, i1p, f)));
        const p = r.pts[i], hw = r.half[i][0];
        if (hw < 2.2) continue;
        const d = p[1] - c.H0;
        const g1 = hash(k, 572) + hash(k, 576) - 1;         // (two throws: gathered to the middle of the column)
        const x = p[0] + toward * hw * 0.14 + g1 * Math.min(hw * 0.62, 3 + 17 * f);
        const y = p[1] + (hash(k, 575) - 0.5) * 4;
        const bright = 0.4 + 0.6 * Math.pow(hash(k, 574), 1.4) * (1 - 0.5 * Math.abs(g1));
        const len = Math.min(hw * 0.5, (1.3 + 4.4 * Math.pow(hash(k, 573), 1.7)) * (0.65 + 0.85 * f));
        lens(W, x, y, len, clamp(d * 0.0024, 0.42, 0.9), silver, clamp01((air.dark ? 0.78 : 0.95) * pal.moonlight * bright));
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

    // 5. Reeds at the water's edge, in two places on the near reach where they read (both in the
    //    leading margin column, clear of the cards): blades that taper from a foot to a point, 6 to 16
    //    points tall, the tallest in the middle of the clump — and ALL LEANING ONE WAY, a few degrees
    //    downstream, as reeds in a current do (blades fanned out to both sides are a row of pins). Two
    //    or three of a clump carry a seed head: a slender spindle, never a round knob. Under each, its
    //    reflection, broken. They are of the land's own dark, a step under it — never the tree's ink:
    //    the tree stays the darkest thing in the picture. On the pale page they go most of the way to
    //    the water's tone, and at night they go with the river.
    {
      const landDark = [pal.ground[0] - 0.03, pal.ground[1] * 1.2, pal.ground[2] * 1.2];
      const mid = r.pts[Math.round(0.8 * (r.pts.length - 1))];
      const inkL = air.dark ? pal.shown(landDark) : shownW(mix3(mix3([pal.ground[0] - 0.14, pal.ground[1] * 1.2, pal.ground[2] * 1.2], pal.ink, 0.45), waterAt(mid[0], mid[1]), 0.35));
      const inkA = air.dark ? 0.94 : 0.4 * (1 - 0.8 * lightNight);
      // [how far down the river, which bank (1 right, −1 left), how many blades, size]
      for (const [t, side, count, size] of [[0.735, 1, 8, 0.95], [0.872, 1, 10, 1.15]]) {
        const i = Math.round(t * (r.pts.length - 1));
        const e0 = side > 0 ? r.right[i] : r.left[i];
        const tall = clamp((e0[1] - c.H0) * 0.055 * size, 8, 15.5);   // the clump's tallest blade, points (it is larger the nearer it stands)
        const flow = Math.sign(r.pts[Math.min(r.pts.length - 1, i + 10)][0] - r.pts[Math.max(0, i - 10)][0]) || 1;   // downstream, on the picture
        const reach = Math.max(4, Math.round(tall * 0.5));      // how far along the bank it spreads, in samples
        for (let k = 0; k < count; k += 1) {
          const u = (k + 0.5) / count - 0.5;                   // across the clump: −0.5 … 0.5
          const j = clamp(i + Math.round(u * 2 * reach + (hash(k + i, 591) - 0.5) * 3), 1, r.pts.length - 2);
          const e = side > 0 ? r.right[j] : r.left[j], m = r.pts[j];
          // (its foot stands in the shallows, a point or two out from the bank)
          const inX = Math.sign(m[0] - e[0]) * (1.2 + 1.6 * hash(k + i, 596));
          const x = e[0] + inX + (hash(k + i, 593) - 0.5) * 1.6, y = e[1] + (hash(k + i, 594) - 0.5) * 2.4;
          const hgt = Math.max(6, tall * (0.5 + 0.5 * (1 - 4 * u * u)) * (0.78 + 0.3 * hash(k + i, 592)));
          const lean = flow * hgt * Math.tan((5 + 7 * hash(k + i, 595)) * DEG);     // 5–12° downstream
          const wd = Math.max(0.42, tall * 0.03);              // half its width at the foot
          a.fillStyle = css(inkL, inkA);
          a.beginPath();
          a.moveTo(px(x - wd), py(y + 0.6));
          a.quadraticCurveTo(px(x + lean * 0.3 - wd * 0.7), py(y - hgt * 0.6), px(x + lean), py(y - hgt));
          a.quadraticCurveTo(px(x + lean * 0.4 + wd * 0.8), py(y - hgt * 0.52), px(x + wd), py(y + 0.6));
          a.closePath();
          a.fill();
          if (k % 4 === 1) {
            // a seed head: a slender dark spindle a little under the tip, lying along its blade
            const f = 0.8, hx = x + lean * f, hy = y - hgt * f;
            a.beginPath();
            a.ellipse(px(hx), py(hy), wd * 1.15 * s, Math.max(1.3, hgt * 0.13) * s, Math.atan2(lean, hgt), 0, TAU);
            a.fill();
          }
          // its reflection: shorter, fainter, broken once by the water's movement
          a.fillStyle = css(inkL, inkA * 0.26);
          for (const [fy, fl] of [[0.15, 0.12], [0.4, 0.08]]) {
            a.beginPath();
            a.ellipse(px(x - lean * 0.5 * fy), py(y + 1.2 + hgt * fy), wd * 1.1 * s, hgt * fl * s, 0, 0, TAU);
            a.fill();
          }
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
  function mistCanvas(band, pal, mask, K = 1) {
    const s = G.s, air = pal.air;
    const css = K === 1 ? plainCss : brightCss(K);       // (a band painted INTO a plane that is painted bright: see NIGHT_K)
    if (band.pools && !mask) return null;
    const x0 = mask ? mask.x0 : Math.max(band.x0, G.xL), x1 = mask ? mask.x0 + mask.w : Math.min(band.x1, G.xR);
    if (x1 - x0 < 8) return null;
    const w = Math.ceil((x1 - x0) * s), h = Math.ceil((mask ? mask.h : band.h) * s);
    const c = mk(w, h);
    const ctx = c.getContext('2d');
    const stops = [];                                    // [how far along, its colour there] — kept for `settle`
    /** Dark, at night, a layer of mist laid BETWEEN the planes: in so few levels a thin wash of dark
     *  paint cannot carry its own colour (the canvas keeps colour × alpha in whole levels), so the
     *  faint skirt of the mist only darkened what lay behind it — a dark line round every pool, and
     *  the straight top and end of a band's own canvas. There the paint is laid once more through a
     *  dither: at each pixel, colour × alpha rounded up or down by a throw of the world's own noise. */
    const settle = (out) => {
      if (K !== 1 || !(air.dark && pal.deepNight >= 1)) return out;
      if (!mask) {
        // (a band's texture does not quite reach nothing at its top edge: there it is let go)
        ctx.globalCompositeOperation = 'destination-out';
        const g = ctx.createLinearGradient(0, 0, 0, 3 * s);
        g.addColorStop(0, 'rgba(0,0,0,1)'); g.addColorStop(1, 'rgba(0,0,0,0)');
        ctx.fillStyle = g;
        ctx.fillRect(0, 0, w, 3 * s);
        ctx.globalCompositeOperation = 'source-over';
      }
      const img = ctx.getImageData(0, 0, w, h), d = img.data;
      const col = new Float32Array(w * 3);
      for (let px = 0, k = 0; px < w; px += 1) {
        const f = (px + 0.5) / w;
        while (k < stops.length - 2 && f > stops[k + 1][0]) k += 1;
        const a0 = stops[k], a1 = stops[k + 1];
        const t = clamp01((f - a0[0]) / Math.max(1e-6, a1[0] - a0[0]));
        for (let ch = 0; ch < 3; ch += 1) col[px * 3 + ch] = 255 * lerp(a0[1][ch], a1[1][ch], t);
      }
      const throws = ditherNoise();
      const gx0 = Math.round(x0 * s) + 97, gy0 = Math.round(out.y * s) + 41;
      for (let py = 0; py < h; py += 1) {
        const row = ((gy0 + py) & 255) << 8;
        for (let px = 0, i = py * w * 4; px < w; px += 1, i += 4) {
          const a = d[i + 3];
          if (a === 0) continue;
          const u = throws[row | ((gx0 + px) & 255)], k = a / 255, back = 255 / a;
          for (let ch = 0; ch < 3; ch += 1) {
            const lv = Math.floor(col[px * 3 + ch] * k + u);
            d[i + ch] = lv <= 0 ? 0 : Math.min(255, Math.round(lv * back));
          }
        }
      }
      ctx.putImageData(img, 0, 0);
      return out;
    };
    ctx.fillStyle = (() => {
      const grad = ctx.createLinearGradient(0, 0, w, 0);
      const tint = (x) => {
        let raw = air.mistAt(pal.dxLamp(x), pal.dxSun(x));
        // under the low sun the mist in a hollow is the most luminous thing in the land: it takes the glow
        const nearSun = pal.byMoon ? 0 : Math.exp(-Math.abs(pal.dxSun(x)) / 0.32) * air.lastLight * (1 - smoothstep(5, 12, pal.altDeg));
        if (nearSun > 0.01) raw = mix3(raw, [Math.max(raw[0], air.glow[0]) + 0.03, air.glow[1], air.glow[2]], 0.5 * nearSun);
        // (the pale page by day: mist is air — it has the low sky's own value, a breath over it, never a grey of its own)
        if (!air.dark && air.day > 0) { const low = air.skyAt(pal.dxSun(x), 0.03); raw = mix3(raw, [Math.max(raw[0], low[0] + 0.004), raw[1], raw[2]], 0.8 * air.day); }
        const q = pal.shown(raw);
        // dark, at night: a breath of mist — held at one quiet value (under a card's), whatever the room's depth
        if (pal.deepNight > 0) q[0] = lerp(q[0], NIGHT_MIST, pal.deepNight);
        // the pale page at night: paler than the land and nearly its colour — never blue puddles
        if (!air.dark) { const k = 1 - 0.62 * pal.nightness; q[1] *= k; q[2] *= k; }
        stops.push([(x - x0) / (x1 - x0), toRgb(q)]);
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
      ctx.globalCompositeOperation = 'source-over';
      return settle({ canvas: c, x0, w, h, y: mask.y0 });
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
    ctx.globalCompositeOperation = 'source-over';
    return settle({ canvas: c, x0, w, h, y: band.y });
  }

  function drawMistBand(ctx, band, pal, y0, offX, alphaK, cached, K = 1) {
    const m = cached ?? mistCanvas(band, pal, undefined, K);
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
    // (in blossom the first leaves are few and small: the handful that would stand in front of a disc of light are specks on it — most of them go)
    const inFlower = clamp01(pal.sea.blossom ?? 0);
    if (leaf) foliage(lerp(0.88, 0.2, inFlower), (add) => add(leaf.back, C(pal.leafShade)), [leaf.gaps]);
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
      foliage(lerp(0.9, 0.2, inFlower), (add, g) => {
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
        // After sunset, in the low key, a turning crown keeps a few leaves alight on the side the sun
        // went down — gold, at its full chroma, until the twilight has gone: autumn does not rest on a
        // silhouette. (Only the leaves turned that way, and only on that side of the crown.)
        const ember = pal.dark && !pal.byMoon ? smoothstep(-11.5, -6.5, pal.altDeg) * (1 - smoothstep(-2.5, 0.5, pal.altDeg)) * smoothstep(0.55, 0.8, pal.sea.leafHue) : 0;
        if (ember > 0.03) {
          const gold = css(pal.shown(lch(0.52, 0.13, 74), { presence: 1 }));
          for (let i = 0; i < 8; i += 1) {
            if (Math.cos((i * TAU) / 8) * lampX + Math.sin((i * TAU) / 8) * lampY < 0.5) continue;
            g.drawImage(washed(leaf.turned[i], gold, across(0.85 * ember)), 0, 0, m.w, m.h, 0, 0, m.w, m.h);
          }
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
    // Frost is a hair along the wood's upper edge — but each stretch of it begins at its limb's fork,
    // inside the wood of the limb it leaves: on the pale page, a pale chevron under every crotch. There
    // the frost that lies well inside the wood (a point from any edge) is taken off, once for these
    // masks. (The low key's, where it is faint, is laid as it always was.)
    if (m.frost && !pal.dark && !m.frostEdge) {
      const inner = mk(m.w, m.h), x = inner.getContext('2d');
      x.filter = `blur(${(0.7 * s).toFixed(2)}px)`;
      x.drawImage(m.wood, 0, 0);
      x.filter = 'none';
      const img = x.getImageData(0, 0, m.w, m.h);
      for (let k = 3; k < img.data.length; k += 4) img.data[k] = img.data[k] > 236 ? 255 : 0;
      x.putImageData(img, 0, 0);
      const c = mk(m.w, m.h), y = c.getContext('2d');
      y.drawImage(m.frost, 0, 0);
      y.globalCompositeOperation = 'destination-out';
      y.drawImage(inner, 0, 0);
      m.frostEdge = c;
    }
    lay(pal.dark ? m.frost : m.frostEdge, C(pal.frost), pal.dark ? 0.28 : 0.34);
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
    // (`month`: tonight's cream at half its warmth — the month-nights' own. On the pale page tonight's
    // star is ivory, not white — `ivory`, about (255, 244, 214) — the first night's a little less warm,
    // the month-nights' half as warm: the same order of warmth as in the dark print.)
    const tints = { cool: lch(0.94, 0.04, 255), plain: lch(0.985, 0.008, 95), warm: lch(0.955, 0.055, 82), rose: lch(0.93, 0.05, 20), tonight: lch(0.965, 0.07, 84), ink: lch(0.40, 0.05, 285), white: lch(1, 0, 0),
      month: lch(0.965, 0.035, 84), ivory: lch(0.968, 0.041, 90), ivoryFirst: lch(0.972, 0.033, 90), ivoryMonth: lch(0.978, 0.0205, 90) };
    out.lum = Object.fromEntries(Object.entries(tints).map(([name, lab]) => [name, lab[0] ** 3]));   // (a tint's luminance, near enough: L³)
    // (a month-night's mark has a core of its own: 1.6 pt in radius at the size it is drawn, 0.70 of the sprite)
    const cores = { month: 1.6 / 0.70, ivoryMonth: 1.6 / 0.70 };
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
      ctx.arc(0, 0, (cores[name] ?? 1.9) * s, 0, TAU);
      ctx.fill();
      out[`glint-${name}`] = c;
    }
    // tonight's star: hair-thin flares and a small clean core — a point of light, never a disc
    for (const [name, lab] of [['tonight', tints.tonight], ['ivory', tints.ivory]]) {
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
    // The light page's star is a clean white point on a little deeper sky. That dusk is soft and wide —
    // three of the point's radii and more — and never as strong as the point is white, so the white is
    // what reads (a patch as strong as its core is a bruise with a speck in it); it has no edge of its
    // own (never a ring round a dot). Round a faint star it is not drawn at all (drawStars): only the
    // point is left. Under a month night's four-point mark, and tonight's star, it is the same thing
    // larger: dusk gathered at the heart, reaching out under the rays.
    out.deep = (() => {
      const c = mk(size, size);
      const ctx = c.getContext('2d');
      const lab = lch(0.54, 0.09, 283);
      const g = ctx.createRadialGradient(size / 2, size / 2, 0, size / 2, size / 2, size / 2);
      for (const [t, a] of [[0, 0.5], [0.12, 0.5], [0.2, 0.4], [0.3, 0.27], [0.42, 0.16], [0.56, 0.08], [0.72, 0.03], [0.9, 0]]) g.addColorStop(t, css(lab, a));
      ctx.fillStyle = g;
      ctx.fillRect(0, 0, size, size);
      return c;
    })();
    // …and its bright nights are the same round mark as every other night, larger: a crisp white core
    // (a quarter of the sprite's half) and nothing else. Four points are kept for the first night, the
    // month-nights and tonight — one mark, one meaning, in both appearances.
    out.bright = (() => {
      const c = mk(size, size);
      const ctx = c.getContext('2d');
      const lab = lch(1, 0, 0);
      const g = ctx.createRadialGradient(size / 2, size / 2, 0, size / 2, size / 2, size / 2);
      g.addColorStop(0, css(lab, 1)); g.addColorStop(0.215, css(lab, 1)); g.addColorStop(0.265, css(lab, 0)); g.addColorStop(1, css(lab, 0));
      ctx.fillStyle = g;
      ctx.fillRect(0, 0, size, size);
      return c;
    })();
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
    // (the leading page's stars are thinned against its title and the line under it as the list is built,
    // and the title changes with the hour — "The day so far", "Miller's book": it is part of the key, or
    // a long-lived page keeps the stars of the title it was built under)
    const key = [state.ageDays, nightBegunOf(state), c.kind, G.Wa, L.name?.x, L.name?.width, L.age?.width, L.gear?.x,
      L.title?.x, L.title?.width, L.subtitle?.width, L.title?.y, L.subtitle?.y, L.subtitle?.height].map((v) => (typeof v === 'number' ? Math.round(v * 2) / 2 : v)).join('|');
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
    // A FOUR-POINT STAR IS NEVER AT A CARD'S EDGE. In the 12 pt gap between the Feed and Diaper tiles a
    // month-night's mark stood exactly where the app's own sparkle glyph would (cover, 191 × 358). So
    // the first night's and the month-nights' stars keep 10 pt from every edge of every card in the
    // standing layouts — the night's two (asleep; awake for a feed) and, for the Today card, the rest
    // pose: such a star is whole in the open, or well behind a card, never in a gap (a 12 pt gap has
    // no place 10 pt from both sides) and never half out from under an edge. These are taken places:
    // the night is cast again (below), and the count is what it was.
    // (UNDER GLASS a four-point star is not moved: it is drawn as a point — drawStars, underGlass. The
    // other way, a place of its own clear of the glass rows, is the lab switch glass=place, below.)
    const cardEdges = (c.cards ?? []).concat((c.cards ?? []).slice(0, 1).map(([x0, y0, x1, y1]) => [x0 - c.T, y0 + c.D, x1 - c.T, y1 + c.D]));
    const glassRows = (c.glass ?? []).map((i) => c.cards[i]);
    const atCardEdge = (x, y) => {
      // (nor is it cut by the display's own edge, in either pose: at 13 pt tall a mark 5 pt under the
      // top of the everyday view lost the tip of its upper ray)
      if (x < xMin + 2 || x > xMax - 2 || y < yMin + 2) return true;
      if (Math.abs(y - c.D) < 9 || (y > c.D - 9 && Math.abs(x + c.T - G.Wa) < 7)) return true;
      for (const [x0, y0, x1, y1] of cardEdges) {
        const inside = Math.min(x - x0, x1 - x, y - y0, y1 - y);
        const d = inside >= 0 ? inside : Math.hypot(Math.max(x0 - x, 0, x - x1), Math.max(y0 - y, 0, y - y1));
        if (d < 10) return true;
      }
      return false;
    };
    const inGlassRow = (x, y) => glassRows.some(([x0, y0, x1, y1]) => x > x0 && x < x1 && y > y0 && y < y1);
    const list = [];
    const placeGlass = urlGlass === 'place', moved = [];
    let firstAt = null;                                  // the first night's own place, once it has taken it
    const free = (x, y, big, pair = 80, skipMoved = false) => {
      if (x < xMin || x > xMax || y < yMin || y > floor(x)) return false;
      const wide = big ? 9 : 0;                           // (a four-point star keeps further from the words and the buttons: beside a line of text it is an asterisk)
      for (const r of outs) if (x > r.x0 - wide && x < r.x1 + wide && y > r.y0 - wide && y < r.y1 + wide) return false;
      if (big && atCardEdge(x, y)) return false;
      // tonight's star has dark sky of its own round it in the clear window (and no four-point star
      // near enough to be taken for it); beside the tree, at rest, a smaller clearing
      if (Math.hypot(x - tonightLook.x, y - tonightLook.y) < (big ? 70 : 30 * c.starScale)) return false;
      if (Math.hypot(x - tonightRest.x, y - tonightRest.y) < 17) return false;
      // …and so has the first night's, where it has a place of its own (the Duo's header gap): nothing
      // within 18 pt of it, and no other four-point star within 60 pt — in the gap beside his name it
      // is the one star of its kind, at two years as on the first day
      if (firstAt && Math.hypot(x - firstAt.x, y - firstAt.y) < (big ? 60 : 18)) return false;
      for (const o of list) {
        if (skipMoved && o.nx != null) continue;          // (glass=place: a star that has been given another place is judged where it now is)
        // (…and two four-point stars are not neighbours: 80 pt between them while the sky has the room
        // — `pair` — a month-night cast again beside another made a level pair of marks, 61 pt apart)
        const gap = big && o.kind !== 'night' && o.kind !== 'tonight' ? pair : (o.kind === 'night' ? apart : apart + 5) + (big ? 5 : 0);
        if (Math.abs(x - o.lx) < gap && Math.hypot(x - o.lx, y - o.ly) < gap) return false;
      }
      return true;
    };
    for (const star of nights(state.ageDays, { tonightLit: nightBegunOf(state) })) {
      if (star.kind === 'tonight') {
        list.push({ ...star, lx: tonightLook.x, ly: tonightLook.y });
        continue;
      }
      // the first night — the brightest star in his sky — has a place of its own where the night's
      // view shows it with the cards on (if that place is free on this display)
      const own = star.kind === 'first' && c.firstUp && free(c.firstUp.x, c.firstUp.y, false);
      const at = own ? { ...c.firstUp } : place(star);
      const big = star.kind !== 'night';
      let { x, y } = at;
      if (own) { list.push({ ...star, lx: x, ly: y }); firstAt = at; continue; }
      // One star per night has to be countable: a place that is taken, hidden or behind the
      // words gives way to the nearest free one — judged only against the nights before it.
      if (!free(x, y, big)) {
        let found = false;
        // first, cast again: the night's own second, third… place, anywhere in the sky (the nearest
        // free place would line the stars up along the edge of whatever they could not sit behind)
        // (a four-point star has more to keep clear of — the cards' edges, the others of its kind — so
        // it is cast more often; and when his sky is full of them, at two years, it settles for less
        // room between two of them before it settles for a card's edge)
        const fr = (v2) => v2 - Math.floor(v2);
        for (const pair of big ? [80, 60, 44] : [0]) {
          for (let k = 1; k <= (big ? 90 : 30) && !found; k += 1) {
            const again = place({ ...star, u: fr(star.u + k * 0.6180339887), v: fr(star.v + k * 0.7548776662) });
            if (free(again.x, again.y, big, pair)) { x = again.x; y = again.y; found = true; }
          }
        }
        for (let ring = 1; ring <= 40 && !found; ring += 1) {
          for (let k = 0; k < 12; k += 1) {
            const a = (k / 12 + hash(star.night, 31) + ring * 0.07) * TAU, r = ring * apart * 0.6;
            const nx = at.x + Math.cos(a) * r, ny = at.y + Math.sin(a) * r * 0.9;
            if (free(nx, ny, big, 20)) { x = nx; y = ny; found = true; break; }
          }
        }
      }
      const entry = { ...star, lx: x, ly: y };
      // THE LAB SWITCH glass=place — the other answer to a four-point star under glass, shot to compare
      // and not chosen (hill-painted.md, "His stars"): a four-point star whose place is inside a glass
      // row of the table is given another, clear of the glass, of every card's edge, of the nights
      // before it and of the others so moved. Every other star keeps its place (the nights after it are
      // still judged against the place it left). It gathers the four-point stars behind the Today card:
      // the bedtime poster's lower sky loses all of them, and the rest pose has none.
      if (placeGlass && big && inGlassRow(x, y)) {
        const fr = (v2) => v2 - Math.floor(v2);
        const clear = (nx, ny, pair) => !inGlassRow(nx, ny) && free(nx, ny, true, pair, true) && moved.every((m) => Math.hypot(nx - m.nx, ny - m.ny) >= pair);
        search: for (const pair of [80, 60, 44, 24]) {
          for (let k = 1; k <= 240; k += 1) {
            const again = place({ ...star, u: fr(star.u + k * 0.6180339887), v: fr(star.v + k * 0.7548776662) });
            if (clear(again.x, again.y, pair)) { entry.nx = again.x; entry.ny = again.y; moved.push(entry); break search; }
          }
        }
      }
      list.push(entry);
    }
    for (const m of moved) { m.lx = m.nx; m.ly = m.ny; }
    // world coordinates (rest pose): the looked-up place, turned back and lowered (tonight's: its place beside the tree)
    for (const st of list) { st.x = st.lx + c.T; st.y = st.ly - c.D; if (st.kind === 'tonight') { st.x = c.tonight.x; st.y = c.tonight.y; } }
    // The ordinary sky of the leading page (nobody's stars), on the whole tall sky: fainter than
    // his, as thick as his at the fold — so that, looking up, there is no boundary where the anchor
    // window begins — and thinning and dimming to the far left. It fills as his does (a newborn's
    // sky is not upstaged by the page beside it).
    const far = [];
    if (G.ox > 0) {
      const span = G.ox + c.T - 2;                         // from the fold (looking up) to the leading edge
      // (by his nights, tonight's among them whether its star is lit yet or not: the page beside his sky does not gain a star the instant he goes down)
      const count = clamp(Math.round(1.12 * Math.max(1, Math.floor(state.ageDays) + 1) * (span / G.Wa) * 0.84), 80, 460);
      const expShare = 0.36, fall = 190;
      // (20 pt of plain sky before the title's first letter: a star 15 pt left of "T" read as a mark on the title)
      const title = L.title ? { x0: L.title.x - G.ox - 20, x1: L.title.x - G.ox + Math.max(L.title.width, L.subtitle ? L.subtitle.width : 0) + 22, y0: L.title.y - 8, y1: (L.subtitle ? L.subtitle.y + L.subtitle.height : L.title.y + L.title.height) + 8 } : null;
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
   *  (points), its pace and its strength. It leaves as the view arrives (lab/presence.js, MOMENT.band:
   *  2.1 s on the Duo, 2.3 s on the slab — the star is then within a few points of its place in the
   *  clear window, and the band's own light is held back until it is well away from the star) and
   *  from THAT place, fixed on the display — so it never wobbles with the camera — and it crosses the
   *  anchor window to its farthest corner in 2.1 s (Duo, 276 pt/s) or 2.0 s (slab, 410 pt/s): it has
   *  crossed by 4.2 s (4.3 s), his last star has answered by 4.0 s and settled before the cards begin
   *  to come back (4.6 s). The pace is the anchor window's, so the spread's phone page is the cover's
   *  picture at every instant of it. `strength` is 0 once it has crossed; `radius` runs on (which
   *  stars it has passed is asked of it for as long as the event lasts). */
  function ringOf(state, tilt) {
    const e = state.event;
    if (!e || e.kind !== 'bedtime' || state.asleep !== 'night' || state.reduceMotion) return null;
    const c = G.cfg;
    const band = MOMENT.band[c.kind];
    const age = e.age - band.leaves;
    if (age <= 0) return null;
    const at = tonightHome(1, tilt);
    const foot = c.H0 + c.D + (c.kind === 'duo' ? 74 : 104);     // the display's foot, looking up (the cover's: the spread is 9 pt shorter)
    const far = Math.hypot(Math.max(c.tonightUp.x, G.Wa - c.tonightUp.x), Math.max(c.tonightUp.y, foot - c.tonightUp.y));
    const speed = far / band.crosses;
    const radius = speed * age;
    let strength = smoothstep(0, 0.4, age) * (1 - smoothstep(far * 1.04, far * 1.3, radius));
    if (strength <= 0.003) strength = 0;
    return { radius, strength, age, at, far, speed };
  }

  function drawStars(ctx, state, pal, time, off, ring) {
    const s = G.s, c = G.cfg;
    const out = pal.starsOut;
    const asleepNight = state.asleep === 'night';
    const bed = state.event && state.event.kind === 'bedtime' && asleepNight ? state.event.age : null;
    if (!(out > 0.004) && bed == null) return;
    const stars = starsFor(state);
    const scale = c.starScale;
    const still = time == null ? 1 : 1 - 0.6 * pal.B.depth;
    const lead = state.lead == null ? 1 : clamp01(state.lead);
    const light = !pal.dark;
    const moonAt = pal.moonNow;
    const mR = c.moonR + 5;
    // (a four-point star beside the moon is a point within 40 pt of its centre and has its four
    // points again 60 pt out — on the Duo; by the moon's size on the slab. moonstar=old: the lab switch.)
    const moonNear = 40, moonFar = 60;
    // A little brighter once he is down; the sky has gone deeper.
    const settle = 1 + 0.1 * pal.B.depth * (bed == null ? 1 : smoothstep(4, 8, bed));
    ctx.globalCompositeOperation = 'source-over';
    /** As the ring passes: [swell — a breath that rises fast and lets go; kept — what stays with a star that is out]. */
    const paceK = ring ? ring.speed / 250 : 1;           // (the swell's lengths were set for a band going 250 pt/s: the same breath in time at any pace)
    const sinceOf = (x, y) => (ring.radius - Math.hypot(x - ring.at.x, y - ring.at.y)) / paceK;
    const answer = (x, y) => {
      if (!ring || !(ring.strength > 0)) return 0;
      const since = sinceOf(x, y);
      if (since < -26) return 0;
      const pulse = since < 0 ? Math.exp(-((since / 10) ** 2)) : Math.exp(-((since / 95) ** 2));
      return pulse * Math.sqrt(ring.strength);
    };
    // (which stars the band has passed. Under Reduce Motion there is no band: the looked-up still is
    // the sky after it, the rest still the sky before it, and the two dissolve.)
    const passed = (x, y) => (ring ? smoothstep(-10, 30, sinceOf(x, y)) : bed != null && state.reduceMotion ? clamp01(pal.look) : 0);
    // In a sky still too light for stars (a July bedtime) the band shows them one by one — and they keep
    // a faint presence while the cards are away, so the held frame is a sky of stars, not a crescent of
    // them; they are let go as the cards come back over the sky. That presence comes up over the whole
    // sky as the view arrives, at two fifths of itself AHEAD of the band — the band then does not
    // switch a population on along a hard edge: it finds faint stars and leaves them clearer (the
    // step from one to the other is spread over a hundred points behind the crest).
    const mo = state.reduceMotion ? MOMENT.reduced : MOMENT;
    const leaves = state.reduceMotion ? mo.dissolve[0] : mo.band[c.kind].leaves;
    const kept = bed == null ? 0 : 0.34 * smoothstep(leaves - 0.5, leaves + 0.4, bed) * (1 - easeOut((bed - mo.back[0]) / (mo.back[1] - mo.back[0])));
    const keptAt = (x, y) => kept * (state.reduceMotion ? clamp01(pal.look) : ring ? 0.4 + 0.6 * smoothstep(-20, 100, sinceOf(x, y)) : 0.4);   // (before the band leaves, every star is ahead of it)
    // Tonight's star keeps its own dark sky all the way up: while the view is between the poses the
    // star crosses the field (236 pt up and 123 across on the Duo, 596 pt on the slab), and any star
    // that comes near it gives way — nothing runs through it. The clearing it carries opens from the
    // one laid out beside the tree (nothing within 17 pt there: the rule starts inside it, so no
    // star is touched in the frame the move begins) to the full 30 pt over the first tenth of the
    // rise, and is the one laid out in the clear window when it arrives (starsFor).
    const sparkW = pal.look > 0 && pal.look < 1 ? clamp01(1.5 * (pal.tonightSpark ?? 0)) : 0;
    const tAt = pal.tonightAt;
    const opened = smoothstep(0, 0.1, pal.look);
    const rIn = lerp(7, 14, opened), rOut = lerp(13, 30 * c.starScale - 1, opened);
    const clearOfTonight = (x, y) => (sparkW > 0 && tAt ? 1 - sparkW * (1 - smoothstep(rIn, rOut, Math.hypot(x - tAt.x, y - tAt.y))) : 1);

    // the ordinary sky of the leading page
    if (stars.far.length) {
      const horizonY = c.H0 + c.D * pal.look + off.tiltY;
      // Opening the Duo at night: the valley's light is starlight. In the bare second the page's stars
      // come out from the fold outward — once, slowly: dim until the front reaches them, a small
      // swell as it passes, then themselves. (By day there are none; under Reduce Motion nothing moves.)
      // The front leaves the fold at once and runs at 700 pt/s: it is in the margin column — the one part
      // of the page its cards never cover — by 0.55 s and has crossed it by 0.7 s, before the cards
      // begin to land (0.9 s); and its swell is larger there (×1.9), where it will go on being seen.
      const openAge = state.event && state.event.kind === 'open' && !state.reduceMotion ? state.event.age : null;
      const foldX = G.ox - 10, frontAt = openAge == null ? Infinity : 700 * Math.max(0, openAge);
      const marginX = state.layout?.title ? state.layout.title.x : G.ox - 388;   // the leading page's cards begin here; the margin column is to its left
      // The bedtime band is the phone page's: its light dies at the fold, and so do the answers — the
      // leading page's stars are still when its cards come back (they answered to 5.2 s, mid-page, as
      // the cards returned). Only the stars in the gutter, beside the phone page, still answer.
      const foldFade = (x) => smoothstep(G.ox - 75, G.ox - 20, x);
      // A star of the leading page's sky is never seen inside the anchor window: the phone page's sky
      // is his alone, and the cover's picture. (It is hidden by where it IS, not by how far the view
      // has turned: for 0.6 s of the rise the spread's phone page showed a few of these that the cover
      // does not have.) The line is where it always was at the two poses — 3 pt left of the window at
      // rest, 2 pt looking up — and soft only while the view moves, so a star crossing it fades.
      const edgeX = G.ox - 3 + clamp01(pal.look), edgeSoft = 6 * onTheWay(pal.look);
      const T1 = lead > 0 ? state.layout?.title : null;
      const T2 = T1 ? state.layout.subtitle : null;
      for (const f of stars.far) {
        const x = G.ox + f.x + off.x, y = f.y + off.y;
        if (y < -4 || y > G.H + 4 || x < -4) continue;
        const tw = time == null || f.steady ? 0.94 : 1 - 0.3 * (0.5 - 0.5 * Math.cos(TAU * (time / f.period + f.phase))) * still;
        if (x > edgeX) continue;                              // (inside the anchor window: his sky alone)
        let wave = answer(x, y) * foldFade(x);
        let arrived = 1;
        if (openAge != null) {
          const since = frontAt - (foldX - x);
          arrived = 0.4 + 0.6 * smoothstep(-30, 60, since);
          const swell = 0.75 * (1 + 0.9 * (1 - smoothstep(marginX - 14, marginX + 40, x)));
          if (since > -30) wave = Math.max(wave, out * swell * Math.exp(-(((since - 20) / 110) ** 2)) * smoothstep(-30, 10, since));
        }
        let a = f.a * Math.max(out, wave * 0.8, kept * 0.5) * tw * (light ? 0.8 : 0.9) * (1 + 0.6 * wave) * settle * arrived;
        if (edgeSoft > 0) a *= 1 - smoothstep(edgeX - edgeSoft, edgeX, x);
        a *= 0.35 + 0.65 * smoothstep(4, 46, horizonY - y);   // thinned by the air near the horizon
        // none behind the leading page's title when it is there
        if (T1 && x > T1.x - 20 && x < T1.x + T1.width + 8 && y > T1.y - 8 && y < (T2 ? T2.y + T2.height : T1.y + T1.height) + 8) a *= 1 - lead;
        if (a < 0.006) continue;
        const r = Math.min(1.05, f.r) * s * scale * (1 + 0.3 * wave);     // (none larger than the largest of his: 1.15 pt)
        if (light) {
          // (as his are drawn on the pale page — small crisp points, the few bright ones a larger crisp core — and fainter)
          if (f.m > 0.62) {
            const half = Math.min(1.05 / 0.24, 2.8 + 2.4 * (f.m - 0.62) / 0.38) * s * scale * (1 + 0.3 * wave);
            ctx.globalAlpha = clamp01(a * 0.4);
            ctx.drawImage(sprites.deep, x * s - half * 1.7, y * s - half * 1.7, half * 3.4, half * 3.4);
            ctx.globalAlpha = clamp01(a);
            ctx.drawImage(sprites.bright, x * s - half, y * s - half, half * 2, half * 2);
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

    // THE PALE PAGE'S FIELD AT A YEAR. Some three hundred like-sized white points over a land band that
    // is nearly white say snow falling before they say stars. Once his sky is dense (`dense`: nothing
    // at 180 nights, all of it from 330 — at 142 the page is the storybook night it was, to the byte)
    // the ordinary nights (a) drown toward the land, as stars do in the horizon's glow — their strength
    // falls to nothing over the lowest 118 pt of sky — and (b) stand on a wider ladder of sizes: the
    // large core on its dusk is kept for the brightest tenth (it was the brighter fifth: 21 % of his ordinary nights at a year, now 11 %), and the rest
    // are smaller crisp points, the faint ones smaller and fainter than they were. No place moves; the
    // four-point stars and the dark print are untouched.
    const dense = light && urlField !== 'old' ? smoothstep(180, 330, stars.list.length) : 0;
    const marks = [];                                      // the four-point stars as drawn: [x, y, kind, how much of the four-point mark] — window.__hillPainted.stars.marks
    stars.marks = marks;
    for (const star of stars.list) {
      if (star.kind === 'tonight') continue;               // lit over everything: see drawTonight
      let x = G.ox + star.x + off.x, y = star.y + off.y;
      if (y < -8 || y > G.H + 8) continue;
      const big = star.kind === 'first' || star.kind === 'month';
      let byMoon = 0;
      if (moonAt) {
        const dx = x - moonAt.x, dy = y - moonAt.y;
        const d = Math.hypot(dx, dy);
        // A FOUR-POINT STAR BESIDE THE MOON IS A POINT. A bright star close to the moon is the moon's
        // companion — a star and a moon are an emblem (on the default day a month-night's mark stood
        // 32 pt right of the disc at 21:00, looking up with the cards away, and within 66 pt of it all
        // evening). Stars near a moon drown in its glare: within `near` of the centre of the moon the
        // mark is the point an ordinary bright night is, and it has all its four points again `far`
        // out. By how strongly the moon stands in this sky (`moonSky`: its disc as the cards-away
        // picture draws it — which, now that the cards cut a disc and do not hide it, is simply the
        // moon as drawn, but for the glyphs' box) — never by what the chrome is doing: a card that
        // comes over the moon changes nothing about the star. (While a card could take a disc away
        // the rule first asked the DRAWN disc, and the place below asked it too: as the cards
        // returned at a 21:00 bedtime the disc went out in a tenth of a second and the star beside it
        // grew its four points and slid 8.8 pt in the same five frames, under the arriving Today
        // card.) Tonight's star is not in this loop.
        if (big && urlMoonStar !== 'old') {
          const k = c.moonR / 9.5;
          byMoon = (pal.moonSky ?? 0) * (1 - smoothstep(moonNear * k, moonFar * k, d));
        }
        // (a four-point star stands off further — 32 pt from the moon's centre on the Duo: its rays reach
        // 7 pt, one touching the moon's limb is an emblem, and one 9 pt off it still read as the moon's own.
        // Its PLACE is the sky's: where the star and the moon are, never how the star or the disc is
        // drawn — as a point it keeps the same 32 pt.)
        const off2 = big ? mR + 17.5 : mR;
        if (d < off2) {
          const a = d < 0.01 ? hash(star.night, 9) * TAU : Math.atan2(dy, dx);
          x = moonAt.x + Math.cos(a) * off2; y = moonAt.y + Math.sin(a) * off2;
        }
      }
      // THE ORDER OF RANK, by summed light: tonight's star, then the first night's, then the month-nights
      // (each at twice the brightest ordinary night or more), then the ordinary nights. So a four-point
      // star is never a ghost: it is not drawn under 0.8 of its full strength — its twinkle is a fifth of
      // itself at most, and the air near the horizon takes a fifth at most.
      const twOwn = time == null ? 0.92 : 1 - (1 - twinkle(star, time)) * still;
      const tw = big ? 1 - (1 - twOwn) * (0.2 / 0.68) : twOwn;
      const wave = answer(x, y);
      // out in the order of brightness as the sky darkens; the ring shows any of them for a breath
      const threshold = (1 - star.magnitude) * 0.8;
      // (in a sky too light for stars — where a standing frame draws none at all — the moment shows them
      // only by the band and by what it leaves them, and lets them go: its last frame is the standing one)
      const shown = out > 0.004 ? smoothstep(threshold - 0.05, threshold + 0.2, out) : 0;
      // a real range: most nights are small faint lights, a few are bright (m: 0 the faintest … 1)
      const m = clamp01((star.magnitude - 0.22) / 0.5);
      // THE BAND IS SPARED THE THINNING WHERE THE STANDING SKY DRAWS NO STARS. On a July evening the sun
      // is up at bedtime and the sky has no stars of its own: the band's answers, and what it leaves
      // them while the cards are away, are the pale page's ONLY stars in the moment — and thinned as a
      // standing field is they were fewer than half (the cover at 3.0 s: about 40 points that read
      // at 1×, to 18; the slab 20 to 8, and those low over the apricot horizon nearly all gone). So a
      // star the band is showing takes its first size and light — and is not drowned toward the land —
      // by how little the sky itself shows of it (`shown`: nil in July, all of it on a November
      // night, where the thinning is the gain it was made for and nothing changes), eased by how far
      // the band has it (`wave`, `keptAt`: nil at both ends of the moment, so no standing frame and no
      // join moves). `thinK`: this star's share of `dense`.
      let thinK = dense;
      if (dense > 0 && !big && bed != null && shown < 1) thinK *= 1 - (1 - shown) * smoothstep(0, 0.15, Math.max(wave, keptAt(x, y)));
      let alpha = (light ? lerp(0.74 + 0.26 * m, 0.60 + 0.40 * m, big ? 0 : thinK) : 0.50 + 0.50 * Math.pow(m, 0.6)) * tw * shown * settle;
      if (bed != null) alpha *= 1 + 0.22 * passed(x, y) * (1 - smoothstep(5.5, 12, bed));   // (it keeps a fifth more light, and lets it go slowly into the settled night's own)
      alpha = Math.max(alpha, wave * (0.6 + 0.4 * star.magnitude), keptAt(x, y) * (0.6 + 0.4 * m)) + 0.4 * wave * shown;
      alpha *= clearOfTonight(x, y);
      // thinned by the air near the horizon
      const horizonY = c.H0 + (c.D * pal.look) + off.tiltY;
      const thin = 0.4 + 0.6 * smoothstep(4, 46, horizonY - y);
      alpha *= big ? Math.max(0.8, thin) : thin;
      if (thinK > 0 && !big) alpha *= lerp(1, smoothstep(8, 118, horizonY - y), thinK);     // (the pale page, dense: drowned toward the land)
      if (!(alpha > 0.006)) continue;
      const grow = 1 + 0.45 * wave;
      const px = x * s, py = y * s;
      const tint = light ? 'white' : star.warmth > 0.3 ? 'warm' : star.warmth < -0.25 ? 'cool' : hash(star.night, 8) > 0.9 ? 'rose' : 'plain';
      // A FOUR-POINT STAR IS NEVER SEEN THROUGH GLASS AS FOUR POINTS. Through a glass tile a
      // month-night's mark is a small sparkle beside the tile's own words — "changed at 7:35 PM ✦", the
      // app's AI glyph (cover, 326 × 420, in the Diaper tile). Under a glass card it is drawn as the
      // brightest ordinary night is — a round point — by that card's opacity (underGlass): its place
      // is its own, so with the cards away (the bedtime moment, the sky alone) it is the mark it was.
      // And beside the moon (`byMoon`, above). `point`: 0 the four-point mark … 1 the point. On
      // the way from one to the other its rays draw in — shorter, at their full light until they are
      // nearly gone — as the point comes up: a smaller sparkle, never a grey ghost of the large one.
      const point = big ? Math.max(underGlass(state, x, y), byMoon) : 1;
      if (big) marks.push([Math.round((x - G.ox) * 10) / 10, Math.round(y * 10) / 10, star.kind, Math.round((1 - point) * 1000) / 1000]);
      if (big && point < 1) {
        // The first night's: about 16 pt across. A month-night's: about 10 × 13 pt with a core of
        // 1.6 pt, in tonight's cream at half its warmth (it took the ordinary nights' tints: one was
        // rose, one blue, and at 0.52 of the sprite none was stronger than a bright ordinary night).
        const first = star.kind === 'first';
        const half = 14 * s * scale * (first ? 0.86 : 0.70) * grow * (1 - 0.8 * point);
        const rays = alpha * (1 - smoothstep(0.6, 1, point));
        if (light) {
          ctx.globalAlpha = clamp01(rays * 0.55);
          ctx.drawImage(sprites.deep, px - half * 1.5, py - half * 1.5, half * 3, half * 3);
        } else {
          ctx.globalAlpha = clamp01(rays * 0.16);
          ctx.drawImage(sprites.glowWarm, px - half * 0.7, py - half * 0.7, half * 1.4, half * 1.4);
        }
        ctx.globalAlpha = clamp01(rays);
        ctx.drawImage(sprites[`glint-${light ? (first ? 'ivoryFirst' : 'ivoryMonth') : first ? 'warm' : 'month'}`], px - half, py - half, half * 2, half * 2);
      }
      if (big && point > 0) {
        // (…the point: an ordinary night's at its cap — 1.15 pt, a peak luminance of 0.85 — in the mark's own warmth)
        const r = 1.15 * s * scale * grow;
        if (light) {
          const half = (1.15 / 0.24) * s * scale * grow;
          ctx.globalAlpha = clamp01(alpha * point * 0.5);
          ctx.drawImage(sprites.deep, px - half * 1.7, py - half * 1.7, half * 3.4, half * 3.4);
          ctx.globalAlpha = clamp01(alpha * point);
          ctx.drawImage(sprites.bright, px - half, py - half, half * 2, half * 2);
        } else {
          const a = Math.min(alpha, STAR_PEAK / sprites.lum.warm) * point;
          ctx.globalAlpha = clamp01(a * 0.13);
          ctx.drawImage(sprites.glowWarm, px - r * 4, py - r * 4, r * 8, r * 8);
          ctx.globalAlpha = clamp01(a);
          ctx.drawImage(sprites['dot-warm'], px - r * 2.33, py - r * 2.33, r * 4.66, r * 4.66);
        }
      }
      if (!big) {
        // (an ordinary night is capped: 1.15 pt in radius, and a peak luminance of 0.85 — the largest
        // were 1.47 pt and 0.96, as strong as a month-night's mark. Only as it stands: the band's swell is its own.)
        const r = Math.min(1.15, 0.52 + 0.95 * Math.pow(m, 0.85)) * s * scale * grow;
        alpha = Math.max(Math.min(alpha, STAR_PEAK / sprites.lum[tint]), Math.min(alpha, wave));
        if (light) {
          // On a pale page a light needs a little deeper sky around it — a soft patch, never a disc.
          // And a field of soft round white dots is falling snow: so here the faint nights are small
          // crisp points with no patch at all, and the brighter fifth a larger crisp ROUND core on its
          // own bit of dusk (one mark, one meaning: four points are kept for the first night, the
          // month-nights and tonight — the brighter fifth used to be small four-point glints here).
          const coreAt = lerp(0.6, 0.76, thinK);
          if (m > coreAt) {
            // (its core is 0.24 of this: 0.82 pt … capped at 1.15 pt — it went on to 1.54)
            const half = Math.min(1.15 / 0.24, 3.4 + 3.0 * (m - coreAt) / (1 - coreAt)) * s * scale * grow;
            ctx.globalAlpha = clamp01(alpha * 0.5);
            ctx.drawImage(sprites.deep, px - half * 1.7, py - half * 1.7, half * 3.4, half * 3.4);
            ctx.globalAlpha = clamp01(alpha);
            ctx.drawImage(sprites.bright, px - half, py - half, half * 2, half * 2);
            continue;
          }
          const rl = lerp(0.56 + 0.62 * m, 0.42 + 0.66 * m, thinK) * s * scale * grow;
          ctx.globalAlpha = clamp01(alpha * (0.22 + 0.4 * m) * smoothstep(0.25, 0.6, m) * (1 - 0.6 * thinK));   // (a faint night has no patch: only its point)
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
    // How lit it is: sparkOf (lit exactly while the night has begun; lit once, from what it was).
    const spark = sparkOf(state);
    if (!(spark > 0.004)) return;
    // Under Reduce Motion the star belongs to the looked-up still: while an event dissolves the two
    // stills there is one star on screen, not one beside the tree and one in the window.
    if (state.reduceMotion && state.event && urlLook == null && pal.look < 0.5
      && ['bedtime', 'arrive', 'settle'].includes(state.event.kind)) return;
    const s = G.s, c = G.cfg;
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
      // on a light page: a little dusk gathered round it, so the ivory star shows (it was a white star
      // on lilac, carried by its patch: the core is ivory now, about (255, 244, 214), and the dusk
      // under it seven levels deeper)
      const r = 26 * s * scale * (0.7 + 0.3 * k) * breath;
      ctx.globalAlpha = clamp01(0.78 * k);
      ctx.drawImage(sprites.deep, px - r, py - r, r * 2, r * 2);
    }
    const half = 14 * s * scale * (0.62 + 0.38 * k);
    const sprite = sprites[`spark-${pal.dark ? 'tonight' : 'ivory'}`];
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
    if (spark > 1) {                                     // past full: the spark (on the pale page a paler ivory, not white)
      ctx.globalAlpha = clamp01((spark - 1) * 2);
      const r = 2.4 * s;
      ctx.drawImage(sprites[pal.dark ? 'dot-white' : 'dot-ivoryMonth'], px - r * 2.33, py - r * 2.33, r * 4.66, r * 4.66);
    }
    // The ring is not a line: one soft band of light going out across the sky, once — feathered
    // on both sides, brightest just behind its leading edge, a long soft trail inside it, and
    // fading as it grows so that it has all but gone before it reaches the far corner. It only
    // tells the eye where to look; the stars answering as it passes carry the gesture (they answer
    // to `ring.strength`, which lasts the whole way — the band's own light does not).
    if (ring && ring.strength > 0 && urlBand !== 'answers') {
      const R = ring.radius;
      const farC = ring.far;
      // (it is never a circle round the star — that is sonar. Its light is HELD until the crest is
      // 150 pt out: wider than the strip's window, so on the Duo its first visible state is an arc that
      // already leaves the window on both sides, and on the slab one that already spans the header's
      // gap. It was visible from 46 pt out, a closed ring round the star for a third of a second. It
      // comes up broad and soft, is fullest two fifths of the way across, and has gone by nine tenths.)
      const band = smoothstep(150, Math.max(farC * 0.42, 230), R) * (1 - smoothstep(farC * 0.44, farC * 0.9, R));
      if (band > 0.004) {
        // (it leaves from the star's place in the clear window, which does not move: `ring.at`)
        const bx = ring.at.x * s, by = ring.at.y * s;
        // (broad: 54 pt + 0.14 R made a stroke some 30 pt wide at half strength — a drawn line. It is
        // nearly twice that now, and its peak is set for that width: less in the dark print, where a
        // broad swell needs little; more on the pale page, where a broad one is the only kind that
        // does not read as a ring. `band=arc` in the URL plays the old even arc, to compare.)
        const arc = urlBand === 'arc';
        const Wd = (54 + R * 0.14) * (arc ? 1 : 1.8);     // it widens as it goes
        const r0 = Math.max(0, R - Wd * 0.6), r1 = R + Wd * 0.5;
        const tint = pal.dark ? lch(0.88, 0.05, 84) : lch(0.995, 0.012, 95);
        const peak = (pal.dark ? 0.085 : 0.22) * band * (arc ? 1 : pal.dark ? 0.8 : 1.25);
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
        // IT IS NOT AN ARC EITHER. At one strength all the way round, the crest was a large letter "C"
        // drawn across the sky (a pale ring on the pale page). Its strength now varies ALONG the crest:
        // fullest on the bearing from the star to the middle of the open sky, uneven on the way, and gone
        // a quarter-turn to either side — so what crosses the sky is a soft swell of light with no ends,
        // not a stroke of even width. (The stars answer all the way round, as they did: `ring.radius`.)
        if (!arc) {
          const aim = Math.atan2((c.H0 + c.D) * 0.5 - ring.at.y, G.ox + G.Wa * 0.5 - ring.at.x);
          const lobe = b.createConicGradient(aim - Math.PI, bx, by);
          for (let k = 0; k <= 48; k += 1) {
            const dAng = (k / 48 - 0.5) * 360;               // degrees from the bearing
            const u = Math.abs(dAng) / 80;
            const uneven = 0.86 + 0.14 * Math.cos((dAng + 24) * DEG * 3.3);
            lobe.addColorStop(k / 48, `rgba(0,0,0,${(u >= 1 ? 0 : Math.pow(Math.cos(u * Math.PI / 2), 2) * uneven).toFixed(3)})`);
          }
          b.fillStyle = lobe;
          b.fillRect(0, 0, G.pxW, G.pxH);
        }
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

  function drawLife(ctx, state, pal, time, offKnoll, look, tree = 1) {
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

    // Leaves lying under the tree, and a few on their way down (petals in spring) — the tree's own:
    // where it is not drawn (treeShown), nor are they.
    const falling = Math.max(sea.leafFall * (0.3 + 0.7 * sea.foliage), sea.petals * 0.8);
    if (falling > 0.03 && tree > 0.004) {
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
        dab(sp, x, y, 0.7 + 0.5 * hash(i, 103), 0.75 * tree);
      }
      const adrift = Math.round(7 * falling);
      for (let i = 0; i < adrift; i += 1) {
        const period = 30 + 16 * hash(i, 104);
        const f = time == null ? hash(i, 105) : (((time / period + hash(i, 105)) % 1) + 1) % 1;
        const x = tr.x + (hash(i, 106) - 0.5) * tr.h * 0.7 + Math.sin(f * 9 + i) * 6 + f * 9;
        const y = tr.baseY - tr.h * 0.7 + f * tr.h * 0.74;
        dab(sp, x, y, 1.0, Math.sin(Math.PI * f) * 0.9 * tree);
      }
    }

    // Fireflies beneath the tree on summer evenings, from the last of the sun on.
    const dusk = sea.fireflies * (1 - smoothstep(-2.5, 3.5, pal.altDeg)) * (1 - 0.5 * smoothstep(-14, -30, -pal.altDeg));
    if (dusk > 0.02) {
      // (They are the WORLD's, cast over the anchor window first: twelve by the tree, the rest over its
      // land — the same ones, in the same places, on the cover and on the spread's phone page — and then
      // the leading page's own, to the left of it. They were cast over each display's own width, so
      // after dusk in July the cover and the spread's phone page had different fireflies: up to 255
      // pixels by up to 105 levels at the foot of the looked-up frame.)
      const own = Math.round(12 + 14 * (G.Wa / 466));
      const count = own + Math.round(14 * (G.ox / 466));
      for (let i = 0; i < count; i += 1) {
        let x, y;
        if (i < 12) {
          x = tr.x - tr.h * 0.6 + hash(i, 121) * tr.h * 1.2;
          y = i < 4 ? tr.baseY - 5 - hash(i, 122) * tr.h * 0.3 : knoll.at(x) + 3 + hash(i, 122) * tr.h * 0.5;
        } else {
          x = i < own ? hash(i, 121) * (G.Wa + c.T) : -G.ox * hash(i, 121);
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
    // It arrives as the view comes to rest (in by 2.8 s) and has gone (4.6 s) as the cards begin to
    // come back: the page's title gives way to the page — it is never read through a returning card.
    // (lab/presence.js, MOMENT.caption; under Reduce Motion it stands for two seconds after the dissolve.)
    const arrive = bed == null ? 1 : momentCaption(bed, state.reduceMotion);
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
      // (A held frame paints the cap's own colour through the blur, as it always did: the picture is
      // the old one to the level. While the animation RUNS the cap's colour changes with the tone at
      // every frame of an event — a new blurred fill each time, a canvas made in mid-move: there the
      // guard is one white mask per size, blurred once and tinted, as the sun's rings are.)
      const live = !state.frozen;
      const key = live ? `${w}|${h}` : `${w}|${h}|${cap}`;
      let sprite = guardSprites.get(key);
      if (!sprite) {
        if (guardSprites.size > 24) guardSprites.clear();
        sprite = mk(w, h);
        const b = sprite.getContext('2d');
        b.filter = `blur(${feather * 0.5 * s}px)`;
        b.fillStyle = live ? '#fff' : cap;
        b.beginPath();
        b.roundRect(feather * s, feather * s, w - 2 * feather * s, h - 2 * feather * s, 10 * s);
        b.fill();
        guardSprites.set(key, sprite);
      }
      if (live) sprite = tinted(sprite, cap);
      ctx.globalCompositeOperation = pal.dark ? 'darken' : 'lighten';
      ctx.globalAlpha = opacity;
      ctx.drawImage(sprite, 0, 0, w, h, Math.round((box.x - pad - feather) * s), Math.round((box.y - pad - feather) * s), w, h);
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

  /** THE TREE IS A LAYER OF ITS OWN, and with the cards on, looking up, it is not drawn at all — trunk,
   *  limbs, leaves, blossom, snow, the leaves lying under it: in both appearances. The land stays.
   *  (It used to be drawn "only behind the cards": through the lab's glass that left a violet stain in
   *  the sleep card on the pale page, a crown with no trunk under the shorter Sleep tile when he is awake
   *  in the night, and a trunk stub under the slider on the slab. The night's subject with the cards on
   *  is tonight's star among his stars; the tree is what the cards uncover at bedtime.)
   *  → how much of it is drawn, 0 … 1: all of it at rest, and looking up with the cards away (the bare
   *  poster of the bedtime moment); it goes with the cards' return (their opacity), leaves early in a
   *  rise behind the cards (`arrive`: gone before it has sunk to the capsule) and comes back over the
   *  last of the way down at first light (`settle`). Continuous in `look` and in the cards' opacity:
   *  no pop, no join that jumps. The cards that count are the phone page's own (not the header's words,
   *  the strip, the tab capsule or the undo toast, which stay through the moment). */
  function treeShown(state, look) {
    const up = smoothstep(0.05, 0.45, look);
    if (!(up > 0)) return 1;
    let on = 0;
    for (const card of state.cards ?? []) {
      if (card.kind === 'header' || card.kind === 'strip' || card.kind === 'tabbar' || card.kind === 'toast') continue;
      if (card.x + card.width <= G.ox) continue;           // (the leading page's cards are not over the tree)
      on = Math.max(on, clamp01(card.opacity ?? 1));
    }
    return 1 - up * on;
  }

  /** UNDER THE GLASS TILES THE SNOW IS A STEP DEEPER — a shade that belongs to the cards, not to the land.
   *  In the dark appearance snow is the palest thing on the ground (a third of the way to white at dusk),
   *  and a glass tile over it goes milky: on 15 January at 16:28 the ground under the Feed and Diaper
   *  tiles stood at 4–5 times a card's luminance (0.047 and 0.060 against 0.0117). Painting the snow
   *  itself deeper there would take it from the bare panorama too — the knoll, the strip and the valley
   *  are the winter. So the land is painted as it is, and where the phone page's glass tiles lie
   *  (`tile`, `sleep`: one field, from the first tile's top to the foot of the display, let go over
   *  12 pt outside it) a soft shade is laid over the LAND alone, by the tiles' opacity: with the cards
   *  away, or the sky alone, there is none. Its strength comes from how light the snow is at this hour
   *  against what a tile can take (about 0.03: two and a half cards), so at night, and in any season
   *  without snow, it is nothing at all. → null, or { amount 0 … 1 of black over the land, mask, key }. */
  function cardShade(state, pal) {
    if (!pal.dark || !(pal.sea.snow > 0.03)) return null;
    let x0 = Infinity, x1 = -Infinity, y0 = Infinity, on = 0;
    for (const card of state.cards ?? []) {
      if ((card.kind !== 'tile' && card.kind !== 'sleep') || card.x + card.width <= G.ox) continue;
      const o = clamp01(card.opacity ?? 1);
      if (!(o > 0)) continue;
      on = Math.max(on, o);
      x0 = Math.min(x0, card.x); x1 = Math.max(x1, card.x + card.width); y0 = Math.min(y0, card.y);
    }
    if (!(on > 0)) return null;
    const lit = pal.shown(pal.snowShade)[0] ** 3 * SNOW_UNDER_GLASS.reads;       // about what the snow under a tile reads now
    const keep = clamp(SNOW_UNDER_GLASS.most / Math.max(1e-6, lit), SNOW_UNDER_GLASS.floor, 1);   // the share of its light it may keep
    const amount = (1 - Math.pow(keep, 1 / 2.2)) * smoothstep(0.03, 0.3, pal.sea.snow) * on;
    if (!(amount > 0.004)) return null;
    const s = G.s, q = 0.25;
    const box = [x0, y0, x1].map((v) => Math.round(v * 2) / 2);
    const mk2 = `${box.join(',')}|${G.pxW}|${G.pxH}`;
    if (!G.shade || G.shade.key !== mk2) {
      const mw = Math.ceil(G.pxW * q) + 2, mh = Math.ceil(G.pxH * q) + 2;
      const canvas = mk(mw, mh);
      const m = canvas.getContext('2d');
      m.setTransform(q * s, 0, 0, q * s, 0, 0);
      m.filter = `blur(${4 * s * q}px)`;
      m.fillStyle = '#000';
      m.fillRect(box[0] - 6, box[1] - 6, box[2] - box[0] + 12, G.H + 60 - box[1]);
      m.filter = 'none';
      G.shade = { key: mk2, canvas, mw, mh, q };
    }
    return { amount, mask: G.shade, key: `${mk2}|${Math.round(amount * 500)}` };
  }
  /** …laid over the land layer `lc` (source-atop: only where there is land). */
  function layCardShade(lc, shade) {
    const m = shade.mask;
    lc.setTransform(1, 0, 0, 1, 0, 0);
    lc.globalCompositeOperation = 'source-atop';
    lc.globalAlpha = clamp01(shade.amount);
    lc.imageSmoothingEnabled = true;
    lc.drawImage(m.canvas, 0, 0, m.mw, m.mh, 0, 0, m.mw / m.q, m.mh / m.q);
    lc.globalCompositeOperation = 'source-over';
    lc.globalAlpha = 1;
  }

  /** The planes of land for one pose, far to near, with the mist between them and the sun's bloom
   *  lying over the far ones. `open`: seconds since the Duo opened, or null. `tree`: how much of the
   *  tree is drawn (treeShown). */
  function drawLand(ctx, pal, look, tilt, breath, open, sunNow, bloomAmt, tree = 1) {
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
      drawPlane(ctx, plane.canvas, (G.xL + G.ox + off.x) * s, (plane.y0 + off.y) * s, look);
      if (plane.id === 'knoll' && tree > 0.004) {
        // the tree stands on its knoll: ink at its true value, carried by the knoll's plane
        const t = G.tree;
        ctx.globalAlpha = Math.min(1, tree);
        drawPlane(ctx, t.canvas, (G.xL + G.ox + off.x) * s + Math.round((t.x - G.xL) * s - t.masks.cx), (plane.y0 + off.y) * s + Math.round((t.baseY - plane.y0) * s - t.masks.cy), look);
        ctx.globalAlpha = 1;
      }
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
          ctx.drawImage(b.canvas, 0, 0, cw, ch, onGrid((G.xL + G.ox + off.x) * s, look) + RL.x, onGrid((RL.y0 + off.y) * s, look) + RL.y, cw, ch);
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
    drawPlane(ctx, G.sky, (G.xL + G.ox + skyOff.x) * s, (G.skyTop + skyOff.y) * s, look);
    ctx.filter = 'none';

    // where the bodies are in this pose
    const sunNow = bodyAt(state, pal.sunXf, pal.altDeg, c.sunR, look, sunHead(pal.sunXf));
    sunNow.x += G.ox + tilt.x * SKYPLANE.tilt[0]; sunNow.y += skyOff.tiltY;
    let moonNow = null;
    if (state.moon) {
      moonNow = bodyAt(state, pal.moonXf, state.moon.altitude / DEG, c.moonR, look);
      moonNow.x += G.ox + tilt.x * SKYPLANE.tilt[0]; moonNow.y += skyOff.tiltY;
    }
    pal.moonNow = moonNow && state.moon.altitude > -0.02 ? moonNow : null;
    // (where this pose puts them, for tools/measure.mjs: it names a disc it has found by the state's x,
    // and looking up the camera's turn stands between the two — window.__skyBodies. The place, x AND y:
    // by x alone any disc-like blob in the moon's column, at any height, would be named the moon.)
    G.bodies = { sun: { x: sunNow.x, y: sunNow.y }, moon: pal.moonNow ? { x: moonNow.x, y: moonNow.y } : null };
    G.discs = { sun: 0, moon: 0 };                          // how strongly each disc is drawn in this frame, 0 … 1 (window.__hillPainted.discs: for a probe)
    // A DISC IS NOT DRAWN DIRECTLY BEHIND THE WI-FI AND BATTERY GLYPHS — the one place the chrome hides
    // a disc (BRIEF.md, "Signed off": the sun and the moon keep their places all day and all night, and
    // the cards cover what they cover). White glyphs on a cream disc cannot be read, and a crescent
    // touching the Wi-Fi glyph is the Focus moon. The place is the glyphs' own box and no more: the
    // 50 × 13 pt the two stand in, centred in the Duo's column, their foot at the head of the strip's
    // clear window (lab/chrome.js, duoStrip; the lab's layout says only where that window begins).
    // A disc any part of which would stand within 1 pt of that box is out of sight, and it is whole
    // again once it stands 4 pt further off (the moon 6: a faint moon is a moon, a sun at half strength
    // a tan ball — about three minutes of an afternoon). With it go its halo's rings and its glare;
    // the sky's own glow round the sun stays.
    // Beside the box, over it, under it, behind the island (which is black, and simply covers what
    // is behind it) a disc is drawn. (It was the whole width of the strip's column, from its head to
    // 16 pt under the icons: no disc under or beside them — withdrawn with "whole or not at all".)
    // The icons sit lower while a sleep runs (the island is longer): `heads` — where the clear
    // window begins awake, and asleep. A sleep that has just begun or ended does not pop a disc (or a
    // cloud, below) off or on: over the event's first 0.6 s the box goes from where it was.
    const SC = state.layout?.stripClear;
    const heads = SC ? [SC.yMin - (state.asleep ? ISLAND_GROWS : 0), SC.yMin + (state.asleep ? 0 : ISLAND_GROWS)] : null;
    const join = sleepJoin(state.event);
    // (The icons are the chrome's: with the sky alone — no strip in `state.cards` — nothing is hidden.)
    const strip = (state.cards ?? []).find((cd) => cd.kind === 'strip');
    const stripOn = strip ? clamp01(strip.opacity ?? 1) : 0;
    const ev = state.event;
    const raises = Boolean(ev && !ev.begunBefore && state.asleep === 'night' && (ev.kind === 'bedtime' || ev.kind === 'arrive'));
    const clearOfGlyphs = (body, R, ramp) => {
      if (!heads || !body || !(stripOn > 0)) return 1;
      const cx = strip.x + strip.width / 2;
      const dx = Math.max(cx - GLYPHS.width / 2 - body.x, 0, body.x - (cx + GLYPHS.width / 2));
      if (dx > R + 1 + ramp) return 1;
      const clear = (head) => smoothstep(R + 1, R + 1 + ramp, Math.hypot(dx, Math.max(head - GLYPHS.height - body.y, 0, body.y - head)));
      const now = clear(heads[state.asleep ? 1 : 0]);
      // (An event that RAISES the view — bedtime, or the night's sleep arriving — never shows a disc the
      // glyphs were hiding: the box goes down 34 pt as the island grows, and a sun that stood behind it
      // came out for half a second before the move took it out of sight again, below. There the box
      // hides a disc at both of its places.)
      if (raises) return 1 - stripOn * (1 - Math.min(clear(heads[0]), lerp(clear(heads[0]), now, join)));
      const was = join < 1 ? clear(heads[state.event.kind === 'wake' ? 1 : 0]) : now;
      return 1 - stripOn * (1 - lerp(was, now, join));
    };
    // WHILE THE VIEW MOVES a disc in the strip's column passes the island and the icons out of sight,
    // and comes out once, under them: nothing of it until its top stands 16 pt clear of the icons'
    // foot, over the whole width of the column (the moon comes out over 12 pt, the sun over 6). This is
    // the strip's old rule, kept for the move alone (`onTheWay`: nil at both poses, so every standing
    // frame is the owner's — a disc where it stands — and no join moves). Without it a July
    // evening's sun, standing beside the island at rest, came down the strip in three pieces: out
    // behind the icons, in, out again beside tonight's star (which keeps its 30 pt, below), in.
    const moving = onTheWay(look);
    const passesIcons = (body, R, ramp) => {
      if (!(moving > 0) || !heads || !body || !(stripOn > 0)) return 1;
      const inColumn = smoothstep(SC.x - 2, SC.x + 4, body.x + R);
      if (!(inColumn > 0)) return 1;
      const clear = (head) => smoothstep(head + 16 - ramp, head + 16, body.y - R);
      const now = clear(heads[state.asleep ? 1 : 0]);
      const was = join < 1 ? clear(heads[state.event.kind === 'wake' ? 1 : 0]) : now;
      return 1 - moving * stripOn * inColumn * (1 - lerp(was, now, join));
    };
    // (how strongly the moon stands in this sky whatever the chrome is doing — the header's own rule
    // only, bodyAt: what the stars ask, below)
    const moonStands = moonNow ? moonNow.seen : 0;
    if (moonNow) moonNow.seen *= clearOfGlyphs(moonNow, c.moonR, 6) * passesIcons(moonNow, c.moonR, 12);
    sunNow.seen *= clearOfGlyphs(sunNow, c.sunR, 4) * passesIcons(sunNow, c.sunR, 6);

    const knollPlane = G.planes.find((p) => p.id === 'knoll');
    const knollOff = planeOffset(knollPlane, look, tilt);
    const tonightAt = tonightHome(look, tilt);
    const ring = ringOf(state, tilt);
    pal.tonightAt = tonightAt; pal.tonightSpark = sparkOf(state);
    // WITH THE CARDS ON A DISC IS DRAWN WHERE IT STANDS, exactly as the cards-away picture draws it —
    // the moon's and the sun's, in both poses, on every display. The cards simply lie over it: an
    // opaque card covers what it covers (half a disc at a card's edge, a cap in the margin), through a
    // glass tile it shows as the glass shows it. The owner's decision (BRIEF.md, "Signed off — what
    // Taylor decided on round three", 3): he was offered "whole or not at all" — a disc drawn only
    // where the whole of it stood in the open, which is what this code did for one pass — and chose
    // this, knowing the cost. So the sky asks the cards nothing about a disc; what it still asks is
    // the header's own rule (bodyAt, `seen`), the two buttons' rims (clearOfButtons) and the glyphs'
    // box (above).

    // (how strongly the moon's disc is drawn in this frame, 0 … 1 — `moonDisc` — and how strongly it
    // stands in this sky with the chrome away, `moonSky`: the same but for the glyphs' box. The stars
    // ask the second: a four-point star beside the moon is a point, drawStars.)
    let moonDisc = 0, moonSky = 0;
    if (pal.moonNow) {
      const m = state.moon;
      const up = smoothstep(-1.5, 0.5, m.altitude / DEG), night = 1 - smoothstep(-8, 3, pal.altDeg);
      const drawn = lerp(0.42 + 0.58 * night, 1, dayMoonOf(pal)) * up * lerp(smoothstep(0.04, 0.2, m.fraction), 1, pal.nightness) * clearOfButtons(state, moonNow.x, moonNow.y, c.moonR);
      moonSky = drawn * moonStands;
      moonDisc = drawn * moonNow.seen;
    }
    pal.moonSky = clamp01(moonSky);
    G.discs.moon = clamp01(moonDisc);

    drawStars(ctx, state, pal, time, skyOff, ring);
    drawShootingStar(ctx, pal, time, skyOff);

    // the moon: a quiet halo, then the disc
    if (pal.moonNow) {
      const m = state.moon;
      const clear = pal.dark ? clearOfText(state, moonNow.x, moonNow.y, c.moonR) : 1;
      const dayMoon = dayMoonOf(pal);
      const mk2 = [pal.dark, Math.round(m.fraction * 200), Math.round(m.rotation * 60), m.inDaylight, Math.round(pal.altDeg * 4), Math.round(clear * 20), Math.round(m.altitude / DEG),
        dayMoon > 0 ? `${Math.round(dayMoon * 100)}|${skyBehindMoon(pal).map((v) => Math.round(v * 400)).join(',')}` : ''].join('|');
      if (G.moon.key !== mk2) { paintMoon(state, pal, clear); G.moon.key = mk2; }
      const up = smoothstep(-1.5, 0.5, m.altitude / DEG);
      const vis = moonDisc;
      const haloAmt = pal.nightness * (0.3 + 0.7 * m.fraction) * clear * up * moonNow.seen;
      if (haloAmt > 0.02) {
        // two painted rings of light, barely there: the room stays dark. (Looking up, the moon has the
        // sky to itself and nothing under it but sky: its halo is a little fuller there.)
        const fuller = pal.dark ? 1 + 1.3 * look * smoothstep(70, 190, moonNow.E) : 1;
        // THE MOON'S GLOW KEEPS UNDER A CARD. Dark, at night, nothing below the header but the disc
        // itself is lighter than a card (0.0117). The rings were sized for a moon high in a sky of
        // 0.003; low over the land the night's sky is its lightest (0.009 with the room un-dimmed), and
        // there the rings lifted the sky round the limb to 0.0113 — at the limit, once a card over the
        // moon no longer hides its disc and the tree no longer stands in front of it (03:00 on the
        // default day, awake, looking up: the Sleep tile's glass lies over that glow). So in the deep
        // night the rings give way to the sky they stand in: no more of them than brings the sky just
        // under the lower limb (8 pt under it: the lightest sky they lie on) to `most`, and never under
        // `least` of themselves. A function of the sky behind the moon alone — the same with the cards
        // on and away, in both poses; a moon in a darker sky (higher; or the room dimmed: he is asleep)
        // keeps all of its glow.
        let held = 1;
        if (pal.dark && pal.deepNight > 0) {
          const room = MOON_GLOW.most - luminance(skyBehindMoon(pal, c.moonR + 8));
          held = lerp(1, clamp(room / (MOON_GLOW.adds * haloAmt * fuller), MOON_GLOW.least, 1), pal.deepNight);
        }
        G.discs.moonGlow = held;
        for (const [k, a] of [[5.2, (pal.dark ? 0.05 : 0.5) * fuller * held], [2.6, (pal.dark ? 0.09 : 0.7) * fuller * held]]) {
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
      const haloLab = mix3(air.sun, air.glow, 0.5);
      const warm = { presence: Math.max(air.presence, 0.6) };
      // On the pale page the disc is a light — lighter than the paper round it — and so has no colour
      // of its own: THE COLOUR BELONGS TO WHAT SURROUNDS IT. Its halo is apricot, about (250, 205, 160),
      // and DEEPER than the sky (it was the disc's own cream, paler than the sky: a pale hole with a
      // paler smudge round it) — fullest through the last hour, a quieter straw while the sun is high.
      const lowL = pal.dark ? 0 : 1 - smoothstep(5, 17, pal.altDeg);
      if (pal.dark || urlSun === 'old') {
        const haloAmt = (pal.dark ? 0.16 + 0.34 * low : 0.5 + 0.3 * low) * clear * sunVis * (pal.dark ? 0.35 + 0.65 * air.presence : 1);
        drawSunHalo(ctx, state, sunNow.x * s, sunNow.y * s, css(air.show(haloLab, warm)), haloAmt);
      } else {
        const halo = mix3(mix3(haloLab, lch(0.90, 0.062, 80), 0.6), lch(0.877, 0.078, 66.5), lowL);
        drawSunHalo(ctx, state, sunNow.x * s, sunNow.y * s, css(air.show(halo, warm)), lerp(0.55, 1, lowL) * sunVis, SUN_RINGS_LIGHT);
      }
      let disc = air.sun;
      if (pal.dark && clear < 1) disc = mix3([0.33, disc[1] * 0.7, disc[2] * 0.7], disc, clear);
      // (never a disc bitten by a button's rim: behind the gear or the avatar there is only its glow.
      // A card's edge is another matter: the cards cut the sun as they cut the moon — above)
      // (…nor, while the view is on its way between the poses, a disc beside tonight's star: on an early
      // summer bedtime the sun comes down the strip as the star climbs it, and passed 9 pt from it. The
      // star keeps its dark sky against the sun's disc as it does against his other stars; the glow stays.)
      const byStar = onTheWay(look) * clamp01(pal.tonightSpark);
      const starRoom = byStar > 0 ? lerp(1, smoothstep(c.sunR + 6, c.sunR + 30, Math.hypot(sunNow.x - tonightAt.x, sunNow.y - tonightAt.y)), byStar) : 1;
      const discA = clamp01(sunVis * clearOfButtons(state, sunNow.x, sunNow.y, c.sunR) * starRoom * risingDisc(state, pal.sunXf, sunNow.y));
      G.discs.sun = discA;
      ctx.globalAlpha = discA;
      ctx.fillStyle = css(disc);
      const round = discPath(sunNow.x * s, sunNow.y * s, R, 0.012, 4.2);
      ctx.fill(round);
      if (!pal.dark && urlSun !== 'old') {
        // …and an edge of its own: a thin apricot line just inside the limb, about (255, 196, 140) and
        // 1.2 pt wide, soft on its inner side — a line of paint, not an outline. The radius and the
        // place are the disc's.
        const edge = air.show(mix3(lch(0.90, 0.075, 78), lch(0.861, 0.099, 64.4), lowL), warm);
        const g = ctx.createRadialGradient(sunNow.x * s, sunNow.y * s, Math.max(0, R - 2.1 * s), sunNow.x * s, sunNow.y * s, R * 1.02);
        g.addColorStop(0, css(edge, 0)); g.addColorStop(0.32, css(edge, 0.45)); g.addColorStop(0.52, css(edge, 1)); g.addColorStop(1, css(edge, 1));
        ctx.globalAlpha = discA * lerp(0.6, 1, lowL);
        ctx.fillStyle = g;
        ctx.fill(round);
      }
      ctx.globalAlpha = 1;
    }

    // clouds, on the sky's own plane. By night they are barely there: a shape of the sky's own colour
    // that softly hides the stars behind it (a veil of the sky itself, then a breath of its form).
    {
      const nightK = pal.starsOut;
      // (`SC`, `heads`, `join`: the strip's clear window, where it begins awake and asleep, and how far a
      // sleep's start or end has carried what the sky shows there — above, with the discs)
      // How far the sky's plane has travelled from where it rests, in device pixels (whole ones at
      // either pose, fractions in between): what carries the clouds.
      const skyRest = planeOffset(SKYPLANE, 0, tilt);
      const skyGone = { x: onGrid((G.xL + G.ox + skyOff.x) * s, look) - Math.round((G.xL + G.ox + skyRest.x) * s),
        y: onGrid((G.skyTop + skyOff.y) * s, look) - Math.round((G.skyTop + skyRest.y) * s) };
      for (const cloud of G.clouds) {
        const f = (((cloud.phase + (time ?? 0) / cloud.period) % 1) + 1) % 1;
        const x = cloud.x + cloud.span * (0.5 - f);            // drifting from the sunset side
        const y = c.H0 - cloud.e;
        const sx = G.ox + x + skyOff.x, sy = y + skyOff.y;
        if (sx < -cloud.len || sx > G.W + cloud.len || sy < -40 || sy > G.H + 40 + cloud.rise) continue;
        const fade = smoothstep(0, 0.18, f) * (1 - smoothstep(0.82, 1, f));
        let a = fade * cloudClear(state, sx, sy, cloud);
        // the everyday view's own (the strip's, the header's) leave as the camera looks up — nothing
        // stands among his stars — and the looked-up view's own arrives with it
        if (cloud.rest) a *= 1 - smoothstep(0.1, 0.55, look);
        if (cloud.up) a *= smoothstep(0.35, 0.85, look);
        // …nor under the strip's own furniture: a cloud keeps 24 pt of plain sky between the status
        // icons and its top, or it is not drawn (close under them it is one more icon) — so while a
        // sleep runs, and the icons sit lower, the strip has none
        if (heads && sx + cloud.len / 2 > SC.x + 20) {
          // (asked of the cloud WHERE IT STANDS AT REST, not where the rising camera has carried it: once
          // the view had sunk it 24 pt below the longer island it was "clear" again and came back to full
          // in a tenth of a second, 36 pt lower, before leaving a second time with the everyday view's own)
          const top = sy - cloud.rise - (skyOff.y - skyOff.tiltY);
          const under = (head) => smoothstep(head + 10, head + 24, top);
          const now = under(heads[state.asleep ? 1 : 0]);
          const was = join < 1 ? under(heads[state.event.kind === 'wake' ? 1 : 0]) : now;
          a *= lerp(was, now, join);
        }
        // …nor across a card's edge: a cloud partly behind a card and partly clear of it is bitten.
        // (It goes with the card — with the cards away, the bare panorama and the bedtime moment, it is there.)
        const box = [sx - cloud.len * 0.46, sy - cloud.rise - 1, sx + cloud.len * 0.46, sy - 1];
        for (const card of state.cards ?? []) {
          if (card.kind === 'header' || card.kind === 'strip' || !(card.opacity > 0.01)) continue;
          a *= 1 - Math.min(1, card.opacity) * acrossEdge(box, card);
        }
        // …nor across the sun's disc: a cloud cutting the disc in two is a bitten sun (nor the moon's)
        for (const [body, R, vis] of [[sunNow, c.sunR, sunVis], [pal.moonNow, c.moonR, pal.moonNow ? pal.moonNow.seen : 0]]) {
          if (!body || !(vis > 0.05) || body.x < -R || body.x > G.W + R) continue;   // (a body off the display hides nothing)
          const ddx = Math.max(sx - cloud.len / 2 - body.x, 0, body.x - (sx + cloud.len / 2)), ddy = Math.max(sy - cloud.rise - body.y, 0, body.y - (sy + 2));
          a *= lerp(1, smoothstep(R + 1, R + 16, Math.hypot(ddx, ddy)), clamp01(vis));
        }
        if (a < 0.02) continue;
        const light = cloudLight(cloud, pal, x, y);
        const ck = `${keys.air}|${light.key}`;
        if (cloud.key !== ck) { paintCloud(cloud, pal, x, y, light); cloud.key = ck; }
        const m = cloud.masks;
        // (A cloud is on the sky's plane and keeps its place on it: the whole pixel it has at rest, carried
        // by the plane's own travel — between pixels while the view moves, where it is drawn smoothed as
        // the plane is. It used to be rounded to a whole pixel of the DISPLAY in every frame of the move,
        // and slipped up to a pixel against the sky and the land from one frame to the next.)
        const px0 = Math.round((G.ox + x + skyRest.x) * s - m.cx) + skyGone.x, py0 = Math.round((y + skyRest.y) * s - m.cy) + skyGone.y;
        if (nightK > 0.02) {
          // the sky's own picture, laid once more over the stars inside the cloud's silhouette
          // (cut once and kept: it changes only when the sky is repainted or the cloud has drifted a pixel
          // — never with the camera: the cloud and the sky move as one)
          const vx = Math.round(onGrid((G.xL + G.ox + skyOff.x) * s, look) - px0), vy = Math.round(onGrid((G.skyTop + skyOff.y) * s, look) - py0);
          const vk = `${keys.air}|${cloud.maskKey}|${vx}|${vy}`;
          if (!cloud.veil || cloud.veil.width !== m.w || cloud.veil.height !== m.h) { cloud.veil = mk(m.w, m.h); cloud.veilKey = ''; }
          if (cloud.veilKey !== vk) {
            const v = cloud.veil.getContext('2d');
            v.globalCompositeOperation = 'source-over';
            v.clearRect(0, 0, m.w, m.h);
            v.drawImage(G.sky, vx, vy);
            v.globalCompositeOperation = 'destination-in';
            v.drawImage(m.body, 0, 0);
            cloud.veilKey = vk;
          }
          ctx.globalAlpha = clamp01(a * 0.5 * nightK);
          ctx.filter = adj;
          drawPlane(ctx, cloud.veil, px0, py0, look);
          ctx.filter = 'none';
        }
        ctx.globalAlpha = clamp01(a * (cloud.high ? 0.9 : 0.96) * lerp(1, 0.4, nightK));
        drawPlane(ctx, cloud.canvas, px0, py0, look);
      }
      ctx.globalAlpha = 1;
    }

    // the land, far to near, with the mist that lies between the planes — composed once and kept
    // while nothing moves (the camera and the mist's slow breathing are what move it)
    const bloomAmt = pal.byMoon ? 0 : clamp01(pal.air.glowAmt * 1.3) * smoothstep(-7, -1, pal.altDeg) * (1 - 0.7 * smoothstep(6, 20, pal.altDeg)) * (pal.dark ? 1 : 0.5);
    const open = state.event && state.event.kind === 'open' && !state.reduceMotion ? state.event.age : null;
    const breath = (band) => (time == null ? 0 : Math.round((band.pools ? 7 : 16) * Math.sin(TAU * (time / (240 + 37 * band.seed) + band.seed * 0.37)) * 4) / 4);
    const tree = treeShown(state, look);
    const shade = cardShade(state, pal);
    // (with a shade the land is always composed aside — the shade lies on the land alone — the opening's
    // frames too; they are then keyed by the instant and painted afresh each time)
    if (open == null || shade) {
      const key = [keys.land, look.toFixed(5), tilt.x, tilt.y, Math.round(sunNow.x * 4), Math.round(bloomAmt * 50),
        G.planes.map((p) => (p.mists ?? []).map(breath).join(',')).join(';'), Math.round(tree * 1000), shade ? shade.key : '', open == null ? '' : open].join('|');
      if (!G.landCache) G.landCache = { key: '', canvas: mk(G.pxW, G.pxH) };
      if (G.landCache.key !== key) {
        const lc = G.landCache.canvas.getContext('2d');
        lc.setTransform(1, 0, 0, 1, 0, 0);
        lc.globalCompositeOperation = 'source-over';
        lc.globalAlpha = 1;
        lc.clearRect(0, 0, G.pxW, G.pxH);
        drawLand(lc, pal, look, tilt, breath, open, sunNow, bloomAmt, tree);
        if (shade) layCardShade(lc, shade);
        G.landCache.key = key;
      }
      ctx.filter = adj;
      ctx.drawImage(G.landCache.canvas, 0, 0);
      ctx.filter = 'none';
    } else {
      ctx.filter = adj;
      drawLand(ctx, pal, look, tilt, breath, open, sunNow, bloomAmt, tree);
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
      // THE GLARE LIES ON THE LAND ONLY WHILE THE SUN STANDS CLEAR OF IT. While the whole disc is in
      // the sky with 0.6 of its radius of sky, or more, under its lower limb (its centre 1.6 radii over
      // the skyline: at the signature minute it is 1.9), light spills round what stands in front of it
      // — the tree, the ridge under it — as it always did. As the disc comes down onto the far ridge the
      // spill withdraws to the sky, and to what stands against the sky (the crown), and has left the
      // land by the time the centre is 0.6 radii over the skyline: a sun that is half behind a hill
      // cannot throw a round bloom on the near side of that hill — that is a camera's glare. There the
      // ridge's rim and the mist carry the light (the haze under the sun, drawLand, is level and wide).
      const onLand = urlGlare === 'old' ? 1 : smoothstep(0.6 * c.sunR, 1.6 * c.sunR, G.skyline(pal.sunRest.x) - pal.sunRest.y);
      const box = [sunNow.x * s - r, sunNow.y * s - r, 2 * r, 2 * r];
      if (onLand >= 1) ctx.fillRect(...box);
      else {
        // (`onLand` of the gradient everywhere; the rest only above the skyline, let go over the 10 pt
        // under it so that the trunk, which stands across that line, carries no step. That part is
        // painted ONCE, aside, and its foot taken off it there — five thin lays of the gradient itself
        // added up the canvas's own rounding to six levels of noise, different on the cover and the spread.)
        if (onLand > 0) { ctx.globalAlpha = onLand; ctx.fillRect(...box); }
        const bx0 = Math.floor(box[0]) - 2, by0 = Math.floor(box[1]) - 2, bw = Math.ceil(box[2]) + 5;
        const gl = scratch('glare', bw, bw);
        gl.translate(-bx0, -by0);
        gl.fillStyle = g;
        gl.fillRect(...box);
        gl.globalCompositeOperation = 'destination-out';
        gl.fillStyle = 'rgba(0,0,0,0.2)';
        const x0 = sunNow.x - r / s - 4, x1 = sunNow.x + r / s + 4;
        const line = [];
        for (let x = x0; x <= x1 + 1; x += 2) line.push([x, Math.min(G.H + 4, skylineNow(x, look, tilt))]);
        for (let lay = 0; lay < 5; lay += 1) {
          const land = new Path2D();
          land.moveTo(x0 * s, by0 + bw + 4);
          for (const [x, y] of line) land.lineTo(x * s, (y + 2.5 * lay) * s);
          land.lineTo(x1 * s, by0 + bw + 4);
          land.closePath();
          gl.fill(land);
        }
        ctx.globalAlpha = 1 - onLand;
        ctx.drawImage(gl.canvas, 0, 0, bw, bw, bx0, by0, bw, bw);
        ctx.globalAlpha = 1;
      }
      ctx.globalCompositeOperation = 'source-over';
    }
    drawLife(ctx, state, pal, time, knollOff, look, tree);

    drawTonight(ctx, state, pal, time, tonightAt, ring);
    drawSnowfall(ctx, state, pal, time);
    drawCaption(ctx, state, pal, look);
  }

  let lastState = null;
  let lookBuffer = null;
  let painted = null, lastRaw = null, lastRenderMs = 0, lastMovedMs = -1e9;
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
    // The tone is MOVING while its true value (not the stepped one) still changes from one frame to the
    // next, and for a little over a second after — long enough to bridge a plateau inside an event (the
    // bloom's hold). So the planes are painted afresh exactly once, when the tone has come to rest.
    // (Judged by the stepped tone and a third of a second, the tail of a slow settling — steps further
    // apart than the wait — went back and forth between the exact paint and a filter of 0.999.)
    const raw = { p: pal.B.presence, d: pal.B.depth };
    if (lastRaw && Math.abs(raw.p - lastRaw.p) + Math.abs(raw.d - lastRaw.d) > 1e-6) lastMovedMs = nowMs;
    const moving = nowMs - lastMovedMs < 1200;
    let adjust = null;
    if (playing && keys.base === baseKey && painted && moving && Math.abs(tone.p - painted.p) <= 0.62) {
      if (tone.p !== painted.p || tone.d !== painted.d) {
        let bright, sat;
        if (pal.dark) {
          const f = (t) => (1 - 0.12 * (1 - t.p)) * (1 - 0.14 * t.d), g = (t) => (0.4 + 0.6 * t.p) * (1 - 0.12 * t.d);
          const Lk = f(tone) / f(painted), Ck = g(tone) / g(painted);
          bright = Math.pow(Lk, 1.25); sat = Ck / Lk;
        } else {
          const c0 = lerp(0.2, 0.62, pal.air.night);
          const g = (t) => (c0 + (1 - c0) * t.p) * (1 - 0.25 * t.d);
          bright = 1 - 0.013 * (tone.d - painted.d); sat = g(tone) / g(painted);
        }
        // (No filter within 0.2 % of 1: on a near-black sky ANY brightness below 1 takes every pixel
        // down a whole code value — an 8-bit layer cannot be multiplied by 0.999.)
        const parts = [];
        if (Math.abs(bright - 1) >= 0.002) parts.push(`brightness(${bright.toFixed(4)})`);
        if (Math.abs(sat - 1) >= 0.002) parts.push(`saturate(${sat.toFixed(4)})`);
        if (parts.length) adjust = parts.join(' ');
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
    lastRaw = raw;
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
      if (pal.moonRest && state.moon.altitude > -0.01 && near(pal.moonRest, c.moonR)) burns.push({ x: pal.moonRest.x, y: pal.moonRest.y, r: c.moonR, power: (0.4 + 0.6 * pal.nightness) * smoothstep(0.1, 0.4, state.moon.fraction) * (1 - dayMoonOf(pal)) });
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

    // Every cloud's masks are cut with the first frame, for the side the lamp stands on now — the
    // looked-up view's own cloud too, which first shows a third of the way into a rise: cut there, it
    // made five canvases in the middle of the move.
    for (const cloud of G.clouds) {
      if (cloud.masks) continue;
      const cx = cloud.x, cy = c.H0 - cloud.e;
      const light = cloudLight(cloud, pal, cx, cy);
      paintCloud(cloud, pal, cx, cy, light);
      cloud.key = '';                                      // (painted again where it is, when it is first drawn)
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
      window.__skyBodies = G.bodies ?? null;
      window.__hillPainted = { timing, look, discs: G.discs ?? null, snowShade: pal.shown(pal.snowShade)[0] ** 3, tree: treeShown(state, state.reduceMotion ? Math.round(look) : look), stars: st.length ? {
        total: st.length,
        places: st.map((q) => [Math.round(q.lx * 10) / 10, Math.round(q.ly * 10) / 10, q.kind]),   // looked-up display points (anchor window's x)
        marks: G.stars.marks ?? [],                        // the four-point stars in view as last drawn: [x, y (display points, the anchor window's x), kind, how much of the mark is four-point 0 … 1]
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
