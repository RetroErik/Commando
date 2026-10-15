"""Rule-based recolouring of the original CGA artwork into the proposed 256-colour VGA palette.

Every function takes a pixel grid (rows of 0..3 or None = transparent) and returns a grid of palette indices
(or None).  Dimensions, transparency and pixel positions are never changed: only the colour of each existing
pixel is decided (from its original colour, its role in the sprite and its neighbours -> simple top-left lighting).
"""
from vga_palette import ramp_color as rc, RAMP_IDX


def void(g, x, y, black_is_void=True):
    if y < 0 or y >= len(g) or x < 0 or x >= len(g[y]):
        return True
    v = g[y][x]
    return v is None or (black_is_void and v == 0)


def adj(g, x, y):
    """Light direction from the top-left: +1 for each exposed top/left side, -1 for exposed bottom/right."""
    s = 0
    if void(g, x, y - 1):
        s += 1
    if void(g, x - 1, y):
        s += 1
    if void(g, x, y + 1):
        s -= 1
    if void(g, x + 1, y):
        s -= 1
    if void(g, x - 1, y - 1) and s >= 0:
        s += 0.5
    return s


def mapgrid(g, fn):
    h = len(g)
    return [[None if v is None else fn(v, x, y, g, h, len(row)) for x, v in enumerate(row)] for y, row in enumerate(g)]


def clampi(v, lo, hi):
    return max(lo, min(hi, v))


# ------------------------------------------------------------------ characters
def character(g, kind, head_frac=0.32):
    body_c = 2 if kind == 'hero' else 1
    cloth = 'hero_cloth' if kind == 'hero' else 'enemy_cloth'
    head_rows = max(4, round(len(g) * head_frac))

    def fn(v, x, y, g, h, w):
        a = adj(g, x, y)
        grad = (0.5 - y / max(1, h - 1)) * 1.2
        if v == 0:
            return rc(cloth, 0)
        if v == body_c:
            return rc(cloth, clampi(round(3.6 + a * 0.9 + grad), 1, 6))
        if v == 3:
            if y < head_rows:
                return rc('skin', clampi(round(2.6 + a * 0.8 + grad * 0.6), 0, 5))
            return rc('khaki', clampi(round(4.2 + a * 0.7 + grad * 0.6), 1, 6))
        # the other accent colour: weapon steel (hero) / red sash (enemy)
        if kind == 'hero':
            return rc('steel', clampi(round(4.4 + a * 0.8), 1, 7))
        return rc('hero_cloth', clampi(round(3.6 + a * 0.8), 1, 6))
    return mapgrid(g, fn)


# ------------------------------------------------------------------ effects, bullets
def effect(g):
    h = len(g)
    w = max(len(r) for r in g)
    cx, cy = (w - 1) / 2, (h - 1) / 2

    def fn(v, x, y, g_, h_, w_):
        d = (((x - cx) / max(1, w / 2)) ** 2 + ((y - cy) / max(1, h / 2)) ** 2) ** 0.5
        glow = (1 - min(1, d)) * 1.2
        base = {3: 6.8, 1: 5.0, 2: 3.6, 0: 1.0}[v]
        if v == 0:
            return rc('smoke', 1)
        return rc('fire', clampi(round(base + glow), 1, 8))
    return mapgrid(g, fn)


def bullet(g):
    def fn(v, x, y, g_, h, w):
        return rc('tracer', {3: 5, 1: 3.4, 2: 2, 0: 0}[v])
    return mapgrid(g, fn)


def gold_text(g, top=7.2, bottom=3.2, shadow=True):
    h = len(g)

    def fn(v, x, y, g_, h_, w_):
        t = y / max(1, h - 1)
        if v == 0:
            return rc('bronze', 0)
        return rc('gold', clampi(round(top + (bottom - top) * t), 0, 7))
    return mapgrid(g, fn)


