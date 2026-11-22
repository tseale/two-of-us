#!/usr/bin/env node
// Sky lab → Swift: the numbers behind the night's rules.
//
//     node design/sky-lab/tools/swift-fixtures/night.mjs
//
// Writes TwoOfUsTests/SkyCoreFixturesNight.swift from the lab's own modules: where the sun stands
// (lab/solar.js, `sunPosition`), when it rises through an angle (a search over that same function),
// the lab's night hours and "the night has begun" minute by minute (lab/core.js through `buildState`),
// the nights of his life and their month-nights (lab/nights.js), and the eases a `Glide` has to
// reproduce (lab/presence.js, `roomDepth`; the camera's `look` out of skies/hill-painted.js).
//
// Plain node, no dependencies. Nothing in the Swift fixture is typed by hand.

import { fileURLToPath } from 'node:url';
import * as solar from '../../lab/solar.js';
import * as core from '../../lab/core.js';
import { nights } from '../../lab/nights.js';
import { presence, roomDepth, SLEEP_DEPTH, MOMENT } from '../../lab/presence.js';
import { table, writeSwift, zoned } from './emit.mjs';

const RAD = Math.PI / 180;
const MINUTE = 60_000;
const HOUR = 3_600_000;

// ── places ───────────────────────────────────────────────────────────────
// Chicago is the lab's stand-in for the household's place (BRIEF.md): `chicago` is the city's own
// coordinates, as the port's plan pins first light; `lab` is the viewer's default (41.88, −87.63).
const PLACES = {
  chicago: { latitude: 41.8781, longitude: -87.6298, zone: 'America/Chicago' },
  lab: { latitude: 41.88, longitude: -87.63, zone: 'America/Chicago' },
  stockholm: { latitude: 59.3293, longitude: 18.0686, zone: 'Europe/Stockholm' },
  bergen: { latitude: 60.3913, longitude: 5.3221, zone: 'Europe/Oslo' },
  tromso: { latitude: 69.6492, longitude: 18.9553, zone: 'Europe/Oslo' },
  longyearbyen: { latitude: 78.2232, longitude: 15.6267, zone: 'Arctic/Longyearbyen' },
  singapore: { latitude: 1.3521, longitude: 103.8198, zone: 'Asia/Singapore' },
  sydney: { latitude: -33.8688, longitude: 151.2093, zone: 'Australia/Sydney' },
};

// ── the sun's place ──────────────────────────────────────────────────────

function sunPositions() {
  const rows = [];
  const days = [[2026, 11, 21], [2026, 12, 21], [2027, 3, 20], [2027, 6, 21], [2027, 9, 23]];
  for (const [name, place] of Object.entries(PLACES)) {
    if (name === 'lab') continue;
    for (const [y, m, d] of days) {
      // every 2 h 17 min through the UTC day: a different minute of every hour, day and night
      for (let ms = Date.UTC(y, m - 1, d, 0, 11); ms < Date.UTC(y, m - 1, d + 1); ms += 137 * MINUTE) {
        const p = solar.sunPosition(ms, place.latitude, place.longitude);
        rows.push([name, ms, place.latitude, place.longitude, p.altitude, p.azimuth]);
      }
    }
  }
  return table('sunPositions',
    'Where the sun stands: lab/solar.js `sunPosition(date, latitude, longitude)` at eight places on five days\n'
    + '(the solstices, the equinoxes and the lab\'s default day), every 2 h 17 min. Radians; the azimuth from\n'
    + 'north, clockwise.',
    ['place', 'epochMilliseconds', 'latitude', 'longitude', 'altitude', 'azimuth'], rows);
}

// ── when the sun rises through an angle ──────────────────────────────────

/** The next instant after `afterMs` at which the sun comes UP through `degrees`, to the millisecond, by
 *  the lab's `sunPosition`; null where it does not within 26 hours. (A search of the lab's function, a
 *  minute at a time and then bisected: the lab itself only ever asks "is the sun under −7° now?".) */
export function risesThrough(degrees, afterMs, place, spanHours = 26) {
  const height = (ms) => solar.sunPosition(ms, place.latitude, place.longitude).altitude / RAD - degrees;
  let t = afterMs;
  let current = height(t);
  while (t - afterMs < spanHours * HOUR) {
    const later = t + MINUTE;
    const after = height(later);
    if (current < 0 && after >= 0) {
      let low = t, high = later;
      while (high - low > 0.5) {
        const mid = (low + high) / 2;
        if (height(mid) < 0) low = mid; else high = mid;
      }
      return Math.round((low + high) / 2);
    }
    t = later;
    current = after;
  }
  return null;
}

