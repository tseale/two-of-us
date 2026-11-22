#!/usr/bin/env node
// The review set: every sky photographed the same way, so directions can be
// laid side by side. A thin wrapper over tools/shoot.mjs.
//
//   node tools/review.mjs --sky <id>                 everything: 718 shots in 117 runs (--list counts them).
//                                                    Minutes for a 2-D canvas sky; a shader sky in software GL
//                                                    is ~3 s a shot at --jobs 2 (README)
//   node tools/review.mjs --sky <id> --only day,open just those sets
//   node tools/review.mjs --list                     the sets, what is in them, and how many shots
//   … --jobs 2 --timeout 120                         passed on to shoot.mjs (a busy machine, a heavy shader)
//   … --out <dir>                                    somewhere else than shots/<sky>/review
//
// Output: shots/<sky>/review/<set>/[<frame>/]<device>-<scheme>-<HHMM>[-<asleep>].png

import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { solarDay } from '../lab/solar.js';
import { joins, framesOf, firstLightTime } from './joins.mjs';
import { momentVeil } from '../lab/presence.js';

const LAB = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const LAT = 41.88, LON = -87.63;

/** What a run makes: [shots, sheets] (three devices, two schemes and eight hours unless its arguments say otherwise). */
function countOf(run) {
  const list = (flag, fallback) => { const i = run.args.indexOf(flag); return i >= 0 ? run.args[i + 1].split(',').length : fallback; };
  const devices = list('--devices', 3);
  return [devices * 2 * list('--times', 8), run.args.includes('--sheet') ? devices * 2 : 0];
}

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
// strip stay). On the spread the leading page goes with them. The same curve as
// tools/film.mjs's (`UI.bedtime`), which is the moment's own (lab/presence.js,
// `momentVeil`): back over 0–1.0 s, away until 4.6 s, returned by 5.8 s with an
// ease-out — over the sky that is already there (BRIEF.md, round three: the view
// does not come down again). The instants: the tap; the cards half away (0.5 s);
// the cards gone and the view rising (1 s); the held frame with the band crossing
// (3 s) and after it (4.1 s, the poster: the caption still whole); the cards half
// back (5 s); back (9 s); settled.
const veilAt = (age) => Math.round(momentVeil(age) * 1000) / 1000;
const BEDTIME = [0, 0.5, 1, 3, 4.1, 5, 9, 40].map((age) => ({ age, veil: veilAt(age) }));

// A night sleep that arrives from elsewhere (the other phone, Siri, a widget)
// while Home is on screen, at 19:40: the quiet rise behind the cards, 0 to 1 over
// 2.5 s (asleep=night, event=arrive). No card choreography. The instants: the
// frame it arrives; a third of the way up; half way; up; the room dimmed.
const ARRIVE = [0, 0.8, 1.25, 2.5, 6];

// First light, he still sleeps (asleep=night, event=settle, at the first minute
// the sun is over the lab's threshold): the quiet settle behind the cards, down
// over 0.1–2.7 s. The instants: first light; a third down; half way; down; after.
const SETTLE = [0, 0.9, 1.4, 2.7, 6];

// Opening the Duo: the panorama holds on the leading page before its cards land.
const OPEN = [
  { age: 0, lead: 0 }, { age: 0.45, lead: 0 }, { age: 1.1, lead: 0.3 },
  { age: 1.8, lead: 1 }, { age: 3, lead: 1 }, { age: 8, lead: 1 },
];

// The joins (tools/joins.mjs): a viewer parameter → the shoot.mjs option that sets it.
const SHOOT_FLAG = { time: '--times', asleep: '--asleep', date: '--date', tz: '--tz', age: '--age', event: '--event',
  eventAge: '--event-age', woke: '--woke', begun: '--begun' };
const JUNE = ['--date', '2027-06-21', '--tz', '-5', '--age', '354'];

