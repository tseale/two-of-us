// Sky lab — the sky's colours, hills, clouds and stars.
//
// A port of `enum SkyPalette` in TwoOfUs/DesignSystem/SkyBackground.swift:
// the same member names, the same constants and keyframes, the same seeded
// star generator, the same formulas. "Today's sky" (skies/baseline.js) is
// drawn from this, and every mockup is compared against that baseline, so the
// Swift is the truth: if it changes, port the change here and run
// `node design/sky-lab/tools/test-math.mjs`.
//
// Pure: no DOM, no globals, no machine time zone (`scene` takes
// `tzOffsetHours`: local = UTC + tzOffsetHours).
//
// Shapes:
//   RGB   = { r, g, b }                       each 0–1 (Swift: red, green, blue)
//   Look  = { top, mid, sun, core, warm, haze, mist, mistAlpha,
//             hills: [4 RGB], deep, light: { dawn, day, dusk } }
//   Scene = { look, isNight, body: {x, y}, cloudOpacity, starOpacity, isDark,
//             moon, page, cloudStrength, moonGlow, starStrength,
//             moonGlowByPhase, moonPoolByPhase }
//   Moon  = { x, y, fraction, phase, rotation, inDaylight,
//             altitude, azimuth, passProgress }
//
// Everything in `SkyPalette` is also a named export of this module (and
// `rgb`, `mix`, `css` are also on `SkyPalette`), so `palette.scene(...)` and
// `palette.SkyPalette.scene(...)` are the same function. Nothing uses `this`.

import * as solar from './solar.js';

const HOUR_MS = 3_600_000;
const DAY_MS = 86_400_000;

function clamp01(value) {
  return Math.min(Math.max(value, 0), 1);
}

function deepFreeze(value) {
  if (value !== null && typeof value === 'object' && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const key of Object.keys(value)) deepFreeze(value[key]);
  }
  return value;
}

// ───────────────────────────────────────────────────────────────── Colour ──

/** RGB(hex:). From 0xRRGGBB → { r, g, b }, each 0–1. */
export function rgb(hex) {
  return {
    r: ((hex >> 16) & 0xFF) / 255,
    g: ((hex >> 8) & 0xFF) / 255,
    b: (hex & 0xFF) / 255,
  };
}

/** RGB.mixed(with:by:). `a` towards `b` by `t` (clamped to 0–1). */
export function mix(a, b, t) {
  const f = clamp01(t);
  return {
    r: a.r + (b.r - a.r) * f,
    g: a.g + (b.g - a.g) * f,
    b: a.b + (b.b - a.b) * f,
  };
}

/** A CSS colour for an RGB: 'rgba(r, g, b, a)', channels rounded to 0–255. */
export function css(c, alpha = 1) {
  const channel = (v) => Math.round(clamp01(v) * 255);
  const a = Math.round(clamp01(alpha) * 10_000) / 10_000;
  return `rgba(${channel(c.r)}, ${channel(c.g)}, ${channel(c.b)}, ${a})`;
}

// ────────────────────────────────────────────────────────────────── Looks ──

/** The light page colour the sky fades into (`AppColor.bg`, light). */
export const page = deepFreeze(rgb(0xF2F2F7));
/** The dark page colour the dark sky fades into (`AppColor.bg`, dark). */
export const darkPage = deepFreeze(rgb(0x000000));

// CloudLight: how much of each cloud lighting (dawn, day, dusk) to show. A
// keyframe is all of one; between keyframes the weights still sum to 1.
const ofDawn = { dawn: 1, day: 0, dusk: 0 };
const ofDay = { dawn: 0, day: 1, dusk: 0 };
const ofDusk = { dawn: 0, day: 0, dusk: 1 };

/** CloudLight.mixed(with:by:). */
function mixLight(a, b, t) {
  const f = clamp01(t);
  return {
    dawn: a.dawn + (b.dawn - a.dawn) * f,
    day: a.day + (b.day - a.day) * f,
    dusk: a.dusk + (b.dusk - a.dusk) * f,
  };
}

