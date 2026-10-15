"""Capture the title-screen text (BIOS teletype) the moment hook_modetext runs, for each sound mode."""
import os, sys, subprocess
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu_game import *

exe = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(HERE, 'build', 'COMMANDO.EXE')
nm = subprocess.run([r'C:\FPC\3.2.2\bin\i386-win32\nm.exe', os.path.join(HERE, 'build', 'vga.pe')], capture_output=True, text=True).stdout
sym = {l.split()[2]: int(l.split()[0], 16) for l in nm.splitlines() if len(l.split()) == 3}
for mode in (0, 1, 2, 3):
    g = Game(exe); c = g.cpu
    os.chdir(os.path.dirname(exe))
    CS = LOAD_SEG * 16
    cur = [0, 0]; text = {}
    orig = g.int_10

    def int10(g=g, c=c, cur=cur, text=text, orig=orig):
        ah = (c.r[0] >> 8) & 0xFF
        if ah == 0x02:
            cur[0], cur[1] = c.r[2] & 0xFF, (c.r[2] >> 8) & 0xFF
        elif ah == 0x0E:
            ch = c.r[0] & 0xFF
            if ch == 13: cur[0] = 0
            elif ch == 10: cur[1] += 1
            else:
                text[(cur[0], cur[1])] = chr(ch); cur[0] += 1
        elif ah == 0x06:
            text.clear()
        else:
            orig()
    g.int_10 = int10
    g.run(200_000)
    c.mem[CS + sym['s_mode']] = mode
    hit = sym['hook_modetext']
    seen = False
    while c.icount < 6_000_000:
        c.step()
        if c.icount >= g.next_tick:
            g.next_tick += g.tick_period; g.tick()
        if c.s[1] == LOAD_SEG and c.ip == hit:
            seen = True
            for _ in range(400_000):
                c.step()
                if c.icount >= g.next_tick:
                    g.next_tick += g.tick_period; g.tick()
            break
    rows = {}
    for (x, y), ch in text.items():
        rows.setdefault(y, {})[x] = ch
    print('mode', mode, 'hook reached', seen)
    for y in sorted(rows):
        print('   %2d | %s' % (y, ''.join(rows[y].get(x, ' ') for x in range(0, 60)).rstrip()))
