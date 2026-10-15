"""Snapshot the screen right after the patched 'music device' text is drawn (pause / instructions screen)."""
import os, sys, subprocess
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu_game import *
exe = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(HERE, 'build', 'COMMANDO.EXE')
limit = int(sys.argv[2]) if len(sys.argv) > 2 else 60_000_000
nm = subprocess.run([r'C:\FPC\3.2.2\bin\i386-win32\nm.exe', os.path.join(HERE, 'build', 'vga.pe')], capture_output=True, text=True).stdout
sym = {l.split()[2]: int(l.split()[0], 16) for l in nm.splitlines() if len(l.split()) == 3}
g = Game(exe); c = g.cpu
os.chdir(os.path.dirname(exe))
CS = LOAD_SEG
hit = sym['hook_modetext']
g.run(300_000)
mode = int(sys.argv[3]) if len(sys.argv) > 3 else 0
c.mem[CS * 16 + sym['s_mode']] = mode
hits = 0
while c.icount < limit:
    c.step()
    if c.icount >= g.next_tick:
        g.next_tick += g.tick_period
        g.tick()
    if c.s[1] == CS and c.ip == hit:
        hits += 1
        if hits == 1:
            for _ in range(int(sys.argv[4]) if len(sys.argv) > 4 else 60_000):       # let the screen finish drawing
                c.step()
                if c.icount >= g.next_tick:
                    g.next_tick += g.tick_period
                    g.tick()
            g.frame().convert('RGB').save(os.path.join(HERE, 'test', 'pausemenu_mode%d.png' % mode))
            print('hit at icount', c.icount)
            break
print('hits', hits)
