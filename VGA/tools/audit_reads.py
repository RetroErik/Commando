"""Which instructions READ the scenery layers, RAM screen and sprite data?  (collision-dependency audit)"""
import os, sys, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu_game import *

lvl = int(sys.argv[1]) if len(sys.argv) > 1 else 1
g = Game(os.path.join(ROOT, 'COMMANDO.EXE'))
c = g.cpu
g.run(4_000_000)
g.press(0x3920)
DS = (LOAD_SEG + 0x835) * 16
patched = False
limit = c.icount + 3_000_000
while c.icount < limit and not patched:
    c.step()
    if c.s[1] == LOAD_SEG and c.ip == 0x35AC:
        c.mem[DS + 0xFB58] = lvl
        patched = True
g.run(2_000_000)
seg = g.screen_mem_blocks[0][0]
regions = [('ground56 DS:DCE2', DS + 0xDCE2, DS + 0xDCE2 + 0x1C00),
           ('layer28 DS:CD60', DS + 0xCD60, DS + 0xCD60 + 0xE00),
           ('RAM screen %04X' % seg, seg * 16, seg * 16 + 0x4000),
           ('sprite data DS:1B52-9100', DS + 0x1B52, DS + 0x9100),
           ('level data DS:9454-CC54', DS + 0x9454, DS + 0xCC54),
           ('video B800', 0xB8000, 0xBC000)]
hist = {r[0]: collections.Counter() for r in regions}


def hook(a, size):
    for name, lo, hi in regions:
        if lo <= a < hi:
            hist[name][c.cur_ip] += size
            return


c.rwatch = (min(r[1] for r in regions), max(r[2] for r in regions))
c.read_hook = hook
g.run(int(sys.argv[2]) if len(sys.argv) > 2 else 2_000_000)
for name, _, _ in regions:
    print(name)
    for ip, n in [x for x in hist[name].most_common() if not (0x7F00 <= x[0] <= 0x8100 or 0x7C00 <= x[0] <= 0x7C90)][:25]:
        print('   %04X  %d' % (ip, n))

