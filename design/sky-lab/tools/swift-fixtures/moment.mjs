#!/usr/bin/env node
// Sky lab → Swift fixtures: the world, the camera and the moment.
//
//     node design/sky-lab/tools/swift-fixtures/moment.mjs            (writes TwoOfUsTests/SkyCoreFixturesMoment.swift)
//     node design/sky-lab/tools/swift-fixtures/moment.mjs --check    (writes nothing; exits 1 if the file on disk is stale)
//
// The painted hill is being built in SwiftUI (TwoOfUs/Sky/Core: SkyWorld, SkyCamera, Moment). Their
// unit tests do not restate the Swift: they compare it with what THE LAB says, and this script is
// where the lab says it. Nothing below is typed by hand — every number is read out of the lab's own
// code as it runs:
//
//   · lab/core.js, lab/presence.js, lab/oklab.js are imported and called (the displays, MOMENT,
//     momentVeil, momentCaption, roomDepth, and `buildState`, which decides what an event IS for a
//     given hour — a bedtime at 19:40 is the moment, the same tap at 21:00 is only `arrive`);
//   · skies/hill-painted.js keeps its worlds (DUO, SLAB) and its camera (lookOf, sparkOf,
//     planeOffset, onGrid, tonightHome, ringOf, treeShown) inside the module's closure and exports
//     none of them. So the lab's page is opened in headless Chromium (Playwright, as tools/joins.mjs
//     does) and the sky module is served with ONE LINE ADDED IN TRANSIT — never on disk — that
//     leaves those names on `globalThis.__hpProbe`, read-only; and one more inside `starsFor` that
//     keeps the star boxes it has just laid out. The functions then run in their own closure, with
//     the geometry the page built for that display and scale;
//   · four small expressions are local to a drawing function and cannot be reached even so (the
//     caption's opacity, the band's own light, the faint stars kept in a light sky, how a cloud
//     leaves or arrives with the look). Their SOURCE TEXT is cut out of hill-painted.js and
//     evaluated as it stands, with the lab's own helpers. (The caption's is also asked OFF the
//     moment's table — `captionRule` — where the table itself never shows what the cards do to it.)
//
// If the sky module changes shape (a name is renamed, a marked line reworded) this script stops and
// says which mark it could not find: fix the mark here, never the number in the Swift.
//
// A few frames are also really drawn (`__lab.set`), and `window.__hillPainted.look` — what the page
// itself used for that frame — is compared with the probe's answer, so the probe cannot drift from
// the picture.

import http from 'node:http';
import fsp from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { DEVICES, parseParams, buildState, minutesToTime, FIRST_LIGHT_DEG } from '../../lab/core.js';
import { MOMENT, SLEEP_DEPTH, momentVeil, momentCaption, roomDepth, easeOut } from '../../lab/presence.js';
import { smoothstep } from '../../lab/oklab.js';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const LAB_ROOT = path.resolve(HERE, '..', '..');
const REPO_ROOT = path.resolve(LAB_ROOT, '..', '..');
const OUT = path.join(REPO_ROOT, 'TwoOfUsTests', 'SkyCoreFixturesMoment.swift');
const SKY = 'hill-painted';
const SKY_PATH = `/skies/${SKY}.js`;

const fail = (message) => { process.stderr.write(`moment.mjs: ${message}\n`); process.exit(1); };

// ───────────────────────────────────────────────── the sky module, in transit ──

/** What the probe leaves behind: names from the sky module's own scope, nothing computed here. */
const PROBE_MARK = '  return { render, destroy, ready };';
const PROBE = '  globalThis.__hpProbe = { DUO, SLAB, SKYPLANE, PADL, PADR, G: () => G, lookOf, sparkOf, onTheWay, planeOffset, onGrid, tonightHome, ringOf, treeShown, starsFor };\n';
/** …and, inside starsFor, the boxes his stars are laid out in (a local there). */
const BOXES_MARK = '    for (const bx of boxes) { bx.push((bx[1] - bx[0]) * (bx[3] - bx[2]) * bx[4]); boxTotal += bx[6]; }';
const BOXES = '\n    G.__starBoxes = { boxes: boxes.map((bx) => bx.slice(0, 6)), xMin, xMax, yMin, SW };';

function once(source, mark, what) {
  const parts = source.split(mark);
  if (parts.length !== 2) fail(`${SKY}.js: expected exactly one "${what}" (found ${parts.length - 1}). The sky module has changed shape: update the mark in tools/swift-fixtures/moment.mjs.`);
  return parts;
}

