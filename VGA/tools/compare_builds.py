"""Prove that a VGA build runs the SAME game logic as the original.

1. Both executables start in normal timing, fire is pressed on the title and the run continues until player-controlled
   gameplay is active (game state DS:FA19 != 0).
2. From that moment time is driven ONLY by the retrace waits (virtual time), so both builds see exactly the same game clock
   per frame, independent of how many instructions their graphics routines need.
3. After the same number of retrace waits the complete data segment (all variables, object tables, score, random state,
   scroll position, scenery attribute layer ...) is compared byte by byte.

Intentional differences: DS:FA1E (RAM screen segment), DS:9164 (menu text 'Toggle Music' -> 'Music Device'), the
timer sub-phase DS:924E.   python compare_builds.py [EXE_VGA] [retraces_after_start]
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu_game import *


def run(exe, frames):
    g = Game(exe)
    os.chdir(os.path.dirname(os.path.abspath(exe)))
    c = g.cpu
    ds = struct.unpack_from('<H', c.mem, LOAD_SEG * 16 + 0xA7)[0] * 16
    # normal timing; fire is pressed on the title; sync at the exact instruction that starts player-controlled play (CS:34B1)
    pressed = False
    while not (c.s[1] == LOAD_SEG and c.ip == 0x34B1) and c.icount < 60_000_000:
        c.step()
        if c.icount >= g.next_tick:
            g.next_tick += g.tick_period
            g.tick()
        if not pressed and c.icount >= 4_000_000:
            g.press(0x3920)
            pressed = True
    sync_icount = c.icount
    struct.pack_into('<H', c.mem, ds + 0x91E6, 0x00C8)         # identical random seed at the sync point
    g.virtual_time = True                   # from here on time is driven only by retrace waits
    g.next_tick = c.icount + g.fallback_period
    g.vt_acc = 0
    g.vt_last_retrace = c.icount
    state = lambda: c.mem[ds + 0xFA19]
    base = g.retrace_calls
    gs = state()
    g.run(2_000_000_000, stop_cb=lambda gg: gg.retrace_calls >= base + frames)
    print('  synced at instruction %d (state %d), ran %d retraces in virtual time, final state %d' % (sync_icount, gs, g.retrace_calls - base, state()))
    return g, bytes(c.mem[ds: ds + 0x10000])


if __name__ == '__main__':
    orig = os.path.join(ROOT, 'COMMANDO.EXE')
    vga = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(HERE, 'build', 'COMMANDO.EXE')
    frames = int(sys.argv[2]) if len(sys.argv) > 2 else 3000
    go, do = run(orig, frames)
    gv, dv = run(vga, frames)
    for name, d in (('original', do), ('VGA', dv)):
        w = lambda a: d[a] | (d[a + 1] << 8)
        print('  %-8s map scroll DS:CD5E=%d  random seed DS:91E6=%04X  score digits %s  game state %d' % (name, w(0xCD5E), w(0x91E6), d[0xFB20:0xFB26].hex(), d[0xFA19]))
    RING = range(0xDCE2, 0xDCE2 + 0x1C00)          # original 2-bit display ring: the VGA build draws its own 8-bit ring instead
    diff = [i for i in range(0x10000) if do[i] != dv[i] and i not in RING]
    print('data segment bytes differing outside the display ring DS:DCE2-F8E1: %d of %d' % (len(diff), 0x10000 - len(RING)))
    print('(collision/attribute layer DS:CD60-DB5F identical: %s)' % (do[0xCD60:0xCD60 + 0xE00] == dv[0xCD60:0xCD60 + 0xE00]))
    ranges = []
    for i in diff:
        if ranges and i - ranges[-1][1] <= 2:
            ranges[-1][1] = i
        else:
            ranges.append([i, i])
    for a, b in ranges[:40]:
        print('  DS:%04X-%04X  orig %s  vga %s' % (a, b, do[a:b + 1].hex(), dv[a:b + 1].hex()))
