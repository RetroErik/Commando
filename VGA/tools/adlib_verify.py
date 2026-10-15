"""Verify AdLib pitch conversion against the game's own note divisors (independent Python model).
Runs the build in ADLIB mode (M pressed once), logs every divisor fetched by the music sequencer (hook_notefetch)
and every OPL A0/B0 write on channel 0, then compares frequencies."""
import os, sys, subprocess, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu_game import *

exe = os.path.join(HERE, 'build', 'COMMANDO.EXE')
pe = os.path.join(HERE, 'build', 'vga.pe')
nm = subprocess.run([r'C:\FPC\3.2.2\bin\i386-win32\nm.exe', pe], capture_output=True, text=True).stdout
sym = {l.split()[2]: int(l.split()[0], 16) for l in nm.splitlines() if len(l.split()) == 3}
g = Game(exe)
g.io_log = []
c = g.cpu
os.chdir(os.path.dirname(exe))
CS = LOAD_SEG
nf_ret = sym['nf_ret']
notes = []      # (icount, divisor) from the sequencer
total = int(sys.argv[1]) if len(sys.argv) > 1 else 8_000_000
g.run(300_000)
g.press(0x324D)
pressed_space = False
while c.icount < total:
    c.step()
    if c.s[1] == CS and c.ip == nf_ret:
        if c.mem[CS * 16 + sym['s_mode']] == 2:
            notes.append((c.icount, c.r[0]))
    if c.icount >= g.next_tick:
        g.next_tick += g.tick_period
        g.tick()
    if not pressed_space and c.icount > 3_500_000:
        g.press(0x3920)
        pressed_space = True

# decode channel-0 OPL traffic: B0 writes carry the key-on bit
regs = {}
cur_reg = None
events = []
for t, p, v in g.io_log:
    if p == 0x388:
        cur_reg = v
    elif p == 0x389 and cur_reg is not None:
        regs[cur_reg] = v
        if cur_reg == 0xB0:
            keyon = (v >> 5) & 1
            fnum = ((v & 3) << 8) | regs.get(0xA0, 0)
            block = (v >> 2) & 7
            events.append((t, keyon, fnum, block))
print('sequencer notes fetched:', len(notes), ' distinct divisors:', len(set(d for _, d in notes)))
ons = [e for e in events if e[1]]
print('OPL channel-0 key-on writes:', len(ons))
bad = 0
checked = 0
fetched = [(t, d) for t, d in notes if d]
for (t, d), (_, _, fnum, block) in zip(fetched, ons):
    f_pit = 1193182.0 / d
    f_opl = fnum * 49716.0 / (1 << (20 - block))
    err = abs(f_opl - f_pit) / f_pit
    checked += 1
    if err > 0.01 and not (d < 193):
        bad += 1
        print('  mismatch: div %d -> %.1f Hz expected, OPL fnum %d block %d = %.1f Hz (%.2f%%)' % (d, f_pit, fnum, block, f_opl, err * 100))
print('checked %d notes (sequencer order vs key-on order), %d outside 1%%; fetched=%d key-ons=%d' % (checked, bad, len(fetched), len(ons)))
print('sample (div, Hz): ', [(d, round(1193182.0 / d, 1)) for _, d in notes[:8] if d])
