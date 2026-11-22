// Home's UI as HTML, drawn over the sky: the phone page, the spread's leading
// page, and the system strip / tab bar. A mockup of what the app draws today —
// laid out from the Swift, not from screenshots:
//
//   TwoOfUs/Features/Home/HomeView.swift        compactList, header, timelineSection,
//                                               tonightCard, spreadDetailsPage
//   TwoOfUs/Features/Home/TodayHeroCard.swift   the Today card and its DayFlowStrip
//   TwoOfUs/Features/Home/LogButtons.swift      the three log tiles
//   TwoOfUs/Features/Sleep/SleepActiveCard.swift
//   TwoOfUs/Features/Timeline/DayTimelineView.swift
//   TwoOfUs/Features/Home/SpreadDetailViews.swift, Shared/{PageTitle,SpreadGrid,PhonePage}.swift
//
//   createChrome(root, options?) → { update(state) → cards, layout, destroy() }
//   sampleNight() → { bedtime, wake }   the sample day's night, for state.tonightLit
//
// `root` is an empty <div> filling the display over the sky. Its background
// stays transparent. Styles: lab/chrome.css (index.html links it).

// ─────────────────────────────────────────────────────────────── geometry ──

/** Points. `top` is where the header starts; `side` the page's side margin. */
const DEVICES = {
  // iPhone Duo closed: nothing across the top, the system strip down the trailing edge.
  cover: { width: 466, height: 678, strip: 84, side: 20, top: 22, bottomInset: 34 },
  // iPhone Duo open: the phone page is the cover's page, moved (PhonePage.frame).
  spread: { width: 951, height: 669, strip: 84, side: 20, top: 22, bottomInset: 34 },
  // A slab iPhone (17 Pro): 62 pt status bar, then the list's own 8 pt.
  iphone: { width: 402, height: 874, strip: 0, side: 16, top: 70, bottomInset: 34, statusBar: 62 },
};

/** SpreadGrid on the 951 × 669 display. */
const GRID = { leadingX: 97.5, pageWidth: 350, headY: 22, top: 103, surfaceGap: 12 };

/** The phone page's content width on the Duo (PhonePage.closedContentWidth). */
const CLOSED_CONTENT_WIDTH = 382;

// ───────────────────────────────────────────────────────────── the family ──

// The names the app's own demo world uses (Store/DemoData.swift): Alex is this
// phone's parent ("You"), Jordan the co-parent. The baby is Miller.
const BABY = { name: 'Miller', color: '#5AC8B8' };
const PEOPLE = {
  A: { name: 'Alex', color: '#5AC8B8', me: true },
  J: { name: 'Jordan', color: '#FF8FA3', me: false },
};

// SharedSettings, as this household has them: bottles every 3 h, and a night
// window of 9 PM – 5 AM — which is what makes the leading page's moments fall
// at 5 / 10 / 17 / 21 o'clock (HomeView.detailsMoment).
const SETTINGS = { feedTarget: 180, diaperTarget: 180, nightStart: 21 * 60, nightEnd: 5 * 60, nightSpacing: 180 };
/** WakeWindow.predicted for a four-month-old with a week of naps behind him. */
const WAKE_WINDOW = 110;

// One ordinary day at four months, in minutes from local midnight. Every day
// is this day (earlier days shifted by a few minutes), so the time slider
// moves "now" across a day that stays put.
const TEMPLATE = {
  // [start, end] — the last one runs past midnight.
  sleeps: [[85, 245], [275, 400], [505, 550], [675, 760], [875, 925], [1060, 1105], [1210, 1495]],
  // [time, oz, who, note?]
  feeds: [
    [60, 4, 'J'], [250, 3.5, 'A'], [430, 5, 'A'], [590, 4, 'J'],
    [775, 5.5, 'J'], [950, 4.5, 'A'], [1125, 5, 'J'], [1310, 4, 'A', 'Dream feed'],
  ],
  // [time, type, who]
  diapers: [
    [68, 'wet', 'J'], [255, 'wet', 'A'], [405, 'wet', 'A'], [555, 'dirty', 'A'],
    [765, 'wet', 'J'], [935, 'both', 'A'], [1112, 'wet', 'J'], [1175, 'wet', 'A'], [1318, 'wet', 'A'],
  ],
};
// Standalone notes, by day offset: [time, who, text].
const NOTES = {
  0: [[810, 'A', 'Rolled front to back twice on the play mat!']],
  '-1': [[1040, 'A', 'Giggled at the ceiling fan for ten minutes']],
};

// ────────────────────────────────────────────────────────────── formatting ──

const NNBSP = ' ';
const WEEKDAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const clamp = (v, lo, hi) => Math.min(Math.max(v, lo), hi);
const px = (v) => `${Math.round(v * 100) / 100}px`;

/** TimeFormatting.clock — "2:14 PM". `m` is minutes from today's midnight (any day). */
function clock(m) {
  const t = ((Math.round(m) % 1440) + 1440) % 1440;
  const h = Math.floor(t / 60);
  return `${h % 12 || 12}:${String(t % 60).padStart(2, '0')}${NNBSP}${h < 12 ? 'AM' : 'PM'}`;
}

/** TimeFormatting.duration(minutes:) — "6h 30m", "45m", "2h". */
function duration(mins) {
  const total = Math.max(0, Math.round(mins));
  const h = Math.floor(total / 60);
  const m = total % 60;
  if (h === 0) return `${m}m`;
  return m === 0 ? `${h}h` : `${h}h ${m}m`;
}

/** TimeFormatting.since — "just now" under a minute. */
const since = (mins) => (mins < 1 ? 'just now' : duration(Math.floor(mins)));

/** WakeWindow.shortLabel — "1h50m". */
function shortLabel(mins) {
  const total = Math.max(0, Math.round(mins));
  const h = Math.floor(total / 60);
  const m = total % 60;
  if (h === 0) return `${m}m`;
  return m === 0 ? `${h}h` : `${h}h${m}m`;
}

/** OzFormat.string — "4", "4.5", "3.75". */
function oz(v) {
  if (v === Math.round(v)) return String(Math.round(v));
  const s = v.toFixed(2);
  return s.endsWith('0') ? s.slice(0, -1) : s;
}

const plural = (n, unit) => `${n} ${unit}${n === 1 ? '' : 's'}`;

/** "8p", "2a" — NightsChart's axis. */
function hourNarrow(m) {
  const h = Math.floor((((Math.round(m) % 1440) + 1440) % 1440) / 60);
  return `${h % 12 || 12}${h < 12 ? 'a' : 'p'}`;
}

// SleepLanguage: a sleep that starts 8 PM – 6 AM is a sleep; a daytime one is
// a nap until it passes two hours.
const startsAtNight = (m) => {
  const h = Math.floor((((m % 1440) + 1440) % 1440) / 60);
  return h >= 20 || h < 6;
};
const isNap = (start, end) => !startsAtNight(start) && end - start < 120;
const gerund = (start, now) => (isNap(start, now) ? 'napping' : 'sleeping');
const sleepNoun = (start, end) => (isNap(start, end) ? 'Nap' : 'Sleep');
// The running sleep's word. `asleep=night` says this is the night's sleep, so it
// is "sleeping" whenever it began (SleepActiveCard's eyebrow for a night sleep is
// "MILLER IS SLEEPING"); otherwise SleepLanguage's clock rule decides, as above.
// This is the lab's licence, not the app's rule: the app goes by the clock alone,
// so a sleep begun at 19:36 reads "napping" there until it has run two hours.
const runningWord = (sleep, now) => (sleep.night ? 'sleeping' : gerund(sleep.start, now));

/**
 * The sample day's night, in minutes from local midnight: `bedtime` is when he
 * goes down for the night (the first sleep of the evening that SleepLanguage
 * calls a sleep), `wake` when the last sleep of the small hours ends. Null if
 * the template has no such night. lab/core.js's `state.tonightLit` keeps a
 * copy of these two numbers (tools/test-math.mjs checks they agree).
 */
export function sampleNight() {
  const evening = TEMPLATE.sleeps.filter(([start]) => start >= 720 && startsAtNight(start)).map(([start]) => start);
  const morning = TEMPLATE.sleeps.filter(([start]) => start < 720 && startsAtNight(start)).map(([, end]) => end);
  if (!evening.length || !morning.length) return null;
  return { bedtime: Math.min(...evening), wake: Math.max(...morning) };
}

// ───────────────────────────────────────────────────────────────── icons ──

const svg = (w, h, vb, body, extra = '') =>
  `<svg width="${w}" height="${h}" viewBox="${vb}" fill="none" ${extra}aria-hidden="true">${body}</svg>`;

/** A four-point sparkle centred on (cx, cy). */
const sparkle = (cx, cy, r) =>
  `M${cx} ${cy - r}Q${cx + r * 0.16} ${cy - r * 0.16} ${cx + r} ${cy}Q${cx + r * 0.16} ${cy + r * 0.16} ${cx} ${cy + r}` +
  `Q${cx - r * 0.16} ${cy + r * 0.16} ${cx - r} ${cy}Q${cx - r * 0.16} ${cy - r * 0.16} ${cx} ${cy - r}Z`;

function gearOutline() {
  const teeth = 8;
  const step = (Math.PI * 2) / teeth;
  const pts = [];
  for (let i = 0; i < teeth; i += 1) {
    const a = i * step - Math.PI / 2;
    for (const [r, da] of [[7.0, -0.3], [9.4, -0.17], [9.4, 0.17], [7.0, 0.3]]) {
      pts.push(`${(12 + r * Math.cos(a + da * step)).toFixed(2)} ${(12 + r * Math.sin(a + da * step)).toFixed(2)}`);
    }
  }
  return `M${pts.join('L')}Z`;
}

