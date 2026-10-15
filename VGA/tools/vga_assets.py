"""Pack the APPROVED VGA artwork into binary form for the VGA build.

Outputs (build/):
  assets.bin    paragraph-aligned asset block (sprites, glyphs, tiles, title pieces, scenery)
  tables.s      assembler include: lookup tables + layout constants + palette
  assets_info.json  human-readable index

Conventions (all 8 bits per pixel):
  pixel value 0   = transparent (colour key)
  pixel value 255 = opaque pure black
Sprite asset = [wpx][h] pixels(h*wpx) | [wpx_odd] pixels(h*wpx_odd)  (odd image only if the CGA record has one)
Glyph  asset = 12x12 / 8x8 pixels, row-major, 0 = not ink
Title  asset = [wpx][h] pixels
Scenery asset = CGA bitmap bytes expanded 1 byte -> 4 pixels in the SAME order (so DS pointers map linearly)
"""
import os, sys, json, struct
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cgagfx import *
from catalog_sprites import all_sprites
from vga_palette import PALETTE, RAMP_IDX, ramp_color as rc
import vga_art as art
from make_previews import vga_for, text_grid, glyph_grid
from check_black import exterior_zero

BUILD = os.path.join(HERE, 'build')
os.makedirs(BUILD, exist_ok=True)
BLACK = 255


def finalize(grid, orig, force_black_all=False, black_exterior=False):
    """Replace palette index 0 (transparent key) of OPAQUE pixels by 255; optional exterior black."""
    ext = exterior_zero(orig) if black_exterior else set()
    out = []
    for y, row in enumerate(grid):
        r = []
        for x, v in enumerate(row):
            if v is None:
                r.append(0)
            elif force_black_all or (x, y) in ext:
                r.append(BLACK)
            else:
                r.append(BLACK if v == 0 else v)
        out.append(r)
    return out


def flat(grid):
    return bytes(v for row in grid for v in row)


class Pack:
    def __init__(self):
        self.buf = bytearray()

    def add(self, data):
        while len(self.buf) % 16:
            self.buf.append(0)
        para = len(self.buf) // 16
        self.buf += data
        while len(self.buf) % 16:
            self.buf.append(0)
        return para


def sprite_asset(sp):
    force_all = sp['d'] == 0x64B6
    black_ext = sp['group'] == 'grenade_stock'
    ev = finalize(vga_for(sp), sp['even'], force_all, black_ext)
    data = bytes([len(ev[0]), len(ev)]) + flat(ev)
    if sp['odd_off']:
        sp2 = dict(sp, even=sp['odd'])
        od = finalize(vga_for(sp2), sp['odd'], force_all, black_ext)
        data += bytes([len(od[0])]) + flat(od)
    return data


def clean_glyph(a, w, h):
    for i in range(w * h):
        b = IMG[a + i]
        for p in range(4):
            if (b >> (6 - 2 * p)) & 3 not in (0, 3):
                return False
    return True


def build():
    pk = Pack()
    info = {}
    sprites = all_sprites()
    sprite_tab = []
    for sp in sprites:
        para = pk.add(sprite_asset(sp))
        sprite_tab.append((sp['d'], para))
    sprite_tab.sort()
    info['sprites'] = len(sprite_tab)

    # ---- glyph tables: index = code (0..0x8F)
    glyph_tab = [0xFFFF] * 0x90
    ngl = 0
    for code in range(0x01, 0x60):
        a = DS_BASE + 0xB6 + 36 * code
        rows = glyph_grid_code(code)
        if not any(v for r in rows for v in r) or not clean_glyph(a, 3, 12):
            continue
        g = art.gold_text([[3 if v else None for v in r] for r in rows])
        grid = [[(g[y][x] if rows[y][x] else 0) for x in range(12)] for y in range(12)]
        if code == 0x01:
            grid = [[BLACK] * 12 for _ in range(12)]       # block glyph = erase rectangle (drawn in colour 0)
        glyph_tab[code] = pk.add(flat(grid))
        ngl += 1
    ntile = 0
    for n in range(10):
        a = DS_BASE + 0x16 + 16 * n
        rows = []
        for y in range(8):
            r = []
            for x in range(2):
                b = IMG[a + y * 2 + x]
                for p in range(4):
                    r.append(3 if (b >> (6 - 2 * p)) & 3 else None)
            rows.append(r)
        g = art.steel_ui(rows)
        grid = [[(g[y][x] if rows[y][x] else 0) for x in range(8)] for y in range(8)]
        glyph_tab[0x80 + n] = pk.add(flat(grid))
        ntile += 1
    info['glyphs'] = ngl
    info['tiles'] = ntile

    # ---- title pieces
    ptrs = [struct.unpack_from('<H', IMG, 0x193C + 2 * i)[0] for i in range(5)]
    title_tab = []
    for i, p in enumerate(ptrs):
        s = menu_sprite_at(p)
        v = art.title_logo(s['even']) if i < 4 else art.character(s['even'], 'hero', 0.26)
        grid = finalize(v, s['even'])
        title_tab.append(pk.add(bytes([len(grid[0]), len(grid)]) + flat(grid)))
    info['title'] = len(title_tab)

    # ---- scenery: every distinct display bitmap of levels 1-3 (see tools/scenery_map.py)
    import atlas_scenery_all as sa, scenery_map as sm
    scen_tab = []
    for b in sa.all_bitmaps():
        grid = sm.vga_grid(b['level'], b['ptr'], sa.grid(b), b['orflag'])
        para = pk.add(flat(grid))
        scen_tab.append((b['level'], b['ptr'], b['width'] * b['rows'], para, b['orflag']))
    info['scenery'] = len(scen_tab)

    return pk, sprite_tab, glyph_tab, title_tab, scen_tab, info


