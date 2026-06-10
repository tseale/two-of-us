#!/usr/bin/env python3
"""
Two of Us — app icon + launch artwork generator.

The shipping mark is "Two of Us": two overlapping circles (the two parents) that
screen-blend into a bright shared glow, with a warm point of light (the baby,
Miller) at the heart. Earlier explorations ("Bottle on teal", "Three-dot trinity")
are kept for the preview contact sheet.

All masters follow Apple's app-icon guidelines: full-bleed square, no pre-applied
corner rounding, no text, key content centered in the safe area, sRGB, flattened
(no alpha). Everything is drawn at 4x supersample and downsampled for clean AA.

From the single source geometry this writes, in one run:
  - the AppIcon.appiconset PNG fallback (default / dark / tinted),
  - the LaunchLogo imageset used by the static launch screen, and
  - the layered PNGs for the Icon Composer `.icon` (design/icon/TwoOfUs.icon).

Usage: python3 design/icon/generate_icons.py
Output: design/icon/out/*.png  (+ asset catalogs & the .icon scaffold)
"""

import os
import math
from PIL import Image, ImageDraw, ImageFilter, ImageChops

# ---- config -----------------------------------------------------------------
SIZE = 1024
SS = 4                       # supersample factor
S = SIZE * SS               # working canvas size
OUT = os.path.join(os.path.dirname(__file__), "out")
os.makedirs(OUT, exist_ok=True)

# brand palette (from docs/DESIGN.md + DesignSystem/Colors.swift)
TEAL = (0x5A, 0xC8, 0xB8)
TEAL_DEEP = (0x2E, 0x8D, 0x80)
PERIWINKLE = (0x8E, 0x8E, 0xFF)
AMBER = (0xF5, 0xB9, 0x71)
BLACK = (0x00, 0x00, 0x00)
DARK_CARD = (0x1C, 0x1C, 0x1E)
WHITE = (0xFF, 0xFF, 0xFF)
MILK = (0xFD, 0xFB, 0xF4)


def hexd(c):
    return c if len(c) == 4 else (c[0], c[1], c[2], 255)


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(len(a)))


# ---- gradient helpers -------------------------------------------------------
def linear_gradient(size, top, bottom):
    """Vertical linear gradient, fully opaque."""
    w, h = size
    base = Image.new("RGB", (1, h))
    px = base.load()
    for y in range(h):
        px[0, y] = lerp(top, bottom, y / max(1, h - 1))
    return base.resize((w, h)).convert("RGBA")


def radial_gradient(size, inner, outer, center=None, radius=None):
    """Radial gradient from inner (center) to outer (edge)."""
    w, h = size
    if center is None:
        center = (w / 2, h * 0.42)
    if radius is None:
        radius = math.hypot(w, h) * 0.62
    img = Image.new("RGB", (w, h))
    px = img.load()
    cx, cy = center
    for y in range(h):
        for x in range(w):
            d = math.hypot(x - cx, y - cy) / radius
            px[x, y] = lerp(inner, outer, min(1.0, d))
    return img.convert("RGBA")


def rounded_rect_mask(size, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1],
                                        radius=radius, fill=255)
    return m


# ---- shape helpers ----------------------------------------------------------
def soft_shadow(layer, blur, offset=(0, 0), color=(0, 0, 0, 110)):
    """Return a blurred shadow image from a layer's alpha."""
    a = layer.split()[3]
    sh = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    tint = Image.new("RGBA", layer.size, color)
    sh.paste(tint, offset, a)
    return sh.filter(ImageFilter.GaussianBlur(blur))


def gloss(layer_size, box, strength=70):
    """A soft elliptical top highlight inside box -> RGBA overlay."""
    g = Image.new("RGBA", layer_size, (0, 0, 0, 0))
    d = ImageDraw.Draw(g)
    x0, y0, x1, y1 = box
    d.ellipse([x0, y0, x1, y1], fill=(255, 255, 255, strength))
    return g.filter(ImageFilter.GaussianBlur((x1 - x0) * 0.12))


