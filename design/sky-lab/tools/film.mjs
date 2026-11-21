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
// The UI's part in each moment is the lab's, the same as tools/review.mjs's
// stills, made continuous:
//   bedtime   the cards fall back over 1.6 s, stay away until 5 s and are back
//             by 8.4 s (`veil`); on the spread the leading page goes with them.
//   open      the leading page stays bare for 0.9 s and its cards have landed
//             by 1.9 s (`lead`).
//   wake      the UI does nothing.
// The sky's part is whatever the sky does with `state.event.age`.

import http from 'node:http';
import fsp from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { DEVICES } from '../lab/core.js';

const LAB_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

const USAGE = `Usage: node tools/film.mjs --sky <id> --event bedtime|open|wake --out <path without extension> [options]

  --device cover|spread|iphone   (default: cover)      --scheme light|dark   (default: dark)
  --time HH:MM                   local time             (default: 19:40 bedtime, 16:12 open, 06:40 wake)
  --asleep 0|nap|night           (default: night for bedtime, else 0)
  --date YYYY-MM-DD  --tz <hours>  --age <days>  --lat <deg>  --lon <deg>   passed to the viewer
  --seconds <n>                  how long the moment runs (default: 10 bedtime, 4.5 open, 9 wake)
  --before <s>  --after <s>      the first and last frame, held (default: 0.7 and 1.2)
  --fps <n>                      (default: 30)          --dpr <n>             (default: 2)
  --param key=value              any other viewer parameter (repeatable)
  --formats mp4,webm             (default: both)        --frames <dir>        keep the PNG frames there

Writes <out>.mp4 (H.264) and <out>.webm (VP9), and prints their paths.`;

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
  bedtime: (age, device) => {
    const veil = smooth(0, 1.6, age) * (1 - smooth(5, 8.4, age));
    return device === 'spread' ? { veil, lead: 1 - veil } : { veil };
  },
  open: (age) => ({ lead: smooth(0.9, 1.9, age) }),
  wake: () => ({}),
};
const DEFAULTS = {
  bedtime: { time: '19:40', asleep: 'night', seconds: 10 },
  open: { time: '16:12', asleep: '0', seconds: 4.5 },
  wake: { time: '06:40', asleep: '0', seconds: 9 },
};

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
  if (!Object.hasOwn(UI, options.event ?? '')) fail('--event is bedtime, open or wake');
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
  const formats = String(options.formats ?? 'mp4,webm').split(',').map((s) => s.trim()).filter(Boolean);
  for (const format of formats) if (!['mp4', 'webm'].includes(format)) fail(`unknown format "${format}" (mp4, webm)`);

  const query = {
    sky: options.sky, device, scheme, time: options.time ?? defaults.time, asleep: options.asleep ?? defaults.asleep,
    chrome: '1', dpr: String(dpr), t: '12', event: options.event, eventAge: '0',
  };
  for (const key of ['date', 'tz', 'age', 'lat', 'lon']) if (options[key] != null) query[key] = String(options[key]);
  for (const pair of options.param) {
    const eq = String(pair).indexOf('=');
    if (eq < 1) fail(`--param takes key=value (got "${pair}")`);
    query[pair.slice(0, eq)] = pair.slice(eq + 1);
  }
  Object.assign(query, Object.fromEntries(Object.entries(UI[options.event](0, device)).map(([k, v]) => [k, String(v)])));

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
    const search = new URLSearchParams(query).toString().replace(/%3A/gi, ':').replace(/%2C/gi, ',');
    await page.goto(`${server.origin}/index.html?${search}`, { waitUntil: 'load', timeout: 60000 });
    await page.waitForFunction(() => window.__labReady === true || Boolean(window.__labError), null, { timeout: 60000 });
    const problem = await page.evaluate(() => window.__labError);
    if (problem) throw new Error(problem);
    const box = await page.locator('#display').boundingBox();
    // H.264 wants even sizes; the three displays have them at dpr 2, and this keeps it so at any dpr.
    const clip = { x: box.x, y: box.y, width: Math.floor(box.width * dpr / 2) * 2 / dpr, height: Math.floor(box.height * dpr / 2) * 2 / dpr };

    const shoot = async () => {
      count += 1;
      await page.screenshot({ path: path.join(frames, `f${String(count).padStart(5, '0')}.png`), clip, animations: 'disabled', caret: 'hide' });
    };
    const total = Math.round(seconds * fps);
    for (let i = 0; i <= total; i += 1) {
      const age = i / fps;
      const patch = { eventAge: age, t: 12 + age, ...UI[options.event](age, device) };
      await page.evaluate((p) => window.__lab.set(p), patch);
      const error = await page.evaluate(() => window.__labError);
      if (error) throw new Error(`at ${age.toFixed(2)} s: ${error}`);
      // The held first and last frames are the same picture, written out again.
      const holds = i === 0 ? Math.round(before * fps) : i === total ? Math.round(after * fps) : 0;
      for (let h = 0; h <= holds; h += 1) await shoot();
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
