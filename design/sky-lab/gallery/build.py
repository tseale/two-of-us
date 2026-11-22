#!/usr/bin/env python3
"""Turn the review shots into the gallery's images.

    python3 gallery/build.py                 # round one: the skies in gallery/content.json
    python3 gallery/build.py --round 2       # gallery/content-2.json → gallery/dist-2/
    python3 gallery/build.py --round 3       # gallery/content-3.json → gallery/dist-3/
    python3 gallery/build.py true-light      # just these

Reads shots/<sky>/review/…, writes gallery/img/<sky>/<key>.webp and
gallery/manifest.json ({sky: [key, …]}), then assembles gallery/dist/index.html
from gallery/index.html (the page) and gallery/content.json (the words).
gallery/img/, gallery/film/, gallery/dist/ and the manifest are not committed.
Films made by tools/film.mjs into gallery/film/<sky>/ are picked up as they are.
"""
import json, os, re, sys
from PIL import Image

LAB = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TIMES = ['0650', '0930', '1230', '1610', '1640', '1730', '2100', '0300']
BED = ['t0', 't1_6', 't3', 't5', 't9', 't40']
OPEN = ['t0', 't0_45', 't1_1', 't1_8', 't3']
NIGHT = ['1940', '2100', '0300']
SEASONS = {'autumn': '1756', 'winter': '1628', 'spring': '1929', 'summer': '2015'}   # 14 min before sunset


def wanted(extras=False, sky=None):
    """(key, path under the sky's review shots) for every image the page shows.
    91 a sky: one published version holds 511 files, and six skies must fit.
    `extras` (a sky marked "extras": true in the round's content) adds bedtime in
    the light appearance, on the open Duo and on the slab: 24 more.
    A sky's entry in the content can also carry
      "bed":   [[frame, label], …]  its own bedtime instants, in place of BED;
      "night": true                 the cards-on frames while a night sleep runs
                                    (asleep/, 7:40, 9:00 and 3:00): 18 more;
      "stills": {key: path}         any other shots, by name (a film's poster, say);
      "bedJuly": "1955"             the minute its July bedtime was shot at (1940 unless said)."""
    sky = sky or {}
    bed = [f for f, _ in sky['bed']] if sky.get('bed') else BED
    july = sky.get('bedJuly') or '1940'
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
    for f in bed:
        out.append((f'bed-nov-cover-dark-{f}', f'bedtime/november/{f}/cover-dark-1940-night.png'))
        out.append((f'bed-jul-cover-dark-{f}', f'bedtime/july/{f}/cover-dark-{july}-night.png'))
        if extras:
            out.append((f'bed-nov-cover-light-{f}', f'bedtime/november/{f}/cover-light-1940-night.png'))
            out.append((f'bed-jul-cover-light-{f}', f'bedtime/july/{f}/cover-light-{july}-night.png'))
            out.append((f'bed-nov-spread-dark-{f}', f'bedtime/november/{f}/spread-dark-1940-night.png'))
            out.append((f'bed-nov-iphone-dark-{f}', f'bedtime/november/{f}/iphone-dark-1940-night.png'))
    if sky.get('night'):
        for scheme in ('light', 'dark'):
            for device in ('cover', 'spread', 'iphone'):
                for t in NIGHT:
                    out.append((f'asleep-{device}-{scheme}-{t}', f'asleep/{device}-{scheme}-{t}-night.png'))
    out += list((sky.get('stills') or {}).items())
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
    config = {sky['id']: sky for sky in content['skies']} if content else {}
    extras = {sky['id'] for sky in content['skies'] if sky.get('extras')} if content else set()
    plain = {sky['id'] for sky in content['skies'] if sky.get('reference')} if content else {'baseline'}
    text = open(os.path.join(LAB, 'skies/index.js')).read()
    listed = re.findall(r"'([a-z0-9-]+)'", text.split('export const skies')[1])
    skies = args or ([sky['id'] for sky in content['skies']] if content else listed)
    manifest_path = os.path.join(LAB, 'gallery/manifest.json' if round_no == 1 else f'gallery/manifest-{round_no}.json')
    manifest = json.load(open(manifest_path)) if os.path.exists(manifest_path) else {}
    total = 0
    for sky in skies:
        # "shots": "<sky>/<folder>" in the content shows another set of shots under this name
        # (an earlier round's, kept beside the current review for comparison)
        root = os.path.join(LAB, 'shots', config.get(sky, {}).get('shots') or os.path.join(sky, 'review'))
        if not os.path.isdir(root):
            print(f'{sky}: no review shots, skipped')
            continue
        out_dir = os.path.join(LAB, 'gallery/img', sky)
        os.makedirs(out_dir, exist_ok=True)
        have, missing, size = [], [], 0
        for key, rel in wanted(sky in extras, config.get(sky)):
            if sky in plain and not key.startswith(('day-', 'bare-')):   # a reference: its days only
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
    print(f'total {total / 1e6:.1f} MB → gallery/img/, {os.path.relpath(manifest_path, LAB)}')
    assemble(manifest, content, dist, pairs(content))