/** Look.mixed(with:by:). */
function mixLook(a, b, t) {
  const f = clamp01(t);
  return {
    top: mix(a.top, b.top, f),
    mid: mix(a.mid, b.mid, f),
    sun: mix(a.sun, b.sun, f),
    core: mix(a.core, b.core, f),
    warm: mix(a.warm, b.warm, f),
    haze: mix(a.haze, b.haze, f),
    mist: mix(a.mist, b.mist, f),
    mistAlpha: a.mistAlpha + (b.mistAlpha - a.mistAlpha) * f,
    hills: a.hills.map((hill, index) => mix(hill, b.hills[index], f)),
    deep: mix(a.deep, b.deep, f),
    light: mixLight(a.light, b.light, f),
  };
}

/** One keyframe of the day: the sky at the top and in the middle, the sun's
 *  colour and its core, the warm pool around it, the haze the hills stand in,
 *  the valley mist, the four hills' crests (back to front) and the front
 *  hill's foot, and which lighting the clouds wear. */
function makeLook({ top, mid, sun, core, warm, haze, mist, mistAlpha, hills, deep, light }) {
  return deepFreeze({
    top: rgb(top), mid: rgb(mid), sun: rgb(sun), core: rgb(core),
    warm: rgb(warm), haze: rgb(haze), mist: rgb(mist), mistAlpha,
    hills: hills.map(rgb), deep: rgb(deep), light: { ...light },
  });
}

/** How strong the sun's glow and warm pool are, against the original (fully
 *  coloured) sky. */
export const glow = 0.32;
/** How opaque the clouds and wisps are. */
export const cloudStrength = 0.8;
/** …and in the dark appearance, where the painted (light) textures would
 *  otherwise glow against the deep sky: a faint, moonlit veil. */
export const darkCloudStrength = 0.16;
/** The moon's glow in the dark appearance, against the light one's. */
export const darkMoonGlow = 0.4;
/** The stars and glints in the dark appearance, against the light one's. */
export const darkStarStrength = 0.6;

// The keyframes, hushed: each colour keeps its hue at a fifth of its chroma
// (OKLCH) and sits 55 % of the way to the page's lightness (night a little
// less, so the stars show). Mist stays near white.
const sageHills = [0xE4E8EA, 0xDDE3E2, 0xD5DDDB, 0xCED7D3];

const dawn = makeLook({
  top: 0xD3D5DF, mid: 0xEDE8E9, sun: 0xDEBEAE, core: 0xF9F4EF,
  warm: 0xEFE4DE, haze: 0xF1EDEC, mist: 0xFFF0EC, mistAlpha: 0.6,
  hills: [0xEBE7EA, 0xE5E0E4, 0xDEDAE0, 0xD8D3DA],
  deep: 0xD1CDD5, light: ofDawn });
const morning = makeLook({
  top: 0xCED8E3, mid: 0xE5E9EE, sun: 0xF0E6CA, core: 0xFEFDF8,
  warm: 0xF4F2E9, haze: 0xEEF0F2, mist: 0xFFFFFF, mistAlpha: 0.62,
  hills: sageHills, deep: 0xC8D2CE, light: ofDay });
const noon = makeLook({
  top: 0xC7D2DF, mid: 0xE1E7ED, sun: 0xF4EED8, core: 0xFFFFFC,
  warm: 0xF6F4EE, haze: 0xEEF0F2, mist: 0xFFFFFF, mistAlpha: 0.62,
  hills: sageHills, deep: 0xC8D2CE, light: ofDay });
const dusk = makeLook({
  top: 0xCAC8D8, mid: 0xEAE2E4, sun: 0xD9B2A4, core: 0xF5ECE6,
  warm: 0xEDE0D9, haze: 0xEEEAEB, mist: 0xFFECF2, mistAlpha: 0.55,
  hills: [0xE8E4E9, 0xE1DDE3, 0xDAD5DE, 0xD2CDD7],
  deep: 0xCBC7D2, light: ofDusk });
const night = makeLook({
  top: 0x9C9FAD, mid: 0xC3C5CE, sun: 0xFAF5F0, core: 0xFFFFFF,
  warm: 0xD3D2DA, haze: 0xDBDBE1, mist: 0xDEE0F6, mistAlpha: 0.4,
  hills: [0xD1D2D9, 0xC5C6CF, 0xB9BBC5, 0xAEB0BC],
  deep: 0xA7A9B5, light: ofDay });

