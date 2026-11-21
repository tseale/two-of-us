// Sky lab — the sky's clocks.
//
// A line-for-line port of TwoOfUs/Store/SolarClock.swift and
// TwoOfUs/Store/MoonClock.swift (same constants, same formulas, same search),
// plus one thing the Swift doesn't have: the sun's own altitude and azimuth
// (`sunPosition`), from the solar series MoonClock already carries.
//
// Pure: no DOM, no globals, and it never reads the machine's time zone.
// Where the Swift uses `Calendar.current`, the caller passes `tzOffsetHours`
// (local = UTC + tzOffsetHours). The Swift is the truth; if it changes, port
// the change here and run `node design/sky-lab/tools/test-math.mjs`.
//
// Conventions, for everything exported here:
//   - `date` is a JS Date (a number of epoch milliseconds works too).
//   - latitude / longitude are degrees, east positive.
//   - angles are radians. Azimuths are reckoned from NORTH, clockwise:
//     east = PI/2, south = PI, west = 3PI/2, always in [0, 2PI).

const RAD = Math.PI / 180;
const HOUR_MS = 3_600_000;
const DAY_MS = 86_400_000;

/** Epoch milliseconds of a Date (or of a number that already is one). */
function millis(date) {
  return typeof date === 'number' ? date : date.getTime();
}

/** Epoch seconds, as Swift's `timeIntervalSince1970`. */
function seconds(date) {
  return millis(date) / 1000;
}

function requireOffset(tzOffsetHours) {
  if (typeof tzOffsetHours !== 'number' || !Number.isFinite(tzOffsetHours)) {
    throw new TypeError('solar: tzOffsetHours must be a finite number (local = UTC + tzOffsetHours)');
  }
  return tzOffsetHours;
}

// ───────────────────────────────────────────────────────────── SolarClock ──
// Where the sun is today: sunrise and sunset for a place, and how far through
// the day (or the night) a moment is. The NOAA approximation (good to a
// minute or two away from the poles).

/**
 * SolarClock.day(containing:latitude:longitude:calendar:).
 * Sunrise and sunset on the LOCAL calendar day containing `date`.
 * Null where the sun neither rises nor sets that day (polar day or night).
 * @returns {{ sunrise: Date, sunset: Date } | null}
 */
export function solarDay(date, latitude, longitude, tzOffsetHours) {
  const tzMs = requireOffset(tzOffsetHours) * HOUR_MS;
  // Local noon, so the UTC day used below is the local day's.
  const localDay = Math.floor((millis(date) + tzMs) / DAY_MS);
  const noon = localDay * DAY_MS + 12 * HOUR_MS - tzMs;
  const utcMidnight = Math.floor(noon / DAY_MS) * DAY_MS;
  const yearStart = Date.UTC(new Date(utcMidnight).getUTCFullYear(), 0, 1);
  const dayOfYear = Math.round((utcMidnight - yearStart) / DAY_MS) + 1;

  const gamma = 2 * Math.PI / 365 * (dayOfYear - 1);
  const eqTime = 229.18 * (0.000075 + 0.001868 * Math.cos(gamma) - 0.032077 * Math.sin(gamma)
                           - 0.014615 * Math.cos(2 * gamma) - 0.040849 * Math.sin(2 * gamma));
  const decl = 0.006918 - 0.399912 * Math.cos(gamma) + 0.070257 * Math.sin(gamma)
      - 0.006758 * Math.cos(2 * gamma) + 0.000907 * Math.sin(2 * gamma)
      - 0.002697 * Math.cos(3 * gamma) + 0.00148 * Math.sin(3 * gamma);
  const lat = latitude * Math.PI / 180;
  const zenith = 90.833 * Math.PI / 180;
  const cosHA = Math.cos(zenith) / (Math.cos(lat) * Math.cos(decl)) - Math.tan(lat) * Math.tan(decl);
  if (!(cosHA >= -1 && cosHA <= 1)) return null;
  const ha = Math.acos(cosHA) * 180 / Math.PI;
  const sunriseMinutes = 720 - 4 * (longitude + ha) - eqTime;
  const sunsetMinutes = 720 - 4 * (longitude - ha) - eqTime;
  return {
    sunrise: new Date(utcMidnight + sunriseMinutes * 60 * 1000),
    sunset: new Date(utcMidnight + sunsetMinutes * 60 * 1000),
  };
}

