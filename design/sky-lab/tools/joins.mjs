#!/usr/bin/env node
// Sky lab — joins. BRIEF.md, "After the first review", item 2: no join may jump.
//
//   node tools/joins.mjs --sky hill-painted
//   node tools/joins.mjs --sky hill-painted --only wake-night,settle-nov --devices cover --schemes dark --save /tmp/joins
//
// A join is a change of state while Home is on screen: a sleep starting or
// ending, the bedtime moment's start and end, a night sleep that arrives from
// elsewhere, first light. For each join this shoots four frames at one instant
// of the animation (t=12), on every display, in both appearances, the sky alone
// (chrome=0) and with the cards on:
//
//   before   the standing frame before the change (no event)
//   age0     the event's first frame (eventAge=0)
//   age40    the event's last frame (eventAge=40: every curve has run out)
//   after    the standing frame that follows (no event)
//
// and compares  before | age0  (the START: the first frame after the change
// must be the frame before it)  and  age40 | after  (the END: the event's last
// frame must be the standing frame that follows it).
//
// For each pair, with d = the largest of the three channels' differences at a
// pixel, in 8-bit levels: the mean of d, the share of pixels with d > 2 and with
// d > 6, the largest d and where it is (points), and the box of the pixels over
// 6. Sky alone, that is the whole frame but for the header's words (name, age,
// the leading page's title and the line under it, in either frame: the sky
// gives way under them by design, and a title changes when a sleep starts).
// With the cards on, the chrome itself changes when a sleep starts or ends (the
// sleep card, the longer island), which is not the sky's doing: the numbers are
// taken over the OPEN SKY only — what no card covers in either frame, without
// the header's words and buttons, the strip's own furniture (clock, island,
// status icons) and, round a card that is in only one of the two frames or has
// moved, the 36 pt its shadow can reach.
//
// LIMITS. The lab is deterministic: two shots of the same state are the same
// bytes (`--self` checks that and must print 0). So a join has no noise of its
// own to hide in, and the limits are set from the picture's grain instead — the
// paper grain and the dither together stand a pixel about 1.7 levels from its
// neighbours' mean (the median; 4 levels at the 90th percentile — measured over
// a patch of the dark night sky and printed at the head of every run), so a
// change that stays well inside the grain cannot be seen:
//
//   mean d       ≤ 0.25 levels   (a seventh of the grain, over everything counted)
//   share d > 2  ≤ 0.5 %         (no area larger than a 30 pt square steps out of the grain)
//   share d > 6  ≤ 0.02 %        (nothing the size of a star, about 9 pt², appears or goes)
//   largest d    ≤ 12 levels     (no single point lights or goes out)
//
// Exit code 1 if any pair is over a limit. `--limits mean,over2%,over6%,max`
// changes them for a run (say so when you quote its numbers).
//
// Two causes of a jump are shown here and owned elsewhere: the strip's cloud,
// which is switched off and on with the clear window in the frame a sleep starts
// or ends (a join that crosses it says so beside its FAIL), and whatever happens
// inside the bedtime timeline between age 0 and age 40 (this tool looks only at
// an event's two ends; tools/film.mjs shows the rest).

import http from 'node:http';
import zlib from 'node:zlib';
import fsp from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createRequire } from 'node:module';
import * as core from '../lab/core.js';

const LAB_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const { DEVICES, parseParams, buildState, minutesToTime } = core;

export const LIMITS = Object.freeze({ mean: 0.25, over2: 0.5, over6: 0.02, max: 12 });

const JULY = { date: '2027-07-04', tz: '-5', age: '367' };
const JUNE = { date: '2027-06-21', tz: '-5', age: '354' };

/** First light on a date: the first local minute of the morning at which the sun has come up through
 *  the lab's threshold (lab/core.js, FIRST_LIGHT_DEG) → 'HH:MM'. */
