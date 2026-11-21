#!/usr/bin/env python3
"""Turn the review shots into the gallery's images.

    python3 gallery/build.py                 # every sky in skies/index.js that has shots
    python3 gallery/build.py true-light      # just these

Reads shots/<sky>/review/…, writes gallery/img/<sky>/<key>.webp and
gallery/manifest.json ({sky: [key, …]}), then assembles gallery/dist/index.html
from gallery/index.html (the page) and gallery/content.json (the words).
gallery/img/, gallery/dist/ and the manifest are not committed.
"""
import json, os, re, sys
from PIL import Image

LAB = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TIMES = ['0650', '0930', '1230', '1610', '1640', '1730', '2100', '0300']
BED = ['t0', 't1_6', 't3', 't5', 't9', 't40']
OPEN = ['t0', 't0_45', 't1_1', 't1_8', 't3']
SEASONS = {'autumn': '1756', 'winter': '1628', 'spring': '1929', 'summer': '2015'}   # 14 min before sunset


def wanted():
    """(key, path under shots/<sky>/review) for every image the page shows.
    91 a sky: one published version holds 511 files, and six skies must fit."""
    out = []
    for scheme in ('light', 'dark'):
        for t in TIMES:
            for device in ('cover', 'spread'):
                out.append((f'day-{device}-{scheme}-{t}', f'day/{device}-{scheme}-{t}.png'))
        for t in ('0650', '1230', '1610', '2100'):
            out.append((f'day-iphone-{scheme}-{t}', f'day/iphone-{scheme}-{t}.png'))
        for t in ('0650', '1610', '1640', '2100'):
            out.append((f'bare-spread-{scheme}-{t}', f'bare/spread-{scheme}-{t}.png'))
        for f in OPEN:
            out.append((f'open-golden-{scheme}-{f}', f'open/golden/{f}/spread-{scheme}-1612.png'))
        for name, pre in SEASONS.items():
            out.append((f'season-{name}-bare-{scheme}', f'seasons/{name}-bare/spread-{scheme}-{pre}.png'))
            out.append((f'season-{name}-cover-{scheme}', f'seasons/{name}/cover-{scheme}-{pre}.png'))
    for f in OPEN:
        out.append((f'open-night-dark-{f}', f'open/night/{f}/spread-dark-2100-night.png'))
    for f in BED:
        out.append((f'bed-nov-cover-dark-{f}', f'bedtime/november/{f}/cover-dark-1940-night.png'))
        out.append((f'bed-jul-cover-dark-{f}', f'bedtime/july/{f}/cover-dark-1940-night.png'))
    return out


def main():
    text = open(os.path.join(LAB, 'skies/index.js')).read()
    listed = re.findall(r"'([a-z0-9-]+)'", text.split('export const skies')[1])
    skies = sys.argv[1:] or listed
    manifest_path = os.path.join(LAB, 'gallery/manifest.json')
    manifest = json.load(open(manifest_path)) if os.path.exists(manifest_path) else {}
    total = 0
    for sky in skies:
        root = os.path.join(LAB, 'shots', sky, 'review')
        if not os.path.isdir(root):
            print(f'{sky}: no review shots, skipped')
            continue
        out_dir = os.path.join(LAB, 'gallery/img', sky)
        os.makedirs(out_dir, exist_ok=True)
        have, missing, size = [], [], 0
        for key, rel in wanted():
            if sky == 'baseline' and not key.startswith(('day-', 'bare-')):
                continue
            src = os.path.join(root, rel)
            if not os.path.exists(src):
                missing.append(key)
                continue
            dst = os.path.join(out_dir, key + '.webp')
            if not os.path.exists(dst) or os.path.getmtime(dst) < os.path.getmtime(src):
                Image.open(src).convert('RGB').save(dst, 'WEBP', quality=90, method=6)
            have.append(key)
            size += os.path.getsize(dst)
        manifest[sky] = have
        total += size
        print(f'{sky}: {len(have)} images, {size / 1e6:.1f} MB' + (f', MISSING {len(missing)}: {missing[:6]}…' if missing else ''))
    json.dump(manifest, open(manifest_path, 'w'), indent=0)
    print(f'total {total / 1e6:.1f} MB → gallery/img/, gallery/manifest.json')
    assemble(manifest)


def assemble(manifest):
    """gallery/index.html + gallery/content.json + the manifest → gallery/dist/index.html."""
    content_path = os.path.join(LAB, 'gallery/content.json')
    if not os.path.exists(content_path):
        print('no gallery/content.json yet: page not assembled')
        return
    content = json.load(open(content_path))
    page = open(os.path.join(LAB, 'gallery/index.html')).read()
    shown = {sky['id']: manifest.get(sky['id'], []) for sky in content['skies']}
    for name, value in (('PAGE', content['page']), ('SKIES', content['skies']), ('MANIFEST', shown)):
        head, rest = page.split(f'/*{name}*/', 1)
        _, tail = rest.split('/*END*/', 1)
        page = head + json.dumps(value, ensure_ascii=False) + tail
    os.makedirs(os.path.join(LAB, 'gallery/dist'), exist_ok=True)
    open(os.path.join(LAB, 'gallery/dist/index.html'), 'w').write(page)
    files = sum(len(v) for v in shown.values())
    print(f'gallery/dist/index.html assembled: {len(content["skies"])} skies, {files} images, {len(page) / 1024:.0f} KB')


if __name__ == '__main__':
    main()
