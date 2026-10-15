import sys, os, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shotidx import *
from cgagfx import IMG, DS_BASE
LIM = 0x115A0
idx = shot_to_idx(sys.argv[1])
x0, x1, y0, y1 = map(int, sys.argv[2:6])
hits = {}
for x in range(x0, x1 - 4, 2):
    for y in range(y0, y1 - 12):
        col = bytes((idx[yy][x] << 6) | (idx[yy][x + 1] << 4) | (idx[yy][x + 2] << 2) | idx[yy][x + 3] for yy in range(y, y + 12))
        if len(set(col)) < 4:
            continue
        for m in re.finditer(re.escape(col), IMG[:LIM], re.S):
            hits.setdefault(m.start(), []).append((y, x))
for p in sorted(hits)[:40]:
    print('img %05X ds %05X  at %s' % (p, p - DS_BASE, hits[p][:3]))
print(len(hits), 'distinct hits')