const ICON = {
  // gearshape (title3)
  gear: svg(24, 24, '0 0 24 24',
    `<path d="${gearOutline()}" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/>` +
    '<circle cx="12" cy="12" r="3.1" stroke="currentColor" stroke-width="1.6"/>'),
  plus: (size, weight = 2.2) => svg(size, size, '0 0 12 12',
    `<path d="M6 1.6v8.8M1.6 6h8.8" stroke="currentColor" stroke-width="${weight}" stroke-linecap="round"/>`),
  // The ⊕ badge's own plus: 10.2 pt long, 2.2 pt thick in the 22 pt disc (measured on the app).
  badgePlus: svg(22, 22, '0 0 22 22',
    '<path d="M11 7v8M7 11h8" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/>'),
  // circle.fill / exclamationmark.circle.fill at 12 pt bold: a 12 pt disc in a
  // frame about 14 pt wide (an SF Symbol's frame is wider than its disc).
  dot: svg(13.8, 13.5, '0 0 13.8 13.5', '<circle cx="6.9" cy="6.75" r="6" fill="currentColor"/>'),
  alert: svg(13.8, 13.5, '0 0 13.8 13.5',
    '<circle cx="6.9" cy="6.75" r="6" fill="currentColor"/><path d="M6.9 3.55v3.7" stroke="#fff" stroke-width="1.6" stroke-linecap="round"/><circle cx="6.9" cy="9.75" r="0.95" fill="#fff"/>'),
  pencil: svg(11, 11, '0 0 12 12',
    '<path d="M8.3 1.6l2.1 2.1-6.3 6.3-2.7.6.6-2.7 6.3-6.3z" stroke="currentColor" stroke-width="1.2" stroke-linejoin="round"/>'),
  chevron: svg(7, 11, '0 0 7 11', '<path d="M1.2 1.2l4.3 4.3-4.3 4.3" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/>'),
  chevrons: svg(14, 11, '0 0 14 11',
    '<path d="M1.5 1.4l4 4.1-4 4.1M8 1.4l4 4.1-4 4.1" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>'),
  check: svg(18, 16, '0 0 18 16', '<path d="M2 8.6l4.6 4.8L16 2.4" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/>'),
  checkCircle: svg(12, 12, '0 0 12 12',
    '<circle cx="6" cy="6" r="6" fill="currentColor"/><path d="M3.3 6.2l1.9 1.9 3.6-4" stroke="#fff" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/>'),
  sun: svg(22, 22, '0 0 22 22',
    '<circle cx="11" cy="11" r="4.1" stroke="currentColor" stroke-width="2.1"/>' +
    '<path d="M11 1.6v2.2M11 18.2v2.2M1.6 11h2.2M18.2 11h2.2M4.35 4.35l1.55 1.55M16.1 16.1l1.55 1.55M4.35 17.65l1.55-1.55M16.1 5.9l1.55-1.55" stroke="currentColor" stroke-width="2.1" stroke-linecap="round"/>'),
  moonZzz: svg(12, 12, '0 0 12 12',
    '<path d="M5.2 1.3a5 5 0 1 0 5.4 6.6 4.2 4.2 0 0 1-5.4-6.6z" fill="currentColor"/>' +
    '<path d="M7.6 1.2h2.6L7.6 4.2h2.6" stroke="currentColor" stroke-width="1" stroke-linecap="round" stroke-linejoin="round"/>'),
  clock: svg(11, 11, '0 0 12 12',
    '<circle cx="6" cy="6" r="4.9" stroke="currentColor" stroke-width="1.1"/><path d="M6 3.2V6l1.9 1.2" stroke="currentColor" stroke-width="1.1" stroke-linecap="round" stroke-linejoin="round"/>'),
  moonStarsSmall: svg(11, 11, '0 0 24 24',
    `<path d="M11.4 4.2a8.6 8.6 0 1 0 8.9 11.6 7.2 7.2 0 0 1-8.9-11.6z" fill="currentColor"/><path d="${sparkle(17.6, 5.4, 3.4)}" fill="currentColor"/>`),
  // Tab icons: house.fill, moon.stars.fill, chart.bar.xaxis, sparkles.
  house: svg(26, 26, '0 0 24 24',
    '<path d="M12.9 3.1a1.4 1.4 0 0 0-1.8 0L3 10.1a1.1 1.1 0 0 0 .7 1.95h.9V19a1.9 1.9 0 0 0 1.9 1.9h3.1v-4.7a1 1 0 0 1 1-1h2.8a1 1 0 0 1 1 1v4.7h3.1a1.9 1.9 0 0 0 1.9-1.9v-6.95h.9a1.1 1.1 0 0 0 .7-1.95l-8.1-7z" fill="currentColor"/>'),
  moonStars: svg(26, 26, '0 0 24 24',
    `<path d="M10.6 4.6a8.4 8.4 0 1 0 9.2 11.3 7 7 0 0 1-9.2-11.3z" fill="currentColor"/>` +
    `<path d="${sparkle(16.9, 5.7, 3.3)}" fill="currentColor"/><path d="${sparkle(20.9, 10.3, 1.9)}" fill="currentColor"/>`),
  chart: svg(26, 26, '0 0 24 24',
    '<rect x="4.2" y="10.4" width="3.5" height="7.2" rx="1" fill="currentColor"/><rect x="8.6" y="5" width="3.5" height="12.6" rx="1" fill="currentColor"/>' +
    '<rect x="13" y="7.8" width="3.5" height="9.8" rx="1" fill="currentColor"/><rect x="17.4" y="11.6" width="3.5" height="6" rx="1" fill="currentColor"/>' +
    '<rect x="2.6" y="19.3" width="18.8" height="1.7" rx="0.85" fill="currentColor"/>'),
  sparkles: svg(26, 26, '0 0 24 24',
    `<path d="${sparkle(13.6, 13.4, 7.6)}" fill="currentColor"/><path d="${sparkle(6.2, 6.6, 3.4)}" fill="currentColor"/><path d="${sparkle(8.6, 2.6, 1.6)}" fill="currentColor"/>`),
  // Status bar.
  cellular: svg(18, 12, '0 0 18 12',
    '<rect x="0" y="8" width="3" height="4" rx="0.8" fill="currentColor"/><rect x="5" y="5.4" width="3" height="6.6" rx="0.8" fill="currentColor"/>' +
    '<rect x="10" y="2.7" width="3" height="9.3" rx="0.8" fill="currentColor"/><rect x="15" y="0" width="3" height="12" rx="0.8" fill="currentColor"/>'),
  wifi: svg(17, 12, '0 0 17 12',
    '<path d="M1.2 4.3a10.4 10.4 0 0 1 14.6 0M3.8 7a6.7 6.7 0 0 1 9.4 0" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/><path d="M6.3 9.6a3.1 3.1 0 0 1 4.4 0L8.5 11.9z" fill="currentColor"/>'),
  battery: svg(27, 13, '0 0 27 13',
    '<rect x="0.5" y="0.5" width="23" height="12" rx="3.8" stroke="currentColor" stroke-opacity="0.4"/><rect x="2" y="2" width="20" height="9" rx="2.4" fill="currentColor"/>' +
    '<path d="M25 4.4v4.2c.9-.3 1.5-1.2 1.5-2.1s-.6-1.8-1.5-2.1z" fill="currentColor" fill-opacity="0.45"/>'),
};

// ──────────────────────────────────────────────────────────── the sample day ──

const jitter = (d, i) => (d === 0 ? 0 : ((Math.abs(d) * 5 + i * 3) % 7) - 3);

/**
 * Everything that has happened by `now` (minutes from today's local midnight),
 * consistent with whether a sleep is running. Times are minutes from today's
 * midnight; yesterday's are negative.
 */
function buildDay(now, asleep) {
  let sleeps = [];
  let feeds = [];
  let diapers = [];
  let notes = [];
  for (const d of [-2, -1, 0]) {
    const base = d * 1440;
    TEMPLATE.sleeps.forEach(([s, e], i) => {
      sleeps.push({ start: base + s + jitter(d, i), end: base + e + (e > 1440 ? jitter(d + 1, i) : jitter(d, i)) });
    });
    TEMPLATE.feeds.forEach(([t, amount, who, note], i) => {
      const varied = d === 0 ? amount : clamp(amount + (((Math.abs(d) + i) % 3) - 1) * 0.5, 3, 5.5);
      feeds.push({ t: base + t + jitter(d, i + 2), oz: varied, who, note: note || null });
    });
    TEMPLATE.diapers.forEach(([t, type, who], i) => {
      diapers.push({ t: base + t + jitter(d, i + 2), type, who });
    });
    (NOTES[d] || []).forEach(([t, who, text]) => notes.push({ t: base + t, who, text }));
  }

  // Only what has happened.
  sleeps = sleeps.filter((s) => s.start <= now);
  feeds = feeds.filter((f) => f.t <= now);
  diapers = diapers.filter((x) => x.t <= now);
  notes = notes.filter((n) => n.t <= now);

  let running = sleeps.find((s) => s.end > now) || null;
  if (running) running.end = null;

  if (!asleep && running) {
    // He is up. Either he woke a little while ago, or he hasn't gone down yet.
    if (now - running.start < 38) sleeps = sleeps.filter((s) => s !== running);
    else running.end = now - 18;
    running = null;
  } else if (asleep && !running) {
    // He has just gone down: half an hour ago, or as soon after the last
    // thing logged as leaves him a few minutes asleep.
    const lastEvent = Math.max(-Infinity, ...feeds.map((f) => f.t), ...diapers.map((x) => x.t), ...notes.map((n) => n.t));
    const lastWake = Math.max(-Infinity, ...sleeps.map((s) => s.end));
    let start = Math.max(now - 30, lastEvent + 3, lastWake + 6);
    if (now - start < 4) {
      // Something was logged in the last few minutes: it happened just before.
      start = now - 4;
      for (const list of [feeds, diapers, notes]) for (const e of list) if (e.t > start - 2) e.t = start - 2;
      for (const s of sleeps) if (s.end > start - 6) s.end = start - 6;
    }
    running = { start, end: null };
    sleeps.push(running);
  }
  if (asleep === 'night' && running && isNap(running.start, now) && now >= 360 && now < 1080) {
    // Asked for a night's sleep in the middle of the day: a long stretch, past
    // the nap crossover. (From 6 PM a fresh sleep stands — the app itself
    // calls a sleep that starts before 8 PM a nap for its first two hours.)
    const start = now - 125;
    sleeps = sleeps.filter((s) => s === running || s.end <= start - 20);
    running.start = start;
  }
  if (asleep === 'night' && running) running.night = true;

  return { now, sleeps, feeds, diapers, notes, running };
}

/** What the phone page reads off the day. */
function summarize(day) {
  const { now, sleeps, feeds, diapers, running } = day;
  const todayFeeds = feeds.filter((f) => f.t >= 0);
  const todayDiapers = diapers.filter((x) => x.t >= 0);
  // Finished sleeps' share of today, plus the running one's (TodayHeroCard.sleepTotal).
  let sleepMinutes = 0;
  for (const s of sleeps) {
    const end = s.end == null ? now : s.end;
    sleepMinutes += Math.max(0, end - Math.max(s.start, 0));
  }
  const finished = sleeps.filter((s) => s.end != null);
  const lastSleep = finished[finished.length - 1] || null;
  return {
    feedCount: todayFeeds.length,
    feedOz: todayFeeds.reduce((sum, f) => sum + f.oz, 0),
    diaperCount: todayDiapers.length,
    wet: todayDiapers.filter((x) => x.type !== 'dirty').length,
    dirty: todayDiapers.filter((x) => x.type !== 'wet').length,
    sleepMinutes,
    lastFeed: feeds[feeds.length - 1] || null,
    lastDiaper: diapers[diapers.length - 1] || null,
    lastSleep,
    running,
  };
}

