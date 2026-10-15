"""Report scenery blits that miss the VGA asset table (fallback path) in the VGA build."""
import os, sys, subprocess, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu_game import *
exe = os.path.abspath(sys.argv[1]); n = int(sys.argv[2]); lvl = int(sys.argv[3]) if len(sys.argv) > 3 else 1
nm = subprocess.run([r'C:\FPC\3.2.2\bin\i386-win32\nm.exe', os.path.join(os.path.dirname(os.path.dirname(exe)), 'build', 'vga.pe')], capture_output=True, text=True).stdout
sym = {l.split()[2]: int(l.split()[0], 16) for l in nm.splitlines() if len(l.split()) == 3}
fb, ck = sym['bl_fallback'], sym['ck_out']
g = Game(exe); c = g.cpu
os.chdir(os.path.dirname(exe))
ds_seg = struct.unpack_from('<H', c.mem, LOAD_SEG * 16 + 0xA7)[0]
g.run(3_300_000); g.press(0x3920)
done = False
while not done:
    g.run(1)
    if c.s[1] == LOAD_SEG and c.ip == 0x35AC:
        c.mem[ds_seg * 16 + 0xFB58] = lvl; done = True
hits = collections.Counter()
end = c.icount + n
while c.icount < end:
    c.step()
    if c.s[1] == LOAD_SEG and c.ip == fb:
        bp = c.r[5]; ss = c.s[2] << 4
        hits[(c.rw(ss + bp + 4), c.rw(ss + bp + 6), c.rw(ss + bp + 8))] += 1
    if c.icount >= g.next_tick:
        g.next_tick += g.tick_period; g.tick()
for (d, s, cnt), k in sorted(hits.items(), key=lambda kv: kv[0][1]):
    print('fallback: dest %04X src DS:%04X count %d  x%d' % (d, s, cnt, k))
