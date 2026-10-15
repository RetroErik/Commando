"""Generate the original-CGA atlases and the PROPOSED VGA preview sheets (nothing here touches the game)."""
import os, sys, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image, ImageDraw, ImageFont
from cgagfx import *
from catalog_sprites import all_sprites
from vga_palette import PALETTE, RAMP_IDX, ramp_color as rc
import vga_art as art
from atlas_orig import checker, BG, FONT, FONT_B
import extract_scenery as xs

ATLAS = os.path.join(HERE, 'atlas')
PREVIEW = os.path.join(HERE, 'preview')
os.makedirs(ATLAS, exist_ok=True)
os.makedirs(PREVIEW, exist_ok=True)


def img_from(grid, pal, scale, bg=None):
    h = len(grid)
    w = max(len(r) for r in grid)
    im = Image.new('RGBA', (w * scale, h * scale), (0, 0, 0, 0))
    px = im.load()
    for y, r in enumerate(grid):
        for x, c in enumerate(r):
            if c is None:
                continue
            col = pal[c] + (255,)
            for dy in range(scale):
                for dx in range(scale):
                    px[x * scale + dx, y * scale + dy] = col
    return im


def vga_for(sp):
    g, rows = sp['group'], sp['even']
    if g in ('hero', 'hero_fire'):
        return art.character(rows, 'hero')
    if g == 'hero_cheer':
        return art.character(rows, 'hero', 0.45)
    if g == 'hero_down':
        return art.character(rows, 'hero', 0.5)
    if g == 'title_art':
        return art.character(rows, 'hero', 0.26)
    if g in ('enemy_soldier', 'enemy_dying'):
        return art.character(rows, 'enemy')
    if g == 'enemy_armsup':
        return art.character(rows, 'enemy', 0.45)
    if g == 'enemy_down':
        return art.character(rows, 'enemy', 0.55)
    if g == 'side_art':
        return art.side_pod(rows)
    if g in ('grenade_stock', 'supply_crate'):
        return art.crate(rows)
    if g == 'grenade':
        return art.grenade(rows)
    if g == 'motorbike':
        return art.vehicle(rows, 2, 'brick', 'olive')
    if g == 'jeep':
        return art.vehicle(rows, 2, 'olive')
    if g == 'truck':
        return art.vehicle(rows, 1, 'olive')
    if g == 'gun_emplacement':
        return art.vehicle(rows, 1, 'steel', 'brick')
    if g.startswith('effect'):
        return art.effect(rows)
    if g == 'bullet':
        return art.bullet(rows)
    if g == 'points':
        return art.gold_text(rows)
    if g == 'cursor':
        return art.steel_ui(rows)
    return None


