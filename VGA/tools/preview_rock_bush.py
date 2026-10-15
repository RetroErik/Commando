"""Focus preview of the changed level 1 objects, also shown in the jungle context -> preview/scenery_rock_bush_vga.png (preview only)."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image
from make_previews import pair_sheet, img_from
import atlas_scenery_all as sa, scenery_map as sm, vga_art as art
from vga_palette import PALETTE
from cgagfx import HERE

want = {0xAD38, 0xAB94, 0xAEDC}
bm = {b['ptr']: b for b in sa.all_bitmaps() if b['level'] == 1 and b['ptr'] in want}
items = []
for p in (0xAD38, 0xAB94, 0xAEDC):
    b = bm[p]
    g = sa.grid(b)
    v = sm.vga_grid(1, p, g, b['orflag'])
    items.append(('L1 DS:%04X %dx%d [%s]' % (p, b['width'] * 4, b['rows'], sm.KIND[(1, p)]), g, [[None if c == 0 else c for c in r] for r in v]))
print(pair_sheet(items, os.path.join(HERE, 'preview', 'scenery_rock_bush_vga.png'), 'PROPOSED VGA - level 1 bush (AD38 + AB94) and rock (AEDC)', 3, 5))

# context mock-up: bush made of AD38 (left) + AB94 (right), and the rock, on the jungle ground
W, H = 140, 70
ground = art.ground_swatch('L1', W, H)
canvas = [[c for c in row] for row in ground]


def blit(grid, x0, y0):
    for y, r in enumerate(grid):
        for x, c in enumerate(r):
            if c and 0 <= y0 + y < H and 0 <= x0 + x < W:
                canvas[y0 + y][x0 + x] = c


for p, x0, y0 in ((0xAD38, 6, 8), (0xAB94, 46, 8), (0xAEDC, 100, 20)):
    b = bm[p]
    blit(sm.vga_grid(1, p, sa.grid(b), b['orflag']), x0, y0)
im = img_from(canvas, PALETTE, 1)
base = Image.new('RGB', im.size, (0, 0, 0))
base.paste(im, (0, 0), im)
base.resize((W * 6, H * 6), Image.NEAREST).save(os.path.join(HERE, 'preview', 'rock_bush_context_vga.png'))