// The dark appearance's keyframes, hushed the way the light ones are: each
// colour keeps its hue at two fifths of its chroma (OKLCH) and sits 12 %
// nearer black than the full-strength palette it came from. It falls away to
// black by the middle of the screen, and below the zenith every tone is under
// a card's own grey. Night is the deepest, close to the night ink; sunset and
// sunrise carry the twilight violet and mauve. (The sun's own disc colours
// are the full palette's: it is a light, not ground.)
const darkDawn = makeLook({
  top: 0x1D1E29, mid: 0x161316, sun: 0xC99A88, core: 0xF2E2D8,
  warm: 0x2A2426, haze: 0x100E11, mist: 0x2C272A, mistAlpha: 0.32,
  hills: [0x141216, 0x100E12, 0x0C0B0D, 0x080709],
  deep: 0x050405, light: ofDawn });
const darkMorning = makeLook({
  top: 0x191E28, mid: 0x111319, sun: 0xCFC6A2, core: 0xF2EEDF,
  warm: 0x212328, haze: 0x0D0E11, mist: 0x24282B, mistAlpha: 0.3,
  hills: [0x121415, 0x0F1112, 0x0B0D0E, 0x070909],
  deep: 0x040505, light: ofDay });
const darkNoon = makeLook({
  top: 0x1D232F, mid: 0x12151B, sun: 0xD6CFAE, core: 0xF5F2E6,
  warm: 0x23252B, haze: 0x0D0F12, mist: 0x252A2D, mistAlpha: 0.3,
  hills: [0x131516, 0x101213, 0x0C0E0E, 0x070909],
  deep: 0x040505, light: ofDay });
const darkDusk = makeLook({
  top: 0x221F31, mid: 0x19141B, sun: 0xC4877A, core: 0xEFD6CB,
  warm: 0x2B2227, haze: 0x110E14, mist: 0x2E2732, mistAlpha: 0.34,
  hills: [0x16131A, 0x120F15, 0x0D0B10, 0x09080B],
  deep: 0x040405, light: ofDusk });
const darkNight = makeLook({
  top: 0x161420, mid: 0x0C0B12, sun: 0xFAF5F0, core: 0xFFFFFF,
  warm: 0x1B1924, haze: 0x09080C, mist: 0x22202E, mistAlpha: 0.3,
  hills: [0x100F17, 0x0C0C12, 0x09080D, 0x060508],
  deep: 0x030204, light: ofDay });

function frames(...pairs) {
  return Object.freeze(pairs.map(([at, frameLook]) => Object.freeze({ at, look: frameLook })));
}

/** The day's looks against its own light: 0 at sunrise, 1 at sunset. */
export const dayFrames = frames([0, dawn], [0.18, morning], [0.5, noon], [0.82, morning], [1, dusk]);
/** The night's: 0 at sunset, 1 at the next sunrise. */
export const nightFrames = frames([0, dusk], [0.12, night], [0.88, night], [1, dawn]);
/** The dark appearance's day and night, on the same clock. */
export const darkDayFrames = frames([0, darkDawn], [0.18, darkMorning], [0.5, darkNoon],
                                    [0.82, darkMorning], [1, darkDusk]);
export const darkNightFrames = frames([0, darkDusk], [0.12, darkNight], [0.88, darkNight], [1, darkDawn]);

/** SkyPalette.look(at:in:). The look `progress` (0–1) of the way through
 *  `frames`, blended between the keyframes either side. */
export function look(progress, inFrames) {
  const p = clamp01(progress);
  for (let index = 0; index < inFrames.length - 1; index += 1) {
    if (p <= inFrames[index + 1].at) {
      const a = inFrames[index];
      const b = inFrames[index + 1];
      const span = b.at - a.at;
      return mixLook(a.look, b.look, span > 0 ? (p - a.at) / span : 0);
    }
  }
  return inFrames[inFrames.length - 1].look;
}

/** Where the sun (or moon) sits, as fractions of the screen: low on the left
 *  as it rises, highest — just peeking over the top edge — at its noon, low
 *  on the right as it sets. */
