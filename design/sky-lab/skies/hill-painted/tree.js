// The tree — one grown tree, the same every day of his life.
//
// A broad, open-grown field tree (an old oak's habit): a short stout trunk that
// divides low into a few heavy limbs, one long arm reaching out on the side the
// sun sets, a crown wider than it is tall, made of lobes — one to each limb —
// with sky between them. It is grown once from a fixed seed:
//
//   1. a SCAFFOLD set by hand: the trunk and the first reach of each main limb
//      (this is the drawing — where the character is);
//   2. the rest GROWN the way a crown fills: twigs reach for the open places
//      inside the crown's lobes until it is full (space colonisation), each limb
//      as thick as the twigs it carries (the pipe model), then eased so no limb
//      has a kink the hand would not have made.
//
// Unit space: the foot of the trunk at (0, 0), up is −y, the whole about 1 tall
// and a little wider. `treeMasks()` cuts the white alpha masks the painter tints:
// wood, twigs, the crown in leaf (every leaf a small mark on a twig the tree
// already has: the far side, the near masses in three paints, the near leaves
// by the way each is turned — so the painter can light them from wherever the
// lamp is — and the thin ones light comes through), blossom, snow, frost, the
// last leaves. In the app these masks ship pre-rendered at three sizes for each
// state of the season; only their paint changes.

import { rng, noise2 } from '../../lab/noise.js';
import { hash } from '../../lab/nights.js';

const TAU = Math.PI * 2;
const smoothstep01 = (t) => { const x = Math.min(1, Math.max(0, t)); return x * x * (3 - 2 * x); };

/** The crown: lobes [cx, cy, rx, ry, weight]. Each belongs to a limb. */
const LOBES = [
  [0.040, -0.775, 0.225, 0.170, 1.0],     // the leader's
  [-0.265, -0.615, 0.200, 0.180, 1.0],    // the great left limb's
  [0.275, -0.655, 0.200, 0.170, 0.95],    // the right limb's
  [-0.350, -0.405, 0.125, 0.100, 0.50],   // a low left bough
  [0.385, -0.405, 0.125, 0.100, 0.52],    // the long arm's
  [0.005, -0.540, 0.230, 0.170, 0.60],    // the heart of the crown
];

/** The scaffold: polylines of [x, y]; each later one starts ON an earlier one. */
const SCAFFOLD = [
  // trunk: a slow S
  [[0, 0], [0.012, -0.08], [0.002, -0.16], [-0.006, -0.225]],
  // the great left limb: sweeps out, then turns up at an elbow
  [[-0.005, -0.205], [-0.075, -0.275], [-0.155, -0.325], [-0.235, -0.390], [-0.285, -0.475], [-0.300, -0.560]],
  // the leader: up through the middle, never straight
  [[-0.006, -0.225], [0.022, -0.320], [0.000, -0.420], [0.036, -0.520], [0.028, -0.630], [0.052, -0.720]],
  // the right limb
  [[0.000, -0.225], [0.075, -0.300], [0.135, -0.385], [0.215, -0.450], [0.265, -0.540], [0.275, -0.620]],
  // the long arm: low, nearly level, lifting at its end
  [[0.008, -0.165], [0.090, -0.205], [0.190, -0.235], [0.290, -0.268], [0.378, -0.330], [0.415, -0.392]],
  // a low bough off the great left limb
  [[-0.155, -0.325], [-0.245, -0.335], [-0.325, -0.355], [-0.378, -0.402]],
  // risers into the heart of the crown
  [[-0.075, -0.275], [-0.088, -0.370], [-0.060, -0.460], [-0.082, -0.550]],
  [[0.135, -0.385], [0.118, -0.470], [0.150, -0.555]],
];

