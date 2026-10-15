"""Profile calls to the rendering primitives (entry IP -> count, call sites, sample stack args) for a scripted run."""
import os, sys, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu_game import *

FUN = {0x8139: 'present', 0x76D1: 'groundblit', 0x765C: 'objs->ram', 0x75EA: 'objs->B800', 0x6D4E: 'glyph', 0x18A3: 'titleblit',
       0x7590: 'ramfill', 0x6A2B: 'dissolve', 0x77AA: 'clearB800', 0x7743: 'colorkey', 0x6C7C: 'text1', 0x6CA2: 'textstr', 0x6A92: 'setbg/present',
       0x7C3F: 'sprite', 0x7899: 'restore', 0x6BC3: 'drawobjs', 0x6BAD: 'drawobjsB800', 0x64DD: 'peek', 0x64F0: 'poke', 0x5239: 'scenebuild', 0x57DC: 'frame',
       0x5705: 'sceneinit', 0x6AB0: 'textmode', 0x69E3: 'initmode', 0x75D2: 'present2', 0x8172: 'retrace'}
phases = [int(x) for x in sys.argv[1].split(',')]   # instruction counts at which to print a report
g = Game(os.path.join(ROOT, 'COMMANDO.EXE'))
c = g.cpu
CS = LOAD_SEG
keys = {int(k): int(v, 16) for k, v in (e.split(':') for e in sys.argv[2].split(','))} if len(sys.argv) > 2 else {}
cnt = collections.Counter()
sites = collections.defaultdict(collections.Counter)
args = {}
pressed = set()
for ph in phases:
    while c.icount < ph:
        c.step()
        if c.s[1] == CS and c.ip in FUN:
            ip = c.ip
            sp = (c.s[2] << 4) + c.r[4]
            ret = c.rw(sp)
            cnt[ip] += 1
            sites[ip][ret] += 1
            args.setdefault((ip, ret), [c.rw(sp + 2 + 2 * i) for i in range(7)])
        if c.icount >= g.next_tick:
            g.next_tick += g.tick_period
            g.tick()
        for t, k in keys.items():
            if c.icount >= t and t not in pressed:
                pressed.add(t)
                g.press(k)
    print('=== up to', c.icount)
    for ip, n in sorted(cnt.items(), key=lambda kv: -kv[1]):
        print('%04X %-14s x%-6d sites: %s' % (ip, FUN[ip], n, ', '.join('%04X:%d' % (r, k) for r, k in sites[ip].most_common(6))))
    cnt.clear(); sites.clear()
    g.cga_frame().convert('RGB').save(os.path.join(HERE, 'test', 'prof_%d.png' % ph))

