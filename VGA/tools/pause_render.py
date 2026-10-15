"""Render the pause/instructions screen of a build in the emulator by running the key handler 35CF(ESC) in
player-controlled state 4.  BIOS teletype text (INT 10h AH=0Eh) is captured and printed as text rows.
python pause_render.py EXE OUT.png [mode]"""
import os, sys, subprocess
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu_game import *
from PIL import ImageDraw

exe = os.path.abspath(sys.argv[1]); out = os.path.abspath(sys.argv[2]); mode = int(sys.argv[3]) if len(sys.argv) > 3 else None
nm = subprocess.run([r'C:\FPC\3.2.2\bin\i386-win32\nm.exe', os.path.join(HERE, 'build', 'vga.pe')], capture_output=True, text=True).stdout
sym = {l.split()[2]: int(l.split()[0], 16) for l in nm.splitlines() if len(l.split()) == 3}
g = Game(exe); c = g.cpu
os.chdir(os.path.dirname(exe))
CS = LOAD_SEG * 16
ds_seg = struct.unpack_from('<H', c.mem, CS + 0xA7)[0]
DS = ds_seg * 16
cur = [0, 0]
text = {}
orig_int10 = g.int_10


def int10():
    ah = (c.r[0] >> 8) & 0xFF
    if ah == 0x02:
        cur[0], cur[1] = c.r[2] & 0xFF, (c.r[2] >> 8) & 0xFF
    elif ah == 0x0E:
        ch = c.r[0] & 0xFF
        if ch == 13:
            cur[0] = 0
        elif ch == 10:
            cur[1] += 1
        else:
            text[(cur[0], cur[1])] = chr(ch)
            cur[0] += 1
    elif ah == 0x06:
        text.clear()
    else:
        orig_int10()


g.int_10 = int10
g.run(300_000)
if mode is not None:
    c.mem[CS + sym['s_mode']] = mode
g.run(3_000_000)
g.press(0x3920)
g.run(2_500_000)
c.mem[DS + 0xFA19] = 2
# run the ESC key handler; it blocks in the pause loop waiting for ESC, so stop once the screen text is complete
c.push(0xFFF0)
c.ip = 0x5F80
text.clear()
steps = 0
while steps < 2_500_000 and not (len(text) > 120):
    c.step()
    steps += 1
    if c.icount >= g.next_tick:
        g.next_tick += g.tick_period
        g.tick()
g.run(20000)
im = g.frame().convert('RGB')
d = ImageDraw.Draw(im)
for (x, y), ch in text.items():
    d.text((x * 4, y * 8), ch, fill=(255, 255, 255))
im.save(out)
rows = {}
for (x, y), ch in text.items():
    rows.setdefault(y, {})[x] = ch
for y in sorted(rows):
    print('%2d | %s' % (y, ''.join(rows[y].get(x, ' ') for x in range(0, 60)).rstrip()))