# ---- concept 1: bottle on teal (flat / minimal) ----------------------------
def make_bottle(bg_mode="teal"):
    if bg_mode == "teal":
        bg = linear_gradient((S, S), lerp(TEAL, WHITE, 0.06), TEAL)
    else:  # dark
        bg = Image.new("RGBA", (S, S), hexd(BLACK))

    img = bg.copy()

    # --- bottle geometry (centered, within safe area) ---
    cx = S / 2
    body_w = S * 0.40
    body_h = S * 0.46
    body_top = S * 0.36
    body_left = cx - body_w / 2
    body_right = cx + body_w / 2
    body_bottom = body_top + body_h
    body_r = body_w * 0.30

    # collar + nipple
    collar_w = body_w * 0.58
    collar_h = S * 0.05
    collar_top = body_top - collar_h
    nipple_w = body_w * 0.30
    nipple_h = S * 0.085
    nipple_top = collar_top - nipple_h

    bottle = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    bd = ImageDraw.Draw(bottle)

    body_fill = MILK if bg_mode == "teal" else WHITE

    # nipple (rounded dome)
    bd.rounded_rectangle([cx - nipple_w / 2, nipple_top, cx + nipple_w / 2, collar_top + collar_h * 0.5],
                         radius=nipple_w * 0.45, fill=hexd(body_fill))
    # collar ring
    bd.rounded_rectangle([cx - collar_w / 2, collar_top, cx + collar_w / 2, body_top + collar_h * 0.3],
                         radius=collar_h * 0.5, fill=hexd(body_fill))
    # body
    bd.rounded_rectangle([body_left, body_top, body_right, body_bottom],
                         radius=body_r, fill=hexd(body_fill))

    # single milk fill (lower portion) — one flat teal block, no ticks/gloss
    fill_top = body_top + body_h * 0.44
    fill = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(fill).rounded_rectangle(
        [body_left, fill_top, body_right, body_bottom], radius=body_r, fill=hexd(TEAL))
    body_mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(body_mask).rounded_rectangle(
        [body_left, body_top, body_right, body_bottom], radius=body_r, fill=255)
    fill.putalpha(Image.composite(fill.split()[3], Image.new("L", (S, S), 0), body_mask))
    bottle.alpha_composite(fill)

    img.alpha_composite(bottle)
    return img


# ---- concept 2: three-dot trinity (flat) -----------------------------------
def _trinity_points():
    cx, cy = S / 2, S / 2
    r = S * 0.15                       # dot radius
    spread = S * 0.205                 # distance from center
    # top, bottom-left, bottom-right (triangle)
    return r, [
        (cx, cy - spread * 1.02, TEAL),
        (cx - spread * 0.90, cy + spread * 0.60, PERIWINKLE),
        (cx + spread * 0.90, cy + spread * 0.60, AMBER),
    ]


def make_trinity(bg_mode="dark"):
    """bg_mode: 'dark'/'flat' -> opaque bg; 'transparent' -> dots only;
    'tinted' -> grayscale dots on transparent (for the iOS tinted variant)."""
    r, pts = _trinity_points()

    if bg_mode == "transparent" or bg_mode == "tinted":
        img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    elif bg_mode == "flat":
        img = Image.new("RGBA", (S, S), hexd(DARK_CARD))
    else:
        img = Image.new("RGBA", (S, S), hexd(BLACK))

    dots = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dd = ImageDraw.Draw(dots)
    for x, y, col in pts:
        if bg_mode == "tinted":
            # luminance-varied grays so the three dots stay distinct once tinted
            lum = int(round(0.299 * col[0] + 0.587 * col[1] + 0.114 * col[2]))
            col = (lum, lum, lum)
        dd.ellipse([x - r, y - r, x + r, y + r], fill=hexd(col))
    img.alpha_composite(dots)
    return img


# ---- concept 3: "two of us" — two parents overlapping, baby at the heart ----
# Two soft circles (the parents) overlap like a Venn; where they meet the colors
# screen-blend into a bright shared glow, and a warm point of light (Miller) rests
# at the heart. No dark negative space, so it reads as togetherness — not an "eye".
# The baby is a warm near-white, deliberately NOT amber (amber is the diaper color
# in the app, so a warm-white point keeps the meaning "a new little light", not poop).
# Drawn as separable layers so the same geometry feeds the flat PNG fallback and the
# Icon Composer .icon export.

# Geometry as (x, y, r) fractions of the canvas S, relative to its center
# (+y points down). Deliberately NOT mirrored: slightly different sizes and a
# gentle vertical stagger keep the overlap from reading as a tidy symmetric almond.
LEFT_C  = (-0.118,  0.052, 0.246)   # periwinkle parent — a little low and left, larger
RIGHT_C = ( 0.126, -0.044, 0.221)   # teal parent — a little high and right, smaller
BABY_C  = ( 0.052, -0.070, 0.073)   # baby — nestled up where they meet, off dead-center

BABY = (0xFF, 0xF4, 0xE8)   # warm near-white — a new little light (not amber)


def _disk(center, r):
    """A filled-circle alpha mask on the working canvas."""
    m = Image.new("L", (S, S), 0)
    cx, cy = center
    ImageDraw.Draw(m).ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    return m


def _colored(mask, color):
    layer = Image.new("RGBA", (S, S), hexd(color))
    layer.putalpha(mask)
    return layer


