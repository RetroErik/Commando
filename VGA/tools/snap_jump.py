"""Test-only: jump the map row counter (DS:CD5E) forward so later scenery is built, then snapshot.
python snap_jump.py EXE LEVEL OUTPREFIX row1,row2,..."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu_game import *
exe = os.path.abspath(sys.argv[1]); lvl = int(sys.argv[2]); out = os.path.abspath(sys.argv[3]); rows = [int(x) for x in sys.argv[4].split(',')]
g = Game(exe); c = g.cpu
os.chdir(os.path.dirname(exe))
ds_seg = struct.unpack_from('<H', c.mem, LOAD_SEG * 16 + 0xA7)[0]
DS = ds_seg * 16
g.run(3_300_000); g.press(0x3920)
done = False
while not done:
    g.run(1)
    if c.s[1] == LOAD_SEG and c.ip == 0x35AC:
        c.mem[DS + 0xFB58] = lvl; done = True
g.run(2_500_000)
for r in rows:
    for _ in range(12):                      # keep the hero near the top so the original code scrolls the map
        c.mem[DS + 0xFB9F] = 0x40
        g.run(100_000)
    g.frame().convert('RGB').save('%s_%03d.png' % (out, r))
    print('row', r, 'cd5e now', struct.unpack_from('<H', c.mem, DS + 0xCD5E)[0])