/** Urgency.from — green under two thirds of the target, red past it. */
function urgency(elapsed, target) {
  const ratio = elapsed / target;
  if (ratio < 2 / 3) return 'green';
  return ratio <= 1 ? 'amber' : 'red';
}

/**
 * Tonight's roster (NightSchedule): the night's bottles a spacing apart from
 * its first, parents alternating from the first in join order.
 */
function tonight(day) {
  const { now, feeds } = day;
  const { nightStart, nightEnd, nightSpacing } = SETTINGS;
  // The window this evening / this small hour belongs to.
  const start = now < nightEnd ? nightStart - 1440 : nightStart;
  const end = start + ((nightEnd - nightStart + 1440) % 1440);
  // The night's first bottle: one logged in the window (or its grace hour),
  // else three hours after the last daytime one.
  const logged = feeds.filter((f) => f.t >= start - 60 && f.t <= end);
  const before = feeds.filter((f) => f.t < start - 60);
  const lastBefore = before[before.length - 1];
  const projected = lastBefore ? Math.max(lastBefore.t + nightSpacing, start) : start;
  const anchor = logged.length && logged[0].t < projected + 90 ? Math.min(logged[0].t, projected) : projected;
  const anchorSlot = Math.round(anchor / 5) * 5;
  const rows = [];
  const order = ['A', 'J'];
  for (let t = anchorSlot, i = 0; t <= end; t += nightSpacing, i += 1) {
    const done = logged.some((f) => Math.abs(f.t - t) <= 90);
    let status = 'upcoming';
    if (done) status = 'done';
    else if (now > t + 90) status = 'missed';
    else if (now > t) status = 'overdue';
    rows.push({ t, who: order[i % 2], status });
  }
  const active = now >= start && now < end;
  const approaching = !active && rows.length > 0 && now >= rows[0].t - 90 && now < start;
  const business = rows.some((r) => r.status === 'upcoming' || r.status === 'overdue');
  return { rows, start, end, shown: (active || approaching) && business };
}

/** NightReport: the night `now` is in, or the last one. */
function nightReport(day) {
  const { now, sleeps, feeds, diapers } = day;
  const { nightStart, nightEnd } = SETTINGS;
  const length = (nightEnd - nightStart + 1440) % 1440;
  let start = nightStart - 1440;
  if (now >= nightStart) start = nightStart;
  const end = start + length;
  const upTo = Math.min(now, end);
  const segments = [];
  for (const s of sleeps) {
    const a = Math.max(s.start, start);
    const b = Math.min(s.end == null ? now : s.end, upTo);
    if (b > a) segments.push([a, b]);
  }
  const asleep = segments.reduce((sum, [a, b]) => sum + (b - a), 0);
  const longest = segments.reduce((best, [a, b]) => Math.max(best, b - a), 0);
  const wakeUps = segments.filter(([, b]) => b < upTo - 1).length;
  const nightFeeds = feeds.filter((f) => f.t >= start && f.t <= upTo);
  const nightDiapers = diapers.filter((x) => x.t >= start && x.t <= upTo);
  const share = (who) => ({
    feeds: nightFeeds.filter((f) => f.who === who).length,
    oz: nightFeeds.filter((f) => f.who === who).reduce((sum, f) => sum + f.oz, 0),
    diapers: nightDiapers.filter((x) => x.who === who).length,
  });
  return {
    start, end, upTo, complete: now >= end, segments, asleep, longest, wakeUps,
    feeds: nightFeeds, oz: nightFeeds.reduce((sum, f) => sum + f.oz, 0),
    diaperCount: nightDiapers.length, shares: { A: share('A'), J: share('J') },
  };
}

/** The six nights before it, whole — the same night, a little different each time. */
function priorNights(report) {
  const length = report.end - report.start;
  const rows = [];
  for (let k = 6; k >= 1; k -= 1) {
    const j = ((k * 7) % 9) - 4;
    const first = clamp(235 + j * 4 - (k === 4 ? 70 : 0), 120, length);
    const segments = [[0, first], [first + 28 + (k % 3) * 4, 425 + j * 2], [454 + j, length]];
    if (k === 4) segments.splice(1, 0, [first + 22, first + 60]);
    const clean = segments.filter(([a, b]) => b > a + 2).map(([a, b]) => [clamp(a, 0, length), clamp(b, 0, length)]);
    rows.push({
      k,
      segments: clean,
      feeds: [50 + j * 2, 240 + j * 3, 430 + j],
      asleep: clean.reduce((sum, [a, b]) => sum + (b - a), 0),
    });
  }
  return rows;
}

// ─────────────────────────────────────────────────────────────── the page ──

/**
 * Avatar's monogram: the initial in rounded bold at 44 % of the size, centred.
 * SwiftUI centres the line box, which puts the cap height (0.705 em) on the
 * circle's centre to within a hair; the baseline is set to do exactly that.
 */
const avatar = (person, size) => {
  const fontSize = size * 0.44;
  const baseline = size / 2 + 0.3555 * fontSize;
  return `<span class="avatar" style="width:${px(size)};height:${px(size)};background:${person.color}">` +
    `<svg viewBox="0 0 ${size} ${size}" aria-hidden="true"><text x="${size / 2}" y="${baseline.toFixed(2)}" text-anchor="middle" font-size="${fontSize.toFixed(2)}">${esc(person.name[0])}</text></svg></span>`;
};

/** TimeFormatting.age: days → weeks → months. */
function ageText(date, tz, ageDays) {
  if (ageDays < 14) return ageDays === 1 ? '1 day old' : `${ageDays} days old`;
  if (ageDays < 56) return `${Math.floor(ageDays / 7)} weeks old`;
  const today = localDate(date, tz);
  const born = new Date(today.getTime() - ageDays * 86400000);
  let months = (today.getUTCFullYear() - born.getUTCFullYear()) * 12 + today.getUTCMonth() - born.getUTCMonth();
  if (today.getUTCDate() < born.getUTCDate()) months -= 1;
  return months === 1 ? '1 month old' : `${months} months old`;
}

/** The local calendar day as a UTC-midnight Date (so getUTC* reads local fields). */
function localDate(date, tz) {
  const shifted = new Date(date.getTime() + tz * 3600000);
  return new Date(Date.UTC(shifted.getUTCFullYear(), shifted.getUTCMonth(), shifted.getUTCDate()));
}

function header(ctx) {
  return `<div class="header" data-card="header">
    ${avatar(BABY, 60)}
    <div class="who"><div class="f-hero c-text ellipsis">${BABY.name}</div><div class="f-sub c-text2 nowrap">${ctx.age}</div></div>
    <div class="gear">${ICON.gear}</div>
  </div>`;
}

/** TodayHeroCard: "Today", the day-flow strip, three totals. */
function hero(ctx) {
  const { day, sum, now } = ctx;
  const w = ctx.cardWidth - 32;
  const nowH = now / 60;
  const x = (h) => (clamp(h, 0, 24) / 24) * w;
  const nowX = x(nowH);
  // A span never passes now; its minimum width grows leftward from it.
  const span = (from, to, minWidth) => {
    const x0 = x(Math.min(from, nowH));
    const x1 = Math.max(x0, x(Math.min(to, nowH)));
    const width = Math.max(minWidth, x1 - x0);
    const right = Math.min(x0 + width, Math.max(x1, nowX));
    return [Math.max(0, right - width), width];
  };
  let strip = '<div class="track"></div>';
  for (const s of day.sleeps) {
    const end = s.end == null ? now : s.end;
    if (end <= 0) continue;
    const [left, width] = span(s.start / 60, end / 60, 11.6);
    strip += `<i class="nap" style="left:${px(left)};width:${px(width)}"></i>`;
  }
  const mark = (t, glyph, y) => {
    const gx = clamp(x(Math.min(t / 60, nowH)), 6, w - 6);
    return `<span class="mark" style="left:${px(gx)};top:${px(y)}">${glyph}</span>`;
  };
  for (const f of day.feeds) if (f.t >= 0) strip += mark(f.t, '🍼', 11.84);
  for (const d of day.diapers) if (d.t >= 0) strip += mark(d.t, d.type === 'wet' ? '💧' : '💩', 46.44);
  if (sum.running) {
    strip += `<i class="glow" style="left:${px(nowX)}"></i><i class="glow-dot" style="left:${px(nowX)}"></i>`;
  } else {
    strip += `<i class="now" style="left:${px(nowX)}"></i>`;
  }
  for (const [h, text] of [[0, '12a'], [6, '6a'], [12, '12p'], [18, '6p'], [24, '12a']]) {
    strip += `<span class="hour" style="left:${px(clamp(x(h), 7, w - 9))}">${text}</span>`;
  }

  const quiet = 'style="color:var(--text3)"';
  const feedValue = sum.feedCount
    ? `<span class="value c-feed">${oz(sum.feedOz)}<span class="unit"> oz</span></span>`
    : `<span class="value" ${quiet}>—</span>`;
  const diaperValue = sum.diaperCount
    ? `<span class="value c-diaper">${sum.diaperCount}<span class="unit"> ${sum.diaperCount === 1 ? 'diaper' : 'diapers'}</span></span>`
    : `<span class="value" ${quiet}>—</span>`;
  const diaperParts = [];
  if (sum.wet) diaperParts.push(`${sum.wet} wet`);
  if (sum.dirty) diaperParts.push(`${sum.dirty} dirty`);
  const diaperCaption = sum.diaperCount ? diaperParts.join(' · ') : 'changes';
  const mins = Math.floor(sum.sleepMinutes);
  const h = Math.floor(mins / 60);
  const m = mins % 60;
  let sleepValue = `<span class="value" ${quiet}>—</span>`;
  if (mins > 0) {
    let inner = '';
    if (h > 0) inner += `${h}<span class="unit">h</span>`;
    if (m > 0 || h === 0) inner += `${h > 0 ? ' ' : ''}${m}<span class="unit">m</span>`;
    sleepValue = `<span class="value c-sleep">${inner}</span>`;
  }
  const sleepCaption = sum.running
    ? `<span class="caption live">${ICON.moonZzz}${runningWord(sum.running, now)}</span>`
    : '<span class="caption">sleep</span>';

  return `<div class="surface hero" data-card="hero">
    <div class="hero-title"><span class="f-title3r c-text">Today</span><span class="f-sub c-text2 nowrap">${ctx.dateShort}</span></div>
    <div class="hero-day">
      <div class="strip">${strip}</div>
      <div class="totals" data-fit="totals">
        <div class="total" style="left:${px(w / 6)}">${feedValue}<span class="caption">${sum.feedCount ? plural(sum.feedCount, 'feed') : 'no feeds yet'}</span></div>
        <div class="total" style="left:${px(w / 2)}">${diaperValue}<span class="caption">${diaperCaption}</span></div>
        <div class="total" style="left:${px((w * 5) / 6)}">${sleepValue}${sleepCaption}</div>
      </div>
    </div>
  </div>`;
}

