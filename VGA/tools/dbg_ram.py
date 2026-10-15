"""Debug helper: run a build to N instructions and dump the RAM screen (DS:FA1E) + A000 as images; list primitive call counts."""
import os, sys, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu_game import *
from PIL import Image

exe = os.path.abspath(sys.argv[1]); n = int(sys.argv[2]); out = os.path.abspath(sys.argv[3])
g = Game(exe)
c = g.cpu
os.chdir(os.path.dirname(exe))
hdr = open(exe, 'rb').read(32)
ds_seg = struct.unpack_from('<H', c.mem, LOAD_SEG * 16 + 0xA7)[0]   # relocated DS immediate
DS = ds_seg * 16
cnt = collections.Counter()
names = {0x8139: 'present', 0x76D1: 'ground', 0x7C3F: 'sprite', 0x6D4E: 'glyph', 0x18A3: 'title', 0x6A2B: 'dissolve', 0x7590: 'ramfill',
         0x77AA: 'clear', 0x7743: 'ckey', 0x6C7C: 'text', 0x6CA2: 'str', 0x8172: 'retrace', 0x7899: 'restore', 0x6A92: 'setbg'}
pressed = False
while c.icount < n:
    c.step()
    if not pressed and len(sys.argv) > 4 and c.icount >= int(sys.argv[4]):
        g.press(0x3920)
        pressed = True
    if c.s[1] == LOAD_SEG and c.ip in names:
        cnt[names[c.ip]] += 1
    if c.icount >= g.next_tick:
        g.next_tick += g.tick_period
        g.tick()
print(dict(cnt))
ram = struct.unpack_from('<H', c.mem, DS + 0xFA1E)[0]
print('RAM screen seg %04X, DS %04X' % (ram, ds_seg))
im = Image.new('P', (320, 200))
pal = []
for col in g.palette:
    pal += list(col)
im.putpalette(pal)
im.frombytes(bytes(c.mem[ram * 16: ram * 16 + 64000]))
im.convert('RGB').save(out + '_ram.png')
g.frame().convert('RGB').save(out + '_a000.png')
print('mode', g.video_mode)