function sunRises() {
  const rows = [];
  const add = (label, placeName, degrees, afterMs) => {
    const place = typeof placeName === 'string' ? PLACES[placeName] : placeName;   // a name, or a place of its own
    const rise = risesThrough(degrees, afterMs, place);
    rows.push([label, place.latitude, place.longitude, degrees, afterMs, rise ?? 'never']);
  };
  const evening = (placeName, y, m, d) => zoned(PLACES[placeName].zone, y, m, d, 18);

  // The plan's two pins: first light (−7°) in Chicago after the evenings of 21 Nov 2026 and 20 Jun 2027,
  // and the angle at which "Night N" turns (−4°) on the same mornings.
  add('chicago-first-light-22-nov-2026', 'chicago', -7, evening('chicago', 2026, 11, 21));
  add('chicago-first-light-21-jun-2027', 'chicago', -7, evening('chicago', 2027, 6, 20));
  add('chicago-count-turns-22-nov-2026', 'chicago', -4, evening('chicago', 2026, 11, 21));
  add('chicago-count-turns-21-jun-2027', 'chicago', -4, evening('chicago', 2027, 6, 20));
  // The same two mornings at the lab's own default place (41.88, −87.63).
  add('lab-first-light-22-nov-2026', 'lab', -7, evening('lab', 2026, 11, 21));
  add('lab-count-turns-22-nov-2026', 'lab', -4, evening('lab', 2026, 11, 21));
  // The nights the clocks change in Chicago (forward on 14 Mar 2027, back on 7 Nov 2027).
  add('chicago-first-light-14-mar-2027', 'chicago', -7, evening('chicago', 2027, 3, 13));
  add('chicago-first-light-7-nov-2027', 'chicago', -7, evening('chicago', 2027, 11, 6));
  // Sunrise's own angle, and a high one, so the search is not only ever asked for twilight.
  add('chicago-sunrise-22-nov-2026', 'chicago', -0.833, evening('chicago', 2026, 11, 21));
  add('chicago-ten-degrees-22-nov-2026', 'chicago', 10, evening('chicago', 2026, 11, 21));
  // Elsewhere: the equator, the south.
  add('singapore-first-light-22-nov-2026', 'singapore', -7, evening('singapore', 2026, 11, 21));
  add('sydney-first-light-22-dec-2026', 'sydney', -7, evening('sydney', 2026, 12, 21));
  // Far north. Stockholm's midsummer sun is under −7° for one hour (it bottoms out at −7.2°), so there
  // is still a first light, at about 01:19; Bergen's, a degree further north, never gets that low, and
  // Tromsø's never sets. Longyearbyen's midwinter sun never comes within 7° of the horizon, and by early
  // February it does again, towards noon.
  add('stockholm-first-light-2-may-2027', 'stockholm', -7, evening('stockholm', 2027, 5, 1));
  add('stockholm-first-light-21-jun-2027', 'stockholm', -7, evening('stockholm', 2027, 6, 20));
  add('bergen-first-light-21-jun-2027', 'bergen', -7, evening('bergen', 2027, 6, 20));
  add('tromso-first-light-21-jun-2027', 'tromso', -7, evening('tromso', 2027, 6, 20));
  add('longyearbyen-first-light-22-dec-2026', 'longyearbyen', -7, evening('longyearbyen', 2026, 12, 21));
  add('longyearbyen-first-light-6-feb-2027', 'longyearbyen', -7, evening('longyearbyen', 2027, 2, 5));
  // A short dip. Uppsala is half a degree north of Stockholm: on the night of 1 July 2027 its sun is under
  // −7° for 24 minutes (00:41:43 to 01:05:33 local), the first such night after the midsummer ones that
  // have none. Asked from an odd minute, 18:07, so that a search stepping by the half hour (18:07, …,
  // 00:37, 01:07) steps clean over it: the app's search has to be finer than the dips it is asked about.
  const uppsala = { latitude: 59.8586, longitude: 17.6389, zone: 'Europe/Stockholm' };
  add('uppsala-first-light-2-jul-2027', uppsala, -7, zoned(uppsala.zone, 2027, 7, 1, 18, 7));
  // A year of Chicago mornings, every 13th day, from an arbitrary minute of the night before.
  for (let ms = Date.UTC(2026, 6, 2, 3, 7); ms < Date.UTC(2027, 6, 2); ms += 13 * 24 * HOUR) {
    add(`chicago-first-light-after-${new Date(ms).toISOString().slice(0, 16)}Z`, 'chicago', -7, ms);
  }
  return table('sunRises',
    'When the sun next comes up through an angle: the first instant after `after` at which lab/solar.js\n'
    + '`sunPosition(…).altitude` passes `degrees` going up, found by stepping a minute at a time and\n'
    + 'bisecting to the millisecond; `never` where it does not within 26 hours.',
    ['label', 'latitude', 'longitude', 'degrees', 'afterEpochMilliseconds', 'riseEpochMilliseconds'], rows);
}

