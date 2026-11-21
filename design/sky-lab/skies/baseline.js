// Today's sky — `TwoOfUs/DesignSystem/SkyBackground.swift`, ported layer for
// layer. This is the "before" in every comparison, so nothing here is
// designed: every stop, alpha, size and blur is the Swift's, in the Swift's
// order. Colours and geometry come from `env.palette` (lab/palette.js, the
// port of `enum SkyPalette`); only the DRAWING lives here.
//
//   SkyBackground   →  a `view` (see `layout`): where one sky sits, whether it
//                      draws its orb, the sky it runs on from (`companion`),
//                      and its leading feather
//   SkyScene.body   →  `paintBack` (sky gradient, warm pool, moon glow, sun
//                      bloom, sun disc, clouds), `paintStars`, `paintFront`
//                      (moon disc, hills, mist), `paintGrain`
//   StarField       →  `paintStars`
//   MoonPhaseShape, GlintShape, RidgeShape  →  `moonPhasePath`, `GLINT`, `ridgePath`
//
// SwiftUI → canvas, as used below:
//   .blur(radius: r)              ctx.filter = blur(r px)      (r is the Gaussian's sigma in both)
//   .shadow(color:, radius: r)    shadowBlur = 2r, no offset   (canvas blurs by shadowBlur / 2)
//                                 — for a FLAT fill or an image only. Under a gradient fill a
//                                 canvas shadow is wrong (see `sunHalo`), so the sun's is worked
//                                 out and drawn as a gradient; so is the mist's blur (`blurredMistStops`)
//   .opacity(a)                   globalAlpha (a container's opacity reaches each child: no group)
//   .blendMode(.plusLighter)      'lighter';  .blendMode(.softLight)  'soft-light'
//   Linear/RadialGradient stops   addColorStop, 1:1;  UnitPoint × the view's size = points
//   .position(p)                  the view's centre at p;  .scaleEffect / .rotationEffect about the centre
// Canvas blurs and shadows ignore the transform, so both are multiplied by
// `state.dpr` by hand.
//
// The Duo's spread is two skies, as in the app (HomeView.spreadBehindPhone and
// the compact list's `.background`): the leading page's fills the display —
// no orb, the phone page's sky as its companion, so its hills and the sun's or
// moon's glow run on from that sky — and the phone page's own sky (the cover's)
// lies over it from `state.phone.x` to the trailing edge, feathered in over
// 18 pt. Each lays out its clouds, stars and glints by its OWN width, so the
// leading sky is "wide" (951 > 700) and the phone page's is not; what the
// leading sky puts past the fold (a cloud, stars, three glints) is under the
// phone page's sky, as it is in the app.
//
// One canvas. Per sky, two cached layers (under the stars, over them); a
// frame is: back, stars, front, grain — and nothing at all when nothing moved.
//
// Not ported: the flat page under Reduce Transparency / Increase Contrast.

import { cloudArt as homeCloudArt, wispArt as homeWispArt } from '../lab/palette.js';

export const meta = {
  id: 'baseline',
  name: "Today's sky",
  blurb: 'The sky the app ships today (SkyBackground.swift), ported layer for layer — the "before".',
};

// ─────────────────────────────────────────────────────────── constants ──
// Only what is NOT in `enum SkyPalette` (lab/palette.js has the rest).

/** `AppColor.nightlightCream` (Colors.swift): the moon, its glow, the glints' halo. */
const CREAM = { r: 0xFF / 255, g: 0xF4 / 255, b: 0xE8 / 255 };
/** `PhonePage.featherWidth`: how far the phone page's sky fades in on the spread. */
const FEATHER = 18;
/** The grain: `Image("SkyGrain")`, tiled, soft light at 0.3. An @3x asset. */
const GRAIN = 'SkyGrain';
const GRAIN_OPACITY = 0.3;
const GRAIN_ASSET_SCALE = 3;
/** `GlintShape`: a four-point star, in the unit square. */
const GLINT = [[0.5, 0], [0.56, 0.44], [1, 0.5], [0.56, 0.56], [0.5, 1], [0.44, 0.56], [0, 0.5], [0.44, 0.44]];

const TAU = Math.PI * 2;

/** The sun (`SkyScene.sun`): a 46 pt circle filled by a radial gradient —
 *  [location, which of the look's colours, opacity] — with a shadow in the
 *  sun's colour. */
const SUN_RADIUS = 23;
const SUN_DISC = [[0, 'core', 1], [0.42, 'core', 1], [0.72, 'sun', 0.95], [1, 'sun', 0]];
const SUN_SHADOW_OPACITY = 0.55;
const SUN_SHADOW_RADIUS = 17;

/**
 * The sun's shadow, as a radial profile: { reach (points), stops: [{ at, alpha }] }.
 *
 * `.shadow(color:radius:)` is the caster's own alpha, Gaussian-blurred (sigma =
 * radius), in the shadow's colour, under the caster. The sun's disc is opaque
 * to 42 % of its radius and gone at the rim, so its shadow is a wide halo —
 * the blurred alpha is 0.48 at the centre, a quarter at the rim and still a
 * tenth 13 pt past it — and most of what reads as the sun's glow.
 *
 * A canvas shadow cannot draw it: for a gradient FILL Chromium blurs the path
 * and then tints it with the fill, so nothing at all lands outside the disc
 * (and under a blurred 8-bit layer the faint outer part is lost on the dark
 * sky). A round caster's shadow is round, though, and this disc never changes
 * shape, so the blur is worked out once — the disc's alpha a(r), convolved
 * with the 2-D Gaussian — and drawn as a radial gradient: exact.
 * (Exported for tools/test-math.mjs, which checks it against the blur itself.)
 */
