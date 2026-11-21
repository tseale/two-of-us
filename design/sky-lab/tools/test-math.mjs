#!/usr/bin/env node
// Sky lab — checks for lab/solar.js, lab/palette.js and the numbers in skies/baseline.js.
//
//     node design/sky-lab/tools/test-math.mjs
//
// Plain node, no dependencies; exits non-zero when anything fails.
//
// 1. The reference checks of TwoOfUsTests/SolarClockTests.swift,
//    MoonClockTests.swift and SkyPaletteTests.swift, ported one for one (the
//    Swift test's name is in each title). Not ported: MoonPhaseShape's test —
//    the shape is a view, not part of SkyPalette (skies/baseline.js draws it).
// 2. Checks for what the lab adds: `sunPosition`, the from-north azimuths,
//    the Moon's extra fields, the plain-field Scene, `css`.
// 3. The port against the Swift source itself: the keyframe tables, ridges,
//    cloud / wisp / glint placements and constants are read out of
//    SkyBackground.swift and compared, and the numbers in each formula are
//    compared with the numbers in the Swift's — so a typo here, or a later
//    change there, fails loudly. (Skipped when the Swift isn't beside the lab.)
// 4. The DRAWING — skies/baseline.js against `SkyScene`, `StarField` and the
//    three shapes, layer by layer: every stop, alpha, size and blur in each
//    Swift function is in its twin, the gradients' stops in the same order,
//    and the sun's worked-out halo is the Gaussian blur it stands for. (What
//    the canvas then makes of those calls is checked by eye and by pixel, in
//    a browser — not here.)
// 5. What the viewer adds to the state (lab/core.js): `sun.x` (equal to the
//    baseline's rule by day, continuous through sunset and sunrise),
//    `tonightLit` against the chrome's sample night, `snowfall` through the URL
//    and through lab/season.js, the layout's stand-in.

import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import * as solar from '../lab/solar.js';
import * as palette from '../lab/palette.js';
import * as core from '../lab/core.js';
import { season, forceSnowfall } from '../lab/season.js';
import { sampleNight } from '../lab/chrome.js';
import { sunHalo } from '../skies/baseline.js';

const { SkyPalette, rgb, mix, css } = palette;
const DEG = Math.PI / 180;

// ──────────────────────────────────────────────────────────────── Harness ──

let testCount = 0;
let checkCount = 0;
const failedTests = [];
let problems = [];

function ok(condition, message) {
  checkCount += 1;
  if (!condition) problems.push(message);
}

function near(actual, expected, accuracy, message = '') {
  const good = typeof actual === 'number' && Math.abs(actual - expected) <= accuracy;
  ok(good, `${message ? `${message}: ` : ''}got ${actual}, expected ${expected} ± ${accuracy}`);
}

function equal(actual, expected, message = '') {
  ok(Object.is(actual, expected) || actual === expected,
     `${message ? `${message}: ` : ''}got ${JSON.stringify(actual)}, expected ${JSON.stringify(expected)}`);
}

function same(actual, expected, message = '') {
  ok(JSON.stringify(actual) === JSON.stringify(expected),
     `${message ? `${message}: ` : ''}got ${JSON.stringify(actual)}, expected ${JSON.stringify(expected)}`);
}

/** XCTUnwrap: stops the test when the value is missing. */
function unwrap(value, message = 'expected a value') {
  checkCount += 1;
  if (value === null || value === undefined) throw new Error(`${message}: got ${value}`);
  return value;
}

function test(name, body) {
  testCount += 1;
  problems = [];
  let note = '';
  try {
    note = body() ?? '';
  } catch (error) {
    problems.push(error instanceof Error ? (error.stack ?? error.message) : String(error));
  }
  if (problems.length > 0) {
    failedTests.push(name);
    console.log(`FAIL  ${name}`);
    for (const problem of problems) console.log(`        ${problem.split('\n').join('\n        ')}`);
  } else {
    console.log(`ok    ${name}${note ? `  — ${note}` : ''}`);
  }
}

function section(title) {
  console.log(`\n${title}`);
}

// ──────────────────────────────────────────────────────────────── Helpers ──

function utc(text) {
  const date = new Date(text);
  if (Number.isNaN(date.getTime())) throw new Error(`bad date ${text}`);
  return date;
}

/** A local wall-clock time as an instant, for a zone at `tz` hours from UTC. */
function local(tz, y, m, d, h = 12, min = 0) {
  return new Date(Date.UTC(y, m - 1, d, h, min) - tz * 3_600_000);
}

/** Minutes past local midnight, by the clock's hour and minute. */
function clockMinutes(date, tz) {
  const dayMs = 86_400_000;
  const localMs = ((date.getTime() + tz * 3_600_000) % dayMs + dayMs) % dayMs;
  return Math.floor(localMs / 60_000);
}

function assertClock(actual, tz, hour, minute, message, tolerance = 5) {
  near(clockMinutes(actual, tz), hour * 60 + minute, tolerance, `${message} (minutes past midnight)`);
}

function assertRGB(a, b, message = 'colour') {
  near(a.r, b.r, 0.0001, `${message} red`);
  near(a.g, b.g, 0.0001, `${message} green`);
  near(a.b, b.b, 0.0001, `${message} blue`);
}

function luminance(c) {
  return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
}

/** The signed difference between two angles, in (−PI, PI]. */
function angleBetween(a, b) {
  let d = (a - b) % (2 * Math.PI);
  if (d > Math.PI) d -= 2 * Math.PI;
  if (d <= -Math.PI) d += 2 * Math.PI;
  return d;
}

const EST = -5;
const EDT = -4;
const CST = -6;
const chicago = { latitude: 41.9, longitude: -87.6 };

// ═════════════════════════════════════════════════ SolarClockTests.swift ══
section('SolarClock (lab/solar.js) — SolarClockTests.swift');

test('testNewYorkInNovember', () => {
  // Nov 13, 2026: sunrise ≈ 6:41 AM, sunset ≈ 4:40 PM (EST).
  const day = unwrap(solar.solarDay(local(EST, 2026, 11, 13), 40.71, -74.01, EST));
  assertClock(day.sunrise, EST, 6, 41, 'sunrise');
  assertClock(day.sunset, EST, 16, 40, 'sunset');
});

test('testNewYorkAtMidsummer', () => {
  // Jun 21, 2026: sunrise ≈ 5:25 AM, sunset ≈ 8:31 PM (EDT).
  const day = unwrap(solar.solarDay(local(EDT, 2026, 6, 21), 40.71, -74.01, EDT));
  assertClock(day.sunrise, EDT, 5, 25, 'sunrise');
  assertClock(day.sunset, EDT, 20, 31, 'sunset');
});

test('testThePolarNightHasNoSunrise', () => {
  equal(solar.solarDay(local(EST, 2026, 12, 21), 80, 15, EST), null);
});

test('testPhases', () => {
  const day = { sunrise: local(EST, 2026, 11, 13, 7), sunset: local(EST, 2026, 11, 13, 17) };
  same(solar.solarPhase(local(EST, 2026, 11, 13, 12), day), { isNight: false, progress: 0.5 });
  same(solar.solarPhase(local(EST, 2026, 11, 13, 7), day), { isNight: false, progress: 0 });
  // A 10-hour day leaves a 14-hour night: 7 PM is 2/14 through it…
  const evening = solar.solarPhase(local(EST, 2026, 11, 13, 19), day);
  equal(evening.isNight, true, 'evening is night');
  near(evening.progress, 2.0 / 14, 0.0001, 'evening');
  // …and 5 AM is 2 hours short of sunrise.
  const early = solar.solarPhase(local(EST, 2026, 11, 13, 5), day);
  equal(early.isNight, true, 'early morning is night');
  near(early.progress, 12.0 / 14, 0.0001, 'early');
});

test('testTheApproximateLocationIsTheTimeZonesMeridian', () => {
  // The Swift takes New York's STANDARD offset in July; here the caller does.
  const east = solar.approximateLocation(EST);
  near(east.longitude, -75, 0.001, 'longitude');
  near(east.latitude, 40, 0.001, 'latitude');
});

test('the solar day is the LOCAL calendar day, whatever the instant', () => {
  // 11:30 PM and 12:30 AM local are different days, though one UTC day apart
  // the other way round in Chicago; every instant of a local day gives the
  // same sunrise.
  const lateEvening = solar.solarDay(local(CST, 2026, 11, 21, 23, 30), 41.88, -87.63, CST);
  const justAfter = solar.solarDay(local(CST, 2026, 11, 22, 0, 30), 41.88, -87.63, CST);
  const morning = solar.solarDay(local(CST, 2026, 11, 21, 0, 5), 41.88, -87.63, CST);
  equal(lateEvening.sunrise.getTime(), morning.sunrise.getTime(), 'same day, same sunrise');
  near(justAfter.sunrise.getTime() - lateEvening.sunrise.getTime(), 86_400_000, 120_000, 'the next day');
  // Chicago, Nov 21, 2026: sunrise ≈ 6:47 AM, sunset ≈ 4:25 PM (CST).
  assertClock(morning.sunrise, CST, 6, 47, 'Chicago sunrise');
  assertClock(morning.sunset, CST, 16, 25, 'Chicago sunset');
  // East of Greenwich the local day starts in the UTC day before.
  const tokyo = solar.solarDay(local(9, 2026, 11, 21, 0, 30), 35.68, 139.69, 9);
  assertClock(tokyo.sunrise, 9, 6, 22, 'Tokyo sunrise');
  assertClock(tokyo.sunset, 9, 16, 31, 'Tokyo sunset');
  ok(tokyo.sunrise > local(9, 2026, 11, 21, 0, 30), 'that local day\'s sunrise, not the day before\'s');
});

// ══════════════════════════════════════════════════ MoonClockTests.swift ══
section('MoonClock (lab/solar.js) — MoonClockTests.swift');

test('testPositionMatchesTheReference', () => {
  // SunCalc's own reference case: 2013-03-05 00:00 UTC at 50.5° N, 30.5° E.
  const position = solar.moonPosition(utc('2013-03-05T00:00:00Z'), 50.5, 30.5);
  // MoonClock's azimuth is from south, westward; the lab's is that plus PI.
  near(position.azimuth - Math.PI, -0.9783999522438226, 1e-9, 'azimuth (MoonClock\'s convention)');
  near(position.azimuth, Math.PI - 0.9783999522438226, 1e-9, 'azimuth (from north, clockwise)');
  near(position.altitude, 0.014551482243892251, 1e-9, 'altitude');
  near(position.distance, 364121.37256256194, 1e-3, 'distance');
});

test('testIlluminationMatchesTheReference', () => {
  const light = solar.moonIllumination(utc('2013-03-05T00:00:00Z'));
  near(light.fraction, 0.4848068202456373, 1e-9, 'fraction');
  near(light.phase, 0.7548368838538762, 1e-9, 'phase');
  near(light.angle, 1.6732942678578346, 1e-9, 'angle');
});

test('testPhaseAtKnownNewAndFullMoons', () => {
  const eclipse = solar.moonIllumination(utc('2024-04-08T18:21:00Z'));
  ok(eclipse.fraction < 0.002, `the April 2024 eclipse: new moon (got ${eclipse.fraction})`);
  const full = solar.moonIllumination(utc('2024-09-18T02:34:00Z'));
  ok(full.fraction > 0.999, `the September 2024 full moon (got ${full.fraction})`);
  near(full.phase, 0.5, 0.01, 'full phase');
});

test('testRiseAndSetMatchTheReference', () => {
  // SunCalc's reference moon times for 2013-03-04 at the same place: rise
  // 23:54:29, set 07:47:58 UTC. Bisection lands within a minute.
  // Up at 05:00: it rose the evening before and sets at 07:47.
  const morning = unwrap(solar.moonPass(utc('2013-03-04T05:00:00Z'), 50.5, 30.5));
  const set = unwrap(morning.set, 'a set');
  near((set - utc('2013-03-04T07:47:58Z')) / 1000, 0, 60, 'set (seconds off)');
  // Up at 03:00 the next morning: it rose at 23:54.
  const night = unwrap(solar.moonPass(utc('2013-03-05T03:00:00Z'), 50.5, 30.5));
  const rise = unwrap(night.rise, 'a rise');
  near((rise - utc('2013-03-04T23:54:29Z')) / 1000, 0, 60, 'rise (seconds off)');
  ok(rise instanceof Date && set instanceof Date, 'rise and set are Dates');
});

