import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu_game import *
exe = os.path.abspath(sys.argv[1]); lvl = int(sys.argv[2]); out = os.path.abspath(sys.argv[3]); step = int(sys.argv[4]); count = int(sys.argv[5])
g = Game(exe); c = g.cpu
os.chdir(os.path.dirname(exe))
ds_seg = struct.unpack_from('<H', c.mem, LOAD_SEG * 16 + 0xA7)[0]
g.run(3_300_000); g.press(0x3920)
done = False
while not done:
    g.run(1)
    if c.s[1] == LOAD_SEG and c.ip == 0x35AC:
        c.mem[ds_seg * 16 + 0xFB58] = lvl; done = True
for i in range(count):
    g.run(step)
    g.frame().convert('RGB').save('%s_%02d.png' % (out, i))
print('ok')