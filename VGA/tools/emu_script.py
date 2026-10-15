"""Scripted emulator run: python emu_script.py OUTDIR "EVENTS"
EVENTS: comma-separated  <instr>:key:<hexscancode>  |  <instr>:snap:<name>   (instr counts are absolute)
Optional env EXE to run a patched executable.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu_game import *

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
events = []
for e in sys.argv[2].split(','):
    p = e.split(':')
    events.append((int(p[0]), p[1], p[2]))
events.sort(key=lambda t: t[0])
g = Game(os.environ.get('EXE', os.path.join(ROOT, 'COMMANDO.EXE')))
c = g.cpu
i = 0
for t, kind, arg in events:
    g.run(t - c.icount)
    if kind == 'key':
        g.press(int(arg, 16))
    elif kind == 'snap':
        g.cga_frame().convert('RGB').save(os.path.join(out, arg + '.png'))
print('done', c.icount, 'CS:IP %04X:%04X' % (c.s[1], c.ip), g.log[-3:], g.unknown_ints)
print('INT9 vector %04X:%04X' % (c.rw(0x26), c.rw(0x24)))