function sinceLine(elapsed, target) {
  const level = urgency(elapsed, target);
  const value = since(elapsed);
  const text = value === 'just now' ? value : `${value} ago`;
  const marker = level === 'amber' ? ICON.dot : level === 'red' ? ICON.alert : '';
  return `<div class="since f-sub ${level}"><span>${text}</span>${marker}</div>`;
}

const hintLine = (hint) =>
  `<div class="hint f-cap" data-fit="hint">${hint.ai ? `<span class="ai">✦ ${esc(hint.text)}</span>` : `<span>${esc(hint.text)}</span>`}</div>`;

function tile({ title, glyph, tint, status, hint, detail }) {
  return `<div class="glass tile" data-card="tile" style="--tint:var(${tint})">
    <div class="col">
      <div class="glyph">${glyph}</div>
      <div class="lines"><div class="title nowrap">${title}</div>${status}${hintLine(hint)}</div>
    </div>
    ${detail ? `<div class="detail"><span class="label c-text3">${esc(detail.label)}</span><span class="f-bodyr c-text2 nowrap">${esc(detail.value)}</span></div>` : ''}
    <div class="plus">${ICON.badgePlus}</div>
  </div>`;
}

/** HomeView.feedHint / diaperHint / sleepHint, with predictions on. */
function tiles(ctx) {
  const { sum, now } = ctx;
  const out = [];
  let feed = { status: '', hint: { text: 'log a bottle' } };
  if (sum.lastFeed) {
    const last = sum.lastFeed.t;
    const predicted = last + 175; // his own cadence, a touch under the 3 h target
    const hint = predicted > now
      ? { ai: true, text: `next ~${clock(predicted)} · ~${oz(startsAtNight(predicted) ? 4 : 4.5)} oz` }
      : { text: `bottle was due ~${clock(last + SETTINGS.feedTarget)}` };
    feed = { status: sinceLine(now - last, SETTINGS.feedTarget), hint };
  }
  let diaper = { status: '', hint: { text: 'log a change' } };
  if (sum.lastDiaper) {
    diaper = {
      status: sinceLine(now - sum.lastDiaper.t, SETTINGS.diaperTarget),
      hint: { text: `changed at ${clock(sum.lastDiaper.t)}` },
    };
  }
  out.push(`<div class="tiles">
    ${tile({ title: 'Feed', glyph: '🍼', tint: '--accent-feed', ...feed })}
    ${tile({ title: 'Diaper', glyph: '💩', tint: '--accent-diaper', ...diaper })}
  </div>`);

  if (!sum.running) {
    let sleep = { status: '', hint: { text: 'start timer' }, detail: null };
    if (sum.lastSleep) {
      const woke = sum.lastSleep.end;
      const next = woke + WAKE_WINDOW;
      const noun = startsAtNight(next) ? 'sleep' : 'nap';
      let hint = {
        text: next < now
          ? `${noun} was due ~${clock(next)} · ${shortLabel(WAKE_WINDOW)} awake`
          : `next ${noun} ~${clock(next)} · ${shortLabel(WAKE_WINDOW)} awake`,
      };
      if (next > now && noun === 'nap') hint = { ai: true, text: `next ~${clock(next)} · usually ~${shortLabel(next > 960 ? 35 : 55)}` };
      sleep = {
        status: sinceLine(now - woke, WAKE_WINDOW),
        hint,
        detail: {
          label: `last ${sleepNoun(sum.lastSleep.start, woke).toLowerCase()}`,
          value: duration(woke - sum.lastSleep.start),
        },
      };
    }
    out.push(tile({ title: 'Sleep', glyph: '💤', tint: '--accent-sleep', ...sleep }));
  }
  return out.join('');
}

/** SleepActiveCard — the full card, or the short one where the display is under 700 pt tall. */
function sleepCard(ctx) {
  const { sum, now } = ctx;
  const s = sum.running;
  const word = runningWord(s, now).toUpperCase();
  const usual = s.night || startsAtNight(s.start) ? 270 : 70;
  const predicted = s.start + usual;
  const eyebrow = `<div class="label c-sleep">${BABY.name.toUpperCase()} IS ${word}</div>`;
  const sinceRow = `<div class="sincerow f-cap"><span class="nowrap">since ${clock(s.start)}</span>${ICON.pencil}</div>`;
  const wake = predicted > now ? `<div class="f-cap" style="height:14.3px"><span class="ai">✦ predicted wake ~${clock(predicted)}</span></div>` : '';
  const elapsed = duration(Math.floor(now - s.start));
  const slide = `<div class="slide">
    <i class="wake"></i>
    <div class="words f-sub"><span>Slide to wake up</span>${ICON.chevrons}</div>
    <div class="check">${ICON.check}</div>
    <div class="thumb">${ICON.sun}</div>
  </div>`;
  if (ctx.short) {
    return `<div class="glass sleepcard short" data-card="sleep" style="--tint:var(--accent-sleep)">
      <div class="status">
        <div class="emoji" style="font-size:30px;line-height:35.8px">💤</div>
        <div class="lines">${eyebrow}<div class="timer" style="font-size:40px;line-height:47.7px">${elapsed}</div>${sinceRow}${wake}</div>
      </div>
      ${slide}
    </div>`;
  }
  return `<div class="glass sleepcard" data-card="sleep" style="--tint:var(--accent-sleep)">
    <div class="status">
      <div class="emoji" style="font-size:34px;line-height:40.6px">💤</div>
      ${eyebrow}<div class="timer" style="font-size:48px;line-height:57.3px">${elapsed}</div>${sinceRow}
      ${wake ? `<div style="padding-top:2px">${wake}</div>` : ''}
    </div>
    ${slide}
  </div>`;
}

/** HomeView.tonightCard — the night's bottles and whose they are. */
function tonightCard(ctx) {
  const plan = ctx.tonight;
  const rows = plan.rows.map((row, index) => {
    const settled = row.status === 'done' || row.status === 'missed';
    const person = PEOPLE[row.who];
    let state = '';
    if (row.status === 'done') state = `<span class="c-sleep">${ICON.checkCircle}</span>`;
    else if (row.status === 'overdue') state = '<span style="font-size:9px;color:var(--urgency-amber)">overdue</span>';
    else if (row.status === 'missed') state = '<span class="c-text3" style="font-size:9px">skipped</span>';
    return `<div class="trow${index === plan.rows.length - 1 ? ' last' : ''}">
      <span class="time f-cap2 mono c-text3" ${settled ? 'style="opacity:.6"' : ''}>${clock(row.t)}</span>
      <span class="trail"><i ${settled ? 'style="--dot:color-mix(in srgb, var(--accent-feed) 35%, var(--card))"' : ''}></i></span>
      ${state}<span style="flex:1"></span>
      <span class="f-cap2 ${settled ? 'c-text3' : 'c-text2'} nowrap">${person.me ? 'You' : person.name}</span>${avatar(person, 16)}
    </div>`;
  }).join('');
  const next = plan.rows.find((row) => row.status === 'upcoming');
  return `<div class="surface tonight" data-card="detail">
    <div class="head"><span class="emoji f-callout">🌙</span><span class="label">Tonight's Schedule</span><span style="flex:1"></span><span class="c-text3">${ICON.chevron}</span></div>
    ${rows}
    ${next ? `<div class="f-cap2" style="padding-top:6px"><span class="ai">✦ usually takes ~4 oz at ${clock(next.t)}</span></div>` : ''}
    <div class="foot f-cap2"><span>${ICON.clock}Every 3h</span><span>·</span><span>${ICON.moonStarsSmall}${clock(SETTINGS.nightStart)}–${clock(SETTINGS.nightEnd)}</span></div>
  </div>`;
}

/** DayTimelineRow's sleep capsule: square-root growth, 14–40 pt. */
const barLength = (minutes) => clamp(14 + Math.sqrt(Math.max(0, minutes)) * 1.6, 14, 40);

/** "Recent · Last 24 hours" on its card, newest first. */
function timeline(ctx) {
  const { day, now } = ctx;
  const from = now - 1440;
  const entries = [];
  for (const f of day.feeds) {
    if (f.t >= from) entries.push({ t: f.t, kind: 'feed', glyph: '🍼', title: `Feed · ${oz(f.oz)} oz`, note: f.note, who: f.who, node: '--accent-feed' });
  }
  for (const d of day.diapers) {
    if (d.t >= from) {
      entries.push({
        t: d.t, kind: 'diaper', glyph: d.type === 'wet' ? '💧' : '💩',
        title: `Diaper · ${d.type[0].toUpperCase()}${d.type.slice(1)}`, who: d.who, node: '--accent-diaper',
      });
    }
  }
  for (const n of day.notes) {
    if (n.t >= from) entries.push({ t: n.t, kind: 'note', glyph: '📝', title: n.text, who: n.who, node: '--accent-note' });
  }
  for (const s of day.sleeps) {
    if (s.end == null) {
      entries.push({
        t: s.start, kind: 'sleep', glyph: '💤', live: true, node: '--accent-sleep', bar: barLength(now - s.start),
        title: `${runningWord(s, now)[0].toUpperCase()}${runningWord(s, now).slice(1)} · ${duration(Math.floor(now - s.start))}`,
      });
    } else if (s.start >= from) {
      entries.push({
        t: s.start, end: s.end, kind: 'sleep', glyph: '💤', node: '--accent-sleep', bar: barLength(s.end - s.start),
        title: `${sleepNoun(s.start, s.end)} · ${duration(s.end - s.start)}`,
      });
    }
  }
  entries.sort((a, b) => b.t - a.t);

  const rows = entries.map((e) => {
    const when = e.kind === 'sleep' && !e.live
      ? `<div class="when two${e.bar < 26.2 ? ' tight' : ''} f-cap2 mono" style="height:${px(e.bar)}"><span>${clock(e.end)}</span><span>${clock(e.t)}</span></div>`
      : `<div class="when f-cap mono">${clock(e.t)}</div>`;
    const node = e.kind === 'sleep'
      ? `<i class="node bar" style="--node:var(${e.node});height:${px(e.bar)};margin-top:${px(-e.bar / 2)}"></i>`
      : `<i class="node" style="--node:var(${e.node})"></i>`;
    return `<div class="trowt">
      ${when}<div class="rail">${node}</div>
      <div class="what"><span class="emoji f-callout">${e.glyph}</span>
        <div class="words"><span class="t f-sub${e.live ? ' mono' : ''}">${esc(e.title)}</span>${e.note ? `<span class="f-cap c-text2">${esc(e.note)}</span>` : ''}</div>
        ${e.who ? avatar(PEOPLE[e.who], 24) : ''}
      </div>
    </div>`;
  }).join('');

  return `<div class="timeline" data-card="timeline">
    <div class="thead">
      <div class="titles"><span class="f-title3r c-text">Recent</span><span class="f-sub c-text2 nowrap">Last 24 hours</span></div>
      <span class="pill">${ICON.plus(10, 1.9)}Add note</span>
    </div>
    <div class="trowt cap"><div class="when label c-text3">Now</div><div class="rail"><i class="ring"></i></div></div>
    ${rows}
  </div>`;
}