def pair_sheet(items, path, title, cols, scale, subtitle=None):
    """items: (label, cga_grid, vga_grid).  Left = original CGA, right = proposed VGA, both enlarged x`scale` for viewing only."""
    tiles = []
    for lab, o, v in items:
        io = img_from(o, [tuple(c) for c in CGA_PAL], scale)
        iv = img_from(v, PALETTE, scale)
        tiles.append((lab, io, iv))
    cw = max(i.width + 8 + j.width for _, i, j in tiles) + 16
    ch = max(max(i.height, j.height) for _, i, j in tiles) + 34
    rows = (len(tiles) + cols - 1) // cols
    head = 44
    sheet = Image.new('RGB', (cols * cw, rows * ch + head), BG)
    d = ImageDraw.Draw(sheet)
    d.text((10, 6), title, fill=(255, 230, 120), font=FONT_B)
    d.text((10, 24), subtitle or 'left: original CGA   |   right: PROPOSED 256-colour VGA   (enlarged x%d for inspection only - game assets stay 1:1)' % scale,
           fill=(170, 200, 255), font=FONT)
    for n, (lab, io, iv) in enumerate(tiles):
        x, y = (n % cols) * cw, (n // cols) * ch + head
        d.text((x + 8, y + 4), lab, fill=(225, 225, 225), font=FONT)
        for k, im in enumerate((io, iv)):
            ox = x + 8 + k * (io.width + 8)
            if k == 0:
                bgim = Image.new('RGB', im.size, (0, 0, 0))
                d.rectangle([ox - 1, y + 21, ox + im.width, y + 22 + im.height], outline=(90, 90, 110))
            else:
                bgim = checker(im.width, im.height, 8)
                d.rectangle([ox - 1, y + 21, ox + im.width, y + 22 + im.height], outline=(90, 90, 110))
            sheet.paste(bgim, (ox, y + 22))
            sheet.paste(im, (ox, y + 22), im)
    sheet.save(path)
    return sheet.size


def cga_sheet(items, path, title, cols, scale):
    tiles = [(lab, img_from(o, [tuple(c) for c in CGA_PAL], scale)) for lab, o in items]
    cw = max(i.width for _, i in tiles) + 16
    ch = max(i.height for _, i in tiles) + 34
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new('RGB', (cols * cw, rows * ch + 30), BG)
    d = ImageDraw.Draw(sheet)
    d.text((10, 6), title, fill=(255, 230, 120), font=FONT_B)
    for n, (lab, im) in enumerate(tiles):
        x, y = (n % cols) * cw, (n // cols) * ch + 30
        d.text((x + 8, y + 4), lab, fill=(225, 225, 225), font=FONT)
        sheet.paste(Image.new('RGB', im.size, (0, 0, 0)), (x + 8, y + 22))
        sheet.paste(im, (x + 8, y + 22), im)
    sheet.save(path)


SHEETS = {
    'hero': (['hero', 'hero_fire', 'hero_cheer', 'hero_down'], 'Hero (Super Joe) - 26 frames', 4, 4, 8),
    'enemies': (['enemy_soldier', 'enemy_armsup', 'enemy_down', 'enemy_dying'], 'Enemy soldiers - 27 frames', 4, 4, 8),
    'vehicles_objects': (['jeep', 'truck', 'motorbike', 'gun_emplacement', 'supply_crate', 'grenade', 'grenade_stock', 'cursor', 'title_art'],
                         'Vehicles, objects, pickups, panel pieces', 4, 3, 5),
    'effects': (['effect_burst', 'effect_blast', 'effect_skull', 'bullet', 'points'], 'Effects, bullets and score pop-ups', 4, 6, 8),
}


def main():
    sprites = all_sprites()
    by_group = {}
    for sp in sprites:
        by_group.setdefault(sp['group'], []).append(sp)

    # ---- original CGA atlases by category + proposed VGA previews
    sizes = {}
    for key, (groups, title, cols, scale, ccols) in SHEETS.items():
        items_o, items_p = [], []
        for g in groups:
            for sp in by_group.get(g, []):
                lab = '%04X %dx%d %s' % (sp['d'], sp['w'] * 4, sp['h'], g)
                items_o.append((lab, sp['even']))
                items_p.append((lab, sp['even'], vga_for(sp)))
        cga_sheet(items_o, os.path.join(ATLAS, 'orig_%s_cga.png' % key), 'ORIGINAL CGA - ' + title, ccols, scale)
        sizes[key] = pair_sheet(items_p, os.path.join(PREVIEW, '%s_vga.png' % key), 'PROPOSED VGA - ' + title, cols, scale)
    print('sheets', sizes)

    # ---- palette
    pal_sheet(os.path.join(PREVIEW, 'palette_vga.png'))
    scenery_sheet()
    ui_sheet()
    mock_sheet(by_group)


def pal_sheet(path):
    sw = 26
    names = list(RAMP_IDX)
    W, H = 260 + 12 * sw, 60 + len(names) * (sw + 4)
    sheet = Image.new('RGB', (W, H), BG)
    d = ImageDraw.Draw(sheet)
    d.text((10, 8), 'PROPOSED VGA PALETTE (mode 13h, 256 entries) - named ramps, dark -> light', fill=(255, 230, 120), font=FONT_B)
    d.text((10, 28), 'index 0 = black (also the colour-key for transparent sprite pixels); %d entries used, %d free for later effects' % (len([c for c in PALETTE]) - PALETTE.count((0, 0, 0)) + 1, PALETTE.count((0, 0, 0)) - 1), fill=(170, 200, 255), font=FONT)
    for r, name in enumerate(names):
        y = 56 + r * (sw + 4)
        d.text((10, y + 6), '%-12s %3d-%-3d' % (name, RAMP_IDX[name][0], RAMP_IDX[name][-1]), fill=(225, 225, 225), font=FONT)
        for i, idx in enumerate(RAMP_IDX[name]):
            d.rectangle([260 + i * sw, y, 260 + i * sw + sw - 2, y + sw - 2], fill=PALETTE[idx])
    sheet.save(path)


def scenery_sheet():
    import json as _j
    cat = _j.load(open(os.path.join(HERE, 'extracted', 'scenery_catalog.json')))
    items = []
    for name, e in cat.items():
        ds = open(os.path.join(HERE, 'extracted', 'scenery_%s.bin' % name), 'rb').read()
        w, h = e['width_bytes'], e['rows']
        rows = []
        for y in range(h):
            r = []
            for x in range(w):
                b = ds[y * w + x]
                for p in range(4):
                    r.append((b >> (6 - 2 * p)) & 3)
            rows.append(r)
        if name == 'L1_AFDE' or name == 'L1_B396':
            v = art.palm(rows)
            # OR-blit bitmaps: colour 0 is transparent
            v = [[None if rows[y][x] == 0 else v[y][x] for x in range(len(rows[y]))] for y in range(h)]
            o = [[None if c == 0 else c for c in r] for r in rows]
        elif name == 'L1_AD38':
            v, o = art.cliff(rows), rows
        elif name == 'L1_AFC4':
            v, o = art.pebbles(rows), rows
        elif name == 'L3_AC56':
            v, o = art.gate(rows), rows
        else:
            v, o = art.wall(rows), rows
        items.append(('%s  DS:%04X  %dx%d %s' % (name[:2], e['ds_offset'], w * 4, h, 'OR-blit' if e['or_blit'] else 'copy'), o, v))
    # ground fills
    for kind, lab in (('L1', 'Level 1 ground (black -> jungle floor)'), ('L2', 'Level 2 ground (cyan/black dither -> sand dither)'),
                      ('L3', 'Level 3 ground (cyan/black dither -> stone dither)')):
        g = art.ground_swatch(kind)
        if kind == 'L1':
            o = [[0] * 64 for _ in range(40)]
        else:
            o = [[1 if (x + y) % 2 == 0 else 0 for x in range(64)] for y in range(40)]
        items.append((lab, o, g))
    print(pair_sheet(items, os.path.join(PREVIEW, 'scenery_vga.png'), 'PROPOSED VGA - Scenery bitmaps (levels 1-3) and ground fills', 2, 3))


def glyph_grid(ch):
    a = DS_BASE + 0xB6 + 36 * ord(ch)
    rows = []
    for y in range(12):
        r = []
        for x in range(3):
            b = IMG[a + y * 3 + x]
            for p in range(4):
                r.append(3 if (b >> (6 - 2 * p)) & 3 else None)
        rows.append(r)
    return rows


def text_grid(s, spacing=12):
    gl = [glyph_grid(c) if c != ' ' else [[None] * 12 for _ in range(12)] for c in s]
    w = spacing * len(s)
    out = [[None] * w for _ in range(12)]
    for i, g in enumerate(gl):
        for y in range(12):
            for x in range(12):
                out[y][i * spacing + x] = g[y][x]
    return out


def ui_sheet():
    items = []
    for s in ('SCORE 000300', 'PRESS FIRE TO START', 'ABCDEFGHIJKLM', 'NOPQRSTUVWXYZ', '0123456789 .'):
        o = text_grid(s)
        items.append(('font: "%s"' % s, o, art.gold_text(o)))
    # frame tiles 0x80-0x89
    tiles = []
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
        tiles.append(rows)
    strip_o = [[None] * (9 * 10) for _ in range(8)]
    for i, t in enumerate(tiles):
        for y in range(8):
            for x in range(8):
                strip_o[y][i * 9 + x] = t[y][x]
    items.append(('frame tiles 80-89 (8x8)', strip_o, art.steel_ui(strip_o)))
    # title logo + hero art
    ptrs = [struct.unpack_from('<H', IMG, 0x193C + 2 * i)[0] for i in range(5)]
    for i, p in enumerate(ptrs[:4]):
        s = menu_sprite_at(p)
        items.append(('title logo piece %d (%dx%d)' % (i, s['w'] * 4, s['h']), s['even'], art.title_logo(s['even'])))
    s = menu_sprite_at(ptrs[4])
    items.append(('title hero (%dx%d)' % (s['w'] * 4, s['h']), s['even'], art.character(s['even'], 'hero', 0.26)))
    for sp in all_sprites():
        if sp['group'] == 'side_art':
            items.append(('side art %04X (%dx%d)' % (sp['d'], sp['w'] * 4, sp['h']), sp['even'], art.side_pod(sp['even'])))
    print(pair_sheet(items, os.path.join(PREVIEW, 'ui_vga.png'), 'PROPOSED VGA - UI: fonts, frame tiles, title logo, side art', 3, 2))


def mock_sheet(by_group):
    W, H = 320, 200
    g = [[0] * W for _ in range(H)]

    def blit(grid, x0, y0):
        for y, r in enumerate(grid):
            for x, c in enumerate(r):
                if c is not None and 0 <= y0 + y < H and 0 <= x0 + x < W:
                    g[y0 + y][x0 + x] = c
    # ground
    sw = art.ground_swatch('L1', 230, 150)
    blit(sw, 45, 10)
    # scenery
    import json as _j
    cat = _j.load(open(os.path.join(HERE, 'extracted', 'scenery_catalog.json')))

    def scen(name):
        e = cat[name]
        ds = open(os.path.join(HERE, 'extracted', 'scenery_%s.bin' % name), 'rb').read()
        rows = [[(ds[y * e['width_bytes'] + x // 4] >> (6 - 2 * (x % 4))) & 3 for x in range(e['width_bytes'] * 4)] for y in range(e['rows'])]
        return rows
    palm_rows = scen('L1_AFDE')
    pv = art.palm(palm_rows)
    pv = [[None if palm_rows[y][x] == 0 else pv[y][x] for x in range(len(palm_rows[y]))] for y in range(len(palm_rows))]
    blit(pv, 128, 8)
    blit(pv, 64, 88)
    blit(pv, 214, 76)
    cr = scen('L1_AD38')
    blit(art.cliff(cr), 233, 40)
    # frame (2px steel) around playfield + panel
    def frame(x0, y0, x1, y1):
        for t in range(2):
            for x in range(x0, x1 + 1):
                g[y0 + t][x] = rc('steel', 7 - t * 2)
                g[y1 - t][x] = rc('steel', 3 - t)
            for y in range(y0, y1 + 1):
                g[y][x0 + t] = rc('steel', 7 - t * 2)
                g[y][x1 - t] = rc('steel', 3 - t)
    frame(44, 9, 275, 160)
    frame(44, 168, 275, 198)
    for y in range(170, 197):
        for x in range(46, 274):
            g[y][x] = 0
    sp = {s['d']: s for s in all_sprites()}
    blit(art.character(sp[0x3DAC]['even'], 'hero'), 150, 98)
    blit(art.character(sp[0x2244]['even'], 'enemy'), 108, 120)
    blit(art.character(sp[0x1E12]['even'], 'enemy'), 232, 20)
    blit(art.character(sp[0x2BF0]['even'], 'enemy'), 188, 62)
    blit(art.bullet(sp[0x804A]['even']), 160, 84)
    blit(art.effect(sp[0x80A6]['even']), 196, 112)
    # side art
    pods = [s for s in all_sprites() if s['group'] == 'side_art']
    for i in range(5):
        blit(art.side_pod(pods[0]['even']), 0, 10 + 35 * i)
        blit(art.side_pod(pods[1]['even']), 280, 10 + 35 * i)
    # panel text
    blit(art.gold_text(text_grid('SCORE')), 76, 174)
    blit(art.gold_text(text_grid('300', 12)), 124, 184)
    blit(art.crate(sp[0x6B8C]['even']), 190, 170)
    blit(art.character(sp[0x52D0]['even'], 'hero', 0.5), 244, 172)
    blit(art.gold_text(text_grid('05', 12)), 246, 185)
    im = img_from(g, PALETTE, 1)
    base = Image.new('RGB', im.size, (0, 0, 0))
    base.paste(im, (0, 0), im)
    base.save(os.path.join(PREVIEW, 'playfield_mock_vga_1to1.png'))
    base.resize((W * 3, H * 3), Image.NEAREST).save(os.path.join(PREVIEW, 'playfield_mock_vga.png'))


if __name__ == '__main__':
    main()