export function bodyPosition(progress) {
  const p = clamp01(progress);
  return { x: 0.04 + 0.92 * p, y: 0.30 - 0.30 * Math.sin(Math.PI * p) };
}

// ────────────────────────────────────────────────────────────── The scene ──

/** Where the sun neither rises nor sets: a plain 6:45-to-6:15 day. */
export function fallbackDay(date, tzOffsetHours) {
  const tzMs = tzOffsetHours * HOUR_MS;
  const now = typeof date === 'number' ? date : date.getTime();
  // The local day's midnight (Swift: `calendar.startOfDay(for: date)`).
  const start = Math.floor((now + tzMs) / DAY_MS) * DAY_MS - tzMs;
  return { sunrise: new Date(start + 6.75 * HOUR_MS), sunset: new Date(start + 18.25 * HOUR_MS) };
}

/**
 * SkyPalette.scene(at:location:dark:calendar:). Everything one frame of the
 * sky needs.
 *
 * `latitude`/`longitude` null or omitted (Swift's `location: nil`) falls back
 * to the time zone's own meridian at 40°N (`solar.approximateLocation`).
 *
 * The Swift `Scene`'s computed properties are plain fields here:
 *   page             the page colour the sky fades into a little past halfway
 *   cloudStrength    how opaque the clouds and wisps are
 *   moonGlow         the moon's glow, as a fraction of the light appearance's
 *   starStrength     the stars' and glints' brightness, likewise
 *   moonGlowByPhase  how much of the moon's glow shows: a thin crescent barely
 *                    glows, a full moon fully
 *   moonPoolByPhase  the warm pool around the moon at night, by the same rule
 * `cloudOpacity` fades the clouds in after sunrise and out before sunset;
 * `starOpacity` brings the stars out after sunset (`starOpacity(q)`).
 * `moon` is null while the moon is down.
 */
export function scene({ date, latitude, longitude, tzOffsetHours, dark = false }) {
  if (typeof tzOffsetHours !== 'number' || !Number.isFinite(tzOffsetHours)) {
    throw new TypeError('SkyPalette.scene: tzOffsetHours must be a finite number (local = UTC + tzOffsetHours)');
  }
  const place = latitude == null || longitude == null
    ? solar.approximateLocation(tzOffsetHours)
    : { latitude, longitude };
  const day = solar.solarDay(date, place.latitude, place.longitude, tzOffsetHours)
    ?? fallbackDay(date, tzOffsetHours);
  const phase = solar.solarPhase(date, day);
  const isDay = !phase.isNight;
  const isDark = Boolean(dark);
  const moonNow = moon({ date, latitude: place.latitude, longitude: place.longitude, inDaylight: isDay });
  const moonGlow = isDark ? darkMoonGlow : 1;
  const byPhase = 0.35 + 0.65 * (moonNow?.fraction ?? 0);
  const shared = {
    isDark,
    moon: moonNow,
    page: isDark ? darkPage : page,
    cloudStrength: isDark ? darkCloudStrength : cloudStrength,
    moonGlow,
    starStrength: isDark ? darkStarStrength : 1,
    moonGlowByPhase: moonGlow * byPhase,
    moonPoolByPhase: byPhase,
  };
  if (isDay) {
    const p = phase.progress;
    return {
      look: look(p, isDark ? darkDayFrames : dayFrames),
      isNight: false,
      body: bodyPosition(p),
      cloudOpacity: Math.min(1, Math.min(p, 1 - p) / 0.1),
      starOpacity: 0,
      ...shared,
    };
  }
  const q = phase.progress;
  return {
    look: look(q, isDark ? darkNightFrames : nightFrames),
    isNight: true,
    body: bodyPosition(q),
    cloudOpacity: 0,
    starOpacity: starOpacity(q),
    ...shared,
  };
}

// ─────────────────────────────────────────────────────────────── The moon ──

/** How opaque the moon is in the daytime sky. */
export const daytimeMoonOpacity = 0.55;