test('testThereIsNoPassWhileTheMoonIsDown', () => {
  // Midnight in Chicago, 2026-11-15: a young crescent set hours ago.
  equal(solar.moonPass(utc('2026-11-15T06:00:00Z'), 41.9, -87.6), null, 'pass');
  equal(solar.moonPassProgress(utc('2026-11-15T06:00:00Z'), 41.9, -87.6), null, 'progress');
});

test('testAnEveningCrescent', () => {
  // Dusk in Chicago, 2026-11-14 (6:16 PM CST): a waxing crescent, about 28 %
  // lit, low in the south-west three quarters of the way through its pass
  // (it rose at 11:29 AM and sets at 8:47 PM), lit low on its right.
  const date = utc('2026-11-15T00:16:00Z');
  const light = solar.moonIllumination(date);
  near(light.fraction, 0.28, 0.01, 'fraction');
  ok(light.phase < 0.25, `waxing (phase ${light.phase})`);
  const progress = unwrap(solar.moonPassProgress(date, 41.9, -87.6));
  near(progress, 0.729, 0.01, 'progress');
  const chi = solar.moonBrightLimbZenithAngle(date, 41.9, -87.6);
  const rotation = SkyPalette.brightLimbRotation(chi);
  near(rotation / DEG, 34, 2, 'lit on its right, turned down towards the sunset (degrees)');
  // The comment's own times, and its "low in the south-west".
  const pass = unwrap(solar.moonPass(date, 41.9, -87.6));
  assertClock(unwrap(pass.rise), CST, 11, 29, 'moonrise', 2);
  assertClock(unwrap(pass.set), CST, 20, 47, 'moonset', 2);
  const position = solar.moonPosition(date, 41.9, -87.6);
  ok(position.azimuth > Math.PI && position.azimuth < 1.5 * Math.PI,
     `south-west is between PI and 3PI/2 from north (got ${position.azimuth})`);
  ok(position.altitude > 0 && position.altitude < 30 * DEG, `low (got ${position.altitude / DEG}°)`);
});

test('testBrightLimbRotationPointsTheLitSideAlongTheLimb', () => {
  // χ = −90° (bright limb due west, to the right): no turn.
  near(SkyPalette.brightLimbRotation(-Math.PI / 2), 0, 1e-9);
  // χ = 0 (bright limb straight up): the right side turned to the top.
  near(SkyPalette.brightLimbRotation(0), -Math.PI / 2, 1e-9);
  // χ = 90° (to the left, east): turned half way round.
  near(Math.abs(SkyPalette.brightLimbRotation(Math.PI / 2)), Math.PI, 1e-9);
});

// ═════════════════════════════════════════════════════ The lab's own sun ══
section('sunPosition and the lab\'s conventions (lab/solar.js)');

test('sunPosition is SunCalc\'s getPosition (its own reference case)', () => {
  // SunCalc's test suite: 2013-03-05 00:00 UTC at 50.5° N, 30.5° E →
  // azimuth −2.5003175907168385 (from south), altitude −0.7000406838781611.
  const sun = solar.sunPosition(utc('2013-03-05T00:00:00Z'), 50.5, 30.5);
  near(angleBetween(sun.azimuth - Math.PI, -2.5003175907168385), 0, 1e-9, 'azimuth');
  near(sun.altitude, -0.7000406838781611, 1e-9, 'altitude');
  ok(sun.azimuth >= 0 && sun.azimuth < 2 * Math.PI, 'azimuth in [0, 2PI)');
});

test('at solarDay\'s sunrise and sunset the sun is at about −0.83°', () => {
  // Two different series (NOAA for the times, SunCalc's for the place) must
  // agree: the centre 0.833° below the horizon, to well within a degree.
  const places = [
    { name: 'Chicago', latitude: 41.88, longitude: -87.63, tz: -6 },
    { name: 'New York', latitude: 40.71, longitude: -74.01, tz: -5 },
    { name: 'Quito', latitude: -0.18, longitude: -78.47, tz: -5 },
    { name: 'Tokyo', latitude: 35.68, longitude: 139.69, tz: 9 },
    { name: 'Sydney', latitude: -33.87, longitude: 151.21, tz: 10 },
    { name: 'Edinburgh', latitude: 55.95, longitude: -3.19, tz: 0 },
  ];
  let worst = 0;
  let count = 0;
  for (const place of places) {
    for (let month = 1; month <= 12; month += 1) {
      for (const dayOfMonth of [6, 21]) {
        const noon = local(place.tz, 2026, month, dayOfMonth);
        const day = unwrap(solar.solarDay(noon, place.latitude, place.longitude, place.tz));
        for (const [which, instant] of [['sunrise', day.sunrise], ['sunset', day.sunset]]) {
          const altitude = solar.sunPosition(instant, place.latitude, place.longitude).altitude / DEG;
          worst = Math.max(worst, Math.abs(altitude + 0.833));
          count += 1;
          near(altitude, -0.833, 1, `${place.name} 2026-${month}-${dayOfMonth} ${which} altitude (degrees)`);
        }
      }
    }
  }
  return `${count} sunrises and sunsets, worst ${worst.toFixed(3)}° from −0.833°`;
});

test('the sun rises in the east, is due south at solar noon, sets in the west', () => {
  // A northern mid-latitude (the lab's default place).
  const latitude = 41.88;
  const longitude = -87.63;
  let worstNoon = 0;
  for (let month = 1; month <= 12; month += 1) {
    const day = unwrap(solar.solarDay(local(CST, 2026, month, 21), latitude, longitude, CST));
    const solarNoon = new Date((day.sunrise.getTime() + day.sunset.getTime()) / 2);
    const rise = solar.sunPosition(day.sunrise, latitude, longitude);
    const noon = solar.sunPosition(solarNoon, latitude, longitude);
    const set = solar.sunPosition(day.sunset, latitude, longitude);
    worstNoon = Math.max(worstNoon, Math.abs(noon.azimuth - Math.PI) / DEG);
    near(noon.azimuth / DEG, 180, 2, `month ${month}: azimuth at solar noon (degrees)`);
    ok(rise.azimuth > 0 && rise.azimuth < Math.PI, `month ${month}: rises in the eastern half (${rise.azimuth / DEG}°)`);
    ok(set.azimuth > Math.PI && set.azimuth < 2 * Math.PI, `month ${month}: sets in the western half (${set.azimuth / DEG}°)`);
    near(rise.azimuth + set.azimuth, 2 * Math.PI, 2 * DEG, `month ${month}: rise and set mirror each other about south`);
    ok(noon.altitude > rise.altitude && noon.altitude > set.altitude, `month ${month}: highest at noon`);
    // Its noon height is 90° − latitude + declination: 24.7°…71.6° here.
    ok(noon.altitude / DEG > 24 && noon.altitude / DEG < 72.5, `month ${month}: noon altitude ${noon.altitude / DEG}°`);
  }
  // The equinox: due east and due west; the solstices: 71.6° and 24.7° up.
  const equinox = unwrap(solar.solarDay(local(CST, 2026, 3, 20), latitude, longitude, CST));
  near(solar.sunPosition(equinox.sunrise, latitude, longitude).azimuth / DEG, 90, 2, 'equinox sunrise azimuth');
  near(solar.sunPosition(equinox.sunset, latitude, longitude).azimuth / DEG, 270, 2, 'equinox sunset azimuth');
  const noonOf = (month, d) => {
    const day = solar.solarDay(local(CST, 2026, month, d), latitude, longitude, CST);
    return solar.sunPosition(new Date((day.sunrise.getTime() + day.sunset.getTime()) / 2), latitude, longitude);
  };
  near(noonOf(6, 21).altitude / DEG, 90 - latitude + 23.44, 0.3, 'midsummer noon altitude');
  near(noonOf(12, 21).altitude / DEG, 90 - latitude - 23.44, 0.3, 'midwinter noon altitude');
  return `solar-noon azimuth within ${worstNoon.toFixed(2)}° of south all year`;
});

test('the sun is below the horizon exactly when solarPhase says night', () => {
  const latitude = 41.88;
  const longitude = -87.63;
  let disagreements = 0;
  for (let minute = 0; minute < 24 * 60; minute += 7) {
    const instant = new Date(local(CST, 2026, 11, 21, 0, 0).getTime() + minute * 60_000);
    const day = solar.solarDay(instant, latitude, longitude, CST);
    const phase = solar.solarPhase(instant, day);
    const sun = solar.sunPosition(instant, latitude, longitude);
    ok(sun.azimuth >= 0 && sun.azimuth < 2 * Math.PI, 'azimuth in [0, 2PI)');
    ok(phase.progress >= 0 && phase.progress <= 1, 'progress in 0…1');
    // Away from the two crossings themselves (a couple of minutes' slack).
    const clear = Math.abs(sun.altitude / DEG + 0.833) > 0.6;
    if (clear && (sun.altitude / DEG < -0.833) !== phase.isNight) disagreements += 1;
  }
  equal(disagreements, 0, 'altitude and phase disagree');
});

test('moonPass brackets the moment, at the horizon, and passProgress follows it', () => {
  const date = utc('2026-11-21T22:10:00Z');   // the lab's default instant
  const pass = unwrap(solar.moonPass(date, 41.88, -87.63));
  const rise = unwrap(pass.rise);
  const set = unwrap(pass.set);
  ok(rise < date && date < set, 'rose before, sets after');
  for (const [which, instant] of [['rise', rise], ['set', set]]) {
    near(solar.moonPosition(instant, 41.88, -87.63).altitude / DEG, 0.133, 0.01, `altitude at ${which} (degrees)`);
  }
  const progress = unwrap(solar.moonPassProgress(date, 41.88, -87.63));
  near(progress, (date - rise) / (set - rise), 1e-6, 'progress');
  near(solar.moonPassProgress(new Date(rise.getTime() + 60_000), 41.88, -87.63), 0, 0.01, 'just after rising');
  near(solar.moonPassProgress(new Date(set.getTime() - 60_000), 41.88, -87.63), 1, 0.01, 'just before setting');
  equal(solar.moonPassProgress(new Date(set.getTime() + 600_000), 41.88, -87.63), null, 'after setting');
});

test('solar.js exports exactly the contract', () => {
  same(Object.keys(solar).sort(), ['approximateLocation', 'moonBrightLimbZenithAngle', 'moonIllumination',
                                   'moonPass', 'moonPassProgress', 'moonPosition', 'solarDay', 'solarPhase',
                                   'sunPosition']);
  same(Object.keys(solar.sunPosition(utc('2026-11-21T22:10:00Z'), 41.88, -87.63)), ['altitude', 'azimuth']);
  same(Object.keys(solar.moonPosition(utc('2026-11-21T22:10:00Z'), 41.88, -87.63)),
       ['altitude', 'azimuth', 'distance', 'parallacticAngle']);
  same(Object.keys(solar.moonIllumination(utc('2026-11-21T22:10:00Z'))), ['fraction', 'phase', 'angle']);
  let threw = false;
  try { solar.solarDay(utc('2026-11-21T22:10:00Z'), 41.88, -87.63); } catch { threw = true; }
  ok(threw, 'solarDay without a tzOffsetHours throws rather than guess a zone');
});

// ════════════════════════════════════════════════ SkyPaletteTests.swift ══
section('SkyPalette (lab/palette.js) — SkyPaletteTests.swift');

test('testTheSunRisesLowOnTheLeftAndSetsLowOnTheRight', () => {
  const rise = SkyPalette.bodyPosition(0);
  const noon = SkyPalette.bodyPosition(0.5);
  const set = SkyPalette.bodyPosition(1);
  near(rise.x, 0.04, 0.0001);
  near(set.x, 0.96, 0.0001);
  near(noon.x, 0.5, 0.0001);
  near(noon.y, 0, 0.0001, 'highest at its noon');
  near(rise.y, 0.30, 0.0001);
  near(set.y, 0.30, 0.0001);
});

test('testSunriseIsWarmMiddayBlueSunsetLavender', () => {
  const rise = SkyPalette.look(0, SkyPalette.dayFrames);
  ok(rise.mid.r > rise.mid.b, 'sunrise mid is warm');
  ok(rise.warm.r > rise.warm.b, 'sunrise pool is warm');
  const noon = SkyPalette.look(0.5, SkyPalette.dayFrames).top;
  ok(noon.b > noon.r, 'noon is blue');
  const set = SkyPalette.look(1, SkyPalette.dayFrames).top;
  ok(set.b > set.g, 'sunset is lavender');
});

