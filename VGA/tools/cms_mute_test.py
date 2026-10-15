"""CMS music mute/restore through the game's music setter (used by the ESC pause) and the 'is music on' query."""
import os, sys, subprocess
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fxlib import *
exe = os.path.join(HERE, 'build', 'COMMANDO.EXE')
nm = subprocess.run([r'C:\FPC\3.2.2\bin\i386-win32\nm.exe', os.path.join(HERE, 'build', 'vga.pe')], capture_output=True, text=True).stdout
sym = {l.split()[2]: int(l.split()[0], 16) for l in nm.splitlines() if len(l.split()) == 3}
g = Game(exe); g.io_log = []; c = g.cpu
os.chdir(os.path.dirname(exe))
CS = LOAD_SEG * 16
g.run(3_300_000)
g.press(0x324D)
for _ in range(40):
    g.run(100_000)
    if c.mem[CS + sym['s_mode']] == 1:
        break
g.run(3_000_000)
for _ in range(60):
    g.run(100_000)
    if any(c.mem[CS + sym['sid_current_volumes'] + k] for k in range(3)): break
print('current volumes', [hex(c.mem[CS + sym['sid_current_volumes'] + k]) for k in range(3)])


def vols(since):
    reg = {0: None, 1: None}; out = []
    for t, p, v in g.io_log:
        if t < since: continue
        if p == 0x221: reg[0] = v
        elif p == 0x223: reg[1] = v
        elif p == 0x220 and reg[0] in (0x00, 0x03): out.append(('c0', hex(reg[0]), hex(v)))
        elif p == 0x222 and reg[1] in (0x00, 0x03): out.append(('c1', hex(reg[1]), hex(v)))
    return out


def query():
    saved = (list(c.r), list(c.s), c.ip, c.get_flags())
    call_far_near(g, 0x66C1, [])
    return None


t0 = c.icount
call_far_near(g, 0x6784, [0])
print('music OFF   -> volume writes', vols(t0), ' sid_enabled', c.mem[CS + sym['sid_enabled']], ' game flag 6583 =', c.mem[CS + 0x6583])
t0 = c.icount
call_far_near(g, 0x6784, [1])
print('music ON    -> volume writes', vols(t0), ' sid_enabled', c.mem[CS + sym['sid_enabled']], ' game flag 6583 =', c.mem[CS + 0x6583])
