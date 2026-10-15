"""Extract fonts, tiles and menu bitmaps from COMMANDO.EXE and render original-CGA atlases."""
import os, sys, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cgagfx import *
from atlas_orig import atlas, rows_to_image, OUT
from PIL import Image

EXTRACT = os.path.join(HERE, 'extracted')
os.makedirs(EXTRACT, exist_ok=True)


def glyph_rows(a, w, h):
    """Font glyph: w bytes x h rows, each pixel pair 00 = background, 11 (3) = ink. Return rows of 0/1 (None = background)."""
    rows = []
    for y in range(h):
        row = []
        for x in range(w):
            b = IMG[a + y * w + x]
            for p in range(4):
                v = (b >> (6 - 2 * p)) & 3
                row.append(3 if v else None)
        rows.append(row)
    return rows


def main():
    # large font: DS:00B6 + 36*ch, 3 bytes x 12 rows
    cells = []
    big = []
    for ch in range(0x7F):
        a = DS_BASE + 0xB6 + 36 * ch
        rows = glyph_rows(a, 3, 12)
        if any(any(p for p in r) for r in rows):
            cells.append(('%02X %s' % (ch, chr(ch) if 0x20 < ch < 0x7F else ''), rows))
            big.append(ch)
    print('large font glyphs:', len(big), 'codes', [hex(c) for c in big][:5], '...')
    print(atlas(cells, os.path.join(OUT, 'font_large_cga.png'), 16, 4, 'Large font: DS:00B6 + 36*code, 12x12 px, 2bpp mask (ink drawn in the caller-selected color)'))
    # tiles: DS:0016 + 16*(code-0x80), 2 bytes x 8 rows (frame/border tiles)
    cells = []
    for n in range(10):
        a = DS_BASE + 0x16 + 16 * n
        rows = []
        for y in range(8):
            row = []
            for x in range(2):
                b = IMG[a + y * 2 + x]
                for p in range(4):
                    v = (b >> (6 - 2 * p)) & 3
                    row.append(3 if v else None)
            rows.append(row)
        cells.append(('%02X' % (0x80 + n), rows))
    print(atlas(cells, os.path.join(OUT, 'font_small_tiles_cga.png'), 10, 8, 'Small 8x8 tiles/glyphs: DS:0016 + 16*(code-0x80) (codes 80-89: playfield frame pieces)'))
    # menu sprites (code segment pointer table at 193C)
    ptrs = [struct.unpack_from('<H', IMG, 0x193C + 2 * i)[0] for i in range(5)]
    cells = []
    info = []
    for i, p in enumerate(ptrs):
        s = menu_sprite_at(p)
        cells.append(('menu %d  CS:%04X  %dx%d' % (i, p, s['w'] * 4, s['h']), s['even']))
        info.append(dict(index=i, cs_offset=p, w=s['w'] * 4, h=s['h']))
    print(atlas(cells, os.path.join(OUT, 'menu_title_cga.png'), 2, 3, 'Title/menu bitmaps in the code segment (pointer table CS:193C)'))
    json.dump(dict(menu=info), open(os.path.join(EXTRACT, 'menu_fonts_catalog.json'), 'w'), indent=1)


if __name__ == '__main__':
    main()