test('testMiddayIsTheDeepestBlue', () => {
  const morning = SkyPalette.look(0.25, SkyPalette.dayFrames).top;
  const noon = SkyPalette.look(0.5, SkyPalette.dayFrames).top;
  ok(noon.r < morning.r, 'noon is deeper than morning');
});

test('testTheSkyStaysQuietBehindTheCards', () => {
  for (const frame of SkyPalette.dayFrames) {
    const look = frame.look;
    for (const colour of [look.top, look.mid, look.haze, look.deep, ...look.hills]) {
      const high = Math.max(colour.r, colour.g, colour.b);
      const low = Math.min(colour.r, colour.g, colour.b);
      ok(high - low < 0.12, `barely tinted (frame ${frame.at})`);
      ok(low > 0.75, `light (frame ${frame.at})`);
    }
  }
});

test('testTheNightIsDeeperSoTheStarsShow', () => {
  const night = SkyPalette.look(0.5, SkyPalette.nightFrames).top;
  const day = SkyPalette.look(0.5, SkyPalette.dayFrames).top;
  ok(night.r + night.g + night.b < day.r + day.g + day.b, 'night is deeper');
});

test('testTheNightJoinsTheDayAtBothEnds', () => {
  assertRGB(SkyPalette.look(0, SkyPalette.nightFrames).top, SkyPalette.look(1, SkyPalette.dayFrames).top, 'sunset');
  assertRGB(SkyPalette.look(1, SkyPalette.nightFrames).top, SkyPalette.look(0, SkyPalette.dayFrames).top, 'sunrise');
});

test('testLooksBlendBetweenFrames', () => {
  const a = SkyPalette.look(0, SkyPalette.dayFrames);
  const b = SkyPalette.look(0.18, SkyPalette.dayFrames);
  const mid = SkyPalette.look(0.09, SkyPalette.dayFrames);
  assertRGB(mid.top, mix(a.top, b.top, 0.5), 'top');
  for (let index = 0; index < 4; index += 1) {
    assertRGB(mid.hills[index], mix(a.hills[index], b.hills[index], 0.5), `hill ${index}`);
  }
  near(mid.mistAlpha, (a.mistAlpha + b.mistAlpha) / 2, 0.0001, 'mistAlpha');
});

test('testMixingIsClamped', () => {
  const a = { r: 0, g: 0, b: 0 };
  const b = { r: 1, g: 1, b: 1 };
  assertRGB(mix(a, b, 2), b, 'over');
  assertRGB(mix(a, b, -1), a, 'under');
});

test('testCloudLightingIsAlwaysOneWholeCrossfade', () => {
  for (const frames of [SkyPalette.dayFrames, SkyPalette.nightFrames]) {
    for (let step = 0; step <= 40; step += 1) {
      const light = SkyPalette.look(step / 40, frames).light;
      near(light.dawn + light.day + light.dusk, 1, 0.0001, 'weights sum to one');
      ok(Math.min(light.dawn, light.day, light.dusk) >= 0, 'no negative weight');
    }
  }
  same(SkyPalette.look(0, SkyPalette.dayFrames).light, { dawn: 1, day: 0, dusk: 0 }, 'ofDawn');
  same(SkyPalette.look(0.5, SkyPalette.dayFrames).light, { dawn: 0, day: 1, dusk: 0 }, 'ofDay');
  same(SkyPalette.look(1, SkyPalette.dayFrames).light, { dawn: 0, day: 0, dusk: 1 }, 'ofDusk');
});

test('testEveryLookHasFourHills', () => {
  for (const frames of [SkyPalette.dayFrames, SkyPalette.nightFrames]) {
    for (const frame of frames) equal(frame.look.hills.length, SkyPalette.ridges.length);
  }
});

test('testRidgesStackBackToFrontAlongTheBottom', () => {
  const height = 678.0;
  const ridges = SkyPalette.ridges;
  for (let index = 0; index < ridges.length - 1; index += 1) {
    ok(ridges[index].baseline(height) < ridges[index + 1].baseline(height), `ridge ${index} is behind ${index + 1}`);
    ok(ridges[index].blur > ridges[index + 1].blur, 'the far ridges are the softer');
  }
  // Every crest stays in the bottom third, on a phone and on the open Duo.
  for (const ridge of ridges) {
    for (const point of ridge.points(951, height)) {
      ok(point.y > height * 0.68, `crest below 68 % (${point.y})`);
      ok(point.y < height, `crest above the bottom (${point.y})`);
    }
  }
});

test('testRidgePointsSpanPastBothEdges', () => {
  const points = SkyPalette.ridges[0].points(466, 678);
  ok(points[0].x < 0, 'starts past the left edge');
  ok(points[points.length - 1].x > 466, 'ends past the right edge');
  // Swift's stride(from: -30, through: 496, by: 10): −30, −20, … 490.
  equal(points.length, 53, 'samples');
  equal(points[0].x, -30, 'first');
  equal(points[52].x, 490, 'last');
  equal(SkyPalette.ridges[0].points(470, 678).length, 54, 'through, not to: 500 is included');
});

test('testStarsAreFixedAndHighInTheSky', () => {
  const phone = SkyPalette.stars(466);
  same(phone, SkyPalette.stars(466), 'the same stars every frame');
  equal(phone.length, 24);
  ok(SkyPalette.stars(951).length > phone.length, 'more across a wider screen');
  for (const star of phone) {
    ok(star.x >= 0 && star.x <= 1, 'x');
    ok(star.y >= 0 && star.y <= 0.36, 'y');
    ok(star.alpha >= 0 && star.alpha <= 1, 'alpha');
    ok(star.period >= 2.4 && star.period <= 5.2, 'period');
    ok(star.phase >= 0 && star.phase < 1, 'phase');
  }
  ok(phone.some((star) => star.twinkles), 'most twinkle');
  ok(phone.some((star) => !star.twinkles), 'a few hold steady');
});

test('testStarsComeOutAfterSunsetAndGoBeforeSunrise', () => {
  near(SkyPalette.starOpacity(0), 0, 0.0001);
  near(SkyPalette.starOpacity(0.02), 0, 0.0001);
  near(SkyPalette.starOpacity(0.05), 0.5, 0.0001);
  near(SkyPalette.starOpacity(0.08), 1, 0.0001);
  near(SkyPalette.starOpacity(0.5), 1, 0.0001);
  near(SkyPalette.starOpacity(0.95), 0.5, 0.0001);
  near(SkyPalette.starOpacity(1), 0, 0.0001);
});

test('testATwinkleSwellsBetweenAFifthAndFull', () => {
  const star = { x: 0.5, y: 0.1, size: 2, alpha: 1, twinkles: true, period: 4, phase: 0 };
  near(SkyPalette.twinkle(star, 0), 1, 0.0001);
  near(SkyPalette.twinkle(star, 2), 0.22, 0.0001);
  for (let step = 0; step <= 80; step += 1) {
    const value = SkyPalette.twinkle(star, step / 10);
    ok(value >= 0.2199, 'never under 22 %');
    ok(value <= 1.0001, 'never over full');
  }
  const steady = { ...star, twinkles: false };
  equal(SkyPalette.twinkle(steady, 2), 1);
});

test('testGlintsPulseOnTheirOwnRhythm', () => {
  equal(SkyPalette.glints(false).length, 5);
  equal(SkyPalette.glints(true).length, 7);
  for (const wide of [false, true]) {
    const glints = SkyPalette.glints(wide);
    equal(new Set(glints.map((glint) => glint.phase)).size, glints.length, 'out of step with one another');
    for (const glint of glints) {
      ok(glint.x >= 0 && glint.x <= 1, 'x');
      ok(glint.y >= 0 && glint.y <= 1, 'y');
      for (let step = 0; step <= 40; step += 1) {
        const time = step / 4;
        const value = SkyPalette.sparkle(glint, time);
        ok(value >= -0.0001 && value <= 1.0001, 'sparkle in 0…1');
        near(value, SkyPalette.sparkle(glint, time + glint.period), 0.000001, 'periodic');
      }
    }
  }
});

test('testCloudsUseKnownTextures', () => {
  for (const wide of [false, true]) {
    for (const cloud of SkyPalette.clouds(wide)) {
      ok(Number.isInteger(cloud.art) && cloud.art >= 0 && cloud.art < SkyPalette.cloudArt.length, 'a known texture');
    }
  }
});

test('testTheDarkSkyStaysDeepBehindTheCards', () => {
  for (const frames of [SkyPalette.darkDayFrames, SkyPalette.darkNightFrames]) {
    for (const frame of frames) {
      const look = frame.look;
      for (const colour of [look.top, look.mid, look.haze, look.deep, look.warm, ...look.hills]) {
        ok(luminance(colour) < 0.2, 'deep');
      }
      for (const colour of [look.mid, look.haze, look.deep, ...look.hills]) {
        ok(luminance(colour) < luminance(rgb(0x1C1C1E)), 'under a card\'s own grey');
      }
    }
  }
});

test('testTheDarkNightIsTheDeepestAndPurple', () => {
  const night = SkyPalette.look(0.5, SkyPalette.darkNightFrames).top;
  const noon = SkyPalette.look(0.5, SkyPalette.darkDayFrames).top;
  const dusk = SkyPalette.look(1, SkyPalette.darkDayFrames).top;
  ok(luminance(night) < luminance(noon), 'night under noon');
  ok(luminance(night) < luminance(dusk), 'night under dusk');
  // Twilight and night lean violet: blue first, then red over green.
  for (const colour of [night, dusk]) {
    ok(colour.b > colour.r, 'blue over red');
    ok(colour.r > colour.g, 'red over green');
  }
});

test('testTheDarkNightJoinsTheDarkDayAtBothEnds', () => {
  assertRGB(SkyPalette.look(0, SkyPalette.darkNightFrames).top, SkyPalette.look(1, SkyPalette.darkDayFrames).top, 'sunset');
  assertRGB(SkyPalette.look(1, SkyPalette.darkNightFrames).top, SkyPalette.look(0, SkyPalette.darkDayFrames).top, 'sunrise');
});

test('testDarkLooksHaveFourHillsAndWholeCloudCrossfades', () => {
  for (const frames of [SkyPalette.darkDayFrames, SkyPalette.darkNightFrames]) {
    for (const frame of frames) equal(frame.look.hills.length, SkyPalette.ridges.length);
    for (let step = 0; step <= 40; step += 1) {
      const light = SkyPalette.look(step / 40, frames).light;
      near(light.dawn + light.day + light.dusk, 1, 0.0001, 'weights sum to one');
    }
  }
});

test('testTheDarkSceneFadesToTheBlackPageWithFaintClouds', () => {
  // The Swift uses today's noon; any noon does.
  const noon = local(EST, 2026, 11, 21, 12);
  const at = { date: noon, latitude: 40, longitude: -75, tzOffsetHours: EST };
  const light = SkyPalette.scene(at);
  const dark = SkyPalette.scene({ ...at, dark: true });
  assertRGB(light.page, SkyPalette.page, 'light page');
  assertRGB(dark.page, SkyPalette.darkPage, 'dark page');
  ok(dark.cloudStrength < light.cloudStrength, 'fainter clouds');
  ok(dark.moonGlow < light.moonGlow, 'quieter moon');
  equal(light.isDark, false);
  equal(dark.isDark, true);
  ok(luminance(dark.look.top) < luminance(light.look.top), 'deeper');
});

test('testASkyBesideAnotherRunsItsRidgesOn', () => {
  // The spread's leading sky lays its hills out on the phone page's x, so at
  // the phone page's origin both skies' ridges are at one height.
  const origin = 485.0;
  for (const ridge of SkyPalette.ridges) {
    const leading = ridge.points(951, 669, origin);
    const phone = ridge.points(466, 669);
    for (const point of leading) near(point.y, ridge.y(point.x - origin, 669), 0.0001, 'on the phone page\'s x');
    const atSeam = unwrap(leading.find((point) => Math.abs(point.x - origin - 5) < 0.001), 'a sample at the seam');
    const phoneNearSeam = phone.find((point) => Math.abs(point.x - 5) < 0.001);
    if (phoneNearSeam) near(atSeam.y, phoneNearSeam.y, 0.0001, 'one height at the seam');
    near(atSeam.y, ridge.y(5, 669), 0.0001, 'the seam sample is the phone page\'s x = 5');
  }
});