def steel_ui(g):
    """Bevelled steel for frame pieces / cursor."""
    def fn(v, x, y, g_, h, w):
        a = adj(g_, x, y)
        return rc('steel', clampi(round(5.0 + a * 1.1), 1, 7))
    return mapgrid(g, fn)


# ------------------------------------------------------------------ objects / vehicles
def crate(g):
    def fn(v, x, y, g_, h, w):
        a = adj(g_, x, y)
        if v == 0:
            return rc('olive', 0)
        if v == 1:
            return rc('olive', clampi(round(5.2 + a * 0.6), 3, 6))
        if v == 2:
            return rc('olive', clampi(round(3.8 + a * 0.6), 2, 5))
        return rc('khaki', clampi(round(5.6 + a * 0.6), 3, 6))
    return mapgrid(g, fn)


def vehicle(g, body_c, body_ramp='olive', accent_ramp='brick'):
    def fn(v, x, y, g_, h, w):
        a = adj(g_, x, y)
        grad = (0.5 - y / max(1, h - 1)) * 0.8
        if v == 0:
            return rc('gray', 1)
        if v == body_c:
            return rc(body_ramp, clampi(round(3.6 + a * 0.8 + grad), 1, 6))
        if v == 3:
            return rc('khaki', clampi(round(4.4 + a * 0.6 + grad), 2, 6))
        other = 'enemy_cloth' if v == 1 else accent_ramp
        return rc(other, clampi(round(3.6 + a * 0.8), 1, 6))
    return mapgrid(g, fn)


def grenade(g):
    def fn(v, x, y, g_, h, w):
        a = adj(g_, x, y)
        if v == 0:
            return rc('olive', 0)
        return rc('olive', clampi(round({1: 4.0, 2: 3.0, 3: 5.4}[v] + a * 0.6), 1, 6))
    return mapgrid(g, fn)


def side_pod(g):
    def fn(v, x, y, g_, h, w):
        a = adj(g_, x, y)
        if v == 0:
            return rc('leaf', 0)
        if v == 1:
            return rc('leaf', clampi(round(3.8 + a * 0.9 + (x / w - 0.5) * -0.8), 1, 6))
        if v == 2:
            return rc('brick', clampi(round(3.2 + a * 0.9), 1, 5))
        return rc('sand', clampi(round(4.6 + a * 0.7), 2, 6))
    return mapgrid(g, fn)


def title_logo(g):
    h = len(g)

    def fn(v, x, y, g_, h_, w_):
        t = y / max(1, h - 1)
        if v == 3:
            return rc('gold', clampi(round(7.0 - 3.6 * t), 2, 7))
        if v == 1:
            return rc('bronze', 4 - (1 if y % 2 else 0) - (1 if t > 0.55 else 0))
        if v == 2:
            return rc('bronze', 2 - (1 if t > 0.55 else 0))
        return rc('bronze', 0)
    return mapgrid(g, fn)