export function firstLightTime(common = {}) {
  const threshold = core.FIRST_LIGHT_DEG ?? -7;
  for (let m = 0; m < 12 * 60; m += 1) {
    const state = buildState(parseParams({ ...common, time: minutesToTime(m) }));
    const morning = state.sun.isNight ? state.sun.progress > 0.5 : state.sun.progress < 0.5;
    if (morning && state.sun.altitude * 180 / Math.PI >= threshold) return minutesToTime(m);
  }
  return '06:00';
}

/**
 * The joins. `common`: what all four frames share. `before` / `after`: the standing states (no
 * event). `event`: the state from the event's first frame on (eventAge is added by the tool).
 * `theirs`: a cause this tool shows but another pass owns (printed beside a failing pair).
 */
export function joins() {
  const dawnNov = firstLightTime({});
  const dawnJun = firstLightTime(JUNE);
  return [
    { id: 'bedtime-nov', about: '(a, b) evening awake → bedtime → the standing night, November 19:40',
      common: { time: '19:40' }, before: { asleep: '0' }, event: { asleep: 'night', event: 'bedtime' }, after: { asleep: 'night' },
      theirs: 'the strip cloud hides when the clear window shrinks, and the stars it veiled show (the day pass)' },
    { id: 'bedtime-jul', about: '(a, b) evening awake → bedtime → the standing night, July 19:55 (the sun still up, in the crown)',
      common: { time: '19:55', ...JULY }, before: { asleep: '0' }, event: { asleep: 'night', event: 'bedtime' }, after: { asleep: 'night' },
      theirs: 'the strip cloud hides when the clear window shrinks (the day pass)' },
    { id: 'wake-night', about: '(c) the standing night at 03:00 → wake (a feed) → awake at night: nothing moves, the room un-dims',
      common: { time: '03:00' }, before: { asleep: 'night' }, event: { asleep: '0', event: 'wake', woke: 'night' }, after: { asleep: '0' } },
    // (the lab has no sleep log: before the sample bedtime, 20:10, a wake has to be TOLD the sleep was the
    // night's, and the awake frame after it that the night has begun — `woke=night`, `begun=1`)
    { id: 'wake-night-early', about: '(c) down for the night at 19:40, awake again at 19:55, before the sample bedtime → wake → awake: the view stays up, the star lit (woke=night; the frame after is told begun=1)',
      common: { time: '19:55' }, before: { asleep: 'night' }, event: { asleep: '0', event: 'wake', woke: 'night' }, after: { asleep: '0', begun: '1' } },
    { id: 'arrive-back', about: '(d) awake at night, 03:00 → arrive (put down again) → the standing night: nothing moves, the room dims',
      common: { time: '03:00' }, before: { asleep: '0' }, event: { asleep: 'night', event: 'arrive' }, after: { asleep: 'night' } },
    { id: 'wake-nap-1310', about: '(e) a nap at 13:10 → wake → awake',
      common: { time: '13:10' }, before: { asleep: 'nap' }, event: { asleep: '0', event: 'wake', woke: 'nap' }, after: { asleep: '0' },
      theirs: 'the strip cloud shows when the clear window grows (the day pass)' },
    { id: 'wake-nap-1610', about: '(e) a nap at 16:10 → wake → awake',
      common: { time: '16:10' }, before: { asleep: 'nap' }, event: { asleep: '0', event: 'wake', woke: 'nap' }, after: { asleep: '0' },
      theirs: 'the strip cloud shows when the clear window grows (the day pass)' },
    { id: 'arrive-nap', about: '(f) awake at 13:10 → arrive (a nap) → the nap',
      common: { time: '13:10' }, before: { asleep: '0' }, event: { asleep: 'nap', event: 'arrive' }, after: { asleep: 'nap' },
      theirs: 'the strip cloud hides when the clear window shrinks (the day pass)' },
    { id: 'arrive-night', about: '(g) evening awake, 19:40 → arrive (a night sleep begun elsewhere) → the standing night',
      common: { time: '19:40' }, before: { asleep: '0' }, event: { asleep: 'night', event: 'arrive' }, after: { asleep: 'night' },
      theirs: 'the strip cloud hides when the clear window shrinks, and the stars it veiled show (the day pass)' },
    { id: 'settle-nov', about: `(h) first light in November (${dawnNov}), he still sleeps: looking up → settle → the rest pose`,
      common: { time: dawnNov, asleep: 'night' }, before: { begun: '1' }, event: { event: 'settle' }, after: {} },
    { id: 'settle-jun', about: `(h) first light on 21 June (${dawnJun}), he still sleeps: looking up → settle → the rest pose`,
      common: { time: dawnJun, asleep: 'night', ...JUNE }, before: { begun: '1' }, event: { event: 'settle' }, after: {} },
    { id: 'wake-morning', about: '(i) asleep after first light, November 06:40 → wake → the morning',
      common: { time: '06:40' }, before: { asleep: 'night' }, event: { asleep: '0', event: 'wake', woke: 'night' }, after: { asleep: '0' },
      theirs: 'the strip cloud shows when the clear window grows (the day pass)' },
    { id: 'bedtime-late', about: '(lab only) awake at 21:00, the night already begun → bedtime by hand: no moment, it plays as arrive',
      common: { time: '21:00' }, before: { asleep: '0' }, event: { asleep: 'night', event: 'bedtime' }, after: { asleep: 'night' } },
  ];
}

