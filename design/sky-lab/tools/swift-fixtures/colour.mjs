#!/usr/bin/env node
// Sky lab → Swift: colour.
//
//     node design/sky-lab/tools/swift-fixtures/colour.mjs
//
// Writes TwoOfUsTests/SkyCoreFixturesColour.swift, which OKLabTests holds TwoOfUs/Sky/Core/OKLab.swift
// against: what the lab's OWN colour functions make of a few thousand colours, each way.
//
//   · lab/oklab.js                 hex, toOklab, toOklch, fromOklab, fromOklch, mixOk, rampOk, css,
//                                  smoothstep, lerp
//   · skies/hill-painted/air.js    lch, mix3, toRgb, css, luminance — the painted hill's own
//   · skies/hill-painted.js        heldTo
//
// The colours are drawn from a seeded generator, so the file comes out the same, byte for byte, every
// time; a few are set by hand below where a rule has an edge (black, white, a light above white, a
// colour exactly at a limit). Inputs are written short (a six-digit hex, three decimals) and the
// lab's answers in full.
//
// Plain node, no dependencies. Nothing in the Swift fixture is typed by hand.

import { fileURLToPath } from 'node:url';
import * as oklab from '../../lab/oklab.js';
import * as air from '../../skies/hill-painted/air.js';
import { heldTo } from '../../skies/hill-painted.js';
import { table, writeSwift } from './emit.mjs';

