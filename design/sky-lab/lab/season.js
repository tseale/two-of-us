// The land turns with the real season, so his first year reads in the hills:
// bare late-autumn slopes now, snow, blossom, fireflies on summer evenings.
//
// Pure. From the day of the year and the latitude's sign (the southern
// hemisphere is half a year out of step). Everything is continuous — there is no
// day on which the hills change.

import { smoothstep } from './oklab.js';

/** 1 inside [start, end] (days of the year, wrapping past 365), easing in and
 *  out over `soft` days. */
function window(day, start, end, soft) {
  const d = ((day % 365) + 365) % 365;
  const last = end < start ? end + 365 : end;
  const inside = (x) => smoothstep(start - soft, start + soft, x) * (1 - smoothstep(last - soft, last + soft, x));
  return Math.max(inside(d), inside(d + 365), inside(d - 365));
}

/**
 * → {
 *   name,            'winter' | 'spring' | 'summer' | 'autumn' (the strongest)
 *   weights,         { winter, spring, summer, autumn } summing to 1
 *   snow,            0–1 snow lying on the land
 *   snowfall,        0–1 snow in the air (only some days — `daySeed` picks them)
 *   foliage,         0 bare branches … 1 full leaf
 *   leafHue,         0 fresh spring green · 0.5 deep summer green · 0.8 amber · 1 russet
 *   leafFall,        0–1 leaves in the air
 *   blossom,         0–1 trees in flower
 *   petals,          0–1 petals in the air
 *   fireflies,       0–1 (a sky shows them only from dusk)
 *   grass,           0 dormant straw … 1 green
 *   frost            0–1 hoar on the ground at dawn
 * }
 */
export function season(dayOfYear, latitude = 41.88) {
  const day = latitude < 0 ? dayOfYear + 182.5 : dayOfYear;
  const angle = (2 * Math.PI * (day - 15)) / 365;           // 0 in mid-January
  const raw = {
    winter: Math.max(0, Math.cos(angle)),
    spring: Math.max(0, Math.sin(angle)),
    summer: Math.max(0, -Math.cos(angle)),
    autumn: Math.max(0, -Math.sin(angle)),
  };
  const total = raw.winter + raw.spring + raw.summer + raw.autumn;
  const weights = Object.fromEntries(Object.entries(raw).map(([k, v]) => [k, v / total]));
  const name = Object.entries(weights).sort((a, b) => b[1] - a[1])[0][0];

  const snow = window(day, 345, 60, 12);                     // mid-December → early March
  const foliage = window(day, 115, 305, 16);                 // leafing out late April, bare by mid-November
  const turning = smoothstep(255, 300, ((day % 365) + 365) % 365);   // mid-September → late October
  const greening = 1 - smoothstep(115, 165, ((day % 365) + 365) % 365);
  const leafHue = turning > 0 ? 0.5 + 0.5 * turning : 0.5 - 0.5 * greening;
  const blossom = window(day, 105, 135, 9);                  // mid-April → mid-May
  const fireflies = window(day, 160, 232, 12);               // June → mid-August
  const leafFall = window(day, 275, 322, 10);                // October → mid-November
  const grass = window(day, 95, 300, 22);
  const frost = window(day, 300, 345, 14) * (1 - snow) + window(day, 60, 95, 12) * (1 - snow);

  // Snow falls on about two winter days in five; the lab can force it with snowfall=1.
  const seed = Math.sin(Math.floor(dayOfYear) * 127.1) * 43758.5453;
  const daySeed = seed - Math.floor(seed);
  const snowfall = snow > 0.5 && daySeed < 0.4 ? 0.5 + daySeed : 0;

  return { name, weights, snow, snowfall, foliage, leafHue, leafFall, blossom, petals: blossom * 0.8,
           fireflies, grass, frost };
}
