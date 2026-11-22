#!/usr/bin/env node
// Sky lab → Swift: the palette for a minute.
//
//     node design/sky-lab/tools/swift-fixtures/palette.mjs
//
// Writes TwoOfUsTests/SkyCoreFixturesPalette.swift, which HillPaletteTests holds
// TwoOfUs/Sky/Core/HillPalette.swift against: the painted hill's palette (skies/hill-painted.js,
// `resolve`) — the land's and the tree's paints, the amounts the painter turns on, and the hush —
//
//   · at the lab's eight standard hours (tools/shoot.mjs) on its default date, on the four season
//     dates of tools/review.mjs and on a day when the leaves are turning, in both appearances;
//   · through a summer's day, hour by hour (the sun from 25° under the horizon to 71° over it), through
//     a November dusk and dawn every twenty minutes, and through the last of that dusk — the sun from
//     7° to 13° down, where the night's own rules come in — every four;
//   · asleep for the night and for a nap; and on nights with a bright moon low, high and down.
//
// `resolve` lives inside the sky module's closure and is not exported. So the lab's page is opened in
// headless Chromium and the sky module is served with ONE LINE ADDED IN TRANSIT — never on disk — that
// leaves `resolve` on `globalThis.__hpPalette`. It then runs in its own closure on states the page's own
// lab/core.js builds (`buildState(parseParams(query))`), and what it returns is read out; nothing is
// re-derived here. Its answers are taken on the cover AND on the slab, and must be the same on both:
// nothing exported depends on the display's world (where the sun and the lamp stand does, and is left
// to the world's own types).
//
// Needs Playwright with Chromium (already installed for the lab's tools; never run `playwright install`
// from here). About ten seconds. Nothing in the Swift fixture is typed by hand.

import http from 'node:http';
import fsp from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { DEVICES, minutesToTime } from '../../lab/core.js';
import { table, writeSwift } from './emit.mjs';

const LAB_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const SKY_PATH = '/skies/hill-painted.js';
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json', '.png': 'image/png', '.svg': 'image/svg+xml', '.woff2': 'font/woff2' };

// ── the sky module, in transit ───────────────────────────────────────────
const PROBE_MARK = '  return { render, destroy, ready };';
const PROBE = '  globalThis.__hpPalette = { resolve };\n';

function withProbe(source) {
  const parts = source.split(PROBE_MARK);
  if (parts.length !== 2) {
    throw new Error(`hill-painted.js: expected exactly one "${PROBE_MARK.trim()}" (found ${parts.length - 1}). The sky module has changed shape: update the mark in tools/swift-fixtures/palette.mjs.`);
  }
  if (!/\n {2}function resolve\(state, look\) \{/.test(source)) throw new Error('hill-painted.js: no `resolve(state, look)` in the sky\'s closure any more.');
  return parts[0] + PROBE + PROBE_MARK + parts[1];
}

function serve(root, skySource) {
  const server = http.createServer(async (request, response) => {
    try {
      let pathname = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
      if (pathname.endsWith('/')) pathname += 'index.html';
      const file = path.resolve(root, `.${pathname}`);
      if (!file.startsWith(root + path.sep)) throw Object.assign(new Error('outside the lab'), { code: 'ENOENT' });
      const body = pathname === SKY_PATH ? Buffer.from(skySource) : await fsp.readFile(file);
      response.writeHead(200, { 'Content-Type': TYPES[path.extname(file).toLowerCase()] ?? 'application/octet-stream', 'Cache-Control': 'no-store' });
      response.end(body);
    } catch (error) {
      response.writeHead(error.code === 'ENOENT' ? 404 : 500, { 'Content-Type': 'text/plain; charset=utf-8' });
      response.end(String(error.message));
    }
  });
  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => resolve({
      origin: `http://127.0.0.1:${server.address().port}`,
      close: () => new Promise((done) => { server.closeAllConnections?.(); server.close(() => done()); }),
    }));
  });
}

// ── the minutes asked ────────────────────────────────────────────────────