test('testTheSceneHasTheMoonOnlyWhileItIsUp', () => {
  const place = { ...chicago, tzOffsetHours: CST };
  // 6:16 PM CST, 2026-11-14: the crescent is up in the south-west.
  const dusk = SkyPalette.scene({ date: utc('2026-11-15T00:16:00Z'), ...place, dark: true });
  const moon = unwrap(dusk.moon, 'a moon at dusk');
  near(moon.fraction, 0.28, 0.01, 'fraction');
  ok(moon.x > 0.5, 'past the middle of its arc, towards where it sets');
  equal(moon.inDaylight, false);
  // Midnight: it has set — no moon, no moonlight.
  const midnight = SkyPalette.scene({ date: utc('2026-11-15T06:00:00Z'), ...place, dark: true });
  equal(midnight.moon, null, 'no moon at midnight');
  near(midnight.moonGlowByPhase, midnight.moonGlow * 0.35, 1e-9, 'moonGlowByPhase');
  // Early afternoon: it is up in the daytime sky, drawn pale.
  const afternoon = SkyPalette.scene({ date: utc('2026-11-14T20:00:00Z'), ...place });
  equal(afternoon.moon?.inDaylight, true, 'in daylight');
});

test('testTheMoonSitsAsHighAsItReallyIs', () => {
  // Nov 16 2026, 4:47 PM CST, 40°N 90°W: a near-first-quarter moon about 40 %
  // through its pass but only ~33° up in the south-southeast.
  const date = utc('2026-11-16T22:47:00Z');
  const moon = unwrap(SkyPalette.moon({ date, latitude: 40, longitude: -90, inDaylight: false }));
  near(moon.x, 0.41, 0.03, 'x');
  near(moon.y, 0.30 * (1 - 33.0 / 90), 0.015, 'y');
  near(SkyPalette.altitudeHeight(0), 0.30, 1e-9);
  near(SkyPalette.altitudeHeight(Math.PI / 2), 0, 1e-9);
  near(SkyPalette.altitudeHeight(-0.1), 0.30, 1e-9);
  // The lab's extras say the same thing.
  near(moon.altitude / DEG, 33, 1.5, 'altitude (degrees)');
  ok(moon.azimuth > 135 * DEG && moon.azimuth < 180 * DEG, `south-southeast (got ${moon.azimuth / DEG}°)`);
  near(moon.passProgress, 0.40, 0.03, 'passProgress');
});

test('testTheDarkStarsAndMoonAreQuieter', () => {
  const at = { date: utc('2026-11-15T00:16:00Z'), ...chicago, tzOffsetHours: CST };
  const light = SkyPalette.scene(at);
  const dark = SkyPalette.scene({ ...at, dark: true });
  ok(dark.starStrength < light.starStrength, 'quieter stars');
  ok(dark.moonGlowByPhase < light.moonGlowByPhase, 'quieter glow');
  same(dark.moon, light.moon, 'the same moon');
});

// ════════════════════════════════════════════════ The lab's own palette ══
section('The lab\'s shapes and helpers (lab/palette.js)');

test('rgb, mix and css', () => {
  same(rgb(0xFF8000), { r: 1, g: 128 / 255, b: 0 });
  same(rgb(0x000000), { r: 0, g: 0, b: 0 });
  same(mix(rgb(0x000000), rgb(0xFFFFFF), 0.25), { r: 0.25, g: 0.25, b: 0.25 });
  equal(css(rgb(0xF2F2F7)), 'rgba(242, 242, 247, 1)');
  equal(css(rgb(0xD3D5DF), 0.5), 'rgba(211, 213, 223, 0.5)');
  equal(css({ r: 2, g: -1, b: 0.5 }, 3), 'rgba(255, 0, 128, 1)', 'clamped');
  equal(css(SkyPalette.glintColor, 0), 'rgba(255, 251, 242, 0)');
  // A round trip of every keyframe colour: css() gives back the Swift hex.
  for (const frames of [SkyPalette.dayFrames, SkyPalette.nightFrames, SkyPalette.darkDayFrames, SkyPalette.darkNightFrames]) {
    for (const { look } of frames) {
      for (const colour of [look.top, look.mid, look.sun, look.core, look.warm, look.haze, look.mist, look.deep, ...look.hills]) {
        const [r, g, b] = css(colour).match(/\d+/g).map(Number);
        assertRGB(rgb((r << 16) | (g << 8) | b), colour, 'round trip');
      }
    }
  }
});

test('the star generator is Swift\'s, exactly', () => {
  // The first draws of the Lehmer generator from seed 7, worked by hand:
  // 7 × 16807 = 117649; × 16807 mod (2^31 − 1) = 1977326743; then 621132276.
  const first = SkyPalette.stars(466)[0];
  equal(first.y, Math.pow(117648 / 2147483646, 1.4) * 0.36, 'first star y (draw 1)');
  equal(first.size, 0.9 + (1977326742 / 2147483646) * 1.6, 'first star size (draw 2)');
  equal(first.x, 621132275 / 2147483646, 'first star x (draw 3)');
  // …and every star, against the same generator run in exact integers.
  for (const width of [402, 466, 951, 100, 1366]) {
    let seed = 7n;
    const next = () => {
      seed = (seed * 16807n) % 2147483647n;
      return Number(seed - 1n) / 2147483646;
    };
    const count = Math.max(8, Math.round(24 * width / 466));
    const expected = [];
    for (let n = 0; n < count; n += 1) {
      const depth = Math.pow(next(), 1.4);
      const size = 0.9 + next() * 1.6;
      const x = next();
      const alpha = (0.45 + next() * 0.5) * (1 - 0.55 * depth);
      const period = 2.4 + next() * 2.8;
      const twinkles = next() < 0.65;
      const phase = twinkles ? next() : 0;
      expected.push({ x, y: depth * 0.36, size, alpha, twinkles, period, phase });
    }
    same(SkyPalette.stars(width), expected, `stars(${width})`);
  }
  equal(SkyPalette.stars(402).length, 21, 'iPhone');
  equal(SkyPalette.stars(951).length, 49, 'the spread');
  equal(SkyPalette.stars(100).length, 8, 'never fewer than 8');
});

test('glints have Swift\'s periods and phases', () => {
  // period = 3.6 + (index mod 3) × 1.1; phase = (index × 1.37) mod period / period.
  const glints = SkyPalette.glints(true);
  near(glints[0].period, 3.6, 1e-12);
  near(glints[1].period, 4.7, 1e-12);
  near(glints[2].period, 5.8, 1e-12);
  near(glints[3].period, 3.6, 1e-12);
  equal(glints[0].phase, 0);
  near(glints[1].phase, 1.37 / 4.7, 1e-12);
  near(glints[3].phase, (4.11 - 3.6) / 3.6, 1e-12, 'wraps round its period');
  near(glints[6].phase, (8.22 - 7.2) / 3.6, 1e-12, 'wraps twice');
  near(SkyPalette.sparkle({ period: 4, phase: 0 }, 0), 0, 1e-12, 'at rest');
  near(SkyPalette.sparkle({ period: 4, phase: 0 }, 2), 1, 1e-12, 'full sparkle');
});

test('SkyPalette has the Swift enum\'s members', () => {
  const members = ['page', 'darkPage', 'glow', 'cloudStrength', 'darkCloudStrength', 'darkMoonGlow',
                   'darkStarStrength', 'daytimeMoonOpacity', 'dayFrames', 'nightFrames', 'darkDayFrames',
                   'darkNightFrames', 'look', 'bodyPosition', 'scene', 'moon', 'altitudeHeight',
                   'brightLimbRotation', 'ridges', 'cloudArt', 'wispArt', 'wideLayoutWidth', 'clouds', 'wisps',
                   'starOpacity', 'stars', 'twinkle', 'glintColor', 'glints', 'sparkle'];
  for (const member of members) {
    ok(member in SkyPalette, `SkyPalette.${member}`);
    ok(palette[member] === SkyPalette[member], `also a named export: ${member}`);
  }
  for (const name of ['rgb', 'mix', 'css', 'SkyPalette']) ok(typeof palette[name] !== 'undefined', `export ${name}`);
  for (const name of ['look', 'bodyPosition', 'scene', 'moon', 'altitudeHeight', 'brightLimbRotation', 'clouds',
                      'wisps', 'starOpacity', 'stars', 'twinkle', 'glints', 'sparkle']) {
    equal(typeof SkyPalette[name], 'function', name);
  }
  equal(SkyPalette.ridges.length, 4);
  for (const ridge of SkyPalette.ridges) {
    for (const key of ['base', 'amplitude', 'blur']) equal(typeof ridge[key], 'number', `ridge.${key}`);
    equal(ridge.frequencies.length, 3);
    equal(ridge.phases.length, 3);
    for (const key of ['y', 'baseline', 'crestTop', 'points']) equal(typeof ridge[key], 'function', `ridge.${key}`);
    same(Object.keys(ridge.points(466, 678)[0]), ['x', 'y']);
  }
  same(Object.keys(SkyPalette.clouds(false)[0]), ['art', 'x', 'y', 'width', 'flipped']);
  same(Object.keys(SkyPalette.wisps(false)[0]), ['x', 'y', 'width', 'alpha']);
  same(Object.keys(SkyPalette.stars(466)[0]), ['x', 'y', 'size', 'alpha', 'twinkles', 'period', 'phase']);
  same(Object.keys(SkyPalette.glints(false)[0]), ['x', 'y', 'size', 'period', 'phase']);
  same(Object.keys(SkyPalette.cloudArt[0]), ['dawn', 'day', 'dusk', 'aspect']);
  same(Object.keys(SkyPalette.wispArt), ['dawn', 'day', 'dusk', 'aspect']);
  same(Object.keys(SkyPalette.dayFrames[0]), ['at', 'look']);
});

test('a Scene and its Moon have the contract\'s fields', () => {
  // The lab's default frame: 2026-11-21 16:10 in Chicago (CST).
  const at = { date: local(CST, 2026, 11, 21, 16, 10), latitude: 41.88, longitude: -87.63, tzOffsetHours: CST };
  const scene = SkyPalette.scene({ ...at, dark: true });
  same(Object.keys(scene), ['look', 'isNight', 'body', 'cloudOpacity', 'starOpacity', 'isDark', 'moon', 'page',
                            'cloudStrength', 'moonGlow', 'starStrength', 'moonGlowByPhase', 'moonPoolByPhase']);
  same(Object.keys(scene.look), ['top', 'mid', 'sun', 'core', 'warm', 'haze', 'mist', 'mistAlpha', 'hills', 'deep', 'light']);
  same(Object.keys(scene.look.light), ['dawn', 'day', 'dusk']);
  same(Object.keys(scene.body), ['x', 'y']);
  const moon = unwrap(scene.moon, 'the moon is up that afternoon');
  same(Object.keys(moon), ['x', 'y', 'fraction', 'phase', 'rotation', 'inDaylight', 'altitude', 'azimuth', 'passProgress']);

  // A quarter of an hour before a 4:25 PM sunset: day, nearly over, the sun
  // low on the right, the clouds on their way out, the dusk lighting coming.
  equal(scene.isNight, false);
  const day = solar.solarDay(at.date, at.latitude, at.longitude, CST);
  const phase = solar.solarPhase(at.date, day);
  near(scene.body.x, 0.04 + 0.92 * phase.progress, 1e-12, 'body.x');
  ok(phase.progress > 0.95 && phase.progress < 1, `late in the day (${phase.progress})`);
  near(scene.cloudOpacity, (1 - phase.progress) / 0.1, 1e-12, 'cloudOpacity');
  equal(scene.starOpacity, 0);
  ok(scene.look.light.dusk > 0.8, 'dusk-lit');
  // The computed properties, as fields.
  equal(scene.isDark, true);
  same(scene.page, SkyPalette.darkPage);
  equal(scene.cloudStrength, SkyPalette.darkCloudStrength);
  equal(scene.moonGlow, SkyPalette.darkMoonGlow);
  equal(scene.starStrength, SkyPalette.darkStarStrength);
  near(scene.moonPoolByPhase, 0.35 + 0.65 * moon.fraction, 1e-12, 'moonPoolByPhase');
  near(scene.moonGlowByPhase, 0.4 * (0.35 + 0.65 * moon.fraction), 1e-12, 'moonGlowByPhase');
  const light = SkyPalette.scene(at);
  same([light.page, light.cloudStrength, light.moonGlow, light.starStrength],
       [SkyPalette.page, 0.8, 1, 1], 'the light appearance');
  near(light.moonGlowByPhase, light.moonPoolByPhase, 1e-12);
  // A waxing gibbous three days before full, rising in the east, in daylight.
  equal(moon.inDaylight, true);
  ok(moon.fraction > 0.85 && moon.fraction < 0.95 && moon.phase > 0.25 && moon.phase < 0.5, 'waxing gibbous');
  ok(moon.azimuth > 60 * DEG && moon.azimuth < 120 * DEG, `in the east (${moon.azimuth / DEG}°)`);
  near(moon.x, 0.04 + 0.92 * moon.passProgress, 1e-12, 'moon.x from its pass');
  near(moon.y, 0.30 * (1 - moon.altitude / (Math.PI / 2)), 1e-12, 'moon.y from its altitude');
  same(moon, SkyPalette.moon({ date: at.date, latitude: at.latitude, longitude: at.longitude, inDaylight: true }));

  // Two hours on: night, the stars out, the same moon lit for the night.
  const night = SkyPalette.scene({ ...at, date: local(CST, 2026, 11, 21, 18, 10), dark: true });
  equal(night.isNight, true);
  equal(night.cloudOpacity, 0);
  equal(night.starOpacity, 1);
  equal(night.moon?.inDaylight, false);
  // And 3 AM belongs to the night that ends at that day's sunrise.
  const small = SkyPalette.scene({ ...at, date: local(CST, 2026, 11, 21, 3, 0) });
  equal(small.isNight, true);
  ok(small.body.x > 0.5, '3 AM is past the middle of the night');
});

