import os, sys, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu_game import *
exe = os.path.join(ROOT, 'COMMANDO.EXE')
g = Game(exe); g.virtual_time = True; g.next_tick = g.fallback_period
c = g.cpu
g.run(500_000_000, stop_cb=lambda gg: gg.retrace_calls >= 1500)
h = collections.Counter()
for _ in range(60000):
    c.step()
    if c.s[1] == LOAD_SEG:
        h[c.ip >> 4] += 1
print('top IP regions (paragraph):', [(hex(k << 4), v) for k, v in h.most_common(8)])
print('ticks', g.ticks, 'retraces', g.retrace_calls, 'video', g.video_mode)
# find the last few retrace callers
sp = (c.s[2] << 4)