/**
 * SkyPalette.moon(at:latitude:longitude:inDaylight:). The moon as it is now,
 * for the sky, or null while it is below the horizon.
 *
 *   x, y        where it sits (fractions of the screen): across by how far it
 *               is through its own pass from moonrise to moonset, as the sun
 *               crosses from sunrise to sunset; up by its real altitude
 *               (`altitudeHeight`), so a low winter moon stays low
 *   fraction    the lit fraction of its face: 0 new, 1 full
 *   phase       0 new, 0.25 first quarter, 0.5 full, 0.75 last quarter
 *   rotation    the turn (radians, clockwise on screen) that takes a moon lit
 *               on its right to the bright limb's real angle from the zenith
 *   inDaylight  it is up while the sun is: drawn pale and without its glow
 * …and, for the lab (not in the Swift struct):
 *   altitude      radians above the horizon, refracted (`solar.moonPosition`)
 *   azimuth       radians from north, clockwise
 *   passProgress  0 at moonrise, 1 at moonset (what `x` is laid out from)
 */
export function moon({ date, latitude, longitude, inDaylight }) {
  const progress = solar.moonPassProgress(date, latitude, longitude);
  if (progress === null) return null;
  const illumination = solar.moonIllumination(date);
  const position = solar.moonPosition(date, latitude, longitude);
  const chi = solar.moonBrightLimbZenithAngle(date, latitude, longitude);
  return {
    x: bodyPosition(progress).x,
    y: altitudeHeight(position.altitude),
    fraction: illumination.fraction,
    phase: illumination.phase,
    rotation: brightLimbRotation(chi),
    inDaylight: Boolean(inDaylight),
    altitude: position.altitude,
    azimuth: position.azimuth,
    passProgress: progress,
  };
}

/** The screen height (fraction from the top) for a real altitude: the horizon
 *  where the arc meets it, the zenith at the top edge. */
export function altitudeHeight(altitude) {
  const horizonY = bodyPosition(0).y;
  return horizonY * (1 - clamp01(altitude / (Math.PI / 2)));
}

/** The on-screen turn for a bright limb at zenith angle χ (radians, reckoned
 *  from the zenith towards the east — to the left as you face the moon): the
 *  drawn moon is lit on its right, so it is turned until its right points
 *  along (−sin χ, −cos χ), y down. */
export function brightLimbRotation(chi) {
  return Math.atan2(-Math.cos(chi), -Math.sin(chi));
}

// ────────────────────────────────────────────────────────────────── Hills ──

/** One ridge line: a baseline (fraction of the screen's height up from the
 *  bottom) with three slow waves on it, so it never visibly repeats.
 *  Frequencies are per 466 pt — the Duo's outer display — so a wider screen
 *  shows more hills rather than stretched ones. `blur` is its softening, in
 *  points: more for the far ridges. */
function makeRidge(base, amplitude, frequencies, phases, blur) {
  const y = (x, height) => {
    const k = 2 * Math.PI * x / 466;
    const wave = 0.55 * Math.sin(k * frequencies[0] + phases[0])
      + 0.17 * Math.sin(k * frequencies[1] + phases[1])
      + 0.45 * Math.sin(k * frequencies[2] + phases[2]);
    return height - base * height + amplitude * height * wave;
  };
  return deepFreeze({
    base, amplitude, frequencies, phases, blur,
    /** The ridge line's y at `x` (points, in the ridge's own x). */
    y,
    baseline: (height) => height - base * height,
    /** Where the crest colour starts (just under the highest crests). */
    crestTop: (height) => height - base * height - amplitude * height * 0.8,
    /** Samples every 10 pt, from just past the left edge (−30) to just past
     *  the right (width + 30). `xOffset` is where the ridge's own x = 0 sits:
     *  a sky beside another runs the other's ridges on rather than starting
     *  its own. */
    points: (width, height, xOffset = 0) => {
      const points = [];
      // Swift's `stride(from: -30, through: width + 30, by: 10)`: each sample
      // is start + n × step, never an accumulated sum.
      for (let n = 0; ; n += 1) {
        const x = -30 + n * 10;
        if (x > width + 30) break;
        points.push({ x, y: y(x - xOffset, height) });
      }
      return points;
    },
  });
}

