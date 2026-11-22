// The place: where the hills, the knoll, the river and the clouds are.
//
// World coordinates are points: x = 0 at the anchor window's leading edge
// (`state.phone.x`), running on to the left on the spread's leading page and a
// little to the right (the camera turns that way when it looks up); y is the
// display's y in the REST pose, so the horizon is `horizon` from the top.
// Everything here is drawn by hand as numbers — a hill is a base line and a few
// rounded shoulders, never noise — and the shader and the 2-D canvas both read
// the same tables, so the tree stands exactly on the knoll the shader draws.

export const N_HILL = 8;      // planes of land, far → near
export const N_BUMP = 4;      // shoulders per plane
export const N_RIVER = 112;    // samples of the river's course
export const N_CLOUD = 6;
export const N_BLOB = 6;      // soft forms per cloud

// A plane of land:
//   base    its line, points below the horizon
//   bumps   [x, height, half-width, roundness] — rounded shoulders standing on the line
//   side    [x0, x1, fall]: the line falls away by `fall` from x0 to x1 (a spur that ends)
//   haze    how far it has gone into the air, 0 near … 1 lost
//   soft    its edge, points
//   depth   0 far … 1 near (parallax)
//   wob     [amplitude, phase]: the hand's wobble along the crest
//   mist    [level below the horizon, thickness, amount]: the pool lying in front of it
//   fade    how far down its slope it has sunk into the valley's air
//   drop    how much faster than the horizon it sinks when the camera looks up
//   woods   [x0, x1, height]: a wood standing on the crest
//   floor   true: the valley's flat floor, with the river on it
//   foot    a hill that stands ON the floor ends at this level below the horizon, in mist
const hill = (h) => ({ bumps: [], side: null, wob: [1, 0], mist: null, fade: 60, drop: 0, woods: null, floor: false, foot: 0, ...h });

