"""Collect every scenery record passed to the ground-strip builder (50E4) over a long run of one level.
Usage: trace_records.py LEVEL INSTR   -> analysis/records_levelN.txt"""
import os, sys, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu_game import *

lvl = int(sys.argv[1])
total = int(sys.argv[2])
g = Game(os.path.join(ROOT, 'COMMANDO.EXE'))
c = g.cpu
g.run(4_000_000)
g.press(0x3920)
DS_SEG = LOAD_SEG + 0x835
DS = DS_SEG * 16
patched = False
limit = c.icount + 3_000_000
while c.icount < limit and not patched:
    c.step()
    if c.s[1] == LOAD_SEG and c.ip == 0x35AC:
        c.mem[DS + 0xFB58] = lvl
        patched = True
recs = {}
end = c.icount + total
mem = c.mem
next_snap = c.icount + 5_000_000
frames = 0
while c.icount < end:
    c.step()
    if c.s[1] == LOAD_SEG and c.ip == 0x50E4:
        sp = (c.s[2] << 4) + c.r[4]
        rec = c.rw(sp + 2)
        b = bytes(mem[DS + rec: DS + rec + 14])
        key = b.hex()
        recs[key] = recs.get(key, 0) + 1
    if c.icount >= c.icount and c.icount > 0 and g.ticks and c.icount % 1 == 0 and c.icount >= next_snap:
        next_snap += 5_000_000
        g.cga_frame().convert('RGB').save(os.path.join(HERE, 'analysis', 'lv%d_t%03d.png' % (lvl, frames)))
        frames += 1
    if c.icount >= g.next_tick:
        g.next_tick += g.tick_period
        g.tick()
out = os.path.join(HERE, 'analysis', 'records_level%d.txt' % lvl)
with open(out, 'w') as f:
    for k, n in sorted(recs.items()):
        f.write('%s %d\n' % (k, n))
open(os.path.join(HERE, 'analysis', 'ds_level%d_end.bin' % lvl), 'wb').write(bytes(mem[DS:DS + 0x10000]))
print('records', len(recs), 'icount', c.icount)
