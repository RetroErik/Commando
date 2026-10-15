"""Run gameplay for a given level index (ds:fb58) in the emulator; save a screenshot + data segment dump.
Usage: run_level.py N [extra_instr]"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu_game import *

lvl = int(sys.argv[1])
extra = int(sys.argv[2]) if len(sys.argv) > 2 else 2_500_000
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
print('patched', patched, 'icount', c.icount)
g.run(extra)
out = os.path.join(HERE, 'analysis')
g.cga_frame().convert('RGB').save(os.path.join(out, 'level%d.png' % lvl))
open(os.path.join(out, 'ds_level%d.bin' % lvl), 'wb').write(bytes(c.mem[DS:DS + 0x10000]))
print([l for l in g.log if l[0] == 'int13'])