export function growTree(seed = 20260702) {
  const rnd = rng(seed);
  const nodes = [];
  const add = (x, y, parent) => {
    nodes.push({ x, y, parent, kids: 0, w: 0, tip: false });
    if (parent >= 0) nodes[parent].kids += 1;
    return nodes.length - 1;
  };

  // 1. the scaffold, resampled to the growing step
  const STEP0 = 0.0125;
  const nearest = (x, y) => {
    let best = 0, bd = Infinity;
    for (let i = 0; i < nodes.length; i += 1) {
      const d = (nodes[i].x - x) ** 2 + (nodes[i].y - y) ** 2;
      if (d < bd) { bd = d; best = i; }
    }
    return best;
  };
  SCAFFOLD.forEach((line, li) => {
    let last = li === 0 ? add(line[0][0], line[0][1], -1) : nearest(line[0][0], line[0][1]);
    const P = (i) => line[Math.max(0, Math.min(line.length - 1, i))];
    for (let s = 0; s < line.length - 1; s += 1) {
      const p0 = P(s - 1), p1 = P(s), p2 = P(s + 1), p3 = P(s + 2);
      const len = Math.hypot(p2[0] - p1[0], p2[1] - p1[1]);
      const n = Math.max(1, Math.round(len / STEP0));
      for (let k = 1; k <= n; k += 1) {
        const t = k / n, t2 = t * t, t3 = t2 * t;
        const cr = (a, b, c, d) => 0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3);
        last = add(cr(p0[0], p1[0], p2[0], p3[0]), cr(p0[1], p1[1], p2[1], p3[1]), last);
      }
    }
  });
  const scaffoldCount = nodes.length;

  // 2. the open places in the crown's lobes
  const scatter = (count, rimBias) => {
    const points = [];
    let guard = 0;
    while (points.length < count && guard < count * 60) {
      guard += 1;
      const lobe = LOBES[Math.floor(rnd() * LOBES.length)];
      if (rnd() > lobe[4]) continue;
      const a = rnd() * TAU, r = Math.pow(rnd(), rimBias);
      const x = lobe[0] + Math.cos(a) * r * lobe[2];
      const y = lobe[1] + Math.sin(a) * r * lobe[3];
      if (y > -0.26) continue;                           // nothing grows under the fork
      points.push({ x, y, alive: true, near: -1, d: Infinity });
    }
    return points;
  };

  // 3. growth, twice: boughs first (long strides toward a few places), then
  //    the twigs (short strides toward many). A limb forks only so often.
  const grow = (points, STEP, REACH, KILL, rounds, spacing) => {
    let fresh = 0;
    for (const p of points) { p.near = -1; p.d = Infinity; }
    const forkedAt = new Map();                          // node → the round it last sent out a side shoot
    for (let round = 0; round < rounds; round += 1) {
      for (const p of points) {
        if (!p.alive) continue;
        for (let i = fresh; i < nodes.length; i += 1) {
          const d = Math.hypot(p.x - nodes[i].x, p.y - nodes[i].y);
          if (d < p.d) { p.d = d; p.near = i; }
        }
        if (p.d < KILL) p.alive = false;
      }
      fresh = nodes.length;
      const pull = new Map();
      for (const p of points) {
        if (!p.alive || p.d >= REACH) continue;
        const e = pull.get(p.near) ?? { x: 0, y: 0, n: 0 };
        e.x += (p.x - nodes[p.near].x) / p.d;
        e.y += (p.y - nodes[p.near].y) / p.d;
        e.n += 1;
        pull.set(p.near, e);
      }
      if (pull.size === 0) break;
      let grew = false;
      for (const [i, e] of pull) {
        const n = nodes[i];
        if (n.kids >= 2) continue;
        if (n.kids === 1) {
          // a side shoot: not beside another one
          let near = false, a = i;
          for (let k = 0; k < spacing && a >= 0; k += 1) { if (k > 0 && nodes[a].kids >= 2) near = true; a = nodes[a].parent; }
          if (near || forkedAt.has(i)) continue;
          if (e.n < 2 && rnd() < 0.6) continue;
        }
        const len = Math.hypot(e.x, e.y) || 1;
        const nx = n.x + (e.x / len) * STEP + (rnd() - 0.5) * STEP * 0.4;
        const ny = n.y + (e.y / len) * STEP - STEP * 0.14 + (rnd() - 0.5) * STEP * 0.4;   // lifting toward the light
        let crowded = false;
        for (let m = nodes.length - 1; m >= 0; m -= 1) {
          if (Math.abs(nodes[m].x - nx) < STEP * 0.6 && Math.abs(nodes[m].y - ny) < STEP * 0.6) { crowded = true; break; }
        }
        if (crowded) continue;
        if (n.kids === 1) {
          forkedAt.set(i, round);
          // the shoot marks its neighbours too
          let a = n.parent;
          for (let k = 0; k < spacing && a >= 0; k += 1) { forkedAt.set(a, round); a = nodes[a].parent; }
        }
        add(nx, ny, i);
        grew = true;
      }
      if (!grew && round > 4) break;
    }
  };
  grow(scatter(170, 0.6), 0.0165, 0.30, 0.042, 90, 5);
  const boughCount = nodes.length;

  // 3b. the twigs: sprays that leave the boughs outward and upward, forking at
  //     narrow angles and stopping at the crown's own outline — the fine haze
  //     that gives a bare crown its shape.
  const inside = (x, y, k = 1.04) => {
    if (y > -0.25) return false;
    for (const [cx, cy, rx, ry] of LOBES) {
      const u = (x - cx) / (rx * k), v = (y - cy) / (ry * k);
      if (u * u + v * v < 1) return true;
    }
    return false;
  };
  const CELL = 0.0105;
  const grid = new Map();
  const cellKey = (x, y) => `${Math.floor(x / CELL)},${Math.floor(y / CELL)}`;
  const mark = (x, y) => { const k = cellKey(x, y); grid.set(k, (grid.get(k) ?? 0) + 1); };
  for (const n of nodes) mark(n.x, n.y);
  const TW = 0.0108;
  const HEART = [0.0, -0.50];
  const spray = (parent, x0, y0, th0, len, depth) => {
    let cur = parent, x = x0, y = y0, th = th0;
    const steps = Math.max(2, Math.round(len / TW));
    let side = rnd() < 0.5 ? 1 : -1;
    let made = 0;
    for (let k = 1; k <= steps; k += 1) {
      th += (rnd() - 0.5) * 0.26;
      // lift toward the light, and lean away from the heart of the crown
      const out = Math.atan2(y - HEART[1], x - HEART[0]);
      let d = out - th; while (d > Math.PI) d -= TAU; while (d < -Math.PI) d += TAU;
      th += 0.05 * d;
      d = -Math.PI / 2 - th; while (d > Math.PI) d -= TAU; while (d < -Math.PI) d += TAU;
      th += 0.035 * d;
      x += Math.cos(th) * TW; y += Math.sin(th) * TW;
      if (!inside(x, y)) break;
      if ((grid.get(cellKey(x, y)) ?? 0) >= 3) break;
      cur = add(x, y, cur);
      mark(x, y);
      made += 1;
      if (depth < 5 && k >= 2 && k < steps && rnd() < 0.34) {
        spray(cur, x, y, th + side * (0.55 + 0.4 * rnd()), len * (0.42 + 0.2 * rnd()), depth + 1);
        side = -side;
      }
    }
    if (depth < 5 && made >= 2) {
      const spread = 0.26 + 0.2 * rnd();
      spray(cur, x, y, th + spread, len * (0.60 + 0.2 * rnd()), depth + 1);
      spray(cur, x, y, th - spread * (0.7 + 0.5 * rnd()), len * (0.60 + 0.2 * rnd()), depth + 1);
    }
  };
  for (let i = 1; i < boughCount; i += 1) {
    const n = nodes[i];
    const q = nodes[n.parent];
    const th = Math.atan2(n.y - q.y, n.x - q.x);
    if (n.kids === 0) {
      spray(i, n.x, n.y, th, 0.11 + 0.05 * rnd(), 1);
      continue;
    }
    if (n.y > -0.275 && Math.abs(n.x) < 0.11) continue;         // not on the trunk or the limbs' first reach
    if (hash(i, 51) > 0.42) continue;
    // a side spray, more often on the limb's outer / upper side
    const out = Math.atan2(n.y - HEART[1], n.x - HEART[0]);
    let sideSign = Math.sin(out - th) > 0 ? 1 : -1;
    if (rnd() < 0.28) sideSign = -sideSign;
    const reach = 0.060 + 0.075 * rnd();
    spray(i, n.x, n.y, th + sideSign * (0.75 + 0.45 * rnd()), reach, 2);
  }

  // 4. ease the grown limbs (never the hand's scaffold, never a fork)
  for (let pass = 0; pass < 3; pass += 1) {
    const firstKid = new Int32Array(nodes.length).fill(-1);
    for (let i = 1; i < nodes.length; i += 1) if (firstKid[nodes[i].parent] < 0) firstKid[nodes[i].parent] = i;
    for (let i = scaffoldCount; i < nodes.length; i += 1) {
      const n = nodes[i];
      if (n.kids !== 1) continue;
      const a = nodes[n.parent], b = nodes[firstKid[i]];
      n.x += ((a.x + b.x) / 2 - n.x) * 0.5;
      n.y += ((a.y + b.y) / 2 - n.y) * 0.5;
    }
  }

  // 5. every limb as thick as what it carries (the pipe model)
  const POWER = 2.12;
  for (let i = nodes.length - 1; i >= 0; i -= 1) {
    const n = nodes[i];
    if (n.kids === 0) { n.w = 1; n.tip = true; }
    if (n.parent >= 0) nodes[n.parent].w += n.w;
  }
  const foot = Math.pow(nodes[0].w, 1 / POWER);
  const TRUNK = 0.072;
  for (const n of nodes) n.w = Math.max(0.0026, (Math.pow(n.w, 1 / POWER) / foot) * TRUNK);
  // steps from the farthest tip it carries (0 at a tip): for leaves and twigs
  for (const n of nodes) n.order = 0;
  for (let i = nodes.length - 1; i >= 0; i -= 1) {
    const n = nodes[i];
    if (n.parent >= 0) nodes[n.parent].order = Math.max(nodes[n.parent].order, n.order + 1);
  }
  const tips = nodes.filter((n) => n.tip);
  let minX = 0, maxX = 0, minY = 0;
  for (const n of nodes) { minX = Math.min(minX, n.x); maxX = Math.max(maxX, n.x); minY = Math.min(minY, n.y); }
  return { nodes, tips, lobes: LOBES, bounds: { minX, maxX, minY }, scaffoldCount, boughCount };
}

