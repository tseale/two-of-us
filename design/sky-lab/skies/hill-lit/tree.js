// The tree on the knoll — one grown, broad-crowned tree, the same every day.
//
// It is grown once from a fixed seed: a hand-set scaffold (a short stout trunk
// that divides into five limbs, each with its own elbow, and their second
// limbs), then twigs that reach for the open places in a broad dome (space
// colonisation), and every limb as thick as the twigs it carries (da Vinci's
// rule). Only its dress changes: bare with frost and a few last leaves, snow
// lying on the limbs, blossom, a full crown in masses that follow the limbs,
// amber and thinning.
//
// Unit space: the trunk's foot at (0, 0), up is −y, the crown's top at −1,
// the crown about 1.07 wide. In the app this file is a build script: it would
// write the masks (wood, rim, three leaf tones, blossom, snow, frost, last
// leaves) as images, and the sky tints them.

import { rng } from '../../lab/noise.js';
import { hash } from '../../lab/nights.js';

const TAU = Math.PI * 2;
const STEP = 0.0135;

/** A Catmull-Rom path through `pts`, sampled about every `step`. */
function strand(pts, step) {
  const out = [];
  const P = (i) => pts[Math.max(0, Math.min(pts.length - 1, i))];
  for (let i = 0; i < pts.length - 1; i += 1) {
    const p0 = P(i - 1), p1 = P(i), p2 = P(i + 1), p3 = P(i + 2);
    const len = Math.hypot(p2[0] - p1[0], p2[1] - p1[1]);
    const n = Math.max(1, Math.round(len / step));
    for (let k = i === 0 ? 0 : 1; k <= n; k += 1) {
      const t = k / n, t2 = t * t, t3 = t2 * t;
      const f = (a, b, c, d) => 0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3);
      out.push([f(p0[0], p1[0], p2[0], p3[0]), f(p0[1], p1[1], p2[1], p3[1])]);
    }
  }
  return out;
}

// The scaffold. Each limb leaves the nearest node already grown.
const TRUNK = [[0, 0], [0.006, -0.08], [-0.008, -0.165], [0.004, -0.245]];
const LIMBS = [
  // the low left limb: long, nearly level, an elbow up at the end
  [[-0.004, -0.2], [-0.085, -0.262], [-0.2, -0.288], [-0.315, -0.338], [-0.42, -0.372], [-0.495, -0.44]],
  // upper left
  [[0, -0.245], [-0.062, -0.36], [-0.158, -0.468], [-0.232, -0.6], [-0.292, -0.712]],
  // the leader
  [[0.004, -0.245], [0.034, -0.39], [-0.012, -0.548], [0.04, -0.7], [0.018, -0.84], [0.046, -0.94]],
  // upper right
  [[0.006, -0.24], [0.098, -0.35], [0.196, -0.452], [0.292, -0.585], [0.352, -0.7]],
  // the low right limb: the longest, reaching toward where the sun sets
  [[0.006, -0.192], [0.108, -0.248], [0.236, -0.262], [0.352, -0.318], [0.462, -0.35], [0.548, -0.42]],
  // their second limbs
  [[-0.2, -0.288], [-0.262, -0.4], [-0.352, -0.498], [-0.412, -0.588]],
  [[-0.158, -0.468], [-0.118, -0.61], [-0.142, -0.755], [-0.172, -0.862]],
  [[0.196, -0.452], [0.184, -0.6], [0.222, -0.74], [0.198, -0.855]],
  [[0.236, -0.262], [0.322, -0.402], [0.424, -0.5], [0.468, -0.59]],
  [[-0.012, -0.548], [-0.066, -0.665], [-0.056, -0.8], [-0.082, -0.915]],
  // a small low branch on the trunk's left, the kind a real tree keeps
  [[-0.006, -0.15], [-0.07, -0.178], [-0.13, -0.218], [-0.165, -0.262]],
];

