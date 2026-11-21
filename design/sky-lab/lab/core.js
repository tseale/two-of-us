// Sky lab — the viewer's core: the device presets, URL → `state`, and the
// animation loop that hands that state to a sky module and to Home's chrome.
// The README is the contract; this file is the part of it called "the viewer".
//
//   DEVICES                              the three displays (points)
//   DEFAULTS                             every URL parameter's default
//   parseParams(searchParams) → params   the URL, validated and filled in
//   toSearch(params) → string            the way back: a query without defaults
//   buildState(params, t, cards) → state the README's `state` object (pure)
//   run() → Promise<lab>                 mounts the viewer into #display (browser only)
//
// Nothing at the top level touches the DOM, so node can import this file too
// (tools/shoot.mjs reads DEVICES and labels its sheets with buildState).

import * as solar from './solar.js';
import * as palette from './palette.js';

const HOUR_MS = 3_600_000;
const DAY_MS = 86_400_000;

function deepFreeze(value) {
  if (value && typeof value === 'object' && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const key of Object.keys(value)) deepFreeze(value[key]);
  }
  return value;
}

// ─────────────────────────────────────────────────────────────── displays ──

/** The displays, in points (README, "Displays"). Frozen; `buildState` hands
 *  out copies. */
export const DEVICES = deepFreeze({
  // iPhone Duo closed. The system strip is an 84 pt column on the trailing edge.
  cover: {
    width: 466, height: 678,
    phone: { x: 0, width: 466 },
    fold: null,
    strip: { side: 'trailing', width: 84 },
  },
  // iPhone Duo open, landscape. The phone page keeps the cover's sky where it was.
  spread: {
    width: 951, height: 669,
    phone: { x: 485, width: 466 },
    fold: { x: 475.5, bandMinX: 455.5, bandMaxX: 495.5 },
    strip: { side: 'trailing', width: 84 },
  },
  // A slab iPhone.
  iphone: {
    width: 402, height: 874,
    phone: { x: 0, width: 402 },
    fold: null,
    strip: null,
  },
});

/** The corner radius the bezel gives each display (`bezel=1` only). */
const CORNER = { cover: 38, spread: 38, iphone: 56 };
const BEZEL = 10;

// ───────────────────────────────────────────────────────────── parameters ──

/** Every parameter's default (README, "The viewer's URL"), then the lab's
 *  additions: `event` + `eventAge`, `lead`, `tilt`, `toast` (fields BRIEF.md
 *  and lab/chrome.js read from the state) and `zoom` (the panel's). */
export const DEFAULTS = Object.freeze({
  sky: 'baseline',
  device: 'cover',
  scheme: 'dark',
  date: '2026-11-21',
  time: '16:10',
  lat: 41.88,
  lon: -87.63,
  tz: -6,
  asleep: false,       // false | 'nap' | 'night'
  age: 142,
  chrome: true,
  t: null,             // null = running; a number freezes the animation there
  motion: true,        // false = Reduce Motion
  dpr: 2,
  ui: false,
  bezel: false,
  event: null,         // null | 'bedtime' | 'wake' | 'open' | 'close' → state.event.kind
  eventAge: 0,         // seconds since the event → state.event.age
  lead: null,          // null | 0–1 → state.lead (the spread's leading page's opacity)
  tilt: null,          // null | { x, y }, −1…1 each → state.tilt
  toast: false,        // true → state.toast (the undo toast)
  zoom: 1,             // the display's magnification, with ui=1 or bezel=1 only
});

const pad2 = (n) => String(n).padStart(2, '0');
const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));

function number(raw, fallback, lo = -Infinity, hi = Infinity) {
  if (raw == null || String(raw).trim() === '') return fallback;
  const value = Number(raw);
  return Number.isFinite(value) ? clamp(value, lo, hi) : fallback;
}

function flag(raw, fallback) {
  if (raw == null) return fallback;
  const value = String(raw).trim().toLowerCase();
  if (['1', 'true', 'on', 'yes'].includes(value)) return true;
  if (['0', 'false', 'off', 'no'].includes(value)) return false;
  return fallback;
}

/** 'YYYY-MM-DD' (a real calendar day) → the same, zero-padded; else null. */
function cleanDate(raw) {
  const m = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(String(raw ?? '').trim());
  if (!m) return null;
  const [year, month, day] = [Number(m[1]), Number(m[2]), Number(m[3])];
  const check = new Date(Date.UTC(year, month - 1, day));
  if (check.getUTCFullYear() !== year || check.getUTCMonth() !== month - 1 || check.getUTCDate() !== day) return null;
  return `${m[1]}-${pad2(month)}-${pad2(day)}`;
}

/** 'HH:MM' or 'HH:MM:SS' (24 h; 'HHMM' is accepted) → minutes since local
 *  midnight, fractional; NaN if it is not a time. */
export function timeToMinutes(time) {
  const m = /^(\d{1,2}):?(\d{2})(?::(\d{2}(?:\.\d+)?))?$/.exec(String(time ?? '').trim());
  if (!m) return NaN;
  const [hours, minutes, secs] = [Number(m[1]), Number(m[2]), Number(m[3] ?? 0)];
  if (hours > 23 || minutes > 59 || secs >= 60) return NaN;
  return hours * 60 + minutes + secs / 60;
}