/**
 * SolarClock.approximateLocation. A rough place for a phone that hasn't said
 * where it is: the time zone's own meridian (15° per hour from UTC), at a
 * temperate 40°N. (The Swift takes the zone's STANDARD offset — daylight time
 * taken back out — so pass the standard offset to match it exactly.)
 * @returns {{ latitude: number, longitude: number }}
 */
export function approximateLocation(tzOffsetHours) {
  return { latitude: 40, longitude: requireOffset(tzOffsetHours) * 15 };
}

/**
 * SolarClock.phase(at:in:). Where `date` falls: through the daylight
 * (progress 0 at sunrise, 1 at sunset) or through the night (0 at sunset,
 * 1 at the next sunrise). `day` is a `solarDay` result.
 * Swift's `.day(p)` is `{ isNight: false, progress: p }`; `.night(q)` is
 * `{ isNight: true, progress: q }`.
 * @returns {{ isNight: boolean, progress: number }}
 */
export function solarPhase(date, day) {
  const now = seconds(date);
  const sunrise = seconds(day.sunrise);
  const sunset = seconds(day.sunset);
  const dayLength = sunset - sunrise;
  const nightLength = Math.max(86_400 - dayLength, 1);
  if (now >= sunrise && now <= sunset && dayLength > 0) {
    return { isNight: false, progress: (now - sunrise) / dayLength };
  }
  if (now > sunset) {
    return { isNight: true, progress: Math.min((now - sunset) / nightLength, 1) };
  }
  return { isNight: true, progress: Math.max(1 - (sunrise - now) / nightLength, 0) };
}

// ────────────────────────────────────────────────────────────── MoonClock ──
// Where the moon is, how much of it is lit and which way its bright edge
// faces, and how far it is through its pass from moonrise to moonset.
//
// The low-precision lunar and solar series used by SunCalc (Agafonkin, after
// Meeus and the astronomy answers at aa.quae.nl): a fraction of a degree in
// position and well under a minute in rise and set.

/** The obliquity of the ecliptic. */
const OBLIQUITY = RAD * 23.4397;

/** MoonClock.horizon: the altitude of the moon's centre at rise and set
 *  (its semi-diameter and refraction already counted in the position). */
const MOON_HORIZON = 0.133 * RAD;
/** MoonClock.searchSpan: how far either side of a moment to look for the
 *  rise and the set — more than a lunar day (≈ 24 h 50 min). Seconds. */
const SEARCH_SPAN = 30 * 3600;
/** MoonClock.searchStep: the coarse search step; each crossing is then
 *  bisected to the second. Seconds. */
const SEARCH_STEP = 600;

/** MoonClock.days(since2000:). Days since J2000.0, from epoch seconds. */
function daysSince2000(t) {
  return t / 86_400 - 0.5 + 2_440_588 - 2_451_545;
}

function rightAscension(l, b) {
  return Math.atan2(Math.sin(l) * Math.cos(OBLIQUITY) - Math.tan(b) * Math.sin(OBLIQUITY), Math.cos(l));
}

function declination(l, b) {
  return Math.asin(Math.sin(b) * Math.cos(OBLIQUITY) + Math.cos(b) * Math.sin(OBLIQUITY) * Math.sin(l));
}

function siderealTime(d, lw) {
  return RAD * (280.16 + 360.9856235 * d) - lw;
}

function altitudeOf(h, phi, dec) {
  return Math.asin(Math.sin(phi) * Math.sin(dec) + Math.cos(phi) * Math.cos(dec) * Math.cos(h));
}

/** Radians from SOUTH, positive towards the west (MoonClock's and SunCalc's
 *  own convention). */
function azimuthFromSouth(h, phi, dec) {
  return Math.atan2(Math.sin(h), Math.cos(h) * Math.sin(phi) - Math.tan(dec) * Math.cos(phi));
}

/** From-south-westward → from-north-clockwise, in [0, 2PI). */
function fromNorth(southWestward) {
  const a = (southWestward + Math.PI) % (2 * Math.PI);
  return a < 0 ? a + 2 * Math.PI : a;
}

/** Bennett's formula, for an altitude in radians (clamped at the horizon so
 *  it stays finite below it). */
function refraction(h) {
  const altitude = Math.max(h, 0);
  return 0.0002967 / Math.tan(altitude + 0.00312536 / (altitude + 0.08901179));
}

