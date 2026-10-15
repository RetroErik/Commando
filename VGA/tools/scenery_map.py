"""Which VGA treatment each scenery display bitmap (level, DS pointer) gets.  See atlas/scenery_all_cga.png for the originals."""
import vga_art as art

L1, L2, L3 = 1, 2, 3
KIND = {
    # level 1 (jungle + fortress)
    (L1, 0x945C): 'metal', (L1, 0x95CE): 'wall', (L1, 0x9952): 'bush', (L1, 0x9ACE): 'bush', (L1, 0x9C4A): 'wall', (L1, 0x9E1C): 'wall',
    (L1, 0x9FC0): 'metal', (L1, 0xA2A8): 'metal', (L1, 0xA61C): 'metal', (L1, 0xA8F4): 'metal',
    (L1, 0xAB94): 'bigbush', (L1, 0xAD38): 'bigbush', (L1, 0xAEDC): 'rock', (L1, 0xAFC4): 'pebbles', (L1, 0xAFDE): 'palm', (L1, 0xB396): 'palm',
    # level 2 (desert)
    (L2, 0x945C): 'wall', (L2, 0x94C0): 'wall', (L2, 0x9524): 'wall', (L2, 0x9696): 'wall', (L2, 0x9996): 'wall',
    (L2, 0x9B94): 'dune', (L2, 0x9C78): 'dune', (L2, 0x9E58): 'dune', (L2, 0x9F08): 'dune', (L2, 0x9FEC): 'dune', (L2, 0xA1CC): 'dune',
    (L2, 0xA27C): 'wall', (L2, 0xA44E): 'wall', (L2, 0xA5F2): 'metal', (L2, 0xA8DA): 'metal', (L2, 0xAC4E): 'metal', (L2, 0xAF26): 'metal',
    (L2, 0xB1C6): 'bunker', (L2, 0xB4B2): 'bunker', (L2, 0xB78E): 'trench', (L2, 0xB83E): 'trench', (L2, 0xB8EE): 'trench',
    (L2, 0xB99E): 'water', (L2, 0xBBDA): 'wall',
    # level 3 (fortress yard)
    (L3, 0x945C): 'roof', (L3, 0x9590): 'roof', (L3, 0x96C4): 'roof', (L3, 0x97F8): 'roof', (L3, 0x992C): 'bush', (L3, 0x9AA8): 'bush',
    (L3, 0x9C24): 'wall', (L3, 0x9FAC): 'wall', (L3, 0xA0A2): 'wall', (L3, 0xA198): 'wall', (L3, 0xA372): 'wall', (L3, 0xA54C): 'wall',
    (L3, 0xA642): 'wall', (L3, 0xA738): 'wall', (L3, 0xA924): 'wall', (L3, 0xAA1A): 'hedge', (L3, 0xAC56): 'gate', (L3, 0xB09A): 'pole',
    (L3, 0xB292): 'tower', (L3, 0xB562): 'palm', (L3, 0xB91A): 'palm',
}

BLACK = 255


def vga_grid(level, ptr, rows, orflag):
    """rows = CGA pixel grid (0..3). Returns grid of palette indices, 0 = transparent (colour key), 255 = opaque black."""
    kind = KIND.get((level, ptr), 'wall')
    h, w = len(rows), len(rows[0])
    if kind == 'bigbush':
        v = art.bush_textured(rows)
        return [[0 if v[y][x] is None else v[y][x] for x in range(w)] for y in range(h)]
    if kind == 'rock':
        v = art.rock_murky(rows)   # art.rock_solid = faceted boulder alternative
        return [[0 if v[y][x] is None else v[y][x] for x in range(w)] for y in range(h)]
    if kind == 'palm':
        v = art.palm(rows)
        return [[0 if rows[y][x] == 0 else (v[y][x] or 0) for x in range(w)] for y in range(h)]
    if kind in art.THEMES:
        spec, transp = art.THEMES[kind]
        v = art.themed(rows, spec, transp)
    else:
        fn = {'cliff': art.cliff, 'pebbles': art.pebbles, 'gate': art.gate}[kind]
        v = fn(rows)
    out = [[0 if v[y][x] is None else (BLACK if v[y][x] == 0 else v[y][x]) for x in range(w)] for y in range(h)]
    if kind == 'pebbles':
        out = [[0 if rows[y][x] == 0 else out[y][x] for x in range(w)] for y in range(h)]
    if orflag:
        out = [[0 if rows[y][x] == 0 else out[y][x] for x in range(w)] for y in range(h)]
    return out