/** Minutes since local midnight → 'HH:MM', or 'HH:MM:SS' when it is not on a minute. */
export function minutesToTime(minutes) {
  const total = Math.round((((minutes % 1440) + 1440) % 1440) * 60) % 86_400;
  const [h, m, s] = [Math.floor(total / 3600), Math.floor(total / 60) % 60, total % 60];
  return s === 0 ? `${pad2(h)}:${pad2(m)}` : `${pad2(h)}:${pad2(m)}:${pad2(s)}`;
}

/**
 * The viewer's URL → params: every parameter present, typed, and valid (an
 * unknown or malformed value falls back to its default).
 * @param {URLSearchParams | string | Record<string, unknown>} [searchParams]
 */
export function parseParams(searchParams) {
  const source = searchParams == null ? new URLSearchParams()
    : typeof searchParams === 'string' ? new URLSearchParams(searchParams)
    : searchParams;
  const get = typeof source.get === 'function'
    ? (key) => source.get(key)
    : (key) => (source[key] == null ? null : String(source[key]));
  const D = DEFAULTS;

  const sky = (get('sky') ?? '').trim() || D.sky;
  const device = Object.hasOwn(DEVICES, get('device') ?? '') ? get('device') : D.device;
  const scheme = ['light', 'dark'].includes(get('scheme')) ? get('scheme') : D.scheme;
  const minutes = timeToMinutes(get('time'));
  const asleep = ['nap', 'night'].includes(get('asleep')) ? get('asleep') : D.asleep;
  const t = number(get('t'), null);
  const event = /^[a-z][a-z0-9_-]*$/i.test(get('event') ?? '') && !['0', 'none'].includes(get('event'))
    ? get('event') : D.event;
  const lead = number(get('lead'), null, 0, 1);
  const tiltParts = String(get('tilt') ?? '').split(',').map((part) => Number(part));
  const tilt = tiltParts.length === 2 && tiltParts.every(Number.isFinite) && String(get('tilt')).trim() !== ''
    ? { x: clamp(tiltParts[0], -1, 1), y: clamp(tiltParts[1], -1, 1) }
    : D.tilt;

  return {
    sky,
    device,
    scheme,
    date: cleanDate(get('date')) ?? D.date,
    time: Number.isNaN(minutes) ? D.time : minutesToTime(minutes),
    lat: number(get('lat'), D.lat, -90, 90),
    lon: number(get('lon'), D.lon, -180, 180),
    tz: number(get('tz'), D.tz, -12, 14),
    asleep,
    age: number(get('age'), D.age, 0),
    chrome: flag(get('chrome'), D.chrome),
    t,
    motion: flag(get('motion'), D.motion),
    dpr: number(get('dpr'), D.dpr, 1, 3),
    ui: flag(get('ui'), D.ui),
    bezel: flag(get('bezel'), D.bezel),
    event,
    eventAge: number(get('eventAge'), D.eventAge, 0),
    lead,
    tilt,
    toast: flag(get('toast'), D.toast),
    zoom: number(get('zoom'), D.zoom, 0.25, 4),
  };
}

/** params → the query string (no '?'), in a fixed order, defaults left out. */
export function toSearch(params) {
  const D = DEFAULTS;
  const out = new URLSearchParams();
  const put = (key, value, isDefault) => { if (!isDefault) out.set(key, String(value)); };
  const p = params;
  put('sky', p.sky, p.sky === D.sky);
  put('device', p.device, p.device === D.device);
  put('scheme', p.scheme, p.scheme === D.scheme);
  put('date', p.date, p.date === D.date);
  put('time', p.time, p.time === D.time);
  put('lat', p.lat, p.lat === D.lat);
  put('lon', p.lon, p.lon === D.lon);
  put('tz', p.tz, p.tz === D.tz);
  put('asleep', p.asleep || 0, !p.asleep);
  put('age', p.age, p.age === D.age);
  put('chrome', p.chrome ? 1 : 0, p.chrome === D.chrome);
  put('t', p.t, p.t == null);
  put('motion', p.motion ? 1 : 0, p.motion === D.motion);
  put('dpr', p.dpr, p.dpr === D.dpr);
  put('event', p.event, p.event == null);
  put('eventAge', p.eventAge, p.event == null || p.eventAge === D.eventAge);
  put('lead', p.lead, p.lead == null);
  put('tilt', p.tilt ? `${p.tilt.x},${p.tilt.y}` : '', p.tilt == null);
  put('toast', 1, !p.toast);
  put('ui', 1, !p.ui);
  put('bezel', 1, !p.bezel);
  put('zoom', p.zoom, p.zoom === D.zoom);
  // Colons and commas are legal in a query and read better unescaped.
  return out.toString().replace(/%3A/gi, ':').replace(/%2C/gi, ',');
}

// ────────────────────────────────────────────────────────────────── state ──

/** Where the sun neither rises nor sets: the Swift's plain 06:45–18:15 day. */
function fallbackDay(date, tzOffsetHours) {
  if (typeof palette.fallbackDay === 'function') return palette.fallbackDay(date, tzOffsetHours);
  const tzMs = tzOffsetHours * HOUR_MS;
  const start = Math.floor((date.getTime() + tzMs) / DAY_MS) * DAY_MS - tzMs;
  return { sunrise: new Date(start + 6.75 * HOUR_MS), sunset: new Date(start + 18.25 * HOUR_MS) };
}

