"""Calibrate the emulated Plantronics demo: when does gameplay start, and how many retrace waits / screen presents per second of game time.
python plan_calibrate.py
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu_plantronics import *
import emu_game


def cyan_border(im):
    px = im.load()
    return sum(1 for x in range(60, 260) for y in range(10, 16) if px[x, y] == (0, 170, 170))


g = PlanGame()
os.chdir(PLAN)
c = g.cpu
n = 0
while c.icount < 60_000_000:
    g.run(200_000)
    if cyan_border(g.frame_plantronics()) > 300:
        break
print('gameplay detected at instruction', c.icount)
hits = [0]
presents = [0]
orig_on_int = g.on_int


def counting_on_int(num):
    if num == 0x62:
        presents[0] += 1
    return orig_on_int(num)


g.cpu.on_int = counting_on_int
start = c.icount
r0 = [0]


def stop(gg):
    if c.s[1] == emu_game.LOAD_SEG and c.ip == 0x8172:
        hits[0] += 1
    return False


g.run(6_000_000, stop_cb=stop)
print('over %d instructions: retrace waits %d, INT 62h presents %d' % (c.icount - start, hits[0], presents[0]))