function phonePage(ctx) {
  const { geo, sum } = ctx;
  const parts = [hero(ctx), tiles(ctx)];
  if (sum.running) parts.push(sleepCard(ctx));
  if (ctx.options.tonightCard !== false && ctx.tonight.shown) parts.push(tonightCard(ctx));
  return `<div class="page" style="left:${px(geo.pageX)};width:${px(geo.pageWidth)};padding:${px(geo.top)} ${px(geo.side)} 0">
    ${header(ctx)}
    <div class="veiled"${ctx.veil > 0 ? ` style="--veil:${1 - ctx.veil}"` : ''}>
      <div class="stack">${parts.join('')}</div>
      ${timeline(ctx)}
    </div>
  </div>`;
}

// ─────────────────────────────────────────────────────────── system chrome ──

const TABS = [['Home', 'house'], ['Nighttime', 'moonStars'], ['History', 'chart'], ['Stats', 'sparkles']];

const tabItems = () => TABS.map(([name, icon], i) => `<div class="tab${i === 0 ? ' on' : ''}">${ICON[icon]}<span>${name}</span></div>`).join('');

/** The time as the status bar shows it: no AM/PM. */
function statusTime(now) {
  const t = ((Math.floor(now) % 1440) + 1440) % 1440;
  const h = Math.floor(t / 60);
  return `${h % 12 || 12}:${String(t % 60).padStart(2, '0')}`;
}

/** A slab iPhone: the status bar across the top, the floating tab capsule at the foot. */
function slabChrome(ctx) {
  const { geo, now } = ctx;
  const W = geo.width;
  const barW = 352;
  const barH = 62;
  const barY = geo.height - 21 - barH;
  // A running sleep's Live Activity, compact: 💤 on the island's leading side,
  // the timer on its trailing side. The island widens and the status bar gives
  // up its signal bars to make the room.
  const running = ctx.sum.running;
  let island = `<div class="island" style="left:${px(W / 2 - 63)};top:14px;width:126px;height:37px"></div>`;
  if (running) {
    const mins = Math.floor(now - running.start);
    const timer = mins >= 60 ? `${Math.floor(mins / 60)}:${String(mins % 60).padStart(2, '0')}:00` : `${mins}:00`;
    island = `<div class="island live" style="left:${px(W / 2 - 63 - 30)};top:14px;width:${px(126 + 30 + 44)};height:37px">
        <span class="emoji" style="font-size:15px;line-height:37px">💤</span><span class="mono" style="font:600 ${mins >= 60 ? 12 : 13}px/37px var(--font-text);color:var(--accent-sleep)">${timer}</span>
      </div>`;
  }
  return `<div class="sys" style="left:0;top:0;width:${px(W)};height:${px(geo.statusBar)}" data-card="strip">
      <div class="clock" style="left:${px(73)};top:22.5px;transform:translateX(-50%)">${statusTime(now)}</div>
      ${island}
      <div class="status-icons" style="right:${px(73 - 37)};top:26.5px">${running ? '' : ICON.cellular}${ICON.wifi}${ICON.battery}</div>
    </div>
    <div class="tabbar" data-card="tabbar" style="left:${px((W - barW) / 2)};top:${px(barY)};width:${px(barW)};height:${px(barH)}">${tabItems()}</div>`;
}

/**
 * iPhone Duo: status, Dynamic Island and the tab bar in an 84 pt column on the
 * trailing edge. The column itself is not a surface — the sky runs under it.
 */
function duoStrip(ctx) {
  const { geo, now } = ctx;
  const left = geo.width - geo.strip;
  const cx = geo.strip / 2;
  const asleep = !!ctx.sum.running;
  // The Duo's island is the narrow one: a compact Live Activity is a 28 pt
  // circle on its end (SleepActivityWidget shows 💤 there).
  const islandH = asleep ? 108 : 74;
  const islandY = 50;
  const barW = 64;
  const barH = TABS.length * 60 + 8;
  const barY = geo.height - geo.bottomInset - barH;
  return `<div class="sys" style="left:${px(left)};top:0;width:${px(geo.strip)};height:${px(geo.height)}" data-card="strip">
      <div class="clock" style="left:${px(cx)};top:18px;transform:translateX(-50%)">${statusTime(now)}</div>
      <div class="island" style="left:${px(cx - 18.5)};top:${px(islandY)};width:37px;height:${px(islandH)}">${asleep ? '<span class="emoji" style="font-size:15px;line-height:28px;margin-bottom:5px">💤</span>' : ''}</div>
      <div class="status-icons" style="left:${px(cx)};top:${px(islandY + islandH + 14)};transform:translateX(-50%)">${ICON.wifi}${ICON.battery}</div>
      <div class="tabbar vertical" data-card="tabbar" style="left:${px((geo.strip - barW) / 2)};top:${px(barY)};width:${px(barW)};height:${px(barH)}">${tabItems()}</div>
    </div>`;
}

// ──────────────────────────────────────────────── the spread's leading page ──

const figure = (label, value, usual, color) =>
  `<div class="fig"><span class="label">${esc(label)}</span><span class="v" ${color ? `style="color:var(${color})"` : ''}>${esc(value)}</span><span class="f-cap c-text2">${usual ? esc(usual) : '&nbsp;'}</span></div>`;

/** HomeView.sharesCard: feeds and diapers, each parent's side by side. */
function sharesCard(title, tally) {
  const column = (person, t) => `<div class="tally">
      <div class="who">${avatar(person, 24)}<span class="f-sub w-semi c-text">${person.me ? 'You' : person.name}</span></div>
      <span class="f-sub w-semi c-feed">🍼 ${plural(t.feeds, 'feed')} · ${oz(t.oz)} oz</span>
      <span class="f-sub w-semi c-diaper">💧 ${plural(t.diapers, 'diaper')}</span>
    </div>`;
  return `<div class="surface dcard" data-card="detail">
    <span class="label">${esc(title)}</span>
    <div style="display:flex;gap:16px;padding-top:4px">${column(PEOPLE.J, tally.J)}${column(PEOPLE.A, tally.A)}</div>
  </div>`;
}

/** "+35m vs usual", "−1h 10m vs usual", "about usual" (within 15 min). */
function againstUsual(diff) {
  const mins = Math.round(diff);
  if (Math.abs(mins) < 15) return 'about usual';
  return `${mins > 0 ? '+' : '−'}${duration(Math.abs(mins))} vs usual`;
}

/** Last night (5–10 AM) and tonight so far: headline, who was up, the week's nights. */
function nightDetails(ctx) {
  const report = nightReport(ctx.day);
  const prior = priorNights(report);
  const slept = report.asleep > 0;
  // His other nights, stopped at the same moment.
  const elapsed = report.upTo - report.start;
  const usual = prior.reduce((sum, night) => sum + night.segments.reduce((s, [a, b]) => s + Math.max(0, Math.min(b, elapsed) - a), 0), 0) / prior.length;
  const best = Math.max(...prior.map((night) => Math.max(...night.segments.map(([a, b]) => Math.max(0, Math.min(b, elapsed) - a)))));
  const usualWakes = Math.round(prior.reduce((sum, night) => sum + night.segments.filter(([, b]) => b < elapsed - 1).length, 0) / prior.length);

  const headline = `<div class="surface dcard" data-card="detail">
    <div class="rowb"><span class="label c-sleep">${report.complete ? 'Asleep' : 'Asleep so far'}</span><span class="f-cap c-text3 nowrap">${clock(report.start)} – ${clock(report.end)}</span></div>
    <div style="display:flex;align-items:baseline;gap:10px;white-space:nowrap">
      <span class="f-round mono" style="font-size:34px;line-height:40.6px;font-weight:800;color:var(${slept ? '--text' : '--text3'})">${slept ? duration(report.asleep) : 'None logged'}</span>
      ${slept ? `<span class="f-sub w-semi c-text2">${againstUsual(report.asleep - usual)}</span>` : ''}
    </div>
    <div class="figs">
      ${figure('Longest', slept ? duration(report.longest) : '—', best <= 0 ? null : report.longest > best ? 'best this week' : `best ${duration(best)}`, '--accent-sleep')}
      ${figure('Woke', slept ? plural(report.wakeUps, 'time') : '—', `usually ${usualWakes}`)}
      ${figure('Bottles', String(report.feeds.length), report.feeds.length ? `${oz(report.oz)} oz` : null, '--accent-feed')}
    </div>
  </div>`;

  const shares = report.feeds.length + report.diaperCount > 0
    ? sharesCard(report.complete ? 'Who was up' : 'Up with him tonight', report.shares)
    : '';

  // NightsChart: seven rows, the night the page is about at the bottom.
  const length = report.end - report.start;
  const nightStartDay = report.start < 0 ? ctx.weekday - 1 : ctx.weekday;
  const track = (segments, feedTimes, current) => {
    const pct = (v) => `${(clamp(v / length, 0, 1) * 100).toFixed(2)}%`;
    let html = '<i style="left:0;right:0;height:var(--h);background:var(--card2)"></i>';
    for (const [a, b] of segments) {
      html += `<i style="left:${pct(a)};width:max(3px, ${pct(b - a)});height:var(--h);background:color-mix(in srgb, var(--accent-sleep) ${current ? 100 : 50}%, transparent)"></i>`;
    }
    for (const t of feedTimes) {
      html += `<i style="left:calc(${pct(t)} - var(--h) * 0.35);width:calc(var(--h) * 0.7);height:calc(var(--h) * 0.7);background:color-mix(in srgb, var(--accent-feed) ${current ? 100 : 70}%, transparent);box-shadow:inset 0 0 0 1.5px var(--card)"></i>`;
    }
    return html;
  };
  const rows = prior.map((night) => `<div class="nrow">
      <span class="day f-cap">${WEEKDAYS[(((nightStartDay - night.k) % 7) + 7) % 7].slice(0, 3)}</span>
      <div class="ntrack">${track(night.segments, night.feeds, false)}</div>
      <span class="sum f-cap mono">${duration(night.asleep)}</span>
    </div>`);
  rows.push(`<div class="nrow cur">
      <span class="day f-cap">${WEEKDAYS[((nightStartDay % 7) + 7) % 7].slice(0, 3)}</span>
      <div class="ntrack">${track(report.segments.map(([a, b]) => [a - report.start, b - report.start]), report.feeds.map((f) => f.t - report.start), true)}</div>
      <span class="sum f-cap mono">${slept ? duration(report.asleep) : '—'}</span>
    </div>`);
  const nights = `<div class="surface dcard fills" data-card="detail" style="gap:10px">
    <div class="rowb"><span class="label">His week of nights</span><span style="display:flex;gap:10px"><span class="legend f-cap2"><i style="background:var(--accent-sleep)"></i>sleep</span><span class="legend f-cap2"><i style="background:var(--accent-feed)"></i>bottle</span></span></div>
    <div class="nights" data-fit="nights">${rows.join('')}
      <div class="naxis f-cap2"><span style="width:34px"></span><span class="ticks"><span>${hourNarrow(report.start)}</span><span>${hourNarrow(report.start + length / 2)}</span><span>${hourNarrow(report.end)}</span></span><span style="width:52px"></span></div>
    </div>
  </div>`;
  return headline + shares + nights;
}