// ── the lab's night, minute by minute ────────────────────────────────────

/** The lab's own answers for every minute of nine Chicago days, through `buildState` exactly as the
 *  viewer asks: is it night hours (`nightHours`), has the night begun with nobody asleep (the lab then
 *  goes by its sample day's 20:10 bedtime), and has it begun with a night sleep running. One character
 *  a minute, from 00:00: 1 yes, 0 no. `tz` is the lab's fixed offset for that date (Chicago's own). */
function labNightHours() {
  const days = [
    ['2026-11-21', -6], ['2026-12-21', -6], ['2027-01-31', -6], ['2027-03-20', -5], ['2027-05-01', -5],
    ['2027-06-21', -5], ['2027-07-15', -5], ['2027-09-23', -5], ['2027-10-31', -5],
  ];
  const rows = [];
  for (const [date, tz] of days) {
    let hours = '', awake = '', asleep = '';
    for (let m = 0; m < 1440; m += 1) {
      const query = { date, time: core.minutesToTime(m), tz, lat: core.DEFAULTS.lat, lon: core.DEFAULTS.lon };
      const up = core.buildState(core.parseParams(query));
      const down = core.buildState(core.parseParams({ ...query, asleep: 'night' }));
      hours += core.nightHours(up.sun, m) ? '1' : '0';
      awake += up.nightBegun ? '1' : '0';
      asleep += down.nightBegun ? '1' : '0';
    }
    rows.push([date, tz, core.DEFAULTS.lat, core.DEFAULTS.lon, core.SAMPLE_NIGHT.bedtime, core.SAMPLE_NIGHT.wake, hours, awake, asleep]);
  }
  return table('labNightHours',
    'The lab\'s night, minute by minute, on nine days at its default place: lab/core.js `nightHours(state.sun,\n'
    + 'minutes)`, and `state.nightBegun` from `buildState` with nobody asleep (the lab then takes the night to\n'
    + 'have begun at its sample day\'s bedtime) and with `asleep=night`. Each of the last three cells is 1440\n'
    + 'characters, one a minute from 00:00 local: 1 yes, 0 no. `tz` is hours from UTC; the sample night\'s\n'
    + 'bedtime and wake are minutes from local midnight (`SAMPLE_NIGHT`).',
    ['date', 'tz', 'latitude', 'longitude', 'sampleBedtime', 'sampleWake', 'nightHours', 'begunAwake', 'begunAsleepNight'], rows);
}

// ── the nights of his life ───────────────────────────────────────────────

/** lab/nights.js at a spread of ages: how many stars he has once tonight's is lit, tonight's own number,
 *  and how many of the earlier nights are month-nights (the lab's 30.44-day months). */
function labNights() {
  const ages = [0, 1, 2, 29, 30, 31, 32, 60, 61, 62, 91, 92, 93, 122, 123, 141, 142, 143, 183, 184, 364, 365, 366, 729, 730, 731, 800];
  const rows = ages.map((age) => {
    const lit = nights(age, { tonightLit: true });
    const before = nights(age);
    const tonight = lit.find((star) => star.kind === 'tonight');
    return [age, lit.length, tonight.night, before.filter((star) => star.kind === 'month').length,
            before.filter((star) => star.kind === 'first').length];
  });
  return table('labNights',
    'The nights of his life: lab/nights.js `nights(ageDays, { tonightLit })` at a spread of ages. `stars` is how\n'
    + 'many he has once tonight\'s is lit, `tonight` the number of tonight\'s own, `monthNightsBefore` and\n'
    + '`firstNightsBefore` how many of the nights before tonight are of those kinds.',
    ['ageDays', 'stars', 'tonight', 'monthNightsBefore', 'firstNightsBefore'], rows);
}

