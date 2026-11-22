#!/usr/bin/env node
// Sky lab → Swift fixtures: the lab's hash and noise, the land's skyline, and his stars.
//
//     node design/sky-lab/tools/swift-fixtures/stars.mjs            (writes TwoOfUsTests/SkyCoreFixturesStars.swift)
//     node design/sky-lab/tools/swift-fixtures/stars.mjs --check    (writes nothing; exits 1 if the file on disk is stale)
//     node design/sky-lab/tools/swift-fixtures/stars.mjs --dump f   (also writes every list at full precision to f, as JSON: for chasing a place that disagrees)
//
// The painted hill is being built in SwiftUI (TwoOfUs/Sky/Core: SkyNoise, Skyline, StarChart). Their
// unit tests do not restate the Swift: they compare it with what THE LAB says, and this script is
// where the lab says it. Nothing below is typed by hand — every number is read out of the lab's own
// code as it runs:
//
//   · lab/noise.js and lab/nights.js are imported and called (hash2, rng, noise2, fbm2, fbm1; the
//     per-night hash and `nights()`);
//   · skies/hill-painted.js keeps its own lattice noise (vn, fb), the land's skyline, the star
//     keep-outs and `starsFor` inside the module and exports none of them. So the lab's page is
//     opened in headless Chromium (Playwright, as tools/joins.mjs does) and the sky module is
//     served with a few lines ADDED IN TRANSIT — never on disk — that leave those names on
//     `globalThis.__hpProbe`, read-only, and note HOW each star came to its place (its first cast,
//     the k-th cast again, the spiral) on the list `starsFor` builds. None of them changes what
//     the module computes;
//   · for every display and age the page is really drawn at night (`__lab.set({ age })`, 21:00, a
//     night sleep running: the night has begun), and the list read is THE MODULE'S OWN — the one
//     it has just drawn (`G.stars`), with the census it publishes (`window.__hillPainted.stars`)
//     and the layout the page measured for that age (the age line's width changes with it);
//   · a few more skies are cast by calling `starsFor` with a state of this script's making (a
//     far older child, a long name, a header with nothing measured, a wall of words that leaves
//     the sky a narrow band, a name that ends just short of the first night's own place): they are
//     there to drive the rules the standard ages never reach — the spiral, a place that cannot be
//     found, the first night's place asked for as an ordinary night's — and are marked `cast`, not
//     `drawn`;
//   · and for two of the drawn skies the module's own `free` — the rule a place is judged by —
//     is asked about some 1,500 places chosen to lie a tenth of a point either side of every
//     distance the rule keeps.
//
// If the sky module changes shape (a name is renamed, a marked line reworded) this script stops and
// says which mark it could not find: fix the mark here, never the number in the Swift.

import http from 'node:http';
import fsp from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { DEVICES } from '../../lab/core.js';
import { hash, nights } from '../../lab/nights.js';
import { hash2, rng, noise2, fbm2, fbm1 } from '../../lab/noise.js';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const LAB_ROOT = path.resolve(HERE, '..', '..');
const REPO_ROOT = path.resolve(LAB_ROOT, '..', '..');
const OUT = path.join(REPO_ROOT, 'TwoOfUsTests', 'SkyCoreFixturesStars.swift');
const SKY = 'hill-painted';
const SKY_PATH = `/skies/${SKY}.js`;

const fail = (message) => { process.stderr.write(`stars.mjs: ${message}\n`); process.exit(1); };

// ───────────────────────────────────────────────── the sky module, in transit ──

/** [what it is, the line as the module has it, the line as it is served]. Each must be found exactly once. */
const TRANSIT = [
  ['return { render, destroy, ready }',
    '  return { render, destroy, ready };',
    '  globalThis.__hpProbe = { DUO, SLAB, G: () => G, starsFor, starKeepOuts, vn, fb, crownTop, hash };\n  return { render, destroy, ready };'],
  // how a star came to its place: 0 its first cast …
  ['starsFor: a night\'s first cast',
    '      let { x, y } = at;',
    '      let { x, y } = at; G.__how = 0;'],
  // … (if nothing is found at all it stands where it was first cast: every cast and the spiral's 480 steps tried, and one more)
  ['starsFor: the search begins',
    '        let found = false;',
    '        let found = false; G.__how = (big ? 270 : 30) + 481;'],
  // … the k-th cast again (a four-point star: 90 with 80 pt between two of them, 90 with 60, 90 with 44) …
  ['starsFor: cast again',
    'if (free(again.x, again.y, big, pair)) { x = again.x; y = again.y; found = true; }',
    'if (free(again.x, again.y, big, pair)) { x = again.x; y = again.y; found = true; G.__how = (pair === 60 ? 90 : pair === 44 ? 180 : 0) + k; }'],
  // … or, after them, the n-th step of the spiral
  ['starsFor: the spiral',
    'if (free(nx, ny, big, 20)) { x = nx; y = ny; found = true; break; }',
    'if (free(nx, ny, big, 20)) { x = nx; y = ny; found = true; G.__how = (big ? 270 : 30) + (ring - 1) * 12 + k + 1; break; }'],
  ['starsFor: the entry',
    '      const entry = { ...star, lx: x, ly: y };',
    '      const entry = { ...star, lx: x, ly: y, how: G.__how };'],
  // the rules it placed them by: the floor's samples are read from it, and `free` is asked about
  // places of this script's choosing once the sky is cast
  ['starsFor: its result',
    '    G.stars = { key, list, far, tonightLook };',
    '    G.__starParts = { floor, free, outs, cardEdges, xMin, xMax, yMin, apart };\n    G.stars = { key, list, far, tonightLook };'],
];

function inTransit(source) {
  let out = source;
  for (const [what, from, to] of TRANSIT) {
    const parts = out.split(from);
    if (parts.length !== 2) fail(`${SKY}.js: expected exactly one "${what}" (found ${parts.length - 1}). The sky module has changed shape: update the mark in tools/swift-fixtures/stars.mjs.`);
    out = parts[0] + to + parts[1];
  }
  return out;
}

// ─────────────────────────────────────────────────────────────── the page ──

