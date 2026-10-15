"""Build the sprite catalog, check odd-x variants, and write the original-CGA atlases + extracted raw data."""
import os, sys, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cgagfx import *
from scan_sprites import scan, parse_abs
from defs import classify, EXCLUDE, EXTRA

EXTRACT = os.path.join(HERE, 'extracted')
os.makedirs(os.path.join(EXTRACT, 'sprites'), exist_ok=True)


def all_sprites():
    found = {s['d']: s for s in scan()}
    for d in EXTRA:
        s = parse_abs(DS_BASE + d, 1)
        found[d] = s
    out = []
    for d in sorted(found):
        if d in EXCLUDE:
            continue
        s = found[d]
        sp = sprite_at(s['a'])
        grp, label, conf = classify(d)
        sp.update(group=grp, label=label, confidence=conf, end=s['end'])
        out.append(sp)
    return out


def odd_is_shifted_even(sp):
    """True if the odd-x image equals the even image shifted right by 2 pixels (so one VGA bitmap serves both)."""
    if not sp['odd_off']:
        return None
    ev, od = sp['even'], sp['odd']
    if len(ev) != len(od):
        return False
    for ry, (a, b) in enumerate(zip(ev, od)):
        shifted = [None, None] + list(a)
        bb = list(b)
        n = max(len(shifted), len(bb))
        shifted += [None] * (n - len(shifted))
        bb += [None] * (n - len(bb))
        for x in range(n):
            if shifted[x] != bb[x]:
                return False
    return True


if __name__ == '__main__':
    sprites = all_sprites()
    cat = []
    shifted_ok = 0
    shifted_bad = []
    for sp in sprites:
        s = odd_is_shifted_even(sp)
        if s is True:
            shifted_ok += 1
        elif s is False:
            shifted_bad.append('%04X' % sp['d'])
        raw = IMG[sp['a']: sp['end']]
        name = 'spr_%04X' % sp['d']
        open(os.path.join(EXTRACT, 'sprites', name + '.bin'), 'wb').write(raw)
        cat.append(dict(id='%04X' % sp['d'], image_offset='%05X' % sp['a'], exe_file_offset='%05X' % (sp['a'] + 0x200),
                        width_px=sp['w'] * 4, height=sp['h'], width_bytes=sp['w'], odd_variant=bool(sp['odd_off']),
                        odd_width_bytes=sp['ow'], record_bytes=len(raw), group=sp['group'], label=sp['label'],
                        confidence=sp['confidence'], odd_is_even_shifted_2px=s))
    json.dump(cat, open(os.path.join(EXTRACT, 'sprites_catalog.json'), 'w'), indent=1)
    print(len(sprites), 'sprites;', 'odd == even shifted 2px:', shifted_ok, 'mismatch:', shifted_bad)
    from collections import Counter
    print(Counter(s['group'] for s in sprites))
