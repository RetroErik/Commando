"""Render the real Plantronics ColorPlus build (Codex/Plantronics/run) headlessly.

The patched COMMANDO.EXE is run in the emulator together with the Plantronics loader (STARTC.COM): the loader is executed
until it EXECs the original launcher; then the game starts with the loader's INT 60h-69h handlers resident, exactly like on a card.
The two video banks B800:0000 (colour bits 0-1) and BC00:0000 (colour bits 2-3) are combined into a 16-colour RGBI picture.
python emu_plantronics.py OUTDIR "instr:key:3920,instr:snap:name,..."
"""
import os, sys, struct
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import emu_game
from emu_game import Game
from emu86 import Halt
from PIL import Image

PLAN = os.path.join(os.path.dirname(emu_game.HERE), 'Codex', 'Plantronics', 'run')
COM_SEG = 0x1000
emu_game.PSP_SEG = 0x2000
emu_game.LOAD_SEG = 0x2010

# ColorPlus 16-colour RGBI index (bit0 blue, bit1 green, bit2 red, bit3 intensity), derived from the documented results
# (dark-cyan frames, red hero, blue enemies): low bank = CGA palette 0 (value bit0 = green, bit1 = red), high bank bit1 = blue, bit0 = intensity
RGBI = [(0, 0, 0), (0, 0, 170), (0, 170, 0), (0, 170, 170), (170, 0, 0), (170, 0, 170), (170, 85, 0), (170, 170, 170),
        (85, 85, 85), (85, 85, 255), (85, 255, 85), (85, 255, 255), (255, 85, 85), (255, 85, 255), (255, 255, 85), (255, 255, 255)]


def plane_color(lo, hi):
    return ((hi >> 1) & 1) | ((lo & 1) << 1) | (((lo >> 1) & 1) << 2) | ((hi & 1) << 3)


class PlanGame(Game):
    def __init__(self):
        super().__init__(os.path.join(PLAN, 'COMMANDO.EXE'))
        self.dat = open(os.path.join(PLAN, 'COMMANDO.DAT'), 'rb').read()
        c = self.cpu
        self.game_regs = (list(c.r), list(c.s), c.ip)
        com = open(os.path.join(PLAN, 'STARTC.COM'), 'rb').read()
        base = COM_SEG * 16
        c.mem[base + 0x100: base + 0x100 + len(com)] = com
        c.mem[base:base + 2] = b'\xcd\x20'
        struct.pack_into('<H', c.mem, base + 2, 0x9FC0)
        for i in range(4):
            c.s[i] = COM_SEG
        c.r[4] = 0xFFFE
        c.ip = 0x100
        self.started = False

    def int_21(self):
        c = self.cpu
        if (c.r[0] >> 8) & 0xFF == 0x4B and not self.started:
            self.started = True
            c.r[:], c.s[:], c.ip = list(self.game_regs[0]), list(self.game_regs[1]), self.game_regs[2]
            c.cf = 0
            return
        super().int_21()

    def frame_plantronics(self):
        m = self.cpu.mem
        im = Image.new('RGB', (320, 200))
        px = im.load()
        for y in range(200):
            off = (y & 1) * 0x2000 + (y >> 1) * 80
            for xb in range(80):
                lo, hi = m[0xB8000 + off + xb], m[0xBC000 + off + xb]
                for k in range(4):
                    sh = 6 - 2 * k
                    px[xb * 4 + k, y] = RGBI[plane_color((lo >> sh) & 3, (hi >> sh) & 3)]
        return im


if __name__ == '__main__':
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    steps = []
    for s in sys.argv[2].split(','):
        n, kind, arg = s.split(':')
        steps.append((int(n), kind, arg))
    g = PlanGame()
    os.chdir(PLAN)
    c = g.cpu
    for n, kind, arg in steps:
        try:
            g.run(n - c.icount)
        except Halt as e:
            print('halt', e)
            break
        if kind == 'key':
            g.press(int(arg, 16))
        elif kind == 'snap':
            g.frame_plantronics().save(os.path.join(out, arg + '.png'))
            print('snap', arg, 'at', c.icount, 'started', g.started, 'mode', g.video_mode, 'unknown', dict(list(g.unknown_ints.items())[:6]))