const HOURS = ['06:50', '09:30', '12:30', '16:10', '16:40', '17:30', '21:00', '03:00'];   // tools/shoot.mjs, DEFAULT_TIMES
// tools/review.mjs, SEASONS — and the lab's own default day first.
const DAYS = [
  { name: 'default', date: '2026-11-21', tz: -6 },
  { name: 'autumn', date: '2026-10-15', tz: -5 },
  { name: 'winter', date: '2027-01-15', tz: -6 },
  { name: 'spring', date: '2027-04-28', tz: -5 },
  { name: 'summer', date: '2027-07-04', tz: -5 },
  // 29 September: the crown between deep green and amber (lab/season.js, leafHue about 0.66).
  { name: 'turning', date: '2026-09-29', tz: -5 },
];
const SCHEMES = ['dark', 'light'];
const every = (from, to, step) => { const out = []; for (let m = from; m <= to; m += step) out.push(minutesToTime(m)); return out; };

function minutes() {
  const out = [];
  const add = (group, day, time, more = {}) => {
    for (const scheme of SCHEMES) out.push({ group, query: { date: day.date, tz: String(day.tz), time, scheme, ...more } });
  };
  for (const day of DAYS) for (const time of HOURS) add(`hours-${day.name}`, day, time);
  for (const time of every(0, 23 * 60, 60)) add('summer-day', DAYS[4], time);
  for (const time of [...every(15 * 60 + 30, 18 * 60 + 30, 20), ...every(5 * 60 + 40, 7 * 60, 20)]) add('november-twilight', DAYS[0], time);
  for (const time of every(17 * 60 + 4, 17 * 60 + 36, 4)) add('november-last-light', DAYS[0], time);
  for (const time of ['16:40', '21:00', '03:00']) add('asleep-night', DAYS[0], time, { asleep: 'night' });
  for (const time of ['12:30', '16:10']) add('asleep-nap', DAYS[0], time, { asleep: 'nap' });
  // 24 November 2026 is a full moon: the evenings round it, early, late and before dawn.
  for (const date of ['2026-11-19', '2026-11-24', '2026-11-28']) {
    for (const time of ['18:20', '23:00', '05:10']) add('moon', { date, tz: -6 }, time);
  }
  return out;
}

// What is read out of `resolve`'s answer, in the page. Colours are OKLab [L, a, b].
const COLOURS = ['ground', 'snowLit', 'snowShade', 'frostLit', 'ink', 'inkLit', 'leafShade', 'leafBody0', 'leafBody1', 'leafBody2',
  'leafCore', 'leafLit', 'leafSky', 'leafGlow', 'blossom', 'blossomShade', 'blossomLit', 'snow', 'frost', 'lastLeaf'];
const AMOUNTS = ['nightness', 'moonlight', 'deepNight', 'lampPower', 'mistAmount', 'backlit', 'starsOut'];
// Two colours through the palette's own `shown` (the air's `show`, then the dark night's cap): one
// lighter than a card may be at night, one that is not. And the first again held above the hush, the way
// the tree's painter asks for it: `shown(lab, { presence: Math.max(air.presence, 0.82) })`.
const SHOWN = [[0.62, 0.02, -0.05], [0.15, 0.01, -0.02]];
const HELD = 0.82;