export const DUO = {
  name: 'duo',
  horizon: 292,            // rest: the gap under the Today card, the middle of the strip's window
  rise: 308,               // looking up, the horizon is at 600
  turn: 79,                // …and the camera has turned this far toward the tree
  lead: 485,
  sunR: 11.5, moonR: 8.5,
  body: { low: 22.85, cap: 186, above: [306, 487] },
  arch: [0.60, 0.44, 0.10, 1.35],
  tree: { x: 396, h: 60, hill: 4 },
  tonight: { dx: 43, dy: -80 },             // from the tree's foot: above its right shoulder
  captionFoot: 34,                          // the caption's baseline above the display's foot
  hills: [
    // the far range, and the second: low rounded backs the sun sets behind
    hill({ base: -5, bumps: [[-360, 15, 170, 2], [-60, 11, 120, 2], [190, 12, 140, 2], [492, 11, 62, 2]], haze: 0.84, soft: 1.4, depth: 0, wob: [0.9, 1.3], fade: 30 }),
    hill({ base: 8, bumps: [[-425, 26, 105, 2.2], [-70, 20, 100, 2.2], [215, 16, 140, 2], [610, 18, 130, 2]], haze: 0.7, soft: 1.1, depth: 0.1, wob: [1.1, 4.1],
      mist: [10, 9, 0.6], fade: 40, woods: [150, 268, 2.4] }),
    // the valley's floor, and the river on it
    hill({ floor: true, base: 9, haze: 0.5, soft: 1.3, depth: 0.2, wob: [0.3, 2.2], fade: 200 }),
    // two hills standing on the floor: the wooded one on the far bank, in the leading margin,
    // and the round one the river bends about
    hill({ base: 300, bumps: [[-640, 282, 320, 4], [-236, 242, 150, 2.2]], foot: 104, haze: 0.5, soft: 1.0, depth: 0.3, wob: [1.0, 7.7],
      fade: 46, woods: [-600, -408, 5.6] }),
    // the knoll's hill: it ends behind the shoulder in front of it
    hill({ base: 400, bumps: [[370, 344, 330, 4], [396, 67, 84, 2.5], [200, 20, 110, 2]], haze: 0.3, soft: 0.7, depth: 0.5, wob: [0.9, 11.2],
      mist: [34, 16, 0.86], fade: 80 }),
    // the nearer shoulders: the first comes down into the valley at the fold, a rounded bluff
    hill({ base: 412, bumps: [[300, 302, 380, 4], [130, 52, 200, 2.3], [520, 34, 150, 2]], haze: 0.2, soft: 0.6, depth: 0.68, wob: [1.3, 5.9],
      mist: [146, 26, 0.5], fade: 110, drop: 40 }),
    hill({ base: 440, bumps: [[420, 220, 290, 4], [430, 44, 190, 2.3]], haze: 0.12, soft: 0.55, depth: 0.84, wob: [1.5, 9.4],
      mist: [262, 30, 0.42], fade: 120, drop: 90 }),
    hill({ base: 470, bumps: [[190, 150, 250, 4], [170, 36, 240, 2.3]], haze: 0.05, soft: 0.5, depth: 1, wob: [1.6, 3.3], fade: 140, drop: 150 }),
  ],
  // The river's course down the valley floor: [x, points below the horizon, half-width].
  // It comes through the gap in the far hills, shows a bend in the fold gutter, swings
  // back under the leading cards, and comes down the leading margin column as a broad reach.
  river: [[-196, 9, 0.8], [-160, 15, 1.6], [-214, 26, 3], [-128, 44, 5.5], [-36, 70, 8], [-150, 108, 12],
    [-322, 150, 17], [-446, 212, 25], [-462, 268, 31], [-398, 330, 40], [-300, 400, 54]],
  // The trees along the river: [points below the horizon, bank (−1 left, +1 right), points clear of the water, size].
  // Pollards and poplars in ones and twos — they say "river", give the valley its scale, and carry the season.
  bankTrees: [[11, 1, 2, 0.8], [13.5, -1, 2, 1], [17, 1, 2.5, 0.9], [24, -1, 3, 1.1], [29, 1, 3, 0.8], [36, -1, 4, 1], [41, 1, 3, 1.15], [52, -1, 5, 0.9],
    [60, -1, 30, 1.1], [66, -1, 6, 1], [84, 1, 6, 1.1], [97, 1, 8, 0.85], [118, -1, 9, 1.1], [139, 1, 12, 1], [146, -1, 11, 0.8],
    [176, 1, 14, 1.05], [226, -1, 6, 1], [238, 1, 16, 1.1], [262, -1, 5, 0.85], [300, 1, 20, 1]],
  // Clouds: where each stands, how far and how slowly it drifts in its life, and its forms
  // [dx, dy, rx, ry] with a flat foot at `foot` below its middle.
  clouds: [
    // the one in the gap between his name and the gear
    { x: 262, y: 47, travel: 14, period: 560, phase: 0.48, foot: 5,
      blobs: [[2, 0, 25, 5.6], [12, -6, 12, 8.6], [-4, -4, 13, 6.6], [26, -1.5, 10, 5.4], [-28, 1.8, 15, 3.2], [-44, 3, 10, 1.9]] },
    // on the frieze, between the leading page's title and the fold
    { x: -84, y: 52, travel: 26, period: 640, phase: 0.47, foot: 4.6,
      blobs: [[0, 0, 20, 4.6], [-8, -4.6, 9, 6.4], [6, -3.2, 10, 5], [22, 1.6, 13, 2.6], [36, 2.6, 9, 1.6]] },
    // a long low bank over the valley's far gate
    { x: -262, y: 222, travel: 40, period: 700, phase: 0.46, foot: 4.4,
      blobs: [[0, 0, 58, 4.6], [-40, -3.4, 24, 5.6], [22, -4.6, 28, 6.6], [70, 1.4, 32, 3], [-84, 1.6, 28, 2.6], [108, 2.2, 22, 2]] },
    // in the leading margin column
    { x: -436, y: 132, travel: 24, period: 600, phase: 0.5, foot: 5,
      blobs: [[0, 0, 22, 5.6], [-8, -6, 11, 8.4], [8, -3.6, 11, 6], [-24, 1.8, 11, 3], [26, 2, 14, 2.6], [40, 3, 8, 1.6]] },
    // two more in the sky above the rest view, for the evenings the camera looks up before dark
    { x: 196, y: -122, travel: 22, period: 620, phase: 0.49, foot: 5.6,
      blobs: [[0, 0, 40, 6.4], [-22, -5, 16, 8], [4, -8, 18, 10], [30, -3, 16, 7], [-52, 2, 16, 3.6], [58, 2.2, 15, 3.2]] },
    { x: 404, y: -44, travel: 16, period: 580, phase: 0.5, foot: 4,
      blobs: [[0, 0, 17, 4.4], [-6, -3.6, 8, 5.4], [7, -4, 8, 5.4], [-19, 1.2, 8, 2.6], [20, 1.2, 8, 2.4]] },
  ],
};