let sunHaloProfile = null;
export function sunHalo() {
  if (sunHaloProfile) return sunHaloProfile;
  const R = SUN_RADIUS;
  const sigma = SUN_SHADOW_RADIUS;
  const reach = R + 4 * sigma;
  // The disc's alpha at radius r: the gradient's stops, alpha only.
  const discAlpha = (r) => {
    const t = r / R;
    for (let index = 0; index < SUN_DISC.length - 1; index += 1) {
      const [from, , a] = SUN_DISC[index];
      const [to, , b] = SUN_DISC[index + 1];
      if (t <= to) return a + (b - a) * (to > from ? (t - from) / (to - from) : 0);
    }
    return 0;
  };
  // A(d) = (1 / 2 pi sigma^2) * integral of a(r) exp(-|p - q|^2 / 2 sigma^2) over the disc, |q| = d.
  const rings = 92;         // 1/4 pt
  const angles = 64;        // over half the circle; the other half mirrors it
  const count = 96;         // a stop a point, near enough
  const stops = [];
  for (let n = 0; n <= count; n += 1) {
    const d = reach * n / count;
    let sum = 0;
    for (let i = 0; i < rings; i += 1) {
      const r = (i + 0.5) * R / rings;
      let ring = 0;
      for (let k = 0; k < angles; k += 1) {
        const theta = (k + 0.5) * Math.PI / angles;
        ring += Math.exp(-(d * d + r * r - 2 * d * r * Math.cos(theta)) / (2 * sigma * sigma));
      }
      sum += discAlpha(r) * r * ring;
    }
    stops.push({ at: n / count, alpha: sum * (R / rings) / (angles * sigma * sigma) });
  }
  stops[count].alpha = 0;   // 4 sigma out: already under a thousandth
  sunHaloProfile = { reach, stops };
  return sunHaloProfile;
}

// ────────────────────────────────────────────────────────────── assets ──

/** href → { image: HTMLImageElement | null, settled, promise }. Shared by every instance. */
const imageCache = new Map();

function loadImage(href) {
  let entry = imageCache.get(href);
  if (entry) return entry;
  entry = { image: null, settled: false, promise: null };
  entry.promise = new Promise((resolve) => {
    const image = new Image();
    const finish = (ok) => {
      if (entry.settled) return;
      entry.settled = true;
      entry.image = ok ? image : null;
      if (!ok) console.warn(`sky/baseline: could not load ${href}`);
      resolve(entry);
    };
    image.onload = () => {
      // Decoded before the first draw, so a frame never stalls on it.
      const decoded = typeof image.decode === 'function' ? image.decode() : Promise.resolve();
      decoded.then(() => finish(true), () => finish(true));
    };
    image.onerror = () => finish(false);
    image.src = href;
  });
  imageCache.set(href, entry);
  return entry;
}

function assetNames(cloudArt, wispArt) {
  const names = new Set([GRAIN]);
  for (const art of [...cloudArt, wispArt]) {
    names.add(art.dawn);
    names.add(art.day);
    names.add(art.dusk);
  }
  return [...names];
}

// The lab's own assets are fetched while this module loads (top-level await),
// so the very first `render` already has its clouds and grain — a frozen frame
// is complete without the viewer having to know when the images arrived.
// (`create` still loads anything else `env` asks for, and redraws when it lands.)
const HOME_ASSETS = typeof document !== 'undefined' && typeof Image !== 'undefined'
  ? new URL('../assets/', import.meta.url).href
  : null;
if (HOME_ASSETS) {
  const entries = assetNames(homeCloudArt, homeWispArt).map((name) => loadImage(`${HOME_ASSETS}${name}.png`));
  await Promise.race([
    Promise.all(entries.map((entry) => entry.promise)),
    new Promise((resolve) => setTimeout(resolve, 6000)),   // never hang the import on a stuck request
  ]);
}

// ─────────────────────────────────────────────────────────────── shapes ──

/** `MoonPhaseShape(lit:)` in a square of radius `r` about the origin: the lit
 *  part, bright edge on the right — down the limb, back up the terminator. */
function moonPhasePath(lit, r) {
  const terminator = 1 - 2 * Math.min(Math.max(lit, 0), 1);   // 1 new, 0 half, −1 full
  const steps = 48;
  const path = new Path2D();
  for (let step = 0; step <= steps; step += 1) {
    const t = Math.PI * step / steps;
    const x = r * Math.sin(t);
    const y = -r * Math.cos(t);
    if (step === 0) path.moveTo(x, y); else path.lineTo(x, y);
  }
  for (let step = steps; step >= 0; step -= 1) {
    const t = Math.PI * step / steps;
    path.lineTo(terminator * r * Math.sin(t), -r * Math.cos(t));
  }
  path.closePath();
  return path;
}