/** The crown's outline at unit x: the highest y (most negative) any lobe reaches, or null. For keeping stars clear. */
export function crownTop(x) {
  let top = null;
  for (const [cx, cy, rx, ry] of LOBES) {
    const u = (x - cx) / rx;
    if (Math.abs(u) >= 1) continue;
    const y = cy - ry * Math.sqrt(1 - u * u);
    if (top == null || y < top) top = y;
  }
  return top;
}

// ── in leaf: where the foliage is massed ──
// Blocked in by hand over the limbs, as a painter would before drawing a single leaf.

/** The crown's OUTLINE in leaf: a few convex masses of unequal size, [cx, cy, r] — the top, the two
 *  shoulders, the heart, the tuft on the low left bough, the spray at the long arm's end (16, 12, 10,
 *  9, 7 and 5 pt on the Duo's 88 pt tree) — and the smaller ones that join them. A leaf grows only on a
 *  twig inside one of them: the silhouette is a run of unequal rounded masses, the sky between two of
 *  them comes to a point (a V, never a square bay), and no mass has a level top or a plumb side. The
 *  great bay at the lower right, where the sun goes down, is simply where no mass is — open in every
 *  season, so the sun always sets through limbs. Nothing stands further right than 0.44 (the leaf at
 *  the long arm's end is drawn in along the arm), nor further left than −0.44. */
const CROWN = [
  [0.055, -0.770, 0.182],                               // the top, over the leader
  [-0.285, -0.628, 0.138],                              // the left shoulder, on the great left limb
  [0.310, -0.665, 0.120],                               // the right shoulder
  [-0.045, -0.560, 0.104],                              // the heart, hanging over the fork
  [-0.355, -0.432, 0.078],                              // the tuft on the low left bough
  [0.380, -0.468, 0.058],                               // the spray at the long arm's end
  [0.165, -0.535, 0.088], [-0.190, -0.490, 0.070],      // under the two shoulders
  [-0.135, -0.760, 0.075],                              // between the top and the left shoulder, set back: a notch there, not a gap
  [0.378, -0.565, 0.052],                               // the bough that hangs from the right shoulder to the arm's end: the spray there is part of the crown
  [-0.275, -0.485, 0.050],                              // …and the one that joins the low tuft to the left shoulder
];

/** lab/noise.js's lattice, read on a turned grid. A threshold through value noise follows its
 *  lattice — level tops and plumb sides; turned 31° a mass's edge has neither. */
const TURN_C = Math.cos(0.54), TURN_S = Math.sin(0.54);
const turned = (x, y, f, seed) => noise2((x * TURN_C + y * TURN_S) * f + 3.1, (y * TURN_C - x * TURN_S) * f + 7.9, seed);

/** How far unit (x, y) is from the heart of the nearest mass of the crown's outline: under 1 inside it.
 *  (Every mass is a little out of round.) */
export function crownEdge(x, y) {
  const swell = 1 + 0.16 * (turned(x, y, 6.5, 53) - 0.5);
  let edge = 9;
  for (const [cx, cy, r] of CROWN) edge = Math.min(edge, Math.hypot(x - cx, y - cy) / (r * swell));
  return edge;
}

/** The NEAR forms of the crown: boughs of foliage, unequal, NEAREST FIRST — the low ones hang in front
 *  of the ones above and behind them, so each one's lit side lies against its neighbour's shade.
 *  [cx, cy, rx, ry, paint (0, 1 or 2), mass]. `mass`: which of the crown's few large masses it is part
 *  of (0 the top, 1 the left shoulder, 2 the right shoulder, 3 the heart, 4 a tuft of its own) — the
 *  forms of one mass are painted alike and turn to the light together. A leaf belongs to the nearest
 *  form it is inside; the leaves inside none are the far side of the crown. */
const FORMS = [
  [0.385, -0.470, 0.055, 0.046, 1, 4],      // the spray at the long arm's end
  [-0.355, -0.428, 0.090, 0.066, 2, 4],     // the tuft on the low left bough
  [0.030, -0.485, 0.100, 0.070, 1, 3],      // the heart, hanging lowest over the fork
  [-0.170, -0.545, 0.105, 0.085, 0, 3],     // …its left
  [0.200, -0.520, 0.095, 0.072, 2, 3],      // …its right, over the bay
  [-0.345, -0.615, 0.125, 0.105, 1, 1],     // the left shoulder, on the great left limb
  [0.345, -0.655, 0.135, 0.105, 0, 2],      // the right shoulder
  [0.085, -0.620, 0.110, 0.080, 2, 2],
  [-0.115, -0.700, 0.115, 0.080, 0, 1],
  [0.215, -0.775, 0.120, 0.078, 1, 0],      // the top's right
  [0.020, -0.840, 0.135, 0.085, 2, 0],      // the top, over the leader
  [-0.200, -0.800, 0.105, 0.070, 1, 0],     // …its left
];
/** The large masses' own centres and reach, for the way a whole mass turns: [cx, cy, rx, ry]. */
const MASSES = [
  [0.025, -0.815, 0.25, 0.13], [-0.25, -0.64, 0.24, 0.15], [0.25, -0.655, 0.25, 0.14], [0.0, -0.52, 0.30, 0.10], [0, 0, 0, 0],
];

