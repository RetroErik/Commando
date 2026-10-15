"""v1.2 sound-layer test in the emulator: 4-mode M cycle, CMS register traffic, effects on the CMS chip, score banks."""
import os, sys, subprocess, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fxlib import *

exe = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(HERE, 'build', 'COMMANDO.EXE')
nm = subprocess.run([r'C:\FPC\3.2.2\bin\i386-win32\nm.exe', os.path.join(HERE, 'build', 'vga.pe')], capture_output=True, text=True).stdout
sym = {l.split()[2]: int(l.split()[0], 16) for l in nm.splitlines() if len(l.split()) == 3}
g = Game(exe); g.io_log = []; c = g.cpu
os.chdir(os.path.dirname(exe))
CS = LOAD_SEG * 16
g.run(3_300_000)
print('allowed %02X' % c.mem[CS + sym['s_allowed']], 'seg0 %04X seg1 %04X (CS %04X)' % (c.rw(CS + sym['sid_seg0']), c.rw(CS + sym['sid_seg1']), LOAD_SEG))


def mode():
    return c.mem[CS + sym['s_mode']]


def press_m(expect):
    g.press(0x324D)
    for _ in range(40):
        g.run(100_000)
        if mode() == expect:
            break
    g.run(200_000)


def ports(since):
    cnt = collections.Counter(p for t, p, v in g.io_log if t >= since)
    return {hex(k): v for k, v in sorted(cnt.items())}


for expect in (1, 2, 3, 0):
    t0 = c.icount
    press_m(expect)
    g.run(2_500_000)
    print('M -> mode %d (expect %d): ports %s' % (mode(), expect, ports(t0)))
    if expect == 1:
        regs0 = collections.Counter(); cur = {}
        for t, p, v in g.io_log:
            if t < t0: continue
            if p in (0x221, 0x223):
                cur[p] = v
            elif p in (0x220, 0x222):
                regs0[(p, cur.get(p + 1))] += 1
        print('   distinct (port,reg) written:', len(regs0), ' SID cursor %d bank %d' % (c.rw(CS + sym['sid_cursor']), c.mem[CS + sym['sid_bank']]))

# gunfire in CMS mode: the game's effect must reach chip 0 channel 0 (regs 08h/10h/14h)
press_m(1)
n0 = len(g.io_log)
for i in range(3):
    start_effect(g)
    g.run(300_000)
cur = None; seen = collections.Counter()
for t, p, v in g.io_log[n0:]:
    if p == 0x221:
        cur = v
    elif p == 0x220 and cur in (0x08, 0x10, 0x14):
        seen[hex(cur)] += 1
print('effect in CMS mode -> chip0 regs', dict(seen), ' speaker-port writes:', sum(1 for t, p, v in g.io_log[n0:] if p in (0x42, 0x61)))