test('scene falls back as the Swift does', () => {
  // No place: the zone's meridian at 40°N.
  const date = local(CST, 2026, 11, 21, 16, 10);
  same(SkyPalette.scene({ date, tzOffsetHours: CST }),
       SkyPalette.scene({ date, latitude: 40, longitude: -90, tzOffsetHours: CST }), 'approximateLocation');
  // No sunrise (the polar night): a plain 6:45-to-6:15 day.
  equal(solar.solarDay(local(1, 2026, 12, 21), 80, 15, 1), null);
  const polarNoon = SkyPalette.scene({ date: local(1, 2026, 12, 21, 12), latitude: 80, longitude: 15, tzOffsetHours: 1 });
  equal(polarNoon.isNight, false);
  near(polarNoon.body.x, 0.04 + 0.92 * ((12 - 6.75) / 11.5), 1e-9, 'fallback day progress');
  const polarEvening = SkyPalette.scene({ date: local(1, 2026, 12, 21, 20), latitude: 80, longitude: 15, tzOffsetHours: 1 });
  equal(polarEvening.isNight, true);
  near(polarEvening.body.x, 0.04 + 0.92 * ((20 - 18.25) / 12.5), 1e-9, 'fallback night progress');
  let threw = false;
  try { SkyPalette.scene({ date, latitude: 41.88, longitude: -87.63 }); } catch { threw = true; }
  ok(threw, 'scene without a tzOffsetHours throws rather than guess a zone');
});

test('nothing reads the machine\'s time zone', () => {
  const fingerprint = () => {
    const date = utc('2026-11-22T03:40:00Z');   // 9:40 PM in Chicago, already the 22nd in UTC
    const day = solar.solarDay(date, 41.88, -87.63, CST);
    return JSON.stringify([
      day, solar.solarPhase(date, day), solar.moonPass(date, 41.88, -87.63),
      solar.sunPosition(date, 41.88, -87.63), solar.approximateLocation(CST),
      SkyPalette.scene({ date, latitude: 41.88, longitude: -87.63, tzOffsetHours: CST, dark: true }),
      SkyPalette.scene({ date: local(1, 2026, 12, 21, 12), latitude: 80, longitude: 15, tzOffsetHours: 1 }),
    ]);
  };
  const original = process.env.TZ;
  const runs = ['UTC', 'America/Chicago', 'Asia/Kolkata', 'Pacific/Kiritimati', 'Pacific/Pago_Pago'].map((zone) => {
    process.env.TZ = zone;
    return { zone, offset: new Date(2026, 10, 21, 12).getTimezoneOffset(), print: fingerprint() };
  });
  if (original === undefined) delete process.env.TZ; else process.env.TZ = original;
  if (new Set(runs.map((run) => run.offset)).size < 2) {
    return 'skipped: this node does not follow process.env.TZ';
  }
  for (const run of runs) ok(run.print === runs[0].print, `the same sky with the machine in ${run.zone}`);
  return `the same under ${runs.length} machine time zones`;
});

// ═══════════════════════════════════════════ Against the Swift source ══
section('The port against the Swift source itself');

