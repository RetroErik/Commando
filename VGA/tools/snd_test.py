"""Sound-layer test in the 8086 emulator: python snd_test.py [EXE]
Checks the M-key cycle, the INT 60h/61h speaker bridge and the OPL register traffic of the VGA build."""
import os, sys, subprocess, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu_game import *

exe = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(HERE, 'build', 'COMMANDO.EXE')
pe = os.path.join(HERE, 'build', 'vga.pe')
nm = subprocess.run([r'C:\FPC\3.2.2\bin\i386-win32\nm.exe', pe], capture_output=True, text=True).stdout
sym = {l.split()[2]: int(l.split()[0], 16) for l in nm.splitlines() if len(l.split()) == 3}
g = Game(exe)
g.io_log = []
c = g.cpu
os.chdir(os.path.dirname(exe))
CS = LOAD_SEG * 16


def mode():
    return c.mem[CS + sym['s_mode']]


def summary(tag, since):
    cnt = collections.Counter(p for t, p, v in g.io_log if t >= since)
    print('%-28s mode=%d  writes: %s' % (tag, mode(), {hex(k): v for k, v in sorted(cnt.items())}))


g.run(300_000)
print('after startup: mode', mode(), 'allowed %02X' % c.mem[CS + sym['s_allowed']], 'IVT60 %04X:%04X IVT61 %04X:%04X' % (c.rw(0x182), c.rw(0x180), c.rw(0x186), c.rw(0x184)))
t0 = c.icount
g.run(3_000_000)
summary('title, speaker mode', t0)
t0 = c.icount
for step in range(4):
    g.press(0x324D)
    g.run(150_000)
    t1 = c.icount
    g.run(2_500_000)
    summary('after M #%d' % (step + 1), t0)
    t0 = c.icount
adl = [(t, v) for t, p, v in g.io_log if p == 0x389]
print('total opl data writes', len(adl))
