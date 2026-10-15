"""Side-by-side preview (original CGA | proposed VGA) of ALL scenery bitmaps -> preview/scenery_all_vga.png"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_previews import pair_sheet
import atlas_scenery_all as sa, scenery_map as sm
from cgagfx import HERE

items = []
for b in sa.all_bitmaps():
    g = sa.grid(b)
    v = sm.vga_grid(b['level'], b['ptr'], g, b['orflag'])
    o = [[None if (b['orflag'] and c == 0) else c for c in r] for r in g]
    vv = [[None if c == 0 else c for c in r] for r in v]
    kind = sm.KIND.get((b['level'], b['ptr']), 'wall')
    items.append(('L%d DS:%04X %dx%d %s [%s]' % (b['level'], b['ptr'], b['width'] * 4, b['rows'], 'OR' if b['orflag'] else 'copy', kind), o, vv))
print(pair_sheet(items, os.path.join(HERE, 'preview', 'scenery_all_vga.png'), 'PROPOSED VGA - ALL scenery bitmaps of levels 1-3 (rock, bush, walls, gates, bunkers ...)', 4, 2))