function sunCoordinates(d) {
  const m = RAD * (357.5291 + 0.98560028 * d);
  const c = RAD * (1.9148 * Math.sin(m) + 0.02 * Math.sin(2 * m) + 0.0003 * Math.sin(3 * m));
  const perihelion = RAD * 102.9372;
  const longitude = m + c + perihelion + Math.PI;
  return { rightAscension: rightAscension(longitude, 0), declination: declination(longitude, 0), distance: 0 };
}

function moonCoordinates(d) {
  const l0 = RAD * (218.316 + 13.176396 * d);   // mean longitude
  const m = RAD * (134.963 + 13.064993 * d);    // mean anomaly
  const f = RAD * (93.272 + 13.229350 * d);     // mean distance from the node
  const longitude = l0 + RAD * 6.289 * Math.sin(m);
  const latitude = RAD * 5.128 * Math.sin(f);
  return {
    rightAscension: rightAscension(longitude, latitude),
    declination: declination(longitude, latitude),
    distance: 385_001 - 20_905 * Math.cos(m),
  };
}

/** MoonClock.position, at epoch seconds `t`, with MoonClock's own azimuth
 *  (from south, westward). Everything below is built on this. */
function moonAt(t, latitude, longitude) {
  const lw = RAD * -longitude;
  const phi = RAD * latitude;
  const d = daysSince2000(t);
  const moon = moonCoordinates(d);
  const hourAngle = siderealTime(d, lw) - moon.rightAscension;
  let altitude = altitudeOf(hourAngle, phi, moon.declination);
  const parallactic = Math.atan2(Math.sin(hourAngle),
                                 Math.tan(phi) * Math.cos(moon.declination)
                                 - Math.sin(moon.declination) * Math.cos(hourAngle));
  altitude += refraction(altitude);
  return {
    azimuth: azimuthFromSouth(hourAngle, phi, moon.declination),
    altitude,
    distance: moon.distance,
    parallacticAngle: parallactic,
  };
}

function illuminationAt(t) {
  const d = daysSince2000(t);
  const sun = sunCoordinates(d);
  const moon = moonCoordinates(d);
  const sunDistance = 149_598_000.0;
  const elongation = Math.acos(Math.sin(sun.declination) * Math.sin(moon.declination)
                               + Math.cos(sun.declination) * Math.cos(moon.declination)
                               * Math.cos(sun.rightAscension - moon.rightAscension));
  const inclination = Math.atan2(sunDistance * Math.sin(elongation),
                                 moon.distance - sunDistance * Math.cos(elongation));
  const angle = Math.atan2(Math.cos(sun.declination) * Math.sin(sun.rightAscension - moon.rightAscension),
                           Math.sin(sun.declination) * Math.cos(moon.declination)
                           - Math.cos(sun.declination) * Math.sin(moon.declination)
                           * Math.cos(sun.rightAscension - moon.rightAscension));
  return {
    fraction: (1 + Math.cos(inclination)) / 2,
    phase: 0.5 + 0.5 * inclination * (angle < 0 ? -1 : 1) / Math.PI,
    angle,
  };
}

/**
 * NEW — not in the Swift. Where the sun is, from the same solar series
 * MoonClock uses for the moon's light (`sunCoordinates` + sidereal time);
 * this is SunCalc's `getPosition`.
 *
 * `altitude` is the sun's centre above the horizon, WITHOUT refraction
 * (negative below the horizon). At `solarDay`'s sunrise and sunset it reads
 * about −0.83° (−0.0145 rad), which is NOAA's definition of them: the upper
 * limb on a refracted horizon. `azimuth` is from north, clockwise.
 * @returns {{ altitude: number, azimuth: number }}
 */
export function sunPosition(date, latitude, longitude) {
  const lw = RAD * -longitude;
  const phi = RAD * latitude;
  const d = daysSince2000(seconds(date));
  const sun = sunCoordinates(d);
  const hourAngle = siderealTime(d, lw) - sun.rightAscension;
  return {
    altitude: altitudeOf(hourAngle, phi, sun.declination),
    azimuth: fromNorth(azimuthFromSouth(hourAngle, phi, sun.declination)),
  };
}

