#!/usr/bin/env node
// Sky lab — films. Plays one of the sky's moments on one display and writes it
// as a video, so the motion can be watched and not only read as stills.
//
//   node design/sky-lab/tools/film.mjs --sky hill-painted --event bedtime \
//        --device cover --scheme dark --out gallery/film/hill-painted/bed-nov-cover-dark
//
// Nothing here runs in real time. The viewer is frozen (`t=`) and stepped one
// frame at a time through `window.__lab.set`, each frame is shot once it is
// fully drawn, and ffmpeg (which must be on the PATH) joins them. So a film is
// exact at any render cost — and says nothing about how fast a phone draws it.
//
// A film begins BEFORE its event: the standing state the event starts from is
// held for `--before` seconds (0.7 by default), and only then does the event
// begin — so the film shows its own first frame's join, and a jump there is a
// jump in the film. What "before" is:
//   bedtime, arrive   he is awake (asleep=0), the same minute
//   wake              the sleep that ends is still running (asleep=<woke>)
//   settle            the night has not ended yet (begun=1)
//   open              (the closed Duo is another display: the event's own first
//                     frame is held instead)
//
// The UI's part in each moment is the lab's, the same as tools/review.mjs's
// stills, made continuous:
//   bedtime   the cards fall back over 1.6 s, stay away until 4.8 s and are back
//             by 6.8 s (`veil`); on the spread the leading page goes with them.
//   open      the leading page stays bare for 0.9 s and its cards have landed
//             by 1.9 s (`lead`).
//   arrive    a sleep that began elsewhere: the UI does nothing (the sleep card
//             is there from the first frame).
//   settle    first light: the UI does nothing.
//   wake      the UI does nothing (the sleep card goes with the first frame).
// The sky's part is whatever the sky does with `state.event.age`.

import http from 'node:http';
import fsp from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { DEVICES, parseParams, buildState, timeToMinutes, minutesToTime, wokeFrom, FIRST_LIGHT_DEG } from '../lab/core.js';

const LAB_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

const USAGE = `Usage: node tools/film.mjs --sky <id> --event bedtime|arrive|settle|wake|open --out <path without extension> [options]

  --device cover|spread|iphone   (default: cover)      --scheme light|dark   (default: dark)
  --time HH:MM                   local time             (default: 19:40 bedtime and arrive, 03:00 wake, 16:12 open;
                                                         settle: the date's first light — the first minute the sun is over ${FIRST_LIGHT_DEG}°)
  --asleep 0|nap|night           the state from the event on (default: night for bedtime, arrive and settle, else 0)
  --woke night|nap               wake only: the sleep that ended (default: by the hour, as the lab does — night at 03:00)
  --date YYYY-MM-DD  --tz <hours>  --age <days>  --lat <deg>  --lon <deg>   passed to the viewer
  --seconds <n>                  how long the moment runs (default: 8 bedtime, 5 arrive, 5 settle, 6.5 wake, 4.5 open)
  --before <s>                   the standing state BEFORE the event, held (default: 0.7; 0: the film starts on the event's first frame)
  --after <s>                    the last frame, held (default: 1.2)
  --fps <n>                      (default: 30; 60 for judging motion)   --dpr <n>   (default: 2)
  --param key=value              any other viewer parameter (repeatable)
  --formats mp4,webm             (default: both; none: frames only)     --frames <dir>   keep the PNG frames there

Frames are f00001.png …: the held "before" first (round(before × fps) of them), then one per 1/fps from the
event's age 0. Writes <out>.mp4 (H.264) and <out>.webm (VP9), and prints their paths. If the lab plays the event
as something else, or drops it (bedtime once the night has begun, say), it says so on stderr.`;

const TYPES = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json', '.png': 'image/png', '.jpg': 'image/jpeg',
  '.webp': 'image/webp', '.svg': 'image/svg+xml', '.woff2': 'font/woff2', '.woff': 'font/woff', '.ttf': 'font/ttf',
  '.otf': 'font/otf', '.txt': 'text/plain; charset=utf-8',
};

function fail(message) {
  process.stderr.write(`film: ${message}\n\n${USAGE}\n`);
  process.exit(2);
}

function parseArgs(argv) {
  const options = { param: [] };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '-h' || arg === '--help') { process.stdout.write(`${USAGE}\n`); process.exit(0); }
    if (!arg.startsWith('--')) fail(`unexpected argument "${arg}"`);
    const eq = arg.indexOf('=');
    const key = eq === -1 ? arg.slice(2) : arg.slice(2, eq);
    const value = eq === -1 ? argv[i += 1] : arg.slice(eq + 1);
    if (value == null) fail(`--${key} needs a value`);
    if (key === 'param') options.param.push(value);
    else options[key] = value;
  }
  return options;
}

const smooth = (a, b, x) => {
  const u = Math.min(1, Math.max(0, (x - a) / (b - a)));
  return u * u * (3 - 2 * u);
};

