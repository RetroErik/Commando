"""Empirical proof that gameplay does not depend on sprite pixel/mask data.

Run the original game twice in the emulator: once untouched, once with the mask/value bytes of EVERY sprite
record replaced by pseudo-random (but legal) data while the headers (odd offset, height, width) stay intact.
Compare the instruction counts and the complete work-area/variable region of the data segment afterwards.
"""
import os, sys, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu_game import *
from catalog_sprites import all_sprites


def run(scramble, instr=6_000_000, level=1):
    g = Game(os.path.join(ROOT, 'COMMANDO.EXE'))
    c = g.cpu
    base = LOAD_SEG * 16
    if scramble:
        rnd = random.Random(1234)
        for sp in all_sprites():
            a = sp['a']
            regions = [(a + 4, sp['h'] * sp['w'])]
            if sp['odd_off']:
                od = a + 2 + sp['odd_off']
                regions.append((od + 2, sp['oh'] * sp['ow']))
            for start, cells in regions:
                for i in range(cells):
                    m = rnd.choice([0x00, 0x55, 0xAA, 0xFF, 0xC3, 0x3C, rnd.randrange(256)])
                    v = rnd.randrange(256) & ~m & 0xFF
                    c.mem[base + start + 2 * i] = m
                    c.mem[base + start + 2 * i + 1] = v
    g.run(4_000_000)
    g.press(0x3920)
    DS = (LOAD_SEG + 0x835) * 16
    patched = False
    limit = c.icount + 3_000_000
    while c.icount < limit and not patched:
        c.step()
        if c.s[1] == LOAD_SEG and c.ip == 0x35AC:
            c.mem[DS + 0xFB58] = level
            patched = True
    g.run(instr)
    return c.icount, bytes(c.mem[DS:DS + 0x10000]), g


if __name__ == '__main__':
    level = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 6_000_000
    ic0, ds0, g0 = run(False, n, level)
    ic1, ds1, g1 = run(True, n, level)
    # variables / work area: everything from DS:9250 up (the sprite data region below it legitimately differs)
    lo = 0x9250
    diff = [i for i in range(lo, 0x10000) if ds0[i] != ds1[i]]
    print('level', level, 'instructions: original %d, scrambled %d' % (ic0, ic1))
    print('DS:9250-FFFF differing bytes after %d instructions of gameplay: %d' % (n, len(diff)))
    if diff:
        print('first differing offsets:', ['%04X' % d for d in diff[:20]])
    f0 = g0.cga_frame()
    f1 = g1.cga_frame()
    print('screens identical:', list(f0.getdata()) == list(f1.getdata()), '(expected False: sprites are drawn differently)')