const here = (relative) => fileURLToPath(new URL(relative, import.meta.url));
const swiftPaths = {
  sky: here('../../../TwoOfUs/DesignSystem/SkyBackground.swift'),
  solar: here('../../../TwoOfUs/Store/SolarClock.swift'),
  moon: here('../../../TwoOfUs/Store/MoonClock.swift'),
};
if (!Object.values(swiftPaths).every((path) => existsSync(path))) {
  console.log(`skip  (no Swift source at ${swiftPaths.sky})`);
} else {
  const whole = readFileSync(swiftPaths.sky, 'utf8');
  const start = whole.indexOf('enum SkyPalette');
  const swift = start >= 0 ? whole.slice(start) : '';
  const hex = (text) => rgb(parseInt(text, 16));
  const numbers = (text) => text.split(',').map((part) => Number(part.trim()));

  /** The text inside the parentheses that open at `open`. */
  const balanced = (text, open) => {
    let depth = 0;
    for (let index = open; index < text.length; index += 1) {
      if (text[index] === '(') depth += 1;
      if (text[index] === ')') {
        depth -= 1;
        if (depth === 0) return text.slice(open + 1, index);
      }
    }
    throw new Error('unbalanced parentheses in the Swift source');
  };

  /** Every `private static let <name> = Look(…)`, as a lab Look. */
  const swiftLooks = () => {
    const sage = unwrap(swift.match(/private static let sageHills = \[([^\]]*)\]/), 'sageHills')[1];
    const sageHills = [...sage.matchAll(/0x([0-9A-Fa-f]{6})/g)].map((m) => hex(m[1]));
    const looks = {};
    for (const match of swift.matchAll(/private static let (\w+) = Look\(/g)) {
      const body = balanced(swift, match.index + match[0].length - 1);
      const colour = (name) => hex(unwrap(body.match(new RegExp(`\\b${name}: RGB\\(hex: 0x([0-9A-Fa-f]{6})\\)`)), `${match[1]}.${name}`)[1]);
      const hillsList = body.match(/hills: \[([^\]]*)\]/);
      const hills = hillsList
        ? [...hillsList[1].matchAll(/0x([0-9A-Fa-f]{6})/g)].map((m) => hex(m[1]))
        : (unwrap(body.match(/hills: sageHills/), `${match[1]}.hills`), sageHills);
      const light = unwrap(body.match(/light: \.of(Dawn|Day|Dusk)/), `${match[1]}.light`)[1];
      looks[match[1]] = {
        top: colour('top'), mid: colour('mid'), sun: colour('sun'), core: colour('core'),
        warm: colour('warm'), haze: colour('haze'), mist: colour('mist'),
        mistAlpha: Number(unwrap(body.match(/mistAlpha: ([\d.]+)/), `${match[1]}.mistAlpha`)[1]),
        hills, deep: colour('deep'),
        light: { dawn: light === 'Dawn' ? 1 : 0, day: light === 'Day' ? 1 : 0, dusk: light === 'Dusk' ? 1 : 0 },
      };
    }
    return looks;
  };

  test('the keyframes are the Swift\'s (every Look, every frame)', () => {
    ok(swift.length > 0, 'found enum SkyPalette');
    const looks = swiftLooks();
    equal(Object.keys(looks).length, 10, 'ten looks in the Swift (five light, five dark)');
    let colours = 0;
    for (const name of ['dayFrames', 'nightFrames', 'darkDayFrames', 'darkNightFrames']) {
      const list = unwrap(swift.match(new RegExp(`static let ${name}: \\[\\(at: Double, look: Look\\)\\] = \\[([\\s\\S]*?)\\n\\s*\\]`)), name)[1];
      const entries = [...list.matchAll(/\(([\d.]+), (\w+)\)/g)].map((m) => ({ at: Number(m[1]), look: unwrap(looks[m[2]], `look ${m[2]}`) }));
      ok(entries.length >= 4, `${name} has its frames (${entries.length})`);
      same(SkyPalette[name], entries, name);
      colours += entries.length * 12;
    }
    return `${colours} colours compared`;
  });

  test('the constants are the Swift\'s', () => {
    const scalar = (name) => Number(unwrap(swift.match(new RegExp(`static let ${name}(?:: CGFloat)? = ([\\d.]+)`)), name)[1]);
    for (const name of ['glow', 'cloudStrength', 'darkCloudStrength', 'darkMoonGlow', 'darkStarStrength',
                        'daytimeMoonOpacity', 'wideLayoutWidth']) {
      equal(SkyPalette[name], scalar(name), name);
    }
    for (const name of ['page', 'darkPage', 'glintColor']) {
      same(SkyPalette[name], hex(unwrap(swift.match(new RegExp(`static let ${name} = RGB\\(hex: 0x([0-9A-Fa-f]{6})\\)`)), name)[1]), name);
    }
  });

  test('the ridges are the Swift\'s', () => {
    const found = [...swift.matchAll(/Ridge\(base: ([\d.]+), amplitude: ([\d.]+), frequencies: \(([^)]*)\), phases: \(([^)]*)\), blur: ([\d.]+)\)/g)]
      .map((m) => ({ base: Number(m[1]), amplitude: Number(m[2]), frequencies: numbers(m[3]), phases: numbers(m[4]), blur: Number(m[5]) }));
    equal(found.length, 4, 'four ridges in the Swift');
    same(SkyPalette.ridges.map(({ base, amplitude, frequencies, phases, blur }) => ({ base, amplitude, frequencies, phases, blur })), found);
    // …and the wave itself, worked by hand for one point of the back ridge.
    const k = 2 * Math.PI * 100 / 466;
    const wave = 0.55 * Math.sin(k * 0.9 + 0.6) + 0.17 * Math.sin(k * 2.3 + 2.1) + 0.45 * Math.sin(k * 0.31 + 0.9);
    near(SkyPalette.ridges[0].y(100, 678), 678 - 0.245 * 678 + 0.022 * 678 * wave, 1e-9, 'y(100)');
    near(SkyPalette.ridges[0].baseline(678), 678 * (1 - 0.245), 1e-9, 'baseline');
    near(SkyPalette.ridges[0].crestTop(678), 678 * (1 - 0.245) - 0.022 * 678 * 0.8, 1e-9, 'crestTop');
  });

  test('the clouds, wisps and glints are the Swift\'s', () => {
    const art = [...swift.matchAll(/CloudArt\(dawn: "(\w+)", day: "(\w+)", dusk: "(\w+)", aspect: ([\d.]+) \/ ([\d.]+)\)/g)]
      .map((m) => ({ dawn: m[1], day: m[2], dusk: m[3], aspect: Number(m[4]) / Number(m[5]) }));
    equal(art.length, 4, 'three clouds and the wisp');
    same(SkyPalette.cloudArt, art.slice(0, 3), 'cloudArt');
    same(SkyPalette.wispArt, art[3], 'wispArt');

    const clouds = [...swift.matchAll(/CloudPlacement\(art: (\d+), x: ([\d.]+), y: ([\d.]+), width: ([\d.]+), flipped: (true|false)\)/g)]
      .map((m) => ({ art: Number(m[1]), x: Number(m[2]), y: Number(m[3]), width: Number(m[4]), flipped: m[5] === 'true' }));
    equal(clouds.length, 6, 'cloud placements (wide, then phone)');
    same(SkyPalette.clouds(true), clouds.slice(0, 4), 'clouds(wide)');
    same(SkyPalette.clouds(false), clouds.slice(4), 'clouds(phone)');

    const wisps = [...swift.matchAll(/WispPlacement\(x: ([\d.]+), y: ([\d.]+), width: ([\d.]+), alpha: ([\d.]+)\)/g)]
      .map((m) => ({ x: Number(m[1]), y: Number(m[2]), width: Number(m[3]), alpha: Number(m[4]) }));
    equal(wisps.length, 5, 'wisp placements (wide, then phone)');
    same(SkyPalette.wisps(true), wisps.slice(0, 3), 'wisps(wide)');
    same(SkyPalette.wisps(false), wisps.slice(3), 'wisps(phone)');

    const spots = [...swift.matchAll(/\(x: ([\d.]+), y: ([\d.]+), size: (\d+)\)/g)]
      .map((m) => ({ x: Number(m[1]), y: Number(m[2]), size: Number(m[3]) }));
    equal(spots.length, 12, 'glint spots (wide, then phone)');
    const place = ({ x, y, size }) => ({ x, y, size });
    same(SkyPalette.glints(true).map(place), spots.slice(0, 7), 'glints(wide)');
    same(SkyPalette.glints(false).map(place), spots.slice(7), 'glints(phone)');
  });

  // The formulas. A port keeps every number, so the numeric literals of a
  // Swift formula and of its JS twin must be the same numbers.
  const jsSolar = readFileSync(here('../lab/solar.js'), 'utf8');
  const jsPalette = readFileSync(here('../lab/palette.js'), 'utf8');
  const swiftSolar = readFileSync(swiftPaths.solar, 'utf8');
  const swiftMoon = readFileSync(swiftPaths.moon, 'utf8');

  /** `text` from the marker `from` up to the next `to` (or the end). */
  const region = (text, from, to) => {
    const begin = text.indexOf(from);
    if (begin < 0) throw new Error(`marker not found: ${from}`);
    const end = to === undefined ? text.length : text.indexOf(to, begin + from.length);
    if (end < 0) throw new Error(`marker not found: ${to}`);
    return text.slice(begin, end);
  };

  /** The numeric literals in source text, in order: comments and strings
   *  dropped, digit separators removed, hex read as a number. Not tuple
   *  members (`.0`), closure arguments (`$0`) or digits in names. */
  const literals = (text) => {
    const code = text.split('\n').map((line) => line.replace(/\/\/.*$/, '')).join('\n')
      .replace(/\/\*[\s\S]*?\*\//g, '')
      .replace(/'[^'\n]*'|"[^"\n]*"|`[^`]*`/g, '""');
    return [...code.matchAll(/(?<![\w.$])(0x[0-9A-Fa-f]+|\d[\d_]*(?:\.\d[\d_]*)?)(?!\w)/g)]
      .map((match) => Number(match[1].replace(/_/g, '')));
  };

  const distinct = (list) => [...new Set(list)].sort((a, b) => a - b);

  /** Every number in the Swift is in the port and nothing else is, but for
   *  the named exceptions. */
  const sameNumbers = (swiftText, jsText, { swiftOnly = [], jsOnly = [] } = {}) => {
    const inSwift = distinct(literals(swiftText));
    const inJS = distinct(literals(jsText));
    ok(inSwift.length > 20 && inJS.length > 20, 'found the numbers');
    same(inSwift.filter((n) => !inJS.includes(n)), swiftOnly, 'numbers in the Swift that the port lacks');
    same(inJS.filter((n) => !inSwift.includes(n)), jsOnly, 'numbers in the port that the Swift lacks');
    return `${inSwift.length} distinct numbers`;
  };

  test('SolarClock: the NOAA formula has the Swift\'s numbers, in order', () => {
    const inSwift = literals(region(swiftSolar, 'let gamma', 'return Day'));
    const inJS = literals(region(jsSolar, 'const gamma', 'return {'));
    ok(inSwift.length > 30, 'found the formula');
    same(inJS, inSwift);
    // 3600 is the Swift's seconds → hours (the lab is handed hours); 1000 the lab's milliseconds.
    sameNumbers(region(swiftSolar, 'enum SolarClock'), region(jsSolar, 'export function solarDay', 'const OBLIQUITY'),
                { swiftOnly: [3600], jsOnly: [1000] });
    return `${inSwift.length} numbers`;
  });

  test('MoonClock: the series and the search have the Swift\'s numbers', () => (
    // 180 is the Swift's `rad` (the lab's RAD is at the top of the file); 1000 the lab's milliseconds.
    sameNumbers(region(swiftMoon, 'enum MoonClock'), region(jsSolar, 'const OBLIQUITY'),
                { swiftOnly: [180], jsOnly: [1000] })
  ));

  test('SkyPalette: every number in the Swift enum is in the port, and no other', () => (
    // 3600 is the fallback day's seconds (the lab's HOUR_MS); 10000 rounds css()'s alpha.
    sameNumbers(swift, region(jsPalette, 'export function rgb', 'export const SkyPalette'),
                { swiftOnly: [3600], jsOnly: [10000] })
  ));

  test('SkyPalette: the star generator has the Swift\'s numbers, in order', () => {
    const inSwift = literals(region(swift, 'static func stars(width', 'static func twinkle'));
    const inJS = literals(region(jsPalette, 'export function stars(width', 'export function twinkle'));
    ok(inSwift.length > 20, 'found the generator');
    same(inJS, inSwift);
    return `${inSwift.length} numbers`;
  });

  // ═════════════════════════════════════ The drawing against SkyScene ══
  section('The drawing (skies/baseline.js) against SkyScene, StarField and the shapes');

  const jsSky = readFileSync(here('../skies/baseline.js'), 'utf8');
  const views = start >= 0 ? whole.slice(0, start) : whole;   // everything above `enum SkyPalette`

  // Each Swift function and the part of baseline.js that draws it. The markers
  // are the port's own comments and names: move one and its test says so.
  const twins = {
    'sky(in:)': [region(views, 'private func sky(in size', '/// A soft elliptical pool'),
                 region(jsSky, 'function paintBack(', '// The sun: a soft disc')],
    pool: [region(views, 'private func pool(', '/// A soft disc'),
           region(jsSky, '// A warm pool of light', '// The moon\'s glow (night only)')],
    sun: [region(views, 'private var sun: some View', '/// The moon as it really looks'),
          region(jsSky, 'const SUN_RADIUS', 'let sunHaloProfile')],
    moonDisc: [region(views, 'private func moonDisc', '// MARK: Clouds'),
               region(jsSky, '// The moon wherever it really is', '// Four ridges')],
    'clouds(in:)': [region(views, 'private func clouds(in size', '/// One cloud texture'),
                    region(jsSky, 'function paintClouds', '// ── StarField ──')],
    // (`hills(in:)` places the mist that `mist` draws: the port has both in one loop.)
    'hills(in:)': [region(views, 'private func hills(in size', '/// A soft band of valley mist'),
                   region(jsSky, '// Four ridges', '// ── the grain ──')],
    mist: [region(views, 'private func mist(', '/// The night\'s stars'),
           region(jsSky, '// Four ridges', '// ── the grain ──')],
    'StarField.field(at:)': [region(views, 'private func field(at time', '/// The lit part of the moon'),
                             region(jsSky, 'function paintStars', '// ── the moon, then SkyScene.hills')],
    MoonPhaseShape: [region(views, 'struct MoonPhaseShape', '/// A four-point star'),
                     region(jsSky, 'function moonPhasePath', '/** `RidgeShape`')],
    GlintShape: [region(views, 'private struct GlintShape', '/// One ridge of hills'),
                 region(jsSky, 'const GLINT', 'const TAU')],
    RidgeShape: [region(views, 'private struct RidgeShape', '/// The sky\'s colours'),
                 region(jsSky, 'function ridgePath', '// ─────')],
  };

  /** Every number in the Swift function is in its twin (but for `swiftOnly`),
   *  and the twin adds only `jsOnly`. */
  const twinNumbers = (name, { swiftOnly = [], jsOnly = [] } = {}) => {
    const [swiftText, jsText] = twins[name];
    const inSwift = distinct(literals(swiftText));
    const inJS = distinct(literals(jsText));
    ok(inSwift.length >= 2, `${name}: found the Swift's numbers`);
    same(inSwift.filter((n) => !inJS.includes(n)), swiftOnly, `${name}: numbers in the Swift that the drawing lacks`);
    same(inJS.filter((n) => !inSwift.includes(n)), jsOnly, `${name}: numbers in the drawing that the Swift lacks`);
    return inSwift.length;
  };

  test('every layer has the Swift\'s numbers: sky, pool, sun, moon, clouds, hills, mist, stars', () => {
    let count = 0;
    count += twinNumbers('sky(in:)');
    // 2: the pool's frame is its diameter (the canvas takes the radius).
    count += twinNumbers('pool', { swiftOnly: [2], jsOnly: [0.36, 0.45, 0.7] });
    // 46: the disc's frame, 2 × 23.
    count += twinNumbers('sun', { swiftOnly: [46] });
    // 32: the moon's frame (the canvas takes the radius, 16); 2: shadowBlur = 2 × radius.
    count += twinNumbers('moonDisc', { swiftOnly: [32], jsOnly: [2, 16] });
    // 0, 2: clamping the opacity, and halving a size to centre it.
    count += twinNumbers('clouds(in:)', { jsOnly: [0, 2] });
    // The mist's own numbers (0.55, 40, 54, and their halves 20 and 27) share the loop.
    count += twinNumbers('hills(in:)', { jsOnly: [0.55, 20, 27, 40, 54] });
    // 2: `.position(x: width / 2)`; 20 and 27: half of the 40 and of the 54; 0.5 and 9 are the hills'.
    count += twinNumbers('mist', { swiftOnly: [2], jsOnly: [0.5, 9, 20, 27] });
    // 0.9, the stars' shadow, is inside a colour string in the port (checked below);
    // 0, 0.5, 9, 180: the canvas's own bookkeeping (resets, pixel centres, the scratch's margin, degrees).
    count += twinNumbers('StarField.field(at:)', { swiftOnly: [0.9], jsOnly: [0, 0.5, 9, 180] });
    ok(twins['StarField.field(at:)'][1].includes("ctx.shadowColor = 'rgba(255, 255, 255, 0.9)'"), 'the stars\' shadow is white at 0.9');
    count += twinNumbers('MoonPhaseShape');
    count += twinNumbers('GlintShape');
    count += twinNumbers('RidgeShape');
    return `${count} distinct numbers in 11 functions`;
  });

  test('the gradients\' stops are the Swift\'s, in order', () => {
    const locations = (text) => [...text.matchAll(/location: ([\d.]+)/g)].map((m) => Number(m[1]));
    const stops = (text, gradient) => [...text.matchAll(new RegExp(`\\b${gradient}\\.addColorStop\\(([\\d.]+),`, 'g'))].map((m) => Number(m[1]));
    const [swiftSky, jsSkyPart] = twins['sky(in:)'];
    // The sky gradient, the moon's glow, the sun's bloom — as they come in `sky(in:)`.
    same([...stops(jsSkyPart, 'sky'), ...stops(jsSkyPart, 'glow'), ...stops(jsSkyPart, 'bloom')], locations(swiftSky), 'sky, glow, bloom');
    same(locations(swiftSky), [0, 0.15, 0.33, 0.46, 0.56, 0.66, 0.74, 1, 0, 0.35, 1, 0, 0.12, 0.3, 0.6], 'sky(in:) as read here');
    // …and the opacities, mixes and radii beside them: the same fractions, as
    // often. (One 0.5 less: the Swift's `unit` closure falls back to 0.5 for a
    // sky of no width, which the canvas never needs.)
    const fractions = (text) => literals(text).filter((n) => n > 0 && n < 1).sort((a, b) => a - b);
    const swiftFractions = fractions(swiftSky);
    swiftFractions.splice(swiftFractions.indexOf(0.5), 1);
    same(fractions(jsSkyPart), swiftFractions, 'every fraction in sky(in:), counted');
    // The sun's disc.
    const disc = JSON.parse(unwrap(jsSky.match(/const SUN_DISC = (\[.*\]);/), 'SUN_DISC')[1].replace(/'/g, '"'));
    same(disc.map(([at]) => at), locations(twins.sun[0]), 'the sun disc\'s stops');
    same(disc.map(([, part, alpha]) => [part, alpha]), [['core', 1], ['core', 1], ['sun', 0.95], ['sun', 0]], 'the sun disc\'s colours');
    ok(/look\.core\.color, location: 0\)[\s\S]*look\.core\.color, location: 0\.42\)[\s\S]*look\.sun\.color\.opacity\(0\.95\), location: 0\.72\)[\s\S]*look\.sun\.color\.opacity\(0\), location: 1\)/.test(twins.sun[0]), 'the Swift\'s disc, as read here');
    // The mist: clear, the mist at 55 %, clear — the port draws that profile already blurred.
    same(locations(twins.mist[0]), [0, 0.55, 1], 'the mist\'s stops');
    ok(twins.mist[1].includes('blurredMistStops(54, 0.55, 6)'), 'the mist band: 54 pt tall, peak at 55 %, blurred 6');
    // The hills: crest to foot, between two unit points.
    ok(/createLinearGradient\(0, ridge\.crestTop\(height\), 0, footY\)/.test(twins['hills(in:)'][1]), 'a ridge is filled from crestTop to footY');
  });

  test('the shapes are the Swift\'s: the glint\'s corners, the feather, the cream', () => {
    const corners = [...unwrap(twins.GlintShape[0].match(/let corners[^=]*= \[([\s\S]*?)\]\n/), 'GlintShape.corners')[1]
      .matchAll(/\(([\d.]+), ([\d.]+)\)/g)].map((m) => [Number(m[1]), Number(m[2])]);
    equal(corners.length, 8, 'eight corners');
    same(JSON.parse(unwrap(jsSky.match(/const GLINT = (\[.*\]);/), 'GLINT')[1]), corners, 'GLINT');

    const phonePage = here('../../../TwoOfUs/Features/Shared/PhonePage.swift');
    const colours = here('../../../TwoOfUs/DesignSystem/Colors.swift');
    if (existsSync(phonePage)) {
      const feather = Number(unwrap(readFileSync(phonePage, 'utf8').match(/static let featherWidth: CGFloat = ([\d.]+)/), 'PhonePage.featherWidth')[1]);
      equal(Number(unwrap(jsSky.match(/const FEATHER = ([\d.]+);/), 'FEATHER')[1]), feather, 'FEATHER');
    }
    if (existsSync(colours)) {
      const cream = unwrap(readFileSync(colours, 'utf8').match(/nightlightCream\s*=\s*Color\(hex: "([0-9A-Fa-f]{6})"\)/), 'AppColor.nightlightCream')[1];
      const inPort = unwrap(jsSky.match(/const CREAM = \{ r: 0x([0-9A-F]{2}) \/ 255, g: 0x([0-9A-F]{2}) \/ 255, b: 0x([0-9A-F]{2}) \/ 255 \};/), 'CREAM');
      equal(`${inPort[1]}${inPort[2]}${inPort[3]}`.toUpperCase(), cream.toUpperCase(), 'CREAM');
    }
    equal(Number(unwrap(jsSky.match(/const GRAIN_OPACITY = ([\d.]+);/), 'GRAIN_OPACITY')[1]),
          Number(unwrap(views.match(/Image\("SkyGrain"\)[\s\S]*?\.opacity\(([\d.]+)\)/), 'the grain\'s opacity')[1]), 'the grain\'s opacity');
    ok(/Image\("SkyGrain"\)\s*\.resizable\(resizingMode: \.tile\)\s*\.blendMode\(\.softLight\)/.test(views), 'the grain is tiled, soft light');
  });
}