def pairs(content):
    """The before-and-after pictures of the page's "better" section, cut from two sets of
    shots: {"before": "<sky>/<folder>", "after": "<sky>/<folder>", "groups": [{"pairs":
    [{"key", "shot": path under the folder, "crop": [x, y, w, h] in points (optional)}]}]}
    → gallery/img/cmp/<key>-before.webp and -after.webp. Returns their paths."""
    better = (content or {}).get('page', {}).get('better')
    if not better:
        return []
    out_dir = os.path.join(LAB, 'gallery/img/cmp')
    os.makedirs(out_dir, exist_ok=True)
    made, missing = [], []
    for group in better['groups']:
        for pair in group['pairs']:
            for side in ('before', 'after'):
                src = os.path.join(LAB, 'shots', pair.get(side + 'Root') or better[side], pair.get(side + 'Shot') or pair['shot'])
                if not os.path.exists(src):
                    missing.append(f"{pair['key']}-{side}")
                    continue
                image = Image.open(src).convert('RGB')
                if pair.get('crop'):
                    scale = image.width / pair.get('points', {'cover': 466, 'spread': 951, 'iphone': 402}[group.get('device', 'cover')])
                    x, y, w, h = (round(v * scale) for v in pair['crop'])
                    image = image.crop((x, y, x + w, y + h))
                rel = f"img/cmp/{pair['key']}-{side}.webp"
                image.save(os.path.join(LAB, 'gallery', rel), 'WEBP', quality=92, method=4)
                made.append(rel)
    print(f'before and after: {len(made)} pictures' + (f', MISSING {missing}' if missing else ''))
    return made


def assemble(manifest, content, dist, more=()):
    """gallery/index.html + the round's content + the manifest → <dist>/index.html,
    and <dist>/files.json: the page's images, in publish-sized groups."""
    if content is None:
        print('no content file for this round yet: page not assembled')
        return
    page = open(os.path.join(LAB, 'gallery/index.html')).read()
    if content['page'].get('tabTitle'):
        page = re.sub(r'<title>[^<]*</title>', f"<title>{content['page']['tabTitle']}</title>", page, count=1)
    shown = {sky['id']: manifest.get(sky['id'], []) for sky in content['skies']}
    # Films (tools/film.mjs → gallery/film/<sky>/<name>.mp4 and .webm): a sky has the ones on disk in both formats.
    films = {}
    for sky in shown:
        folder = os.path.join(LAB, 'gallery/film', sky)
        names = sorted(f[:-4] for f in os.listdir(folder) if f.endswith('.mp4')) if os.path.isdir(folder) else []
        films[sky] = [n for n in names if os.path.exists(os.path.join(folder, n + '.webm'))]
    for name, value in (('PAGE', content['page']), ('SKIES', content['skies']), ('MANIFEST', shown), ('FILMS', films)):
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
    for rel in more:
        weight = os.path.getsize(os.path.join(LAB, 'gallery', rel))
        if count + 1 > 240 or size + weight > 56e6:
            groups.append(group); group, count, size = [], 0, 0
        group.append({'path': rel}); count += 1; size += weight
    if group:
        groups.append(group)
    # the films go last, in groups of their own, so the images' groups do not move when a film is added
    group, size = [], 0
    for sky, names in films.items():
        for rel in (f'film/{sky}/{n}.{ext}' for n in names for ext in ('mp4', 'webm')):
            weight = os.path.getsize(os.path.join(LAB, 'gallery', rel))
            if size + weight > 56e6:
                groups.append(group); group, size = [], 0
            group.append({'path': rel}); size += weight
    if group:
        groups.append(group)
    json.dump(groups, open(os.path.join(dist, 'files.json'), 'w'))
    files = sum(len(v) for v in shown.values()) + len(more)
    if any(films.values()):
        print('films: ' + ', '.join(f'{sky} {len(n)}' for sky, n in films.items() if n))
    print(f'{os.path.relpath(dist, LAB)}/index.html assembled: {len(content["skies"])} skies, {files} images in {len(groups)} publish group(s), {len(page) / 1024:.0f} KB')


if __name__ == '__main__':
    main()
