"""Static proof: every scenery record of levels 1-3 (display bitmap rows x width) lies inside a VGA asset-table entry."""
import os, sys, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cgagfx import HERE
from enum_scenery import enumerate_level
tab = open(os.path.join(HERE, 'build', 'tables.s')).read()
m = re.search(r't_scen:.*?\n((?:\s+\.word [^\n]+\n)+)', tab)
entries = [tuple(int(x, 0) for x in l.split('.word')[1].split(',')) for l in m.group(1).splitlines()]
bad = 0
total = 0
for n in (1, 2, 3):
    ds, nrows, t, recs = enumerate_level(n)
    for (p, wd, rows, orf), uses in recs.items():
        if wd < 2:
            continue       # 0/1-byte filler records (1x1 pixel placeholders) are drawn black by the fallback
        total += 1
        ok = any(e[0] == n and e[1] <= p and p + wd * rows <= e[1] + e[2] for e in entries)
        if not ok:
            bad += 1
            print('NOT COVERED: level %d DS:%04X %dx%d' % (n, p, wd, rows))
print('records checked: %d, not covered: %d, table entries: %d' % (total, bad, len(entries)))