// The minutes the sun (mid-morning) and the moon (early evening) cross the
// header's text on the default day.
const TEXT_TIMES = '09:30,09:50,10:10,10:30,17:00,17:40,18:20,19:00,19:40';

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
    name: 'seasons', about: 'His first year: mid-October, mid-January, late April, early July — each 14 min before sunset and 40 min after, all three devices, UI on; plus the spread bare.',
    runs: SEASONS.flatMap((s) => {
      const times = `${fromSunset(s.date, s.tz, -14)},${fromSunset(s.date, s.tz, 40)}`;
      const base = ['--date', s.date, '--tz', String(s.tz), '--age', String(s.age), '--times', times];
      return [
        { dir: s.name, args: [...base, '--devices', 'cover,spread,iphone'] },
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
    name: 'still', about: 'Reduce Motion (motion=0) at three hours, and a second instant of the animation (t=95) to compare drift against the day set.',
    runs: [{ dir: 'reduce-motion', args: ['--motion', '0', '--times', '09:30,16:10,21:00', '--devices', 'cover,spread'] },
           { dir: 't95', args: ['--t', '95', '--times', '09:30,16:10,21:00', '--devices', 'cover,spread'] }],
  });
  out.push({
    name: 'text', about: 'The header\'s text against the sun (09:30–10:30) and the moon (17:00–19:40) as they pass behind it: all three devices, UI on, and bare.',
    runs: [{ dir: '', args: ['--sheet', '--times', TEXT_TIMES] },
           { dir: 'bare', args: ['--sheet', '--times', TEXT_TIMES, '--chrome', '0'] }],
  });
  out.push({
    name: 'tilt', about: 'Parallax at its two ends, tilt −1,−0.5 and 1,0.5, at 16:10 and 21:00 on the cover and the spread (the day set has them level).',
    runs: [{ dir: 'left-up', tilt: '-1,-0.5' }, { dir: 'right-down', tilt: '1,0.5' }].map((end) => (
      { dir: end.dir, args: ['--devices', 'cover,spread', '--times', '16:10,21:00', '--tilt', end.tilt] })),
  });
  out.push({
    name: 'snow', about: 'Snow in the air (snowfall=1) on the winter day: mid-January, 14 min before sunset and 40 min after, cover and spread.',
    runs: SEASONS.filter((s) => s.name === 'winter').map((s) => ({
      dir: '',
      args: ['--date', s.date, '--tz', String(s.tz), '--age', String(s.age),
             '--times', `${fromSunset(s.date, s.tz, -14)},${fromSunset(s.date, s.tz, 40)}`,
             '--devices', 'cover,spread', '--snowfall', '1'],
    })),
  });
  out.push({
    name: 'night', about: 'The night as it stands (BRIEF.md: Home looks up from the night sleep\'s start until first light): awake at 18:30 (before bedtime: at rest), 21:00 and 03:00 (a feed: up, star lit); asleep at 06:10 (up) and 07:30 (after first light: at rest, dimmed); asleep at 05:30 and 08:00 on 21 June (the day, dimmed). With the UI and bare. Sheets.',
    runs: [['', []], ['-bare', ['--chrome', '0']]].flatMap(([suffix, extra]) => [
      { dir: `awake${suffix}`, args: ['--sheet', '--times', '18:30,21:00,03:00', ...extra] },
      { dir: `asleep-nov${suffix}`, args: ['--sheet', '--times', '06:10,07:30', '--asleep', 'night', ...extra] },
      { dir: `asleep-jun${suffix}`, args: ['--sheet', ...JUNE, '--times', '05:30,08:00', '--asleep', 'night', ...extra] },
    ]),
  });
  out.push({
    name: 'arrive', about: 'A night sleep arrives from elsewhere at 19:40 (asleep=night, event=arrive): the quiet rise behind the cards, five instants, 0 to 6 s. No veil.',
    runs: ARRIVE.map((age) => ({ dir: frame(age), args: ['--times', '19:40', '--asleep', 'night', '--event', 'arrive', '--event-age', String(age)] })),
  });
  out.push({
    name: 'settle', about: `First light with him still asleep (${firstLightTime({})}, asleep=night, event=settle): the quiet settle behind the cards, five instants, 0 to 6 s.`,
    runs: SETTLE.map((age) => ({ dir: frame(age), args: ['--times', firstLightTime({}), '--asleep', 'night', '--event', 'settle', '--event-age', String(age)] })),
  });
  out.push({
    name: 'joins', about: 'No join may jump (tools/joins.mjs measures them): for every change of state, the standing frame before | the event\'s first frame, and the event\'s last frame | the standing frame after. Cover, both schemes, UI on.',
    runs: joins().flatMap((join) => framesOf(join).map((f) => ({
      dir: `${join.id}/${f.frame}`,
      args: ['--devices', 'cover', ...Object.entries(f.params).flatMap(([key, value]) => [SHOOT_FLAG[key], String(value)])],
    }))),
  });
  return out;
}