/** `RidgeShape`: one ridge, filled down to (and past) the bottom edge. Through
 *  the midpoints, each sample the control point. */
function ridgePath(ridge, width, height, xOffset) {
  const points = ridge.points(width, height, xOffset);
  const path = new Path2D();
  if (points.length <= 2) return path;
  path.moveTo(points[0].x, points[0].y);
  for (let index = 1; index < points.length - 1; index += 1) {
    const point = points[index];
    const next = points[index + 1];
    path.quadraticCurveTo(point.x, point.y, (point.x + next.x) / 2, (point.y + next.y) / 2);
  }
  const last = points[points.length - 1];
  path.lineTo(last.x, last.y);
  path.lineTo(width + 30, height + 20);
  path.lineTo(-30, height + 20);
  path.closePath();
  return path;
}

// ─────────────────────────────────────────────────────────────── module ──

/**
 * create(host, env) → { render(state), destroy(), ready }
 *
 * `ready` (beyond the contract; the viewer awaits it when it is there) is a
 * Promise that resolves once every image this sky draws has loaded and the
 * last state rendered has been redrawn with them. With the lab's own assets
 * it has nothing to wait for: they arrived with the module.
 */
export function create(host, env) {
  const P = env?.palette?.SkyPalette ?? env?.palette;
  if (!P || typeof P.clouds !== 'function' || !Array.isArray(P.ridges)) {
    throw new TypeError('skies/baseline: env.palette must be lab/palette.js (or its SkyPalette)');
  }
  const { css, mix } = P;
  const doc = host.ownerDocument ?? document;
  const newCanvas = () => doc.createElement('canvas');

  const canvas = newCanvas();
  canvas.setAttribute('aria-hidden', 'true');
  canvas.style.cssText = 'position:absolute;left:0;top:0;display:block;pointer-events:none;';
  host.appendChild(canvas);
  // `willReadFrequently: false`, said out loud: the spread's feather reads two
  // narrow strips back per frame, and Chrome would otherwise move the whole
  // canvas off the GPU for it.
  const main = canvas.getContext('2d', { willReadFrequently: false });

  /** `env.noCanvasFilter` (a test switch) forces the path for browsers without `ctx.filter`. */
  const hasFilter = typeof main.filter === 'string' && env?.noCanvasFilter !== true;

  // ── assets ──
  const assetBase = new URL(env?.assets ?? HOME_ASSETS ?? 'assets/', doc.baseURI).href;
  const assetEntries = new Map();
  for (const name of assetNames(P.cloudArt, P.wispArt)) {
    assetEntries.set(name, loadImage(new URL(`${name}.png`, assetBase).href));
  }
  const image = (name) => assetEntries.get(name)?.image ?? null;
  /** Counts the images that have arrived; part of every cache key. */
  let assetVersion = [...assetEntries.values()].filter((entry) => entry.settled).length;

  let destroyed = false;
  let lastState = null;
  let lastFrameKey = '';

  // Anything still on its way (only when `env.assets` is somewhere other than
  // the lab's own folder, or the network was slow): draw without it for now,
  // and once more when it is all here — a frozen frame gets its clouds and grain.
  const pending = [...assetEntries.values()].filter((entry) => !entry.settled);
  const ready = Promise.all(pending.map((entry) => entry.promise)).then(() => {
    if (pending.length === 0) return;
    assetVersion += pending.length;
    if (!destroyed && lastState) render(lastState);
  });

  // ── one sky (a `SkyBackground`) ──
  // `x`, `width`, `height` in points; `back` and `front` are its still layers:
  // everything under the stars, and everything over them but the grain.
  const views = [];
  const makeView = () => ({ back: newCanvas(), front: newCanvas(), staticKey: '' });

  /** A point on the sky's arc (fractions of the sky) in this view — on the
   *  companion's sky when there is one (`SkyScene.point(_:in:)`). */
  function point(view, position) {
    if (view.companion) {
      return { x: view.companion.originX + position.x * view.companion.width, y: position.y * view.height };
    }
    return { x: position.x * view.width, y: position.y * view.height };
  }

  /** Where the view's leading edge is on `ctx`'s canvas, in device pixels:
   *  on its own layers, the sliver left over from whole pixels; on the
   *  display's canvas, the view's place on the display. */
  const originX = (ctx, view) => (ctx === main ? view.x * view.s : view.tx);

  function begin(ctx, view, clear) {
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.globalAlpha = 1;
    ctx.globalCompositeOperation = 'source-over';
    ctx.shadowColor = 'rgba(0, 0, 0, 0)';
    ctx.shadowBlur = 0;
    if (hasFilter) ctx.filter = 'none';
    if (clear) ctx.clearRect(0, 0, ctx.canvas.width, ctx.canvas.height);
    // Points from here on; the view's own x = 0 at its leading edge.
    ctx.setTransform(view.s, 0, 0, view.s, originX(ctx, view), 0);
    ctx.imageSmoothingEnabled = true;
    ctx.imageSmoothingQuality = 'high';
  }

  // ── SkyScene.sky(in:sun:moon:), then the sun and the clouds ──

  function paintBack(ctx, view, scene) {
    const { width, height, s } = view;
    const look = scene.look;
    const page = scene.page;
    const sun = scene.isNight ? null : point(view, scene.body);
    const moon = scene.moon ? point(view, scene.moon) : null;
    // The glows are drawn for this sky's own sun and moon, or the companion's,
    // and sized by the sky whose sun and moon they are.
    const drawsGlow = view.showsOrb || view.companion != null;
    const orbSkyWidth = view.companion ? view.companion.width : width;
    const reach = Math.max(orbSkyWidth, height);
    const nightMoon = scene.isNight ? moon : null;
    const pooled = drawsGlow ? (sun ?? nightMoon) : null;

    begin(ctx, view, true);

    // The gradient: sky at the top, the page in the middle, the haze the hills
    // stand in at the bottom.
    const sky = ctx.createLinearGradient(0, 0, 0, height);
    sky.addColorStop(0, css(look.top));
    sky.addColorStop(0.15, css(mix(look.top, look.mid, 0.55)));
    sky.addColorStop(0.33, css(look.mid));
    sky.addColorStop(0.46, css(mix(look.mid, page, 0.6)));
    sky.addColorStop(0.56, css(page));
    sky.addColorStop(0.66, css(mix(page, look.haze, 0.6)));
    sky.addColorStop(0.74, css(look.haze));
    sky.addColorStop(1, css(look.haze));
    ctx.fillStyle = sky;
    ctx.fillRect(0, 0, width, height);

    // A warm pool of light around the sun by day, the moon by night: a circle
    // of radius rx, squashed to ry.
    if (pooled) {
      const alpha = 0.45 * P.glow * (sun == null ? scene.moonPoolByPhase : 1);
      const radius = Math.max(orbSkyWidth * 0.7, 1);
      const ry = Math.max(height * 0.36, 1);
      ctx.save();
      ctx.translate(pooled.x, pooled.y);
      ctx.scale(1, ry / radius);
      const pool = ctx.createRadialGradient(0, 0, 0, 0, 0, radius);
      pool.addColorStop(0, css(look.warm, alpha));
      pool.addColorStop(1, css(look.warm, 0));
      ctx.fillStyle = pool;
      ctx.beginPath();
      ctx.arc(0, 0, radius, 0, TAU);
      ctx.fill();
      ctx.restore();
    }

    // The moon's glow (night only)…
    if (drawsGlow && nightMoon) {
      const strength = scene.moonGlowByPhase;
      const glow = ctx.createRadialGradient(nightMoon.x, nightMoon.y, 0, nightMoon.x, nightMoon.y, reach * 0.25);
      glow.addColorStop(0, css(CREAM, 0.4 * strength));
      glow.addColorStop(0.35, css(CREAM, 0.12 * strength));
      glow.addColorStop(1, css(CREAM, 0));
      ctx.fillStyle = glow;
      ctx.fillRect(0, 0, width, height);
    }
    // …and the sun's bloom.
    if (drawsGlow && sun) {
      const bloom = ctx.createRadialGradient(sun.x, sun.y, 0, sun.x, sun.y, reach * 0.5);
      bloom.addColorStop(0, css(look.sun, 0.55 * P.glow));
      bloom.addColorStop(0.12, css(look.sun, 0.25 * P.glow));
      bloom.addColorStop(0.3, css(look.sun, 0.1 * P.glow));
      bloom.addColorStop(0.6, css(look.sun, 0));
      ctx.fillStyle = bloom;
      ctx.fillRect(0, 0, width, height);
    }

    if (scene.isNight) return;   // the stars come next, on their own clock

    // The sun: a soft disc — bright core, no rim — glowing into the bloom.
    // Its `.shadow(color: sun at 0.55, radius: 17)` first (`sunHalo`), the
    // disc over it.
    if (view.showsOrb && sun) {
      const shadow = sunHalo();
      const halo = ctx.createRadialGradient(sun.x, sun.y, 0, sun.x, sun.y, shadow.reach);
      for (const stop of shadow.stops) halo.addColorStop(stop.at, css(look.sun, SUN_SHADOW_OPACITY * stop.alpha));
      ctx.fillStyle = halo;
      ctx.beginPath();
      ctx.arc(sun.x, sun.y, shadow.reach, 0, TAU);
      ctx.fill();

      const disc = ctx.createRadialGradient(sun.x, sun.y, 0, sun.x, sun.y, SUN_RADIUS);
      for (const [at, part, alpha] of SUN_DISC) disc.addColorStop(at, css(look[part], alpha));
      ctx.fillStyle = disc;
      ctx.beginPath();
      ctx.arc(sun.x, sun.y, SUN_RADIUS, 0, TAU);
      ctx.fill();
    }

    paintClouds(ctx, view, scene);
  }

  // ── SkyScene.clouds(in:) ──

  /** One cloud texture in the scene's light (`cloudImage`): its dawn, day and
   *  dusk lightings added together by their weights — an exact crossfade, as
   *  the three share one silhouette and the weights sum to one. */
  const litCache = new Map();   // art.day → { key, canvas }
  function litTexture(art, light) {
    const sources = [[image(art.dawn), light.dawn], [image(art.day), light.day], [image(art.dusk), light.dusk]];
    const first = sources.find(([source]) => source)?.[0];
    if (!first) return null;
    const key = `${light.dawn}|${light.day}|${light.dusk}|${sources.map(([source]) => (source ? 1 : 0)).join('')}`;
    let cached = litCache.get(art.day);
    if (!cached) {
      cached = { key: '', canvas: newCanvas() };
      litCache.set(art.day, cached);
    }
    if (cached.key === key) return cached.canvas;
    const texture = cached.canvas;
    texture.width = first.naturalWidth;
    texture.height = first.naturalHeight;
    const ctx = texture.getContext('2d');
    ctx.globalCompositeOperation = 'lighter';   // .plusLighter (over nothing, the first is itself)
    for (const [source, weight] of sources) {
      if (!source || !(weight > 0)) continue;
      ctx.globalAlpha = Math.min(weight, 1);
      ctx.drawImage(source, 0, 0, texture.width, texture.height);
    }
    cached.key = key;
    return texture;
  }

  function paintClouds(ctx, view, scene) {
    if (!(scene.cloudOpacity > 0)) return;
    const { width, height } = view;
    const wide = width > P.wideLayoutWidth;
    const light = scene.look.light;
    const draw = (art, cx, cy, w, opacity, flipped) => {
      const texture = litTexture(art, light);
      if (!texture) return;
      const h = w * art.aspect;
      ctx.save();
      ctx.globalAlpha = Math.min(Math.max(opacity * scene.cloudOpacity, 0), 1);
      ctx.translate(cx, cy);
      if (flipped) ctx.scale(-1, 1);
      ctx.drawImage(texture, -w / 2, -h / 2, w, h);
      ctx.restore();
    };
    for (const wisp of P.wisps(wide)) {
      draw(P.wispArt, wisp.x * width, wisp.y * height, wisp.width, wisp.alpha * scene.cloudStrength, false);
    }
    for (const cloud of P.clouds(wide)) {
      const art = P.cloudArt[cloud.art];
      // `y` is where the cloud's flat base sits: 84 % down its texture.
      draw(art, cloud.x * width, cloud.y * height - cloud.width * art.aspect * 0.34, cloud.width,
        scene.cloudStrength, cloud.flipped);
    }
  }

  // ── StarField ──

  let glintScratch = null;

  /** `time` null draws the stars still: full brightness, glints part-way open. */
  function paintStars(ctx, view, scene, time) {
    const visibility = scene.starOpacity * scene.starStrength;
    if (!(visibility > 0)) return;
    const { width, height, s } = view;
    const stars = P.stars(width);
    const glints = P.glints(width > P.wideLayoutWidth);

    begin(ctx, view, false);
    ctx.fillStyle = '#fff';
    ctx.shadowColor = 'rgba(255, 255, 255, 0.9)';
    for (const star of stars) {
      const twinkle = time == null ? 1 : P.twinkle(star, time);
      const alpha = star.alpha * twinkle * visibility;
      if (!(alpha > 0)) continue;
      ctx.globalAlpha = Math.min(alpha, 1);
      ctx.shadowBlur = 2 * (star.size > 2 ? 2.5 : 1) * s;
      ctx.beginPath();
      ctx.arc(star.x * width, star.y * height, star.size / 2, 0, TAU);
      ctx.fill();
    }

    // A glint has two shadows, the second cast by the first: the star and its
    // tight white glow are drawn aside, and that is laid down with the cream halo.
    glintScratch ??= newCanvas();
    const scratch = glintScratch.getContext('2d');
    for (const glint of glints) {
      const sparkle = time == null ? 0.6 : P.sparkle(glint, time);
      const alpha = (0.3 + 0.7 * sparkle) * visibility;
      if (!(alpha > 0)) continue;
      const cx = glint.x * width * s + originX(ctx, view);   // device px on this canvas
      const cy = glint.y * height * s;
      const half = Math.ceil((glint.size / 2 + 9) * s) + 1;   // room for the first shadow (3 sigma = 6 pt)
      const side = half * 2 + 1;
      const left = Math.floor(cx) - half;
      const top = Math.floor(cy) - half;
      if (glintScratch.width < side || glintScratch.height < side) {
        glintScratch.width = side;
        glintScratch.height = side;
      }
      scratch.setTransform(1, 0, 0, 1, 0, 0);
      scratch.clearRect(0, 0, glintScratch.width, glintScratch.height);
      scratch.setTransform(s, 0, 0, s, cx - left, cy - top);
      scratch.rotate((25 * sparkle) * Math.PI / 180);
      const scale = 0.45 + 0.55 * sparkle;
      scratch.scale(scale, scale);
      scratch.shadowColor = css(P.glintColor, 0.95);
      scratch.shadowBlur = 2 * 2 * s;
      scratch.fillStyle = css(P.glintColor);
      scratch.beginPath();
      GLINT.forEach(([x, y], index) => {
        const px = (x - 0.5) * glint.size;
        const py = (y - 0.5) * glint.size;
        if (index === 0) scratch.moveTo(px, py); else scratch.lineTo(px, py);
      });
      scratch.closePath();
      scratch.fill();

      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.globalAlpha = Math.min(alpha, 1);
      ctx.shadowColor = css(CREAM, 0.7);
      ctx.shadowBlur = 2 * 6 * s;
      ctx.drawImage(glintScratch, 0, 0, side, side, left, top, side, side);
    }
    ctx.shadowColor = 'rgba(0, 0, 0, 0)';
    ctx.shadowBlur = 0;
    ctx.globalAlpha = 1;
  }

  // ── the moon, then SkyScene.hills(in:) ──

  let blurScratch = null;

  /** `shape.fill(style).blur(radius:)` without `ctx.filter`: the shape's alpha
   *  blurred as a shadow (a Gaussian of the same sigma), then the unblurred
   *  gradient poured into it — the fill is a slow ramp, so only its alpha edge
   *  shows the blur. */
  function fillBlurredWithoutFilter(ctx, view, path, style, radius) {
    blurScratch ??= newCanvas();
    const target = ctx.canvas;
    if (blurScratch.width !== target.width || blurScratch.height !== target.height) {
      blurScratch.width = target.width;
      blurScratch.height = target.height;
    }
    const scratch = blurScratch.getContext('2d');
    const away = target.height + Math.ceil(60 * view.s);   // draw the shape off the canvas; keep only its shadow
    scratch.setTransform(1, 0, 0, 1, 0, 0);
    scratch.globalCompositeOperation = 'source-over';
    scratch.clearRect(0, 0, target.width, target.height);
    scratch.shadowColor = '#000';
    scratch.shadowBlur = 2 * radius * view.s;
    scratch.shadowOffsetY = -away;
    scratch.setTransform(view.s, 0, 0, view.s, view.tx, away);
    scratch.fillStyle = '#000';
    scratch.fill(path);
    scratch.shadowColor = 'rgba(0, 0, 0, 0)';
    scratch.shadowOffsetY = 0;
    scratch.setTransform(view.s, 0, 0, view.s, view.tx, 0);
    scratch.globalCompositeOperation = 'source-in';
    scratch.fillStyle = style;
    scratch.fillRect(-40, -40, view.width + 80, view.height + 80);
    ctx.save();
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.drawImage(blurScratch, 0, 0);
    ctx.restore();
  }

  /** The mist band's alpha down its height after `.blur(radius:)`, worked out
   *  rather than filtered: the 0 → alpha → 0 ramp convolved with the Gaussian.
   *  → gradient stops. (The band is 20 pt wider than the sky at each end, so
   *  only its profile blurs; and a filtered 8-bit layer this faint comes out
   *  short — the dark appearance's mist is six levels at its peak, and
   *  `ctx.filter` lost one to two of them.) */
  function blurredMistStops(bandHeight, peakAt, sigma) {
    const reach = 3 * sigma;
    const profile = (y) => {
      if (y <= 0 || y >= bandHeight) return 0;
      const peak = peakAt * bandHeight;
      return y < peak ? y / peak : (bandHeight - y) / (bandHeight - peak);
    };
    const stops = [];
    const span = bandHeight + 2 * reach;
    const count = Math.ceil(span);
    for (let index = 0; index <= count; index += 1) {
      const y = -reach + span * index / count;
      let sum = 0;
      let weightSum = 0;
      for (let d = -reach; d <= reach; d += 0.25) {
        const weight = Math.exp(-(d * d) / (2 * sigma * sigma));
        sum += weight * profile(y + d);
        weightSum += weight;
      }
      stops.push({ at: index / count, value: sum / weightSum });
    }
    return { stops, top: -reach, span };
  }

  let mistProfile = null;

  function paintFront(ctx, view, scene) {
    const { width, s } = view;
    const look = scene.look;
    const moon = scene.moon;

    begin(ctx, view, true);

    // The moon wherever it really is while it is up — by day too, pale.
    if (view.showsOrb && moon) {
      const at = point(view, moon);
      const daylight = moon.inDaylight ? P.daytimeMoonOpacity : 1;
      ctx.save();
      ctx.translate(at.x, at.y);
      // The whole disc, a faint earthshine…
      ctx.globalAlpha = daylight;
      ctx.fillStyle = css(CREAM, 0.06 * scene.starStrength);
      ctx.beginPath();
      ctx.arc(0, 0, 16, 0, TAU);
      ctx.fill();
      // …and the lit part, turned to the bright limb's real angle, with its glow.
      const glow = 0.85 * (0.4 + 0.6 * moon.fraction) * scene.moonGlow * (moon.inDaylight ? 0 : 1);
      ctx.rotate(moon.rotation);
      if (glow > 0) {
        ctx.shadowColor = css(CREAM, glow);
        ctx.shadowBlur = 2 * 9 * s;
      }
      ctx.fillStyle = css(CREAM);
      ctx.fill(moonPhasePath(moon.fraction, 16));
      ctx.restore();
    }

    // Four ridges, back to front: darkest at the crest, dissolving into the
    // valley mist below, each blurred a little — the far ones more.
    const height = Math.max(view.height, 1);
    const ridges = P.ridges;
    const xOffset = view.companion ? view.companion.originX : 0;
    ridges.forEach((ridge, index) => {
      const crest = look.hills[index];
      const isFront = index === ridges.length - 1;
      const foot = isFront ? look.deep : mix(crest, look.haze, 0.5);
      const footY = isFront ? height : ridges[index + 1].baseline(height) + 6;
      const fill = ctx.createLinearGradient(0, ridge.crestTop(height), 0, footY);
      fill.addColorStop(0, css(crest));
      fill.addColorStop(1, css(foot));
      const path = ridgePath(ridge, width, height, xOffset);
      if (hasFilter) {
        ctx.save();
        ctx.filter = `blur(${ridge.blur * s}px)`;
        ctx.fillStyle = fill;
        ctx.fill(path);
        ctx.restore();
      } else {
        fillBlurredWithoutFilter(ctx, view, path, fill, ridge.blur);
      }

      if (isFront) return;
      // A soft band of valley mist just above the next ridge's crest:
      // (width + 40) × 54, centred at centreY, clear → mist at 55 % → clear,
      // blurred 6 — drawn as the blurred profile itself (`blurredMistStops`).
      const centreY = ridges[index + 1].baseline(height) - 9;
      const top = centreY - 27;
      mistProfile ??= blurredMistStops(54, 0.55, 6);
      const mist = ctx.createLinearGradient(0, top + mistProfile.top, 0, top + mistProfile.top + mistProfile.span);
      for (const stop of mistProfile.stops) mist.addColorStop(stop.at, css(look.mist, look.mistAlpha * stop.value));
      ctx.fillStyle = mist;
      ctx.fillRect(-20, top + mistProfile.top, width + 40, mistProfile.span);
    });
  }

  // ── the grain ──

  /** Three tiles of the grain (256 pt: the @3x asset is 256 px, 85⅓ pt a
   *  tile), resampled once to this pixel density so the pattern lands on
   *  whole pixels. */
  const grainCache = { key: '', canvas: null, pointsWide: 0, pointsTall: 0 };
  function grainTile(s) {
    const source = image(GRAIN);
    if (!source) return null;
    const key = `${s}|${source.src}`;
    if (grainCache.key === key) return grainCache;
    const wide = source.naturalWidth * GRAIN_ASSET_SCALE;     // three tiles across, at the asset's own scale
    const tall = source.naturalHeight * GRAIN_ASSET_SCALE;
    const pointsWide = wide / GRAIN_ASSET_SCALE;
    const pointsTall = tall / GRAIN_ASSET_SCALE;
    const full = newCanvas();
    full.width = wide;
    full.height = tall;
    const fullCtx = full.getContext('2d');
    for (let row = 0; row < GRAIN_ASSET_SCALE; row += 1) {
      for (let column = 0; column < GRAIN_ASSET_SCALE; column += 1) {
        fullCtx.drawImage(source, column * source.naturalWidth, row * source.naturalHeight);
      }
    }
    const pxWide = Math.max(1, Math.round(pointsWide * s));
    const pxTall = Math.max(1, Math.round(pointsTall * s));
    let tile = full;
    if (pxWide !== wide || pxTall !== tall) {
      tile = newCanvas();
      tile.width = pxWide;
      tile.height = pxTall;
      const tileCtx = tile.getContext('2d');
      tileCtx.imageSmoothingEnabled = true;
      tileCtx.imageSmoothingQuality = 'high';
      tileCtx.drawImage(full, 0, 0, pxWide, pxTall);
    }
    grainCache.key = key;
    grainCache.canvas = tile;
    grainCache.pointsWide = pointsWide;
    grainCache.pointsTall = pointsTall;
    return grainCache;
  }

  /** `Image("SkyGrain").resizable(resizingMode: .tile).blendMode(.softLight).opacity(0.3)` */
  function paintGrain(ctx, view) {
    const grain = grainTile(view.s);
    if (!grain) return;
    begin(ctx, view, false);
    const pattern = ctx.createPattern(grain.canvas, 'repeat');
    pattern.setTransform(new DOMMatrix().scale(grain.pointsWide / grain.canvas.width,
      grain.pointsTall / grain.canvas.height));
    ctx.globalCompositeOperation = 'soft-light';
    ctx.globalAlpha = GRAIN_OPACITY;
    ctx.fillStyle = pattern;
    ctx.fillRect(0, 0, view.width, view.height);
    ctx.globalCompositeOperation = 'source-over';
    ctx.globalAlpha = 1;
  }

  // ── putting one sky together ──

  /** One sky onto the display's canvas, at its own place. `view.back` and
   *  `view.front` are its still layers; only the stars are drawn per frame. */
  function paintView(view, scene, time, staticKey) {
    if (view.staticKey !== staticKey) {
      paintBack(view.back.getContext('2d'), view, scene);
      paintFront(view.front.getContext('2d'), view, scene);
      view.staticKey = staticKey;
    }
    const whole = view.pxLeft === 0 && view.back.width >= canvas.width;
    main.save();
    if (!whole) {
      // A sky is clipped to its own frame (in the app, by the feather's mask),
      // or to the part of it that shows.
      main.setTransform(1, 0, 0, 1, 0, 0);
      main.beginPath();
      main.rect(view.pxLeft, 0, view.back.width, view.back.height);
      main.clip();
    }
    begin(main, view, false);
    main.setTransform(1, 0, 0, 1, 0, 0);
    main.drawImage(view.back, view.pxLeft, 0);
    if (scene.isNight) paintStars(main, view, scene, time);
    main.setTransform(1, 0, 0, 1, 0, 0);
    main.globalAlpha = 1;
    main.drawImage(view.front, view.pxLeft, 0);
    paintGrain(main, view);
    main.restore();
  }

  /** `SkyBackground.leadingFeather`: the mask is clear → opaque across the
   *  first `feather` points of the sky, so over that strip the sky beneath
   *  shows through, less and less. `beneath` is that strip as it was before
   *  this sky was drawn. Mixed here in floating point and rounded once: an
   *  8-bit masked layer loses up to a level in the dark, and on the night sky
   *  that reads as a seam down the fold. */
  function featherStrip(view) {
    const columns = Math.min(Math.ceil(view.feather * view.s + view.tx - 1e-6), canvas.width - view.pxLeft);
    return columns > 0 ? { x: view.pxLeft, columns } : null;
  }
  function feather(view, strip, beneath) {
    const over = main.getImageData(strip.x, 0, strip.columns, canvas.height).data;
    const data = beneath.data;
    const span = view.feather * view.s;
    for (let column = 0; column < strip.columns; column += 1) {
      const cover = Math.min(Math.max((column + 0.5 - view.tx) / span, 0), 1);   // the mask at the pixel's centre
      for (let index = column * 4, end = data.length; index < end; index += strip.columns * 4) {
        data[index] += (over[index] - data[index]) * cover;
        data[index + 1] += (over[index + 1] - data[index + 1]) * cover;
        data[index + 2] += (over[index + 2] - data[index + 2]) * cover;
      }
    }
    main.putImageData(beneath, strip.x, 0);
  }

  /** Which skies this display has, back to front (see the header). */
  function layout(state, s) {
    const { width, height } = state;
    const phone = state.phone ?? { x: 0, width };
    // `shown`: how much of a sky can be seen at all. Past its feather the
    // phone page's sky hides the leading one entirely, so (when it reaches the
    // trailing edge, as it does) that part of the leading sky is never painted.
    // Everything is still laid out on the sky's full `width`.
    const hidesTheRest = phone.x + phone.width >= width - 1e-6;
    const specs = phone.x > 0
      ? [{ x: 0, width, shown: hidesTheRest ? Math.min(width, phone.x + FEATHER) : width,
           showsOrb: false, companion: { originX: phone.x, width: phone.width }, feather: 0 },
         { x: phone.x, width: phone.width, shown: phone.width, showsOrb: true, companion: null, feather: FEATHER }]
      : [{ x: 0, width, shown: width, showsOrb: true, companion: null, feather: 0 }];
    const pxHeight = Math.ceil(height * s - 1e-6);
    views.length = specs.length;
    specs.forEach((spec, index) => {
      const view = views[index] ?? (views[index] = makeView());
      // Its layers sit on whole device pixels; `tx` is what is left over.
      const pxLeft = Math.floor(spec.x * s + 1e-6);
      const pxWidth = Math.ceil((spec.x + spec.shown) * s - 1e-6) - pxLeft;
      Object.assign(view, spec, { height, s, pxLeft, tx: spec.x * s - pxLeft });
      for (const layer of [view.back, view.front]) {
        if (layer.width !== pxWidth || layer.height !== pxHeight) {
          layer.width = pxWidth;
          layer.height = pxHeight;
          view.staticKey = '';
        }
      }
    });
    return pxHeight;
  }

  function render(state) {
    if (destroyed || !state || !state.scene) return;
    lastState = state;
    const scene = state.scene;
    const s = Number.isFinite(state.dpr) && state.dpr > 0 ? state.dpr : 1;
    const phone = state.phone ?? { x: 0, width: state.width };
    // Still under Reduce Motion (and whenever the lab has no clock to give).
    const time = state.reduceMotion || !Number.isFinite(state.t) ? null : state.t;
    const twinkling = scene.isNight && scene.starOpacity * scene.starStrength > 0 && time != null;

    const staticKey = [state.width, state.height, s, phone.x, phone.width, assetVersion,
      JSON.stringify(scene)].join('|');
    const frameKey = `${staticKey}|${twinkling ? time : 'still'}`;
    if (frameKey === lastFrameKey) return;   // nothing moved: the canvas already shows this frame
    lastFrameKey = '';

    const pxHeight = layout(state, s);
    const pxWidth = Math.ceil(state.width * s - 1e-6);
    if (canvas.width !== pxWidth || canvas.height !== pxHeight) {
      canvas.width = pxWidth;
      canvas.height = pxHeight;
    }
    const cssWidth = `${pxWidth / s}px`;
    const cssHeight = `${pxHeight / s}px`;
    if (canvas.style.width !== cssWidth) canvas.style.width = cssWidth;
    if (canvas.style.height !== cssHeight) canvas.style.height = cssHeight;

    for (const view of views) {
      const strip = view.feather > 0 ? featherStrip(view) : null;
      const beneath = strip ? main.getImageData(strip.x, 0, strip.columns, canvas.height) : null;
      paintView(view, scene, time, staticKey);
      if (strip) feather(view, strip, beneath);
    }
    lastFrameKey = frameKey;
  }

  function destroy() {
    destroyed = true;
    lastState = null;
    views.length = 0;
    litCache.clear();
    canvas.remove();
  }

  return { render, destroy, ready };
}
