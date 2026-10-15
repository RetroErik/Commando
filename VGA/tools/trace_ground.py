"""Trace writers to the scrolling ground/tree buffers in the data segment during gameplay."""
import os, sys, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu_game import *

g = Game(os.environ.get('EXE', os.path.join(ROOT, 'COMMANDO.EXE')))
c = g.cpu
g.run(4_000_000)
g.press(0x3920)
DS = (LOAD_SEG + 0x835) * 16
lo, hi = DS + 0xCD60, DS + 0xF8E0
hist = collections.Counter()
rows = collections.Counter()


def hook(a, size, v):
    hist[c.cur_ip] += size
    rows[(a - DS) >> 8] += size


c.watch = (lo, hi)
c.write_hook = hook
g.run(int(sys.argv[1]) if len(sys.argv) > 1 else 1_500_000)
for ip, n in hist.most_common(30):
    print('%04X %d' % (ip, n))
print('by 256B block of DS offset:', sorted((k << 8, v) for k, v in rows.items())[:50])

