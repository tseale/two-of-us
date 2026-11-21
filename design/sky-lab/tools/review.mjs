#!/usr/bin/env node
// The review set: every sky photographed the same way, so directions can be
// laid side by side. A thin wrapper over tools/shoot.mjs.
//
//   node tools/review.mjs --sky <id>                 everything (about 2 minutes)
//   node tools/review.mjs --sky <id> --only day,open just those sets
//   node tools/review.mjs --list                     the sets and what is in them
//
// Output: shots/<sky>/review/<set>/[<frame>/]<device>-<scheme>-<HHMM>[-<asleep>].png

import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { solarDay } from '../lab/solar.js';

const LAB = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const LAT = 41.88, LON = -87.63;

/** Local HH:MM, `offsetMinutes` from that local day's sunset. */
function fromSunset(dateText, tz, offsetMinutes) {
  const [y, m, d] = dateText.split('-').map(Number);
  const noon = new Date(Date.UTC(y, m - 1, d, 12 - tz));
  const { sunset } = solarDay(noon, LAT, LON, tz);
  const local = new Date(sunset.getTime() + (tz * 60 + offsetMinutes) * 60000);
  return `${String(local.getUTCHours()).padStart(2, '0')}:${String(local.getUTCMinutes()).padStart(2, '0')}`;
}

// He was born on 2 July 2026 in the lab's story (142 days old on 21 November).
const SEASONS = [
  { name: 'autumn', date: '2026-10-15', tz: -5, age: 105 },
  { name: 'winter', date: '2027-01-15', tz: -6, age: 197 },
  { name: 'spring', date: '2027-04-28', tz: -5, age: 300 },
  { name: 'summer', date: '2027-07-04', tz: -5, age: 367 },
];

// Bedtime: the cards fall back for a few seconds while his star is lit, then
// return. `veil` is how far back they are (1 = gone; the header and the system
// strip stay). On the spread the leading page goes with them.
const BEDTIME = [
  { age: 0, veil: 0 }, { age: 0.7, veil: 0.5 }, { age: 1.6, veil: 1 }, { age: 3, veil: 1 },
  { age: 5, veil: 1 }, { age: 6.5, veil: 0.5 }, { age: 9, veil: 0 }, { age: 40, veil: 0 },
];

// Opening the Duo: the panorama holds on the leading page before its cards land.
const OPEN = [
  { age: 0, lead: 0 }, { age: 0.45, lead: 0 }, { age: 1.1, lead: 0.3 },
  { age: 1.8, lead: 1 }, { age: 3, lead: 1 }, { age: 8, lead: 1 },
];

const frame = (age) => `t${String(age).replace('.', '_')}`;