const CROWN = { cx: 0.02, cy: -0.6 };
/** 0 at the crown's middle, 1 on its edge: a broad lobed dome whose foot rises toward the sides. */
function crownQ(x, y) {
  const dx = x - CROWN.cx, dy = y - CROWN.cy;
  const th = Math.atan2(dy, dx);
  const lobes = 1 + 0.06 * Math.cos(3 * th + 4.35) + 0.04 * Math.cos(5 * th + 1.7);
  const rx = dx > 0 ? 0.555 : 0.525, ry = dy < 0 ? 0.375 : 0.37;
  const q = Math.hypot(dx / rx, dy / ry) / lobes;
  const foot = -0.215 - 0.15 * Math.pow(Math.min(1, Math.abs(dx) / 0.5), 1.5);
  return y > foot ? 2 : q;
}

function grow() {
  const rnd = rng(19750613);
  let nodes = [];
  const add = (x, y, parent, limb, scaffold) => {
    nodes.push({ x, y, parent, limb, scaffold, bud: true, kids: 0, tips: 0, w: 0 });
    if (parent >= 0) nodes[parent].kids += 1;
    return nodes.length - 1;
  };
  const nearest = (x, y) => {
    let best = 0, bd = Infinity;
    for (let i = 0; i < nodes.length; i += 1) {
      const d = (nodes[i].x - x) ** 2 + (nodes[i].y - y) ** 2;
      if (d < bd) { bd = d; best = i; }
    }
    return best;
  };
  let last = -1;
  for (const [x, y] of strand(TRUNK, STEP)) { last = add(x, y, last, 0, 1); nodes[last].bud = false; }
  LIMBS.forEach((pts, index) => {
    const path = strand(pts, STEP);
    let at = nearest(path[0][0], path[0][1]);
    for (let k = 1; k < path.length; k += 1) {
      // a little tremor in the hand, more toward the tip
      const f = k / (path.length - 1);
      const j = 0.004 * f;
      at = add(path[k][0] + (rnd() - 0.5) * j, path[k][1] + (rnd() - 0.5) * j, at, index + 1, 1 - 0.75 * f);
      // a limb buds here and there, not along its whole length like a comb — and freely at its end
      nodes[at].bud = f > 0.86 || (f > 0.22 && k % 5 === (index % 5));
    }
  });

  // Where twigs want to be: all through the dome, most of all in its shell.
  const points = [];
  let guard = 0;
  while (points.length < 1250 && guard < 80000) {
    guard += 1;
    const x = -0.56 + rnd() * 1.16, y = -1.02 + rnd() * 0.84;
    const q = crownQ(x, y);
    if (q > 1) continue;
    if (rnd() > 0.1 + 0.9 * Math.pow(q, 2.2)) continue;
    points.push({ x, y, alive: true, near: -1, d: Infinity });
  }
  const REACH = 0.22, KILL = 0.017;
  let fresh = 0;
  for (let round = 0; round < 400; round += 1) {
    for (const p of points) {
      if (!p.alive) continue;
      for (let i = fresh; i < nodes.length; i += 1) {
        if (!nodes[i].bud) continue;
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
      const len = Math.hypot(e.x, e.y) || 1;
      // a twig keeps something of the way it was already going
      let dx = e.x / len, dy = e.y / len;
      if (n.parent >= 0 && !n.scaffold) {
        const q = nodes[n.parent];
        const pl = Math.hypot(n.x - q.x, n.y - q.y) || 1;
        dx = dx * 0.72 + ((n.x - q.x) / pl) * 0.28;
        dy = dy * 0.72 + ((n.y - q.y) / pl) * 0.28;
        const dl = Math.hypot(dx, dy) || 1;
        dx /= dl; dy /= dl;
      }
      const nx = n.x + dx * STEP + (rnd() - 0.5) * STEP * 0.4;
      const ny = n.y + dy * STEP - 0.0012 + (rnd() - 0.5) * STEP * 0.4;
      let crowded = false;
      for (let k = nodes.length - 1; k >= 0; k -= 1) {
        if (Math.abs(nodes[k].x - nx) < STEP * 0.7 && Math.hypot(nodes[k].x - nx, nodes[k].y - ny) < STEP * 0.7) { crowded = true; break; }
      }
      if (crowded) continue;
      add(nx, ny, i, n.limb, 0);
      grew = true;
    }
    if (!grew) break;
  }

  // Bristles off: a spur of one or two joints on a thick limb is not a branch.
  const count = () => {
    for (const n of nodes) { n.tips = 0; n.kids = 0; }
    for (const n of nodes) if (n.parent >= 0) nodes[n.parent].kids += 1;
    for (let i = nodes.length - 1; i >= 0; i -= 1) {
      const n = nodes[i];
      if (n.kids === 0) n.tips = 1;
      if (n.parent >= 0) nodes[n.parent].tips += n.tips;
    }
  };
  for (let pass = 0; pass < 2; pass += 1) {
    count();
    const drop = new Set();
    nodes.forEach((n, i) => {
      if (n.kids !== 0 || n.scaffold) return;
      const chain = [i];
      let at = n.parent;
      while (at >= 0 && nodes[at].kids === 1 && !nodes[at].scaffold) { chain.push(at); at = nodes[at].parent; }
      if (at >= 0 && chain.length < 4 && (nodes[at].scaffold || nodes[at].tips > 7)) for (const k of chain) drop.add(k);
    });
    if (!drop.size) break;
    const map = new Map();
    const keptNodes = [];
    nodes.forEach((n, i) => { if (!drop.has(i)) { map.set(i, keptNodes.length); keptNodes.push(n); } });
    for (const n of keptNodes) n.parent = n.parent < 0 ? -1 : map.get(n.parent);
    nodes = keptNodes;
  }
  count();

  // The finest twigs: every shoot ends in a small fork.
  const ends = nodes.map((n, i) => (n.kids === 0 ? i : -1)).filter((i) => i >= 0);
  for (const i of ends) {
    const n = nodes[i];
    const q = nodes[n.parent];
    const base = Math.atan2(n.y - q.y, n.x - q.x);
    const forks = n.scaffold ? 3 : 2;
    for (let f = 0; f < forks; f += 1) {
      let a = base + (f === 0 ? -1 : f === 1 ? 1 : 0.15) * (0.38 + 0.4 * rnd());
      let at = i, x = n.x, y = n.y;
      const joints = 2 + Math.floor(rnd() * 3);
      for (let k = 0; k < joints; k += 1) {
        a += (rnd() - 0.5) * 0.5 - 0.06 * Math.cos(a);          // and turns a little up toward the light
        x += Math.cos(a) * STEP * 0.92; y += Math.sin(a) * STEP * 0.92;
        if (crownQ(x, y) > 1.12) break;
        at = add(x, y, at, n.limb, 0);
      }
    }
  }
  count();

  // Every limb as thick as what it carries: cross-sections add.
  const foot = Math.sqrt(nodes[0].tips);
  for (const n of nodes) {
    n.w = 0.094 * Math.sqrt(n.tips) / foot;
    if (n.scaffold) n.w = Math.max(n.w, 0.0055 + 0.02 * n.scaffold * (n.limb === 0 ? 4 : 1));
    n.w = Math.max(n.w, 0.003);
  }
  // the bole never thinner than the limbs it carries
  for (const n of nodes) if (n.limb === 0) n.w = Math.max(n.w, 0.072);

  // Leaf masses: the tips gathered round the outer half of each limb.
  const seeds = [];
  LIMBS.forEach((pts, index) => {
    const a = pts[pts.length - 1], b = pts[Math.max(1, pts.length - 3)];
    seeds.push({ x: a[0], y: a[1], limb: index + 1 }, { x: (a[0] + b[0]) / 2, y: (a[1] + b[1]) / 2 - 0.02, limb: index + 1 });
  });
  const tips = [];
  nodes.forEach((n, index) => {
    n.index = index;
    const fine = n.w < 0.0058;
    if (!(n.kids === 0 || (fine && hash(index, 11) < 0.5))) return;
    let best = 0, bd = Infinity;
    seeds.forEach((s, k) => { const d = (s.x - n.x) ** 2 + (s.y - n.y) ** 2; if (d < bd) { bd = d; best = k; } });
    tips.push({ x: n.x, y: n.y, clump: best, index, end: n.kids === 0 });
  });
  const clumps = seeds.map(() => ({ x: 0, y: 0, n: 0, r: 0 }));
  for (const t of tips) { const c = clumps[t.clump]; c.x += t.x; c.y += t.y; c.n += 1; }
  for (const c of clumps) if (c.n) { c.x /= c.n; c.y /= c.n; }
  for (const t of tips) { const c = clumps[t.clump]; c.r += Math.hypot(t.x - c.x, t.y - c.y); }
  for (const c of clumps) c.r = c.n ? Math.max(0.05, (c.r / c.n) * 1.5) : 0.1;
  return { nodes, tips, clumps };
}

let grown = null;
export function tree() {
  if (!grown) grown = grow();
  return grown;
}

/** The crown's reach at unit height `v` above the foot (0 … 1): half-widths to the left and right. */
export function crownSpan(v) {
  const y = -v;
  if (y > -0.2 || y < -1.01) return null;
  let left = 0, right = 0;
  for (let x = 0; x <= 0.62; x += 0.01) {
    if (crownQ(CROWN.cx + x, y) <= 1) right = x + CROWN.cx;
    if (crownQ(CROWN.cx - x, y) <= 1) left = x - CROWN.cx;
  }
  return { left, right };
}

/**
 * Paints the tree into a canvas of its own.
 *   doc      the document (for createElement)
 *   H        the tree's height in device pixels (foot to crown top)
 *   px       one point in device pixels (the dpr)
 *   sea      lab/season.js's answer for the day
 *   ink      colours, CSS strings: wood, woodLit, leafShade, leaf, leafLit, blossom,
 *            blossomShade, snow, snowShade, frost, lastLeaf
 *   light    { x, y } a unit vector toward the light on the page (y down), and
 *            { amt } 0–1 how much of it there is; { top } 0–1 how much comes from the sky above
 *   glare    null | { x, y, r, amt, colour: [r, g, b] }: the sun's disc behind it, in device
 *            pixels from the foot — the twigs that cross it thin and take its colour
 * → { canvas, ox, oy }  (the foot is at (ox, oy) in the canvas)
 */
export function paintTree(doc, { H, px, sea, ink, light, glare }) {
  const T = tree();
  const W = Math.ceil(H * 1.44), HH = Math.ceil(H * 1.34);
  const ox = Math.round(W * 0.485), oy = Math.round(H * 1.22);
  const canvas = doc.createElement('canvas');
  canvas.width = W; canvas.height = HH;
  const ctx = canvas.getContext('2d');
  ctx.lineCap = 'round'; ctx.lineJoin = 'round';
  const X = (u) => ox + u * H, Y = (v) => oy + v * H;
  const { nodes, tips, clumps } = T;
  const lx = light.x, ly = light.y, amt = Math.max(0, Math.min(1, light.amt));
  const top = light.top ?? 0.3;

  // ── leaves: three tones, darkest first, each mass lit on its own ──
  const foliage = sea.foliage;
  const kept = (t, salt) => hash(t.index, salt) < Math.min(1, foliage * (1.06 - 0.5 * sea.leafFall) + 0.02);
  const toneOf = (t) => {
    const c = clumps[t.clump];
    let nx = (t.x - c.x) / c.r * 0.75 + (t.x - CROWN.cx) / 0.55 * 0.55;
    let ny = (t.y - c.y) / c.r * 0.75 + (t.y - CROWN.cy) / 0.4 * 0.55;
    const len = Math.hypot(nx, ny) || 1;
    nx /= len; ny /= len;
    const grip = Math.min(1, len / 0.9);
    return 0.5 + 0.5 * grip * (amt * (nx * lx + ny * ly) + top * -ny) / Math.max(0.35, amt + top);
  };
  const dab = (t, r, squash, salt) => {
    const a = hash(t.index, salt) * TAU;
    const rr = r * (0.72 + 0.56 * hash(t.index, salt + 1));
    ctx.beginPath();
    ctx.ellipse(X(t.x) + Math.cos(a) * rr * 0.3, Y(t.y) + Math.sin(a) * rr * 0.3, rr, rr * squash, a, 0, TAU);
    ctx.fill();
  };
  const leaves = [];
  if (foliage > 0.03) {
    for (const t of tips) {
      if (!kept(t, 21)) continue;
      const tone = toneOf(t);
      leaves.push({ t, tone, dx: 0, dy: 0, salt: 0 });
      // two more beside it, so a mass is many leaves and not a few discs
      for (let k = 1; k <= 2; k += 1) {
        const a = hash(t.index, 70 + k) * TAU, d = H * 0.03 * (0.5 + hash(t.index, 80 + k));
        leaves.push({ t, tone: tone + (hash(t.index, 90 + k) - 0.5) * 0.14, dx: Math.cos(a) * d, dy: Math.sin(a) * d * 0.8, salt: k * 7 });
      }
    }
  }
  const leafR = H * (0.019 + 0.011 * Math.min(1, foliage * 1.2));
  const leafDab = (l, r, squash, salt) => {
    const a = hash(l.t.index, salt + l.salt) * TAU;
    const rr = r * (0.7 + 0.6 * hash(l.t.index, salt + l.salt + 1));
    ctx.beginPath();
    ctx.ellipse(X(l.t.x) + l.dx, Y(l.t.y) + l.dy, rr, rr * squash, a, 0, TAU);
    ctx.fill();
  };
  if (leaves.length) {
    // the mass itself, behind the limbs: its shadow side in shade, the rest in the leaf's own colour
    ctx.fillStyle = ink.leafShade;
    for (const l of leaves) leafDab(l, leafR * 1.3, 0.86, 31);
  }

  // ── wood ──
  const stroke = (colour, dx, dy, minW, scale = 1) => {
    ctx.strokeStyle = colour;
    // by thickness, thick first, so the paths batch
    const buckets = new Map();
    for (const n of nodes) {
      if (n.parent < 0) continue;
      const w = n.w * H * scale;
      if (w < minW) continue;
      const key = w < 1 ? Math.round(w * 8) / 8 : w < 3 ? Math.round(w * 3) / 3 : Math.round(w);
      let list = buckets.get(key);
      if (!list) { list = []; buckets.set(key, list); }
      list.push(n);
    }
    for (const [w, list] of [...buckets].sort((a, b) => b[0] - a[0])) {
      // a twig thinner than a pixel is a fainter pixel, not a thinner line
      ctx.lineWidth = Math.max(0.95, w);
      ctx.globalAlpha = w >= 0.95 ? 1 : Math.max(0.3, w / 0.95);
      ctx.beginPath();
      for (const n of list) {
        const q = nodes[n.parent];
        ctx.moveTo(X(q.x) + dx, Y(q.y) + dy);
        ctx.lineTo(X(n.x) + dx, Y(n.y) + dy);
      }
      ctx.stroke();
    }
    ctx.globalAlpha = 1;
  };
  const flare = (colour, dx, dy) => {
    const n = nodes[5];
    ctx.fillStyle = colour;
    ctx.beginPath();
    ctx.moveTo(X(-0.082) + dx, Y(0.012) + dy);
    ctx.quadraticCurveTo(X(-0.044) + dx, Y(-0.012) + dy, X(n.x - n.w / 2) + dx, Y(n.y) + dy);
    ctx.lineTo(X(n.x + n.w / 2) + dx, Y(n.y) + dy);
    ctx.quadraticCurveTo(X(0.05) + dx, Y(-0.012) + dy, X(0.092) + dx, Y(0.012) + dy);
    ctx.closePath();
    ctx.fill();
  };
  if (amt > 0.04) {
    // the side that faces the light: the same limbs, slid a hair toward it, under the wood
    const reach = Math.min(1.1 * px, H * 0.014);
    ctx.globalAlpha = 1;
    stroke(ink.woodLit, lx * reach, ly * reach, 1.5);
    flare(ink.woodLit, lx * reach, ly * reach * 0.4);
  }
  stroke(ink.wood, 0, 0, 0);
  flare(ink.wood, 0, 0);

  // ── frost, or snow lying along the upper side of the limbs ──
  const lying = (colour, amount, thick, minW, salt, gate) => {
    ctx.strokeStyle = colour;
    for (const n of nodes) {
      if (n.parent < 0 || n.w < minW) continue;
      const q = nodes[n.parent];
      const len = Math.hypot(n.x - q.x, n.y - q.y) || 1;
      const flat = Math.abs(n.x - q.x) / len;
      if (flat < 0.3 || hash(n.index, salt) > amount * gate) continue;
      const lift = n.w * H * 0.5 + thick * px * 0.28;
      ctx.lineWidth = Math.max(0.8, thick * px * (0.4 + 0.6 * flat) * (0.6 + 0.4 * amount));
      ctx.beginPath();
      ctx.moveTo(X(q.x), Y(q.y) - lift);
      ctx.lineTo(X(n.x), Y(n.y) - lift);
      ctx.stroke();
    }
  };
  if (sea.snow > 0.04) { lying(ink.snow, sea.snow, 1.15, 0.0085, 41, 4); ctx.globalAlpha = 0.85; lying(ink.snow, sea.snow, 0.6, 0.0042, 43, 0.55); ctx.globalAlpha = 1; }
  else if (sea.frost > 0.04) { ctx.globalAlpha = 0.6; lying(ink.frost, sea.frost, 0.5, 0.0075, 42, 0.8); ctx.globalAlpha = 1; }

  // ── leaves in front: the body of each mass, then the side that has the light ──
  if (leaves.length) {
    leaves.sort((p, q) => p.tone - q.tone);
    ctx.fillStyle = ink.leaf;
    for (const l of leaves) if (l.tone > 0.3 && hash(l.t.index, 33 + l.salt) < 0.92) leafDab(l, leafR * 1.05, 0.82, 35);
    ctx.fillStyle = ink.leafLit;
    for (const l of leaves) if (l.tone > 0.54 && hash(l.t.index, 37 + l.salt) < 0.3 + 2.6 * (l.tone - 0.54)) leafDab(l, leafR * 0.74, 0.78, 39);
  }

  // ── blossom: small dabs at the twig ends, two tones ──
  if (sea.blossom > 0.04) {
    const r = H * 0.019;
    for (const pass of [0, 1]) {
      ctx.fillStyle = pass === 0 ? ink.blossomShade : ink.blossom;
      for (const t of tips) {
        if (hash(t.index, 51) > sea.blossom * (t.end ? 0.95 : 0.6)) continue;
        const tone = toneOf(t);
        if (pass === 1 && tone < 0.42 - 0.3 * hash(t.index, 53)) continue;
        dab(t, r * (pass === 0 ? 1.25 : 0.95), 0.85, 55 + pass);
      }
    }
  }

  // ── the last leaves of autumn, clinging ──
  const clinging = sea.leafFall * (1 - foliage);
  if (clinging > 0.02) {
    ctx.fillStyle = ink.lastLeaf;
    for (const t of tips) {
      if (!t.end || hash(t.index, 61) > clinging * 0.2) continue;
      ctx.beginPath();
      ctx.ellipse(X(t.x) + (hash(t.index, 63) - 0.5) * 2 * px, Y(t.y) + 0.9 * px, 0.62 * px, 1.05 * px, (hash(t.index, 62) - 0.5) * 1.6, 0, TAU);
      ctx.fill();
    }
  }

  // ── against the sun: what crosses the disc thins into its light and takes its colour ──
  if (glare && glare.amt > 0.02) {
    const gx = ox + glare.x, gy = oy + glare.y;
    ctx.globalCompositeOperation = 'source-atop';
    const warm = ctx.createRadialGradient(gx, gy, 0, gx, gy, glare.r * 4.2);
    const c = glare.colour;
    warm.addColorStop(0, `rgba(${c[0]},${c[1]},${c[2]},${(glare.warm ?? 0.8) * glare.amt})`);
    warm.addColorStop(0.3, `rgba(${c[0]},${c[1]},${c[2]},${(glare.warm ?? 0.8) * 0.55 * glare.amt})`);
    warm.addColorStop(1, `rgba(${c[0]},${c[1]},${c[2]},0)`);
    ctx.fillStyle = warm;
    ctx.fillRect(0, 0, W, HH);
    ctx.globalCompositeOperation = 'destination-out';
    const eat = ctx.createRadialGradient(gx, gy, 0, gx, gy, glare.r * 2.1);
    eat.addColorStop(0, `rgba(0,0,0,${(glare.eat ?? 0.3) * glare.amt})`);
    eat.addColorStop(0.5, `rgba(0,0,0,${(glare.eat ?? 0.3) * 0.8 * glare.amt})`);
    eat.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = eat;
    ctx.fillRect(0, 0, W, HH);
    ctx.globalCompositeOperation = 'source-over';
  }
  return { canvas, ox, oy };
}
