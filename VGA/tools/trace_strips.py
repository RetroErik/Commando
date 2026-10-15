"""Log calls to the ground-strip blitters 5F5D (OR copy) and 6498 (copy) made while building scenery rows."""
import os, sys, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu_game import *

g = Game(os.environ.get('EXE', os.path.join(ROOT, 'COMMANDO.EXE')))
c = g.cpu
g.run(4_000_000)
g.press(0x3920)
DS_SEG = LOAD_SEG + 0x835
CS_SEG = LOAD_SEG
calls = collections.Counter()
srcs = {}
n = 0
limit = c.icount + int(sys.argv[1])
while c.icount < limit:
    c.step()
    if c.s[1] == CS_SEG and c.ip in (0x5F5D, 0x6498):
        sp = (c.s[2] << 4) + c.r[4]
        # after "push bp / mov bp,sp" the args are at [sp+2..]; at function entry: ret at [sp], args at [sp+2],[sp+4],[sp+6]
        d, s, cnt = c.rw(sp + 2), c.rw(sp + 4), c.rw(sp + 6)
        ret = c.rw(sp)
        calls[(c.ip, ret, s, cnt)] += 1
for (fn, ret, s, cnt), k in sorted(calls.items(), key=lambda kv: kv[0][2]):
    print('fn %04X from %04X src DS:%04X count %d  x%d' % (fn, ret, s, cnt, k))
