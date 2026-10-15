"""Q-key test: with AdLib selected and a note sounding, a pending 'q' must key off all OPL voices and set mode OFF."""
import os, sys, subprocess
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu_game import *
exe = os.path.join(HERE, 'build', 'COMMANDO.EXE')
nm = subprocess.run([r'C:\FPC\3.2.2\bin\i386-win32\nm.exe', os.path.join(HERE, 'build', 'vga.pe')], capture_output=True, text=True).stdout
sym = {l.split()[2]: int(l.split()[0], 16) for l in nm.splitlines() if len(l.split()) == 3}
g = Game(exe); g.io_log = []; c = g.cpu
os.chdir(os.path.dirname(exe))
CS = LOAD_SEG * 16
g.run(3_500_000)
g.press(0x324D)
for _ in range(60):
    g.run(100_000)
    if c.mem[CS + sym['s_mode']] == 2:
        break
# wait for a melody note to be keyed on
state = {}
cur = None
def keyed():
    k = None
    for t, p, v in g.io_log:
        if p == 0x388: k = v
        elif p == 0x389 and k == 0xB0:
            state['b0'] = v
    return state.get('b0', 0) & 0x20
for _ in range(120):
    g.run(100_000)
    if keyed():
        break
print('mode', c.mem[CS + sym['s_mode']], 'channel-0 key-on:', bool(keyed()))
n0 = len(g.io_log)
g.press(0x1071)          # 'q'
g.run(400_000)
k = None; last = {}
for t, p, v in g.io_log[n0:]:
    if p == 0x388: k = v
    elif p == 0x389: last[k] = v
print('after Q: mode', c.mem[CS + sym['s_mode']], 'B0=%s BD=%s' % (hex(last.get(0xB0, -1)), hex(last.get(0xBD, -1))), '(B0 bit5 must be 0)')
