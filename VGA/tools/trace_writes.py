"""Trace which instructions write to CGA video RAM and the game's RAM screen buffers during gameplay."""
import os, sys, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu_game import *

g = Game(os.environ.get('EXE', os.path.join(ROOT, 'COMMANDO.EXE')))
c = g.cpu
g.run(4_000_000)
g.press(0x3920)
g.run(2_500_000)
print('allocations (seg, paragraphs):', [(hex(a), hex(b)) for a, b in g.screen_mem_blocks])
lo = min(a for a, b in g.screen_mem_blocks) * 16
hi = 0xBC000
hist = collections.Counter()
regions = {}


def region(a):
    if 0xB8000 <= a < 0xBC000:
        return 'B800'
    for seg, n in g.screen_mem_blocks:
        if seg * 16 <= a < (seg + n) * 16:
            return '%04X' % seg
    return 'other'


def hook(a, size, v):
    hist[(c.cur_ip, region(a))] += size


c.watch = (lo, hi)
c.write_hook = hook
n0 = c.icount
g.run(int(sys.argv[1]) if len(sys.argv) > 1 else 1_500_000)
print('traced instrs', c.icount - n0)
by_ip = collections.defaultdict(lambda: collections.Counter())
for (ip, reg), n in hist.items():
    by_ip[ip][reg] += n
for ip, cnt in sorted(by_ip.items(), key=lambda kv: -sum(kv[1].values()))[:40]:
    print('%04X  %s' % (ip, dict(cnt)))