/** The lab's month-nights among his first 800 nights, as it counts months (30.4375 days). */
function labMonthNights() {
  const months = nights(800).filter((star) => star.kind === 'month').map((star) => star.night);
  return table('labMonthNights',
    'The month-nights among his first 800 nights as the lab counts them (lab/nights.js, `monthsBy`: a month is\n'
    + '30.4375 days, "the app would use his real date of birth"). One row; night numbers, in order.',
    months.map((_, i) => `month${i + 1}`), [months]);
}

/** How much of the starfield is out (lab/presence.js, `presence(state).stars`) around the two morning
 *  angles of 22 Nov 2026 in Chicago: first light (−7°) and the angle "Night N" turns at (−4°). */
function labStarlight() {
  const place = PLACES.chicago;
  const evening = zoned(place.zone, 2026, 11, 21, 18);
  const firstLight = risesThrough(-7, evening, place);
  const turn = risesThrough(-4, evening, place);
  const at = (label, ms) => {
    const altitude = solar.sunPosition(ms, place.latitude, place.longitude).altitude;
    const p = presence({ sun: { altitude }, moon: null, asleep: false, event: null });
    return [label, ms, altitude / RAD, p.stars];
  };
  return table('labStarlight',
    'How much of the starfield is out on the morning of 22 Nov 2026 in Chicago: lab/presence.js\n'
    + '`presence(state).stars` (none above −4°, all of it below −12°) at first light, five minutes before the\n'
    + 'sun passes −4°, and as it does.',
    ['label', 'epochMilliseconds', 'sunAltitudeDegrees', 'stars'],
    [at('first-light', firstLight), at('five-minutes-before-the-turn', turn - 5 * MINUTE), at('the-turn', turn)]);
}

// ── the room's dimming, eased ────────────────────────────────────────────

/** lab/presence.js `roomDepth(state)` through each change of a sleep, every tenth of a second for ten
 *  seconds: the smoothstep eases a `Glide` has to reproduce. And the two depths themselves. */
function labRoomDepth() {
  const rows = [];
  const curves = {
    'bedtime-night': (age) => ({ asleep: 'night', event: { kind: 'bedtime', age } }),
    'arrive-night': (age) => ({ asleep: 'night', event: { kind: 'arrive', age } }),
    'arrive-nap': (age) => ({ asleep: 'nap', event: { kind: 'arrive', age } }),
    'wake-night': (age) => ({ asleep: false, event: { kind: 'wake', age, woke: 'night' } }),
    'wake-nap': (age) => ({ asleep: false, event: { kind: 'wake', age, woke: 'nap' } }),
  };
  for (const [label, state] of Object.entries(curves)) {
    for (let i = 0; i <= 100; i += 1) {
      const age = i / 10;
      rows.push([label, age, roomDepth(state(age))]);
    }
  }
  rows.push(['standing-night', 0, roomDepth({ asleep: 'night', event: null })]);
  rows.push(['standing-nap', 0, roomDepth({ asleep: 'nap', event: null })]);
  rows.push(['standing-awake', 0, roomDepth({ asleep: false, event: null })]);
  if (SLEEP_DEPTH.night !== 1 || SLEEP_DEPTH.nap !== 0.45) console.warn('  note: SLEEP_DEPTH has changed');
  return table('labRoomDepth',
    'The room\'s dimming through each change of a sleep: lab/presence.js `roomDepth(state)` at `age` seconds\n'
    + 'into a bedtime, an arrival (night sleep, nap) and a wake (from each), every tenth of a second; and\n'
    + 'standing, with no event.',
    ['curve', 'age', 'depth'], rows);
}

/** The quiet dissolve's length, as the lab has it (the one number of MOMENT this layer reads). */
function labQuiet() {
  return table('labQuiet', 'lab/presence.js `MOMENT.quiet`: how long a dissolve is, in seconds.',
    ['dissolve'], [[MOMENT.quiet.dissolve]]);
}

// ── write ────────────────────────────────────────────────────────────────

writeSwift({
  file: 'SkyCoreFixturesNight',
  script: fileURLToPath(import.meta.url),
  sources: [
    'design/sky-lab/lab/solar.js      sunPosition',
    'design/sky-lab/lab/core.js       buildState, nightHours, nightHasBegun, SAMPLE_NIGHT',
    'design/sky-lab/lab/nights.js     nights',
    'design/sky-lab/lab/presence.js   presence (stars), roomDepth, MOMENT.quiet',
  ],
  tables: [sunPositions(), sunRises(), labNightHours(), labNights(), labMonthNights(), labStarlight(),
           labRoomDepth(), labQuiet()],
});
