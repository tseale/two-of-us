#!/usr/bin/env node
// Sky lab — measure. The one shared ruler for BRIEF.md's hard limits.
//
//   node tools/measure.mjs --sky baseline
//   node tools/measure.mjs --sky true-light --devices cover --schemes dark --times 16:40,03:00 --json out.json
//
// For every (device × scheme × time) it opens the viewer twice, frozen at `t`:
//
//   chrome=1  reads the REAL geometry from the chrome's DOM — where the name, the
//             age line, the leading page's title and subtitle and the strip's clock
//             are (the ink of the glyphs, found by recolouring the text and looking
//             at which pixels changed), every card and its kind, the gear, the
//             island, the status icons — and then, with the chrome hidden, shoots
//             the sky exactly as it was drawn beneath that chrome ("under");
//   chrome=0  shoots the sky alone ("bare"), as tools/shoot.mjs --chrome 0 does.
//
// From those pixels, in linear-light WCAG relative luminance:
//
//   a) behind each text: min, p0.5, median, p99.5, max over the glyphs' ink box
//      padded 2 pt, and the WCAG contrast of the text's computed colour against
//      the worst percentile (the verdict) and against the worst single pixel;
//   b) the ground below the top band in medians of 8 pt blocks — under the cards,
//      in the open (margins, gutter, strip) and both — against the appearance's
//      card and page, with the sun's / moon's disc found and reported apart.
//      "Nothing lighter than a card" is judged on areas, as the brief asks: the
//      level three touching blocks reach together; the lightest single block (a
//      star with its halo) is printed beside it;
//   c) the ground's mean OKLab chroma, so "hush" and "bloom" are numbers;
//   d) at night, a rough count of sharp points in the anchor window (his stars),
//      and with --stars-by-age the count of what differs from the same frame at
//      age 0 — which only his stars do.
//
// Also, without a verdict: the cover's sky against the spread's phone page ("one
// world, two windows"), the sun's and moon's x against the state's, the clock.
//
// Every numeric limit in BRIEF.md is a named check (CHECKS below) with its
// threshold and the sentence it comes from: PASS, AT-LIMIT (passes, within 5 % of
// the threshold) or FAIL per frame, and a summary. Exit code 1 if anything FAILs.
// METHOD below says how each number is made; it is copied into the JSON.
//
// Deterministic: the same command prints the same numbers, and --from-json prints
// the same tables again from a saved JSON. No dependencies but Playwright
// (preinstalled) and Node's own zlib for reading the PNGs.

import http from 'node:http';
import zlib from 'node:zlib';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const LAB_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const STANDARD_TIMES = ['06:50', '09:30', '12:30', '16:10', '16:40', '17:30', '21:00', '03:00'];
const DEVICE_SIZES = { cover: [466, 678], spread: [951, 669], iphone: [402, 874] };   // README, "Displays"

const USAGE = `Usage: node tools/measure.mjs --sky <id> [options]

  --sky <id>              the sky module, skies/<id>.js (required)
  --devices <list>        cover,spread,iphone            (default: all three)
  --schemes <list>        light,dark                     (default: both)
  --times <list>          local HH:MM, comma-separated   (default: ${STANDARD_TIMES.join(',')})
  --asleep 0|nap|night    a sleep is running             (default: 0)
  --date YYYY-MM-DD  --tz <hours>  --lat <deg>  --lon <deg>  --age <days>
                          passed through to the viewer   (defaults: the viewer's)
  --param key=value       any other viewer parameter (repeatable)
  --t <seconds>           the animation instant, frozen  (default: 12, as tools/shoot.mjs)
  --dpr <n>               pixels per point, 1-3          (default: 2)
  --jobs <n>              frames measured at once        (default: 2)
  --timeout <s>           per page load                  (default: 90)
  --json <file>           write everything measured as JSON
  --quiet                 print only the summary, not the table of frames
  --annotate <dir>        save, per frame, <frame>-chrome.png (the rectangles this tool
                          measured, drawn over the chrome=1 shot) and <frame>-sky.png (the
                          disc, the points counted and, on a dark night, the blocks lighter
                          than a card — red where they make an area, dashed orange where
                          they are a point — drawn over the sky alone)
  --save-shots <dir>      save the pixels that were measured: <frame>-bare.png, <frame>-under.png
  --stars-by-age          at night, load the sky alone once more at age 0 and count what differs:
                          his stars and nothing else (one more page load per night frame)
  --sky-file <path>       serve this file as skies/<id>.js without putting it in skies/
                          (for probe skies; its relative imports still resolve inside the lab)
  --from-json <file>      measure nothing: print the tables again from a JSON this tool wrote
                          (--sky is then not needed; with --json, write it back with the
                          summary and notes as this version of the tool words them)

What it measures, per frame (relative luminance is WCAG's, linear light, 0-1):
  text     name, age, the spread's title and subtitle, the strip's clock: the luminance behind
           the glyphs' ink box padded 2 pt — min, p0.5, median, p99.5, max — and the contrast
           of the text's own colour against (pct) the worst percentile, p99.5 under light text
           and p0.5 under dark text, and (abs) the single worst pixel. THE LIMITS USE pct:
           "about areas, not star points". abs is printed beside it and never hidden.
  ground   below the top band, medians of 8 pt blocks: all of it ("below"), the part under
           the opaque and glass cards ("cards") and the part in the open ("open"). The
           sun's / moon's disc is found as the brightest compact, sharp-edged blob and left
           out of those numbers; it is reported on its own line with what it would add.
           "Nothing lighter than a card" is judged on AREAS, as the brief says: the level
           three touching blocks reach together ("area"). The lightest single block — a
           star with its halo can be one — is the strict figure beside it.
  chroma   mean OKLab chroma of the 8 pt blocks under the cards, in the open and in the top band.
  points   at night, sharp bright points in the anchor window, against ageDays (+1 where
           tonight's star is lit: state.tonightLit, or asleep=night in a lab without it). APPROXIMATE — a detector, not a census: it counts chips of
           bright texture and misses faint stars. --stars-by-age adds the count of blobs that
           differ from the same frame at age 0, which only his stars do (expected: ageDays).

A sky that draws differently when it knows where the cards are (state.cards is empty with
chrome=0) is measured twice, "bare" and "under"; otherwise the two are the same picture
and one set of numbers is printed.

Exit code: 0 all checks pass, 1 a check FAILs or a frame could not be measured, 2 bad usage.`;

// ───────────────────────────────────────────────────────────── the limits ──

/** BRIEF.md's numeric limits. `stat` says which number the verdict is given on. */
const CHECKS = [
  {
    id: 'contrast-primary', label: 'contrast ≥ 7:1', kind: 'contrast', roles: ['name', 'title'], schemes: ['light', 'dark'],
    dir: '>=', threshold: 7,
    brief: 'Hard limits: "At full bloom the name must stay ≥ 7:1 and the secondary line ≥ 3:1." (The text on the sky is "his name, age, the page titles"; the spread\'s title is set like the name, so it is held to the name\'s limit and listed separately.)',
  },
  {
    id: 'contrast-secondary', label: 'contrast ≥ 3:1', kind: 'contrast', roles: ['age', 'subtitle'], schemes: ['light', 'dark'],
    dir: '>=', threshold: 3,
    brief: 'Hard limits: "At full bloom the name must stay ≥ 7:1 and the secondary line ≥ 3:1."',
  },
  {
    id: 'light-grey-ground', label: 'light: L behind grey line ≥ 0.55', kind: 'behind', roles: ['age', 'subtitle'], schemes: ['light'],
    dir: '>=', threshold: 0.55,
    brief: 'Director\'s notes: "Light: behind the grey line (#6C6C70) the sky\'s relative luminance must stay ≥ 0.55 (about #C4C4C4 or lighter)".',
  },
  {
    id: 'dark-grey-ground', label: 'dark: L behind grey line ≤ 0.072', kind: 'behind', roles: ['age', 'subtitle'], schemes: ['dark'],
    dir: '<=', threshold: 0.072,
    brief: 'Director\'s notes: "Dark: behind the grey line (#98989F) ≤ 0.072 (about #4C4C4C or darker)".',
  },
  {
    id: 'dark-name-ground', label: 'dark: L behind white name ≤ 0.10', kind: 'behind', roles: ['name', 'title'], schemes: ['dark'],
    dir: '<=', threshold: 0.10,
    brief: 'Director\'s notes: "Dark: … behind the white name ≤ 0.10".',
  },
  {
    id: 'dark-night-ground', label: 'dark night: ground below band ≤ card', kind: 'ground', schemes: ['dark'], nightOnly: true,
    dir: '<=', threshold: null,       // the card's own luminance, read from the chrome (#1C1C1E → 0.0116)
    brief: 'Hard limits: "night in the dark appearance is near-black with tints, the moon\'s glow is quiet, and nothing below the top band is lighter than a card (#1C1C1E)"; Director\'s notes: "\'Nothing lighter than a card\' is about areas, not star points."',
  },
];

const METHOD = {
  luminance: 'WCAG relative luminance: sRGB bytes → linear (c ≤ 0.04045 ? c/12.92 : ((c+0.055)/1.055)^2.4), L = 0.2126 R + 0.7152 G + 0.0722 B.',
  contrast: '(L_lighter + 0.05) / (L_darker + 0.05). The text colour is the element\'s computed colour. "pct" is the least contrast against any pixel between the p0.5 and p99.5 ranks, "abs" against any pixel at all: that is p99.5 / max under text lighter than its ground and p0.5 / min under text darker than it — unless the ground crosses the text\'s own luminance, when it is the pixel nearest to it (worst.crossed).',
  percentiles: 'Nearest rank on the sorted values: p = value[ceil(p/100 · n) − 1]; the median is p50.',
  textRect: 'The ink box of the glyphs — the pixels that change when the text alone is recoloured red and then cyan (coverage ≥ 1/16) — padded 2 pt, clipped to the display.',
  textVerdict: 'Verdicts use the worst percentile behind the text: p99.5 where the text is lighter than its ground, p0.5 where it is darker ("pct"). The single worst pixel ("abs") is reported beside it and is stricter; the brief speaks of areas, not points.',
  smooth: 'smooth3 is the extreme of a sliding 3 pt × 3 pt mean (the ground a letter\'s stroke sits on); given for comparison with round one\'s claims, never used for a verdict.',
  band: 'The top band ends where the first card begins on each page (cover and the spread\'s phone page: the hero card\'s top; the spread\'s leading page and gutter: the leading cards\' top). "Below the band" is everything under that line except the Dynamic Island.',
  area: 'The brief: "\'Nothing lighter than a card\' is about areas, not star points." A star with its halo can lift the median of one 8 pt block, or of two when it sits on their shared edge. So the dark-night verdict is given on areaLevel — the lightest level that three touching blocks (8-connected; 192 pt² or more) reach together, found by adding the blocks lightest first and joining neighbours until a group has three. "Three" is this tool\'s reading of "area"; the brief gives no size. The strict figure beside it is the lightest single block (max), and ground.maxWithDisc is that with the disc\'s own blocks left in.',
  blocks: 'Blocks are 8 pt × 8 pt on a grid from the display\'s top-left. A block counts for a region when at least half of it lies in the region (and outside any disc); its value is the median luminance of those pixels.',
  regions: 'cards = the union of the opaque (hero, timeline, detail) and glass (tile, sleep, tabbar, toast) card rects; open = below the band and under no card; below = both.',
  disc: 'The sun\'s / moon\'s disc is detected, not read from the state (a sky may put it at its own height): on 2 pt cell means, the brightest cell\'s connected blob above background + 50 % (then 70 %, 85 %) of its excess; it is a disc if it is 10–90 pt across, no more than 3:1, fills at least 35 % of its box\'s ellipse (so a thin crescent is NOT found, and is then counted as ground), and the ring 4–6 pt outside it has lost at least 30 % of the blob\'s mean excess. Up to two are kept, the second only if its excess is at least a quarter of the first\'s. state.sun.x (or state.scene.body where the lab has no sun.x; the sun is looked for down to −6°) and state.moon only name it: "sun" or "moon" when its x is within a fifth of the anchor window of where the state puts that body, else "unknown". A named disc and 3 pt around it are left out of the block statistics and reported apart (ground.maxWithDisc is the figure with it left in); an unknown blob is reported but stays in the ground.',
  night: 'A night frame, for "dark night", is one with the sun at or below −10.5° — where lab/presence.js\'s solar bloom has fully settled.',
  chroma: 'OKLab chroma of each 8 pt block\'s mean colour (averaged in linear light), then the mean over the region\'s blocks.',
  points: 'APPROXIMATE. Grey level g = 255·sRGB(L). A pixel is a candidate when g differs from the mean of the 7 pt square around it (taken without the other candidates) by max(6 levels, 6 robust σ of the window, 6 σ of the 15 pt square around it); 8-connected candidates form a fragment when their box is ≤ 12 pt and they are clear of the disc; fragments within 4 pt of each other are one point (the arms of a glint); a run of them longer than 12 pt (a brushed ridge line), a point with three or more others within 8 pt (a texture) and a point on a line with four or more others within 30 pt (a drawn edge) are not counted. Brighter and darker points are counted apart. Counted in the anchor window, all heights. Faint or twinkled-down stars are missed; chips of bright texture are counted. Expected: ageDays, and one more where tonight\'s star is lit (state.tonightLit; asleep=night in a lab without it).',
  starsByAge: 'With --stars-by-age: the sky alone is shot once more at age 0 (no stars of his yet); pixels 2 levels or more apart are grouped into 8-connected blobs in the anchor window (a blob must reach 4 levels to count), and inside a blob each separate core (pixels at least half as far apart as the blob\'s most different one; cores within 3 pt are one) is a star. Blobs larger than 40 pt are set aside. Expected ageDays: tonight\'s star is the same at both ages and cancels.',
  anchor: 'One world, two windows (no verdict): each cover frame against the spread\'s phone page (x from state.phone.x) at the same scheme and time, both reduced to one mean colour per point; the mean over points of the largest channel difference in 8-bit levels, and the share of points more than 8 levels apart — at the same y, and at the vertical shift (−12…12 pt) that fits best. The spread is 9 pt shorter than the cover.',
  discX: 'Sun and moon against the baseline\'s clock (no verdict): a named disc\'s offsetX is its centre\'s x minus state.phone.x + state.sun.x (state.scene.body.x in a lab without it; state.moon.x for the moon) × state.phone.width. The summary line counts the dark appearance only (on a light page a pale cloud can pass for a disc).',
  sources: 'bare = the viewer with chrome=0. under = the viewer with chrome=1 and the chrome hidden for the shot, i.e. the sky as drawn beneath the real cards. When the two differ by more than 2 levels anywhere, both are measured and judged.',
};

// ──────────────────────────────────────────────────────────── arguments ──

function fail(message) {
  process.stderr.write(`measure: ${message}\n\n${USAGE}\n`);
  process.exit(2);
}