/** What the lab's UI does at `age` seconds into each moment. */
const UI = {
  // (the cards come back over the sky that is already there: the view does not come down — BRIEF.md, round three)
  bedtime: (age, device) => {
    const veil = smooth(0, 1.6, age) * (1 - smooth(4.8, 6.8, age));
    return device === 'spread' ? { veil, lead: 1 - veil } : { veil };
  },
  open: (age) => ({ lead: smooth(0.9, 1.9, age) }),
  arrive: () => ({}),
  settle: () => ({}),
  wake: () => ({}),
};
const DEFAULTS = {
  bedtime: { time: '19:40', asleep: 'night', seconds: 8 },
  open: { time: '16:12', asleep: '0', seconds: 4.5 },
  arrive: { time: '19:40', asleep: 'night', seconds: 5 },
  settle: { time: null, asleep: 'night', seconds: 5 },          // (time: first light on the date)
  wake: { time: '03:00', asleep: '0', seconds: 6.5 },
};

/** First light on the film's date: the first local minute of the morning with the sun over the lab's threshold. */
function firstLight(query) {
  for (let m = 0; m < 12 * 60; m += 1) {
    const state = buildState(parseParams({ ...query, time: minutesToTime(m) }));
    const morning = state.sun.isNight ? state.sun.progress > 0.5 : state.sun.progress < 0.5;
    if (morning && state.sun.altitude * 180 / Math.PI >= FIRST_LIGHT_DEG) return minutesToTime(m);
  }
  return '06:00';
}

/** The standing state an event starts from, as a patch over the event's own query (null: there is none to show). */
function stateBefore(event, query) {
  if (event === 'bedtime' || event === 'arrive') return { asleep: '0' };
  if (event === 'wake') return { asleep: query.woke ?? wokeFrom(timeToMinutes(query.time)) };
  if (event === 'settle') return { begun: '1' };
  return null;
}

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

