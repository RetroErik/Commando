"""Snapshot gameplay of a given level in any build: python snap_level.py EXE LEVEL OUTPNG [extra_instr]"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu_game import *
exe, lvl, out = os.path.abspath(sys.argv[1]), int(sys.argv[2]), os.path.abspath(sys.argv[3])
extra = int(sys.argv[4]) if len(sys.argv) > 4 else 6_000_000
g = Game(exe)
os.chdir(os.path.dirname(exe))
c = g.cpu
ds_seg = struct.unpack_from('<H', c.mem, LOAD_SEG * 16 + 0xA7)[0]
g.run(3_300_000)
g.press(0x3920)
done = False
limit = c.icount + 4_000_000
while not done and c.icount < limit:
    g.run(1)
    if c.s[1] == LOAD_SEG and c.ip == 0x35AC:
        c.mem[ds_seg * 16 + 0xFB58] = lvl
        done = True
g.run(extra)
g.frame().convert('RGB').save(out)
print('ok', done, g.video_mode)