function main() {
  const argv = process.argv.slice(2);
  const value = (flag) => { const i = argv.indexOf(flag); return i >= 0 ? argv[i + 1] : null; };
  const all = sets();
  if (argv.includes('--list') || argv.includes('--help')) {
    let shots = 0, sheets = 0, runs = 0;
    for (const s of all) {
      const counts = s.runs.map(countOf);
      const mine = counts.reduce((sum, c) => sum + c[0], 0);
      shots += mine; sheets += counts.reduce((sum, c) => sum + c[1], 0); runs += s.runs.length;
      process.stdout.write(`${s.name.padEnd(9)} ${s.about} (${mine} shots)\n${s.runs.map((r) => `            ${r.dir || '.'}  ${r.args.join(' ')}`).join('\n')}\n`);
    }
    process.stdout.write(`\n${shots} shots and ${sheets} sheets in ${runs} runs of shoot.mjs\n`);
    return;
  }
  const unknown = argv.filter((arg, i) => arg.startsWith('--') && !['--sky', '--only', '--jobs', '--timeout', '--out'].includes(arg)
    && !(i > 0 && argv[i - 1] === '--only'));
  if (unknown.length) { process.stderr.write(`review: unknown option ${unknown.join(', ')} (--sky, --only, --out, --jobs, --timeout, --list)\n`); process.exit(1); }
  const sky = value('--sky');
  if (!sky) { process.stderr.write('review: --sky <id> is required (--list shows the sets)\n'); process.exit(1); }
  const only = value('--only')?.split(',').map((s) => s.trim());
  const chosen = only ? all.filter((s) => only.includes(s.name)) : all;
  if (!chosen.length) { process.stderr.write(`review: no such set (${all.map((s) => s.name).join(', ')})\n`); process.exit(1); }
  const pass = ['--jobs', '--timeout'].flatMap((flag) => (value(flag) ? [flag, value(flag)] : []));
  // --out: the set's root, instead of shots/<sky>/review (relative to where you run it).
  const root = value('--out') ? path.resolve(process.cwd(), value('--out')) : path.join(LAB, 'shots', sky, 'review');
  const started = Date.now();
  let failed = 0;
  for (const set of chosen) {
    for (const run of set.runs) {
      const out = path.join(root, set.name, run.dir);
      const result = spawnSync(process.execPath, [path.join(LAB, 'tools/shoot.mjs'), '--sky', sky, '--out', out, ...run.args, ...pass],
        { cwd: LAB, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
      // shoot.mjs's own summary ("48/48 shots, 6 sheets in … (13.2 s)") is the last line it writes to stderr.
      const last = (result.stderr || '').trim().split('\n').filter((line) => /^shoot: \d+\/\d+ shots/.test(line)).pop() || '';
      if (result.status !== 0) { failed += 1; process.stderr.write(`review: ${set.name}/${run.dir} FAILED\n${result.stderr || result.stdout}\n`); }
      else process.stdout.write(`${set.name}/${run.dir || '.'}: ${last.replace(/^shoot: /, '')}\n`);
    }
  }
  const where = path.relative(process.cwd(), root);
  process.stdout.write(`review: ${chosen.map((s) => s.name).join(', ')} in ${((Date.now() - started) / 1000).toFixed(0)} s → ${where && !where.startsWith('..') ? where : root}/\n`);
  if (failed) process.exit(1);
}

main();