export const SLAB = {
  name: 'slab',
  horizon: 140,            // rest: the header is a small complete landscape
  rise: 628,               // looking up, the horizon is at 768, just above the tab capsule
  turn: 38,
  lead: 0,
  sunR: 8.5, moonR: 7.5,
  body: { low: 14.2, cap: 66, above: [154, 618] },
  arch: [0.5, 0.3, 0.08, 1.1],
  tree: { x: 285, h: 55, hill: 2 },
  tonight: { dx: 31, dy: -60 },
  captionFoot: 124,
  hills: [
    hill({ base: -4, bumps: [[330, 12, 60, 2], [455, 16, 70, 2], [40, 4, 90, 2]], haze: 0.86, soft: 1.3, depth: 0, wob: [0.6, 1.3], fade: 26 }),
    hill({ base: 2, bumps: [[392, 11, 56, 2.2], [150, 4, 100, 2]], haze: 0.72, soft: 1.0, depth: 0.1, wob: [0.7, 4.1], mist: [6, 8, 0.6], fade: 34 }),
    hill({ base: 46, bumps: [[285, 58, 62, 2.5], [108, 16, 110, 2]], haze: 0.32, soft: 0.7, depth: 0.4, wob: [0.8, 11.2], mist: [34, 18, 0.62], fade: 90 }),
    hill({ base: 150, bumps: [[90, 50, 190, 2.3], [430, 34, 150, 2]], haze: 0.24, soft: 0.6, depth: 0.58, wob: [1.3, 5.9], mist: [190, 34, 0.5], fade: 150, drop: 30 }),
    hill({ base: 330, bumps: [[310, 54, 210, 2.3], [-20, 30, 150, 2]], haze: 0.16, soft: 0.55, depth: 0.74, wob: [1.5, 9.4], mist: [372, 40, 0.45], fade: 170, drop: 70 }),
    hill({ base: 520, bumps: [[90, 50, 230, 2.3], [440, 34, 160, 2]], haze: 0.1, soft: 0.5, depth: 0.88, wob: [1.6, 3.3], mist: [560, 44, 0.4], fade: 170, drop: 120 }),
    hill({ base: 690, bumps: [[300, 44, 240, 2.3]], haze: 0.05, soft: 0.5, depth: 1, wob: [1.6, 6.1], fade: 160, drop: 170 }),
  ],
  river: null,
  bankTrees: [],
  // none in the header: it is full. Two in the sky above it, for the evenings the camera looks up before dark.
  clouds: [
    { x: 150, y: -330, travel: 20, period: 620, phase: 0.49, foot: 5,
      blobs: [[2, 0, 30, 5.6], [14, -6, 13, 8.6], [-6, -4, 15, 6.6], [30, -1.5, 12, 5.4], [-34, 1.8, 16, 3.2], [-52, 3, 11, 1.9]] },
    { x: 318, y: -120, travel: 14, period: 580, phase: 0.5, foot: 4,
      blobs: [[0, 0, 17, 4.4], [-6, -3.6, 8, 5.4], [7, -4, 8, 5.4], [-19, 1.2, 8, 2.6], [20, 1.2, 8, 2.4]] },
  ],
};

const sstep = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t); };

/** The hand's wobble along a crest: three slow sines (the shader's, to the letter). */
export function wobble(h, wx) {
  const s = h.wob[1];
  return h.wob[0] * (Math.sin(wx * 0.0231 + s) * 0.9 + Math.sin(wx * 0.0517 + s * 1.7) * 0.55 + Math.sin(wx * 0.113 + s * 2.3) * 0.28);
}

/** A plane's crest at world x: world y (rest pose). */
export function crestAt(cfg, index, wx) {
  const h = cfg.hills[index];
  let y = cfg.horizon + h.base;
  for (const [bx, bh, bw, p] of h.bumps) y -= bh * Math.exp(-Math.pow(Math.abs(wx - bx) / bw, p));
  if (h.side) y += h.side[2] * sstep(h.side[0], h.side[1], wx);
  return y + wobble(h, wx);
}