/** Runs in the page: `resolve` on the state for each query; a plain record per minute. */
async function readOut({ queries, shown, held }) {
  const core = await import('/lab/core.js');
  const DEG = Math.PI / 180;
  return queries.map((query) => {
    const state = core.buildState(core.parseParams({ sky: 'hill-painted', ...query }), 12);
    const pal = globalThis.__hpPalette.resolve(state, 0);
    const three = (lab) => [lab[0], lab[1], lab[2]];
    return {
      dayOfYear: state.dayOfYear, latitude: state.latitude, asleep: state.asleep || 'awake',
      sunNight: state.sun.isNight ? 1 : 0, sunProgress: state.sun.progress,
      altitude: pal.altDeg, morning: pal.morning ? 1 : 0,
      moon: state.moon ? [state.moon.altitude / DEG, state.moon.fraction] : null,
      bloom: { presence: pal.B.presence, solar: pal.B.solar, moon: pal.B.moon, depth: pal.B.depth, stars: pal.B.stars },
      season: [pal.sea.snow, pal.sea.frost, pal.sea.grass, pal.sea.leafHue],
      amounts: { nightness: pal.nightness, moonlight: pal.moonlight, deepNight: pal.deepNight, lampPower: pal.lamp.power,
        mistAmount: pal.mistAmt, backlit: pal.backlit, starsOut: pal.starsOut },
      lamp: pal.lamp.kind, byMoon: pal.byMoon ? 1 : 0,
      colours: { ground: three(pal.ground), snowLit: three(pal.snowLit), snowShade: three(pal.snowShade), frostLit: three(pal.frostLit),
        ink: three(pal.ink), inkLit: three(pal.inkLit), leafShade: three(pal.leafShade),
        leafBody0: three(pal.leafBody[0]), leafBody1: three(pal.leafBody[1]), leafBody2: three(pal.leafBody[2]),
        leafCore: three(pal.leafCore), leafLit: three(pal.leafLit), leafSky: three(pal.leafSky), leafGlow: three(pal.leafGlow),
        blossom: three(pal.blossom), blossomShade: three(pal.blossomShade), blossomLit: three(pal.blossomLit),
        snow: three(pal.snow), frost: three(pal.frost), lastLeaf: three(pal.lastLeaf) },
      shown: [...shown.map((lab) => three(pal.shown(lab.slice()))),
        three(pal.shown(shown[0].slice(), { presence: Math.max(pal.air.presence, held) }))],
      air: { land: three(pal.air.land), rim: three(pal.air.rim), presence: pal.air.presence, depth: pal.air.depth, moonlight: pal.air.moonlight },
    };
  });
}

async function onDisplay(browser, origin, device, queries) {
  const preset = DEVICES[device];
  const context = await browser.newContext({ viewport: { width: Math.ceil(preset.width), height: Math.ceil(preset.height) }, deviceScaleFactor: 1 });
  try {
    const page = await context.newPage();
    await page.goto(`${origin}/index.html?sky=hill-painted&device=${device}&chrome=0&dpr=1&t=12`, { waitUntil: 'load', timeout: 60000 });
    await page.waitForFunction(() => window.__labReady === true || Boolean(window.__labError), null, { timeout: 60000 });
    const error = await page.evaluate(() => window.__labError ?? null);
    if (error) throw new Error(`the lab's page: ${error}`);
    if (!(await page.evaluate(() => typeof globalThis.__hpPalette?.resolve === 'function'))) throw new Error('the probe did not reach the page');
    return await page.evaluate(readOut, { queries, shown: SHOWN, held: HELD });
  } finally {
    await context.close();
  }
}