/**
 * The README's `state` for these params at animation time `t` (seconds).
 * Pure: the same arguments give an equal state. Every object in it is fresh
 * except `cards`, which is the array passed in (the chrome refills its own in
 * place, so whoever holds the state sees a re-measure).
 *
 * Beyond the README's fields, in this order after them:
 *   tilt   { x, y }, −1…1 each — the device's tilt, for parallax (0, 0 unless `tilt=`)
 *   event  null | { kind, age } — lab/presence.js's events (`event=`, `eventAge=`)
 *   lead   0–1, only when `lead=` is given — the leading page's opacity (lab/chrome.js)
 *   toast  { message }, only with `toast=1` — the undo toast (lab/chrome.js)
 *
 * @param {ReturnType<typeof parseParams>} params
 * @param {number} [t]      seconds; defaults to `params.t`, else 0
 * @param {Array<{x:number,y:number,width:number,height:number,kind:string}>} [cards]
 */
export function buildState(params, t, cards = []) {
  const p = params;
  const device = Object.hasOwn(DEVICES, p.device) ? p.device : DEFAULTS.device;
  const preset = DEVICES[device];
  const tz = p.tz;

  const [year, month, dayOfMonth] = p.date.split('-').map(Number);
  const minutes = timeToMinutes(p.time);
  const localMidnight = Date.UTC(year, month - 1, dayOfMonth);         // the local day, as if it were UTC
  const date = new Date(localMidnight + Math.round(minutes * 60_000) - tz * HOUR_MS);
  const dayOfYear = Math.round((localMidnight - Date.UTC(year, 0, 1)) / DAY_MS) + 1;

  const position = solar.sunPosition(date, p.lat, p.lon);
  const day = solar.solarDay(date, p.lat, p.lon, tz) ?? fallbackDay(date, tz);
  const phase = solar.solarPhase(date, day);
  const scene = palette.scene({
    date, latitude: p.lat, longitude: p.lon, tzOffsetHours: tz, dark: p.scheme === 'dark',
  });
  const m = scene.moon;

  const state = {
    device,
    width: preset.width,
    height: preset.height,
    dpr: p.dpr,
    phone: { ...preset.phone },
    fold: preset.fold ? { ...preset.fold } : null,
    strip: preset.strip ? { ...preset.strip } : null,
    scheme: p.scheme === 'light' ? 'light' : 'dark',

    date,
    tzOffsetHours: tz,
    latitude: p.lat,
    longitude: p.lon,
    dayOfYear,
    localHour: minutes / 60,

    sun: {
      altitude: position.altitude,
      azimuth: position.azimuth,
      isNight: phase.isNight,
      progress: phase.progress,
      sunrise: day.sunrise,
      sunset: day.sunset,
    },
    moon: m ? {
      altitude: m.altitude,
      azimuth: m.azimuth,
      fraction: m.fraction,
      phase: m.phase,
      rotation: m.rotation,
      passProgress: m.passProgress,
      inDaylight: m.inDaylight,
      x: m.x,
      y: m.y,
    } : null,
    scene,

    asleep: p.asleep === 'nap' || p.asleep === 'night' ? p.asleep : false,
    ageDays: p.age,

    t: Number.isFinite(t) ? t : (p.t ?? 0),
    reduceMotion: !p.motion,
    cards,

    tilt: p.tilt ? { x: p.tilt.x, y: p.tilt.y } : { x: 0, y: 0 },
    event: p.event ? { kind: p.event, age: p.eventAge } : null,
  };
  if (p.lead != null) state.lead = p.lead;
  if (p.toast) state.toast = { message: 'Logged 4.5 oz' };
  return state;
}

// ─────────────────────────────────────────────────────────────── the viewer ──

/** The times the panel's jump buttons offer — tools/shoot.mjs's default set. */
const JUMPS = ['03:00', '06:50', '09:30', '12:30', '16:10', '16:40', '17:30', '21:00'];
/** How long anything the viewer waits on (a sky's images, the fonts) may take
 *  before it gives up waiting and says so. */
const PATIENCE_MS = 15_000;
const DEG = 180 / Math.PI;

const SKY_ID = /^[A-Za-z0-9][A-Za-z0-9_-]*$/;

function within(promise, ms, what) {
  let timer;
  const timeout = new Promise((resolve) => {
    timer = setTimeout(() => {
      console.warn(`sky lab: gave up waiting for ${what} after ${ms / 1000} s`);
      resolve();
    }, ms);
  });
  return Promise.race([Promise.resolve(promise).catch(() => {}), timeout]).finally(() => clearTimeout(timer));
}

const localTime = (date, tz) => {
  const ms = (((date.getTime() + tz * HOUR_MS) % DAY_MS) + DAY_MS) % DAY_MS;
  return `${pad2(Math.floor(ms / HOUR_MS))}:${pad2(Math.floor(ms / 60_000) % 60)}`;
};

/**
 * Mounts the viewer: a sky host and the chrome's root inside #display, the
 * panel and bezel around it when asked for, and the frame loop.
 *
 * Sets `window.__labReady = true` once a frame is fully drawn (the sky has
 * rendered, its images and the fonts have arrived, two animation frames have
 * passed), and `window.__labError` (a string) if the sky cannot be drawn —
 * `__labReady` stays false then. Also leaves `window.__lab` behind, for tools:
 *   __lab.params        the live params
 *   __lab.state         the state last handed to the sky
 *   __lab.cards         what the chrome last returned
 *   __lab.set(patch)    change params as the panel would → a promise that
 *                       resolves when that frame is fully drawn
 *
 * @returns {Promise<typeof window.__lab>}
 */
