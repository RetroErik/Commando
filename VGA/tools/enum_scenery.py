"""Statically enumerate ALL scenery records of levels 1-3 from the loaded level data (analysis/ds_level*.bin dumps).

Level blob (already relocated by the game's loader 3A41, base DS:9454):
  +2 word  number of map rows           +4 word  pointer to the row table
  row entry (5 bytes): +0 byte ground fill, +1 word record count, +3 word pointer to the records
  record (13 bytes): +2 col, +3 ptr28 (attribute bitmap), +5 rows, +6 first map row, +8 ptr56 (display bitmap), +A attr, +B OR flag, +C width
"""
import os, sys, struct, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cgagfx import HERE
AN = os.path.join(HERE, 'analysis')
EX = os.path.join(HERE, 'extracted')


def enumerate_level(n):
    ds = open(os.path.join(AN, 'ds_level%d.bin' % n), 'rb').read()
    w = lambda a: struct.unpack_from('<H', ds, a)[0]
    nrows, tab = w(0x9454 + 2), w(0x9454 + 4)
    recs = {}
    for i in range(nrows):
        e = tab + 5 * i
        cnt, ptr = w(e + 1), w(e + 3)
        for k in range(cnt):
            r = ptr + 13 * k
            b = ds[r:r + 13]
            rec = dict(col=b[2], ptr28=b[3] | (b[4] << 8), rows=b[5], row0=b[6] | (b[7] << 8), ptr56=b[8] | (b[9] << 8), attr=b[10], orflag=b[11], width=b[12])
            recs.setdefault((rec['ptr56'], rec['width'], rec['rows'], rec['orflag']), []).append((i, rec['col'], rec['row0']))
    return ds, nrows, tab, recs


if __name__ == '__main__':
    out = {}
    for n in (1, 2, 3):
        ds, nrows, tab, recs = enumerate_level(n)
        print('level', n, 'rows', nrows, 'table', hex(tab), 'distinct bitmaps', len(recs))
        for (p, wd, rows, orf), uses in sorted(recs.items()):
            print('   DS:%04X  %2d bytes x %2d rows  or=%d  uses=%d  (e.g. maprow %d col %d)' % (p, wd, rows, orf, len(uses), uses[0][0], uses[0][1]))
        out[n] = [dict(ptr56=p, width=wd, rows=rows, orflag=orf, uses=len(u)) for (p, wd, rows, orf), u in sorted(recs.items())]
    json.dump(out, open(os.path.join(EX, 'scenery_all_records.json'), 'w'), indent=1)
