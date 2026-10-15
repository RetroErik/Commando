"""Prove (or disprove) that gameplay logic only reads sprite *headers*, never mask/pixel bytes."""
import os, sys, collections, bisect
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu_game import *
from scan_sprites import scan

sprites = scan()
starts = [s['a'] - 0x8350 for s in sprites]
ends = [s['end'] - 0x8350 for s in sprites]
g = Game(os.path.join(ROOT, 'COMMANDO.EXE'))
c = g.cpu
g.run(4_000_000)
g.press(0x3920)
DS = (LOAD_SEG + 0x835) * 16
lvl = int(sys.argv[1]) if len(sys.argv) > 1 else 1
patched = False
limit = c.icount + 3_000_000
while c.icount < limit and not patched:
    c.step()
    if c.s[1] == LOAD_SEG and c.ip == 0x35AC:
        c.mem[DS + 0xFB58] = lvl
        patched = True
g.run(1_500_000)
DRAW = lambda ip: (0x7C3F <= ip <= 0x8100) or (0x7899 <= ip <= 0x7BF0) or ip in range(0x7743, 0x77A9) or ip in range(0x76D1, 0x7742) or ip in range(0x18A3, 0x191F)
offs = collections.Counter()
logic_ips = collections.defaultdict(collections.Counter)


def hook(a, size):
    d = a - DS
    if not (0x1B52 <= d < 0x9100):
        return
    ip = c.cur_ip
    if DRAW(ip):
        return
    i = bisect.bisect_right(starts, d) - 1
    if i >= 0 and d < ends[i]:
        rel = d - starts[i]
        offs[rel if rel < 8 else 8] += 1
        logic_ips[ip][rel if rel < 8 else 8] += 1
    else:
        offs['outside'] += 1


c.rwatch = (DS + 0x1B52, DS + 0x9100)
c.read_hook = hook
g.run(int(sys.argv[2]) if len(sys.argv) > 2 else 3_000_000)
print('level', lvl, 'logic reads by byte offset inside sprite record (8 = 8 or more):', dict(offs))
bad = {ip: dict(v) for ip, v in logic_ips.items() if any(k == 8 or (isinstance(k, int) and k > 3) for k in v)}
print('logic IPs that read beyond header bytes:', bad)