async function main() {
  const require = createRequire(import.meta.url);
  const { chromium } = require('playwright');
  const asked = minutes();
  const server = await serve(LAB_ROOT, withProbe(await fsp.readFile(path.join(LAB_ROOT, SKY_PATH), 'utf8')));
  const browser = await chromium.launch();
  let cover, slab;
  try {
    cover = await onDisplay(browser, server.origin, 'cover', asked.map((m) => m.query));
    slab = await onDisplay(browser, server.origin, 'iphone', asked.map((m) => m.query));
  } finally {
    await browser.close();
    await server.close();
  }
  if (JSON.stringify(cover) !== JSON.stringify(slab)) throw new Error('the palette is not the same on the cover and on the slab: something exported depends on the display\'s world');

  const rows = asked.map(({ group, query }, i) => {
    const r = cover[i];
    return [group, query.date, query.time, query.scheme === 'dark' ? 1 : 0, r.asleep, r.dayOfYear, r.latitude,
      r.sunNight, r.sunProgress, r.altitude, r.morning, ...(r.moon ?? ['down', 'down']),
      r.bloom.presence, r.bloom.solar, r.bloom.moon, r.bloom.depth, r.bloom.stars, ...r.season,
      ...AMOUNTS.map((name) => r.amounts[name]), r.lamp, r.byMoon,
      ...COLOURS.flatMap((name) => r.colours[name]), ...r.shown.flat(),
      ...r.air.land, ...r.air.rim, r.air.presence, r.air.depth, r.air.moonlight];
  });
  const groups = [...new Set(asked.map((m) => m.group))];
  console.log(`  ${rows.length} minutes in ${groups.length} groups (${groups.join(', ')}); the same on the cover and on the slab`);
  const altitudes = cover.map((r) => r.altitude);
  console.log(`  the sun from ${Math.min(...altitudes).toFixed(1)}° to ${Math.max(...altitudes).toFixed(1)}°; a moon up in ${cover.filter((r) => r.moon).length} of them, lighting the land in ${cover.filter((r) => r.byMoon).length}`);

  const columns = ['group', 'date', 'time', 'dark', 'asleep', 'dayOfYear', 'latitude', 'sunNight', 'sunProgress', 'altitude', 'morning',
    'moonAltitude', 'moonFraction', 'presence', 'solarBloom', 'moonBloom', 'depth', 'stars',
    'seasonSnow', 'seasonFrost', 'seasonGrass', 'seasonLeafHue',
    ...AMOUNTS, 'lamp', 'byMoon',
    ...COLOURS.flatMap((name) => [`${name}L`, `${name}A`, `${name}B`]),
    'shownAL', 'shownAA', 'shownAB', 'shownBL', 'shownBA', 'shownBB', 'shownHeldL', 'shownHeldA', 'shownHeldB',
    'airLandL', 'airLandA', 'airLandB', 'airRimL', 'airRimA', 'airRimB', 'airPresence', 'airDepth', 'airMoonlight'];
  writeSwift({
    file: 'SkyCoreFixturesPalette',
    script: fileURLToPath(import.meta.url),
    sources: [
      'design/sky-lab/skies/hill-painted.js   resolve (the palette for a minute), run in the lab\'s own page',
      'design/sky-lab/lab/core.js             buildState (the state for each minute)',
      'design/sky-lab/lab/presence.js         presence (the hush: `resolve` keeps it as `B`)',
    ],
    tables: [
      table('shownColours',
        'The two colours each row of `minutes` shows through the palette (`shownA…`, `shownB…`): OKLab L, a, b.\n'
        + `The first is shown once more held above the hush (\`shownHeld…\`), at a presence of at least ${HELD}.`,
        ['L', 'a', 'b'], SHOWN),
      table('minutesColumns', 'The names of the columns of `minutes`, in order: one row.', columns.map((_, i) => `c${i}`), [columns]),
      table('minutes',
        'The painted hill\'s palette, minute by minute: skies/hill-painted.js `resolve(state, 0)` on the state\n'
        + 'lab/core.js builds for the date, time, appearance and sleep of each row (Chicago, the lab\'s place).\n'
        + '  · what it was given: the day of the year and the latitude (the season\'s), whether the sun is\n'
        + '    down and how far through the day or night it is (`sunNight`, `sunProgress`), its altitude in\n'
        + '    degrees and whether it is on its way up, the moon\'s altitude in degrees and lit fraction\n'
        + '    (`down` while it is under the horizon);\n'
        + '  · the hush the lab gives the minute (lab/presence.js: presence, the sun\'s bloom, the moon\'s,\n'
        + '    the room\'s depth, how far the stars are out) and four of the season\'s amounts as it used them;\n'
        + '  · its amounts, which light the land answers (`lamp`: sun or moon; `byMoon` 1 or 0), every paint as\n'
        + '    OKLab L, a, b, the two `shownColours` through its `shown` (and the first held above the hush:\n'
        + '    `shown(lab, { presence: Math.max(air.presence, 0.82) })`), and the air it was mixed in (the\n'
        + '    land\'s tone, the rim, and the presence, depth and moonlight the air was asked with).',
        columns, rows),
    ],
  });
}

main().catch((error) => {
  process.stderr.write(`palette: ${String(error.message ?? error).split('\n')[0]}\n`);
  process.exit(1);
});