function parseArgs(argv) {
  const flags = new Set(['help', 'quiet', 'stars-by-age']);
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

const KNOWN = new Set(['sky', 'devices', 'schemes', 'times', 'asleep', 'date', 'tz', 'lat', 'lon', 'age', 'param', 't', 'dpr',
  'jobs', 'timeout', 'json', 'quiet', 'annotate', 'save-shots', 'sky-file', 'stars-by-age', 'from-json', 'help']);

const list = (value, fallback) => (value == null ? fallback : String(value).split(',').map((s) => s.trim()).filter(Boolean));

function numberOption(options, key, fallback, lo, hi) {
  if (options[key] == null) return fallback;
  const value = Number(options[key]);
  if (!Number.isFinite(value) || value < lo || value > hi) fail(`--${key} must be a number from ${lo} to ${hi} (got "${options[key]}")`);
  return value;
}

function cleanTime(text) {
  const m = /^(\d{1,2}):?(\d{2})$/.exec(String(text).trim());
  if (!m || Number(m[1]) > 23 || Number(m[2]) > 59) fail(`"${text}" is not a time (HH:MM, 24 h)`);
  return `${m[1].padStart(2, '0')}:${m[2]}`;
}

function readOptions(argv) {
  const options = parseArgs(argv);
  if (options.help) { process.stdout.write(`${USAGE}\n`); process.exit(0); }
  for (const key of Object.keys(options)) if (!KNOWN.has(key)) fail(`unknown option --${key}`);
  if (options['from-json'] != null) {
    return {
      fromJson: path.resolve(process.cwd(), String(options['from-json'])),
      json: options.json == null ? null : path.resolve(process.cwd(), String(options.json)),
      quiet: Boolean(options.quiet),
    };
  }
  if (!options.sky || options.sky === true) fail('--sky <id> is required');
  if (!/^[A-Za-z0-9][A-Za-z0-9_-]*$/.test(options.sky)) fail(`"${options.sky}" is not a sky id`);
  const devices = list(options.devices, Object.keys(DEVICE_SIZES));
  for (const device of devices) if (!Object.hasOwn(DEVICE_SIZES, device)) fail(`unknown device "${device}" (cover, spread, iphone)`);
  const schemes = list(options.schemes, ['light', 'dark']);
  for (const scheme of schemes) if (!['light', 'dark'].includes(scheme)) fail(`unknown scheme "${scheme}" (light, dark)`);
  const times = list(options.times, STANDARD_TIMES).map(cleanTime);
  if (!devices.length || !schemes.length || !times.length) fail('nothing to measure');
  const asleep = options.asleep ?? '0';
  if (!['0', 'nap', 'night'].includes(asleep)) fail(`--asleep is 0, nap or night (got "${asleep}")`);

  // What every frame's URL carries besides device, scheme, time and chrome.
  const query = { sky: options.sky, asleep, t: numberOption(options, 't', 12, -1e9, 1e9), dpr: numberOption(options, 'dpr', 2, 1, 3) };
  for (const key of ['date', 'tz', 'lat', 'lon', 'age']) if (options[key] != null) query[key] = String(options[key]);
  for (const pair of options.param) {
    const eq = String(pair).indexOf('=');
    if (eq < 1) fail(`--param takes key=value (got "${pair}")`);
    const key = pair.slice(0, eq);
    if (['device', 'scheme', 'time', 'chrome', 'ui', 'bezel', 'zoom'].includes(key)) fail(`--param ${key}= is set by the tool itself`);
    query[key] = pair.slice(eq + 1);
  }
  const resolve = (p) => (p == null ? null : path.resolve(process.cwd(), String(p)));
  return {
    sky: options.sky, devices, schemes, times, asleep, query,
    dpr: query.dpr,
    jobs: Math.round(numberOption(options, 'jobs', 2, 1, 16)),
    timeout: numberOption(options, 'timeout', 90, 1, 3600) * 1000,
    json: resolve(options.json),
    quiet: Boolean(options.quiet),
    annotate: resolve(options.annotate),
    saveShots: resolve(options['save-shots']),
    skyFile: resolve(options['sky-file']),
    starsByAge: Boolean(options['stars-by-age']),
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

/** A static server for the lab on a free port (the pattern of tools/shoot.mjs).
 *  `overrides` maps a URL path to a file elsewhere (--sky-file). */
function serve(root, overrides) {
  const server = http.createServer(async (request, response) => {
    try {
      const url = new URL(request.url, 'http://localhost');
      let pathname = decodeURIComponent(url.pathname);
      if (pathname.endsWith('/')) pathname += 'index.html';
      let file = path.resolve(root, `.${pathname}`);
      let cache = 'max-age=600';
      if (overrides.has(pathname)) {
        file = overrides.get(pathname);
        cache = 'no-store';
      } else if (file !== root && !file.startsWith(root + path.sep)) {
        throw Object.assign(new Error('outside the lab'), { code: 'ENOENT' });
      }
      const body = await fsp.readFile(file);
      response.writeHead(200, { 'Content-Type': TYPES[path.extname(file).toLowerCase()] ?? 'application/octet-stream', 'Cache-Control': cache });
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

// ─────────────────────────────────────────────────────────────── pixels ──

/** A PNG as Playwright writes it (8-bit RGB or RGBA, not interlaced) → { width, height, rgb }. */
function decodePng(buffer) {
  if (buffer.length < 8 || buffer.readUInt32BE(0) !== 0x89504e47 || buffer.readUInt32BE(4) !== 0x0d0a1a0a) throw new Error('not a PNG');
  let offset = 8;
  let width = 0;
  let height = 0;
  let channels = 0;
  const parts = [];
  while (offset < buffer.length) {
    const length = buffer.readUInt32BE(offset);
    const type = buffer.toString('latin1', offset + 4, offset + 8);
    const body = buffer.subarray(offset + 8, offset + 8 + length);
    if (type === 'IHDR') {
      width = body.readUInt32BE(0);
      height = body.readUInt32BE(4);
      if (body[8] !== 8 || (body[9] !== 2 && body[9] !== 6) || body[12] !== 0) {
        throw new Error(`unsupported PNG (bit depth ${body[8]}, colour type ${body[9]}, interlace ${body[12]})`);
      }
      channels = body[9] === 6 ? 4 : 3;
    } else if (type === 'IDAT') {
      parts.push(body);
    } else if (type === 'IEND') {
      break;
    }
    offset += 12 + length;
  }
  const raw = zlib.inflateSync(Buffer.concat(parts));
  const stride = width * channels;
  if (raw.length < (stride + 1) * height) throw new Error('truncated PNG');
  const rgb = new Uint8Array(width * height * 3);
  let previous = new Uint8Array(stride);
  let current = new Uint8Array(stride);
  let p = 0;
  let o = 0;
  let minAlpha = 255;
  for (let y = 0; y < height; y += 1) {
    const filter = raw[p];
    p += 1;
    for (let i = 0; i < stride; i += 1) current[i] = raw[p + i];
    p += stride;
    if (filter === 1) {
      for (let i = channels; i < stride; i += 1) current[i] = (current[i] + current[i - channels]) & 255;
    } else if (filter === 2) {
      for (let i = 0; i < stride; i += 1) current[i] = (current[i] + previous[i]) & 255;
    } else if (filter === 3) {
      for (let i = 0; i < stride; i += 1) {
        const left = i >= channels ? current[i - channels] : 0;
        current[i] = (current[i] + ((left + previous[i]) >> 1)) & 255;
      }
    } else if (filter === 4) {
      for (let i = 0; i < stride; i += 1) {
        const a = i >= channels ? current[i - channels] : 0;
        const b = previous[i];
        const c = i >= channels ? previous[i - channels] : 0;
        const pa = Math.abs(b - c);
        const pb = Math.abs(a - c);
        const pc = Math.abs(a + b - 2 * c);
        current[i] = (current[i] + (pa <= pb && pa <= pc ? a : pb <= pc ? b : c)) & 255;
      }
    } else if (filter !== 0) {
      throw new Error(`bad PNG filter ${filter}`);
    }
    if (channels === 3) {
      rgb.set(current, o);
      o += stride;
    } else {
      for (let i = 0; i < stride; i += 4) {
        rgb[o] = current[i]; rgb[o + 1] = current[i + 1]; rgb[o + 2] = current[i + 2];
        if (current[i + 3] < minAlpha) minAlpha = current[i + 3];
        o += 3;
      }
    }
    const swap = previous; previous = current; current = swap;
  }
  if (minAlpha < 255) throw new Error('the screenshot is not opaque');
  return { width, height, rgb };
}

const LINEAR = new Float64Array(256);
for (let i = 0; i < 256; i += 1) {
  const c = i / 255;
  LINEAR[i] = c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
}
const encode = (v) => (v <= 0.0031308 ? 12.92 * v : 1.055 * v ** (1 / 2.4) - 0.055);
const luminanceOf = (r, g, b) => 0.2126 * LINEAR[r] + 0.7152 * LINEAR[g] + 0.0722 * LINEAR[b];
const contrast = (a, b) => (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);

/** OKLab chroma and hue (degrees) of a linear-light sRGB colour (the matrices of lab/oklab.js). */
function oklabOfLinear(lr, lg, lb) {
  const l = Math.cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb);
  const m = Math.cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb);
  const s = Math.cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb);
  return {
    L: 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
    a: 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
    b: 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s,
  };
}

/** 'rgb(1, 2, 3)' / 'rgba(…)' / '#rrggbb' → { r, g, b, a } (bytes; a 0–1), or null. */
function parseColour(text) {
  const value = String(text ?? '').trim();
  let m = /^#([0-9a-f]{6})$/i.exec(value);
  if (m) {
    const n = parseInt(m[1], 16);
    return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255, a: 1 };
  }
  m = /^#([0-9a-f]{3})$/i.exec(value);
  if (m) {
    const [r, g, b] = m[1].split('').map((c) => parseInt(c + c, 16));
    return { r, g, b, a: 1 };
  }
  m = /^rgba?\(([^)]+)\)$/i.exec(value);
  if (m) {
    const parts = m[1].split(/[\s,/]+/).filter(Boolean).map(Number);
    if (parts.length >= 3 && parts.every(Number.isFinite)) {
      return { r: Math.round(parts[0]), g: Math.round(parts[1]), b: Math.round(parts[2]), a: parts.length > 3 ? parts[3] : 1 };
    }
  }
  return null;
}
const hexOf = (c) => `#${[c.r, c.g, c.b].map((v) => v.toString(16).padStart(2, '0')).join('').toUpperCase()}`;

/** Nearest-rank percentile of an ascending array. */
function percentile(sorted, p) {
  const n = sorted.length;
  if (!n) return null;
  return sorted[Math.min(n - 1, Math.max(0, Math.ceil((p / 100) * n) - 1))];
}

class Picture {
  /** @param {{width:number,height:number,rgb:Uint8Array}} image  @param {number} dpr */
  constructor(image, dpr) {
    this.width = image.width;
    this.height = image.height;
    this.rgb = image.rgb;
    this.dpr = dpr;
    const n = this.width * this.height;
    this.Y = new Float64Array(n);
    for (let i = 0, j = 0; i < n; i += 1, j += 3) this.Y[i] = luminanceOf(this.rgb[j], this.rgb[j + 1], this.rgb[j + 2]);
  }

  /** A rect in points → whole device pixels covering it, clipped: [x0, y0, x1, y1), exclusive ends. */
  box(rect) {
    const e = 1e-6;
    const x0 = Math.max(0, Math.floor(rect.x * this.dpr + e));
    const y0 = Math.max(0, Math.floor(rect.y * this.dpr + e));
    const x1 = Math.min(this.width, Math.ceil((rect.x + rect.width) * this.dpr - e));
    const y1 = Math.min(this.height, Math.ceil((rect.y + rect.height) * this.dpr - e));
    return [x0, y0, Math.max(x0, x1), Math.max(y0, y1)];
  }
}

// ───────────────────────────────────────────────────── reading the chrome ──

/** Runs in the page (chrome=1): the geometry of everything this tool looks behind. */
function readChrome() {
  const display = document.getElementById('display');
  const lab = window.__lab;
  const s = lab.state;
  const frame = display.getBoundingClientRect();
  const scale = frame.width > 0 && s.width > 0 ? frame.width / s.width : 1;
  const round = (v) => Math.round(v * 1000) / 1000;
  const rel = (r) => ({ x: round((r.left - frame.left) / scale), y: round((r.top - frame.top) / scale), width: round(r.width / scale), height: round(r.height / scale) });
  const root = display.querySelector('.tou-chrome') || document.getElementById('chrome-root');
  if (!root) throw new Error('the chrome is not in the page (no .tou-chrome)');

  const opacityOf = (el) => {
    let value = 1;
    for (let node = el; node && node !== display; node = node.parentElement) value *= Number(getComputedStyle(node).opacity);
    return round(value);
  };

  // A text: the run of text nodes directly inside one element.
  let serial = 0;
  const textsIn = (container, skip) => {
    const found = new Map();
    const walker = document.createTreeWalker(container, NodeFilter.SHOW_TEXT);
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      if (!node.nodeValue.trim()) continue;
      const parent = node.parentElement;
      if (!parent || parent.closest('svg') || (skip && parent.closest(skip))) continue;
      const range = document.createRange();
      range.selectNodeContents(node);
      const rects = [...range.getClientRects()].filter((r) => r.width > 0 && r.height > 0);
      if (!rects.length) continue;
      const entry = found.get(parent) ?? { element: parent, text: '', left: Infinity, top: Infinity, right: -Infinity, bottom: -Infinity };
      entry.text += node.nodeValue;
      for (const r of rects) {
        entry.left = Math.min(entry.left, r.left); entry.top = Math.min(entry.top, r.top);
        entry.right = Math.max(entry.right, r.right); entry.bottom = Math.max(entry.bottom, r.bottom);
      }
      found.set(parent, entry);
    }
    return [...found.values()].map((entry) => {
      const style = getComputedStyle(entry.element);
      serial += 1;
      const id = `m${serial}`;
      entry.element.setAttribute('data-measure', id);
      return {
        id,
        text: entry.text.replace(/\s+/g, ' ').trim(),
        line: rel({ left: entry.left, top: entry.top, width: entry.right - entry.left, height: entry.bottom - entry.top }),
        colour: style.color,
        fill: style.webkitTextFillColor || style.color,
        font: `${style.fontWeight} ${style.fontSize} ${style.fontFamily.split(',')[0].trim()}`,
        opacity: opacityOf(entry.element),
      };
    });
  };

  const texts = [];
  const furniture = [];
  const push = (kind, el) => { if (el) furniture.push({ kind, ...rel(el.getBoundingClientRect()), opacity: opacityOf(el) }); };
  const phoneX = s.phone ? s.phone.x : 0;

  for (const header of root.querySelectorAll('[data-card="header"]')) {
    const box = header.getBoundingClientRect();
    const leading = phoneX > 0 && (box.left - frame.left) / scale + box.width / scale / 2 < phoneX;
    const main = textsIn(header, '.weekstamp');
    const names = leading ? ['title', 'subtitle'] : ['name', 'age'];
    main.forEach((text, i) => texts.push({ role: names[i] ?? `${leading ? 'lead' : 'header'}-text-${i + 1}`, page: leading ? 'leading' : 'phone', ...text }));
    for (const stamp of header.querySelectorAll('.weekstamp')) {
      push('weekstamp', stamp);
      textsIn(stamp).forEach((text, i) => texts.push({ role: i === 0 ? 'stamp-label' : 'stamp-number', page: 'leading', ...text }));
    }
    for (const avatar of header.querySelectorAll('.avatar')) push('avatar', avatar);
    for (const gear of header.querySelectorAll('.gear')) push('gear', gear);
  }
  for (const strip of root.querySelectorAll('[data-card="strip"]')) {
    textsIn(strip, '[data-card="tabbar"], .island').forEach((text, i) => texts.push({ role: i === 0 ? 'clock' : `strip-text-${i + 1}`, page: 'strip', ...text }));
    for (const island of strip.querySelectorAll('.island')) push('island', island);
    for (const icons of strip.querySelectorAll('.status-icons')) {
      push('status-icons', icons);
      for (const svg of icons.querySelectorAll('svg')) push('status-icon', svg);
    }
  }
  for (const tab of root.querySelectorAll('[data-card="tabbar"] .tab')) push('tab', tab);

  const dom = [...root.querySelectorAll('[data-card]')].map((el) => ({ kind: el.dataset.card, ...rel(el.getBoundingClientRect()), opacity: opacityOf(el) }));
  const tokens = {};
  const rootStyle = getComputedStyle(root);
  for (const name of ['--bg', '--card', '--text', '--text2']) tokens[name.slice(2)] = rootStyle.getPropertyValue(name).trim();

  const moon = s.moon ? { altitude: s.moon.altitude, fraction: s.moon.fraction, x: s.moon.x, y: s.moon.y, inDaylight: s.moon.inDaylight } : null;
  return {
    state: {
      device: s.device, width: s.width, height: s.height, dpr: s.dpr, scheme: s.scheme,
      phone: s.phone, fold: s.fold, strip: s.strip,
      localHour: s.localHour, dayOfYear: s.dayOfYear, asleep: s.asleep, ageDays: s.ageDays, t: s.t,
      sun: { altitude: s.sun.altitude, azimuth: s.sun.azimuth, isNight: s.sun.isNight, progress: s.sun.progress, x: typeof s.sun.x === 'number' ? s.sun.x : null },
      tonightLit: typeof s.tonightLit === 'boolean' ? s.tonightLit : null,
      moon,
      body: s.scene && s.scene.body ? { x: s.scene.body.x, y: s.scene.body.y } : null,
      event: s.event ?? null, veil: s.veil ?? null, lead: s.lead ?? null,
    },
    origin: { x: frame.left, y: frame.top, scale },
    cards: lab.cards.map((card) => ({ kind: card.kind, x: card.x, y: card.y, width: card.width, height: card.height })),
    // The lab's own measure of the header's text, where it has one (state.layout): only compared with ours.
    labLayout: (() => {
      const layout = lab.layout ?? s.layout;
      if (!layout || typeof layout !== 'object') return null;
      const out = {};
      for (const key of ['name', 'age', 'title', 'subtitle']) {
        const r = layout[key];
        if (r && [r.x, r.y, r.width, r.height].every(Number.isFinite)) out[key] = { x: r.x, y: r.y, width: r.width, height: r.height };
      }
      return Object.keys(out).length ? out : null;
    })(),
    dom, texts, furniture, tokens,
  };
}

/** Runs in the page: the state alone (chrome=0). */
function readBare() {
  const s = window.__lab.state;
  return { sunAltitude: s.sun.altitude, width: s.width, height: s.height, cards: window.__lab.cards.length, t: s.t };
}

const INK_STYLE = `
  [data-measure-ink="a"], [data-measure-ink="a"] * { color: rgb(255, 0, 0) !important; -webkit-text-fill-color: rgb(255, 0, 0) !important; }
  [data-measure-ink="b"], [data-measure-ink="b"] * { color: rgb(0, 255, 255) !important; -webkit-text-fill-color: rgb(0, 255, 255) !important; }
  .tou-chrome[data-measure-hidden], #chrome-root[data-measure-hidden] { visibility: hidden !important; opacity: 0 !important; }
  .tou-chrome[data-measure-hidden] * { visibility: hidden !important; }`;

const SHOT = { animations: 'disabled', caret: 'hide' };
const inkCache = new Map();

/**
 * The ink box of one text, in points: the pixels that change when the text is
 * drawn red and then cyan (every channel moves by coverage × 255, whatever is
 * behind it). Nothing about the sky enters it. Falls back to the line box when
 * the text is not drawn (opacity 0).
 */
async function inkBox(page, device, text, geometry) {
  const key = [device, text.role, text.text, text.font, text.line.x, text.line.y, text.line.width, text.line.height, text.opacity].join('|');
  if (inkCache.has(key)) return inkCache.get(key);
  const margin = 6;
  const x0 = Math.max(0, Math.floor(text.line.x - margin));
  const y0 = Math.max(0, Math.floor(text.line.y - margin));
  const x1 = Math.min(geometry.state.width, Math.ceil(text.line.x + text.line.width + margin));
  const y1 = Math.min(geometry.state.height, Math.ceil(text.line.y + text.line.height + margin));
  let result = { ...text.line, source: 'line box (no ink found)' };
  if (x1 > x0 && y1 > y0) {
    const clip = { x: geometry.origin.x + x0, y: geometry.origin.y + y0, width: x1 - x0, height: y1 - y0 };
    const shoot = async (mark) => {
      await page.evaluate(([id, value]) => {
        const el = document.querySelector(`[data-measure="${id}"]`);
        if (value) el.setAttribute('data-measure-ink', value); else el.removeAttribute('data-measure-ink');
      }, [text.id, mark]);
      return mark ? decodePng(await page.screenshot({ clip, ...SHOT })) : null;
    };
    const a = await shoot('a');
    const b = await shoot('b');
    await shoot(null);
    let minX = Infinity; let minY = Infinity; let maxX = -1; let maxY = -1;
    for (let y = 0, i = 0; y < a.height; y += 1) {
      for (let x = 0; x < a.width; x += 1, i += 3) {
        const d = Math.max(Math.abs(a.rgb[i] - b.rgb[i]), Math.abs(a.rgb[i + 1] - b.rgb[i + 1]), Math.abs(a.rgb[i + 2] - b.rgb[i + 2]));
        if (d >= 16) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    if (maxX >= 0) {
      const k = a.width / (x1 - x0);      // device pixels per point in the shot
      result = { x: x0 + minX / k, y: y0 + minY / k, width: (maxX + 1 - minX) / k, height: (maxY + 1 - minY) / k, source: 'ink' };
    }
  }
  inkCache.set(key, result);
  return result;
}

// ───────────────────────────────────────────────────────────── analysis ──

const OPAQUE_KINDS = new Set(['hero', 'timeline', 'detail']);
const GLASS_KINDS = new Set(['tile', 'sleep', 'tabbar', 'toast']);
const BIT = { below: 1, opaque: 2, glass: 4, occluder: 8, disc: 16 };
const PAD_PT = 2;
const BLOCK_PT = 8;

/** Where the top band ends on each page (points from the top). */
function bandFoot(geometry) {
  const { state, cards } = geometry;
  const surfaces = cards.filter((card) => OPAQUE_KINDS.has(card.kind) || card.kind === 'tile' || card.kind === 'sleep');
  const phoneX = state.phone ? state.phone.x : 0;
  const top = (items) => (items.length ? Math.min(...items.map((card) => card.y)) : null);
  const phone = top(surfaces.filter((card) => card.x + card.width / 2 >= phoneX));
  const leading = phoneX > 0 ? top(surfaces.filter((card) => card.x + card.width / 2 < phoneX)) : null;
  const headers = cards.filter((card) => card.kind === 'header');
  const fallback = headers.length ? Math.max(...headers.map((card) => card.y + card.height)) : 0;
  return { phone: phone ?? leading ?? fallback, leading: leading ?? phone ?? fallback, phoneX };
}

/** Statistics behind one text. */
function behindText(picture, rect, colour, opacity) {
  const padded = { x: rect.x - PAD_PT, y: rect.y - PAD_PT, width: rect.width + 2 * PAD_PT, height: rect.height + 2 * PAD_PT };
  const [x0, y0, x1, y1] = picture.box(padded);
  const w = x1 - x0;
  const h = y1 - y0;
  if (w < 1 || h < 1) return null;
  const values = new Float64Array(w * h);
  let sum = 0;
  for (let y = y0, k = 0; y < y1; y += 1) {
    const row = y * picture.width;
    for (let x = x0; x < x1; x += 1, k += 1) { values[k] = picture.Y[row + x]; sum += values[k]; }
  }
  // The sliding 3 pt mean: the ground a stroke sits on, without single grains.
  const side = Math.max(1, Math.round(3 * picture.dpr));
  let smoothMin = null;
  let smoothMax = null;
  if (w >= side && h >= side) {
    const integral = new Float64Array((w + 1) * (h + 1));
    for (let y = 0; y < h; y += 1) {
      let run = 0;
      for (let x = 0; x < w; x += 1) {
        run += values[y * w + x];
        integral[(y + 1) * (w + 1) + x + 1] = integral[y * (w + 1) + x + 1] + run;
      }
    }
    smoothMin = Infinity; smoothMax = -Infinity;
    for (let y = 0; y + side <= h; y += 1) {
      for (let x = 0; x + side <= w; x += 1) {
        const total = integral[(y + side) * (w + 1) + x + side] - integral[y * (w + 1) + x + side]
          - integral[(y + side) * (w + 1) + x] + integral[y * (w + 1) + x];
        const mean = total / (side * side);
        if (mean < smoothMin) smoothMin = mean;
        if (mean > smoothMax) smoothMax = mean;
      }
    }
  }
  const sorted = Float64Array.from(values).sort();
  const stats = {
    min: sorted[0], p0_5: percentile(sorted, 0.5), median: percentile(sorted, 50), p99_5: percentile(sorted, 99.5), max: sorted[sorted.length - 1],
    mean: sum / sorted.length, smooth3Min: smoothMin, smooth3Max: smoothMax, pixels: sorted.length,
  };
  const fg = luminanceOf(colour.r, colour.g, colour.b);
  // The text's colour as drawn: its own alpha and its ancestors' opacity mix it into the ground.
  const alpha = Math.min(1, Math.max(0, (colour.a ?? 1) * (opacity ?? 1)));
  const drawn = (ground) => {
    if (alpha >= 0.999) return fg;
    const g = encode(ground);
    const mix = (c) => LINEAR[Math.round(255 * Math.min(1, Math.max(0, alpha * (c / 255) + (1 - alpha) * g)))];
    return 0.2126 * mix(colour.r) + 0.7152 * mix(colour.g) + 0.0722 * mix(colour.b);
  };
  const against = (ground) => contrast(drawn(ground), ground);
  const lighter = fg >= stats.median;        // the text is lighter than its ground
  const n = sorted.length;
  const rank = (p) => Math.min(n - 1, Math.max(0, Math.ceil((p / 100) * n) - 1));
  // The pixel among sorted[from..to] the text has the least contrast against: the nearest
  // one below the text's own luminance or the nearest one above it, whichever ratio is smaller.
  const nearest = (from, to) => {
    let lo = from;
    let hi = to;
    while (lo < hi) {
      const mid = (lo + hi) >> 1;
      if (sorted[mid] < fg) lo = mid + 1; else hi = mid;
    }
    return lo > from && against(sorted[lo - 1]) <= against(sorted[lo]) ? sorted[lo - 1] : sorted[lo];
  };
  const sidePct = lighter ? stats.p99_5 : stats.p0_5;
  const sideAbs = lighter ? stats.max : stats.min;
  const nearPct = nearest(rank(0.5), rank(99.5));
  const nearAbs = nearest(0, n - 1);
  const worstSmooth = smoothMin == null ? null : lighter ? smoothMax : smoothMin;
  return {
    rect: padded,
    luminance: stats,
    text: { colour: hexOf(colour), luminance: fg, alpha, lighterThanGround: lighter },
    // `pct`, `abs`: the task's worst-case ground — p99.5 / max under light text, p0.5 / min under dark text.
    // `crossed`: the ground passes through the text's own luminance (some pixel between those ranks is nearer to it).
    worst: { statistic: lighter ? 'p99.5' : 'p0.5', pct: sidePct, abs: sideAbs, smooth3: worstSmooth, nearestPct: nearPct, nearestAbs: nearAbs, crossed: nearPct !== sidePct },
    contrast: {
      pct: against(nearPct),
      abs: against(nearAbs),
      median: against(stats.median),
      smooth3: worstSmooth == null ? null : against(worstSmooth),
    },
  };
}

/** The sun's / moon's disc: the brightest compact, sharp-edged blob (METHOD.disc). */
function findDiscs(picture, geometry) {
  const { dpr } = picture;
  const cell = Math.max(1, Math.round(2 * dpr));
  const cw = Math.floor(picture.width / cell);
  const ch = Math.floor(picture.height / cell);
  const means = new Float64Array(cw * ch);
  for (let cy = 0; cy < ch; cy += 1) {
    for (let cx = 0; cx < cw; cx += 1) {
      let sum = 0;
      for (let y = cy * cell; y < (cy + 1) * cell; y += 1) {
        const row = y * picture.width;
        for (let x = cx * cell; x < (cx + 1) * cell; x += 1) sum += picture.Y[row + x];
      }
      means[cy * cw + cx] = sum / (cell * cell);
    }
  }
  const background = percentile(Float64Array.from(means).sort(), 50);
  const pt = cell / dpr;                       // one cell, in points
  const taken = new Uint8Array(cw * ch);
  const discs = [];
  const { state } = geometry;
  const phone = state.phone ?? { x: 0, width: state.width };
  const expected = [];
  // The sun: state.sun.x where the lab gives it (it runs on past sunset; used down to −6°), else
  // the baseline's scene.body while the sun is up.
  if (typeof state.sun.x === 'number' && state.sun.altitude * 180 / Math.PI > -6) expected.push({ body: 'sun', x: phone.x + state.sun.x * phone.width });
  else if (!state.sun.isNight && state.body) expected.push({ body: 'sun', x: phone.x + state.body.x * phone.width });
  if (state.moon) expected.push({ body: 'moon', x: phone.x + state.moon.x * phone.width });

  for (let attempt = 0; attempt < 24 && discs.length < 2; attempt += 1) {
    let peak = -1;
    let at = -1;
    for (let i = 0; i < means.length; i += 1) if (!taken[i] && means[i] > peak) { peak = means[i]; at = i; }
    if (at < 0 || peak - background < 0.04) break;
    if (discs.length && peak - background < 0.25 * (discs[0].peak - background)) break;   // a second body is of the first's order
    let found = null;
    let last = null;
    for (const level of [0.5, 0.7, 0.85]) {
      const threshold = background + level * (peak - background);
      const seen = new Uint8Array(cw * ch);
      const stack = [at];
      seen[at] = 1;
      const cells = [];
      let minX = cw; let minY = ch; let maxX = -1; let maxY = -1;
      while (stack.length) {
        const i = stack.pop();
        cells.push(i);
        const cx = i % cw;
        const cy = (i - cx) / cw;
        if (cx < minX) minX = cx;
        if (cx > maxX) maxX = cx;
        if (cy < minY) minY = cy;
        if (cy > maxY) maxY = cy;
        for (let dy = -1; dy <= 1; dy += 1) {
          for (let dx = -1; dx <= 1; dx += 1) {
            const nx = cx + dx;
            const ny = cy + dy;
            if (nx < 0 || ny < 0 || nx >= cw || ny >= ch) continue;
            const j = ny * cw + nx;
            if (!seen[j] && !taken[j] && means[j] >= threshold) { seen[j] = 1; stack.push(j); }
          }
        }
      }
      last = cells;
      const wide = (maxX - minX + 1) * pt;
      const tall = (maxY - minY + 1) * pt;
      if (Math.min(wide, tall) < 10) break;                   // a point or a glint: it only shrinks from here
      if (Math.max(wide, tall) > 90 || Math.max(wide, tall) / Math.min(wide, tall) > 3) continue;   // a glow or a band: look higher up it
      if (cells.length * pt * pt < 0.35 * (Math.PI / 4) * wide * tall) continue;                    // a cross or a wisp, not a filled shape
      // Sharp-edged? The ring two to three cells outside must have fallen away.
      let inside = 0;
      let weight = 0;
      let sx = 0;
      let sy = 0;
      for (const i of cells) {
        inside += means[i];
        const cx = i % cw;
        const cy = (i - cx) / cw;
        const wgt = means[i] - background;
        weight += wgt; sx += wgt * (cx + 0.5); sy += wgt * (cy + 0.5);
      }
      inside /= cells.length;
      let ring = 0;
      let ringCount = 0;
      for (let cy = Math.max(0, minY - 3); cy <= Math.min(ch - 1, maxY + 3); cy += 1) {
        for (let cx = Math.max(0, minX - 3); cx <= Math.min(cw - 1, maxX + 3); cx += 1) {
          if (seen[cy * cw + cx]) continue;
          let near = Infinity;       // chessboard distance to the blob
          for (let dy = -3; dy <= 3 && near > 1; dy += 1) {
            for (let dx = -3; dx <= 3; dx += 1) {
              const nx = cx + dx;
              const ny = cy + dy;
              if (nx < 0 || ny < 0 || nx >= cw || ny >= ch || !seen[ny * cw + nx]) continue;
              near = Math.min(near, Math.max(Math.abs(dx), Math.abs(dy)));
            }
          }
          if (near === 2 || near === 3) { ring += means[cy * cw + cx]; ringCount += 1; }
        }
      }
      const fall = ringCount ? (ring / ringCount - background) / (inside - background) : 0;
      if (fall > 0.7) continue;                               // soft all the way out: a glow
      const cxPt = (sx / weight) * pt;
      const cyPt = (sy / weight) * pt;
      let reach = 0;
      for (const i of cells) {
        const cx = i % cw;
        const cy = (i - cx) / cw;
        reach = Math.max(reach, Math.hypot((cx + 0.5) * pt - cxPt, (cy + 0.5) * pt - cyPt));
      }
      found = { x: cxPt, y: cyPt, radius: reach + pt / 2, width: wide, height: tall, peak, mean: inside, level, ringFall: fall, cells: cells.length };
      break;
    }
    if (found) {
      let name = 'unknown';
      let best = Infinity;
      let where = null;
      for (const e of expected) {
        if (discs.some((disc) => disc.body === e.body)) continue;      // one sun, one moon
        const d = Math.abs(e.x - found.x);
        if (d < best && d <= 0.2 * phone.width) { best = d; name = e.body; where = e.x; }
      }
      found.body = name;
      found.expectedX = where;                  // the baseline's x for that body (state.scene.body / state.moon)
      found.offsetX = where == null ? null : found.x - where;
      found.exclusion = found.radius + 3;
      found.leftOut = name !== 'unknown';       // only what the state says is the sun or the moon leaves the ground's numbers
      discs.push(found);
      const r = Math.ceil((found.exclusion + 6) / pt);
      const ccx = Math.round(found.x / pt);
      const ccy = Math.round(found.y / pt);
      for (let cy = Math.max(0, ccy - r); cy <= Math.min(ch - 1, ccy + r); cy += 1) {
        for (let cx = Math.max(0, ccx - r); cx <= Math.min(cw - 1, ccx + r); cx += 1) taken[cy * cw + cx] = 1;
      }
    } else {
      for (const i of last) taken[i] = 1;
    }
  }

  // Each disc's glow, in rings outward from the edge of what was left out (2 pt cell means;
  // the median and the 90th percentile, so a star in the ring does not speak for the glow).
  for (const disc of discs) {
    disc.halo = [[0, 8], [8, 20], [20, 40]].map(([from, to]) => {
      const values = [];
      const r1 = disc.exclusion + to;
      for (let cy = Math.max(0, Math.floor((disc.y - r1) / pt)); cy <= Math.min(ch - 1, Math.ceil((disc.y + r1) / pt)); cy += 1) {
        for (let cx = Math.max(0, Math.floor((disc.x - r1) / pt)); cx <= Math.min(cw - 1, Math.ceil((disc.x + r1) / pt)); cx += 1) {
          const d = Math.hypot((cx + 0.5) * pt - disc.x, (cy + 0.5) * pt - disc.y) - disc.exclusion;
          if (d >= from && d < to) values.push(means[cy * cw + cx]);
        }
      }
      values.sort((a, b) => a - b);
      return { fromPt: from, toPt: to, cells: values.length, median: percentile(values, 50), p90: percentile(values, 90), max: values.length ? values[values.length - 1] : null };
    });
  }
  return { discs, background, expected };
}

/** Per-pixel region bits (BIT). */
function regionMask(picture, geometry, discs) {
  const { width, height, dpr } = picture;
  const mask = new Uint8Array(width * height);
  const foot = bandFoot(geometry);
  const footPhone = Math.round(foot.phone * dpr);
  const footLeading = Math.round(foot.leading * dpr);
  const phoneX = Math.round(foot.phoneX * dpr);
  for (let y = 0; y < height; y += 1) {
    const row = y * width;
    for (let x = 0; x < width; x += 1) if (y >= (x >= phoneX ? footPhone : footLeading)) mask[row + x] = BIT.below;
  }
  const paint = (rect, bit) => {
    const [x0, y0, x1, y1] = picture.box(rect);
    for (let y = y0; y < y1; y += 1) {
      const row = y * width;
      for (let x = x0; x < x1; x += 1) mask[row + x] |= bit;
    }
  };
  for (const card of geometry.cards) {
    if (OPAQUE_KINDS.has(card.kind)) paint(card, BIT.opaque);
    else if (GLASS_KINDS.has(card.kind)) paint(card, BIT.glass);
  }
  for (const item of geometry.furniture) if (item.kind === 'island') paint(item, BIT.occluder);
  for (const disc of discs) {
    if (!disc.leftOut) continue;
    const r = disc.exclusion * dpr;
    const cx = disc.x * dpr;
    const cy = disc.y * dpr;
    for (let y = Math.max(0, Math.floor(cy - r)); y < Math.min(height, Math.ceil(cy + r)); y += 1) {
      const row = y * width;
      for (let x = Math.max(0, Math.floor(cx - r)); x < Math.min(width, Math.ceil(cx + r)); x += 1) {
        if (Math.hypot(x + 0.5 - cx, y + 0.5 - cy) <= r) mask[row + x] |= BIT.disc;
      }
    }
  }
  return { mask, foot };
}

const REGIONS = {
  below: (m) => (m & (BIT.below | BIT.opaque | BIT.glass)) !== 0 && (m & BIT.occluder) === 0,
  cards: (m) => (m & (BIT.opaque | BIT.glass)) !== 0 && (m & BIT.occluder) === 0,
  open: (m) => (m & BIT.below) !== 0 && (m & (BIT.opaque | BIT.glass | BIT.occluder)) === 0,
  band: (m) => (m & (BIT.below | BIT.opaque | BIT.glass | BIT.occluder)) === 0,
};

/** Block medians and block chroma for one region. `cardL`: the card's luminance, for the count over it. */
function blockStats(picture, mask, inRegion, cardL) {
  const { width, height, dpr, rgb, Y } = picture;
  const side = Math.max(1, Math.round(BLOCK_PT * dpr));
  const member = new Uint8Array(32);
  for (let m = 0; m < 32; m += 1) member[m] = inRegion(m) ? 1 : 0;
  const medians = [];
  const chromas = [];
  const blocks = [];
  const discMedians = [];
  const columns = Math.ceil(width / side);
  const lines = Math.ceil(height / side);
  const grid = new Int32Array(columns * lines).fill(-1);       // block (column, line) → its index in `blocks`
  const scratch = new Float64Array(side * side);
  let sumL = 0; let sumA = 0; let sumB = 0;
  for (let by = 0; by < height; by += side) {
    for (let bx = 0; bx < width; bx += side) {
      const yEnd = Math.min(height, by + side);
      const xEnd = Math.min(width, bx + side);
      const full = (yEnd - by) * (xEnd - bx);
      let n = 0;
      let discN = 0;
      let r = 0; let g = 0; let b = 0;
      for (let y = by; y < yEnd; y += 1) {
        const row = y * width;
        for (let x = bx; x < xEnd; x += 1) {
          const m = mask[row + x];
          if (!member[m & 15]) continue;
          if (m & BIT.disc) { discN += 1; continue; }
          scratch[n] = Y[row + x];
          n += 1;
          const j = (row + x) * 3;
          r += LINEAR[rgb[j]]; g += LINEAR[rgb[j + 1]]; b += LINEAR[rgb[j + 2]];
        }
      }
      if (n * 2 >= full && n > 0) {
        const sorted = scratch.subarray(0, n).slice().sort();
        const median = percentile(sorted, 50);
        medians.push(median);
        const lab = oklabOfLinear(r / n, g / n, b / n);
        chromas.push(Math.hypot(lab.a, lab.b));
        sumL += lab.L; sumA += lab.a; sumB += lab.b;
        grid[(by / side) * columns + bx / side] = blocks.length;
        blocks.push({ x: bx / dpr, y: by / dpr, median });
      } else if (discN * 2 >= full) {
        // A block the disc owns: what it would have read with the disc left in.
        let k = 0;
        for (let y = by; y < yEnd; y += 1) {
          const row = y * width;
          for (let x = bx; x < xEnd; x += 1) if (member[mask[row + x] & 15]) { scratch[k] = Y[row + x]; k += 1; }
        }
        discMedians.push(percentile(scratch.subarray(0, k).slice().sort(), 50));
      }
    }
  }
  if (!medians.length) return null;
  const sorted = Float64Array.from(medians).sort();
  const sortedC = Float64Array.from(chromas).sort();
  const n = sorted.length;
  const meanA = sumA / n;
  const meanB = sumB / n;
  let over = 0;
  if (cardL != null) for (const v of sorted) if (v > cardL) over += 1;

  // "About areas, not star points": a star with its halo can lift one 8 pt block, or two when
  // it sits on their shared edge. An AREA is three or more touching blocks (192 pt² and up).
  // areaLevel is the lightest level three touching blocks reach together: add the blocks
  // lightest first, joining neighbours; when a group first has three, that block's median is it.
  const order = blocks.map((_, i) => i).sort((p, q) => blocks[q].median - blocks[p].median || p - q);
  const parent = new Int32Array(blocks.length).fill(-1);       // -1: not yet added
  const size = new Int32Array(blocks.length);
  const root = (i) => { while (parent[i] !== i) { parent[i] = parent[parent[i]]; i = parent[i]; } return i; };
  const neighbours = (i, visit) => {
    const c = Math.round(blocks[i].x * dpr / side);
    const l = Math.round(blocks[i].y * dpr / side);
    for (let dl = -1; dl <= 1; dl += 1) {
      for (let dc = -1; dc <= 1; dc += 1) {
        if (!dl && !dc) continue;
        const cc = c + dc;
        const ll = l + dl;
        if (cc < 0 || ll < 0 || cc >= columns || ll >= lines) continue;
        const j = grid[ll * columns + cc];
        if (j >= 0) visit(j);
      }
    }
  };
  const AREA_BLOCKS = 3;
  let areaLevel = null;
  let groupsOver = 0;
  let largestOver = 0;
  let loneOver = 0;
  let pending = cardL != null;
  const closeOver = () => {            // every block lighter than a card has been added: count their groups
    const seen = new Map();
    for (let i = 0; i < blocks.length; i += 1) {
      if (parent[i] < 0) continue;
      const r = root(i);
      seen.set(r, size[r]);
      blocks[i].inArea = size[r] >= AREA_BLOCKS;      // decided now, before any block no lighter than a card joins
    }
    for (const count of seen.values()) {
      groupsOver += 1;
      if (count > largestOver) largestOver = count;
      if (count < AREA_BLOCKS) loneOver += count;
    }
    pending = false;
  };
  for (const i of order) {
    if (pending && blocks[i].median <= cardL) closeOver();
    if (!pending && areaLevel != null) break;
    parent[i] = i;
    size[i] = 1;
    neighbours(i, (j) => {
      if (parent[j] < 0) return;
      const a = root(i);
      const b = root(j);
      if (a === b) return;
      parent[b] = a;
      size[a] += size[b];
    });
    if (areaLevel == null && size[root(i)] >= AREA_BLOCKS) areaLevel = blocks[i].median;
  }
  if (pending) closeOver();
  const stats = {
    blocks: n,
    min: sorted[0], p5: percentile(sorted, 5), median: percentile(sorted, 50), p95: percentile(sorted, 95), p99: percentile(sorted, 99), max: sorted[n - 1],
    mean: sorted.reduce((a, v) => a + v, 0) / n,
    areaLevel, areaBlocks: AREA_BLOCKS,
    overCard: cardL == null ? null : over,
    overCardShare: cardL == null ? null : over / n,
    overCardGroups: cardL == null ? null : groupsOver,
    overCardLargestGroup: cardL == null ? null : largestOver,
    overCardInPoints: cardL == null ? null : loneOver,
    discBlocks: discMedians.length,
    maxWithDisc: discMedians.length ? Math.max(sorted[n - 1], ...discMedians) : sorted[n - 1],
    chroma: {
      mean: chromas.reduce((a, v) => a + v, 0) / n, median: percentile(sortedC, 50), p95: percentile(sortedC, 95), max: sortedC[n - 1],
      ofMeanColour: Math.hypot(meanA, meanB), hueDeg: (Math.atan2(meanB, meanA) * 180 / Math.PI + 360) % 360, meanOkL: sumL / n,
    },
  };
  return { stats, blocks };
}

/** Sharp points in the anchor window (METHOD.points). APPROXIMATE. */
function countPoints(picture, geometry, discs) {
  const { width, height, dpr, Y } = picture;
  const phone = geometry.state.phone ?? { x: 0, width: geometry.state.width };
  const wx0 = Math.max(0, Math.round(phone.x * dpr));
  const wx1 = Math.min(width, Math.round((phone.x + phone.width) * dpr));
  const G = new Float32Array(width * height);
  for (let i = 0; i < G.length; i += 1) G[i] = 255 * encode(Y[i]);
  const integral = new Float64Array((width + 1) * (height + 1));
  for (let y = 0; y < height; y += 1) {
    let run = 0;
    for (let x = 0; x < width; x += 1) {
      run += G[y * width + x];
      integral[(y + 1) * (width + 1) + x + 1] = integral[y * (width + 1) + x + 1] + run;
    }
  }
  const reach = Math.max(2, Math.round(3.5 * dpr));          // a 7 pt square
  const D = new Float32Array(width * height);
  const boxSum = (table, xa, ya, xb, yb) => table[yb * (width + 1) + xb] - table[ya * (width + 1) + xb] - table[yb * (width + 1) + xa] + table[ya * (width + 1) + xa];
  const difference = (sums, counts) => {
    for (let y = 0; y < height; y += 1) {
      const ya = Math.max(0, y - reach);
      const yb = Math.min(height, y + reach + 1);
      for (let x = wx0; x < wx1; x += 1) {
        const xa = Math.max(0, x - reach);
        const xb = Math.min(width, x + reach + 1);
        const n = counts ? boxSum(counts, xa, ya, xb, yb) : (yb - ya) * (xb - xa);
        D[y * width + x] = n > 0 ? G[y * width + x] - boxSum(sums, xa, ya, xb, yb) / n : 0;
      }
    }
  };
  // Robust noise: 1.4826 × the median absolute difference, over every third pixel of the window.
  const noise = () => {
    const sample = [];
    for (let y = 0; y < height; y += 3) for (let x = wx0; x < wx1; x += 3) sample.push(Math.abs(D[y * width + x]));
    sample.sort((a, b) => a - b);
    return 1.4826 * (sample.length ? sample[Math.floor(sample.length / 2)] : 0);
  };
  // First pass: against the plain mean of the square. A bright point lifts the mean around
  // itself and would read as a ring of dark ones, so the second pass takes the mean of the
  // square WITHOUT the first pass's candidates.
  difference(integral, null);
  let sigma = noise();
  let threshold = Math.max(6, 6 * sigma);
  const sums = new Float64Array((width + 1) * (height + 1));
  const counts = new Float64Array((width + 1) * (height + 1));
  for (let y = 0; y < height; y += 1) {
    let runSum = 0;
    let runCount = 0;
    for (let x = 0; x < width; x += 1) {
      const i = y * width + x;
      const plain = x < wx0 || x >= wx1 || Math.abs(D[i]) < threshold;
      if (plain) { runSum += G[i]; runCount += 1; }
      sums[(y + 1) * (width + 1) + x + 1] = sums[y * (width + 1) + x + 1] + runSum;
      counts[(y + 1) * (width + 1) + x + 1] = counts[y * (width + 1) + x + 1] + runCount;
    }
  }
  difference(sums, counts);
  sigma = noise();
  threshold = Math.max(6, 6 * sigma);
  // Grain is not the same everywhere (it grows with the light), so the bar is local too:
  // 6 × the noise of the 15 pt square around the pixel, from its mean absolute difference
  // (1.2533 × mean|D| is σ for Gaussian noise, and a lone point barely moves it).
  const wide = Math.max(4, Math.round(7.5 * dpr));
  const absolute = new Float64Array((width + 1) * (height + 1));
  for (let y = 0; y < height; y += 1) {
    let run = 0;
    for (let x = 0; x < width; x += 1) {
      run += Math.abs(D[y * width + x]);
      absolute[(y + 1) * (width + 1) + x + 1] = absolute[y * (width + 1) + x + 1] + run;
    }
  }
  const bar = new Float32Array(width * height);
  for (let y = 0; y < height; y += 1) {
    const ya = Math.max(0, y - wide);
    const yb = Math.min(height, y + wide + 1);
    for (let x = wx0; x < wx1; x += 1) {
      const xa = Math.max(wx0, x - wide);
      const xb = Math.min(wx1, x + wide + 1);
      bar[y * width + x] = Math.max(threshold, 6 * 1.2533 * boxSum(absolute, xa, ya, xb, yb) / ((yb - ya) * (xb - xa)));
    }
  }
  const nearDisc = (x, y) => discs.some((disc) => Math.hypot(x / dpr - disc.x, y / dpr - disc.y) <= disc.exclusion + 2);
  const limit = 12 * dpr;

  const scan = (sign) => {
    const seen = new Uint8Array(width * height);
    const points = [];
    let rejectedLarge = 0;
    let rejectedDisc = 0;
    for (let y = 0; y < height; y += 1) {
      for (let x = wx0; x < wx1; x += 1) {
        const start = y * width + x;
        if (seen[start] || sign * D[start] < bar[start]) continue;
        const stack = [start];
        seen[start] = 1;
        let minX = x; let maxX = x; let minY = y; let maxY = y;
        let count = 0;
        let best = 0;
        let sx = 0; let sy = 0; let sw = 0;
        while (stack.length) {
          const i = stack.pop();
          const px = i % width;
          const py = (i - px) / width;
          count += 1;
          const d = sign * D[i];
          if (d > best) best = d;
          sx += d * px; sy += d * py; sw += d;
          if (px < minX) minX = px;
          if (px > maxX) maxX = px;
          if (py < minY) minY = py;
          if (py > maxY) maxY = py;
          for (let dy = -1; dy <= 1; dy += 1) {
            for (let dx = -1; dx <= 1; dx += 1) {
              const nx = px + dx;
              const ny = py + dy;
              if (nx < wx0 || ny < 0 || nx >= wx1 || ny >= height) continue;
              const j = ny * width + nx;
              if (!seen[j] && sign * D[j] >= bar[j]) { seen[j] = 1; stack.push(j); }
            }
          }
        }
        if (maxX - minX + 1 > limit || maxY - minY + 1 > limit) { rejectedLarge += 1; continue; }
        const cx = sx / sw;
        const cy = sy / sw;
        if (nearDisc(cx, cy)) { rejectedDisc += 1; continue; }
        points.push({ x: (cx + 0.5) / dpr, y: (cy + 0.5) / dpr, pixels: count, levels: best });
      }
    }
    return { points, rejectedLarge, rejectedDisc };
  };
  // A star stands alone. Fragments within 4 pt are one point (a glint's arms); a run of them
  // more than 12 pt long is an edge, not a star (the chips of a brushed ridge line); a point
  // with three or more others within 8 pt is part of a texture; and one on a line with four
  // or more others within 30 pt is part of a drawn edge.
  const settle = (found) => {
    const points = found.points;
    const parent = points.map((_, i) => i);
    const root = (i) => { while (parent[i] !== i) { parent[i] = parent[parent[i]]; i = parent[i]; } return i; };
    const grid = new Map();
    const cellOf = (v) => Math.floor(v / 8);
    points.forEach((point, i) => {
      const key = `${cellOf(point.x)},${cellOf(point.y)}`;
      if (!grid.has(key)) grid.set(key, []);
      grid.get(key).push(i);
    });
    const near = (point, radius, visit) => {
      for (let gy = cellOf(point.y - radius); gy <= cellOf(point.y + radius); gy += 1) {
        for (let gx = cellOf(point.x - radius); gx <= cellOf(point.x + radius); gx += 1) {
          for (const j of grid.get(`${gx},${gy}`) ?? []) if (Math.hypot(points[j].x - point.x, points[j].y - point.y) <= radius) visit(j);
        }
      }
    };
    points.forEach((point, i) => near(point, 4, (j) => { const a = root(i); const b = root(j); if (a !== b) parent[Math.max(a, b)] = Math.min(a, b); }));
    const groups = new Map();
    points.forEach((point, i) => {
      const r = root(i);
      const g = groups.get(r) ?? { minX: Infinity, minY: Infinity, maxX: -Infinity, maxY: -Infinity, sx: 0, sy: 0, sw: 0, pixels: 0, levels: 0, parts: 0 };
      g.minX = Math.min(g.minX, point.x); g.maxX = Math.max(g.maxX, point.x);
      g.minY = Math.min(g.minY, point.y); g.maxY = Math.max(g.maxY, point.y);
      g.sx += point.x * point.pixels; g.sy += point.y * point.pixels; g.sw += point.pixels;
      g.pixels += point.pixels; g.levels = Math.max(g.levels, point.levels); g.parts += 1;
      groups.set(r, g);
    });
    let rejectedRuns = 0;
    const merged = [];
    for (const g of groups.values()) {
      if (g.maxX - g.minX > 12 || g.maxY - g.minY > 12) { rejectedRuns += 1; continue; }
      merged.push({ x: g.sx / g.sw, y: g.sy / g.sw, pixels: g.pixels, levels: g.levels, parts: g.parts });
    }
    let rejectedCrowded = 0;
    let rejectedLines = 0;
    const kept = merged.filter((point) => {
      const around = merged.filter((other) => other !== point && Math.hypot(other.x - point.x, other.y - point.y) <= 30);
      let close = 0;
      for (const other of around) if (Math.hypot(other.x - point.x, other.y - point.y) <= 8) close += 1;
      if (close >= 3) { rejectedCrowded += 1; return false; }
      // On a line with four or more others within 30 pt (1.5 pt to either side of it): a drawn edge.
      for (const through of around) {
        const dx = through.x - point.x;
        const dy = through.y - point.y;
        const length = Math.hypot(dx, dy);
        if (length < 1e-6) continue;
        let onLine = 0;
        for (const other of around) if (Math.abs((other.x - point.x) * dy - (other.y - point.y) * dx) / length <= 1.5) onLine += 1;
        if (onLine >= 4) { rejectedLines += 1; return false; }
      }
      return true;
    });
    return { points: kept, fragments: points.length, rejectedLarge: found.rejectedLarge, rejectedDisc: found.rejectedDisc, rejectedRuns, rejectedCrowded, rejectedLines };
  };
  const bright = settle(scan(1));
  const dark = settle(scan(-1));
  const tally = (r) => ({ fragments: r.fragments, largerThan12pt: r.rejectedLarge, atTheDisc: r.rejectedDisc, runs: r.rejectedRuns, crowded: r.rejectedCrowded, onALine: r.rejectedLines });
  return {
    approximate: true,
    bright: bright.points.length, dark: dark.points.length,
    thresholdLevels: threshold, noiseSigmaLevels: sigma,
    rejected: { bright: tally(bright), dark: tally(dark) },
    window: { x: phone.x, width: phone.width },
    brightPoints: bright.points, darkPoints: dark.points,
  };
}

/**
 * His stars, counted by what they are: the pixels that differ between this frame and the
 * same frame at age 0 (when he has no stars yet). Pixels 2 levels or more apart form
 * 8-connected blobs in the anchor window (a blob must reach 4 levels to count); inside a
 * blob, each separate core (pixels at least half as far apart as the blob's most different
 * pixel, cores within 3 pt taken as one) is a star, so two stars whose halos touch are
 * still two. Expected: ageDays — tonight's star, lit or not, is the same in both frames
 * and cancels. Still approximate.
 */
function countByAge(picture, zero, geometry) {
  const { width, height, dpr } = picture;
  const phone = geometry.state.phone ?? { x: 0, width: geometry.state.width };
  const wx0 = Math.max(0, Math.round(phone.x * dpr));
  const wx1 = Math.min(width, Math.round((phone.x + phone.width) * dpr));
  const apart = new Uint8Array(width * height);
  let pixels = 0;
  let outside = 0;
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const i = y * width + x;
      const j = i * 3;
      const d = Math.max(Math.abs(picture.rgb[j] - zero.rgb[j]), Math.abs(picture.rgb[j + 1] - zero.rgb[j + 1]), Math.abs(picture.rgb[j + 2] - zero.rgb[j + 2]));
      if (d < 2) continue;
      if (x < wx0 || x >= wx1) { outside += 1; continue; }
      apart[i] = d;
      pixels += 1;
    }
  }
  const share = pixels / ((wx1 - wx0) * height);
  if (share > 0.2) return { approximate: true, count: null, expected: geometry.state.ageDays, note: 'more than a fifth of the anchor window changes with age: not a matter of points', differingShare: share, differingOutsideWindow: outside };
  const state = new Uint8Array(width * height);        // 1: taken into a blob; 2: taken into a core
  const flood = (start, accept, mark) => {
    const members = [];
    const stack = [start];
    state[start] = mark;
    while (stack.length) {
      const i = stack.pop();
      members.push(i);
      const px = i % width;
      const py = (i - px) / width;
      for (let dy = -1; dy <= 1; dy += 1) {
        for (let dx = -1; dx <= 1; dx += 1) {
          const nx = px + dx;
          const ny = py + dy;
          if (nx < wx0 || ny < 0 || nx >= wx1 || ny >= height) continue;
          const j = ny * width + nx;
          if (accept(j)) { state[j] = mark; stack.push(j); }
        }
      }
    }
    return members;
  };
  const stars = [];
  let blobs = 0;
  let areas = 0;
  let faint = 0;
  for (let y = 0; y < height; y += 1) {
    for (let x = wx0; x < wx1; x += 1) {
      const start = y * width + x;
      if (!apart[start] || state[start]) continue;
      const blob = flood(start, (j) => apart[j] > 0 && state[j] === 0, 1);
      let minX = width; let maxX = -1; let minY = height; let maxY = -1;
      let most = 0;
      for (const i of blob) {
        const px = i % width;
        const py = (i - px) / width;
        if (px < minX) minX = px;
        if (px > maxX) maxX = px;
        if (py < minY) minY = py;
        if (py > maxY) maxY = py;
        if (apart[i] > most) most = apart[i];
      }
      if (maxX - minX + 1 > 40 * dpr || maxY - minY + 1 > 40 * dpr) { areas += 1; continue; }
      if (most < 4) { faint += 1; continue; }             // a stray pixel of a halo's fringe, or a star nobody could see
      blobs += 1;
      const bar = Math.max(2, most / 2);
      const cores = [];
      for (const i of blob) {
        if (state[i] !== 1 || apart[i] < bar) continue;
        const core = flood(i, (j) => state[j] === 1 && apart[j] >= bar, 2);
        let sx = 0; let sy = 0;
        for (const k of core) { const px = k % width; sx += px; sy += (k - px) / width; }
        cores.push({ x: (sx / core.length + 0.5) / dpr, y: (sy / core.length + 0.5) / dpr, pixels: core.length });
      }
      // Cores within 3 pt of each other are one star (the arms of a glint).
      const kept = [];
      for (const core of cores.sort((p, q) => q.pixels - p.pixels)) {
        if (!kept.some((other) => Math.hypot(other.x - core.x, other.y - core.y) <= 3)) kept.push(core);
      }
      stars.push(...kept);
    }
  }
  return { approximate: true, count: stars.length, expected: geometry.state.ageDays, blobs, fainterThan4Levels: faint, largerThan40pt: areas, differingShare: share, differingOutsideWindow: outside, places: stars };
}

/** The anchor window of a picture at one colour per point (the mean of each point's pixels, sRGB bytes). */
function anchorThumbnail(picture, geometry) {
  const { dpr } = picture;
  const phone = geometry.state.phone ?? { x: 0, width: geometry.state.width };
  const step = Math.max(1, Math.round(dpr));
  const w = Math.floor(phone.width);
  const h = Math.floor(picture.height / step);
  const x0 = Math.round(phone.x * dpr);
  const data = new Float32Array(w * h * 3);
  for (let y = 0; y < h; y += 1) {
    for (let x = 0; x < w; x += 1) {
      let r = 0; let g = 0; let b = 0;
      for (let yy = 0; yy < step; yy += 1) {
        for (let xx = 0; xx < step; xx += 1) {
          const j = ((y * step + yy) * picture.width + x0 + x * step + xx) * 3;
          r += picture.rgb[j]; g += picture.rgb[j + 1]; b += picture.rgb[j + 2];
        }
      }
      const o = (y * w + x) * 3;
      data[o] = r / (step * step); data[o + 1] = g / (step * step); data[o + 2] = b / (step * step);
    }
  }
  return { width: w, height: h, data };
}

/**
 * "One world, two windows": the cover's sky against the spread's phone page, point for
 * point. `shift` moves the spread's picture down by that many points against the cover's
 * (the spread is 9 pt shorter). → the mean of the largest channel difference (8-bit
 * levels) and the share of points more than 8 levels apart, over the rows both have.
 */
function compareAnchors(cover, spread, shift) {
  const w = Math.min(cover.width, spread.width);
  const rows = Math.min(cover.height - Math.max(0, shift), spread.height - Math.max(0, -shift));
  let sum = 0;
  let far = 0;
  let worst = 0;
  for (let y = 0; y < rows; y += 1) {
    const yc = y + Math.max(0, shift);
    const ys = y + Math.max(0, -shift);
    for (let x = 0; x < w; x += 1) {
      const a = (yc * cover.width + x) * 3;
      const b = (ys * spread.width + x) * 3;
      const d = Math.max(Math.abs(cover.data[a] - spread.data[b]), Math.abs(cover.data[a + 1] - spread.data[b + 1]), Math.abs(cover.data[a + 2] - spread.data[b + 2]));
      sum += d;
      if (d > 8) far += 1;
      if (d > worst) worst = d;
    }
  }
  const n = rows * w;
  return { shiftPt: shift, meanLevels: sum / n, shareOver8Levels: far / n, maxLevels: worst };
}

/** Everything measured from one picture of the sky. */
function measurePicture(picture, geometry, texts, tokens) {
  const out = { texts: {}, ground: {}, chroma: {}, discs: [], points: null };
  for (const text of texts) {
    if (text.opacity < 0.02) { out.texts[text.role] = { skipped: 'not drawn (opacity 0)' }; continue; }
    const result = behindText(picture, text.ink, text.colourParsed, text.opacity);
    if (result) out.texts[text.role] = result;
  }
  const found = findDiscs(picture, geometry);
  out.discs = found.discs;
  out.discBackground = found.background;
  out.discExpected = found.expected;
  const { mask, foot } = regionMask(picture, geometry, found.discs);
  out.bandFoot = { phone: foot.phone, leading: foot.leading };
  const blocksOver = [];
  for (const name of ['below', 'cards', 'open', 'band']) {
    const result = blockStats(picture, mask, REGIONS[name], tokens.cardL);
    if (!result) continue;
    const { chroma, ...ground } = result.stats;
    if (name !== 'band') out.ground[name] = ground;
    out.chroma[name] = chroma;
    if (name === 'below') for (const block of result.blocks) if (block.median > tokens.cardL) blocksOver.push(block);       // .inArea: part of an area, else a point
  }
  // Where each disc is.
  for (const disc of out.discs) {
    const x = Math.min(picture.width - 1, Math.max(0, Math.round(disc.x * picture.dpr)));
    const y = Math.min(picture.height - 1, Math.max(0, Math.round(disc.y * picture.dpr)));
    const m = mask[y * picture.width + x];
    disc.where = m & BIT.occluder ? 'island' : m & BIT.opaque ? 'under an opaque card' : m & BIT.glass ? 'under a glass card' : m & BIT.below ? 'open, below the band' : 'top band';
    disc.belowBand = (m & (BIT.below | BIT.opaque | BIT.glass)) !== 0;
  }
  const night = geometry.state.sun.altitude * 180 / Math.PI < -6;
  if (night) out.points = countPoints(picture, geometry, out.discs);
  return { measured: out, blocksOver };
}

function judge(value, threshold, dir) {
  if (value == null || threshold == null) return null;
  const ok = dir === '>=' ? value >= threshold : value <= threshold;
  if (!ok) return 'FAIL';
  return Math.abs(value - threshold) <= 0.05 * Math.abs(threshold) ? 'AT-LIMIT' : 'PASS';
}

/** The checks that apply to this frame, judged on one source's measurements. */
function verdictsFor(frame, source, measured) {
  const rows = [];
  for (const check of CHECKS) {
    if (!check.schemes.includes(frame.scheme)) continue;
    if (check.kind === 'ground') {
      if (check.nightOnly && !frame.state.nightFrame) continue;
      const ground = measured.ground.below;
      if (!ground) continue;
      const threshold = frame.tokens.cardL;
      rows.push({
        check: check.id, role: null, source, statistic: 'the lightest area below the band: the level three touching 8 pt blocks reach together (medians, disc left out)',
        value: ground.areaLevel, threshold, verdict: judge(ground.areaLevel, threshold, check.dir),
        strictStatistic: 'the lightest single 8 pt block (a star with its halo counts)', strictValue: ground.max, strictVerdict: judge(ground.max, threshold, check.dir),
        withDisc: ground.maxWithDisc,
      });
      continue;
    }
    for (const role of check.roles) {
      const text = measured.texts[role];
      if (!text || text.skipped) continue;
      const lighter = text.text.lighterThanGround;
      if (check.kind === 'contrast') {
        rows.push({
          check: check.id, role, source, statistic: `contrast against ${text.worst.statistic}`,
          value: text.contrast.pct, threshold: check.threshold, verdict: judge(text.contrast.pct, check.threshold, check.dir),
          strictStatistic: `contrast against the ${lighter ? 'lightest' : 'darkest'} pixel`, strictValue: text.contrast.abs, strictVerdict: judge(text.contrast.abs, check.threshold, check.dir),
        });
      } else {
        // The luminance behind the line: the dark appearance's limits are ceilings, the light one's a floor.
        const high = check.dir === '<=';
        const value = high ? text.luminance.p99_5 : text.luminance.p0_5;
        const strict = high ? text.luminance.max : text.luminance.min;
        rows.push({
          check: check.id, role, source, statistic: high ? 'p99.5' : 'p0.5',
          value, threshold: check.threshold, verdict: judge(value, check.threshold, check.dir),
          strictStatistic: high ? 'max' : 'min', strictValue: strict, strictVerdict: judge(strict, check.threshold, check.dir),
        });
      }
    }
  }
  return rows;
}

// ─────────────────────────────────────────────────────────── one frame ──

const stamp = (time) => time.replaceAll(':', '');
const frameId = (device, scheme, time, asleep) => `${device}-${scheme}-${stamp(time)}${asleep === '0' ? '' : `-${asleep}`}`;

function frameQuery(options, device, scheme, time, chrome) {
  const search = new URLSearchParams({ ...options.query, device, scheme, time, chrome: chrome ? '1' : '0' });
  return search.toString().replace(/%3A/gi, ':').replace(/%2C/gi, ',');
}

async function openViewer(context, url, timeout, noise) {
  const page = await context.newPage();
  page.on('pageerror', (error) => noise.push(error.message));
  let gaveUp = null;
  page.on('console', (message) => {
    if (message.type() === 'error') noise.push(message.text());
    // The viewer stops waiting for a slow sky after 15 s and calls the frame drawn regardless.
    if (message.text().includes('gave up waiting')) gaveUp = message.text();
  });
  try {
    await page.goto(url, { waitUntil: 'load', timeout });
    await page.waitForFunction(() => window.__labReady === true || Boolean(window.__labError), null, { timeout });
    const error = await page.evaluate(() => window.__labError);
    if (error) throw new Error(error);
    if (gaveUp) throw new Error(`the frame may not be fully drawn (${gaveUp})`);
  } catch (error) {
    await page.close().catch(() => {});
    throw error;
  }
  return page;
}

async function overlay(page, shapes, file, box) {
  await page.evaluate((items) => {
    document.getElementById('measure-overlay')?.remove();
    const layer = document.createElement('div');
    layer.id = 'measure-overlay';
    layer.style.cssText = 'position:absolute;inset:0;z-index:99999;pointer-events:none;overflow:hidden;';
    for (const item of items) {
      const el = document.createElement('div');
      el.style.cssText = `position:absolute;box-sizing:border-box;left:${item.x}px;top:${item.y}px;width:${item.width}px;height:${item.height}px;`
        + `border:${item.weight ?? 0.5}px ${item.dash ? 'dashed' : 'solid'} ${item.colour};${item.round ? 'border-radius:50%;' : ''}${item.fill ? `background:${item.fill};` : ''}`;
      if (item.label) {
        const tag = document.createElement('span');
        tag.textContent = item.label;
        tag.style.cssText = `position:absolute;left:0;${item.labelBelow ? 'top:100%' : 'bottom:100%'};font:600 6px/7px ui-monospace,Menlo,Consolas,monospace;`
          + `white-space:nowrap;color:${item.colour};background:rgba(0,0,0,.72);padding:0 1.5px;letter-spacing:0;`;
        el.append(tag);
      }
      layer.append(el);
    }
    document.getElementById('display').append(layer);
  }, shapes);
  await page.screenshot({ path: file, clip: box, ...SHOT });
  await page.evaluate(() => document.getElementById('measure-overlay')?.remove());
}

async function measureFrame(contextFor, options, origin, job, presenceOf) {
  const noise = [];
  const { device, scheme, time } = job;
  const context = await contextFor(device);
  let pageA = null;
  let pageB = null;
  try {
    // ── chrome=1: the geometry, and the sky as drawn beneath it ──
    pageA = await openViewer(context, `${origin}/index.html?${frameQuery(options, device, scheme, time, true)}`, options.timeout, noise);
    await pageA.addStyleTag({ content: INK_STYLE });
    const geometry = await pageA.evaluate(readChrome);
    const box = await pageA.locator('#display').boundingBox();
    if (!box || box.width < 1 || box.height < 1) throw new Error('the display has no size');
    const texts = [];
    for (const text of geometry.texts) {
      const colour = parseColour(text.fill) ?? parseColour(text.colour);
      if (!colour) throw new Error(`cannot read the colour of "${text.text}" (${text.colour})`);
      const ink = await inkBox(pageA, device, text, geometry);
      texts.push({ ...text, colourParsed: colour, ink });
    }
    const hide = (on) => pageA.evaluate((flag) => {
      for (const el of document.querySelectorAll('.tou-chrome, #chrome-root')) {
        if (flag) el.setAttribute('data-measure-hidden', ''); else el.removeAttribute('data-measure-hidden');
      }
    }, on);
    await hide(true);
    const underPng = await pageA.screenshot({ clip: box, ...SHOT });
    await hide(false);

    // ── chrome=0: the sky alone ──
    pageB = await openViewer(context, `${origin}/index.html?${frameQuery(options, device, scheme, time, false)}`, options.timeout, noise);
    const bareState = await pageB.evaluate(readBare);
    const boxB = await pageB.locator('#display').boundingBox();
    const barePng = await pageB.screenshot({ clip: boxB, ...SHOT });
    if (!options.annotate) { await pageB.close(); pageB = null; }

    // ── optionally, the sky alone at age 0: what differs is his stars ──
    let zeroPng = null;
    if (options.starsByAge && geometry.state.sun.altitude * 180 / Math.PI < -6) {
      const search = new URLSearchParams(frameQuery(options, device, scheme, time, false));
      search.set('age', '0');
      const pageC = await openViewer(context, `${origin}/index.html?${search.toString().replace(/%3A/gi, ':').replace(/%2C/gi, ',')}`, options.timeout, noise);
      try {
        zeroPng = await pageC.screenshot({ clip: await pageC.locator('#display').boundingBox(), ...SHOT });
      } finally {
        await pageC.close().catch(() => {});
      }
    }

    const bare = new Picture(decodePng(barePng), options.dpr);
    const underImage = decodePng(underPng);
    if (bare.width !== Math.round(geometry.state.width * options.dpr) || bare.height !== Math.round(geometry.state.height * options.dpr)) {
      throw new Error(`the shot is ${bare.width} × ${bare.height} px, not the display at dpr ${options.dpr}`);
    }
    if (underImage.width !== bare.width || underImage.height !== bare.height) throw new Error('the two shots differ in size');
    if (Math.abs(bareState.sunAltitude - geometry.state.sun.altitude) > 1e-12) throw new Error('the two loads are not the same instant');

    // How far the sky under the chrome is from the sky alone.
    let differing = 0;
    let maxDiff = 0;
    for (let i = 0; i < bare.rgb.length; i += 3) {
      const d = Math.max(Math.abs(bare.rgb[i] - underImage.rgb[i]), Math.abs(bare.rgb[i + 1] - underImage.rgb[i + 1]), Math.abs(bare.rgb[i + 2] - underImage.rgb[i + 2]));
      if (d > maxDiff) maxDiff = d;
      if (d > 2) differing += 1;
    }
    const sameSky = differing === 0;

    const card = parseColour(geometry.tokens.card) ?? (scheme === 'light' ? { r: 255, g: 255, b: 255 } : { r: 0x1c, g: 0x1c, b: 0x1e });
    const pageColour = parseColour(geometry.tokens.bg) ?? (scheme === 'light' ? { r: 0xf2, g: 0xf2, b: 0xf7 } : { r: 0, g: 0, b: 0 });
    const tokens = {
      card: hexOf(card), cardL: luminanceOf(card.r, card.g, card.b),
      page: hexOf(pageColour), pageL: luminanceOf(pageColour.r, pageColour.g, pageColour.b),
    };

    const sunDeg = geometry.state.sun.altitude * 180 / Math.PI;
    const presence = presenceOf ? presenceOf(geometry.state) : null;
    const frame = {
      id: job.id, device, scheme, time, asleep: options.asleep,
      query: frameQuery(options, device, scheme, time, false),
      state: {
        sunAltitudeDeg: sunDeg, isNight: geometry.state.sun.isNight, nightFrame: sunDeg <= -10.5,
        presence: presence ? { presence: presence.presence, solar: presence.solar, moon: presence.moon, depth: presence.depth, stars: presence.stars } : null,
        moon: geometry.state.moon ? { altitudeDeg: geometry.state.moon.altitude * 180 / Math.PI, fraction: geometry.state.moon.fraction, x: geometry.state.moon.x } : null,
        ageDays: geometry.state.ageDays,
        // Tonight's star is lit when the lab says so (state.tonightLit); in a lab without it, while a night sleep runs.
        tonightLit: geometry.state.tonightLit ?? geometry.state.asleep === 'night',
        tonightLitFrom: geometry.state.tonightLit == null ? 'asleep' : 'state.tonightLit',
        expectedStars: geometry.state.ageDays + ((geometry.state.tonightLit ?? geometry.state.asleep === 'night') ? 1 : 0),
      },
      tokens,
      geometry: {
        texts: texts.map((text) => ({ role: text.role, page: text.page, text: text.text, colour: hexOf(text.colourParsed), font: text.font, opacity: text.opacity, lineBox: text.line, inkBox: { x: text.ink.x, y: text.ink.y, width: text.ink.width, height: text.ink.height }, inkFrom: text.ink.source })),
        cards: geometry.cards, furniture: geometry.furniture,
        phone: geometry.state.phone, fold: geometry.state.fold, strip: geometry.state.strip,
        labLayout: geometry.labLayout,
        // The largest distance between an edge of our ink box and the same edge of the lab's box (state.layout), in points.
        labLayoutLargestEdgeDifference: geometry.labLayout ? texts.reduce((worst, text) => {
          const lab = geometry.labLayout[text.role];
          if (!lab || text.ink.source !== 'ink') return worst;
          return Math.max(worst, Math.abs(lab.x - text.ink.x), Math.abs(lab.y - text.ink.y),
            Math.abs(lab.x + lab.width - text.ink.x - text.ink.width), Math.abs(lab.y + lab.height - text.ink.y - text.ink.height));
        }, 0) : null,
      },
      sources: { sameSky, differingPixels: differing, differingShare: differing / (bare.width * bare.height), maxLevelDifference: maxDiff, measured: sameSky ? ['bare'] : ['bare', 'under'] },
      measurements: {},
      verdicts: [],
    };

    const pictures = { bare };
    if (!sameSky) pictures.under = new Picture(underImage, options.dpr);
    const overBlocks = {};
    for (const [source, picture] of Object.entries(pictures)) {
      const { measured, blocksOver } = measurePicture(picture, geometry, texts, tokens);
      frame.measurements[source] = measured;
      overBlocks[source] = blocksOver;
      frame.verdicts.push(...verdictsFor(frame, source, measured));
    }
    frame.geometry.bandFoot = frame.measurements.bare.bandFoot;
    if (device === 'cover' || device === 'spread') job.anchor = anchorThumbnail(bare, geometry);
    let byAgePlaces = [];
    if (zeroPng && frame.measurements.bare.points) {
      const byAge = countByAge(bare, decodePng(zeroPng), geometry);
      byAgePlaces = byAge.places ?? [];
      delete byAge.places;
      frame.measurements.bare.points.byAge = byAge;
    }

    if (options.saveShots) {
      await fsp.writeFile(path.join(options.saveShots, `${job.id}-bare.png`), barePng);
      await fsp.writeFile(path.join(options.saveShots, `${job.id}-under.png`), underPng);
    }
    if (options.annotate) {
      const shapes = [];
      const foot = frame.geometry.bandFoot;
      const phoneX = geometry.state.phone ? geometry.state.phone.x : 0;
      if (phoneX > 0) shapes.push({ x: 0, y: foot.leading, width: phoneX, height: 0, colour: '#ff3bd4', weight: 0.5, dash: true, label: `band foot ${foot.leading}` });
      shapes.push({ x: phoneX, y: foot.phone, width: geometry.state.width - phoneX, height: 0, colour: '#ff3bd4', weight: 0.5, dash: true, label: `band foot ${foot.phone}` });
      for (const cardRect of geometry.cards) {
        if (OPAQUE_KINDS.has(cardRect.kind)) shapes.push({ ...cardRect, colour: '#ffd60a', label: cardRect.kind });
        else if (GLASS_KINDS.has(cardRect.kind)) shapes.push({ ...cardRect, colour: '#64d2ff', label: cardRect.kind });
        else shapes.push({ ...cardRect, colour: 'rgba(255,255,255,.55)', dash: true, label: cardRect.kind, labelBelow: true });
      }
      for (const item of geometry.furniture) shapes.push({ ...item, colour: '#bf5af2', round: ['gear', 'avatar', 'weekstamp'].includes(item.kind), label: ['status-icon', 'tab'].includes(item.kind) ? '' : item.kind, labelBelow: true });
      for (const text of texts) {
        shapes.push({ ...text.line, colour: 'rgba(48,209,88,.8)', dash: true });
        shapes.push({ x: text.ink.x, y: text.ink.y, width: text.ink.width, height: text.ink.height, colour: '#ff453a' });
        shapes.push({ x: text.ink.x - PAD_PT, y: text.ink.y - PAD_PT, width: text.ink.width + 2 * PAD_PT, height: text.ink.height + 2 * PAD_PT, colour: '#30d158', label: text.role });
      }
      await overlay(pageA, shapes, path.join(options.annotate, `${job.id}-chrome.png`), box);

      const sky = [];
      const source = sameSky ? 'bare' : 'under';
      const measured = frame.measurements[source];
      // The blocks lighter than a card — where that is a limit: the dark appearance at night.
      if (scheme === 'dark' && frame.state.nightFrame) {
        for (const block of overBlocks[source]) {
          sky.push(block.inArea
            ? { x: block.x, y: block.y, width: BLOCK_PT, height: BLOCK_PT, colour: 'rgba(255,69,58,.9)', fill: 'rgba(255,69,58,.25)' }
            : { x: block.x, y: block.y, width: BLOCK_PT, height: BLOCK_PT, colour: 'rgba(255,159,10,.9)', dash: true });
        }
      }
      if (phoneX > 0) sky.push({ x: 0, y: foot.leading, width: phoneX, height: 0, colour: '#ff3bd4', dash: true });
      sky.push({ x: phoneX, y: foot.phone, width: geometry.state.width - phoneX, height: 0, colour: '#ff3bd4', dash: true });
      for (const disc of measured.discs) {
        sky.push({ x: disc.x - disc.exclusion, y: disc.y - disc.exclusion, width: 2 * disc.exclusion, height: 2 * disc.exclusion, colour: '#ffd60a', round: true, dash: !disc.leftOut, label: `${disc.body}${disc.leftOut ? ' disc' : ' blob (kept in the ground)'}, peak ${disc.peak.toFixed(3)}` });
      }
      if (measured.points) {
        for (const point of measured.points.brightPoints) sky.push({ x: point.x - 3, y: point.y - 3, width: 6, height: 6, colour: '#30d158', round: true });
        for (const point of measured.points.darkPoints) sky.push({ x: point.x - 3, y: point.y - 3, width: 6, height: 6, colour: '#64d2ff', round: true });
        for (const point of byAgePlaces) sky.push({ x: point.x - 4.5, y: point.y - 4.5, width: 9, height: 9, colour: '#ff9f0a' });
      }
      for (const text of texts) sky.push({ x: text.ink.x - PAD_PT, y: text.ink.y - PAD_PT, width: text.ink.width + 2 * PAD_PT, height: text.ink.height + 2 * PAD_PT, colour: '#30d158' });
      if (sameSky) {
        await overlay(pageB, sky, path.join(options.annotate, `${job.id}-sky.png`), boxB);
      } else {
        await hide(true);
        await overlay(pageA, sky, path.join(options.annotate, `${job.id}-sky.png`), box);
      }
    }
    // The points' places are for the overlay; the JSON keeps the counts.
    for (const measured of Object.values(frame.measurements)) {
      if (measured.points) { delete measured.points.brightPoints; delete measured.points.darkPoints; }
    }
    frame.console = [...new Set(noise)];
    return frame;
  } finally {
    await pageA?.close().catch(() => {});
    await pageB?.close().catch(() => {});
  }
}

// ──────────────────────────────────────────────────────────────── output ──

const WORSE = { PASS: 0, 'AT-LIMIT': 1, FAIL: 2 };
const f3 = (v) => (v == null ? '—' : v.toFixed(3));
const f4 = (v) => (v == null ? '—' : v.toFixed(4));
const ratio = (v) => (v == null ? '—' : v >= 100 ? v.toFixed(0) : v.toFixed(2));
const padEnd = (text, n) => String(text).padEnd(n);
const padStart = (text, n) => String(text).padStart(n);

function table(rows, aligns) {
  const widths = rows[0].map((_, c) => Math.max(...rows.map((row) => String(row[c] ?? '').length)));
  return rows.map((row) => row.map((cell, c) => (aligns[c] === 'r' ? padStart(cell ?? '', widths[c]) : padEnd(cell ?? '', widths[c]))).join('  ').trimEnd()).join('\n');
}

function frameLines(frame) {
  const lines = [];
  for (const source of frame.sources.measured) {
    const m = frame.measurements[source];
    const text = (role) => {
      const t = m.texts[role];
      return !t || t.skipped ? '—' : `${ratio(t.contrast.pct)}/${ratio(t.contrast.abs)}`;
    };
    const behind = (role) => {
      const t = m.texts[role];
      return !t || t.skipped ? '—' : f3(t.worst.pct);
    };
    const below = m.ground.below;
    const cards = m.ground.cards;
    const open = m.ground.open;
    const disc = m.discs.length
      ? m.discs.map((d) => `${d.body}${d.leftOut ? '' : '(kept)'} ${f3(d.peak)}@${Math.round(d.x)},${Math.round(d.y)}${d.belowBand ? '' : '(band)'}`).join(' + ')
      : '—';
    const verdicts = frame.verdicts.filter((row) => row.source === source);
    const worst = verdicts.reduce((a, row) => (WORSE[row.verdict] > WORSE[a] ? row.verdict : a), 'PASS');
    const flagged = verdicts.filter((row) => row.verdict !== 'PASS').map((row) => `${row.check}${row.role ? `·${row.role}` : ''}=${row.verdict}`);
    const pres = frame.state.presence ? frame.state.presence.presence.toFixed(2) : '—';
    lines.push([
      frame.device, frame.scheme, frame.time, frame.sources.sameSky ? 'bare=under' : source,
      frame.state.sunAltitudeDeg.toFixed(1), pres,
      text('name'), behind('name'), text('age'), behind('age'), text('title'), text('subtitle'),
      below ? f4(below.areaLevel) : '—', below ? f4(below.max) : '—', below ? f4(below.p99) : '—', below ? f4(below.median) : '—', below ? f4(below.min) : '—',
      cards ? f4(cards.median) : '—', open ? f4(open.median) : '—',
      frame.scheme === 'dark' && below ? `${(100 * below.overCardShare).toFixed(1)}%` : '',
      disc,
      m.chroma.cards ? f3(m.chroma.cards.mean) : '—', m.chroma.open ? f3(m.chroma.open.mean) : '—', m.chroma.band ? f3(m.chroma.band.mean) : '—',
      m.points ? `${m.points.bright}${frame.scheme === 'light' ? `/${m.points.dark}d` : ''}${m.points.byAge ? ` [${m.points.byAge.count ?? 'n/a'} by age]` : ''}` : '',
      verdicts.length ? worst : '—', flagged.join(' '),
    ]);
  }
  return lines;
}

const FRAME_HEAD = ['device', 'scheme', 'time', 'source', 'sun°', 'pres',
  'name c', 'name L', 'age c', 'age L', 'title c', 'sub c',
  'below area', 'max', 'p99', 'median', 'min', 'cards med', 'open med', '>card', 'disc (peak L @ x,y pt)',
  'C cards', 'C open', 'C band', 'points~', 'verdict', 'flagged'];
const FRAME_ALIGN = ['l', 'l', 'l', 'l', 'r', 'r', 'r', 'r', 'r', 'r', 'r', 'r', 'r', 'r', 'r', 'r', 'r', 'r', 'r', 'r', 'l', 'r', 'r', 'r', 'r', 'l', 'l'];

/** One row per check × scheme × role: the worst frame, and how many of each verdict. */
function summarize(frames) {
  const groups = new Map();
  for (const frame of frames) {
    for (const row of frame.verdicts) {
      const check = CHECKS.find((c) => c.id === row.check);
      const key = `${row.check}|${frame.scheme}|${row.role ?? ''}`;
      const group = groups.get(key) ?? { check: row.check, label: check.label, dir: check.dir, scheme: frame.scheme, role: row.role, threshold: row.threshold, n: 0, PASS: 0, 'AT-LIMIT': 0, FAIL: 0, strictFAIL: 0, worst: null, strictWorst: null };
      group.n += 1;
      group[row.verdict] += 1;
      if (row.strictVerdict === 'FAIL') group.strictFAIL += 1;
      const worse = (a, b) => (check.dir === '>=' ? a < b : a > b);
      if (!group.worst || worse(row.value, group.worst.value)) group.worst = { value: row.value, frame: frame.id, source: row.source, verdict: row.verdict, presence: frame.state.presence?.presence ?? null };
      if (!group.strictWorst || worse(row.strictValue, group.strictWorst.value)) group.strictWorst = { value: row.strictValue, frame: frame.id, source: row.source, verdict: row.strictVerdict };
      groups.set(key, group);
    }
  }
  const order = (g) => `${String(CHECKS.findIndex((c) => c.id === g.check)).padStart(2, '0')}|${g.scheme === 'light' ? 0 : 1}|${['name', 'title', 'age', 'subtitle', null].indexOf(g.role)}`;
  return [...groups.values()].sort((a, b) => order(a).localeCompare(order(b)));
}

/** The numbers the brief gives no number for: reported, not judged. */
function unjudged(frames, anchors = []) {
  const out = [];
  const pick = (list, value, lowest) => list.reduce((best, item) => {
    const v = value(item);
    if (v == null) return best;
    return !best || (lowest ? v < best.v : v > best.v) ? { v, item } : best;
  }, null);
  const rows = frames.flatMap((frame) => frame.sources.measured.map((source) => ({ frame, source, m: frame.measurements[source] })));
  const tag = (r) => `${r.item.frame.id}${r.item.frame.sources.sameSky ? '' : ` (${r.item.source})`}`;
  const light = rows.filter((r) => r.frame.scheme === 'light' && r.m.ground.below);
  const dark = rows.filter((r) => r.frame.scheme === 'dark' && r.m.ground.below);
  if (light.length) {
    const pageL = light[0].frame.tokens.pageL;
    for (const [region, name] of [['below', 'all below the band'], ['open', 'in the open'], ['cards', 'under the cards']]) {
      const some = light.filter((r) => r.m.ground[region]);
      if (!some.length) continue;
      const darkest = pick(some, (r) => r.m.ground[region].min, true);
      const p5 = pick(some, (r) => r.m.ground[region].p5, true);
      const medLo = pick(some, (r) => r.m.ground[region].median, true);
      const medHi = pick(some, (r) => r.m.ground[region].median, false);
      const top = pick(some, (r) => r.m.ground[region].max, false);
      out.push({ id: `light-ground-${region}`, text: `light, ground ${name} (page ${f3(pageL)}, card 1.000): darkest block ${f3(darkest.v)} at ${tag(darkest)}; lowest p5 ${f3(p5.v)} at ${tag(p5)}; median ${f3(medLo.v)} (${tag(medLo)}) … ${f3(medHi.v)} (${tag(medHi)}); lightest block ${f3(top.v)} at ${tag(top)}`, values: { darkest: darkest.v, lowestP5: p5.v, medianLow: medLo.v, medianHigh: medHi.v, lightest: top.v } });
    }
  }
  if (dark.length) {
    const day = dark.filter((r) => !r.frame.state.nightFrame);
    if (day.length) {
      const top = pick(day, (r) => r.m.ground.below.max, false);
      const p99 = pick(day, (r) => r.m.ground.below.p99, false);
      const med = pick(day, (r) => r.m.ground.below.median, false);
      out.push({ id: 'dark-day-ground', text: `dark, day and bloom (sun above −10.5°), ground below the band (card ${f4(day[0].frame.tokens.cardL)}): lightest block ${f4(top.v)} at ${tag(top)}; highest p99 ${f4(p99.v)} at ${tag(p99)}; highest median ${f4(med.v)} at ${tag(med)}`, values: { lightest: top.v, highestP99: p99.v, highestMedian: med.v } });
    }
    const night = dark.filter((r) => r.frame.state.nightFrame);
    if (night.length) {
      const share = pick(night, (r) => r.m.ground.below.overCardShare, false);
      const p99 = pick(night, (r) => r.m.ground.below.p99, false);
      const med = pick(night, (r) => r.m.ground.below.median, false);
      const group = pick(night, (r) => r.m.ground.below.overCardLargestGroup, false);
      const lone = pick(night, (r) => r.m.ground.below.overCardInPoints, false);
      const withDisc = pick(night, (r) => r.m.ground.below.maxWithDisc, false);
      out.push({ id: 'dark-night-ground-detail', text: `dark night, ground below the band: highest p99 ${f4(p99.v)} at ${tag(p99)}; highest median ${f4(med.v)} at ${tag(med)}; largest share of blocks over a card ${(100 * share.v).toFixed(2)} % at ${tag(share)}; `
        + `largest touching group of blocks over a card ${group.v} blocks (${group.v * BLOCK_PT * BLOCK_PT} pt²) at ${tag(group)}; most blocks over a card that are points, not areas (groups of 1–2) ${lone.v} at ${tag(lone)}; with the disc's own blocks left in the lightest block is ${f4(withDisc.v)} at ${tag(withDisc)}`,
        values: { highestP99: p99.v, highestMedian: med.v, largestShareOverCard: share.v, largestGroupBlocks: group.v, mostPointBlocks: lone.v, lightestWithDisc: withDisc.v } });
    }
  }
  for (const scheme of ['light', 'dark']) {
    const some = rows.filter((r) => r.frame.scheme === scheme && r.m.discs.some((d) => d.belowBand && d.leftOut));
    if (!some.length) continue;
    const peak = pick(some, (r) => Math.max(...r.m.discs.filter((d) => d.belowBand && d.leftOut).map((d) => d.peak)), false);
    const halo = pick(some.filter((r) => r.frame.state.nightFrame), (r) => Math.max(...r.m.discs.filter((d) => d.belowBand && d.leftOut).map((d) => d.halo[1].p90 ?? 0)), false);
    out.push({ id: `${scheme}-disc`, text: `${scheme}, sun/moon disc below the band (left out of the ground above): in ${some.length} of ${rows.filter((r) => r.frame.scheme === scheme).length} measurements; brightest ${f3(peak.v)} at ${tag(peak)}`
      + (halo ? `; at night, the glow 8–20 pt outside the disc (90th percentile of 2 pt cells) is at most ${f4(halo.v)}, at ${tag(halo)}` : ''), values: { brightest: peak.v, nightHalo8to20: halo ? halo.v : null } });
  }
  for (const scheme of ['light', 'dark']) {
    const some = rows.filter((r) => r.frame.scheme === scheme && r.m.chroma.cards && r.frame.state.presence);
    if (!some.length) continue;
    const mean = (list, region) => (list.length ? list.reduce((a, r) => a + (r.m.chroma[region]?.mean ?? 0), 0) / list.length : null);
    const hush = some.filter((r) => r.frame.state.presence.presence <= 0.05);
    const bloom = some.filter((r) => r.frame.state.presence.presence >= 0.95);
    const top = pick(some, (r) => r.m.chroma.cards.mean, false);
    out.push({ id: `${scheme}-chroma`, text: `${scheme}, mean OKLab chroma — hush (presence ≤ 0.05, ${hush.length} frames): cards ${f3(mean(hush, 'cards'))}, open ${f3(mean(hush, 'open'))}, band ${f3(mean(hush, 'band'))}; bloom (presence ≥ 0.95, ${bloom.length} frames): cards ${f3(mean(bloom, 'cards'))}, open ${f3(mean(bloom, 'open'))}, band ${f3(mean(bloom, 'band'))}; highest under the cards ${f3(top.v)} at ${tag(top)}`,
      values: { hush: { cards: mean(hush, 'cards'), open: mean(hush, 'open'), band: mean(hush, 'band') }, bloom: { cards: mean(bloom, 'cards'), open: mean(bloom, 'open'), band: mean(bloom, 'band') }, highestCards: top.v } });
  }
  const nights = rows.filter((r) => r.m.points && r.frame.state.nightFrame && r.source === 'bare');
  for (const scheme of ['dark', 'light']) {
    const some = nights.filter((r) => r.frame.scheme === scheme);
    if (!some.length) continue;
    const nightsSoFar = some[0].frame.state.ageDays;
    const lit = some.filter((r) => r.frame.state.expectedStars > r.frame.state.ageDays).length;
    const span = (values) => (Math.min(...values) === Math.max(...values) ? `${values[0]}` : `${Math.min(...values)}–${Math.max(...values)}`);
    const counts = [...new Set(some.map((r) => r.frame.device))].map((device) => {
      const mine = some.filter((r) => r.frame.device === device);
      const byAge = mine.map((r) => r.m.points.byAge?.count).filter((v) => v != null);
      return `${device} ${span(mine.map((r) => r.m.points.bright))}${scheme === 'light' ? ` bright / ${span(mine.map((r) => r.m.points.dark))} dark` : ''}`
        + `${byAge.length ? ` [by age: ${span(byAge)} of ${mine[0].frame.state.ageDays}]` : ''} over ${mine.length} frame${mine.length === 1 ? '' : 's'}`;
    });
    out.push({ id: `${scheme}-points`, text: `${scheme}, sharp points in the anchor window at night — APPROXIMATE (expected ${nightsSoFar}, one per night of his life so far, and one more where tonight's is lit: ${lit} of these ${some.length} frames by ${some[0].frame.state.tonightLitFrom === 'state.tonightLit' ? 'state.tonightLit' : 'asleep=night'}): ${counts.join('; ')}`,
      values: { nightsSoFar, framesWithTonightLit: lit, counts: some.map((r) => ({ frame: r.frame.id, expected: r.frame.state.expectedStars, bright: r.m.points.bright, dark: r.m.points.dark, byAge: r.m.points.byAge?.count ?? null })) } });
  }
  const clocks = rows.filter((r) => r.m.texts.clock && !r.m.texts.clock.skipped);
  if (clocks.length) {
    const worst = pick(clocks, (r) => r.m.texts.clock.contrast.pct, true);
    out.push({ id: 'clock', text: `the strip's clock (no limit in the brief): lowest contrast ${ratio(worst.v)}:1 at ${tag(worst)}`, values: { lowestContrast: worst.v } });
  }
  const stamps = rows.filter((r) => r.m.texts['stamp-label'] && !r.m.texts['stamp-label'].skipped);
  if (stamps.length) {
    const label = pick(stamps, (r) => r.m.texts['stamp-label'].contrast.pct, true);
    const num = pick(stamps.filter((r) => r.m.texts['stamp-number'] && !r.m.texts['stamp-number'].skipped), (r) => r.m.texts['stamp-number'].contrast.pct, true);
    out.push({ id: 'weekstamp', text: `the spread's WEEK stamp, evening only (text on the sky the brief does not name): "WEEK" lowest ${ratio(label.v)}:1 at ${tag(label)}${num ? `; the number lowest ${ratio(num.v)}:1 at ${tag(num)}` : ''}`, values: { label: label.v, number: num ? num.v : null } });
  }
  // Sun and moon against the baseline's clock: how far the named discs are from the state's x.
  // (In the dark appearance only: on a light page a pale cloud can pass for a disc.)
  const named = rows.flatMap((r) => (r.source === 'bare' && r.frame.scheme === 'dark' ? r.m.discs.filter((d) => d.leftOut && d.offsetX != null).map((d) => ({ d, r })) : []));
  if (named.length) {
    const far = named.reduce((a, b) => (Math.abs(b.d.offsetX) > Math.abs(a.d.offsetX) ? b : a));
    const mean = named.reduce((a, b) => a + Math.abs(b.d.offsetX), 0) / named.length;
    out.push({ id: 'disc-x', text: `sun and moon against the state's x (state.sun.x or scene.body, state.moon), dark appearance: ${named.length} discs found, mean |offset| ${mean.toFixed(1)} pt, largest ${far.d.offsetX.toFixed(1)} pt (${far.d.body}, ${far.r.frame.id})`, values: { discs: named.length, meanAbsOffsetPt: mean, largestOffsetPt: far.d.offsetX } });
  }
  if (anchors.length) {
    const worst = anchors.reduce((a, b) => (b.sameY.meanLevels > a.sameY.meanLevels ? b : a));
    const identical = anchors.filter((a) => a.sameY.maxLevels <= 2).length;
    const shifts = [...new Set(anchors.map((a) => a.bestShift.shiftPt))].sort((a, b) => a - b);
    const worstBest = anchors.reduce((a, b) => (b.bestShift.meanLevels > a.bestShift.meanLevels ? b : a));
    out.push({ id: 'anchor', text: `one world, two windows — the cover's sky against the spread's phone page, point for point at the same y (${anchors.length} pairs): ${identical} identical to within 2 levels; `
      + `largest mean difference ${worst.sameY.meanLevels.toFixed(2)} levels with ${(100 * worst.sameY.shareOver8Levels).toFixed(1)} % of points more than 8 levels apart (${worst.cover}); `
      + `the vertical shift of the spread's picture that fits best: ${shifts.map((v) => `${v} pt`).join(', ')} (then at most ${worstBest.bestShift.meanLevels.toFixed(2)} levels, ${(100 * worstBest.bestShift.shareOver8Levels).toFixed(1)} % apart, ${worstBest.cover})`,
      values: { pairs: anchors.length, identicalPairs: identical, worstSameY: worst.sameY, bestShiftsPt: shifts, worstAtBestShift: worstBest.bestShift } });
  }
  const laidOut = frames.filter((frame) => frame.geometry.labLayoutLargestEdgeDifference != null);
  if (laidOut.length) {
    const worst = laidOut.reduce((a, b) => (b.geometry.labLayoutLargestEdgeDifference > a.geometry.labLayoutLargestEdgeDifference ? b : a));
    out.push({ id: 'layout', text: `the text boxes: this tool's ink boxes against the lab's own (state.layout: name, age, title, subtitle), ${laidOut.length} frames — largest difference of any edge ${worst.geometry.labLayoutLargestEdgeDifference.toFixed(2)} pt (${worst.id})`, values: { frames: laidOut.length, largestEdgeDifferencePt: worst.geometry.labLayoutLargestEdgeDifference } });
  }
  const differing = frames.filter((frame) => !frame.sources.sameSky);
  out.push({ id: 'sources', text: differing.length
    ? `the sky under the chrome differs from the sky alone in ${differing.length} of ${frames.length} frames (up to ${Math.max(...differing.map((f) => f.sources.maxLevelDifference))} levels, ${(100 * Math.max(...differing.map((f) => f.sources.differingShare))).toFixed(1)} % of the pixels): both were measured and judged`
    : `the sky under the chrome is the sky alone in all ${frames.length} frames (no pixel more than 2 levels apart)`, values: { framesDiffering: differing.length } });
  return out;
}

function printReport(options, frames, summary, notes, problems) {
  const out = [];
  out.push(`sky ${options.sky} · ${frames.length} frames · asleep ${options.asleep} · t ${options.query.t} · dpr ${options.dpr}`);
  if (!options.quiet && frames.length) {
    out.push('');
    out.push('c = WCAG contrast pct/abs (against the worst percentile / the worst pixel); L = the worst percentile behind the text;');
    out.push('below, cards, open = medians of 8 pt blocks below the top band (disc left out); area = the level three touching blocks reach together;');
    out.push('>card = share of blocks lighter than a card; C = mean OKLab chroma; points~ = approximate.');
    out.push('');
    out.push(table([FRAME_HEAD, ...frames.flatMap(frameLines)], FRAME_ALIGN));
  }
  if (summary.length) {
    out.push('');
    out.push('Checks (verdict on "worst"; "strict" is the single worst pixel behind a text, or the lightest single 8 pt block of ground):');
    out.push(table([
      ['check', 'scheme', 'text', 'limit', 'worst', 'at', 'verdict', 'PASS', 'AT-LIMIT', 'FAIL', 'strict', 'at', 'strict FAILs'],
      ...summary.map((g) => {
        const isRatio = g.check.startsWith('contrast');
        // Enough decimals that a value never prints as the limit it is on the wrong side of.
        const show = (v) => {
          let digits = isRatio ? 2 : g.check === 'dark-night-ground' ? 4 : 3;
          while (digits < 6 && v !== g.threshold && v.toFixed(digits) === g.threshold.toFixed(digits)) digits += 1;
          return isRatio ? `${v >= 100 ? v.toFixed(0) : v.toFixed(digits)}:1` : v.toFixed(digits);
        };
        return [g.label, g.scheme, g.role ?? 'ground', `${g.dir === '>=' ? '≥' : '≤'} ${isRatio ? g.threshold : g.check === 'dark-night-ground' ? f4(g.threshold) : g.threshold}`,
          show(g.worst.value), `${g.worst.frame}${g.worst.source === 'under' ? ' (under)' : ''}`, g.worst.verdict, g.PASS, g['AT-LIMIT'], g.FAIL,
          show(g.strictWorst.value), g.strictWorst.frame, `${g.strictFAIL}/${g.n}`];
      }),
    ], ['l', 'l', 'l', 'l', 'r', 'l', 'l', 'r', 'r', 'r', 'r', 'l', 'r']));
  }
  if (notes.length) {
    out.push('');
    out.push('Reported without a verdict (the brief gives no number):');
    for (const note of notes) out.push(`  · ${note.text}`);
  }
  const fails = summary.reduce((a, g) => a + g.FAIL, 0);
  const atLimit = summary.reduce((a, g) => a + g['AT-LIMIT'], 0);
  out.push('');
  out.push(`${options.sky}: ${fails ? `FAIL — ${fails} failing check${fails === 1 ? '' : 's'} across the frames` : atLimit ? 'PASS, with checks AT-LIMIT' : 'PASS'}`
    + `${atLimit ? ` (${atLimit} at the limit)` : ''}${problems.length ? ` · ${problems.length} frame${problems.length === 1 ? '' : 's'} could not be measured` : ''}`);
  process.stdout.write(`${out.join('\n')}\n`);
}

// ───────────────────────────────────────────────────────────────── main ──

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

/** What --json writes. */
function documentOf(options, frames, summary, notes, anchors, problems) {
  return {
    tool: 'design/sky-lab/tools/measure.mjs', version: 1,
    sky: options.sky,
    options: { devices: options.devices, schemes: options.schemes, times: options.times, asleep: options.asleep, starsByAge: options.starsByAge, query: options.query },
    method: METHOD,
    checks: CHECKS.map((check) => ({ id: check.id, label: check.label, kind: check.kind, roles: check.roles ?? null, schemes: check.schemes, direction: check.dir, threshold: check.threshold ?? 'the card\'s luminance (tokens.cardL)', atLimitWithin: '5 % of the threshold, on the passing side', brief: check.brief })),
    summary, notes, anchors, problems, frames,
  };
}

/** --from-json: the summary, the notes and the tables again from saved frames. */
async function reprint(options) {
  const saved = JSON.parse(await fsp.readFile(options.fromJson, 'utf8'));
  if (!Array.isArray(saved.frames) || !saved.options) throw new Error(`${options.fromJson} is not a JSON this tool wrote`);
  const view = { ...saved.options, sky: saved.sky, dpr: saved.options.query.dpr, quiet: options.quiet };
  const anchors = saved.anchors ?? [];
  const problems = saved.problems ?? [];
  const summary = summarize(saved.frames);
  const notes = unjudged(saved.frames, anchors);
  printReport(view, saved.frames, summary, notes, problems);
  if (options.json) {
    await fsp.mkdir(path.dirname(options.json), { recursive: true });
    await fsp.writeFile(options.json, `${JSON.stringify(documentOf(view, saved.frames, summary, notes, anchors, problems), null, 1)}\n`);
    process.stderr.write(`measure: wrote ${options.json}\n`);
  }
  if (problems.length || summary.some((group) => group.FAIL > 0)) process.exitCode = 1;
}

async function main() {
  const options = readOptions(process.argv.slice(2));
  if (options.fromJson) { await reprint(options); return; }
  const started = Date.now();
  const overrides = new Map();
  if (options.skyFile) {
    if (!fs.existsSync(options.skyFile)) { process.stderr.write(`measure: there is no ${options.skyFile}\n`); process.exit(1); }
    overrides.set(`/skies/${options.sky}.js`, options.skyFile);
  } else if (!fs.existsSync(path.join(LAB_ROOT, 'skies', `${options.sky}.js`))) {
    process.stderr.write(`measure: there is no skies/${options.sky}.js in ${LAB_ROOT}\n`);
    process.exit(1);
  }
  for (const dir of [options.annotate, options.saveShots, options.json ? path.dirname(options.json) : null]) {
    if (dir) await fsp.mkdir(dir, { recursive: true });
  }

  // lab/presence.js names the bloom; without it the frames are still measured.
  let presenceOf = null;
  try {
    const module = await import('../lab/presence.js');
    if (typeof module.presence === 'function') presenceOf = (state) => module.presence({ sun: state.sun, moon: state.moon, event: state.event, asleep: state.asleep });
  } catch { /* reported as "—" */ }

  const require = createRequire(import.meta.url);
  const { chromium } = require('playwright');
  const server = await serve(LAB_ROOT, overrides);
  const browser = await chromium.launch();
  const problems = [];
  const done = new Map();
  try {
    const contexts = new Map();
    const contextFor = (device) => {
      if (!contexts.has(device)) {
        const [width, height] = DEVICE_SIZES[device];
        contexts.set(device, browser.newContext({ viewport: { width, height }, deviceScaleFactor: options.dpr }));
      }
      return contexts.get(device);
    };
    const jobs = [];
    for (const device of options.devices) {
      for (const scheme of options.schemes) {
        for (const time of options.times) jobs.push({ device, scheme, time, id: frameId(device, scheme, time, options.asleep) });
      }
    }
    let count = 0;
    await pool(jobs, options.jobs, async (job) => {
      const began = Date.now();
      try {
        const frame = await measureFrame(contextFor, options, server.origin, job, presenceOf);
        done.set(job.id, frame);
        count += 1;
        process.stderr.write(`measure: ${String(count).padStart(3)}/${jobs.length} ${job.id} (${((Date.now() - began) / 1000).toFixed(1)} s)\n`);
        for (const line of frame.console) process.stderr.write(`measure: ${job.id}: console: ${line}\n`);
      } catch (error) {
        const reason = String(error.message ?? error).split('\n')[0];
        problems.push({ frame: job.id, reason });
        process.stderr.write(`measure: FAILED ${job.id}: ${reason}\n`);
      }
    });
    const frames = jobs.map((job) => done.get(job.id)).filter(Boolean);
    // One world, two windows: every cover frame against the spread's phone page at the same scheme and time.
    const anchors = [];
    for (const cover of jobs.filter((job) => job.device === 'cover' && job.anchor)) {
      const spread = jobs.find((job) => job.device === 'spread' && job.scheme === cover.scheme && job.time === cover.time && job.anchor);
      if (!spread) continue;
      const same = compareAnchors(cover.anchor, spread.anchor, 0);
      let best = same;
      for (let shift = -12; shift <= 12; shift += 1) {
        const tried = compareAnchors(cover.anchor, spread.anchor, shift);
        if (tried.meanLevels < best.meanLevels - 1e-9) best = tried;
      }
      anchors.push({ scheme: cover.scheme, time: cover.time, cover: cover.id, spread: spread.id, sameY: same, bestShift: best });
    }
    const summary = summarize(frames);
    const notes = unjudged(frames, anchors);
    printReport(options, frames, summary, notes, problems);
    if (options.json) {
      const document = documentOf(options, frames, summary, notes, anchors, problems);
      await fsp.writeFile(options.json, `${JSON.stringify(document, null, 1)}\n`);
      process.stderr.write(`measure: wrote ${options.json}\n`);
    }
    process.stderr.write(`measure: ${frames.length}/${jobs.length} frames in ${((Date.now() - started) / 1000).toFixed(1)} s\n`);
    if (problems.length || summary.some((group) => group.FAIL > 0)) process.exitCode = 1;
  } finally {
    await browser.close().catch(() => {});
    await server.close();
  }
}

main().catch((error) => {
  process.stderr.write(`measure: ${error.stack ?? error}\n`);
  process.exit(1);
});
