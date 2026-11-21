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
// wood, twigs, leaf masses (three depths), blossom, snow, frost, the last leaves.
// In the app these masks ship pre-rendered at three sizes; only their paint changes.

import { rng } from '../../lab/noise.js';
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

/**
 * Cut the tree's masks at a size.
 *   mk(w, h)   a canvas factory
 *   H          the tree's height in device pixels (unit 1 → H)
 *   s          device pixels per point
 *   sea        lab/season.js's answer (foliage, leafHue, leafFall, blossom, snow, frost)
 * → { size, cx, cy, wood, twigs, leafBack, leafMid, leafFront, blossomA, blossomB, snow, frost, lastLeaves, fallen }
 *   every mask `size` square, the foot of the trunk at (cx, cy).
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
  // Not dabs: MASSES. Each limb's lobe carries a handful of gathered clumps of leaf — rounded,
  // with a leaf-scalloped edge — that overlap into one crown with a clear outer shape (the lobes'
  // own, so the silhouette is the bare tree's), in three depths: the shaded masses behind the
  // wood, the body of each clump in front of it, and the tops that catch the light. Between the
  // masses there are a few windows of sky, set where the limbs pass, so the limbs show through.
  const n1 = (x, salt) => { const i = Math.floor(x), f = x - i, u = f * f * (3 - 2 * f); return hash(i, salt) * (1 - u) + hash(i + 1, salt) * u; };
  /** Smooth noise round a closed outline: `period` cells to the turn, so the edge meets itself. */
  const ring = (x, period, salt) => {
    const i = Math.floor(x), f = x - i, u = f * f * (3 - 2 * f);
    const at = (k) => hash(((k % period) + period) % period, salt);
    return at(i) * (1 - u) + at(i + 1) * u;
  };
  /** A gathered mass of leaf, cut by hand: never an ellipse (two or three slow bulges), and its edge
   *  is LEAVES — unequal points, a few standing well out, most barely — not a row of equal scallops. */
  const mass = (ctx, cx, cy, rx, ry, seed) => {
    if (rx < 0.004 || ry < 0.004) return;
    const girth = Math.PI * (rx + ry);
    const tips = Math.max(7, Math.round(girth / 0.034));
    const steps = tips * 8;
    const small = 0.030 / Math.max(0.03, Math.min(rx, ry));
    ctx.beginPath();
    for (let k = 0; k <= steps; k += 1) {
      const t = (k % steps) / steps, a = t * TAU;
      // the leaves are not evenly spaced round the edge
      const tw = t * tips + 0.7 * (ring(t * Math.ceil(tips / 2), Math.ceil(tips / 2), seed + 3) - 0.5);
      const cell = Math.floor(tw), f = tw - cell;
      const amp = 0.2 + 1.5 * Math.pow(hash(((cell % tips) + tips) % tips, seed + 5), 1.6);
      const tip = 1 - Math.pow(Math.abs(2 * f - 1), 1.45);
      const slow = 0.20 * (ring(t * 3, 3, seed + 1) - 0.5) + 0.12 * (ring(t * 7, 7, seed + 2) - 0.5);
      const r = 1 + slow + small * 0.34 * amp * (tip - 0.42);
      const x = X(cx + Math.cos(a) * rx * r), y = Y(cy + Math.sin(a) * ry * r);
      if (k === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
    }
    ctx.closePath();
    ctx.fill();
  };
  /** The masses one lobe carries: [cx, cy, rx, ry, id] — few and large, unequal: two or three round
   *  its rim and one at its heart. The long arm's lobe (the low one on the sunset side) carries only a
   *  small spray at the arm's end: under it the crown is OPEN — a bay of sky where the sun goes
   *  down, so that in leaf, too, the sun is seen through the limbs. */
  const clumpsOf = (lobe, j) => {
    const [cx, cy, rx, ry, weight] = lobe;
    if (j === 4) return [[cx + rx * 0.52, cy - ry * 0.62, rx * 0.5, ry * 0.5, j * 16], [cx + rx * 0.08, cy - ry * 0.98, rx * 0.4, ry * 0.36, j * 16 + 1]];
    const big = rx > 0.16;
    const n = big ? 3 : 2;
    const out = [];
    for (let k = 0; k < n; k += 1) {
      const id = j * 16 + k;
      const a = (k / n) * TAU + (hash(id, 91) - 0.5) * 0.9 + j * 1.3 - Math.PI / 2;
      const d = 0.40 + 0.14 * hash(id, 92);
      const sz = (big ? 0.66 : 0.76) * (0.74 + 0.5 * hash(id, 93));
      out.push([cx + Math.cos(a) * rx * d, cy + Math.sin(a) * ry * d, rx * sz, ry * sz * 1.04, id]);
    }
    if (weight >= 0.9) out.push([cx + (hash(j, 94) - 0.5) * rx * 0.2, cy - ry * 0.05, rx * 0.62, ry * 0.6, j * 16 + 15]);
    return out;
  };
  /** Sky in the crown, where the limbs pass. Never a porthole: three BAYS that run in from the
   *  crown's underside along the leader and the two great limbs (each a few overlapping cuts), and
   *  two small ragged gaps higher up between the lobes. [x, y, rx, ry, group] — groups 3+ open only
   *  as the crown thins. */
  const WINDOWS = [
    [0.020, -0.385, 0.062, 0.050, 0], [0.026, -0.455, 0.040, 0.040, 0], [0.006, -0.515, 0.022, 0.026, 0],
    [-0.175, -0.395, 0.058, 0.046, 1], [-0.228, -0.455, 0.036, 0.036, 1], [-0.262, -0.508, 0.020, 0.024, 1],
    [0.150, -0.415, 0.054, 0.044, 2], [0.205, -0.478, 0.034, 0.034, 2], [0.246, -0.530, 0.018, 0.022, 2],
    [-0.132, -0.704, 0.040, 0.017, 3], [-0.098, -0.682, 0.024, 0.022, 3], [-0.160, -0.722, 0.018, 0.012, 3],
    [0.146, -0.724, 0.036, 0.015, 4], [0.178, -0.704, 0.021, 0.020, 4],
    [-0.035, -0.640, 0.036, 0.016, 5], [-0.008, -0.622, 0.020, 0.018, 5], [0.300, -0.505, 0.034, 0.016, 6], [0.322, -0.488, 0.018, 0.016, 6], [-0.335, -0.535, 0.032, 0.015, 7], [-0.31, -0.52, 0.017, 0.016, 7],
  ];
  /** Cut the sky out of a leaf mask. `bays` scales the three bays, `gaps` the two gaps (0 = closed),
   *  `more` the ones that only open as the crown thins. */
  const punch = (ctx, bays, gaps, more) => {
    ctx.globalCompositeOperation = 'destination-out';
    WINDOWS.forEach(([wx, wy, rx, ry, group], i) => {
      const k = group <= 2 ? bays : group <= 4 ? gaps : more;
      if (k > 0.08) mass(ctx, wx, wy, rx * k, ry * k, 700 + i);
    });
    ctx.globalCompositeOperation = 'source-over';
  };

  // Leaves.
  const foliage = sea.foliage;
  if (foliage > 0.04) {
    const back = mask(), mid = mask(), front = mask();
    const fall = sea.leafFall;                              // autumn: thinning
    const grown = foliage * foliage * (3 - 2 * foliage);    // spring: the clumps are small, then fill
    const size = (0.50 + 0.50 * grown) * (1 - 0.09 * fall) * (1 - 0.3 * (sea.blossom ?? 0));
    tree.lobes.forEach((lobe, j) => {
      const [cx, cy, rx, ry] = lobe;
      // the whole lobe, once the crown is full (autumn opens it up again)
      const whole = smoothstep01((grown - 0.72) / 0.25) * (1 - 0.30 * fall);
      if (whole > 0.02 && j < 4) mass(back, cx, cy + 0.012, rx * 0.95 * (0.7 + 0.3 * whole), ry * 0.95 * (0.7 + 0.3 * whole), 300 + j);
      for (const [x, y, crx, cry, id] of clumpsOf(lobe, j)) {
        if (hash(id, 95) < 0.14 * fall) continue;            // a clump lost to the wind
        mass(back, x, y + 0.012, crx * size * 1.05, cry * size * 1.05, 310 + id);
        if (hash(id, 96) > 0.14 + 0.2 * fall) mass(mid, x - 0.008, y - 0.016, crx * size * 0.80, cry * size * 0.76, 400 + id);
        if (hash(id, 97) > 0.36 + 0.25 * fall) mass(front, x - 0.006 + (hash(id, 98) - 0.5) * crx * 0.4, y - cry * size * 0.34, crx * size * 0.46, cry * size * 0.40, 500 + id);
      }
    });
    // (the bays are cut wider in the nearer layers, so the crown's shaded inside shows round them; the
    // small gaps are cut the same in all three — a ring of shade round a small hole would be an eye)
    const open = 1 - grown;
    const gaps = 1 + 0.5 * open + 0.35 * fall, more = 1.05 * fall + 1.1 * open - 0.05;
    punch(back, 0.86 + 0.5 * open + 0.36 * fall, gaps, more);
    punch(mid, 1.12 + 0.5 * open + 0.4 * fall, gaps * 1.06, more * 1.06);
    punch(front, 1.3 + 0.5 * open + 0.4 * fall, gaps * 1.12, more * 1.12);
    out.leafBack = back.canvas; out.leafMid = mid.canvas; out.leafFront = front.canvas;
  }

  // Blossom: the same gathered clumps, smaller and airier — a cloud of it on each bough, in two
  // tones, with the wood and the sky showing between; a frill of single flowers at the twig ends.
  if (sea.blossom > 0.04) {
    const a = mask(), b = mask();
    const full = sea.blossom;
    tree.lobes.forEach((lobe, j) => {
      for (const [x, y, crx, cry, id] of clumpsOf(lobe, j)) {
        if (hash(id, 71) > 0.30 + 0.62 * full) continue;
        const k = 0.42 + 0.17 * full;
        mass(b, x + 0.005, y + 0.014, crx * k * 1.06, cry * k * 1.0, 600 + id);
        mass(a, x - 0.005, y - 0.008, crx * k * 0.82, cry * k * 0.76, 640 + id);
        // two or three smaller sprays beside it, so its edge is not one curve
        for (let q = 0; q < 3; q += 1) {
          const ang = hash(id * 4 + q, 72) * TAU, dd = 0.95 + 0.4 * hash(id * 4 + q, 73);
          const sx = x + Math.cos(ang) * crx * k * dd, sy = y + Math.sin(ang) * cry * k * dd;
          if (hash(id * 4 + q, 74) > full) continue;
          mass(q === 0 ? b : a, sx, sy, crx * k * 0.34, cry * k * 0.34, 660 + id * 4 + q);
        }
      }
    });
    punch(b, 1.05, 0, 0); punch(a, 1.3, 0, 0);
    const tipNodes = nodes.filter((n) => n.order <= 1 && n.w < 0.016);
    tipNodes.forEach((n, i) => {
      if (hash(i, 75) > 0.14 * full) return;
      const ctx = hash(i, 76) < 0.6 ? a : b;
      ctx.beginPath();
      ctx.arc(X(n.x + (hash(i, 77) - 0.5) * 0.03), Y(n.y + (hash(i, 78) - 0.5) * 0.03), (0.006 + 0.005 * hash(i, 79)) * H, 0, TAU);
      ctx.fill();
    });
    out.blossomA = a.canvas; out.blossomB = b.canvas;
  }

  // Snow lies as a CAP along the upper side of the limbs that are level enough to hold it: a clear
  // pale ridge a point and a half to two points deep on the great limbs (it has to be read from the
  // strip, at phone size), thinner on the lesser ones, broken where it has slid off, round at its
  // ends, and a small drift in every fork. Frost is a hair of the same, on the wood's top edge.
  const lying = (amount, weight, minW, cap) => {
    const ctx = mask();
    for (let i = 1; i < nodes.length; i += 1) {
      const n = nodes[i];
      if (n.w < minW) continue;
      const q = nodes[n.parent];
      const dx = n.x - q.x, dy = n.y - q.y;
      const len = Math.hypot(dx, dy) || 1;
      let flat = Math.abs(dx) / len;                     // 0 for a limb going straight up
      if (cap) {
        // …judged over a longer stretch of the limb, so a cap runs on unbroken where the limb only wavers
        let a = n.parent, hops = 1;
        while (hops < 5 && nodes[a].parent >= 0) { a = nodes[a].parent; hops += 1; }
        const ex = n.x - nodes[a].x, ey = n.y - nodes[a].y;
        flat = Math.min(1, 0.25 * flat + 0.75 * (Math.abs(ex) / (Math.hypot(ex, ey) || 1)));
      }
      if (flat < 0.42) continue;
      // snow slides off in runs: whole stretches of a limb are bare
      let run = i, steps = 0;
      while (steps < 3 && nodes[run].parent > 0 && nodes[nodes[run].parent].kids === 1) { run = nodes[run].parent; steps += 1; }
      if (hash(Math.floor(run / 3), 85) > 0.5 + 0.45 * amount) continue;
      // the limb's upper normal
      let nx = -dy / len, ny = dx / len;
      if (ny > 0) { nx = -nx; ny = -ny; }
      const px = n.w * H;
      let lw, sit;
      if (cap) {
        // as deep as the limb can carry: 1.5–2 pt on the great limbs, about a point on the boughs
        const depth = Math.max(0.62 * s, Math.min(2.0 * s, px * 0.5 + 0.35 * s));
        lw = depth * weight * (0.45 + 0.55 * smoothstep01((flat - 0.42) / 0.4));
        sit = 0.30;                                       // it sits ON the limb: most of it above the wood
      } else {
        lw = Math.max(0.42 * s, Math.min(0.85 * s, px * 0.34)) * weight * (0.55 + 0.45 * flat);
        sit = 0.15;
      }
      const lift = px * 0.5 + lw * sit;
      ctx.lineWidth = lw;
      ctx.beginPath();
      ctx.moveTo(X(q.x) + nx * (q.w * H * 0.5 + lw * sit), Y(q.y) + ny * (q.w * H * 0.5 + lw * sit));
      ctx.lineTo(X(n.x) + nx * lift, Y(n.y) + ny * lift);
      ctx.stroke();
    }
    return ctx.canvas;
  };
  if (sea.snow > 0.04) {
    out.snow = lying(sea.snow, 1, 0.0085, true);
    // every fork holds a little: a small drift lying in the crotch (the great fork holds the most)
    const ctx = out.snow.getContext('2d');
    ctx.fillStyle = '#fff';
    ctx.beginPath();
    ctx.ellipse(X(-0.004), Y(-0.236), 0.020 * H, 0.0085 * H, 0, 0, TAU);
    ctx.fill();
    for (let i = 1; i < nodes.length; i += 1) {
      const n = nodes[i];
      if (n.kids < 2 || n.w < 0.019 || n.y > -0.24) continue;
      if (hash(i, 87) > 0.25 + 0.55 * sea.snow) continue;
      const r = Math.max(0.8 * s, Math.min(1.7 * s, n.w * H * 0.5));
      ctx.beginPath();
      ctx.ellipse(X(n.x), Y(n.y) - n.w * H * 0.42 - r * 0.2, r, r * 0.52, 0, 0, TAU);
      ctx.fill();
    }
  }
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