def glyph_grid_code(code):
    a = DS_BASE + 0xB6 + 36 * code
    rows = []
    for y in range(12):
        r = []
        for x in range(3):
            b = IMG[a + y * 3 + x]
            for p in range(4):
                r.append(3 if (b >> (6 - 2 * p)) & 3 else None)
        rows.append(r)
    return rows


def gcol_bytes():
    """Per level (1..3): 4 colour-map entries for CGA value 0..3, then 16 noise shades for value 0."""
    R = RAMP_IDX
    j = R['jungle']
    l1 = [R['jungle'][1], R['leaf'][3], R['trunk'][3], R['sand'][4]]
    n1 = [j[0], j[0], j[1], j[1], j[1], j[1], j[1], j[1], j[1], j[1], j[1], j[1], j[2], j[2], j[2], R['leaf'][2]]
    l2 = [R['sand'][2], R['sand'][3], R['sand'][4], R['sand'][6]]
    n2 = [l2[0]] * 16
    l3 = [R['stone'][2], R['stone'][3], R['brick'][3], R['stone'][7]]
    n3 = [l3[0]] * 16
    return [l1 + n1, l2 + n2, l3 + n3]


def write_tables(pk, sprite_tab, glyph_tab, title_tab, scen_tab, info, snd_cms=0):
    open(os.path.join(BUILD, 'assets.bin'), 'wb').write(bytes(pk.buf))
    C = ['# generated by tools/vga_assets.py - do not edit', '        .intel_syntax noprefix',
         '        .set ASSET_BYTES, %d' % len(pk.buf), '        .set N_SPRITES, %d' % len(sprite_tab),
         '        .set N_SCEN, %d' % len(scen_tab), '        .set SND_CMS, %d' % snd_cms, '        .set RING_PARAS, 0x700']
    open(os.path.join(BUILD, 'consts.s'), 'w').write('\n'.join(C) + '\n')
    G = ['# generated by tools/vga_assets.py - do not edit']
    for lv in gcol_bytes():
        G.append('        .byte ' + ','.join(str(v) for v in lv))
    open(os.path.join(BUILD, 'gcol.s'), 'w').write('\n'.join(G) + '\n')
    L = []
    L.append('# generated by tools/vga_assets.py - do not edit')
    L.append('        .intel_syntax noprefix')
    L.append('t_sprite_keys:')
    L.append('        .word ' + ','.join('0x%04X' % k for k, _ in sprite_tab))
    L.append('t_sprite_paras:')
    L.append('        .word ' + ','.join('0x%04X' % p for _, p in sprite_tab))
    L.append('t_glyph:')
    for i in range(0, len(glyph_tab), 16):
        L.append('        .word ' + ','.join('0x%04X' % v for v in glyph_tab[i:i + 16]))
    L.append('t_title:')
    L.append('        .word ' + ','.join('0x%04X' % v for v in title_tab))
    L.append('t_scen:     # level, cga_base, cga_size, vga_para, or_blit')
    for lvl, base, size, para, orb in scen_tab:
        L.append('        .word %d,0x%04X,%d,0x%04X,%d' % (lvl, base, size, para, orb))
    L.append('t_palette:')
    for i in range(0, 256, 8):
        L.append('        .byte ' + ','.join('%d,%d,%d' % tuple(c >> 2 for c in ((255, 255, 255) if j == 3 else PALETTE[j])) for j in range(i, i + 8)))
    open(os.path.join(BUILD, 'tables.s'), 'w').write('\n'.join(L) + '\n')
    info['asset_bytes'] = len(pk.buf)
    json.dump(info, open(os.path.join(BUILD, 'assets_info.json'), 'w'), indent=1)


if __name__ == '__main__':
    r = build()
    write_tables(*r)
    print(r[-1])
