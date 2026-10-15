import os, sys, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu_game import *
exe = os.path.abspath(sys.argv[1]); stop_ip = int(sys.argv[2], 16); n = int(sys.argv[3])
g = Game(exe)
c = g.cpu
os.chdir(os.path.dirname(exe))
hist = collections.deque(maxlen=int(sys.argv[4]) if len(sys.argv) > 4 else 80)
while c.icount < n:
    hist.append((c.s[1], c.ip, c.s[3], c.r[0], c.r[1], c.r[2], c.r[3], c.r[4], c.r[5], c.r[6], c.r[7], c.s[0]))
    c.step()
    if c.s[1] == LOAD_SEG and c.ip == stop_ip and c.icount > 100000:
        break
    if c.icount >= g.next_tick:
        g.next_tick += g.tick_period
        g.tick()
for h in hist:
    print('%04X:%04X ds=%04X ax=%04X cx=%04X dx=%04X bx=%04X sp=%04X bp=%04X si=%04X di=%04X es=%04X' % h)
