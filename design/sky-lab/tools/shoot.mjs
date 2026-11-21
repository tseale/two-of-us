#!/usr/bin/env node
// Sky lab — screenshots. One PNG per (device × scheme × time) of a sky, clipped
// to the display, and optionally a contact sheet per device × scheme.
//
//   node design/sky-lab/tools/shoot.mjs --sky baseline --sheet
//
// It serves design/sky-lab itself (a free port), opens the viewer with the
// animation frozen (`t=`), waits for `window.__labReady`, and shoots #display.
// Paths are printed, one per line, as they are written (stdout carries nothing
// else); a failed shot is reported on stderr and makes the exit code 1.

import http from 'node:http';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { DEVICES, parseParams, buildState, timeToMinutes, minutesToTime } from '../lab/core.js';

const LAB_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const DEFAULT_TIMES = ['06:50', '09:30', '12:30', '16:10', '16:40', '17:30', '21:00', '03:00'];

const USAGE = `Usage: node tools/shoot.mjs --sky <id> [options]

  --sky <id>              the sky module, skies/<id>.js (required)
  --devices <list>        cover,spread,iphone            (default: all three)
  --schemes <list>        light,dark                     (default: both)
  --times <list>          local HH:MM, comma-separated   (default: ${DEFAULT_TIMES.join(',')})
  --asleep 0|nap|night    a sleep is running             (default: 0)
  --chrome 1|0            Home's UI over the sky, or the sky alone (default: 1)
  --date YYYY-MM-DD  --lat <deg>  --lon <deg>  --tz <hours>  --age <days>
                          passed through to the viewer   (defaults: the viewer's)
  --t <seconds>           the animation instant, frozen  (default: 12)
  --dpr <n>               pixels per point, 1-3          (default: 2)
  --out <dir>             where the PNGs go              (default: shots/<sky> in the lab)
  --sheet                 also a contact sheet per device x scheme: sheet-<device>-<scheme>.png
  --sheet-scale <0-1>     thumbnail size on the sheet    (default: 0.5)

Also passed through: --motion 0|1, --event <kind> --event-age <s>, --lead <0-1>,
--veil <0-1>, --tilt <x,y>, --snowfall <0-1> (snow in the air, forced), --lit 0|1
(tonight's star, forced), --toast 1, --bezel 1 (shoots the device, bezel included),
and any other viewer parameter as --param key=value (repeatable).
Tuning: --jobs <n> pages at once (default 4), --timeout <s> per shot (default 45),
--sheet-cols <n> thumbnails per row (default: as many as fit in --sheet-width <px>,
default 2000 — eight covers or four spreads to a row), --sheet-dpr <n> (default 1).

Files: <device>-<scheme>-<HHMM>[-<asleep>].png. Variants of the same times share
those names, so give them their own --out (e.g. --chrome 0 --out shots/<sky>/bare).`;

// ──────────────────────────────────────────────────────────── arguments ──

function fail(message) {
  process.stderr.write(`shoot: ${message}\n\n${USAGE}\n`);
  process.exit(2);
}

function parseArgs(argv) {
  const flags = new Set(['sheet', 'help']);
  const options = { param: [] };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '-h') { options.help = true; continue; }
    if (!arg.startsWith('--')) fail(`unexpected argument "${arg}"`);
    const eq = arg.indexOf('=');
    const key = eq === -1 ? arg.slice(2) : arg.slice(2, eq);
    let value;
    if (flags.has(key)) {
      value = eq === -1 ? true : !['0', 'false'].includes(arg.slice(eq + 1));
    } else if (eq !== -1) {
      value = arg.slice(eq + 1);
    } else {
      i += 1;
      if (i >= argv.length) fail(`--${key} needs a value`);
      value = argv[i];
    }
    if (key === 'param') options.param.push(value);
    else options[key] = value;
  }
  return options;
}

const KNOWN = new Set(['sky', 'devices', 'schemes', 'times', 'asleep', 'chrome', 'date', 'lat', 'lon', 'tz', 'age',
  't', 'dpr', 'out', 'sheet', 'sheet-scale', 'sheet-cols', 'sheet-width', 'sheet-dpr', 'motion', 'event', 'event-age',
  'lead', 'veil', 'tilt', 'snowfall', 'lit', 'toast', 'bezel', 'jobs', 'timeout', 'param', 'help']);

