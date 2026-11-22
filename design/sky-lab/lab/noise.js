// Seeded noise for skies: the same picture for the same state, every time.
// JS versions for canvas work, and the same functions as a GLSL chunk for
// WebGL skies (which port almost line for line to a SwiftUI Metal shader).

/** A stable 0–1 hash of two integers and a seed. */
export function hash2(x, y, seed = 0) {
  let h = (Math.imul(x | 0, 0x27d4eb2d) ^ Math.imul(y | 0, 0x165667b1) ^ Math.imul((seed | 0) + 1, 0x9e3779b1)) >>> 0;
  h ^= h >>> 15; h = Math.imul(h, 0x85ebca6b) >>> 0;
  h ^= h >>> 13; h = Math.imul(h, 0xc2b2ae35) >>> 0;
  h ^= h >>> 16;
  return (h >>> 0) / 4294967296;
}

/** A seeded sequence of 0–1 numbers (mulberry32). */
export function rng(seed = 1) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const fade = (t) => t * t * t * (t * (t * 6 - 15) + 10);

/** Smooth value noise, 0–1. */
export function noise2(x, y, seed = 0) {
  const xi = Math.floor(x), yi = Math.floor(y);
  const u = fade(x - xi), v = fade(y - yi);
  const a = hash2(xi, yi, seed), b = hash2(xi + 1, yi, seed);
  const c = hash2(xi, yi + 1, seed), d = hash2(xi + 1, yi + 1, seed);
  return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
}

/** Fractal noise, 0–1: `octaves` layers, each twice as fine and `gain` as strong. */
export function fbm2(x, y, { octaves = 5, gain = 0.5, lacunarity = 2, seed = 0 } = {}) {
  let sum = 0, amp = 0.5, norm = 0;
  for (let o = 0; o < octaves; o++) {
    sum += amp * noise2(x, y, seed + o * 131);
    norm += amp;
    x = x * lacunarity + 17.3; y = y * lacunarity - 9.1;
    amp *= gain;
  }
  return sum / norm;
}

/** 1-D fractal noise for ridge lines and the like, 0–1. */
export function fbm1(x, opts = {}) {
  return fbm2(x, 0.5, opts);
}

/** The same, for a fragment shader. `#version 300 es` or WebGL1 both fine. */
export const GLSL_NOISE = /* glsl */ `
float hash21(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}
float vnoise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
  float a = hash21(i), b = hash21(i + vec2(1.0, 0.0));
  float c = hash21(i + vec2(0.0, 1.0)), d = hash21(i + vec2(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
float fbm(vec2 p) {
  float s = 0.0, a = 0.5, n = 0.0;
  mat2 r = mat2(0.8, -0.6, 0.6, 0.8);
  for (int i = 0; i < 6; i++) { s += a * vnoise(p); n += a; p = r * p * 2.03 + 11.7; a *= 0.5; }
  return s / n;
}
// OKLab mixing, so gradients between distant hues stay clean.
vec3 toLinear(vec3 c) { return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c)); }
vec3 toGamma(vec3 c) { return mix(c * 12.92, 1.055 * pow(max(c, 0.0), vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c)); }
vec3 oklab(vec3 srgb) {
  vec3 c = toLinear(srgb);
  vec3 lms = pow(max(mat3(0.4122214708, 0.2119034982, 0.0883024619,
                          0.5363325363, 0.6806995451, 0.2817188376,
                          0.0514459929, 0.1073969566, 0.6299787005) * c, 0.0), vec3(1.0 / 3.0));
  return mat3(0.2104542553, 1.9779984951, 0.0259040371,
              0.7936177850, -2.4285922050, 0.7827717662,
              -0.0040720468, 0.4505937099, -0.8086757660) * lms;
}
vec3 unoklab(vec3 lab) {
  vec3 lms = mat3(1.0, 1.0, 1.0,
                  0.3963377774, -0.1055613458, -0.0894841775,
                  0.2158037573, -0.0638541728, -1.2914855480) * lab;
  lms = lms * lms * lms;
  vec3 c = mat3(4.0767416621, -1.2684380046, -0.0041960863,
                -3.3077115913, 2.6097574011, -0.7034186147,
                0.2309699292, -0.3413193965, 1.7076147010) * lms;
  return toGamma(clamp(c, 0.0, 1.0));
}
vec3 mixOk(vec3 a, vec3 b, float t) { return unoklab(mix(oklab(a), oklab(b), t)); }
`;
