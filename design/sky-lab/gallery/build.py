#!/usr/bin/env python3
"""Turn the review shots into the gallery's images.

    python3 gallery/build.py                 # round one: the skies in gallery/content.json
    python3 gallery/build.py --round 2       # gallery/content-2.json → gallery/dist-2/
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


def wanted(extras=False):
    """(key, path under shots/<sky>/review) for every image the page shows.
    91 a sky: one published version holds 511 files, and six skies must fit.
    `extras` (a sky marked "extras": true in the round's content) adds bedtime in
    the light appearance, on the open Duo and on the slab: 24 more."""
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
        if extras:
            out.append((f'bed-nov-cover-light-{f}', f'bedtime/november/{f}/cover-light-1940-night.png'))
            out.append((f'bed-jul-cover-light-{f}', f'bedtime/july/{f}/cover-light-1940-night.png'))
            out.append((f'bed-nov-spread-dark-{f}', f'bedtime/november/{f}/spread-dark-1940-night.png'))
            out.append((f'bed-nov-iphone-dark-{f}', f'bedtime/november/{f}/iphone-dark-1940-night.png'))
    return out


def paths(round_no):
    """(content file, dist directory) for a round: content.json + dist/ for round one,
    content-<n>.json + dist-<n>/ after that. The images are shared."""
    if round_no == 1:
        return os.path.join(LAB, 'gallery/content.json'), os.path.join(LAB, 'gallery/dist')
    return os.path.join(LAB, f'gallery/content-{round_no}.json'), os.path.join(LAB, f'gallery/dist-{round_no}')


def main():
    args = sys.argv[1:]
    round_no = 1
    if '--round' in args:
        i = args.index('--round')
        round_no = int(args[i + 1])
        del args[i:i + 2]
    content_path, dist = paths(round_no)
    content = json.load(open(content_path)) if os.path.exists(content_path) else None
    extras = {sky['id'] for sky in content['skies'] if sky.get('extras')} if content else set()
    text = open(os.path.join(LAB, 'skies/index.js')).read()
    listed = re.findall(r"'([a-z0-9-]+)'", text.split('export const skies')[1])
    skies = args or ([sky['id'] for sky in content['skies']] if content else listed)
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
        for key, rel in wanted(sky in extras):
            if sky == 'baseline' and not key.startswith(('day-', 'bare-')):
                continue
            src = os.path.join(root, rel)
            if not os.path.exists(src):
                missing.append(key)
                continue
            dst = os.path.join(out_dir, key + '.webp')
            if not os.path.exists(dst) or os.path.getmtime(dst) < os.path.getmtime(src):
                Image.open(src).convert('RGB').save(dst, 'WEBP', quality=90, method=4)
            have.append(key)
            size += os.path.getsize(dst)
        manifest[sky] = have
        total += size
        print(f'{sky}: {len(have)} images, {size / 1e6:.1f} MB' + (f', MISSING {len(missing)}: {missing[:6]}…' if missing else ''))
    json.dump(manifest, open(manifest_path, 'w'), indent=0)
    print(f'total {total / 1e6:.1f} MB → gallery/img/, gallery/manifest.json')
    assemble(manifest, content, dist)


def assemble(manifest, content, dist):
    """gallery/index.html + the round's content + the manifest → <dist>/index.html,
    and <dist>/files.json: the page's images, in publish-sized groups."""
    if content is None:
        print('no content file for this round yet: page not assembled')
        return
    page = open(os.path.join(LAB, 'gallery/index.html')).read()
    if content['page'].get('tabTitle'):
        page = re.sub(r'<title>[^<]*</title>', f"<title>{content['page']['tabTitle']}</title>", page, count=1)
    shown = {sky['id']: manifest.get(sky['id'], []) for sky in content['skies']}
    for name, value in (('PAGE', content['page']), ('SKIES', content['skies']), ('MANIFEST', shown)):
        head, rest = page.split(f'/*{name}*/', 1)
        _, tail = rest.split('/*END*/', 1)
        page = head + json.dumps(value, ensure_ascii=False) + tail
    os.makedirs(dist, exist_ok=True)
    open(os.path.join(dist, 'index.html'), 'w').write(page)
    groups, group, count, size = [], [], 0, 0
    for sky, keys in shown.items():
        for key in keys:
            rel = f'img/{sky}/{key}.webp'
            weight = os.path.getsize(os.path.join(LAB, 'gallery', rel))
            if count + 1 > 240 or size + weight > 56e6:
                groups.append(group); group, count, size = [], 0, 0
            group.append({'path': rel}); count += 1; size += weight
    if group:
        groups.append(group)
    json.dump(groups, open(os.path.join(dist, 'files.json'), 'w'))
    files = sum(len(v) for v in shown.values())
    print(f'{os.path.relpath(dist, LAB)}/index.html assembled: {len(content["skies"])} skies, {files} images in {len(groups)} publish group(s), {len(page) / 1024:.0f} KB')


if __name__ == '__main__':
    main()