# ------------------------------------------------------------------ scenery (copy-blit bitmaps have no transparency)
def palm(g):
    h = len(g)
    # find the ground-dot band at the bottom (white pixels in the last rows)
    def fn(v, x, y, g_, h_, w_):
        a = adj(g_, x, y)
        if v == 1:
            return rc('leaf', clampi(round(4.0 + a * 0.9 + (0.5 - y / 44.0) * 1.4), 1, 6))
        if v == 3:
            if y >= 46:
                return rc('rock', 4)   # sand / pebble speckles around the trunk base
            return rc('leaf', 7)
        if v == 2:
            ring = 1 if (y // 3) % 2 else 0
            return rc('trunk', clampi(round(3.0 + a * 0.8 - ring), 1, 5))
        return rc('jungle', 0)
    return mapgrid(g, fn)


def cliff(g):
    def fn(v, x, y, g_, h, w):
        if v == 0:
            return rc('rock', 0 if (x + y) % 3 else 1)
        if v == 1:
            return rc('sand', clampi(round(4.0 + (0.5 - y / h) * 1.4 + (1 if (x + y) % 5 == 0 else 0)), 2, 6))
        return rc('sand', 6)
    return mapgrid(g, fn)


def pebbles(g):
    def fn(v, x, y, g_, h, w):
        return rc('rock', {0: 0, 1: 4, 2: 3, 3: 5}[v])
    return mapgrid(g, fn)


def wall(g):
    def fn(v, x, y, g_, h, w):
        if v == 0:
            return rc('stone', 0)
        if v == 1:
            return rc('stone', 4 + (1 if (x + y) % 2 else 0))
        if v == 2:
            return rc('brick', clampi(3 + (1 if (x + y) % 2 else 0) + (1 if x % 7 == 0 else 0), 1, 5))
        return rc('stone', 7)
    return mapgrid(g, fn)


def gate(g):
    def fn(v, x, y, g_, h, w):
        a = adj(g_, x, y)
        if v == 3:
            return rc('steel', clampi(round(6.0 + a * 0.8), 3, 7))
        if v == 0:
            return rc('steel', 0)
        if v == 1:
            return rc('stone', 3 + (1 if (x + y) % 2 else 0))
        return rc('brick', clampi(3 + (1 if (x + y) % 2 else 0), 1, 5))
    return mapgrid(g, fn)


def ground_swatch(kind, w=64, h=40):
    """Return a grid of palette indices for the ground fill of each level."""
    import random
    rnd = random.Random(7)
    g = []
    for y in range(h):
        row = []
        for x in range(w):
            if kind == 'L1':
                r = rnd.random()
                row.append(rc('jungle', 1 + (1 if r > 0.8 else 0) - (1 if r < 0.1 else 0)) if r < 0.97 else rc('leaf', 2))
            elif kind == 'L2':
                row.append(rc('sand', 3 if (x + y) % 2 == 0 else 2))
            else:
                row.append(rc('stone', 3 if (x + y) % 2 == 0 else 2))
        g.append(row)
    return g


# ------------------------------------------------------------------ generic themed scenery (all level bitmaps)
def themed(g, spec, transparent=(), gain_default=0.7):
    """spec: {cga value: (ramp, base level, light gain)}; values in `transparent` become colour key 0."""
    def fn(v, x, y, g_, h, w):
        if v in transparent:
            return None
        ramp, base, gain = spec[v]
        a = adj(g_, x, y)
        return rc(ramp, clampi(round(base + a * gain), 0, len(RAMP_IDX[ramp]) - 1))
    return mapgrid(g, fn)


THEMES = {
    'bush':   ({0: ('leaf', 1, 0), 1: ('leaf', 5, 0.8), 2: ('leaf', 3, 0.7), 3: ('leaf', 7, 0.5)}, (0,)),
    'bigbush': ({0: ('leaf', 0, 0), 1: ('leaf', 4, 1.0), 2: ('leaf', 2, 0.7), 3: ('leaf', 6, 0.8)}, (0,)),
    'rock':   ({0: ('stone', 1, 0), 1: ('stone', 4, 0.9), 2: ('stone', 2, 0.7), 3: ('stone', 6, 0.7)}, (0,)),
    'wall':   ({0: ('stone', 0, 0), 1: ('stone', 4, 0.5), 2: ('brick', 3, 0.7), 3: ('stone', 6, 0.5)}, ()),
    'metal':  ({0: ('steel', 1, 0), 1: ('steel', 4, 0.8), 2: ('brick', 3, 0.6), 3: ('steel', 6, 0.6)}, ()),
    'roof':   ({0: ('steel', 0, 0), 1: ('steel', 4, 0.5), 2: ('brick', 3, 0.5), 3: ('steel', 6, 0.5)}, (0,)),
    'bunker': ({0: ('stone', 1, 0), 1: ('steel', 6, 0.6), 2: ('brick', 3, 0.7), 3: ('stone', 5, 0.8)}, (0,)),
    'dune':   ({0: ('sand', 2, 0), 1: ('sand', 3, 0), 2: ('rock', 3, 0.8), 3: ('sand', 6, 0.4)}, ()),
    'trench': ({0: ('rock', 0, 0), 1: ('sand', 3, 0), 2: ('rock', 2, 0.6), 3: ('sand', 5, 0.4)}, ()),
    'water':  ({0: ('water', 1, 0), 1: ('water', 3, 0.7), 2: ('rock', 3, 0.7), 3: ('water', 5, 0.5)}, ()),
    'hedge':  ({0: ('stone', 1, 0), 1: ('stone', 3, 0.5), 2: ('brick', 3, 0.9), 3: ('stone', 5, 0.5)}, ()),
    'tower':  ({0: ('stone', 1, 0), 1: ('steel', 4, 0.6), 2: ('wood', 3, 1.0), 3: ('sand', 5, 0.7)}, (0,)),
    'pole':   ({0: ('stone', 1, 0), 1: ('steel', 4, 0.6), 2: ('brick', 3, 0.7), 3: ('stone', 6, 0.5)}, (0,)),
}


# ------------------------------------------------------------------ textured bush and solid rock (level 1 cover objects)
def _hash(x, y, s=0):
    return ((x * 73856093) ^ (y * 19349663) ^ (s * 83492791)) & 0xFFFF


def bush_textured(g):
    """Cyan mass -> leafy canopy with clumps; dithered lower part -> dark foliage speckles/grass tips."""
    h = len(g)
    w = len(g[0])

    def fn(v, x, y, g_, h_, w_):
        if v == 0:
            return None
        a = adj(g_, x, y)
        if v == 1:   # canopy
            clump = ((x // 3 + y // 2) % 3) - 1            # soft clumps
            n = (_hash(x, y) % 5 == 0)
            lvl = 4.0 + a * 0.9 + clump * 0.8 + (1.0 if n else 0.0) - (y / max(1, h)) * 0.6
            return rc('leaf', clampi(round(lvl), 1, 7))
        # white / other dithered pixels below the canopy: leaf tips and shadowed grass
        lvl = 2.0 + (1.5 if (x + y) % 2 == 0 else 0.0) + (1.0 if _hash(x, y, 3) % 4 == 0 else 0.0)
        return rc('leaf', clampi(round(lvl), 1, 6))
    return mapgrid(g, fn)


def _hull(points):
    pts = sorted(set(points))
    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lo, up = [], []
    for p in pts:
        while len(lo) >= 2 and cross(lo[-2], lo[-1], p) <= 0:
            lo.pop()
        lo.append(p)
    for p in reversed(pts):
        while len(up) >= 2 and cross(up[-2], up[-1], p) <= 0:
            up.pop()
        up.append(p)
    return lo[:-1] + up[:-1]


def _inside(poly, x, y):
    n = len(poly)
    s = None
    for i in range(n):
        x0, y0 = poly[i]
        x1, y1 = poly[(i + 1) % n]
        c = (x1 - x0) * (y - y0) - (y1 - y0) * (x - x0)
        if c != 0:
            if s is None:
                s = c > 0
            elif s != (c > 0):
                return False
    return True


def rock_solid(g):
    """Solid, faceted boulder (light from the top left) inside the hull of the original hatched silhouette.
    Cyan pixels stay grass tufts; the detached white pixels at the lower right become small pebbles."""
    h = len(g)
    w = len(g[0])
    main = [(x, y) for y in range(h) for x in range(min(w, 21)) if g[y][x] == 3 and y <= 18 and x <= 19]
    poly = _hull([(x - 0.5, y - 0.5) for x, y in main] + [(x + 1.5, y - 0.5) for x, y in main] +
                 [(x - 0.5, y + 0.5) for x, y in main] + [(x + 1.5, y + 0.5) for x, y in main])
    inside = {(x, y) for y in range(h) for x in range(w) if _inside(poly, x + 0.5, y + 0.5)}
    ys = [y for _, y in inside]
    xs = [x for x, _ in inside]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0 + 1.5
    rx, ry = (x1 - x0) / 2.0 + 1, (y1 - y0) / 2.0 + 1
    seeds = [(cx - 0.35 * rx, cy - 0.35 * ry, 0.9), (cx + 0.30 * rx, cy - 0.45 * ry, 0.1), (cx + 0.05 * rx, cy + 0.05 * ry, 0.5),
             (cx - 0.45 * rx, cy + 0.30 * ry, -0.2), (cx + 0.45 * rx, cy + 0.25 * ry, -0.7), (cx - 0.05 * rx, cy + 0.55 * ry, -0.9)]
    out = [[None] * w for _ in range(h)]
    edge = set()
    for (x, y) in inside:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            if (x + dx, y + dy) not in inside:
                edge.add((x, y))
    cell = {}
    for (x, y) in inside:
        best = min(range(len(seeds)), key=lambda i: (x - seeds[i][0]) ** 2 + (y - seeds[i][1]) ** 2)
        cell[(x, y)] = best
    for (x, y) in inside:
        nx, ny = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
        z = max(0.0, 1.0 - nx * nx - ny * ny) ** 0.5
        lam = (-nx * 0.55 - ny * 0.65 + z * 0.55)               # light from the upper left
        lvl = 3.6 + lam * 2.0 + seeds[cell[(x, y)]][2] * 0.9    # facet brightness
        lvl += ((_hash(x, y, 9) % 5) - 2) * 0.28               # grain
        nb = [cell.get((x + dx, y + dy)) for dx, dy in ((1, 0), (0, 1))]
        if any(n is not None and n != cell[(x, y)] for n in nb):
            lvl -= 1.3                                         # crack lines between facets
        if (x, y) in edge:
            lvl = min(lvl, 2.0) - 1.4                          # dark outline
        if y >= y1 - 1:
            lvl -= 0.9                                         # contact shadow
        out[y][x] = rc('stone', clampi(round(lvl), 0, 7))
    for y in range(h):
        for x in range(w):
            if (x, y) in inside:
                continue
            if g[y][x] == 1:
                out[y][x] = rc('leaf', clampi(round(4.0 + ((_hash(x, y, 5) % 3) - 1)), 2, 6))
            elif g[y][x] == 3 and (x > 19 or y > 18):
                out[y][x] = rc('stone', clampi(4 + (_hash(x, y, 7) % 3), 3, 6))
    return out

def rock_murky(g):
    """Previous (approved-by-eye) rock: low-contrast stone fill between the outermost hatch dots of each row,
    light speckle where the original had dots, green grass tufts for the cyan pixels."""
    h = len(g)
    w = len(g[0])
    cy = h * 0.45
    out = [[None] * w for _ in range(h)]
    spans = {}
    for y in range(h):
        xs = [x for x in range(w) if g[y][x] in (3, 2)]
        if len(xs) >= 2 and max(xs) - min(xs) >= 3:
            spans[y] = (min(xs), max(xs))
    for y, (x0, x1) in spans.items():
        for x in range(x0, x1 + 1):
            t = (x - x0) / max(1, x1 - x0)
            vshade = 1.0 - abs(y - cy) / max(6.0, h * 0.5)
            lvl = 3.9 + vshade * 1.5 - t * 1.5 + ((_hash(x, y) % 3) - 1) * 0.3
            if g[y][x] in (3, 2):
                lvl += 0.7
            if x in (x0, x1) or y == min(spans) or y == max(spans):
                lvl -= 2.2
            out[y][x] = rc('stone', clampi(round(lvl), 0, 7))
    for y in range(h):
        for x in range(w):
            if g[y][x] == 1:
                out[y][x] = rc('leaf', clampi(round(4.0 + ((_hash(x, y, 5) % 3) - 1)), 2, 6))
    return out