/**
 * MoonClock.position(at:latitude:longitude:). The moon's place in the sky.
 *
 *   altitude          radians above the horizon, with atmospheric refraction
 *   azimuth           radians from NORTH, clockwise (east = PI/2, south = PI,
 *                     west = 3PI/2), in [0, 2PI)
 *   distance          kilometres from the Earth's centre
 *   parallacticAngle  how far the sky's north on the moon's disc leans from
 *                     the zenith (radians)
 *
 * MoonClock's own `Position.azimuth` is the SunCalc convention instead:
 * radians from SOUTH, positive towards the west, in (−PI, PI]. The value
 * here is that plus PI, wrapped — so MoonClock's azimuth is `azimuth − PI`.
 * @returns {{ altitude: number, azimuth: number, distance: number, parallacticAngle: number }}
 */
export function moonPosition(date, latitude, longitude) {
  const moon = moonAt(seconds(date), latitude, longitude);
  return {
    altitude: moon.altitude,
    azimuth: fromNorth(moon.azimuth),
    distance: moon.distance,
    parallacticAngle: moon.parallacticAngle,
  };
}

/**
 * MoonClock.illumination(at:). How the moon is lit.
 *
 *   fraction  the lit fraction of its face: 0 new, 1 full
 *   phase     0 new, 0.25 first quarter, 0.5 full, 0.75 last quarter
 *   angle     the midpoint of the bright limb, in radians reckoned eastward
 *             from the disc's north point: negative while waxing, positive
 *             waning
 * @returns {{ fraction: number, phase: number, angle: number }}
 */
export function moonIllumination(date) {
  return illuminationAt(seconds(date));
}

/**
 * MoonClock.brightLimbZenithAngle. Which way the bright limb faces as seen
 * from the ground: its angle from the zenith (radians, towards the east — the
 * left as you face the moon). A waxing crescent at dusk is lit low on its
 * right.
 * @returns {number}
 */
export function moonBrightLimbZenithAngle(date, latitude, longitude) {
  const t = seconds(date);
  return illuminationAt(t).angle - moonAt(t, latitude, longitude).parallacticAngle;
}

/** MoonClock.pass, in epoch seconds: `{ rise, set }` (either may be null),
 *  or null while the moon is down. */
function passAround(at, latitude, longitude) {
  const height = (t) => moonAt(t, latitude, longitude).altitude - MOON_HORIZON;
  if (!(height(at) > 0)) return null;
  let rise = null;
  let t = at;
  let current = height(t);
  while (at - t < SEARCH_SPAN) {
    const earlier = t - SEARCH_STEP;
    const before = height(earlier);
    if (before <= 0 && current > 0) {
      rise = crossing(earlier, t, height);
      break;
    }
    t = earlier;
    current = before;
  }
  let set = null;
  t = at;
  current = height(t);
  while (t - at < SEARCH_SPAN) {
    const later = t + SEARCH_STEP;
    const after = height(later);
    if (current > 0 && after <= 0) {
      set = crossing(t, later, height);
      break;
    }
    t = later;
    current = after;
  }
  return { rise, set };
}

/** Bisects to where `height` changes sign between `a` and `b`, to a second. */
function crossing(a, b, height) {
  let low = a;
  let high = b;
  const lowAbove = height(low) > 0;
  while (high - low > 1) {
    const mid = low + (high - low) / 2;
    if ((height(mid) > 0) === lowAbove) low = mid; else high = mid;
  }
  return low + (high - low) / 2;
}

/**
 * MoonClock.pass(around:latitude:longitude:). When the moon last rose before
 * `date` and next sets after it, while it is up at `date`; null while it is
 * below the horizon. Either end is null when it doesn't happen within 30
 * hours (near the poles, where the moon can stay up or down for days).
 * @returns {{ rise: Date | null, set: Date | null } | null}
 */
export function moonPass(date, latitude, longitude) {
  const pass = passAround(seconds(date), latitude, longitude);
  if (pass === null) return null;
  return {
    rise: pass.rise === null ? null : new Date(pass.rise * 1000),
    set: pass.set === null ? null : new Date(pass.set * 1000),
  };
}

/**
 * MoonClock.passProgress. How far the moon is through its pass at `date`:
 * 0 at moonrise, 1 at moonset; null while it is below the horizon. A pass
 * with no rise or no set in reach (near the poles) is put at its middle.
 * @returns {number | null}
 */
export function moonPassProgress(date, latitude, longitude) {
  const at = seconds(date);
  const pass = passAround(at, latitude, longitude);
  if (pass === null) return null;
  const { rise, set } = pass;
  if (rise === null || set === null || !(set > rise)) return 0.5;
  return Math.min(Math.max((at - rise) / (set - rise), 0), 1);
}
