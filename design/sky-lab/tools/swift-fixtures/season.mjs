#!/usr/bin/env node
// Sky lab → Swift: the season, day by day.
//
//     node design/sky-lab/tools/swift-fixtures/season.mjs
//
// Writes TwoOfUsTests/SkyCoreFixturesSeason.swift from lab/season.js: every field of `season(state)` on
// each of the 365 days of his first year (2 July 2026 to 1 July 2027) at the lab's default place, the
// way a sky asks for it (`season(state)` on the state `buildState` makes for that date); the same for a
// spread of days south of the equator, on the 366th day of a leap year, and with the snow in the air
// told from outside.
//
// Plain node, no dependencies. Nothing in the Swift fixture is typed by hand.

import { fileURLToPath } from 'node:url';
import * as core from '../../lab/core.js';
import { season } from '../../lab/season.js';
import { table, writeSwift, isoDay } from './emit.mjs';

const DAY = 86_400_000;
const FIELDS = ['snow', 'snowfall', 'foliage', 'leafHue', 'leafFall', 'blossom', 'petals', 'fireflies', 'grass', 'frost'];
const WEIGHTS = ['winter', 'spring', 'summer', 'autumn'];

const cells = (s) => [s.name, ...WEIGHTS.map((k) => s.weights[k]), ...FIELDS.map((k) => s[k])];

/** The season state the sky's tree masks and painted planes are keyed on. The expression lives inside
 *  the sky module's closure (skies/hill-painted.js, `seaKey` in `render`), so it is repeated here, in
 *  the lab's own order: each of the seven to the nearest fortieth. */
const treeStep = (sea) => [sea.foliage, sea.blossom, sea.snow, sea.frost, sea.leafFall, sea.grass, sea.leafHue].map((v) => Math.round(v * 40));

function firstYear() {
  const rows = [];
  const steps = new Set();
  let quiet = 0, longestQuiet = 0, previous = null;
  for (let ms = Date.UTC(2026, 6, 2); ms < Date.UTC(2027, 6, 2); ms += DAY) {
    const date = isoDay(ms);
    const state = core.buildState(core.parseParams({ date }));
    const sea = season(state);
    const step = treeStep(sea);
    const key = step.join(' ');
    steps.add(key);
    quiet = key === previous ? quiet + 1 : 0;
    longestQuiet = Math.max(longestQuiet, quiet);
    previous = key;
    rows.push([date, state.dayOfYear, state.latitude, ...cells(sea), ...step]);
  }
  console.log(`  his first year: ${rows.length} days, ${steps.size} distinct tree steps, the longest run of days on one step is ${longestQuiet + 1}`);
  return table('firstYear',
    'Every day of his first year, 2 July 2026 to 1 July 2027, at the lab\'s default place: lab/season.js\n'
    + '`season(state)` on the state `buildState` makes for that date — the call the painted hill makes. The\n'
    + 'last seven columns are the step the sky keys its tree on (skies/hill-painted.js, `seaKey`: foliage,\n'
    + 'blossom, snow, frost, leaf fall, grass and leaf hue, each times 40 and rounded).',
    ['date', 'dayOfYear', 'latitude', 'name', ...WEIGHTS, ...FIELDS,
     'stepFoliage', 'stepBlossom', 'stepSnow', 'stepFrost', 'stepLeafFall', 'stepGrass', 'stepLeafHue'], rows);
}

function elsewhere() {
  const rows = [];
  const add = (label, dayOfYear, latitude, snowfall) => {
    const sea = season(dayOfYear, latitude, snowfall == null ? {} : { snowfall });
    rows.push([label, dayOfYear, latitude, snowfall ?? 'own', ...cells(sea)]);
  };
  // South of the equator the year is half a year out of step (Sydney), every eleventh day.
  for (let day = 1; day <= 365; day += 11) add('south', day, -33.8688);
  // The equator itself counts as north; a leap year's 366th day; the day before the year starts.
  add('equator', 200, 0);
  add('leap-day-366', 366, 41.88);
  add('south-leap-day-366', 366, -33.8688);
  add('day-zero', 0, 41.88);
  // The snow in the air, told from outside (the lab's `snowfall=`): taken as it is, held to 0–1, on a
  // winter day that has none of its own, on one that has, and in July.
  const winterDays = [];
  for (let day = 1; day <= 40 && winterDays.length < 2; day += 1) {
    const own = season(day, 41.88).snowfall;
    if (winterDays.length === 0 && own === 0) winterDays.push(day);
    if (winterDays.length === 1 && own > 0) winterDays.push(day);
  }
  for (const day of [...winterDays, 196]) {
    add('own-snowfall', day, 41.88);
    add('told-none', day, 41.88, 0);
    add('told-some', day, 41.88, 0.7);
    add('told-too-much', day, 41.88, 1.3);
    add('told-less-than-none', day, 41.88, -1);
  }
  return table('elsewhere',
    'lab/season.js `season(dayOfYear, latitude, { snowfall })` away from the default: south of the equator,\n'
    + 'on the equator, on the 366th day of a leap year, and with the snow in the air told from outside\n'
    + '(`snowfall` is that number, or `own` for the day\'s own roll).',
    ['label', 'dayOfYear', 'latitude', 'snowfall', 'name', ...WEIGHTS, ...FIELDS], rows);
}

writeSwift({
  file: 'SkyCoreFixturesSeason',
  script: fileURLToPath(import.meta.url),
  sources: [
    'design/sky-lab/lab/season.js     season',
    'design/sky-lab/lab/core.js       buildState (the day of the year for a date)',
    'design/sky-lab/skies/hill-painted.js   seaKey (the tree\'s step; repeated in the exporter)',
  ],
  tables: [firstYear(), elsewhere()],
});
