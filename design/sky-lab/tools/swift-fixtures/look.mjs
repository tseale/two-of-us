#!/usr/bin/env node
// Sky lab → Swift: how far the camera has looked up, through each event.
//
//     node design/sky-lab/tools/swift-fixtures/look.mjs
//
// Writes TwoOfUsTests/SkyCoreFixturesLook.swift. `look` is worked out inside the sky module's closure
// (skies/hill-painted.js, `lookOf`), so this exporter runs the lab's own page in headless Chromium, as
// tools/film.mjs does: the viewer is frozen and stepped through `window.__lab.set`, and after each frame
// the value the sky itself used is read from `window.__hillPainted.look`. Nothing is re-derived here.
//
// Needs Playwright with Chromium (already installed for the lab's tools; never run `playwright install`
// from here). About a minute. Nothing in the Swift fixture is typed by hand.

import http from 'node:http';
import fsp from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { DEVICES, parseParams, buildState, minutesToTime, FIRST_LIGHT_DEG } from '../../lab/core.js';
import { MOMENT } from '../../lab/presence.js';
import { table, writeSwift } from './emit.mjs';

const LAB_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json', '.png': 'image/png', '.svg': 'image/svg+xml', '.woff2': 'font/woff2' };

function serve(root) {
  const server = http.createServer(async (request, response) => {
    try {
      let pathname = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
      if (pathname.endsWith('/')) pathname += 'index.html';
      const file = path.resolve(root, `.${pathname}`);
      if (!file.startsWith(root + path.sep)) throw Object.assign(new Error('outside the lab'), { code: 'ENOENT' });
      const body = await fsp.readFile(file);
      response.writeHead(200, { 'Content-Type': TYPES[path.extname(file).toLowerCase()] ?? 'application/octet-stream' });
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

/** First light on the lab's default date: the first local minute of the morning with the sun over the
 *  lab's threshold (tools/film.mjs's own way of finding the minute `settle` plays at). */
function firstLightMinute(query) {
  for (let m = 0; m < 12 * 60; m += 1) {
    const state = buildState(parseParams({ ...query, time: minutesToTime(m) }));
    const morning = state.sun.isNight ? state.sun.progress > 0.5 : state.sun.progress < 0.5;
    if (morning && state.sun.altitude * 180 / Math.PI >= FIRST_LIGHT_DEG) return minutesToTime(m);
  }
  throw new Error('no first light on the default date');
}

// Each event as the lab's films play it, on the display named, from its first frame.
const PLAYS = [
  { label: 'arrive', device: 'cover', event: 'arrive', time: '19:40', seconds: 2.8, step: 0.1 },
  { label: 'settle', device: 'cover', event: 'settle', time: null, seconds: 3.0, step: 0.1 },
  { label: 'bedtime-duo', device: 'cover', event: 'bedtime', time: '19:40', seconds: 2.7, step: 0.1 },
  { label: 'bedtime-slab', device: 'iphone', event: 'bedtime', time: '19:40', seconds: 3.0, step: 0.1 },
  { label: 'arrive-reduced', device: 'cover', event: 'arrive', time: '19:40', seconds: 0.8, step: 0.05, motion: '0' },
  { label: 'settle-reduced', device: 'cover', event: 'settle', time: null, seconds: 0.8, step: 0.05, motion: '0' },
];

async function main() {
  const require = createRequire(import.meta.url);
  const { chromium } = require('playwright');
  const server = await serve(LAB_ROOT);
  const browser = await chromium.launch();
  const rows = [];
  try {
    for (const play of PLAYS) {
      const query = {
        sky: 'hill-painted', device: play.device, scheme: 'dark', asleep: 'night', chrome: '0', dpr: '1', t: '12',
        event: play.event, eventAge: '0', ...(play.motion ? { motion: play.motion } : {}),
      };
      query.time = play.time ?? firstLightMinute(query);
      const preset = DEVICES[play.device];
      const context = await browser.newContext({ viewport: { width: Math.ceil(preset.width), height: Math.ceil(preset.height) }, deviceScaleFactor: 1 });
      const page = await context.newPage();
      const search = new URLSearchParams(query).toString().replace(/%3A/gi, ':');
      await page.goto(`${server.origin}/index.html?${search}`, { waitUntil: 'load', timeout: 60000 });
      await page.waitForFunction(() => window.__labReady === true || Boolean(window.__labError), null, { timeout: 60000 });
      const frames = Math.round(play.seconds / play.step);
      for (let i = 0; i <= frames; i += 1) {
        const age = Math.round(i * play.step * 1000) / 1000;
        await page.evaluate((patch) => window.__lab.set(patch), { eventAge: age, t: 12 + age });
        const seen = await page.evaluate(() => ({
          error: window.__labError, look: window.__hillPainted?.look,
          kind: window.__lab.state.event?.kind ?? null, age: window.__lab.state.event?.age ?? null,
          note: window.__lab.state.eventNote ?? null,
        }));
        if (seen.error) throw new Error(`${play.label} at ${age} s: ${seen.error}`);
        if (seen.kind !== play.event || seen.note) throw new Error(`${play.label}: the lab plays this as ${seen.kind} (${seen.note ?? 'no note'})`);
        if (typeof seen.look !== 'number' || seen.age !== age) throw new Error(`${play.label} at ${age} s: no look for that frame`);
        rows.push([play.label, age, seen.look]);
      }
      await context.close();
      console.log(`  ${play.label}: ${frames + 1} frames at ${query.time} on the ${play.device}`);
    }
  } finally {
    await browser.close();
    await server.close();
  }

  writeSwift({
    file: 'SkyCoreFixturesLook',
    script: fileURLToPath(import.meta.url),
    sources: [
      'design/sky-lab/skies/hill-painted.js   lookOf, read from the running page (window.__hillPainted.look)',
      'design/sky-lab/lab/presence.js         MOMENT.rise',
    ],
    tables: [
      table('look',
        'How far the camera has looked up, 0 on the hill … 1 up, `age` seconds into each event as the lab\'s own\n'
        + 'page plays it (skies/hill-painted.js, `lookOf`): a night sleep arriving from elsewhere, first light,\n'
        + 'and the bedtime moment\'s rise on the Duo (the cover) and on the slab; then the two quiet events under\n'
        + 'Reduce Motion, where `look` is the weight of the looked-up still in a dissolve.',
        ['play', 'age', 'look'], rows),
      table('rise',
        'When the bedtime moment\'s rise starts and ends on each display, in seconds since the tap\n'
        + '(lab/presence.js, `MOMENT.rise`).',
        ['display', 'starts', 'ends'],
        [['duo', MOMENT.rise.duo[0], MOMENT.rise.duo[1]], ['slab', MOMENT.rise.slab[0], MOMENT.rise.slab[1]]]),
    ],
  });
}

main().catch((error) => {
  process.stderr.write(`look: ${String(error.message ?? error).split('\n')[0]}\n`);
  process.exit(1);
});
