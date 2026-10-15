"""How often does the original game start a sound effect (CS:658C != 0) during gameplay?"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu_game import *
exe = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(ROOT, 'COMMANDO.EXE')
g = Game(exe); c = g.cpu
os.chdir(os.path.dirname(exe))
CS = LOAD_SEG * 16
g.run(3_300_000)
g.press(0x3920)
prev = 0; starts = []
end = c.icount + int(sys.argv[2] if len(sys.argv) > 2 else 20_000_000)
while c.icount < end:
    c.step()
    if c.icount >= g.next_tick:
        g.next_tick += g.tick_period
        g.tick()
    cur = c.rw(CS + 0x658C)
    if cur and not prev:
        starts.append((c.icount, cur, c.rw(CS + 0x658E)))
    prev = cur
print('effect starts:', len(starts), starts[:8])