function sets() {
  const out = [];
  out.push({ name: 'day', about: 'The standard matrix: 3 devices × 2 schemes × 8 hours, with sheets.', runs: [{ dir: '', args: ['--sheet'] }] });
  out.push({ name: 'bare', about: 'The same with the UI off: the picture whole.', runs: [{ dir: '', args: ['--sheet', '--chrome', '0'] }] });
  out.push({
    name: 'asleep', about: 'A night sleep running: 19:40, 21:00, 03:00.',
    runs: [{ dir: '', args: ['--sheet', '--times', '19:40,21:00,03:00', '--asleep', 'night'] },
           { dir: 'nap', args: ['--sheet', '--times', '09:30,13:10', '--asleep', 'nap'] }],
  });
  out.push({
    name: 'seasons', about: 'His first year: mid-October, mid-January, late April, early July — each 14 min before sunset and 40 min after, cover and spread, UI on; plus the spread bare.',
    runs: SEASONS.flatMap((s) => {
      const times = `${fromSunset(s.date, s.tz, -14)},${fromSunset(s.date, s.tz, 40)}`;
      const base = ['--date', s.date, '--tz', String(s.tz), '--age', String(s.age), '--times', times];
      return [
        { dir: s.name, args: [...base, '--devices', 'cover,spread'] },
        { dir: `${s.name}-bare`, args: [...base, '--devices', 'spread', '--chrome', '0'] },
      ];
    }),
  });
  out.push({
    name: 'bedtime', about: 'He goes down for the night at 19:40 — in November (full dark) and in July (the sun still up). Eight instants; the cards fall back and return.',
    runs: [{ key: 'november', extra: [] }, { key: 'july', extra: ['--date', '2027-07-04', '--tz', '-5', '--age', '367'] }].flatMap((when) =>
      BEDTIME.map((f) => ({
        dir: `${when.key}/${frame(f.age)}`,
        args: [...when.extra, '--times', '19:40', '--asleep', 'night', '--event', 'bedtime', '--event-age', String(f.age),
               '--param', `veil=${f.veil}`, '--lead', String(1 - f.veil)],
      }))),
  });
  out.push({
    name: 'open', about: 'The Duo opens — at golden hour, at midday, at night. Six instants; the leading page\'s cards land after a beat.',
    runs: [{ key: 'golden', time: fromSunset('2026-11-21', -6, -14), asleep: '0' }, { key: 'midday', time: '12:30', asleep: '0' },
           { key: 'night', time: '21:00', asleep: 'night' }].flatMap((when) =>
      OPEN.map((f) => ({
        dir: `${when.key}/${frame(f.age)}`,
        args: ['--devices', 'spread', '--times', when.time, '--asleep', when.asleep, '--event', 'open',
               '--event-age', String(f.age), '--lead', String(f.lead)],
      }))),
  });
  out.push({
    name: 'still', about: 'Reduce Motion (motion=0) at four hours, and a second instant of the animation (t=95) to compare drift against the day set.',
    runs: [{ dir: 'reduce-motion', args: ['--motion', '0', '--times', '09:30,16:10,21:00', '--devices', 'cover,spread'] },
           { dir: 't95', args: ['--t', '95', '--times', '09:30,16:10,21:00', '--devices', 'cover,spread'] }],
  });
  return out;
}

function main() {
  const argv = process.argv.slice(2);
  const value = (flag) => { const i = argv.indexOf(flag); return i >= 0 ? argv[i + 1] : null; };
  const all = sets();
  if (argv.includes('--list') || argv.includes('--help')) {
    for (const s of all) process.stdout.write(`${s.name.padEnd(9)} ${s.about}\n${s.runs.map((r) => `            ${r.dir || '.'}  ${r.args.join(' ')}`).join('\n')}\n`);
    return;
  }
  const sky = value('--sky');
  if (!sky) { process.stderr.write('review: --sky <id> is required (--list shows the sets)\n'); process.exit(1); }
  const only = value('--only')?.split(',').map((s) => s.trim());
  const chosen = only ? all.filter((s) => only.includes(s.name)) : all;
  if (!chosen.length) { process.stderr.write(`review: no such set (${all.map((s) => s.name).join(', ')})\n`); process.exit(1); }
  const started = Date.now();
  let failed = 0;
  for (const set of chosen) {
    for (const run of set.runs) {
      const out = path.join(LAB, 'shots', sky, 'review', set.name, run.dir);
      const result = spawnSync(process.execPath, [path.join(LAB, 'tools/shoot.mjs'), '--sky', sky, '--out', out, ...run.args],
        { cwd: LAB, encoding: 'utf8' });
      const last = (result.stdout || '').trim().split('\n').pop() || '';
      if (result.status !== 0) { failed += 1; process.stderr.write(`review: ${set.name}/${run.dir} FAILED\n${result.stderr || result.stdout}\n`); }
      else process.stdout.write(`${set.name}/${run.dir || '.'}: ${last.replace(/^shoot: /, '')}\n`);
    }
  }
  process.stdout.write(`review: ${chosen.map((s) => s.name).join(', ')} in ${((Date.now() - started) / 1000).toFixed(0)} s → shots/${sky}/review/\n`);
  if (failed) process.exit(1);
}

main();