/** Cumulative ounces at each hour, for PaceChart. */
function pace(ctx) {
  const { day, now } = ctx;
  const todays = day.feeds.filter((f) => f.t >= 0);
  const cumulative = (list, hour) => list.filter((f) => f.t <= hour * 60).reduce((sum, f) => sum + f.oz, 0);
  const nowHour = clamp(now / 60, 0, 24);
  const today = [];
  for (let h = 0; h < nowHour; h += 1) today.push([h, cumulative(todays, h)]);
  const soFar = todays.reduce((sum, f) => sum + f.oz, 0);
  today.push([nowHour, soFar]);
  // His usual day: the same day, averaged over a week of slightly different ones.
  const usualAt = (hour) => {
    let total = 0;
    for (let d = 1; d <= 7; d += 1) {
      TEMPLATE.feeds.forEach(([t, amount], i) => {
        const varied = clamp(amount + (((d + i) % 3) - 1) * 0.5, 3, 5.5) * 0.97;
        if (t + ((d * 11 + i * 7) % 50) - 25 <= hour * 60) total += varied;
      });
    }
    return total / 7;
  };
  const usual = [];
  for (let h = 0; h <= 24; h += 1) usual.push([h, usualAt(h)]);
  return { today, usual, soFar, usualSoFar: usualAt(nowHour), usualTotal: usualAt(24) };
}

/** 10 AM – 5 PM: the split between you, his rhythm, the day's bottles against his usual. */
function dayDetails(ctx) {
  const { day, now } = ctx;
  const todays = day.feeds.filter((f) => f.t >= 0);
  const tally = (who) => ({
    feeds: todays.filter((f) => f.who === who).length,
    oz: todays.filter((f) => f.who === who).reduce((sum, f) => sum + f.oz, 0),
    diapers: day.diapers.filter((x) => x.t >= 0 && x.who === who).length,
  });
  const gaps = todays.slice(1).map((f, i) => f.t - todays[i].t);
  const gap = gaps.length ? gaps.reduce((a, b) => a + b, 0) / gaps.length : null;
  const avg = todays.length ? Math.round((todays.reduce((sum, f) => sum + f.oz, 0) / todays.length) * 10) / 10 : null;
  const naps = day.sleeps.filter((s) => s.start >= SETTINGS.nightEnd);
  const napMinutes = naps.reduce((sum, s) => sum + ((s.end == null ? now : s.end) - s.start), 0);
  const usualNaps = Math.round((napMinutes * 0.93) / 5) * 5;
  const rhythm = `<div class="surface dcard" data-card="detail">
    <span class="label">His rhythm, by this time</span>
    <div class="figs">
      ${figure('Bottles every', gap ? duration(gap) : '—', 'usually 3h 5m', '--accent-feed')}
      ${figure('Avg bottle', avg ? `${oz(avg)} oz` : '—', 'usually 4.3 oz', '--accent-feed')}
    </div>
    <div class="figs" style="padding-top:0">
      ${figure(naps.length ? plural(naps.length, 'nap') : 'Naps', naps.length ? duration(napMinutes) : 'None yet', naps.length ? `usually ${duration(usualNaps)}` : null, '--accent-sleep')}
      ${figure('Wake window', `~${shortLabel(WAKE_WINDOW)}`, 'his age and his week', '--accent-sleep')}
    </div>
  </div>`;

  const p = pace(ctx);
  ctx.pace = p;
  const diff = Math.round(p.soFar - p.usualSoFar);
  const against = Math.abs(diff) < 1 ? 'about usual' : `${diff > 0 ? '+' : '−'}${Math.abs(diff)} oz vs usual`;
  const chart = `<div class="surface dcard fills" data-card="detail">
    <div class="rowb"><span class="label c-feed">Bottles through the day</span><span class="f-cap w-semi c-text2 nowrap">${against}</span></div>
    <div class="f-sub c-text">${oz(Math.round(p.soFar))} oz so far — usually ${oz(Math.round(p.usualSoFar))} by now, and ${oz(Math.round(p.usualTotal))} by the end of the day.</div>
    <div class="chart" data-fit="pace"></div>
  </div>`;
  return sharesCard('Today, between you', { A: tally('A'), J: tally('J') }) + rhythm + chart;
}

/** 5 PM until tonight's window: his book — the day's highlights, then and next. */
function bookDetails(ctx) {
  const { day, now } = ctx;
  const items = [];
  // The day's longest sleep that ended today.
  const ended = day.sleeps.filter((s) => s.end != null && s.end >= 0 && s.end <= now);
  const best = ended.reduce((top, s) => (!top || s.end - s.start > top.end - top.start ? s : top), null);
  if (best && best.end - best.start >= 120) items.push({ t: best.start, glyph: '💤', text: `Slept ${duration(best.end - best.start)} straight` });
  for (const n of day.notes) if (n.t >= 0) items.push({ t: n.t, glyph: '📝', text: `“${n.text}”`, detail: PEOPLE[n.who].name });
  const bottles = day.feeds.filter((f) => f.t >= 0).sort((a, b) => b.oz - a.oz);
  if (bottles.length >= 2 && bottles[0].oz > bottles[1].oz) items.push({ t: bottles[0].t, glyph: '🍼', text: `Biggest bottle: ${oz(bottles[0].oz)} oz` });
  items.sort((a, b) => a.t - b.t);

  const list = items.map((item) => `<div class="hl">
      <span class="when f-cap mono">${clock(item.t)}</span><span class="emoji f-body">${item.glyph}</span>
      <div class="words"><span class="f-sub w-semi c-text">${esc(item.text)}</span>${item.detail ? `<span class="f-cap c-text2">${esc(item.detail)}</span>` : ''}</div>
    </div>`).join('');
  const highlights = `<div class="surface dcard fills" data-card="detail">
    <div class="rowb"><span class="label" style="color:var(--accent-milestone)">Today's highlights</span>${items.length ? `<span class="f-cap w-semi c-text3">${items.length}</span>` : ''}</div>
    ${items.length
    ? `<div style="display:flex;flex-direction:column;gap:12px;padding-top:4px">${list}</div>`
    : '<div class="f-sub c-text3">The day\'s best moments will gather here as you log them.</div>'}
  </div>`;

  // A month ago today, and the next day worth looking forward to (AgeMarks).
  const today = localDate(ctx.date, ctx.tz);
  const then = new Date(today.getTime() - 30 * 86400000);
  const born = new Date(today.getTime() - ctx.ageDays * 86400000);
  let next = null;
  for (let months = 1; months <= 24 && !next; months += 1) {
    const mark = new Date(Date.UTC(born.getUTCFullYear(), born.getUTCMonth() + months, born.getUTCDate()));
    const days = Math.round((mark - today) / 86400000);
    if (days >= 0 && days <= 31) next = { title: months === 12 ? '1 year old' : months === 24 ? '2 years old' : `${months} ${months === 1 ? 'month' : 'months'} old`, days, date: mark };
  }
  for (const count of [100, 200, 300, 500, 1000]) {
    const days = count - ctx.ageDays;
    if (days >= 0 && days <= 31 && (!next || days < next.days)) next = { title: `${count} days old`, days, date: new Date(today.getTime() + days * 86400000) };
  }
  const shortDate = (d) => `${MONTHS[d.getUTCMonth()].slice(0, 3)} ${d.getUTCDate()}`;
  let coming = '';
  if (next) {
    let when = `in ${next.days} days · ${shortDate(next.date)}`;
    if (next.days <= 0) when = 'today 🎉';
    else if (next.days === 1) when = 'tomorrow';
    else if (next.days < 7) when = `on ${WEEKDAYS[next.date.getUTCDay()]}`;
    coming = `<div class="divider"></div>
      <span class="label" style="color:var(--accent-milestone)">Coming up</span>
      <div class="rowb"><span class="f-sub w-semi c-text">${next.title}</span><span class="f-foot c-text2 nowrap">${when}</span></div>`;
  }
  const thenAndNext = `<div class="surface dcard" data-card="detail">
    <span class="label">A month ago today</span>
    <span class="f-sub w-semi c-text">${shortDate(then)} · ${Math.floor(Math.max(ctx.ageDays - 30, 0) / 7)} weeks old</span>
    <span class="f-foot c-text2">7 feeds · 31 oz · slept 13h 20m</span>
    ${coming}
  </div>`;
  return highlights + thenAndNext;
}

/** HomeView.detailsMoment, with a co-parent. */
function detailsMoment(now) {
  const { nightStart, nightEnd } = SETTINGS;
  const hour = Math.floor(now / 60);
  if (now >= nightStart || now < nightEnd) return 'night';
  if (hour >= 5 && hour < 10) return 'morning';
  if (hour >= 17) return 'evening';
  return 'day';
}