// ═══════════════════════════════════════════════ The lab's default day ══
section('The lab\'s default day: 21 November 2026, Chicago (41.88, −87.63, UTC−6)');

test('the sun and the moon are where an almanac puts them', () => {
  const lat = 41.88;
  const lon = -87.63;
  const at = (hour, minute = 0) => local(CST, 2026, 11, 21, hour, minute);
  // Sunrise 6:46 and sunset 4:26 by the almanac.
  const day = unwrap(solar.solarDay(at(12), lat, lon, CST), 'the sun rises and sets');
  assertClock(day.sunrise, CST, 6, 47, 'sunrise', 2);
  assertClock(day.sunset, CST, 16, 26, 'sunset', 2);
  // Due south at its highest (11:36, as Chicago is west of its zone's meridian), 28° up.
  let noon = { altitude: -1 };
  for (let minute = 10 * 60; minute <= 14 * 60; minute += 1) {
    const position = solar.sunPosition(at(0, minute), lat, lon);
    if (position.altitude > noon.altitude) noon = { ...position, minute };
  }
  near(noon.azimuth / DEG, 180, 0.5, 'the sun\'s azimuth at its highest');
  near(noon.altitude / DEG, 90 - lat - 20, 0.5, 'its altitude then (declination −20°)');
  near(noon.minute, 11 * 60 + 36, 3, 'solar noon, minutes past midnight');
  ok(solar.sunPosition(at(9, 30), lat, lon).azimuth < Math.PI, 'south-east in the morning');
  ok(solar.sunPosition(at(15), lat, lon).azimuth > Math.PI, 'south-west in the afternoon');
  // A waxing gibbous: first quarter was the 17th, full is the 24th.
  for (const [hour, minute] of [[16, 10], [17, 30], [21, 0]]) {
    const light = solar.moonIllumination(at(hour, minute));
    ok(light.phase > 0.25 && light.phase < 0.5, `waxing gibbous at ${hour}:${minute} (phase ${light.phase.toFixed(3)})`);
    ok(light.fraction > 0.85 && light.fraction < 0.95, `about nine tenths lit at ${hour}:${minute} (${light.fraction.toFixed(3)})`);
    ok(solar.moonPassProgress(at(hour, minute), lat, lon) !== null, `the moon is up at ${hour}:${minute}`);
  }
  let full = null;
  for (let t = Date.UTC(2026, 10, 22); t < Date.UTC(2026, 10, 27) && full === null; t += 600_000) {
    if (solar.moonIllumination(new Date(t)).phase >= 0.5) full = new Date(t);
  }
  equal(unwrap(full, 'a full moon that week').toISOString().slice(0, 10), '2026-11-24', 'the full moon (24 November, 14:53 UTC)');
  // Up in the evening: it rose mid-afternoon in the east and is high in the south by nine.
  const pass = unwrap(solar.moonPass(at(21), lat, lon), 'the moon is up at nine');
  assertClock(unwrap(pass.rise), CST, 14, 15, 'moonrise', 10);
  near(solar.moonPosition(at(16, 10), lat, lon).azimuth / DEG, 90, 10, 'in the east at 16:10');
  near(solar.moonPosition(at(21), lat, lon).azimuth / DEG, 180, 15, 'near south at 21:00');
  ok(solar.moonPosition(at(21), lat, lon).altitude / DEG > 55, 'and high');
  // …and the scene puts them the same way round: the window looks south.
  const afternoon = palette.scene({ date: at(16, 10), latitude: lat, longitude: lon, tzOffsetHours: CST });
  ok(!afternoon.isNight && afternoon.body.x > 0.9, 'the sun low on the right before sunset');
  ok(unwrap(afternoon.moon, 'the moon at 16:10').x < 0.25 && afternoon.moon.inDaylight, 'the moon low on the left, in daylight');
  const evening = palette.scene({ date: at(21), latitude: lat, longitude: lon, tzOffsetHours: CST });
  ok(evening.isNight && evening.starOpacity === 1 && evening.cloudOpacity === 0, 'night at nine: stars, no clouds');
  near(unwrap(evening.moon, 'the moon at 21:00').x, 0.47, 0.05, 'the moon mid-sky');
});

// ═════════════════════════════════════ What the viewer adds to the state ══
section('What the viewer adds to the state (lab/core.js, lab/season.js)');

/** state.sun.x at an instant, the way buildState works it out. */
function sunXAt(date, place, tz) {
  const day = solar.solarDay(date, place.latitude, place.longitude, tz) ?? palette.fallbackDay(date, tz);
  return core.sunX(solar.solarPhase(date, day), day);
}

const SUN_X_PLACES = [
  ['Chicago, November', { latitude: 41.88, longitude: -87.63 }, CST, [2026, 11, 21]],
  ['Chicago, January', { latitude: 41.88, longitude: -87.63 }, CST, [2027, 1, 15]],
  ['Chicago, July', { latitude: 41.88, longitude: -87.63 }, -5, [2027, 7, 4]],
  ['Chicago, the equinox', { latitude: 41.88, longitude: -87.63 }, -5, [2027, 3, 20]],
  ['London, December', { latitude: 51.5, longitude: -0.13 }, 0, [2026, 12, 21]],
  ['Stockholm, June', { latitude: 59.33, longitude: 18.07 }, 2, [2027, 6, 21]],
  ['Sydney, January', { latitude: -33.87, longitude: 151.21 }, 11, [2027, 1, 15]],
];

test('sun.x is the baseline\'s rule while the sun is up', () => {
  let count = 0;
  for (const [name, place, tz, [y, m, d]] of SUN_X_PLACES) {
    for (let minute = 0; minute < 1440; minute += 7) {
      const date = local(tz, y, m, d, 0, minute);
      const scene = palette.scene({ date, latitude: place.latitude, longitude: place.longitude, tzOffsetHours: tz });
      if (scene.isNight) continue;
      count += 1;
      equal(sunXAt(date, place, tz), scene.body.x, `${name}, ${minute} min past midnight`);
    }
  }
  ok(count > 400, `daylight minutes were checked (${count})`);
  // …and through buildState, on the lab's default day.
  for (const time of ['06:50', '09:30', '12:30', '16:10']) {
    const state = core.buildState(core.parseParams({ time }));
    ok(!state.sun.isNight, `the sun is up at ${time}`);
    equal(state.sun.x, state.scene.body.x, `state.sun.x at ${time}`);
  }
  return `${count} daylight instants`;
});

test('sun.x is continuous, at one pace, through sunset and sunrise', () => {
  for (const [name, place, tz, [y, m, d]] of SUN_X_PLACES) {
    const day = unwrap(solar.solarDay(local(tz, y, m, d), place.latitude, place.longitude, tz), `${name}: a sunrise and a sunset`);
    const x = (ms) => sunXAt(new Date(ms), place, tz);
    const perSecond = 0.92 / ((day.sunset - day.sunrise) / 1000);
    for (const [what, edge, at] of [['sunset', day.sunset.getTime(), 0.96], ['sunrise', day.sunrise.getTime(), 0.04]]) {
      near(x(edge), at, 1e-9, `${name}: at ${what}`);
      // No jump: a second either side differs by a second's travel.
      near(x(edge + 1000) - x(edge - 1000), 2 * perSecond, 1e-9, `${name}: across ${what}, two seconds' travel`);
      // No change of pace: ten minutes before and ten minutes after cover the same ground.
      near(x(edge + 600_000) - x(edge), x(edge) - x(edge - 600_000), 1e-9, `${name}: the pace either side of ${what}`);
    }
    // Off to the right after sunset, back from the left before sunrise: it
    // crosses the window's edge when the day's pace has carried it the last 0.04
    // (25 min in a Chicago November, 49 in a Stockholm June).
    const toTheEdge = 0.04 / perSecond * 1000;
    ok(x(day.sunset.getTime() + 1) > 0.96, `${name}: past 0.96 the moment the sun has set`);
    near(x(day.sunset.getTime() + toTheEdge), 1, 1e-6, `${name}: at the right edge ${(toTheEdge / 60_000).toFixed(0)} min after sunset`);
    ok(x(day.sunset.getTime() + toTheEdge + 60_000) > 1, `${name}: off the right edge a minute later`);
    ok(x(day.sunrise.getTime() - 1) < 0.04, `${name}: short of 0.04 the moment before sunrise`);
    near(x(day.sunrise.getTime() - toTheEdge), 0, 1e-6, `${name}: at the left edge ${(toTheEdge / 60_000).toFixed(0)} min before sunrise`);
    ok(x(day.sunrise.getTime() - toTheEdge - 60_000) < 0, `${name}: off the left edge a minute earlier`);
  }
});