const TYPES = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json', '.png': 'image/png', '.jpg': 'image/jpeg',
  '.webp': 'image/webp', '.svg': 'image/svg+xml', '.woff2': 'font/woff2', '.woff': 'font/woff', '.ttf': 'font/ttf',
  '.otf': 'font/otf', '.txt': 'text/plain; charset=utf-8',
};

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

// ───────────────────────────────────────────────────────────── the samples ──

/** The lab's displays, and what the Swift calls them (the slab is the lab's `iphone`). */
const DISPLAYS = [['cover', 'cover'], ['spread', 'spread'], ['slab', 'iphone']];
/** Whole days of age: the first night, the first week, a month, the first two month-nights' own
 *  nights (61, 92: tonight IS a month-night), the default day and the day after, and on to two years. */
const AGES = [0, 1, 7, 30, 61, 92, 142, 143, 200, 300, 367, 368, 560, 730];
/** The ages whose keep-outs are written out… */
const DETAIL_AGES = [0, 142, 300];
/** …and those whose leading-page stars are (the spread's; nobody's stars). */
const PAGE_AGES = [0, 92, 142, 300, 730];
const DEFAULT_AGE = 142;

/** The skies cast with a state of this script's making: [name, display, what is changed]. */
const EXTRA = [
  // far past two years: the sky is full, and a night's every cast is taken — the spiral
  ['old', 'cover', { ageDays: 1500 }],
  ['old', 'slab', { ageDays: 1500 }],
  // a long name and a long age line (the header's block reaches the gear)
  ['longName', 'cover', { ageDays: 368, name: { dw: 110 }, age: { dw: 120 } }],
  ['longName', 'slab', { ageDays: 368, name: { dw: 130 }, age: { dw: 140 } }],
  // nothing measured in the header at all, and no strip window told
  ['bare', 'cover', { ageDays: 142, bare: true }],
  ['bare', 'slab', { ageDays: 142, bare: true }],
  // only the avatar and the gear (no words yet)
  ['buttons', 'spread', { ageDays: 200, buttons: true }],
  // a wall of words: the header's block covers all but a band of the sky, so an ordinary night
  // runs out of casts too, goes to the spiral, and at last finds nowhere
  ['crowded', 'cover', { ageDays: 260, wall: 236 }],
  ['crowded', 'slab', { ageDays: 260, wall: 520 }],
  // his name's block ends 5 pt short of the first night's own place (looked-up x): nearer than a four-point
  // star may stand to words (9 pt), not nearer than an ordinary night may — the place is asked for as an
  // ordinary night's (`free(c.firstUp.x, c.firstUp.y, false)`), so it is kept
  ['nameEnds', 'cover', { ageDays: 142, nameEnds: 5 }],
];
/** Coordinates past 2⁶³, where a port's conversion to a whole number would trap: JavaScript's `| 0` still
 *  wraps them, and the lab's noise there is a lattice value like any other. [x, y, seed]
 *  (None so large that doubling it for a second octave overflows: that is NaN, whose bits are the machine's.) */
const FAR_OUT = [[1e19, -3e25, 7], [-9.3e18, 2 ** 63, 0], [2 ** 64 + 2 ** 12, -(2 ** 70), 23], [1.5e300, -4e307, 3]];
/** The drawn skies whose `free` is probed: [display, age]. */
const PROBED = [['cover', 142], ['slab', 368]];

/** A double's 64 bits, as 16 hex digits. */
const bits = (v) => { const b = Buffer.alloc(8); b.writeDoubleBE(v); return b.toString('hex'); };
/** A float32's 32 bits (the value must BE a float32), as 8 hex digits; `inf` where there is none. */
const bits32 = (v) => {
  if (v === Infinity) return 'inf';
  if (Math.fround(v) !== v) fail(`not a float32: ${v}`);
  const b = Buffer.alloc(4); b.writeFloatBE(v); return b.toString('hex');
};
const hex8 = (u) => (u >>> 0).toString(16).padStart(8, '0');
/** A number as the fixtures print it: at most `places` decimals, no trailing zeros. */
const num = (v, places = 7) => {
  if (v == null) return 'nil';
  if (typeof v !== 'number' || !Number.isFinite(v)) fail(`not a finite number: ${v}`);
  const r = Number(v.toFixed(places));
  return Object.is(r, -0) ? '0' : String(r);
};
/** Hundredths of a point, whole. */
const cents = (v) => String(Math.round(v * 100));
const rectText = (r) => (r ? [r.x, r.y, r.width, r.height].map((v) => num(v, 4)).join(',') : 'nil');
/** Tokens, wrapped into lines of about `width` characters. */
function wrap(tokens, width = 150) {
  const lines = [];
  let line = '';
  for (const token of tokens) {
    if (line && line.length + 1 + token.length > width) { lines.push(line); line = ''; }
    line += (line ? ' ' : '') + token;
  }
  if (line) lines.push(line);
  return lines;
}

/** Values in runs of `per`, each line headed by `head(the index of its first value)`. */
function runs(head, values, per = 200) {
  const lines = [];
  for (let i = 0; i < values.length; i += per) lines.push([head(i), ...values.slice(i, i + per)].join(' '));
  return lines;
}

/** A small seeded sequence for the sample points (the lab's own `hash`, so the samples never change). */
const sample = (i, salt, span) => Number(((hash(i, salt) - 0.5) * 2 * span).toFixed(4));

// ─────────────────────────────────────────────────────────────── writing ──