function withProbe(source) {
  let [head, tail] = once(source, PROBE_MARK, 'return { render, destroy, ready }');
  let out = head + PROBE + PROBE_MARK + tail;
  [head, tail] = once(out, BOXES_MARK, 'the star boxes\' area loop in starsFor');
  out = head + BOXES_MARK + BOXES + tail;
  return out;
}

/** The text between two marks of the sky module (the first included, the second not). */
function cut(source, from, to, what) {
  const a = source.indexOf(from);
  if (a < 0 || source.indexOf(from, a + 1) >= 0) fail(`${SKY}.js: expected exactly one "${from.trim()}" (${what}).`);
  const b = source.indexOf(to, a);
  if (b < 0) fail(`${SKY}.js: "${to.trim()}" does not follow "${from.trim()}" (${what}).`);
  return source.slice(a, b);
}

/** The four expressions that are locals of a drawing function, as the lab wrote them. */
function transplants(source) {
  const clamp01 = (x) => Math.min(1, Math.max(0, x));
  // drawCaption: from its first line to where it starts to draw → `alpha`.
  const captionBody = cut(source, "    if (state.asleep !== 'night' || !(state.veil > 0.01)) return;", '    if (!(alpha > 0.01)) return;', 'drawCaption');
  if (!/const alpha = /.test(captionBody)) fail(`${SKY}.js: drawCaption no longer computes "alpha".`);
  const captionFn = new Function('state', 'look', 'clamp01', 'smoothstep', 'momentCaption', `${captionBody}\n return alpha;`);
  // drawTonight: the band's own light, from the ring's radius → `band`.
  const bandBody = cut(source, '      const R = ring.radius;', '      if (band > 0.004) {', 'drawTonight, the band');
  if (!/const band = /.test(bandBody)) fail(`${SKY}.js: drawTonight no longer computes "band".`);
  const bandFn = new Function('ring', 'smoothstep', `${bandBody}\n return band;`);
  // drawStars: the faint presence his stars keep in a sky too light for them → `kept`.
  const keptBody = cut(source, '    const mo = state.reduceMotion ? MOMENT.reduced : MOMENT;', '    const keptAt = ', 'drawStars, kept');
  if (!/const kept = /.test(keptBody)) fail(`${SKY}.js: drawStars no longer computes "kept".`);
  const keptFn = new Function('state', 'bed', 'c', 'MOMENT', 'smoothstep', 'easeOut', `${keptBody}\n return kept;`);
  // compose: the everyday view's clouds leave as the camera looks up, the looked-up view's own arrives → `a`.
  const cloudBody = cut(source, '        if (cloud.rest) a *= ', '        // …nor under the strip\'s own furniture', 'compose, the clouds by look');
  if (!/if \(cloud\.up\) a \*= /.test(cloudBody)) fail(`${SKY}.js: compose no longer brings the looked-up cloud in by the look.`);
  const cloudFn = new Function('cloud', 'look', 'smoothstep', `let a = 1;\n${cloudBody}\n return a;`);
  return {
    cloud: (belongs, look) => cloudFn({ rest: belongs === 'rest', up: belongs === 'up' }, look, smoothstep),
    caption: (state, look) => captionFn(state, look, clamp01, smoothstep, momentCaption) ?? 0,
    bandLight: (ring) => (ring && ring.strength > 0 ? bandFn(ring, smoothstep) : 0),
    kept: (state, bed, kind) => keptFn(state, bed, { kind }, MOMENT, smoothstep, easeOut),
  };
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
const SCALES = [1, 2, 3];
const LOOKS = [0, 0.25, 0.5, 0.75, 1];
const TILTS = [[0, 0], [1, 1], [-1, -1], [0.37, -0.61]];
/** Every 0.05 s from 0 to 10 s. */
const AGES = Array.from({ length: 201 }, (_, i) => i / 20);

/** First light on the lab's default date: the first local minute with the sun over the threshold. */
function firstLight() {
  for (let m = 0; m < 12 * 60; m += 1) {
    const state = buildState(parseParams({ time: minutesToTime(m) }));
    const morning = state.sun.isNight ? state.sun.progress > 0.5 : state.sun.progress < 0.5;
    if (morning && (state.sun.altitude * 180) / Math.PI >= FIRST_LIGHT_DEG) return minutesToTime(m);
  }
  return fail('no first light on the default date');
}

/** The lab's state for a viewer query (lab/core.js decides what the event is), cut down to what
 *  the camera and the moment read — plain data, so it can be handed to the page. */
function labState(query, expectKind) {
  const state = buildState(parseParams({ sky: SKY, ...query }));
  const kind = state.event ? state.event.kind : null;
  if (kind !== expectKind) fail(`the lab plays ${JSON.stringify(query)} as ${kind} (${state.eventNote ?? 'no note'}), not ${expectKind}`);
  return { asleep: state.asleep, nightBegun: state.nightBegun, tonightLit: state.tonightLit, reduceMotion: state.reduceMotion, event: state.event ? { ...state.event } : null };
}

/** The events, as the viewer's queries: [name, the event the lab must make of it, the query]. */
function scenarios() {
  const dawn = firstLight();
  return {
    bedtime: [
      ['bedtime', 'bedtime', { time: '19:40', asleep: 'night', event: 'bedtime' }],
    ],
    quiet: [
      // a night sleep from elsewhere, and the night begins with it: the quiet rise
      ['arrive', 'arrive', { time: '19:40', asleep: 'night', event: 'arrive' }],
      // put down again after a 03:00 feed: the night had begun — nothing moves, the room dims
      ['arriveAgain', 'arrive', { time: '03:00', asleep: 'night', event: 'arrive' }],
      // a nap begins at 13:10: nothing moves, the room dims to a nap's depth
      ['arriveNap', 'arrive', { time: '13:10', asleep: 'nap', event: 'arrive' }],
      // first light, he still sleeps: the quiet settle
      ['settle', 'settle', { time: dawn, asleep: 'night', event: 'settle' }],
      // a 03:00 feed: nothing moves, the room un-dims from a night's depth
      ['wakeNight', 'wake', { time: '03:00', asleep: '0', event: 'wake', woke: 'night' }],
      // a nap ends at 13:10: the room un-dims from a nap's depth
      ['wakeNap', 'wake', { time: '13:10', asleep: '0', event: 'wake', woke: 'nap' }],
    ],
  };
}

// ─────────────────────────────────────────────────────────────── writing ──

/** A number as the fixtures print it: at most seven decimals, no trailing zeros. */
const num = (v) => {
  if (v == null) return 'nil';
  if (typeof v !== 'number' || !Number.isFinite(v)) fail(`not a finite number: ${v}`);
  const r = Number(v.toFixed(7));
  return Object.is(r, -0) ? '0' : String(r);
};
const nums = (list) => list.map(num).join(' ');

function swiftFile(sections) {
  const lines = [];
  lines.push('// GENERATED by design/sky-lab/tools/swift-fixtures/moment.mjs — do not edit by hand.');
  lines.push('// Regenerate:  node design/sky-lab/tools/swift-fixtures/moment.mjs');
  lines.push('// (Node 22 and Playwright with Chromium; `--check` only compares.)');
  lines.push('//');
  lines.push('// What the sky lab says about the world, the camera and the bedtime moment — read out of the');
  lines.push('// lab\'s own code as it runs (lab/core.js, lab/presence.js, and the closure of');
  lines.push(`// skies/${SKY}.js on the lab's page). The tests of SkyWorld, SkyCamera and Moment compare the`);
  lines.push('// Swift with these; a change in the lab shows up here as a diff and there as a failing test.');
  lines.push('');
  lines.push('import Foundation');
  lines.push('');
  lines.push('/// The lab\'s numbers for `SkyWorldTests`, `SkyCameraTests` and `MomentTests`, as compact text:');
  lines.push('/// records are "key value value …" lines; tables have their column names on the first line.');
  lines.push('/// Data only: read with `SkyCoreFixture.records` and `SkyCoreFixture.Table`');
  lines.push('/// (TwoOfUsTests/SkyCoreFixture.swift).');
  lines.push('enum SkyCoreFixturesMoment {');
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
  const skySource = await fsp.readFile(path.join(LAB_ROOT, 'skies', `${SKY}.js`), 'utf8');
  const local = transplants(skySource);
  const require = createRequire(import.meta.url);
  const { chromium } = require('playwright');
  const server = await serve(LAB_ROOT, withProbe(skySource));
  const browser = await chromium.launch();
  const timeout = 90_000;

  /** A page of the lab on one display at one scale, drawn once (daylight: the default hour). */
  async function open(device, scale, query = {}) {
    const preset = DEVICES[device];
    const context = await browser.newContext({ viewport: { width: Math.ceil(preset.width), height: Math.ceil(preset.height) }, deviceScaleFactor: scale });
    const page = await context.newPage();
    const noise = [];
    page.on('pageerror', (error) => noise.push(error.message));
    const search = new URLSearchParams({ sky: SKY, device, dpr: String(scale), t: '12', chrome: '0', ...query }).toString().replace(/%3A/gi, ':');
    await page.goto(`${server.origin}/index.html?${search}`, { waitUntil: 'load', timeout });
    await page.waitForFunction(() => window.__labReady === true || Boolean(window.__labError), null, { timeout });
    const problem = await page.evaluate(() => window.__labError);
    if (problem || noise.length) fail(`the lab's page: ${problem ?? noise.join(' | ')}`);
    if (!(await page.evaluate(() => Boolean(globalThis.__hpProbe)))) fail('the probe did not reach the page');
    return { page, close: () => context.close() };
  }

  const world = [];          // records
  const camera = [['display', 'scale', 'plane', 'look', 'tiltX', 'tiltY', 'x', 'y', 'restedX', 'restedY'].join(' ')];
  const tonight = [['display', 'scale', 'look', 'tiltX', 'tiltY', 'x', 'y'].join(' ')];
  const bedtime = [['display', 'motion', 'age', 'cards', 'look', 'star', 'caption', 'captionLit', 'bandRadius', 'bandStrength', 'bandLight', 'depth', 'kept', 'tree'].join(' ')];
  const quiet = [['event', 'display', 'motion', 'age', 'look', 'star', 'depth', 'tree'].join(' ')];
  const looks = [['look', 'onTheWay', 'cloudRest', 'cloudUp', 'cloudAlways', 'treeCardsOn', 'treeCardsHalf', 'treeCardsAway', 'treeCardsOver', 'treeCardsUnder'].join(' ')];
  const table = [];          // records: the moment's table and its anchors
  const captionRule = [['cards', 'look', 'age', 'lit', 'caption'].join(' ')];
  const scn = scenarios();
  let drawnChecks = 0;

  try {
    // ── the displays (lab/core.js) ──
    for (const [name, device] of DISPLAYS) {
      const d = DEVICES[device];
      world.push(`display.${name}.size ${nums([d.width, d.height])}`);
      world.push(`display.${name}.anchor ${nums([d.phone.x, d.phone.width])}`);
      world.push(`display.${name}.strip ${d.strip ? `${d.strip.side} ${num(d.strip.width)}` : 'nil'}`);
      world.push(`display.${name}.fold ${d.fold ? num(d.fold.x) : 'nil'}`);
    }

    const seenWorlds = new Set();
    for (const [name, device] of DISPLAYS) {
      for (const scale of SCALES) {
        const { page, close } = await open(device, scale);
        // ── the world this display is a window on (once per world: the cover's, the slab's) ──
        const info = await page.evaluate(() => {
          const P = globalThis.__hpProbe, G = P.G(), c = G.cfg;
          G.stars.key = '';
          P.starsFor(window.__lab.state);
          const knoll = c.planes.find((p) => p.id === 'knoll').shapes.find((sh) => sh.id === 'knoll');
          const summit = knoll.crest.reduce((a, b) => (b[1] < a[1] ? b : a));
          return {
            kind: c.kind, sameWorld: c === (window.__lab.state.strip ? P.DUO : P.SLAB), ox: G.ox, Wa: G.Wa, s: G.s,
            cfg: JSON.parse(JSON.stringify({ ...c, planes: c.planes.map((p) => ({ id: p.id, sink: p.sink, slide: p.slide, tilt: p.tilt })), river: undefined })),
            sky: P.SKYPLANE, pad: [P.PADL, P.PADR], skyTop: G.skyTop, skyBot: G.skyBot, treeFoot: G.tree.baseY, summit,
            boxes: G.__starBoxes,
            keys: Object.keys(c), planeKeys: [...new Set(c.planes.flatMap((p) => Object.keys(p)))],
          };
        });
        if (!info.sameWorld) fail(`${device}: the page's world is not the one its strip says`);
        if (scale === SCALES[0]) world.push(`display.${name}.world ${info.kind}`);
        const k = info.kind;
        if (!seenWorlds.has(k) && scale === 2) {
          seenWorlds.add(k);
          const c = info.cfg;
          world.push(`${k}.H0 ${num(c.H0)}`, `${k}.D ${num(c.D)}`, `${k}.T ${num(c.T)}`, `${k}.table ${num(c.table)}`, `${k}.Emax ${num(c.Emax)}`);
          world.push(`${k}.anchor ${nums([info.Wa, DEVICES[device].height])}`);
          world.push(`${k}.tree ${nums([c.tree.x, c.tree.h])}`, `${k}.treeFoot ${num(info.treeFoot)}`, `${k}.knollSummit ${nums(info.summit.slice(0, 2))}`);
          world.push(`${k}.tonight ${nums([c.tonight.x, c.tonight.y])}`, `${k}.tonightUp ${nums([c.tonightUp.x, c.tonightUp.y])}`);
          world.push(`${k}.firstUp ${c.firstUp ? nums([c.firstUp.x, c.firstUp.y]) : 'nil'}`);
          world.push(`${k}.sunR ${num(c.sunR)}`, `${k}.moonR ${num(c.moonR)}`, `${k}.starScale ${num(c.starScale)}`);
          world.push(`${k}.sets ${c.sets ? nums([c.sets.sun, c.sets.moon]) : 'nil'}`);
          world.push(`${k}.caption ${nums([c.caption.x, c.caption.y, c.caption.size])}`);
          world.push(`${k}.tallSky ${nums([info.skyTop, info.skyBot])}`, `${k}.pad ${nums(info.pad)}`);
          world.push(`${k}.sky ${nums([info.sky.sink, info.sky.slide, ...info.sky.tilt])}`);
          world.push(`${k}.planes ${c.planes.map((p) => p.id).join(' ')}`);
          for (const p of c.planes) world.push(`${k}.plane.${p.id} ${nums([p.sink, p.slide, ...p.tilt])}`);
          world.push(`${k}.clouds ${c.clouds.map((cl) => cl.id).join(' ')}`);
          for (const cl of c.clouds) {
            const known = ['id', 'x', 'e', 'len', 'rise', 'span', 'period', 'phase', 'rest', 'up', 'high', 'wob', 'top'];
            const extra = Object.keys(cl).filter((key) => !known.includes(key));
            if (extra.length) fail(`${k} cloud ${cl.id} has fields this script does not export: ${extra.join(', ')}`);
            world.push(`${k}.cloud.${cl.id} ${nums([cl.x, cl.e, cl.len, cl.rise, cl.span, cl.period, cl.phase, cl.wob])} ${cl.rest ? 'rest' : cl.up ? 'up' : 'always'} ${cl.high ? 'high' : 'low'}`);
            world.push(`${k}.cloud.${cl.id}.top ${nums(cl.top.flat())}`);
          }
          world.push(`${k}.cards ${num(c.cards.length)}`);
          c.cards.forEach((card, i) => world.push(`${k}.card.${i} ${nums(card)}`));
          world.push(`${k}.glass ${nums(c.glass)}`);
          // the star boxes, as starsFor laid them out for the lab's own layout
          const b = info.boxes;
          world.push(`${k}.starField ${nums([b.xMin, b.xMax, b.yMin])}`, `${k}.stripWindow ${k === 'duo' ? num(b.SW) : 'nil'}`);
          world.push(`${k}.boxes ${num(b.boxes.length)}`);
          b.boxes.forEach((bx, i) => {
            world.push(`${k}.box.${i} ${nums(bx.slice(0, 5))}`);
            world.push(`${k}.box.${i}.columns ${bx[5] ? nums(bx[5].flat()) : 'nil'}`);
          });
          // what this script does NOT carry of the world, said out loud
          const carried = ['kind', 'H0', 'D', 'T', 'table', 'Emax', 'tree', 'tonight', 'tonightUp', 'firstUp', 'sunR', 'moonR', 'sets', 'starScale', 'cards', 'glass', 'caption', 'planes', 'clouds'];
          const left = info.keys.filter((key) => !carried.includes(key))
            .concat(info.planeKeys.filter((key) => !['id', 'sink', 'slide', 'tilt'].includes(key)).map((key) => `planes.${key}`));
          world.push(`${k}.notCarried ${left.length ? left.join(' ') : 'nil'}`);
        }

        // ── the camera: every plane's offset for each look and tilt ──
        const cam = await page.evaluate(({ looks, tilts }) => {
          const P = globalThis.__hpProbe, G = P.G(), s = G.s;
          const planes = [{ id: 'sky', ...P.SKYPLANE }, ...G.planes];
          const rows = [], homes = [];
          for (const [tx, ty] of tilts) {
            const tilt = { x: tx, y: ty };
            for (const look of looks) {
              for (const plane of planes) {
                const off = P.planeOffset(plane, look, tilt);
                // where the layer is drawn (compose, drawPlane), less where its picture starts: its offset as placed
                const x0 = (G.xL + G.ox) * s, y0 = 0;
                const rx = (P.onGrid(x0 + off.x * s, look) - x0) / s, ry = (P.onGrid(y0 + off.y * s, look) - y0) / s;
                rows.push([plane.id, look, tx, ty, off.x, off.y, rx, ry]);
              }
              const home = P.tonightHome(look, tilt);
              homes.push([look, tx, ty, home.x, home.y]);
            }
          }
          return { rows, homes, origin: [(G.xL + G.ox) * s, s] };
        }, { looks: LOOKS, tilts: TILTS });
        if (!Number.isInteger(cam.origin[0])) fail(`${device} @${scale}×: the planes do not start on a whole pixel (${cam.origin[0]})`);
        for (const [plane, ...rest] of cam.rows) camera.push(`${name} ${scale} ${plane} ${nums(rest)}`);
        for (const row of cam.homes) tonight.push(`${name} ${scale} ${nums(row)}`);

        // ── the moment and the quiet events (the curves do not depend on the scale: once, at 2×) ──
        if (scale === 2) {
          const jobs = [];
          for (const motion of ['1', '0']) {
            for (const [, expect, query] of scn.bedtime) {
              for (const age of AGES) {
                const state = labState({ ...query, device, eventAge: age, motion }, expect);
                const veil = momentVeil(age, motion === '0');
                jobs.push({ table: 'bedtime', motion, age, veil, state });
              }
            }
            for (const [event, expect, query] of name === 'spread' ? [] : scn.quiet) {
              for (const age of AGES) jobs.push({ table: 'quiet', event, motion, age, state: labState({ ...query, device, eventAge: age, motion }, expect) });
            }
          }
          const answers = await page.evaluate((list) => {
            const P = globalThis.__hpProbe, G = P.G();
            const base = window.__lab.state;
            return list.map((job) => {
              const state = { ...base, ...job.state };
              const look = P.lookOf(state);
              const ring = P.ringOf(state, { x: 0, y: 0 });
              // the phone page's cards, as far back as the moment has them (a quiet event: all there)
              const cards = [{ kind: 'tile', x: G.ox + 20, y: 300, width: 160, height: 140, opacity: job.veil == null ? 1 : 1 - job.veil }];
              return { look, star: P.sparkOf(state), ring: ring ? { radius: ring.radius, strength: ring.strength, far: ring.far, speed: ring.speed } : null,
                tree: P.treeShown({ ...state, cards }, state.reduceMotion ? Math.round(look) : look) };
            });
          }, jobs);
          jobs.forEach((job, i) => {
            const a = answers[i];
            const reduced = job.motion === '0';
            const depth = roomDepth(job.state);
            if (job.table === 'bedtime') {
              const state = { ...job.state, veil: job.veil };
              bedtime.push(`${name} ${reduced ? 'reduced' : 'full'} ${nums([job.age, job.veil, a.look, a.star, local.caption(state, a.look), momentCaption(job.age, reduced),
                a.ring ? a.ring.radius : 0, a.ring ? a.ring.strength : 0, local.bandLight(a.ring), depth, local.kept(job.state, job.age, info.kind), a.tree])}`);
              if (a.ring && !table.some((row) => row.startsWith(`band.${info.kind}.reach `))) {
                table.push(`band.${info.kind}.reach ${num(a.ring.far)}`, `band.${info.kind}.speed ${num(a.ring.speed)}`);
              }
            } else {
              quiet.push(`${job.event} ${name} ${reduced ? 'reduced' : 'full'} ${nums([job.age, a.look, a.star, depth, a.tree])}`);
            }
          });

          // ── what follows the look alone, every hundredth of it (the same on every display: once) ──
          if (looks.length === 1) {
            const steps = Array.from({ length: 101 }, (_, i) => i / 100);
            const gates = await page.evaluate((list) => {
              const P = globalThis.__hpProbe, G = P.G();
              const cards = (opacity) => [{ kind: 'tile', x: G.ox + 20, y: 300, width: 160, height: 140, opacity }];
              // (…and with an opacity past 1 or under 0, as a spring's overshoot gives one: the lab holds it to 0 … 1)
              return list.map((look) => [P.onTheWay(look), P.treeShown({ cards: cards(1) }, look), P.treeShown({ cards: cards(0.5) }, look), P.treeShown({ cards: cards(0) }, look),
                P.treeShown({ cards: cards(1.5) }, look), P.treeShown({ cards: cards(-0.5) }, look)]);
            }, steps);
            steps.forEach((look, i) => looks.push(nums([look, gates[i][0], local.cloud('rest', look), local.cloud('up', look), local.cloud('always', look), ...gates[i].slice(1)])));
          }

          // ── the rise's peak pace, points a second: the sky's travel by the look's steepest millisecond ──
          if (!table.some((row) => row.startsWith(`anchor.peak.${info.kind} `))) {
            const state = labState({ ...scn.bedtime[0][2], device, eventAge: 0, motion: '1' }, 'bedtime');
            const peak = await page.evaluate((st) => {
              const P = globalThis.__hpProbe, c = P.G().cfg;
              const at = (age) => P.lookOf({ ...window.__lab.state, ...st, event: { ...st.event, age } });
              let most = 0;
              for (let i = 0; i < 4000; i += 1) most = Math.max(most, (at((i + 1) / 1000) - at(i / 1000)) * 1000);
              return most * c.D;
            }, state);
            table.push(`anchor.peak.${info.kind} ${num(peak)}`);
            // ── the last millisecond at which his stars still answer the band, and how strongly: `ringOf` puts
            // the strength out all at once under 0.003, between two of the samples above ──
            const answers = await page.evaluate((st) => {
              const P = globalThis.__hpProbe;
              let last = null;
              for (let ms = 0; ms <= 8000; ms += 1) {
                const ring = P.ringOf({ ...window.__lab.state, ...st, event: { ...st.event, age: ms / 1000 } }, { x: 0, y: 0 });
                if (ring && ring.strength > 0) last = [ms / 1000, ring.strength];
              }
              return last;
            }, state);
            if (!answers) fail(`${device}: the band never has a strength`);
            table.push(`anchor.bandAnswers.${info.kind} ${nums(answers)}`);
          }

          // ── really drawn: the page's own `look` for a few frames of the moment ──
          for (const age of [0.3, 0.95, 1.35, 2.0, 2.55, 6]) {
            const drawn = await page.evaluate(async (eventAge) => {
              await window.__lab.set({ time: '19:40', asleep: 'night', event: 'bedtime', eventAge });
              return { look: window.__hillPainted.look, probe: globalThis.__hpProbe.lookOf(window.__lab.state), kind: window.__lab.state.event?.kind };
            }, age);
            const sample = bedtime.find((row) => row.startsWith(`${name} full ${num(age)} `));
            const mine = Number(sample.split(' ')[4]);
            if (drawn.kind !== 'bedtime' || Math.abs(drawn.look - drawn.probe) > 1e-12 || Math.abs(drawn.look - mine) > 1e-6) {
              fail(`${device}: at ${age} s the page drew look ${drawn.look} (${drawn.kind}); the probe says ${drawn.probe}, the samples ${mine}`);
            }
            drawnChecks += 1;
          }
        }
        await close();
      }
    }
  } finally {
    await browser.close();
    await server.close();
  }

  // ── the caption's own rule (drawCaption's opacity, cut from the source above), asked OFF the table: the
  // cards part-way back, the view part-way up, an opacity past 1 — combinations the moment's table never
  // makes (there the cards are wholly away for as long as the caption is lit), which another clock can ──
  for (const veil of [0, 0.005, 0.01, 0.0100001, 0.02, 0.1, 0.25, 0.5, 0.75, 0.9, 1, 1.2]) {
    for (const look of [0, 0.5, 0.6, 0.7, 0.8, 0.9, 1]) {
      for (const age of [2.2, 2.5, 3.5, 4.4]) {
        const state = { asleep: 'night', veil, reduceMotion: false, event: { kind: 'bedtime', age, begunBefore: false } };
        captionRule.push(nums([veil, look, age, momentCaption(age, false), local.caption(state, look)]));
      }
    }
  }

  // ── the moment's table (lab/presence.js), and the anchors the design quotes, found by looking ──
  const M = MOMENT;
  table.unshift(
    `fall ${nums(M.fall)}`, `rise.duo ${nums(M.rise.duo)}`, `rise.slab ${nums(M.rise.slab)}`,
    `band.duo ${nums([M.band.duo.leaves, M.band.duo.crosses])}`, `band.slab ${nums([M.band.slab.leaves, M.band.slab.crosses])}`,
    `caption.in ${nums(M.caption.in)}`, `caption.out ${nums(M.caption.out)}`, `back ${nums(M.back)}`,
    `reduced.fall ${nums(M.reduced.fall)}`, `reduced.dissolve ${nums(M.reduced.dissolve)}`,
    `reduced.caption.in ${nums(M.reduced.caption.in)}`, `reduced.caption.out ${nums(M.reduced.caption.out)}`, `reduced.back ${nums(M.reduced.back)}`,
    `quiet.dissolve ${num(M.quiet.dissolve)}`,
    `depth.night ${num(SLEEP_DEPTH.night)}`, `depth.nap ${num(SLEEP_DEPTH.nap)}`,
  );
  // "under 5 % by 0.87 s": the first hundredth of a second at which a card is under a twentieth of itself
  let under = null;
  for (let i = 0; i <= 1000 && under == null; i += 1) if (1 - momentVeil(i / 100) < 0.05) under = i / 100;
  // "the whole": the first hundredth from which the cards are back for good
  let whole = null;
  for (let i = 1000; i >= 0; i -= 1) { if (momentVeil(i / 100) > 0) break; whole = i / 100; }
  table.push(`anchor.cardsUnderATwentieth ${num(under)}`, `anchor.whole ${num(whole)}`, `anchor.wholeReduced ${num(M.reduced.back[1])}`);
  // "up by": the first sample at which the view is up
  for (const [name, kind] of [['cover', 'duo'], ['slab', 'slab']]) {
    const rows = bedtime.filter((row) => row.startsWith(`${name} full `)).map((row) => row.split(' ').map(Number));
    const up = rows.find((row) => row[4] >= 1);
    table.push(`anchor.up.${kind} ${num(up[2])}`);
  }

  const sections = [
    ['world', ['The displays (lab/core.js, DEVICES) and the two hand-set worlds (hill-painted.js, DUO and SLAB),',
      'with what the page derives from them: the tall sky\'s extent, the tree\'s foot on the knoll, the star',
      'boxes `starsFor` lays out for the lab\'s own layout. `notCarried`: the world\'s fields left in the lab.'], world],
    ['camera', ['Every plane\'s offset (`planeOffset`) for a look and a tilt, on each display at 1×, 2× and 3×, in',
      'points; `rested`: as the layer is placed (`onGrid`: on the pixel grid at either pose).'], camera],
    ['tonight', ['Tonight\'s star\'s place on the display (`tonightHome`), by look and tilt, in points.'], tonight],
    ['looks', ['What follows the look alone, every hundredth of it: `onTheWay` (the gate for what belongs only to',
      'the move), how much of a cloud is there by the view it belongs to (compose), and how much of the tree',
      'is drawn (`treeShown`) with the phone page\'s cards on, half there, and away — and with an opacity of',
      '1.5 (`treeCardsOver`) and −0.5 (`treeCardsUnder`), which the lab holds to 0 … 1.'], looks],
    ['table', ['The moment\'s table (lab/presence.js, MOMENT and SLEEP_DEPTH), the band\'s reach and',
      'pace (`ringOf`), and the anchors the design quotes, found by stepping the lab\'s own curves',
      '(`anchor.bandAnswers`: the last millisecond his stars answer the band, and its strength there).'], table],
    ['captionRule', ['The caption\'s opacity as drawCaption works it out, asked off the moment\'s table: `cards` (how far',
      'the cards have stepped back — the lab\'s veil), `look`, the moment\'s `age`, `lit` (`momentCaption` at',
      'that age) and the opacity (`caption`).'], captionRule],
    ['bedtime', ['The bedtime moment, every 0.05 s from 0 to 10 s, in full and under Reduce Motion: `cards`',
      '(`momentVeil`), `look` (`lookOf`), `star` (`sparkOf`), `caption` (drawCaption\'s opacity) and `captionLit`',
      '(`momentCaption` alone), the band (`ringOf`; `bandLight`: its own light, drawTonight), `depth`',
      '(`roomDepth`), `kept` (drawStars) and `tree` (`treeShown`, with the cards as far back as `cards`).'], bedtime],
    ['quiet', ['The quiet events, sampled the same way on the cover and the slab (they do not know the display):',
      'arrive (the night begins), arriveAgain (after a feed), arriveNap, settle (first light), wakeNight,',
      'wakeNap. `tree`: with the cards on.'], quiet],
  ];
  const text = swiftFile(sections);
  const before = await fsp.readFile(OUT, 'utf8').catch(() => null);
  if (check) {
    if (before !== text) fail(`${path.relative(REPO_ROOT, OUT)} is stale: run node design/sky-lab/tools/swift-fixtures/moment.mjs`);
    process.stdout.write(`moment.mjs: ${path.relative(REPO_ROOT, OUT)} is up to date (${drawnChecks} drawn frames agreed with the probe)\n`);
    return;
  }
  await fsp.writeFile(OUT, text);
  process.stdout.write(`moment.mjs: wrote ${path.relative(REPO_ROOT, OUT)} — ${world.length} world records, ${camera.length - 1} camera rows, ${tonight.length - 1} homes, ${looks.length - 1} looks, ${bedtime.length - 1} + ${quiet.length - 1} samples; ${drawnChecks} drawn frames agreed with the probe${before === text ? ' (unchanged)' : ''}\n`);
}

main().catch((error) => fail(error.stack ?? String(error)));
