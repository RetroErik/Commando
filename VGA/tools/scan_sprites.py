"""Scan the whole COMMANDO.EXE load image for sprite records and print a catalog.

Sprite record at image offset A:
    word  odd_off        ; odd-x image header is at A + 2 + odd_off (0 = shares the even image)
    byte  height
    byte  width_bytes    ; 4 CGA pixels per byte
    height*width * (mask, value)
    [odd image: byte height, byte width_bytes, data]
Drawing: screen = (screen & mask) | value  (mask bit pair 11 = transparent)
Data-segment offset D = A - 0x8350.
"""
import os, struct, sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.join(os.path.dirname(HERE), 'Original game files')
EXE = open(os.path.join(ROOT, 'COMMANDO.EXE'), 'rb').read()
IMG = EXE[0x200:]
DS_BASE = 0x8350


def parse_abs(a, min_cells=4):
    if a + 4 > len(IMG):
        return None
    odd_off = struct.unpack_from('<H', IMG, a)[0]
    h, w = IMG[a + 2], IMG[a + 3]
    if not (1 <= h <= 64 and 1 <= w <= 20):
        return None
    n = 2 * h * w
    if a + 4 + n > len(IMG) or h * w < min_cells:
        return None
    body = IMG[a + 4:a + 4 + n]
    bad = sum(1 for i in range(0, n, 2) if body[i] & body[i + 1])
    if bad > n // 40:
        return None
    if all(body[i] == 0xFF for i in range(0, n, 2)):
        return None
    end = a + 4 + n
    if odd_off == 0:
        ow = w
    elif odd_off == 2 + n:
        oh, ow = IMG[a + 4 + n], IMG[a + 5 + n]
        if oh != h or ow not in (w, w + 1, w + 2):
            return None
        end = a + 4 + n + 2 + 2 * oh * ow
        if end > len(IMG):
            return None
    else:
        return None
    return dict(a=a, d=a - DS_BASE, h=h, w=w, ow=ow, odd=(odd_off != 0), end=end, bad=bad)


def scan(lo=0x8350, hi=0x12000):
    found = []
    a = lo
    while a < hi:
        s = parse_abs(a)
        if s:
            found.append(s)
            a = s['end']
        else:
            a += 1
    return found


if __name__ == '__main__':
    lo = int(sys.argv[1], 16) if len(sys.argv) > 1 else 0x8350
    hi = int(sys.argv[2], 16) if len(sys.argv) > 2 else 0x12000
    f = scan(lo, hi)
    print(len(f), 'sprites')
    prev = None
    for s in f:
        gap = ''
        if prev is not None and s['a'] != prev['end']:
            gap = '  gap %d' % (s['a'] - prev['end'])
        print('img %05X  ds %05X-%05X  %2dx%-2d w=%d ow=%d odd=%d bad=%d%s' % (
            s['a'], s['d'] & 0xFFFFF, (s['end'] - DS_BASE) & 0xFFFFF, s['w'] * 4, s['h'], s['w'], s['ow'], s['odd'], s['bad'], gap))
        prev = s