function leadingPage(ctx) {
  const { geo } = ctx;
  const moment = detailsMoment(ctx.now);
  let title;
  let body;
  if (moment === 'morning') {
    title = ['Last night', 'how the night went', ''];
    body = nightDetails(ctx);
  } else if (moment === 'evening') {
    const stamp = `<div class="weekstamp"><span class="c-text2" style="font:700 9px/11px var(--font-text);letter-spacing:1px">WEEK</span><span class="f-round c-text" style="font-size:20px;line-height:22px;font-weight:900">${Math.floor(ctx.ageDays / 7)}</span></div>`;
    title = [`${BABY.name}'s book`, ctx.dateLong, stamp];
    body = bookDetails(ctx);
  } else if (moment === 'night') {
    title = ['Tonight', 'the two of you', `<span style="opacity:.6;display:flex">${avatar(PEOPLE.J, 52)}</span>`];
    body = nightDetails(ctx);
  } else {
    title = ['The day so far', 'against his usual', ''];
    body = dayDetails(ctx);
  }
  const foot = geo.height - geo.bottomInset;
  // At lead = 0 the page is still laid out — state.layout measures its title —
  // but hidden outright, and measure() leaves its surfaces out of the cards.
  const opacity = ctx.lead <= 0 ? 'opacity:0;visibility:hidden;' : ctx.lead < 1 ? `opacity:${ctx.lead};` : '';
  const ghost = ctx.lead <= 0 ? ' data-ghost' : '';
  // SpreadGrid.avatarFrame: 52 pt, 22 pt in from the display's edge, 4 pt under the head line.
  const marginAvatar = ctx.options.marginAvatar
    ? `<div data-card="header"${ghost} style="${opacity}position:absolute;left:22px;top:${px(GRID.headY + 4)};display:flex">${avatar(BABY, 52)}</div>`
    : '';
  return `${marginAvatar}<div class="lead-title" data-card="header"${ghost} style="${opacity}left:${px(GRID.leadingX)};top:${px(GRID.headY)};width:${px(GRID.pageWidth)}">
      <div class="words"><div class="f-hero c-text ellipsis">${esc(title[0])}</div><div class="f-sub c-text2">${esc(title[1])}</div></div>${title[2]}
    </div>
    <div class="lead-col"${ghost} style="${opacity}left:${px(GRID.leadingX)};top:${px(GRID.top)};width:${px(GRID.pageWidth)};height:${px(foot - GRID.top)}">${body}</div>`;
}

/**
 * The undo toast (LoggedToast) — only when asked for. Home's rides on the
 * list itself in every layout: 20 pt in from the page's sides, 8 pt above the
 * safe area's foot (on a slab iPhone, above the tab capsule).
 */
function toast(ctx, data) {
  const { geo } = ctx;
  const width = Math.min(480, geo.pageWidth - 40);
  const left = geo.pageX + (geo.pageWidth - width) / 2;
  const bottom = ctx.device === 'iphone' ? 21 + 62 + 8 : geo.bottomInset + 8;
  return `<div class="toast f-sub" data-card="toast" style="left:${px(left)};width:${px(width)};bottom:${px(bottom)}">
    <span class="c-text">${esc(data.message || 'Logged 4.5 oz')}</span><span class="w-bold" style="color:${data.accent || 'var(--accent-feed)'}">Undo</span>
  </div>`;
}

// ──────────────────────────────────────────────────────── charts and fitting ──

/** A monotone cubic through the points, as an SVG path (Swift Charts' `.monotone`). */
function monotonePath(points) {
  const n = points.length;
  if (n === 0) return '';
  if (n === 1) return `M${points[0][0]} ${points[0][1]}`;
  const dx = [];
  const slope = [];
  for (let i = 0; i < n - 1; i += 1) {
    dx.push(points[i + 1][0] - points[i][0]);
    slope.push((points[i + 1][1] - points[i][1]) / (dx[i] || 1));
  }
  const tangent = [slope[0]];
  for (let i = 1; i < n - 1; i += 1) {
    tangent.push(slope[i - 1] * slope[i] <= 0 ? 0 : (2 * slope[i - 1] * slope[i]) / (slope[i - 1] + slope[i]));
  }
  tangent.push(slope[n - 2]);
  let d = `M${points[0][0].toFixed(2)} ${points[0][1].toFixed(2)}`;
  for (let i = 0; i < n - 1; i += 1) {
    const [x0, y0] = points[i];
    const [x1, y1] = points[i + 1];
    const h = dx[i] / 3;
    d += `C${(x0 + h).toFixed(2)} ${(y0 + tangent[i] * h).toFixed(2)} ${(x1 - h).toFixed(2)} ${(y1 - tangent[i + 1] * h).toFixed(2)} ${x1.toFixed(2)} ${y1.toFixed(2)}`;
  }
  return d;
}

/** PaceChart: today solid to now, his usual day dashed behind it. */
function drawPace(el, p) {
  const width = el.clientWidth;
  const height = el.clientHeight;
  if (width < 40 || height < 30) { el.innerHTML = ''; return; }
  const right = 22;
  const bottom = 16;
  const plotW = width - right;
  const plotH = height - bottom - 2;
  const top = 2;
  const max = Math.max(p.usualTotal, p.soFar, 1);
  const step = max > 30 ? 20 : 10;
  const yMax = Math.ceil((max * 1.02) / step) * step;
  const X = (hour) => (hour / 24) * plotW;
  const Y = (value) => top + plotH - (value / yMax) * plotH;
  let grid = '';
  let labels = '';
  for (const [h, text] of [[0, '12a'], [6, '6a'], [12, '12p'], [18, '6p'], [24, '12a']]) {
    grid += `<line x1="${X(h)}" y1="${top}" x2="${X(h)}" y2="${top + plotH}"/>`;
    labels += `<text x="${X(h) + 3}" y="${height - 3}">${text}</text>`;
  }
  for (let v = 0; v <= yMax; v += step) {
    grid += `<line x1="0" y1="${Y(v)}" x2="${plotW}" y2="${Y(v)}"/>`;
    labels += `<text x="${plotW + 5}" y="${Y(v) + 3.5}">${v}</text>`;
  }
  const last = p.today[p.today.length - 1];
  el.innerHTML = `<svg viewBox="0 0 ${width} ${height}" preserveAspectRatio="none">
    <g stroke="var(--separator)" stroke-width="0.5">${grid}</g>
    <g fill="var(--text3)" font-size="10" style="font-family:var(--font-text)">${labels}</g>
    <path d="${monotonePath(p.usual.map(([h, v]) => [X(h), Y(v)]))}" fill="none" stroke="var(--text3)" stroke-width="2" stroke-dasharray="4 4"/>
    <path d="${monotonePath(p.today.map(([h, v]) => [X(h), Y(v)]))}" fill="none" stroke="var(--accent-feed)" stroke-width="3" stroke-linecap="round"/>
    <circle cx="${X(last[0])}" cy="${Y(last[1])}" r="4.4" fill="var(--accent-feed)"/>
  </svg>`;
}

/** The measurements SwiftUI makes at layout time, made here once the text has its font. */
function fit(root, ctx) {
  // EqualSlotRow: the middle column is pinned to the centre; the outer two
  // rest at their thirds and slide outward before they would touch it.
  for (const row of root.querySelectorAll('[data-fit="totals"]')) {
    const cols = row.children;
    if (cols.length !== 3) continue;
    const width = row.clientWidth;
    const w = [cols[0].offsetWidth, cols[1].offsetWidth, cols[2].offsetWidth];
    const mid = width / 2;
    let left = Math.min(width / 6, mid - w[1] / 2 - 12 - w[0] / 2);
    left = Math.max(left, w[0] / 2);
    let right = Math.max((width * 5) / 6, mid + w[1] / 2 + 12 + w[2] / 2);
    right = Math.min(right, width - w[2] / 2);
    cols[0].style.left = px(left);
    cols[2].style.left = px(right);
  }
  // `.minimumScaleFactor(0.75)` on a tile's hint line.
  for (const hint of root.querySelectorAll('[data-fit="hint"]')) {
    const inner = hint.firstElementChild;
    if (!inner) continue;
    inner.style.display = 'inline-block';
    inner.style.transformOrigin = 'left center';
    inner.style.transform = '';
    const room = hint.clientWidth;
    const need = inner.offsetWidth;
    if (need > room && room > 0) inner.style.transform = `scale(${Math.max(0.75, room / need)})`;
  }
  // NightsChart: each track is 55 % of its row, 8–18 pt.
  for (const chart of root.querySelectorAll('[data-fit="nights"]')) {
    const row = chart.querySelector('.nrow');
    if (row) chart.style.setProperty('--h', px(clamp(row.clientHeight * 0.55, 8, 18)));
  }
  for (const el of root.querySelectorAll('[data-fit="pace"]')) {
    if (ctx.pace) drawPace(el, ctx.pace);
  }
}

// ────────────────────────────────────────────────────────── where the text is ──

let inkContext = null;

/**
 * The box of a one-line text's glyphs — its ink, not its line or its row — in
 * client px: { left, top, right, bottom }, or null if the element has no text.
 *
 * Where the text starts and where its baseline lies come from the laid-out
 * DOM (a Range over the text; an empty inline-block, which sits on the
 * baseline, put in for the measurement and taken out again). How far the ink
 * reaches from there comes from the same font through a canvas's measureText.
 * Text on more than one line, or a browser without those metrics, gets the
 * boxes of its lines instead.
 */
function inkBox(el, scale = 1) {
  if (!el || typeof document === 'undefined') return null;
  const text = el.textContent;
  if (!text || !text.trim()) return null;
  const range = document.createRange();
  range.selectNodeContents(el);
  const run = range.getBoundingClientRect();
  const lines = range.getClientRects().length;
  if (run.width <= 0 || run.height <= 0) return null;
  const own = el.getBoundingClientRect();
  const clip = (r) => ({
    left: Math.max(r.left, own.left), top: r.top, right: Math.min(r.right, own.right), bottom: r.bottom,
  });
  if (lines !== 1) return clip(run);

  if (!inkContext) inkContext = document.createElement('canvas').getContext('2d');
  const style = getComputedStyle(el);
  let metrics = null;
  if (inkContext) {
    inkContext.font = `${style.fontStyle} ${style.fontWeight} ${style.fontSize} ${style.fontFamily}`;
    if ('letterSpacing' in inkContext) inkContext.letterSpacing = style.letterSpacing === 'normal' ? '0px' : style.letterSpacing;
    if ('fontKerning' in inkContext) inkContext.fontKerning = style.fontKerning;
    if ('textRendering' in inkContext) {
      // The canvas wants its own spelling of the computed (lower-case) keyword.
      inkContext.textRendering = { geometricprecision: 'geometricPrecision', optimizelegibility: 'optimizeLegibility',
        optimizespeed: 'optimizeSpeed' }[style.textRendering.toLowerCase()] ?? 'auto';
    }
    inkContext.textBaseline = 'alphabetic';
    inkContext.textAlign = 'left';
    inkContext.direction = 'ltr';
    metrics = inkContext.measureText(text);
  }
  if (!metrics || !Number.isFinite(metrics.actualBoundingBoxAscent)) return clip(run);

  const probe = document.createElement('span');
  probe.style.cssText = 'display:inline-block;width:0;height:0;margin:0;padding:0;border:0;vertical-align:baseline;';
  el.appendChild(probe);
  const baseline = probe.getBoundingClientRect().bottom;
  el.removeChild(probe);
  // The run is in client px (the viewer may be zoomed: `scale`); the canvas's metrics are in CSS px.
  return clip({
    left: run.left - metrics.actualBoundingBoxLeft * scale,
    right: run.left + metrics.actualBoundingBoxRight * scale,
    top: baseline - metrics.actualBoundingBoxAscent * scale,
    bottom: baseline + metrics.actualBoundingBoxDescent * scale,
  });
}