/** The skyline at world x: the highest land, whichever plane it is (rest pose). */
export function skyline(cfg, wx) {
  let y = Infinity;
  for (let i = 0; i < cfg.hills.length; i += 1) y = Math.min(y, crestAt(cfg, i, wx));
  return y;
}

/** Cubic Hermite through non-uniform stops, no overshoot (a bend's apex is flat). */
function hermite(xs, ys, x) {
  const n = xs.length;
  if (x <= xs[0]) return ys[0];
  if (x >= xs[n - 1]) return ys[n - 1];
  let i = 0;
  while (x > xs[i + 1]) i += 1;
  const h = xs[i + 1] - xs[i];
  const t = (x - xs[i]) / h;
  const slope = (j) => {
    if (j === 0) return (ys[1] - ys[0]) / (xs[1] - xs[0]);
    if (j === n - 1) return (ys[n - 1] - ys[n - 2]) / (xs[n - 1] - xs[n - 2]);
    const a = (ys[j] - ys[j - 1]) / (xs[j] - xs[j - 1]);
    const b = (ys[j + 1] - ys[j]) / (xs[j + 1] - xs[j]);
    return a * b <= 0 ? 0 : (2 * a * b) / (a + b);
  };
  const m0 = slope(i) * h, m1 = slope(i + 1) * h;
  const t2 = t * t, t3 = t2 * t;
  return (2 * t3 - 3 * t2 + 1) * ys[i] + (t3 - 2 * t2 + t) * m0 + (-2 * t3 + 3 * t2) * ys[i + 1] + (t3 - t2) * m1;
}

/** The river's course for the shader: N_RIVER samples [x, half-width], denser toward the
 *  horizon (sample k is at Y0 + (Y1 − Y0)·(k/(N−1))²), and its span [Y0, Y1]. */
export function riverTable(cfg) {
  const out = new Float32Array(N_RIVER * 2);
  if (!cfg.river) return { table: out, y0: 0, y1: 1, on: 0 };
  const Y = cfg.river.map((p) => p[1]);
  const y0 = Y[0], y1 = Y[Y.length - 1];
  for (let k = 0; k < N_RIVER; k += 1) {
    const u = k / (N_RIVER - 1);
    const y = y0 + (y1 - y0) * u * u;
    out[k * 2] = hermite(Y, cfg.river.map((p) => p[0]), y);
    out[k * 2 + 1] = hermite(Y, cfg.river.map((p) => p[2]), y);
  }
  return { table: out, y0, y1, on: 1 };
}

/** Where a cloud is at `t` seconds, and how much of it there is: it forms, drifts
 *  `travel` points in `period` seconds, thins away, and forms again where it began —
 *  so it never wanders across his name. (`t` null: at rest, mid-life.) */
export function cloudNow(cloud, t) {
  if (t == null) return { x: cloud.x, y: cloud.y, alpha: 1 };
  const f = (((t / cloud.period + cloud.phase) % 1) + 1) % 1;
  return { x: cloud.x + (f - 0.5) * cloud.travel, y: cloud.y, alpha: sstep(0, 0.14, f) * (1 - sstep(0.86, 1, f)) };
}

/** A cloud's cover at a world point, 0–1 (the shader's body, without its drawn tooth). */
export function cloudCover(cloud, at, wx, wy) {
  let f = 0;
  for (const [dx, dy, rx, ry] of cloud.blobs) {
    const u = (wx - at.x - dx) / rx, v = (wy - at.y - dy) / ry;
    f += Math.exp(-(u * u + v * v));
  }
  return sstep(0.42, 0.62, f) * (1 - sstep(cloud.foot - 1.5, cloud.foot + 1.5, wy - at.y)) * at.alpha;
}

/** The river at `Y` points below the horizon: its middle and half-width (world points), or null off its course. */
export function riverAt(cfg, Y) {
  if (!cfg.river) return null;
  const ys = cfg.river.map((p) => p[1]);
  if (Y < ys[0] || Y > ys[ys.length - 1]) return null;
  return { x: hermite(ys, cfg.river.map((p) => p[0]), Y), hw: hermite(ys, cfg.river.map((p) => p[2]), Y) };
}