test('sun.x jumps once a day, in the middle of the night', () => {
  for (const [name, place, tz, [y, m, d]] of SUN_X_PLACES) {
    // Noon to noon, minute by minute: it only ever moves right, a minute's
    // travel at a time, but for the one wrap from far right to far left.
    const start = local(tz, y, m, d, 12).getTime();
    const jumps = [];
    let previous = sunXAt(new Date(start), place, tz);
    let worst = 0;
    for (let minute = 1; minute <= 1440; minute += 1) {
      const date = new Date(start + minute * 60_000);
      const now = sunXAt(date, place, tz);
      const step = now - previous;
      if (step < -0.9) jumps.push({ minute, date, from: previous, to: now });
      else worst = Math.max(worst, Math.abs(step));
      previous = now;
    }
    equal(jumps.length, 1, `${name}: wraps`);
    // A minute's travel, and at local midnight the hop SolarClock.phase itself
    // makes as one day's sunrise and sunset hand over to the next: up to 0.004 of
    // the window, two or three minutes' travel (README).
    ok(worst < 0.012, `${name}: every other minute is a small step (largest ${worst.toFixed(4)})`);
    if (jumps.length === 1) {
      const [jump] = jumps;
      const day = solar.solarDay(jump.date, place.latitude, place.longitude, tz);
      const phase = solar.solarPhase(jump.date, day);
      ok(phase.isNight, `${name}: the wrap is at night`);
      near(phase.progress, 0.5, 0.01, `${name}: at the middle of the night`);
      // How far out depends on the night: 1.65 in a Chicago November, 1.09 in a Stockholm June.
      ok(jump.from > 1 && jump.to < 0, `${name}: from off the right (${jump.from.toFixed(2)}) to off the left (${jump.to.toFixed(2)})`);
      near(jump.from - 0.96, 0.04 - jump.to, 0.01, `${name}: as far out on one side as on the other`);
    }
  }
});

test('tonightLit: asleep for the night, or inside the sample day\'s night', () => {
  // lab/core.js keeps a copy of the chrome's sample night (or 19:40–06:30 if the sample had none).
  same(core.SAMPLE_NIGHT, sampleNight() ?? { bedtime: 19 * 60 + 40, wake: 6 * 60 + 30 }, 'SAMPLE_NIGHT is lab/chrome.js\'s sampleNight()');
  same(core.SAMPLE_NIGHT, { bedtime: 1210, wake: 400 }, 'down at 20:10, up at 06:40');
  const lit = (query) => core.buildState(core.parseParams(query)).tonightLit;
  for (const [time, expected] of [['20:09', false], ['20:10', true], ['21:00', true], ['23:59', true], ['00:00', true],
    ['03:00', true], ['06:39', true], ['06:40', false], ['06:50', false], ['12:30', false], ['16:10', false], ['19:40', false]]) {
    equal(lit({ time }), expected, `awake at ${time}`);
  }
  equal(lit({ time: '12:30', asleep: 'night' }), true, 'asleep for the night at midday');
  equal(lit({ time: '19:40', asleep: 'night' }), true, 'asleep for the night at 19:40');
  equal(lit({ time: '12:30', asleep: 'nap' }), false, 'a nap lights nothing');
  equal(lit({ time: '21:00', asleep: 'nap' }), true, 'a nap inside the sample night changes nothing');
  equal(lit({ time: '12:30', lit: '1' }), true, 'lit=1 forces it');
  equal(lit({ time: '21:00', lit: '0' }), false, 'lit=0 forces it off');
  equal(lit({ time: '21:00', asleep: 'night', lit: '0' }), false, 'lit=0 wins over asleep=night');
  equal(typeof lit({}), 'boolean', 'always a boolean');
});

test('snowfall, lit and the rest of the URL round-trip', () => {
  const defaults = core.parseParams('');
  equal(defaults.snowfall, null, 'snowfall is unset by default');
  equal(defaults.lit, null, 'lit is unset by default');
  equal(core.toSearch(defaults), '', 'the defaults are an empty query');
  ok(!('snowfall' in core.buildState(defaults)), 'state.snowfall is absent until asked for');
  for (const [query, snowfall, lit] of [['snowfall=1', 1, null], ['snowfall=0', 0, null], ['snowfall=0.4&lit=1', 0.4, true],
    ['lit=0', null, false], ['snowfall=7', 1, null], ['snowfall=-2', 0, null], ['snowfall=deep&lit=perhaps', null, null]]) {
    const params = core.parseParams(query);
    equal(params.snowfall, snowfall, `${query}: snowfall`);
    equal(params.lit, lit, `${query}: lit`);
    same(core.parseParams(core.toSearch(params)), params, `${query}: toSearch and back`);
    equal(core.buildState(params).snowfall, snowfall ?? undefined, `${query}: state.snowfall`);
  }
  const busy = 'sky=wet-wash&device=spread&scheme=light&date=2027-01-15&time=17:22&tz=-5&asleep=night&age=197&chrome=0&t=12'
    + '&motion=0&event=bedtime&eventAge=3&lead=0.3&veil=0.5&tilt=-1,0.5&toast=1&snowfall=1&lit=0';
  equal(core.toSearch(core.parseParams(busy)), busy, 'every parameter comes back in toSearch\'s order');
});

test('season() says what the lab says is in the air', () => {
  const winter = 15;                      // the review set's winter day: snow lying, none falling
  const natural = season(winter, 41.88);
  equal(natural.snow, 1, 'snow lies in mid-January');
  equal(natural.snowfall, 0, 'none in the air that day');
  same(season(winter), natural, 'the latitude still defaults');
  // An option, or a whole state…
  equal(season(winter, 41.88, { snowfall: 1 }).snowfall, 1, 'options.snowfall');
  equal(season(winter, 41.88, { snowfall: 0.25 }).snowfall, 0.25, 'options.snowfall, a part');
  equal(season(1, 41.88, { snowfall: 0 }).snowfall, 0, 'options.snowfall = 0 clears a snowy day');
  ok(season(1, 41.88).snowfall > 0, '(day 1 is one)');
  const state = core.buildState(core.parseParams({ date: '2027-01-15', snowfall: '1' }));
  equal(state.snowfall, 1, 'state.snowfall');
  equal(season(state).snowfall, 1, 'season(state)');
  same({ ...season(state), snowfall: 0 }, season(state.dayOfYear, state.latitude), 'season(state) is otherwise the day\'s');
  same(season(core.buildState(core.parseParams({ date: '2027-01-15' }))), natural, 'season(state) without snowfall is the day\'s own');
  // …or the lab's override, for the two-argument call every sky makes.
  forceSnowfall(1);
  try {
    equal(season(winter, 41.88).snowfall, 1, 'forced: the two-argument call');
    same({ ...season(winter, 41.88), snowfall: 0 }, natural, 'forced: nothing else changes');
    equal(season(200, 41.88).snow, 0, 'forced: no snow lies in July for it');
    equal(season(winter, 41.88, { snowfall: 0.5 }).snowfall, 0.5, 'an explicit option still wins');
    forceSnowfall(0);
    equal(season(1, 41.88).snowfall, 0, 'forced to 0: a snowy day is clear');
  } finally {
    forceSnowfall(null);
  }
  same(season(winter, 41.88), natural, 'and back to the day\'s own');
});

test('state.layout has a stand-in wherever no chrome was measured', () => {
  const fields = ['measured', 'name', 'age', 'avatar', 'gear', 'firstCardTop', 'stripClear', 'title', 'subtitle'];
  for (const device of ['cover', 'spread', 'iphone']) {
    const layout = core.buildState(core.parseParams({ device })).layout;
    same(Object.keys(layout), fields, `${device}: the fields, in order`);
    equal(layout.measured, false, `${device}: marked as not measured`);
    for (const key of ['name', 'age', 'avatar', 'gear']) {
      const r = unwrap(layout[key], `${device}: ${key}`);
      ok([r.x, r.y, r.width, r.height].every(Number.isFinite) && r.width > 0 && r.height > 0, `${device}: ${key} is a rect`);
      ok(r.y + r.height <= layout.firstCardTop, `${device}: ${key} is above the first card`);
    }
    equal(layout.stripClear === null, device === 'iphone', `${device}: stripClear only on the Duo`);
    equal(layout.title === null, device !== 'spread', `${device}: a title only on the spread`);
    equal(layout.subtitle === null, device !== 'spread', `${device}: a subtitle only on the spread`);
  }
  const awake = core.estimateLayout('cover', false).stripClear;
  const asleep = core.estimateLayout('cover', 'night').stripClear;
  same(Object.keys(awake), ['x', 'width', 'yMin', 'yMax'], 'stripClear\'s fields');
  ok(asleep.yMin > awake.yMin && asleep.yMax === awake.yMax, 'the island grows down when a sleep is running');
  equal(awake.x + awake.width, core.DEVICES.cover.width, 'the window runs to the display\'s edge');
  // A measured layout handed to buildState is the one in the state.
  const measured = { measured: true };
  ok(core.buildState(core.parseParams(''), 0, [], measured).layout === measured, 'buildState passes a measured layout through');
});

// The sun's halo is pure maths, so it is checked wherever the lab is.
section('The sun\'s halo (skies/baseline.js)');

test('sunHalo is the disc\'s alpha under a Gaussian of sigma 17', () => {
  const halo = sunHalo();
  const R = 23;
  const sigma = 17;
  equal(halo.reach, R + 4 * sigma, 'it reaches 4 sigma past the rim');
  equal(halo.stops[0].at, 0, 'the first stop');
  equal(halo.stops[halo.stops.length - 1].at, 1, 'the last stop');
  equal(halo.stops[halo.stops.length - 1].alpha, 0, 'it ends at nothing');
  for (let index = 1; index < halo.stops.length; index += 1) {
    ok(halo.stops[index].at > halo.stops[index - 1].at, `stop ${index} is further out`);
    ok(halo.stops[index].alpha < halo.stops[index - 1].alpha, `stop ${index} is fainter`);
  }
  // The disc's alpha (SkyScene.sun): 1 to 42 % of the radius, 0.95 at 72 %, 0 at the rim.
  const discAlpha = (r) => {
    const t = r / R;
    if (t <= 0.42) return 1;
    if (t <= 0.72) return 1 - 0.05 * (t - 0.42) / 0.30;
    if (t <= 1) return 0.95 * (1 - (t - 0.72) / 0.28);
    return 0;
  };
  // The blur itself, by brute force on a 0.1 pt grid.
  const blurred = (d) => {
    const step = 0.1;
    let sum = 0;
    for (let x = -R + step / 2; x < R; x += step) {
      for (let y = -R + step / 2; y < R; y += step) {
        const alpha = discAlpha(Math.hypot(x, y));
        if (alpha > 0) sum += alpha * Math.exp(-((x - d) ** 2 + y * y) / (2 * sigma * sigma));
      }
    }
    return sum * step * step / (2 * Math.PI * sigma * sigma);
  };
  const at = (d) => {
    const position = d / halo.reach * (halo.stops.length - 1);
    const index = Math.min(Math.floor(position), halo.stops.length - 2);
    return halo.stops[index].alpha + (halo.stops[index + 1].alpha - halo.stops[index].alpha) * (position - index);
  };
  let worst = 0;
  for (const d of [0, 4.5, 9.7, 16, 23, 30, 36, 44.4, 55, 70]) {
    const expected = blurred(d);
    worst = Math.max(worst, Math.abs(at(d) - expected));
    near(at(d), expected, 0.0005, `the halo ${d} pt from the centre`);
  }
  near(at(0), 0.479, 0.001, 'at the centre');
  near(at(R), 0.251, 0.001, 'at the rim');
  ok(at(R + 13) > 0.09, 'still a tenth 13 pt past the rim');
  // Its total is the disc's own (a blur moves alpha, it makes none).
  let total = 0;
  let discTotal = 0;
  for (let r = 0.005; r < halo.reach; r += 0.01) {
    total += at(r) * 2 * Math.PI * r * 0.01;
    discTotal += discAlpha(r) * 2 * Math.PI * r * 0.01;
  }
  near(total / discTotal, 1, 0.002, 'the halo holds all of the disc\'s alpha');
  return `within ${worst.toExponential(1)} of the blur`;
});

// ──────────────────────────────────────────────────────────────── Summary ──

console.log('');
if (failedTests.length > 0) {
  console.log(`FAILED: ${failedTests.length} of ${testCount} tests (${checkCount} checks)`);
  for (const name of failedTests) console.log(`  - ${name}`);
  process.exit(1);
}
console.log(`All ${testCount} tests passed (${checkCount} checks).`);
