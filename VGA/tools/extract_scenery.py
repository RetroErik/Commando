"""Extract the scenery bitmaps referenced by the level scenery records (traced from the emulator)."""
import os, sys, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cgagfx import CGA_PAL, HERE
from atlas_orig import atlas
from PIL import Image

AN = os.path.join(HERE, 'analysis')
EXTRACT = os.path.join(HERE, 'extracted')


def load_records(n):
    ds = open(os.path.join(AN, 'ds_level%d.bin' % n), 'rb').read()
    recs = []
    for l in open(os.path.join(AN, 'records_level%d.txt' % n)):
        h, cnt = l.split()
        b = bytes.fromhex(h)
        recs.append(dict(col=b[2], ptr28=b[3] | (b[4] << 8), rows=b[5], row0=b[6] | (b[7] << 8), ptr56=b[8] | (b[9] << 8),
                         attr=b[10], orflag=b[11], width=b[12], uses=int(cnt), raw=h))
    if n != 1:   # after game over the demo restarts on level 1 data; drop the level 1 records seen again
        l1 = set()
        for l in open(os.path.join(AN, 'records_level1.txt')):
            b = bytes.fromhex(l.split()[0])
            l1.add(b[8] | (b[9] << 8))
        recs = [r for r in recs if r['ptr56'] not in l1]
    return ds, recs


def bitmap_rows(ds, off, w, h):
    rows = []
    for y in range(h):
        row = []
        for x in range(w):
            b = ds[off + y * w + x]
            for p in range(4):
                row.append((b >> (6 - 2 * p)) & 3)
        rows.append(row)
    return rows


def attr_rows(ds, off, w, h):
    """layer-28 attribute map: show 2-bit values as gray levels for documentation only"""
    rows = []
    for y in range(h):
        row = []
        for x in range(w):
            b = ds[off + y * w + x]
            for p in range(4):
                row.append((b >> (6 - 2 * p)) & 3)
        rows.append(row)
    return rows


def main():
    cat = {}
    cells = []
    seen = set()
    GRAY = [(20, 20, 20), (90, 90, 90), (170, 170, 170), (255, 255, 255)]
    attr_cells = []
    for n in (1, 2, 3):
        try:
            ds, recs = load_records(n)
        except FileNotFoundError:
            continue
        for r in recs:
            key = (n, r['ptr56'], r['width'], r['rows'])
            if key in seen:
                continue
            seen.add(key)
            rows = bitmap_rows(ds, r['ptr56'], r['width'], r['rows'])
            name = 'L%d_%04X' % (n, r['ptr56'])
            cells.append(('L%d  DS:%04X  %dx%d  %s' % (n, r['ptr56'], r['width'] * 4, r['rows'], 'OR-blit' if r['orflag'] else 'copy-blit'), rows))
            w28 = (r['width'] + 1) // 2
            arows = attr_rows(ds, r['ptr28'], w28, r['rows'])
            attr_cells.append(('L%d  DS:%04X  attr %dx%d' % (n, r['ptr28'], w28 * 4, r['rows']), arows))
            raw = bytes(ds[r['ptr56']: r['ptr56'] + r['width'] * r['rows']])
            cat[name] = dict(level=n, ds_offset=r['ptr56'], width_bytes=r['width'], rows=r['rows'], or_blit=bool(r['orflag']),
                             attr_ptr=r['ptr28'], attr_width_bytes=w28, record=r['raw'], uses=r['uses'])
            open(os.path.join(EXTRACT, 'scenery_%s.bin' % name), 'wb').write(raw)
            open(os.path.join(EXTRACT, 'scenery_%s_attr.bin' % name), 'wb').write(bytes(ds[r['ptr28']: r['ptr28'] + w28 * r['rows']]))
    print(len(cells), 'scenery bitmaps')
    atlas(cells, os.path.join(HERE, 'atlas', 'scenery_cga.png'), 4, 3, 'Scenery bitmaps from the level data (DAT tracks 28-39), 2bpp, drawn into the scrolling ground buffer')
    atlas(attr_cells, os.path.join(HERE, 'atlas', 'scenery_collision_attr.png'), 4, 3,
          'Scenery attribute/collision layer (second bitmap of every record; read by gameplay logic, never displayed)', pal=GRAY)
    json.dump(cat, open(os.path.join(EXTRACT, 'scenery_catalog.json'), 'w'), indent=1)


if __name__ == '__main__':
    main()


