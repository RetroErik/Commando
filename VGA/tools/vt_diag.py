import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu_game import *
exe = os.path.join(ROOT, 'COMMANDO.EXE')
g = Game(exe); g.virtual_time = True; g.next_tick = g.fallback_period
c = g.cpu
ds = struct.unpack_from('<H', c.mem, LOAD_SEG * 16 + 0xA7)[0] * 16
for r in (500, 1500, 3000, 6000, 10000):
    g.run(500_000_000, stop_cb=lambda gg, r=r: gg.retrace_calls >= r)
    print('retraces %6d icount %9d ticks %6d CS:IP %04X:%04X video mode %d  FA19=%d  keyq=%s irq8vec=%04X:%04X' % (
        g.retrace_calls, c.icount, g.ticks, c.s[1], c.ip, g.video_mode, c.mem[ds + 0xFA19], g.key_queue, c.rw(0x22), c.rw(0x20)))
g.press(0x3920)
for r in (10500, 11000, 12000):
    g.run(500_000_000, stop_cb=lambda gg, r=r: gg.retrace_calls >= r)
    print('after key: retraces %6d CS:IP %04X:%04X FA19=%d keyq=%s' % (g.retrace_calls, c.s[1], c.ip, c.mem[ds + 0xFA19], g.key_queue))