const list = (value, fallback) => (value == null ? fallback : String(value).split(',').map((s) => s.trim()).filter(Boolean));

function numberOption(options, key, fallback, lo, hi) {
  if (options[key] == null) return fallback;
  const value = Number(options[key]);
  if (!Number.isFinite(value) || value < lo || value > hi) fail(`--${key} must be a number from ${lo} to ${hi} (got "${options[key]}")`);
  return value;
}

function readOptions(argv) {
  const options = parseArgs(argv);
  if (options.help) { process.stdout.write(`${USAGE}\n`); process.exit(0); }
  for (const key of Object.keys(options)) if (!KNOWN.has(key)) fail(`unknown option --${key}`);
  if (!options.sky || options.sky === true) fail('--sky <id> is required');
  if (!/^[A-Za-z0-9][A-Za-z0-9_-]*$/.test(options.sky)) fail(`"${options.sky}" is not a sky id`);

  const devices = list(options.devices, Object.keys(DEVICES));
  for (const device of devices) if (!Object.hasOwn(DEVICES, device)) fail(`unknown device "${device}" (cover, spread, iphone)`);
  const schemes = list(options.schemes, ['light', 'dark']);
  for (const scheme of schemes) if (!['light', 'dark'].includes(scheme)) fail(`unknown scheme "${scheme}" (light, dark)`);
  const times = list(options.times, DEFAULT_TIMES).map((time) => {
    const minutes = timeToMinutes(time);
    if (Number.isNaN(minutes)) fail(`"${time}" is not a time (HH:MM, 24 h)`);
    return minutesToTime(minutes);
  });
  if (!devices.length || !schemes.length || !times.length) fail('nothing to shoot');
  const asleep = options.asleep ?? '0';
  if (!['0', 'nap', 'night'].includes(asleep)) fail(`--asleep is 0, nap or night (got "${asleep}")`);
  const chrome = options.chrome ?? '1';
  if (!['0', '1'].includes(chrome)) fail(`--chrome is 1 or 0 (got "${chrome}")`);

  // What every shot's URL carries besides device, scheme and time.
  const query = { sky: options.sky, asleep, chrome, t: numberOption(options, 't', 12, -1e9, 1e9), dpr: numberOption(options, 'dpr', 2, 1, 3) };
  for (const key of ['date', 'lat', 'lon', 'tz', 'age', 'motion', 'event', 'lead', 'veil', 'tilt', 'snowfall', 'lit', 'toast', 'bezel']) {
    if (options[key] != null) query[key] = String(options[key]);
  }
  if (options['event-age'] != null) query.eventAge = String(options['event-age']);
  for (const pair of options.param) {
    const eq = String(pair).indexOf('=');
    if (eq < 1) fail(`--param takes key=value (got "${pair}")`);
    query[pair.slice(0, eq)] = pair.slice(eq + 1);
  }
  // The viewer falls back to a default for a value it cannot read; say so here instead.
  const read = parseParams(query);
  if (options.date != null) {
    const [year, month, day] = String(options.date).split('-');
    if (read.date !== `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`) {
      fail(`--date "${options.date}" is not a date (YYYY-MM-DD)`);
    }
  }
  for (const key of ['lat', 'lon', 'tz', 'age', 'snowfall', 'veil']) {
    if (options[key] != null && read[key] !== Number(options[key])) {
      fail(`--${key} "${options[key]}" is not a value the viewer accepts (it would use ${read[key]})`);
    }
  }
  if (options.lit != null && !['0', '1'].includes(String(options.lit))) fail(`--lit is 0 or 1 (got "${options.lit}")`);

  return {
    sky: options.sky,
    devices, schemes, times, asleep, chrome, query,
    dpr: query.dpr,
    bezel: read.bezel,
    out: options.out ? path.resolve(process.cwd(), options.out) : path.join(LAB_ROOT, 'shots', options.sky),
    sheet: Boolean(options.sheet),
    sheetScale: numberOption(options, 'sheet-scale', 0.5, 0.05, 1),
    sheetCols: options['sheet-cols'] == null ? null : Math.round(numberOption(options, 'sheet-cols', 0, 1, 1000)),
    sheetWidth: numberOption(options, 'sheet-width', 2000, 200, 16000),
    sheetDpr: numberOption(options, 'sheet-dpr', 1, 0.5, 3),
    jobs: Math.round(numberOption(options, 'jobs', 4, 1, 16)),
    timeout: numberOption(options, 'timeout', 45, 1, 3600) * 1000,
  };
}