/** The four frames of a join → [{ frame, params }] (viewer parameters, without device, scheme and chrome). */
export function framesOf(join) {
  return [
    { frame: 'before', params: { ...join.common, ...join.before } },
    { frame: 'age0', params: { ...join.common, ...join.event, eventAge: '0' } },
    { frame: 'age40', params: { ...join.common, ...join.event, eventAge: '40' } },
    { frame: 'after', params: { ...join.common, ...join.after } },
  ];
}

const USAGE = `Usage: node tools/joins.mjs --sky <id> [options]

  --only <ids>            some joins only (--list names them)
  --devices <list>        cover,spread,iphone            (default: all three)
  --schemes <list>        dark,light                     (default: both)
  --chrome <list>         0,1: the sky alone, the cards on (default: both)
  --save <dir>            keep the frames: <dir>/<join>/<device>-<scheme>-c<chrome>-<frame>.png
  --json <file>           the numbers, as JSON
  --limits a,b,c,d        mean (levels), share over 2 (%), share over 6 (%), largest (levels); default ${Object.values(LIMITS).join(',')}
  --self                  shoot every "before" twice and compare the two (must be 0: the lab is deterministic)
  --param key=value       any other viewer parameter, on every frame (repeatable)
  --jobs <n>              pages at once (default 2)      --timeout <s>   per shot (default 60)
  --dpr <n>               (default 2)                    --list          the joins, and stop

Prints one line per pair and PASS or FAIL; exit code 1 on any FAIL.`;

function fail(message) {
  process.stderr.write(`joins: ${message}\n\n${USAGE}\n`);
  process.exit(2);
}

function parseArgs(argv) {
  const flags = new Set(['self', 'list', 'help']);
  const options = { param: [] };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '-h') { options.help = true; continue; }
    if (!arg.startsWith('--')) fail(`unexpected argument "${arg}"`);
    const eq = arg.indexOf('=');
    const key = eq === -1 ? arg.slice(2) : arg.slice(2, eq);
    let value;
    if (flags.has(key)) value = true;
    else if (eq !== -1) value = arg.slice(eq + 1);
    else { i += 1; if (i >= argv.length) fail(`--${key} needs a value`); value = argv[i]; }
    if (key === 'param') options.param.push(value); else options[key] = value;
  }
  return options;
}

// ───────────────────────────────────────────────────────────────── PNG ──

