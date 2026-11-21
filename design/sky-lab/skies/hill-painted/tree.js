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

  // Leaves: dabs gathered along the twigs — so the crown keeps the limbs'
  // own shape, with sky between the lobes — in three depths.
  const foliage = sea.foliage;
  if (foliage > 0.04) {
    const back = mask(), mid = mask(), front = mask();
    const thin = 1 - 0.6 * sea.leafFall;                   // autumn: thinning
    // how deep inside its lobe a twig is (0 at the rim … 1 at the heart): leaves crowd the rims,
    // so each limb's lobe keeps its own outline and there is sky between them
    const depthIn = (x, y) => {
      let best = 0;
      for (const [cx, cy, rx, ry] of tree.lobes.slice(0, 5)) {
        const u = (x - cx) / rx, v = (y - cy) / ry;
        best = Math.max(best, 1 - Math.sqrt(u * u + v * v));
      }
      return best;
    };
    const twigNodes = nodes.filter((n) => n.order <= 12 && n.w < 0.022);
    twigNodes.forEach((n, i) => {
      const inLobe = depthIn(n.x, n.y);
      if (inLobe < -0.12) return;                          // the heart's own twigs carry few leaves
      const keep = foliage * thin * (n.order <= 4 ? 1 : 0.9 - 0.04 * n.order) * (inLobe < 0 ? 0.45 : 1);
      for (let k = 0; k < 5; k += 1) {
        const id = i * 5 + k;
        if (hash(id, 61) > keep) continue;
        const roll = hash(id, 65);
        const layer = roll < 0.40 ? 0 : roll < 0.76 ? 1 : 2;
        const a = hash(id, 62) * TAU, d = hash(id, 63) * (layer === 0 ? 0.036 : 0.028);
        const r = ([0.0135, 0.0105, 0.0075][layer] + [0.013, 0.010, 0.008][layer] * hash(id, 64)) * H * (0.7 + 0.3 * foliage);
        // leaves hang: the masses sit a little under their twigs
        const x = X(n.x + Math.cos(a) * d), y = Y(n.y + Math.sin(a) * d * 0.8 + (layer === 0 ? 0.010 : 0.002));
        const ctx = [back, mid, front][layer];
        ctx.beginPath();
        ctx.ellipse(x, y, r * 1.18, r * 0.8, (hash(id, 66) - 0.5) * 1.6, 0, TAU);
        ctx.fill();
      }
    });
    out.leafBack = back.canvas; out.leafMid = mid.canvas; out.leafFront = front.canvas;
  }

  // Blossom: small dabs at the twig ends, two tones; the wood still shows.
  if (sea.blossom > 0.04) {
    const a = mask(), b = mask();
    const twigNodes = nodes.filter((n) => n.order <= 7 && n.w < 0.016);
    twigNodes.forEach((n, i) => {
      const dabs = n.order <= 1 ? 3 : 1;
      for (let k = 0; k < dabs; k += 1) {
        const id = i * 5 + k;
        if (hash(id, 72) > sea.blossom * (n.order <= 1 ? 0.8 : 0.34)) continue;
        const ctx = hash(id, 73) < 0.6 ? a : b;
        const r = (0.0075 + 0.0095 * hash(id, 74)) * H;
        ctx.beginPath();
        ctx.arc(X(n.x + (hash(id, 76) - 0.5) * 0.05), Y(n.y + (hash(id, 77) - 0.5) * 0.045), r, 0, TAU);
        ctx.fill();
      }
    });
    out.blossomA = a.canvas; out.blossomB = b.canvas;
  }

  // Snow lying along the upper side of the limbs; frost, a thinner line of the same.
  const lying = (amount, thickness, minW) => {
    const ctx = mask();
    for (let i = 1; i < nodes.length; i += 1) {
      const n = nodes[i];
      if (n.w < minW) continue;
      const q = nodes[n.parent];
      const len = Math.hypot(n.x - q.x, n.y - q.y) || 1;
      const flat = Math.abs(n.x - q.x) / len;            // 0 for a limb going straight up
      if (flat < 0.30) continue;
      const lift = n.w * H * 0.5 + thickness * s * 0.22;
      ctx.lineWidth = Math.max(0.5 * s, thickness * s * (0.4 + 0.6 * flat) * amount);
      ctx.beginPath();
      ctx.moveTo(X(q.x), Y(q.y) - lift);
      ctx.lineTo(X(n.x), Y(n.y) - lift);
      ctx.stroke();
    }
    return ctx.canvas;
  };
  if (sea.snow > 0.04) out.snow = lying(sea.snow, 1.25, 0.0075);
  if (sea.frost > 0.04) out.frost = lying(sea.frost, 0.55, 0.0095);

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