/** SKY in the crown: [cx, cy, rx, ry, kind]. kind 0: the bays that run in from the underside along the
 *  limbs; 1: holes that are always there; 2: holes that open as the crown thins. */
const SKY = [
  [0.225, -0.395, 0.075, 0.060, 0],                                           // the sunset bay's head, under the right shoulder (the bay itself is the outline's: CROWN)
  [0.012, -0.365, 0.070, 0.070, 0],                                           // under the heart, round the fork
  [-0.215, -0.415, 0.060, 0.050, 0],                                          // between the great limb and its low bough
  [-0.225, -0.585, 0.040, 0.034, 1], [0.235, -0.598, 0.036, 0.040, 1],       // where the two great limbs pass
  [0.040, -0.612, 0.030, 0.036, 1], [-0.065, -0.745, 0.034, 0.022, 1],       // …and the leader
  [0.150, -0.455, 0.030, 0.026, 1], [-0.300, -0.510, 0.030, 0.022, 1],
  [0.105, -0.780, 0.022, 0.016, 1], [-0.115, -0.470, 0.024, 0.020, 1],
  [-0.045, -0.885, 0.030, 0.018, 2], [0.115, -0.850, 0.028, 0.020, 2], [-0.300, -0.730, 0.030, 0.022, 2],
  [0.300, -0.760, 0.032, 0.022, 2], [-0.150, -0.660, 0.030, 0.024, 2], [0.140, -0.640, 0.026, 0.022, 2],
  [-0.400, -0.620, 0.026, 0.024, 2], [0.420, -0.660, 0.026, 0.022, 2], [-0.180, -0.830, 0.026, 0.018, 2],
];

/** What a leaf at unit (x, y) is part of. `open` 0–1: how far the crown has thinned; `pick` 0–1: the
 *  leaf's own lot (a form's edge frays into single leaves: near it, some belong and some do not).
 *  → { clear   0 in a bay or a hole … 1 in full leaf (the chance a leaf is here at all),
 *      bay     the same for the bays alone,
 *      form    which near form it belongs to (−1: the far side of the crown),
 *      deep    0 at the form's edge … 1 at its heart,
 *      tx, ty  the way it is turned — out from its form, out from its mass, and off the small swells
 *              of the foliage (a slow noise) — what the painter lights it by } */
function leafAt(x, y, open, pick = 0.5) {
  let clear = 1, bay = 1;
  const rag = 1 + 0.36 * (turned(x, y, 21, 7) - 0.5);
  for (const [cx, cy, rx, ry, kind] of SKY) {
    const k = kind === 2 ? 1.25 * open : kind === 1 ? 1 + 0.5 * open : 1 + 0.12 * open;
    if (k < 0.1) continue;
    const d = Math.hypot((x - cx) / (rx * k), (y - cy) / (ry * k)) * rag;
    if (d >= 1.25) continue;
    const c = smoothstep01((d - 0.80) / 0.42);
    clear = Math.min(clear, c);
    if (kind === 0) bay = Math.min(bay, c);
  }
  let form = -1, deep = 0, tx = 0, ty = 0;
  const reach = 0.74 + 0.40 * pick;
  for (let k = 0; k < FORMS.length; k += 1) {
    const [cx, cy, rx, ry, , mass] = FORMS[k];
    const ux = (x - cx) / rx, uy = (y - cy) / ry;
    if (Math.abs(ux) > 1.5 || Math.abs(uy) > 1.5) continue;
    const d = Math.hypot(ux, uy) / (1 + 0.40 * (turned(x + k * 0.81, y - k * 0.34, 9, 31) - 0.5) + 0.22 * (turned(x - k * 0.12, y + k * 0.24, 24, 33) - 0.5));
    if (d >= reach) continue;
    form = k; deep = 1 - d;
    const M = MASSES[mass];
    tx = 0.72 * ux + (M[2] ? 0.34 * (x - M[0]) / M[2] : 0);
    ty = 0.72 * uy + (M[3] ? 0.34 * (y - M[1]) / M[3] : 0);
    break;
  }
  // the crown's outline: inside one of its masses, or there is no leaf. Its edge frays into single
  // leaves, each by its own lot — a leaf's length either way, a little further in as the crown thins
  const out = 1 - smoothstep01((crownEdge(x, y) - (0.93 + 0.15 * (pick - 0.5) - 0.07 * open)) / 0.05);
  clear *= out;
  bay = Math.min(bay, out);
  // small gaps where the foliage is loose (fewer in the heart of a form, more as the crown thins)
  const gap = turned(x, y, 13.5, 11);                  // (a seed whose low places fall between the masses, not on one)
  clear *= smoothstep01((gap - (0.27 + 0.13 * open - 0.16 * Math.max(0, deep))) / 0.10);
  const e = 0.006, f = 17;
  const bx = (noise2((x + e) * f, y * f, 41) - noise2((x - e) * f, y * f, 41)) / (2 * e * f);
  const by = (noise2(x * f, (y + e) * f, 41) - noise2(x * f, (y - e) * f, 41)) / (2 * e * f);
  return { clear, bay, form, deep, tx: tx - 0.30 * bx, ty: ty - 0.30 * by };
}

/**
 * Cut the tree's masks at a size.
 *   mk(w, h)   a canvas factory
 *   H          the tree's height in device pixels (unit 1 → H)
 *   s          device pixels per point
 *   sea        lab/season.js's answer (foliage, leafHue, leafFall, blossom, snow, frost)
 * → { w, h, cx, cy, wood, twigs, leaf: { back, twigs, body[3], turned[8], thin, gaps }, blossomA, blossomB,
 *     snow, snowFine, frost, lastLeaves }
 *   every mask w × h, the foot of the trunk at (cx, cy); the ones a season has no use for are absent.
 *   (The bare tree — wood, twigs, frost, lastLeaves — is cut exactly as it always was.)
 */
