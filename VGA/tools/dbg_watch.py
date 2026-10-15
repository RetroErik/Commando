import os, sys, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu_game import *
exe = os.path.abspath(sys.argv[1]); n = int(sys.argv[2]); watch = [int(x, 16) for x in sys.argv[3].split(',')]
g = Game(exe)
c = g.cpu
os.chdir(os.path.dirname(exe))
while c.icount < n:
    c.step()
    if c.s[1] == LOAD_SEG and c.ip in watch:
        sp = (c.s[2] << 4) + c.r[4]
        print('hit %04X at icount %d, ret=%04X stack=%s' % (c.ip, c.icount, c.rw(sp), ' '.join('%04X' % c.rw(sp + 2 * i) for i in range(1, 8))))
    if c.icount >= g.next_tick:
        g.next_tick += g.tick_period
        g.tick()
