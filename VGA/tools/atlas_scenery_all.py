"""Extract ALL distinct scenery display bitmaps of levels 1-3 and render a CGA atlas (atlas/scenery_all_cga.png)."""
import os, sys, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cgagfx import HERE, CGA_PAL
from enum_scenery import enumerate_level
from atlas_orig import atlas

EX = os.path.join(HERE, 'extracted')


def all_bitmaps():
    out = []
    for n in (1, 2, 3):
        ds, nrows, tab, recs = enumerate_level(n)
        best = {}
        for (p, wd, rows, orf), uses in recs.items():
            if wd < 2:
                continue
            k = (p, wd, orf)
            if k not in best or best[k][0] < rows:
                best[k] = (rows, sum(len(u) for u in [uses]))
        for (p, wd, orf), (rows, _) in sorted(best.items()):
            raw = bytes(ds[p:p + wd * rows])
            out.append(dict(level=n, ptr=p, width=wd, rows=rows, orflag=orf, raw=raw))
    return out


def grid(b):
    return [[(b['raw'][y * b['width'] + x // 4] >> (6 - 2 * (x % 4))) & 3 for x in range(b['width'] * 4)] for y in range(b['rows'])]


if __name__ == '__main__':
    bm = all_bitmaps()
    cells = [('L%d DS:%04X %dx%d %s' % (b['level'], b['ptr'], b['width'] * 4, b['rows'], 'OR' if b['orflag'] else 'copy'), grid(b)) for b in bm]
    print(len(bm), 'bitmaps', atlas(cells, os.path.join(HERE, 'atlas', 'scenery_all_cga.png'), 6, 2, 'ALL scenery display bitmaps (levels 1-3, from the level data)'))
    json.dump([{k: (v if k != 'raw' else None) for k, v in b.items()} for b in bm], open(os.path.join(EX, 'scenery_all_catalog.json'), 'w'), indent=1)
