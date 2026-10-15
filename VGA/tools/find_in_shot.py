import sys, os, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shotidx import *
from cgagfx import IMG, DS_BASE
LIM = 0x115A0
idx = shot_to_idx(sys.argv[1])
x0, x1, y0, y1 = map(int, sys.argv[2:6])
mode = sys.argv[6] if len(sys.argv) > 6 else 'raw'
hits = {}
for y in range(y0, y1):
    for x in range(x0, x1 - 20, 2):
        px = idx[y][x:x + 20]
        if len(set(px)) < 3:
            continue
        bs = bytes((px[i] << 6) | (px[i + 1] << 4) | (px[i + 2] << 2) | px[i + 3] for i in range(0, 20, 4))
        if mode == 'raw':
            pat = re.escape(bs)
        elif mode == 'pair':   # value byte is the 2nd of each (mask,value) pair
            pat = b''.join(b'.' + re.escape(bytes([b])) for b in bs)
        for m in re.finditer(pat, IMG[:LIM], re.S):
            hits.setdefault(m.start(), []).append((y, x))
for p in sorted(hits)[:40]:
    print('img %05X ds %05X  rows %s' % (p, p - DS_BASE, hits[p][:3]))
print(len(hits), 'distinct hits')
