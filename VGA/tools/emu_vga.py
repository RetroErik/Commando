"""Scripted emulator run of any build:  python emu_vga.py EXE OUTDIR "EVENTS" [virtual]
EVENTS: comma list  <instr>:key:<hex bios key> | <instr>:snap:<name>   (instruction counts are absolute)
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu_game import *

exe, out = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
os.makedirs(out, exist_ok=True)
events = []
for e in sys.argv[3].split(','):
    p = e.split(':')
    events.append((int(p[0]), p[1], p[2]))
events.sort(key=lambda t: t[0])
g = Game(exe)
if len(sys.argv) > 4 and sys.argv[4] == 'virtual':
    g.virtual_time = True
    g.next_tick = g.fallback_period
c = g.cpu
os.chdir(os.path.dirname(os.path.abspath(exe)))
for t, kind, arg in events:
    g.run(t - c.icount)
    if kind == 'key':
        g.press(int(arg, 16))
    elif kind == 'snap':
        g.frame().convert('RGB').save(os.path.join(out, arg + '.png'))
print('done', c.icount, 'CS:IP %04X:%04X' % (c.s[1], c.ip), 'mode', g.video_mode, 'frames', g.frame_calls, 'retraces', g.retrace_calls, g.log[-3:], g.unknown_ints)
