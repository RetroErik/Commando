"""Independent model of the CMS score player (SID_MODE 5 semantics of Codex/cmsrun.s) checked against the register
writes the VGA build makes on ports 220h-223h in CMS mode.  python cms_model.py [instructions]"""
import os, sys, subprocess
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu_game import *

score = open(os.path.join(HERE, 'audio', 'sidenv_full.bin'), 'rb').read()
VOL = [0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x77, 0x99]


def model_writes(nframes):
    """Return the list of (chip, reg, value) the player must write for the first `nframes` score frames."""
    out = []
    pos = 0
    st = dict(f0=0, n0=0, o23=0, f1=0, n1=0, o01_1=0, o23_1=0)
    frames = 0
    while frames < nframes:
        d = score[pos]; pos += 1
        if d == 0xFF:
            pos = 0
            continue
        if d & 0x80:
            frames += (d & 0x7F)          # skip count frames without writes
            continue
        for v in (1, 2, 3):
            if not d & (1 << (v - 1)):
                continue
            tone, state = score[pos], score[pos + 1]; pos += 2
            vol = VOL[(state & 0x38) >> 3]
            if v == 1:
                out.append((0, 0x03, vol)); out.append((0, 0x0B, tone))
                st['o23'] = (st['o23'] & 0x0F) | ((state & 7) << 4)
                out.append((0, 0x11, st['o23']))
                st['f0'] &= 0xF7; st['n0'] = 0
                if state & 0x80:
                    if state & 0x40: st['n0'] = 8
                    else: st['f0'] |= 8
                out.append((0, 0x14, st['f0'])); out.append((0, 0x15, st['n0']))
            elif v == 2:
                out.append((1, 0x00, vol)); out.append((1, 0x08, tone))
                st['o01_1'] = (st['o01_1'] & 0xF0) | (state & 7)
                out.append((1, 0x10, st['o01_1']))
                bit = 1
                st['f1'] &= ~bit & 0xFF; st['n1'] &= ~bit & 0xFF
                if state & 0x80:
                    if state & 0x40: st['n1'] |= bit
                    else: st['f1'] |= bit
                out.append((1, 0x14, st['f1'])); out.append((1, 0x15, st['n1']))
            else:
                out.append((1, 0x03, vol)); out.append((1, 0x0B, tone))
                st['o23_1'] = (st['o23_1'] & 0x0F) | ((state & 7) << 4)
                out.append((1, 0x11, st['o23_1']))
                bit = 8
                st['f1'] &= ~bit & 0xFF; st['n1'] &= ~bit & 0xFF
                if state & 0x80:
                    if state & 0x40: st['n1'] |= bit
                    else: st['f1'] |= bit
                out.append((1, 0x14, st['f1'])); out.append((1, 0x15, st['n1']))
        frames += 1
    return out


if __name__ == '__main__':
    exe = os.path.join(HERE, 'build', 'COMMANDO.EXE')
    nm = subprocess.run([r'C:\FPC\3.2.2\bin\i386-win32\nm.exe', os.path.join(HERE, 'build', 'vga.pe')], capture_output=True, text=True).stdout
    sym = {l.split()[2]: int(l.split()[0], 16) for l in nm.splitlines() if len(l.split()) == 3}
    g = Game(exe); g.io_log = []; c = g.cpu
    os.chdir(os.path.dirname(exe))
    CS = LOAD_SEG * 16
    g.run(3_300_000)
    mark = len(g.io_log)
    g.press(0x324D)
    for _ in range(40):
        g.run(100_000)
        if c.mem[CS + sym['s_mode']] == 1:
            break
    g.run(int(sys.argv[1]) if len(sys.argv) > 1 else 12_000_000)
    ev = g.io_log[mark:]
    got = []
    reg = {0: None, 1: None}
    for t, p, v in ev:
        if p == 0x221: reg[0] = v
        elif p == 0x223: reg[1] = v
        elif p == 0x220: got.append((0, reg[0], v))
        elif p == 0x222: got.append((1, reg[1], v))
    last_init = max(i for i, (ch, r, v) in enumerate(got) if ch == 1 and r == 0x16)
    player = got[last_init + 1:]
    exp = model_writes(400)
    # the game's own speaker gate writes (INT 60h) reach chip 0 register 14h through cms_gate with the unchanged
    # mask value; they are expected extras and must never change the music state
    last14 = 0
    i = j = skipped = 0
    mism = []
    while i < len(player) and j < len(exp):
        if player[i] == exp[j]:
            if exp[j][:2] == (0, 0x14):
                last14 = exp[j][2]
            i += 1; j += 1
        elif player[i][:2] == (0, 0x14) and player[i][2] == last14:
            skipped += 1; i += 1
        else:
            mism.append((i, player[i], exp[j])); i += 1; j += 1
    print('player writes %d, model writes (400 frames) %d, matched %d, gate extras %d, mismatches %d' % (len(player), len(exp), j - len(mism), skipped, len(mism)))
    for m in mism[:6]:
        print('  #%d got %s expected %s' % m)