/** Back to front. */
export const ridges = Object.freeze([
  makeRidge(0.245, 0.022, [0.9, 2.3, 0.31], [0.6, 2.1, 0.9], 3.2),
  makeRidge(0.195, 0.024, [0.75, 1.9, 0.38], [2.4, 0.3, 2.6], 2.2),
  makeRidge(0.14, 0.022, [1.1, 2.6, 0.45], [4.1, 1.2, 4.3], 1.5),
  makeRidge(0.078, 0.016, [0.6, 1.7, 0.52], [1.3, 3.3, 6.0], 1.0),
]);

// ───────────────────────────────────────────────────────────────── Clouds ──

/** The cloud textures, each in its three lightings (asset names in
 *  TwoOfUs/Assets.xcassets/Sky), and its height over its width. */
export const cloudArt = deepFreeze([
  { dawn: 'SkyCloud1Dawn', day: 'SkyCloud1Day', dusk: 'SkyCloud1Dusk', aspect: 388.0 / 700 },
  { dawn: 'SkyCloud2Dawn', day: 'SkyCloud2Day', dusk: 'SkyCloud2Dusk', aspect: 312.0 / 500 },
  { dawn: 'SkyCloud3Dawn', day: 'SkyCloud3Day', dusk: 'SkyCloud3Dusk', aspect: 312.0 / 800 },
]);
export const wispArt = deepFreeze(
  { dawn: 'SkyWispDawn', day: 'SkyWispDay', dusk: 'SkyWispDusk', aspect: 150.0 / 800 });

/** Wider than this (the Duo open, an iPad) the sky gets the wide layout. */
export const wideLayoutWidth = 700;

// A cloud: which texture (`art`, an index into `cloudArt`), where its flat
// base sits (`x`, `y`: fractions of the screen), how wide (points), and
// whether it is mirrored.
const wideClouds = deepFreeze([
  { art: 0, x: 0.885, y: 0.27, width: 210, flipped: false },
  { art: 1, x: 0.515, y: 0.12, width: 130, flipped: true },
  { art: 2, x: 0.06, y: 0.44, width: 240, flipped: false },
  { art: 1, x: 0.035, y: 0.13, width: 120, flipped: false },
]);
const phoneClouds = deepFreeze([
  { art: 0, x: 0.9, y: 0.27, width: 200, flipped: false },
  { art: 1, x: 0.66, y: 0.095, width: 132, flipped: true },
]);

// A wisp: its centre (fractions of the screen), width (points), and opacity.
const wideWisps = deepFreeze([
  { x: 0.27, y: 0.05, width: 340, alpha: 0.55 },
  { x: 0.5, y: 0.42, width: 220, alpha: 0.45 },
  { x: 0.93, y: 0.5, width: 200, alpha: 0.45 },
]);
const phoneWisps = deepFreeze([
  { x: 0.26, y: 0.045, width: 300, alpha: 0.5 },
  { x: 0.92, y: 0.43, width: 190, alpha: 0.5 },
]);

/** Placed where the screen's own sky shows: beside the column of cards and
 *  behind the header on a phone; in the margins and between the pages on the
 *  open Duo. → [{ art, x, y, width, flipped }] */
export function clouds(wide) {
  return wide ? wideClouds : phoneClouds;
}

/** → [{ x, y, width, alpha }] */
export function wisps(wide) {
  return wide ? wideWisps : phoneWisps;
}

// ────────────────────────────────────────────────────────────────── Stars ──

/** How much of the starfield shows, `q` (night progress) 0 at sunset to 1 at
 *  sunrise: none for the first ~20 minutes, all of it about an hour after
 *  sunset (as the sky darkens), and gone again by sunrise. */
export function starOpacity(q) {
  const rise = (q - 0.02) / 0.06;
  const fall = (0.98 - q) / 0.06;
  return Math.min(1, Math.max(0, Math.min(rise, fall)));
}

/**
 * Fixed stars (the same every frame, so they never jump), in the top 36 % of
 * the sky, thinning and dimming towards the horizon; about 24 across a phone,
 * more across a wider screen.
 *
 * A star: where (`x`, `y`: fractions of the screen), how big (`size`,
 * points), how bright (`alpha`), and — for the two in three that twinkle —
 * how long one twinkle takes (`period`, seconds) and where in it the star
 * starts (`phase`, a fraction of the period).
 * → [{ x, y, size, alpha, twinkles, period, phase }]
 */