// ── a seeded generator (mulberry32), so a rerun writes the same file ─────
function seeded(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
/** A number in lo … hi with three decimals: short to write, and exactly what both sides read. */
const short = (rand, lo, hi) => Math.round((lo + (hi - lo) * rand()) * 1000) / 1000;
const hex6 = (value) => value.toString(16).padStart(6, '0');
const randomHex = (rand) => Math.floor(rand() * 0x1000000);
const rgbOf = (c) => [c.r, c.g, c.b];
const labOf = (c) => [c.L, c.a, c.b];
/** The three levels in a canvas colour, `rgba(r, g, b, alpha)`. */
const levels = (text) => text.match(/^rgba\((\d+),\s*(\d+),\s*(\d+),/).slice(1, 4).map(Number);

const EDGES = [0x000000, 0xffffff, 0xff0000, 0x00ff00, 0x0000ff, 0xffff00, 0x00ffff, 0xff00ff,
  0x010101, 0x0a0a0a, 0x0b0b0b, 0x808080, 0xf2f2f7, 0x1c1c1e, 0x6c6c70, 0x98989f];

// ── lab/oklab.js ─────────────────────────────────────────────────────────

function fromSRGB() {
  const rand = seeded(20260702);
  const rows = [];
  const add = (value) => rows.push([hex6(value), ...labOf(oklab.toOklab(oklab.hex(value)))]);
  EDGES.forEach(add);
  for (let i = 0; i < 1500; i += 1) add(randomHex(rand));
  return table('fromSRGB',
    'A display colour → OKLab: lab/oklab.js `toOklab(hex(…))`. The first sixteen are set by hand (black,\n'
    + 'white, the six corners, the darkest greys either side of the gamma curve\'s knee, the app\'s page,\n'
    + 'card and grey text); the rest are drawn at random.',
    ['hex', 'L', 'a', 'b'], rows);
}

function oklch() {
  const rand = seeded(1433);
  const rows = [];
  for (const value of [...EDGES, ...Array.from({ length: 284 }, () => randomHex(rand))]) {
    const c = oklab.toOklch(oklab.hex(value));
    rows.push([hex6(value), c.L, c.C, c.h]);
  }
  return table('oklch',
    'A display colour → lightness, chroma, hue in radians: lab/oklab.js `toOklch(hex(…))`.',
    ['hex', 'L', 'C', 'h'], rows);
}

/** OKLab colours to bring back: half of them quiet enough to fit a display, half wherever. */
function labs(rand, count) {
  const out = [
    [0, 0, 0], [1, 0, 0], [0.5, 0, 0], [1.2, 0.03, 0.02], [1.9, 0.085, 0.01], [-0.1, 0.05, -0.02],
    [0.7, 0.4, 0.1], [0.3, -0.3, 0.2], [0.6, 0.1, -0.35], [0.999, 0.002, 0.001], [0.001, 0, 0.001],
  ];
  while (out.length < count) {
    out.push(out.length % 2
      ? [short(rand, 0.02, 0.99), short(rand, -0.09, 0.09), short(rand, -0.09, 0.09)]
      : [short(rand, -0.1, 1.3), short(rand, -0.42, 0.42), short(rand, -0.42, 0.42)]);
  }
  return out;
}

function toSRGB() {
  const rows = labs(seeded(905), 1500).map((lab) => [...lab, ...rgbOf(oklab.fromOklab({ L: lab[0], a: lab[1], b: lab[2] }))]);
  return table('toSRGB',
    'OKLab → a display colour, by the lab\'s own fit: lab/oklab.js `fromOklab`. A colour no display can\n'
    + 'show gives up chroma, never hue, in eighteen halvings.',
    ['L', 'a', 'b', 'red', 'green', 'blue'], rows);
}

function fromOklch() {
  const rand = seeded(77);
  const rows = [];
  for (let i = 0; i < 200; i += 1) {
    const lch = [short(rand, 0, 1.1), short(rand, 0, 0.3), short(rand, -4, 7)];
    rows.push([...lch, ...rgbOf(oklab.fromOklch({ L: lch[0], C: lch[1], h: lch[2] }))]);
  }
  return table('fromOklch',
    'Lightness, chroma, hue in radians → a display colour: lab/oklab.js `fromOklch`.',
    ['L', 'C', 'h', 'red', 'green', 'blue'], rows);
}

function mixOk() {
  const rand = seeded(4099);
  const rows = [];
  // Blue to orange, the lab's own example of why: through rose and lilac, never grey-green.
  for (let i = 0; i <= 10; i += 1) rows.push(['2f6fde', 'f28c28', i / 10, ...rgbOf(oklab.mixOk(oklab.hex(0x2f6fde), oklab.hex(0xf28c28), i / 10))]);
  for (let i = 0; i < 290; i += 1) {
    const a = randomHex(rand), b = randomHex(rand);
    const t = i % 9 === 0 ? short(rand, -0.5, 1.5) : short(rand, 0, 1);   // some past either end: `t` is held to 0–1
    rows.push([hex6(a), hex6(b), t, ...rgbOf(oklab.mixOk(oklab.hex(a), oklab.hex(b), t))]);
  }
  return table('mixOk',
    'The perceptual mix of two display colours: lab/oklab.js `mixOk(hex(a), hex(b), t)`.',
    ['a', 'b', 't', 'red', 'green', 'blue'], rows);
}

// A ramp like a sky's: night blue, lilac, ember, gold, pale day (with two stops on one position).
const RAMP = [[0, 0x1c1c3a], [0.2, 0x6a5fa8], [0.45, 0xe8734a], [0.45, 0xf2b25c], [0.8, 0xfbe9c8], [1, 0xf2f2f7]];

function ramp() {
  const stops = RAMP.map(([at, value]) => [at, oklab.hex(value)]);
  const rows = [];
  for (let i = -4; i <= 44; i += 1) {
    const x = i / 40;
    rows.push([x, ...rgbOf(oklab.rampOk(stops, x))]);
  }
  return [
    table('rampStops', 'The stops of the ramp sampled in `ramp`: a position and a colour each.', ['at', 'hex'],
      RAMP.map(([at, value]) => [at, hex6(value)])),
    table('ramp',
      'A colour along `rampStops`: lab/oklab.js `rampOk(stops, x)`, from before the first stop to past the last.',
      ['x', 'red', 'green', 'blue'], rows),
  ];
}

function levelsOfSRGB() {
  const rand = seeded(255);
  const rows = [];
  const add = (c) => rows.push([c.r, c.g, c.b, ...levels(oklab.css(c))]);
  // Each level's lower edge (a half goes up), then colours a little outside 0–1, then anything.
  for (const level of [0, 1, 2, 127, 128, 254, 255]) add({ r: (level - 0.5) / 255, g: level / 255, b: (level + 0.5) / 255 });
  for (let i = 0; i < 30; i += 1) add({ r: short(rand, -0.2, 1.2), g: short(rand, -0.2, 1.2), b: short(rand, -0.2, 1.2) });
  for (let i = 0; i < 160; i += 1) add({ r: rand(), g: rand(), b: rand() });
  return table('levels',
    'A display colour as eight-bit levels: the three numbers in lab/oklab.js `css(c)`.',
    ['red', 'green', 'blue', 'redLevel', 'greenLevel', 'blueLevel'], rows);
}

function smoothstepAndLerp() {
  const rand = seeded(31);
  const steps = [];
  // The sky's own edges, ascending and DESCENDING (smoothstep(0.2, 0.04, haze) is in the land's painter).
  for (const [a, b] of [[0, 1], [-13, -7], [2.5, 10], [-10.5, -4.5], [0.2, 0.04], [9, 24], [-1.5, 2.5], [0.95, 1.9]]) {
    for (let i = -2; i <= 12; i += 1) {
      const x = a + (b - a) * (i / 10);
      steps.push([a, b, x, oklab.smoothstep(a, b, x)]);
    }
  }
  for (let i = 0; i < 40; i += 1) {
    const a = short(rand, -20, 20), b = a + short(rand, 0.5, 30) * (i % 4 === 0 ? -1 : 1), x = short(rand, -30, 40);
    steps.push([a, b, x, oklab.smoothstep(a, b, x)]);
  }
  const lerps = [];
  for (let i = 0; i < 60; i += 1) {
    const a = short(rand, -2, 2), b = short(rand, -2, 2), t = i % 5 === 0 ? short(rand, -0.5, 1.5) : short(rand, 0, 1);
    lerps.push([a, b, t, oklab.lerp(a, b, t)]);
  }
  return [
    table('smoothstep',
      'lab/oklab.js `smoothstep(a, b, x)`: 0 at `a`, 1 at `b`, eased, held outside — also where `a` is the\n'
      + 'greater of the two, which the sky uses for an amount that falls as `x` rises.',
      ['a', 'b', 'x', 'value'], steps),
    table('lerp', 'lab/oklab.js `lerp(a, b, t)`: not held to 0–1.', ['a', 'b', 't', 'value'], lerps),
  ];
}

// ── skies/hill-painted/air.js: the painted hill's own ────────────────────

function skySRGB() {
  const rows = labs(seeded(1210), 900).map((lab) => [...lab, ...air.toRgb(lab), air.luminance(lab), ...levels(air.css(lab))]);
  return table('skySRGB',
    'OKLab → a display colour, by the painted hill\'s fit: skies/hill-painted/air.js `toRgb` (lightness held\n'
    + 'to 0–1, chroma given up in fourteen halvings); then `luminance` of the same colour (WCAG, with no\n'
    + 'fitting), and the three levels in `css` of it.',
    ['L', 'a', 'b', 'red', 'green', 'blue', 'luminance', 'redLevel', 'greenLevel', 'blueLevel'], rows);
}

function lch() {
  const rand = seeded(360);
  const rows = [];
  // The table's own hues first, then anything.
  for (const h of [0, 36, 40, 90, 95, 180, 235, 262, 270, 318, 360]) rows.push([0.8, 0.1, h, ...air.lch(0.8, 0.1, h)]);
  for (let i = 0; i < 190; i += 1) {
    const c = [short(rand, -0.1, 1.9), short(rand, 0, 0.2), short(rand, -30, 400)];
    rows.push([...c, ...air.lch(...c)]);
  }
  return table('lch',
    'Lightness, chroma, hue IN DEGREES → OKLab, the way the air table is written: skies/hill-painted/air.js `lch`.',
    ['L', 'C', 'hueDegrees', 'outL', 'outA', 'outB'], rows);
}

function mix3() {
  const rand = seeded(3);
  const rows = [];
  for (let i = 0; i < 100; i += 1) {
    const a = [short(rand, 0, 1.2), short(rand, -0.2, 0.2), short(rand, -0.2, 0.2)];
    const b = [short(rand, 0, 1.2), short(rand, -0.2, 0.2), short(rand, -0.2, 0.2)];
    const t = i % 6 === 0 ? short(rand, -0.5, 1.5) : short(rand, 0, 1);
    rows.push([...a, ...b, t, ...air.mix3(a, b, t)]);
  }
  return table('mix3',
    'A straight mix of two OKLab colours, `t` NOT held to 0–1: skies/hill-painted/air.js `mix3`.',
    ['aL', 'aA', 'aB', 'bL', 'bA', 'bB', 't', 'outL', 'outA', 'outB'], rows);
}

// ── skies/hill-painted.js ────────────────────────────────────────────────

function held() {
  const rand = seeded(1265);
  const rows = [];
  const add = (lab, sky, up, down, own) => {
    const out = heldTo(lab, sky, up, down, own);
    rows.push([...lab, ...sky, up, down, own, ...out, out === lab ? 'untouched' : 'held']);
  };
  // tools/test-math.mjs's own cases…
  const sky = [0.30, -0.01, -0.05];
  add([0.80, 0.05, 0.10], sky, 1.3, 1.2, 0);
  add([0.80, 0.05, 0.10], sky, 1.3, 1.2, 1);
  add([0.05, 0, 0], sky, 1.3, 1.2, 0);
  add([0.33, 0, -0.04], sky, 1.3, 1.2, 0);
  add(sky, sky, 1.3, 1.3, 0);
  // …a colour of the sky's own lightness, a colour under black, a sky under black…
  add([0.30, 0.1, 0.1], sky, 1.3, 1.2, 0.5);
  add([-0.05, 0.02, 0.01], sky, 1.3, 1.2, 0.5);
  add([0.5, 0.02, 0.01], [-0.02, 0, 0], 1.3, 1.2, 0.5);
  add([0.9, 0.02, 0.01], [0.2, 0, -0.03], 0.5, 1.2, 0.2);   // an upper limit under black: it goes to black's own
  // …a colour of the sky's own lightness that is nevertheless past a limit (only a limit under 1 : 1 can say
  // so, above or below): there is no way toward the sky's value to go, and the lab hands it back as it was…
  add([0.60, 0.05, 0.02], [0.60, -0.02, -0.04], 0.8, 1.2, 0.3);
  add([0.60, 0.05, 0.02], [0.60, -0.02, -0.04], 1.3, 0.8, 0.3);
  // …and the limits the sky really asks for (the moon by day, and a cloud's four paints in each appearance).
  const asks = [[1.15, 1.15, 0.3], [1.3, 1.1, 0.15], [1.46, 1.05, 0.5], [1.5, 1.1, 0.6], [1.9, 1, 0.7],
    [1.3, 1.07, 0.5], [1.3, 1.04, 0.7], [1.3, 1.1, 0.7], [1.3, 1.02, 0.8]];
  for (let i = 0; i < 400; i += 1) {
    const [up, down, own] = asks[i % asks.length];
    add([short(rand, 0, 1.2), short(rand, -0.15, 0.15), short(rand, -0.15, 0.15)],
      [short(rand, 0.05, 1), short(rand, -0.1, 0.1), short(rand, -0.1, 0.1)], up, down, i % 31 === 0 ? short(rand, -0.5, 1.5) : own);
  }
  return table('held',
    'A colour held within a contrast of its sky: skies/hill-painted.js `heldTo(lab, sky, up, down, own)`.\n'
    + 'The last column says whether the lab handed the colour back untouched (inside both limits, or of\n'
    + 'the sky\'s own lightness) or held it.',
    ['L', 'a', 'b', 'skyL', 'skyA', 'skyB', 'up', 'down', 'own', 'outL', 'outA', 'outB', 'outcome'], rows);
}

writeSwift({
  file: 'SkyCoreFixturesColour',
  script: fileURLToPath(import.meta.url),
  sources: [
    'design/sky-lab/lab/oklab.js                 hex, toOklab, toOklch, fromOklab, fromOklch, mixOk, rampOk, css, smoothstep, lerp',
    'design/sky-lab/skies/hill-painted/air.js    lch, mix3, toRgb, css, luminance',
    'design/sky-lab/skies/hill-painted.js        heldTo',
  ],
  tables: [fromSRGB(), oklch(), toSRGB(), fromOklch(), mixOk(), ...ramp(), levelsOfSRGB(), ...smoothstepAndLerp(),
    skySRGB(), lch(), mix3(), held()],
});
