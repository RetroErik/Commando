"""Render raw regions of the load image as CGA 2bpp bitmaps to spot unlabeled graphics."""
import os, sys
from PIL import Image
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.join(os.path.dirname(HERE), 'Original game files')
EXE = open(os.path.join(ROOT, 'COMMANDO.EXE'), 'rb').read()
IMG = EXE[0x200:]
PAL = [(0, 0, 0), (85, 255, 255), (255, 85, 255), (255, 255, 255)]  # CGA palette 1 high intensity (approx)
PAL = [(0, 0, 0), (0, 170, 0), (170, 0, 0), (170, 85, 0)]  # CGA palette 0 low intensity


def render(lo, hi, bytes_per_row, scale, path):
    n = hi - lo
    rows = (n + bytes_per_row - 1) // bytes_per_row
    im = Image.new('RGB', (bytes_per_row * 4, rows))
    px = im.load()
    for i in range(n):
        b = IMG[lo + i]
        x0 = (i % bytes_per_row) * 4
        y = i // bytes_per_row
        for p in range(4):
            px[x0 + p, y] = PAL[(b >> (6 - 2 * p)) & 3]
    im = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
    im.save(path)


if __name__ == '__main__':
    lo, hi, bpr, sc = int(sys.argv[1], 16), int(sys.argv[2], 16), int(sys.argv[3]), int(sys.argv[4])
    render(lo, hi, bpr, sc, sys.argv[5])