// ──────────────────────────────────────────────────────────────── the API ──

/** Links lab/chrome.css if the page has not (index.html does). */
function ensureStyles(onLoad) {
  if (typeof document === 'undefined') return;
  const href = new URL('./chrome.css', import.meta.url).href;
  for (const link of document.querySelectorAll('link[rel~="stylesheet"]')) {
    if (link.href.split('?')[0] === href.split('?')[0]) return;
  }
  const link = document.createElement('link');
  link.rel = 'stylesheet';
  link.href = href;
  link.addEventListener('load', onLoad);
  document.head.appendChild(link);
}

/**
 * @param {HTMLElement} root  An empty <div> filling the display, over the sky
 *   (position:absolute; inset:0). Its background stays transparent.
 * @param {{ tonightCard?: boolean, marginAvatar?: boolean }} [options]
 *   tonightCard: false leaves "Tonight's Schedule" off the phone page at night.
 *   marginAvatar: true hangs the 52 pt avatar in the spread's outer margin
 *   (SpreadGrid.avatarFrame). Home's spread does not draw it today — the
 *   other tabs' spreads do — so it is off unless asked for.
 * @returns {{ update(state: object): Array<{x:number,y:number,width:number,height:number,kind:string,opacity:number}>, layout: object, destroy(): void }}
 *   update(state) lays Home out for the state and returns the surfaces that
 *   cover the sky, in display points, each with the `opacity` it is drawn at
 *   (1; 1 − veil under the phone page's veil; lead on the leading page).
 *   Beyond the README's fields it reads three optional ones: `state.lead`
 *   (0–1, the leading page's opacity; at 0 its surfaces are not in the cards),
 *   `state.veil` (0–1) and `state.toast` ({ message, accent? } — the undo toast).
 *   `layout` is the README's `state.layout`, measured by the same update: one
 *   object for the chrome's life, refilled in place like the cards.
 */
export function createChrome(root, options = {}) {
  root.classList.add('tou-chrome');
  let key = null;
  let ctx = null;
  let alive = true;
  // One array for the chrome's life, refilled in place: whoever holds it
  // (state.cards) sees a re-measure too.
  const cards = [];

  // The same for the layout (state.layout): one object, its fields replaced.
  const layout = {
    measured: false, name: null, age: null, avatar: null, gear: null,
    firstCardTop: 0, stripClear: null, title: null, subtitle: null,
  };

  const measure = (state) => {
    const frame = root.getBoundingClientRect();
    const scale = frame.width > 0 && state.width > 0 ? frame.width / state.width : 1;
    const round = (v) => Math.round(v * 100) / 100;
    // How much of an element is let through by everything above it (a page's
    // veil, the leading page's fade): the product of the opacities up to the root.
    const opacityOf = (el) => {
      let opacity = 1;
      for (let node = el; node && node !== root; node = node.parentElement) {
        const own = Number.parseFloat(getComputedStyle(node).opacity);
        if (Number.isFinite(own)) opacity *= own;
      }
      return round(opacity);
    };
    cards.length = 0;
    for (const el of root.querySelectorAll('[data-card]')) {
      if (el.closest('[data-ghost]')) continue;        // laid out for state.layout only (lead = 0)
      const r = el.getBoundingClientRect();
      const x0 = Math.max(0, (r.left - frame.left) / scale);
      const y0 = Math.max(0, (r.top - frame.top) / scale);
      const x1 = Math.min(state.width, (r.right - frame.left) / scale);
      const y1 = Math.min(state.height, (r.bottom - frame.top) / scale);
      if (x1 - x0 < 0.5 || y1 - y0 < 0.5) continue;
      cards.push({
        x: round(x0), y: round(y0), width: round(x1 - x0), height: round(y1 - y0),
        kind: el.dataset.card, opacity: opacityOf(el),
      });
    }

    // ── state.layout: where the header's own things are ──
    const box = (el) => {
      if (!el) return null;
      const r = el.getBoundingClientRect();
      return {
        x: round((r.left - frame.left) / scale), y: round((r.top - frame.top) / scale),
        width: round(r.width / scale), height: round(r.height / scale),
      };
    };
    const ink = (el) => {
      const r = inkBox(el, scale);
      return r && {
        x: round((r.left - frame.left) / scale), y: round((r.top - frame.top) / scale),
        width: round((r.right - r.left) / scale), height: round((r.bottom - r.top) / scale),
      };
    };
    const page = root.querySelector('.page');
    const stack = page && page.querySelector('.stack');
    const strip = root.querySelector('.sys .tabbar.vertical');
    let stripClear = null;
    if (strip && stack) {
      // The Duo's column between the last thing at its head (the Dynamic Island,
      // then wifi and battery under it) and the tab capsule, from the cards'
      // trailing edge to the display's.
      const sys = strip.parentElement;
      const head = Math.max(...[...sys.querySelectorAll('.clock, .island, .status-icons')]
        .map((el) => el.getBoundingClientRect().bottom));
      const x = (stack.getBoundingClientRect().right - frame.left) / scale;
      stripClear = {
        x: round(x), width: round(state.width - x),
        yMin: round((head - frame.top) / scale),
        yMax: round((strip.getBoundingClientRect().top - frame.top) / scale),
      };
    }
    layout.measured = true;
    layout.name = page && ink(page.querySelector('.header .who .f-hero'));
    layout.age = page && ink(page.querySelector('.header .who .f-sub'));
    layout.avatar = page && box(page.querySelector('.header .avatar'));
    layout.gear = page && box(page.querySelector('.header .gear'));
    layout.firstCardTop = stack ? round((stack.getBoundingClientRect().top - frame.top) / scale) : 0;
    layout.stripClear = stripClear;
    layout.title = ink(root.querySelector('.lead-title .words .f-hero'));
    layout.subtitle = ink(root.querySelector('.lead-title .words .f-sub'));
    return cards;
  };

  // Text widths settle when the fonts arrive. No surface's frame depends on
  // them, but the fitted lines (the totals row, a tile's hint) do.
  const settle = () => {
    if (!alive || !ctx) return;
    fit(root, ctx);
    measure(ctx.state);
  };
  ensureStyles(settle);
  if (typeof document !== 'undefined' && document.fonts) {
    // Ask for the faces now, so they are on their way before the first layout.
    // (The "Lab …" faces are local ones under another name — lab/chrome.css —
    // and simply fail to load where the font is not installed.)
    if (document.fonts.load) {
      for (const face of ['800 34px "Nunito"', '400 15px "Lab Inter"', '500 12px "Lab Inter"',
        '600 15px "Lab Inter"', '700 12px "Lab Inter"', '30px "Lab Emoji"']) {
        document.fonts.load(face, face.includes('Emoji') ? '🍼' : 'A').then(settle, () => {});
      }
    }
    document.fonts.ready.then(settle);
    if (document.fonts.addEventListener) document.fonts.addEventListener('loadingdone', settle);
  }

  function update(state) {
    const device = DEVICES[state.device] ? state.device : 'cover';
    const date = state.date instanceof Date ? state.date : new Date();
    const preset = DEVICES[device];
    const width = state.width || preset.width;
    const height = state.height || preset.height;
    const tz = state.tzOffsetHours == null ? -6 : state.tzOffsetHours;
    const localHour = state.localHour == null
      ? (((date.getTime() / 3600000 + tz) % 24) + 24) % 24
      : state.localHour;
    const now = Math.floor(localHour * 60 + 1e-6);
    const asleep = state.asleep === 'nap' || state.asleep === 'night' ? state.asleep : false;
    const ageDays = state.ageDays == null ? 142 : Math.round(state.ageDays);
    const today = localDate(date, tz);
    const lead = state.lead == null ? 1 : clamp(Number(state.lead), 0, 1);
    const veil = state.veil == null ? 0 : clamp(Number(state.veil), 0, 1);
    const toastData = state.toast ? (typeof state.toast === 'object' ? state.toast : { message: String(state.toast) }) : null;
    const stripWidth = state.strip ? state.strip.width : preset.strip;
    const pageX = state.phone ? state.phone.x : (device === 'spread' ? width - stripWidth - CLOSED_CONTENT_WIDTH : 0);
    const phoneWidth = state.phone ? state.phone.width : (device === 'spread' ? CLOSED_CONTENT_WIDTH + stripWidth : width);

    const nextKey = [device, state.scheme, width, height, today.getTime(), now, asleep, ageDays, lead, veil,
      pageX, phoneWidth, stripWidth, toastData ? JSON.stringify(toastData) : ''].join('|');
    if (nextKey === key) return cards;
    key = nextKey;

    const geo = {
      width, height, strip: stripWidth, side: preset.side, top: preset.top, bottomInset: preset.bottomInset,
      statusBar: preset.statusBar || 0, pageX, pageWidth: phoneWidth - stripWidth,
    };
    const day = buildDay(now, asleep);
    ctx = {
      state, options, device, geo, now, tz, date, ageDays, lead, veil, day,
      sum: summarize(day),
      tonight: tonight(day),
      // The short sleep card wherever the display is under PaneLayout.roomyHeight.
      short: height < 700,
      cardWidth: geo.pageWidth - 2 * geo.side,
      weekday: today.getUTCDay(),
      age: ageText(date, tz, ageDays),
      dateShort: `${WEEKDAYS[today.getUTCDay()].slice(0, 3)}, ${MONTHS[today.getUTCMonth()].slice(0, 3)} ${today.getUTCDate()}`,
      dateLong: `${WEEKDAYS[today.getUTCDay()]}, ${MONTHS[today.getUTCMonth()]} ${today.getUTCDate()}`,
      pace: null,
    };

    let html = '';
    if (device === 'spread') html += leadingPage(ctx);
    html += phonePage(ctx);
    html += device === 'iphone' ? slabChrome(ctx) : duoStrip(ctx);
    if (toastData) html += toast(ctx, toastData);

    root.dataset.scheme = state.scheme === 'light' ? 'light' : 'dark';
    root.dataset.device = device;
    root.innerHTML = html;
    fit(root, ctx);
    return measure(state);
  }

  function destroy() {
    alive = false;
    if (typeof document !== 'undefined' && document.fonts && document.fonts.removeEventListener) {
      document.fonts.removeEventListener('loadingdone', settle);
    }
    root.innerHTML = '';
    root.classList.remove('tou-chrome');
    delete root.dataset.scheme;
    delete root.dataset.device;
    key = null;
    cards.length = 0;
    ctx = null;
  }

  return { update, layout, destroy };
}
