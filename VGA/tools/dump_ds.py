"""Dump the gameplay data segment from the emulator and render candidate scenery bitmaps."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu_game import *
from cgagfx import CGA_PAL
from PIL import Image

g = Game(os.path.join(ROOT, 'COMMANDO.EXE'))
c = g.cpu
g.run(4_000_000)
g.press(0x3920)
g.run(1_500_000)
DS = (LOAD_SEG + 0x835) * 16
ds = bytes(c.mem[DS:DS + 0x10000])
open(os.path.join(HERE, 'analysis', 'ds_gameplay.bin'), 'wb').write(ds)
print('saved')


def render(off, w, rows, scale=3):
    im = Image.new('RGB', (w * 4, rows))
    px = im.load()
    for y in range(rows):
        for xb in range(w):
            b = ds[off + y * w + xb]
            for p in range(4):
                px[xb * 4 + p, y] = CGA_PAL[(b >> (6 - 2 * p)) & 3]
    return im.resize((im.width * scale, im.height * scale), Image.NEAREST)


tests = [('AD38 w10', 0xAD38, 10, 28), ('AE50 w5', 0xAE50, 5, 28), ('AFC4 w3', 0xAFC4, 3, 4), ('AFD4 w2', 0xAFD4, 2, 4),
         ('AFDE w11', 0xAFDE, 11, 56), ('B246 w6', 0xB246, 6, 56), ('B396 w11', 0xB396, 11, 56), ('B5FE w6', 0xB5FE, 6, 56)]
W = sum(i[2] * 4 * 3 + 20 for i in tests)
sheet = Image.new('RGB', (W, 56 * 3 + 10), (40, 40, 60))
x = 0
for name, off, w, rows in tests:
    im = render(off, w, rows)
    sheet.paste(im, (x, 0))
    x += im.width + 20
sheet.save(os.path.join(HERE, 'analysis', 'scenery_probe.png'))
print(sheet.size)
