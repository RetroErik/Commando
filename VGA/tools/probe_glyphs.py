"""Which glyph codes / colours does the game draw (6D4E), and what is the colour table at DS:9230?"""
import os, sys, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu_game import *

g = Game(os.path.join(ROOT, 'COMMANDO.EXE'))
c = g.cpu
used = collections.Counter()
title = []
DS = (LOAD_SEG + 0x835) * 16
phases = [(4_000_000, None), (3_000_000, 0x3920), (8_000_000, None), (30_000_000, None)]
for n, key in phases:
    if key:
        g.press(key)
    end = c.icount + n
    while c.icount < end:
        c.step()
        if c.s[1] == LOAD_SEG and c.ip == 0x6D4E:
            used[(c.r[3], c.r[0] & 0xF)] += 1
        if c.s[1] == LOAD_SEG and c.ip == 0x18A3:
            sp = (c.s[2] << 4) + c.r[4]
            title.append([c.rw(sp + 2 + 2 * i) for i in range(4)])
        if c.icount >= g.next_tick:
            g.next_tick += g.tick_period
            g.tick()
print('colour table DS:9230 =', bytes(c.mem[DS + 0x9230:DS + 0x9240]).hex(' '))
print('glyph (code, colour) usage:')
for (code, col), n in sorted(used.items()):
    print('  %02X colour %d  x%d' % (code, col, n))
print('title blits (seg,x,y,idx):', [tuple(hex(v) for v in t) for t in title][:10])