/** A PNG as Playwright writes it (8-bit RGB or RGBA, not interlaced) → { width, height, rgb }. */
export function decodePng(buffer) {
  let at = 8;
  let width = 0, height = 0, colour = 0;
  const data = [];
  while (at < buffer.length) {
    const length = buffer.readUInt32BE(at);
    const type = buffer.toString('latin1', at + 4, at + 8);
    const body = buffer.subarray(at + 8, at + 8 + length);
    if (type === 'IHDR') {
      width = body.readUInt32BE(0); height = body.readUInt32BE(4); colour = body[9];
      if (body[8] !== 8 || (colour !== 2 && colour !== 6) || body[12] !== 0) throw new Error('joins: a PNG that is not 8-bit RGB(A), non-interlaced');
    } else if (type === 'IDAT') data.push(body);
    at += 12 + length;
  }
  const bpp = colour === 6 ? 4 : 3;
  const raw = zlib.inflateSync(Buffer.concat(data));
  const stride = width * bpp;
  const rgb = new Uint8Array(width * height * 3);
  let prev = new Uint8Array(stride), line = new Uint8Array(stride);
  for (let y = 0; y < height; y += 1) {
    const filter = raw[y * (stride + 1)];
    const row = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    for (let x = 0; x < stride; x += 1) {
      const a = x >= bpp ? line[x - bpp] : 0, b = prev[x], c = x >= bpp ? prev[x - bpp] : 0;
      let v = row[x];
      if (filter === 1) v += a;
      else if (filter === 2) v += b;
      else if (filter === 3) v += (a + b) >> 1;
      else if (filter === 4) { const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c); v += pa <= pb && pa <= pc ? a : pb <= pc ? b : c; }
      line[x] = v & 255;
    }
    for (let x = 0; x < width; x += 1) {
      rgb[(y * width + x) * 3] = line[x * bpp]; rgb[(y * width + x) * 3 + 1] = line[x * bpp + 1]; rgb[(y * width + x) * 3 + 2] = line[x * bpp + 2];
    }
    const swap = prev; prev = line; line = swap;
  }
  return { width, height, rgb };
}

// ───────────────────────────────────────────────────────────── comparing ──

/** What of the display counts, for one frame of a pair: 1 = it does. Rects in points.
 *  Never the header's words (the sky gives way under them by design — a star behind a title that
 *  has just grown longer is not a pop). With the cards on, also not what a card covers, nor the
 *  strip's own furniture, nor — where a card is in only one of the two frames, or has moved — the
 *  reach of its shadow. `other`: the cards of the pair's other frame. */
function openMask(width, height, dpr, cards, layout, other) {
  const mask = new Uint8Array(width * height).fill(1);
  const cut = (x, y, w, h, pad) => {
    const x0 = Math.max(0, Math.floor((x - pad) * dpr)), x1 = Math.min(width, Math.ceil((x + w + pad) * dpr));
    const y0 = Math.max(0, Math.floor((y - pad) * dpr)), y1 = Math.min(height, Math.ceil((y + h + pad) * dpr));
    for (let yy = y0; yy < y1; yy += 1) mask.fill(0, yy * width + x0, yy * width + x1);
  };
  const same = (a, b) => a.kind === b.kind && Math.abs(a.x - b.x) < 0.5 && Math.abs(a.y - b.y) < 0.5 && Math.abs(a.width - b.width) < 0.5 && Math.abs(a.height - b.height) < 0.5;
  for (const card of cards ?? []) {
    if (card.kind === 'header') continue;                                        // text and buttons on bare sky: cut below, by their own boxes
    if (card.kind === 'strip') {
      // the Duo's column: its furniture stands above the clear window; the slab's status bar: all of it
      const clear = layout?.stripClear;
      if (clear) cut(card.x, card.y, card.width, Math.max(0, clear.yMin + 6 - card.y), 0);
      else cut(card.x, card.y, card.width, card.height, 0);
      continue;
    }
    cut(card.x, card.y, card.width, card.height, (other ?? []).some((o) => same(o, card)) ? 4 : 36);
  }
  const words = (cards ?? []).length ? ['name', 'age', 'avatar', 'gear', 'title', 'subtitle'] : ['name', 'age', 'title', 'subtitle'];
  for (const key of words) {
    const box = layout?.[key];
    if (box) cut(box.x, box.y, box.width, box.height, 3);
  }
  return mask;
}