function swiftFile(sections) {
  const lines = [];
  lines.push('// GENERATED by design/sky-lab/tools/swift-fixtures/stars.mjs — do not edit by hand.');
  lines.push('// Regenerate:  node design/sky-lab/tools/swift-fixtures/stars.mjs');
  lines.push('// (Node 22 and Playwright with Chromium; `--check` only compares.)');
  lines.push('//');
  lines.push('// What the sky lab says about its hash and noise, the land\'s skyline and his stars — read out');
  lines.push('// of the lab\'s own code as it runs (lab/noise.js, lab/nights.js, and the closure of');
  lines.push(`// skies/${SKY}.js on the lab's page, where every sky here was cast and all but the ones marked`);
  lines.push('// `cast` really drawn). The tests of SkyNoise, Skyline and StarChart compare the Swift with');
  lines.push('// these; a change in the lab shows up here as a diff and there as a failing test.');
  lines.push('');
  lines.push('import Foundation');
  lines.push('');
  lines.push('/// The lab\'s numbers for `SkyNoiseTests`, `SkylineTests` and `StarChartTests` (and the distances of');
  lines.push('/// `SkyMathTests`), as compact text. Bit patterns are hex (16 digits a double, 8 a float or a 32-bit');
  lines.push('/// hash); places are whole hundredths of a point. Data only: read with `SkyCoreFixture.words`,');
  lines.push('/// `SkyCoreFixture.double(bits:)` and `SkyCoreFixture.float(bits:)` (TwoOfUsTests/SkyCoreFixture.swift).');
  lines.push('enum SkyCoreFixturesStars {');
  for (const [name, doc, body] of sections) {
    for (const d of doc) lines.push(`    /// ${d}`);
    lines.push(`    static let ${name} = """`);
    for (const row of body) {
      if (/["\\]/.test(row)) fail(`a fixture line cannot be written as it stands: ${row}`);
      lines.push(`        ${row}`);
    }
    lines.push('        """');
    if (name !== sections[sections.length - 1][0]) lines.push('');
  }
  lines.push('}');
  lines.push('');
  return lines.join('\n');
}

// ────────────────────────────────────────────────────────────────── main ──

async function main() {
  const check = process.argv.includes('--check');
  const dumpAt = process.argv.indexOf('--dump');
  const dumpFile = dumpAt >= 0 ? process.argv[dumpAt + 1] : null;
  const dump = { skies: [] };
  const skySource = await fsp.readFile(path.join(LAB_ROOT, 'skies', `${SKY}.js`), 'utf8');
  const require = createRequire(import.meta.url);
  const { chromium } = require('playwright');
  const server = await serve(LAB_ROOT, inTransit(skySource));
  const browser = await chromium.launch();
  const timeout = 90_000;

  async function open(device) {
    const preset = DEVICES[device];
    const context = await browser.newContext({ viewport: { width: Math.ceil(preset.width), height: Math.ceil(preset.height) }, deviceScaleFactor: 1 });
    const page = await context.newPage();
    const noise = [];
    page.on('pageerror', (error) => noise.push(error.message));
    const search = new URLSearchParams({ sky: SKY, device, dpr: '1', t: '12', chrome: '0', time: '21:00', asleep: 'night' }).toString().replace(/%3A/gi, ':');
    await page.goto(`${server.origin}/index.html?${search}`, { waitUntil: 'load', timeout });
    await page.waitForFunction(() => window.__labReady === true || Boolean(window.__labError), null, { timeout });
    const problem = await page.evaluate(() => window.__labError);
    if (problem || noise.length) fail(`the lab's page: ${problem ?? noise.join(' | ')}`);
    if (!(await page.evaluate(() => Boolean(globalThis.__hpProbe)))) fail('the probe did not reach the page');
    return { page, close: () => context.close() };
  }

  // ── the hash and the noise that are plain modules (lab/nights.js, lab/noise.js) ──
  const hashes = [];
  for (const salt of [1, 2, 3, 4, 5, 6, 7, 8, 9]) hashes.push(...runs((i) => `run ${salt} ${1 + i}`, Array.from({ length: 200 }, (_, i) => hex8(hash(1 + i, salt) * 4294967296))));
  for (const salt of [31, 41, 42, 43, 44, 45, 46, 47, 48, 49]) hashes.push(...runs((i) => `run ${salt} ${i}`, Array.from({ length: 60 }, (_, i) => hex8(hash(i, salt) * 4294967296))));
  hashes.push(...runs((i) => `run 0 ${i - 40}`, Array.from({ length: 80 }, (_, i) => hex8(hash(i - 40) * 4294967296))));
  // (whole numbers past 32 bits and negative salts: JavaScript's `| 0` wraps them, and so must the Swift)
  for (const [n, salt] of [[0, 0], [-1, 0], [2147483647, 1], [2147483648, 1], [-2147483648, 2], [4294967296 + 5, 3], [-4294967301, 3], [123456789, -1], [7, -2147483648], [7, 2147483647], [9007199254740991, 4], [1e6, 1e6]]) {
    hashes.push(`one ${n} ${salt} ${hex8(hash(n, salt) * 4294967296)}`);
  }

  const lattice = [];
  for (const seed of [0, 23, 41]) {
    for (let y = -3; y < 13; y += 1) lattice.push([`run ${seed} ${y} -5`, ...Array.from({ length: 32 }, (_, i) => hex8(hash2(i - 5, y, seed) * 4294967296))].join(' '));
  }
  for (const [x, y, seed] of [[0, 0, 0], [255, 255, 23], [-1, -1, -1], [2147483647, -2147483648, 5], [4294967296 + 3, 7, 2147483647], [1e6, -1e6, 131 * 4], [65535, 2, 43]]) {
    lattice.push(`one ${x} ${y} ${seed} ${hex8(hash2(x, y, seed) * 4294967296)}`);
  }

  const sequences = [];
  for (const seed of [1, 0, 20260702, 4294967295, 123456789]) {
    const next = rng(seed);
    sequences.push([String(seed), ...Array.from({ length: 48 }, () => hex8(next() * 4294967296))].join(' '));
  }

  const noise = [];
  // (on a lattice point, half-way, just under one, negative, far out — then a spread)
  const points = [[0, 0], [1, 1], [0.5, 0.5], [-0.5, 2.25], [3, -7], [0.999999, 0.000001], [-12.75, -0.125], [255.5, 255.5], [256, -256], [1000.3, -2000.7], [-0, 0], [17.3, -9.1]];
  for (let i = 0; i < 260; i += 1) points.push([sample(i, 101, 300), sample(i, 102, 300)]);
  points.slice(0, 172).forEach(([x, y], i) => {
    const seed = [0, 3, 23, 131, -5][i % 5];
    noise.push(`noise2 ${x} ${y} ${seed} ${bits(noise2(x, y, seed))}`);
  });
  points.slice(0, 100).forEach(([x, y], i) => {
    noise.push(`fbm2 ${x} ${y} 5 0.5 2 0 ${bits(fbm2(x, y))}`);
    const o = { octaves: 1 + (i % 6), gain: [0.5, 0.6, 0.45][i % 3], lacunarity: [2, 2.1, 1.9][i % 3], seed: [7, 0, 23, -2][i % 4] };
    noise.push(`fbm2 ${x} ${y} ${o.octaves} ${o.gain} ${o.lacunarity} ${o.seed} ${bits(fbm2(x, y, o))}`);
  });
  points.slice(0, 60).forEach(([x], i) => {
    const o = { octaves: 2 + (i % 4), gain: 0.5, lacunarity: 2, seed: i % 9 };
    noise.push(`fbm1 ${x} ${o.octaves} ${o.gain} ${o.lacunarity} ${o.seed} ${bits(fbm1(x, o))}`);
  });
  for (const [x, y, seed] of FAR_OUT) noise.push(`noise2 ${x} ${y} ${seed} ${bits(noise2(x, y, seed))}`);

  // ── every night's own numbers (lab/nights.js): the first 160 nights, then every seventh to two years ──
  const everyNight = nights(730, { tonightLit: true });
  const nightRows = [['night', 'kind', 'u', 'v', 'magnitude', 'warmth', 'period', 'phase', 'steady'].join(' ')];
  for (const q of everyNight) {
    if (q.night > 160 && q.night % 14 !== 0 && q.night !== 731) continue;
    nightRows.push([q.night, q.kind, bits(q.u), bits(q.v), num(q.magnitude, 13), num(q.warmth, 13), num(q.twinkle.period, 13), num(q.twinkle.phase, 13), q.twinkle.steady ? 1 : 0].join(' '));
  }
  const monthNights = everyNight.filter((q) => q.kind === 'month').map((q) => q.night);

  const drift = [];           // the sky module's own lattice noise, and V8's hypot
  const land = [];            // the crests, the skyline, the tree's foot, the floor
  const keepOuts = [];
  const rooms = [];
  const skies = [];
  const pages = [];
  let drawn = 0, unlit = 0;
  const stats = { first: 0, again: 0, spiral: 0, nowhere: 0, most: 0 };

  /** One sky, written: its head (the layout it was cast for, the module's census) and every star. */
  function writeSky(mode, name, display, out) {
    const L = out.layout ?? {};
    const sum = out.list.reduce((a, q) => [a[0] + q.lx, a[1] + q.ly], [0, 0]);
    skies.push(['@', mode, name, display, out.ageDays, `anchor=${num(out.ox)},${num(out.Wa)}`, `size=${num(out.W)},${num(out.H)}`,
      `strip=${L.stripClear ? num(L.stripClear.x, 4) : 'nil'}`, `name=${rectText(L.name)}`, `age=${rectText(L.age)}`,
      `avatar=${rectText(L.avatar)}`, `gear=${rectText(L.gear)}`,
      `census=${out.census ? [out.census.total, out.census.rest, out.census.up].join(',') : 'nil'}`,
      `sum=${num(sum[0], 6)},${num(sum[1], 6)}`].join(' '));
    const tokens = out.list.map((q) => {
      const how = q.kind === 'tonight' || q.how == null ? '' : (q.how > 0 ? String(q.how) : '');
      const code = `${q.kind === 'night' ? (how ? 'n' : '') : q.kind[0]}${how}`;
      for (const k of ['night', 'month', 'first', 'tonight']) if (k !== q.kind && k[0] === q.kind[0]) fail('two kinds share a letter');
      if (q.kind === 'tonight') {
        if (q.x !== out.tonight.x || q.y !== out.tonight.y) fail(`${display} ${out.ageDays}: tonight's star is not at its rest home`);
      } else if (q.x !== q.lx + out.T || q.y !== q.ly - out.D) fail(`${display} ${out.ageDays}: night ${q.night} at rest is not its looked-up place turned back and lowered`);
      return `${cents(q.lx)},${cents(q.ly)}${code ? `,${code}` : ''}`;
    });
    skies.push(...wrap(tokens));
    out.list.forEach((q, i) => {
      if (q.night !== i + 1) fail(`${display} ${out.ageDays}: the list is not night by night`);
      if (q.kind === 'tonight' || q.how == null) return;
      const base = q.kind === 'night' ? 30 : 270;
      if (q.how === 0) stats.first += 1; else if (q.how <= base) stats.again += 1; else if (q.how <= base + 480) stats.spiral += 1; else stats.nowhere += 1;
      stats.most = Math.max(stats.most, q.how);
    });
    dump.skies.push({ mode, name, display, age: out.ageDays, layout: out.layout, ox: out.ox, Wa: out.Wa,
      list: out.list.map((q) => [q.night, q.kind, q.lx, q.ly, q.how ?? null]), far: out.far });
  }

  try {
    const seenWorlds = new Set();
    let coverLand = null;
    for (const [name, device] of DISPLAYS) {
      const { page, close } = await open(device);

      // ── once: the sky module's lattice noise, the page's hypot, the crown's outline ──
      {
        if (!drift.length) {
          const got = await page.evaluate((pts) => {
            const P = globalThis.__hpProbe;
            return {
              vn: pts.slice(0, 172).map(([x, y]) => P.vn(x, y)),
              fb: pts.slice(0, 172).map(([x, y], i) => P.fb(x, y, 1 + (i % 4))),
              // (the drift of his stars, as starsFor asks for it)
              knots: pts.slice(0, 80).map(([x, y]) => [P.fb(Math.abs(x) / 150 + 3.7, Math.abs(y) / 150 + 1.3, 2), P.fb(Math.abs(x) / 150 + 9.1, Math.abs(y) / 150 + 6.6, 2)]),
              hypot: pts.slice(0, 150).map(([x, y]) => Math.hypot(x, y)),
              crown: Array.from({ length: 141 }, (_, i) => P.crownTop((i - 70) / 100)),
            };
          }, points);
          points.slice(0, 172).forEach(([x, y], i) => drift.push(`vn ${x} ${y} ${bits(got.vn[i])}`));
          points.slice(0, 172).forEach(([x, y], i) => drift.push(`fb ${x} ${y} ${1 + (i % 4)} ${bits(got.fb[i])}`));
          points.slice(0, 80).forEach(([x, y], i) => drift.push(`knots ${Math.abs(x)} ${Math.abs(y)} ${bits(got.knots[i][0])} ${bits(got.knots[i][1])}`));
          points.slice(0, 150).forEach(([x, y], i) => drift.push(`hypot ${x} ${y} ${bits(got.hypot[i])}`));
          for (const [a, b] of [[3, 4], [130, -4], [50, 0], [0, 0], [0, -7.5], [1e-200, 1e-200], [1e200, 1e200], [0.1, 0.2]]) {
            drift.push(`hypot ${a} ${b} ${bits(await page.evaluate(([p, q]) => Math.hypot(p, q), [a, b]))}`);
          }
          const farOut = await page.evaluate((pts) => pts.map(([x, y]) => [globalThis.__hpProbe.vn(x, y), globalThis.__hpProbe.fb(x, y, 2)]), FAR_OUT);
          FAR_OUT.forEach(([x, y], i) => { drift.push(`vn ${x} ${y} ${bits(farOut[i][0])}`); drift.push(`fb ${x} ${y} 2 ${bits(farOut[i][1])}`); });
          land.push(...runs((i) => `crown ${i - 70}`, got.crown.map((v) => (v == null ? 'nil' : bits(v))), 100));
        }
      }
      // ── once per world: its crests and skyline, the floor under his stars. The cover does not build
      // the crests it never sees (the leading page's): the Duo's land is read on the spread, and the
      // cover's must be the same wherever the cover looks ──
      {
        const world = await page.evaluate(() => {
          const P = globalThis.__hpProbe, G = P.G(), c = G.cfg;
          const shapes = [];
          let index = 0;
          for (const plane of c.planes) {
            for (const def of plane.shapes) {
              if (def.mist) continue;
              index += 1;
              shapes.push({ plane: plane.id, sink: plane.sink, id: def.id, index, wob: def.wob ?? 1, floor: Boolean(def.floor), crest: def.crest });
            }
          }
          const xs = [];
          const from = Math.min(...shapes.map((sh) => sh.crest[0][0])), to = Math.max(...shapes.map((sh) => sh.crest[sh.crest.length - 1][0]));
          for (let x = from - 3; x <= to + 3; x += 1) xs.push(x);
          const halves = [100.5, 101.5, 100.49999, -0.5, -1.5, 250.5000001, 407.5, 408.4999, from - 0.5, to + 0.5];
          const parts = G.__starParts;
          const floorXs = [];
          for (let x = parts.xMin; x <= parts.xMax; x += 1) floorXs.push(x);
          return { kind: c.kind, shapes, from: from - 3, seen: [G.xL, G.xR], skyline: xs.map((x) => G.skyline(x)), halves: halves.map((x) => [x, G.skyline(x)]),
            treeFoot: G.tree.baseY, floorFrom: parts.xMin, floor: floorXs.map((x) => parts.floor(x)), floorHalf: floorXs.map((x) => parts.floor(x + 0.37)),
            apart: parts.apart, field: [parts.xMin, parts.xMax, parts.yMin] };
        });
        const k = world.kind;
        if (name === 'cover') { coverLand = world; }
        if (name === 'spread') {
          if (!coverLand || coverLand.kind !== k || coverLand.from !== world.from) fail('the cover and the spread are not windows on one world');
          let same = 0;
          world.skyline.forEach((y, i) => {
            const x = world.from + i;
            if (x < coverLand.seen[0] || x > coverLand.seen[1]) return;
            if (!Object.is(y, coverLand.skyline[i])) fail(`the cover's skyline is not the spread's at world x ${x}`);
            same += 1;
          });
          if (same < 600 || coverLand.treeFoot !== world.treeFoot || coverLand.floor.some((v, i) => v !== world.floor[i])) fail('the cover and the spread do not share their land');
        }
        if (name !== 'cover') {
        if (seenWorlds.has(k)) fail(`two displays wrote the ${k} world's land`);
        seenWorlds.add(k);
        for (const sh of world.shapes) {
          land.push(`${k}.shape ${sh.id} ${sh.plane} ${num(sh.sink)} ${sh.index} ${num(sh.wob)} ${sh.floor ? 'floor' : 'crest'} ${sh.crest.flat().map((v) => num(v)).join(' ')}`);
        }
        land.push(...runs((i) => `${k}.skyline ${world.from + i}`, world.skyline.map(bits32)));
        for (const [x, y] of world.halves) land.push(`${k}.at ${x} ${bits32(y)}`);
        land.push(`${k}.treeFoot ${bits(world.treeFoot)}`);
        land.push(`${k}.field ${world.field.map((v) => num(v)).join(' ')} ${num(world.apart)}`);
        land.push(...runs((i) => `${k}.floor ${world.floorFrom + i} 0`, world.floor.map((v) => num(v, 4))));
        land.push(...runs((i) => `${k}.floor ${world.floorFrom + i} 0.37`, world.floorHalf.map((v) => num(v, 4))));
        }
      }

      // ── the standard ages: really drawn at night, the module's own list ──
      for (const age of AGES) {
        const out = await page.evaluate(async (ageDays) => {
          await window.__lab.set({ age: ageDays });
          const P = globalThis.__hpProbe, G = P.G(), c = G.cfg, st = window.__lab.state;
          const S = G.stars;
          const pick = (q) => ({ night: q.night, kind: q.kind, lx: q.lx, ly: q.ly, x: q.x, y: q.y, how: q.how ?? null });
          const list = S.list.map(pick);
          const far = S.far.map((f) => [f.x, f.y, f.m, f.r, f.a, f.tint, f.phase, f.period, f.steady]);
          const key = S.key;
          const census = window.__hillPainted.stars;
          // the same sky before he is down: the night has not begun, tonight's star is not lit
          const before = P.starsFor({ ...st, nightBegun: false, tonightLit: false }).list.map(pick);
          const back = P.starsFor(st);
          return { ageDays: st.ageDays, begun: st.nightBegun, key, sameKey: back.key === key, layout: JSON.parse(JSON.stringify(st.layout)), ox: G.ox, Wa: G.Wa, W: G.W, H: G.H,
            T: c.T, D: c.D, tonight: c.tonight, list, far, before,
            census: census ? { total: census.total, rest: census.rest, up: census.up } : null,
            outs: P.starKeepOuts(st) };
        }, age);
        if (out.ageDays !== age || out.begun !== true || !out.key.startsWith(`${age}|true|`) || !out.sameKey) fail(`${device} at ${age} days: the page did not draw that night (${out.key})`);
        if (!out.census || out.census.total !== out.list.length) fail(`${device} at ${age} days: the module's census (${JSON.stringify(out.census)}) is not of the list read (${out.list.length})`);
        // tonight's star takes nobody's place: before he is down the sky is the same, less that one star
        if (out.before.length !== out.list.length - 1 || out.before.some((q, i) => q.lx !== out.list[i].lx || q.ly !== out.list[i].ly || q.kind !== out.list[i].kind)) {
          fail(`${device} at ${age} days: lighting tonight's star moved another`);
        }
        unlit += 1;
        drawn += 1;
        writeSky('drawn', 'lab', name, out);
        if (PROBED.some(([d, a]) => d === name && a === age)) {
          const asked = await page.evaluate(() => {
            const P = globalThis.__hpProbe, G = P.G(), c = G.cfg, R = G.__starParts, list = G.stars.list;
            const pts = [];
            const add = (x, y) => pts.push([Math.round(x * 100) / 100, Math.round(y * 100) / 100]);
            const ring = (cx, cy, radii, n, turn) => {
              for (const r of radii) for (let i = 0; i < n; i += 1) { const a = (i / n + turn) * Math.PI * 2; add(cx + Math.cos(a) * r, cy + Math.sin(a) * r); }
            };
            // tonight's two homes, and the first night's own place
            ring(c.tonightUp.x, c.tonightUp.y, [30 * c.starScale - 0.1, 30 * c.starScale + 0.1, 69.9, 70.1], 10, 0.03);
            ring(c.tonight.x - c.T, c.tonight.y + c.D, [16.9, 17.1], 10, 0.07);
            if (c.firstUp) ring(c.firstUp.x, c.firstUp.y, [17.9, 18.1, 59.9, 60.1], 10, 0.01);
            // round the four-point stars: the room an ordinary night keeps from one, and two of them from each other
            list.filter((q) => q.kind === 'month' || q.kind === 'first').slice(0, 5)
              .forEach((q, i) => ring(q.lx, q.ly, [10.5, 10.7, 19.9, 20.1, 43.9, 44.1, 59.9, 60.1, 79.9, 80.1], 4, 0.11 + i * 0.07));
            // round a few ordinary nights: never closer than 5.6 pt, a four-point star 5 pt more
            list.filter((q) => q.kind === 'night').slice(0, 6).forEach((q, i) => ring(q.lx, q.ly, [5.5, 5.7, 10.5, 10.7], 4, 0.05 + i * 0.09));
            // across each edge of each keep-out: an ordinary night's line, and a four-point star's 9 pt out
            for (const r of R.outs) {
              const mx = (r.x0 + r.x1) / 2 + 1.7, my = (r.y0 + r.y1) / 2 + 1.3;
              for (const d of [-0.1, 0.1, 8.9, 9.1]) { add(r.x0 - d, my); add(r.x1 + d, my); add(mx, r.y0 - d); add(mx, r.y1 + d); }
            }
            // 10 pt either side of every card's edge
            for (const [x0, y0, x1, y1] of R.cardEdges) {
              const mx = (x0 + x1) / 2 + 3.3, my = (y0 + y1) / 2 + 2.2;
              for (const d of [-10.1, -9.9, 9.9, 10.1]) { add(x0 - d, my); add(x1 + d, my); add(mx, y0 - d); add(mx, y1 + d); }
            }
            // the display's own edges, looking up and at rest
            for (const y of [R.yMin - 0.1, R.yMin + 0.1, R.yMin + 1.9, R.yMin + 2.1, c.D - 9.1, c.D - 8.9, c.D + 8.9, c.D + 9.1]) for (const x of [140.3, 250.7, 330.2]) add(x, y);
            for (const x of [R.xMin - 0.1, R.xMin + 0.1, R.xMin + 1.9, R.xMin + 2.1, R.xMax - 2.1, R.xMax - 1.9, R.xMax - 0.1, R.xMax + 0.1,
              G.Wa - c.T - 7.1, G.Wa - c.T - 6.9, G.Wa - c.T + 6.9, G.Wa - c.T + 7.1]) for (const y of [120.4, c.D - 20.3, c.D + 30.6, c.D + 120.2]) add(x, y);
            // (…the trailing side of the rest view, all the way down it: most of that line is behind something else)
            for (const x of [G.Wa - c.T - 7.1, G.Wa - c.T - 6.9, G.Wa - c.T + 6.9, G.Wa - c.T + 7.1]) {
              for (const dy of [-8.5, 12.7, 55.1, 71.3, 97.9, 150.4, 186.2, 240.8]) add(x, c.D + dy);
            }
            // the land and the tree's crown
            for (let x = R.xMin + 3; x < R.xMax; x += 23) { const f = R.floor(x); add(x, f - 0.1); add(x, f + 0.1); }
            // and anywhere
            for (let i = 0; i < 120; i += 1) add(P.hash(i, 201) * G.Wa, P.hash(i, 202) * (c.H0 + c.D));
            return pts.map(([x, y]) => [x, y, (R.free(x, y, false) ? 1 : 0) + (R.free(x, y, true) ? 2 : 0) + (R.free(x, y, true, 60) ? 4 : 0)
              + (R.free(x, y, true, 44) ? 8 : 0) + (R.free(x, y, true, 20) ? 16 : 0)]);
          });
          const tally = [0, 0, 0, 0, 0];
          for (const [, , b] of asked) for (let i = 0; i < 5; i += 1) if (b & (1 << i)) tally[i] += 1;
          rooms.push(`@ ${name} ${age} asked=${asked.length} free=${tally.join(',')}`);
          rooms.push(...wrap(asked.map(([x, y, b]) => `${num(x, 2)},${num(y, 2)},${b}`)));
        }
        if (DETAIL_AGES.includes(age)) {
          keepOuts.push(`${name} ${age} ${out.outs.map((r) => [r.x0, r.y0, r.x1, r.y1].map((v) => num(v, 6)).join(',')).join(' ')}`);
        }
        if (name === 'spread' && !out.far.length) fail('the spread has no leading-page stars');
        if (name !== 'spread' && out.far.length) fail(`${device}: a display with no leading page has leading-page stars`);
        if (name === 'spread' && PAGE_AGES.includes(age)) {
          const L = out.layout;
          pages.push(['@', name, age, `title=${rectText(L.title)}`, `subtitle=${rectText(L.subtitle)}`, `count=${out.far.length}`,
            `sum=${num(out.far.reduce((a, f) => a + f[0], 0), 6)},${num(out.far.reduce((a, f) => a + f[1], 0), 6)}`].join(' '));
          pages.push(...wrap(out.far.map((f) => (age === DEFAULT_AGE
            ? `${cents(f[0])},${cents(f[1])},${num(f[2], 6)},${num(f[3], 6)},${num(f[4], 6)},${f[5]},${num(f[6], 6)},${num(f[7], 6)},${f[8] ? 1 : 0}`
            : `${cents(f[0])},${cents(f[1])}`))));
        }
      }

      // ── the leading page's sky once more, behind a title cut to end where the 22 pt of plain sky kept
      // past its last glyph hold ONE MORE of the page's stars, by half a point: the pad's own width, which
      // no title the page really shows happens to test ──
      if (name === 'spread') {
        const padded = await page.evaluate(async (base) => {
          await window.__lab.set({ age: base });
          const P = globalThis.__hpProbe, G = P.G(), st = window.__lab.state;
          const L = JSON.parse(JSON.stringify(st.layout));
          if (!L.title || !L.subtitle) return null;
          const cast = (layout) => { G.stars.key = ''; return P.starsFor({ ...st, layout }).far.map((f) => [f.x, f.y]); };
          const standing = cast(L);
          // the nearest star past the title's end, in its rows (rest-pose y, as the rule asks)
          const y0 = L.title.y - 8, y1 = L.subtitle.y + L.subtitle.height + 8;
          const end = L.title.x - G.ox + Math.max(L.title.width, L.subtitle.width) + 22;
          const next = standing.filter((f) => f[1] > y0 && f[1] < y1 && f[0] > end).sort((a, b) => a[0] - b[0])[0];
          if (!next) return null;
          // (to the hundredth of a point, as a rect is written out below)
          const width = Math.round((next[0] + 0.5 - 22 - (L.title.x - G.ox)) * 100) / 100;
          const layout = { ...L, title: { ...L.title, width }, subtitle: { ...L.subtitle, width: Math.min(L.subtitle.width, width) } };
          const far = cast(layout);
          P.starsFor(st);
          return { layout, far, standing: standing.length, inside: L.title.x - G.ox + width + 22 - next[0] };
        }, DEFAULT_AGE);
        if (!padded) fail('the leading page has no star past its title to cut the title to');
        if (padded.far.length !== padded.standing - 1 || !(padded.inside > 0.3 && padded.inside < 0.7)) {
          fail(`the cut title hides ${padded.standing - padded.far.length} stars (one is wanted), the star ${padded.inside} pt inside its pad`);
        }
        pages.push(['@', name, DEFAULT_AGE, `title=${rectText(padded.layout.title)}`, `subtitle=${rectText(padded.layout.subtitle)}`, `count=${padded.far.length}`,
          `sum=${num(padded.far.reduce((a, f) => a + f[0], 0), 6)},${num(padded.far.reduce((a, f) => a + f[1], 0), 6)}`, 'cut=1'].join(' '));
        pages.push(...wrap(padded.far.map((f) => `${cents(f[0])},${cents(f[1])}`)));
      }

      // ── the skies of this script's making: cast, not drawn ──
      for (const [extra, where, change] of EXTRA) {
        if (where !== name) continue;
        const out = await page.evaluate(async ({ change: ch, base }) => {
          await window.__lab.set({ age: base });
          const P = globalThis.__hpProbe, G = P.G(), c = G.cfg, st = window.__lab.state;
          const layout = JSON.parse(JSON.stringify(st.layout));
          if (ch.name) layout.name.width += ch.name.dw;
          if (ch.age) layout.age.width += ch.age.dw;
          if (ch.bare) { layout.name = null; layout.age = null; layout.avatar = null; layout.gear = null; if (G.ox === 0) layout.stripClear = null; }
          if (ch.buttons) { layout.name = null; layout.age = null; }
          if (ch.nameEnds) {
            // (the header's block ends 13 pt of clear sky and 7 pt of room past the last glyph: starKeepOuts)
            layout.name.width = G.ox + c.firstUp.x - ch.nameEnds - 20 - layout.name.x;
            layout.age.width = Math.min(layout.age.width, layout.name.x + layout.name.width - layout.age.x);
          }
          if (ch.wall) {
            layout.name = { x: G.ox + 30, y: 10, width: G.Wa - 90, height: 20 };
            layout.age = { x: G.ox + 30, y: 30, width: G.Wa - 90, height: ch.wall };
          }
          const state = { ...st, ageDays: ch.ageDays, layout };
          const S = P.starsFor(state);
          const pick = (q) => ({ night: q.night, kind: q.kind, lx: q.lx, ly: q.ly, x: q.x, y: q.y, how: q.how ?? null });
          const list = S.list.map(pick);
          const far = S.far.map((f) => [f.x, f.y]);
          const outs = P.starKeepOuts(state);
          P.starsFor(st);
          return { ageDays: ch.ageDays, layout, ox: G.ox, Wa: G.Wa, W: G.W, H: G.H, T: c.T, D: c.D, tonight: c.tonight, firstUp: c.firstUp ?? null, list, far, outs, census: null };
        }, { change, base: DEFAULT_AGE });
        if (change.nameEnds) {
          const short = out.firstUp.x - out.outs[0].x1, first = out.list[0];
          if (!(short > 0 && short < 9)) fail(`${extra}: the header's block ends ${short} pt short of the first night's place, not within a four-point star's 9`);
          if (first.kind !== 'first' || first.lx !== out.firstUp.x || first.ly !== out.firstUp.y) fail(`${extra}: the lab no longer keeps the first night's own place there`);
        }
        writeSky('cast', extra, name, out);
        keepOuts.push(`${name}.${extra} ${out.ageDays} ${out.outs.map((r) => [r.x0, r.y0, r.x1, r.y1].map((v) => num(v, 6)).join(',')).join(' ')}`);
      }
      await close();
    }
  } finally {
    await browser.close();
    await server.close();
  }

  const facts = [
    `ages ${AGES.join(' ')}`,
    `monthNights ${monthNights.join(' ')}`,
    `drawn ${drawn}`,
    // every drawn sky was also cast with the night not begun: the same places, less tonight's star
    `sameBeforeHeIsDown ${unlit}`,
    `placed first ${stats.first} again ${stats.again} spiral ${stats.spiral} nowhere ${stats.nowhere} most ${stats.most}`,
  ];

  const sections = [
    ['facts', ['What was sampled: the ages (whole days), the lab\'s month-nights through two years (lab/nights.js:',
      'every 30.4375 days), how many skies were really drawn, how many of those were also cast with the',
      'night not begun and found the same less tonight\'s star, and how his stars came to their places.'], facts],
    ['hashes', ['lab/nights.js `hash(n, salt)`, as its 32 bits. `run salt from v…`: n = from, from + 1, …;',
      '`one n salt v`.'], hashes],
    ['lattice', ['lab/noise.js `hash2(x, y, seed)`, as its 32 bits. `run seed y from v…`: x = from, from + 1, …;',
      '`one x y seed v`.'], lattice],
    ['sequences', ['lab/noise.js `rng(seed)`: the seed, then its first 48 numbers as their 32 bits.'], sequences],
    ['noise', ['lab/noise.js: `noise2 x y seed bits`, `fbm2 x y octaves gain lacunarity seed bits`,',
      '`fbm1 x octaves gain lacunarity seed bits`.'], noise],
    ['drift', [`skies/${SKY}.js, on the lab's page: its own lattice noise — \`vn x y bits\`, \`fb x y octaves bits\`,`,
      '`knots x y bitsX bitsY` (the two samples `starsFor` drifts a place by) — and the page\'s',
      '`Math.hypot` (`hypot a b bits`), which his stars\' spacing is measured with.'], drift],
    ['nights', ['lab/nights.js `nights(730, { tonightLit: true })`: nights 1 – 160, then every fourteenth, and the',
      'last. u and v as bits.'], nightRows],
    ['land', ['The land under his stars, per world: `shape id plane sink index wobble crest|floor x y x y …` (the',
      'crest lines as set by hand, and the number the hand\'s wobble is seeded with); `skyline from v…` (the',
      'module\'s `G.skyline` at every whole world x, float bits); `at x v` (between whole x); `treeFoot`',
      '(bits); `field xMin xMax yMin apart`; `floor from dx v…` (the lowest a star may sit at looked-up',
      'x = from + dx, from + 1 + dx, …); and `crown from v…` (tree.js `crownTop` at from/100, …; bits). A',
      'run of values is cut into lines, each headed by where it starts.'], land],
    ['keepOuts', ['`starKeepOuts`: `display[.sky] age x0,y0,x1,y1 …`, looked-up points, the anchor window\'s x.'], keepOuts],
    ['rooms', ['The module\'s own `free`, asked about places a tenth of a point either side of every distance the',
      'rule keeps, in two of the drawn skies with all their stars standing. `@ display age asked= free=` heads',
      'a sky (how many places, and how many were free for each asking); then `x,y,bits`: a looked-up place',
      'and 1 if an ordinary night could stand there, 2 a four-point star with 80 pt from its kind, 4 with',
      '60, 8 with 44, 16 with 20.'], rooms],
    ['skies', ['His stars. `@ drawn|cast name display age anchor=x,width size=w,h strip=x name= age= avatar=',
      'gear= census=total,rest,up sum=x,y` heads a sky (rects are x,y,width,height in display points, as',
      'the lab\'s page measured them; `sum`: the places summed, to six decimals); then every night in',
      'order, `x,y[,code]`: its looked-up place in hundredths of a point (the anchor window\'s x) and,',
      'where it is not an ordinary night at its first cast, a letter (m month-night, f the first',
      'night, t tonight) and how many casts it took (blank: none).'], skies],
    ['pages', ['The leading page\'s ordinary sky (the spread), at 0, 92, 142, 300 and 730 days. `@ display age',
      'title= subtitle= count= sum=` heads it; then every star, `x,y` in hundredths of a point (world x,',
      'rest-pose y) — and at 142 days also `,m,r,a,tint,phase,period,steady`. The last (`cut=1`) is 142',
      'days again behind a title cut to end half a point past one more star: it gives way too.'], pages],
  ];
  const text = swiftFile(sections);
  if (dumpFile) await fsp.writeFile(dumpFile, JSON.stringify(dump));
  const before = await fsp.readFile(OUT, 'utf8').catch(() => null);
  const said = `${skies.filter((row) => row.startsWith('@')).length} skies (${drawn} drawn), ${facts[4]}; ${(text.length / 1024).toFixed(0)} KB`;
  if (check) {
    if (before !== text) fail(`${path.relative(REPO_ROOT, OUT)} is stale: run node design/sky-lab/tools/swift-fixtures/stars.mjs`);
    process.stdout.write(`stars.mjs: ${path.relative(REPO_ROOT, OUT)} is up to date — ${said}\n`);
    return;
  }
  await fsp.writeFile(OUT, text);
  process.stdout.write(`stars.mjs: wrote ${path.relative(REPO_ROOT, OUT)} — ${said}${before === text ? ' (unchanged)' : ''}\n`);
}

main().catch((error) => fail(error.stack ?? String(error)));