export function treeMasks(tree, mk, H, s, sea) {
  const padX = Math.ceil(H * 0.70), padTop = Math.ceil(H * 1.10), padBot = Math.ceil(H * 0.10);
  const w = padX * 2, h = padTop + padBot;
  const cx = padX, cy = padTop;
  const X = (u) => cx + u * H, Y = (v) => cy + v * H;
  const mask = () => {
    const ctx = mk(w, h).getContext('2d');
    ctx.fillStyle = '#fff'; ctx.strokeStyle = '#fff'; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
    return ctx;
  };
  const { nodes, tips } = tree;
  const out = { w, h, cx, cy };

  // Wood: the limbs you can count. Twigs: everything finer, drawn thinner than
  // a pixel can hold, so it is a tone — the haze that gives a bare crown its outline.
  const wood = mask(), twigs = mask();
  const fine = 0.0105;                                  // unit width under which a limb is a twig
  for (let i = 1; i < nodes.length; i += 1) {
    const n = nodes[i], q = nodes[n.parent];
    const px = n.w * H;
    const ctx = n.w < fine ? twigs : wood;
    const lw = Math.max(0.85, px);
    ctx.globalAlpha = n.w < fine ? Math.min(1, 0.55 + 0.45 * (px / 0.85)) * (0.72 + 0.28 * Math.min(1, n.order / 5)) : 1;
    ctx.lineWidth = lw;
    ctx.beginPath();
    ctx.moveTo(X(q.x), Y(q.y));
    ctx.lineTo(X(n.x), Y(n.y));
    ctx.stroke();
  }
  wood.globalAlpha = 1; twigs.globalAlpha = 1;
  // the foot, flaring into the ground: two roots' worth
  const n6 = nodes[5];
  wood.beginPath();
  wood.moveTo(X(-0.082), Y(0.018));
  wood.bezierCurveTo(X(-0.045), Y(0.004), X(-0.036), Y(-0.03), X(n6.x - n6.w * 0.52), Y(n6.y));
  wood.lineTo(X(n6.x + n6.w * 0.52), Y(n6.y));
  wood.bezierCurveTo(X(0.040), Y(-0.03), X(0.050), Y(0.004), X(0.092), Y(0.018));
  wood.closePath();
  wood.fill();
  out.wood = wood.canvas;
  out.twigs = twigs.canvas;

  // ── the crown in leaf ──
  // By the same hand as the bare tree: LEAVES, not clumps. Every leaf is one small pointed mark that
  // grows on a twig the tree already has, splayed from it; a full crown is some eight thousand of them.
  // Where they are massed is blocked in first, as a painter would (FORMS, SKY above): the marks inside
  // a form are the near, lit foliage and are cut in front of the limbs; all of them together, a little
  // larger and a touch softer, are the far side of the crown, behind the limbs. So the silhouette
  // breaks into leaf points and gaps (it is the twigs' own outline, frayed), the limbs show wherever
  // the near forms part, and sky comes through the bays and holes.
  //   leaf.twigs      the twigs that are in sight in leaf (below)
  //   leaf.back       every leaf — the crown's far side and its whole silhouette (behind the wood)
  //   leaf.body[3]    the near masses, in three paints (several greens; amber, gold and russet)
  //   leaf.turned[8]  the near leaves by the way each is turned (eight directions, 0 = +x, clockwise on
  //                   the canvas): the painter lights those turned to the lamp and shades those turned away
  //   leaf.thin       the leaves light comes through: the crown's edges, the rims of its holes, a few inside
  //   leaf.gaps       the same leaves cut a little larger: taken out whole where a disc of light stands behind the crown
  if (sea.foliage > 0.04) {
    const fall = sea.leafFall, bloom = sea.blossom ?? 0;
    const grown = sea.foliage * sea.foliage * (3 - 2 * sea.foliage);     // spring: the leaves are few and small, then fill
    const keep = (0.30 + 0.70 * grown) * (1 - 0.40 * fall) * (1 - 0.76 * bloom);
    const sizeK = (0.60 + 0.40 * grown) * (1 - 0.18 * bloom) * (1 - 0.06 * fall);
    const open = Math.min(1, 0.95 * fall + 1.1 * (1 - grown));          // how far the crown has opened (autumn; early spring)
    const lists = { back: [], body: [[], [], []], turned: [[], [], [], [], [], [], [], []], thin: [], gaps: [] };
    const put = (list, x, y, len, wid, ang) => { list.push(x, y, len, wid, ang); };
    const inLeaf = new Uint8Array(nodes.length);                        // the twigs that carry a leaf (then: or lead to one)
    for (let i = 1; i < nodes.length; i += 1) {
      const n = nodes[i];
      if (n.w >= 0.016 || n.y > -0.27) continue;
      const q = nodes[n.parent];
      const th = Math.atan2(n.y - q.y, n.x - q.x);
      // autumn takes the twig ends first: the twigs show at the crown's edge
      const bare = fall * (n.order === 0 ? 0.9 : n.order === 1 ? 0.7 : n.order === 2 ? 0.4 : n.order === 3 ? 0.15 : 0);
      const per = n.tip ? 3 : 2;
      for (let j = 0; j < per; j += 1) {
        const id = i * 4 + j;
        if (hash(id, 201) > keep || hash(id, 202) < bare) continue;
        // a leaf stands off its twig, to one side then the other; the end one carries on past the tip
        const side = j === 2 ? 0 : j === 0 ? 1 : -1;
        const a = th + side * (0.5 + 0.95 * hash(id, 203)) + (hash(id, 208) - 0.5) * 0.5;
        const len = (0.019 + 0.014 * hash(id, 204)) * sizeK;
        const reach = len * (0.34 + 0.5 * hash(id, 205));
        const x = n.x + Math.cos(a) * reach, y = n.y + Math.sin(a) * reach - 0.003;
        const at = leafAt(x, y, open, hash(id, 211));
        if (hash(id, 206) >= at.clear) continue;
        const wid = len * (0.40 + 0.16 * hash(id, 207));
        // (a leaf hangs a little: its mark leans toward the level as often as along the twig)
        const ang = a + (hash(id, 209) - 0.5) * 0.9;
        put(lists.back, x, y + 0.003, len * 1.12, wid * 1.2, ang);
        inLeaf[i] = 1;
        if (at.clear < 0.78 || hash(id, 210) < 0.16 + 0.5 * open) { put(lists.thin, x, y, len, wid, ang); put(lists.gaps, x, y + 0.0015, len * 1.2, wid * 1.34, ang); }
        if (at.form < 0) continue;
        // the paint: mostly its form's own, but no two leaves quite alike — a mass is many marks, not one tone
        const own = FORMS[at.form][4], lot = hash(id, 212);
        put(lists.body[lot < 0.56 ? own : lot < 0.80 ? (own + 1) % 3 : (own + 2) % 3], x, y, len, wid, ang);
        // the way it is turned: surely at its form's edge, less and less toward its heart
        const turn = Math.hypot(at.tx, at.ty);
        if (hash(id, 214) < 0.84 * smoothstep01((turn - 0.30) / 0.62)) {
          const dir = Math.atan2(at.ty, at.tx) + (hash(id, 215) - 0.5) * 0.7;
          put(lists.turned[((Math.round(dir / (TAU / 8)) % 8) + 8) % 8], x, y, len * 0.94, wid * 0.92, ang);
        }
      }
    }
    const minLen = 1.15 * s, minWid = 0.56 * s;
    const strew = (list, soft) => {
      const ctx = mask();
      let count = 0;
      ctx.beginPath();
      for (let k = 0; k < list.length; k += 5) {
        const len = Math.max(minLen, list[k + 2] * H), wid = Math.max(minWid, list[k + 3] * H);
        const px = X(list[k]), py = Y(list[k + 1]);
        const c = Math.cos(list[k + 4]), sn = Math.sin(list[k + 4]);
        const hx = c * len * 0.5, hy = sn * len * 0.5, wx = -sn * wid, wy = c * wid;
        ctx.moveTo(px - hx, py - hy);
        ctx.quadraticCurveTo(px + wx, py + wy, px + hx, py + hy);
        ctx.quadraticCurveTo(px - wx, py - wy, px - hx, py - hy);
        count += 1;
        if (count % 400 === 0) { ctx.fill(); ctx.beginPath(); }
      }
      ctx.fill();
      if (!soft) return ctx.canvas;
      // (the far side, which is the crown's whole silhouette.) A hairline slit between leaves is not sky —
      // a hole is a leaf wide or more: slits a pixel wide are closed, and nothing is taken off any leaf.
      const closed = mask();
      closed.filter = `blur(${(0.5 * s).toFixed(2)}px)`;
      closed.drawImage(ctx.canvas, 0, 0);
      closed.filter = 'none';
      const img = closed.getImageData(0, 0, w, h);
      for (let k = 3; k < img.data.length; k += 4) {
        const v = img.data[k];
        img.data[k] = v <= 120 ? 0 : v >= 152 ? 255 : Math.round(((v - 120) / 32) * 255);
      }
      closed.putImageData(img, 0, 0);
      closed.drawImage(ctx.canvas, 0, 0);
      // …and it is a touch softer than the near leaves: the same shape, a little out of focus under itself
      const blurred = mask();
      blurred.filter = `blur(${(soft * s).toFixed(2)}px)`;
      blurred.drawImage(closed.canvas, 0, 0);
      blurred.filter = 'none';
      blurred.globalAlpha = 0.55;
      blurred.drawImage(closed.canvas, 0, 0);
      blurred.globalAlpha = 1;
      return blurred.canvas;
    };
    const back = strew(lists.back, 0.14);
    // The twigs in leaf. In a full crown the twigs are where the leaves are: what is seen of them is
    // the ones that LEAD to leaves — across a hole, out along a bare stretch of limb to the spray at
    // its end — and nothing else (a hole is sky and limbs). As the crown opens (autumn; the first
    // leaves of spring) more and more of every twig stands clear of its leaves, until the whole bare
    // crown is back.
    let twigsIn = twigs.canvas;
    if (open < 0.6) {
      for (let i = nodes.length - 1; i >= 1; i -= 1) if (inLeaf[i]) inLeaf[nodes[i].parent] = 1;
      const cut = mask();
      if (open > 0.04) {
        // (how far a twig may stand clear of the leaves: further and further as the crown opens)
        cut.drawImage(twigs.canvas, 0, 0);
        const near = mask();
        near.filter = `blur(${((0.2 + 6 * open) * s).toFixed(2)}px)`;
        near.drawImage(back, 0, 0);
        near.filter = 'none';
        const img = near.getImageData(0, 0, w, h);
        const lo = 255 * (0.42 - 0.3 * Math.min(1, open * 4)), hi = lo + 40;
        for (let k = 3; k < img.data.length; k += 4) {
          const v = img.data[k];
          img.data[k] = v <= lo ? 0 : v >= hi ? 255 : Math.round(((v - lo) / (hi - lo)) * 255);
        }
        near.putImageData(img, 0, 0);
        cut.globalCompositeOperation = 'destination-in';
        cut.drawImage(near.canvas, 0, 0);
        cut.globalCompositeOperation = 'source-over';
      }
      // (drawn exactly as the bare twigs are — first cleared from what is already there, so none is inked twice)
      for (const clear of [true, false]) {
        cut.globalCompositeOperation = clear ? 'destination-out' : 'source-over';
        for (let i = 1; i < nodes.length; i += 1) {
          const n = nodes[i];
          if (!inLeaf[i] || n.w >= fine) continue;
          const q = nodes[n.parent], px = n.w * H;
          cut.globalAlpha = clear ? 1 : Math.min(1, 0.55 + 0.45 * (px / 0.85)) * (0.72 + 0.28 * Math.min(1, n.order / 5));
          cut.lineWidth = Math.max(0.85, px);
          cut.beginPath();
          cut.moveTo(X(q.x), Y(q.y));
          cut.lineTo(X(n.x), Y(n.y));
          cut.stroke();
        }
      }
      cut.globalAlpha = 1;
      twigsIn = cut.canvas;
    }
    out.leaf = {
      back,
      twigs: twigsIn,
      body: lists.body.map((list) => strew(list)),
      turned: lists.turned.map((list) => strew(list)),
      thin: strew(lists.thin),
      gaps: strew(lists.gaps),
    };
  }

  // Blossom: flowers, not foam. Each is a small round mark and they come in SPRAYS — some twigs laden
  // from end to end, the next ones bare — thickest toward the twig ends and on the upper side, in two
  // tones (the lit flowers; the ones under them and in the crown's shade). The twigs and the limbs
  // stay in sight between the sprays, and the first leaves come with them (above).
  if (sea.blossom > 0.04) {
    const a = mask(), b = mask();
    const full = sea.blossom;
    const dot = (ctx, x, y, r) => { ctx.moveTo(x + r, y); ctx.arc(x, y, r, 0, TAU); };
    a.beginPath(); b.beginPath();
    for (let i = 1; i < nodes.length; i += 1) {
      const n = nodes[i];
      if (n.w >= 0.0105 || n.order > 7 || n.y > -0.27) continue;
      // which sprays are laden: a slow field over the crown, and the twig ends more than their feet
      // (…on the turned grid, so no mass of blossom has a plumb side; and a few sprays always cross the trunk's own line under the top)
      const laden = turned(n.x, n.y, 11, 61) * 0.75 + turned(n.x, n.y, 27, 62) * 0.25
        + 0.22 * Math.exp(-(((n.x - 0.005) / 0.075) ** 2) - (((n.y + 0.845) / 0.085) ** 2));
      const p = full * smoothstep01((laden + 0.06 * (3 - Math.min(3, n.order)) - 0.50) / 0.20) * (0.2 + 0.8 * leafAt(n.x, n.y, 0.4).bay) * 0.47;
      for (let j = 0; j < 3; j += 1) {
        const id = i * 4 + j;
        if (hash(id, 71) > p * (j === 0 ? 1 : 0.7)) continue;
        const ang = hash(id, 72) * TAU, off = 0.004 + 0.011 * hash(id, 73);
        const x = X(n.x + Math.cos(ang) * off), y = Y(n.y + Math.sin(ang) * off * 0.8 - 0.005);
        const r = Math.max(0.5 * s, (0.0056 + 0.0046 * hash(id, 74)) * H);
        // the lower ones of a spray, and one in three, are in its shade
        const shaded = Math.sin(ang) > 0.35 || hash(id, 75) < 0.3;
        if (shaded) dot(b, x + 0.3 * s, y + 0.5 * s, r * 1.12); else dot(a, x, y, r);
      }
    }
    a.fill(); b.fill();
    out.blossomA = a.canvas; out.blossomB = b.canvas;
  }

  // Snow LIES: one unbroken cap along the upper side of every stretch of limb level enough to hold it —
  // deepest along the middle of the stretch, thinning to nothing at both ends and where the limb
  // steepens, its top a little uneven (1.5–2 pt on the great limbs: it has to be read from the strip,
  // at phone size; under a point on the boughs) — never a row of blocks. Whole stretches are bare
  // where it has slid off. A small pillow lies in the forks. The level twigs carry a hair of it
  // (`snowFine`). Frost (below, `lying`) is a hair of the same on the wood's top edge.
  if (sea.snow > 0.04) {
    const amount = sea.snow;
    const ctx = mask();
    const kids = nodes.map(() => []);
    for (let i = 1; i < nodes.length; i += 1) kids[nodes[i].parent].push(i);
    /** How level the limb is at node i (0 straight up … 1 level), judged over a longer stretch so a cap runs on where the limb only wavers. */
    const level = (i) => {
      const n = nodes[i], q = nodes[n.parent];
      const dx = n.x - q.x, dy = n.y - q.y;
      let a = n.parent, hops = 1;
      while (hops < 5 && nodes[a].parent >= 0) { a = nodes[a].parent; hops += 1; }
      const ex = n.x - nodes[a].x, ey = n.y - nodes[a].y;
      return Math.min(1, 0.25 * (Math.abs(dx) / (Math.hypot(dx, dy) || 1)) + 0.75 * (Math.abs(ex) / (Math.hypot(ex, ey) || 1)));
    };
    /** Snow slides off in runs: whole stretches of a limb are bare. */
    const slid = (i) => {
      let run = i, steps = 0;
      while (steps < 3 && nodes[run].parent > 0 && nodes[nodes[run].parent].kids === 1) { run = nodes[run].parent; steps += 1; }
      return hash(Math.floor(run / 3), 85) > 0.5 + 0.45 * amount;
    };
    const MINW = 0.0085;
    const flat = new Float32Array(nodes.length);
    const holds = new Uint8Array(nodes.length);
    for (let i = 1; i < nodes.length; i += 1) {
      if (nodes[i].w < MINW) continue;
      flat[i] = level(i);
      holds[i] = flat[i] >= 0.42 && !slid(i) ? 1 : 0;
    }
    const taken = new Uint8Array(nodes.length);
    for (let i = 1; i < nodes.length; i += 1) {
      if (!holds[i] || taken[i]) continue;
      // one stretch: from where this limb begins to hold snow, along its heir, to where it stops
      const run = [nodes[i].parent, i];
      taken[i] = 1;
      for (let cur = i; ;) {
        let heir = -1;
        for (const k of kids[cur]) if (holds[k] && !taken[k] && (heir < 0 || nodes[k].w > nodes[heir].w)) heir = k;
        if (heir < 0) break;
        run.push(heir); taken[heir] = 1; cur = heir;
      }
      const m = run.length;
      const px = run.map((k) => X(nodes[k].x)), py = run.map((k) => Y(nodes[k].y));
      const along = [0];
      for (let k = 1; k < m; k += 1) along.push(along[k - 1] + Math.hypot(px[k] - px[k - 1], py[k] - py[k - 1]));
      const total = along[m - 1];
      const stout = nodes[run[1]].w * H;
      if (total < Math.max(1.6 * s, stout * 0.8)) continue;                 // too short a ledge to hold any
      const ends = Math.min(total * 0.5, Math.max(1.5 * s, stout * 1.1));   // how far in from an end the cap is full
      const top = [], foot = [];
      for (let k = 0; k < m; k += 1) {
        const a = Math.max(0, k - 1), b = Math.min(m - 1, k + 1);
        let tx = px[b] - px[a], ty = py[b] - py[a];
        const tl = Math.hypot(tx, ty) || 1;
        tx /= tl; ty /= tl;
        let nx = -ty, ny = tx;
        if (ny > 0) { nx = -nx; ny = -ny; }                                // the limb's upper side
        const node = nodes[run[k]];
        const half = node.w * H * 0.5;
        // as deep as the limb can carry, less where it steepens; rounded off at both ends of the stretch
        const u = Math.min(1, Math.min(along[k], total - along[k]) / ends);
        const round = Math.sqrt(Math.max(0, 1 - (1 - u) * (1 - u)));
        const carry = Math.max(0.6 * s, Math.min(2.1 * s, node.w * H * 0.55 + 0.42 * s));
        const lie = 0.42 + 0.58 * smoothstep01(((k === 0 ? flat[run[1]] : flat[run[k]]) - 0.42) / 0.4);
        const uneven = 0.86 + 0.28 * (0.5 * hash(Math.floor(run[k] / 3), 86) + 0.5 * hash(Math.floor(run[k] / 3) + 1, 86));
        const depth = carry * lie * round * uneven * (0.55 + 0.45 * amount);
        foot.push([px[k] + nx * half * 0.72, py[k] + ny * half * 0.72]);
        top.push([px[k] + nx * (half + depth), py[k] + ny * (half + depth)]);
      }
      ctx.beginPath();
      ctx.moveTo(foot[0][0], foot[0][1]);
      for (let k = 1; k < m; k += 1) ctx.lineTo(foot[k][0], foot[k][1]);
      ctx.lineTo(top[m - 1][0], top[m - 1][1]);
      for (let k = m - 2; k >= 1; k -= 1) ctx.quadraticCurveTo(top[k][0], top[k][1], (top[k][0] + top[k - 1][0]) / 2, (top[k][1] + top[k - 1][1]) / 2);
      ctx.lineTo(top[0][0], top[0][1]);
      ctx.closePath();
      ctx.fill();
    }
    // the forks: a small pillow of it lying in the cup between the two limbs that leave (the great fork holds the most)
    ctx.beginPath();
    ctx.ellipse(X(-0.004), Y(-0.238), 0.019 * H, 0.0072 * H, 0, 0, TAU);
    ctx.fill();
    const upLimb = (i, far) => {
      let cur = i, gone = 0;
      while (gone < far) {
        let heir = -1;
        for (const k of kids[cur]) if (heir < 0 || nodes[k].w > nodes[heir].w) heir = k;
        if (heir < 0) break;
        gone += Math.hypot(nodes[heir].x - nodes[cur].x, nodes[heir].y - nodes[cur].y) * H;
        cur = heir;
      }
      return nodes[cur];
    };
    for (let i = 1; i < nodes.length; i += 1) {
      const n = nodes[i];
      if (n.kids < 2 || n.w < 0.017 || n.y > -0.24) continue;
      if (hash(i, 87) > 0.25 + 0.55 * amount) continue;
      const far = Math.max(1.2 * s, Math.min(2.5 * s, n.w * H * 0.95));
      const a = upLimb(kids[i][0], far), b = upLimb(kids[i][1], far);
      const fx = X(n.x), fy = Y(n.y), ax = X(a.x), ay = Y(a.y), bx = X(b.x), by = Y(b.y);
      const mx = (ax + bx) / 2, my = (ay + by) / 2;
      if (my > fy - 0.5 * s || Math.abs(ax - bx) < 0.9 * s) continue;       // not a cup that opens upward
      // a small pillow lying in the cup, a little way up from the fork
      const r = Math.max(0.7 * s, Math.min(1.5 * s, Math.abs(ax - bx) * 0.30));
      ctx.beginPath();
      ctx.ellipse(fx + (mx - fx) * 0.5, fy + (my - fy) * 0.5, r, r * 0.58, 0, 0, TAU);
      ctx.fill();
    }
    out.snow = ctx.canvas;
    // the twigs: a hair of snow along the upper side of the level ones, in broken runs
    const fineCtx = mask();
    fineCtx.lineWidth = Math.max(0.9, 0.46 * s);
    for (let i = 1; i < nodes.length; i += 1) {
      const n = nodes[i];
      if (n.w >= MINW) continue;
      const q = nodes[n.parent];
      const lv = level(i);
      if (lv < 0.55 || hash(Math.floor(i / 5), 88) > 0.10 + 0.22 * amount) continue;
      const lift = Math.max(0.85, n.w * H) * 0.5 + fineCtx.lineWidth * 0.42;
      fineCtx.globalAlpha = 0.55 + 0.45 * smoothstep01((lv - 0.5) / 0.3);
      fineCtx.beginPath();
      fineCtx.moveTo(X(q.x), Y(q.y) - lift);
      fineCtx.lineTo(X(n.x), Y(n.y) - lift);
      fineCtx.stroke();
    }
    fineCtx.globalAlpha = 1;
    out.snowFine = fineCtx.canvas;
  }

  // Frost is a hair of white on the wood's top edge: a thin line along the upper side of each stretch of
  // limb level enough to hold it, broken in runs. (The default day's — its drawing is not to change.)
  const lying = (amount, weight, minW) => {
    const ctx = mask();
    for (let i = 1; i < nodes.length; i += 1) {
      const n = nodes[i];
      if (n.w < minW) continue;
      const q = nodes[n.parent];
      const dx = n.x - q.x, dy = n.y - q.y;
      const len = Math.hypot(dx, dy) || 1;
      const flat = Math.abs(dx) / len;                   // 0 for a limb going straight up
      if (flat < 0.42) continue;
      // it lies in runs: whole stretches of a limb are bare
      let run = i, steps = 0;
      while (steps < 3 && nodes[run].parent > 0 && nodes[nodes[run].parent].kids === 1) { run = nodes[run].parent; steps += 1; }
      if (hash(Math.floor(run / 3), 85) > 0.5 + 0.45 * amount) continue;
      // the limb's upper normal
      let nx = -dy / len, ny = dx / len;
      if (ny > 0) { nx = -nx; ny = -ny; }
      const px = n.w * H;
      const lw = Math.max(0.42 * s, Math.min(0.85 * s, px * 0.34)) * weight * (0.55 + 0.45 * flat);
      const sit = 0.15;
      const lift = px * 0.5 + lw * sit;
      ctx.lineWidth = lw;
      ctx.beginPath();
      ctx.moveTo(X(q.x) + nx * (q.w * H * 0.5 + lw * sit), Y(q.y) + ny * (q.w * H * 0.5 + lw * sit));
      ctx.lineTo(X(n.x) + nx * lift, Y(n.y) + ny * lift);
      ctx.stroke();
    }
    return ctx.canvas;
  };
  if (sea.frost > 0.04) out.frost = lying(sea.frost, 0.7, 0.0105);

  // The last leaves of autumn, clinging at the twig ends.
  const clinging = Math.max(sea.leafFall * (1 - sea.foliage), 0);
  if (clinging > 0.02) {
    const ctx = mask();
    tips.forEach((t, i) => {
      if (hash(i, 81) > clinging * 0.11) return;
      ctx.beginPath();
      ctx.ellipse(X(t.x) + (hash(i, 83) - 0.5) * 2 * s, Y(t.y) + 1.1 * s, 0.85 * s, 1.3 * s, (hash(i, 82) - 0.5) * 1.2, 0, TAU);
      ctx.fill();
    });
    out.lastLeaves = ctx.canvas;
  }
  return out;
}