/** Two frames of one size → the numbers. `mask`: 1 where a pixel counts (null: everywhere). */
export function compare(a, b, dpr, mask = null) {
  const { width, height } = a;
  let count = 0, sum = 0, over2 = 0, over6 = 0, max = 0, maxAt = -1;
  let bx0 = Infinity, by0 = Infinity, bx1 = -1, by1 = -1;
  for (let i = 0, p = 0; i < width * height; i += 1, p += 3) {
    if (mask && !mask[i]) continue;
    const d = Math.max(Math.abs(a.rgb[p] - b.rgb[p]), Math.abs(a.rgb[p + 1] - b.rgb[p + 1]), Math.abs(a.rgb[p + 2] - b.rgb[p + 2]));
    count += 1; sum += d;
    if (d > 2) over2 += 1;
    if (d > 6) {
      over6 += 1;
      const x = i % width, y = (i - x) / width;
      if (x < bx0) bx0 = x; if (x > bx1) bx1 = x; if (y < by0) by0 = y; if (y > by1) by1 = y;
    }
    if (d > max) { max = d; maxAt = i; }
  }
  const pt = (v) => Math.round(v / dpr);
  return {
    pixels: count,
    mean: count ? sum / count : 0,
    over2: count ? (100 * over2) / count : 0,
    over6: count ? (100 * over6) / count : 0,
    max,
    maxAt: maxAt < 0 ? null : { x: pt(maxAt % width), y: pt(Math.floor(maxAt / width)) },
    box6: over6 ? { x0: pt(bx0), y0: pt(by0), x1: pt(bx1), y1: pt(by1) } : null,
  };
}

/** The grain: over a patch of sky, |pixel − the mean of its 3 × 3| (green channel): its median and 90th percentile, in levels
 *  (a few stars in the patch do not move either). */
export function grainOf(image, dpr, patch = { x: 40, y: 150, width: 120, height: 120 }) {
  const { width, rgb } = image;
  const x0 = Math.round(patch.x * dpr) + 1, y0 = Math.round(patch.y * dpr) + 1;
  const x1 = Math.round((patch.x + patch.width) * dpr) - 1, y1 = Math.round((patch.y + patch.height) * dpr) - 1;
  const out = [];
  for (let y = y0; y < y1; y += 1) for (let x = x0; x < x1; x += 1) {
    let sum = 0;
    for (let dy = -1; dy <= 1; dy += 1) for (let dx = -1; dx <= 1; dx += 1) sum += rgb[((y + dy) * width + x + dx) * 3 + 1];
    out.push(Math.abs(rgb[(y * width + x) * 3 + 1] - sum / 9));
  }
  out.sort((p, q) => p - q);
  return { median: out[Math.floor(out.length * 0.5)], p90: out[Math.floor(out.length * 0.9)] };
}

const verdict = (r, limits) => (r.mean <= limits.mean && r.over2 <= limits.over2 && r.over6 <= limits.over6 && r.max <= limits.max);

// ──────────────────────────────────────────────────────────────── main ──

const TYPES = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json', '.png': 'image/png', '.jpg': 'image/jpeg',
  '.webp': 'image/webp', '.svg': 'image/svg+xml', '.woff2': 'font/woff2', '.woff': 'font/woff', '.ttf': 'font/ttf',
  '.otf': 'font/otf', '.txt': 'text/plain; charset=utf-8',
};

