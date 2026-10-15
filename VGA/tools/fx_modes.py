"""Trigger the game's gunfire effect in every sound mode and report what each device receives.
python fx_modes.py [EXE] [CMS 0/1]"""
import os, sys, subprocess, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fxlib import *

exe = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(HERE, 'build', 'COMMANDO.EXE')
nm = subprocess.run([r'C:\FPC\3.2.2\bin\i386-win32\nm.exe', os.path.join(HERE, 'build', 'vga.pe')], capture_output=True, text=True).stdout
sym = {l.split()[2]: int(l.split()[0], 16) for l in nm.splitlines() if len(l.split()) == 3}
g = Game(exe)
g.io_log = []
c = g.cpu
os.chdir(os.path.dirname(exe))
CS = LOAD_SEG * 16
g.run(3_300_000)
g.press(0x3920)
g.run(2_000_000)         # into gameplay


def mode():
    return c.mem[CS + sym['s_mode']]


def press_m_and_wait(expect):
    g.press(0x324D)
    for _ in range(40):
        g.run(100_000)
        if mode() == expect:
            break
    g.run(200_000)


def run_mode(name):
    t0 = c.icount
    n0 = len(g.io_log)
    for shot in range(3):
        start_effect(g)
        g.run(300_000)
    ev = g.io_log[n0:]
    cnt = collections.Counter(p for _, p, _ in ev)
    regs = collections.Counter()
    cur = None
    for t, p, v in ev:
        if p == 0x388:
            cur = v
        elif p == 0x389 and cur in (0xA3, 0xB3, 0xBD):
            regs[cur] += 1
    print('%-9s mode=%d  ports %s  OPL gun regs %s' % (name, mode(), {hex(k): v for k, v in sorted(cnt.items())}, {hex(k): v for k, v in regs.items()}))


run_mode('speaker')
for expect in (2, 3, 0):
    press_m_and_wait(expect)
    run_mode('mode %d' % expect)
