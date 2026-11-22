#!/usr/bin/env node
// Sky lab → Swift: the air.
//
//     node design/sky-lab/tools/swift-fixtures/air.mjs
//
// Writes TwoOfUsTests/SkyCoreFixturesAir.swift, which AirTests holds TwoOfUs/Sky/Core/Air.swift against:
// what the painted hill's own `airFor` (skies/hill-painted/air.js) answers
//
//   · for a sweep of the sun from −20° to +62° — every key of the table, the altitudes half way between
//     them, and the day above them — in both appearances, in the evening and (for fourteen of them) in
//     the morning: every colour and amount it returns, and the sky on a small grid;
//   · at the lab's eight standard hours on its default date (tools/shoot.mjs: 06:50 … 03:00 on
//     21 November 2026 in Chicago), with the hush the lab gives that hour: the sky on a close grid,
//     from left of the sun to two pages right of it and from under the horizon to past the zenith;
//   · the haze, the mist under a moon and without one, and `show` — the hush and the dimmed room —
//     for the air's own presence and for one held above it.
//
// The sky's samples are single precision in the lab (Float32Array); they are written as the shortest
// decimal that reads back to the same single, and the Swift reads them as singles.
//
// Plain node, no dependencies. Nothing in the Swift fixture is typed by hand.

import { fileURLToPath } from 'node:url';
import * as core from '../../lab/core.js';
import { presence } from '../../lab/presence.js';
import { airFor, E_STOPS } from '../../skies/hill-painted/air.js';
import { table, writeSwift } from './emit.mjs';

const flag = (b) => (b ? 1 : 0);

/** A single-precision value as the shortest decimal that reads back to it. */
function single(x) {
  if (Math.fround(x) !== x) throw new RangeError(`fixture: ${x} is not a single-precision value`);
  for (let digits = 1; digits <= 9; digits += 1) {
    const text = Number(x.toPrecision(digits));
    if (Math.fround(text) === x) return text;
  }
  throw new RangeError(`fixture: no short form for ${x}`);
}

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
const short = (rand, lo, hi) => Math.round((lo + (hi - lo) * rand()) * 1000) / 1000;

// ── the sweep ────────────────────────────────────────────────────────────
// Every key of the table (30, 15, 8, 2.5, −0.8, −4, −7.5, −11, −18), the sun's-disc keys (−3), the
// altitudes the rules turn at (−13, −10, −9.5, −7, −2, −1, 16) and the ground between and beyond.
const SWEEP = [-20, -18, -16, -14.5, -13, -12, -11, -10, -9.5, -9, -8, -7.5, -7, -6, -5, -4, -3, -2.4, -2, -1, -0.8,
  0, 1, 2, 2.5, 3.5, 5, 6, 8, 10, 11.5, 13, 15, 16, 20, 22.5, 30, 40, 50, 60, 62];
const MORNINGS = new Set([-18, -14.5, -11, -9, -7.5, -6, -4, -2.4, -0.8, 1, 2.5, 5, 8, 20]);

/** The instants of the sweep: each altitude in both appearances, evening first; some also in the morning. */
function sweep() {
  const out = [];
  for (const altDeg of SWEEP) {
    for (const dark of [true, false]) {
      out.push({ altDeg, dark, morning: false });
      if (MORNINGS.has(altDeg)) out.push({ altDeg, dark, morning: true });
    }
  }
  return out;
}

// What `airFor` returns that is a colour, and what is an amount (the Swift's names in comments there).
const COLOURS = [['sun', (a) => a.sun], ['glow', (a) => a.glow], ['rim', (a) => a.rim], ['land', (a) => a.land],
  ['mist', (a) => a.mist], ['mistFar', (a) => a.mistFar], ['ambient', (a) => a.ambient], ['silver', (a) => a.silver],
  ['lowLit', (a) => a.cloud.loLit], ['lowShade', (a) => a.cloud.loShade],
  ['highLit', (a) => a.cloud.hiLit], ['highShade', (a) => a.cloud.hiShade]];
const AMOUNTS = [['night', (a) => a.night], ['day', (a) => a.day], ['lastLight', (a) => a.lastLight],
  ['glowAmount', (a) => a.glowAmt], ['rimAmount', (a) => a.rimAmt], ['gain', (a) => a.gain],
  ['lowAmount', (a) => a.cloud.loAmt], ['highAmount', (a) => a.cloud.hiAmt]];