def _screen(a, b):
    """Photographic 'screen' blend of two RGB colors -> brighter shared tone."""
    return tuple(255 - (255 - a[i]) * (255 - b[i]) // 255 for i in range(3))


def _gray(c):
    l = int(round(0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]))
    return (l, l, l)


def _circle(spec):
    """(x, y, r) fractions of S, relative to center -> (center_px, radius_px)."""
    x, y, r = spec
    return (S / 2 + S * x, S / 2 + S * y), S * r


def make_cradle_layers(tinted=False):
    """Separable foreground layers for Icon Composer: (left_rgba, right_rgba,
    dot_rgba) — two full parent circles plus the baby dot. Icon Composer blends
    the overlapping circles with real glass on device; colors collapse to
    luminance grays when tinted so the system tint reads cleanly."""
    (lc, lr), (rc, rr), (bc, br) = _circle(LEFT_C), _circle(RIGHT_C), _circle(BABY_C)
    lcol, rcol, dcol = (PERIWINKLE, TEAL, BABY) if not tinted else \
        (_gray(PERIWINKLE), _gray(TEAL), _gray(BABY))
    left = _colored(_disk(lc, lr), lcol)
    right = _colored(_disk(rc, rr), rcol)
    dot = _colored(_disk(bc, br), dcol)
    return left, right, dot


def cradle_background(bg_mode="dark"):
    """Opaque background plate. 'dark' -> subtle radial lift on near-black so the
    mark sits in depth (the .icon's glass layers add the real specular on device)."""
    if bg_mode == "transparent":
        return Image.new("RGBA", (S, S), (0, 0, 0, 0))
    if bg_mode == "flat":
        return Image.new("RGBA", (S, S), hexd(DARK_CARD))
    return radial_gradient((S, S), (0x18, 0x18, 0x20), BLACK,
                           center=(S / 2, S * 0.44), radius=S * 0.72)