function run(command, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { stdio: ['ignore', 'ignore', 'pipe'] });
    let err = '';
    child.stderr.on('data', (chunk) => { err = (err + chunk).slice(-4000); });
    child.once('error', reject);
    child.once('close', (code) => (code === 0 ? resolve() : reject(new Error(`${command} exited ${code}: ${err.trim().split('\n').slice(-3).join(' | ')}`))));
  });
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (!options.sky || !/^[A-Za-z0-9][A-Za-z0-9_-]*$/.test(options.sky)) fail('--sky <id> is required');
  if (!Object.hasOwn(UI, options.event ?? '')) fail('--event is bedtime, arrive, settle, wake or open');
  if (!options.out) fail('--out <path without extension> is required');
  const device = options.device ?? 'cover';
  if (!Object.hasOwn(DEVICES, device)) fail(`unknown device "${device}" (cover, spread, iphone)`);
  const scheme = options.scheme ?? 'dark';
  const defaults = DEFAULTS[options.event];
  const number = (key, fallback) => {
    const value = options[key] == null ? fallback : Number(options[key]);
    if (!Number.isFinite(value) || value < 0) fail(`--${key} is not a number (got "${options[key]}")`);
    return value;
  };
  const fps = number('fps', 30);
  const dpr = number('dpr', 2);
  const seconds = number('seconds', defaults.seconds);
  const before = number('before', 0.7);
  const after = number('after', 1.2);
  const formats = String(options.formats ?? 'mp4,webm').split(',').map((s) => s.trim()).filter((s) => s && s !== 'none');
  for (const format of formats) if (!['mp4', 'webm'].includes(format)) fail(`unknown format "${format}" (mp4, webm, none)`);
  if (options.woke != null && !['night', 'nap'].includes(options.woke)) fail(`--woke is night or nap (got "${options.woke}")`);

  // The state from the event's first frame on…
  const query = {
    sky: options.sky, device, scheme, asleep: options.asleep ?? defaults.asleep,
    chrome: '1', dpr: String(dpr), t: '12', event: options.event, eventAge: '0',
  };
  for (const key of ['date', 'tz', 'age', 'lat', 'lon']) if (options[key] != null) query[key] = String(options[key]);
  query.time = options.time ?? defaults.time ?? firstLight(query);
  if (options.woke != null) query.woke = options.woke;
  for (const pair of options.param) {
    const eq = String(pair).indexOf('=');
    if (eq < 1) fail(`--param takes key=value (got "${pair}")`);
    query[pair.slice(0, eq)] = pair.slice(eq + 1);
  }
  Object.assign(query, Object.fromEntries(Object.entries(UI[options.event](0, device)).map(([k, v]) => [k, String(v)])));
  // …and the standing state before it, which the film opens on.
  const beforePatch = before > 0 ? stateBefore(options.event, query) : null;
  const first = beforePatch ? { ...query, ...beforePatch } : query;
  if (beforePatch) { delete first.event; delete first.eventAge; }

  const out = path.resolve(options.out);
  await fsp.mkdir(path.dirname(out), { recursive: true });
  const frames = options.frames ? path.resolve(options.frames) : await fsp.mkdtemp(path.join(os.tmpdir(), 'sky-film-'));
  await fsp.mkdir(frames, { recursive: true });

  const require = createRequire(import.meta.url);
  const { chromium } = require('playwright');
  const server = await serve(LAB_ROOT);
  const browser = await chromium.launch();
  const started = Date.now();
  let count = 0;
  try {
    const preset = DEVICES[device];
    const context = await browser.newContext({
      viewport: { width: Math.ceil(preset.width), height: Math.ceil(preset.height) }, deviceScaleFactor: dpr,
    });
    const page = await context.newPage();
    const noise = new Set();
    page.on('pageerror', (error) => noise.add(error.message));
    const search = new URLSearchParams(first).toString().replace(/%3A/gi, ':').replace(/%2C/gi, ',');
    await page.goto(`${server.origin}/index.html?${search}`, { waitUntil: 'load', timeout: 60000 });
    await page.waitForFunction(() => window.__labReady === true || Boolean(window.__labError), null, { timeout: 60000 });
    const problem = await page.evaluate(() => window.__labError);
    if (problem) throw new Error(problem);
    const box = await page.locator('#display').boundingBox();
    // H.264 wants even sizes; the three displays have them at dpr 2, and this keeps it so at any dpr.
    const clip = { x: box.x, y: box.y, width: Math.floor(box.width * dpr / 2) * 2 / dpr, height: Math.floor(box.height * dpr / 2) * 2 / dpr };

    /** Shoots the frame as it stands and writes it `copies` times (a held frame is one picture, written out again). */
    const shoot = async (copies = 1) => {
      const png = await page.screenshot({ clip, animations: 'disabled', caret: 'hide' });
      for (let k = 0; k < copies; k += 1) {
        count += 1;
        await fsp.writeFile(path.join(frames, `f${String(count).padStart(5, '0')}.png`), png);
      }
    };
    const total = Math.round(seconds * fps);
    const holdBefore = Math.round(before * fps), holdAfter = Math.round(after * fps);
    // The standing state before the event, held. (`open` has none to show: its own first frame is held.)
    if (beforePatch && holdBefore > 0) await shoot(holdBefore);
    // The event's own params, set with its first frame (and whatever the "before" forced, let go).
    const start = { asleep: query.asleep, event: options.event, begun: query.begun ?? '', woke: query.woke ?? '' };
    for (let i = 0; i <= total; i += 1) {
      const age = i / fps;
      const patch = { ...(i === 0 ? start : {}), eventAge: age, t: 12 + age, ...UI[options.event](age, device) };
      await page.evaluate((p) => window.__lab.set(p), patch);
      const error = await page.evaluate(() => window.__labError);
      if (error) throw new Error(`at ${age.toFixed(2)} s: ${error}`);
      if (i === 0) {
        const played = await page.evaluate(() => ({ kind: window.__lab.state.event?.kind ?? null, note: window.__lab.state.eventNote ?? null }));
        if (played.note) process.stderr.write(`film: the lab says — ${played.note}\n`);
        else if (played.kind !== options.event) process.stderr.write(`film: the lab plays this as ${played.kind ?? 'no event at all'}\n`);
      }
      await shoot(1 + (i === 0 && !beforePatch ? holdBefore : 0) + (i === total ? holdAfter : 0));
    }
    for (const line of noise) process.stderr.write(`film: console: ${line}\n`);
  } finally {
    await browser.close();
    await server.close();
  }
  process.stderr.write(`film: ${count} frames in ${((Date.now() - started) / 1000).toFixed(0)} s\n`);

  const input = ['-y', '-hide_banner', '-loglevel', 'error', '-framerate', String(fps), '-i', path.join(frames, 'f%05d.png')];
  if (formats.includes('mp4')) {
    // aq-mode 3 spends bits on the dark, flat skies, where 8-bit video bands first.
    await run('ffmpeg', [...input, '-c:v', 'libx264', '-preset', 'slow', '-crf', '17', '-x264-params', 'aq-mode=3',
      '-pix_fmt', 'yuv420p', '-colorspace', 'bt709', '-color_primaries', 'bt709', '-color_trc', 'iec61966-2-1',
      '-movflags', '+faststart', `${out}.mp4`]);
    process.stdout.write(`${out}.mp4\n`);
  }
  if (formats.includes('webm')) {
    await run('ffmpeg', [...input, '-c:v', 'libvpx-vp9', '-crf', '30', '-b:v', '0', '-row-mt', '1', '-pix_fmt', 'yuv420p', `${out}.webm`]);
    process.stdout.write(`${out}.webm\n`);
  }
  if (!options.frames) await fsp.rm(frames, { recursive: true, force: true });
}

main().catch((error) => {
  process.stderr.write(`film: ${String(error.message ?? error).split('\n')[0]}\n`);
  process.exit(1);
});
