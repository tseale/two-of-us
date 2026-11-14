#!/usr/bin/env python3
"""Home's sky textures (TwoOfUs/Assets.xcassets/Sky): soft cumulus clouds and a
wisp, each lit three ways (dawn, day, dusk) for SkyBackground to crossfade
between, and the fine grain tile laid over the sky so its gradients never band.

Procedural and seeded, so a rerun reproduces the committed PNGs exactly:

    python3 scripts/make_sky_textures.py

Needs numpy and Pillow. Clouds are drawn at 1.25x their largest on-screen size
at @3x, so they stay soft rather than blurry.
"""
import os
import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'TwoOfUs', 'Assets.xcassets', 'Sky')
S = 1.25


def fbm(h, w, rng, octaves=6, base=4, persistence=0.55):
    acc = np.zeros((h, w), np.float32); amp = 1.0; tot = 0
    for o in range(octaves):
        gh = base * 2 ** o; gw = max(2, int(gh * w / h))
        g = rng.random((gh + 1, gw + 1)).astype(np.float32)
        img = Image.fromarray((g * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
        acc += amp * (np.asarray(img, np.float32) / 255 - 0.5); tot += amp; amp *= persistence
    return acc / tot


def blur(a, s):
    """Gaussian blur by FFT (periodic; every texture keeps clear margins)."""
    n, m = a.shape
    fy = np.fft.fftfreq(n)[:, None]; fx = np.fft.fftfreq(m)[None, :]
    return np.real(np.fft.ifft2(np.fft.fft2(a) * np.exp(-2 * np.pi ** 2 * s ** 2 * (fx ** 2 + fy ** 2))))


def cumulus(W, H, seed, n_base, n_mid, n_top, base_y=0.8, span=(0.12, 0.88), height=0.55):
    """A cumulus: a flat base, a body highest in the middle and cauliflower
    lumps on top, each puff lit from above; returns (alpha, shade)."""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    blobs = []
    x0, x1 = span
    for i in range(n_base):
        cx = x0 + (x1 - x0) * (i + 0.5) / n_base + rng.normal(0, 0.02)
        r = rng.uniform(0.09, 0.13)
        blobs.append((cx, base_y - 0.12, r, r * W / H * 0.9, 1.0))
    blobs.append(((x0 + x1) / 2, base_y - 0.07, (x1 - x0) * 0.46, 0.17, 1.0))
    for i in range(n_mid):
        u = (i + 0.5) / n_mid
        cx = x0 + 0.1 + (x1 - x0 - 0.2) * u + rng.normal(0, 0.02)
        r = rng.uniform(0.10, 0.15) * (0.75 + 0.5 * np.sin(np.pi * u))
        blobs.append((cx, base_y - 0.18 - height * 0.45 * np.sin(np.pi * u), r, r * W / H * 0.95, 1.0))
    for i in range(n_top):
        u = rng.uniform(0.2, 0.8)
        cx = x0 + (x1 - x0) * u
        r = rng.uniform(0.045, 0.08)
        blobs.append((cx, base_y - 0.2 - height * 0.62 * np.sin(np.pi * u) + rng.normal(0, 0.03), r, r * W / H, 0.9))
    d = np.zeros((H, W), np.float32); lit = np.zeros((H, W), np.float32)
    for (cx, cy, rx, ry, a) in blobs:
        g = a * np.exp(-(((xx - cx * W) / (rx * W)) ** 2 + ((yy - cy * H) / (ry * H)) ** 2))
        d = np.maximum(d, g)
        lit = np.maximum(lit, g * np.clip(0.55 - 0.65 * (yy - cy * H) / (ry * H), 0, 1))
    by = base_y * H
    d *= 1 / (1 + np.exp((yy - by) / (0.025 * H)))
    dens = d + 0.28 * fbm(H, W, rng, octaves=5, base=3)
    alpha = np.clip((dens - 0.36) / 0.22, 0, 1)
    alpha = blur(alpha * alpha * (3 - 2 * alpha), 2.2 * S)
    puff = blur(lit / max(lit.max(), 1e-6), 6 * S)
    vert = np.clip((yy - (by - height * H)) / (height * H), 0, 1)
    shade = 0.5 * puff + 0.62 * (1 - vert) ** 1.3 + 0.05 * blur(fbm(H, W, rng, 4, 8), 2 * S)
    return np.clip(alpha, 0, 1), np.clip(shade + 0.08, 0, 1)


def save(alpha, shade, lit, shadow, name, max_a=0.97):
    lit = np.array(lit, np.float32); shadow = np.array(shadow, np.float32)
    rgb = shadow + (lit - shadow) * shade[..., None]
    img = np.dstack([np.clip(rgb, 0, 255), np.clip(alpha * max_a, 0, 1)[..., None] * 255]).astype(np.uint8)
    Image.fromarray(img, 'RGBA').save(os.path.join(ROOT, name), optimize=True)


hx = lambda h: [int(h[i:i + 2], 16) for i in (1, 3, 5)]
# (lit tops, shaded undersides) for each light. Hushed to match SkyPalette:
# a fifth of the original colour, the undersides pulled 55 % of the way to the
# page's lightness. (The full-colour originals were FFFFFF/B9C9E6,
# FFF4EC/D8AEBE and FFEFE8/BFA1CF.)
LIGHTS = {
    'day': (hx('#FFFFFF'), hx('#DCDFE5')),
    'dawn': (hx('#F8F6F4'), hx('#E0D7DA')),
    'dusk': (hx('#F5F2F0'), hx('#D7D1DA')),
}
CLOUDS = {  # SkyPalette.cloudArt, in order
    1: dict(W=560, H=310, seed=3, n_base=5, n_mid=5, n_top=7, base_y=0.84, height=0.5),
    2: dict(W=400, H=250, seed=44, n_base=3, n_mid=3, n_top=4, span=(0.18, 0.82), base_y=0.84, height=0.5),
    3: dict(W=640, H=250, seed=27, n_base=7, n_mid=6, n_top=6, height=0.36, span=(0.08, 0.92), base_y=0.84),
}


def main():
    for k, spec in CLOUDS.items():
        spec = dict(spec)
        W, H, seed = round(spec.pop('W') * S), round(spec.pop('H') * S), spec.pop('seed')
        a, sh = cumulus(W, H, seed, **spec)
        for t, (lit, shadow) in LIGHTS.items():
            save(a, sh, lit, shadow, f'SkyCloud{k}{t.title()}.imageset/sky-cloud-{k}-{t}.png')
    rng = np.random.default_rng(5)
    W, H = round(640 * S), round(120 * S)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    d = np.exp(-(((xx - 0.5 * W) / (0.38 * W)) ** 2 + ((yy - 0.5 * H) / (0.15 * H)) ** 2))
    n = fbm(H, W, rng, octaves=5, base=2)
    alpha = blur(np.clip((d + 0.9 * n * d - 0.18) / 0.5, 0, 1), 3 * S)
    for t, (lit, shadow) in LIGHTS.items():
        save(alpha, np.ones_like(alpha) * 0.92, lit, shadow, f'SkyWisp{t.title()}.imageset/sky-wisp-{t}.png', max_a=0.7)
    # Grain: a 256 px tile of mid-grey noise, used at @3x under a soft-light blend.
    rng = np.random.default_rng(11)
    g = blur(rng.normal(0, 1, (256, 256)), 0.45)
    g = g / g.std() * 34 + 128
    Image.fromarray(np.clip(g, 0, 255).astype(np.uint8), 'L').save(
        os.path.join(ROOT, 'SkyGrain.imageset', 'sky-grain@3x.png'), optimize=True)


if __name__ == '__main__':
    main()