function instants() {
  const rows = sweep().map(({ altDeg, dark, morning }) => {
    const air = airFor({ altDeg, dark, morning, presence: 0.3, depth: 0 });
    return [altDeg, flag(dark), flag(morning), ...AMOUNTS.map(([, get]) => get(air)), ...COLOURS.flatMap(([, get]) => [...get(air)])];
  });
  return table('instants',
    'Everything `airFor({ altDeg, dark, morning, presence: 0.3, depth: 0 })` returns that is an amount or\n'
    + 'a colour (each colour as OKLab L, a, b; `ambient` is single precision in the lab). `dark` and\n'
    + '`morning` are 1 or 0.',
    ['altitude', 'dark', 'morning', ...AMOUNTS.map(([name]) => name), ...COLOURS.flatMap(([name]) => [`${name}L`, `${name}A`, `${name}B`])], rows);
}

// ── the sky ──────────────────────────────────────────────────────────────

/** One row per instant and dx: the sky at each elevation of `es`, three singles each. */
function skyRows(label, air, dxs, es, lead) {
  return dxs.map((dx) => [...lead, dx, ...es.flatMap((e) => air.skyAt(dx, e).map(single))]);
}
const skyColumns = (es) => es.flatMap((_, i) => [`L${i}`, `a${i}`, `b${i}`]);

const SWEEP_DX = [-0.7, 0, 0.35, 1.1, 2.1];
const SWEEP_E = [0, 0.07, 0.29, 0.8, 1, 1.7];

function skySweep() {
  const rows = sweep().flatMap(({ altDeg, dark, morning }) => skyRows('', airFor({ altDeg, dark, morning, presence: 0.3, depth: 0 }),
    SWEEP_DX, SWEEP_E, [altDeg, flag(dark), flag(morning)]));
  return [
    table('skySweepElevations', 'The elevations (table units) the columns of `skySweep` stand at, in order.', ['e'], SWEEP_E.map((e) => [e])),
    table('skySweep',
      '`airFor(…).skyAt(dx, e)` through the sweep: the sky `dx` anchor-widths from the sun at each of\n'
      + '`skySweepElevations`, as OKLab L, a, b — single precision, as the lab keeps a sample.',
      ['altitude', 'dark', 'morning', 'dx', ...skyColumns(SWEEP_E)], rows),
  ];
}

const HOURS = ['06:50', '09:30', '12:30', '16:10', '16:40', '17:30', '21:00', '03:00'];   // tools/shoot.mjs, DEFAULT_TIMES
const HOURS_DX = [-1.4, -0.6, -0.25, -0.05, 0, 0.1, 0.3, 0.62, 0.95, 1.35, 2.4];
// Every stop of a column (air.js, E_STOPS), the elevations the haze and the ambient are read at, between
// the stops, under the horizon and past the zenith.
const HOURS_E = [...new Set([-0.2, ...E_STOPS, 0.012, 0.27, 0.55, 0.86, 1.2, 1.9, 2.6])].sort((a, b) => a - b);

/** The air's inputs at one of the lab's standard hours, as the lab's own state has them. */
function hour(time, scheme) {
  const state = core.buildState(core.parseParams({ time, scheme }));
  const altDeg = state.sun.altitude / (Math.PI / 180);
  const morning = state.sun.isNight ? state.sun.progress > 0.5 : state.sun.progress < 0.5;
  const b = presence(state);
  return { time, altDeg, dark: scheme !== 'light', morning, presence: b.presence, depth: b.depth };
}

function skyHours() {
  const hours = [];
  const rows = [];
  for (const time of HOURS) {
    for (const scheme of ['dark', 'light']) {
      const h = hour(time, scheme);
      hours.push([time, flag(h.dark), h.altDeg, flag(h.morning), h.presence, h.depth]);
      rows.push(...skyRows('', airFor(h), HOURS_DX, HOURS_E, [time, flag(h.dark)]));
    }
  }
  return [
    table('hours',
      'The lab\'s eight standard hours (tools/shoot.mjs) on its default date and place, in each appearance:\n'
      + 'the sun\'s altitude in degrees, whether it is on its way up, and the hush and the room\'s depth\n'
      + 'the lab gives that hour (lab/core.js `buildState`, lab/presence.js `presence`).',
      ['time', 'dark', 'altitude', 'morning', 'presence', 'depth'], hours),
    table('skyHoursElevations', 'The elevations (table units) the columns of `skyHours` stand at, in order.', ['e'], HOURS_E.map((e) => [e])),
    table('skyHours',
      '`airFor(…).skyAt(dx, e)` at each of `hours`: the sky `dx` anchor-widths from the sun at each of\n'
      + '`skyHoursElevations`, as OKLab L, a, b — single precision.',
      ['time', 'dark', 'dx', ...skyColumns(HOURS_E)], rows),
  ];
}

