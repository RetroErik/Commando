"""Generate labelled atlases of the original CGA graphics into VGA/atlas/."""
import os, sys, json
from PIL import Image, ImageDraw, ImageFont
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cgagfx import *
from scan_sprites import scan

OUT = os.path.join(HERE, 'atlas')
os.makedirs(OUT, exist_ok=True)
try:
    FONT = ImageFont.truetype('consola.ttf', 12)
    FONT_B = ImageFont.truetype('consolab.ttf', 13)
except Exception:
    FONT = FONT_B = ImageFont.load_default()
BG = (48, 52, 64)
CHECK = ((70, 74, 90), (58, 62, 78))


def rows_to_image(rows, pal, scale):
    h = len(rows)
    w = max(len(r) for r in rows) if rows else 0
    im = Image.new('RGBA', (w * scale, h * scale), (0, 0, 0, 0))
    px = im.load()
    for y, r in enumerate(rows):
        for x, c in enumerate(r):
            if c is None:
                continue
            col = pal[c] + (255,)
            for dy in range(scale):
                for dx in range(scale):
                    px[x * scale + dx, y * scale + dy] = col
    return im


def checker(w, h, s=6):
    im = Image.new('RGB', (w, h))
    d = ImageDraw.Draw(im)
    for y in range(0, h, s):
        for x in range(0, w, s):
            d.rectangle([x, y, x + s - 1, y + s - 1], fill=CHECK[((x // s) + (y // s)) & 1])
    return im


def atlas(cells, path, cols, scale, title, cell_min=(0, 0), pal=CGA_PAL):
    """cells = list of (label, rows). Draw each on a checker background in a grid."""
    ims = [(lab, rows_to_image(rows, pal, scale)) for lab, rows in cells]
    cw = max(max(i.width for _, i in ims), cell_min[0]) + 12
    ch = max(max(i.height for _, i in ims), cell_min[1]) + 30
    nrows = (len(ims) + cols - 1) // cols
    head = 28
    sheet = Image.new('RGB', (cols * cw, nrows * ch + head), BG)
    d = ImageDraw.Draw(sheet)
    d.text((8, 6), title, fill=(255, 230, 120), font=FONT_B)
    for i, (lab, im) in enumerate(ims):
        x, y = (i % cols) * cw, (i // cols) * ch + head
        d.text((x + 6, y + 4), lab, fill=(220, 220, 220), font=FONT)
        bg = checker(im.width, im.height, max(scale * 2, 6))
        sheet.paste(bg, (x + 6, y + 22))
        sheet.paste(im, (x + 6, y + 22), im)
    sheet.save(path)
    return sheet.size


if __name__ == '__main__':
    spr = scan()
    cells = []
    for s in spr:
        sp = sprite_at(s['a'])
        cells.append(('%04X %dx%d%s' % (sp['d'], sp['w'] * 4, sp['h'], '' if sp['odd_off'] else ' *'), sp['even']))
    print(atlas(cells, os.path.join(OUT, 'raw_all_sprites_cga.png'), 8, 3, 'All CGA sprite records in data segment (label = data-seg offset, size, * = no odd-x variant)'))