// ─────────────────────────────────────────────────────────────── server ──

const TYPES = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json', '.png': 'image/png', '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg', '.webp': 'image/webp', '.svg': 'image/svg+xml', '.woff2': 'font/woff2', '.woff': 'font/woff',
  '.ttf': 'font/ttf', '.otf': 'font/otf', '.txt': 'text/plain; charset=utf-8', '.md': 'text/markdown; charset=utf-8',
  '.glsl': 'text/plain; charset=utf-8', '.frag': 'text/plain; charset=utf-8', '.vert': 'text/plain; charset=utf-8',
  '.wasm': 'application/wasm', '.bin': 'application/octet-stream',
};

/** A static server for the lab on a free port. `/__out/<file>` reads the
 *  output folder and `/__sheet/<name>` a page held in `pages` — both for the
 *  contact sheets. */
function serve(root, outDir, pages) {
  const server = http.createServer(async (request, response) => {
    try {
      const url = new URL(request.url, 'http://localhost');
      let pathname = decodeURIComponent(url.pathname);
      if (pathname.startsWith('/__sheet/')) {
        const page = pages.get(pathname.slice('/__sheet/'.length));
        if (page == null) throw Object.assign(new Error('no such sheet'), { code: 'ENOENT' });
        response.writeHead(200, { 'Content-Type': TYPES['.html'], 'Cache-Control': 'no-store' });
        response.end(page);
        return;
      }
      let base = root;
      let cache = 'max-age=600';
      if (pathname.startsWith('/__out/')) {
        base = outDir;
        cache = 'no-store';
        pathname = pathname.slice('/__out'.length);
      }
      if (pathname.endsWith('/')) pathname += 'index.html';
      const file = path.resolve(base, `.${pathname}`);
      if (file !== base && !file.startsWith(base + path.sep)) throw Object.assign(new Error('outside the lab'), { code: 'ENOENT' });
      const body = await fsp.readFile(file);
      response.writeHead(200, {
        'Content-Type': TYPES[path.extname(file).toLowerCase()] ?? 'application/octet-stream',
        'Cache-Control': cache,
      });
      response.end(body);
    } catch (error) {
      const missing = error.code === 'ENOENT' || error.code === 'EISDIR' || error.code === 'ENOTDIR';
      response.writeHead(missing ? 404 : 500, { 'Content-Type': 'text/plain; charset=utf-8' });
      response.end(missing ? 'Not found' : String(error.message));
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

// ──────────────────────────────────────────────────────────────── shots ──

/** Runs `worker` over `items`, `limit` at a time, in order of starting. */
async function pool(items, limit, worker) {
  let next = 0;
  const lanes = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (next < items.length) {
      const item = items[next];
      next += 1;
      await worker(item);
    }
  });
  await Promise.all(lanes);
}

const shown = (file) => {
  const relative = path.relative(process.cwd(), file);
  return relative && !relative.startsWith('..') && !path.isAbsolute(relative) ? relative : file;
};

const stamp = (time) => time.replaceAll(':', '');
const suffix = (asleep) => (asleep === '0' ? '' : `-${asleep}`);
const shotName = (device, scheme, time, asleep) => `${device}-${scheme}-${stamp(time)}${suffix(asleep)}.png`;

function shotUrl(origin, options, device, scheme, time) {
  const search = new URLSearchParams({ ...options.query, device, scheme, time });
  return `${origin}/index.html?${search.toString().replace(/%3A/gi, ':').replace(/%2C/gi, ',')}`;
}

async function shootOne(context, options, job, problems) {
  const page = await context.newPage();
  const noise = [];
  page.on('pageerror', (error) => noise.push(error.message));
  page.on('console', (message) => { if (message.type() === 'error') noise.push(message.text()); });
  try {
    await page.goto(job.url, { waitUntil: 'load', timeout: options.timeout });
    await page.waitForFunction(() => window.__labReady === true || Boolean(window.__labError), null, { timeout: options.timeout });
    const error = await page.evaluate(() => window.__labError);
    if (error) throw new Error(error);
    const box = await page.locator(options.bezel ? '#device' : '#display').boundingBox();
    if (!box || box.width < 1 || box.height < 1) throw new Error('the display has no size');
    await page.screenshot({ path: job.file, clip: box, animations: 'disabled', caret: 'hide' });
    process.stdout.write(`${shown(job.file)}\n`);
    job.done = true;
    for (const line of new Set(noise)) process.stderr.write(`shoot: ${job.name}: console: ${line}\n`);
  } catch (error) {
    const reason = String(error.message ?? error).split('\n')[0];
    problems.push(`${job.name}: ${reason}`);
    process.stderr.write(`shoot: FAILED ${job.name}: ${reason}\n  ${job.url}\n`);
    for (const line of new Set(noise)) process.stderr.write(`  console: ${line}\n`);
  } finally {
    await page.close().catch(() => {});
  }
}

// ──────────────────────────────────────────────────────────────── sheets ──

const escapeHtml = (text) => String(text).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

/** What the sun is doing at this shot, for its caption. */
function caption(options, device, scheme, time) {
  try {
    const state = buildState(parseParams({ ...options.query, device, scheme, time }));
    const degrees = state.sun.altitude * 180 / Math.PI;
    return `sun ${degrees >= 0 ? '+' : '−'}${Math.abs(degrees).toFixed(1)}°`;
  } catch {
    return '';
  }
}

function sheetHtml(options, device, scheme, jobs) {
  const preset = DEVICES[device];
  const rim = options.bezel ? 10 : 0;
  const width = Math.round((preset.width + 2 * rim) * options.sheetScale);
  const height = Math.round((preset.height + 2 * rim) * options.sheetScale);
  const gap = 10;
  const pad = 14;
  const count = jobs.length;
  const fits = Math.max(1, Math.floor((options.sheetWidth - 2 * pad + gap) / (width + gap)));
  const rows = options.sheetCols ? Math.ceil(count / options.sheetCols) : Math.ceil(count / fits);
  const columns = options.sheetCols ? Math.min(options.sheetCols, count) : Math.ceil(count / rows);
  const dark = scheme === 'dark';
  const read = parseParams(options.query);
  const title = [options.sky, device, scheme, read.date,
    options.asleep !== '0' ? `asleep: ${options.asleep}` : '', options.chrome === '0' ? 'sky alone' : '',
    read.event ? `event: ${read.event} +${read.eventAge}s` : '',
    read.snowfall != null ? `snowfall ${read.snowfall}` : '', read.lit != null ? `star ${read.lit ? 'lit' : 'unlit'}` : '',
    read.tilt ? `tilt ${read.tilt.x},${read.tilt.y}` : '',
    `t=${options.query.t}`].filter(Boolean).join('  ·  ');
  const cells = jobs.map((job) => `
    <figure>${job.done
      ? `<img src="/__out/${encodeURIComponent(path.basename(job.file))}?v=${Date.now()}" width="${width}" height="${height}" alt="">`
      : `<div class="missing" style="width:${width}px;height:${height}px">failed</div>`}
      <figcaption><b>${escapeHtml(job.time)}</b><span>${escapeHtml(caption(options, device, scheme, job.time))}</span></figcaption>
    </figure>`).join('');
  return `<!doctype html><html><head><meta charset="utf-8"><style>
    html, body { margin: 0; background: ${dark ? '#19191c' : '#dcdce1'}; }
    #sheet { display: inline-block; padding: ${pad}px; color: ${dark ? '#e6e6ea' : '#1c1c1e'};
      font: 13px/1 ui-sans-serif, system-ui, "Inter", "Helvetica Neue", Arial, sans-serif; }
    h1 { margin: 0 0 ${pad - 2}px; font-size: 13px; font-weight: 600; white-space: nowrap; }
    .grid { display: grid; grid-template-columns: repeat(${columns}, ${width}px); gap: ${gap}px; }
    figure { margin: 0; }
    img, .missing { display: block; outline: 1px solid ${dark ? 'rgba(255,255,255,.10)' : 'rgba(0,0,0,.12)'}; }
    .missing { display: flex; align-items: center; justify-content: center; color: #d9534f; }
    figcaption { display: flex; justify-content: space-between; align-items: baseline; padding: 6px 1px 2px;
      font-variant-numeric: tabular-nums; }
    figcaption b { font-size: 14px; font-weight: 600; }
    figcaption span { opacity: .6; font-size: 11px; }
  </style></head><body><div id="sheet"><h1>${escapeHtml(title)}</h1><div class="grid">${cells}</div></div></body></html>`;
}

async function shootSheet(browser, origin, pages, options, device, scheme, jobs, problems) {
  const name = `sheet-${device}-${scheme}${suffix(options.asleep)}`;
  const file = path.join(options.out, `${name}.png`);
  pages.set(name, sheetHtml(options, device, scheme, jobs));
  const context = await browser.newContext({ viewport: { width: 1200, height: 800 }, deviceScaleFactor: options.sheetDpr });
  try {
    const page = await context.newPage();
    await page.goto(`${origin}/__sheet/${name}`, { waitUntil: 'load', timeout: options.timeout });
    await page.evaluate(() => Promise.all([...document.images].map((image) => image.decode().catch(() => {}))));
    const size = await page.evaluate(() => {
      const box = document.getElementById('sheet').getBoundingClientRect();
      return { width: Math.ceil(box.width), height: Math.ceil(box.height) };
    });
    await page.setViewportSize(size);
    await page.screenshot({ path: file, clip: { x: 0, y: 0, ...size } });
    process.stdout.write(`${shown(file)}\n`);
  } catch (error) {
    const reason = String(error.message ?? error).split('\n')[0];
    problems.push(`${name}: ${reason}`);
    process.stderr.write(`shoot: FAILED ${name}: ${reason}\n`);
  } finally {
    await context.close().catch(() => {});
  }
}

// ───────────────────────────────────────────────────────────────── main ──

async function main() {
  const options = readOptions(process.argv.slice(2));
  const started = Date.now();
  if (!fs.existsSync(path.join(LAB_ROOT, 'skies', `${options.sky}.js`))) {
    process.stderr.write(`shoot: there is no skies/${options.sky}.js in ${shown(LAB_ROOT)}\n`);
    process.exit(1);
  }
  await fsp.mkdir(options.out, { recursive: true });

  const require = createRequire(import.meta.url);
  const { chromium } = require('playwright');
  const pages = new Map();
  const server = await serve(LAB_ROOT, options.out, pages);
  const browser = await chromium.launch();
  const problems = [];
  try {
    // One context per device (its viewport is the display), shared by that device's shots.
    const contexts = new Map();
    const contextFor = (device) => {
      if (!contexts.has(device)) {
        const preset = DEVICES[device];
        const room = options.bezel ? 120 : 0;
        contexts.set(device, browser.newContext({
          viewport: { width: Math.ceil(preset.width) + room, height: Math.ceil(preset.height) + room },
          deviceScaleFactor: options.dpr,
        }));
      }
      return contexts.get(device);
    };

    const jobs = [];
    for (const device of options.devices) {
      for (const scheme of options.schemes) {
        for (const time of options.times) {
          const name = shotName(device, scheme, time, options.asleep);
          jobs.push({
            device, scheme, time, name,
            file: path.join(options.out, name),
            url: shotUrl(server.origin, options, device, scheme, time),
            done: false,
          });
        }
      }
    }
    await pool(jobs, options.jobs, async (job) => shootOne(await contextFor(job.device), options, job, problems));

    let sheets = 0;
    if (options.sheet) {
      for (const device of options.devices) {
        for (const scheme of options.schemes) {
          const mine = jobs.filter((job) => job.device === device && job.scheme === scheme);
          await shootSheet(browser, server.origin, pages, options, device, scheme, mine, problems);
          sheets += 1;
        }
      }
    }
    const good = jobs.filter((job) => job.done).length;
    process.stderr.write(`shoot: ${good}/${jobs.length} shots${options.sheet ? `, ${sheets} sheets` : ''} `
      + `in ${shown(options.out)} (${((Date.now() - started) / 1000).toFixed(1)} s)\n`);
  } finally {
    await browser.close().catch(() => {});
    await server.close();
  }
  if (problems.length) process.exitCode = 1;
}

main().catch((error) => {
  process.stderr.write(`shoot: ${error.stack ?? error}\n`);
  process.exit(1);
});
