#!/usr/bin/env python3
"""
Two of Us — app icon concept generator.

Renders two directions ("Bottle on teal" and "Three-dot trinity") as 1024x1024
masters following Apple's app-icon guidelines: full-bleed square, no pre-applied
corner rounding, no text, key content centered in the safe area, sRGB, flattened
(no alpha). Everything is drawn at 4x supersample and downsampled for clean AA.

Usage: python3 design/icon/generate_icons.py
Output: design/icon/out/*.png
"""

import os
import math
from PIL import Image, ImageDraw, ImageFilter

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


# ---- build the shipping AppIcon variants into the asset catalog -------------
def build_appicon():
    repo = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    icon_dir = os.path.join(repo, "TwoOfUs", "Assets.xcassets", "AppIcon.appiconset")
    os.makedirs(icon_dir, exist_ok=True)

    # default + dark: trinity on solid black, flattened (no alpha)
    finalize(make_trinity("dark"), os.path.join(icon_dir, "icon-1024.png"), BLACK)
    finalize(make_trinity("dark"), os.path.join(icon_dir, "icon-1024-dark.png"), BLACK)
    # tinted: grayscale dots on transparent (system applies the user's tint)
    tint = make_trinity("tinted").resize((SIZE, SIZE), Image.LANCZOS)
    tint.save(os.path.join(icon_dir, "icon-1024-tinted.png"), "PNG")
    print("wrote AppIcon variants ->", os.path.relpath(icon_dir, repo))


def build_launch_logo():
    """Centered trinity mark (transparent) for the launch screen, @1x/2x/3x."""
    repo = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    logo_dir = os.path.join(repo, "TwoOfUs", "Assets.xcassets", "LaunchLogo.imageset")
    os.makedirs(logo_dir, exist_ok=True)
    master = make_trinity("transparent").resize((SIZE, SIZE), Image.LANCZOS)
    pt = 240  # displayed point size
    for scale, suffix in ((1, ""), (2, "@2x"), (3, "@3x")):
        px = pt * scale
        master.resize((px, px), Image.LANCZOS).save(
            os.path.join(logo_dir, f"launch-logo{suffix}.png"), "PNG")
    print("wrote LaunchLogo ->", os.path.relpath(logo_dir, repo))


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
    masters["bottle-1024.png"] = finalize(make_bottle("teal"), "bottle-1024.png")[1]
    masters["bottle-dark-1024.png"] = finalize(make_bottle("dark"), "bottle-dark-1024.png", BLACK)[1]
    masters["trinity-1024.png"] = finalize(make_trinity("dark"), "trinity-1024.png", BLACK)[1]
    masters["trinity-dark-1024.png"] = finalize(make_trinity("flat"), "trinity-dark-1024.png", BLACK)[1]

    # contact sheet: large pair on top, small rounded thumbs below
    pad = 60
    big = 460
    small = 120
    cols = [masters["bottle-1024.png"], masters["trinity-1024.png"]]
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
    # the two dark variants too
    for im in [masters["bottle-dark-1024.png"], masters["trinity-dark-1024.png"]]:
        t = rounded_thumb(im, small)
        sheet.paste(t, (xx, row_y), t)
        xx += small + 30
    sheet.save(os.path.join(OUT, "preview-contact-sheet.png"), "PNG")

    build_appicon()
    build_launch_logo()

    print("wrote:")
    for f in sorted(os.listdir(OUT)):
        print("  design/icon/out/" + f)


if __name__ == "__main__":
    main()
