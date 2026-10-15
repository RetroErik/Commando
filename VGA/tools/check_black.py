import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from catalog_sprites import all_sprites
from collections import deque

def exterior_zero(g):
    h = len(g); w = len(g[0])
    seen = set(); q = deque()
    for y in range(h):
        for x in range(w):
            if (x in (0, w - 1) or y in (0, h - 1)) and g[y][x] == 0:
                q.append((x, y)); seen.add((x, y))
    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and g[ny][nx] == 0 and (nx, ny) not in seen:
                seen.add((nx, ny)); q.append((nx, ny))
    return seen

def main():
    for sp in all_sprites():
        for name in ('even', 'odd'):
            g = sp[name]
            if not g:
                continue
            total = sum(len(r) for r in g)
            zero = sum(1 for r in g for v in r if v == 0)
            ext = len(exterior_zero(g))
            partial = 0
            if ext or zero > total * 0.3:
                print('%04X %-14s %-4s opaque0=%d exterior0=%d of %d' % (sp['d'], sp['group'], name, zero, ext, total))
    

if __name__ == '__main__':
    main()