def make_cradle(bg_mode="dark"):
    """Composited master with a bright screen-blended overlap (no dark hole).
    bg_mode: 'dark'/'flat' opaque bg; 'transparent' mark-only (launch logo);
    'tinted' grayscale on transparent (iOS tinted variant)."""
    tinted = bg_mode == "tinted"
    transparent = bg_mode in ("transparent", "tinted")
    img = cradle_background("transparent" if transparent else bg_mode)

    (lc, lr), (rc, rr), (bc, br) = _circle(LEFT_C), _circle(RIGHT_C), _circle(BABY_C)
    lmask, rmask = _disk(lc, lr), _disk(rc, rr)
    overlap = ImageChops.darker(lmask, rmask)              # intersection (min)
    left_only = ImageChops.subtract(lmask, overlap)
    right_only = ImageChops.subtract(rmask, overlap)

    lcol, rcol, dcol = PERIWINKLE, TEAL, BABY
    blend = _screen(PERIWINKLE, TEAL)                      # bright shared glow
    if tinted:
        lcol, rcol, dcol, blend = _gray(lcol), _gray(rcol), _gray(dcol), _gray(blend)

    def stamp(mask, col):
        img.paste(Image.new("RGBA", (S, S), hexd(col)), (0, 0), mask)

    stamp(left_only, lcol)
    stamp(right_only, rcol)
    stamp(overlap, blend)

    # baby: a soft warm halo then the bright point of light, nestled up off-center
    if not tinted:
        halo = _disk(bc, br * 1.9)
        halo = halo.point(lambda v: v * 95 // 255).filter(ImageFilter.GaussianBlur(S * 0.022))
        img.alpha_composite(_colored(halo, BABY))
    img.alpha_composite(_colored(_disk(bc, br), dcol))
    return img


# ---- build the shipping AppIcon variants into the asset catalog -------------
def build_appicon():
    repo = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    icon_dir = os.path.join(repo, "TwoOfUs", "Assets.xcassets", "AppIcon.appiconset")
    os.makedirs(icon_dir, exist_ok=True)

    # default + dark: cradle on the depth background, flattened (no alpha)
    finalize(make_cradle("dark"), os.path.join(icon_dir, "icon-1024.png"), BLACK)
    finalize(make_cradle("dark"), os.path.join(icon_dir, "icon-1024-dark.png"), BLACK)
    # tinted: grayscale mark on transparent (system applies the user's tint)
    tint = make_cradle("tinted").resize((SIZE, SIZE), Image.LANCZOS)
    tint.save(os.path.join(icon_dir, "icon-1024-tinted.png"), "PNG")
    print("wrote AppIcon variants ->", os.path.relpath(icon_dir, repo))


def build_launch_logo():
    """Centered cradle mark (transparent) for the launch screen, @1x/2x/3x.
    Matches the SwiftUI SplashView start state so the hand-off is seamless."""
    repo = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    logo_dir = os.path.join(repo, "TwoOfUs", "Assets.xcassets", "LaunchLogo.imageset")
    os.makedirs(logo_dir, exist_ok=True)
    master = make_cradle("transparent").resize((SIZE, SIZE), Image.LANCZOS)
    pt = 240  # displayed point size
    for scale, suffix in ((1, ""), (2, "@2x"), (3, "@3x")):
        px = pt * scale
        master.resize((px, px), Image.LANCZOS).save(
            os.path.join(logo_dir, f"launch-logo{suffix}.png"), "PNG")
    print("wrote LaunchLogo ->", os.path.relpath(logo_dir, repo))


def build_icon_layers():
    """Export the separable layers for the Icon Composer `.icon` bundle: a
    full-bleed opaque background plus three transparent foreground layers
    (two parent circles + the baby). These feed design/icon/TwoOfUs.icon/Assets,
    deliberately kept OUT of the compiled `TwoOfUs/` sources so an unfinished
    bundle can't affect the build — open it in Icon Composer on a Mac to tune the
    glass material / appearances, then wire it into the project (see docs)."""
    here = os.path.dirname(__file__)
    repo = os.path.abspath(os.path.join(here, "..", ".."))
    assets = os.path.join(here, "TwoOfUs.icon", "Assets")
    os.makedirs(assets, exist_ok=True)

    def save(img, name):
        img.resize((SIZE, SIZE), Image.LANCZOS).save(os.path.join(assets, name), "PNG")

    bg = cradle_background("dark").convert("RGB").convert("RGBA")
    left, right, dot = make_cradle_layers()
    save(bg, "background.png")
    save(left, "parent-left.png")
    save(right, "parent-right.png")
    save(dot, "baby.png")
    print("wrote Icon Composer layers ->",
          os.path.relpath(assets, repo))


# ---- finalize: downsample + flatten ----------------------------------------
def finalize(img, name, flatten_bg=None):
    out = img.resize((SIZE, SIZE), Image.LANCZOS).convert("RGBA")
    # flatten to remove alpha (Apple requires no alpha on the master)
    bg = Image.new("RGB", (SIZE, SIZE), flatten_bg or (0, 0, 0))
    bg.paste(out, (0, 0), out)
    path = os.path.join(OUT, name)
    bg.save(path, "PNG")
    return path, bg


def rounded_thumb(rgb_img, px, radius_frac=0.225):
    t = rgb_img.resize((px, px), Image.LANCZOS).convert("RGBA")
    m = rounded_rect_mask((px, px), int(px * radius_frac))
    t.putalpha(m)
    return t


# ---- run --------------------------------------------------------------------
def main():
    masters = {}
    masters["cradle-1024.png"] = finalize(make_cradle("dark"), "cradle-1024.png", BLACK)[1]
    masters["cradle-dark-1024.png"] = finalize(make_cradle("flat"), "cradle-dark-1024.png", BLACK)[1]
    masters["trinity-1024.png"] = finalize(make_trinity("dark"), "trinity-1024.png", BLACK)[1]
    masters["bottle-1024.png"] = finalize(make_bottle("teal"), "bottle-1024.png")[1]

    # contact sheet: large pair on top, small rounded thumbs below
    pad = 60
    big = 460
    small = 120
    cols = [masters["cradle-1024.png"], masters["trinity-1024.png"]]
    sheet_w = pad * 3 + big * 2
    sheet_h = pad * 4 + big + small + 70
    sheet = Image.new("RGB", (sheet_w, sheet_h), (0x10, 0x10, 0x12))
    d = ImageDraw.Draw(sheet)
    for i, im in enumerate(cols):
        x = pad + i * (big + pad)
        thumb = rounded_thumb(im, big)
        sheet.paste(thumb, (x, pad), thumb)
    # small home-screen-size row (masked corners)
    label_y = pad * 2 + big
    d.text((pad, label_y), "at home-screen size (~120px, system corner mask):", fill=(0xAA, 0xAA, 0xB0))
    row_y = label_y + 40
    xx = pad
    for im in cols:
        t = rounded_thumb(im, small)
        sheet.paste(t, (xx, row_y), t)
        xx += small + 30
    # the dark-card variant + bottle alt too
    for im in [masters["cradle-dark-1024.png"], masters["bottle-1024.png"]]:
        t = rounded_thumb(im, small)
        sheet.paste(t, (xx, row_y), t)
        xx += small + 30
    sheet.save(os.path.join(OUT, "preview-contact-sheet.png"), "PNG")

    build_appicon()
    build_launch_logo()
    build_icon_layers()

    print("wrote:")
    for f in sorted(os.listdir(OUT)):
        print("  design/icon/out/" + f)


if __name__ == "__main__":
    main()