export async function run() {
  const win = window;
  const doc = document;
  const params = parseParams(new URLSearchParams(win.location.search));
  win.__labReady = false;
  win.__labError = null;

  // ── the display: a sky host underneath, the chrome's root above it ──
  let display = doc.getElementById('display');
  if (!display) {
    display = doc.createElement('div');
    display.id = 'display';
    doc.body.prepend(display);
  }
  display.textContent = '';
  display.style.position = 'relative';
  display.style.overflow = 'hidden';

  const chromeRoot = doc.createElement('div');
  chromeRoot.id = 'chrome-root';
  chromeRoot.style.cssText = 'position:absolute;inset:0;';
  const errorBox = doc.createElement('div');
  errorBox.id = 'lab-error';
  errorBox.setAttribute('role', 'alert');
  errorBox.hidden = true;
  display.append(chromeRoot, errorBox);

  const deviceEl = doc.getElementById('device');     // the bezel; optional
  const stageEl = doc.getElementById('stage');       // what the zoom sizes; optional
  let panel = doc.getElementById('panel');
  let panelBuilt = false;
  let crease = null;
  let layoutKey = '';

  // ── what is mounted ──
  let host = null;               // the current sky's own <div>
  let sky = null;                // { render, destroy, ready? }
  let skyMeta = null;
  let skyGeneration = 0;
  let skyBroken = false;         // render() threw: wait for a change before trying again
  let renderPending = false;     // an async render() has not come back yet
  let lastRender = null;         // the promise render() returned, if it did
  let skyIds = [DEFAULTS.sky];

  let chromeModule;              // undefined: not asked for yet; null: not there
  let chrome = null;             // { update, destroy }
  let chromeKey = null;
  let chromeNote = '';
  let cards = [];

  let lastState = null;
  let dirty = true;
  let settleGeneration = 0;
  let sweep = 0;                 // the day running by: minutes of sky per second of yours
  let pointerTilt = false;
  let liveTilt = null;

  // ── the clock ──
  let clockBase = params.t ?? 0;
  let clockStart = performance.now();
  let eventStart = clockBase;    // the `t` at which the current event began
  let lastTick = performance.now();
  const frozen = () => params.t != null;
  const currentT = () => (frozen() ? params.t : clockBase + (performance.now() - clockStart) / 1000);

  // ── errors: in the display, readable, never a blank page ──
  let errorKind = null;          // 'load' | 'render' | 'state'
  function showError(kind, title, error, hint) {
    errorKind = kind;
    if (kind == null) {
      errorBox.hidden = true;
      errorBox.textContent = '';
      win.__labError = null;
      return;
    }
    const message = error instanceof Error ? error.message : String(error ?? '');
    errorBox.textContent = '';
    const add = (tag, text) => {
      if (!text) return;
      const node = doc.createElement(tag);
      node.textContent = text;
      errorBox.append(node);
    };
    add('strong', title);
    add('p', message);
    add('p', hint);
    const stack = error instanceof Error && error.stack
      ? error.stack.split('\n').filter((line) => /^\s+at /.test(line)).slice(0, 4).join('\n').replaceAll(`${win.location.origin}/`, '')
      : '';
    add('pre', stack);
    errorBox.hidden = false;
    win.__labError = `${title}: ${message}`;
    console.error(`sky lab: ${title}`, error);
  }

  function setTitle() {
    doc.title = `Sky lab · ${params.sky} · ${params.device} · ${params.scheme} · ${params.time.slice(0, 5)}`;
  }

  // ── layout: the display's size, the bezel, the zoom ──
  function applyLayout() {
    setTitle();
    const key = [params.device, params.scheme, params.ui, params.bezel, params.zoom].join('|');
    if (key === layoutKey) return;
    layoutKey = key;
    const preset = DEVICES[params.device];
    display.style.width = `${preset.width}px`;
    display.style.height = `${preset.height}px`;
    const body = doc.body;
    body.classList.toggle('lab-ui', params.ui);
    body.classList.toggle('lab-bezel', params.bezel);
    const bare = !params.ui && !params.bezel;
    body.classList.toggle('lab-bare', bare);
    doc.documentElement.classList.toggle('lab-bare', bare);      // no scrollbars around the bare display
    body.dataset.device = params.device;
    body.dataset.scheme = params.scheme;

    const radius = params.bezel ? CORNER[params.device] : 0;
    display.style.borderRadius = radius ? `${radius}px` : '';
    const rim = params.bezel ? BEZEL : 0;
    if (deviceEl) {
      deviceEl.style.padding = rim ? `${rim}px` : '';
      deviceEl.style.borderRadius = rim ? `${radius + rim}px` : '';
      deviceEl.style.width = '';
      deviceEl.style.transform = '';
      if (crease) { crease.remove(); crease = null; }
      if (params.bezel && preset.fold) {
        crease = doc.createElement('div');
        crease.id = 'crease';
        const band = preset.fold.bandMaxX - preset.fold.bandMinX;
        crease.style.cssText = `position:absolute;pointer-events:none;top:${rim}px;bottom:${rim}px;`
          + `left:${rim + preset.fold.bandMinX}px;width:${band}px;`;
        deviceEl.append(crease);
      }
      // The zoom is the panel's and the bezel's: the bare display is always 1:1.
      const zoom = params.ui || params.bezel ? params.zoom : 1;
      const outerWidth = preset.width + 2 * rim;
      const outerHeight = preset.height + 2 * rim;
      if (zoom !== 1) {
        deviceEl.style.width = `${outerWidth}px`;
        deviceEl.style.transform = `scale(${zoom})`;
        deviceEl.style.transformOrigin = '0 0';
      }
      if (stageEl) {
        const sized = zoom !== 1;
        stageEl.style.width = sized ? `${outerWidth * zoom}px` : '';
        stageEl.style.height = sized ? `${outerHeight * zoom}px` : '';
      }
    }
  }

  // ── the chrome: optional, and never allowed to take the sky down with it ──
  async function loadChromeModule() {
    if (chromeModule !== undefined) return chromeModule;
    try {
      const module = await import('./chrome.js');
      if (typeof module.createChrome !== 'function') throw new Error('lab/chrome.js does not export createChrome(root)');
      chromeModule = module;
    } catch (error) {
      chromeModule = null;
      chromeNote = 'lab/chrome.js is not there: the sky alone';
      console.warn('sky lab: no chrome —', error);
    }
    return chromeModule;
  }

  function dropChrome(error) {
    if (error) {
      chromeNote = `the chrome failed: ${error.message ?? error}`;
      console.error('sky lab: the chrome failed —', error);
    }
    try { chrome?.destroy?.(); } catch { /* it is going away regardless */ }
    chrome = null;
    chromeKey = null;
    chromeRoot.textContent = '';
    cards = [];
  }

  function syncChrome(state) {
    const wanted = params.chrome && chromeModule != null;
    if (!wanted) {
      if (chrome) dropChrome();
      cards = [];
      return;
    }
    if (!chrome) {
      try {
        chrome = chromeModule.createChrome(chromeRoot);
        chromeKey = null;
      } catch (error) {
        chromeModule = null;
        dropChrome(error);
        return;
      }
    }
    // Whenever the minute, device, scheme or asleep changes — and anything
    // else the chrome reads — but not every frame.
    const key = [params.device, params.scheme, params.date, params.time.slice(0, 5), params.asleep,
      params.age, params.tz, params.lead, params.toast].join('|');
    if (key === chromeKey) return;
    chromeKey = key;
    try {
      const next = chrome.update(state);
      cards = Array.isArray(next) ? next : [];
    } catch (error) {
      chromeModule = null;
      dropChrome(error);
    }
  }

  // ── the sky ──
  async function loadSkyList() {
    try {
      const module = await import('../skies/index.js');
      const ids = (module.skies ?? []).map((entry) => (typeof entry === 'string' ? entry : entry?.id)).filter(Boolean);
      if (ids.length) skyIds = ids;
    } catch {
      skyIds = [DEFAULTS.sky];   // skies/index.js is not there yet
    }
  }

  function unloadSky() {
    try { sky?.destroy?.(); } catch (error) { console.warn('sky lab: destroy() threw —', error); }
    sky = null;
    skyMeta = null;
    skyBroken = false;
    renderPending = false;
    lastRender = null;
    host?.remove();
    host = null;
  }

  async function loadSky(id) {
    const generation = ++skyGeneration;
    unloadSky();
    showError(null);
    const listed = () => `skies/index.js lists: ${skyIds.join(', ')}.`;
    try {
      if (!SKY_ID.test(id)) throw new Error('A sky id is letters, digits, "-" and "_" — the file name in skies/ without ".js".');
      const module = await import(`../skies/${id}.js`);
      if (generation !== skyGeneration) return;
      if (typeof module.create !== 'function') throw new Error(`skies/${id}.js does not export create(host, env).`);
      host = doc.createElement('div');
      host.id = 'sky-host';
      host.style.cssText = 'position:absolute;inset:0;overflow:hidden;';
      display.insertBefore(host, chromeRoot);
      const instance = await module.create(host, { assets: 'assets/', solar, palette });
      if (generation !== skyGeneration) {
        try { instance?.destroy?.(); } catch { /* superseded */ }
        return;
      }
      if (!instance || typeof instance.render !== 'function') {
        throw new Error(`skies/${id}.js: create() did not return { render(state), destroy() }.`);
      }
      sky = instance;
      skyMeta = { id, ...(module.meta ?? {}) };
    } catch (error) {
      if (generation !== skyGeneration) return;
      unloadSky();
      showError('load', `Sky "${id}" could not be loaded`, error,
        SKY_ID.test(id) ? `Looked for skies/${id}.js. ${listed()}` : listed());
    }
  }

  // ── one frame ──
  function drawFrame() {
    dirty = false;
    let state;
    try {
      state = buildState(params, currentT(), cards);
    } catch (error) {
      showError('state', 'These parameters do not make a state', error);
      return;
    }
    if (liveTilt) state.tilt = { ...liveTilt };
    // An event plays on from `eventAge` while the animation runs; frozen, it is exactly `eventAge`.
    if (state.event && !frozen()) state.event.age = params.eventAge + Math.max(0, state.t - eventStart);

    syncChrome(state);
    state.cards = cards;
    lastState = state;

    if (sky && renderPending) dirty = true;     // an async render is still out: this frame waits its turn
    if (sky && !skyBroken && !renderPending) {
      try {
        const result = sky.render(state);
        if (result && typeof result.then === 'function') {
          renderPending = true;
          const failedIn = sky;
          lastRender = Promise.resolve(result).then(
            () => { renderPending = false; },
            (error) => {
              renderPending = false;
              if (failedIn !== sky) return;
              skyBroken = true;
              showError('render', `Sky "${params.sky}" failed while rendering`, error);
            },
          );
        }
      } catch (error) {
        skyBroken = true;
        showError('render', `Sky "${params.sky}" failed while rendering`, error);
      }
    }
    if (panelBuilt && params.ui) refreshPanel(state);
  }

  function tick(now) {
    win.requestAnimationFrame(tick);
    const dt = Math.min(0.25, (now - lastTick) / 1000);
    lastTick = now;
    if (sweep > 0) {
      params.time = minutesToTime(timeToMinutes(params.time) + sweep * dt);
      dirty = true;
      syncUrl();
    }
    if (frozen() && !dirty) return;       // a frozen frame is drawn once
    drawFrame();
  }

  // ── "fully drawn" ──
  const nextFrame = () => new Promise((resolve) => win.requestAnimationFrame(() => resolve()));

  async function fontsReady() {
    if (!doc.fonts) return;
    // Lay out first, so the faces the chrome asks for have started loading.
    void display.offsetHeight;
    await doc.fonts.ready;
    for (let pass = 0; pass < 4 && doc.fonts.status === 'loading'; pass += 1) await doc.fonts.ready;
  }

  async function imagesReady() {
    const images = [...display.querySelectorAll('img')].filter((image) => !image.complete);
    await Promise.all(images.map((image) => new Promise((resolve) => {
      image.addEventListener('load', resolve, { once: true });
      image.addEventListener('error', resolve, { once: true });
    })));
  }

  /** Draws the frame for the params as they now are and resolves once it is
   *  complete: the sky rendered, everything it and the chrome load arrived. */
  async function settle() {
    const generation = ++settleGeneration;
    win.__labReady = false;
    drawFrame();
    if (lastRender) await within(lastRender, PATIENCE_MS, 'the sky to render');
    if (sky && sky.ready != null) {
      await within(typeof sky.ready === 'function' ? sky.ready() : sky.ready, PATIENCE_MS, 'the sky to be ready');
    }
    await within(fontsReady(), PATIENCE_MS, 'the fonts');
    await within(imagesReady(), PATIENCE_MS, 'the images');
    if (generation !== settleGeneration) return;
    // Once more with everything in: the chrome has re-fitted to its fonts, and a
    // sky that drew before its images came redraws with them.
    drawFrame();
    if (lastRender) await within(lastRender, PATIENCE_MS, 'the sky to render');
    await nextFrame();
    await nextFrame();
    if (generation !== settleGeneration) return;
    win.__labReady = win.__labError == null;
  }

  // ── changes (the panel's, and __lab.set's) ──
  let urlTimer = 0;
  let urlAt = 0;
  function writeUrl() {
    urlAt = performance.now();
    const search = toSearch(params);
    win.history.replaceState(null, '', search ? `?${search}` : win.location.pathname);
    setTitle();
  }
  /** Browsers ration replaceState: at most a few a second while something is dragged. */
  function syncUrl() {
    if (urlTimer) return;
    const wait = Math.max(0, 250 - (performance.now() - urlAt));
    urlTimer = win.setTimeout(() => { urlTimer = 0; writeUrl(); }, wait);
  }

  /** Applies a patch of params — validated the way the URL is — and settles. */
  async function change(patch) {
    const merged = { ...toRaw(params), ...patch };
    const next = parseParams(merged);
    const before = { ...params };
    Object.assign(params, next);
    // `t`: pausing and playing keep the clock continuous; an event plays from its age again.
    if (before.t != null && params.t == null) {
      clockBase = before.t;
      clockStart = performance.now();
      eventStart = clockBase;
    }
    if (params.event !== before.event || 'eventAge' in patch || 'event' in patch) eventStart = currentT();
    // Whatever went wrong while drawing, this change may have put right.
    skyBroken = false;
    if (errorKind === 'render' || errorKind === 'state') showError(null);
    applyLayout();
    if (params.chrome && chromeModule === undefined) await loadChromeModule();
    if (params.sky !== before.sky || (!sky && 'sky' in patch)) await loadSky(params.sky);
    dirty = true;
    syncUrl();
    if (params.ui && !panelBuilt) buildPanel();
    if (panelBuilt) panel.hidden = !params.ui;
    if (panelBuilt && params.ui) syncPanel();
    await settle();
  }

  /** params → the strings the URL would carry (so a patch can be validated with them). */
  function toRaw(p) {
    return {
      ...p,
      asleep: p.asleep || '0',
      chrome: p.chrome ? '1' : '0',
      motion: p.motion ? '1' : '0',
      ui: p.ui ? '1' : '0',
      bezel: p.bezel ? '1' : '0',
      toast: p.toast ? '1' : '0',
      t: p.t == null ? '' : p.t,
      lead: p.lead == null ? '' : p.lead,
      tilt: p.tilt ? `${p.tilt.x},${p.tilt.y}` : '',
      event: p.event ?? '',
    };
  }

  // ── the panel (ui=1): beside the display, never over it ──
  const outputs = {};

  function buildPanel() {
    if (!panel) {
      panel = doc.createElement('aside');
      panel.id = 'panel';
      doc.body.append(panel);
    }
    panel.hidden = false;
    panelBuilt = true;
    const seg = (key, options) => `<span class="seg" data-seg="${key}">${options
      .map(([value, label]) => `<button type="button" data-value="${value}">${label ?? value}</button>`).join('')}</span>`;
    panel.innerHTML = `
      <header><strong>Sky lab</strong><a data-act="bare" title="This frame alone, as tools/shoot.mjs sees it">bare</a></header>
      <label class="row"><span>Sky</span><select data-key="sky"></select></label>
      <p class="note" data-out="blurb"></p>
      <div class="row"><span>Device</span>${seg('device', [['cover'], ['spread'], ['iphone']])}</div>
      <div class="row"><span>Scheme</span>${seg('scheme', [['light'], ['dark']])}</div>
      <div class="row"><span>Time</span><output data-out="time"></output><em data-out="phase"></em></div>
      <input type="range" data-key="time" min="0" max="1439" step="1" aria-label="Time of day">
      <div class="jumps" data-out="jumps"></div>
      <label class="row"><span>Date</span><input type="date" data-key="date"></label>
      <div class="row"><span>Asleep</span>${seg('asleep', [['0', 'awake'], ['nap'], ['night']])}</div>
      <div class="row"><span>Show</span>
        <label><input type="checkbox" data-key="chrome"> Home UI</label>
        <label><input type="checkbox" data-key="bezel"> bezel</label></div>
      <div class="row"><span>Motion</span><button type="button" data-act="play"></button><output data-out="t"></output></div>
      <div class="row"><span>Day</span>${seg('sweep', [['0', 'still'], ['10', '10 min/s'], ['60', '1 h/s']])}</div>
      <p class="note" data-out="chrome"></p>
      <details>
        <summary>More</summary>
        <div class="row"><span>Zoom</span>${seg('zoom', [['0.5', '50'], ['0.75', '75'], ['1', '100'], ['1.5', '150'], ['2', '200']])}</div>
        <div class="row"><span>Pixels</span>${seg('dpr', [['1', '@1x'], ['2', '@2x'], ['3', '@3x']])}</div>
        <label class="row"><span>Age</span><input type="number" data-key="age" min="0" step="1"> days</label>
        <label class="row"><span>Lat</span><input type="number" data-key="lat" min="-90" max="90" step="0.01"></label>
        <label class="row"><span>Lon</span><input type="number" data-key="lon" min="-180" max="180" step="0.01"></label>
        <label class="row"><span>UTC</span><input type="number" data-key="tz" min="-12" max="14" step="0.5"> h</label>
        <div class="row"><span>Event</span><select data-key="event">
          <option value="">none</option><option>bedtime</option><option>wake</option><option>open</option><option>close</option>
        </select><input type="number" data-key="eventAge" min="0" step="0.1" title="Seconds since the event"> s</div>
        <label class="row"><span>Lead</span><input type="range" data-key="lead" min="0" max="1" step="0.05" title="The spread's leading page's opacity"></label>
        <div class="row"><span></span>
          <label><input type="checkbox" data-key="reduce"> Reduce Motion</label>
          <label><input type="checkbox" data-key="toast"> toast</label></div>
        <div class="row"><span></span><label><input type="checkbox" data-key="pointerTilt"> tilt follows the pointer</label></div>
      </details>
      <pre data-out="readout"></pre>`;
    for (const node of panel.querySelectorAll('[data-out]')) outputs[node.dataset.out] = node;

    panel.addEventListener('click', (event) => {
      const button = event.target.closest('button');
      const act = event.target.closest('[data-act]')?.dataset.act;
      if (act === 'play') {
        change({ t: frozen() ? '' : Math.round(currentT() * 100) / 100 });
      } else if (button?.dataset.jump) {
        change({ time: button.dataset.jump });
      } else if (button && button.parentElement.dataset.seg) {
        const key = button.parentElement.dataset.seg;
        if (key === 'sweep') {
          sweep = Number(button.dataset.value);
          // Stopped, the clock rests on a whole minute.
          if (sweep === 0) change({ time: params.time.slice(0, 5) });
          else syncPanel();
        } else {
          change({ [key]: button.dataset.value });
        }
      }
    });
    panel.addEventListener('input', (event) => {
      const key = event.target.dataset.key;
      if (!key) return;
      const control = event.target;
      if (key === 'time') change({ time: minutesToTime(Number(control.value)) });
      else if (key === 'lead') change({ lead: control.value });
      else if (key === 'chrome' || key === 'bezel' || key === 'toast') change({ [key]: control.checked ? '1' : '0' });
      else if (key === 'reduce') change({ motion: control.checked ? '0' : '1' });
      else if (key === 'pointerTilt') { pointerTilt = control.checked; if (!pointerTilt) { liveTilt = null; dirty = true; } }
    });
    // Typed fields apply when they are committed, so half a number is never a state.
    panel.addEventListener('change', (event) => {
      const key = event.target.dataset.key;
      if (['sky', 'date', 'age', 'lat', 'lon', 'tz', 'event', 'eventAge'].includes(key)) {
        if (event.target.value === '' && key !== 'event') { syncPanel(); return; }
        change({ [key]: event.target.value });
      }
    });

    // Tilt, for a sky with parallax: the pointer's place over the display, −1…1.
    const tiltTarget = deviceEl ?? display;
    tiltTarget.addEventListener('pointermove', (event) => {
      if (!pointerTilt) return;
      const box = display.getBoundingClientRect();
      liveTilt = {
        x: clamp(((event.clientX - box.left) / box.width) * 2 - 1, -1, 1),
        y: clamp(((event.clientY - box.top) / box.height) * 2 - 1, -1, 1),
      };
      dirty = true;
    });
    tiltTarget.addEventListener('pointerleave', () => {
      if (!liveTilt) return;
      liveTilt = null;
      dirty = true;
    });
    syncPanel();
  }

  /** The controls, from the params. */
  function syncPanel() {
    const select = panel.querySelector('[data-key="sky"]');
    const ids = skyIds.includes(params.sky) ? skyIds : [...skyIds, params.sky];
    if (select.options.length !== ids.length || [...select.options].some((option, i) => option.value !== ids[i])) {
      select.replaceChildren(...ids.map((id) => new Option(id, id)));
    }
    select.value = params.sky;
    outputs.blurb.textContent = skyMeta
      ? [skyMeta.name, skyMeta.blurb].filter(Boolean).join(' — ')
      : '';
    const values = {
      device: params.device, scheme: params.scheme, asleep: params.asleep || '0',
      sweep: String(sweep), zoom: String(params.zoom), dpr: String(params.dpr),
    };
    for (const group of panel.querySelectorAll('[data-seg]')) {
      for (const button of group.children) {
        button.classList.toggle('on', button.dataset.value === values[group.dataset.seg]);
      }
    }
    const set = (key, value) => {
      const control = panel.querySelector(`[data-key="${key}"]`);
      if (!control) return;
      // A field being typed in is left alone until it is committed.
      if (doc.activeElement === control && ['number', 'date'].includes(control.type)) return;
      if (control.type === 'checkbox') control.checked = Boolean(value);
      else control.value = value;
    };
    set('time', Math.floor(timeToMinutes(params.time)));
    set('date', params.date);
    set('chrome', params.chrome);
    set('bezel', params.bezel);
    set('age', params.age);
    set('lat', params.lat);
    set('lon', params.lon);
    set('tz', params.tz);
    set('event', params.event ?? '');
    set('eventAge', params.eventAge);
    set('lead', params.lead ?? 1);
    set('reduce', !params.motion);
    set('toast', params.toast);
    set('pointerTilt', pointerTilt);
    panel.querySelector('[data-act="play"]').textContent = frozen() ? 'Play' : 'Pause';
    panel.querySelector('[data-act="bare"]').href = `?${toSearch({ ...params, ui: false, bezel: false, zoom: 1 })}`;
    outputs.chrome.textContent = chromeNote;
    outputs.chrome.hidden = !chromeNote;
  }

  /** The read-outs that move with the frame. */
  let jumpsKey = '';
  function refreshPanel(state) {
    const { sun, moon } = state;
    outputs.time.textContent = params.time.slice(0, 5);
    outputs.phase.textContent = `${sun.isNight ? 'night' : 'day'} ${sun.progress.toFixed(3)}`;
    outputs.t.textContent = `t ${state.t.toFixed(1)} s${frozen() ? ' (frozen)' : ''}`;
    const slider = panel.querySelector('[data-key="time"]');
    if (doc.activeElement !== slider || sweep > 0) slider.value = Math.floor(timeToMinutes(params.time));

    const rise = localTime(sun.sunrise, state.tzOffsetHours);
    const set = localTime(sun.sunset, state.tzOffsetHours);
    const key = `${rise}|${set}`;
    if (key !== jumpsKey) {
      jumpsKey = key;
      const marks = [...JUMPS.map((time) => [time, time]), [rise, `rise ${rise}`], [set, `set ${set}`]]
        .sort((a, b) => timeToMinutes(a[0]) - timeToMinutes(b[0]));
      outputs.jumps.innerHTML = marks
        .map(([time, label]) => `<button type="button" data-jump="${time}"${label === time ? '' : ' class="sun"'}>${label}</button>`).join('');
    }
    const deg = (radians, width = 6) => `${(radians * DEG >= 0 ? '+' : '') + (radians * DEG).toFixed(1)}°`.padStart(width);
    const lines = [
      `sun   alt ${deg(sun.altitude)}  az ${(sun.azimuth * DEG).toFixed(0).padStart(3)}°`,
      moon
        ? `moon  alt ${deg(moon.altitude)}  az ${(moon.azimuth * DEG).toFixed(0).padStart(3)}°\n      ${Math.round(moon.fraction * 100)}% lit, ${moon.phase < 0.5 ? 'waxing' : 'waning'}`
        : 'moon  down',
      `day ${state.dayOfYear}  age ${state.ageDays} d  cards ${state.cards.length}`,
    ];
    if (state.event) lines.push(`event ${state.event.kind}  age ${state.event.age.toFixed(1)} s`);
    if (liveTilt) lines.push(`tilt  ${state.tilt.x.toFixed(2)}, ${state.tilt.y.toFixed(2)}`);
    outputs.readout.textContent = lines.join('\n');
  }

  // ── go ──
  applyLayout();
  await Promise.all([loadSkyList(), params.chrome ? loadChromeModule() : null]);
  await loadSky(params.sky);
  if (params.ui) buildPanel();

  const lab = {
    get params() { return params; },
    get state() { return lastState; },
    get cards() { return cards; },
    get sky() { return skyMeta; },
    /** Change params as the panel would; resolves when that frame is fully drawn. */
    async set(patch) {
      await change(Object.fromEntries(Object.entries(patch ?? {}).map(([key, value]) => [key,
        typeof value === 'boolean' ? (value ? '1' : '0')
          : value == null ? ''
          : key === 'tilt' && typeof value === 'object' ? `${value.x},${value.y}`
          : value])));
      return lastState;
    },
  };
  win.__lab = lab;

  const settled = settle();
  win.requestAnimationFrame(tick);
  await settled;
  return lab;
}