function serve(root) {
  const server = http.createServer(async (request, response) => {
    try {
      let pathname = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
      if (pathname.endsWith('/')) pathname += 'index.html';
      const file = path.resolve(root, `.${pathname}`);
      if (!file.startsWith(root + path.sep)) throw Object.assign(new Error('outside the lab'), { code: 'ENOENT' });
      const body = await fsp.readFile(file);
      response.writeHead(200, { 'Content-Type': TYPES[path.extname(file).toLowerCase()] ?? 'application/octet-stream', 'Cache-Control': 'max-age=600' });
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

async function pool(items, limit, worker) {
  let next = 0;
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (next < items.length) { const item = items[next]; next += 1; await worker(item); }
  }));
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) { process.stdout.write(`${USAGE}\n`); return; }
  const all = joins();
  if (options.list) {
    for (const join of all) {
      process.stdout.write(`${join.id.padEnd(15)} ${join.about}\n`);
      for (const f of framesOf(join)) process.stdout.write(`${''.padEnd(17)}${f.frame.padEnd(7)} ${new URLSearchParams(f.params).toString().replace(/%3A/gi, ':').replace(/&/g, ' ')}\n`);
    }
    return;
  }
  const known = new Set(['sky', 'only', 'devices', 'schemes', 'chrome', 'save', 'json', 'limits', 'self', 'param', 'jobs', 'timeout', 'dpr', 'list', 'help']);
  for (const key of Object.keys(options)) if (!known.has(key)) fail(`unknown option --${key}`);
  if (!options.sky || !/^[A-Za-z0-9][A-Za-z0-9_-]*$/.test(options.sky)) fail('--sky <id> is required');
  const list = (value, fallback) => (value == null ? fallback : String(value).split(',').map((s) => s.trim()).filter(Boolean));
  const devices = list(options.devices, Object.keys(DEVICES));
  for (const device of devices) if (!Object.hasOwn(DEVICES, device)) fail(`unknown device "${device}" (cover, spread, iphone)`);
  const schemes = list(options.schemes, ['dark', 'light']);
  for (const scheme of schemes) if (!['light', 'dark'].includes(scheme)) fail(`unknown scheme "${scheme}" (light, dark)`);
  const chromes = list(options.chrome, ['0', '1']);
  for (const chrome of chromes) if (!['0', '1'].includes(chrome)) fail(`--chrome is a list of 0 and 1 (got "${chrome}")`);
  const only = list(options.only, null);
  const chosen = only ? all.filter((join) => only.includes(join.id)) : all;
  if (!chosen.length) fail(`no such join (${all.map((join) => join.id).join(', ')})`);
  const limits = { ...LIMITS };
  if (options.limits != null) {
    const parts = String(options.limits).split(',').map(Number);
    if (parts.length !== 4 || !parts.every((v) => Number.isFinite(v) && v >= 0)) fail('--limits takes four numbers: mean,over2%,over6%,max');
    [limits.mean, limits.over2, limits.over6, limits.max] = parts;
  }
  const dpr = Number(options.dpr ?? 2);
  const jobs = Math.max(1, Math.round(Number(options.jobs ?? 2)));
  const timeout = Number(options.timeout ?? 60) * 1000;
  const extra = {};
  for (const pair of options.param) {
    const eq = String(pair).indexOf('=');
    if (eq < 1) fail(`--param takes key=value (got "${pair}")`);
    extra[pair.slice(0, eq)] = pair.slice(eq + 1);
  }
  const save = options.save ? path.resolve(process.cwd(), options.save) : null;

  // Join by join (a run of all of them is some five hundred frames: they are not all held at once).
  // A standing frame is often one join's "after" and another's "before": its PNG is kept and reused.
  const keyOf = (query) => new URLSearchParams(Object.entries(query).sort(([a], [b]) => (a < b ? -1 : 1))).toString();
  const standing = new Map();            // key → { png, cards, layout } of the standing frames already shot
  let shotCount = 0;

  const require = createRequire(import.meta.url);
  const { chromium } = require('playwright');
  const server = await serve(LAB_ROOT);
  const browser = await chromium.launch();
  const started = Date.now();
  const lines = [];
  const say = (line) => { lines.push(line); process.stdout.write(`${line}\n`); };
  const results = [];
  let failures = 0, selfCount = 0, selfWorst = 0, grainSaid = false;
  say(`joins: sky ${options.sky} · ${chosen.length} joins × ${devices.join(', ')} × ${schemes.join(', ')} × chrome ${chromes.join(', ')} · dpr ${dpr} · t 12`);
  say(`limits: mean ≤ ${limits.mean} levels, over 2 levels ≤ ${limits.over2} %, over 6 levels ≤ ${limits.over6} %, largest ≤ ${limits.max} levels`);
  const head = `${'join'.padEnd(15)} ${'display'.padEnd(18)} ${'pair'.padEnd(6)} ${'mean'.padStart(7)} ${'>2 %'.padStart(7)} ${'>6 %'.padStart(7)} ${'max'.padStart(4)}  where`;
  try {
    const contexts = new Map();
    const contextFor = (device) => {
      if (!contexts.has(device)) {
        const preset = DEVICES[device];
        contexts.set(device, browser.newContext({ viewport: { width: Math.ceil(preset.width), height: Math.ceil(preset.height) }, deviceScaleFactor: dpr }));
      }
      return contexts.get(device);
    };
    const shootOne = async (shot, fresh = false) => {
      const kept = !fresh && !shot.query.event ? standing.get(shot.key) : null;
      if (kept) { Object.assign(shot, kept, { image: decodePng(kept.png) }); return; }
      const page = await (await contextFor(shot.device)).newPage();
      const noise = [];
      page.on('pageerror', (error) => noise.push(error.message));
      page.on('console', (message) => { if (message.type() === 'error') noise.push(message.text()); });
      try {
        const search = new URLSearchParams(shot.query).toString().replace(/%3A/gi, ':').replace(/%2C/gi, ',');
        await page.goto(`${server.origin}/index.html?${search}`, { waitUntil: 'load', timeout });
        await page.waitForFunction(() => window.__labReady === true || Boolean(window.__labError), null, { timeout });
        const problem = await page.evaluate(() => window.__labError);
        if (problem) throw new Error(problem);
        const info = await page.evaluate(() => ({ cards: window.__lab.cards, layout: window.__lab.layout }));
        shot.cards = info.cards; shot.layout = info.layout;
        const box = await page.locator('#display').boundingBox();
        shot.png = await page.screenshot({ clip: box, animations: 'disabled', caret: 'hide' });
        shot.image = decodePng(shot.png);
        shotCount += 1;
        if (noise.length) shot.error = [...new Set(noise)].join(' | ');
        if (!fresh && !shot.query.event) standing.set(shot.key, { png: shot.png, cards: shot.cards, layout: shot.layout });
      } catch (error) {
        shot.error = String(error.message ?? error).split('\n')[0];
      } finally {
        await page.close().catch(() => {});
      }
    };

    for (const join of chosen) {
      const shots = new Map();
      const want = (params, device, scheme, chrome) => {
        const query = { sky: options.sky, t: '12', dpr: String(dpr), ...extra, ...params, device, scheme, chrome };
        const key = keyOf(query);
        if (!shots.has(key)) shots.set(key, { key, query, device, image: null, png: null, cards: null, layout: null, error: null });
        return shots.get(key);
      };
      const plan = [];
      for (const device of devices) for (const scheme of schemes) for (const chrome of chromes) {
        plan.push({ join, device, scheme, chrome, frames: Object.fromEntries(framesOf(join).map((f) => [f.frame, want(f.params, device, scheme, chrome)])) });
      }
      await pool([...shots.values()], jobs, (shot) => shootOne(shot));
      say('');
      say(`${join.id} — ${join.about}`);
      for (const shot of shots.values()) {
        if (!shot.image) { failures += 1; say(`FAILED to shoot ${shot.key}: ${shot.error}`); }
        else if (shot.error) { failures += 1; say(`console error in ${shot.key}: ${shot.error}`); }
      }
      // the grain, read once from the first dark sky-only frame
      if (!grainSaid) {
        const flat = [...shots.values()].find((shot) => shot.image && shot.query.chrome === '0' && shot.query.scheme === 'dark');
        if (flat) {
          const g = grainOf(flat.image, dpr);
          say(`grain: |pixel − the mean of its 3 × 3|, green, over x 40–160, y 150–270 of ${flat.device} dark ${flat.query.time}: median ${g.median.toFixed(2)}, 90th percentile ${g.p90.toFixed(2)} levels`);
          grainSaid = true;
        }
      }
      say(head);
      for (const row of plan) {
        if (save) {
          const dir = path.join(save, join.id);
          await fsp.mkdir(dir, { recursive: true });
          for (const [frame, shot] of Object.entries(row.frames)) {
            if (shot.png) await fsp.writeFile(path.join(dir, `${row.device}-${row.scheme}-c${row.chrome}-${frame}.png`), shot.png);
          }
        }
        for (const [name, left, right] of [['start', row.frames.before, row.frames.age0], ['end', row.frames.age40, row.frames.after]]) {
          if (!left.image || !right.image) continue;
          const a = openMask(left.image.width, left.image.height, dpr, left.cards, left.layout, right.cards);
          const b = openMask(right.image.width, right.image.height, dpr, right.cards, right.layout, left.cards);
          const mask = a.map((v, i) => v & b[i]);
          const r = compare(left.image, right.image, dpr, mask);
          const ok = verdict(r, limits);
          if (!ok) failures += 1;
          const where = r.max > 0 ? `largest at (${r.maxAt.x}, ${r.maxAt.y})${r.box6 ? `; over 6 in x ${r.box6.x0}–${r.box6.x1}, y ${r.box6.y0}–${r.box6.y1}` : ''}` : 'identical';
          const display = `${row.device}-${row.scheme}-${row.chrome === '1' ? 'cards' : 'sky'}`;
          say(`${join.id.padEnd(15)} ${display.padEnd(18)} ${name.padEnd(6)} ${r.mean.toFixed(3).padStart(7)} ${r.over2.toFixed(2).padStart(7)} ${r.over6.toFixed(3).padStart(7)} ${String(r.max).padStart(4)}  ${where}  ${ok ? 'PASS' : `FAIL${join.theirs ? ` [this join also crosses a cause another pass owns: ${join.theirs}]` : ''}`}`);
          results.push({ join: join.id, device: row.device, scheme: row.scheme, chrome: row.chrome, pair: name, ...r, pass: ok });
        }
      }
      if (options.self) {
        // the same state, shot again: the lab is deterministic, so this must be 0
        const again = plan.map((row) => ({ first: row.frames.before, second: { ...row.frames.before, image: null, png: null } }));
        await pool(again, jobs, (pair) => shootOne(pair.second, true));
        for (const pair of again) {
          if (!pair.first.image || !pair.second.image) continue;
          selfCount += 1;
          selfWorst = Math.max(selfWorst, compare(pair.first.image, pair.second.image, dpr).max);
        }
      }
      for (const shot of shots.values()) shot.image = null;
    }
  } finally {
    await browser.close().catch(() => {});
    await server.close();
  }

  if (options.self) {
    say('');
    say(`self: ${selfCount} standing frames shot twice — largest difference ${selfWorst} levels${selfWorst === 0 ? ' (the same bytes)' : ''}`);
    if (selfWorst > 0) failures += 1;
  }
  say('');
  const failed = results.filter((r) => !r.pass);
  say(`joins: ${results.length - failed.length} of ${results.length} pairs within the limits (${shotCount} frames shot in ${((Date.now() - started) / 1000).toFixed(0)} s)${failed.length ? `; over: ${[...new Set(failed.map((r) => `${r.join} ${r.pair}`))].join(', ')}` : ''}`);
  say(failures ? 'joins: FAIL' : 'joins: PASS');
  if (options.json) await fsp.writeFile(path.resolve(process.cwd(), options.json), JSON.stringify({ sky: options.sky, limits, results }, null, 1));
  if (failures) process.exitCode = 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    process.stderr.write(`joins: ${error.stack ?? error}\n`);
    process.exit(1);
  });
}