// ── the haze, the mist ───────────────────────────────────────────────────

function haze() {
  const rows = [];
  for (const { altDeg, dark, morning } of sweep()) {
    if (morning) continue;
    const air = airFor({ altDeg, dark, morning, presence: 0.3, depth: 0 });
    for (const dx of [-0.9, -0.06, 0, 0.45, 1.2, 2]) rows.push([altDeg, flag(dark), dx, ...air.hazeAt(dx)]);
  }
  return table('haze',
    '`airFor(…).hazeAt(dx)` through the sweep (evening): the air between the ridges `dx` anchor-widths\n'
    + 'from the sun, as OKLab L, a, b.',
    ['altitude', 'dark', 'dx', 'L', 'a', 'b'], rows);
}

function mist() {
  const rows = [];
  for (const altDeg of [-18, -12, -9.5, -7.5, -4, -0.8, 2.5, 8, 30]) {
    for (const dark of [true, false]) {
      for (const moonlight of [0, 0.35, 1]) {
        const air = airFor({ altDeg, dark, morning: altDeg === -4, presence: 0.3, depth: 0, moonlight });
        for (const [dxLight, dxSun] of [[0, 0], [-0.3, -0.3], [0.5, -1.2], [1.6, 0.4]]) {
          rows.push([altDeg, flag(dark), flag(altDeg === -4), moonlight, dxLight, dxSun, ...air.mistAt(dxLight, dxSun)]);
        }
      }
    }
  }
  return table('mist',
    '`airFor({ …, moonlight }).mistAt(dxLight, dxSun)`: mist `dxLight` anchor-widths from the light it\n'
    + 'answers and `dxSun` from the sun, with no moon, some moon and a full one high up.',
    ['altitude', 'dark', 'morning', 'moonlight', 'dxLight', 'dxSun', 'L', 'a', 'b'], rows);
}

// ── the hush and the dimmed room ─────────────────────────────────────────

function shown() {
  const rand = seeded(1612);
  const rows = [];
  // (presence, depth): hushed, the lab's own rest, itself; asleep for the night, a nap; and presences
  // outside 0–1, which `airFor` holds.
  const tones = [[0, 0], [0.35, 0], [1, 0], [0.2, 1], [0.6, 0.45], [1.4, 0], [-0.2, 0.3]];
  for (const altDeg of [30, 5, -3, -8.5, -11.5, -18]) {
    for (const dark of [true, false]) {
      for (const [p, depth] of tones) {
        const air = airFor({ altDeg, dark, morning: false, presence: p, depth });
        for (const held of ['own', 0.6, 0.82]) {
          const lab = [short(rand, 0.05, 1.1), short(rand, -0.12, 0.12), short(rand, -0.12, 0.12)];
          // (the tree, the water, a cloud and the sun's halo ask for `Math.max(air.presence, 0.6)` and the like)
          const out = held === 'own' ? air.show(lab) : air.show(lab, { presence: Math.max(air.presence, held) });
          rows.push([altDeg, flag(dark), p, depth, held, air.presence, ...lab, ...out]);
        }
      }
    }
  }
  return table('shown',
    '`airFor({ altDeg, dark, presence, depth }).show(lab)` — a colour as it is shown, through the hush and\n'
    + 'the dimmed room — for the air\'s own presence (`held` is `own`) and for one held above the hush, as\n'
    + 'the painter asks it: `show(lab, { presence: Math.max(air.presence, held) })`. `airPresence` is the\n'
    + 'presence the air kept (held to 0–1).',
    ['altitude', 'dark', 'presence', 'depth', 'held', 'airPresence', 'L', 'a', 'b', 'outL', 'outA', 'outB'], rows);
}

writeSwift({
  file: 'SkyCoreFixturesAir',
  script: fileURLToPath(import.meta.url),
  sources: [
    'design/sky-lab/skies/hill-painted/air.js    airFor: its colours and amounts, skyAt, hazeAt, mistAt, show',
    'design/sky-lab/lab/core.js                  buildState (the sun at the standard hours)',
    'design/sky-lab/lab/presence.js              presence (the hush at those hours)',
  ],
  tables: [instants(), ...skySweep(), ...skyHours(), haze(), mist(), shown()],
});