export function stars(width) {
  // The Swift's Lehmer generator on a UInt64. Exact in a double too: the
  // seed stays under 2^31, so seed × 16807 stays under 2^46.
  let seed = 7;
  const next = () => {
    seed = (seed * 16807) % 2_147_483_647;
    return (seed - 1) / 2_147_483_646;
  };
  const count = Math.max(8, Math.round(24 * width / 466));
  const result = [];
  for (let n = 0; n < count; n += 1) {
    const depth = Math.pow(next(), 1.4);
    const size = 0.9 + next() * 1.6;
    const x = next();
    const alpha = (0.45 + next() * 0.5) * (1 - 0.55 * depth);
    const period = 2.4 + next() * 2.8;
    const twinkles = next() < 0.65;
    const phase = twinkles ? next() : 0;
    result.push({ x, y: depth * 0.36, size, alpha, twinkles, period, phase });
  }
  return result;
}

/** A star's brightness at `time` (seconds, any epoch), as a fraction of its
 *  own: a slow swell between 22 % and full; 1 for the steady ones. */
export function twinkle(star, time) {
  if (!star.twinkles || !(star.period > 0)) return 1;
  return 0.61 + 0.39 * Math.cos(2 * Math.PI * (time / star.period + star.phase));
}

/** The glints' warm white. */
export const glintColor = deepFreeze(rgb(0xFFFBF2));

const wideGlintSpots = [
  { x: 0.035, y: 0.22, size: 17 }, { x: 0.07, y: 0.62, size: 13 }, { x: 0.49, y: 0.1, size: 16 },
  { x: 0.505, y: 0.47, size: 12 }, { x: 0.935, y: 0.32, size: 14 }, { x: 0.965, y: 0.07, size: 18 },
  { x: 0.27, y: 0.035, size: 13 },
];
const phoneGlintSpots = [
  { x: 0.93, y: 0.07, size: 17 }, { x: 0.84, y: 0.3, size: 13 }, { x: 0.6, y: 0.115, size: 14 },
  { x: 0.965, y: 0.5, size: 12 }, { x: 0.03, y: 0.42, size: 12 },
];

/**
 * The brighter four-point glints, where the screen's own sky shows: beside
 * the cards and behind the header on a phone; the margins and between the
 * pages on the open Duo.
 *
 * A glint: its centre (fractions of the screen), its size (points), and its
 * slow pulse (`period` in seconds, starting `phase`).
 * → [{ x, y, size, period, phase }]
 */
export function glints(wide) {
  const spots = wide ? wideGlintSpots : phoneGlintSpots;
  return spots.map((spot, index) => {
    const period = 3.6 + (index % 3) * 1.1;
    const phase = ((index * 1.37) % period) / period;
    return { x: spot.x, y: spot.y, size: spot.size, period, phase };
  });
}

/** How open a glint is at `time` (seconds, any epoch): 0 at rest (small, dim,
 *  upright), 1 at full sparkle (full size and brightness, turned 25°). */
export function sparkle(glint, time) {
  if (!(glint.period > 0)) return 0;
  return 0.5 - 0.5 * Math.cos(2 * Math.PI * (time / glint.period + glint.phase));
}

// ─────────────────────────────────────────────────────────────── The enum ──

/** `enum SkyPalette`, member for member. */
export const SkyPalette = {
  page, darkPage,
  glow, cloudStrength, darkCloudStrength, darkMoonGlow, darkStarStrength, daytimeMoonOpacity,
  dayFrames, nightFrames, darkDayFrames, darkNightFrames,
  look, bodyPosition,
  scene, fallbackDay,
  moon, altitudeHeight, brightLimbRotation,
  ridges,
  cloudArt, wispArt, wideLayoutWidth, clouds, wisps,
  starOpacity, stars, twinkle, glintColor, glints, sparkle,
  // The colour helpers, here too.
  rgb, mix, css,
};
// So `const { SkyPalette, rgb } = x` works whether `x` is this module or the
// enum itself. Not enumerable: it stays out of loops and JSON.
Object.defineProperty(SkyPalette, 'SkyPalette', { value: SkyPalette, enumerable: false });
Object.freeze(SkyPalette);
