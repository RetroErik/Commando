"""Convert a DOSBox 320x200 screenshot of a CGA mode 4 screen into 2bpp pixel indices (0-3)."""
import sys, os
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cgagfx import CGA_PAL


def shot_to_idx(path):
    im = Image.open(path).convert('RGB')
    assert im.size == (320, 200), im.size
    px = im.load()
    pal = CGA_PAL
    out = []
    for y in range(200):
        row = []
        for x in range(320):
            c = px[x, y]
            best = min(range(4), key=lambda i: sum((c[k] - pal[i][k]) ** 2 for k in range(3)))
            row.append(best)
        out.append(row)
    return out


def idx_to_bytes(idx):
    """Rows of pixel indexes -> list of rows of packed bytes."""
    rows = []
    for r in idx:
        b = []
        for x in range(0, len(r) - 3, 4):
            b.append((r[x] << 6) | (r[x + 1] << 4) | (r[x + 2] << 2) | r[x + 3])
        rows.append(bytes(b))
    return rows
