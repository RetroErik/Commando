"""Copy raw graphics blobs out of the original files into VGA/extracted and build the reference-screen contact sheet."""
import os, sys, struct, shutil
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cgagfx import *
from PIL import Image

EX = os.path.join(HERE, 'extracted')
os.makedirs(os.path.join(EX, 'level_data'), exist_ok=True)
os.makedirs(os.path.join(EX, 'fonts'), exist_ok=True)
os.makedirs(os.path.join(EX, 'menu'), exist_ok=True)

DAT = open(os.path.join(ROOT, 'COMMANDO.DAT'), 'rb').read()
# STARTC/START.COM serve INT 13h reads from COMMANDO.DAT: file offset = track*4096 + (sector-1)*512.
# The game loads 3.5 tracks (14336 bytes) of level data per area to DS:9454: level n -> track 24+4n.
for n in (1, 2, 3):
    t = 24 + 4 * n
    blob = DAT[t * 4096: t * 4096 + 14336]
    open(os.path.join(EX, 'level_data', 'level%d_tracks%d-%d.bin' % (n, t, t + 3)), 'wb').write(blob)
open(os.path.join(EX, 'fonts', 'font_large_12x12_DS00B6.bin'), 'wb').write(IMG[DS_BASE + 0xB6: DS_BASE + 0xB6 + 36 * 0x60])
open(os.path.join(EX, 'fonts', 'font_tiles_8x8_DS0016.bin'), 'wb').write(IMG[DS_BASE + 0x16: DS_BASE + 0x16 + 160])
ptrs = [struct.unpack_from('<H', IMG, 0x193C + 2 * i)[0] for i in range(6)] + [0x330C]
for i in range(5):
    open(os.path.join(EX, 'menu', 'menu%d_CS%04X.bin' % (i, ptrs[i])), 'wb').write(IMG[ptrs[i]: ptrs[i + 1] if i < 4 else 0x330C])
print('raw blobs written')

# reference screens (captured from the original game: DOSBox + the offline emulator, CGA mode 4 palette 1)
srcs = [('title', os.path.join(HERE, 'test', 'emu', 'frame_002.png')),
        ('high scores', os.path.join(HERE, 'test', 'emu', 'final.png')),
        ('level 1', os.path.join(HERE, 'analysis', 'level1.png')),
        ('level 2', os.path.join(HERE, 'analysis', 'level2.png')),
        ('level 3', os.path.join(HERE, 'analysis', 'level3.png')),
        ('name entry', os.path.join(HERE, 'test', 'shots4', 'raw', 'commando_021.png'))]
ok = [(n, p) for n, p in srcs if os.path.exists(p)]
os.makedirs(os.path.join(HERE, 'atlas', 'screens'), exist_ok=True)
for n, p in ok:
    shutil.copy(p, os.path.join(HERE, 'atlas', 'screens', 'orig_%s.png' % n.replace(' ', '_')))
print([n for n, _ in ok])
